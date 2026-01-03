//
//  WinDropConnector.swift
//  WinDropBridge
//
//  Created by Davide Castaldi on 15/12/25.
//


import Foundation
import Network
import UIKit

@Observable
final class WinDropConnector {
    
    static public let shared = WinDropConnector()
    
    var receiverHost: NWEndpoint.Host? = nil
    var receiverPort: NWEndpoint.Port? = nil
    var sessionId: String? = nil
    var localReceivePort: Int? = nil  // iOS device's own port for receiving files
    var savedSessions: [SavedSession] = []
    
    let deviceName: String = UIDevice.current.name + "" + UIDevice.current.systemVersion
    
    /// Callback to start the receiver when handshake completes
    var onHandshakeSuccess: ((_ port: Int, _ sessionToken: String) -> Void)? = nil
    
    private var connection: NWConnection?
    private let queue = DispatchQueue(label: "windrop.connection.queue")
    private let sessionsStorageKey = "windrop.saved_sessions"
    private var pendingHandshake: HandshakeData? = nil  // Per persistenza dopo validazione
    
    // Sessione attualmente in uso
    var currentSession: SavedSession? {
        didSet {
            if let session = currentSession {
                receiverHost = NWEndpoint.Host(session.receiverIp)
                receiverPort = NWEndpoint.Port(integerLiteral: UInt16(session.receiverPort))
                sessionId = session.id
                localReceivePort = session.localReceivePort
            }
        }
    }
    
    // Inizializzazione: carica le sessioni salvate
    init() {
        loadSessions()
    }
    
    // MARK: - Session Persistence
    
    /// Carica tutte le sessioni salvate da UserDefaults
    private func loadSessions() {
        guard let data = UserDefaults.standard.data(forKey: sessionsStorageKey) else {
            print("📭 No saved sessions found")
            return
        }
        
        do {
            let sessions = try JSONDecoder().decode([SavedSession].self, from: data)
            self.savedSessions = sessions
            
            // Se c'è almeno una sessione, usala come sessione corrente
            if let mostRecent = sessions.max(by: { $0.lastUsedAt < $1.lastUsedAt }) {
                self.currentSession = mostRecent
                print("📱 Restored session: \(mostRecent.displayName)")
            }
        } catch {
            print("❌ Failed to load sessions: \(error)")
        }
    }
    
    /// Salva tutte le sessioni su UserDefaults
    private func saveSessions() {
        do {
            let data = try JSONEncoder().encode(savedSessions)
            UserDefaults.standard.set(data, forKey: sessionsStorageKey)
            print("💾 Saved \(savedSessions.count) session(s)")
        } catch {
            print("❌ Failed to save sessions: \(error)")
        }
    }
    
    /// Aggiunge una nuova sessione validata
    func addSession(_ session: SavedSession) {
        // Evita duplicati basati su sessionId
        savedSessions.removeAll { $0.id == session.id }
        savedSessions.insert(session, at: 0)
        saveSessions()
        
        // Usa la nuova sessione come corrente
        currentSession = session
        print("✅ Session added and set as current: \(session.displayName)")
    }
    
    /// Rimuove una sessione salvata
    func removeSession(_ session: SavedSession) {
        savedSessions.removeAll { $0.id == session.id }
        
        // Se era la sessione corrente, passa a quella più recente
        if currentSession?.id == session.id {
            currentSession = savedSessions.first
        }
        
        saveSessions()
        print("🗑️ Session removed: \(session.displayName)")
    }
    
    /// Clears all saved sessions
    func flushAllSessions() {
        savedSessions.removeAll()
        currentSession = nil
        saveSessions()
        print("🗑️ All sessions flushed")
    }
    
    /// Cambia la sessione attualmente in uso
    func switchSession(_ session: SavedSession) {
        currentSession = session
        var updated = session
        updated.updateLastUsed()
        
        // Aggiorna nella lista
        if let index = savedSessions.firstIndex(where: { $0.id == session.id }) {
            savedSessions[index] = updated
            saveSessions()
        }
        
        print("🔄 Switched to session: \(session.displayName)")
        
        // Trigger sessionId change to rebind sender in UI
        Task { @MainActor in
            self.sessionId = session.id
        }
    }
    
    /// Ripristina la connessione a una sessione salvata (per riavvio app)
    func reconnectToSession(_ session: SavedSession) {
        print("🔌 Reconnecting to saved session: \(session.displayName)")
        switchSession(session)
        
        // Crea un HandshakeData virtuale per il riconnect
        let handshake = HandshakeData(
            receiverIp: session.receiverIp,
            receiverPort: session.receiverPort,
            sessionToken: session.sessionToken,
            publicKey: session.publicKey
        )
        
        connect(to: handshake)
    }
    
    func handleQRCode(base64String: String, completion: @escaping (HandshakeData) -> Void) {
        guard let handshake = decodeHandshake(from: base64String) else {
            print("❌ Invalid QR payload")
            return
        }
        
        // Save QR code data
        saveQRCodeData(handshake)
        
        Task { @MainActor in
            self.receiverHost = NWEndpoint.Host(handshake.receiverIp)
            self.receiverPort = NWEndpoint.Port(integerLiteral: UInt16(handshake.receiverPort))
            // We set a "placeholder" session ID if the real one isn't back yet
            // to force the UI to trigger.
            self.sessionId = handshake.sessionToken
            
            print("📍 Connector updated with: \(handshake.receiverIp):\(handshake.receiverPort)")
            
            // Now attempt the actual TCP connection
            connect(to: handshake)
        }
    }
    
    // MARK: - QR Code Storage
    
    private func saveQRCodeData(_ handshake: HandshakeData) {
        let defaults = UserDefaults.standard
        
        // Save as a dictionary for easy retrieval
        let qrData: [String: Any] = [
            "receiverIp": handshake.receiverIp,
            "receiverPort": handshake.receiverPort,
            "sessionToken": handshake.sessionToken,
            "publicKey": handshake.publicKey,
            "scannedAt": ISO8601DateFormatter().string(from: Date())
        ]
        
        defaults.set(qrData, forKey: "lastScannedQRCode")
        print("💾 QR code data saved: \(handshake.receiverIp):\(handshake.receiverPort) with token \(handshake.sessionToken)")
    }
    
    // MARK: - Decode
    
    private func decodeHandshake(from base64String: String) -> HandshakeData? {
        print("\n--- 🔍 QR DECODE START ---")
        
        // 1. Clean and Decode Base64
        let cleanedBase64 = base64String.filter { !$0.isWhitespace }
        guard let decodedData = Data(base64Encoded: cleanedBase64, options: [.ignoreUnknownCharacters]),
              let decodedString = String(data: decodedData, encoding: .utf8) else {
            print("❌ 1. Base64 or UTF8 decoding failed")
            return nil
        }
        
        print("2. Decoded String: \(decodedString)")
        
        // 2. Split by the pipe delimiter
        let components = decodedString.components(separatedBy: "|")
        
        // Check for at least 3 parts (Address, Token, Key)
        guard components.count >= 3 else {
            print("❌ 3. Invalid Pipe Format. Found \(components.count) components. String: \(decodedString)")
            return nil
        }
        
        // 3. Extract Host and Port from component [0] (e.g. "192.168.1.150:5050")
        let addressPart = components[0].trimmingCharacters(in: .whitespacesAndNewlines)
        let addressParts = addressPart.split(separator: ":")
        
        guard addressParts.count == 2, let portInt = Int(addressParts[1]) else {
            print("❌ 4. Invalid Address format: \(addressPart)")
            return nil
        }
        
        let ip = String(addressParts[0])
        let port = portInt
        let token = components[1]
        let publicKey = components[2]
        
        print("✅ 5. Parsed successfully: \(ip):\(port)")
        
        return HandshakeData(
            receiverIp: ip,
            receiverPort: port,
            sessionToken: token,
            publicKey: publicKey
        )
    }
    
    private func connect(to handshake: HandshakeData) {
        // Salva il handshake per usarlo dopo la validazione
        self.pendingHandshake = handshake
        
        // Create the host and port once
        let host = NWEndpoint.Host(handshake.receiverIp)
        let port = NWEndpoint.Port(integerLiteral: UInt16(handshake.receiverPort))
        
        let connection = NWConnection(host: host, port: port, using: .tcp)
        self.connection = connection
        
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                print("✓ TCP connected to \(host):\(port)")
                Task { @MainActor in
                    // Store the native types for the UI and Sender
                    self?.receiverHost = host
                    self?.receiverPort = port
                    self?.sendHandshake(token: handshake.sessionToken)
                }
            case .failed(let error):
                print("❌ Connection failed: \(error)")
                Task { @MainActor in self?.cleanup() }
            default: break
            }
        }
        connection.start(queue: queue)
        
    }
    
    // MARK: - Handshake
    
    private func sendHandshake(token: String) {
        // Build handshake request with iOS local receive port
        // iOS listens on port 5051 for receiving files
        let localPort = 5051
        
        let deviceName = Self.resolveDeviceName()  // Informational only, not used for validation
        let handshakeRequest = HandshakeRequest(
            type: "HANDSHAKE",
            client: "iOS",
            sessionToken: token,
            receiverListenPort: localPort,
            deviceName: deviceName
        )
        
        guard let jsonData = try? JSONEncoder().encode(handshakeRequest),
              var jsonString = String(data: jsonData, encoding: .utf8) else {
            print("❌ Failed to encode handshake request")
            cleanup()
            return
        }
        
        // 🔍 Debug: Print the exact JSON being sent
        print("📤 Sending handshake JSON: \(jsonString.trimmingCharacters(in: .whitespacesAndNewlines))")
        print("🎯 iOS advertising listen port: \(localPort)")
        
        jsonString.append("\n")
        guard let data = jsonString.data(using: .utf8) else {
            cleanup()
            return
        }
        
        // Store the local port we're advertising
        self.localReceivePort = localPort
        
        connection?.send(content: data, completion: .contentProcessed { [weak self] error in
            if let error {
                print("❌ Failed to send handshake:", error)
                self?.cleanup()
                return
            }
            self?.receiveHandshakeResponse()
        })
    }
    
    private func receiveHandshakeResponse() {
        // Receive response without framing (ACCEPT or REJECT as plain text)
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 256) { [weak self] data, _, _, error in
            guard let self = self else { return }
            
            if let error {
                print("❌ Failed to receive handshake response:", error)
                self.cleanup()
                return
            }
            
            guard let data = data else {
                print("❌ No handshake response received")
                self.cleanup()
                return
            }
            
            let response = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            
            if response == "ACCEPT" {
                print("✅ Server accepted handshake")
                
                Task { @MainActor in
                    // Extract host and port from the existing connection
                    if let endpoint = self.connection?.endpoint,
                       case let .hostPort(host, port) = endpoint {
                        self.receiverHost = host
                        self.receiverPort = port
                    }
                    
                    // Crea e salva la sessione validata
                    if let handshake = self.pendingHandshake, let localPort = self.localReceivePort {
                        // Use the sessionToken as the ID - this is what the server knows
                        let savedSession = SavedSession(from: handshake, sessionId: handshake.sessionToken, localReceivePort: localPort)
                        self.addSession(savedSession)
                        self.pendingHandshake = nil
                        
                        // 🔥 Immediately notify the app to start the receiver
                        print("🎯 Starting receiver on port \(localPort) with token \(handshake.sessionToken)")
                        self.onHandshakeSuccess?(localPort, handshake.sessionToken)
                    }
                    
                    let hostStr = self.receiverHost?.debugDescription ?? "nil"
                    let portRaw = self.receiverPort?.rawValue ?? 0
                    print("📱 Connection ready: \(hostStr):\(portRaw)")
                }
            } else if response == "REJECT" {
                print("❌ Server rejected handshake - invalid or expired session token")
                self.cleanup()
            } else {
                print("❌ Unexpected server response: \(response)")
                self.cleanup()
            }
        }
    }
    
    // MARK: - Framing (length-prefixed)
    
    private func sendFrame(_ payload: Data) {
        var length = UInt32(payload.count).bigEndian
        let header = Data(bytes: &length, count: 4)
        
        connection?.send(content: header + payload, completion: .contentProcessed { error in
            if let error {
                print("❌ Send failed:", error)
            }
        })
    }
    
    private func parseHostPort(_ value: String) -> (host: String, port: Int)? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        
        let parts = trimmed.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: true)
        guard parts.count == 2 else {
            return nil
        }
        
        let host = String(parts[0])
        guard let port = Int(parts[1]), (1...65535).contains(port) else {
            return nil
        }
        
        return (host, port)
    }
    
    private func receiveFrame(completion: @escaping (Data?) -> Void) {
        connection?.receive(minimumIncompleteLength: 4, maximumLength: 4) { [weak self] header, _, _, error in
            guard
                let self,
                let header,
                header.count == 4,
                error == nil
            else {
                completion(nil)
                return
            }
            
            let length = header.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
            
            self.connection?.receive(minimumIncompleteLength: Int(length),
                                     maximumLength: Int(length)) { data, _, _, _ in
                completion(data)
            }
        }
    }
    
    private func cleanup() {
        connection?.cancel()
        connection = nil
    }
    
    // MARK: - Device Name Resolution
    
    /// Resolve the actual device name (informational only)
    private static func resolveDeviceName() -> String {
        return UIDevice.current.name + "" + UIDevice.current.systemVersion
    }
}

