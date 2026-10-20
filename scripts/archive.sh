#!/usr/bin/env bash
# Archive a Release build and export (or upload) it for App Store Connect.
#
#   DEVELOPMENT_TEAM=ABCDE12345 scripts/archive.sh            # → build/LaWallet.ipa
#   DEVELOPMENT_TEAM=ABCDE12345 scripts/archive.sh --upload   # → straight to App Store Connect / TestFlight
#
# The team can also come from Config/Local.xcconfig. Upload needs Xcode signed in to an account on that team
# (Xcode → Settings → Accounts) or an App Store Connect API key (-authenticationKeyPath/-ID/-IssuerID, see README).
# Build number = commit count, so every archive from a new commit is accepted without manual bumps.
set -euo pipefail
cd "$(dirname "$0")/.."

OUT=build
ARCHIVE="$OUT/LaWallet.xcarchive"
BUILD_NUMBER="${BUILD_NUMBER:-$(git rev-list --count HEAD)}"
TEAM_ARGS=()
[[ -n "${DEVELOPMENT_TEAM:-}" ]] && TEAM_ARGS=(DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM")

command -v xcodegen >/dev/null && xcodegen generate --quiet
rm -rf "$ARCHIVE"

xcodebuild archive \
  -project LaWallet.xcodeproj -scheme LaWallet -configuration Release \
  -destination 'generic/platform=iOS' -archivePath "$ARCHIVE" \
  -skipPackagePluginValidation -skipMacroValidation -allowProvisioningUpdates \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" ${TEAM_ARGS[@]+"${TEAM_ARGS[@]}"}

EXPORT_OPTIONS=Config/ExportOptions.plist
if [[ "${1:-}" == "--upload" ]]; then
  EXPORT_OPTIONS="$OUT/ExportOptions-upload.plist"
  cp Config/ExportOptions.plist "$EXPORT_OPTIONS"
  /usr/libexec/PlistBuddy -c "Add :destination string upload" "$EXPORT_OPTIONS"
fi

xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportPath "$OUT" \
  -exportOptionsPlist "$EXPORT_OPTIONS" -allowProvisioningUpdates

echo "LaWallet $(/usr/libexec/PlistBuddy -c 'Print :ApplicationProperties:CFBundleShortVersionString' "$ARCHIVE/Info.plist") ($BUILD_NUMBER) → $OUT"
