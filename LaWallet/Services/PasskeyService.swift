import AuthenticationServices
import LaWalletKit

/// Passkey ↔ Nostr identity via WebAuthn PRF (`apps/web/lib/client/passkey-api.ts`). rpId = instance endpoint host.
/// Interface is fixed; the onboarding feature fills in the implementation.
@MainActor
final class PasskeyService {
    static let shared = PasskeyService()

    /// PRF needs iOS 18+ and a platform authenticator.
    static var isSupported: Bool { true }

    /// Signup: registers a passkey, derives the nsec from its PRF output and signs in (`login(keys:method:.passkey)`).
    func createAccount(app: AppModel) async throws { throw APIError(status: 0, message: "Not implemented") }

    /// Login: discoverable assertion with PRF → derived nsec → sign in.
    func login(app: AppModel) async throws { throw APIError(status: 0, message: "Not implemented") }

    /// Settings → Security: link an extra passkey to the signed-in account (authenticated registration).
    func addToCurrentAccount(app: AppModel, label: String?) async throws { throw APIError(status: 0, message: "Not implemented") }
}
