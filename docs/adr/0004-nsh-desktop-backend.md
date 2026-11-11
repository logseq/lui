# ADR 0004: NSH desktop backend

Status: accepted direction; implementation and desktop qualification pending

Date: 2026-11-11

Implementation plan: [006-nsh-desktop-migration.md](../agent-guide/006-nsh-desktop-migration.md)

## Context

LUI already serves Web, iOS and Android. The requested change replaces the MyGo
desktop backend with NSH on macOS, Windows and Linux, using native views or
self-drawn UI. Desktop applications also need packaging, distribution signing
and whole-application updates. A WebView application shell does not meet this
requirement.

The migration must preserve LUI's retained node identity, controlled values,
atomic batches, native extensions, host services and bounded virtual rows. It
must preserve the Apple Swift packages, Android Gradle/JNI backend and mobile
tooling used by downstream applications. Backend deletion is authorized;
mobile retirement and Dune-file changes are not.

Research is pinned to `longbridge/nsh` commit
`cdfdf75c1509cdb34c6220e6b5bf923452c0cb76` (workspace version `0.5.0`, Rust
`1.97`). It is a specific source revision, not a claim that every API on NSH
main is a released compatibility promise. The official `nsh` and
`nsh-design-guides` skills were installed from this revision. Later dependency
updates require rerunning the adapter's qualification.

## Findings from the implementation

| Layer | Observed responsibility | Consequence for LUI |
| --- | --- | --- |
| `nsh-core` | Retained shadow tree, Taffy layout, text measurement interfaces, reactive ownership, lists and mount instructions | Reuse these facilities; add no independent layout engine or generic reactive runtime. |
| Rust element/component API | A component constructs once; closures/signals update dependent bindings | Retain elements across patches and bind changing values. Rebuilding the root on every batch defeats this model. |
| `nsh-base` | Unstyled controls and compound behavior, including focus, keyboard, accessibility and overlays | LUI supplies its existing visual defaults and theme; behavior comes from semantic components. |
| `nsh-engine` | One engine thread per surface; commits produce mount batches for the platform | Apply each LUI transaction coherently on the engine thread. Keep foreign-runtime waits off that thread. |
| Platform backends | Platform UI thread mounts and draws results; text shaping is separated from drawing | Use public platform runners, rather than copying their mount/surface implementation. |

NSH is not uniformly an operating-system widget toolkit. macOS uses layer-backed
AppKit views and CoreText; Linux uses GTK widgets and GSK/Pango; Windows draws a
retained tree with Direct2D/DirectWrite in a Win32 surface. Text editing and
other system facilities use specialized native integration. These routes meet
the requested native/self-drawn boundary. They do not establish identical IME,
accessibility or rendering quality across the three systems; those need native
tests. See the pinned [architecture](https://github.com/longbridge/nsh/blob/cdfdf75c1509cdb34c6220e6b5bf923452c0cb76/docs/dev/architecture.md)
and platform implementations for [macOS](https://github.com/longbridge/nsh/blob/cdfdf75c1509cdb34c6220e6b5bf923452c0cb76/crates/nsh-platform-macos/src/lib.rs),
[Linux](https://github.com/longbridge/nsh/blob/cdfdf75c1509cdb34c6220e6b5bf923452c0cb76/crates/nsh-platform-linux/src/lib.rs)
and [Windows](https://github.com/longbridge/nsh/blob/cdfdf75c1509cdb34c6220e6b5bf923452c0cb76/crates/nsh-platform-windows/src/lib.rs).

Rust roots run without QuickJS. A TSX root would introduce another application
language/runtime without removing the OCaml bridge. Public `Root`,
`EngineConfig`, platform `AppSource::Rust` and `run_app` are the intended seams.
Although `Core` exposes operations, the ready-made platform surfaces do not
expose a general LUI-batch injection API. Private `ElNode` fields and platform
surface internals are not an adapter contract. See the pinned
[engine](https://github.com/longbridge/nsh/blob/cdfdf75c1509cdb34c6220e6b5bf923452c0cb76/crates/nsh-engine/src/lib.rs)
and [Rust guide](https://github.com/longbridge/nsh/blob/cdfdf75c1509cdb34c6220e6b5bf923452c0cb76/website/docs/rust.md).

NSH's Rust `virtual_list` already recycles cells, follows position bindings and
accepts logical counts and keys. Core list retention covers keyboard focus,
overlay ownership and text selection. Public viewability reports describe
visible rows; they are not an explicit export of the full requested overscan
window and interaction pins. LUI's sparse `virtual_rows` needs that additional
ownership information. Matching these contracts through public bindings and
cell lifetimes is the principal feasibility question, not a solved consequence
of both frameworks having a virtual list. See
[the Rust list API](https://github.com/longbridge/nsh/blob/cdfdf75c1509cdb34c6220e6b5bf923452c0cb76/crates/nsh-core/src/element/virtual_list.rs),
[list retention](https://github.com/longbridge/nsh/blob/cdfdf75c1509cdb34c6220e6b5bf923452c0cb76/docs/dev/scrolling-and-lists.md)
and [LUI's existing contract](../agent-guide/005-bounded-virtual-rows.md).

## Decision

Implement a Rust-only adapter in `platform/nsh`, using pinned public NSH APIs.
Retain the existing OCaml application model and native C ABI. NSH owns native
layout, rendering and interaction; LUI owns application state, wire semantics,
theme defaults and the translation between those contracts.

On 2026-11-11 the user authorized a minimal NSH keyed-list fix in the
[`logseq/nsh`](https://github.com/logseq/nsh) fork, on branch `fork/logseq`.
Limit dependency changes to key-based retention of cells, active interaction
pins, measurements and native editor continuity during keyed sibling moves,
keeping the contiguous-splice fast path. This explicit
authorization supersedes the app skill's default prohibition on modifying
NSH for an app. The current dependency is pinned to immutable commit
`bfa15d0c843c0d6f5bf3a2a230e8ca56b876b61c` on `logseq/nsh` (`fork/logseq`,
[review](https://github.com/logseq/nsh/pull/1)); the
adapter continues to use public NSH APIs. This revision merges official
upstream main `de7f3637171b769f18474796fd5159a60b2de726`, as requested,
while retaining the authorized repairs. It also preserves same-parent AppKit
and GTK subtrees during native sibling reorders instead of detaching focused
editors. This changes no public NSH API or controlled-state protocol. See the
[native focus regression](../agent-guide/review-probes/2026-11-11/nsh-keyed-native-focus.md)
and the
[synchronization evidence](../agent-guide/review-probes/2026-11-11/nsh-main-sync.md).
No floating branch dependency or unrelated new fork API is covered by this
exception. The
[public probe](../agent-guide/review-probes/2026-11-11/nsh-keyed-list-reorder.md)
reproduces the need at both 1,000 and 100,000 source items.

```text
OCaml application / LUI runtime
  -> existing C ABI: ordered JSON batches
  -> Rust decode + transactional retained store
  -> retained NSH bindings + LUI styled controls
  -> NSH core / engine
  -> AppKit, GTK/GSK or Win32/Direct2D

native semantic events -> ordered bridge requests -> OCaml -> batches
```

### Ownership and threading

Use one persistent OCaml worker thread for the loaded runtime, separate from
NSH's engine and platform UI threads. The existing bridge releases/reacquires
the runtime lock around calls and does not make arbitrary engine threads valid
OCaml callers. The worker serializes startup, dispatch, timers, agent requests,
resync and disposal. Keep the initialized library loaded for process lifetime;
do not unload a running OCaml runtime or migrate its calls across threads.
Initially support one active LUI session per process and reject a competing
session explicitly. Multiple independent OCaml applications in one process are
outside this migration.

Use an established channel/future implementation for wakeups, with ordered
requests and responses. Neither the UI thread nor the NSH engine waits for
OCaml. Bound queued work; preserve discrete edits and commands, and coalesce
only supersedable maintenance feedback. Test overload and shutdown explicitly.
Schedule OCaml clock work at its next deadline, rechecking after every bridge
call. Do not add frame polling, an idle collector or a hand-built executor.

### Retained updates and validation

- Decode a batch once. Preserve OCaml integer IDs and generations without an
  intermediate floating-point representation; validate their accepted range.
- Validate a transaction before publishing any signal or native change. Keep
  rollback state proportional to touched nodes and affected child lists.
- Require sequential ordinary generations. Accept an authoritative snapshot
  through a separate replacement path, including an unchanged generation.
- Keep root lookup indexed. Unrelated node updates must not scan or clone the
  complete retained tree. Explicit subtree removal may visit that subtree.
- Give each live node one retained identity with a session/incarnation guard.
  Store child structure separately from property bindings so a label update
  does not reconstruct descendants. Structural edits use stable keyed owners.
- Ignore retired-incarnation events. Re-entrant callbacks must not hold store
  borrows or publish partial transactions. Controlled values remain owned by
  OCaml, including rejection or normalization of an edit proposal.
- Retain a bounded mirror of mounted LUI nodes because atomic validation and
  event identity require it. Do not mirror the application's complete domain
  model or add a second generic reactive graph.

Reuse the canonical OCaml/schema exporter. Generate the adapter's validator
data/code at build-development time and compare it against the canonical
oracle in tests. Do not interpret an OCaml AST in the shipped application or
embed the oracle there. Freshness checks must compare reproducible generated
output, not merely a set of source hashes. The prototype's type-only property
checks do not meet this requirement.

### Components, presentation and extensions

Inventory all 87 current wire kinds and their admitted properties, events,
defaults and child contracts. Map semantic controls to their NSH counterparts;
for example, a switch uses `Switch`, and a menu uses menu behavior. Shared LUI
compositions may use several NSH primitives where no direct equivalent exists,
but must retain LUI semantics and reuse NSH interaction infrastructure.

On 2026-11-12 the user clarified the compatibility boundary: inspect production
usage in `logseq/mobile`, `logseq/logseq_journal` and Logseq's `refactor/lui` branch
(the third target was explicitly added on 2026-11-12) before reproducing a
legacy component or optional behavior. Preserve the APIs and behavior those
applications actually use. For components or behavior unused by all three, adopt
NSH's native component model and defaults, documenting concrete desktop API
migrations where necessary. Do not build another focus, gesture or lifecycle
controller merely to preserve an unused legacy convention. Domain objects named
Tree or Timeline, backend compatibility tables, tests and generated schemas are
not evidence that the corresponding LUI UI component is used.

In particular, neither application uses LUI Tree, so the adapter should use the
native NSH Tree's data, expansion, selection, virtualization and keyboard model.
The unused legacy authored-row event model is not an acceptance requirement.
Toast is used by mobile capture confirmation, but its `on_dismiss` is cleanup,
not a veto. The replaced MyGo desktop already closed a Toast before notifying
the application and did not reopen an expired retained node. Use native NSH
Toast/ToastStack/ToastManager; do not introduce refusal recovery or custom swipe
handling for that inferred requirement. Other used components, including the
Journal header's ViewThatFits, retain their actual downstream requirements.

The user explicitly excluded SwipeActions and SwipeAction from NSH desktop
scope on 2026-11-12. Keep their canonical wire kinds and maintained mobile
implementations; desktop applications should expose the corresponding actions
as ordinary commands or a ContextMenu. NSH rejects these mobile-only kinds
explicitly rather than mounting an empty placeholder. This leaves 85 required
desktop kinds out of the 87-kind shared contract.

Put presentation policy in a small `ui` layer using LUI's existing semantic
theme tokens, control variants, sizes, icons and appearance inheritance. NSH
parts are invisible until styled. Explicit application colors remain data;
backend defaults must follow tokens. Do not introduce a new design system,
silent generic-view fallback or a large family of one-use wrappers. Apply
layout properties to the real layout participant rather than adding an
identity wrapper that changes flex or intrinsic sizing.

Preserve the extension/tweak registry, fingerprint validation, application
scope and freeze lifecycle from ADRs [0002](0002-dynamic-components.md) and
[0003](0003-platform-tweaks.md). Factories remain executable application-owned
Rust code; wire data cannot instantiate arbitrary native classes. Explicitly
reject unsupported selected capabilities and document any narrowly scoped
exception. Unimplemented behavior is not supported merely because it renders.

### Virtual collections

Use NSH's existing virtualization, measurement, scroll commands and retention.
First prove a public-API adapter from cell position/lifetime to LUI's bounded
window protocol, including distant retained rows. Keep total logical extent,
generation, sparse indices, offscreen targets, reading anchors and scroll-token
completion semantics. Maintenance feedback cannot depend on a user handler or
the collection's enabled state.

Do not advertise bounded-row capability until a real OCaml-to-NSH test proves
it. Eager literal children retain their existing meaning; eagerly constructing
100,000 source rows is not an acceptable implementation of `virtual_rows`.
If public APIs cannot preserve the contract, record the precise failing case
and reconsider this boundary before expanding the adapter. Do not access private
list internals, fork NSH silently or implement another virtualizer as a shortcut.

### Packaging, signing and updates

Use `nsh.json` with a Rust root and a CLI from the same pinned source. CLI runner
generation can retarget NSH dependencies, so development/package scripts must
select and verify the exact Git checkout resolved from the application's
manifest instead of mixing Git
and release crates. Check the generated runner dependency graph as well.

| Target | NSH provides at the pinned revision | LUI integration still required |
| --- | --- | --- |
| macOS | Release `.app`, ad hoc signing, architecture selection | Include the matching OCaml library and assets; sign nested code with Developer ID, notarize and staple before producing final update archives. |
| Windows | Release directory/ZIP, Inno Setup script and installer when Inno Setup is installed | Build and load the OCaml DLL with the target toolchain; include its dependencies; Authenticode-sign the executable, DLLs and installer. |
| Linux | Release directory, desktop entry and tarball | Include the OCaml library and document GTK 4.14+/Pango and other actual runtime dependencies; validate on the supported distribution baseline. |

The upstream packaging layer is not a complete credentialed distribution
pipeline. Do not describe Linux tarballs as deb/rpm/AppImage packages or macOS
ad hoc signing as Developer ID distribution. Final archives must contain both
halves of the application; the updater must never replace a bare OCaml library
independently of its matching runner. See the pinned
[packaging guide](https://github.com/longbridge/nsh/blob/cdfdf75c1509cdb34c6220e6b5bf923452c0cb76/website/docs/packaging.md).

Use `nsh-updater` for signed-manifest checking, archive verification and
installation, with one existing HTTP transport and application-owned progress
UI. Rust apps supply transport and invoke installation/restart explicitly;
adding an `updater` JSON key alone is insufficient. Use whole-app updates for
the compiled OCaml/Rust application, rather than adding TSX OTA delivery.
Exercise cancellation, tampered downloads, stale/wrong-app manifests,
non-writable installations and install failure. Distribution credentials stay
outside the repository. See the pinned
[Rust updater API](https://github.com/longbridge/nsh/blob/cdfdf75c1509cdb34c6220e6b5bf923452c0cb76/crates/nsh-updater/src/lib.rs)
and [update guide](https://github.com/longbridge/nsh/blob/cdfdf75c1509cdb34c6220e6b5bf923452c0cb76/website/docs/app-updates.md).

### Compatibility and removal

The target host profile is `NshHost` / `"nsh"`, with native host code `6`.
Do not reuse MyGo code `5`, SwiftUI `2`/`258`, Kotlin `4`/`260`, or OS codes.
The MyGo host constructor removal is an intentional source migration; record
exhaustive-match and extension-registration examples in `docs/api-migrations.md`.
Legacy code `5` becomes a generic profile, without claiming NSH capabilities.
Probe optional native exports before using them; older libraries must take
the documented eager/generic route or produce an explicit incompatibility
error rather than a truncated list. Preserve existing ordinary event ordinals
and the shared batch format.

Remove MyGo source, Go dependencies, active build targets and CI as part of the
migration. Their behavioral coverage is a parity inventory, not a test count
to discard. Keep historical design documents recognizable as historical;
update current README instructions and migration examples. Pending worktree
deletions do not make the new default ready: qualification below is required.

## Alternatives considered

| Alternative | Assessment |
| --- | --- |
| Flutter desktop | Viable self-drawn route with a mature ecosystem, but adds Dart and another bridge. The user selected NSH; do not maintain both new backends in this migration. |
| TSX/QuickJS NSH host | Adds an application runtime and translation layer without a requirement for dynamically delivered TSX screens. Rust roots provide the required native path directly. |
| Direct `Core::apply` plus a copied platform mounter | Avoids some element bindings but transfers platform lifecycle and private integration maintenance to LUI. Rejected for this migration. |
| Rebuild the complete NSH tree after every batch | Simpler prototype, but loses editing/focus identity and scales updates with unrelated content. Rejected. |
| Reimplement controls, focus and virtualization above plain views | Duplicates NSH behavior and increases the correctness/performance surface. Rejected. |

## Qualification and consequences

This decision reduces duplication by retaining LUI's application and wire
contracts while reusing NSH behavior. It adds Rust and a bounded retained
adapter, plus a serialized OCaml worker. Cross-platform native behavior and
delivery remain engineering work; a successful `cargo check` proves neither
component parity nor shipping readiness.

The current prototype compiles but has incomplete validators, eager collection
fallbacks, synchronous dispatch, generic component fallbacks and presentation
gaps. Its migration files and backend deletions are not an accepted final
implementation. The existing core test run passed 249 cases; it does not
qualify the new backend or the final working tree.

Completion requires the plan's entire matrix to pass: canonical conformance,
real headless and native interaction, complete existing maintained-backend
regressions, reproducible packaged applications and update tests. Performance
acceptance includes measured sparse-update scaling and bounded mounted rows;
the plan defines workloads and limits. No compiler-warning suppression, type
casts bypassing safety, Dune edits, vendored dependency trees or reduced test
coverage may be used to meet those gates.

## Final application acceptance clarification

On 2026-11-12 the user made Logseq's actual `refactor/lui` application the final
acceptance target: completely replace MyGo with NSH, remove the old active
backend/build/launch/package integration, and perform UX review and remediation
against `master`. Graph View is excluded. Database graphs and other graph-backed
features remain required. Component counts and fixture tests do not establish
this result. The execution plan records the frozen master comparison revision,
application startup/service/extension gates and actual UX review requirements.

## Compile-time provider coverage clarification

Real application integration exposed declared LUI style values that the NSH
provider still refused at runtime. Acceptance now requires earlier coverage:
closed canonical domains are generated into provider types and lowered with
exhaustive matches; open style grammars use typed parsed values; known literals
are checked before launch where target information is available. Dynamic values
retain transactional validation. An actual Logseq headless startup gate, using
its real native library and services in isolated state, must precede a fresh
launch receipt. This supplements static checking and does not substitute for
native UI/UX qualification. No Dune changes or separate copied capability schema
are authorized by this clarification.
