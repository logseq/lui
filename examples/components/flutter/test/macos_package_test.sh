#!/bin/sh

set -eu

project_dir=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
repository_dir=$(CDPATH= cd -- "$project_dir/../../.." && pwd)
app_bundle="$project_dir/build/macos/Build/Products/Debug/lui_components.app"
executable="$app_bundle/Contents/MacOS/lui_components"
native_library="$app_bundle/Contents/Frameworks/liblui_components.dylib"

(cd "$repository_dir" &&
  opam exec -- dune build -j 1 \
    examples/components/native/liblui_components.dylib)

cd "$project_dir"
flutter build macos --debug

# Flutter's incremental embed phase can refresh App.framework after Xcode has
# sealed the outer debug bundle. Re-sign only the outer app so its resource
# envelope always describes the frameworks produced by this build.
codesign --force --sign - "$app_bundle"

test -x "$executable"
test -f "$native_library"
file "$native_library" | grep -q 'Mach-O.*dynamically linked shared library'
codesign --verify --deep --strict "$app_bundle"
