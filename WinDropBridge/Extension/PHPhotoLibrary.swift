//
//  PHPhotoLibrary.swift
//  WinDropBridge
//
//  Created by Davide Castaldi on 23/10/25.
//

import Photos

extension PHPhotoLibrary {
    /// Async/await wrapper around performChanges, guaranteed to run on the main queue.
    static func performChangesAsync(_ changes: @escaping () -> Void) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            DispatchQueue.main.async {
                PHPhotoLibrary.shared().performChanges(changes) { success, error in
                    if let error {
                        cont.resume(throwing: error)
                    } else if success {
                        cont.resume()
                    } else {
                        cont.resume(throwing: NSError(
                            domain: "PHPhotoLibraryError",
                            code: -1,
                            userInfo: [NSLocalizedDescriptionKey: "Unknown failure saving to Photos."]
                        ))
                    }
                }
            }
        }
    }
}
