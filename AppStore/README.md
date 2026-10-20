# App Store release

Everything needed to ship LaWallet to TestFlight and the App Store. The listing text lives in `metadata/`, laid out the
way `fastlane deliver` expects (`metadata/<locale>/name.txt`, …), so it can be pasted into App Store Connect or uploaded
as is.

## One-time setup (done 2026-10-20)

- **App record:** "LaWallet: Lightning Wallet" (Apple ID 6824778831, SKU `lawallet-ios`, bundle `io.lawallet.wallet`) on
  team JL86VWP8H7. "LaWallet" was already taken on the App Store; the home-screen name is still LaWallet.
- **Signing:** Release signs manually with *Apple Distribution* and the **LaWallet App Store** profile (created through
  the API; the team has no registered devices, so automatic signing can't make the development profile it wants first).
  The Team ID goes in the gitignored `Config/Local.xcconfig`.
- **API key:** App Manager key "GitHub Actions iOS release". Export `ASC_KEY_PATH`, `ASC_KEY_ID`, `ASC_ISSUER_ID`. The
  issuer ID is under Users and Access → Integrations.
- **Server:** beta.lawallet.io serves the AASA with `APPLE_APP_IDS=JL86VWP8H7.io.lawallet.wallet`, which passkeys and
  activation links need. `DELETE /api/account` must be live there before submitting (guideline 5.1.1(v)).
- **Organization account:** wallets must come from an organization (guideline 3.1.5(b)). The plan is to convert this
  individual membership to La Crypta: get La Crypta's D-U-N-S number, then ask Apple Developer Support to migrate the
  membership. That keeps the team ID, the app and the certificates.

## Every release

```bash
pnpm start:dev-server            # in lawallet-nwc: funded local signups for the UI tests
xcodebuild test -project LaWallet.xcodeproj -scheme LaWallet \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -skipPackagePluginValidation -skipMacroValidation
scripts/screenshots.sh           # only when the UI changed → AppStore/screenshots/{en,es}/ (gitignored)
scripts/archive.sh --upload      # Release archive → App Store Connect (build number = commit count)
REVIEW_FIRST_NAME=… REVIEW_LAST_NAME=… REVIEW_EMAIL=… REVIEW_PHONE=+… \
  scripts/appstore-metadata.py --build <n> [--screenshots]   # listing, age rating, categories, review info, build
```

`appstore-metadata.py` needs `pip install pyjwt cryptography requests`. Three things stay manual in App Store Connect:
the App Privacy answers (publishing them is an attestation), pricing changes, and **Submit for Review**.

Bump `MARKETING_VERSION` in `project.yml` for each user-facing version. The build number comes from the commit count,
so it never needs a manual bump.

## Questions App Store Connect asks

| Question | Answer |
| --- | --- |
| Export compliance | `ITSAppUsesNonExemptEncryption = NO` is set in Info.plist. The app uses standard cryptography (HTTPS, secp256k1 signatures, NIP-44/NIP-04 message encryption) for authentication and to protect user data. Confirm this with whoever owns legal for the project before the first submission. |
| Age rating | Answer "None" to everything. No user-generated content feed, no web browser, no gambling. |
| Content rights | No third-party content. |
| Sign in with Apple | Not required: there's no third-party or social login. Accounts are Nostr keys and passkeys. |
| Privacy policy URL | https://lawallet.io/privacy |

### App Privacy label

Matches `LaWallet/Resources/PrivacyInfo.xcprivacy`. Nothing is used for tracking, and every item is **linked to the
user** with purpose **App Functionality**:

- **Identifiers → User ID**: the Nostr public key.
- **Contact Info → Other User Contact Info**: the Lightning address (username@domain).
- **Financial Info → Other Financial Info**: payments to the address, card spending limits, remote-wallet connections.

Not collected: location, contacts, browsing history, diagnostics, crash data. Camera frames and NFC reads stay on the
device.

## Review risks

- **Paid Lightning addresses (3.1.1).** On instances that charge for usernames, the claim screen asks for a Lightning
  payment to unlock one. That can read as buying a digital good without In-App Purchase. beta.lawallet.io offers free
  usernames, so the reviewer won't see it there. If App Review raises it, hide the paid path on iOS.
- **Demo account.** Put a funded nsec in App Store Connect → App Review Information, never in this repo. Review notes:
  `metadata/review_information/notes.txt`.
- **NFC.** The reviewer has no Bolt Card. The notes explain that the card features need one, and every other flow
  works without it.
