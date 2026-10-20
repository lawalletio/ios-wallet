# App Store release

Everything needed to ship LaWallet to TestFlight and the App Store. The listing text lives in `metadata/`, laid out the
way `fastlane deliver` expects (`metadata/<locale>/name.txt`, …), so it can be pasted into App Store Connect or uploaded
as is.

## One-time setup

1. **Team.** Create `Config/Local.xcconfig` (gitignored) with `DEVELOPMENT_TEAM = <your Team ID>`. The enrolled account
   must be an **organization**: App Review only accepts wallets from organizations (guideline 3.1.5(b)).
2. **App ID** `io.lawallet.wallet` with these capabilities: Associated Domains, NFC Tag Reading. Automatic signing
   creates it on the first archive (`-allowProvisioningUpdates`).
3. **App Store Connect record.** Name *LaWallet*, primary language English (U.S.), bundle ID `io.lawallet.wallet`,
   SKU `lawallet-ios`. Category **Finance** (secondary: Utilities).
4. **Server side, on every instance the reviewer might hit (at least beta.lawallet.io):**
   - `APPLE_APP_IDS=<TEAMID>.io.lawallet.wallet` set, so `/.well-known/apple-app-site-association` serves the app.
     Passkeys and universal links depend on it (lawallet-nwc PR #365).
   - `DELETE /api/account` deployed. The in-app **Delete account** button (Settings → Security) needs it, and Apple
     requires account deletion (guideline 5.1.1(v)). Until it ships, the button explains that the instance can't
     delete accounts yet, which App Review will reject.

## Every release

```bash
pnpm start:dev-server            # in lawallet-nwc: funded local signups for the UI tests
xcodebuild test -project LaWallet.xcodeproj -scheme LaWallet \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -skipPackagePluginValidation -skipMacroValidation
scripts/screenshots.sh           # only when the UI changed → AppStore/screenshots/{en,es}/ (gitignored)
scripts/archive.sh --upload      # Release archive → App Store Connect (build number = commit count)
```

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
