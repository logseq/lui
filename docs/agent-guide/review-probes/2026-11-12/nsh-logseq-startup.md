# Logseq NSH compiler and startup qualification

## Enforced checks

Canonical constructor metadata supplies closed native domains. The NSH display
and image-fit providers, frame axes, popup direction, popup alignment and orientation consume
generated enums with exhaustive matches. The
compiler regression runs the actual provider functions, then adds a canonical
case and requires Rust E0004. Open CSS strings retain typed parsing and atomic
preflight; arbitrary dynamic values are not claimed to be statically proven.

The actual Logseq build checks contract freshness, snapshots its scoped source
inputs, and builds a private candidate executable, OCaml library and resources.
Before publication, an isolated Headless process loads that real application,
opens its sidebar through the native button, and requires Demo/Journals plus a
visible dated journal title in the nonzero measured main scroll region. Backend
errors fail the gate even outside the viewport. Changed sources or a failed gate
leave the previous publication intact. Successful receipts describe the tested
bytes and are published last.

## Locked-screen native evidence

The regular native backend was launched in background mode with the explicit
private qualification flag, empty owner-local credentials and private storage.
The fresh loopback listener was identified before requesting a screenshot with
`tooling/lui_agent.mjs --artifact ...`. No screen-unlock, display-power or
application-activation action was used.

The inspected 2880 by 1800 content capture is
`_build/nsh/logseq-native/qualified-journal-body.png` in the LUI checkout. It shows
the real `Nov 12th, 2026` heading and empty journal block, rather than only header
icons or a backend diagnostic. The capture remains an ignored local artifact.

This revealed a real difference from ordinary Headless tests: macOS display-link
ticks stop while locked. DOM host services now synchronize with the public
commit callback through `app::wait_for_commit`, and measurement requests supply
their own layout commit. The regression starts the public engine with a mount
sink that never delivers display frames; mounting, a real 320 by 180 measurement
and result publication complete with zero requested frames.

## Validation and remaining acceptance

- LUI NSH at `8f60110e`: 229 tests, zero failures or ignored tests; strict
  all-target Clippy. Six closed domains reject injected future cases with E0004.
- NSH tooling: 45 Python tests, including the future-enum compilation proofs.
- Logseq UI: 5636 checks, zero failures; shared native/Web contracts also pass.
- Logseq Rust host: 31 library, binary and actual startup tests pass; strict
  all-target Clippy also passes.
- The CLI skill is installed through the versioned repository skill and validates.

This establishes the private Demo startup path and a light native content frame.
It does not complete the migration. The actual `refactor/lui` integration,
master UX comparison, dark visual review, interactive editor/IME, operating-system
accessibility, platform performance and packaged signing/update acceptance remain.
Graph View is excluded; other graph-backed features and assets remain required.

## Canonical CLI and real application packaging

The actual Logseq seven-argument bridge now additionally exports the existing
optional semantic agent ABI. It forwards through `Lui_agent.app_target` under
the application entry lock, draining ordered batches before replying. The native
host uses the same worker and publisher as ordinary events. No second selector
engine is introduced. A Rust/C fixture verifies UTF-8 request lengths, same-worker
execution and ordered patch/platform callbacks with the semantic reply.

At LUI `44a3be2c` and Logseq `d5f1887ea3`, the fresh background native process
answered `hello`, found and pressed the actual left-menu control, then produced
`_build/nsh/logseq-native/qualified-sidebar-cli.png`. The inspected capture shows
the Demo sidebar, Journals and the real dated journal body. Neither activation
nor a display-power operation was used. These actions inspect the semantic tree;
they do not qualify physical pointer or keyboard input.

The actual macOS `Logseq-NSH-darwin-arm64-2.0.2.zip` was built from the qualified
host, real OCaml library, DB worker and receipt-owned resources. Relocation and
ad-hoc bundle signing/verification passed. The archive was extracted outside the
checkout; the actual App startup gate passed using its packaged library, worker
and resources. That gate remains Headless: it does not establish native packaged
window launch, Developer ID distribution, notarization or whole-app updates.
Five package ownership/freshness/installed-launcher tests and three Windows DLL
source guard tests passed. No actual Windows application build is claimed.

The native CLI More action exposed another genuine gap: externally anchored menu
popovers are rejected. The body-only startup gate did not visit that surface.
The next build gate must exercise real menus as well as the journal body; menu
support and master parity remain unfinished. Old screenshot and package evidence
must not be presented as qualification of later source changes.
