//
//  ContentView.swift
//  WinDropBridge
//
//  Created by Davide Castaldi on 17/10/25.
//
import SwiftUI
import PhotosUI

struct ContentView: View {
    @State private var vm = TransferViewModel(
        photoService: PhotoLibraryService(),
        sender: WinDropSender(host: "192.168.1.160", port: 5050)
    )
    @State private var selectedItem: PhotosPickerItem?

    var body: some View {
        VStack(spacing: 16) {
            Text("WinDrop Client").font(.title2).bold()

            if let data = vm.previewImageData, let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable().scaledToFit()
                    .cornerRadius(12).shadow(radius: 4)
                    .containerRelativeFrame(.horizontal) { length, _ in
                        length * 0.9
                    }
                    .containerRelativeFrame(.vertical) { length, _ in
                        length * 0.6
                    }
            }

            if let name = vm.filename {
                Text("\(name)")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .lineLimit(1).truncationMode(.middle)
            }

            PhotosPicker("Choose Photo", selection: $selectedItem, matching: .images)
                .buttonStyle(.borderedProminent)
                .onChange(of: selectedItem) { _, newItem in
                    vm.handleSelection(newItem)
                }

            Text(vm.status)
                .foregroundColor(.gray)
                .padding(.top, 8)
        }
        .padding()
    }
}

#Preview {
    ContentView()
}

