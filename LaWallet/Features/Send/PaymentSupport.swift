import LaWalletKit
import SwiftUI

// Shared by the send / receive / withdraw / claim flows.

/// Message for UI that surfaces a helper error (`lib/client/i18n/errors.ts`): helper-tagged errors are
/// localized, wallet / LNURL-service / server text passes through verbatim.
struct PayError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

enum PayErrors {
    static func text(_ error: Error, fallback: String = t("errors.nwc.generic")) -> String {
        switch error {
        case let e as Destination.ParseError:
            return t("errors.destination.\(e)")
        case let e as LNURLError:
            switch e.code {
            case .unreachable, .invalidResponse, .unsupported, .missingFields, .noAmount, .belowOneSat, .invalidCallback:
                return t("errors.lnurl.\(e.code.rawValue)")
            default:
                return e.message.isEmpty ? fallback : e.message
            }
        case let e as RelayError:
            switch e {
            case .timeout: return t("errors.nwc.timeout")
            case .notConnected: return t("errors.nwc.relayOffline")
            case .rejected(let m): return m.isEmpty ? fallback : m
            }
        case NWCError.timeout:
            return t("errors.nwc.timeout")
        case let e as LocalizedError:
            return e.errorDescription ?? fallback
        default:
            return fallback
        }
    }
}

// MARK: amount entry (use-amount-currency-input.ts + amount-currency.ts)

/// The keypad string is always in the selected display currency; sats are derived.
enum PayAmount {
    static func decimals(_ code: String) -> Int { Currencies.currency(code)?.decimals ?? 2 }

    /// Display value → sats, rounded up to a whole positive sat (`parseAmountToSats`).
    static func sats(_ raw: String, _ code: String, _ rates: [String: Double]?) -> Int? {
        guard let v = Double(raw), v > 0 else { return nil }
        let exact: Double
        switch code {
        case "SAT": exact = v
        case "BTC": exact = v * 100_000_000
        default:
            guard let rate = rates?[code], rate > 0 else { return nil }
            exact = v / rate * 100_000_000
        }
        let rounded = exact.rounded()
        return max(1, abs(exact - rounded) < 1e-9 ? Int(rounded) : Int(exact.rounded(.up)))
    }

    /// sats → keypad string in `code` (`formatInputFromSats`).
    static func format(_ sats: Int?, _ code: String, _ rates: [String: Double]?) -> String {
        guard let sats, sats > 0 else { return "0" }
        if code == "SAT" { return String(sats) }
        guard let v = Currencies.convert(sats: sats, to: code, rates: rates) else { return "0" }
        if code == "BTC" { return trimmed(v, 8) }
        return String(format: "%.2f", v > 0 && v < 0.01 ? 0.01 : v)
    }

    static func trimmed(_ v: Double, _ digits: Int) -> String {
        var s = String(format: "%.\(digits)f", v)
        if s.contains(".") {
            while s.hasSuffix("0") { s.removeLast() }
            if s.hasSuffix(".") { s.removeLast() }
        }
        return s.isEmpty ? "0" : s
    }
}

extension CurrencyStore {
    /// Sats for a keypad string typed in the selected currency.
    func sats(fromInput value: String) -> Int? { PayAmount.sats(value, selected, rates) }
}

/// Amount display + currency pills + keypad. Switching currency converts what was typed.
struct PayAmountPad: View {
    @Binding var value: String
    var disabled = false
    @Environment(AppModel.self) private var app

    var body: some View {
        let cur = app.currencies
        let code = cur.selected
        VStack(spacing: 12) {
            AmountDisplay(value: value, unit: cur.unit(code),
                          subline: code == "SAT" ? nil : cur.sats(fromInput: value).map { "\($0.formatted()) sats" })
                .padding(.vertical, -20)
            CurrencyToggle(codes: cur.active, selected: Binding(get: { cur.selected }, set: { next in
                value = PayAmount.format(cur.sats(fromInput: value), next, cur.rates)
                cur.selected = next
            }))
            AmountKeypad(value: $value, decimals: PayAmount.decimals(code))
                .disabled(disabled)
                .padding(.top, 8)
        }
    }
}

// MARK: recipients

extension PayAvatar {
    static func initials(_ source: String) -> String {
        let local = source.split(separator: "@").first.map(String.init) ?? source
        let parts = local.split(whereSeparator: { " ._-".contains($0) }).map(String.init)
        let first = parts.first?.first.map(String.init) ?? "?"
        let second = parts.count > 1 ? parts[1].first.map(String.init) : parts.first.flatMap { $0.dropFirst().first.map(String.init) }
        return (first + (second ?? "")).uppercased()
    }
}

struct PayAvatar: View {
    let url: URL?
    let name: String
    var size: CGFloat = 56

    var body: some View {
        ZStack {
            LW.background
            Text(PayAvatar.initials(name)).font(LW.font(max(10, size * 0.3), .medium)).foregroundStyle(LW.muted)
            if let url {
                AsyncImage(url: url) { phase in
                    if let img = phase.image { img.resizable().scaledToFill() }
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(LW.border.opacity(0.7)))
    }
}

struct PayRecipient {
    let name: String
    let subtitle: String
    let avatar: URL?
    let address: String?
}

extension FlowState {
    var sendAddress: String? {
        if case .lnurlPay(_, let address)? = destination { return address?.lowercased() }
        return nil
    }

    /// `buildRecipientDetails` from the send steps: saved contact → LUD-06 metadata → address local-part.
    var payRecipient: PayRecipient? {
        guard let destination else { return nil }
        let address = sendAddress
        let contact = address.flatMap { a in ContactsStore.shared.contacts.first { $0.address.lowercased() == a } }
        let profileName = payParams?.text ?? payParams?.identifier
        let fallback = address.map { String($0.split(separator: "@")[0]) } ?? recipientLabel ?? sendInput
        let name = [contact?.name, profileName, fallback].compactMap { $0?.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty } ?? fallback
        let kind: String = switch destination {
        case .invoice: t("send.kind.invoice")
        case .lnurlPay: t("send.kind.address")
        case .npub: t("send.kind.nostrProfile")
        }
        let domain = address.flatMap { $0.split(separator: "@").last.map(String.init) }
        let avatar = contact?.avatar.flatMap(URL.init(string:)) ?? recipientAvatar ?? payParams?.imageURL ?? domain.flatMap(AddressSuggestions.avatar)
        return PayRecipient(name: name, subtitle: address ?? kind, avatar: avatar, address: address)
    }
}

extension LNURLPayParams {
    /// LUD-06 metadata avatar as a `data:` URL.
    var imageURL: URL? { image.flatMap { URL(string: "data:image/png;base64,\($0.base64EncodedString())") } }
}

/// "To" card used by the amount step (`RecipientPreview`).
struct PayRecipientCard: View {
    let info: PayRecipient
    var body: some View {
        HStack(spacing: 12) {
            PayAvatar(url: info.avatar, name: info.name, size: 56)
            VStack(alignment: .leading, spacing: 2) {
                Text(t("send.to").uppercased()).font(LW.font(12, .medium)).tracking(1.6).foregroundStyle(LW.muted)
                Text(info.name).font(LW.font(16, .semibold)).foregroundStyle(LW.foreground).lineLimit(1)
                Text(info.subtitle).font(LW.font(12)).foregroundStyle(LW.muted).lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(LW.card.opacity(0.8))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(LW.border.opacity(0.7)))
        .accessibilityIdentifier("send.recipient")
    }
}

// MARK: receipts (payment-receipt.ts / payment-receipt.tsx)

enum PayReceiptText {
    static func build(amount: String, fee: String? = nil, recipient: String? = nil, destination: String? = nil,
                      comment: String? = nil, date: Date?, paymentHash: String?, preimage: String?) -> String {
        let l = "shared.receipt.text."
        var lines = [t(l + "title"), "", "\(t(l + "status")): \(t("shared.receipt.settled"))", "\(t(l + "amount")): \(amount)"]
        if let fee, !fee.isEmpty { lines.append("\(t(l + "fee")): \(fee)") }
        let to = recipient?.trimmingCharacters(in: .whitespaces) ?? ""
        if !to.isEmpty { lines.append("\(t(l + "to")): \(to)") }
        if let destination, !destination.isEmpty, destination != to { lines.append("\(t(l + "destination")): \(destination)") }
        if let comment, !comment.isEmpty { lines.append("\(t(l + "note")): \(comment)") }
        if let date { lines.append("\(t(l + "time")): \(PayReceiptText.time(date))") }
        if let paymentHash, !paymentHash.isEmpty { lines += ["", "\(t(l + "paymentHash")):", paymentHash] }
        if let preimage, !preimage.isEmpty { lines += ["", "\(t(l + "preimage")):", preimage] }
        return lines.joined(separator: "\n")
    }

    static func time(_ date: Date) -> String { date.formatted(date: .abbreviated, time: .shortened) }
}

/// Share / View activity / Done footer (`PaymentReceiptActions`).
struct PayReceiptActions: View {
    let shareText: String
    let onDone: () -> Void
    @Environment(AppModel.self) private var app

    var body: some View {
        BottomBar {
            HStack(spacing: 8) {
                ShareLink(item: shareText) {
                    Label { Text(t("common.share")) } icon: { Icon("share-2", size: 16) }
                }
                .buttonStyle(.lw(.secondary))
                .accessibilityIdentifier("summary.share")
                Button(t("shared.receipt.viewActivity")) { app.path = NavigationPath([Route.activity]) }
                    .buttonStyle(.lw(.secondary))
                    .accessibilityIdentifier("summary.activity")
            }
            Button(t("common.done"), action: onDone)
                .buttonStyle(.lw(.primary))
                .accessibilityIdentifier("summary.done")
        }
    }
}

/// Spinner + label used inside primary buttons.
struct PayButtonLabel: View {
    let busy: Bool
    let title: String
    var busyTitle: String?
    var icon: String?
    var body: some View {
        HStack(spacing: 8) {
            if busy { ProgressView().controlSize(.small).tint(LW.muted) }
            if !busy || busyTitle != nil { Text(busy ? busyTitle ?? title : title) }
            if !busy, let icon { Icon(icon, size: 16) }
        }
    }
}
