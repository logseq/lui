#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
opam_root=$(opam var root --safe)
toolchain_root=${LG_OCAML_TOOLCHAIN_ROOT:-${LUI_MOBILE_TOOLCHAIN_ROOT:-$opam_root/lg-ocaml-toolchains}}
case "${LUI_ANDROID_ABI:-arm64-v8a}" in
  arm64-v8a) target_arch=aarch64 ;;
  x86_64) target_arch=x86_64 ;;
  *) printf 'Unsupported Android ABI: %s\n' "$LUI_ANDROID_ABI" >&2; exit 1 ;;
esac
export LG_ANDROID_OCAML_PREFIX=${LG_ANDROID_OCAML_PREFIX:-$toolchain_root/ocaml-${LUI_MOBILE_OCAML_VERSION:-5.5.0}/targets/$target_arch-linux-android${LUI_ANDROID_API_LEVEL:-21}}

"$repo_root/tooling/mobile/build_components_ios_simulator.sh"
"$repo_root/tooling/mobile/build_components_android.sh"
"$repo_root/platform/android/gradlew" --no-daemon \
  -p "$repo_root/examples/components/android" :app:assembleDebug
