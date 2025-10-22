//
//  FileHandle.swift
//  WinDropBridge
//
//  Created by Davide Castaldi on 21/10/25.
//

import Foundation

extension FileHandle {
    func bytesAsync(chunkSize: Int) -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { continuation in
            Task.detached {
                do {
                    while true {
                        let data = try self.read(upToCount: chunkSize) ?? Data()
                        if data.isEmpty { break }
                        continuation.yield(data)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}
