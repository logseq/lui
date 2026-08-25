#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
ocaml_version=${LUI_MOBILE_OCAML_VERSION:-5.5.0}
deployment_target=${LUI_IOS_DEPLOYMENT_TARGET:-17.0}
triple="arm64-apple-ios${deployment_target}-simulator"
opam_root=$(opam var root --safe)
shared_root=${LG_OCAML_TOOLCHAIN_ROOT:-${LUI_MOBILE_TOOLCHAIN_ROOT:-$opam_root/lg-ocaml-toolchains}}
target_prefix=${LG_IOS_OCAML_PREFIX:-$shared_root/ocaml-$ocaml_version/targets/$triple}
build_dir="$repo_root/_build/mobile-components/ios-simulator"
package_dir="$repo_root/examples/components/ios-swiftui"
app_dir="$build_dir/LUIComponents.app"
sdk_path=$(xcrun --sdk iphonesimulator --show-sdk-path)
clang=$(xcrun --sdk iphonesimulator --find clang)

[[ -x $target_prefix/bin/ocamlopt.opt ]] || {
  echo "error: shared iOS OCaml toolchain is missing: $target_prefix" >&2
  echo "run tooling/mobile/bootstrap_ios_ocaml.sh explicitly or set LG_IOS_OCAML_PREFIX" >&2
  exit 1
}

opam exec -- dune build -j 1 examples/components/native/gallery_bridge.ml
mkdir -p "$build_dir"
gallery_bridge_complete_o=$(
  "$repo_root/tooling/mobile/build_gallery_ocaml_object.sh" \
    "$target_prefix" "$build_dir/ocaml"
)

"$clang" \
  -target "$triple" \
  -isysroot "$sdk_path" \
  -fPIC \
  -I "$target_prefix/lib/ocaml" \
  -c "$repo_root/platform/flutter/native/lui_ocaml_bridge.c" \
  -o "$build_dir/lui_ocaml_bridge.o"

native_fingerprint=$(shasum -a 256 \
  "$gallery_bridge_complete_o" \
  "$build_dir/lui_ocaml_bridge.o" \
  | shasum -a 256 \
  | cut -d ' ' -f 1)
native_link_dir="$build_dir/native-link-inputs/$native_fingerprint"
mkdir -p "$native_link_dir"
cp "$gallery_bridge_complete_o" "$native_link_dir/gallery_bridge_complete.o"
cp "$build_dir/lui_ocaml_bridge.o" "$native_link_dir/lui_ocaml_bridge.o"

LUI_COMPONENTS_NATIVE_LINK_INPUTS="$native_link_dir/gallery_bridge_complete.o:$native_link_dir/lui_ocaml_bridge.o" \
swift build \
  --disable-keychain \
  --package-path "$package_dir" \
  --product LUIComponentsApp \
  --triple "$triple" \
  --sdk "$sdk_path"

swift_build_dir="$package_dir/.build/arm64-apple-ios-simulator/debug"
rm -rf "$app_dir"
mkdir -p "$app_dir"
cp "$package_dir/Info.plist" "$app_dir/Info.plist"
"$repo_root/tooling/mobile/configure_ios_info_plist.sh" \
  "$app_dir/Info.plist" "$deployment_target"
cp "$swift_build_dir/LUIComponentsApp" "$app_dir/LUIComponentsApp"
codesign --force --sign - --timestamp=none "$app_dir"

echo "$app_dir"
