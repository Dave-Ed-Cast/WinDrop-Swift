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

struct TransferRequest {
    let data: Data
    let filename: String
    let mimeType: String?
    
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
    
    /// Main entry point for NSItemProvider (used by Share Extensions and older APIs)
    static func create(from provider: NSItemProvider) async throws -> TransferPayload {
        
        guard let type = supportedTypes.first(where: { provider.hasItemConformingToTypeIdentifier($0.identifier) }) else {
            throw AppLogger.loadFailed("Unsupported file type")
        }
        
        let fileName: String
        
        do {
            let itemForName = try await provider.loadItem(forTypeIdentifier: type.identifier, options: nil)
            let rawName = await provider.resolveFilename(item: itemForName)
            fileName = rawName.sanitizeFilename()
        } catch {
            throw AppLogger.loadFailed("Could not load filename: \(error.localizedDescription)")
        }
        
        do {
            if type.conforms(to: .movie) || type.conforms(to: .video) || type.conforms(to: .audio) || type == .pdf {
                let url = try await loadURL(from: provider, type: type)
                return .stream(url: url, filename: fileName)
            }
            
            if type.conforms(to: .image) {
                let data = try await loadImageData(from: provider, type: type)
                let mime = fileName.mimeType()
                let request = TransferRequest(data: data, filename: fileName, mimeType: mime)
                return .memory(request: request)
            }
        } catch {
            throw AppLogger.generic("Failed to load data: \(error)")
        }
        
        throw AppLogger.loadFailed("Could not process data type")
    }
    
    
    /// Creates a payload to transfer starting from the item selected from the gallery.
    /// - Parameter item: The media content from the gallery
    /// - Returns: The transfer payload to use in a `TransferRequest`
    static func create(from item: PhotosPickerItem) async throws -> TransferPayload {
        
        let originalFilename: String?
        if let id = item.itemIdentifier {
            originalFilename = await id.resolveFilename()
        } else {
            originalFilename = nil
        }
        
        let fallbackName = originalFilename?.sanitizeFilename() ?? "file_\(UUID().uuidString)"
        
        var loadedURL: URL?
        do {
            loadedURL = try await item.loadTransferable(type: URL.self)
        } catch {
            AppLogger.loadFailed("WARNING: Url loading failed, Falling back to Data: \(error.localizedDescription)").log()
            loadedURL = nil
        }
        
        if let url = loadedURL {
            
            let finalFilename: String
            let ext: String
            
            if url.pathExtension.isEmpty {
                let preferredUTI = item.supportedContentTypes.first(where: { supportedTypes.contains($0) })
                ext = preferredUTI?.preferredFilenameExtension ?? {
                    print("WARNING: extension extraction from URL path failed, using default (mp4)")
                    return "mp4"
                }()
            } else {
                ext = url.pathExtension
            }
            
            finalFilename = (fallbackName as NSString).deletingPathExtension + "." + ext

            
            let filename = finalFilename.sanitizeFilename()
            print("Successfully loaded URL from PhotosPickerItem: \(filename)")
            return .stream(url: url, filename: filename)
        }
        
        // If URL failed, try to load as Data (for smaller items)
        if let data = try? await item.loadTransferable(type: Data.self) {
            
            let preferredUTI = item.supportedContentTypes.first(where: { supportedTypes.contains($0) })
            let ext = preferredUTI?.preferredFilenameExtension ?? {
                AppLogger.loadFailed("WARNING: extraction from UTI failed, using default (jpg)").log()
                return "jpg"
            }()
            
            let finalFilename = (fallbackName as NSString).deletingPathExtension + "." + ext
            let filename = finalFilename.sanitizeFilename()
            
            let mime = filename.mimeType()
            let request = TransferRequest(data: data, filename: filename, mimeType: mime)
            AppLogger.generic("Successfully loaded Data from PhotosPickerItem: \(filename)").log()
            return .memory(request: request)
            
        }
        
        throw AppLogger.loadFailed("PhotosPickerItem did not resolve to a file URL or Data")
    }
    
    
    private static func loadURL(from provider: NSItemProvider, type: UTType) async throws -> URL {
        let item = try await provider.loadItem(forTypeIdentifier: type.identifier, options: nil)
        guard let url = item as? URL else {
            throw AppLogger.loadFailed("Could not resolve file URL")
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
        
        throw AppLogger.loadFailed("Unsupported image data format")
    }
}
