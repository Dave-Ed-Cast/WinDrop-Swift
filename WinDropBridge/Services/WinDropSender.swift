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

    init(host: String, port: UInt16) {
        self.host = NWEndpoint.Host(host)
        self.port = NWEndpoint.Port(rawValue: port)!
    }

    // MARK: - Single-shot send (SIZE path; small files)
    func send(_ request: TransferRequest) async -> String {
        await withCheckedContinuation { cont in
            let connection = NWConnection(host: host, port: port, using: .tcp)
            self.connection = connection

            @Sendable func finish(_ msg: String) {
                cont.resume(returning: msg)
                connection.cancel()
                Task { @MainActor in self.connection = nil }
            }

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    Task.detached {
                        do {
                            var header = "FILENAME:\(request.filename)\n"
                            header += "SIZE:\(request.data.count)\n"
                            if let mime = request.mimeType { header += "MIME:\(mime)\n" }
                            header += "ENDHEADER\n"
                            try await connection.sendAll(Data(header.utf8))
                            try await connection.sendAll(request.data)

                            if let reply = try await connection.receive(maximumLength: 1024),
                               let text = String(data: reply, encoding: .utf8) {
                                finish("Server replied: \(text.trimmingCharacters(in: .whitespacesAndNewlines))")
                            } else {
                                finish("No reply from server")
                            }
                        } catch {
                            finish("Send failed: \(error.localizedDescription)")
                        }
                    }
                case .failed(let err):
                    finish("Connection failed: \(err.localizedDescription)")
                default:
                    break
                }
            }
            connection.start(queue: .global())
        }
    }

    // MARK: - Chunked streaming (length-prefixed frames)

    /// Public API used by Files/Share paths. Streams a file in frames:
    /// [u32 big-endian length][length bytes] ... [0x00 00 00 00] EOF.
    @discardableResult
    func sendFileStream(url: URL, filename: String? = nil, chunkSize: Int = 256 * 1024) async throws -> String {
        let name = filename ?? url.lastPathComponent
        let ut = UTType(filenameExtension: url.pathExtension) ?? .data
        let mime = ut.preferredMIMEType ?? "application/octet-stream"

        let conn = NWConnection(host: host, port: port, using: .tcp)
        self.connection = conn

        return try await withCheckedThrowingContinuation { cont in
            conn.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    Task.detached {
                        do {
                            // 1️⃣ Send CHUNKED header
                            var header = "FILENAME:\(name)\n"
                            header += "MIME:\(mime)\n"
                            header += "CHUNKED:YES\nENDHEADER\n"
                            try await conn.sendAll(Data(header.utf8))

                            // 2️⃣ Stream the file
                            let fh = try FileHandle(forReadingFrom: url)
                            defer { try? fh.close() } // cleanup even on error

                            while true {
                                let data = try fh.read(upToCount: chunkSize) ?? Data()
                                if data.isEmpty { break }
                                try await self.sendChunkFrame(data, over: conn)
                            }

                            // 3️⃣ EOF frame
                            try await self.sendEOFFrame(over: conn)

                            // 4️⃣ Optional ACK from server
                            _ = try? await conn.receive(maximumLength: 3)

                            cont.resume(returning: "Streamed \(name) successfully")
                        } catch {
                            cont.resume(throwing: error)
                        }

                        // 5️⃣ Guaranteed cleanup (Swift style)
                        conn.cancel()
                        await MainActor.run { self.connection = nil }
                    }

                case .failed(let e):
                    cont.resume(throwing: e)

                default:
                    break
                }
            }

            conn.start(queue: .global())
        }
    }

    /// Frame = 4-byte BE length + payload
    private func sendChunkFrame(_ payload: Data, over conn: NWConnection) async throws {
        var len = UInt32(payload.count)
        let lenBE = len.bigEndian
        let lenData = withUnsafeBytes(of: lenBE) { Data($0) }
        try await conn.sendAll(lenData)
        try await conn.sendAll(payload)
    }

    /// EOF frame = 4 zero bytes
    private func sendEOFFrame(over conn: NWConnection) async throws {
        var z: UInt32 = 0
        let zBE = z.bigEndian
        let eof = withUnsafeBytes(of: zBE) { Data($0) }
        try await conn.sendAll(eof)
    }

    // MARK: - Legacy close hook (kept for interface compatibility)
    func finishTransfer() async {
        guard let connection else { return }
        // Send EOF frame if the caller forgot (harmless if already sent)
        do {
            var z: UInt32 = 0
            let zBE = z.bigEndian
            let eof = withUnsafeBytes(of: zBE) { Data($0) }
            try await connection.sendAll(eof)
        } catch {
            // ignore close errors
        }
        connection.cancel()
        Task { @MainActor in self.connection = nil }
    }
}
