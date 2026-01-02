//
//  BufferedNWConnection.swift
//  WinDropBridge
//
//  Created by Davide Castaldi on 03/11/25.
//

import Foundation
import Network

/// Stateful reader that preserves overflow (bytes read beyond a delimiter).
final class BufferedNWConnection {
    private let conn: NWConnection
    private var buffer: Data
    private let chunkSize: Int
    
    init(_ conn: NWConnection) {
        self.conn = conn
        self.buffer = Data()
        self.chunkSize = 8192
    }
    
    /// Reads until delimiter bytes appear; returns payload before delimiter.
    func readUntil(_ delimiter: Data) async throws -> Data {
        precondition(!delimiter.isEmpty)
        while true {
            if let range = buffer.range(of: delimiter) {
                let payload = buffer[..<range.lowerBound]
                buffer.removeSubrange(..<range.upperBound)
                return Data(payload)
            }
            // need more bytes
            let more = try await receiveChunk(max: chunkSize)
            guard !more.isEmpty else { throw makeError("EOF before delimiter") }
            buffer.append(more)
        }
    }
    
    /// Receives up to `n` bytes (respects buffered overflow first).
    func receive(upTo size: Int) async throws -> Data {
        if !buffer.isEmpty {
            let take = min(size, buffer.count)
            let out = buffer.prefix(take)
            buffer.removeSubrange(..<out.endIndex)
            return Data(out)
        }
        return try await receiveChunk(max: size)
    }
    
    private func receiveChunk(max: Int) async throws -> Data {
        try await withCheckedThrowingContinuation { cont in
            conn.receive(minimumIncompleteLength: 1, maximumLength: max) { data, _, isComplete, error in
                if let error { cont.resume(throwing: error); return }
                guard let data, !data.isEmpty else {
                    if isComplete {
                        cont.resume(returning: Data())
                    } else {
                        let error = self.makeError("Empty read")
                        Task.detached { cont.resume(throwing: error) }
                    }
                    return
                }
                cont.resume(returning: data)
            }
        }
    }
    
    nonisolated private func makeError(_ msg: String) -> NSError {
        NSError(domain: "BufferedNWConnection", code: -1, userInfo: [NSLocalizedDescriptionKey: msg])
    }
    
    /// Sends all data, ensuring it's fully transmitted.
    func sendAll(_ data: Data) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            Task {
                conn.send(content: data, completion: .contentProcessed { error in
                    if let error {
                        cont.resume(throwing: error)
                    } else {
                        cont.resume()
                    }
                })
            }
        }
    }
    
    /// Stream file to disk. Throws if fewer than `size` bytes are written.
    func receiveFile(to url: URL, size: Int) async throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        FileManager.default.createFile(atPath: url.path, contents: nil)
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        
        var written = 0
        // First, flush any overflow already buffered
        if !buffer.isEmpty {
            let take = min(size, buffer.count)
            try handle.write(contentsOf: buffer.prefix(take))
            buffer.removeSubrange(..<buffer.index(buffer.startIndex, offsetBy: take))
            written += take
        }
        
        while written < size {
            let toRead = min(8192, size - written)
            let chunk = try await receive(upTo: toRead)
            if chunk.isEmpty { break }
            try handle.write(contentsOf: chunk)
            written += chunk.count
        }
        
        if written != size {
            throw NSError(domain: "BufferedNWConnection", code: -2, userInfo: [
                NSLocalizedDescriptionKey: "File truncated: wrote \(written) of \(size) bytes"
            ])
        }
    }
}
