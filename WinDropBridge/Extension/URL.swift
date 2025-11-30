//
//  URL.swift
//  WinDropBridge
//
//  Created by Davide Castaldi on 30/11/25.
//

import Foundation
import UniformTypeIdentifiers

extension URL: TransferLoadable {
    
    /// Creates a payload to transfer starting from a file URL (used for File Importer).
    /// - Parameter url: The file URL obtained from the File Importer
    /// - Returns: The transfer payload to use in a `TransferRequest`
    func asTransferPayload() async throws -> TransferPayload {
        
        // 1. Ensure the URL is accessible (e.g., if it needs security-scoped access)
        let didStartAccessing = self.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                self.stopAccessingSecurityScopedResource()
            }
        }
        
        let filename = self.lastPathComponent.sanitizeFilename()
        
        let fileSizeThreshold: Int64 = 10 * 1024 * 1024 // 10 MB limit for in-memory transfer
        
        if let attributes = try? FileManager.default.attributesOfItem(atPath: self.path),
           let fileSize = attributes[.size] as? Int64,
           fileSize <= fileSizeThreshold {
            
            do {
                let data = try Data(contentsOf: self)
                let mime = filename.mimeType()
                let request = TransferRequest(data: data, filename: filename, mimeType: mime)
                print("Loaded small file as Data: \(filename)")
                return .memory(request: request)
            } catch {
                AppLogger.loadFailed("Failed to load Data for small file: \(error.localizedDescription)").log()
            }
        }
        
        print("Loaded file as URL stream: \(filename)")
        return .stream(url: self, filename: filename)
    }
}
