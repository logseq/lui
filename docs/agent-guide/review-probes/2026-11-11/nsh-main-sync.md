# NSH upstream main synchronization

Date: 2026-11-11

The requested target is `longbridge/nsh` **main**, not the `v0.5.0` release
tag. Upstream main was fetched at
`de7f3637171b769f18474796fd5159a60b2de726` and merged into the authorized
`logseq/nsh` branch `fork/logseq`, producing immutable merge commit
`d21573c25984e9603bf878ae8bb73c1e23408936`. The previous published fork revision was
`028574b7de9ee25a7c6f60660ef72fcb8790a27e`.

The merge is conflict-free. Relative to upstream main, the fork retains the
same nine files for keyed-list identity, measured-size and interaction-owner
retention, explicit active-cell demand and commit settling. No proposed native
press API is included. Upstream's new measurement-anchor changes remain
intact alongside the fork's 1,000/100,000-row regression tests.

## Verification environment

- macOS arm64; Rust 1.97.0; the NSH-required `huacnlee/cargo` fork
  `0.102.0-9` (Cargo 1.101.0). Installing the required fork preserves the
  previous Rustup Cargo proxy as `~/.cargo/bin/cargo.rustup`.
- `CARGO_BUILD_JOBS=2`, `CARGO_PROFILE_DEV_STRIP=none` and
  `CARGO_PROFILE_TEST_STRIP=none`. Without the strip overrides, this host's
  linker/strip combination produces a QuickJS proc-macro dylib that dyld
  rejects with a misaligned LINKEDIT string pool. No source or warning
  settings are changed for this workaround.
- `TMPDIR` is the canonical physical path. The upstream CLI test's mock
  compares `$PWD` with its expected workspace as strings; `/var` versus
  `/private/var` aliases otherwise fail that comparison. The identical test
  passes with a canonical temporary directory.

## Results

`cargo test --locked --workspace` passed: **5,300 passed, 0 failed, 63
ignored**, across 94 reported test suites. Existing ignored tests remain
ignored; this is not evidence that all optional native checks ran. The log is
`/tmp/nsh-main-sync-workspace-tests-canonical-temp.log`.

`cargo clippy --locked --workspace --all-targets -- -D warnings` passed.
The required Cargo fork separately reports manifest unused-dependency warnings
for platform-conditional crates; these were not disabled. Log:
`/tmp/nsh-main-sync-clippy.log`.

`cargo xtask compat` passed against `longbridge/nsh-compat` commit
`e56ebce9857f2571607b919953a72c2fbb0f73d2`, including checkout applications
and verified coverage claims. No compatible release has been recorded yet;
the historical-release checks therefore have no frozen release fixtures.
Log: `/tmp/nsh-main-sync-compat.log`.

`cargo +nightly fmt --all -- --check` reports only import grouping in
`crates/nsh-platform-macos/src/native.rs` and
`crates/nsh-platform-windows/src/native/web.rs`. Both files are unchanged by
the fork. Checking the exact upstream-main Git objects independently produces
the same diffs with rustfmt `1.12.0-nightly (9c5648833e 2026-11-10)`.
These upstream formatting differences are not silently reformatted as part
of the synchronization.

## Adapter follow-up

LUI must keep one exact immutable fork revision across every NSH crate and
its Cargo lockfile; it must not depend on a floating `main` branch. Re-run
the adapter's retained-editor, virtual-row, event and OCaml integration tests
against that revision. Packaging and upgrade evidence from the previous pin
remains historical evidence and does not qualify the synchronized revision.

The adapter manifest and lockfile now resolve all ten NSH packages to
`d21573c25984e9603bf878ae8bb73c1e23408936`. Full adapter tests passed:
**108 passed, 0 failed, 0 ignored**, including real OCaml Todos, clock,
runtime recovery, retained editors and 1,000/100,000-row sparse lists.
Strict all-target Clippy passed. The Python NSH tooling suite passed
**36 tests**, including the Windows portable asset-path regression.
The canonical contract and source-derived support inventory checks passed.
Logs are `/tmp/lui-nsh-main-sync-rust-tests.log`,
`/tmp/lui-nsh-main-sync-clippy.log` and
`/tmp/lui-nsh-main-sync-python-final.log`.

Upstream main adds `RadioGroupProps::accessibility_label`. Reuse that public
prop where it preserves the LUI host-event contract. The inspected ContextMenu
layout-through, controlled Toast swipe refusal and fitting-proposal API gaps
remain; see [the surface API review](nsh-surface-api-gaps.md).
