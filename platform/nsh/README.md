# LUI NSH desktop backend

Experimental replacement for the removed MyGo backend. The implementation is
in progress under [ADR 0004](../../docs/adr/0004-nsh-desktop-backend.md) and the
[migration plan](../../docs/agent-guide/006-nsh-desktop-migration.md). It does
not yet provide complete component parity or qualified distribution packages.
Apple/iOS, Android and Web keep their existing implementations and tooling.

## Build and run

Use Rust 1.97 with `rustfmt` and Clippy, the repository's OCaml/opam toolchain,
and the native prerequisites for the target. macOS needs Xcode command-line
tools; Linux needs GTK 4.14+/Pango development packages; Windows needs its Rust
and OCaml native toolchains. Every NSH dependency is pinned to the same source
revision in `Cargo.toml`, with exact transitive versions in `Cargo.lock`.
The current pin is `logseq/nsh` commit
`d21573c25984e9603bf878ae8bb73c1e23408936` on `fork/logseq`, containing the
minimal keyed-list and active-cell-demand repairs plus upstream main
`de7f3637171b769f18474796fd5159a60b2de726`
([review](https://github.com/logseq/nsh/pull/1)).

```sh
rustup component add --toolchain 1.97.0 rustfmt clippy
LUI_OCAML_LIBRARY="$(bash tooling/build_nsh_todos.sh)" \
  cargo run --manifest-path platform/nsh/Cargo.toml
```

The native library currently builds through the helper on macOS and Linux.
The Windows native DLL builder is `python tooling/build_nsh_windows.py
--application todos` (or `components`), using the pinned native Win32 x86_64
OCaml 5.5.1 compiler and its configured C/FlexDLL toolchain. It compiles and
loads a real DLL, checks the exported bridge ABI and writes a build receipt.
The Windows CI job exercises that DLL and the packaged application; actual
Windows execution remains a qualification gate. A Rust-only build does not
establish OCaml Windows support.

The shell uses a Rust root and native NSH platform runners; no QuickJS or
WebView is needed. `nsh.json` declares the root for pinned-CLI packaging.
The [delivery wrapper](DELIVERY.md) copies the matching OCaml library and
resources, verifies source/architecture receipts, applies signing hooks and
rebuilds complete archives. The real arm64 macOS Todos package has passed
outside-checkout launch, input/add/clear and ad hoc signature verification.
Full installed LUI upgrades, other native targets and credentialed distribution
signing still require qualification.

The default standalone root is `DesktopApp`. When a matching installed updater
asset is configured, it owns native application-menu update actions and an
explicit install/restart confirmation. Without the asset it creates no updater
worker or network request. Rust embedders use `Desktop` to retain their own
application menu ownership. See [the delivery guide](DELIVERY.md) for the signed
whole-application updater and the remaining qualification boundaries.

## Ownership and updates

One persistent worker initializes and calls the process's OCaml runtime.
The initialized library stays resident, and the process admits one active
application session. Reopening reuses that worker and resets application
state. A different OCaml library needs a separate process.

The NSH engine has one bounded input/clock request pump. It asynchronously
waits for the worker, publishes ordered atomic batches and schedules only
the next application deadline. There is no bridge frame poll. A refusal
reports its diagnostic and returns an authoritative snapshot. Ordinary
batches require sequential generations; snapshots establish a new baseline.

Node signals retain identity. Child structure has a separate signal and
uses public keyed `each` ownership, so property edits do not reconstruct
descendants. The application root comes from the native ABI; its component
kind need not be `root`. Keys and test identifiers belong to actual native
elements instead of layout-changing wrappers.

## Checks and remaining gates

```sh
make test-nsh
make test-nsh-integration
```

`cargo test --manifest-path platform/nsh/Cargo.toml` runs the same Rust tests;
the OCaml integration executables build their real Todos library using the
native helper. Distinct fixtures run in separate executables to isolate
OCaml runtimes. Run `make test` separately for existing schema/OCaml checks,
and the maintained Apple, Android and Web checks for full qualification.

Current targeted evidence includes real Todos Chinese input, submit, keyed
reorder/delete and reopen; native refusal/resync, embedded-NUL UTF-8 payloads,
agent compatibility and repeated start/stop; transactional rollback, snapshot
generations, exact large IDs and sparse retained-node sharing.

The upstream public-list probe failed focused-cell identity preservation
for 1,000 and 100,000 items. The authorized repair passes both sizes, retaining
23 demanded cells after a far jump and preserving the edited input. See the
[reproducer analysis](../../docs/agent-guide/review-probes/2026-11-11/nsh-keyed-list-reorder.md).
Bounded-row negotiation remains disabled. The adapter rejects unimplemented
components before publishing their batch instead of silently substituting
empty views or eager source lists. Keep this regression enabled while the
full sparse LUI adapter is qualified.

Headless tests do not qualify native appearance, IME, screen readers,
performance distributions, signing or update installation. Those require the
plan's actual OS and package evidence. Do not claim the migration complete
until those gates pass.
