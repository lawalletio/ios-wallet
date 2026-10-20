import AVFoundation
import LaWalletKit
import PhotosUI
import SwiftUI

/// `/wallet/scan` — scan/scan-screen.tsx. Dispatch lives in `ScanRouter`; this screen owns the camera, paste and NFC inputs.
struct ScanScreen: View {
    enum Camera: Equatable { case requesting, granted, denied, unavailable }

    @Environment(AppModel.self) private var app
    @State private var camera: Camera = .requesting
    @State private var torch = false
    @State private var resolving = false
    @State private var foreign: URL?
    @State private var lastCode: (text: String, at: Date)?
    @State private var photo: PhotosPickerItem?

    var body: some View {
        // No backdrop of its own: the route's ambient light runs at 0 here (plain ink), the camera fills the screen.
        ZStack {
            if camera == .granted {
                QRScannerView(paused: resolving || foreign != nil, torch: torch) { text in Task { await handle(text) } }
                    .ignoresSafeArea()
                viewfinder
            }
            VStack(spacing: 0) {
                header
                Spacer()
                switch camera {
                case .requesting: status("camera", t("scan.requestingCamera"))
                case .denied: denied
                case .unavailable: status("camera", t("scan.cameraUnavailable"), detail: t("ios.pay.noCamera"))
                case .granted: EmptyView()
                }
                Spacer()
                footer
            }
            if resolving {
                VStack(spacing: 14) {
                    ProgressView().controlSize(.large).tint(.white)
                    Text(t("scan.readingCode")).font(LW.font(15, .medium)).foregroundStyle(LW.foreground.opacity(0.85))
                }
                .padding(.horizontal, 32).padding(.vertical, 26)
                .lwSurface()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black.opacity(0.55))
                .accessibilityIdentifier("scan.resolving")
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task { await requestCamera() }
        .onChange(of: photo) { _, item in Task { await scanPhoto(item) } }
        .onDisappear { torch = false }
        .alert(t("scan.differentCommunity"), isPresented: Binding(get: { foreign != nil }, set: { if !$0 { foreign = nil } }), presenting: foreign) { url in
            Button(t("scan.openLink")) { UIApplication.shared.open(url); foreign = nil }
            Button(t("scan.scanAnother"), role: .cancel) { foreign = nil }
        } message: { url in
            Text(t("scan.foreignCard", ["cardHost": url.host() ?? url.absoluteString, "here": app.endpoint.host() ?? ""]))
        }
    }

    // MARK: chrome

    private var header: some View {
        ZStack {
            Text(t("scan.title")).font(LW.font(17, .semibold)).foregroundStyle(.white).shadow(color: .black.opacity(0.4), radius: 8)
            HStack {
                GlassIconButton(icon: "x", label: t("common.close")) { if !app.path.isEmpty { app.path.removeLast() } }
                    .accessibilityIdentifier("scan.close")
                Spacer()
                if camera == .granted && QRScannerView.hasTorch {
                    // GlassIconButton with an on state: frosted light glass + ink icon while the torch is lit.
                    Button { torch.toggle() } label: {
                        Icon("flashlight", size: 18).foregroundStyle(torch ? LW.ink : LW.foreground)
                            .frame(width: 44, height: 44).contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .lwGlass(in: Circle(), tint: torch ? .light : .none, interactive: true)
                    .accessibilityLabel(t("ios.pay.torch"))
                    .accessibilityAddTraits(torch ? .isSelected : [])
                    .accessibilityIdentifier("scan.torch")
                }
            }
        }
        .padding(.horizontal, 16).frame(height: 60)
    }

    private var viewfinder: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height) * 0.7
            let hole = CGRect(x: (geo.size.width - side) / 2, y: (geo.size.height - side) / 2 - 40, width: side, height: side)
            ZStack {
                Path { p in
                    p.addRect(CGRect(origin: .zero, size: geo.size))
                    p.addRoundedRect(in: hole, cornerSize: CGSize(width: 28, height: 28), style: .circular)
                }
                .fill(Color.black.opacity(0.45), style: FillStyle(eoFill: true))
                ViewfinderCorners(radius: 28)
                    .stroke(Color.white, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                    .frame(width: side, height: side).position(x: hole.midX, y: hole.midY)
                    .shadow(color: .black.opacity(0.25), radius: 6)
                Text(t("scan.hint")).font(LW.font(15, .medium)).foregroundStyle(.white.opacity(0.85)).multilineTextAlignment(.center)
                    .frame(width: side + 40).position(x: hole.midX, y: hole.maxY + 38)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private var footer: some View {
        GlassGroup(spacing: 10) {
            VStack(spacing: 10) {
                if NFCReader.isAvailable {
                    Button { Task { await readCard() } } label: {
                        Label { Text(t("ios.nfc.claimCard")) } icon: { Icon("nfc", size: 16) }
                    }
                    .buttonStyle(.lw(.secondary))
                    .accessibilityIdentifier("scan.nfc")
                }
                // Works with no camera at all (simulator) and for QR screenshots on a phone.
                PhotosPicker(selection: $photo, matching: .images) {
                    Label { Text(t("ios.pay.scanPhoto")) } icon: { Icon("image", size: 16) }
                }
                .buttonStyle(.lw(camera == .granted ? .secondary : .theme))
                .accessibilityIdentifier("scan.photo")
                // PasteButton reads the clipboard without the iOS "Allow Paste" prompt.
                PasteButton(payloadType: String.self) { strings in
                    guard let text = strings.first?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return }
                    Task { @MainActor in await handle(text, force: true) }
                }
                .labelStyle(.titleAndIcon)
                .buttonBorderShape(.capsule)
                .controlSize(.large)
                .lwSystemGlass()
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("scan.paste")
            }
        }
        .disabled(resolving)
        .padding(.horizontal, 20).padding(.top, 10).padding(.bottom, 10)
    }

    private func status(_ icon: String, _ title: String, detail: String? = nil) -> some View {
        VStack(spacing: 14) {
            Icon(icon, size: 30).foregroundStyle(LW.muted).frame(width: 72, height: 72).lwGlass(in: Circle())
            Text(title).font(LW.font(18, .semibold)).foregroundStyle(.white)
            if let detail { Text(detail).font(LW.font(15)).foregroundStyle(LW.muted).multilineTextAlignment(.center) }
        }
        .padding(.horizontal, 32)
        .accessibilityIdentifier("scan.status")
    }

    private var denied: some View {
        VStack(spacing: 16) {
            status("alert-circle", t("scan.cameraUnavailable"), detail: t("ios.scan.permission"))
            Button(t("ios.scan.openSettings")) {
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            }
            .buttonStyle(.lw(.secondary, fullWidth: false))
            .accessibilityIdentifier("scan.openSettings")
        }
    }

    // MARK: inputs

    private func requestCamera() async {
        guard QRScannerView.hasCamera else { camera = .unavailable; return }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: camera = .granted
        case .notDetermined: camera = await AVCaptureDevice.requestAccess(for: .video) ? .granted : .denied
        default: camera = .denied
        }
    }

    private func scanPhoto(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        defer { photo = nil }
        guard let data = try? await item.loadTransferable(type: Data.self),
              let text = await Task.detached(priority: .userInitiated, operation: { QRImageDecoder.decode(data) }).value else {
            return app.show(.error, t("ios.pay.noQrInPhoto"))
        }
        await handle(text, force: true)
    }

    private func readCard() async {
        do {
            let url = try await NFCReader.readURL(prompt: t("ios.nfc.prompt"))
            await handle(url, force: true)
        } catch is CancellationError {
        } catch {
            app.show(.error, PayErrors.text(error, fallback: t("errors.nfc.readError")))
        }
    }

    /// Pause, route, and resume on anything unrecognized. The same unrecognized code is ignored for 2.5 s so a QR held
    /// in frame doesn't spam toasts.
    private func handle(_ raw: String, force: Bool = false) async {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !resolving, foreign == nil else { return }
        if !force, let last = lastCode, last.text == text, Date().timeIntervalSince(last.at) < 2.5 { return }
        lastCode = (text, Date())
        resolving = true
        Haptics.tap()
        let outcome = await ScanRouter.route(text, app: app, replacingScan: true)
        resolving = false
        switch outcome {
        case .handled:
            torch = false
        case .foreignActivation(let url):
            foreign = url
        case .unsupported(let message):
            Haptics.error()
            app.show(.error, message)
        }
    }
}

/// Four rounded corner brackets around the scan hole (stroke centered on the hole's edge).
private struct ViewfinderCorners: Shape {
    var radius: CGFloat = 28
    var length: CGFloat = 46

    func path(in r: CGRect) -> Path {
        var p = Path()
        // (start, corner, end) per corner, clockwise from top-left.
        let corners: [(CGPoint, CGPoint, CGPoint)] = [
            (CGPoint(x: r.minX, y: r.minY + length), CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.minX + length, y: r.minY)),
            (CGPoint(x: r.maxX - length, y: r.minY), CGPoint(x: r.maxX, y: r.minY), CGPoint(x: r.maxX, y: r.minY + length)),
            (CGPoint(x: r.maxX, y: r.maxY - length), CGPoint(x: r.maxX, y: r.maxY), CGPoint(x: r.maxX - length, y: r.maxY)),
            (CGPoint(x: r.minX + length, y: r.maxY), CGPoint(x: r.minX, y: r.maxY), CGPoint(x: r.minX, y: r.maxY - length))
        ]
        for (start, corner, end) in corners {
            p.move(to: start)
            p.addArc(tangent1End: corner, tangent2End: end, radius: radius)
            p.addLine(to: end)
        }
        return p
    }
}
