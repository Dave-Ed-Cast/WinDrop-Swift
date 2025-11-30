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
}
