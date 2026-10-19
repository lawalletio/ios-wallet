import AVFoundation
import LaWalletKit
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

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
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
                VStack(spacing: 12) {
                    ProgressView().controlSize(.large).tint(.white)
                    Text(t("scan.readingCode")).font(LW.font(14)).foregroundStyle(LW.muted)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black.opacity(0.7))
                .accessibilityIdentifier("scan.resolving")
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task { await requestCamera() }
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
            Text(t("scan.title")).font(LW.font(16, .medium)).foregroundStyle(.white)
            HStack {
                Button { if !app.path.isEmpty { app.path.removeLast() } } label: {
                    Icon("x").foregroundStyle(.white).frame(width: 40, height: 40).background(.black.opacity(0.35)).clipShape(Circle())
                }
                .accessibilityLabel(t("common.close"))
                .accessibilityIdentifier("scan.close")
                Spacer()
                if camera == .granted && QRScannerView.hasTorch {
                    Button { torch.toggle() } label: {
                        Icon("flashlight").foregroundStyle(torch ? .black : .white).frame(width: 40, height: 40)
                            .background(torch ? Color.white : Color.black.opacity(0.35)).clipShape(Circle())
                    }
                    .accessibilityLabel(t("ios.pay.torch"))
                    .accessibilityIdentifier("scan.torch")
                }
            }
        }
        .padding(.horizontal, 12).frame(height: 56)
    }

    private var viewfinder: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height) * 0.7
            let hole = CGRect(x: (geo.size.width - side) / 2, y: (geo.size.height - side) / 2 - 40, width: side, height: side)
            ZStack {
                Path { p in
                    p.addRect(CGRect(origin: .zero, size: geo.size))
                    p.addRoundedRect(in: hole, cornerSize: CGSize(width: 24, height: 24))
                }
                .fill(Color.black.opacity(0.45), style: FillStyle(eoFill: true))
                RoundedRectangle(cornerRadius: 24).strokeBorder(Color.white.opacity(0.5), lineWidth: 2)
                    .frame(width: side, height: side).position(x: hole.midX, y: hole.midY)
                Text(t("scan.hint")).font(LW.font(14)).foregroundStyle(.white.opacity(0.8)).multilineTextAlignment(.center)
                    .frame(width: side + 40).position(x: hole.midX, y: hole.maxY + 36)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private var footer: some View {
        VStack(spacing: 8) {
            if NFCReader.isAvailable {
                Button { Task { await readCard() } } label: {
                    Label { Text(t("ios.nfc.claimCard")) } icon: { Icon("nfc", size: 16) }
                }
                .buttonStyle(.lw(.secondary))
                .accessibilityIdentifier("scan.nfc")
            }
            // PasteButton reads the clipboard without the iOS "Allow Paste" prompt.
            PasteButton(payloadType: String.self) { strings in
                guard let text = strings.first?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return }
                Task { @MainActor in await handle(text, force: true) }
            }
            .labelStyle(.titleAndIcon)
            .buttonBorderShape(.roundedRectangle(radius: 12))
            .tint(LW.secondary)
            .frame(maxWidth: .infinity)
            .accessibilityIdentifier("scan.paste")
        }
        .disabled(resolving)
        .padding(.horizontal, 16).padding(.bottom, 16)
    }

    private func status(_ icon: String, _ title: String, detail: String? = nil) -> some View {
        VStack(spacing: 12) {
            Icon(icon, size: 40).foregroundStyle(LW.muted)
            Text(title).font(LW.font(16, .semibold)).foregroundStyle(.white)
            if let detail { Text(detail).font(LW.font(14)).foregroundStyle(LW.muted).multilineTextAlignment(.center) }
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
