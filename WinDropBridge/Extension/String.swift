//
//  String.swift
//  WinDropBridge
//
//  Created by Davide Castaldi on 29/11/25.
//

import Foundation
import UniformTypeIdentifiers
import Photos

extension String {
    
    /// Sanitizes the filename by replacing invalid characters with underscores.
    func sanitizeFilename() -> String {
        let invalid = CharacterSet(charactersIn: "\\/:*?\"<>|")
        let safe = self.unicodeScalars.map { invalid.contains($0) ? "_" : Character($0) }
        return String(safe)
    }
    
    /// Attempts to determine the preferred MIME type based on the file extension.
    /// Returns nil if the file extension cannot be resolved to a UTType.
    func mimeType() -> String? {
        let ext = (self as NSString).pathExtension.lowercased()
        guard let utt = UTType(filenameExtension: ext) else {
            return nil
        }
        return utt.preferredMIMEType
    }
    
    /// Resolves the original filename of an asset using the string as a PHAsset local identifier.
    /// This method should only be called on the 'itemIdentifier' property of a PhotosPickerItem.
    /// Returns the sanitized original filename if available in the Photos Library.
    func resolveFilename() async -> String? {
        
        return await MainActor.run {
            let assets = PHAsset.fetchAssets(withLocalIdentifiers: [self], options: nil)
            guard let asset = assets.firstObject else { return nil }
            
            // Get original filename from resource
            let resources = PHAssetResource.assetResources(for: asset)
            guard let res = resources.first else { return nil }
            
            // Use String extension to sanitize the name
            return res.originalFilename.sanitizeFilename()
        }
    }
}
