import CoreImage.CIFilterBuiltins
import SwiftUI

/// Lucide icon from the asset catalog (`lucide-<name>`), template-tinted.
struct Icon: View {
    let name: String
    var size: CGFloat = 20
    init(_ name: String, size: CGFloat = 20) { self.name = name; self.size = size }
    var body: some View {
        Image("lucide-\(name)").resizable().renderingMode(.template).scaledToFit().frame(width: size, height: size)
    }
}

// MARK: buttons (components/ui/button.tsx)

enum LWButtonKind { case primary, theme, secondary, outline, destructive, ghost }

struct LWButtonStyle: ButtonStyle {
    var kind: LWButtonKind = .primary
    var height: CGFloat = 48
    var fullWidth = true
    @Environment(\.theme) private var theme
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(LW.font(15, .medium))
            .lineLimit(1)
            .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: height)
            .padding(.horizontal, 16)
            .foregroundStyle(foreground)
            .background(background)
            .overlay(border)
            .clipShape(RoundedRectangle(cornerRadius: theme.radius * 0.75 + 3, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(isEnabled ? (configuration.isPressed ? 0.85 : 1) : 0.45)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }

    private var foreground: Color {
        switch kind {
        case .primary: Color(hex: "0a0a0a")
        case .destructive: Color(hex: "fef2f2")
        default: LW.foreground
        }
    }

    @ViewBuilder private var background: some View {
        switch kind {
        case .primary: LinearGradient(colors: [Color(hex: "a3a3a3"), Color(hex: "f5f5f5")], startPoint: .top, endPoint: .bottom)
        case .theme: theme.preset.gradient
        case .secondary: LW.secondary
        case .outline, .ghost: Color.clear
        case .destructive: LW.destructive
        }
    }

    @ViewBuilder private var border: some View {
        let shape = RoundedRectangle(cornerRadius: theme.radius * 0.75 + 3, style: .continuous)
        switch kind {
        case .primary: shape.strokeBorder(Color(hex: "404040"))
        case .theme: shape.strokeBorder(theme.preset.t300)
        case .outline: shape.strokeBorder(LW.border)
        default: EmptyView()
        }
    }
}

extension ButtonStyle where Self == LWButtonStyle {
    static func lw(_ kind: LWButtonKind = .primary, height: CGFloat = 48, fullWidth: Bool = true) -> LWButtonStyle {
        LWButtonStyle(kind: kind, height: height, fullWidth: fullWidth)
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
            if let title { Text(title).font(LW.font(16, .medium)).foregroundStyle(LW.foreground) }
            HStack {
                Button { onBack.map { $0() } ?? dismiss() } label: {
                    Icon(close ? "x" : "chevron-left").foregroundStyle(LW.muted).frame(width: 40, height: 40).contentShape(Circle())
                }
                .accessibilityLabel(t("shared.goBack"))
                .accessibilityIdentifier("header.back")
                Spacer()
                trailing().frame(minWidth: 40, alignment: .trailing)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 56)
        .background(LW.background.opacity(0.8))
    }
}

extension ScreenHeader where Trailing == EmptyView {
    init(title: String?, close: Bool = false, onBack: (() -> Void)? = nil) {
        self.init(title: title, close: close, onBack: onBack, trailing: { EmptyView() })
    }
}

/// Settings-style header with the pill "← Back" button.
struct PillHeader: View {
    let title: String
    var onBack: (() -> Void)?
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        ZStack {
            Text(title).font(LW.font(17, .semibold))
            HStack {
                Button { onBack.map { $0() } ?? dismiss() } label: {
                    HStack(spacing: 6) { Icon("chevron-left", size: 16); Text(t("common.back")).font(LW.font(15, .medium)) }
                        .padding(.horizontal, 14).frame(height: 36).background(LW.card).clipShape(Capsule())
                }
                .foregroundStyle(LW.foreground)
                .accessibilityIdentifier("header.back")
                Spacer()
            }
        }
        .padding(.horizontal, 16).frame(height: 56)
    }
}

// MARK: lists (settings-screen.tsx grouped rows)

struct GroupBox<Content: View>: View {
    var label: String?
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let label { Text(label).font(LW.font(14, .medium)).foregroundStyle(LW.muted).padding(.leading, 4) }
            VStack(spacing: 0) { content() }
                .background(LW.card)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }
}

struct RowDivider: View {
    var body: some View { Rectangle().fill(LW.border.opacity(0.4)).frame(height: 1).padding(.leading, 16) }
}

struct NavRow<Trailing: View>: View {
    let title: String
    var icon: String?
    var subtitle: String?
    var external = false
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 12) {
            if let icon { Icon(icon, size: 18).foregroundStyle(LW.muted) }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(LW.font(16, .medium)).foregroundStyle(LW.foreground)
                if let subtitle { Text(subtitle).font(LW.font(12)).foregroundStyle(LW.muted).lineLimit(1) }
            }
            Spacer(minLength: 8)
            trailing()
            Icon(external ? "external-link" : "chevron-right", size: 16).foregroundStyle(LW.muted)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 56)
        .contentShape(Rectangle())
    }
}

extension NavRow where Trailing == EmptyView {
    init(title: String, icon: String? = nil, subtitle: String? = nil, external: Bool = false) {
        self.init(title: title, icon: icon, subtitle: subtitle, external: external, trailing: { EmptyView() })
    }
}

// MARK: nav tabbar (shared/nav-tabbar.tsx)

struct NavTabbar: View {
    enum Tab { case home, settings }
    let active: Tab
    let onHome: () -> Void
    let onScan: () -> Void
    let onSettings: () -> Void
    @Environment(\.theme) private var theme

    var body: some View {
        ZStack {
            HStack {
                side("home", .home, onHome, label: t("shared.nav.home"))
                Spacer()
                side("settings", .settings, onSettings, label: t("shared.nav.settings"))
            }
            .padding(.horizontal, 16)
            .frame(width: 286, height: 64)
            .background(.ultraThinMaterial.opacity(0.6))
            .background(LW.card.opacity(0.9))
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(LW.border.opacity(0.6)))
            .shadow(color: .black.opacity(0.5), radius: 24, y: 12)

            Button(action: onScan) {
                Icon("scan-qr-code", size: 37)
                    .foregroundStyle(LW.foreground)
                    .frame(width: 87, height: 87)
                    .background(theme.preset.gradient)
                    .clipShape(Circle())
                    .overlay(Circle().strokeBorder(theme.preset.t300))
                    .shadow(color: .black.opacity(0.4), radius: 12, y: 6)
            }
            .buttonStyle(PressScale())
            .offset(y: -12)
            .accessibilityLabel(t("shared.nav.scan"))
            .accessibilityIdentifier("nav.scan")
        }
        .padding(.bottom, 8)
    }

    private func side(_ icon: String, _ tab: Tab, _ action: @escaping () -> Void, label: String) -> some View {
        Button(action: action) {
            Icon(icon, size: 28).foregroundStyle(active == tab ? LW.foreground : LW.muted).frame(width: 54, height: 54)
        }
        .accessibilityLabel(label)
        .accessibilityIdentifier("nav.\(icon)")
    }
}

struct PressScale: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.scaleEffect(configuration.isPressed ? 0.95 : 1).animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: currency pills (shared/currency-toggle.tsx)

struct CurrencyToggle: View {
    let codes: [String]
    @Binding var selected: String
    var body: some View {
        if codes.count > 1 {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(codes, id: \.self) { code in
                        Button { selected = code } label: {
                            Text(code == "SAT" ? "sats" : code)
                                .font(LW.font(12, .semibold))
                                .padding(.horizontal, 12).padding(.vertical, 5)
                                .foregroundStyle(selected == code ? LW.foreground : LW.muted)
                                .background(selected == code ? LW.background : .clear)
                                .clipShape(Capsule())
                                .shadow(color: selected == code ? .black.opacity(0.3) : .clear, radius: 1)
                        }
                        .accessibilityIdentifier("currency.\(code)")
                    }
                }
                .padding(4)
            }
            .fixedSize(horizontal: true, vertical: false)
            .background(LW.card)
            .clipShape(Capsule())
        }
    }
}

// MARK: amount display (shared/amount-display.tsx)

struct AmountDisplay: View {
    let value: String
    var unit = "sats"
    var subline: String?
    var body: some View {
        VStack(spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(Self.format(value)).font(LW.font(48, .semibold)).monospacedDigit().foregroundStyle(LW.foreground)
                    .lineLimit(1).minimumScaleFactor(0.4)
                Text(unit).font(LW.font(18)).foregroundStyle(LW.muted)
            }
            if let subline { Text(subline).font(LW.font(14)).foregroundStyle(LW.muted) }
        }
        .padding(.vertical, 32)
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

// MARK: keypad (shared/amount-keypad.tsx)

struct AmountKeypad: View {
    @Binding var value: String
    /// Max fraction digits (0 = integer sats, 2 = fiat, 8 = BTC).
    var decimals = 0
    var maxLength = 12

    var body: some View {
        let keys = ["1", "2", "3", "4", "5", "6", "7", "8", "9", decimals > 0 ? "." : "", "0", "⌫"]
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
            ForEach(keys.indices, id: \.self) { i in
                let k = keys[i]
                if k.isEmpty { Color.clear.frame(height: 58) } else {
                    Button { press(k) } label: {
                        Group { if k == "⌫" { Icon("delete", size: 24) } else { Text(k).font(LW.font(30)) } }
                            .frame(maxWidth: .infinity, minHeight: 58)
                            .foregroundStyle(LW.foreground)
                            .background(LW.card.opacity(0.9))
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(PressScale())
                    .accessibilityIdentifier(k == "⌫" ? "key.delete" : "key.\(k)")
                }
            }
        }
    }

    func press(_ k: String) {
        value = Self.apply(k, to: value, decimals: decimals, maxLength: maxLength)
    }

    static func apply(_ k: String, to value: String, decimals: Int, maxLength: Int) -> String {
        if k == "⌫" { return String(value.dropLast()) }
        if k == "." { return decimals == 0 || value.contains(".") ? value : (value.isEmpty ? "0." : value + ".") }
        if let dot = value.firstIndex(of: ".") , value[value.index(after: dot)...].count >= decimals { return value }
        if value.filter(\.isNumber).count >= maxLength { return value }
        if value == "0" { return k }
        return value + k
    }
}

// MARK: transaction row (shared/transaction-row.tsx)

struct TransactionRowView: View {
    let tx: TxItem
    var body: some View {
        HStack(spacing: 12) {
            Icon(tx.incoming ? "arrow-down-left" : "arrow-up-right", size: 16)
                .foregroundStyle(tx.incoming ? LW.incoming : LW.outgoing)
                .frame(width: 40, height: 40)
                .background((tx.incoming ? LW.incoming : LW.outgoing).opacity(0.1))
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(tx.title).font(LW.font(14, .medium)).foregroundStyle(LW.foreground).lineLimit(1)
                Text(RelativeTime.format(tx.date)).font(LW.font(12)).foregroundStyle(LW.muted)
            }
            Spacer(minLength: 8)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text((tx.incoming ? "+" : "−") + tx.amountSats.formatted()).font(LW.font(14, .semibold)).monospacedDigit()
                    .foregroundStyle(tx.incoming ? LW.incoming : LW.foreground)
                Text("sats").font(LW.font(12)).foregroundStyle(LW.muted)
            }
            if tx.pending { ProgressView().controlSize(.mini).tint(LW.muted) }
        }
        .padding(.horizontal, 12).padding(.vertical, 12)
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

// MARK: QR (shared/qr-display.tsx)

struct QRCodeImage: View {
    let text: String
    var body: some View {
        if let img = Self.make(text) {
            Image(uiImage: img).interpolation(.none).resizable().scaledToFit()
        } else { Color.white }
    }

    static func make(_ text: String) -> UIImage? {
        let f = CIFilter.qrCodeGenerator()
        f.message = Data(text.utf8)
        f.correctionLevel = "M"
        guard let out = f.outputImage?.transformed(by: CGAffineTransform(scaleX: 10, y: 10)),
              let cg = CIContext().createCGImage(out, from: out.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}

struct QRDisplay: View {
    let value: String
    var caption: String?
    var copyValue: String?
    @State private var copied = false
    var body: some View {
        VStack(spacing: 16) {
            QRCodeImage(text: value)
                .frame(width: 240, height: 240)
                .padding(16)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .accessibilityIdentifier("qr.code")
            if let caption {
                Text(caption).font(LW.font(14)).foregroundStyle(LW.muted).lineLimit(1).truncationMode(.middle)
                    .accessibilityIdentifier("qr.caption")
            }
            HStack(spacing: 8) {
                Button {
                    UIPasteboard.general.string = copyValue ?? value
                    copied = true
                    Haptics.tap()
                    Task { try? await Task.sleep(for: .seconds(1.5)); copied = false }
                } label: {
                    Label { Text(copied ? t("common.copied") : t("common.copy")) } icon: { Icon(copied ? "check" : "copy", size: 16) }
                }
                .buttonStyle(.lw(.secondary, height: 40))
                .accessibilityIdentifier("qr.copy")
                ShareLink(item: copyValue ?? value) { Icon("share-2", size: 16) }
                    .frame(width: 40, height: 40).background(LW.secondary).clipShape(RoundedRectangle(cornerRadius: 12))
                    .foregroundStyle(LW.foreground)
            }
            .frame(width: 272)
        }
    }
}

// MARK: swipe to confirm (ui/swipe-button.tsx)

struct SwipeButton: View {
    let label: String
    var loading = false
    let onComplete: () -> Void
    @State private var offset: CGFloat = 0
    @Environment(\.theme) private var theme
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        GeometryReader { geo in
            let knob: CGFloat = 48
            let maxX = geo.size.width - knob - 8
            ZStack(alignment: .leading) {
                Capsule().fill(LW.card).overlay(Capsule().strokeBorder(LW.border))
                Capsule().fill(theme.preset.gradient).frame(width: offset + knob + 8).opacity(0.6)
                Text(loading ? t("send.preview.sending") : label).font(LW.font(15, .medium)).foregroundStyle(LW.muted)
                    .frame(maxWidth: .infinity)
                Circle().fill(theme.preset.gradient).overlay(Circle().strokeBorder(theme.preset.t300))
                    .overlay { if loading { ProgressView().tint(.white) } else { Icon("chevrons-right", size: 22).foregroundStyle(.white) } }
                    .frame(width: knob, height: knob).padding(4).offset(x: offset)
                    .gesture(DragGesture()
                        .onChanged { g in if !loading && isEnabled { offset = min(max(0, g.translation.width), maxX) } }
                        .onEnded { _ in
                            if offset > maxX * 0.85 { offset = maxX; Haptics.success(); onComplete() } else { withAnimation(.spring) { offset = 0 } }
                        })
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(label)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { if !loading { onComplete() } }
            .accessibilityIdentifier("swipe.confirm")
        }
        .frame(height: 56)
        .opacity(isEnabled ? 1 : 0.5)
        .onChange(of: loading) { _, l in if !l { withAnimation(.spring) { offset = 0 } } }
    }
}

// MARK: misc

enum Haptics {
    static func tap() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func error() { UINotificationFeedbackGenerator().notificationOccurred(.error) }
}

struct ErrorText: View {
    let message: String?
    var body: some View {
        if let message, !message.isEmpty {
            Text(message).font(LW.font(13)).foregroundStyle(LW.destructiveText).multilineTextAlignment(.center)
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
            if secure { SecureField(placeholder, text: $text) } else { TextField(placeholder, text: $text) }
        }
        .font(mono ? .system(size: 15, design: .monospaced) : LW.font(16))
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .padding(.horizontal, 14).frame(minHeight: 52)
        .background(LW.background)
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(LW.border))
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
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(LW.card).clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(LW.border))
        .shadow(color: .black.opacity(0.4), radius: 16, y: 8)
        .padding(.horizontal, 16)
        .accessibilityIdentifier("toast")
    }
}

/// Remote image with a neutral placeholder (card designs, avatars, community logos).
struct RemoteImage: View {
    let url: URL?
    var contentMode: ContentMode = .fill
    var body: some View {
        AsyncImage(url: url) { phase in
            if let img = phase.image { img.resizable().aspectRatio(contentMode: contentMode) } else { LW.secondary }
        }
    }
}
