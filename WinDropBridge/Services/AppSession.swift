//
//  AppSession.swift
//  WinDropBridge
//
//  Created by Davide Castaldi on 17/12/25.
//

import Foundation
import Observation
import Network

@Observable
final class AppSession {

    private static let storageKey = "windrop.session"

    private(set) var sender: WinDropSender?
    private(set) var persistedSession: PersistedSession?

    init() {
        restoreIfAvailable()
    }

    func activateSession(from handshake: HandshakeData) {
        let session = PersistedSession(
            host: handshake.receiverIp,
            port: UInt16(handshake.receiverPort),
            sessionToken: handshake.sessionToken
        )

        persist(session)
        buildSender(from: session)
    }

    func clearSession() {
        persistedSession = nil
        sender = nil
        UserDefaults.standard.removeObject(forKey: Self.storageKey)
    }

    // MARK: - Persistence

    private func persist(_ session: PersistedSession) {
        persistedSession = session
        guard let data = try? JSONEncoder().encode(session) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }

    private func restoreIfAvailable() {
        guard sender == nil else { return }

        guard
            let data = UserDefaults.standard.data(forKey: Self.storageKey),
            let session = try? JSONDecoder().decode(PersistedSession.self, from: data)
        else { return }

        persistedSession = session
        buildSender(from: session)
    }

    // MARK: - Sender

    private func buildSender(from session: PersistedSession) {
        sender = WinDropSender(
            host: session.host,
            port: Int(session.port),
            sessionToken: session.sessionToken
        )
    }
}
