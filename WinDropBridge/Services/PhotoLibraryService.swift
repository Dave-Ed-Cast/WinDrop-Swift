//
//  PhotoLibraryService.swift
//  WinDropBridge
//
//  Created by Davide Castaldi on 17/10/25.
//

import Foundation
import Photos
import PhotosUI
import _PhotosUI_SwiftUI

final class PhotoLibraryService {
    
    /// Requests authorization
    func ensurePhotosAuth() async throws {
        let current = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if current == .authorized || current == .limited { return }
        let newStatus = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        guard newStatus == .authorized || newStatus == .limited else {
            throw AppLogger.permissionDenied
        }
    }

    /**
     Converts a PhotosPickerItem (from SwiftUI's PhotosPicker)
     into a Transfer Payload by calling the dedicated TransferRequest factory.
     */
    func buildTransferPayload(from item: PhotosPickerItem) async throws -> TransferPayload {
        // This now calls the specific static factory method in TransferRequest that
        // handles PhotosPickerItem's loadTransferable method.
        return try await TransferRequest.create(from: item)
    }
    
    // If you specifically need to handle PHAssets directly (not via Picker):
    func buildFromAsset(_ asset: PHAsset) async throws -> TransferPayload {
        // This is more complex because PHAsset doesn't automatically map to NSItemProvider
        // simply. Usually, you fetch the resource data or URL.
        
        let resources = PHAssetResource.assetResources(for: asset)
        guard let resource = resources.first else { throw AppLogger.loadFailed("No resource") }
        
        let filename = resource.originalFilename.sanitizeFilename()
        
        // Decide if Stream or Data based on type
        if asset.mediaType == .video {
             // Logic to request AVAsset and get URL...
             // This requires PHImageManager logic usually.
             throw AppLogger.loadFailed("Direct PHAsset video loading requires PHImageManager")
        } else {
            // Request Image Data
            let data = try await withCheckedThrowingContinuation { continuation in
                PHImageManager.default().requestImageDataAndOrientation(for: asset, options: nil) { data, _, _, _ in
                    if let data = data {
                        continuation.resume(returning: data)
                    } else {
                        continuation.resume(throwing: AppLogger.loadFailed("Could not load image data"))
                    }
                }
            }
            
            let mime = filename.mimeType()
            return .memory(request: TransferRequest(data: data, filename: filename, mimeType: mime))
        }
    }
}
