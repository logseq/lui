#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
deployment_target=${LUI_IOS_DEPLOYMENT_TARGET:-17.0}
triple="arm64-apple-ios${deployment_target}-simulator"
package_dir="$repo_root/platform/apple"
fixture="$repo_root/tooling/mobile/fixtures/UIKitHostContract.swift"
sdk_path=$(xcrun --sdk iphonesimulator --show-sdk-path)
modules_dir="$package_dir/.build/arm64-apple-ios-simulator/debug/Modules"

swift build \
  --disable-keychain \
  --package-path "$package_dir" \
  --target LUIAppleBackend \
  --triple "$triple" \
  --sdk "$sdk_path"

xcrun --sdk iphonesimulator swiftc \
  -typecheck \
  -target "$triple" \
  -sdk "$sdk_path" \
  -I "$modules_dir" \
  "$fixture"

echo "qualified UIKit hosting of the shared LUISwiftUIRoot"
