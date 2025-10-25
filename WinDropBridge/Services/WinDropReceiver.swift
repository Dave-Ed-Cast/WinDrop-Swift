//
//  WinDropReceiver.swift
//  WinDropBridge
//
//  Created by Davide Castaldi on 23/10/25.
//

import Foundation
import Network
import Photos

@MainActor
@Observable
final class WinDropReceiver {
    var lastMessage: String = "Idle"
    
    private var listener: NWListener?
    private var activeConnections: [ObjectIdentifier: (conn: NWConnection, queue: DispatchQueue)] = [:]
    private let port: NWEndpoint.Port = 5051
    
    func start() {
        do {
            listener = try NWListener(using: .tcp, on: port)
            lastMessage = "Listening on port \(port)"
        } catch {
            lastMessage = "Failed to start listener: \(error)"
            return
        }
        
        listener?.newConnectionHandler = { [weak self] conn in
            guard let self else { return }
            let id = ObjectIdentifier(conn)
            let queue = DispatchQueue(label: "WinDropReceiver.conn.\(id)")
            Task { @MainActor in self.activeConnections[id] = (conn, queue) }
            conn.start(queue: queue)
            Task { await self.handleConnection(conn, id: id) }
        }
        
        listener?.start(queue: .main)
    }
    
    private func handleConnection(_ conn: NWConnection, id: ObjectIdentifier) async {
        defer {
            conn.cancel()
            activeConnections.removeValue(forKey: id)
        }
        
        do {
            let headerData = try await conn.readUntil("ENDHEADER\n")
            let headerText = String(decoding: headerData, as: UTF8.self)
            guard let meta = parseHeader(headerText) else {
                lastMessage = "Invalid header"
                return
            }
            
            let saveURL = FileManager.default
                .urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent(meta.filename)
            
            lastMessage = "Receiving \(meta.filename)..."
            
            try await conn.receiveFile(to: saveURL, size: meta.size)
            
            lastMessage = "Saved to: \(saveURL.lastPathComponent)"
            await saveToAppropriateLibrary(url: saveURL, mime: meta.mime)
        } catch {
            lastMessage = "Error: \(error.localizedDescription)"
        }
    }
    
    /// Parses a simple header string in the format:
    private func parseHeader(_ text: String) -> (filename: String, size: Int, mime: String)? {
        var filename = ""
        var size: Int = 0
        var mime = "application/octet-stream"
        
        for line in text.split(separator: "\n") {
            if line.hasPrefix("FILENAME:") {
                filename = String(line.dropFirst("FILENAME:".count))
            } else if line.hasPrefix("SIZE:") {
                size = Int(line.dropFirst("SIZE:".count)) ?? 0
            } else if line.hasPrefix("MIME:") {
                mime = String(line.dropFirst("MIME:".count))
            }
        }
        return filename.isEmpty || size <= 0 ? nil : (filename, size, mime)
    }
    
    @MainActor
    func saveToAppropriateLibrary(url: URL, mime: String) async {
        if mime.starts(with: "image/") || mime.starts(with: "video/") {
            await saveToPhotos(url: url, isVideo: mime.starts(with: "video/"))
        } else {
            lastMessage = "Non-media file saved: \(url.lastPathComponent)"
        }
    }
    
    
    @MainActor
    private func saveToPhotos(url: URL, isVideo: Bool) async {
        if PHPhotoLibrary.authorizationStatus(for: .addOnly) == .notDetermined {
            _ = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        }

        guard PHPhotoLibrary.authorizationStatus(for: .addOnly) == .authorized else {
            lastMessage = "Photos access denied."
            return
        }

        let tmpURL = FileManager.default.temporaryDirectory.appendingPathComponent(url.lastPathComponent)
        do {
            if FileManager.default.fileExists(atPath: tmpURL.path) {
                try FileManager.default.removeItem(at: tmpURL)
            }
            try FileManager.default.copyItem(at: url, to: tmpURL)
        } catch {
            lastMessage = "File copy error: \(error.localizedDescription)"
            return
        }

        do {
            try await PHPhotoLibrary.performChangesAsync {
                if isVideo {
                    PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: tmpURL)
                } else {
                    PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: tmpURL)
                }
            }
            lastMessage = "Imported to Photos: \(url.lastPathComponent)"
        } catch {
            lastMessage = "Failed to import: \(error.localizedDescription)"
            print("[WinDropReceiver] Import error:", error)
        }

        try? FileManager.default.removeItem(at: tmpURL)
    }
}
