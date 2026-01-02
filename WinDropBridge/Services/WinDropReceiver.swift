//
//  WinDropReceiver.swift
//  WinDropBridge
//
//  Created by Davide Castaldi on 23/10/25.
//

import Foundation
import Network
import Photos
import SwiftUI

@MainActor
@Observable
final class WinDropReceiver {

    var lastMessage: String = "Idle"

    private var listener: NWListener?
    private var port: NWEndpoint.Port?
    private var expectedSessionToken: String?

    func start(port: Int, sessionToken: String) {
        self.expectedSessionToken = sessionToken
        
        let nwPort = NWEndpoint.Port(integerLiteral: UInt16(port))
        self.port = nwPort
        
        do {
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true

            listener = try NWListener(using: params, on: nwPort)
            let msg = "📡 Listening on port \(port) with token: \(sessionToken)"
            lastMessage = msg
            print(msg)
        } catch {
            let msg = "❌ Listener error: \(error)"
            lastMessage = msg
            print(msg)
            return
        }

        listener?.newConnectionHandler = { [weak self] conn in
            print("🔌 New connection received")
            conn.start(queue: .global(qos: .userInitiated))
            Task { await self?.handle(conn) }
        }

        listener?.start(queue: .main)
    }

    private func handle(_ conn: NWConnection) async {
        defer { conn.cancel() }

        do {
            let reader = BufferedNWConnection(conn)
            print("🤝 Starting handshake...")

            // 0 — Perform handshake (token validation - separate from file transfer)
            try await performHandshake(reader)
            print("✅ Handshake successful")

            // 1 — Read the header (plain text: FILENAME, SIZE, MIME, ENDHEADER)
            print("📄 Reading header...")
            let headerData = try await reader.readUntil(Data("ENDHEADER\n".utf8))

            guard let headerStr = String(data: headerData, encoding: .utf8) else {
                let msg = "❌ Invalid header encoding"
                print(msg)
                update(msg)
                return
            }

            print("📋 Header: \(headerStr)")

            guard let meta = HeaderMeta.parse(headerStr) else {
                let msg = "❌ Header parse failed"
                print(msg)
                update(msg)
                return
            }

            let msg = "📥 Receiving \(meta.filename) (\(meta.size) bytes)..."
            print(msg)
            update(msg)

            // 2 — Prepare save path
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let destURL = docs.appendingPathComponent(meta.filename)

            // 3 — Receive exactly SIZE bytes of binary file data (no chunking, no encoding)
            if !meta.chunked {
                print("💾 Receiving \(meta.size) bytes of binary file data...")
                try await reader.receiveFile(to: destURL, size: meta.size)
                print("✅ File saved to: \(destURL.path)")
            } else {
                let msg = "⚠️ Chunked mode not implemented"
                print(msg)
                update(msg)
                return
            }

            let successMsg = "✅ Saved: \(meta.filename)"
            print(successMsg)
            update(successMsg)

            // 4 — Import to Photos if applicable
            await importIfNeeded(url: destURL, mime: meta.mime)

        } catch {
            let msg = "❌ Error: \(error.localizedDescription)"
            print(msg)
            update(msg)
        }
    }

    // MARK: - Handshake
    
    private func performHandshake(_ reader: BufferedNWConnection) async throws {
        // Receive sessionToken + newline
        print("🔑 Waiting for token...")
        let tokenData = try await reader.readUntil(Data("\n".utf8))
        
        guard let tokenStr = String(data: tokenData, encoding: .utf8) else {
            print("❌ Invalid token encoding")
            throw NSError(domain: "WinDropReceiver", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid token encoding"])
        }
        
        let receivedToken = tokenStr.trimmingCharacters(in: .whitespacesAndNewlines)
        print("🔑 Received token: '\(receivedToken)'")
        
        // Validate token (mandatory)
        guard let expected = expectedSessionToken else {
            print("❌ No expected token configured!")
            try await reader.sendAll(Data("REJECT\n".utf8))
            throw NSError(domain: "WinDropReceiver", code: 3, userInfo: [NSLocalizedDescriptionKey: "Server misconfigured: no expected token"])
        }
        
        print("🔍 Expected token: '\(expected)'")
        guard receivedToken == expected else {
            print("❌ Token mismatch! Sending REJECT")
            try await reader.sendAll(Data("REJECT\n".utf8))
            throw NSError(domain: "WinDropReceiver", code: 2, userInfo: [NSLocalizedDescriptionKey: "Handshake rejected: token mismatch"])
        }
        print("✅ Token validated")
        
        // Send ACCEPT response
        print("✅ Sending ACCEPT")
        try await reader.sendAll(Data("ACCEPT\n".utf8))
    }

    // MARK: - Photos

    @MainActor
    private func importIfNeeded(url: URL, mime: String) async {
        let isPhoto = mime.starts(with: "image/")
        let isVideo = mime.starts(with: "video/")

        guard isPhoto || isVideo else {
            update("Non-media file saved to Files")
            return
        }

        if PHPhotoLibrary.authorizationStatus(for: .addOnly) == .notDetermined {
            _ = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        }

        guard PHPhotoLibrary.authorizationStatus(for: .addOnly) == .authorized else {
            update("Photos permission denied")
            return
        }

        do {
            try await PHPhotoLibrary.performChangesAsync {
                if isVideo {
                    PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
                } else {
                    PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: url)
                }
            }

            try? FileManager.default.removeItem(at: url)
            update("Imported to Photos")

        } catch {
            update("Photos import failed: \(error.localizedDescription)")
        }
    }

    @MainActor
    private func update(_ msg: String) {
        lastMessage = msg
    }
}
