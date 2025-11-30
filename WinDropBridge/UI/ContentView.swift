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
    @State private var tvm: TransferViewModel = {
        guard let sender = WinDropSender(host: "192.168.1.160", port: 5050) else {
            fatalError("Could not create WinDropSender (invalid host or port)")
        }
        return TransferViewModel(
            photoService: PhotoLibraryService(),
            sender: sender
        )
    }()
    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var receiver = WinDropReceiver()
    @State private var showingFilePicker = false
    
    let supportedTypes = UTType.supportedTypes
    
    var body: some View {
        VStack(spacing: 16) {
            Text("WinDrop Client")
                .font(.title2)
                .bold()
            
            if let data = tvm.previewImageData, let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFit()
                    .cornerRadius(12)
                    .shadow(radius: 4)
                    .containerRelativeFrame(.horizontal) { length, _ in length * 0.9 }
                    .containerRelativeFrame(.vertical) { length, _ in length * 0.6 }
            }
            
            if let name = tvm.filename {
                Text(name)
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            
            Text(receiver.lastMessage)
                .font(.footnote)
                .foregroundColor(.gray)
                .padding()
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
            
            PhotosPicker(
                "Choose Photo or Video to upload",
                selection: $selectedItems,
                maxSelectionCount: 10,
                matching: .any(of: [.images, .videos]),
                photoLibrary: .shared()
            )
            .buttonStyle(.borderedProminent)
            .onChange(of: selectedItems) { _, newItems in
                tvm.handleSelection(newItems)
            }
            
            Button {
                showingFilePicker = true
            } label: {
                Text("Import from files")
            }
            .fileImporter(
                isPresented: $showingFilePicker,
                allowedContentTypes: supportedTypes,
                allowsMultipleSelection: true,
                onCompletion: { result in
                    switch result {
                    case .success(let urls):
                        tvm.handleFileImport(urls)
                    case .failure(let error):
                        tvm.status = "File import failed \(error.localizedDescription)"
                        AppLogger.loadFailed("File import failed \(error.localizedDescription)").log()
                    }
                }
            )
            
            Text(tvm.status)
                .foregroundColor(.gray)
                .padding(.top, 8)
        }
        .onAppear {
            let recv = WinDropReceiver()
            recv.start()
            receiver = recv
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
