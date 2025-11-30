//
//  TranserViewModel.swift
//  WinDropBridge
//
//  Created by Davide Castaldi on 17/10/25.
//

import Foundation
import SwiftUI
import PhotosUI
import Combine

@Observable
final class TransferViewModel {
    var previewImageData: Data?
    var filename: String?
    var status: String = "Select a photo to send"
    
    private let photoService: PhotoLibraryService
    private let sender: WinDropSending
    
    /// Creates a view model responsible for preparing and sending file/photo transfers.
    ///
    /// - Parameters:
    ///   - photoService: Abstraction for accessing photo library data.
    ///   - sender: Service that performs the actual data transfer to the remote peer.
    init(photoService: PhotoLibraryService, sender: WinDropSending) {
        self.photoService = photoService
        self.sender = sender
    }
    
    /// Handles user selection from a `PhotosPicker`.
    ///
    /// Converts each `PhotosPickerItem` into a `TransferInput` and forwards processing
    /// to `handleInputs(_:)`.
    ///
    /// - Parameter items: The selected items from the system photo picker.
    func handleSelection(_ items: [PhotosPickerItem]) {
        let inputs = items.map { TransferInput.photoPickerItem($0) }
        handleInputs(inputs)
    }
    
    /// Handles file imports from the system file picker.
    ///
    /// Wraps each `URL` into a `TransferInput` and forwards processing
    /// to `handleInputs(_:)`.
    ///
    /// - Parameter urls: Files selected by the user.
    func handleFileImport(_ urls: [URL]) {
        let inputs = urls.map { TransferInput.url($0) }
        handleInputs(inputs)
    }
    
    /// Processes one or more inputs concurrently and sends them via the `WinDropSending` service.
    ///
    /// Responsibilities:
    /// - Converts inputs into `TransferPayload` using their respective loaders.
    /// - Supports both memory-based and stream-based payloads.
    /// - Sends each payload concurrently using a `ThrowingTaskGroup`.
    /// - Updates the UI with the result of each transfer on the main thread.
    ///
    /// Error handling:
    /// - Individual task failures are logged and reflected in `status`.
    /// - The group continues to process remaining tasks.
    ///
    /// - Parameter inputs: A list of transfer inputs (URLs, picker items, item providers).
    private func handleInputs(_ inputs: [TransferInput]) {
        Task.detached(priority: .userInitiated) {
            await withThrowingTaskGroup(of: Void.self) { group in
                for input in inputs {
                    group.addTask {
                        do {
                            let payload: TransferPayload
                            
                            switch input {
                            case .url: payload = try await input.loadable.asTransferPayload()
                            case .photoPickerItem: payload = try await input.loadable.asTransferPayload()
                            case .itemProvider: payload = try await input.loadable.asTransferPayload()
                            }
                            
                            let result: String
                            let filename: String
                            
                            switch payload {
                            case .memory(let request):
                                result = await self.sender.send(request)
                                filename = request.filename
                                
                            case .stream(let url, let streamFilename):
                                print("Starting stream for: \(streamFilename)")
                                result = try await self.sender.sendFileStream(url: url, filename: streamFilename)
                                filename = streamFilename
                            }
                            
                            await MainActor.run {
                                AppLogger.generic("Sent \(filename): \(result)").log()
                                self.status = "Sent \(filename)"
                            }
                        } catch {
                            await MainActor.run {
                                AppLogger.loadFailed("Failed \(error.localizedDescription)").log()
                                self.status = "Failed \(error.localizedDescription)"
                            }
                        }
                    }
                }
                
                do {
                    try await group.waitForAll()
                } catch {
                    print("Some tasks failed: \(error)")
                }
            }
        }
    }
}
