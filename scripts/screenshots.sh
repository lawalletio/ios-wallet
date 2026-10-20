#!/usr/bin/env bash
# App Store screenshots (6.9" iPhone, 1320×2868) in English and Spanish → AppStore/screenshots/<lang>/.
# Needs the local lawallet-nwc dev server (default http://localhost:3774, LNCurl → NWC faucet) so new accounts are funded;
# override with LAWALLET_UITEST_INSTANCE.
set -euo pipefail
cd "$(dirname "$0")/.."

DEVICE="${DEVICE:-iPhone 17 Pro Max}"   # any 6.9" iPhone; a dedicated "LaWallet Screenshots" sim keeps test wipes off yours
OUT=AppStore/screenshots
UDID=$(xcrun simctl list devices available | grep -m1 "$DEVICE (" | grep -oE '[0-9A-F-]{36}')
xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl status_bar "$UDID" override --time 9:41 --dataNetwork wifi --wifiBars 3 --cellularBars 4 \
  --batteryState charged --batteryLevel 100

for lang in en es; do
  RESULT="build/screenshots-$lang.xcresult"
  rm -rf "$RESULT" "$OUT/$lang" && mkdir -p "$OUT/$lang"
  TEST_RUNNER_SCREENSHOT_LANG=$lang TEST_RUNNER_LAWALLET_UITEST_INSTANCE="${LAWALLET_UITEST_INSTANCE:-http://localhost:3774}" \
    xcodebuild test -project LaWallet.xcodeproj -scheme LaWallet -destination "id=$UDID" \
    -only-testing:LaWalletUITests/ScreenshotTests -resultBundlePath "$RESULT" \
    -skipPackagePluginValidation -skipMacroValidation -quiet
  xcrun xcresulttool export attachments --path "$RESULT" --output-path "$OUT/$lang"
  # Name files by their attachment name (1-home.png …) instead of the exported UUIDs.
  /usr/bin/python3 - "$OUT/$lang" <<'PY'
import json, os, sys
d = sys.argv[1]
for test in json.load(open(os.path.join(d, "manifest.json"))):
    for a in test.get("attachments", []):
        name = a["suggestedHumanReadableName"].split("_")[0]
        os.replace(os.path.join(d, a["exportedFileName"]), os.path.join(d, name + ".png"))
os.remove(os.path.join(d, "manifest.json"))
PY
done
xcrun simctl status_bar "$UDID" clear
ls -1 "$OUT"/*
