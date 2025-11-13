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

/// Handles Photo library authorization and media extraction.
final class PhotoLibraryService {
    func ensurePhotosAuth() async throws {
        let current = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if current == .authorized || current == .limited { return }
        let newStatus = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        guard newStatus == .authorized || newStatus == .limited else {
            throw AppError.permissionDenied
        }
    }

    /// Returns a `TransferRequest` with original data and MIME info.
    func buildTransferRequest(from item: PhotosPickerItem) async throws -> TransferRequest {
        guard let id = item.itemIdentifier else {
            return try await loadFromItemProvider(item)
        }
        try await ensurePhotosAuth()
        return try await loadFromPhotos(id: id)
    }

    private func loadFromItemProvider(_ item: PhotosPickerItem) async throws -> TransferRequest {
        // 1️⃣ If user picked a file (from Files app)
        if let url = try? await item.loadTransferable(type: URL.self) {
            // Use the real file name from URL
            let name = TransferRequest.sanitizeFilename(url.lastPathComponent)
            let data = try Data(contentsOf: url, options: .mappedIfSafe)
            return .init(
                data: data,
                filename: name,
                mimeType: TransferRequest.mimeType(for: name)
            )
        }

        // 2️⃣ If user picked from Photos (Photos app)
        if let assetID = item.itemIdentifier,
           let asset = PHAsset.fetchAssets(withLocalIdentifiers: [assetID], options: nil).firstObject,
           let resource = PHAssetResource.assetResources(for: asset).first {
            
            // Fetch the original data
            let data = try await fetchAssetData(for: resource)
            
            // Use the *original* filename from Photos
            let name = TransferRequest.makeFilename(from: resource, asset: asset)
            print(name)
            
            return .init(
                data: data,
                filename: name,
                mimeType: TransferRequest.mimeType(for: name)
            )
        }

        // 3️⃣ Fallback for unexpected cases (just raw data)
        guard let data = try await item.loadTransferable(type: Data.self) else {
            throw AppError.loadFailed("Unable to load non-Photos item")
        }
        
        // Generate a safe fallback name (very rare)
        let ext = item.supportedContentTypes.first?.preferredFilenameExtension ?? "bin"
        let name = TransferRequest.sanitizeFilename("file_\(UUID().uuidString.prefix(6)).\(ext)")
        
        return .init(
            data: data,
            filename: name,
            mimeType: TransferRequest.mimeType(for: name)
        )
    }

    private func loadFromPhotos(id: String) async throws -> TransferRequest {
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject else {
            throw AppError.assetNotFound
        }

        let isVideo = asset.mediaType == .video
        let resources = PHAssetResource.assetResources(for: asset)

        guard let resource = resources.first(where: {
            isVideo ? ($0.type == .video || $0.type == .fullSizeVideo)
                    : ($0.type == .photo || $0.type == .fullSizePhoto)
        }) ?? resources.first else {
            throw AppError.resourceMissing
        }

        let filename = await determineFilename(for: asset, resource: resource, isVideo: isVideo)
        let safeName = TransferRequest.sanitizeFilename(filename)
        let buffer = try await fetchAssetData(for: resource)

        return .init(
            data: buffer,
            filename: safeName,
            mimeType: TransferRequest.mimeType(for: safeName)
        )
    }

    private func fetchAssetData(for resource: PHAssetResource) async throws -> Data {
        try await withCheckedThrowingContinuation { cont in
            let opts = PHAssetResourceRequestOptions()
            opts.isNetworkAccessAllowed = true
            var buffer = Data()
            buffer.reserveCapacity(2_000_000)
            PHAssetResourceManager.default().requestData(for: resource, options: opts) { chunk in
                buffer.append(chunk)
            } completionHandler: { error in
                if let error {
                    cont.resume(throwing: error)
                } else {
                    cont.resume(returning: buffer)
                }
            }
        }
    }

    private func determineFilename(
        for asset: PHAsset,
        resource: PHAssetResource,
        isVideo: Bool
    ) async -> String {
        // 1️⃣ Get the initial candidate filename (exact from Photos)
        var base = resource.originalFilename
        if base.isEmpty { base = isVideo ? "video.mov" : "photo.jpg"  }

        // 2️⃣ Sanitize (remove invalid characters)
        base = TransferRequest.sanitizeFilename(base)

        // 3️⃣ Get your save directory (Documents, or change as needed)
        guard let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return base }
        
        var filename = TransferRequest.makeFilename(from: resource, asset: asset)
        
        if FileManager.default.fileExists(atPath: directory.appendingPathComponent(filename).path) {
            filename = TransferRequest.makeFilename(from: resource, asset: asset, addDisambiguator: true)
        }

        // 5️⃣ Return the final safe and unique filename
        return filename
    }
}
