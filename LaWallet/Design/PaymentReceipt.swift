import SwiftUI

/// Receipt card + proof rows (components/wallet/shared/payment-receipt.tsx).
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

    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 16) {
                mark
                VStack(spacing: 8) {
                    Text(title).font(LW.font(24, .semibold)).multilineTextAlignment(.center)
                    if let subtitle { Text(subtitle).font(LW.font(14)).foregroundStyle(LW.muted).multilineTextAlignment(.center) }
                    badge
                }
                let c = code ?? app.currencies.selected
                VStack(spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(app.currencies.format(amountSats, c)).font(LW.font(36, .semibold)).monospacedDigit()
                            .lineLimit(1).minimumScaleFactor(0.5)
                        Text(app.currencies.unit(c)).font(LW.font(16, .semibold)).foregroundStyle(LW.muted)
                    }
                    .accessibilityIdentifier("receipt.amount")
                    if c != "SAT" { Text("\(amountSats.formatted()) sats").font(LW.font(14)).foregroundStyle(LW.muted) }
                    CurrencyToggle(codes: app.currencies.active, selected: Binding(get: { c }, set: { code = $0 }))
                }
            }
            .padding(.horizontal, 20).padding(.top, 32).padding(.bottom, 24)
            .frame(maxWidth: .infinity)
            .background(alignment: .top) {
                LinearGradient(colors: [.clear, theme.preset.t300, .clear], startPoint: .leading, endPoint: .trailing).frame(height: 1)
            }

            if !details.isEmpty {
                VStack(spacing: 12) {
                    ForEach(details.indices, id: \.self) { i in
                        if i > 0 { Rectangle().fill(LW.border).frame(height: 1) }
                        HStack(alignment: .top) {
                            Text(details[i].0).foregroundStyle(LW.muted)
                            Spacer(minLength: 12)
                            Text(details[i].1 ?? t("shared.receipt.unavailable")).multilineTextAlignment(.trailing)
                                .foregroundStyle(details[i].1 == nil ? LW.muted : LW.foreground)
                        }
                        .font(LW.font(14))
                    }
                }
                .padding(12).background(LW.card.opacity(0.7)).clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(LW.border.opacity(0.7)))
                .padding(.horizontal, 16).padding(.bottom, 16)
            }
        }
        .background(LW.card)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(LW.border))

        if !proofs.isEmpty {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(t("shared.receipt.proofTitle").uppercased()).font(LW.font(12, .medium)).tracking(2).foregroundStyle(LW.muted)
                    Text(t("shared.receipt.proofHint")).font(LW.font(14)).foregroundStyle(LW.muted)
                }
                ForEach(proofs.indices, id: \.self) { i in proofRow(proofs[i].0, proofs[i].1) }
            }
            .padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(LW.card.opacity(0.85)).clipShape(RoundedRectangle(cornerRadius: 24))
            .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(LW.border.opacity(0.8)))
            .padding(.top, 20)
        }
    }

    @ViewBuilder private var mark: some View {
        let (icon, color): (String, Color) = switch status {
        case .settled: ("check", theme.preset.t400)
        case .pending: ("clock", LW.muted)
        case .failed: ("x", LW.destructiveText)
        }
        Icon(icon, size: 40).foregroundStyle(color).frame(width: 80, height: 80)
            .background(Circle().fill(status == .pending ? LW.secondary : color.opacity(0.15)))
    }

    private var badge: some View {
        let key = switch status { case .settled: "settled"; case .pending: "pending"; case .failed: "failed" }
        return Text(t("shared.receipt.\(key)")).font(LW.font(12, .medium)).padding(.horizontal, 10).padding(.vertical, 3)
            .background(LW.secondary).clipShape(Capsule()).foregroundStyle(status == .failed ? LW.destructiveText : LW.foreground)
    }

    private func proofRow(_ label: String, _ value: String?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label.uppercased()).font(LW.font(10, .semibold)).tracking(1.2).foregroundStyle(LW.muted)
                Spacer()
                if let value {
                    Button { if revealed.contains(label) { revealed.remove(label) } else { revealed.insert(label) } } label: {
                        Icon(revealed.contains(label) ? "eye-off" : "eye", size: 14).frame(width: 28, height: 28)
                    }
                    Button { UIPasteboard.general.string = value; app.show(.success, t("common.copied")) } label: {
                        Icon("copy", size: 14).frame(width: 28, height: 28)
                    }
                }
            }
            .foregroundStyle(LW.muted)
            if let value {
                Text(revealed.contains(label) ? value : String(value.prefix(10)) + "…" + String(value.suffix(10)))
                    .font(.system(size: 12, design: .monospaced)).foregroundStyle(LW.foreground).textSelection(.enabled)
            } else {
                Text(t("shared.receipt.notProvided")).font(LW.font(14)).foregroundStyle(LW.muted)
            }
        }
    }
}

/// Bottom-pinned action bar used by flow screens (`PaymentReceiptLayout` footer).
struct BottomBar<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(spacing: 8) { content() }
            .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 8)
            .background(LW.background.opacity(0.9))
            .overlay(alignment: .top) { Rectangle().fill(LW.border.opacity(0.6)).frame(height: 1) }
    }
}
