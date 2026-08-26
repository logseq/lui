#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
qualification_dir="$repo_root/_build/mobile-components/android-release"
keystore="$qualification_dir/qualification.jks"
bundle_source="$repo_root/examples/components/flutter/build/app/outputs/bundle/release/app-release.aab"
bundle="$qualification_dir/lui-components-release.aab"
alias=lui-release-qualification
password=lui-release-qualification

mkdir -p "$qualification_dir"

if [[ ! -f $keystore ]]; then
  keytool -genkeypair \
    -keystore "$keystore" \
    -storepass "$password" \
    -keypass "$password" \
    -alias "$alias" \
    -keyalg RSA \
    -keysize 3072 \
    -validity 3650 \
    -dname "CN=LUI Release Qualification,OU=Engineering,O=LUI,L=Local,ST=Local,C=US" \
    -noprompt >/dev/null
fi

"$repo_root/tooling/mobile/build_components_android.sh" >/dev/null

(
  cd "$repo_root/examples/components/flutter"
  LUI_ANDROID_KEYSTORE="$keystore" \
  LUI_ANDROID_KEY_ALIAS="$alias" \
  LUI_ANDROID_STORE_PASSWORD="$password" \
  LUI_ANDROID_KEY_PASSWORD="$password" \
    flutter build appbundle --release --target-platform android-arm64
)

cp "$bundle_source" "$bundle"
verification=$(jarsigner -verify "$bundle" 2>&1)
grep -q '^jar verified\.$' <<<"$verification"
certificate=$(keytool -printcert -jarfile "$bundle")
grep -q 'Owner: CN=LUI Release Qualification' <<<"$certificate"
contents=$(unzip -Z1 "$bundle")
grep -Fxq 'base/lib/arm64-v8a/liblui_components.so' <<<"$contents"
grep -Fxq 'BUNDLE-METADATA/com.android.tools.build.obfuscation/proguard.map' <<<"$contents"
grep -Fxq 'BUNDLE-METADATA/com.android.tools/r8.json' <<<"$contents"

bundle_size=$(du -k "$bundle" | awk '{print $1}')
echo "qualified signed Android release bundle: $bundle (${bundle_size} KiB)"
