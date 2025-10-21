//
//  ShareViewController.swift
//  Share
//
//  Created by Davide Castaldi on 18/10/25.
//

import UIKit
import Social
import UniformTypeIdentifiers
import Photos

final class ShareViewController: UIViewController {
    private let sender = WinDropSender(host: "192.168.1.160", port: 5050)

    override func viewDidLoad() {
        super.viewDidLoad()
        Task.detached {
            await self.handleSharedItem()
        }
    }

    @MainActor
    private func completeExtension(_ message: String? = nil) {
        if let message {
            print("[ShareExtension] \(message)")
        }
        extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
    }

    nonisolated private func handleSharedItem() async {
        guard let (_, provider) = await extensionItem() else {
            await completeExtension("Could not handle shared items")
            return
        }

        do {
            let supportedTypes: [UTType] = [
                .image, .jpeg, .png, .tiff, .heic, .heif,
                .movie, .video, .mpeg4Movie, .quickTimeMovie,
                .pdf
            ]

            guard let type = supportedTypes.first(where: { provider.hasItemConformingToTypeIdentifier($0.identifier) }) else {
                await completeExtension("Unsupported type")
                return
            }

            // ===========================
            // 1️⃣ IMAGE HANDLING (small, non-chunked)
            // ===========================
            if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                let item = try await provider.loadItem(forTypeIdentifier: type.identifier, options: nil)

                let data: Data
                let filename: String

                if let url = item as? URL {
                    filename = url.lastPathComponent
                    data = try Data(contentsOf: url)
                } else if let image = item as? UIImage,
                          let jpeg = image.jpegData(compressionQuality: 1.0) {
                    filename = "photo_\(Int(Date().timeIntervalSince1970)).jpg"
                    data = jpeg
                } else {
                    throw AppError.loadFailed("Unsupported image item type")
                }

                let safeName = TransferRequest.sanitizeFilename(filename)
                let mime = TransferRequest.mimeType(for: safeName)
                let request = TransferRequest(data: data, filename: safeName, mimeType: mime)

                let result = await sender.send(request)
                await completeExtension(result)
                return
            }

            // ===========================
            // 2️⃣ VIDEO / LARGE FILE HANDLING (chunked)
            // ===========================
            if provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier)
                || provider.hasItemConformingToTypeIdentifier(UTType.video.identifier)
                || provider.hasItemConformingToTypeIdentifier(UTType.pdf.identifier) {

                let item = try await provider.loadItem(forTypeIdentifier: type.identifier, options: nil)
                guard let url = item as? URL else {
                    throw AppError.loadFailed("Unsupported file item type")
                }

                let safeName = TransferRequest.sanitizeFilename(url.lastPathComponent)
                print("[ShareExtension] Starting stream: \(safeName)")

                do {
                    let result = try await sender.sendFileStream(url: url, filename: safeName)
                    await completeExtension(result)
                } catch {
                    await completeExtension("Stream failed: \(error.localizedDescription)")
                }
                return
            }

            await completeExtension("No supported data found")
        } catch {
            await completeExtension("Error: \(error.localizedDescription)")
        }
    }

    @MainActor
    func extensionItem() async -> (NSExtensionItem, NSItemProvider)? {
        guard let item = extensionContext?.inputItems.first as? NSExtensionItem,
              let provider = item.attachments?.first else {
            completeExtension("No attachments found")
            return nil
        }
        return (item, provider)
    }
}
