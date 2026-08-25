#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
app_id=${LUI_IOS_APP_ID:-dev.lui.components}
flow=${LUI_IOS_E2E_FLOW:-$repo_root/.maestro/ios-components-interactions.yaml}
app_path="$repo_root/_build/mobile-components/ios-simulator/LUIComponents.app"
screenshots_dir="$repo_root/_build/mobile-components/ios-e2e"

die() {
  echo "error: $*" >&2
  exit 1
}

maestro_bin=${MAESTRO_BIN:-$(command -v maestro || true)}
[[ -n $maestro_bin && -x $maestro_bin ]] \
  || die "Maestro CLI is not installed. Install it with: brew install mobile-dev-inc/tap/maestro --formula"

device=${LUI_IOS_SIMULATOR_UDID:-}
if [[ -z $device ]]; then
  device=$(xcrun simctl list devices booted | awk -F'[()]' '/Booted/ { print $2; exit }')
fi
[[ -n $device ]] || die "no booted iOS simulator was found"

if [[ ${LUI_IOS_E2E_SKIP_BUILD:-0} != 1 ]]; then
  "$repo_root/tooling/mobile/build_components_ios_simulator.sh" >/dev/null
fi

xcrun simctl terminate "$device" "$app_id" >/dev/null 2>&1 || true
xcrun simctl uninstall "$device" "$app_id" >/dev/null 2>&1 || true
xcrun simctl install "$device" "$app_path"

mkdir -p "$screenshots_dir"
MAESTRO_CLI_NO_ANALYTICS=1 "$maestro_bin" --device "$device" test "$flow"
xcrun simctl io "$device" screenshot "$screenshots_dir/final.png" >/dev/null

echo "$screenshots_dir/final.png"
