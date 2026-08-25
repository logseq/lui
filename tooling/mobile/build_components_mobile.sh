#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
native_root="$repo_root/_build/mobile-components/lg-development"

"$repo_root/tooling/mobile/build_components_lg.sh" \
  --profile development \
  --output-dir "$native_root"

LUI_GALLERY_OCAML_OBJECT="$native_root/ios-simulator/mobile_app_complete.o" \
  "$repo_root/tooling/mobile/build_components_ios_simulator.sh"

LUI_GALLERY_OCAML_OBJECT="$native_root/android/arm64-v8a/mobile_app_complete.o" \
  "$repo_root/tooling/mobile/build_components_android.sh"

(
  cd "$repo_root/examples/components/flutter"
  flutter build apk --debug --target-platform android-arm64
)
