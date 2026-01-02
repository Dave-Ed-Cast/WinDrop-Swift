//
//  HandshakeData.swift
//  WinDropBridge
//
//  Created by Davide Castaldi on 15/12/25.
//


import Foundation

/// QR payload decoded from Base64 JSON
struct HandshakeData: Codable {
    let receiverIp: String
    let receiverPort: Int
    let sessionToken: String
    let publicKey: String
    
    // Clean the IP manually if needed
    var cleanIP: String {
        receiverIp.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}



/// Initial handshake message sent to Windows
struct HandshakeRequest: Codable {
    let type: String
    let client: String
    let sessionToken: String
    let receiverListenPort: Int
}

/// Response from Windows
struct HandshakeResponse: Codable {
    let status: String
    let sessionId: String?
    let expiresInMs: Int?
    let reason: String?
}
