import AuthenticationServices
import CryptoKit
import LaWalletKit
import UIKit

/// `PasskeyErrorKind` from `apps/web/lib/client/passkey-api.ts`. Local kinds are localized; server text (`fromServer`) shows verbatim.
enum PasskeyError: LocalizedError, Equatable {
    case cancelled, unsupported, prfUnsupported
    /// nil = local InvalidState (localized); otherwise the server's 409 text.
    case duplicate(String?)
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .cancelled: t("auth.passkeyErrors.cancelled")
        case .unsupported: t("auth.passkeyErrors.unsupported")
        case .prfUnsupported: t("auth.passkeyErrors.prf-unsupported")
        case .duplicate(let m): m ?? t("auth.passkeyErrors.duplicate")
        case .failed(let m): m
        }
    }

    var isDuplicate: Bool { if case .duplicate = self { true } else { false } }

    static func from(_ error: Error) -> PasskeyError {
        if let e = error as? PasskeyError { return e }
        if let e = error as? APIError { return e.status == 409 ? .duplicate(e.message) : .failed(e.message) }
        if let e = error as? ASAuthorizationError {
            switch e.code {
            case .canceled: return .cancelled
            case .matchedExcludedCredential: return .duplicate(nil)
            case .notHandled: return .unsupported
            default: return .failed(e.localizedDescription)
            }
        }
        return .failed(error.localizedDescription)
    }
}

/// Passkey ↔ Nostr identity via WebAuthn PRF (`apps/web/lib/client/passkey-api.ts`). rpId = instance endpoint host.
@MainActor
final class PasskeyService {
    static let shared = PasskeyService()

    /// PRF needs iOS 18+ (the deployment target) and a platform authenticator.
    static var isSupported: Bool { true }

    /// Signup: registers a passkey, derives the nsec from its PRF output and signs in (`login(keys:method:.passkey)`).
    func createAccount(app: AppModel) async throws {
        let keys = try await register(app: app, label: nil, authenticated: false)
        try await app.login(keys: keys, method: .passkey)
    }

    /// Login: discoverable assertion with PRF → derived nsec → sign in.
    func login(app: AppModel) async throws {
        let prf: Data
        do {
            prf = try await prfAssertion(rpId: rpId(app), credentialID: nil)
        } catch { throw PasskeyError.from(error) }
        try await app.login(keys: try derive(prf), method: .passkey)
    }

    /// Settings → Security: link an extra passkey to the signed-in account (authenticated registration).
    /// Mirrors `linkPasskey`: the passkey derives its OWN key, which proves itself and is linked as a secondary identity.
    func addToCurrentAccount(app: AppModel, label: String?) async throws {
        _ = try await register(app: app, label: label, authenticated: true)
    }

    // MARK: ceremonies

    private func rpId(_ app: AppModel) -> String { app.endpoint.host() ?? "" }

    private func derive(_ prf: Data) throws -> NostrKeys {
        do { return try NostrKeys(secret: PasskeyPRF.deriveSecret(prfOutput: prf)) } catch { throw PasskeyError.failed(t("ios.common.error")) }
    }

    /// `runRegistrationCeremony`: create (asking for PRF at creation) → pinned PRF assertion if needed → derive → prove → verify.
    private func register(app: AppModel, label: String?, authenticated: Bool) async throws -> NostrKeys {
        do {
            let options = try await app.api.passkeyRegistrationOptions(authenticated: authenticated)
            guard let challengeB64 = options["challenge"]?.string, let challenge = Data(base64URL: challengeB64),
                  let userB64 = options["user"]?["id"]?.string, let userID = Data(base64URL: userB64)
            else { throw PasskeyError.failed(t("ios.common.error")) }
            let rp = options["rp"]?["id"]?.string ?? rpId(app)
            let provider = ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier: rp)
            let request = provider.createCredentialRegistrationRequest(challenge: challenge, name: options["user"]?["name"]?.string ?? "lawallet",
                                                                        userID: userID)
            request.userVerificationPreference = .required
            request.prf = .inputValues(.saltInput1(PasskeyPRF.salt))

            let reg = try await AuthorizationRunner().run(request)
            // Only an explicit "unsupported" with no output is conclusive (same rule as the web).
            if reg.prfSupported == false && reg.prf == nil { throw PasskeyError.prfUnsupported }
            var prf = reg.prf
            if prf == nil { prf = try await prfAssertion(rpId: rp, credentialID: reg.credentialID) }
            guard let prf, let attestation = reg.attestationObject else { throw PasskeyError.prfUnsupported }
            let keys = try derive(prf)

            let proof = try await KeyProof.sign(challenge: challengeB64, signer: LocalSigner(keys: keys))
            let credID = reg.credentialID.base64URL
            var body: [String: JSONValue] = [
                "challenge": .string(challengeB64),
                "credential": [
                    "id": .string(credID),
                    "rawId": .string(credID),
                    "type": "public-key",
                    "response": [
                        "clientDataJSON": .string(reg.clientDataJSON.base64URL),
                        "attestationObject": .string(attestation.base64URL),
                        "transports": ["internal", "hybrid"]
                    ],
                    // The PRF output IS the key material — only `enabled` goes to the server.
                    "clientExtensionResults": ["prf": ["enabled": true]],
                    "authenticatorAttachment": .string(reg.crossPlatform ? "cross-platform" : "platform")
                ],
                "pubkey": .string(keys.publicKey),
                "proof": try JSONValue.parse(Data(proof.json.utf8))
            ]
            if let label = label?.trimmingCharacters(in: .whitespaces), !label.isEmpty { body["label"] = .string(label) }
            try await app.api.verifyPasskeyRegistration(.object(body), authenticated: authenticated)
            return keys
        } catch {
            throw PasskeyError.from(error)
        }
    }

    /// `getPrfAssertion`: local-randomness challenge (PRF depends only on credential + salt). nil credential = discoverable picker.
    private func prfAssertion(rpId: String, credentialID: Data?) async throws -> Data {
        let provider = ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier: rpId)
        let request = provider.createCredentialAssertionRequest(challenge: Data.random(32))
        request.userVerificationPreference = .required
        if let credentialID { request.allowedCredentials = [ASAuthorizationPlatformPublicKeyCredentialDescriptor(credentialID: credentialID)] }
        request.prf = .inputValues(.saltInput1(PasskeyPRF.salt))
        let result = try await AuthorizationRunner().run(request)
        guard let prf = result.prf else { throw PasskeyError.prfUnsupported }
        return prf
    }
}

/// What we need from an `ASAuthorization`, extracted on the main actor so nothing non-Sendable crosses the continuation.
private struct CeremonyResult: Sendable {
    let credentialID: Data
    let clientDataJSON: Data
    var attestationObject: Data?
    var prf: Data?
    var prfSupported: Bool?
    var crossPlatform = false
}

/// One-shot `ASAuthorizationController` wrapped in a continuation. Kept alive by the awaiting caller.
@MainActor
private final class AuthorizationRunner: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    private var continuation: CheckedContinuation<CeremonyResult, Error>?
    private var controller: ASAuthorizationController?

    func run(_ request: ASAuthorizationRequest) async throws -> CeremonyResult {
        try await withCheckedThrowingContinuation { cont in
            continuation = cont
            let c = ASAuthorizationController(authorizationRequests: [request])
            c.delegate = self
            c.presentationContextProvider = self
            controller = c
            c.performRequests()
        }
    }

    private func finish(_ result: Result<CeremonyResult, Error>) {
        continuation?.resume(with: result)
        continuation = nil
        controller = nil
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        switch authorization.credential {
        case let r as ASAuthorizationPlatformPublicKeyCredentialRegistration:
            finish(.success(CeremonyResult(credentialID: r.credentialID, clientDataJSON: r.rawClientDataJSON, attestationObject: r.rawAttestationObject,
                                           prf: r.prf?.first.map(\.data), prfSupported: r.prf?.isSupported,
                                           crossPlatform: r.attachment == .crossPlatform)))
        case let a as ASAuthorizationPlatformPublicKeyCredentialAssertion:
            finish(.success(CeremonyResult(credentialID: a.credentialID, clientDataJSON: a.rawClientDataJSON, prf: a.prf?.first.data)))
        default:
            finish(.failure(PasskeyError.unsupported))
        }
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        finish(.failure(error))
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        let windows = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows)
        return windows.first(where: \.isKeyWindow) ?? windows.first ?? ASPresentationAnchor()
    }
}

private extension SymmetricKey {
    var data: Data { withUnsafeBytes { Data($0) } }
}

private extension Data {
    init?(base64URL s: String) {
        var b64 = s.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        b64 += String(repeating: "=", count: (4 - b64.count % 4) % 4)
        self.init(base64Encoded: b64)
    }

    var base64URL: String {
        base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
}
