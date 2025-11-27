//
//  AppError.swift
//  WinDropBridge
//
//  Created by Davide Castaldi on 16/11/25.
//

import Foundation


enum AppError: LocalizedError {
    case permissionDenied
    case loadFailed(String)
    case generic(String)

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Photo Library access was denied."
        case .loadFailed(let msg):
            return "Failed to load item: \(msg)"
        case .generic(let msg):
            return msg
        }
    }
}
