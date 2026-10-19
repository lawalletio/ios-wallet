@preconcurrency import AVFoundation
import SwiftUI

/// Rear-camera QR reader (`AVCaptureMetadataOutput`, `.qr`). Calls `onCode` on the main actor for every decoded payload
/// while not `paused`; the caller decides what to do with repeats.
struct QRScannerView: UIViewControllerRepresentable {
    var paused: Bool
    var torch: Bool
    let onCode: (String) -> Void

    func makeUIViewController(context: Context) -> QRScannerController {
        let c = QRScannerController()
        c.onCode = onCode
        return c
    }

    func updateUIViewController(_ c: QRScannerController, context: Context) {
        c.onCode = onCode
        c.paused = paused
        c.setTorch(torch)
    }

    static func dismantleUIViewController(_ c: QRScannerController, coordinator: ()) { c.stop() }

    /// Back wide-angle camera, else any video device (front, external). Nil on the iOS Simulator, which has no camera.
    static var device: AVCaptureDevice? {
        AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
            ?? AVCaptureDevice.default(for: .video)
            ?? AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera, .external], mediaType: .video,
                                                position: .unspecified).devices.first
    }

    static var hasCamera: Bool { device != nil }

    static var hasTorch: Bool { device?.hasTorch ?? false }
}

/// Decodes the first QR code in a still image (photo library, screenshot). Works without a camera.
enum QRImageDecoder {
    static func decode(_ data: Data) -> String? {
        guard let image = CIImage(data: data, options: [.applyOrientationProperty: true]) else { return nil }
        return decode(image)
    }

    static func decode(_ image: CIImage) -> String? {
        let detector = CIDetector(ofType: CIDetectorTypeQRCode, context: nil, options: [CIDetectorAccuracy: CIDetectorAccuracyHigh])
        return detector?.features(in: image).compactMap { ($0 as? CIQRCodeFeature)?.messageString }.first { !$0.isEmpty }
    }
}

final class QRScannerController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onCode: ((String) -> Void)?
    var paused = false
    private let capture = CaptureSession()
    private var preview: AVCaptureVideoPreviewLayer?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        let session = capture.session
        guard let device = QRScannerView.device, let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else { return }
        session.addInput(input)
        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else { return }
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: .main)
        output.metadataObjectTypes = output.availableMetadataObjectTypes.contains(.qr) ? [.qr] : []
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(layer)
        preview = layer
        capture.start()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        preview?.frame = view.bounds
    }

    func stop() { capture.stop() }

    func setTorch(_ on: Bool) {
        guard let device = QRScannerView.device, device.hasTorch, (device.torchMode == .on) != on,
              (try? device.lockForConfiguration()) != nil else { return }
        device.torchMode = on ? .on : .off
        device.unlockForConfiguration()
    }

    nonisolated func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput objects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard let text = (objects.first as? AVMetadataMachineReadableCodeObject)?.stringValue, !text.isEmpty else { return }
        MainActor.assumeIsolated {
            guard !paused else { return }
            onCode?(text)
        }
    }
}

/// `startRunning` blocks, so it runs off the main thread.
private final class CaptureSession: @unchecked Sendable {
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "io.lawallet.scan")
    func start() { queue.async { if !self.session.isRunning { self.session.startRunning() } } }
    func stop() { queue.async { if self.session.isRunning { self.session.stopRunning() } } }
}
