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
        if let url = try? await item.loadTransferable(type: URL.self) {
            let name = TransferRequest.sanitizeFilename(url.lastPathComponent)
            let data = try Data(contentsOf: url, options: .mappedIfSafe)
            return .init(
                data: data,
                filename: name,
                mimeType: TransferRequest.mimeType(for: name)
            )
        }

        guard let data = try await item.loadTransferable(type: Data.self) else {
            throw AppError.loadFailed("Unable to load non-Photos item")
        }

        let ext = item.supportedContentTypes.first?.preferredFilenameExtension ?? "bin"
        let name = TransferRequest.sanitizeFilename("shared_\(Int(Date().timeIntervalSince1970)).\(ext)")
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

    private func determineFilename(for asset: PHAsset, resource: PHAssetResource, isVideo: Bool) async -> String {
        if !resource.originalFilename.isEmpty {
            return resource.originalFilename
        }
        if isVideo {
            return "video_\(Int(Date().timeIntervalSince1970)).mov"
        }

        let opts = PHImageRequestOptions()
        opts.isNetworkAccessAllowed = true
        opts.version = .original
        
        var fallback: String?
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            PHImageManager.default().requestImageDataAndOrientation(for: asset, options: opts) { _, _, _, info in
                if let url = info?["PHImageFileURLKey"] as? URL {
                    fallback = FileManager.default.displayName(atPath: url.path)
                }
                cont.resume()
            }
        }
        if let fallback, !fallback.isEmpty {
            return fallback
        } else {
            return "photo_\(Int(Date().timeIntervalSince1970)).jpg"
        }
    }
}
