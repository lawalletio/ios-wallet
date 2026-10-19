import LaWalletKit
import SwiftUI

@main
struct LaWalletApp: App {
    @State private var app: AppModel
    @Environment(\.scenePhase) private var phase

    init() {
        Notifier.registerBackgroundRefresh()
        if ProcessInfo.processInfo.arguments.contains("-uitest-reset") {
            Keychain.wipe()
            UserDefaults.standard.removePersistentDomain(forName: Bundle.main.bundleIdentifier ?? "")
        }
        if let instance = ProcessInfo.processInfo.environment["LAWALLET_INSTANCE"] {
            UserDefaults.standard.set(instance, forKey: AppModel.instanceKey)
            UserDefaults.standard.removeObject(forKey: AppModel.settingsCacheKey)
        }
        // Built after the launch overrides above so it reads the right instance.
        _app = State(initialValue: AppModel())
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
                .environment(\.theme, app.theme)
                .preferredColorScheme(.dark)
                .tint(app.theme.preset.primary)
                .task { await app.bootstrap() }
                .onOpenURL { url in Task { await handle(url) } }
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                    if let url = activity.webpageURL { Task { await handle(url) } }
                }
        }
        .onChange(of: phase) { _, p in
            switch p {
            case .active:
                Task {
                    await app.wallet.refreshBalance()
                    await app.currencies.refreshRates()
                }
            case .background: Notifier.schedule()
            default: break
            }
        }
    }

    /// `lightning:` / `lnurlw:` / `https://<instance>/wallet/activate/<id>` deep links.
    @MainActor private func handle(_ url: URL) async {
        var text = url.absoluteString
        if url.scheme == "lawallet", let q = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "q" })?.value {
            text = q
        }
        if !app.isAuthenticated {
            if let link = ActivationLink.parse(text) { app.pendingActivation = (link.tokenId, Date()) }
            return
        }
        _ = await ScanRouter.route(text, app: app)
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        ZStack(alignment: .top) {
            LW.ink.ignoresSafeArea()
            if !app.bootstrapped {
                LoadingScreen()
            } else if app.isAuthenticated {
                if app.showWelcome { WelcomeScreen() } else { AuthenticatedRoot() }
            } else {
                OnboardingRoot()
            }
            if let toast = app.toast {
                ToastView(toast: toast).transition(.move(edge: .top).combined(with: .opacity)).padding(.top, 8).zIndex(10)
            }
        }
        .animation(.spring(duration: 0.3), value: app.toast)
        .font(LW.font(16))
        .foregroundStyle(LW.foreground)
        .id(app.localeVersion)
    }
}

struct AuthenticatedRoot: View {
    @Environment(AppModel.self) private var app
    var body: some View {
        @Bindable var app = app
        NavigationStack(path: $app.path) {
            HomeScreen()
                .navigationDestination(for: Route.self) { route in
                    route.view.toolbar(.hidden, for: .navigationBar).lwScreenBackground(route.ambientIntensity)
                }
        }
        .task(id: app.isAuthenticated) {
            // Resume a card activation that started while signed out (1 h TTL).
            if let pending = app.pendingActivation, Date().timeIntervalSince(pending.at) < 3600 {
                app.pendingActivation = nil
                app.navigate(.activate(pending.id))
            }
        }
    }
}

struct OnboardingRoot: View {
    @State private var path = NavigationPath()
    @Environment(AppModel.self) private var app
    var body: some View {
        NavigationStack(path: $path) {
            LandingScreen(path: $path)
                .lwScreenBackground(1)
                .navigationDestination(for: AuthRoute.self) { route in
                    route.view.toolbar(.hidden, for: .navigationBar).lwScreenBackground(route.ambientIntensity)
                }
        }
        .environment(\.authPath, $path)
        .task {
            if let pending = app.pendingActivation, Date().timeIntervalSince(pending.at) < 3600 { path.append(AuthRoute.activate(pending.id)) }
        }
    }
}

private struct AuthPathKey: EnvironmentKey { static var defaultValue: Binding<NavigationPath> { .constant(NavigationPath()) } }
extension EnvironmentValues {
    /// Onboarding stack path (signed-out screens push `AuthRoute`s on it).
    var authPath: Binding<NavigationPath> {
        get { self[AuthPathKey.self] }
        set { self[AuthPathKey.self] = newValue }
    }
}

struct LoadingScreen: View {
    var body: some View {
        VStack(spacing: 28) {
            Image("isotypo").resizable().scaledToFit().frame(height: 58)
                .frame(width: 112, height: 112)
                .lwGlass(in: RoundedRectangle(cornerRadius: LW.Radius.sheet, style: .continuous))
                .shadow(color: LW.mint.opacity(0.35), radius: 40)
            ProgressView().tint(LW.foreground.opacity(0.6))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AmbientBackground(intensity: 1))
        .accessibilityIdentifier("loading")
    }
}
