#!/usr/bin/env bash
set -euo pipefail

if [[ ${1:-} != --test-device || $# != 2 ]]; then
    echo "Usage: DRIVE_BIN=/path/to/drive $0 --test-device scenario.drive" >&2
    echo "This explicitly selects a test IME on the connected test device; do not use a personal device." >&2
    exit 2
fi

scenario=$2
port=49377
package=dev.lui.drive.sample
ime=$package/dev.lui.drive.DriveInputMethod
old_ime=$(adb shell settings get secure default_input_method | tr -d '\r')
[[ -n "$old_ime" && "$old_ime" != null ]] || { echo "Cannot preserve current IME; refusing setup" >&2; exit 1; }
printf 'Original IME (restore if the launcher is killed): %s\n' "$old_ime" >&2
enabled=false
if adb shell ime list -s | tr -d '\r' | grep -Fxq "$ime"; then enabled=true; fi
log=$(mktemp)
host_pid=
forwarded=false
cleanup() {
    local status=$?
    trap - EXIT INT TERM
    adb shell ime set "$old_ime" >/dev/null || echo "Restore the original IME manually: $old_ime" >&2
    if ! $enabled; then adb shell ime disable "$ime" >/dev/null || true; fi
    adb shell am force-stop "$package" >/dev/null || true
    if $forwarded; then adb forward --remove "tcp:$port" >/dev/null || true; fi
    if [[ -n "$host_pid" ]]; then kill "$host_pid" 2>/dev/null || true; wait "$host_pid" || true; fi
    cat "$log"
    rm -f "$log"
    exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
adb shell ime enable "$ime" >/dev/null
adb shell ime set "$ime" >/dev/null
adb forward --no-rebind "tcp:$port" "tcp:$port"
forwarded=true
adb shell am instrument -w -e drive true -e port "$port" \
    -e activity "$package/.MainActivity" \
    "$package/dev.lui.drive.DriveInstrumentation" >"$log" 2>&1 &
host_pid=$!
ready=false
for ((i=0; i<150; i++)); do
    if grep -q 'listening on 127.0.0.1' "$log"; then ready=true; break; fi
    if ! kill -0 "$host_pid" 2>/dev/null; then break; fi
    sleep 0.1
done
$ready || { echo "Drive instrumentation did not become ready" >&2; exit 1; }
"${DRIVE_BIN:-drive}" --tcp "127.0.0.1:$port" --input native "$scenario"
