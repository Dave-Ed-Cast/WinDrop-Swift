//
//  PhotoLibraryService.swift
//  WinDropBridge
//
//  Created by Davide Castaldi on 17/10/25.
//

import Foundation
import Photos
import PhotosUI
import _PhotosUI_SwiftUI

final class PhotoLibraryService {
    
    /// Requests authorization
    func ensurePhotosAuth() async throws {
        let current = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if current == .authorized || current == .limited { return }
        let newStatus = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        guard newStatus == .authorized || newStatus == .limited else {
            throw AppLogger.permissionDenied
        }
    }
}
