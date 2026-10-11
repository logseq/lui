# webview-shell

Runs the LUI components web bundle inside the native webview shell
(`lui_webapp`) instead of a browser: an SDL window covered by the
platform web view (WKWebView on macOS), mirroring mygo's
native-shell architecture.

```sh
bash examples/components/webview-shell/run.sh          # build + run
# or, with _build/web-release already present:
dune exec examples/components/webview-shell/main.exe -- \
  examples/components/webview-shell/webapp.json
```

## Bridge

- page → native: `window.webkit.messageHandlers.lui_wv.postMessage(<json>)`
  → one `on_message` string per post (a `Script_message` event drained
  each frame by `Lui_webview`).
- native → page: `Lui_webview.eval` → `evaluateJavaScript`.

`main.ml` installs a page hook on first load (`post hello`, forward
clicks, mount `#lui-shell-badge`) and answers each message by updating
the badge — a visible two-way round trip that requires no changes to
the web build. Off macOS the shell degrades per `lui_webview`'s
contract (other engine or the default browser), where the hook is a
no-op.
