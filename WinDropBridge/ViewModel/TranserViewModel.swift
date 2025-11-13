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
    
    func handleSelection(_ items: [PhotosPickerItem]) {
        Task.detached(priority: .userInitiated) {
            await withThrowingTaskGroup(of: Void.self) { group in
                for item in items {
                    group.addTask {
                        do {
                            // Each iteration builds its own connection + request
                            let request = try await self.photoService.buildTransferRequest(from: item)
                            let result = await self.sender.send(request)

                            await MainActor.run {
                                print("Sent \(request.filename): \(result)")
                                self.status = "Sent \(request.filename)"
                            }
                        } catch {
                            await MainActor.run {
                                print("Failed: \(error)")
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
