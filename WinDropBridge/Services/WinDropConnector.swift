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
        
    var receiverHost: NWEndpoint.Host?
    var receiverPort: NWEndpoint.Port?
    var sessionId: String?
    
    private var connection: NWConnection?
    private let queue = DispatchQueue(label: "windrop.connection.queue")
    
    func handleQRCode(
        base64String: String,
        onDecoded: @escaping (HandshakeData) -> Void
    ) {
        guard let handshake = decodeHandshake(from: base64String) else {
            return
        }

        onDecoded(handshake)
    }
        
    private func decodeHandshake(from base64String: String) -> HandshakeData? {
        
        let cleanedBase64 = base64String.filter { !$0.isWhitespace }
        guard let decodedData = Data(base64Encoded: cleanedBase64, options: [.ignoreUnknownCharacters]),
              let decodedString = String(data: decodedData, encoding: .utf8) else {
            return nil
        }
        
        let components = decodedString.components(separatedBy: "|")
        
        guard components.count >= 3 else { return nil }
        
        let addressPart = components[0].trimmingCharacters(in: .whitespacesAndNewlines)
        let addressParts = addressPart.split(separator: ":")
        
        guard addressParts.count == 2, let portInt = Int(addressParts[1]) else {
            print("❌ 4. Invalid Address format: \(addressPart)")
            return nil
        }
        
        let recIP = String(addressParts[0])
        let port = portInt
        let token = components[1]
        let publicKey = components[2]
                
        return HandshakeData(
            receiverIp: recIP,
            receiverPort: port,
            sessionToken: token,
            publicKey: publicKey
        )
    }
    
    private func connect(to handshake: HandshakeData) {
        let host = NWEndpoint.Host(handshake.receiverIp)
        let port = NWEndpoint.Port(integerLiteral: UInt16(handshake.receiverPort))
        
        let connection = NWConnection(host: host, port: port, using: .tcp)
        self.connection = connection
        
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                Task { @MainActor in
                    self?.receiverHost = host
                    self?.receiverPort = port
                    self?.sendHandshake(token: handshake.sessionToken)
                }
            case .failed(let error):
                
                Task {
                    @MainActor in self?.cleanup()
                }
                AppLogger.loadFailed(error.localizedDescription).log()
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
            guard let self, let data else { return }

            Task { @MainActor in
                do {
                    let response = try JSONDecoder()
                        .decode(HandshakeResponse.self, from: data)

                    if response.status == "ok" {
                        if let endpoint = self.connection?.endpoint,
                           case let .hostPort(host, port) = endpoint {
                            self.receiverHost = host
                            self.receiverPort = port
                        }
                        self.sessionId = response.sessionId
                    } else {
                        self.cleanup()
                    }
                } catch {
                    self.cleanup()
                }
            }
        }
    }
        
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
    
    
    private func receiveFrame(
        completion: @escaping @Sendable (Data?) -> Void
    ) {
        connection?.receive(
            minimumIncompleteLength: 4,
            maximumLength: 4
        ) { [weak connection] header, _, _, error in
            guard
                let connection,
                let header,
                header.count == 4,
                error == nil
            else {
                completion(nil)
                return
            }

            let length = header.withUnsafeBytes {
                $0.load(as: UInt32.self).bigEndian
            }

            connection.receive(
                minimumIncompleteLength: Int(length),
                maximumLength: Int(length)
            ) { data, _, _, _ in
                completion(data)
            }
        }
    }
    
    private func cleanup() {
        connection?.cancel()
        connection = nil
    }
}
