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

    private let statusLabel: UILabel = {
        let label = UILabel()
        label.textAlignment = .center
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        
        view.addSubview(statusLabel)
        NSLayoutConstraint.activate([
            statusLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            statusLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            statusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            statusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20)
        ])
        
        Task { await executeTransfer() }
    }
    
    /// Allows file transfer through the share shortcuts on iOS
    private func executeTransfer() async {
        do {
            Task { @MainActor in
                self.statusLabel.text = "Transferring file..."
            }
            
            let filename = try await handleSharedItem()
            
            let successMessage = formatSuccessMessage(with: [filename])
            completeExtension(finalMessage: successMessage, isSuccess: true)
        } catch {
            AppLogger.generic("Transfer failed: \(error.localizedDescription)").log()
            completeExtension(finalMessage: error.localizedDescription, isSuccess: false)
        }
    }
    
    private func formatSuccessMessage(with filenames: [String]) -> String {
        var message = "Transfer successful:"
        
        for name in filenames { message += "\n• \(name)" }
        return message
    }
    
    /// Displays the final status and then either auto-closes or waits for user interaction.
    /// - Parameters:
    ///   - finalMessage: Transfered files
    ///   - isSuccess: The result action
    private func completeExtension(finalMessage: String, isSuccess: Bool) {
        print("[ShareExtension] Final Status:\n\(finalMessage)")
        
        Task { @MainActor in
            self.statusLabel.text = finalMessage
        }
        if isSuccess {
            Task { @MainActor in
                try await Task.sleep(for: .seconds(1.5))
                self.extensionContext?.completeRequest(returningItems: nil)
            }
        } else {
            let alert = UIAlertController(title: "Transfer Failed.", message: finalMessage, preferredStyle: .alert)
            let okAction = UIAlertAction(title: "OK", style: .default) { [weak self] _ in
                self?.extensionContext?.completeRequest(returningItems: nil)
            }
            alert.addAction(okAction)
            self.present(alert, animated: true, completion: nil)
        }
    }

    /// Handles the transfer logic and returns the filename on success.
    /// - Returns: The filename
    private func handleSharedItem() async throws -> String {
        guard let provider = await firstAttachmentProvider() else {
            throw AppLogger.loadFailed("No attachments found")
        }

        guard let sender = sender else {
            throw AppLogger.loadFailed("Sender is unavailable")
        }

        let payload = try await TransferRequest.create(from: provider)

        switch payload {
        case .memory(let request):
            _ = await sender.send(request)
        case .stream(let url, let filename):
            do {
                _ = try await sender.sendFileStream(url: url, filename: filename)
            } catch {
                throw AppLogger.loadFailed("Stream failed for \(filename): \(error.localizedDescription)")
            }
        }
        return payload.filename
    }
    
    /// Feteches the provider to work with
    /// - Returns: The provider
    private func firstAttachmentProvider() async -> NSItemProvider? {
        guard
            let item = extensionContext?.inputItems.first as? NSExtensionItem,
            let provider = item.attachments?.first
        else { return nil }
        return provider
    }
}
