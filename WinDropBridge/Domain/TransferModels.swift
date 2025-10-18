//
//  TransferModels.swift
//  WinDropBridge
//
//  Created by Davide Castaldi on 17/10/25.
//

import Foundation
import UniformTypeIdentifiers

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
        case .loadFailed(let m): return m
        }
    }
}

struct TransferRequest {
    let data: Data
    let filename: String
    let mimeType: String?

    static func mimeType(for filename: String) -> String? {
        let ext = (filename as NSString).pathExtension.lowercased()
        guard let ut = UTType(filenameExtension: ext) else { return nil }
        return ut.preferredMIMEType
    }

    static func sanitizeFilename(_ name: String) -> String {
        let invalid = CharacterSet(charactersIn: "\\/:*?\"<>|")
        let cleaned = name.unicodeScalars.map { invalid.contains($0) ? "_" : Character($0) }.map(String.init).joined()
        return cleaned.isEmpty ? "file_\(Int(Date().timeIntervalSince1970)).bin" : cleaned
    }
}
