#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
ocaml_version=${LUI_MOBILE_OCAML_VERSION:-5.5.0}
deployment_target=${LUI_IOS_DEPLOYMENT_TARGET:-17.0}
triple="arm64-apple-ios${deployment_target}-simulator"
opam_root=$(opam var root --safe)
shared_root=${LG_OCAML_TOOLCHAIN_ROOT:-${LUI_MOBILE_TOOLCHAIN_ROOT:-$opam_root/lg-ocaml-toolchains}}
target_prefix=${LG_IOS_OCAML_PREFIX:-$shared_root/ocaml-$ocaml_version/targets/$triple}
if [[ ! -d $target_prefix/lib/ocaml ]]; then
  # lui_ocaml_bridge.c only needs the platform-independent OCaml headers;
  # fall back to the host switch when no cross-toolchain prefix exists.
  target_prefix=$(opam var prefix --safe)
fi
build_dir="$repo_root/_build/mobile-components/ios-simulator"
package_dir="$repo_root/examples/components/ios-swiftui"
app_dir="$build_dir/LUIComponents.app"
sdk_path=$(xcrun --sdk iphonesimulator --show-sdk-path)
clang=$(xcrun --sdk iphonesimulator --find clang)

[[ -x $target_prefix/bin/ocamlopt.opt ]] || {
  echo "error: no OCaml toolchain prefix found: $target_prefix" >&2
  echo "set LG_IOS_OCAML_PREFIX to a prefix with bin/ocamlopt.opt + lib/ocaml" >&2
  exit 1
}

mkdir -p "$build_dir"
gallery_bridge_complete_o=${LUI_GALLERY_OCAML_OBJECT:-}
if [[ -z $gallery_bridge_complete_o ]]; then
  # Build the host (macOS) complete object and restamp it for the simulator
  # triple with vtool — the app .cmx are identical arm64 code; a target-
  # toolchain recompile can replace this once iOS objects of the deps exist.
  native_root="$build_dir/ocaml-object"
  mkdir -p "$native_root"
  (cd "$repo_root" && opam exec -- dune build \
    src/lui.cmxa \
    examples/gallery/gallery_app.cmxa \
    examples/components/native/components_bridge.cmxa)
  (cd "$repo_root" && opam exec -- ocamlfind ocamlopt -linkpkg -linkall \
    -package ocaml-signal \
    _build/default/src/lui.cmxa \
    _build/default/examples/gallery/gallery_app.cmxa \
    _build/default/examples/components/native/components_bridge.cmxa \
    -output-complete-obj -o "$native_root/mobile_app_macos.o")
  vtool -set-build-version 7 "$deployment_target" \
    "$(xcrun --sdk iphonesimulator --show-sdk-version)" \
    -replace -output "$native_root/mobile_app_complete.o" \
    "$native_root/mobile_app_macos.o"
  gallery_bridge_complete_o="$native_root/mobile_app_complete.o"
fi
[[ -f $gallery_bridge_complete_o ]] || {
  echo "error: LG mobile object is missing: $gallery_bridge_complete_o" >&2
  exit 1
}

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
