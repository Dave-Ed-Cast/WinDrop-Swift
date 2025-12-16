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

    var body: some Scene {
        WindowGroup {
            ContentView(connector: connector, receiver: receiver)
                .onAppear {
                    receiver.start()
                }
        }
    }
}
