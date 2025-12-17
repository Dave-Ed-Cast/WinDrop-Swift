//
//  AppSession.swift
//  WinDropBridge
//
//  Created by Davide Castaldi on 17/12/25.
//

import Foundation
import Observation

@Observable
final class AppSession {
    let connector = WinDropConnector()
    let transferViewModel = TransferViewModel(
        photoService: PhotoLibraryService()
    )
}
