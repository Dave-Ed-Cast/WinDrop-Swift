//
//  NWConnection.swift
//  WinDropBridge
//
//  Created by Davide Castaldi on 18/10/25.
//

import Foundation
import Network

extension NWConnection {
    enum NWError: Error {
        case posix(POSIXErrorCode)
        case dns(Int32)
        case tls(OSStatus)
    }

    func send(content: Data) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            self.send(content: content, completion: .contentProcessed { error in
                if let error { cont.resume(throwing: error) } else { cont.resume() }
            })
        }
    }

    func receive(maximumLength: Int) async throws -> Data? {
        try await withCheckedThrowingContinuation { cont in
            self.receive(minimumIncompleteLength: 1, maximumLength: maximumLength) { data, _, _, error in
                if let error { cont.resume(throwing: error) } else { cont.resume(returning: data) }
            }
        }
    }

    func sendAll(_ data: Data) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            self.send(content: data, completion: .contentProcessed { err in
                if let err { cont.resume(throwing: err) } else { cont.resume() }
            })
        }
    }

    func waitUntilReady(timeout: TimeInterval = 10) async throws {
        try await withCheckedThrowingContinuation { cont in
            self.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    cont.resume()
                    self.stateUpdateHandler = nil
                case .failed(let error):
                    cont.resume(throwing: error)
                    self.stateUpdateHandler = nil
                default:
                    break
                }
            }
            self.start(queue: .global())
        }
    }

    func readUntil(_ delimiter: String) async throws -> Data {
        guard let delimiterData = delimiter.data(using: .utf8) else {
            throw NSError(domain: "NWConnection", code: -1, userInfo: [NSLocalizedDescriptionKey: "Delimiter encoding failed"])
        }
        var buffer = Data()
        while true {
            let chunk = try await receiveChunk()
            buffer.append(chunk)
            if buffer.range(of: delimiterData, options: [], in: buffer.startIndex..<buffer.endIndex) != nil {
                return buffer
            }
        }
    }
    /// Receives a file of a known size and writes it directly to disk.
    func receiveFile(to url: URL, size: Int) async throws {
        FileManager.default.createFile(atPath: url.path, contents: nil)
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        var total = 0
        while total < size {
            guard let chunk = try await safeReceiveChunk(maxLength: min(8192, size - total)) else {
                print("[WinDropReceiver] Stream ended early at \(total)/\(size) bytes")
                break
            }
            try handle.write(contentsOf: chunk)
            total += chunk.count
        }
        print("[WinDropReceiver] Finished receiving \(total)/\(size) bytes")
    }

    private func safeReceiveChunk(maxLength: Int) async throws -> Data? {
        try await withCheckedThrowingContinuation { cont in
            self.receive(minimumIncompleteLength: 1, maximumLength: maxLength) { data, _, isComplete, error in
                if let error {
                    if case .posix(let code) = error, code == .ENODATA {
                        cont.resume(returning: nil) // graceful EOF
                    } else {
                        cont.resume(throwing: error)
                    }
                    return
                }
                if let data, !data.isEmpty {
                    cont.resume(returning: data)
                } else if isComplete {
                    cont.resume(returning: nil)
                } else {
                    cont.resume(throwing: NSError(
                        domain: "NWConnection",
                        code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "Empty read without completion"]
                    ))
                }
            }
        }
    }

    private func receiveChunk() async throws -> Data {
        try await withCheckedThrowingContinuation { cont in
            self.receive(minimumIncompleteLength: 1, maximumLength: 8192) { data, _, _, error in
                if let error {
                    cont.resume(throwing: error)
                    return
                }
                guard let data, !data.isEmpty else {
                    cont.resume(throwing: NSError(domain: "NWConnection", code: -1, userInfo: [
                        NSLocalizedDescriptionKey: "No data received or connection closed."
                    ]))
                    return
                }
                cont.resume(returning: data)
            }
        }
    }
}
