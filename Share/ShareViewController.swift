//
//  ShareViewController.swift
//  WinDropBridge
//
//  Created by Davide Castaldi on 18/10/25.
//

import UIKit
import UniformTypeIdentifiers
import Photos

final class ShareViewController: UIViewController {
    private let sender: WinDropSender? = WinDropSender(host: "192.168.1.160", port: 5050)

    override func viewDidLoad() {
        super.viewDidLoad()
        Task { await handleSharedItem() }
    }

    private func completeExtension(_ message: String? = nil) {
        if let msg = message { print("[ShareExtension] \(msg)") }
        extensionContext?.completeRequest(returningItems: nil)
    }

    private func handleSharedItem() async {
        guard let provider = await firstAttachmentProvider() else {
            completeExtension("No attachments found")
            return
        }

        do {
            guard let type = detectSupportedType(for: provider) else {
                completeExtension("Unsupported type")
                return
            }

            guard let sender = sender else {
                completeExtension("Sender is unavailable")
                return
            }

            if type.conforms(to: .image) {
                let request = try await buildImageTransferRequest(from: provider, type: type)
                let result = await sender.send(request)
                completeExtension(result)
                return
            }

            if type.conforms(to: .movie)
                || type.conforms(to: .video)
                || type.conforms(to: .audio)
                || type == .pdf {
                
                let url = try await loadURL(from: provider, type: type)
                let safeName = TransferRequest.sanitizeFilename(url.lastPathComponent)
                print("[ShareExtension] Starting stream: \(safeName)")

                do {
                    let result = try await sender.sendFileStream(url: url, filename: safeName)
                    completeExtension(result)
                } catch {
                    completeExtension("Stream failed: \(error.localizedDescription)")
                }
                return
            }

            completeExtension("No supported data found")
        } catch {
            completeExtension("Error: \(error.localizedDescription)")
        }
    }

    private func detectSupportedType(for provider: NSItemProvider) -> UTType? {
        let supported: [UTType] = [
            // Images
            .image, .jpeg, .png, .tiff, .heic, .heif, .jpeg,
            // Video
            .movie, .video, .mpeg4Movie, .quickTimeMovie,
            // Audio
            .audio, .mp3, .wav, .aiff, .mpeg,
            // Documents
            .pdf
        ]
        return supported.first { provider.hasItemConformingToTypeIdentifier($0.identifier) }
    }

    private func firstAttachmentProvider() async -> NSItemProvider? {
        guard
            let item = extensionContext?.inputItems.first as? NSExtensionItem,
            let provider = item.attachments?.first
        else { return nil }
        return provider
    }

    private func loadURL(from provider: NSItemProvider, type: UTType) async throws -> URL {
        let item = try await provider.loadItem(forTypeIdentifier: type.identifier, options: nil)
        guard let url = item as? URL else {
            throw AppError.loadFailed("Unsupported URL type")
        }
        return url
    }

    private func buildImageTransferRequest(from provider: NSItemProvider, type: UTType) async throws -> TransferRequest {
        let item = try await provider.loadItem(forTypeIdentifier: type.identifier, options: nil)

        let data: Data

        if let url = item as? URL {
            data = try Data(contentsOf: url)
        } else if let image = item as? UIImage, let jpeg = image.jpegData(compressionQuality: 1.0) {
            data = jpeg
        } else {
            throw AppError.loadFailed("Unsupported image item type")
        }

        // NEW → universal filename resolver
        let filename = await TransferRequest.resolveFilename(provider: provider, item: item)

        let safe = TransferRequest.sanitizeFilename(filename)
        let mime = TransferRequest.mimeType(for: safe)

        return .init(data: data, filename: safe, mimeType: mime)
    }
    
    // MARK: - PHAsset filename extraction

    private func loadAssetFilename(from provider: NSItemProvider) async -> String? {
        // 1) Look for the Photos asset identifier (com.apple.photos.asset)
        guard provider.hasItemConformingToTypeIdentifier("com.apple.photos.asset") else {
            return nil
        }

        do {
            let item = try await provider.loadItem(
                forTypeIdentifier: "com.apple.photos.asset",
                options: nil
            )

            guard let assetID = item as? String else { return nil }

            // 2) Fetch PHAsset
            let result = PHAsset.fetchAssets(withLocalIdentifiers: [assetID], options: nil)
            guard let asset = result.firstObject else { return nil }

            // 3) Extract real filename via PHAssetResource
            let resources = PHAssetResource.assetResources(for: asset)

            if let primary = resources.first(where: { $0.type == .photo || $0.type == .video }) {
                return primary.originalFilename
            }

            return resources.first?.originalFilename
        } catch {
            print("[ShareExtension] loadAssetFilename failed: \(error)")
            return nil
        }
    }
}
