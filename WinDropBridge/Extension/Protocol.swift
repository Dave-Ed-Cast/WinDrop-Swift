//
//  Protocol.swift
//  WinDropBridge
//
//  Created by Davide Castaldi on 18/10/25.
//

import Foundation

protocol WinDropSending {
    func send(_ request: TransferRequest) async -> String
}
