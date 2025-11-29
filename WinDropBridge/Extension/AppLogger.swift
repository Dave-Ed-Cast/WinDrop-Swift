//
//  AppError.swift
//  WinDropBridge
//
//  Created by Davide Castaldi on 16/11/25.
//

import Foundation


enum AppLogger: LocalizedError {
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
    
    func log() { print("[\(String(describing: self))] Error: \(self.errorDescription ?? "Unknown Error")") }
}
