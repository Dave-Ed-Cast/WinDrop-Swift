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
    private let sender = WinDropSender(host: "192.168.1.160", port: 5050)

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
            .image, .jpeg, .png, .tiff, .heic, .heif,
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
        let filename: String

        if let url = item as? URL {
            data = try Data(contentsOf: url, options: .mappedIfSafe)
            filename = url.lastPathComponent
        } else if let image = item as? UIImage,
                  let jpeg = image.jpegData(compressionQuality: 1.0) {
            data = jpeg
            filename = "photo_\(Int(Date().timeIntervalSince1970)).jpg"
        } else {
            throw AppError.loadFailed("Unsupported image item type")
        }

        let safeName = TransferRequest.sanitizeFilename(filename)
        let mime = TransferRequest.mimeType(for: safeName)
        return TransferRequest(data: data, filename: safeName, mimeType: mime)
    }
}

