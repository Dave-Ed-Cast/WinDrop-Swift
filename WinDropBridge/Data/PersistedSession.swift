//
//  PersistedSession.swift
//  WinDropBridge
//
//  Created by Davide Castaldi on 18/12/25.
//

import Foundation
import Network

struct PersistedSession: Codable {
    let host: String
    let port: UInt16
    let sessionToken: String

    var endpoint: NWEndpoint {
        .hostPort(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(rawValue: port)!
        )
    }
}
