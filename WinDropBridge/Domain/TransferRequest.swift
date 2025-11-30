//
//  TransferModels.swift
//  WinDropBridge
//
//  Created by Davide Castaldi on 17/10/25.
//

import Foundation
import _PhotosUI_SwiftUI

struct TransferRequest {
    let data: Data
    let filename: String
    let mimeType: String?
}

enum TransferInput {
    case url(URL)
    case photoPickerItem(PhotosPickerItem)
    case itemProvider(NSItemProvider)
    
    nonisolated var loadable: TransferLoadable {
        switch self {
        case .url(let url): return url
        case .photoPickerItem(let item): return item
        case .itemProvider(let provider): return provider
        }
    }
}
