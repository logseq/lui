#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
ios_root="$repo_root/_build/mobile-components/lg-ios-simulator"
android_root="$repo_root/_build/mobile-components/lg-android"

"$repo_root/tooling/mobile/build_components_lg.sh" \
  ios simulator \
  --output-dir "$ios_root"

"$repo_root/tooling/mobile/build_components_lg.sh" \
  android \
  --output-dir "$android_root"

LUI_GALLERY_OCAML_OBJECT="$ios_root/ios-simulator/mobile_app_complete.o" \
  "$repo_root/tooling/mobile/build_components_ios_simulator.sh"

LUI_GALLERY_OCAML_OBJECT="$android_root/android/arm64-v8a/mobile_app_complete.o" \
  "$repo_root/tooling/mobile/build_components_android.sh"

(
  cd "$repo_root/examples/components/flutter"
  flutter build apk --debug --target-platform android-arm64
)
