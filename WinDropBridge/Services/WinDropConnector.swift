//
//  WinDropConnector.swift
//  WinDropBridge
//
//  Created by Davide Castaldi on 15/12/25.
//


import Foundation
import Network

@Observable
final class WinDropConnector {
    
    static public let shared = WinDropConnector()
    
    var receiverHost: NWEndpoint.Host? = nil
    var receiverPort: NWEndpoint.Port? = nil
    var sessionId: String? = nil
    
    private var connection: NWConnection?
    private let queue = DispatchQueue(label: "windrop.connection.queue")
    
    func handleQRCode(base64String: String, completion: @escaping (HandshakeData) -> Void) {
        guard let handshake = decodeHandshake(from: base64String) else {
            print("❌ Invalid QR payload")
            return
        }
        
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
        let request = HandshakeRequest(
            type: "handshake",
            version: 1,
            sessionToken: token + "\n",
            client: "ios",
            clientVersion: "1.0.0"
        )
        
        guard let data = try? JSONEncoder().encode(request) else { return }
        
        sendFrame(data)
        receiveResponse()
    }
    
    private func receiveResponse() {
        receiveFrame { [weak self] data in
            guard let self = self, let data = data else { return }
            
            do {
                let response = try JSONDecoder().decode(HandshakeResponse.self, from: data)
                
                if response.status == "ok" {
                    print("✅ Session accepted: \(response.sessionId ?? "-")")
                    
                    Task { @MainActor in
                        // 1. Safely extract host and port from the existing connection
                        if let endpoint = self.connection?.endpoint,
                           case let .hostPort(host, port) = endpoint {
                            
                            // 2. Assign the host and port directly
                            // We use the 'host' object directly instead of converting to string and back
                            self.receiverHost = host
                            self.receiverPort = port
                        }
                        
                        // 3. Store the session ID
                        self.sessionId = response.sessionId
                        
                        // 4. Corrected Print statement for debugging
                        let hostStr = self.receiverHost?.debugDescription ?? "nil"
                        let portRaw = self.receiverPort?.rawValue ?? 0
                        print("📱 UI Properties updated: \(hostStr):\(portRaw)")
                    }
                } else {
                    print("❌ Server returned error status: \(response.status)")
                    self.cleanup()
                }
            } catch {
                print("❌ Response Decode Error: \(error)")
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
}
