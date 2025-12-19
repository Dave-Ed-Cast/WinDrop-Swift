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
    @State private var tvm: TransferViewModel?
    
    // View-only state
    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var showingFilePicker = false
    @State private var showingQRScanner = false
    
    private let supportedTypes = UTType.supportedTypes
    private let connector = WinDropConnector()
    
    var body: some View {
        VStack(spacing: 20) {
            
            Text("WinDrop Client")
                .font(.title2)
                .bold()
            
            // MARK: - Connection status
            
            if let persisted = session.persistedSession {
                VStack(spacing: 4) {
                    Text("Persisted: \(persisted.host):\(Int(persisted.port))")
                        .font(.caption)
                        .fontWeight(.medium)
                }
                .padding(8)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(8)
            } else {
                Text("Status: Not Connected")
                    .font(.caption)
                    .foregroundColor(.red)
            }
            
            // MARK: - Transfer status
            
            if let tvm {
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
            }
            
            // MARK: - Scan QR
            
            Button {
                showingQRScanner = true
            } label: {
                Label("Scan QR Code", systemImage: "qrcode.viewfinder")
            }
            .buttonStyle(.borderedProminent)
            
            Divider().padding(.vertical)
            
            // MARK: - Pickers (enabled only when sender exists)
            
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
                .disabled(session.sender == nil)
                
                Button {
                    showingFilePicker = true
                } label: {
                    Label("Import from Files", systemImage: "folder")
                }
                .buttonStyle(.bordered)
                .disabled(session.sender == nil)
            }
        }
        .padding()
        
        // MARK: - Handlers
        
        // 🔑 Single source of truth: sender availability
        .onChange(of: session.sender) { _, sender in
            guard let sender else {
                tvm = nil
                return
            }
            
            if tvm == nil {
                tvm = TransferViewModel(
                    photoService: PhotoLibraryService(),
                    sender: sender
                )
            }
        }
        
        .onChange(of: selectedItems) { _, newItems in
            tvm?.handleSelection(newItems)
        }
        
        .onAppear {
            if let sender = session.sender, tvm == nil {
                tvm?.status = "on appear recreation"
                tvm = TransferViewModel(photoService: PhotoLibraryService(), sender: sender)
            }
        }
        
        .fileImporter(
            isPresented: $showingFilePicker,
            allowedContentTypes: supportedTypes,
            allowsMultipleSelection: true
        ) { result in
            guard let tvm else { return }
            
            switch result {
            case .success(let urls): tvm.handleFileImport(urls)
            case .failure(let error): tvm.status = "File import failed: \(error.localizedDescription)"
            }
        }
        
        .sheet(isPresented: $showingQRScanner) {
            QRCodeScannerSheet { base64 in
                connector.handleQRCode(base64String: base64) { handshake in
                    session.activateSession(from: handshake)
                }
            }
        }
    }
}
