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
        // 1️⃣ Files app or iCloud Drive → URL-backed
        
        if let url = try? await item.loadTransferable(type: URL.self) {
            let name = TransferRequest.sanitizeFilename(url.lastPathComponent)
            let data = try Data(contentsOf: url)
            print("[PhotoLibraryService] Using URL branch, name = \(name)")
            return .init(
                data: data,
                filename: name,
                mimeType: TransferRequest.mimeType(for: name)
            )
        }

        // 2️⃣ Photos app → use itemIdentifier to resolve filename + PHAssetResource
        if let assetID = item.itemIdentifier {
            print("[PhotoLibraryService] itemIdentifier = \(assetID)")
            let results = PHAsset.fetchAssets(withLocalIdentifiers: [assetID], options: nil)
            if let asset = results.firstObject {
                let resources = PHAssetResource.assetResources(for: asset)

                guard let resource = resources.first else {
                    throw AppError.resourceMissing
                }

                let data = try await fetchAssetData(for: resource, asset: asset)
                let filename = TransferRequest.sanitizeFilename(resource.originalFilename)
                print("[PhotoLibraryService] Using PHAsset branch, filename = \(filename)")

                return .init(
                    data: data,
                    filename: filename,
                    mimeType: TransferRequest.mimeType(for: filename)
                )
            } else {
                print("[PhotoLibraryService] No PHAsset found for id \(assetID)")
            }
        } else {
            print("[PhotoLibraryService] itemIdentifier is NIL")
        }

        // 3️⃣ Fallback — raw Data without metadata
        if let data = try? await item.loadTransferable(type: Data.self) {
            let name = "photo.jpg"
            print("[PhotoLibraryService] FALLBACK branch, using name = \(name)")
            return .init(
                data: data,
                filename: name,
                mimeType: TransferRequest.mimeType(for: name)
            )
        }

        throw AppError.loadFailed("Unable to extract item from item provider")
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
        let buffer = try await fetchAssetData(for: resource, asset: asset)

        return .init(
            data: buffer,
            filename: safeName,
            mimeType: TransferRequest.mimeType(for: safeName)
        )
    }

    private func fetchAssetData(for resource: PHAssetResource, asset: PHAsset) async throws -> Data {

        switch asset.mediaType {
        case .image:
            return try await fetchImageData(asset: asset)

        case .video:
            return try await fetchVideoData(asset: asset)

        default:
            // fallback to resource-based extraction
            return try await fetchRawResourceData(resource)
        }
    }
    
    private func fetchRawResourceData(_ resource: PHAssetResource) async throws -> Data {
        try await withCheckedThrowingContinuation { cont in
            let opts = PHAssetResourceRequestOptions()
            opts.isNetworkAccessAllowed = true
            
            let buffer = NSMutableData()

            PHAssetResourceManager.default().requestData(
                for: resource,
                options: opts,
                dataReceivedHandler: { chunk in
                    buffer.append(chunk)
                },
                completionHandler: { error in
                    if let error = error {
                        cont.resume(throwing: error)
                    } else {
                        cont.resume(returning: buffer as Data)
                    }
                }
            )
        }
    }
    
    private func fetchVideoData(asset: PHAsset) async throws -> Data {
        try await withCheckedThrowingContinuation { cont in
            let opts = PHVideoRequestOptions()
            opts.version = .original
            opts.isNetworkAccessAllowed = true

            PHImageManager.default().requestAVAsset(forVideo: asset, options: opts) { avAsset, _, info in
                if let error = info?[PHImageErrorKey] as? Error {
                    cont.resume(throwing: error)
                    return
                }
                guard let urlAsset = avAsset as? AVURLAsset else {
                    cont.resume(throwing: AppError.loadFailed("Video asset missing URL"))
                    return
                }

                do {
                    let data = try Data(contentsOf: urlAsset.url)
                    cont.resume(returning: data)
                } catch {
                    cont.resume(throwing: error)
                }
            }
        }
    }
    
    private func fetchImageData(asset: PHAsset) async throws -> Data {
        try await withCheckedThrowingContinuation { cont in
            let opts = PHImageRequestOptions()
            opts.version = .original
            opts.isNetworkAccessAllowed = true

            PHImageManager.default().requestImageDataAndOrientation(for: asset, options: opts) { data, _, _, info in
                if let error = info?[PHImageErrorKey] as? Error {
                    cont.resume(throwing: error)
                    return
                }
                guard let data = data else {
                    cont.resume(throwing: AppError.loadFailed("Image data missing"))
                    return
                }
                cont.resume(returning: data)
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
