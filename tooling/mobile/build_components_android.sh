#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
ocaml_version=${LUI_MOBILE_OCAML_VERSION:-5.5.0}
android_abi=${LUI_ANDROID_ABI:-arm64-v8a}
api_level=${LUI_ANDROID_API_LEVEL:-21}
android_home=${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}}

case "$android_abi" in
  arm64-v8a) target_arch=aarch64 ;;
  x86_64) target_arch=x86_64 ;;
  *) echo "error: unsupported Android ABI: $android_abi" >&2; exit 1 ;;
esac

target="${target_arch}-linux-android${api_level}"
opam_root=$(opam var root --safe)
shared_root=${LG_OCAML_TOOLCHAIN_ROOT:-${LUI_MOBILE_TOOLCHAIN_ROOT:-$opam_root/lg-ocaml-toolchains}}
target_prefix=${LG_ANDROID_OCAML_PREFIX:-$shared_root/ocaml-$ocaml_version/targets/$target}
build_dir="$repo_root/_build/mobile-components/android/$android_abi"
jni_library="$repo_root/examples/components/flutter/android/app/src/main/jniLibs/$android_abi/liblui_components.so"

[[ -x $target_prefix/bin/ocamlopt.opt ]] || {
  echo "error: shared Android OCaml toolchain is missing: $target_prefix" >&2
  echo "run tooling/mobile/bootstrap_android_ocaml.sh explicitly or set LG_ANDROID_OCAML_PREFIX" >&2
  exit 1
}

if [[ -d ${ANDROID_NDK_HOME:-} ]]; then
  ndk_root=$ANDROID_NDK_HOME
else
  ndk_root=
  for candidate in "$android_home"/ndk/*; do
    [[ -d $candidate ]] && ndk_root=$candidate
  done
fi
[[ -n ${ndk_root:-} && -d $ndk_root ]] || {
  echo "error: Android NDK is not installed under $android_home/ndk" >&2
  exit 1
}

case "$(uname -s)" in
  Darwin) ndk_host=darwin-x86_64 ;;
  Linux) ndk_host=linux-x86_64 ;;
  *) echo "error: unsupported build host" >&2; exit 1 ;;
esac
ndk_bin="$ndk_root/toolchains/llvm/prebuilt/$ndk_host/bin"

opam exec -- dune build -j 1 examples/components/native/gallery_bridge.ml
mkdir -p "$build_dir" "$(dirname "$jni_library")"
gallery_object=$(
  "$repo_root/tooling/mobile/build_gallery_ocaml_object.sh" \
    "$target_prefix" "$build_dir/ocaml" pic
)

"$ndk_bin/clang" \
  --target="$target" \
  -fPIC \
  -I "$target_prefix/lib/ocaml" \
  -c "$repo_root/platform/flutter/native/lui_ocaml_bridge.c" \
  -o "$build_dir/lui_ocaml_bridge.o"

"$ndk_bin/clang" \
  --target="$target" \
  -shared \
  -Wl,-soname,liblui_components.so \
  -o "$build_dir/liblui_components.so" \
  "$gallery_object" \
  "$build_dir/lui_ocaml_bridge.o" \
  -lm -ldl -pthread

"$ndk_bin/llvm-strip" --strip-unneeded "$build_dir/liblui_components.so"
cp "$build_dir/liblui_components.so" "$jni_library"
echo "$jni_library"
