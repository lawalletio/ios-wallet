# CLAUDE.md

Native SwiftUI port of the LaWallet web wallet (`lawallet-nwc/apps/web/app/wallet`). The web app is the source of
truth for layout, copy and behavior — when changing a screen, read its web counterpart (`components/wallet/**`).

- Protocol logic lives in `Packages/LaWalletKit` (no UIKit). Add tests there first (`swift test`, Swift Testing).
- Money never moves through the REST API: payments, invoices, balance and history are NIP-47 over relays (`NWCClient`).
  REST (`LaWalletAPI`) is identity, settings, addresses, cards, remote wallets.
- NIP-98 `u` must be the instance's public `endpoint` setting + path + query; the payload hash covers the exact body bytes.
  `AppModel.validJWT()` exchanges NIP-98 for a 24 h JWT and re-mints 5 minutes before expiry.
- Copy: `t("ns.key", ["param": v])`. `Resources/*/wallet.json` is generated from the web i18n (do not hand-edit; re-export).
  iOS-only strings go in `ios*.json` for BOTH `en` and `es`. `LaWalletTests/L10nTests` fails on unknown keys.
- Icons are lucide SVGs in `Assets.xcassets/Icons` (`Icon("name")`), generated from the web's `lucide-react`.
- After adding files run `xcodegen generate`. Build with `-skipPackagePluginValidation`.
- Swift 6 strict concurrency: UI state is `@Observable @MainActor`; Kit types are `Sendable`/actors.

## Design language (Liquid Glass)

- Surfaces: `.lwSurface(r)` (26 cards, 22 grouped lists), controls/chrome `.lwGlass(in:)`, recessed wells `.lwInset()`.
  Never glass on glass — rows inside a surface are `RowDivider()`-separated. iOS 18–25 falls back to material automatically.
- Buttons: `.buttonStyle(.lw(...))` only; icon buttons `GlassIconButton`; segments `GlassSegmented`. Glass ignores
  `.opacity`, so disabled state is handled inside `LWButtonStyle` (tint dropped, label dimmed).
- Background: never paint a screen background — routes add `AmbientBackground` (isotype mint/sun/coral light).
  The only orchestrated motion is the payment bloom + the header pill morphing into the payment notice.
- Clear-filled shapes under glass are not hit-testable: add `.contentShape(...)` on anything that takes gestures.
- Labels are sentence case (no tracked ALL CAPS); hero numbers `LW.font(56–68, .semibold).tracking(-2).monospacedDigit()`.
