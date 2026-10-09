# Implementation review fixes

Source review: 001-implementation-review_report.md. All 22 P1/P2 findings are in scope.

Integration target: `/Users/tiensonqin/Codes/projects/logseq`, branch `refactor/lui`.
The checkout was clean at `855ca396a35c09a49e4b17457304778385964fad`.
Reference its TanStack bindings and virtual list behavior during the Web fix.
After the LUI changes, update this branch's dependency integration and affected
call sites, then build and run its focused UI tests.

## Workflow

- [x] Write regression tests for all findings, including failure and recovery paths.
- [x] Run tests and confirm behavioral failures before implementation.
- [x] Implement minimal fixes while preserving existing contracts.
- [x] Run focused and cross-platform verification.
- [x] Refactor only where it simplifies the fixes; verify again.

## Findings

- [x] F01: Sibling owner state identity
- [x] F02: Candidate mount cleanup
- [x] F03: Lifecycle commit and segment rollback
- [x] F04: Owned derived signals
- [x] F05: Subscription replacement cleanup
- [x] F06: Queued handler lifetime
- [x] F07: Android scalar decoding and integer width
- [x] F08: Compose node observation
- [x] F09: Android rejected-batch recovery
- [x] F10: Android bridge session lifecycle
- [x] F11: Android direct self-cycle rejection
- [x] F12: Compose child identity
- [x] F13: Local keyed transaction cost
- [x] F14: Affected Web validation
- [x] F15: Local Android patch cost
- [x] F16: Wide child operation scaling
- [x] F17: Web virtual-list windowing and scrolling
- [x] F18: Stable Apple List identity
- [x] F19: Web DOM application recovery
- [x] F20: False extension event fields
- [x] F21: GPUI protocol validation parity
- [x] F22: Executable performance qualification

## Constraints

Do not change Dune declarations or disable compiler warnings. No implementation changes during the initial RED phase. Use existing executable/test declarations and standalone tooling where necessary. Serialize every Dune invocation.

## Implemented behavior

Reactive owners have distinct sibling identities. Candidate mounts and segment
state roll back together, committed removals retire every scope even when cleanup
raises, and queued callbacks recheck their registration. PPX and library-created
derivations belong to each mounted view; caller-owned signals remain borrowed.

Android preserves JSON scalar types and 64-bit wire integers, exposes observable
state per node, journals affected nodes, keys Compose children by retained IDs,
rejects cycles, and retires bridge receivers by session token. A rejected delta
requests an authoritative runtime snapshot and suppresses deltas until recovery.

Web retains child sequences and indexes sibling operations without repeated list
copies. Validation stays local to affected nodes. TanStack Virtual owns windowing,
stable row measurements, scroll observation, and focused-row retention. Offscreen
DOM resources are released without discarding retained state. Tree navigation
uses the visible window. List scroll requests complete by token and report visible
ranges. A partial DOM failure rebuilds the mirror from the committed store.

Apple List keeps row-local identity across property commits. GPUI validates
standard kind/property/scalar and child contracts, including context menus, with
admission tables exported from the canonical OCaml protocol. Its imperative input
and attribute writes now use the corresponding standard or extension boundary.
Fixed extension CSS dimensions participate in GPUI leaf caching.

GPUI extension specs remain renderer metadata for trusted, OCaml-validated
extension traffic; they do not implement the typed OCaml extension registry.
This capability difference is explicit in platform/gpui/README.md. Standard-node
validation and extension/standard property boundaries are enforced by the store.

Both performance entry points execute in CI. Native qualification covers local
text updates, sustained typing, keyed edits/reversal, flat mounting, wide child
reversal, scroll callbacks, and repeated branch mount/dispose.

## Dependencies and CI

The locked overlay now pins ocaml-signal main at
`df355e15869ceb7220c0365ae7057e4c3fc558b2` (2026-10-09). This contains ranked
propagation, robust disposal, and subquadratic keyed reconciliation. TanStack
Virtual Core is pinned to 3.17.11. Drive remains at
`1e1653d5bdd0810e89d9e3a32b2e0ea2811c1cf5`.

The supplied GitHub job already hit both caches; setup-ocaml nevertheless spent
about 70 seconds updating opam repositories. The new composite restores the
complete compiler/dependency switch before setup-ocaml, skips setup on a hit,
preserves the opam executable, and keys by runner image, architecture, compiler,
dependency manifest, scope, and weekly refresh epoch. Compiler is fixed at 5.5.1.
Actionlint passes. Cache speed/hit behavior awaits the next real Actions run.

## Verification

- OCaml runtime: 100 tests passed with the latest ocaml-signal.
- Schema/PPX/watch tooling: 7 tests passed, including directly mounted reactive
  constructors used by Logseq and constant work across branch replacements.
- Web unit checks: 53 passed. The broader browser suite passed 101 tests before
  the final window edge cases; all seven focused review regressions subsequently
  passed in Chromium, Firefox, and WebKit. Vite hot reload passed.
- GPUI: 83 tests passed across core, renderer units, bindings, and interactive
  regressions. Invalid legacy fixtures were corrected to canonical wire shapes.
- Android unit tests passed; Gallery compileDebugKotlin passed. Snapshot rejection
  and recovery, observation locality, child identity, stop, and failed loading
  have regressions. Real JNI rotation/rejection recovery was not device-tested.
- Swift: the full 168-test suite passed, followed by the focused live SwiftUI
  row-state regression. iOS Simulator arm64 and x86_64 build-for-testing passed.
- Native C bridge GC stress passed.
- Runtime qualification passed all nine configurable budgets. Example native
  measurements: flat mount 10k 13.2 ms, reversal 10k 2.9 ms, 1000 branch lifecycle
  updates 3.9 ms. These exclude host layout/paint and are smoke measurements.
- GPUI release single-property store updates measured 0.3–0.6 microseconds at
  100/1k/10k/50k nodes. These exclude rendering.
- Logseq refactor/lui built js_app and test, then passed 1924 UI checks and native
  and Web contract tests with the updated local LUI and signal packages.

## Remaining validation limits

A full Dune @all build hits an existing native-example sandbox failure: four
example rules omit lui_caml_dispatch.h from their declared dependencies. No Dune
files were changed because AGENTS.md prohibits this without explicit permission.
The application/library, Web, runtime tests, and bridge stress builds above passed.
Android emits existing Kotlin deprecation/redundancy warnings; GPUI's block 0.1.6
dependency emits a future-incompatibility warning. These were not suppressed.

The old LUI branches were removed (13 local and 127 remote), retaining main.
Existing worktree contents were preserved by detaching them. A new
fix/review-runtime-and-renderers branch holds this review's PR.
