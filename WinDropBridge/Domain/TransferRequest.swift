//
//  TransferModels.swift
//  WinDropBridge
//
//  Created by Davide Castaldi on 17/10/25.
//

import Foundation
import UniformTypeIdentifiers
import Photos
import UIKit

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
    
    // MARK: - Unified filename resolver

    /// Resolves the best filename for a shared item:
    /// - If URL-backed → lastPathComponent
    /// - If Photos asset → PHAssetResource.originalFilename
    /// - Else fallback
    static func resolveFilename(provider: NSItemProvider, item: Any) async -> String {

        // 1️⃣ If file-backed URL → easiest path
        if let url = item as? URL {
            return sanitizeFilename(url.lastPathComponent)
        }

        // 2️⃣ If coming from Photos app → try PHAsset-based filename
        if let photoName = await resolveFilenameFromPhotos(provider: provider) {
            return photoName
        }

        // 3️⃣ NEW — If `item` is actually coming from PHAssetResource directly
        if let asset = item as? PHAsset {
            let resources = PHAssetResource.assetResources(for: asset)
            if let resource = resources.first {
                return sanitizeFilename(resource.originalFilename)
            }
        }

        if let resource = item as? PHAssetResource {
            return sanitizeFilename(resource.originalFilename)
        }

        // 4️⃣ If UIImage → no original filename → fallback
        if item is UIImage {
            return "photo_\(Int(Date().timeIntervalSince1970)).jpg"
        }

        // 5️⃣ Default fallback
        return "file_\(UUID().uuidString)"
    }
    
    /// Extract the real filename if the NSItemProvider originated from Photos
    static func resolveFilenameFromPhotos(provider: NSItemProvider) async -> String? {
        guard provider.registeredTypeIdentifiers.contains("com.apple.photos.asset") else {
            return nil
        }

        do {
            let assetId = try await provider.loadItem(
                forTypeIdentifier: "com.apple.photos.asset",
                options: nil
            ) as? String

            guard let assetId else { return nil }

            let assets = PHAsset.fetchAssets(withLocalIdentifiers: [assetId], options: nil)
            guard let asset = assets.firstObject else { return nil }

            let resources = PHAssetResource.assetResources(for: asset)
            guard let res = resources.first else { return nil }

            // ✔️ FIX: return the filename directly
            return sanitizeFilename(res.originalFilename)

        } catch {
            return nil
        }
    }


    // MARK: - Extract filename from PHAsset

    private static func filenameFromPhotosAsset(provider: NSItemProvider) async -> String? {
        do {
            let item = try await provider.loadItem(
                forTypeIdentifier: "com.apple.photos.asset",
                options: nil
            )

            guard let assetID = item as? String else { return nil }

            let results = PHAsset.fetchAssets(withLocalIdentifiers: [assetID], options: nil)
            guard let asset = results.firstObject else { return nil }

            let resources = PHAssetResource.assetResources(for: asset)

            // Prefer the primary resource (photo/video)
            if let primary = resources.first(where: { $0.type == .photo || $0.type == .video }) {
                return primary.originalFilename
            }

            // Otherwise return the first available resource's name
            return resources.first?.originalFilename

        } catch {
            print("[TransferRequest] Failed to get Photos filename:", error)
            return nil
        }
    }
}
