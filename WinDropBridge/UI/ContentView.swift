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
    @State private var selectedItem: PhotosPickerItem?
    @State private var receiver = WinDropReceiver()
    
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
            
            PhotosPicker("Choose Photo or Video", selection: $selectedItem, matching: .any(of: [.images, .videos]))
            .buttonStyle(.borderedProminent)
            .onChange(of: selectedItem) { _, newItem in
                tvm.handleSelection(newItem)
            }
            
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
