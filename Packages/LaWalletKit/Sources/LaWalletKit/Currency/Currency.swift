import Foundation

public struct Currency: Sendable, Hashable, Identifiable {
    public let code: String
    public let name: String
    public let locked: Bool
    public var id: String { code }
    public var unitLabel: String { code == "SAT" ? "sats" : code }
    public var decimals: Int { code == "SAT" ? 0 : code == "BTC" ? 8 : 2 }
}

public enum Currencies {
    /// Same order and names as `apps/web/lib/client/currencies-store.ts`.
    public static let catalog: [Currency] = [
        ("SAT", "Satoshi"), ("BTC", "Bitcoin"), ("ARS", "Peso Argentino"), ("BRL", "Real"), ("CLP", "Peso Chileno"),
        ("COP", "Peso Colombiano"), ("EUR", "Euro"), ("GBP", "Libra Esterlina"), ("JPY", "Yen"), ("MXN", "Peso Mexicano"),
        ("PEN", "Sol"), ("USD", "Dolar Americano"), ("UYU", "Peso Uruguayo"), ("VES", "Bolívar")
    ].map { Currency(code: $0.0, name: $0.1, locked: $0.0 == "SAT") }

    public static let defaultActive = ["SAT", "BTC"]

    public static func currency(_ code: String) -> Currency? { catalog.first { $0.code == code } }

    /// Locked codes first, unknown/duplicate codes dropped; `selected` falls back to the first active.
    public static func normalize(active: [String], selected: String) -> (active: [String], selected: String) {
        var seen = Set<String>()
        let locked = catalog.filter(\.locked).map(\.code)
        let rest = active.filter { code in !locked.contains(code) && currency(code) != nil && seen.insert(code).inserted }
        let list = locked + rest
        return (list, list.contains(selected) ? selected : list[0])
    }

    /// sats → display value. nil when a fiat rate isn't loaded.
    public static func convert(sats: Int, to code: String, rates: [String: Double]?) -> Double? {
        switch code {
        case "SAT": Double(sats)
        case "BTC": Double(sats) / 100_000_000
        default: rates?[code].map { Double(sats) / 100_000_000 * $0 }
        }
    }

    /// display value → sats (rounded down to whole sats).
    public static func toSats(_ value: Double, from code: String, rates: [String: Double]?) -> Int? {
        switch code {
        case "SAT": Int(value.rounded(.down))
        case "BTC": Int((value * 100_000_000).rounded(.down))
        default: rates?[code].flatMap { $0 > 0 ? Int((value / $0 * 100_000_000).rounded(.down)) : nil }
        }
    }

    public static func format(sats: Int, code: String, rates: [String: Double]?, locale: Locale = .current) -> String {
        guard let value = convert(sats: sats, to: code, rates: rates) else { return "—" }
        let f = NumberFormatter()
        f.locale = locale
        f.numberStyle = .decimal
        let digits = currency(code)?.decimals ?? 2
        if code != "SAT", code != "BTC", value != 0, abs(value) < 0.01 { return "< 0.01" }
        f.minimumFractionDigits = digits
        f.maximumFractionDigits = digits
        return f.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}

/// BTC rates from Yadio (`{"BTC":{"USD":…}}`), cached for 60 s — same source as the web wallet.
public actor RatesService {
    public static let shared = RatesService()
    public private(set) var rates: [String: Double]?
    private var fetchedAt: Date?
    private let endpoint = URL(string: "https://api.yadio.io/exrates/BTC")!

    public init(cached: [String: Double]? = nil) { rates = cached }

    @discardableResult
    public func refresh(force: Bool = false, session: URLSession = .shared) async -> [String: Double]? {
        if !force, let fetchedAt, Date().timeIntervalSince(fetchedAt) < 60 { return rates }
        var req = URLRequest(url: endpoint, timeoutInterval: 10)
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        guard let (data, _) = try? await session.data(for: req),
              let btc = try? JSONValue.parse(data)["BTC"], case .object(let obj) = btc else { return rates }
        let parsed = obj.compactMapValues(\.double)
        guard parsed["USD"] != nil else { return rates }
        rates = parsed
        fetchedAt = Date()
        return parsed
    }
}
