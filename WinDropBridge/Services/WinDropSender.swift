//
//  WinDropSender.swift
//  WinDropBridge
//
//  Created by Davide Castaldi on 17/10/25.
//

import Foundation
import Network
import UniformTypeIdentifiers

final class WinDropSender: WinDropSending, Equatable {
    
    static func == (lhs: WinDropSender, rhs: WinDropSender) -> Bool {
        return lhs.host == rhs.host &&
               lhs.port == rhs.port &&
               lhs.sessionToken == rhs.sessionToken
    }
    
    private let host: NWEndpoint.Host
    private let port: NWEndpoint.Port
    private let sessionToken: String
    
    private static let Kilobyte: Int = 1024
    private static let Megabyte: Int = 1024 * Kilobyte
    
    let transferThreshold: Int
    let streamingChunkSize: Int
    
    init?(host: String, port: Int, sessionToken: String) {
        self.host = NWEndpoint.Host(host)
        guard let nwPort = NWEndpoint.Port(rawValue: UInt16(port)) else { return nil }
        self.port = nwPort
        self.sessionToken = sessionToken
        
        // Set the sizes using the new static constants
        self.transferThreshold = 512 * Self.Kilobyte // 512 KB
        self.streamingChunkSize = 2 * Self.Megabyte // 2 MB (Recommended)
    }
    
    func send(_ request: TransferRequest) async -> String {
        await withCheckedContinuation { cont in
            Task {
                do {
                    let reply = try await withConnection { conn in
                        try await self.performHandshake(conn)
                        return try await self.sendRequest(request, over: conn)
                    }
                    cont.resume(returning: reply)
                } catch {
                    cont.resume(returning: "Send failed: \(error.localizedDescription)")
                }
            }
        }
    }
    
    private func performHandshake(_ conn: NWConnection) async throws {
        // Send token + newline
        try await conn.sendAll(Data((sessionToken + "\n").utf8))
        
        // Wait for server ACCEPT response
        guard let reply = try await conn.receive(maximumLength: 32),
              let resp = String(data: reply, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              resp == "ACCEPT" else {
            throw NSError(domain: "WinDropSender", code: 1, userInfo: [NSLocalizedDescriptionKey: "Handshake rejected"])
        }
    }
    
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
    
    /// Streams a file as length-prefixed frames:
    /// [u32 big-endian length][length bytes] ... [0x00 00 00 00] EOF.
    @discardableResult
    func sendFileStream(url: URL, filename: String? = nil) async throws -> String {
        try await withConnection { conn in
            try await self.performHandshake(conn)
            let name = self.resolvedStreamFilename(url: url, override: filename)
            
            let mime = (UTType(filenameExtension: url.pathExtension) ?? .data)
                .preferredMIMEType ?? "application/octet-stream"
            
            let meta = HeaderMeta(filename: name, size: 0, mime: mime, chunked: true)
            try await conn.sendAll(Data(meta.serialize().utf8))
            
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            
            let chunkSize = self.streamingChunkSize
            
            for try await chunk in handle.bytesAsync(chunkSize: chunkSize) {
                try await self.sendChunkFrame(chunk, over: conn)
            }
            
            try await self.sendEOFFrame(over: conn)
            _ = try? await conn.receive(maximumLength: 1024)
            
            return "Streamed \(name) successfully"
        }
    }
    
    private func resolvedStreamFilename(url: URL, override: String? = nil) -> String {
        if let override { return override }
        return url.lastPathComponent.sanitizeFilename()
    }
    
    private func sendRequest(_ request: TransferRequest, over conn: NWConnection) async throws -> String {
        let meta = HeaderMeta(
            filename: request.filename,
            size: request.data.count,
            mime: request.mimeType ?? "application/octet-stream",
            chunked: false
        )
        try await conn.sendAll(Data(meta.serialize().utf8))
        print(request.filename)
        
        // 💡 Use the new descriptive property
        if request.data.count > self.transferThreshold {
            // 💡 Use the streaming chunk size for the small data transfer segmentation
            let chunkSize = self.streamingChunkSize
            for offset in stride(from: 0, to: request.data.count, by: chunkSize) {
                let end = min(offset + chunkSize, request.data.count)
                try await conn.sendAll(request.data.subdata(in: offset..<end))
            }
        } else {
            try await conn.sendAll(request.data)
        }
        
        // Using a constant for byte size here would also be good for clarity
        if let reply = try await conn.receive(maximumLength: 1024),
           let text = String(data: reply, encoding: .utf8) {
            return "Server replied: \(text.trimmingCharacters(in: .whitespacesAndNewlines))"
        } else {
            return "No reply from server"
        }
    }
    
    private func withConnection<T>(_ action: @escaping (NWConnection) async throws -> T) async throws -> T {
        let conn = NWConnection(host: host, port: port, using: .tcp)
        defer {
            conn.cancel()
        }
        
        try await conn.waitUntilReady()
        return try await action(conn)
    }
}
