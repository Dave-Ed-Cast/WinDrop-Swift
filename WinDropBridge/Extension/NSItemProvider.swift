//
//  NSItemProvider.swift
//  WinDropBridge
//
//  Created by Davide Castaldi on 29/11/25.
//

import Foundation
import Photos
import UIKit

extension NSItemProvider: TransferLoadable {
    
    /// Creates a payload to transfer starting from the provider from the item selcted in share extension.
    ///
    /// *Used by Share Extension in iOS shortcuts*
    /// - Returns: The transfer payload to use in a `TransferRequest`
    func asTransferPayload() async throws -> TransferPayload {
        // Find a supported type
        guard let type = UTType.supportedTypes.first(where: { self.hasItemConformingToTypeIdentifier($0.identifier) }) else {
            throw AppLogger.loadFailed("Unsupported file type")
        }
        
        let fileName: String
        
        do {
            let itemForName = try await self.loadItem(forTypeIdentifier: type.identifier, options: nil)
            let rawName = await self.resolveFilename(item: itemForName)
            fileName = rawName.sanitizeFilename()
        } catch {
            throw AppLogger.loadFailed("Could not load filename: \(error.localizedDescription)")
        }
        
        do {
            if type.conforms(to: .movie) || type.conforms(to: .video) || type.conforms(to: .audio) || type == .pdf {
                let url = try await loadURL(from: self, type: type)
                return .stream(url: url, filename: fileName)
            }
            
            if type.conforms(to: .image) {
                let data = try await loadImageData(from: self, type: type)
                let mime = fileName.mimeType()
                let request = TransferRequest(data: data, filename: fileName, mimeType: mime)
                return .memory(request: request)
            }
        } catch {
            throw AppLogger.generic("Failed to load data: \(error)")
        }
        
        throw AppLogger.loadFailed("Could not process data type")
    }
    
    private func resolveFilenameFromPhotos() async -> String? {
        guard self.registeredTypeIdentifiers.contains("com.apple.photos.asset") else {
            return nil
        }
        
        do {
            let assetId = try await self.loadItem(
                forTypeIdentifier: "com.apple.photos.asset",
                options: nil
            ) as? String
            
            guard let assetId else { return nil }
            
            let assets = PHAsset.fetchAssets(withLocalIdentifiers: [assetId], options: nil)
            guard let asset = assets.firstObject else { return nil }
            
            let resources = PHAssetResource.assetResources(for: asset)
            guard let res = resources.first else { return nil }
            
            return res.originalFilename.sanitizeFilename()
            
        } catch {
            return nil
        }
    }
    
    private func resolveFilename(item: Any) async -> String {
        
        // URL-backed
        if let url = item as? URL {
            return url.lastPathComponent.sanitizeFilename()
        }
        
        // Photos PHAsset-based
        if let photoName = await self.resolveFilenameFromPhotos() {
            return photoName
        }
        
        // Item is directly a PHAsset
        if let asset = item as? PHAsset {
            let resource = PHAssetResource.assetResources(for: asset)
            if let res = resource.first {
                return res.originalFilename.sanitizeFilename()
            }
        }
        
        // Item is directly a PHAssetResource
        if let resource = item as? PHAssetResource {
            return resource.originalFilename.sanitizeFilename()
        }
        
        // UIImage fallback
        if item is UIImage {
            return "photo_\(Int(Date().timeIntervalSince1970)).jpg"
        }
        
        // Generic fallback
        return "file_\(UUID().uuidString)"
    }
    
    private func loadURL(from provider: NSItemProvider, type: UTType) async throws -> URL {
        let item = try await provider.loadItem(forTypeIdentifier: type.identifier, options: nil)
        guard let url = item as? URL else {
            throw AppLogger.loadFailed("Could not resolve file URL")
        }
        return url
    }
    
    private func loadImageData(from provider: NSItemProvider, type: UTType) async throws -> Data {
        let item = try await provider.loadItem(forTypeIdentifier: type.identifier, options: nil)
        
        if let url = item as? URL {
            return try Data(contentsOf: url)
        } else if let image = item as? UIImage, let jpeg = image.jpegData(compressionQuality: 1.0) {
            return jpeg
        } else if let data = item as? Data {
            return data
        }
        
        throw AppLogger.loadFailed("Unsupported image data format")
    }
}
