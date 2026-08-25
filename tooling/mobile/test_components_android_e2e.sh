#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
app_id=dev.lui.lui_component_gallery
apk_path="$repo_root/examples/components/flutter/build/app/outputs/flutter-apk/app-debug.apk"
flow="$repo_root/.maestro/android-components-interactions.yaml"
screenshots_dir="$repo_root/_build/mobile-components/android-e2e"
maestro_bin=${MAESTRO_BIN:-$(command -v maestro || true)}

die() {
  echo "error: $*" >&2
  exit 1
}

[[ -n $maestro_bin ]] || die "Maestro is not installed"
[[ -f $flow ]] || die "Android Gallery Maestro flow is missing: $flow"

device=${LUI_ANDROID_DEVICE_ID:-}
if [[ -z $device ]]; then
  connected_devices=$(adb devices | awk '$2 == "device" { print $1 }')
  device_count=$(printf '%s\n' "$connected_devices" | awk 'NF { count += 1 } END { print count + 0 }')
  case $device_count in
    0) die "no connected Android device or emulator was found" ;;
    1) device=$(printf '%s\n' "$connected_devices" | awk 'NF { print; exit }') ;;
    *) die "multiple Android devices are connected; set LUI_ANDROID_DEVICE_ID" ;;
  esac
fi
adb -s "$device" get-state >/dev/null \
  || die "Android device is unavailable: $device"

"$repo_root/tooling/mobile/build_components_android.sh" >/dev/null
(
  cd "$repo_root/examples/components/flutter"
  flutter build apk --debug --target-platform android-arm64
)
[[ -f $apk_path ]] || die "Android Gallery APK is missing: $apk_path"

mkdir -p "$screenshots_dir"
adb -s "$device" install -r "$apk_path" >/dev/null
adb -s "$device" shell am force-stop "$app_id" >/dev/null
MAESTRO_CLI_NO_ANALYTICS=1 "$maestro_bin" --device "$device" test "$flow"
adb -s "$device" exec-out screencap -p > "$screenshots_dir/final.png"
