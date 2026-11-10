#!/bin/sh
set -eu

apple_dir=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
project_dir=$(CDPATH= cd -- "$apple_dir/../../.." && pwd)
configuration=${1:-debug}
bundle="$apple_dir/.build/$configuration/LUIMarkdown.app"
executable="$apple_dir/.build/$configuration/LUIMarkdown"
backend_library="$apple_dir/.build/$configuration/libLUIAppleBackend.dylib"
native_library="$project_dir/_build/default/examples/markdown/native/liblui_markdown.dylib"

cd "$project_dir"
opam exec -- dune build examples/markdown/native/liblui_markdown.dylib
swift build --package-path "$apple_dir" --configuration "$configuration" --product LUIMarkdown

rm -rf "$bundle"
mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Frameworks"
cp "$apple_dir/App/Info.plist" "$bundle/Contents/Info.plist"
cp "$executable" "$bundle/Contents/MacOS/LUIMarkdown"
cp "$backend_library" "$bundle/Contents/Frameworks/libLUIAppleBackend.dylib"
cp "$native_library" "$bundle/Contents/Frameworks/liblui_markdown.dylib"
install_name_tool -add_rpath @executable_path/../Frameworks \
  "$bundle/Contents/MacOS/LUIMarkdown"
codesign --force --sign - "$bundle/Contents/Frameworks/libLUIAppleBackend.dylib"
codesign --force --sign - "$bundle/Contents/Frameworks/liblui_markdown.dylib"
codesign --force --deep --sign - "$bundle"

# Records what the bundle was built from, so tooling/lui_agent.mjs refuses to
# drive it once its sources change. Builds without Node skip the receipt.
if command -v node >/dev/null 2>&1 && [ -f "$project_dir/tooling/lui_build_receipt.mjs" ]; then
  node "$project_dir/tooling/lui_build_receipt.mjs" write --root "$project_dir" \
    --artifact "$bundle" --command "sh examples/markdown/macos-appkit/build-app.sh $configuration" \
    --input src --input ppx --input examples/markdown --input platform/apple --input platform/bridge >&2 \
    || echo "warning: could not write a build receipt for $bundle" >&2
fi

echo "$bundle"
