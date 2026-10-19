import SwiftUI

/// Receipt (components/wallet/shared/payment-receipt.tsx) as one glass sheet: status mark, amount, details, proof.
struct PaymentReceipt: View {
    enum Status { case settled, pending, failed }

    let status: Status
    let title: String
    var subtitle: String?
    let amountSats: Int
    var details: [(String, String?)] = []
    var proofs: [(String, String?)] = []
    @Environment(AppModel.self) private var app
    @Environment(\.theme) private var theme
    @State private var code: String?
    @State private var revealed: Set<String> = []
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 14) {
            VStack(spacing: 18) {
                mark
                VStack(spacing: 8) {
                    Text(title).font(LW.font(26, .bold)).tracking(-0.4).multilineTextAlignment(.center)
                    if let subtitle { Text(subtitle).font(LW.font(15)).foregroundStyle(LW.muted).multilineTextAlignment(.center) }
                    badge
                }
                let c = code ?? app.currencies.selected
                VStack(spacing: 10) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(app.currencies.format(amountSats, c)).font(LW.font(46, .semibold)).tracking(-1.4).monospacedDigit()
                            .lineLimit(1).minimumScaleFactor(0.5)
                            .contentTransition(.numericText())
                        Text(app.currencies.unit(c)).font(LW.font(18, .medium)).foregroundStyle(LW.muted)
                    }
                    .accessibilityIdentifier("receipt.amount")
                    if c != "SAT" { Text("\(amountSats.formatted()) sats").font(LW.font(14)).foregroundStyle(LW.muted) }
                    CurrencyToggle(codes: app.currencies.active, selected: Binding(get: { c }, set: { code = $0 }))
                }

                if !details.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(details.indices, id: \.self) { i in
                            if i > 0 { Rectangle().fill(Color.white.opacity(0.08)).frame(height: 0.5) }
                            HStack(alignment: .top) {
                                Text(details[i].0).foregroundStyle(LW.muted)
                                Spacer(minLength: 16)
                                Text(details[i].1 ?? t("shared.receipt.unavailable")).multilineTextAlignment(.trailing)
                                    .foregroundStyle(details[i].1 == nil ? LW.muted : LW.foreground)
                            }
                            .font(LW.font(15))
                            .padding(.vertical, 12)
                        }
                    }
                    .padding(.horizontal, 16)
                    .lwInset(LW.Radius.control)
                }
            }
            .padding(.horizontal, 18).padding(.top, 30).padding(.bottom, 18)
            .frame(maxWidth: .infinity)
            .lwSurface(LW.Radius.sheet)

            if !proofs.isEmpty {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(t("shared.receipt.proofTitle")).font(LW.font(16, .semibold))
                        Text(t("shared.receipt.proofHint")).font(LW.font(13)).foregroundStyle(LW.muted)
                    }
                    ForEach(proofs.indices, id: \.self) { i in proofRow(proofs[i].0, proofs[i].1) }
                }
                .padding(18).frame(maxWidth: .infinity, alignment: .leading)
                .lwSurface()
            }
        }
        .onAppear { withAnimation(.spring(response: 0.5, dampingFraction: 0.65).delay(0.1)) { appeared = true } }
    }

    @ViewBuilder private var mark: some View {
        let (icon, color): (String, Color) = switch status {
        case .settled: ("check", theme.preset.primary)
        case .pending: ("clock", LW.sun)
        case .failed: ("x", LW.coral)
        }
        Icon(icon, size: 34).foregroundStyle(.white)
            .frame(width: 76, height: 76)
            .lwGlass(in: Circle(), tint: .color(color.opacity(0.75)))
            .shadow(color: color.opacity(0.45), radius: 24, y: 8)
            .scaleEffect(appeared ? 1 : 0.6)
            .opacity(appeared ? 1 : 0)
    }

    private var badge: some View {
        let key = switch status { case .settled: "settled"; case .pending: "pending"; case .failed: "failed" }
        return Text(t("shared.receipt.\(key)")).font(LW.font(12, .semibold)).padding(.horizontal, 12).padding(.vertical, 5)
            .foregroundStyle(status == .failed ? LW.destructiveText : LW.foreground.opacity(0.9))
            .background(Color.white.opacity(0.10), in: Capsule())
    }

    private func proofRow(_ label: String, _ value: String?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label).font(LW.font(13, .semibold)).foregroundStyle(LW.muted)
                Spacer()
                if let value {
                    Button { if revealed.contains(label) { revealed.remove(label) } else { revealed.insert(label) } } label: {
                        Icon(revealed.contains(label) ? "eye-off" : "eye", size: 15).frame(width: 32, height: 32).contentShape(Circle())
                    }
                    .accessibilityLabel(revealed.contains(label) ? t("shared.receipt.hide", ["label": label]) : t("shared.receipt.show", ["label": label]))
                    Button { UIPasteboard.general.string = value; Haptics.tap(); app.show(.success, t("common.copied")) } label: {
                        Icon("copy", size: 15).frame(width: 32, height: 32).contentShape(Circle())
                    }
                    .accessibilityLabel(t("common.copy"))
                }
            }
            .foregroundStyle(LW.muted)
            if let value {
                Text(revealed.contains(label) ? value : String(value.prefix(10)) + "…" + String(value.suffix(10)))
                    .font(.system(size: 13, design: .monospaced)).foregroundStyle(LW.foreground.opacity(0.9)).textSelection(.enabled)
                    .padding(.horizontal, 12).padding(.vertical, 10).frame(maxWidth: .infinity, alignment: .leading)
                    .lwInset()
            } else {
                Text(t("shared.receipt.notProvided")).font(LW.font(14)).foregroundStyle(LW.muted)
            }
        }
    }
}

/// Bottom-pinned actions for flow screens; floats over content (no bar background — the scroll edge softens behind it).
struct BottomBar<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View {
        GlassGroup(spacing: 10) {
            VStack(spacing: 10) { content() }
        }
        .padding(.horizontal, 20).padding(.top, 10).padding(.bottom, 10)
        // Content above stops at the bar; fade its last points so it dissolves instead of being cut.
        .background {
            LinearGradient(stops: [.init(color: LW.ink.opacity(0), location: 0), .init(color: LW.ink.opacity(0.55), location: 0.22),
                                   .init(color: LW.ink.opacity(0.75), location: 1)], startPoint: .top, endPoint: .bottom)
                .padding(.top, -24).padding(.bottom, -60).allowsHitTesting(false)
        }
    }
}
