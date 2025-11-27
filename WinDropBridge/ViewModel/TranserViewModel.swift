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
    
    init(photoService: PhotoLibraryService, sender: WinDropSending) {
        self.photoService = photoService
        self.sender = sender
    }
    
    // Assuming this is inside your ViewModel/Class that has photoService and sender properties

    func handleSelection(_ items: [PhotosPickerItem]) {
        Task.detached(priority: .userInitiated) {
            await withThrowingTaskGroup(of: Void.self) { group in
                for item in items {
                    group.addTask {
                        do {
                            // 1. Build the payload
                            let payload = try await self.photoService.buildTransferPayload(from: item)
                            
                            let result: String
                            let filename: String
                            
                            // 2. Decide how to send based on payload type
                            switch payload {
                            case .memory(let request):
                                // Case A: Small files (Images) -> Send TransferRequest (Data)
                                result = await self.sender.send(request)
                                filename = request.filename

                            case .stream(let url, let streamFilename):
                                // Case B: Large files (Video/PDF) -> Stream URL
                                print("Starting stream for: \(streamFilename)")
                                result = try await self.sender.sendFileStream(url: url, filename: streamFilename)
                                filename = streamFilename
                            }

                            // 3. Update UI on MainActor
                            await MainActor.run {
                                print("Sent \(filename): \(result)")
                                self.status = "Sent \(filename)"
                            }
                        } catch {
                            await MainActor.run {
                                print("Failed: \(error)")
                                self.status = "Failed \(error.localizedDescription)"
                            }
                        }
                    }
                }

                // Await all parallel tasks
                do {
                    try await group.waitForAll()
                } catch {
                    print("Some tasks failed: \(error)")
                }
            }
        }
    }
}
