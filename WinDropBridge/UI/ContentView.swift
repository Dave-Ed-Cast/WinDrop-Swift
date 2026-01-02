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
    @Bindable var receiver: WinDropReceiver

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
    
    // MARK: - Helper Methods
    
    private func bindSenderIfNeeded() {
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
        print("✅ Sender bound: \(hostString):\(port.rawValue)")
    }

    @ViewBuilder
    private var connectionStatusView: some View {
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
    }

    @ViewBuilder
    private var savedSessionsView: some View {
        if !connector.savedSessions.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Saved Sessions")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    
                    Spacer()
                    
                    Button(role: .destructive) {
                        session.connector.flushAllSessions()
                    } label: {
                        Label("Flush All", systemImage: "trash.fill")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                }

                List {
                    ForEach(connector.savedSessions) { session in
                        savedSessionRow(session)
                    }
                }
                .listStyle(.plain)
                .frame(maxHeight: 200)
            }
            .padding(12)
            .background(Color.blue.opacity(0.05))
            .cornerRadius(8)
        }
    }

    @ViewBuilder
    private func savedSessionRow(_ session: SavedSession) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.displayName)
                        .font(.body)
                        .fontWeight(.medium)

                    Text("Token: \(session.sessionToken)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if connector.currentSession?.id == session.id {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                } else {
                    Image(systemName: "circle")
                        .foregroundColor(.gray)
                }
            }

            HStack(spacing: 8) {
                Text("Added: \(session.connectedAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption2)
                    .foregroundColor(.secondary)

                Spacer()

                Button(role: .destructive) {
                    connector.removeSession(session)
                } label: {
                    Image(systemName: "trash")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(8)
        .background(
            connector.currentSession?.id == session.id
                ? Color.green.opacity(0.1)
                : Color.gray.opacity(0.05)
        )
        .cornerRadius(8)
        .contentShape(Rectangle())
        .onTapGesture {
            if connector.currentSession?.id != session.id {
                connector.switchSession(session)
            }
        }
        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    var body: some View {
        VStack(spacing: 20) {

            Text("WinDrop Client")
                .font(.title2)
                .bold()

            // 1️⃣ Connection Status
            connectionStatusView
            
            // Receiver Status
            VStack(spacing: 4) {
                Text("Receiver: \(receiver.lastMessage)")
                    .font(.caption)
                    .foregroundColor(receiver.lastMessage.contains("❌") ? .red : .green)
                    .multilineTextAlignment(.center)
            }
            .padding(8)
            .background(Color.orange.opacity(0.1))
            .cornerRadius(8)

            // MARK: - Saved Sessions
            savedSessionsView

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
        
        // Bind sender on appear if session already exists (e.g., app reopened)
        .onAppear {
            bindSenderIfNeeded()
        }

        // Photo picker
        .onChange(of: selectedItems) { _, newItems in
            tvm.handleSelection(newItems)
        }

        // QR → bind sender (ONE place, ONE time per scan)
        .onChange(of: connector.sessionId) { _, _ in
            bindSenderIfNeeded()
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

        .sheet(isPresented: $showingQRScanner) {
            QRCodeScannerSheet { base64 in
                connector.handleQRCode(base64String: base64) { _ in }
            }
        }
    }
}
