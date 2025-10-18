//
//  NWConnection.swift
//  WinDropBridge
//
//  Created by Davide Castaldi on 18/10/25.
//

import Foundation
import Network

extension NWConnection {
    func send(content: Data) async throws {
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            self.send(content: content, completion: .contentProcessed { error in
                if let error { c.resume(throwing: error) } else { c.resume() }
            })
        }
    }

    func receive(maximumLength: Int) async throws -> Data? {
        try await withCheckedThrowingContinuation { c in
            self.receive(minimumIncompleteLength: 1, maximumLength: maximumLength) { data, _, _, error in
                if let error { c.resume(throwing: error) } else { c.resume(returning: data) }
            }
        }
    }
}
