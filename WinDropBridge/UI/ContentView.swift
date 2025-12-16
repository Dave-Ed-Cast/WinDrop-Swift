//
//  ContentView.swift
//  WinDropBridge
//
//  Created by Davide Castaldi on 17/10/25.
//

import SwiftUI
import PhotosUI
import AVKit

struct ContentView: View {
    
    @State var connector: WinDropConnector
    @Bindable var receiver: WinDropReceiver
    
    // This starts as nil and is only created once the QR handshake is successful
    @State private var tvm: TransferViewModel? = nil

    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var showingFilePicker = false
    @State private var showingQRScanner = false

    let supportedTypes = UTType.supportedTypes

    var body: some View {
        VStack(spacing: 20) {
            Text("WinDrop Client")
                .font(.title2)
                .bold()

            // 1. Connection Status Info
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

            // 2. File Metadata (if TVM exists)
            if let tvm, let name = tvm.filename {
                Text("Selected: \(name)")
                    .font(.footnote)
                    .foregroundColor(.blue)
                    .lineLimit(1)
            }

            // 3. Scan QR Button
            Button {
                showingQRScanner = true
            } label: {
                Label("Scan QR Code", systemImage: "qrcode.viewfinder")
            }
            .buttonStyle(.borderedProminent)

            Divider().padding(.vertical)

            // 4. Media Pickers (Only active if TVM is ready)
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
                .disabled(tvm == nil) // Safety Gate

                Button {
                    showingFilePicker = true
                } label: {
                    Label("Import from Files", systemImage: "folder")
                }
                .buttonStyle(.bordered)
                .disabled(tvm == nil) // Safety Gate
                
                Button("Force Init TVM") {
                    if let host = connector.receiverHost, let port = connector.receiverPort {
                         let hostString = host.debugDescription.replacingOccurrences(of: "\"", with: "")
                         let sender = WinDropSender(host: "192.168.1.150", port: 5050)
                         self.tvm = TransferViewModel(photoService: PhotoLibraryService(), sender: sender!)
                         print("Manual Override: TVM Created")
                    } else {
                         print("Manual Override Failed: Host/Port still nil")
                    }
                }
                .font(.caption)
                .buttonStyle(.plain)
            }
        }
        .padding()
        
        // --- Logic Handlers ---
        
        // Handle Photo Selection
        .onChange(of: selectedItems) { _, newItems in
            if let tvm {
                tvm.handleSelection(newItems)
            }
        }
        
        // Handle File Import
        .fileImporter(
            isPresented: $showingFilePicker,
            allowedContentTypes: supportedTypes,
            allowsMultipleSelection: true
        ) { result in
            guard let tvm else { return }
            switch result {
            case .success(let urls):
                tvm.handleFileImport(urls)
            case .failure(let error):
                tvm.status = "File import failed \(error.localizedDescription)"
            }
        }
        
        // Handle QR Scanner Sheet
        .sheet(isPresented: $showingQRScanner) {
            QRCodeScannerSheet { base64 in
                // Start the network handshake
                connector.handleQRCode(base64String: base64) { _ in }
            }
        }
        
        // Replace your existing .onChange with this "Fast-Track" version
        .onChange(of: connector.receiverHost) { _, newHost in
            guard let host = newHost,
                  let port = connector.receiverPort else {
                print("⏳ Host updated, but port still missing...")
                return
            }

            let hostString = host.debugDescription.replacingOccurrences(of: "\"", with: "")
            
            print("🚀 Fast-Tracking TVM creation for: \(hostString):\(port.rawValue)")
            
            if let sender = WinDropSender(host: hostString, port: Int(port.rawValue)) {
                // We initialize the TVM immediately.
                // We don't wait for the Windows machine to say "Ok".
                self.tvm = TransferViewModel(
                    photoService: PhotoLibraryService(),
                    sender: sender
                )
            }
        }
    }
}
