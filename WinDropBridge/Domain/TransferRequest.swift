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
import _PhotosUI_SwiftUI

// MARK: - Helper Enum for the Result
enum TransferPayload {
    /// Small files (Images) loaded into memory
    case memory(request: TransferRequest)
    /// Large files (Videos, PDFs) pointing to a file on disk
    case stream(url: URL, filename: String)
}

struct TransferRequest {
    let data: Data
    let filename: String
    let mimeType: String?
    
    // MARK: - Supported Types
    static let supportedTypes: [UTType] = [
        // Images
        .image, .jpeg, .png, .tiff, .heic, .heif,
        // Video
        .movie, .video, .mpeg4Movie, .quickTimeMovie,
        // Audio
        .audio, .mp3, .wav, .aiff, .mpeg,
        // Documents
        .pdf
    ]
    
    // MARK: - Factory Logic (1: NSItemProvider / UIKit Compatible)

    /// Main entry point for NSItemProvider (used by Share Extensions and older APIs)
    static func create(from provider: NSItemProvider) async throws -> TransferPayload {
        
        // 1. Detect Type
        guard let type = supportedTypes.first(where: { provider.hasItemConformingToTypeIdentifier($0.identifier) }) else {
            throw AppError.loadFailed("Unsupported file type")
        }
        
        // 2. Load Item generically to help resolve the filename
        let itemForName = try? await provider.loadItem(forTypeIdentifier: type.identifier, options: nil)
        let rawName = await resolveFilename(provider: provider, item: itemForName ?? "")
        let safeName = sanitizeFilename(rawName)

        // 3. Branch Logic: Stream vs Memory
        if type.conforms(to: .movie) || type.conforms(to: .video) || type.conforms(to: .audio) || type == .pdf {
            let url = try await loadURL(from: provider, type: type)
            return .stream(url: url, filename: safeName)
        }
        
        if type.conforms(to: .image) {
            let data = try await loadImageData(from: provider, type: type)
            let mime = mimeType(for: safeName)
            let request = TransferRequest(data: data, filename: safeName, mimeType: mime)
            return .memory(request: request)
        }
        
        throw AppError.loadFailed("Could not process data type")
    }

    // MARK: - Factory Logic (2: PhotosPickerItem / SwiftUI Compatible)

    /// Main entry point for PhotosPickerItem (used by SwiftUI's PhotosPicker)
    static func create(from item: PhotosPickerItem) async throws -> TransferPayload {
        
        // 1. Attempt to resolve the original filename using the itemIdentifier
        let originalFilename: String?
        if let identifier = item.itemIdentifier {
            originalFilename = await resolveFilenameFromIdentifier(identifier)
        } else {
            originalFilename = nil
        }
        
        // Use the resolved name or a generic unique ID as fallback
        let safeBaseName = originalFilename.map(sanitizeFilename) ?? "file_\(UUID().uuidString)"

        // 2. Try to load as a File URL (for streaming large items like videos)
        if let url = try? await item.loadTransferable(type: URL.self) {
            
            // Ensure the filename has the correct extension for the streamed file
            let finalFilename: String
            if url.pathExtension.isEmpty {
                // If temporary URL lacks extension, append the expected one (e.g., .mp4)
                let preferredUTI = item.supportedContentTypes.first(where: { supportedTypes.contains($0) })
                let ext = preferredUTI?.preferredFilenameExtension ?? "mp4"
                finalFilename = (safeBaseName as NSString).deletingPathExtension + "." + ext
            } else {
                // Use the extension from the temporary URL, ensuring the base name is kept.
                let ext = url.pathExtension
                finalFilename = (safeBaseName as NSString).deletingPathExtension + "." + ext
            }

            let safeName = sanitizeFilename(finalFilename)
            print("Successfully loaded URL from PhotosPickerItem: \(safeName)")
            return .stream(url: url, filename: safeName)
        }
        
        // 3. If URL failed, try to load as Data (for smaller images)
        if let data = try? await item.loadTransferable(type: Data.self) {
            
            // Determine file extension for in-memory data
            let preferredUTI = item.supportedContentTypes.first(where: { supportedTypes.contains($0) })
            let fileExtension = preferredUTI?.preferredFilenameExtension ?? "jpg"
            
            // Ensure the filename has the correct extension
            let finalFilename = (safeBaseName as NSString).deletingPathExtension + "." + fileExtension
            let safeName = sanitizeFilename(finalFilename)

            let mime = mimeType(for: safeName)
            let request = TransferRequest(data: data, filename: safeName, mimeType: mime)
            print("Successfully loaded Data from PhotosPickerItem: \(safeName)")
            return .memory(request: request)
        }
        
        throw AppError.loadFailed("PhotosPickerItem did not resolve to a file URL or Data")
    }

    // MARK: - Internal Loaders (NSItemProvider based)

    private static func loadURL(from provider: NSItemProvider, type: UTType) async throws -> URL {
        let item = try await provider.loadItem(forTypeIdentifier: type.identifier, options: nil)
        guard let url = item as? URL else {
            throw AppError.loadFailed("Could not resolve file URL")
        }
        return url
    }

    private static func loadImageData(from provider: NSItemProvider, type: UTType) async throws -> Data {
        let item = try await provider.loadItem(forTypeIdentifier: type.identifier, options: nil)
        
        if let url = item as? URL {
            return try Data(contentsOf: url)
        } else if let image = item as? UIImage, let jpeg = image.jpegData(compressionQuality: 1.0) {
            return jpeg
        } else if let data = item as? Data {
            return data
        }
        
        throw AppError.loadFailed("Unsupported image data format")
    }
    
    // MARK: - Utility Functions
    
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

    // MARK: - Filename from Photos Resources
    
    // New function added based on your input
    static func makeFilename(
        from resource: PHAssetResource,
        asset: PHAsset? = nil,
        addDisambiguator: Bool = false
    ) -> String {
        var base = resource.originalFilename

        if base.isEmpty {
            // Check UTI for video/image type
            let isVideo = resource.uniformTypeIdentifier.contains("video")
            base = isVideo ? "video.mov" : "photo.jpg"
        }

        base = sanitizeFilename(base)

        guard addDisambiguator, let asset else { return base }

        let idSuffix = asset.localIdentifier.split(separator: "/").first?.prefix(5) ?? "dup"
        let ext = (base as NSString).pathExtension
        let stem = (base as NSString).deletingPathExtension

        return ext.isEmpty ?
            "\(stem)_\(idSuffix)" :
            "\(stem)_\(idSuffix).\(ext)"
    }
    
    // MARK: - Unified filename resolver (URL → Photos → UIImage → fallback)
    
    // Replaced existing function with your comprehensive version
    static func resolveFilename(provider: NSItemProvider, item: Any) async -> String {

        // URL-backed
        if let url = item as? URL {
            return sanitizeFilename(url.lastPathComponent)
        }

        // Photos PHAsset-based
        if let photoName = await resolveFilenameFromPhotos(provider: provider) {
            return photoName
        }

        // Item is directly a PHAsset
        if let asset = item as? PHAsset {
            let resource = PHAssetResource.assetResources(for: asset)
            if let res = resource.first {
                return sanitizeFilename(res.originalFilename)
            }
        }

        // Item is directly a PHAssetResource
        if let resource = item as? PHAssetResource {
            return sanitizeFilename(resource.originalFilename)
        }

        // UIImage fallback
        if item is UIImage {
            return "photo_\(Int(Date().timeIntervalSince1970)).jpg"
        }

        // Generic fallback
        return "file_\(UUID().uuidString)"
    }
    
    // MARK: - Filename resolution for Photos (NSItemProvider)
    
    // Replaced existing function with your comprehensive version
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

            return sanitizeFilename(res.originalFilename)

        } catch {
            return nil
        }
    }
    
    // MARK: - Filename resolution from PHAsset localIdentifier (PhotosPickerItem)

    /// Resolves the original filename of an asset using its local identifier from PhotosPickerItem.
    static func resolveFilenameFromIdentifier(_ localIdentifier: String) async -> String? {
        // PHAsset fetching should be done on the main thread for safety,
        // though in an async context, this is usually acceptable. We use MainActor for robustness.
        return await MainActor.run {
            let assets = PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil)
            guard let asset = assets.firstObject else { return nil }

            // Get original filename from resource
            let resources = PHAssetResource.assetResources(for: asset)
            guard let res = resources.first else { return nil }
            
            return sanitizeFilename(res.originalFilename)
        }
    }
}
