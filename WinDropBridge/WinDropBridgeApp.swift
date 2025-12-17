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
            ContentView(session: session)
                .onAppear {
                    receiver.start()
                }
        }
    }
}
