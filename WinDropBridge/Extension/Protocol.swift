//
//  Protocol.swift
//  WinDropBridge
//
//  Created by Davide Castaldi on 18/10/25.
//

import Foundation

/// Protocol your app references (unchanged)
protocol WinDropSending {
    func send(_ request: TransferRequest) async -> String
    func sendFileStream(url: URL, filename: String?, chunkSize: Int) async throws -> String
}
