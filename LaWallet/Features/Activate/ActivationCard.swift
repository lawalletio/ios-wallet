import SwiftUI

/// components/activate/card-3d.tsx, flattened to 2D: the card design gently bobs and sways (rotation + foreshortening),
/// with a sweeping sheen and a pulsing themed glow. Frozen under Reduce Motion.
struct ActivationCard: View {
    let imageURL: URL?
    var title: String?
    var glow = true
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let size = CGSize(width: 300, height: 189)

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { ctx in
            let s = ctx.date.timeIntervalSinceReferenceDate
            let sway = reduceMotion ? 0 : sin(s * 2 * .pi / 7)              // card-sway 7s
            let bob = reduceMotion ? 0 : (1 - cos(s * 2 * .pi / 5.5)) / 2   // card-bob 5.5s
            let pulse = reduceMotion ? 0 : (1 - cos(s * 2 * .pi / 4)) / 2   // activate-glow 4s
            let sheen = s.truncatingRemainder(dividingBy: 5.5) / 5.5        // glare-sweep 5.5s
            ZStack {
                if glow {
                    Circle()
                        .fill(RadialGradient(colors: [theme.preset.primary.opacity(0.5), theme.preset.primary.opacity(0.2), .clear],
                                             center: .center, startRadius: 0, endRadius: 128))
                        .frame(width: 256, height: 256).blur(radius: 40)
                        .opacity(0.3 + 0.35 * pulse).scaleEffect(1 + 0.12 * pulse)
                }
                face(sheen: reduceMotion ? nil : sheen)
                    .scaleEffect(x: 1 - 0.05 * abs(sway), y: 1)
                    .rotationEffect(.degrees(2.5 * sway))
                    .offset(y: -14 * bob)
                    .shadow(color: .black.opacity(0.55), radius: 24, y: 18)
            }
        }
        .frame(width: Self.size.width + 40, height: Self.size.height + 60)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title ?? t("activate.cardAlt"))
        .accessibilityIdentifier("activate.card")
    }

    private func face(sheen: Double?) -> some View {
        ZStack(alignment: .bottomLeading) {
            if let imageURL {
                RemoteImage(url: imageURL)
            } else {
                LinearGradient(colors: [Color(hex: "1c2530"), Color(hex: "0a0a0f"), Color(hex: "26100a")], startPoint: .topLeading, endPoint: .bottomTrailing)
            }
            if let title {
                Text(title).font(LW.font(14, .semibold)).tracking(0.4).foregroundStyle(.white).shadow(radius: 2)
                    .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                    .background(LinearGradient(colors: [.black.opacity(0.7), .clear], startPoint: .bottom, endPoint: .top))
            }
            if let sheen, sheen < 0.45 {
                // 0–15 %: fade in to 0.55, 15–45 %: fade out, while sweeping left → right.
                let opacity = sheen < 0.15 ? sheen / 0.15 * 0.55 : 0.55 * (1 - (sheen - 0.15) / 0.3)
                LinearGradient(colors: [.clear, .white.opacity(0.65), .clear], startPoint: .leading, endPoint: .trailing)
                    .frame(width: Self.size.width / 3, height: Self.size.height * 1.4)
                    .rotationEffect(.degrees(20))
                    .offset(x: Self.size.width * (-0.3 + sheen * 2), y: Self.size.height * 0.2)
                    .opacity(opacity)
                    .allowsHitTesting(false)
            }
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.white.opacity(0.15)))
    }
}

/// components/activate/activation-success.tsx — confetti, pop-in badge with expanding rings + drawn check, the card, CTA.
struct ActivationSuccessView: View {
    let imageURL: URL?
    let title: String?
    let claimAddress: Bool
    /// Sats the claim actually paid (nil when the bonus is off or wasn't granted).
    let bonusSats: Int?
    let onContinue: () -> Void
    @Environment(\.theme) private var theme
    @State private var popped = false
    @State private var checked = false
    @State private var shown = false

    var body: some View {
        ZStack {
            ConfettiRain(lead: theme.preset.primary)
            VStack(spacing: 0) {
                badge.padding(.bottom, 32)
                Text(t("activate.success.title")).font(LW.font(24, .semibold)).foregroundStyle(LW.foreground).opacity(shown ? 1 : 0)
                if !claimAddress || bonusSats != nil {
                    VStack(spacing: 8) {
                        if !claimAddress { Text(linkedText) }
                        if let bonusSats {
                            Text(t("activate.success.bonus", ["sats": bonusSats.formatted()])).font(LW.font(14, .medium)).foregroundStyle(LW.foreground)
                        }
                    }
                    .font(LW.font(14)).foregroundStyle(LW.muted).multilineTextAlignment(.center).frame(maxWidth: 320)
                    .padding(.top, 8).opacity(shown ? 1 : 0)
                }
                ActivationCard(imageURL: imageURL, title: title, glow: false).scaleEffect(0.9).padding(.vertical, 16)
                Button(t(claimAddress ? "activate.success.claimAddress" : "activate.openWallet"), action: onContinue)
                    .buttonStyle(.lw(.primary))
                    .frame(maxWidth: 320)
                    .accessibilityIdentifier("activate.success.continue")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.55)) { popped = true }
            withAnimation(.easeOut(duration: 0.5).delay(0.35)) { checked = true }
            withAnimation(.easeOut(duration: 0.4).delay(0.2)) { shown = true }
        }
    }

    private var linkedText: AttributedString {
        guard let title else { return AttributedString(t("activate.success.linked")) }
        var name = AttributedString(title)
        name.font = LW.font(14, .medium)
        name.foregroundColor = LW.foreground
        return name + AttributedString(t("activate.success.linkedNamed"))
    }

    private var badge: some View {
        ZStack {
            TimelineView(.animation) { ctx in
                let s = ctx.date.timeIntervalSinceReferenceDate
                ZStack {
                    ring(phase: s.truncatingRemainder(dividingBy: 1.6) / 1.6)
                    ring(phase: (s + 1.0).truncatingRemainder(dividingBy: 1.6) / 1.6)
                }
            }
            Circle()
                .fill(theme.preset.gradient)
                .overlay(Circle().strokeBorder(theme.preset.t300))
                .shadow(color: theme.preset.primary.opacity(0.55), radius: 18)
                .frame(width: 80, height: 80)
            CheckPath()
                .trim(from: 0, to: checked ? 1 : 0)
                .stroke(LW.foreground, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                .frame(width: 40, height: 40)
        }
        .frame(width: 96, height: 96)
        .scaleEffect(popped ? 1 : 0)
        .opacity(popped ? 1 : 0)
    }

    /// ring-expand: scale 0.35 → 1.7, opacity 0.7 → 0 (ease-out).
    private func ring(phase: Double) -> some View {
        let e = 1 - pow(1 - phase, 2)
        return Circle().strokeBorder(theme.preset.primary, lineWidth: 2)
            .scaleEffect(0.35 + 1.35 * e).opacity(0.7 * (1 - e))
    }
}

/// The success check `M14 27 L23 36 L39 18` on a 52×52 box.
private struct CheckPath: Shape {
    func path(in r: CGRect) -> Path {
        let sx = r.width / 52, sy = r.height / 52
        var p = Path()
        p.move(to: CGPoint(x: 14 * sx, y: 27 * sy))
        p.addLine(to: CGPoint(x: 23 * sx, y: 36 * sy))
        p.addLine(to: CGPoint(x: 39 * sx, y: 18 * sy))
        return p
    }
}

/// 36 deterministic pieces falling once (`confetti-fall`), drawn in a Canvas.
private struct ConfettiRain: View {
    let lead: Color
    @State private var start = Date()
    @State private var done = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct Piece {
        let x, delay, duration, dx, rot, size: Double
        let color: Int
        let round: Bool
    }

    private static let pieces: [Piece] = (0..<36).map { i in
        func r(_ n: Double) -> Double { ((sin(Double(i) * 9301 + n * 49297) + 1) / 2).truncatingRemainder(dividingBy: 1) }
        return Piece(x: r(1), delay: r(2) * 1.2, duration: 2.2 + r(3) * 1.8, dx: (r(4) - 0.5) * 220, rot: 360 + r(5) * 900,
                     size: 6 + (r(6) * 7).rounded(), color: i % 5, round: r(7) > 0.5)
    }

    var body: some View {
        let colors = [lead, Color(hex: "F5A623"), Color(hex: "E53935"), Color(hex: "A78BFA"), .white]
        TimelineView(.animation(paused: done || reduceMotion)) { ctx in
            let elapsed = ctx.date.timeIntervalSince(start)
            Canvas { gc, size in
                for piece in Self.pieces {
                    let p = (elapsed - piece.delay) / piece.duration
                    guard p >= 0, p <= 1 else { continue }
                    var g = gc
                    g.translateBy(x: piece.x * size.width + piece.dx * p, y: -0.12 * size.height + 1.24 * size.height * p)
                    g.rotate(by: .degrees(piece.rot * p))
                    let rect = CGRect(x: -piece.size / 2, y: -piece.size / 2, width: piece.size, height: piece.size)
                    g.fill(piece.round ? Path(ellipseIn: rect) : Path(roundedRect: rect, cornerRadius: 2), with: .color(colors[piece.color]))
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .task {
            try? await Task.sleep(for: .seconds(5.5))
            done = true
        }
    }
}
