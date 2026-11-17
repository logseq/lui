# macOS installed update and command qualification

Date: 2026-11-17. Target: macOS arm64, OCaml 5.5.1, release compilation.

Run `python3 tooling/qualify_desktop_macos.py --output <new ignored directory>`
on macOS. The successful local run used
`_build/desktop/macos-qualification-2`; generated keys, packages and logs remain
untracked. The harness uses the actual OCaml host, registry, native WebKit bridge
and updater. Its application handlers/frontend are fixtures. A copied updater
script has an appended driver which clicks the existing install/restart controls;
native sources and update handlers are unchanged. This is automated release-flow
qualification, not a visual review of the updater layout.

The harness builds and verifies ad-hoc-signed v1, v2 and failed-start-v2 apps,
packages v1 into a DMG, mounts it read-only and installs it outside the checkout.
A local HTTPS server serves Ed25519-signed releases. Its temporary CA is supplied
only to the app's curl environment; system trust and production feeds are untouched.
Fixture identity and user data are isolated from the Gallery.

| Scenario | Observed artifact requests | Native build sequence | Result |
| --- | --- | --- | --- |
| Full update | Feed, full package | 1 → 2 | Passed |
| File delta | Feed, delta only | 1 → 2 | Passed |
| Damaged delta | Feed, delta, authenticated full fallback | 1 → 2 | Passed |
| Invalid feed signature | Feed only; no artifacts | 1 | Passed |
| Replacement fails startup acknowledgement | Feed, delta | 1 → 2 → 1 | Passed |

For successful replacements and rollback, the complete installed file tree
matches the finalized expected app by SHA-256 and passes strict code-signature
verification. The previous-tree backup disappears only after acknowledgement or
rollback settles. A user-data sentinel survives every case. The invalid-signature
case keeps the original app running and unchanged. Failed-start rollback uses the
real 30-second acknowledgement timeout.

Each case also exercises native commands through actual WKWebView:

- Unicode and escaping survive the frontend/native round trip.
- Unknown commands and malformed arguments produce structured errors.
- Expected handler failures are preserved; unexpected exception details are redacted.
- A blocked command leaves the UI bridge responsive and can be released by another command.
- Only the main application initializes the command registry; updater and installer helpers do not.

The first run exposed implicit string decoding in native reply formatting. Replies
now explicitly convert UTF-8 bytes to `NSString`; the successful repeat covers
Chinese, ellipsis, quotes, backslash and newline.

Native-source SHA-256 values for the successful run:

| File | SHA-256 |
| --- | --- |
| `lui_desktop.ml` | `af1ce01cea82d6aff2a6cc1368cae0aeb15856249b961054919e744c67b92c04` |
| `lui_desktop_update.ml` | `5d931120606ad908134d6a8ff1f17a86135b02b08a29df87ce902de68996c157` |
| `lui_desktop_commands.ml` | `7e0b78c8982891f3cabe2cb4ea806723df368fd96c6c4e08d1f289d99bf6be33` |
| `macos_scheme.mm` | `ae03a31b8cf85deada876e1f8dfd5dd96d2b945c453dadcc584a1ace042d37c9` |
| `lui_desktop_reply.cc` | `41d18ce1c4b53c888a69351ca1e957c70b1990455e365a67acf73f6707e129f9` |

Additional passing checks: release `dune build @all` and `dune runtest`, 12 update
engine regressions, native/Melange command behavior and compile-failure contracts,
164 Web tests, and three real native window lifecycles checking helper/WebKit
process cleanup. Closing/navigating discards pending replies; running handlers
remain responsible for their own cancellation.

Developer ID signing, notarization, public hosting and production update publishing
still need application credentials and deployment qualification. Windows/Linux
native delivery remains deferred. These local ad hoc checks do not establish
Gatekeeper acceptance or production readiness on another platform.
