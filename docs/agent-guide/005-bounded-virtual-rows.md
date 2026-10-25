# Bounded Virtual Rows Implementation Plan

Goal: Keep LUI and host UI nodes proportional to the visible window and active interaction pins while retaining the complete application data source.

Architecture: Add a structural lazy row source inside the existing VirtualList component and reconcile only its requested window through the existing keyed lifecycle.
Web, MyGo, SwiftUI and Kotlin request bounded windows with stable row pins; older hosts retain eager behavior through an explicit capability fallback.
Retain the completed encoder and streaming transaction improvements, and exclude active collection policies from this fix.

Tech Stack: OCaml, ocaml-signal, Melange, the existing Web virtualizer, Go, MyGo ListColumn, SwiftUI, Jetpack Compose, JNI and the shared native C ABI.

Related: Builds on [004-component-api-mygo-parity.md](004-component-api-mygo-parity.md) and the follow-up memory PR #274.

## Problem statement

The current Gallery creates 100,000 LUI row nodes before the host virtualizes their views.
Each row also owns a signal, scope, handlers and keyed bookkeeping.
After diagnostic collection, the loaded application still retains approximately 167 MiB of OCaml objects and 72 MiB of Go objects, before allocator capacity and temporary batches.
Changing collection timing does not remove this representation cost.

Business data and a compact key index may remain proportional to source length.
Mounted nodes, row signals, scopes, handlers, host controls and wire operations must remain proportional to the viewport, overscan and interaction pins.
The Native OCaml renderer remains outside this task.

## Testing Plan

Write the behavioral tests before implementing each layer and observe failures caused by missing behavior.
For a missing public constructor, a temporary eager delegation may make the new test fixture link; the required RED result is excessive mounted nodes or incorrect window behavior, not an unbound symbol.
Keep initial test drafts outside the repository until their target interfaces are available.

| Layer | Required behavior |
| --- | --- |
| OCaml application/runtime | A 100,000-item source produces a bounded initial tree, handlers, row scopes and first batch; overlapping windows preserve identity and evictions dispose ownership. |
| Core lifecycle | Source insert/reorder, empty/shrink, pinned-key removal, constructor failure, stale requests and disposal preserve atomicity and correct ownership. |
| Controlled values | An editor's model value survives eviction/remount; retired-incarnation events cannot edit a replacement. |
| PPX | A derived reactive source is owned per mount and disposed once, without disposing borrowed sources. |
| Protocol | Counts, generation and sparse index vectors validate atomically, including extension-root rows, invalid pins and duplicate/out-of-range indices. |
| MyGo | Real ListColumn scrolling and bottom jumps preserve full logical extent with bounded LUI/backend/control counts and interaction pins. |
| Web | Chromium, Firefox and WebKit verify full scroll extent, window convergence, variable row measurement, anchors, focus, pointer hold, composition and portal owners. |
| SwiftUI | Actual native scrolling and bounded row rendering, far jumps, viewport feedback, focused editor identity, composition and pointer/popup ownership preserve a bounded committed tree across reorder and resync. |
| Kotlin | Actual Compose LazyColumn scrolling, focused far reorder, selection and pointer/popup pins preserve native interaction and a bounded committed tree. |
| Compatibility | Literal/eager virtual_list children still work; old shared libraries and hosts fall back without silently displaying an incomplete collection. |
| Release | Ordinary release Gallery loading, scrolling and clearing 100,000 rows shows bounded counts and substantially reduced physical footprint without externally forced collection or an active GC policy. |

NOTE: I will write *all* tests before I add any implementation behavior.

## Public API and compatibility

Keep the existing component and its layout, scroll, overscan and extent arguments.
Add a structural source with no new wire component kind:

```ocaml
virtual_list ~height:400 ~overscan:5 ~item_extent:28. [
  virtual_rows
    ~source:(reactive (fun model -> model.rows) model_source)
    ~key:(fun row -> row.id)
    ~cmp:Int.compare
    ~scroll_key:(fun row -> Printf.sprintf "row-%d" row.id)
    ~mount:(fun row_source -> row_view row_source)
    ()
]
```

The source is borrowed and contains application data, not pre-mounted nodes.
The optional scroll_key maps items to the existing string scroll-target vocabulary.
Using scroll_target without that mapping must produce an explicit validation error rather than silently failing an offscreen jump.
The structural source must be the sole direct child of VirtualList and must reject other parents or competing dynamic segments.
Existing eager children and keyed collections retain their existing behavior.

Append MyGoHost to the existing host vocabulary without reordering earlier cases.
Map native host code 5 to it and support lazy generation on all four implemented host families.
MyGo advertises code 5 only when the new optional window ABI is available.
Keep semantic SwiftUIHost and KotlinHost profiles unchanged.
Native codes 258 and 260 advertise bounded-row support in addition to the existing SwiftUI code 2 and Kotlin code 4.
Updated native clients probe the optional version entry point and retain codes 2/4 with older libraries.
The application constructors accept an optional virtual_rows capability override before mounting the view; native initializers pass the negotiated capability explicitly.
Old native hosts remain eager with a new library, and unknown Generic hosts remain eager unless explicitly opted in by an implementing host.
Document the additional exhaustive host case and the opt-in row source in docs/api-migrations.md.

## Wire contract

Keep VirtualList and primitive wire value types.
Add these parent properties through the canonical protocol/schema pipeline:

| Property | Meaning |
| --- | --- |
| virtual-total-count | Nonnegative logical source length, independent of mounted children. |
| virtual-generation | Positive accepted source revision; window-only changes do not increment it. |
| virtual-indices | Canonical JSON integer vector parallel to committed children, strictly increasing, unique and within the logical count. |
| virtual-scroll-index | Resolved logical scroll target; -1 means the target is absent and uses the existing missing-target completion outcome. |

Parent metadata supports arbitrary row roots, including extensions that cannot receive standard properties.
Validate the complete metadata/children relationship at transaction commit and preserve the old tree on rejection.

Append internal VirtualWindow(node, generation, first, last, pinned_row_ids) before ExtensionEvent, preserving all existing ordinary event ordinals.
The interval is half-open [first, last) and describes the requested overscan window; an empty source uses [0, 0).
Pins identify existing direct row roots outside that interval.
Public VisibleRange remains the intersecting viewport only.
Pins use node IDs so a source reorder cannot pin a different item by stale numeric index.
Ignore stale source generations and filter dead, foreign or nonchild pins without rejecting a valid window request; coalesce duplicate requests and reissue requests after snapshots.
Maintenance feedback must not depend on a user-visible enabled flag or an application event handler.

Add optional lui_ocaml_virtual_window(node, generation, first, last, pins, count) to the native bridge.
Copy and root the integer list under the registered thread's OCaml lock; retain the Go slice only through the synchronous foreign call.
Missing exports preserve older-library loading and the eager profile fallback.

## Task 1: Protocol and capability contract

1. Write canonical validation, event round-trip and older-library compatibility tests.
2. Update src/lui_protocol.ml and .mli, src/lui_wire_schema.ml, platform host aliases, src/lui_extension.ml and the applicable Gallery host match.
3. Add typed window dispatch in src/lui_native_bridge.ml, platform/native/lui_caml_dispatch.h and platform/native/lui_ocaml_bridge.c.
4. Extend tooling/export_mygo_contract.ml, then regenerate schema/components.json and the maintained MyGo manifest through existing tooling.
5. Verify schema freshness, event ordinals, integer precision, malformed input and atomic final validation.

Do not modify Dune files or suppress warnings.
Keep all generated oracle/build intermediates outside the repository.

## Task 2: Bounded core generation

1. Integrate the upfront core and PPX behavioral tests and observe the eager baseline failure.
2. Add virtual_rows to src/lui_elements.ml and .mli and its derived-source ownership case in ppx/lui_ppx.ml.
3. Extract a private synchronous keyed controller in src/lui_dynamic.ml and .mli, retaining the existing keyed public API.
4. Add exclusive segment ownership and internal window hooks in src/lui_runtime.ml, following existing checkpoint, restore and drop paths.
5. Hold the full business array/key index, but reconcile only the sorted window union active pins.
6. Commit row changes and sparse parent metadata under one checkpoint; constructor or validation failures restore the previous complete window.
7. On source replacement, preserve still-existing mounted keys until the host acknowledges the new source generation so delayed pin feedback cannot prematurely remove focus.
8. Resolve offscreen string targets through scroll_key without mounting intermediate rows.

Bootstrap from known viewport/extent properties, or a small bounded seed when actual geometry is not available.
Ordinary data updates refresh retained item signals; evicted rows dispose scopes and handlers, and remounts use fresh incarnations.
Persistent editor/selection state belongs to application data; focus and active interactions retain their required rows.

## Task 3: Web sparse virtualizer

1. Add actual browser tests before changing platform/web/melange/widgets/lui_web_virtual.ml and lui_web_virtual_anchor.ml.
2. Keep the eager branch and use total logical count with bounded sparse maps in lazy mode.
3. For requested indices not yet mounted, draw temporary geometry placeholders without fabricating LUI nodes or appearance events.
4. Emit a coalesced window request after committed refresh and converge after the resulting batch.
5. Preserve reading anchors and invalidate/remap variable-height caches correctly after source revisions.
6. Use existing focus and layer ownership plus pointer/composition lifecycle to retain required row pins, including portal owners.
7. Complete programmatic scrolling after real target geometry is materialized, preserving existing token/outcome semantics.

Relevant ownership integration is in platform/web/melange/core/lui_web_layers.ml.
Check snapshot resync and stationary-viewport pin changes, not just ordinary scroll events.

## Task 4: MyGo sparse collection and native feedback

1. Add real ListColumn/Tester regressions to platform/mygo/collections_test.go and native runtime integration tests.
2. Update platform/mygo/collections.go to use logical total count and sparse committed children, preserving the eager adapter.
3. Expose the toolkit's actual contiguous requested window and focused/dragged row pins through a focused, tested change in the authorized logseq/mygo fork.
4. Reuse toolkit focus/selection behavior and include pressed/composing/popup-owner rows where necessary.
5. Coalesce VirtualWindow feedback after committed layout and route it through the optional runtime binding in platform/mygo/runtime.go.
6. Validate protocol support, snapshots, stale requests and source reorder with real OCaml Gallery interaction.
7. Pin the immutable fork version, preserve upstream module identity and update required downstream replacements and support documentation.

Never vendor the toolkit or commit build/cache artifacts.

## Task 5: Gallery, migration and release acceptance

1. Migrate examples/gallery/view.ml from keyed to virtual_rows inside its existing virtual_list, following .agents/skills/lui-reactive/SKILL.md.
2. Record source/API, host-profile, wire and lifecycle changes with concrete examples in docs/api-migrations.md and platform/mygo/README.md.
3. Run focused tests, core tests, schema/PPX checks, real OCaml integration, browser coverage and the complete Go race suite.
4. Measure the ordinary release through idle, representative controls, 100,000-row loading/scrolling and Clear, including physical footprint and compression.
5. Verify node/scope/handler/control counts stay bounded while scrolling far and after repeated load/clear cycles.
6. Update PR #274 with final before/after results and exact-head CI evidence; mark ready only after the acceptance gates pass.

The existing no-idle-GC streaming release control is frozen outside Git and is a comparison, not proof of bounded generation.
Do not update the video, as the user canceled further recording.

## Task 6: SwiftUI and Kotlin bounded collections

- [x] Write every native-host and startup-compatibility regression before implementation, including real behavioral RED results rather than missing-symbol or rejected-property errors.
- [x] Add optional capability arguments in src/lui_app.ml and .mli and src/lui_runtime.ml; select bounded generation through the runtime capability in src/lui_dynamic.ml.
- [x] Extend src/lui_native_bridge.ml and all examples/*/native/*_bridge.ml initializers to preserve semantic host profiles while negotiating bounded-row support.
- [x] Export the optional version marker from platform/native/lui_ocaml_bridge.c and qualify both old/new host-library combinations.
- [x] Implement atomic sparse metadata validation and internal window events in platform/apple/Sources/LUIAppleBackend and platform/android/lui/src/main, retaining eager literal children.
- [x] Reuse SwiftUI native scrolling geometry and stable committed-row ownership; preserve the native editor object throughout focus, composition, scrolling and source reorder.
- [x] Reuse Compose LazyColumn and public pin-container ownership; verify a focused row survives a reorder far outside the nearest-key cache range.
- [x] Bridge owned window/pin payloads through Apple native clients and Kotlin JNI without narrowing OCaml integers or violating runtime-lock rules.
- [x] Demonstrate top/end jumps in the shared Gallery through typed scroll targets and fresh tokens, with all-four-host reducer/runtime regressions and no private native test hooks.
- [ ] Run focused tests through actual renderers and the OCaml/native dispatch boundary, then run complete relevant host suites and ordinary Gallery device/emulator qualification.
- [x] Update docs/api-migrations.md and PR #274 with the final API, compatibility matrix and verified test results. Final CI on the pushed commit remains a required publication gate below.

Observe failure first, implement the minimum behavior, verify GREEN, simplify and rerun the affected checks.
Serialize every Dune invocation across the three implementation owners.

## Testing Details

Use real OCaml application/runtime lifecycles and host input rather than tests that only inspect metadata shapes.
Allocation budgets run without race instrumentation; behavioral Go tests still run with races.
Measure release artifacts with no debug hooks, externally forced collection, active GC scheduling or parallel local CPU-heavy jobs.
Serialize every Dune command, including wrapper scripts.
Require all final PR checks to pass on the actual final commit.

## Implementation Details

- Preserve ordinary event ordinals and generated contract freshness.
- Keep old eager behavior available for literal children and older hosts.
- Keep row and metadata changes atomic across decoding and reconciliation.
- Use node ownership and stable keys for pins, with source-generation validation.
- Keep application data separate from the bounded mounted representation.
- Avoid duplicate focus, keyboard, selection and virtualization behavior already supplied by the host toolkit.
- Retain controlled model values and necessary active interaction rows.
- Preserve source borrowing and per-mount reactive derivation ownership.
- Keep third-party source, recordings, caches and build output outside commits.
- Maintain migration examples alongside implementation.

## Resolved contract decisions

The missing-target index sentinel is -1, and the internal window interval is half-open.
The pinned MyGo fork exposes actual requested windows, active interaction pins and authoritative source key lookup without changing its upstream module identity.
An individual row may contain an arbitrarily large subtree, so bounds are stated in mounted rows plus their descendant nodes, not a universal absolute node count.

---
