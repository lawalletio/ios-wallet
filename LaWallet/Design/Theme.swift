import SwiftUI

extension Color {
    init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "#", with: "")
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
        let v = UInt64(s, radix: 16) ?? 0
        self.init(.sRGB, red: Double(v >> 16 & 0xff) / 255, green: Double(v >> 8 & 0xff) / 255, blue: Double(v & 0xff) / 255)
    }
}

/// Dark-only tokens. Base ink from apps/web/app/globals.css; the three light colors are the LaWallet isotype's lobes.
/// Fills are translucent so every surface reads as glass over the ambient light (see Glass.swift).
enum LW {
    /// Opaque screen base under the ambient light.
    static let ink = Color(hex: "0a0a0a")
    // Isotype light.
    static let mint = Color(hex: "55b68c")
    static let sun = Color(hex: "fdc800")
    static let coral = Color(hex: "e95052")

    /// Recessed well (inputs, selected-off states). Not a screen background — use `lwScreenBackground()`.
    static let background = Color.black.opacity(0.30)
    static let foreground = Color(hex: "f5f5f5")
    /// Light frosted fill for secondary pieces that are not full glass (chips, avatars, icon tiles).
    static let card = Color.white.opacity(0.07)
    static let secondary = Color.white.opacity(0.12)
    static let border = Color.white.opacity(0.10)
    static let muted = Color.white.opacity(0.62)
    static let ring = Color.white.opacity(0.40)
    static let destructive = Color(hex: "e95052")
    static let destructiveText = Color(hex: "ff8a8c")
    static let incoming = Color(hex: "22c55e")
    static let outgoing = coral
    static let nwcPurple = Color(hex: "9b87ff")
    static let gold = sun

    static func font(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .custom("Inter", size: size).weight(weight)
    }
}

/// Brand accent preset (`apps/web/lib/client/theme-presets.ts`), picked from `settings.brand_theme`.
struct ThemePreset: Equatable, Sendable {
    let name: String
    let primary: Color
    let t200: Color
    let t300: Color
    let t400: Color

    static let presets: [(hex: String, preset: ThemePreset)] = [
        ("#f5f5f5", .init(name: "Neutral", primary: Color(hex: "f5f5f5"), t200: Color(hex: "404040"), t300: Color(hex: "404040"), t400: Color(hex: "a3a3a3"))),
        ("#22c55e", .green),
        ("#ec4899", .init(name: "Pink", primary: Color(hex: "ec4899"), t200: Color(hex: "9d174d"), t300: Color(hex: "be185d"), t400: Color(hex: "db2777"))),
        ("#f97316", .init(name: "Orange", primary: Color(hex: "f97316"), t200: Color(hex: "9a3412"), t300: Color(hex: "c2410c"), t400: Color(hex: "ea580c"))),
        ("#eab308", .init(name: "Yellow", primary: Color(hex: "eab308"), t200: Color(hex: "854d0e"), t300: Color(hex: "a16207"), t400: Color(hex: "ca8a04"))),
        ("#3b82f6", .init(name: "Blue", primary: Color(hex: "3b82f6"), t200: Color(hex: "1e40af"), t300: Color(hex: "1d4ed8"), t400: Color(hex: "2563eb"))),
        ("#8b5cf6", .init(name: "Violet", primary: Color(hex: "8b5cf6"), t200: Color(hex: "5b21b6"), t300: Color(hex: "6d28d9"), t400: Color(hex: "7c3aed"))),
        ("#a855f7", .init(name: "Purple", primary: Color(hex: "a855f7"), t200: Color(hex: "6b21a8"), t300: Color(hex: "7e22ce"), t400: Color(hex: "9333ea")))
    ]

    static let green = ThemePreset(name: "Green", primary: Color(hex: "22c55e"), t200: Color(hex: "166534"), t300: Color(hex: "15803d"), t400: Color(hex: "16a34a"))

    static func from(brandTheme: String?) -> ThemePreset {
        guard let raw = brandTheme?.lowercased() else { return .green }
        return presets.first { $0.hex == raw || $0.preset.name.lowercased() == raw }?.preset ?? .green
    }

    var gradient: LinearGradient { LinearGradient(colors: [t200, t400], startPoint: .top, endPoint: .bottom) }
}

struct Theme: Equatable, Sendable {
    var preset: ThemePreset = .green
    /// `brand_rounding`: none 0, small 6, medium 12, full 24.
    var radius: CGFloat = 12

    static func from(_ settings: (theme: String?, rounding: String?)) -> Theme {
        let r: CGFloat = switch settings.rounding?.lowercased() {
        case "none": 0
        case "small": 6
        case "full": 24
        default: 12
        }
        return Theme(preset: .from(brandTheme: settings.theme), radius: r)
    }
}

private struct ThemeKey: EnvironmentKey { static let defaultValue = Theme() }

extension EnvironmentValues {
    var theme: Theme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}
