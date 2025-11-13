//
//  TransferModels.swift
//  WinDropBridge
//
//  Created by Davide Castaldi on 17/10/25.
//

import Foundation
import UniformTypeIdentifiers
import Photos

enum AppError: Error, LocalizedError {
    case permissionDenied
    case assetNotFound
    case resourceMissing
    case loadFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .permissionDenied: return "Photos permission not granted"
        case .assetNotFound: return "Selected asset not found"
        case .resourceMissing: return "No valid resource for asset"
        case .loadFailed(let msg): return msg
        }
    }
}

struct TransferRequest {
    let data: Data
    let filename: String
    let mimeType: String?
    
    static func mimeType(for filename: String) -> String? {
        let ext = (filename as NSString).pathExtension.lowercased()
        guard let utt = UTType(filenameExtension: ext) else { return nil }
        return utt.preferredMIMEType
    }
    
    static func sanitizeFilename(_ name: String) -> String {
        let invalid = CharacterSet(charactersIn: "\\/:*?\"<>|")
        let safe = name.unicodeScalars.map { invalid.contains($0) ? "_" : Character($0) }
        return String(safe)
    }
    
    /// Attempts to use the original Photos or Files filename, with optional disambiguator if duplicates exist.
    static func makeFilename(
        from resource: PHAssetResource,
        asset: PHAsset? = nil,
        addDisambiguator: Bool = false
    ) -> String {
        // 1️⃣ Prefer the original filename provided by Photos
        var base = resource.originalFilename
        
        // 2️⃣ Fallback if Photos doesn’t provide any name
        if base.isEmpty {
            let isVideo = resource.uniformTypeIdentifier.contains("video")
            base = isVideo ? "video.mov" : "photo.jpg"
        }
        
        // 3️⃣ Clean invalid filesystem characters
        base = sanitizeFilename(base)
        
        // 4️⃣ Optionally add a small suffix if we need to differentiate duplicates
        guard addDisambiguator, let asset else { return base }
        
        let idSuffix = asset.localIdentifier.split(separator: "/").first?.prefix(5) ?? "dup"
        let ext = (base as NSString).pathExtension
        let stem = (base as NSString).deletingPathExtension
        
        return ext.isEmpty
            ? "\(stem)_\(idSuffix)"
            : "\(stem)_\(idSuffix).\(ext)"
    }
}
