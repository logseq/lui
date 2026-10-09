# LUI implementation review

Date: 2026-10-09. Reviewed revision: `91aecb52a1cba2faaf23aac1d64a0bd1cb6549e7`.

## Scope and status

The current branch was fast-forwarded to latest `origin/main` before this review. The pinned opam source repositories were refreshed: `ocaml-signal` at `868c1459f865b4ba3b227eb440dba40f1c812899`, and `drive` at `1e1653d5bdd0810e89d9e3a32b2e0ea2811c1cf5`. Vendored `deps/drive/src` matches that upstream revision except for its intentional local Dune packaging declaration; its source metadata was corrected. No implementation or Dune files were edited.

This review covers the retained OCaml runtime, reactive ownership and reconciliation, PPX/property bindings, patch stores and renderer paths in Web, Apple, Android, and GPUI, subscriptions, bridge lifecycle, and performance qualification. GPUI execution covered `lui-core`; its interactive renderer was inspected statically. Android composition and Activity lifecycle were inspected in source and compiled Compose bytecode, without an emulator lifecycle run. Apple list identity was inspected in source, without Instruments or a live focus/scroll regression run.

There are **22 actionable findings**, followed by three structural simplification opportunities. P1 means a correctness failure in normal feature use, persistent resource growth, or an important scaling failure; P2 means a narrower failure path or a lower-priority improvement. Evidence is explicitly marked. Standalone probes are in [review-probes/2026-10-09](/Users/tiensonqin/Codes/projects/lui/docs/agent-guide/review-probes/2026-10-09/run.py).

## Findings: reactive runtime and ownership

### F01 — P1: sibling reactive branches share persistent local state

Location: [lui_ui.ml:44](/Users/tiensonqin/Codes/projects/lui/src/lui_ui.ml:44), [lui_dynamic.ml:58](/Users/tiensonqin/Codes/projects/lui/src/lui_dynamic.ml:58), [lui_elements.ml:369](/Users/tiensonqin/Codes/projects/lui/src/lui_elements.ml:369).

`child_context` indexes persistent state scopes by `parent_path + name`. Every switch uses the same `switch-branch` name, while sibling children receive the same parent context. Two sibling switches using the same state slot therefore acquire the same state scope. The conditional branch path has the same identity pattern.

**Reproduced:** sibling switches initialized to 10 and 20 both render 10. This causes separate components to share drafts, selection, or other local state.

**Fix:** assign each structural owner a stable identity, then nest branch identity within that owner. Preserve the owner's identity across remounts; do not make every remount a fresh random scope, which would lose legitimate local state.

### F02 — P1: failed keyed candidate mounts leak runtime nodes and scopes

Location: [lui_dynamic.ml:268](/Users/tiensonqin/Codes/projects/lui/src/lui_dynamic.ml:268), especially mount registration at line 288 and checkpoint at line 319.

Fresh rows are constructed before the transaction checkpoint. Exception cleanup disposes the candidate signal and scope, but nodes created by `mount` have already entered runtime tables and pending operations. A throwing mount hook is even earlier than adding its scope to the cleanup list.

**Reproduced:** adding rows 2 and 3, with row 3 raising after creating its node, leaves mounted node count 2 → 4 while the parent's published children remain unchanged. Updating back to the original rows still leaves four nodes. A throwing `on_mount` leaves the candidate scope mounted and undisposed.

**Fix:** begin candidate staging before invoking user mount code, register candidate cleanup before fallible hooks, and remove all unpublished runtime nodes on failure. Branch mounting has a similar candidate-publication ordering that should be covered by the same lifecycle transaction tests.

### F03 — P1: rollback restores the tree but not its lifecycle or segment state

Location: [lui_dynamic.ml:319](/Users/tiensonqin/Codes/projects/lui/src/lui_dynamic.ml:319), [lui_runtime.ml:17](/Users/tiensonqin/Codes/projects/lui/src/lui_runtime.ml:17), [lui_runtime.ml:214](/Users/tiensonqin/Codes/projects/lui/src/lui_runtime.ml:214).

Keyed reconciliation disposes old row scopes during mutation, before commit. Runtime checkpoints copy hash tables shallowly; dynamic-segment records still share mutable `base`, `size`, and `active` refs with the live runtime. Restoring table entries cannot undo scope disposal, signal effects, or mutations inside those records.

**Reproduced:** a row cleanup raises during removal. Rollback restores one child, but the segment size remains zero and the row scope is disposed. Retrying the removal raises `dynamic segment index is out of bounds`.

**Fix:** stage new ownership, commit structural changes, and only then retire old scopes. Journal segment ref values explicitly. Define which signal updates and callbacks occur after commit; a tree snapshot alone is insufficient.

### F04 — P1: derived reactive signals outlive remounted views

Location: [lui_ppx.ml:4](/Users/tiensonqin/Codes/projects/lui/ppx/lui_ppx.ml:4), [lui_ui.ml:205](/Users/tiensonqin/Codes/projects/lui/src/lui_ui.ml:205), [lui_elements.ml:348](/Users/tiensonqin/Codes/projects/lui/src/lui_elements.ml:348).

The PPX emits unscoped `Signal.map` / `map2`. The property binder owns its wire conversion, but borrows the incoming derived source. When that source was created inside a remounted branch, disposing the branch does not remove its upstream subscription. Internal helpers also create unowned intermediate mappings, including icon conversion and split-property projections.

**Reproduced:** a branch binding text through a local `Signal.map` leaves upstream subscriber count 1 → 21 after 20 remounts. Retired computations continue running on future source updates.

**Fix:** make ownership of newly created derivations explicit and scope PPX/helper-created mappings. Preserve borrowing of caller-owned shared sources. Hoisting reusable derivations helps callers, but does not fix leaking library-created mappings.

### F05 — P2: replacement subscription can become active but untracked

Location: [lui_subscriptions.ml:118](/Users/tiensonqin/Codes/projects/lui/src/lui_subscriptions.ml:118).

Reconciliation starts replacements, then disposes old subscriptions before publishing the desired ownership table. If an old disposer raises, publication and cleanup of the prepared replacements are skipped.

**Reproduced:** two subscriptions started, one old cancellation attempted, one entry still tracked; the newly started replacement is active and untracked.

**Fix:** specify an ownership transfer point, retain cleanup responsibility for every prepared subscription, and continue disposal after recording errors. Never lose the reference to an active subscription because a different disposer raised.

### F06 — P2: queued handlers fire after their owner is removed

Location: [lui_runtime.ml:1925](/Users/tiensonqin/Codes/projects/lui/src/lui_runtime.ml:1925).

Dispatch queues a closure capturing `handler_callback`. It does not recheck handler registration or scope lifetime when the effect runs.

**Reproduced:** enqueue a press, dispose its scope and drop the node, then flush; the callback executes once after disposal. It can mutate state owned by an already retired component.

**Fix:** validate the handler registration/token at effect execution. Checking only the node ID is insufficient if an ID is retained but its handler has been replaced.

## Findings: Android correctness

### F07 — P1: JSON strings are decoded as numbers/booleans; integers wrap

Location: [LuiWire.kt:60](/Users/tiensonqin/Codes/projects/lui/platform/android/lui/src/main/kotlin/dev/lui/LuiWire.kt:60).

`booleanOrNull`, `longOrNull`, and `doubleOrNull` run before checking `isString`. Kotlin's JSON primitive accessors parse quoted content too. The integer branch then narrows Long to Int without a range check.

**Reproduced using built Android classes:** `"123"` becomes `IntValue(123)`, `"true"` and `"false"` become booleans, `"1.5"` becomes a double, and numeric `4294967296` becomes zero. Numeric-looking text values can consequently reject an otherwise valid patch batch.

**Fix:** handle JSON strings first; retain integer width at the wire boundary and validate ranges when converting to a component-specific numeric type.

### F08 — P1: retained node changes do not invalidate skippable Compose node views

Location: [LuiBackend.kt:31](/Users/tiensonqin/Codes/projects/lui/platform/android/lui/src/main/kotlin/dev/lui/LuiBackend.kt:31), [LuiBackend.kt:101](/Users/tiensonqin/Codes/projects/lui/platform/android/lui/src/main/kotlin/dev/lui/LuiBackend.kt:101), [LuiNodeView.kt:103](/Users/tiensonqin/Codes/projects/lui/platform/android/lui/src/main/kotlin/dev/lui/LuiNodeView.kt:103).

Only `Content` reads the global observable revision. `LuiNodeView(backend, id)` reads the retained node through an ordinary map; neither parameter changes for a property update. With strong skipping enabled, recomposing the caller does not force a child with unchanged parameters to execute.

**Compiled-code evidence:** the current Compose-generated `LuiNodeView` checks unchanged parameter flags and `Composer.getSkipping`, then calls `skipToGroupEnd` before fetching the retained node. It does not read revision or observable node state. This leaves a normal property/child update without a dependency that invalidates the affected node view. No live-device composition trace was captured.

**Fix:** expose per-node observable state or revisions and read them inside the node view. Use affected-node invalidation so a text edit does not invalidate every node. A global forced rebuild would hide the dependency bug and add avoidable work.

Reference: [Android documentation on strong skipping](https://developer.android.com/develop/ui/compose/performance/stability/strongskipping), including instance equality for unstable parameters and automatic skipping.

### F09 — P1: one rejected patch can permanently desynchronize Android

Location: [LuiStore.kt:85](/Users/tiensonqin/Codes/projects/lui/platform/android/lui/src/main/kotlin/dev/lui/LuiStore.kt:85), [LuiBridge.kt:54](/Users/tiensonqin/Codes/projects/lui/platform/android/lui/src/main/kotlin/dev/lui/LuiBridge.kt:54), [lui_native_bridge.ml:53](/Users/tiensonqin/Codes/projects/lui/src/lui_native_bridge.ml:53), [MainActivity.kt:44](/Users/tiensonqin/Codes/projects/lui/examples/components/android/app/src/main/java/dev/lui/components/MainActivity.kt:44).

The native bridge reports success when recording a batch, before asynchronous JVM application. The Android store advances generation only when validation succeeds; the sample ignores the returned failure. After a rejection, native generation advances while the host still expects the rejected generation. JNI exports `nativeResync`, but Kotlin does not expose or use it and the backend has no coordinated reset/snapshot entry point.

**Reproduced:** accept generation 1, reject generation 2, then submit valid generation 3; the store remains at 1 and rejects 3 because it expects 2. F07 provides a concrete valid-user-data trigger for this failure path.

**Fix:** agree on receipt versus committed application semantics. Expose and invoke a coordinated reset plus authoritative full snapshot after rejection; include any independently mounted extension trees. Test rejection followed by recovery through the real bridge.

### F10 — P1: Activity recreation retains a stopped bridge and old patch sink

Location: [LuiBridge.kt:65](/Users/tiensonqin/Codes/projects/lui/platform/android/lui/src/main/kotlin/dev/lui/LuiBridge.kt:65), [LuiBridge.kt:191](/Users/tiensonqin/Codes/projects/lui/platform/android/lui/src/main/kotlin/dev/lui/LuiBridge.kt:191), [MainActivity.kt:65](/Users/tiensonqin/Codes/projects/lui/examples/components/android/app/src/main/java/dev/lui/components/MainActivity.kt:65).

`stop` calls native stop but never clears `started` or `patchSink`. A recreated Activity calls `start`; the early `started` check returns before installing the new sink or starting a new native session. Already queued deliveries also capture the previous sink.

**Source-confirmed lifecycle failure:** the sample stops the bridge in `onDestroy` and starts it from a new Activity instance. The next start can report success while retaining the old sink and a stopped runtime. Device rotation/recreation was not executed during this review.

**Fix:** serialize session transitions and define which object owns runtime lifetime. On stop, retire the sink and session token; on restart, install the new sink and establish a consistent native/host baseline. Reject queued delivery from retired sessions.

### F11 — P2: a node can be inserted as its own child

Location: [LuiStore.kt:252](/Users/tiensonqin/Codes/projects/lui/platform/android/lui/src/main/kotlin/dev/lui/LuiStore.kt:252).

The cycle check begins at the target's parent and never tests `target == root`.

**Reproduced:** create column 1 and insert child 1 into parent 1; application succeeds with parent 1 and children `[1]`. Ancestor traversal, recursive dropping, or rendering can then loop or overflow the stack.

**Fix:** reject self-parenting before traversal, and add direct and indirect cycle fixtures shared across stores.

### F12 — P2: Android lazy rows use positional identity

Location: [LuiNodeView.kt:274](/Users/tiensonqin/Codes/projects/lui/platform/android/lui/src/main/kotlin/dev/lui/LuiNodeView.kt:274), and adjacent ordinary row/column child loops.

`LazyColumn.items(children.size)` does not supply a node ID key. Normal child loops likewise do not establish a Compose key. A retained node move changes which ID occupies each composition position, defeating row-local identity and `remember` state.

**Source-confirmed:** keyed OCaml nodes are not translated into keyed Compose rows. Live focus/draft/scroll behavior after reordering needs a composition regression test.

**Fix:** use node IDs as lazy item keys and establish keys around ordinary child composition when identity must survive moves.

## Findings: performance

### F13 — P1: every keyed publication checkpoints the entire application

Location: [lui_dynamic.ml:319](/Users/tiensonqin/Codes/projects/lui/src/lui_dynamic.ml:319), [lui_runtime.ml:214](/Users/tiensonqin/Codes/projects/lui/src/lui_runtime.ml:214).

The keyed reconciliation algorithm uses maps and prefix sums, but unconditionally calls `checkpoint application` with no affected-node set. Even publishing the same one-row key list copies tables for unrelated nodes. This cancels the locality gains of the improved keyed index algorithm.

**Measured native OCaml smoke probe:** 20 unchanged one-row publications with 1,000 / 10,000 / 50,000 unrelated nodes took 2.205 / 39.992 / 330.042 ms and allocated 3.294 / 36.165 / 170.022 MB respectively. These are one-run CPU measurements, not rendered frame times.

**Fix:** an unchanged fast path plus an affected-node journal/checkpoint; include candidate creation and dynamic segment state in that journal. Correct F02/F03 first so reducing transaction scope preserves rollback guarantees.

### F14 — P1: Web validates the full retained tree for a one-property patch

Location: [lui_web_store.ml:612](/Users/tiensonqin/Codes/projects/lui/platform/web/melange/core/lui_web_store.ml:612), [lui_web_store.ml:708](/Users/tiensonqin/Codes/projects/lui/platform/web/melange/core/lui_web_store.ml:708).

Every batch calls `validate_nodes`, which iterates all retained nodes. The store's before-image undo mechanism is already local, but final validation remains global.

**Measured compiled Melange store in Node/V8:** after 20 warmups, 100 single-property updates with 1,000 / 10,000 / 50,000 nodes took 15.54 / 143.61 / 728.68 ms. At 50,000 nodes, store work alone averaged about 7.3 ms per update in the final run; an earlier run averaged 17.3 ms. The variation reinforces using the scaling trend rather than a single timing as the conclusion. Detached text nodes isolate global validation from child-list work; DOM and layout are excluded.

**Fix:** validate the affected invariant closure: touched nodes, former/new parents, relevant child endpoints, and descendants when ancestry changes. Apple already provides an affected-set validation pattern to adapt. Do not merely turn off validation.

### F15 — P2: Android copies and validates the whole tree for every batch

Location: [LuiStore.kt:90](/Users/tiensonqin/Codes/projects/lui/platform/android/lui/src/main/kotlin/dev/lui/LuiStore.kt:90), validation at line 96.

`mapValues { copy() }` copies every node and its collections before applying even a single property operation, then validation scans the complete standard-node map. Cost depends on application size, not the change size.

**Measured JVM store smoke probe:** after 20 warmups, 100 single-property updates took 18.85 / 65.33 / 232.82 ms at 1,000 / 10,000 / 50,000 nodes. This includes JSON decoding in the probe, excludes Compose and device rendering, and is not comparable as a platform ranking against OCaml/V8.

**Fix:** retain first before-images only for touched nodes, restore them on failure, and validate affected invariants. Publish per-node observable state for F08 from the committed affected set.

### F16 — P2: wide child collections still contain quadratic paths

Location: [lui_web_store.ml:25](/Users/tiensonqin/Codes/projects/lui/platform/web/melange/core/lui_web_store.ml:25), [lui_web_store.ml:271](/Users/tiensonqin/Codes/projects/lui/platform/web/melange/core/lui_web_store.ml:271), [lui_runtime.ml:663](/Users/tiensonqin/Codes/projects/lui/src/lui_runtime.ml:663), [GPUI store.rs:435](/Users/tiensonqin/Codes/projects/lui/platform/gpui/crates/lui-core/src/store.rs:435).

Web child lists use repeated length, indexing, splitting, and append. Appending all children to one parent is quadratic. Runtime child diff shifts array positions for each move; a full reversal is quadratic. GPUI `Vec` position searches/removal/insertion also become quadratic for many moves. The balanced `Lui_sequence` implementation and keyed prefix-sum lookup do not fix these downstream paths.

**Measured Web store-only initial flat list mount:** 1,000 / 4,000 / 8,000 rows took 9.86 / 57.94 / 221.64 ms. These are cold one-run samples; the asymptotic conclusion follows from the repeated traversal/append in source.

**Fix:** use an indexed sequence or stage bulk child-order replacement inside a transaction; use a longest-increasing-subsequence move plan where it lowers actual host operations. Benchmark initial mount, middle edits, reversal, and random reorder through the host store, not only key comparisons.

### F17 — P1: Web virtual-list creates and attaches all rows

Location: [lui_web_nodes.ml:49](/Users/tiensonqin/Codes/projects/lui/platform/web/melange/nodes/lui_web_nodes.ml:49), [lui_web_nodes.ml:407](/Users/tiensonqin/Codes/projects/lui/platform/web/melange/nodes/lui_web_nodes.ml:407), DOM insertion in [lui_web_apply.ml:371](/Users/tiensonqin/Codes/projects/lui/platform/web/melange/shell/lui_web_apply.ml:371).

The Web virtual-list kind is a CSS class on a simple platform node. There is no viewport-window path: platform nodes are created and child DOM elements inserted for the full retained collection. The Web renderer also has no handling for the shared visible-range/scroll-token virtual-list protocol fields.

**Source-confirmed:** work and DOM size scale with total rows rather than visible rows. This combines with F16's initial child-list construction cost. No browser heap/frame benchmark was taken for a large virtual list.

**Fix:** implement viewport windowing with stable row IDs, measured/estimated row heights, spacer sizing, overscan, and the advertised scrolling/visible-range contract. A lazy native list and an ordinary Web container currently have materially different behavior under the same kind name.

### F18 — P2: Apple List identity changes with the global commit sequence

Location: [LUISwiftUIRoot.swift:6354](/Users/tiensonqin/Codes/projects/lui/platform/apple/Sources/LUIAppleBackend/LUISwiftUIRoot.swift:6354), [LUIAppleBackend.swift:1248](/Users/tiensonqin/Codes/projects/lui/platform/apple/Sources/LUIAppleBackend/LUIAppleBackend.swift:1248).

`.id(backend.commitSequence)` intentionally remounts List to avoid an iOS 26 collection-update assertion. The identity derives from every backend commit, applies across OS versions, and assumes all lists are small. When the List body is next reevaluated, a changed ID replaces its subtree, risking loss of native focus/scroll and row-local state while adding construction work.

**Source-confirmed; user-visible impact requires live testing.** `commitSequence` itself is not observable: an unrelated commit does not automatically prove every List recomposes. The issue is the changed identity whenever a List is reevaluated after the sequence changes.

**Fix:** preserve stable List identity during normal commits. Diagnose and coalesce affected structural updates or introduce narrowly scoped recovery for the actual inconsistent list/OS path. Validate insert/delete bursts with focus and scroll preservation on the affected OS.

## Findings: host contracts and review infrastructure

### F19 — P1: Web commits its retained mirror before applying the DOM

Location: [lui_web.ml:103](/Users/tiensonqin/Codes/projects/lui/platform/web/melange/shell/lui_web.ml:103), [lui_web_apply.ml:776](/Users/tiensonqin/Codes/projects/lui/platform/web/melange/shell/lui_web_apply.ml:776).

The store commits using an always-successful send callback. The renderer then applies DOM operations sequentially. A thrown DOM or extension callback after earlier operations leaves the store at the complete batch and the DOM at a partial batch. Exception conversion prevents silent generation replay, but does not rebuild the damaged DOM or restore the mirror.

**Source-confirmed failure boundary; no injected live DOM-failure test was run.** Separately, a compiled store probe confirmed that a false send callback consumes its generation and throws while rolling back node state: retrying that generation returns stale and leaves old text. That contract must be explicit to avoid callers treating false as safe retry.

**Fix:** define rejected, committed, and unknown outcomes consistently across hosts. For unknown DOM application, reset/rebuild from the authoritative retained snapshot and reinstall live handlers/extensions. A retained-store-only rollback cannot undo arbitrary platform side effects.

### F20 — P2: Web DOM extension drops legitimate false event fields

Location: [lui_web_dom_ext.ml:106](/Users/tiensonqin/Codes/projects/lui/platform/web/melange/extensions/lui_web_dom_ext.ml:106).

`is_undefined_json` returns true for `Js.Json.JSONFalse`. `put_target_fields` uses it to suppress values, so an unchecked input's `checked: false` field is omitted from the extension event detail instead of being sent. Consumers cannot reliably distinguish an unchecked value from an absent field.

**Source-confirmed:** line 115 creates a JSON boolean then passes it through this filter.

**Fix:** represent absence separately and preserve both boolean values. Add an extension event fixture for checked → unchecked transitions.

### F21 — P2: GPUI store accepts patches rejected by canonical validators

Location: [store.rs:280](/Users/tiensonqin/Codes/projects/lui/platform/gpui/crates/lui-core/src/store.rs:280), child attachment around line 435, [extension.rs](/Users/tiensonqin/Codes/projects/lui/platform/gpui/crates/lui-core/src/extension.rs).

GPUI resolves property names but does not validate standard property kind/value rules before insertion. Child attachment checks broad child acceptance without the complete parent/child constraints. Its extension registry is less descriptive than the fingerprinted typed extension contract. Existing core tests even use trees/operations other hosts reject, so store tests can pass despite protocol drift.

**Source-confirmed:** invalid property-kind/value combinations and illegal child pairings can enter the GPUI mirror. Normal OCaml-generated traffic is usually validated earlier, which narrows the exposure; imperative or externally supplied batches still cross this boundary.

**Fix:** generate value/relationship constraints from shared schema and run the same accept/reject fixtures on every store. Keep explicit host capability differences separate from accidental validation differences.

### F22 — P2: both checked-in performance entry points fail before measuring

Location: [qualify_runtime.sh:35](/Users/tiensonqin/Codes/projects/lui/tooling/performance/qualify_runtime.sh:35), [store_patch_bench.rs:46](/Users/tiensonqin/Codes/projects/lui/platform/gpui/crates/lui-core/examples/store_patch_bench.rs:46).

The qualification script builds a missing `test/lui_runtime_native.exe` and selects an obsolete `lui.benchmark-test` group. The GPUI store benchmark applies generation 2 five times during warmup, violating contiguous generation rules on the second iteration.

**Executed:** Dune reports it does not know how to build the target; the Rust release benchmark panics on repeated generation 2. Thus these tools currently provide no performance budget protection.

**Fix:** point qualification at a real benchmark executable/group, increment warmup generations, and exercise both entry points in CI. Include host-store single-property scaling, flat mounting, keyed reorder, and repeated branch mount/dispose workloads. Do not encode these one-run review timings as fixed cross-machine budgets.

## Complexity that can be simplified

1. **Runtime state and transactions:** `lui_runtime.ml` maintains many parallel mutable tables, count refs, aliases, and mutable segment records without an abstract module boundary. Snapshot, rollback, reload, resync, and reconciliation must each remember the same invariants. Introduce a small transaction journal shared by these paths, and an `.mli` exposing operations rather than mutable internals. Consolidate per-node state incrementally where it actually reduces duplicated bookkeeping. This directly addresses F02/F03/F13; avoid replacing the entire runtime at once.
2. **Renderer decomposition:** `LUISwiftUIRoot.swift` is about 8,000 lines; Android node rendering and Web popup/menu code are similarly broad. Existing policy modules show a workable direction. Extract component families with clear state/identity ownership and keep patch application separate from component behavior. Do not indiscriminately remove type erasure or add abstraction layers without evidence of benefit.
3. **Product-specific GPUI behavior:** hardcoded Logseq extension names and special rendering branches in `lui-gpui/src/extension.rs`, `root.rs`, and `kinds.rs` couple the generic host to one application. Move those adapters to registered extension/provider modules. Maintain the shared host contract in core and keep application-specific interactions at the extension boundary.

## Verification

All existing suites executed during this review passed:

| Suite | Result |
| --- | --- |
| OCaml `dune runtest` | 89 tests passed |
| Apple `swift test` | 167 tests in 7 suites passed |
| Rust `lui-core` | 24 tests passed |
| Android library unit/snapshot tests | 18 tests passed |
| Web check suite | 47 tests passed |
| Component-schema / PPX hygiene | 6 tests passed |
| Web browser layout, overlay, picker lifecycle, popup tracking subset | 68 tests passed |
| Web Melange build | Passed |

The browser selection is a subset, not the entire browser/visual matrix. Store probes exclude device layout/paint and are diagnostic scaling measurements, not production FPS or comparative platform performance claims. The standalone Android probes use built JVM classes; they do not replace instrumentation tests.

Run the standalone reproductions from repository root:

```sh
rtk proxy python3 docs/agent-guide/review-probes/2026-10-09/run.py
# Optional individual suites:
rtk proxy python3 docs/agent-guide/review-probes/2026-10-09/run.py runtime
rtk proxy python3 docs/agent-guide/review-probes/2026-10-09/run.py web
rtk proxy python3 docs/agent-guide/review-probes/2026-10-09/run.py android
```

Recorded output: [observed-results.txt](/Users/tiensonqin/Codes/projects/lui/docs/agent-guide/review-probes/2026-10-09/observed-results.txt).

The runner uses installed opam, Node, Java, Gradle/Android dependencies and creates compiler outputs in a temporary directory. It builds the existing project targets without adding or editing Dune declarations. Probes deliberately inspect runtime internals to make lifecycle and checkpoint failures observable; they are review harnesses rather than suggested public APIs.

## Recommended order

1. Fix Android scalar decoding, per-node observation, generation recovery, and bridge sessions (F07–F10); these can block normal app use.
2. Fix runtime owner identity and lifecycle transactions (F01–F06), with repeated mount/dispose and injected callback failures as regression fixtures.
3. Remove whole-application work from local updates, then implement Web virtual-list windowing and improve wide child operations (F13–F17). Establish working performance gates at the same time (F22).
4. Preserve native row/list identity, close host recovery/validation gaps, and simplify renderer/runtime structure in small changes (F11/F12/F18–F21).
