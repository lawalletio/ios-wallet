# LaWallet for iOS

Native SwiftUI wallet for [LaWallet NWC](https://github.com/lawalletio/lawallet-nwc) communities: a Lightning address,
a Nostr identity and a Nostr Wallet Connect (NIP-47) wallet in your pocket. It is a 1:1 port of the web wallet at
`/wallet` and talks to **beta.lawallet.io** by default; any LaWallet instance can be selected in **Settings → Instance**.

## Features

- Create an account from scratch (random key, passkey) or log in (nsec, passkey, NIP-46 bunker / nostrconnect QR)
- Courtesy NWC wallet assigned by the instance (LNCurl), plus your own NWC remote wallets (add, primary, enable/disable,
  forwarding rules, webhook/Nostr notification rules)
- Send to Lightning addresses, LNURL-pay and BOLT11 invoices (swipe to pay), with saved contacts
- Receive via Lightning address QR or amount invoices; card tap-to-pay on the invoice screen (NFC)
- Scan QR: invoices, addresses, LNURL-pay, LNURL-withdraw (LUD-03 claim) and card activation links
- NFC Bolt Card claim (LUD-03), card activation via QR, card management
- Realtime balance and activity via NIP-47 notifications + local notifications (background refresh when suspended)
- Lightning address claim (free or paid LUD-21 flow), nsec backup, multi-currency display (Yadio rates)
- English / Español, payment sounds, instance branding (theme color + rounding)

## Layout

```
Packages/LaWalletKit   Protocol layer (pure Swift, `swift test` on macOS): NIP-01/04/19/44/46/47/98,
                       BOLT11, LNURL (LUD-03/06/12/16/21), REST client for the LaWallet API, SSE, currencies
LaWallet/              SwiftUI app (App, Design, Features/*, Services, Resources)
LaWalletTests/         App unit tests        LaWalletUITests/   XCUITest flows
project.yml            xcodegen spec (LaWallet.xcodeproj is generated and committed)
```

## Build

Requirements: Xcode 26+, iOS 18+ simulator/device, `brew install xcodegen`.

```bash
xcodegen generate
xcodebuild -project LaWallet.xcodeproj -scheme LaWallet -destination 'platform=iOS Simulator,name=iPhone 17' \
  -skipPackagePluginValidation build
```

`-skipPackagePluginValidation` is needed because `swift-secp256k1` ships a build plugin.

## Test

```bash
# protocol layer (vectors for NIP-44, NIP-19, BOLT11, LNURL, passkey PRF derivation…)
cd Packages/LaWalletKit && swift test

# live end-to-end: new account → address → NWC wallet → invoice → real payment + NIP-47 notification
LAWALLET_E2E_URL=https://beta.lawallet.io \
LAWALLET_E2E_NWC=$(curl -s -X POST "https://faucet.nwc.dev?balance=1000") \
LAWALLET_E2E_PAYER_NWC=$(curl -s -X POST "https://faucet.nwc.dev?balance=1000") \
swift test --filter IntegrationTests

# app unit + UI tests
xcodebuild test -project LaWallet.xcodeproj -scheme LaWallet -destination 'platform=iOS Simulator,name=iPhone 17' \
  -skipPackagePluginValidation
```

UI tests run against `LAWALLET_UITEST_INSTANCE` (default `http://localhost:3774`, a local
`pnpm start:dev-server` of lawallet-nwc). To make local signups receive a funded test wallet, point the instance's
LNCurl server at the Alby NWC faucet: setting `lncurl_server_url=https://faucet.nwc.dev?balance=2100`.

## Passkeys, NFC and associated domains

Passkeys derive the Nostr key from the WebAuthn PRF extension exactly like the web (`lawallet-nsec-prf-v1`), so the same
passkey opens the same account on web and iOS. They require:

1. a real Apple Developer Team ID in `project.yml` (`DEVELOPMENT_TEAM`), and
2. the instance to serve `/.well-known/apple-app-site-association` listing `<TEAMID>.io.lawallet.wallet`
   (lawallet-nwc: `APPLE_APP_IDS` env).

NFC (Bolt Card reading) needs a physical iPhone and the NFC entitlement on that team.

## License

MIT
