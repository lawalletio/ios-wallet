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
                            .listRowBackground(LW.card)
                    } header: { header(t("\(l).activeAssets")) } footer: {
                        Text(t("\(l).hint")).font(LW.font(12)).foregroundStyle(LW.muted).multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity).padding(.top, 4)
                    }

                    Section {
                        HStack(spacing: 8) {
                            Icon("search", size: 16).foregroundStyle(LW.muted)
                            TextField(t("\(l).searchPlaceholder"), text: $query)
                                .font(LW.font(15)).autocorrectionDisabled().textInputAutocapitalization(.never)
                        }
                        .padding(.horizontal, 12).frame(height: 44).background(LW.card)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                    }

                    Section {
                        if available.isEmpty {
                            Text(t("\(l).noMatch")).font(LW.font(14)).foregroundStyle(LW.muted).frame(maxWidth: .infinity).padding(.vertical, 24)
                                .listRowBackground(LW.card.opacity(0.4))
                        } else {
                            ForEach(available) { c in availableRow(c) }.listRowBackground(LW.card)
                        }
                    } header: { header(t("\(l).available")) }
                }
                .listStyle(.insetGrouped)
                .listSectionSpacing(24)
                .scrollContentBackground(.hidden)
                .contentMargins(.bottom, 140, for: .scrollContent)
                .scrollDismissesKeyboard(.immediately)
            }
            SettingsTabbar()
        }
    }

    private func header(_ text: String) -> some View {
        Text(text).font(LW.font(14, .medium)).foregroundStyle(LW.muted).textCase(nil).padding(.leading, -12)
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
                Icon("lock", size: 16).foregroundStyle(LW.muted).frame(width: 36, height: 36).background(LW.secondary)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .accessibilityLabel(t("\(l).alwaysActive"))
            } else {
                Button { app.currencies.setActive(app.currencies.active.filter { $0 != c.code }) } label: {
                    Icon("minus", size: 16).foregroundStyle(Color(hex: "fef2f2")).frame(width: 36, height: 36).background(LW.destructive.opacity(0.9))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(t("\(l).remove", ["name": name(c)]))
                .accessibilityIdentifier("currencies.remove.\(c.code)")
            }
            avatar(c)
            label(c)
            if c.locked {
                Text(t("\(l).alwaysActive")).font(LW.font(11)).foregroundStyle(LW.muted)
            } else {
                Icon("grip-vertical", size: 16).foregroundStyle(LW.muted).frame(width: 36, height: 36)
                    .accessibilityLabel(t("\(l).reorder", ["name": name(c)]))
            }
        }
        .frame(height: 64)
        .listRowInsets(EdgeInsets(top: 0, leading: 12, bottom: 0, trailing: 12))
    }

    private func availableRow(_ c: Currency) -> some View {
        HStack(spacing: 12) {
            Button { app.currencies.setActive(app.currencies.active + [c.code]) } label: {
                Icon("plus", size: 16).foregroundStyle(LW.foreground).frame(width: 36, height: 36).background(LW.secondary)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(t("\(l).add", ["name": name(c)]))
            .accessibilityIdentifier("currencies.add.\(c.code)")
            avatar(c)
            label(c)
        }
        .frame(height: 64)
        .listRowInsets(EdgeInsets(top: 0, leading: 12, bottom: 0, trailing: 12))
    }

    private func avatar(_ c: Currency) -> some View {
        Text(c.code.prefix(3)).font(LW.font(11, .semibold)).tracking(1).foregroundStyle(LW.muted)
            .frame(width: 36, height: 36).background(LW.background).clipShape(RoundedRectangle(cornerRadius: 6))
            .accessibilityHidden(true)
    }

    private func label(_ c: Currency) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(name(c)).font(LW.font(14, .medium)).lineLimit(1)
            Text(c.code).font(LW.font(12)).foregroundStyle(LW.muted)
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
            Text(t("ios.instance.subtitle")).font(LW.font(14)).foregroundStyle(LW.muted)

            SettingsSection(t("ios.instance.current")) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        SettingsIsotype(size: 40)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(app.communityName).font(LW.font(16, .semibold))
                            Text(app.instanceURL.host() ?? app.instanceURL.absoluteString).font(LW.font(14)).foregroundStyle(LW.muted)
                        }
                    }
                    if app.endpoint != app.instanceURL {
                        Text(app.endpoint.absoluteString).font(.system(size: 12, design: .monospaced)).foregroundStyle(LW.muted)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16).background(LW.card).clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
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
                    .buttonStyle(.lw(.outline))
                    .disabled(busy || app.instanceURL == AppModel.defaultInstance)
                    .accessibilityIdentifier("instance.reset")
            }

            Text(t("ios.instance.note")).font(LW.font(12)).foregroundStyle(LW.muted)
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
