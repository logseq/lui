# ADR 0005: OCaml-owned Web desktop host

Status: accepted user direction; initial implementation, delivery qualification pending

Date: 2026-11-17

LUI applications need an OCaml-authored Web frontend, an OCaml-owned desktop
shell, desktop distribution and signed delta updates. Native desktop UI is
not required for this host.
This adds an optional desktop route while preserving the Apple Swift packages,
Android/JNI and downstream mobile tooling.

Implement `platform/desktop` as a native OCaml executable hosting the existing
Melange/DOM frontend. On macOS, use public WKWebView/WKURLSchemeHandler APIs
through a small platform binding, loading packaged assets at `lui://localhost`.
Linux/Windows retain a checksum-pinned upstream `webview/webview` adapter;
qualification on those systems is deferred. Do not introduce a Go/Rust application runtime,
another renderer or another application state model. Keep packaging separate
from runtime ownership and use the target OS's existing signing tools.

The updater is OCaml, with a Web update window. Use an authenticated release
envelope, monotonic integer builds, whole-application packages, file-level
deltas, full-package fallback and a helper outside the installation for
replacement after exit. Preserve old application contents until the new page
acknowledges the expected build. A package-manager-owned installation never
self-updates. OS code signatures/notarization and update feed signatures are
different requirements and are configured separately.

Use a standalone explicit build command while changes to Dune files remain
unauthorized. Downloaded dependencies, artifacts and tests' temporary keys
stay outside tracked source. See the [host guide](../../platform/desktop/README.md)
for exact dependencies, commands, defaults, wire formats and qualification limits.
