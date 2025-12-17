//
//  ContentView.swift
//  WinDropBridge
//
//  Created by Davide Castaldi on 17/10/25.
//

import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct ContentView: View {

    // App-level persistent state
    @Bindable var session: AppSession

    // View-only state
    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var showingFilePicker = false
    @State private var showingQRScanner = false

    private var connector: WinDropConnector {
        session.connector
    }

    private var tvm: TransferViewModel {
        session.transferViewModel
    }

    private let supportedTypes = UTType.supportedTypes

    var body: some View {
        VStack(spacing: 20) {

            Text("WinDrop Client")
                .font(.title2)
                .bold()

            // 1️⃣ Connection Status
            VStack(spacing: 4) {
                if let host = connector.receiverHost {
                    let cleanHost = host.debugDescription.replacingOccurrences(of: "\"", with: "")
                    Text("Connected to: \(cleanHost)")
                        .font(.caption)
                        .fontWeight(.medium)
                } else {
                    Text("Status: Not Connected")
                        .font(.caption)
                        .foregroundColor(.red)
                }

                if let port = connector.receiverPort {
                    Text("Port: \(String(port.rawValue))")
                        .font(.system(.caption, design: .monospaced))
                }
            }
            .padding(8)
            .background(Color.gray.opacity(0.1))
            .cornerRadius(8)

            // 2️⃣ Transfer Status
            if let name = tvm.filename {
                Text("Selected: \(name)")
                    .font(.footnote)
                    .foregroundColor(.blue)
                    .lineLimit(1)
            } else {
                Text(tvm.status)
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }

            // 3️⃣ Scan QR
            Button {
                showingQRScanner = true
            } label: {
                Label("Scan QR Code", systemImage: "qrcode.viewfinder")
            }
            .buttonStyle(.borderedProminent)

            Divider().padding(.vertical)

            // 4️⃣ Pickers (enabled only when sender bound)
            Group {
                PhotosPicker(
                    selection: $selectedItems,
                    maxSelectionCount: 10,
                    matching: .any(of: [.images, .videos]),
                    photoLibrary: .shared()
                ) {
                    Label("Choose Photos/Videos", systemImage: "photo.on.rectangle")
                }
                .buttonStyle(.bordered)
                .disabled(!tvm.isReady)

                Button {
                    showingFilePicker = true
                } label: {
                    Label("Import from Files", systemImage: "folder")
                }
                .buttonStyle(.bordered)
                .disabled(!tvm.isReady)
            }
        }
        .padding()

        // MARK: - Handlers

        // Photo picker
        .onChange(of: selectedItems) { _, newItems in
            tvm.handleSelection(newItems)
        }

        // QR → bind sender (ONE place, ONE time per scan)
        .onChange(of: connector.sessionId) { _, _ in
            guard
                let host = connector.receiverHost,
                let port = connector.receiverPort,
                let token = connector.sessionId
            else { return }

            let hostString = host.debugDescription.replacingOccurrences(of: "\"", with: "")

            guard let sender = WinDropSender(
                host: hostString,
                port: Int(port.rawValue),
                sessionToken: token
            ) else { return }

            tvm.bind(sender: sender)
        }

        // File importer
        .fileImporter(
            isPresented: $showingFilePicker,
            allowedContentTypes: supportedTypes,
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                tvm.handleFileImport(urls)
            case .failure(let error):
                tvm.status = "File import failed: \(error.localizedDescription)"
            }
        }

        // QR scanner sheet
        .sheet(isPresented: $showingQRScanner) {
            QRCodeScannerSheet { base64 in
                connector.handleQRCode(base64String: base64) { _ in }
            }
        }
    }
}
