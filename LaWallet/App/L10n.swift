import Foundation

/// Wallet copy, ported verbatim from apps/web/lib/client/i18n (`wallet.json`) plus iOS-only keys (`ios.json`).
/// Interpolation uses `{name}` placeholders.
final class L10n: @unchecked Sendable {
    static let shared = L10n()
    static let supported = ["en", "es"]
    static let languageKey = "lawallet-locale"

    private var table: [String: String] = [:]
    private var fallback: [String: String] = [:]
    private let lock = NSLock()
    private(set) var locale = "en"

    init() { load(Self.resolvedLocale()) }

    /// Explicit choice from Settings → Language, else the first supported preferred language.
    static func resolvedLocale() -> String {
        if let saved = UserDefaults.standard.string(forKey: languageKey), supported.contains(saved) { return saved }
        let preferred = Locale.preferredLanguages.map { String($0.prefix(2)) }
        return preferred.first(where: supported.contains) ?? "en"
    }

    func load(_ locale: String) {
        let next = Self.read(locale)
        let en = locale == "en" ? next : Self.read("en")
        lock.withLock {
            self.locale = locale
            table = next
            fallback = en
        }
    }

    private static func read(_ locale: String) -> [String: String] {
        var out: [String: String] = [:]
        for name in ["wallet", "ios", "ios-onboarding", "ios-payments", "ios-settings"] {
            guard let url = Bundle.main.url(forResource: name, withExtension: "json", subdirectory: nil, localization: locale)
                ?? Bundle.main.url(forResource: name, withExtension: "json", subdirectory: "\(locale).lproj"),
                let data = try? Data(contentsOf: url),
                let dict = try? JSONDecoder().decode([String: String].self, from: data) else { continue }
            out.merge(dict) { _, new in new }
        }
        return out
    }

    func string(_ key: String, _ args: [String: String] = [:]) -> String {
        var s = lock.withLock { table[key] ?? fallback[key] } ?? key
        for (k, v) in args { s = s.replacingOccurrences(of: "{\(k)}", with: v) }
        return s
    }

    func has(_ key: String) -> Bool { lock.withLock { table[key] != nil } }
}

func t(_ key: String, _ args: [String: String] = [:]) -> String { L10n.shared.string(key, args) }
