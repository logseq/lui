#!/usr/bin/env bash
# Build the components web bundle and boot it in the native webview
# shell. On macOS this opens an SDL window covered by a WKWebView;
# elsewhere it degrades to the platform webview or the default browser
# (see Lui_webapp.boot). Requires the lui opam switch and
# platform/web's npm install.
set -euo pipefail
cd "$(dirname "$0")/../../.."
opam exec -- dune build
node tooling/build_web_release.mjs >/dev/null
opam exec -- dune exec examples/components/webview-shell/main.exe -- \
  examples/components/webview-shell/webapp.json "$@"
