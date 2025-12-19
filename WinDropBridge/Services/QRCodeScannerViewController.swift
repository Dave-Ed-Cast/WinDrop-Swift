//
//  QRCodeScannerViewController.swift
//  WinDropBridge
//
//  Created by Davide Castaldi on 15/12/25.
//


import UIKit
import SwiftUI
import AVFoundation

@MainActor
final class QRCodeScannerViewController: UIViewController {

    private let capture = CaptureController()
    private var previewLayer: AVCaptureVideoPreviewLayer?

    var onQRCodeScanned: ((String) -> Void)?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        checkCameraPermissionAndSetup()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        capture.stop()
    }

    private func checkCameraPermissionAndSetup() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            setupCamera()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                guard granted else {
                    Task { @MainActor in self?.dismiss(animated: true) }
                    return
                }
                Task { @MainActor in self?.setupCamera() }
            }
        default:
            dismiss(animated: true)
        }
    }

    private func setupCamera() {
        let preview = AVCaptureVideoPreviewLayer(session: capture.session)
        preview.videoGravity = .resizeAspectFill
        preview.frame = view.bounds
        view.layer.addSublayer(preview)
        previewLayer = preview

        capture.start(delegate: self)
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

        capture.stop()
        dismiss(animated: true)
        onQRCodeScanned?(value)
    }
}

struct QRCodeScannerSheet: UIViewControllerRepresentable {

    let onScanned: (String) -> Void

    func makeUIViewController(context: Context) -> QRCodeScannerViewController {
        let qrvc = QRCodeScannerViewController()
        qrvc.onQRCodeScanned = onScanned
        return qrvc
    }

    func updateUIViewController(
        _ uiViewController: QRCodeScannerViewController,
        context: Context
    ) {}
}
