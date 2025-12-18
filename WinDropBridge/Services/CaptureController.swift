//
//  CaptureController.swift
//  WinDropBridge
//
//  Created by Davide Castaldi on 18/12/25.
//

import Foundation
import AVFoundation
final class CaptureController {
    let session = AVCaptureSession()
    let queue = DispatchQueue(label: "windrop.capture.queue")

    func start(delegate: AVCaptureMetadataOutputObjectsDelegate) {
        queue.async {
            self.session.beginConfiguration()

            guard
                let device = AVCaptureDevice.default(for: .video),
                let input = try? AVCaptureDeviceInput(device: device),
                self.session.canAddInput(input)
            else {
                self.session.commitConfiguration()
                return
            }

            self.session.addInput(input)

            let output = AVCaptureMetadataOutput()
            guard self.session.canAddOutput(output) else {
                self.session.commitConfiguration()
                return
            }

            self.session.addOutput(output)
            self.session.commitConfiguration()

            DispatchQueue.main.async {
                output.setMetadataObjectsDelegate(delegate, queue: .main)
                output.metadataObjectTypes = [.qr]
            }

            self.session.startRunning()
        }
    }

    func stop() {
        queue.async {
            guard self.session.isRunning else { return }
            self.session.stopRunning()
        }
    }
}
