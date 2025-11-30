//
//  UTType.swift
//  WinDropBridge
//
//  Created by Davide Castaldi on 30/11/25.
//

import Foundation
import UniformTypeIdentifiers

extension UTType {
    
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
}
