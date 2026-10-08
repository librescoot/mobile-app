#!/usr/bin/env bash
set -euo pipefail

flutter build ios --simulator --debug --no-codesign
RUNTIME="$(xcrun simctl list runtimes --json | python3 -c '
import json, sys
runtimes = [item for item in json.load(sys.stdin)["runtimes"] if item.get("isAvailable") and ".iOS-" in item["identifier"]]
if not runtimes:
    sys.exit("No available iOS simulator runtime")
print(max(runtimes, key=lambda item: tuple(map(int, item["version"].split("."))))["identifier"])
')"
DEVICE="$(xcrun simctl create 'CI phone launch' com.apple.CoreSimulator.SimDeviceType.iPhone-16 "$RUNTIME")"
cleanup() {
  xcrun simctl shutdown "$DEVICE" || true
  xcrun simctl delete "$DEVICE" || true
}
trap cleanup EXIT
xcrun simctl boot "$DEVICE"
xcrun simctl bootstatus "$DEVICE" -b
xcrun simctl install "$DEVICE" build/ios/iphonesimulator/Runner.app
xcrun simctl launch --terminate-running-process "$DEVICE" org.librescoot.mobile.unu
sleep 15
if ! xcrun simctl spawn "$DEVICE" launchctl list | awk '
  $1 ~ /^[0-9]+$/ && index($3, "UIKitApplication:org.librescoot.mobile.unu[") == 1 { alive = 1 }
  END { exit !alive }
'; then
  xcrun simctl spawn "$DEVICE" log show --last 2m --style compact --predicate 'process == "Runner"'
  echo 'Phone app did not remain running after launch' >&2
  exit 1
fi
echo 'Phone app remained running after launch'
