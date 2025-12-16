//
//  QRCodeScannerViewController.swift
//  WinDropBridge
//
//  Created by Davide Castaldi on 15/12/25.
//


import UIKit
import SwiftUI
import AVFoundation

final class QRCodeScannerViewController: UIViewController {

    private let captureSession = AVCaptureSession()
    private let captureQueue = DispatchQueue(label: "windrop.capture.queue")

    private var previewLayer: AVCaptureVideoPreviewLayer?

    /// Called once when a QR code is successfully scanned
    var onQRCodeScanned: ((String) -> Void)?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        checkCameraPermissionAndSetup()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        stopSession()
    }

    // MARK: - Permissions

    private func checkCameraPermissionAndSetup() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            setupCamera()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                guard granted else {
                    DispatchQueue.main.async {
                        self?.dismiss(animated: true)
                    }
                    return
                }
                self?.setupCamera()
            }
        default:
            dismiss(animated: true)
        }
    }

    // MARK: - Camera Setup

    private func setupCamera() {
        captureQueue.async { [weak self] in
            guard let self else { return }

            self.captureSession.beginConfiguration()

            guard
                let device = AVCaptureDevice.default(for: .video),
                let input = try? AVCaptureDeviceInput(device: device),
                self.captureSession.canAddInput(input)
            else {
                self.captureSession.commitConfiguration()
                return
            }

            self.captureSession.addInput(input)

            let output = AVCaptureMetadataOutput()
            guard self.captureSession.canAddOutput(output) else {
                self.captureSession.commitConfiguration()
                return
            }

            self.captureSession.addOutput(output)

            self.captureSession.commitConfiguration()

            DispatchQueue.main.async {
                output.setMetadataObjectsDelegate(self, queue: .main)
                output.metadataObjectTypes = [.qr]
                let preview = AVCaptureVideoPreviewLayer(session: self.captureSession)
                preview.videoGravity = .resizeAspectFill
                preview.frame = self.view.layer.bounds
                self.view.layer.addSublayer(preview)
                self.previewLayer = preview
            }

            self.captureSession.startRunning()
        }
    }

    private func stopSession() {
        captureQueue.async { [weak self] in
            guard let self, self.captureSession.isRunning else { return }
            self.captureSession.stopRunning()
        }
    }
}

// MARK: - QR Delegate

extension QRCodeScannerViewController: AVCaptureMetadataOutputObjectsDelegate {

    func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        guard
            let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
            let value = object.stringValue
        else { return }

        stopSession()
        dismiss(animated: true)

        onQRCodeScanned?(value)
    }
}




struct QRCodeScannerSheet: UIViewControllerRepresentable {

    let onScanned: (String) -> Void

    func makeUIViewController(context: Context) -> QRCodeScannerViewController {
        let vc = QRCodeScannerViewController()
        vc.onQRCodeScanned = onScanned
        return vc
    }

    func updateUIViewController(
        _ uiViewController: QRCodeScannerViewController,
        context: Context
    ) {}
}
