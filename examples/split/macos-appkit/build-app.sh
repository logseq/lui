#!/bin/sh
set -eu

apple_dir=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
project_dir=$(CDPATH= cd -- "$apple_dir/../../.." && pwd)
configuration=${1:-debug}
bundle="$apple_dir/.build/$configuration/LUISplitDemo.app"
executable="$apple_dir/.build/$configuration/LUISplitDemo"
backend_library="$apple_dir/.build/$configuration/libLUIAppleBackend.dylib"
native_library="$project_dir/_build/default/examples/split/native/liblui_split.dylib"

cd "$project_dir"
opam exec -- dune build examples/split/native/liblui_split.dylib
swift build --package-path "$apple_dir" --configuration "$configuration" --product LUISplitDemo

rm -rf "$bundle"
mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Frameworks"
cp "$apple_dir/App/Info.plist" "$bundle/Contents/Info.plist"
cp "$executable" "$bundle/Contents/MacOS/LUISplitDemo"
cp "$backend_library" "$bundle/Contents/Frameworks/libLUIAppleBackend.dylib"
cp "$native_library" "$bundle/Contents/Frameworks/liblui_split.dylib"
install_name_tool -add_rpath @executable_path/../Frameworks \
  "$bundle/Contents/MacOS/LUISplitDemo"
codesign --force --sign - "$bundle/Contents/Frameworks/libLUIAppleBackend.dylib"
codesign --force --sign - "$bundle/Contents/Frameworks/liblui_split.dylib"
codesign --force --deep --sign - "$bundle"

# Records what the bundle was built from, so tooling/lui_agent.mjs refuses to
# drive it once its sources change. Builds without Node skip the receipt.
if command -v node >/dev/null 2>&1 && [ -f "$project_dir/tooling/lui_build_receipt.mjs" ]; then
  node "$project_dir/tooling/lui_build_receipt.mjs" write --root "$project_dir" \
    --artifact "$bundle" --command "sh examples/split/macos-appkit/build-app.sh $configuration" \
    --input src --input ppx --input examples/split --input platform/apple --input platform/bridge >&2 \
    || echo "warning: could not write a build receipt for $bundle" >&2
fi

echo "$bundle"
