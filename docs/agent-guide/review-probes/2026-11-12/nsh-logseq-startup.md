# Logseq NSH compiler and startup qualification

## Enforced checks

Canonical constructor metadata supplies closed native domains. The NSH display
and image-fit providers consume generated enums with exhaustive matches. The
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

- LUI NSH: 225 tests, zero failures or ignored tests; strict all-target Clippy.
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
