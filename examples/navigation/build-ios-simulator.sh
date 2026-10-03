#!/usr/bin/env bash
set -euo pipefail
repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
build="$repo/_build/navigation-demo"
triple="arm64-apple-ios17.0-simulator"
sdk=$(xcrun --sdk iphonesimulator --show-sdk-path)
mkdir -p "$build"
cd "$repo"
opam exec -- dune build src/lui.cmxa
opam exec -- ocamlfind ocamlopt -package ocaml-signal -I _build/default/src/.lui.objs/byte -I _build/default/src/.lui.objs/native \
  -c examples/navigation/native/navigation_bridge.ml -o "$build/navigation_bridge.cmx"
opam exec -- ocamlfind ocamlopt -linkpkg -linkall -package ocaml-signal \
  _build/default/src/lui.cmxa "$build/navigation_bridge.cmx" \
  -output-complete-obj -o "$build/navigation_macos.o"
# This follows the existing components demo's arm64 object restamping path.
# A device build requires the real cross compiler; this is Simulator only.
vtool -set-build-version 7 17.0 "$(xcrun --sdk iphonesimulator --show-sdk-version)" \
  -replace -output "$build/navigation_simulator.o" "$build/navigation_macos.o"
prefix=$(opam var prefix --safe)
xcrun --sdk iphonesimulator clang -target "$triple" -isysroot "$sdk" -I "$prefix/lib/ocaml" \
  -c platform/native/lui_ocaml_bridge.c -o "$build/bridge.o"
LUI_NAVIGATION_LINK_INPUTS="$build/navigation_simulator.o:$build/bridge.o" \
  swift build --disable-keychain --package-path examples/navigation/ios-swiftui \
  --scratch-path "$build/swift" --product NavigationDemo --triple "$triple" --sdk "$sdk"
app="$build/NavigationDemo.app"
mkdir -p "$app"
cp "$build/swift/arm64-apple-ios-simulator/debug/NavigationDemo" "$app/NavigationDemo"
cat > "$app/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.logseq.lui.navigation.demo</string>
<key>CFBundleName</key><string>LUI Navigation</string>
<key>CFBundleExecutable</key><string>NavigationDemo</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>1</string><key>CFBundleShortVersionString</key><string>1.0</string>
<key>MinimumOSVersion</key><string>17.0</string>
<key>UIDeviceFamily</key><array><integer>1</integer><integer>2</integer></array>
<key>UILaunchScreen</key><dict/>
</dict></plist>
PLIST
codesign --force --sign - "$app"
printf '%s\n' "$app"
