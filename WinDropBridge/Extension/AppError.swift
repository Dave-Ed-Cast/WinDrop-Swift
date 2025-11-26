//
//  AppError.swift
//  WinDropBridge
//
//  Created by Davide Castaldi on 16/11/25.
//

import Foundation


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
