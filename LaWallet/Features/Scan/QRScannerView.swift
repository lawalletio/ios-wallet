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

    /// Whether a camera exists (false on the simulator).
    static var hasCamera: Bool { AVCaptureDevice.default(for: .video) != nil }

    static var hasTorch: Bool { AVCaptureDevice.default(for: .video)?.hasTorch ?? false }
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
        guard let device = AVCaptureDevice.default(for: .video), let input = try? AVCaptureDeviceInput(device: device),
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
        guard let device = AVCaptureDevice.default(for: .video), device.hasTorch, (device.torchMode == .on) != on,
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
