import LaWalletKit
import SwiftUI

// MARK: currencies (settings/currencies-screen.tsx)

struct CurrenciesScreen: View {
    @Environment(AppModel.self) private var app
    @State private var query = ""
    private let l = "settings.currenciesScreen"

    private var active: [Currency] { app.currencies.active.compactMap(Currencies.currency) }
    private var available: [Currency] {
        let term = query.trimmedValue.lowercased()
        return Currencies.catalog.filter { c in
            !app.currencies.active.contains(c.code)
                && (term.isEmpty || c.code.lowercased().contains(term) || c.name.lowercased().contains(term) || name(c).lowercased().contains(term))
        }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                PillHeader(title: t("\(l).title"))
                List {
                    Section {
                        // iOS 16+: long-press a row to drag it; SAT stays pinned first (`normalize` + moveDisabled).
                        ForEach(active) { c in activeRow(c).moveDisabled(c.locked) }
                            .onMove { from, to in
                                var codes = app.currencies.active
                                codes.move(fromOffsets: from, toOffset: to)
                                app.currencies.setActive(codes)
                            }
                            .listRowBackground(Self.rowGlass)
                    } header: { header(t("\(l).activeAssets")) } footer: {
                        Text(t("\(l).hint")).font(LW.font(13)).foregroundStyle(LW.muted).multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity).padding(.top, 6)
                    }

                    Section {
                        HStack(spacing: 10) {
                            Icon("search", size: 16).foregroundStyle(LW.muted)
                            TextField("", text: $query, prompt: Text(verbatim: t("\(l).searchPlaceholder")).foregroundStyle(LW.muted.opacity(0.8)))
                                .font(LW.font(16)).foregroundStyle(LW.foreground)
                                .autocorrectionDisabled().textInputAutocapitalization(.never)
                        }
                        .padding(.horizontal, 16).frame(minHeight: 54)
                        .lwGlass(in: RoundedRectangle(cornerRadius: LW.Radius.control, style: .continuous))
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                    }

                    Section {
                        if available.isEmpty {
                            Text(t("\(l).noMatch")).font(LW.font(14)).foregroundStyle(LW.muted).frame(maxWidth: .infinity).padding(.vertical, 24)
                                .listRowBackground(Self.rowGlass)
                        } else {
                            ForEach(available) { c in availableRow(c) }.listRowBackground(Self.rowGlass)
                        }
                    } header: { header(t("\(l).available")) }
                }
                .listStyle(.insetGrouped)
                .listSectionSpacing(24)
                .scrollContentBackground(.hidden)
                .scrollIndicators(.hidden)
                .lwSoftScrollEdges()
                .contentMargins(.bottom, 150, for: .scrollContent)
                .scrollDismissesKeyboard(.immediately)
            }
            SettingsTabbar()
        }
    }

    /// `List` keeps native drag-to-reorder, so its sections can't be one glass shape; each row gets the glass fallback
    /// material instead (the list clips the section into a single rounded surface, so there are no seams).
    private static var rowGlass: some View { Rectangle().fill(.ultraThinMaterial) }

    private func header(_ text: String) -> some View {
        Text(text).font(LW.font(14, .semibold)).foregroundStyle(LW.muted).textCase(nil).padding(.leading, -12)
    }

    /// Native currency name in the UI language (`Intl.DisplayNames`); catalog name for SAT/BTC.
    private func name(_ c: Currency) -> String {
        guard c.code != "SAT", c.code != "BTC", let n = Locale(identifier: app.language).localizedString(forCurrencyCode: c.code), n != c.code
        else { return c.name }
        return n.prefix(1).uppercased() + n.dropFirst()
    }

    private func activeRow(_ c: Currency) -> some View {
        HStack(spacing: 12) {
            if c.locked {
                tile(Icon("lock", size: 15).foregroundStyle(LW.muted), Color.white.opacity(0.08))
                    .accessibilityLabel(t("\(l).alwaysActive"))
            } else {
                Button { app.currencies.setActive(app.currencies.active.filter { $0 != c.code }) } label: {
                    tile(Icon("minus", size: 16).foregroundStyle(LW.destructiveText), LW.coral.opacity(0.18))
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(t("\(l).remove", ["name": name(c)]))
                .accessibilityIdentifier("currencies.remove.\(c.code)")
            }
            avatar(c)
            label(c)
            if c.locked {
                Text(t("\(l).alwaysActive")).font(LW.font(12)).foregroundStyle(LW.muted)
            } else {
                Icon("grip-vertical", size: 16).foregroundStyle(LW.muted.opacity(0.8)).frame(width: 36, height: 36)
                    .accessibilityLabel(t("\(l).reorder", ["name": name(c)]))
            }
        }
        .frame(height: 64)
        .listRowInsets(EdgeInsets(top: 0, leading: 14, bottom: 0, trailing: 12))
        .listRowSeparatorTint(Color.white.opacity(0.08))
    }

    private func availableRow(_ c: Currency) -> some View {
        HStack(spacing: 12) {
            Button { app.currencies.setActive(app.currencies.active + [c.code]) } label: {
                tile(Icon("plus", size: 16).foregroundStyle(LW.foreground), Color.white.opacity(0.10))
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(t("\(l).add", ["name": name(c)]))
            .accessibilityIdentifier("currencies.add.\(c.code)")
            avatar(c)
            label(c)
        }
        .frame(height: 64)
        .listRowInsets(EdgeInsets(top: 0, leading: 14, bottom: 0, trailing: 12))
        .listRowSeparatorTint(Color.white.opacity(0.08))
    }

    private func tile(_ icon: some View, _ fill: Color) -> some View {
        icon.frame(width: 36, height: 36).background(fill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func avatar(_ c: Currency) -> some View {
        Text(c.code.prefix(3)).font(LW.font(11, .semibold)).foregroundStyle(LW.foreground.opacity(0.8))
            .frame(width: 36, height: 36).background(Color.white.opacity(0.06), in: Circle())
            .accessibilityHidden(true)
    }

    private func label(_ c: Currency) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(name(c)).font(LW.font(15, .medium)).foregroundStyle(LW.foreground).lineLimit(1)
            Text(c.code).font(LW.font(13)).foregroundStyle(LW.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: language (settings/language-screen.tsx)

struct LanguageScreen: View {
    @Environment(AppModel.self) private var app
    @AppStorage(L10n.languageKey) private var preference: String?
    private static let names = ["en": "English", "es": "Español"]

    var body: some View {
        let device = Locale.preferredLanguages.map { String($0.prefix(2)) }.first(where: L10n.supported.contains) ?? "en"
        SettingsPage(title: t("settings.language")) {
            GroupBox {
                SettingsChoiceRow(title: t("settings.languageScreen.automatic"),
                                  subtitle: t("settings.languageScreen.automaticHint", ["name": Self.names[device] ?? device]),
                                  checked: preference == nil) { choose(nil) }
                    .accessibilityIdentifier("language.auto")
                ForEach(L10n.supported, id: \.self) { code in
                    RowDivider()
                    SettingsChoiceRow(title: Self.names[code] ?? code, checked: preference == code) { choose(code) }
                        .accessibilityIdentifier("language.\(code)")
                }
            }
        }
    }

    private func choose(_ code: String?) {
        preference = code
        app.language = L10n.resolvedLocale()
    }
}

// MARK: payment sound (settings/payment-sound-screen.tsx)

struct PaymentSoundScreen: View {
    @Environment(AppModel.self) private var app
    private let s = "settings.paymentSoundScreen"

    var body: some View {
        SettingsPage(title: t("settings.paymentSound")) {
            GroupBox(label: t("\(s).successful")) {
                ForEach(Array(["chime", "bananero", "off"].enumerated()), id: \.element) { i, id in
                    if i > 0 { RowDivider() }
                    SettingsChoiceRow(title: t("\(s).sounds.\(id).label"), subtitle: t("\(s).sounds.\(id).description"),
                                      checked: app.paymentSound == id) {
                        app.paymentSound = id
                        SoundPlayer.play(id)
                    }
                    .accessibilityIdentifier("sound.\(id)")
                }
            }
            .accessibilityLabel(t("\(s).radioLabel"))
        }
    }
}

// MARK: instance (iOS-only)

/// Which LaWallet community server the app talks to. Reachable signed-out (`AuthRoute.instance`) and from Settings.
struct InstanceScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var url = ""
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        SettingsPage(title: t("ios.instance.title"), tabbar: app.isAuthenticated) {
            Text(t("ios.instance.subtitle")).font(LW.font(15)).foregroundStyle(LW.muted).padding(.horizontal, 6)

            SettingsSection(t("ios.instance.current")) {
                HStack(spacing: 14) {
                    SettingsIconTile(icon: "globe", color: LW.mint, size: 46)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(app.instanceURL.host() ?? app.instanceURL.absoluteString).font(LW.font(20, .semibold)).foregroundStyle(LW.foreground)
                            .lineLimit(1).truncationMode(.middle)
                        Text(app.communityName).font(LW.font(14)).foregroundStyle(LW.muted).lineLimit(1)
                        if app.endpoint != app.instanceURL {
                            Text(app.endpoint.absoluteString).font(.system(size: 12, design: .monospaced)).foregroundStyle(LW.muted)
                                .lineLimit(1).truncationMode(.middle)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(18)
                .lwSurface()
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("instance.current")
            }

            VStack(spacing: 12) {
                LWTextField(placeholder: t("ios.instance.placeholder"), text: $url)
                    .keyboardType(.URL)
                    .submitLabel(.go)
                    .onSubmit { Task { await go(url) } }
                    .accessibilityIdentifier("instance.field")
                ErrorText(message: error)
                GlassGroup(spacing: 10) {
                    VStack(spacing: 6) {
                        Button { Task { await go(url) } } label: {
                            HStack(spacing: 8) {
                                if busy { ProgressView().tint(LW.foreground) }
                                Text(t("ios.instance.switch"))
                            }
                        }
                        .buttonStyle(.lw(.theme))
                        .disabled(busy || url.trimmedValue.isEmpty)
                        .accessibilityIdentifier("instance.switch")
                        Button(t("ios.instance.reset")) { Task { await go(AppModel.defaultInstance.absoluteString) } }
                            .buttonStyle(.lw(.ghost, height: 44))
                            .disabled(busy || app.instanceURL == AppModel.defaultInstance)
                            .accessibilityIdentifier("instance.reset")
                    }
                }
            }

            Text(t("ios.instance.note")).font(LW.font(13)).foregroundStyle(LW.muted).padding(.horizontal, 6)
        }
    }

    private func go(_ raw: String) async {
        guard !busy, !raw.trimmedValue.isEmpty else { return }
        busy = true
        error = nil
        defer { busy = false }
        do {
            try await app.switchInstance(to: raw)
            app.show(.success, t("ios.instance.switched", ["name": app.communityName]))
            dismiss()
        } catch {
            self.error = error.localizedDescription
            Haptics.error()
        }
    }
}
