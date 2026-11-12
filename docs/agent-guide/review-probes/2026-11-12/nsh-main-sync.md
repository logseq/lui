# NSH upstream main synchronization

Date: 2026-11-12

The authorized `logseq/nsh` branch `fork/logseq` now contains official upstream
main snapshot `f60a4791b9b5a26ede288a80792c7b8c542e138d`. The immutable fork
checkpoint is `ea23ae9cd5f56426145ea225f1a220e1eca0d3a2`; the previous LUI pin
was `bfa15d0c843c0d6f5bf3a2a230e8ca56b876b61c`. The synchronization keeps the
authorized keyed-list and native sibling-reorder repairs. It adds no application
geometry API or new fork dependency. Upstream's manifest and lockfile contents
remain unchanged by the merge.

The source qualification ran in `nsh.worktrees/main-refresh` on macOS arm64,
using Rust 1.97.0, the existing huacnlee Cargo/shared cache, two build jobs and
the recorded macOS strip overrides. No compiler or linker warnings were disabled.

| Check at the immutable fork checkpoint | Result |
| --- | --- |
| `cargo test --locked --workspace` | 5,340 passed, zero failed, 65 ignored, 94 suites |
| `cargo clippy --locked --workspace --all-targets -- -D warnings` | Passed |
| `cargo +nightly fmt --all -- --check` | Passed |
| `cargo xtask compat` | Passed against `nsh-compat` `e56ebce9857f2571607b919953a72c2fbb0f73d2` |
| `NSH_KEYED_FOCUS_BACKGROUND_ONLY=1 cargo test --locked -p nsh-platform-macos --test native -- --ignored` | Passed, without application activation |

The compatibility repository has no recorded release fixtures. Its success
therefore proves the checkout application/coverage checks, not compatibility
with frozen historical releases. Ignored workspace cases remain unqualified.
The separate GPUI workspace and actual Linux/Windows platform execution are
not established by this macOS workspace run.

The background AppKit probe verifies retained native editor/responder identity,
selection and window-local native keyboard input across keyed ancestor moves.
Its observed activation policy was Prohibited and `active=false`. This is not
hardware keyboard, foreground-focus or IME qualification. The test checks the
actual activation-policy state rather than assuming a redundant setter must
return true.

The GPUI CLI regression initially failed because its temporary expected path
used macOS's `/var` alias while the real CLI canonicalized it to `/private/var`.
The fixture now canonicalizes its own expected workspace; its dependency/output
assertions remain intact. The same fixture and the complete workspace passed
after that test-only correction.

Logs:

- `/tmp/nsh-main-f60-workspace-final-tests.log`
- `/tmp/nsh-main-f60-workspace-clippy.log`
- `/tmp/nsh-main-f60-format.log`
- `/tmp/nsh-main-f60-compat.log`
- `/tmp/nsh-main-f60-background-keyed-focus.log`
- `/tmp/nsh-main-f60-cli-workspace-test.log`

Cargo's platform-conditional unused-dependency diagnostics and the large native
test binary's compact-unwind linker warning remain visible. Strict Rust Clippy
success does not mean those separate diagnostics were suppressed or absent.

LUI and the actual Logseq application must use this same immutable NSH source
across all direct crates and lockfiles. Adapter, real OCaml, packaged startup,
production row/performance, native UX and signing/update evidence must be rerun
at their resulting application checkpoints. Earlier application archives do not
qualify the synchronized dependency.
