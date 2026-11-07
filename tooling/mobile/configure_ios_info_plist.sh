#!/usr/bin/env bash

set -euo pipefail

info_plist=${1:?usage: $0 INFO_PLIST DEPLOYMENT_TARGET}
deployment_target=${2:?usage: $0 INFO_PLIST DEPLOYMENT_TARGET}
plistbuddy=/usr/libexec/PlistBuddy

set_string() {
  local key=$1
  local value=$2
  "$plistbuddy" -c "Set :$key $value" "$info_plist" 2>/dev/null \
    || "$plistbuddy" -c "Add :$key string $value" "$info_plist"
}

set_bool() {
  local key=$1
  local value=$2
  "$plistbuddy" -c "Set :$key $value" "$info_plist" 2>/dev/null \
    || "$plistbuddy" -c "Add :$key bool $value" "$info_plist"
}

reset_key() {
  "$plistbuddy" -c "Delete :$1" "$info_plist" 2>/dev/null || true
}

set_string CFBundleDevelopmentRegion en
set_string CFBundleInfoDictionaryVersion 6.0
set_bool ITSAppUsesNonExemptEncryption false
set_bool LSRequiresIPhoneOS true
set_string MinimumOSVersion "$deployment_target"
set_bool UIApplicationSupportsIndirectInputEvents true

reset_key CFBundleSupportedPlatforms
"$plistbuddy" -c "Add :CFBundleSupportedPlatforms array" "$info_plist"
"$plistbuddy" -c "Add :CFBundleSupportedPlatforms:0 string iPhoneSimulator" "$info_plist"

reset_key UIDeviceFamily
"$plistbuddy" -c "Add :UIDeviceFamily array" "$info_plist"
"$plistbuddy" -c "Add :UIDeviceFamily:0 integer 1" "$info_plist"
"$plistbuddy" -c "Add :UIDeviceFamily:1 integer 2" "$info_plist"

reset_key UIApplicationSceneManifest
"$plistbuddy" -c "Add :UIApplicationSceneManifest dict" "$info_plist"
"$plistbuddy" -c "Add :UIApplicationSceneManifest:UIApplicationSupportsMultipleScenes bool true" "$info_plist"
"$plistbuddy" -c "Add :UIApplicationSceneManifest:UISceneConfigurations dict" "$info_plist"
