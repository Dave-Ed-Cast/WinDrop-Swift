//
//  Protocol.swift
//  WinDropBridge
//
//  Created by Davide Castaldi on 18/10/25.
//

import Foundation

/// Protocol your app references (unchanged)
protocol WinDropSending: Sendable {
    func send(_ request: TransferRequest) async -> String
    func sendFileStream(url: URL, filename: String?) async throws -> String
}

protocol TransferLoadable {
    /// Transforms the input source into a TransferPayload.
    /// It handles the asynchronous loading and file resolution specific to the conforming type.
    func asTransferPayload() async throws -> TransferPayload
}
