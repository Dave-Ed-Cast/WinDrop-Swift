//
//  NSItemProvider.swift
//  WinDropBridge
//
//  Created by Davide Castaldi on 29/11/25.
//

import Foundation
import Photos
import UIKit

extension NSItemProvider {
    
    func resolveFilenameFromPhotos() async -> String? {
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
    
    func resolveFilename(item: Any) async -> String {
        
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
}
