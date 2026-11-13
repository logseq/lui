# NSH desktop migration implementation plan

Date: 2026-11-11

Status: implementation in progress on
`feat/nsh-desktop-backend`

Decision: [ADR 0004](../adr/0004-nsh-desktop-backend.md)

## Objective and completion rule

The final acceptance target was explicitly clarified on 2026-11-12: the actual
`logseq/logseq` `refactor/lui` branch must completely replace its MyGo desktop
backend with NSH, then undergo a real UX review and fixes against Logseq
`master`. Graph View rendering/interaction is excluded; database graphs,
repositories, workers, references and non-Graph-View navigation remain in scope.
A component fixture or a green LUI library suite does not complete this target.

Priority is the real application's typed startup ABI, worker wakeups, host
services, registered raw/editor/CodeMirror/PDF components, resources/icons,
build/launch/package scripts and persisted application behavior. After native
startup works, remove the old Logseq MyGo implementation and its active build,
launch and packaging paths. Preserve maintained mobile/Web backends and do not
modify Dune files. Generic unused component refinements must not displace the
actual application cutover and UX acceptance work.

The initial integration snapshot is Logseq `refactor/lui`
`29dcb60fdc976dcda1da6ec984057bbf79d88612`. The UX comparison baseline fetched
from `origin/master` is `29fd2edd015e12963742b985ce6d2311c074e09b`.
Record a new explicit comparison revision if this baseline is later refreshed;
"align with master" means reviewed product behavior/UX parity, not an automatic
merge of master into the refactor branch.

Final integration gates:

- Build and run actual Logseq through NSH on the supported desktop targets;
  no MyGo process, runtime library, source dependency or active launch/package
  script remains on the final `refactor/lui` path.
- Use an isolated qualification graph to exercise startup, editing/IME,
  navigation/sidebars, search/commands, properties/tables, menus/shortcuts,
  dialogs, persistence/sync, assets/PDF, extensions and packaging/update flows.
  Graph View is the sole explicitly excluded product surface.
- Review real native screenshots and interactions against the frozen master
  baseline in light/dark, narrow/wide windows, keyboard and accessibility flows;
  record findings, fixes and remaining differences with exact revisions.
- Pass relevant LUI and Logseq tests and all previously required native,
  performance and delivery gates. Do not mark complete while real application
  integration or UX differences remain unverified.


Replace MyGo with an NSH desktop backend for macOS, Windows and Linux. Preserve
the existing LUI application API except for the documented desktop host
migration, keep Apple/iOS, Android and Web maintained, and provide packaging,
distribution-signing integration and whole-app update support. All required
tests must pass. Do not mark this plan complete with compile-only evidence,
partial required-component support, eager source-row rendering or missing OS results.
The user explicitly excluded mobile-only SwipeActions/SwipeAction from NSH
desktop scope on 2026-11-12; preserve their shared contract and mobile backends.
The required desktop component set therefore contains 85 of the 87 common kinds.

Use NSH public Rust APIs pinned to `logseq/nsh` commit
`adc186db7213f3ccd1eacaa836cc721e9779fd14`, Rust 1.97 and committed Cargo
lockfiles. This merges official upstream main
`f60a4791b9b5a26ede288a80792c7b8c542e138d` with the authorized keyed-list
and native editor-focus repairs. It also includes the approved read-only
committed-text geometry API, Checkbox/Link activation modifier events and
native relative font-size inheritance. See the
[synchronization evidence](review-probes/2026-11-12/nsh-main-sync.md) and
[native focus regression](review-probes/2026-11-11/nsh-keyed-native-focus.md).
The pin also contains the existing CLI's release package feature-policy
correction. Its CLI regressions pass, while fresh native packages and upgrades
on all three desktop targets remain acceptance gates. See the
[package-policy evidence](review-probes/2026-11-12/nsh-package-feature-policy-proposal.md).
The initial research and official `nsh` / `nsh-design-guides` skill installation
used `cdfdf75c1509cdb34c6220e6b5bf923452c0cb76`. Read their relevant
references and the nearest source/tests
before changing each adapter boundary. Read LUI's reactive skill before
authoring `Lui_elements` views.

No Dune files may change. Do not suppress compiler warnings or use unsafe type
casts. Preserve mobile packages, JNI and their tooling. Record every actual
public/default/event/wire change, with downstream examples, in
`docs/api-migrations.md`. Do not commit downloads, caches, build products or
recordings. Serialize Dune invocations and performance measurements.

## Compiler and pre-launch compatibility gates

The user strengthened acceptance on 2026-11-12 after real Logseq startup exposed
unsupported `display: contents`, `font-size: 1em` and `white-space` values.
Known provider gaps must be found before opening an application window wherever
static information permits it. Route counts and isolated constructor tests are
insufficient compatibility evidence.

- Generate closed provider value domains from the existing canonical typed view
  schema/contract. Require exhaustive Rust lowering for those domains, so adding
  an enum case produces a compiler error until its semantics are handled. Do not
  introduce a parallel capability JSON source or a wildcard that hides new cases.
- Parse open style grammars into typed internal values with exhaustive lowering.
  Known static literals should be checked by the compiler/PPX or an explicit
  compilation-stage capability pass where target information is available.
  Preserve shared mobile/Web source and avoid claiming a target check is active
  merely because an unused PPX option exists.
- Keep checked construction for dynamic values and pure transactional preflight
  before native publication. This remains necessary even with static checking.
- Prefer constructor types over a literal-only check when a constraint is a
  closed domain: the restriction must also survive aliases, optional forwarding
  and reactive expressions. Add positive and negative compiler probes without
  weakening warnings. Generated provider exhaustiveness alone does not reject
  an existing, explicitly unsupported value at the application call site.
- Gate the actual Logseq build/launch on a headless startup test using its real
  OCaml library, registered factories, platform services and DB worker, with an
  isolated graph/state root. Fail on backend diagnostics and require positive
  native chrome evidence. The gate runs before producing a fresh launch receipt;
  it does not qualify native pixels, IME, performance or all conditional views.

## Evidence and starting state

- The existing `make test` run completed successfully, including 249 core
  cases. This is a baseline, not final NSH qualification.
- An initial Rust adapter passed `cargo check`; it is a feasibility skeleton
  with known correctness and presentation gaps, not a usable replacement.
- The worktree already contains MyGo deletions, tool renames and `NshHost`
  changes. Current Makefile/README/CI integration still needs reconciliation.
- `platform/nsh/contract.json` currently includes the development oracle and
  validator AST (about 1.3 MiB). Split test-only export data from shipped
  validator artifacts.
- Public virtual-list requested-window/pin integration, the real OCaml bridge,
  Windows OCaml linking, final packaged resource lookup, distribution signing
  and update installation have not been demonstrated. Resolve these through
  the stages below; never report them as completed research proofs.

## Stage 1: prove the integration seams

Complete before broad component implementation.

- [x] Build a minimal Rust-root fixture through public `Root`, engine and
  platform APIs, without QuickJS. Keep the fixture inside the adapter's
  existing Cargo structure; no new OCaml/Dune target is needed.
- [x] Prove an ordered OCaml worker request/response path using the existing
  C ABI and a real Todos library. Press and edit through `nsh_testing::Headless`
  and observe OCaml-generated updates. Run each distinct OCaml library in an
  isolated process.
- [ ] Prove node identity survives property updates, child insertion and
  sibling moves; verify the actual editor retains focus/selection.
- [x] Prove the public `virtual_list` cell position/lifecycle APIs can drive
  LUI `VirtualWindow` feedback for viewport, overscan and retained distant
  rows. Verify the same logical extent with bounded mounted LUI and NSH nodes
  for 1,000 and 100,000 source items.
- [ ] Exercise focus, composition, text-selection ends, a pressed row and an
  open row menu through far scrolling and source reorder. Determine which
  retention information is observable through public APIs, rather than
  equating visible indices with the complete requested window.
- [x] Exercise a provisional package on macOS with the OCaml library loaded
  from its resources, without a checkout-relative path. Verify the pinned
  CLI and generated runner resolve one NSH revision.
- [x] Establish Windows DLL build/loading with the actual OCaml Windows
  toolchain, and Linux shared-library loading on Linux runners. A POSIX shell
  stub or a Rust cross-check is insufficient evidence.

Deliver an evidence section at the end of this plan with the exercised
commands, source revision and results. If a seam fails, reduce the failure to
a concrete test and revise the ADR before building around it. The user has
authorized a minimal keyed-list fix in `logseq/nsh`, branch `fork/logseq`;
verify it and pin its exact commit. Do not add private-field access from the
adapter, another virtualizer, an eager source fallback or unrelated fork changes.
Continue independent work on other seams while resolving it.

## Stage 2: canonical wire and transactional store

Primary files: `platform/nsh/src/{wire,store,contract}.rs`,
`tooling/export_native_contract.ml`, `tooling/generate_nsh_contract.py` and
adapter tests.

- [ ] Preserve batch fields, all operations, unknown-field compatibility,
  integer precision, property removal/defaults and existing event ordinals.
- [x] Add sequential generation checks and an explicit authoritative snapshot
  path. Test missing, repeated, stale and skipped generations; resync may
  replace the tree at the current generation.
- [ ] Complete atomic final validation: canonical value domains, required
  properties, cross-property invariants, parents/children, cycles, extension
  fingerprints and sparse virtual metadata. Rejection preserves generation,
  identity counters, root, retained nodes and native UI.
- [x] Use touched-node rollback/commit, indexed root access and explicit
  iterative subtree disposal. Avoid cloning the complete map or walking
  descendants for ordinary property updates. Account separately for an
  affected parent's child-vector cost.
- [x] Generate compact validator tables/functions from the canonical export.
  Keep the canonical oracle in test data only; do not ship an AST interpreter.
  Make regeneration deterministic and `--check` compare actual generated
  contents, including rejection of modified output with unchanged hashes.
- [ ] Add canonical oracle comparisons, malformed-batch/property cases,
  transactional failure cases, large integers and randomized operation
  sequences that check invariants against a simple test model.

Acceptance: canonical value/kind/final-node verdicts agree, rejected batches
are invisible and sparse edits do not perform full-tree work.

## Stage 3: bridge lifecycle, events and clocks

Primary files: new focused Rust runtime/FFI modules, the shared native bridge
only where necessary, and `tooling/build_nsh_{todos,components}.sh`.

- [ ] Resolve C functions with typed `libloading` signatures. Keep unsafe code
  confined to FFI with documented pointer, length, callback and lifetime
  invariants. Copy callback bytes before returning to C; contain Rust panics
  at callback boundaries and report failures.
- [ ] Keep OCaml startup and every later call on one persistent worker. Keep
  its initialized library resident, allow one active session and make failed
  startup, repeated start/stop, disposal and process shutdown deterministic.
- [ ] Use established wakeable channels/futures, ordered replies and session
  guards. Do not block the NSH engine or platform UI thread. Define queue
  capacity and overload behavior; preserve edit/command ordering, coalescing
  only superseded maintenance work.
- [ ] Implement every admitted event with canonical payloads and modifiers,
  including focus-within, pointer, navigation, file requests and extensions.
  Distinguish user events from internal virtual-window maintenance.
- [ ] Deliver all batches in callback order, publish each validated batch
  coherently, recover refusals through last-error and authoritative resync,
  and discard replies from disposed sessions/incarnations.
- [ ] Drive the OCaml clock from its next deadline. Recheck after start,
  dispatch, agent calls, resync and pause/resume. Test timers created and
  cancelled by handlers without a continuously ticking poll loop.
- [ ] Preserve the opt-in loopback agent protocol and build receipts. Reuse
  the existing OCaml agent implementation instead of implementing another
  selector/action engine in Rust.
- [ ] Test startup signal-stack preservation, callback refusal, worker
  ordering, stop/restart, missing optional exports and clock quiescence through
  real OCaml libraries, including Windows and Linux.

Acceptance: real application lifecycle and refusal tests pass; there are no
idle bridge wakeups when no timer/request is pending.

## Stage 4: retained components and LUI presentation

Primary files: retained renderer, a small `platform/nsh/src/ui/` layer,
theme/resource modules and a generated support inventory.

- [ ] Inventory all 87 canonical kinds. For every admitted property, event,
  default and child relationship, name its implementation route and behavior
  test; distinguish native-platform qualification from headless coverage.
- [ ] Separate child-structure notification from property bindings. Create
  owners only for retained behavior and dispose them exactly once. Use stable
  node/incarnation keys; no identity-only wrapper may change layout.
- [ ] Implement layout/text and containers, including stack/overlay/insets,
  fitting, grid spans, inherited typography, rich inline content and property
  removal. Do not pass kebab-case LUI property names blindly to NSH styles.
- [ ] Implement buttons, input families, toggles, radios, slider/stepper,
  select/combobox and tabs with the corresponding NSH semantic behavior.
  Preserve controlled rejection/normalization, read-only editing, caret,
  composition, keyboard navigation, disabled state and event counts.
- [ ] Implement menus, tooltips, dialogs, popovers, drawers/sheets, toasts and
  navigation compositions on NSH behavior roots; preserve triggers, controlled
  open state, dismissal ordering, focus return and nested ownership.
- [ ] Implement remaining collections, tables/trees, resizing/split, media,
  files, icons and host services. Reuse existing portable LUI services where
  applicable rather than introducing competing native service implementations.
- [ ] Implement the application-scoped extension/tweak registries and
  fingerprint validation. Unknown selected capabilities fail atomically;
  never fall through to an empty generic view.
- [ ] Reuse LUI light/dark/system theme tokens, icon assets and density/variant
  defaults. Style every NSH part and state, including focus-visible and
  checked/selected/disabled. Explicit authored data colors stay data.
- [ ] Record the changed Gallery/demo motion inventory before presentation
  code. Preserve existing LUI transition meaning; use native transitions and
  reduced-motion behavior without per-frame OCaml round trips. Streaming text
  and recycled cells do not replay entrance motion.
- [ ] Test real-engine press, keyboard, edit, focus, dismissal and lifetime
  behavior. Inspect native screenshots in both appearances, resize/large text,
  long/CJK content and the skill's full finishing checklist. Complete a
  keyboard-only flow and a screen-reader flow on an available native target;
  report other target evidence separately.

Acceptance: no silent component/property fallback, inventory coverage is
complete and semantic tests demonstrate the behavior rather than only node
existence. Keep any explicit platform exception narrow and documented.

## Stage 5: bounded virtual rows and scrolling

Build on Stage 1's proven public seam and the existing
[bounded-row contract](005-bounded-virtual-rows.md).

- [ ] Use logical count plus sparse committed rows and temporary host geometry
  while requested rows arrive. Do not manufacture LUI row identities for
  placeholders or emit their appearance events.
- [ ] Bridge actual demanded cell positions and retained row owners to
  generation-scoped windows/pins. Coalesce feedback after coherent commits;
  reissue after snapshots and stationary-viewport pin changes.
- [ ] Handle source reorder/shrink/empty/removal, stale generations and node
  incarnations, variable heights, font scale, width changes and reading anchors.
- [ ] Preserve focused/composing/pressed/selected/popup-owning row identity
  while distant from the ordinary window. Release retention when the native
  interaction ends, including cancellation and disposal.
- [ ] Complete offscreen target jumps and exactly-once scroll-token outcomes,
  including missing, removed, superseded and cancelled targets.
- [ ] Preserve literal eager children and older-host/library negotiation.
  Enable the NSH bounded capability only after the end-to-end tests pass.

Acceptance: real OCaml Gallery load, far jump, edit/activate, return and Clear
cycles retain bounded row subtrees and preserve full scroll extent on all
three desktop targets.

## Stage 6: packaging, distribution signing and updates

- [ ] Add a reusable NSH Rust-root application shell and example `nsh.json`,
  pinned CLI setup, build/run/package commands and build receipts. Package
  scripts verify the NSH source and target architecture; no development-only
  absolute paths or mixed revisions may enter the runner.
- [ ] Put the matching OCaml library and required dependent libraries/assets
  in the package. Resolve paths relative to installed resources/executable,
  preserve Unicode/spaces and test launch outside the checkout.
- [ ] Produce macOS `.app`/update archive, Windows directory/ZIP/Inno installer
  and Linux directory/tarball on their own OS runners. Verify minimum supported
  OS/runtime libraries and architecture matching.
- [ ] Add parameterized macOS Developer ID signing, hardened-runtime settings
  where needed, notarization/stapling and verification. Sign nested code
  before the final bundle/archive. Add Windows Authenticode signing and
  verification for code and installer. Use credentials supplied by release CI;
  local ad hoc signing is not credentialed distribution evidence.
- [ ] Integrate `nsh-updater` with one HTTP transport, signed manifests,
  progress/cancellation and application-owned install/restart actions. Compiled
  OCaml/Rust changes always travel as one complete application update.
- [ ] Test signature/hash/size/app-id/version/platform checks, interrupted and
  corrupt downloads, non-writable installation, refusal to downgrade, install
  failure and a successful N-to-N+1 restart from packaged fixtures. Verify the
  documented preservation behavior on failure instead of promising automatic
  rollback after arbitrary post-launch application failures.
- [ ] Provide release documentation and scripts with a local test-key path.
  Production credentialed signing remains a release-environment qualification
  until actual credentials and results exist; record it as unverified, never
  mark it passed from a dry run.

Acceptance: runnable packages contain the complete application, signing hooks
are testable, local signed-fixture updates work, and distribution verification
is reported with its real evidence/credential limitations.

## Stage 7: remove MyGo integration and migrate callers

- [ ] Complete the MyGo source/dependency/CI removal and rename active tools,
  generated manifests, Makefile targets, current README commands and demo
  entrypoints consistently to NSH. Preserve generic native export tooling and
  old behavioral cases by translating the applicable tests.
- [ ] Complete `NshHost` / `"nsh"` / host code `6` across canonical generation,
  runtime profiles, exhaustive matches and native negotiation. Preserve mobile
  codes and ordinary event ordinals; do not repurpose MyGo code `5`.
- [ ] Add concrete downstream migration examples for host matches, extension
  profiles, build/run/package/agent commands, defaults and event semantics.
  State old/new host-library compatibility explicitly.
- [ ] Check the complete diff for unintended mobile, Dune, generated-source,
  dependency-tree and warning-setting changes. Historical MyGo design reports
  may remain as records; live instructions must not point to deleted tools.

## Stage 8: performance and full regression qualification

Limits below are acceptance targets, not results. Collect release measurements
on a named, otherwise idle machine; do not run heavy builds concurrently or
force collection to improve memory samples. Compare the same workload at the
baseline LUI commit `d6e9551266f73d5b9292d0eb92e82984c301e5db` and final head.
Use an isolated baseline worktree when needed, without altering the preserved
user stash.

| Workload | Required observation / gate |
| --- | --- |
| One label edit among 1,000 versus 100,000 retained nodes | No root/descendant reconstruction, unrelated node clone or complete-map scan. Adapter touched-node/binding counts stay constant. Record decode, validation, binding, NSH commit/layout and end-to-end timing separately. |
| Small local batch, up to 100 ordinary property operations | After warmup, target adapter decode/validate/publish p95 <= 2 ms on the named reference machine; compare 1k/100k background trees and investigate >20% median growth beyond measured noise. Exclude actual application/layout cost from this adapter-only claim. |
| Append, remove, reorder and streaming | Measure affected sibling-vector work and mount items; unchanged sibling identities survive. No O(n²) collection path or quadratic revalidation. Streaming does not remount its transcript. |
| 100,000 virtual source items | For a fixed viewport/overscan and fixed active pins, mounted LUI nodes/scopes/handlers and NSH cells remain bounded by those row subtrees, independent of total source length. Model/key/height indexes may remain O(n) and must be reported separately. |
| Focused edit + distant scroll/reorder | Same editor identity/caret/composition and accepted model value; no stale callback edits a recycled row. |
| Ten load/far-jump/Clear cycles | Return live adapter owners, handlers and mounted row counts to baseline; record RSS/physical footprint and peak allocation. Allocator capacity is not itself proof of a live-object leak. |
| 30 seconds idle, no app timer | Zero bridge polling/tick calls; record engine wakeups and CPU separately from operating-system display activity. |
| Native scrolling, popup and input | Record frame time/dropped-frame and event-to-visible latency distributions on each OS. Aim for a 60 Hz frame budget; attribute platform/layout/application outliers rather than claiming bounded adapter work proves frame-rate performance. |

Use NSH trace/headless observations and focused test counters before adding
caches. Any cache must have one invalidation owner and measurements showing
why it is needed. Keep diagnostics outside the production hot path by default.

Required test matrix:

| Area | Final checks |
| --- | --- |
| NSH contract/store/runtime | `cargo fmt --check`, `cargo check --locked --all-targets`, `cargo clippy --locked --all-targets -- -D warnings`, `cargo test --locked`; canonical oracle, model/failure tests and real-engine UI tests. |
| Schema/tooling | Component regeneration/freshness, NSH generated-output freshness, `node --test tooling/test/*.mjs`, Python tooling tests and native build-script tests. |
| OCaml | `opam exec -- dune build @all`, `make test`, explicit `opam exec -- dune runtest -j 1`, repository formatting checks, runtime performance qualifier and bridge GC stress. Serialize all Dune calls. |
| Apple/iOS | `make test-apple` with nonparallel Swift execution; existing SwiftUI/OCaml, UIKit bounded-row checks and iOS build-for-testing from maintained CI. |
| Android | Existing store/Compose and Drive tests, JNI/OCaml bounded-row fixture, sample builds/lints and native Gallery compilation from maintained CI. |
| Web | Existing production build, stylesheet/unit checks, visual baselines, Chromium regressions, Firefox/WebKit ownership/virtual rows and isolated hot reload, as defined by maintained CI. |
| Native desktop | macOS, Linux and Windows real-window input/IME/accessibility/resource tests, actual OCaml integration and packaged launch/update fixtures. Linux headless tests use an actual display server such as Xvfb. |
| Delivery | Packaging, dependency/resource checks, test-key manifest verification and update install/restart on each OS; credentialed distribution checks when the release environment supplies keys. |

Run full suites after integration; rerun affected checks after subsequent fixes.
Do not lower budgets, skip failures, delete applicable tests or update visual
baselines solely to make checks green. Distinguish native evidence from
headless evidence and results from unavailable checks. Cross-OS success needs
actual OS execution, not cfg-gated compilation on macOS.

## Stage 9: final review and evidence

- [ ] Record exact final source/dependency revisions, commands, test totals,
  OS/architecture, performance distributions, package results and remaining
  release-environment limitations here or in a linked qualification report.
- [ ] Verify `docs/api-migrations.md`, current usage documentation and generated
  support inventory agree with the actual implementation.
- [ ] Inspect the entire diff and any staged files, including untracked new
  sources. Confirm no Dune edits, warning suppression, dependency trees,
  secrets or build outputs.
- [ ] Mark implementation complete only when every required implementation and
  test gate passes. Record genuinely unavailable external qualification as
  outstanding; do not imply all-platform/all-tests success.

## Execution evidence

The latest actual-application integration checkpoint is recorded in
[production parent-viewport evidence](review-probes/2026-11-12/logseq-production-parent-checkpoint.md).
Earlier entries below remain historical, revision-scoped results; unchecked
acceptance requirements are not closed by this checkpoint.

2026-11-11 planning: official skills installed at the pinned NSH revision;
architecture, public Rust-root/list APIs, engine ownership and delivery/updater
source reviewed. Existing core baseline: 249 tests passed. Initial adapter:
`cargo check` passed with an irrefutable-pattern warning that must be fixed;
no NSH runtime/native/package/performance qualification has passed yet.

2026-11-11 implementation evidence (uncommitted LUI working tree):

- `make test` passed again, including all 249 core cases and the existing
  schema and auxiliary OCaml suites. `opam exec -- dune build @all` passed.
  No Dune file changed.
- Python native build-script regression: one test passed. NSH generated
  contract freshness and LUI `cargo fmt --check` passed. Rust Clippy passed
  with `-D warnings` before the subsequent dependency probe; rerun it after
  replacing the temporary local override with the immutable fork revision.
- Real Todos through OCaml/C ABI/NSH passed Chinese input, submit, keyed row
  reorder/delete, unchanged editor node identity and application reopen.
  A separate runtime executable passed embedded-NUL/Unicode payloads, agent
  compatibility, refusal/resync, same-generation snapshots, exclusive session
  ownership and repeated start/stop. Five transactional store regressions passed.
- Public virtual-list probes retain 23 live cell demands for both 1,000 and
  100,000 items and balance owner cleanup on explicit list unmount. The
  upstream revision failed focused-key reorder at both sizes. The authorized
  local `logseq/nsh` repair passes both cases and the new multiple-retained-row
  core regression. NSH core: 1,430 passed; 11 existing ignored benchmarks.
  Full NSH workspace tests, final fork publication/pin and broader qualification
  remain pending. The temporary Cargo path override is for this probe only.
- The macOS native runner compiled and launched. Visual inspection was
  unavailable because the desktop was locked; no native appearance, IME or
  accessibility qualification is claimed.

2026-11-11 dependency publication:

- Published the seven-file minimal NSH keyed-list repair to `logseq/nsh`
  `fork/logseq`, commit `a4c64cb33f739368f113d8eaf3c80cc335ef7253`, with
  [draft review #1](https://github.com/logseq/nsh/pull/1). The complete staged
  diff and diff against the fork's main branch were reviewed before pushing.
- NSH workspace tests passed: 5,258 passed, 0 failed, 63 existing ignored tests
  and doc examples. Workspace Clippy, strict core Clippy and `xtask compat`
  passed. See the linked public-list report for commands, trace controls and
  the unchanged baseline formatting/linker limitations.
- LUI now pins every NSH crate to that Git commit. The temporary local path
  override was removed and `cargo check --all-targets` passed against the pin.
  Rerun final adapter tests after the parallel contract/list implementations.
- Property-only retained-node updates now share their child sequence, avoiding
  full child-identity publication. Added 1,000/100,000-child regressions and
  stale-snapshot rejection coverage; runtime verification is pending the
  coordinated Rust integration run.
- Generated-output freshness now compares freshly exported contents, and a
  modified output with unchanged source hashes was correctly rejected.

2026-11-11 active-cell repair and immutable-pin qualification:

- Published the authorized demand-binding repair as
  `028574b7de9ee25a7c6f60660ef72fcb8790a27e` on `logseq/nsh` branch
  `fork/logseq`, in the existing [draft review #1](https://github.com/logseq/nsh/pull/1).
  It adds `Position::is_requested()` and flushes layout-generated binding
  patches before ending the virtual-list commit rounds. This lets the adapter
  release stationary offscreen pins using NSH's existing retention decisions.
- At that revision, NSH workspace tests passed: 5,259 passed, 0 failed,
  63 existing ignored tests/examples. Strict workspace all-target Clippy and
  `xtask compat` passed. Changed Rust files pass formatting; the unchanged
  baseline formatting and debug-linker limitations remain documented separately.
- Every LUI NSH dependency now uses that immutable Git revision. With no local
  override, locked all-target check, strict Clippy and formatting passed.
  The full Rust adapter suite passed 44 tests, 0 failed and 0 ignored, including
  the actual OCaml virtual fixture selected by `LUI_NSH_VIRTUAL_LIBRARY`.
- The real OCaml virtual fixture mounts 23 rows at both 1,000 and 100,000
  source items, with 85 LUI nodes and 142 NSH nodes. It verifies retained editor
  identity/focus, reorder, stationary blur release, shrink/removal, token
  completion and ten additional 100,000-row load/far-jump/Clear cycles. See
  [the active-demand report](review-probes/2026-11-11/nsh-active-cell-demand.md).
- Native controls have 42 explicit rendering paths, with 12 focused control
  tests; this is not a claim of complete semantic support for those kinds.
  Style/theme integration, remaining kinds/events/services, actual packaged
  LUI launch/update, native performance and full cross-platform qualification
  remain outstanding. The migration goal remains active.

2026-11-11 real macOS package qualification:

- The release CLI from NSH `028574b7de9ee25a7c6f60660ef72fcb8790a27e`
  built successfully. Its version output includes the revision suffix,
  `nsh 0.5.0 (028574b)`. Delivery accepts that checked format and rejects a
  different revision or a dirty-build suffix.
- Rust 1.97's stripped proc-macro library failed macOS 27's Mach-O
  alignment check. Delivery now sets `CARGO_PROFILE_RELEASE_STRIP=none` for
  macOS child builds, preserving optimization and warnings. The successful
  release CLI digest is
  `10f9ac2c9e5ae6432747b47850b17ac16f0b9696fc1277dedd922ba0afcc72f5`.
  See [Rust #157750](https://github.com/rust-lang/rust/issues/157750).
- The real generated runner resolved the pinned NSH sources and preserved
  every tested registry dependency tuple. Cargo's empty `.cargo-ok` marker
  is accepted; modified or untracked source files still fail verification.
  Application Rust sources and `build.rs`, when present, are hashed before
  building and checked again before release publication.
- `tooling/nsh_delivery.py package --target macos --arch aarch64` produced
  `LUI Desktop.app` and an 18 MiB update archive with the matching OCaml Todos
  library. Nested code and the final bundle passed ad hoc signing verification.
  The runner digest is
  `47dc8771b30c50f6c11805fad639e46e17eb1a4b6025a7c1b6092b358ed77fba`;
  the archive digest is
  `fc6fa0c6faff2ae05ad1acf39f497d1c3af1bdb007e385c55f9b16a316e8588d`.
- The real packaged-app qualifier passed from a temporary working directory
  outside the checkout, with library/runtime/dynamic-loader overrides removed.
  It received the versioned `Todos` hello, entered a unique draft, pressed Add,
  observed exactly one matching row and an empty editor, and terminated its
  owned native process. Evidence is under
  `_build/nsh-packaged-qualification-028574b7/`; build outputs remain ignored.
- This establishes the provisional macOS packaging seam, not production
  signing/notarization, full native input/IME/accessibility, cross-OS delivery
  or a packaged LUI N-to-N+1 upgrade. Those gates remain open.

2026-11-11 presentation, clock and release-store checkpoint:

- The immutable-pin Rust suite passed 63 tests, 0 failed and 0 ignored, with
  both real OCaml fixture libraries supplied explicitly. Strict all-target
  Clippy (`-D warnings`), formatting and diff whitespace checks passed.
- Scoped theme/style publication preserves native identities and separate child
  signals, validates inherited changes before commit and uses actual viewport
  measurements. Native select/combobox/menu keyboard and controlled-value
  cases, external popover dismissal/focus restoration and native tooltip hints
  have focused behavior tests. These do not establish complete property parity.
- A real clock regression reproduced a 120 ms timer remaining unfired under
  continuous input. The worker now synchronizes host time at request boundaries,
  preserving ordered timer/event batches and refusal recovery. Pause/manual
  advance and timer-free idle behavior remain explicit; no polling was added.
- All 29 Python NSH tooling tests passed together. The combined run caught and
  fixed a module-name collision that isolated qualifier tests had missed.
- Three release Store benchmark processes completed 24,000 measured
  transactions with identity assertions. For 100-property batches, transaction
  medians were 50–52 microseconds and p95 values 52–60 microseconds; 100k/1k
  median ratios were 1.016–1.029. See the
  [complete method and results](review-probes/2026-11-11/nsh-sparse-update-bench.md)
  for source hashes, sample distributions, overlapping validation stages and
  the noisy one-property case. This is not binding/layout/frame qualification.
- The additive `DesktopApp` standalone root now owns optional installed update
  configuration and native menu actions; `Desktop` remains the embedding root.
  Configured-menu and actual packaged LUI upgrade flows still need qualification.
  The Windows native DLL builder and CI steps are implemented, but Windows
  success requires execution on Windows and has not been claimed locally.

2026-11-11 pre-push review checkpoint:

- Fixed a real due-timer resync failure: the authoritative snapshot supersedes
  deltas emitted by the preceding clock synchronization. The actual OCaml clock
  fixture reproduced the failure before the fix and passed afterward.
- Structural sibling changes now validate retained dropdown ownership before
  publication, in one adjacency walk per changed parent. Same-incarnation
  toolbar axis changes reject atomically because native roving navigation fixes
  its axis at creation. Focused tests retain editor identity and accepted state
  after rejected transactions, and verify keyboard behavior afterward.
- The final Rust run passed 66 tests, 0 failed and 0 ignored, including real
  OCaml clock/Todos/100k-row fixtures. Seven Store cases include wire defaults,
  unknown fields, explicit duplicate-field rejection and oversized-snapshot
  rejection. Strict Clippy, formatting, generation freshness and workflow
  syntax checks passed. `make test` passed; a forced serialized OCaml run also
  passed all 249 main tests and the auxiliary suites.
- Independent source review covered worker/FFI lifetimes, request ordering,
  renderer validation, popup identity, update tickets/cancellation, native boot,
  package payload/graph verification and signing order. Remaining accepted but
  unimplemented property/event behavior is recorded in the
  [87-kind support inventory](review-probes/2026-11-11/nsh-support-inventory.md);
  this draft does not claim full component parity or completion.

2026-11-11 published checkpoint qualification:

- Published commit `1ac27c0da460daeeb20113df23915fe6eaede582` on
  `feat/nsh-desktop-backend` in [draft review #356](https://github.com/logseq/lui/pull/356).
  Rebuilt the matching Todos library receipt after the forced Dune test run,
  then packaged that exact checkpoint under `_build/nsh-packages-1ac27c0d/`.
- The real outside-checkout packaged-app qualifier passed again with dynamic
  loader and library overrides removed. It verified the actual Todos hello,
  unique input, one added row and cleared draft. Result evidence is
  `_build/nsh-packaged-qualification-1ac27c0d/result.json`. This is local
  macOS arm64/ad hoc signing evidence, not distribution signing qualification.
- The initial PR CI passed Linux Rust and OCaml integration, macOS Rust,
  Web, Android, core OCaml, C bridge stress and portable services on all
  three desktop OSes. Windows successfully built/loaded the actual OCaml DLL
  and passed real C ABI/input/recovery/repeated teardown. Its adapter check
  found two Unix-only warning cases; macOS OCaml integration found a timing
  assertion that assumed hosted-runner scheduling latency. Both have local
  fixes awaiting qualified reruns. Windows package launch and the maintained
  Apple checks were still running at this observation; no aggregate CI pass
  is claimed.

2026-11-11 component/event and actual-upgrade checkpoint:

- The complete local Rust suite passed 81 tests, 0 failed and 0 ignored;
  all 35 Python NSH tooling tests passed together. Strict all-target Clippy,
  formatting, inventory freshness and workflow syntax checks passed.
- Command icons, variants, sizes and authored gap/main/cross layout now use
  retained native bindings and keyed content slots. Tests preserve the native
  controller, glyph and authored child identities through reordering, and check
  icon-only centering and controlled keyboard activation.
- Native host callbacks now forward supported lifecycle/pointer/gesture events
  and modifiers through the existing optional C ABI. Tests cover flags,
  incarnation rejection, one focus-within owner and controlled picker refusal.
  Typed behavior components still have documented root-event projection gaps.
- Actual packaged LUI N1-to-N2 qualification passed with an identical retained
  80-input LUI source map in both receipts, final installed code hashes,
  authenticated manifests, tamper/cache-corruption rejection and restarted
  Rust/OCaml version markers. See the [method, hashes and precise limits](review-probes/2026-11-11/nsh-packaged-upgrade.md).
- Added native macOS/Linux package launch and source-aware upgrade CI jobs;
  Linux launches use Xvfb. These new jobs need actual runner results. The prior
  checkpoint now passes all three OS Rust adapter jobs and both OCaml
  integration jobs; Windows packaged launch and maintained Apple checks still
  need their terminal evidence.
- The 39 missing kind routes are assigned across parallel basic/layout,
  collection/navigation and surface/service implementations. Admission alone
  will not be counted as full property/event support. The goal remains active.

2026-11-11 synchronized-main and retained-component checkpoint:

- Published `4bb33bdcc323cbe5cf25f6a649468cccb3d9a163` after synchronizing the
  authorized NSH fork with upstream main and pinning exact merge `d21573c`.
  The full local adapter suite passed 126 tests (110 library, 16 integration),
  strict all-target Clippy, formatting, 36 Python tooling tests, contract and
  inventory freshness. `make test` passed, including 249 core cases and the
  full PPX scope/constructor checks. No Dune files were changed.
- The source inventory admits 77 of 87 kinds after adding Breadcrumb,
  Pagination, Stepper/Step, Timeline/TimelineItem and controlled Split. Actual
  Image URL/fit/name/Load and retained BottomTabs pages replace the earlier
  incomplete routes. Admitted routes still have explicit property/event gaps;
  ViewThatFits, ContextMenu, MediaSurface, Tree, Toast, SwipeActions/SwipeAction
  and FilePicker/FileImage/FilePreview remain unimplemented.
- Real macOS BottomTabs input/keyboard/controlled refusal/reorder/Appear tests
  passed. Light/dark images were inspected at narrow and desktop widths. Real
  Image decoding and Todos theme/input checks also passed earlier. Exact tested
  source/log hashes and limits are in the
  [component-batch evidence](review-probes/2026-11-11/nsh-component-batch.md).
  Unicode input is not IME composition or screen-reader qualification.
- At earlier LUI `21b56f98` with the synchronized pin, macOS Rust, OCaml,
  packaging and whole-app upgrades passed. Windows Rust and real OCaml DLL
  integration passed; packaged launch remained pending at the observation.
  Linux dependency setup failed DNS and two system-package jobs were cancelled;
  see [terminal CI evidence](review-probes/2026-11-11/ci-linux-dns-21b56f98.md).
  New-head OS results and production signing remain required.
- ViewThatFits is used by the downstream Journal production header and is
  retained. The usage evidence is recorded separately. The migration goal
  remains active; these checks do not close the unchecked acceptance gates.

### Native component and focus follow-up (2026-11-12)

At this earlier checkpoint, the immutable NSH dependency was `bfa15d0c843c0d6f5bf3a2a230e8ca56b876b61c`.
It includes the authorized same-parent AppKit/GTK focus repair and its Linux
test-only Clippy correction. The actual pinned macOS navigation app passed its
36.7-second keyboard/editor/native-panel flow; see the
[native focus evidence](review-probes/2026-11-11/nsh-keyed-native-focus.md).

Tree and Toast now delegate their native interaction/lifecycle to NSH. FilePicker
uses the native dialog service; MediaSurface uses native Video URLs. Input's
used multiline Enter policy is forwarded to native SubmitBehavior. Split uses
native keyed panels instead of the former custom sizing/focus controller.
ViewThatFits retains and measures ordered alternatives with native layout.
These decisions follow the
[actual downstream usage policy](review-probes/2026-11-11/downstream-nsh-semantics.md)
and the detailed public/default changes in `docs/api-migrations.md`.

At LUI production checkpoint `49f23d4e` with this batch's pinned dependency,
generated-contract refresh and test-only native-key closure correction, the full
Rust suite passed 154 tests (138 library and 16 integration), and the core OCaml
suite passed 251 tests. An additional real OCaml Picked/Dismiss C ABI test passed:
it preserves Unicode paths, error payloads and request integers above 2^53.
After `bb0b0863`, four focused ViewThatFits engine tests also passed; those source
changes still require aggregate and real native fitting qualification. Tooling
regressions passed 42 tests. The generated source inventory now admits 82 of 87
kinds, with explicit restrictions and property/event gaps; admission is not full
OS support. Linux GTK runtime execution, remaining components/host services,
latest full-platform CI and final package/sign/update gates remain open.

The aggregate suite after `bb0b0863`, including ViewThatFits and the real Picked
ABI fixture, passed **159 tests** (142 library and 17 integration), with no
failures or ignored tests. Strict all-target Clippy, format/freshness checks,
42 Python tooling tests and the repeated 251-case core gate passed. The desktop
scope now explicitly excludes the two mobile swipe kinds, leaving three missing
required routes at this checkpoint. Native fitting and the other open platform,
service and packaging qualifications are still pending.

Aggregate log `/tmp/lui-nsh-fit-aggregate-tests.log` SHA-256
`14ed4f44931163933640d74624551aaebd2fc11d7d2dcd2067555c529312df5a`;
strict Clippy log `/tmp/lui-nsh-native-components-clippy.log` SHA-256
`03a502c358e64646143ff251b22cf0f3eb71fc01fb170dbeb31950fa6b1a50a4`.

### Actual Logseq interaction checkpoint (2026-11-12)

The actual release Rust suite passed 46 cases, native OCaml admission and
production 1k/100k/picker virtual-row runners passed, and packaged-native readiness
fixtures passed seven cases. Strict all-target LUI Clippy passed. Exact source,
commands, log hashes and qualification limits are recorded in the
[interaction follow-up](review-probes/2026-11-12/logseq-native-interaction-followup.md).
Visible menu opening, full editor/clipboard UX and remaining platform/delivery
gates are still required.

### Cross-platform delivery seam and picker qualification (2026-11-13)

The NSH desktop workflow at exact LUI
`961107c7c071b04551587b39cc7cdd16f738c07a` completed successfully on every
job: three OS Rust adapter jobs, both Unix OCaml integration jobs, both Unix
native package/whole-app upgrade jobs and the Windows real OCaml DLL/packaged
launch job. Authoritative run:
[NSH desktop 43292878097](https://github.com/logseq/lui/actions/runs/43292878097).
This establishes the Stage 1 native DLL/shared-library delivery seam with the
real native toolchains. The Windows job builds native Todos, Image and FilePicker
DLLs, exercises the ABI, creates an unsigned native package and launches it
outside the checkout. It does not prove Windows installed updates or
distribution signing. The Unix upgrade tests are real complete LUI fixture
packages, not actual Logseq worker/data migrations.

Published LUI `b73fc438e44c58209b8729470bb6c9d3e0989dad` passed 286 release
library cases, eight real OCaml/public-list integration cases, 45 Python tooling
cases and strict all-target release Clippy. Its native submit projection now
uses existing NSH focus-preserving Submit behavior. The actual AppKit many-choice
Enter and pointer flows both retain the query input and accept the immediately
following native key. The AppKit bounds diagnostic now accounts for CALayer
transforms; a real offscreen native geometry fixture passed. See
[input and geometry evidence](review-probes/2026-11-13/input-focus-and-painted-bounds.md).

At actual Logseq `d68e2e0abcb4d8def0168908681ec1a6f65e9e80`, the full release
publisher/startup, 16,427 shared checks, native property/worker/clipboard FFI and
actual AppKit far-down icon-color change passed. The color edit preserves the
same Scroll, source generation, sparse window and last cell, whose new color is
painted inside the native viewport. Later test-only initialization fixes also
passed the full canonical native 1k/100k/complete-picker target. These are scoped
application results; actual table/date input, accessibility, IME and all-module
UX parity remain open.

New LUI `c11ccfbd` source-factory replacement and original reorder integration
targets passed in separate processes, with bounded rows and current-revision
text inside the Headless parent viewport. The corresponding independent AppKit
case subsequently passed at `7ad9d6ca`, preserving native identities and visible
current-revision rows across both replacements without another scroll. See
[source replacement evidence](review-probes/2026-11-13/parent-source-factory-replacement.md).
Later published revisions require their own terminal OS workflow results.
The same eight desktop jobs subsequently passed at the actual Logseq dependency
pin `b73fc438e44c58209b8729470bb6c9d3e0989dad`:
[NSH desktop 43299339007](https://github.com/logseq/lui/actions/runs/43299339007).
Its ordinary CI also passed. The later test-only replacement revision
`2ea42512020fa850e87128468b64d1c5d9a4de03` subsequently passed all eight
desktop jobs in [run 43312221090](https://github.com/logseq/lui/actions/runs/43312221090).
Its ordinary [CI run 43312220933](https://github.com/logseq/lui/actions/runs/43312220933)
also passed every job, including the maintained Apple, Android and Web checks.
These results apply to that exact published revision; later native-dialog and
update-action changes require their own cross-platform qualification.
Actual Logseq portable PDF, production install/restart/signing and full frozen
master UX acceptance remain incomplete; the migration goal stays active.

### Native sheet and updater-owner follow-up (2026-11-13)

The same-port macOS native-sheet inspection/answer seam passed its real,
offscreen AppKit probe, including stale token, replaced sheet, disabled/ambiguous
button and retired/wrong-owner refusal. The CLI skill now documents that native
controller boundary and its limits; see
[native-dialog qualification](native-dialog-agent.md#executed-macos-qualification-2026-11-13).

The updater's existing owner now remains busy until an operational error sheet
settles. Repeated Settings/public checks cannot queue another check or sheet;
retirement during the sheet cannot rearm an old owner. The complete local locked
release suite passed 294 library tests, two public-list tests and eight retained
store tests, with no failures or ignored tests. Strict all-target release Clippy
and formatting passed. Evidence:
`/tmp/lui-update-busy-final-release.log`,
`/tmp/lui-update-busy-final-clippy.log`, and
`/tmp/lui-update-busy-final-format.log`.
The new retirement fixture explicitly signals its own disposal observation;
owner liveness is not itself a reactive signal. These checks do not replace the
actual installed Logseq N1-to-N2 upgrade or the later cross-platform CI gate.

Published revision `fb9146338f93c5fab0892f699e9a3bc9e176d193` subsequently
passed all eight desktop jobs in
[NSH run 43329069368](https://github.com/logseq/lui/actions/runs/43329069368),
including macOS/Linux complete fixture package upgrades and Windows native OCaml
DLL/package launch. Its ordinary
[CI run 43329069310](https://github.com/logseq/lui/actions/runs/43329069310)
also completed successfully. These terminal results qualify that exact published
revision, not the later passive-layout and intrinsic Scroll content changes.
They do not establish actual Logseq installed upgrades or full master UX parity.
