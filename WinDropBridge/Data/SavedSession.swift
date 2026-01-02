//
//  SavedSession.swift
//  WinDropBridge
//
//  Created by Davide Castaldi on 02/01/26.
//

import Foundation

/// Rappresenta una sessione validata salvata localmente
struct SavedSession: Codable, Identifiable, Equatable {
    let id: String  // sessionId dal server
    let receiverIp: String
    let receiverPort: Int
    let sessionToken: String
    let publicKey: String
    let localReceivePort: Int  // iOS device's own port for receiving files
    let connectedAt: Date
    var lastUsedAt: Date
    
    /// Crea una SavedSession da HandshakeData dopo validazione
    init(from handshake: HandshakeData, sessionId: String, localReceivePort: Int, connectedAt: Date = Date()) {
        self.id = sessionId
        self.receiverIp = handshake.receiverIp
        self.receiverPort = handshake.receiverPort
        self.sessionToken = handshake.sessionToken
        self.publicKey = handshake.publicKey
        self.localReceivePort = localReceivePort
        self.connectedAt = connectedAt
        self.lastUsedAt = Date()
    }
    
    /// Aggiorna il timestamp dell'ultimo utilizzo
    mutating func updateLastUsed() {
        self.lastUsedAt = Date()
    }
    
    /// Descrizione leggibile per l'UI
    var displayName: String {
        "\(receiverIp):\(receiverPort)"
    }
}
