//
//  WinDropBridgeApp.swift
//  WinDropBridge
//
//  Created by Davide Castaldi on 17/10/25.
//

import SwiftUI

@main
struct WinDropBridgeApp: App {
    
    @State private var receiver = WinDropReceiver()

    var body: some Scene {
        WindowGroup {
            ContentView(receiver: receiver)
                .onAppear {
                    receiver.start()
                }
        }
    }
}
