import SwiftUI

// MARK: - Liquid Glass toolkit
//
// iOS 26 renders real Liquid Glass (`glassEffect`); iOS 18–25 fall back to a thin material with a hairline rim.
// Hierarchy is carried by shape, not by stacking: chrome & controls are capsules, primary surfaces use `LW.Radius.surface`,
// rows inside a surface are hairline-divided (never glass on glass).

extension LW {
    enum Radius {
        static let sheet: CGFloat = 32
        static let surface: CGFloat = 26
        static let control: CGFloat = 18
        static let inset: CGFloat = 12
    }
}

/// How strongly a glass surface is tinted.
enum GlassTint: Equatable {
    case none
    /// Frosted light glass for the default CTA (dark label on top).
    case light
    case color(Color)
}

private struct GlassModifier<S: Shape>: ViewModifier {
    let shape: S
    var tint: GlassTint = .none
    var interactive = false
    var clear = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *), !reduceTransparency {
            content.glassEffect(glass, in: shape)
        } else {
            content
                .background(fallbackFill, in: shape)
                .overlay(shape.stroke(Color.white.opacity(0.10), lineWidth: 0.75))
        }
    }

    @available(iOS 26.0, *)
    private var glass: Glass {
        var g: Glass = clear ? .clear : .regular
        switch tint {
        case .none: break
        case .light: g = g.tint(Color.white.opacity(0.94))
        case .color(let c): g = g.tint(c)
        }
        return interactive ? g.interactive() : g
    }

    private var fallbackFill: AnyShapeStyle {
        if reduceTransparency {
            switch tint {
            case .none: return AnyShapeStyle(Color(hex: "1c1d1f"))
            case .light: return AnyShapeStyle(Color(hex: "e9ebea"))
            case .color(let c): return AnyShapeStyle(c)
            }
        }
        switch tint {
        case .none: return AnyShapeStyle(.ultraThinMaterial)
        case .light: return AnyShapeStyle(Color.white.opacity(0.82))
        case .color(let c): return AnyShapeStyle(c.opacity(0.85))
        }
    }
}

extension View {
    /// Liquid Glass in `shape`. `interactive` adds the press/touch response (buttons, keys).
    func lwGlass<S: Shape>(in shape: S, tint: GlassTint = .none, interactive: Bool = false, clear: Bool = false) -> some View {
        modifier(GlassModifier(shape: shape, tint: tint, interactive: interactive, clear: clear))
    }

    /// Primary content surface (cards, lists, receipts).
    func lwSurface(_ radius: CGFloat = LW.Radius.surface) -> some View {
        lwGlass(in: RoundedRectangle(cornerRadius: radius, style: .continuous))
    }

    /// Recessed well inside a surface (text fields, code blocks) — darker, no glass.
    func lwInset(_ radius: CGFloat = LW.Radius.inset) -> some View {
        background(Color.black.opacity(0.28), in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Color.white.opacity(0.06)))
    }
}

/// Groups nearby glass so it blends and morphs (iOS 26); a plain container elsewhere.
struct GlassGroup<Content: View>: View {
    var spacing: CGFloat = 12
    @ViewBuilder var content: () -> Content
    var body: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { content() }
        } else {
            content()
        }
    }
}

// MARK: - Ambient light
//
// The LaWallet isotype's three lobes (mint, sun, coral) become soft light fields behind the glass. They drift on a
// clock — every screen draws the same frame at the same instant, so pushes and pops look continuous. A payment makes
// the light bloom behind the balance (green in, coral out): the app's one orchestrated motion.

enum AmbientFlare: Equatable { case incoming, outgoing }

struct AmbientBackground: View {
    /// 1 = home, lower for focused flows so content leads.
    var intensity: Double = 1
    var flare: AmbientFlare?
    var flareAt: Date?
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var phase
    @State private var onScreen = false
    @State private var flaring = false
    @State private var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled

    static let flareDuration: Double = 2.4

    enum FrameRate: Equatable { case paused, drift, display }

    /// How often to redraw. The drift moves ~1.5 pt/s, so 8 fps is indistinguishable from 60 and costs a fraction;
    /// only the payment bloom needs display rate. Hidden screens (under a push, app in background), Low Power Mode and
    /// Reduce Motion hold a still frame.
    nonisolated static func frameRate(onScreen: Bool, active: Bool, flaring: Bool, reduceMotion: Bool, lowPower: Bool) -> FrameRate {
        guard onScreen, active else { return .paused }
        if flaring { return .display }
        return reduceMotion || lowPower ? .paused : .drift
    }

    var body: some View {
        let rate = Self.frameRate(onScreen: onScreen, active: phase == .active, flaring: flaring, reduceMotion: reduceMotion,
                                  lowPower: lowPower)
        TimelineView(.animation(minimumInterval: rate == .drift ? 1.0 / 8 : nil, paused: rate == .paused)) { context in
            Canvas(opaque: true, rendersAsynchronously: true) { ctx, size in
                draw(ctx, size: size, time: reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate, now: context.date)
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
        .onAppear { onScreen = true }
        .onDisappear { onScreen = false }
        .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange).receive(on: RunLoop.main)) { _ in
            lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        }
        .task(id: flareAt) {
            guard let flareAt, Date().timeIntervalSince(flareAt) < Self.flareDuration else { return }
            flaring = true
            try? await Task.sleep(for: .seconds(Self.flareDuration))
            flaring = false
        }
    }

    private func draw(_ ctx: GraphicsContext, size: CGSize, time t: Double, now: Date) {
        ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(LW.ink))
        let w = size.width, h = size.height
        // Slow, out-of-phase drift (periods of ~40–90 s) so the light never looks looped. Additive blending keeps the
        // lobes luminous where they overlap instead of mixing to mud.
        var light = ctx
        light.blendMode = .plusLighter
        func glow(_ color: Color, _ x: Double, _ y: Double, _ r: Double, _ alpha: Double) {
            let center = CGPoint(x: x * w, y: y * h), radius = r * max(w, h)
            light.fill(Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)),
                       with: .radialGradient(Gradient(stops: [.init(color: color.opacity(alpha * intensity), location: 0),
                                                             .init(color: color.opacity(alpha * intensity * 0.35), location: 0.45),
                                                             .init(color: color.opacity(0), location: 1)]),
                                             center: center, startRadius: 0, endRadius: radius))
        }
        glow(LW.mint, 0.86 + 0.05 * sin(t / 13), 0.04 + 0.04 * cos(t / 15), 0.62, 0.30)
        glow(theme.preset.primary, 0.10 + 0.06 * cos(t / 17), 0.24 + 0.04 * sin(t / 11), 0.40, 0.10)
        glow(LW.sun, -0.04 + 0.04 * sin(t / 19), 0.60 + 0.05 * cos(t / 14), 0.30, 0.08)
        glow(LW.coral, 1.02 + 0.04 * cos(t / 12), 0.94 + 0.03 * sin(t / 16), 0.44, 0.17)

        // Payment bloom behind the balance: rises fast, fades over ~2.4 s.
        if let flare, let flareAt {
            let age = now.timeIntervalSince(flareAt)
            if age >= 0, age < Self.flareDuration {
                let p = age / Self.flareDuration
                let strength = sin(min(1, p * 2.2) * .pi / 2) * (1 - p)
                glow(flare == .incoming ? LW.incoming : LW.coral, 0.5, 0.22, 0.30 + 0.25 * p, 0.45 * strength)
            }
        }
        // Gentle vignette keeps text contrast at the edges.
        ctx.fill(Path(CGRect(origin: .zero, size: size)),
                 with: .linearGradient(Gradient(colors: [.black.opacity(0.0), .black.opacity(0.45)]),
                                       startPoint: CGPoint(x: w / 2, y: h * 0.45), endPoint: CGPoint(x: w / 2, y: h)))
    }
}

extension View {
    /// Standard screen backdrop: ambient light under everything, edge-to-edge.
    func lwScreenBackground(_ intensity: Double = 0.75) -> some View {
        background(AmbientBackground(intensity: intensity))
    }
}

// MARK: - Segmented control (currency toggle, tabs)

struct GlassSegmented<ID: Hashable>: View {
    let items: [(id: ID, label: String)]
    @Binding var selection: ID
    var idPrefix = "segment"
    var compact = true
    @Namespace private var ns

    var body: some View {
        HStack(spacing: 2) {
            ForEach(items, id: \.id) { item in
                let on = item.id == selection
                Button {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) { selection = item.id }
                    Haptics.select()
                } label: {
                    Text(item.label)
                        .font(LW.font(compact ? 13 : 14, on ? .semibold : .medium))
                        .foregroundStyle(on ? LW.foreground : LW.muted)
                        .padding(.horizontal, compact ? 14 : 16).padding(.vertical, compact ? 7 : 9)
                        .background {
                            if on {
                                Capsule().fill(Color.white.opacity(0.16))
                                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.14), lineWidth: 0.5))
                                    .matchedGeometryEffect(id: "selection", in: ns)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
                .accessibilityIdentifier("\(idPrefix).\(item.id)")
            }
        }
        .padding(4)
        .lwGlass(in: Capsule())
    }
}

extension View {
    /// Liquid Glass for system-drawn controls we can't restyle by hand (e.g. `PasteButton`).
    @ViewBuilder func lwSystemGlass() -> some View {
        if #available(iOS 26.0, *) {
            self.buttonStyle(.glass)
        } else {
            self.tint(Color.white.opacity(0.18))
        }
    }
}
