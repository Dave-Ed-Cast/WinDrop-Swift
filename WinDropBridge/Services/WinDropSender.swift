//
//  WinDropSender.swift
//  WinDropBridge
//
//  Created by Davide Castaldi on 17/10/25.
//

import Foundation
import Network

final class WinDropSender: WinDropSending {
    private let host: NWEndpoint.Host
    private let port: NWEndpoint.Port

    init(host: String, port: UInt16) {
        self.host = NWEndpoint.Host(host)
        self.port = NWEndpoint.Port(rawValue: port)!
    }

    func send(_ request: TransferRequest) async -> String {
        await withCheckedContinuation { cont in
            let connection = NWConnection(host: host, port: port, using: .tcp)

            @Sendable func finish(_ msg: String) {
                cont.resume(returning: msg)
                connection.cancel()
            }

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    Task.detached {
                        do {
                            var header = "FILENAME:\(request.filename)\nSIZE:\(request.data.count)\n"
                            if let mime = request.mimeType { header += "MIME:\(mime)\n" }
                            header += "ENDHEADER\n"

                            guard let headerData = header.data(using: .utf8) else {
                                finish("Header encoding failed")
                                return
                            }

                            try await connection.send(content: headerData)
                            try await connection.send(content: request.data)

                            if let reply = try await connection.receive(maximumLength: 1024),
                               let text = String(data: reply, encoding: .utf8) {
                                finish("Server replied: \(text.trimmingCharacters(in: .whitespacesAndNewlines))")
                            } else {
                                finish("No reply from server")
                            }
                        } catch {
                            finish("Send failed: \(error.localizedDescription)")
                        }
                    }
                case .failed(let err):
                    finish("Connection failed: \(err.localizedDescription)")
                default:
                    break
                }
            }
            connection.start(queue: .global())
        }
    }
}
