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
    
    let maxSize: Int
    let byte: Int
    let factor: Int
    
    init?(host: String, port: UInt16) {
        self.host = NWEndpoint.Host(host)
        guard let nwPort = NWEndpoint.Port(rawValue: port) else { return nil }
        self.port = nwPort
        
        self.maxSize = 512_000
        self.factor = 256
        self.byte = 1024
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

    private func withConnection<T>(_ action: @escaping (NWConnection) async throws -> T) async throws -> T {
        let conn = NWConnection(host: host, port: port, using: .tcp)
        defer {
            conn.cancel()
        }
        
        try await conn.waitUntilReady()
        return try await action(conn)
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
        
        if request.data.count > self.maxSize {
            let chunkSize = self.factor * self.byte
            for offset in stride(from: 0, to: request.data.count, by: chunkSize) {
                let end = min(offset + chunkSize, request.data.count)
                try await conn.sendAll(request.data.subdata(in: offset..<end))
            }
        } else {
            try await conn.sendAll(request.data)
        }

        if let reply = try await conn.receive(maximumLength: self.byte),
           let text = String(data: reply, encoding: .utf8) {
            return "Server replied: \(text.trimmingCharacters(in: .whitespacesAndNewlines))"
        } else {
            return "No reply from server"
        }
    }

    /// Streams a file as length-prefixed frames:
    /// [u32 big-endian length][length bytes] ... [0x00 00 00 00] EOF.
    @discardableResult
    func sendFileStream(url: URL, filename: String? = nil) async throws -> String {
        try await withConnection { conn in
            
            let name = self.resolvedStreamFilename(url: url, override: filename)
            
            let mime = (UTType(filenameExtension: url.pathExtension) ?? .data)
                .preferredMIMEType ?? "application/octet-stream"

            let meta = HeaderMeta(filename: name, size: 0, mime: mime, chunked: true)
            try await conn.sendAll(Data(meta.serialize().utf8))

            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            
            let chunkSize = self.factor * self.byte

            for try await chunk in handle.bytesAsync(chunkSize: chunkSize) {
                try await self.sendChunkFrame(chunk, over: conn)
            }

            try await self.sendEOFFrame(over: conn)
            _ = try? await conn.receive(maximumLength: 3)
            
            return "Streamed \(name) successfully"
        }
    }
    
    private func resolvedStreamFilename(url: URL, override: String? = nil) -> String {
        if let override { return override }
        return TransferRequest.sanitizeFilename(url.lastPathComponent)
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
