#!/bin/sh
set -eu

apple_dir=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
project_dir=$(CDPATH= cd -- "$apple_dir/../.." && pwd)
configuration=${1:-debug}
bundle="$apple_dir/.build/$configuration/LUITodos.app"
executable="$apple_dir/.build/$configuration/LUITodos"
native_library="$project_dir/_build/default/platform/flutter/native/liblui_todos.dylib"

cd "$project_dir"
opam exec -- dune build platform/flutter/native/liblui_todos.dylib
swift build --package-path "$apple_dir" --configuration "$configuration" --product LUITodos

rm -rf "$bundle"
mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Frameworks"
cp "$apple_dir/App/Info.plist" "$bundle/Contents/Info.plist"
cp "$executable" "$bundle/Contents/MacOS/LUITodos"
cp "$native_library" "$bundle/Contents/Frameworks/liblui_todos.dylib"
codesign --force --sign - "$bundle/Contents/Frameworks/liblui_todos.dylib"
codesign --force --deep --sign - "$bundle"

echo "$bundle"
