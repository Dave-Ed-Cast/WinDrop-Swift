//
//  TransferPayload.swift
//  WinDropBridge
//
//  Created by Davide Castaldi on 30/11/25.
//

import Foundation

enum TransferPayload {
    case memory(request: TransferRequest)
    case stream(url: URL, filename: String)
    
    var filename: String {
        switch self {
        case .memory(let request):
            return request.filename
        case .stream(_, let filename):
            return filename
        }
    }
}
