import CoreImage.CIFilterBuiltins
import SwiftUI
import UniformTypeIdentifiers

/// Lucide icon from the asset catalog (`lucide-<name>`), template-tinted.
struct Icon: View {
    let name: String
    var size: CGFloat = 20
    init(_ name: String, size: CGFloat = 20) { self.name = name; self.size = size }
    var body: some View {
        Image("lucide-\(name)").resizable().renderingMode(.template).scaledToFit().frame(width: size, height: size)
    }
}

// MARK: buttons
//
// Same kinds as components/ui/button.tsx, expressed as Liquid Glass:
// primary = frosted light glass (dark label), theme = brand-tinted glass, secondary = clear glass,
// outline = clear glass with a rim, destructive = coral glass, ghost = text only.

enum LWButtonKind { case primary, theme, secondary, outline, destructive, ghost }

struct LWButtonStyle: ButtonStyle {
    var kind: LWButtonKind = .primary
    var height: CGFloat = 52
    var fullWidth = true
    @Environment(\.theme) private var theme
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let shape = Capsule()
        let label = configuration.label
            .font(LW.font(16, .semibold))
            .lineLimit(1)
            .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: height)
            .padding(.horizontal, 20)
            .foregroundStyle(foreground)
            .tint(foreground)  // spinners inside labels match the text on every variant
            .contentShape(shape)
        // Glass ignores `.opacity`, so a disabled button drops its tint and dims its label instead.
        Group {
            switch kind {
            case .ghost: label
            case .outline: label.lwGlass(in: shape, interactive: isEnabled, clear: true).overlay(shape.strokeBorder(LW.border))
            default: label.lwGlass(in: shape, tint: isEnabled ? tint : .none, interactive: isEnabled)
            }
        }
        .scaleEffect(configuration.isPressed ? 0.97 : 1)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }

    private var tint: GlassTint {
        switch kind {
        case .primary: .light
        case .theme: .color(theme.preset.t400.opacity(0.85))
        case .destructive: .color(LW.coral.opacity(0.75))
        default: .none
        }
    }

    private var foreground: Color {
        guard isEnabled else { return LW.foreground.opacity(0.35) }
        switch kind {
        case .primary: return LW.ink
        case .ghost: return LW.muted
        default: return LW.foreground
        }
    }
}

extension ButtonStyle where Self == LWButtonStyle {
    static func lw(_ kind: LWButtonKind = .primary, height: CGFloat = 52, fullWidth: Bool = true) -> LWButtonStyle {
        LWButtonStyle(kind: kind, height: height, fullWidth: fullWidth)
    }
}

/// Round glass icon button (header back/close, trailing actions).
struct GlassIconButton: View {
    let icon: String
    var size: CGFloat = 44
    var label: String?
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Icon(icon, size: size * 0.42).foregroundStyle(LW.foreground).frame(width: size, height: size).contentShape(Circle())
        }
        .buttonStyle(.plain)
        .lwGlass(in: Circle(), interactive: true)
        .accessibilityLabel(label ?? "")
    }
}

// MARK: header

struct ScreenHeader<Trailing: View>: View {
    var title: String?
    var close = false
    var onBack: (() -> Void)?
    @ViewBuilder var trailing: () -> Trailing
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            if let title { Text(title).font(LW.font(17, .semibold)).foregroundStyle(LW.foreground).lineLimit(1).padding(.horizontal, 64) }
            HStack {
                GlassIconButton(icon: close ? "x" : "chevron-left", label: t("shared.goBack")) { onBack.map { $0() } ?? dismiss() }
                    .accessibilityIdentifier("header.back")
                Spacer()
                trailing().frame(minWidth: 44, alignment: .trailing)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 60)
    }
}

extension ScreenHeader where Trailing == EmptyView {
    init(title: String?, close: Bool = false, onBack: (() -> Void)? = nil) {
        self.init(title: title, close: close, onBack: onBack, trailing: { EmptyView() })
    }
}

/// Settings-style header: glass back button, large left-aligned title underneath (iOS large-title rhythm).
struct PillHeader: View {
    let title: String
    var onBack: (() -> Void)?
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button { onBack.map { $0() } ?? dismiss() } label: {
                HStack(spacing: 4) { Icon("chevron-left", size: 17); Text(t("common.back")).font(LW.font(15, .medium)) }
                    .padding(.leading, 10).padding(.trailing, 14).frame(height: 40).contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .foregroundStyle(LW.foreground)
            .lwGlass(in: Capsule(), interactive: true)
            .accessibilityIdentifier("header.back")
            Text(title).font(LW.font(32, .bold)).tracking(-0.6).foregroundStyle(LW.foreground)
                .accessibilityAddTraits(.isHeader)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 4)
    }
}

// MARK: lists

struct GroupBox<Content: View>: View {
    var label: String?
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let label { Text(label).font(LW.font(14, .semibold)).foregroundStyle(LW.muted).padding(.leading, 6) }
            VStack(spacing: 0) { content() }
                .lwSurface(LW.Radius.surface - 4)
        }
    }
}

struct RowDivider: View {
    var body: some View { Rectangle().fill(Color.white.opacity(0.08)).frame(height: 0.5).padding(.leading, 18) }
}

// MARK: nav tabbar
//
// A glass capsule with Home/Settings and a brand-tinted scan button floating above it. The two are deliberately NOT in
// one GlassEffectContainer: there the shapes blend and the button reads as part of (behind) the bar.

struct NavTabbar: View {
    enum Tab { case home, settings }
    let active: Tab
    let onHome: () -> Void
    let onScan: () -> Void
    let onSettings: () -> Void
    @Environment(\.theme) private var theme

    var body: some View {
        ZStack {
            HStack(spacing: 0) {
                side("home", .home, onHome, label: t("shared.nav.home"))
                Spacer(minLength: 104)
                side("settings", .settings, onSettings, label: t("shared.nav.settings"))
            }
            .padding(.horizontal, 14)
            .frame(width: 292, height: 66)
            .lwGlass(in: Capsule())

            Button(action: onScan) {
                Icon("scan-qr-code", size: 32).foregroundStyle(.white).frame(width: 80, height: 80).contentShape(Circle())
            }
            .buttonStyle(.plain)
            .lwGlass(in: Circle(), tint: .color(theme.preset.t400.opacity(0.95)), interactive: true)
            .overlay(Circle().strokeBorder(Color.white.opacity(0.22), lineWidth: 1))
            .shadow(color: .black.opacity(0.45), radius: 14, y: 8)
            .shadow(color: theme.preset.primary.opacity(0.35), radius: 24, y: 6)
            .offset(y: -20)
            .zIndex(1)
            .accessibilityLabel(t("shared.nav.scan"))
            .accessibilityIdentifier("nav.scan")
        }
        .padding(.top, 40).padding(.bottom, 4)
        .frame(maxWidth: .infinity)
        .background(alignment: .bottom) {
            // Scrim so rows scrolling underneath don't compete with the bar.
            LinearGradient(stops: [.init(color: LW.ink.opacity(0), location: 0), .init(color: LW.ink.opacity(0.7), location: 0.55),
                                   .init(color: LW.ink.opacity(0.85), location: 1)], startPoint: .top, endPoint: .bottom)
                .frame(height: 230).padding(.bottom, -60).allowsHitTesting(false)
        }
    }

    private func side(_ icon: String, _ tab: Tab, _ action: @escaping () -> Void, label: String) -> some View {
        Button(action: action) {
            Icon(icon, size: 25).foregroundStyle(active == tab ? LW.foreground : LW.muted)
                .frame(width: 64, height: 56).contentShape(Rectangle())
        }
        .buttonStyle(PressScale())
        .accessibilityLabel(label)
        .accessibilityAddTraits(active == tab ? .isSelected : [])
        .accessibilityIdentifier("nav.\(icon)")
    }
}

struct PressScale: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.scaleEffect(configuration.isPressed ? 0.96 : 1).animation(.spring(response: 0.22, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: currency pills (glass segmented, sliding selection)

struct CurrencyToggle: View {
    let codes: [String]
    @Binding var selected: String
    var body: some View {
        if codes.count > 1 {
            GlassSegmented(items: codes.map { ($0, $0 == "SAT" ? "sats" : $0) }, selection: $selected, idPrefix: "currency")
        }
    }
}

// MARK: amount display

struct AmountDisplay: View {
    let value: String
    var unit = "sats"
    var subline: String?
    var body: some View {
        VStack(spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(Self.format(value)).font(LW.font(64, .semibold)).tracking(-2).monospacedDigit().foregroundStyle(LW.foreground)
                    .lineLimit(1).minimumScaleFactor(0.35)
                    .contentTransition(.numericText())
                    .animation(.spring(response: 0.3, dampingFraction: 0.8), value: value)
                Text(unit).font(LW.font(20, .medium)).foregroundStyle(LW.muted)
            }
            if let subline { Text(subline).font(LW.font(15)).foregroundStyle(LW.muted).contentTransition(.numericText()) }
        }
        .padding(.vertical, 28)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("amount.display")
    }

    static func format(_ raw: String) -> String {
        guard !raw.isEmpty else { return "0" }
        let parts = raw.split(separator: ".", omittingEmptySubsequences: false)
        let int = String(parts[0].isEmpty ? "0" : parts[0])
        var grouped = ""
        for (i, c) in int.reversed().enumerated() {
            if i > 0, i % 3 == 0 { grouped.insert(",", at: grouped.startIndex) }
            grouped.insert(c, at: grouped.startIndex)
        }
        return raw.contains(".") ? grouped + "." + (parts.count > 1 ? parts[1] : "") : grouped
    }
}

// MARK: keypad (glass keys)

struct AmountKeypad: View {
    @Binding var value: String
    /// Max fraction digits (0 = integer sats, 2 = fiat, 8 = BTC).
    var decimals = 0
    var maxLength = 12

    var body: some View {
        let keys = ["1", "2", "3", "4", "5", "6", "7", "8", "9", decimals > 0 ? "." : "", "0", "⌫"]
        GlassGroup(spacing: 10) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                ForEach(keys.indices, id: \.self) { i in
                    let k = keys[i]
                    if k.isEmpty { Color.clear.frame(height: 60) } else {
                        Button { press(k) } label: {
                            Group { if k == "⌫" { Icon("delete", size: 24) } else { Text(k).font(LW.font(28, .medium)) } }
                                .frame(maxWidth: .infinity, minHeight: 60)
                                .foregroundStyle(LW.foreground)
                                .contentShape(RoundedRectangle(cornerRadius: LW.Radius.control, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .lwGlass(in: RoundedRectangle(cornerRadius: LW.Radius.control, style: .continuous), interactive: true)
                        .accessibilityLabel(k == "⌫" ? t("shared.keypad.deleteLast") : k)
                        .accessibilityIdentifier(k == "⌫" ? "key.delete" : "key.\(k)")
                    }
                }
            }
        }
    }

    func press(_ k: String) {
        let next = Self.apply(k, to: value, decimals: decimals, maxLength: maxLength)
        if next != value { Haptics.select() }
        value = next
    }

    static func apply(_ k: String, to value: String, decimals: Int, maxLength: Int) -> String {
        if k == "⌫" { return String(value.dropLast()) }
        if k == "." { return decimals == 0 || value.contains(".") ? value : (value.isEmpty ? "0." : value + ".") }
        if let dot = value.firstIndex(of: "."), value[value.index(after: dot)...].count >= decimals { return value }
        if value.filter(\.isNumber).count >= maxLength { return value }
        if value == "0" { return k }
        return value + k
    }
}

// MARK: transaction row (lives inside a glass surface — no glass of its own)

/// Transactions in one surface, hairline-separated; a tap opens the receipt. Lazy, for long histories.
struct TransactionList: View {
    let items: [TxItem]
    var rowID = "tx.row"
    @Environment(AppModel.self) private var app

    var body: some View {
        LazyVStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { i, tx in
                if i > 0 { RowDivider().padding(.leading, 56) }
                Button { app.navigate(.activityDetail(tx)) } label: { TransactionRowView(tx: tx) }
                    .buttonStyle(PressScale())
                    .accessibilityIdentifier(rowID)
            }
        }
        .padding(.vertical, 4)
        .lwSurface()
    }
}

struct TransactionRowView: View {
    let tx: TxItem
    var body: some View {
        let color = tx.incoming ? LW.incoming : LW.outgoing
        HStack(spacing: 14) {
            Icon(tx.incoming ? "arrow-down-left" : "arrow-up-right", size: 17)
                .foregroundStyle(color)
                .frame(width: 42, height: 42)
                .background(color.opacity(0.14), in: Circle())
                .overlay(Circle().strokeBorder(color.opacity(0.22), lineWidth: 0.5))
            VStack(alignment: .leading, spacing: 3) {
                Text(tx.title).font(LW.font(15, .medium)).foregroundStyle(LW.foreground).lineLimit(1)
                Text(RelativeTime.format(tx.date)).font(LW.font(13)).foregroundStyle(LW.muted)
            }
            Spacer(minLength: 8)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text((tx.incoming ? "+" : "−") + tx.amountSats.formatted()).font(LW.font(16, .semibold)).monospacedDigit()
                    .foregroundStyle(tx.incoming ? LW.incoming : LW.foreground)
                Text("sats").font(LW.font(12)).foregroundStyle(LW.muted)
            }
            if tx.pending { ProgressView().controlSize(.mini).tint(LW.sun) }
        }
        .padding(.horizontal, 16).padding(.vertical, 13)
        .contentShape(Rectangle())
    }
}

enum RelativeTime {
    static func format(_ date: Date, now: Date = Date()) -> String {
        let diff = now.timeIntervalSince(date)
        if diff < 60 { return t("shared.tx.justNow") }
        let m = Int((diff / 60).rounded())
        if m < 60 { return t("shared.tx.minutesAgo", ["minutes": "\(m)", "n": "\(m)", "count": "\(m)"]) }
        let h = Int((Double(m) / 60).rounded())
        if h < 24 { return t("shared.tx.hoursAgo", ["hours": "\(h)", "n": "\(h)", "count": "\(h)"]) }
        let d = Int((Double(h) / 24).rounded())
        if d < 7 { return t("shared.tx.daysAgo", ["days": "\(d)", "n": "\(d)", "count": "\(d)"]) }
        return date.formatted(date: .numeric, time: .omitted)
    }
}

// MARK: Status

/// Button label that swaps in a spinner (and optionally different copy) while work is in flight.
struct BusyLabel: View {
    let title: String
    var busy: Bool
    var busyTitle: String?
    var icon: String?

    init(_ title: String, busy: Bool, busyTitle: String? = nil, icon: String? = nil) {
        self.title = title
        self.busy = busy
        self.busyTitle = busyTitle
        self.icon = icon
    }

    var body: some View {
        HStack(spacing: 8) {
            if busy { ProgressView().controlSize(.small) }
            Text(busy ? busyTitle ?? title : title)
            if !busy, let icon { Icon(icon, size: 16) }
        }
    }
}

/// Glass capsule for a live status line ("Waiting for payment · 9:59", "Payment detected").
struct StatusPill<Content: View>: View {
    var tint: Color?
    @ViewBuilder var content: () -> Content
    var body: some View {
        HStack(spacing: 8) { content() }
            .font(LW.font(13, .medium))
            .padding(.horizontal, 14).padding(.vertical, 9)
            .lwGlass(in: Capsule(), tint: tint.map { .color($0.opacity(0.16)) } ?? .none)
            .accessibilityElement(children: .combine)
    }
}

// MARK: Copy

/// The one way the app writes to the clipboard. `secret` (keys, connection secrets) keeps the item off Universal
/// Clipboard and expires it after two minutes.
enum Clipboard {
    @MainActor static func copy(_ value: String, secret: Bool = false) {
        if secret {
            UIPasteboard.general.setItems([[UTType.plainText.identifier: value]],
                                          options: [.localOnly: true, .expirationDate: Date().addingTimeInterval(120)])
        } else {
            UIPasteboard.general.string = value
        }
        Haptics.tap()
    }
}

/// Copies `value` and shows `label(true)` (a check) for a moment.
struct CopyButton<Content: View>: View {
    let value: String
    var secret = false
    var onCopy: () -> Void = {}
    @ViewBuilder var label: (_ copied: Bool) -> Content
    @State private var copied = false

    var body: some View {
        Button {
            Clipboard.copy(value, secret: secret)
            copied = true
            onCopy()
        } label: { label(copied) }
        .task(id: copied) {
            guard copied else { return }
            try? await Task.sleep(for: .seconds(1.6))
            copied = false
        }
    }
}

/// "Copy" ⇄ "Copied" label with the matching icon.
struct CopyLabel: View {
    let copied: Bool
    var title = t("common.copy")
    var copiedTitle = t("common.copied")
    var body: some View {
        Label { Text(copied ? copiedTitle : title) } icon: { Icon(copied ? "check" : "copy", size: 16) }
    }
}

// MARK: QR

struct QRCodeImage: View {
    let text: String
    var body: some View {
        if let img = Self.make(text) {
            Image(uiImage: img).interpolation(.none).resizable().scaledToFit()
        } else { Color.white }
    }

    private static let context = CIContext(options: [.cacheIntermediates: false])
    private static let cache = NSCache<NSString, UIImage>()

    /// Rendered once per string: views re-evaluate `body` on every state change, and CoreImage work there hitches pushes.
    static func make(_ text: String) -> UIImage? {
        if let hit = cache.object(forKey: text as NSString) { return hit }
        let f = CIFilter.qrCodeGenerator()
        f.message = Data(text.utf8)
        f.correctionLevel = "M"
        guard let out = f.outputImage?.transformed(by: CGAffineTransform(scaleX: 10, y: 10)),
              let cg = context.createCGImage(out, from: out.extent) else { return nil }
        let image = UIImage(cgImage: cg)
        cache.setObject(image, forKey: text as NSString)
        return image
    }
}

/// White code tile (kept opaque for scanners) set in a glass bezel, with copy/share underneath.
struct QRDisplay: View {
    let value: String
    var caption: String?
    var copyValue: String?
    var body: some View {
        VStack(spacing: 18) {
            QRCodeImage(text: value)
                .frame(width: 232, height: 232)
                .padding(16)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .padding(10)
                .lwSurface(LW.Radius.sheet)
                .accessibilityIdentifier("qr.code")
            if let caption {
                Text(caption).font(LW.font(15, .medium)).foregroundStyle(LW.foreground.opacity(0.85)).lineLimit(1).truncationMode(.middle)
                    .padding(.horizontal, 24)
                    .accessibilityIdentifier("qr.caption")
            }
            GlassGroup(spacing: 10) {
                HStack(spacing: 10) {
                    CopyButton(value: copyValue ?? value) { CopyLabel(copied: $0) }
                    .buttonStyle(.lw(.secondary, height: 46))
                    .accessibilityIdentifier("qr.copy")
                    ShareLink(item: copyValue ?? value) {
                        Icon("share-2", size: 17).foregroundStyle(LW.foreground).frame(width: 46, height: 46).contentShape(Circle())
                    }
                    .lwGlass(in: Circle(), interactive: true)
                }
            }
            .frame(width: 272)
        }
    }
}

// MARK: swipe to confirm

struct SwipeButton: View {
    let label: String
    var loading = false
    let onComplete: () -> Void
    @State private var offset: CGFloat = 0
    @Environment(\.theme) private var theme
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        GeometryReader { geo in
            let knob: CGFloat = 52
            let maxX = geo.size.width - knob - 8
            let progress = maxX > 0 ? offset / maxX : 0
            ZStack(alignment: .leading) {
                Capsule().fill(Color.clear).lwGlass(in: Capsule())
                Capsule().fill(theme.preset.primary.opacity(0.22 + 0.25 * progress)).frame(width: offset + knob + 8)
                Text(loading ? t("send.preview.sending") : label).font(LW.font(16, .semibold)).foregroundStyle(LW.foreground.opacity(0.75 - 0.5 * progress))
                    .frame(maxWidth: .infinity)
                Circle().fill(Color.clear)
                    .frame(width: knob, height: knob)
                    .contentShape(Circle())  // a clear fill isn't hit-testable on its own
                    .lwGlass(in: Circle(), tint: .color(theme.preset.t400.opacity(0.95)))
                    .overlay { if loading { ProgressView().tint(.white) } else { Icon("chevrons-right", size: 22).foregroundStyle(.white) } }
                    .padding(4).offset(x: offset)
                    .gesture(DragGesture()
                        .onChanged { g in if !loading && isEnabled { offset = min(max(0, g.translation.width), maxX) } }
                        .onEnded { _ in
                            if offset > maxX * 0.85 { offset = maxX; Haptics.success(); onComplete() } else { withAnimation(.spring) { offset = 0 } }
                        })
            }
            // The track is a clear glass capsule, so pin the frame: otherwise the control's (and its accessibility)
            // bounds collapse to the knob + label.
            .frame(width: geo.size.width, height: geo.size.height)
            .contentShape(Capsule())
            .accessibilityElement(children: .combine)
            .accessibilityLabel(label)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { if !loading { onComplete() } }
            .accessibilityIdentifier("swipe.confirm")
        }
        .frame(height: 60)
        .opacity(isEnabled ? 1 : 0.5)
        .onChange(of: loading) { _, l in if !l { withAnimation(.spring) { offset = 0 } } }
    }
}

// MARK: misc

enum Haptics {
    static func tap() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func select() { UISelectionFeedbackGenerator().selectionChanged() }
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func error() { UINotificationFeedbackGenerator().notificationOccurred(.error) }
}

struct ErrorText: View {
    let message: String?
    var body: some View {
        if let message, !message.isEmpty {
            Text(message).font(LW.font(13, .medium)).foregroundStyle(LW.destructiveText).multilineTextAlignment(.center)
                .accessibilityIdentifier("error.text")
        }
    }
}

struct LWTextField: View {
    let placeholder: String
    @Binding var text: String
    var secure = false
    var mono = false
    var body: some View {
        Group {
            if secure {
                SecureField("", text: $text, prompt: Text(verbatim: placeholder).foregroundStyle(LW.muted.opacity(0.8)))
            } else {
                TextField("", text: $text, prompt: Text(verbatim: placeholder).foregroundStyle(LW.muted.opacity(0.8)))
            }
        }
        .font(mono ? .system(size: 15, design: .monospaced) : LW.font(16))
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .padding(.horizontal, 16).frame(minHeight: 54)
        .lwGlass(in: RoundedRectangle(cornerRadius: LW.Radius.control, style: .continuous))
        .foregroundStyle(LW.foreground)
    }
}

struct Toast: Equatable, Identifiable {
    enum Kind { case success, error, info }
    let id = UUID()
    let kind: Kind
    let message: String
}

struct ToastView: View {
    let toast: Toast
    var body: some View {
        HStack(spacing: 10) {
            Icon(toast.kind == .error ? "alert-circle" : toast.kind == .success ? "check-circle-2" : "info", size: 18)
                .foregroundStyle(toast.kind == .error ? LW.destructiveText : toast.kind == .success ? LW.incoming : LW.muted)
            Text(toast.message).font(LW.font(14, .medium)).foregroundStyle(LW.foreground).multilineTextAlignment(.leading)
        }
        .padding(.horizontal, 18).padding(.vertical, 13)
        .lwGlass(in: Capsule())
        .padding(.horizontal, 16)
        .accessibilityIdentifier("toast")
    }
}

/// Remote image with a neutral placeholder (card designs, avatars, community logos). Decoded off the main thread and
/// kept in memory, so a view that remounts (the home logo after a payment notice, list rows) never refetches or flashes.
struct RemoteImage: View {
    let url: URL?
    var contentMode: ContentMode = .fill
    var placeholder: Color = LW.card
    @State private var image: UIImage?

    init(url: URL?, contentMode: ContentMode = .fill, placeholder: Color = LW.card) {
        self.url = url
        self.contentMode = contentMode
        self.placeholder = placeholder
        _image = State(initialValue: url.flatMap(ImageCache.cached))
    }

    var body: some View {
        ZStack {
            if let image { Image(uiImage: image).resizable().aspectRatio(contentMode: contentMode) } else { placeholder }
        }
        .task(id: url) { if image == nil { image = await ImageCache.load(url) } }
    }
}

enum ImageCache {
    /// NSCache is internally synchronized; loads finish on arbitrary executors.
    nonisolated(unsafe) private static let memory: NSCache<NSURL, UIImage> = {
        let c = NSCache<NSURL, UIImage>()
        c.totalCostLimit = 48 << 20
        return c
    }()

    static func cached(_ url: URL) -> UIImage? { memory.object(forKey: url as NSURL) }

    static func load(_ url: URL?) async -> UIImage? {
        guard let url else { return nil }
        if let hit = cached(url) { return hit }
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let image = await UIImage(data: data)?.byPreparingForDisplay() else { return nil }
        memory.setObject(image, forKey: url as NSURL, cost: data.count)
        return image
    }
}
