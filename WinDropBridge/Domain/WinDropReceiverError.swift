//
//  WinDropReceiverError.swift
//  WinDropBridge
//
//  Created by Davide Castaldi on 01/12/25.
//


import Foundation

// Custom errors for the file receiver
enum WinDropReceiverError: Error, LocalizedError {
    case connectionCancelled
    case unexpectedEOF
    case headerTooLarge
    case invalidHeaderFormat
    case fileWriteError(Error)
    
    var errorDescription: String? {
        switch self {
        case .connectionCancelled:
            return "The connection was cancelled."
        case .unexpectedEOF:
            return "Unexpected end of file/stream encountered."
        case .headerTooLarge:
            return "Header exceeded the maximum allowed size (4KB)."
        case .invalidHeaderFormat:
            return "The received header format is invalid or incomplete."
        case .fileWriteError(let error):
            return "Failed to write file to disk: \(error.localizedDescription)"
        }
    }
}
