//
//  PhotosPickerItem.swift
//  WinDropBridge
//
//  Created by Davide Castaldi on 29/11/25.
//

import PhotosUI
extension PhotosPickerItem {
    
    /// Resolves the original filename of an asset using its local identifier.
    /// Returns the sanitized original filename if available in the Photos Library.
    func resolveFilename() async -> String? {
        guard let localIdentifier = self.itemIdentifier else { return nil }
        
        // PHAsset fetching should be done on the main thread for safety,
        // We use MainActor for robustness and concurrency safety.
        return await MainActor.run {
            let assets = PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil)
            guard let asset = assets.firstObject else { return nil }
            
            // Get original filename from resource
            let resources = PHAssetResource.assetResources(for: asset)
            guard let res = resources.first else { return nil }
            
            // Use String extension to sanitize the name
            return res.originalFilename.sanitizeFilename()
        }
    }
}
