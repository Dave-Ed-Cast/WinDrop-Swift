//
//  WinDropSender.swift
//  WinDropBridge
//
//  Created by Davide Castaldi on 17/10/25.
//

import Foundation
import Network
import UniformTypeIdentifiers

final class WinDropSender: WinDropSending {
    
    private let host: NWEndpoint.Host
    private let port: NWEndpoint.Port
    private var connection: NWConnection?
    
    init?(host: String, port: UInt16) {
        self.host = NWEndpoint.Host(host)
        guard let nwPort = NWEndpoint.Port(rawValue: port) else { return nil }
        self.port = nwPort
    }
    
    func send(_ request: TransferRequest) async -> String {
        await withCheckedContinuation { cont in
            Task {
                do {
                    let reply = try await withConnection { conn in
                        try await self.sendRequest(request, over: conn)
                    }
                    cont.resume(returning: reply)
                } catch {
                    cont.resume(returning: "Send failed: \(error.localizedDescription)")
                }
            }
        }
    }

    /// Streams a file as length-prefixed frames:
    /// [u32 big-endian length][length bytes] ... [0x00 00 00 00] EOF.
    @discardableResult
    func sendFileStream(url: URL, filename: String? = nil, chunkSize: Int = 256 * 1024) async throws -> String {
        try await withConnection { conn in
            let name = filename ?? url.lastPathComponent
            let utt = UTType(filenameExtension: url.pathExtension) ?? .data
            let mime = utt.preferredMIMEType ?? "application/octet-stream"
            
            var header = "FILENAME:\(name)\n"
            header += "MIME:\(mime)\n"
            header += "CHUNKED:YES\nENDHEADER\n"
            try await conn.sendAll(Data(header.utf8))
            
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }

            for try await chunk in handle.bytesAsync(chunkSize: chunkSize) {
                try await self.sendChunkFrame(chunk, over: conn)
            }
            
            try await self.sendEOFFrame(over: conn)
            _ = try? await conn.receive(maximumLength: 3)
            return "Streamed \(name) successfully"
        }
    }

    private func withConnection<T>(_ action: @escaping (NWConnection) async throws -> T) async throws -> T {
        let conn = NWConnection(host: host, port: port, using: .tcp)
        self.connection = conn
        defer {
            conn.cancel()
            Task { @MainActor in self.connection = nil }
        }
        
        try await conn.waitUntilReady()
        return try await action(conn)
    }

    private func sendRequest(_ request: TransferRequest, over conn: NWConnection) async throws -> String {
        let header = buildHeader(for: request)
        try await conn.sendAll(Data(header.utf8))
        
        if request.data.count > 512_000 {
            let chunkSize = 256 * 1024
            for offset in stride(from: 0, to: request.data.count, by: chunkSize) {
                let end = min(offset + chunkSize, request.data.count)
                let slice = request.data.subdata(in: offset..<end)
                try await conn.sendAll(slice)
            }
        } else {
            try await conn.sendAll(request.data)
        }
        
        if let reply = try await conn.receive(maximumLength: 1024),
           let text = String(data: reply, encoding: .utf8) {
            return "Server replied: \(text.trimmingCharacters(in: .whitespacesAndNewlines))"
        } else {
            return "No reply from server"
        }
    }

    private func buildHeader(for request: TransferRequest) -> String {
        var header = "FILENAME:\(request.filename)\n"
        header += "SIZE:\(request.data.count)\n"
        if let mime = request.mimeType { header += "MIME:\(mime)\n" }
        header += "ENDHEADER\n"
        return header
    }
}

fileprivate extension WinDropSender {
    /// Frame = 4-byte BE length + payload
    func sendChunkFrame(_ payload: Data, over conn: NWConnection) async throws {
        let len = withUnsafeBytes(of: UInt32(payload.count).bigEndian) { Data($0) }
        try await conn.sendAll(len)
        try await conn.sendAll(payload)
    }
    
    /// EOF frame = 4 zero bytes
    func sendEOFFrame(over conn: NWConnection) async throws {
        let eof = withUnsafeBytes(of: UInt32.zero.bigEndian) { Data($0) }
        try await conn.sendAll(eof)
    }
}
