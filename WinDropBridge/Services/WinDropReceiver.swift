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
    private let port: NWEndpoint.Port = 5051

    func start() {
        do {
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true

            listener = try NWListener(using: params, on: port)
            lastMessage = "Listening on port \(port)"
        } catch {
            lastMessage = "Listener error: \(error)"
            return
        }

        listener?.newConnectionHandler = { [weak self] conn in
            conn.start(queue: .global(qos: .userInitiated))
            Task { await self?.handle(conn) }
        }

        listener?.start(queue: .main)
    }

    private func handle(_ conn: NWConnection) async {
        defer { conn.cancel() }

        do {
            let reader = BufferedNWConnection(conn)

            // 1 — Read the header
            let headerData = try await reader.readUntil(Data("ENDHEADER\n".utf8))

            guard let headerStr = String(data: headerData, encoding: .utf8) else {
                update("Invalid header encoding")
                return
            }

            guard let meta = HeaderMeta.parse(headerStr) else {
                update("Header parse failed")
                return
            }

            update("Receiving \(meta.filename)…")

            // 2 — Prepare save path
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let destURL = docs.appendingPathComponent(meta.filename)

            // 3 — Receive the file (always required if meta.chunked == false)
            if !meta.chunked {
                try await reader.receiveFile(to: destURL, size: meta.size)
            } else {
                // CHUNKED mode existed in your original pipeline — you never used it yet
                update("Chunked mode not implemented")
                return
            }

            update("Saved: \(meta.filename)")

            // 4 — Import to Photos if applicable
            await importIfNeeded(url: destURL, mime: meta.mime)

        } catch {
            update("Error: \(error.localizedDescription)")
        }
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
