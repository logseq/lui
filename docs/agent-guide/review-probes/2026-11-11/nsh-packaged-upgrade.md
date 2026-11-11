# Actual packaged LUI upgrade qualification

This is a local macOS arm64 result for NSH
`028574b7de9ee25a7c6f60660ef72fcb8790a27e`, Rust 1.97.0 and the LUI
component/event checkpoint following `ca572bea4da6d3b20a1fa6620885c896b8e5043a`.
The migration remains incomplete. This result does not establish production
signing, HTTPS transport, native menu-triggered restart or cross-OS UI parity.

## Method and source identity

`tooling/qualify_nsh_upgrade.py` built two small Rust-root applications that
depend on the actual local `lui-nsh` crate. Each contains its own compiled Rust
version marker and a matching compiled OCaml fixture, using the regular delivery
wrapper and the exact pinned NSH CLI. They are complete native applications,
not replacement scripts or a code-only update.

The qualifier checks both applications outside the checkout with library and
dynamic-loader overrides removed. It edits the real OCaml draft and invokes its
counter action, checks the accepted text and count, then closes its owned N1
process. The native updater authenticates the CLI-signed N2 manifest, verifies
and installs the complete archive, and the driver starts the installed path.
Both Rust and OCaml must now report 2.0.0 and pass the same reducer checks.

Both package receipts contain the same `luiSourceHashes` map as the persisted
qualification snapshot. It covers 80 inputs: manifests/lock/config, Rust sources,
the included canonical contract, shared SVGs and their licenses. Delivery checks
these inputs before building and again before publishing. The qualifier also
compares the source map before and after its complete run. The external
`installedCodeSha256` map records final code bytes after relocation/signing,
separately from OCaml build-input digests.

Evidence directory: `_build/nsh/upgrade-qualification-source-evidence/`.
The byte digest of `lui-source-snapshot.json` is
`0dda73e505dd9b9228219ddb043683e8f83c0bff59f284bd495bd30ca9aa271e`.
The result and both receipts retain the complete per-path map. A separate root
check confirmed the current compiled sources still matched that map before
committing this checkpoint. Build outputs and test keys remain ignored.

## Results

The actual qualifier exited successfully. N1 reported Rust/OCaml 1.0.0; the
restarted installed application reported Rust/OCaml 2.0.0. Both accepted a unique
edit and produced counter value 1 after one action.

| Final code | N1 SHA-256 | N2 SHA-256 |
| --- | --- | --- |
| Native executable | `ba4828ecf6c5664730f3c06faebfce5e9a8c6b2c308da403f6daf1869df43439` | `f789d4b372245469f4693479f28dc0d76b0841a965999ae2a427e1640dd4c7ec` |
| OCaml library | `e82c2619ec59eebac25c6b46f349cca88dbb859cbe9596bb11a417b8ebd88686` | `79fc30f840326e45fda4595bbb171a2bd836546323a3c8c4e9759eb8ade328a8` |

The N2 archive digest is
`ccdda5fe012c2bdc3399d6e497fe603c2f7e602ad929d5d72bd6e8fa18ebd061`.
Both expected final code hashes are checked against the N2 receipt before
installation and against the installed files afterward.

A modified signed manifest was rejected. Corrupting an already verified cached
archive was rejected before replacement, with the old executable and library
hashes unchanged. The subsequent successful install replaced both halves.

At the matching source checkpoint, the complete LUI Rust suite passed **81 tests,
0 failures and 0 ignored**, including 66 library tests and real OCaml Todos,
clock, runtime and bounded-row fixtures. Strict all-target Clippy and formatting
passed. All **35 Python NSH tooling tests** passed together. These counts are
local results; they do not imply every native platform gate has passed.

## Reproduction and limits

After installing the pinned CLI with `tooling/nsh_delivery.py setup`, run:

```sh
python3 tooling/qualify_nsh_upgrade.py --work _build/nsh/upgrade-qualification-fresh
```

Use a fresh work directory: successful qualification has already replaced N1
with N2. The deterministic fixture key and reserved non-live HTTPS URL are
test-only. Authentication and installation use locally staged assets, with no
network server. The external driver owns quit/restart; this is not proof of
HTTPS download or the standalone menu's operating-system restart path.

Code was signed ad hoc and verified on macOS. Developer ID/notarization and
Windows/Linux delivery require their own evidence. Agent commands prove the
real packaged application/reducer seam, not OS-native IME, screen reader,
keyboard injection, frame timing or visual appearance. Those gates remain open.
