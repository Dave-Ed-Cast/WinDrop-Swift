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

    func handleSelection(_ item: PhotosPickerItem?) {
        guard let item else { return }
        Task {
            do {
                let request = try await photoService.buildTransferRequest(from: item)
                self.previewImageData = request.data
                self.filename = request.filename
                self.status = "Sending \(request.filename)…"
                let result = await sender.send(request)
                self.status = result
            } catch {
                self.status = (error as? LocalizedError)?.errorDescription ?? "Failed"
            }
        }
    }
}
