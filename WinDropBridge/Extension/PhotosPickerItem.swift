//
//  PhotosPickerLibrary.swift
//  WinDropBridge
//
//  Created by Davide Castaldi on 30/11/25.
//

import Foundation
import _PhotosUI_SwiftUI

extension PhotosPickerItem: TransferLoadable {
    
    /// Creates a payload to transfer starting from the item selected from the gallery.
    /// - Parameter item: The media content from the gallery
    /// - Returns: The transfer payload to use in a `TransferRequest`
    func asTransferPayload() async throws -> TransferPayload {
        
        let originalFilename: String?
        if let id = self.itemIdentifier {
            originalFilename = await id.resolveFilename()
        } else {
            originalFilename = nil
        }
        
        let fallbackName = originalFilename?.sanitizeFilename() ?? "file_\(UUID().uuidString)"
        
        var loadedURL: URL?
        do {
            loadedURL = try await self.loadTransferable(type: URL.self)
        } catch {
            AppLogger.loadFailed("WARNING: Url loading failed, Falling back to Data: \(error.localizedDescription)").log()
            loadedURL = nil
        }
        
        if let url = loadedURL {
            
            let finalFilename: String
            let ext: String
            
            if url.pathExtension.isEmpty {
                let preferredUTI = self.supportedContentTypes.first(where: { UTType.supportedTypes.contains($0) })
                ext = preferredUTI?.preferredFilenameExtension ?? {
                    print("WARNING: extension extraction from URL path failed, using default (mp4)")
                    return "mp4"
                }()
            } else {
                ext = url.pathExtension.lowercased()
            }
            
            finalFilename = (fallbackName as NSString).deletingPathExtension + "." + ext.lowercased()
            
            
            let filename = finalFilename.sanitizeFilename()
            print("Successfully loaded URL from PhotosPickerItem: \(filename)")
            return .stream(url: url, filename: filename)
        }
        
        // If URL failed, try to load as Data (for smaller items)
        if let data = try? await self.loadTransferable(type: Data.self) {
            
            let preferredUTI = self.supportedContentTypes.first(where: { UTType.supportedTypes.contains($0) })
            let ext = preferredUTI?.preferredFilenameExtension ?? {
                AppLogger.loadFailed("WARNING: extraction from UTI failed, using default (jpg)").log()
                return "jpg"
            }()
            
            let finalFilename = (fallbackName as NSString).deletingPathExtension + "." + ext.lowercased()
            let filename = finalFilename.sanitizeFilename()
            
            let mime = filename.mimeType()
            let request = TransferRequest(data: data, filename: filename, mimeType: mime)
            AppLogger.generic("Successfully loaded Data from PhotosPickerItem: \(filename)").log()
            return .memory(request: request)
            
        }
        
        throw AppLogger.loadFailed("PhotosPickerItem did not resolve to a file URL or Data")
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
