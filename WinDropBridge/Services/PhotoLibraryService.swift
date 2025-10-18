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
    func ensurePhotosAuth() async throws {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if status == .authorized || status == .limited { return }
        let new = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        guard new == .authorized || new == .limited else { throw AppError.permissionDenied }
    }

    /// Returns original bytes + best filename (no recompression).
    func buildTransferRequest(from item: PhotosPickerItem) async throws -> TransferRequest {
        guard let identifier = item.itemIdentifier else {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                throw AppError.loadFailed("Unable to load non-Photos item")
            }
            let name = "photo_\(Int(Date().timeIntervalSince1970)).jpg"
            return TransferRequest(data: data,
                                   filename: TransferRequest.sanitizeFilename(name),
                                   mimeType: TransferRequest.mimeType(for: name))
        }

        try await ensurePhotosAuth()

        let results = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil)
        guard let asset = results.firstObject else { throw AppError.assetNotFound }

        let resources = PHAssetResource.assetResources(for: asset)
        let resource = resources.first(where: { $0.type == .photo || $0.type == .fullSizePhoto }) ?? resources.first
        guard let resource else { throw AppError.resourceMissing }

        var filename = resource.originalFilename
        if filename.isEmpty {
            let imageOpts = PHImageRequestOptions()
            imageOpts.isNetworkAccessAllowed = true
            imageOpts.version = .original
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                PHImageManager.default().requestImageDataAndOrientation(for: asset, options: imageOpts) { _,_,_, info in
                    if let url = info?["PHImageFileURLKey"] as? URL {
                        let display = FileManager.default.displayName(atPath: url.path)
                        if !display.isEmpty { filename = display }
                    }
                    cont.resume()
                }
            }
        }
        if filename.isEmpty {
            filename = "photo_\(Int(Date().timeIntervalSince1970)).jpg"
        }

        let reqOpts = PHAssetResourceRequestOptions()
        reqOpts.isNetworkAccessAllowed = true

        let data = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Data, Error>) in
            var buffer = Data()
            PHAssetResourceManager.default().requestData(for: resource, options: reqOpts) { chunk in
                buffer.append(chunk)
            } completionHandler: { error in
                if let error { cont.resume(throwing: error) }
                else { cont.resume(returning: buffer) }
            }
        }

        let safe = TransferRequest.sanitizeFilename(filename)
        return TransferRequest(data: data,
                               filename: safe,
                               mimeType: TransferRequest.mimeType(for: safe))
    }
}
