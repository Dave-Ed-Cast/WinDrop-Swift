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
        Task {
            await handleSharedItem()
        }
    }

    private func completeExtension(_ message: String? = nil) {
        if let message {
            print("[ShareExtension] \(message)")
        }
        self.extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
    }

    private func handleSharedItem() async {
        guard let item = extensionContext?.inputItems.first as? NSExtensionItem,
              let provider = item.attachments?.first else {
            completeExtension("No attachments found")
            return
        }

        do {
            let supportedTypes: [UTType] = [.image, .jpeg, .png, .tiff, .heic, .heif]
            guard let type = supportedTypes.first(where: { provider.hasItemConformingToTypeIdentifier($0.identifier) }) else {
                completeExtension("Unsupported type")
                return
            }

            let data: Data
            let filename: String

            // Load the image data
            if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                let item = try await provider.loadItem(forTypeIdentifier: type.identifier, options: nil)
                if let url = item as? URL {
                    filename = url.lastPathComponent
                    data = try Data(contentsOf: url)
                } else if let image = item as? UIImage, let jpeg = image.jpegData(compressionQuality: 1.0) {
                    filename = "photo_\(Int(Date().timeIntervalSince1970)).jpg"
                    data = jpeg
                } else {
                    throw AppError.loadFailed("Unsupported item type")
                }
            } else {
                throw AppError.loadFailed("No image data found")
            }

            let safeName = TransferRequest.sanitizeFilename(filename)
            let mime = TransferRequest.mimeType(for: safeName)
            let request = TransferRequest(data: data, filename: safeName, mimeType: mime)

            let result = await sender.send(request)
            completeExtension(result)
        } catch {
            completeExtension("Error: \(error.localizedDescription)")
        }
    }
}
