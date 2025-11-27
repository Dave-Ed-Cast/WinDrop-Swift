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
        
        // Get a generic unique filename prefix
        let uniquePrefix = "file_\(UUID().uuidString)"
        
        // Find the most appropriate content type from the supported types
        let preferredUTI = item.supportedContentTypes.first(where: { supportedTypes.contains($0) })

        // 1. Try to load as a File URL (for streaming large items like videos)
        if let url = try? await item.loadTransferable(type: URL.self) {
            
            // Determine the file extension: prioritize preferred extension from UTI,
            // otherwise use a generic extension based on type if the temporary URL extension is missing.
            let fileExtension: String
            if let preferredExtension = preferredUTI?.preferredFilenameExtension, !preferredExtension.isEmpty {
                fileExtension = preferredExtension
            } else if url.pathExtension.isEmpty {
                // Fallback for temporary files without extension (e.g., videos)
                fileExtension = preferredUTI?.conforms(to: .video) == true ? "mp4" : "jpg"
            } else {
                // Use the extension from the temporary URL path
                fileExtension = url.pathExtension
            }
            
            let finalFilename = "\(uniquePrefix).\(fileExtension)"
            let safeName = sanitizeFilename(finalFilename)

            print("Successfully loaded URL from PhotosPickerItem: \(safeName)")
            return .stream(url: url, filename: safeName)
        }
        
        // 2. If URL failed, try to load as Data (for smaller images)
        if let data = try? await item.loadTransferable(type: Data.self) {
            
            // Determine file extension for in-memory data
            let fileExtension = preferredUTI?.preferredFilenameExtension ?? "jpg"
            let suggestedFilename = "photo_\(Int(Date().timeIntervalSince1970)).\(fileExtension)"
            let safeName = sanitizeFilename(suggestedFilename)

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

    static func resolveFilename(provider: NSItemProvider, item: Any) async -> String {
        if let url = item as? URL { return sanitizeFilename(url.lastPathComponent) }
        if let photoName = await resolveFilenameFromPhotos(provider: provider) { return photoName }
        if let asset = item as? PHAsset {
            let resources = PHAssetResource.assetResources(for: asset)
            return sanitizeFilename(resources.first?.originalFilename ?? "photo.jpg")
        }
        if provider.registeredTypeIdentifiers.contains(UTType.image.identifier) {
            return "photo_\(Int(Date().timeIntervalSince1970)).jpg"
        }
        return "file_\(UUID().uuidString)"
    }
    
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
}
