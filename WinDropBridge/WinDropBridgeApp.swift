//
//  WinDropBridgeApp.swift
//  WinDropBridge
//
//  Created by Davide Castaldi on 17/10/25.
//

import SwiftUI

@main
struct WinDropBridgeApp: App {
    
    @State var receiver = WinDropReceiver()
    @State var connector = WinDropConnector.shared
    @State var session = AppSession()

    var body: some Scene {
        WindowGroup {
            ContentView(session: session, receiver: receiver)
                .onAppear {
                    startReceiver()
                }
                .onChange(of: connector.currentSession) { _, newSession in
                    // Restart receiver when session changes
                    if let session = newSession {
                        print("🔄 Session changed, restarting receiver on port \(session.localReceivePort)")
                        receiver.start(
                            port: session.localReceivePort,
                            sessionToken: session.sessionToken
                        )
                    }
                }
        }
    }
    
    private func startReceiver() {
        // Start receiver with the most recent saved session's port and token
        if let currentSession = connector.currentSession {
            receiver.start(
                port: currentSession.localReceivePort,
                sessionToken: currentSession.sessionToken
            )
        }
        // If no saved session, receiver won't start (user needs to scan QR first)
    }
}
