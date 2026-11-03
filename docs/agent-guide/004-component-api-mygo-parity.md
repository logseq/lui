# Component API and MyGo Parity Implementation Plan

Goal: Make every portable component in the optimized declarative LUI API work through MyGo's built-in backend, with explicit exceptions only for features particularly tied to Web or mobile platforms.

Architecture: LUI owns component semantics, controlled application state, the retained tree and event contracts.
MyGo supplies rendering, layout, native resources and its existing behavior bases for keyboard input, focus and accessibility.
The adapter translates between these layers without requiring application renderers for standard components.

Tech Stack: OCaml, the shared LUI JSON/C protocol, Go, MyGo, MyGo Tester, the existing DOM backend and desktop host integration tests.

Related: Builds on [003-mygo-capabilities_report.md](003-mygo-capabilities_report.md), the canonical [component schema](../../schema/components.json) and [public element API](../../src/lui_elements.mli).

## Execution status

Implementation branch `feat/mygo-component-parity`, based on merged PR #271.
The current validation results and complete Gallery recording are linked from [PR #273](https://github.com/logseq/lui/pull/273).
Native OCaml rendering and Metal/GPU work are excluded by the user's updated scope; the OCaml-to-MyGo application bridge remains in scope.

| Phase | Status | Evidence |
| --- | --- | --- |
| 1 | Implemented and verified | Behavioral acceptance committed in `7b2bb596`; exact canonical kind/property/child/event export, per-feature support inventory and generator rejection tests are implemented. Public typed virtual-list tuning and read-only editors are documented in the migration guide. |
| 2 | Qualified | OCaml 5.5 startup signal-stack ownership defect fixed in `36d0b843`. Both the previous pin and MyGo 0.6.4/Go 1.27.3 passed 20 fresh processes for each real application, three sessions per process, with profiling/preemption and pending signals: 80 processes total, no retries. The final integration runner also passed 40 fresh processes and 120 sessions on the pinned fork. The compatibility runtime preserves the upstream module identity and is pinned through a Go replacement to `logseq/mygo`; embedding applications copy that replacement. Third-party sources are excluded from LUI commits. |
| 3–8 | Implemented and verified | All standard kinds have built-in adapters. Family tests cover real layout, input, pixels, resource ownership, controlled no-patch rejection, menus, file previews and cancellation. Core OCaml 172, Swift 188, Android 41 and Web 156 regression tests passed; shared-schema checks passed. |
| 9 | Implemented; CI results linked from PR | Real Todos and all 25 Components event families pass with race checks. Real Gallery scrolling, conditional updates, modal dismissal, menu selection and resync pass. macOS native window/IME/NSAccessibility API and OS dialog cancellation checks passed. Real GTK/Win32 windows, native composition callbacks, ATK/UIA roles/actions, menu images/selection and file-dialog cancellation passed; audible screen readers and keyboard candidate UI remain outside the recorded API-level checks. CI includes headless macOS/Linux/Windows and real Linux/macOS OCaml integration. Full local race/oracle/integration/startup regression passed. The complete 76-section Gallery recording is embedded and playback-verified in PR #273; the three-host Go race/fuzz/vet and real Linux/Windows native smoke jobs passed. The current PR checks publish the final OCaml integration/startup results. |

Frozen decisions: automatic activation for ordinary tabs; bottom tabs own selected-page visibility; scroll outcomes `succeeded`, `cancelled`, `missing-target`; typed `overscan` and `item-extent` override legacy semantic attributes; read-only editors preserve focus/copy/navigation; registered image/media frames copy caller pixels and use positive resource IDs.

## Problem statement

The existing backend accepts many standard kinds but does not implement their complete properties, child contracts or interactions.
Examples include tabs rendered as rows, bottom tabs rendered as buttons, plain scroll containers in place of virtualization and picker triggers without complete retained-menu behavior.
Registering an application renderer is currently necessary for several ordinary portable components that MyGo can already implement.


The user-approved direction is to keep LUI's declarative public API and portable semantics, improve concrete inconsistencies, and use MyGo behavior bases wherever their semantics match.
Do not replace LUI with a Go widget API or rename components merely to mirror MyGo names.
The removed `br` component must stay absent from public constructors, protocol kinds, generated schemas and supported-kind claims.


MyGo also has a `js/wasm` Canvas/WebGL2 UI backend.
Its documented browser commands are `mygo dev -web` and `mygo build -platform web`; browser accessibility and file dialogs currently have explicit limitations in the [browser-host documentation](https://mygo.egoist.dev/docs/ui/browsers).
This does not turn its widgets into DOM components, and it does not make the current `dlopen`-based OCaml desktop bridge usable in a browser.
This plan targets desktop MyGo parity first and keeps the existing LUI DOM backend.
An optional LUI-on-MyGo browser host requires a separate transport/runtime design and is not a dependency of desktop parity.

## Testing Plan

Write the complete behavioral acceptance suite before adding implementation behavior, using existing wire batches and public controls to express the intended outcomes.
Tests for proposed public convenience arguments should first specify their equivalent retained-tree and event behavior, then verify the final constructor after its contract is frozen.
Do not use missing-symbol compiler errors, a list of accepted kind names, or screenshots alone as the red-test evidence.
Run each focused suite and record the intended assertion failures before implementing its family.


Add real MyGo Tester tests for initial rendering, set/remove property behavior, child insertion/removal/reordering, pointer and keyboard interaction, disabled/read-only behavior, focus preservation, accessible roles and disposal.
Capture reducer-directed updates in the dispatch sink and apply real batches on a safe boundary, including rejection or normalization of proposed input values.
Use deterministic toolkit time for long press, tooltip, toast and transition tests after qualifying the selected MyGo release.


Add payload-bearing bridge integration tests against the real OCaml app for every applicable event family, not only backend-local event recording.
Run Todos and Components against their own native libraries in separate Go processes because a process can load only one OCaml runtime library.
Drive Components pages through real retained node IDs and callbacks to verify complete component families rather than manufacturing only Go-side equivalents.
Keep custom gallery extensions explicitly registered, while proving standard components work with no `Config.Renderers` entries.
When a final shared validator rejects an absent or invalid property, the MyGo host must reject the same batch atomically, rather than rendering a different default.


Measure virtual collection work with a finite viewport, distant scrolling, prepend/reorder identity and visible ranges excluding overscan.
Test empty, one-item, variable-height and large collections, replaced/cancelled/missing scroll targets, and exactly one completion per request token.
Use pixel checks for layout sizing and source cropping where geometry or actual output is the contract.
For `view-that-fits`, verify measuring an unselected candidate cannot steal focus, emit appearance/input events, start native services or publish duplicate resources; candidate switching must obey the frozen retained lifecycle.
Use live desktop smoke tests for system dialogs, GPU windows, IME and screen readers because headless tests cannot establish those behaviors.


NOTE: I will write *all* tests before I add any implementation behavior.

## Repository rules and workflow

Read @/Users/tiensonqin/.codex/skills/test-driven-development/SKILL.md and @/Users/tiensonqin/.codex/skills/ocaml-development/SKILL.md before implementation.
Read @../../.agents/skills/lui-reactive/SKILL.md before editing any view that constructs `Lui_elements`.
Use `reactive` for reactive view construction and never introduce direct `dyn` calls.
Keep code, comments and PR text in English.
Do not disable warnings, use unsafe type casts or modify any `dune` file under this plan.
Existing native library targets and external linking scripts are sufficient for the planned integration.


All command examples run from the repository root and start with `rtk`.
Run Dune jobs serially, including wrappers such as schema generation or native-library builders that may invoke Dune.
Do not run Go integration simultaneously with a rebuild of the library it loads.
Each numbered implementation step below is a small action; repeat a family slice per behavior rather than implementing the whole family in one unreviewable change.

## Contract and coverage artifacts

Create `platform/mygo/capabilities.json` with entries for standard kinds, applicable properties, events and any feature-level host exceptions.
Give each portable feature an implementation route and a behavior-test reference.
Give each exception a precise feature, affected host, reason and primary source or existing platform contract.
Keep temporary implementation gaps distinct from justified exceptions.


Extend `tooling/generate_mygo_schema.py` to check the capability inventory against the final `schema/components.json` and protocol contracts.
Generate `platform/mygo/SUPPORT.md` from this inventory so documentation cannot silently omit a newly added kind.
Do not use a fixed count as the coverage assertion; compare exact sets from the final schema and reject duplicate, absent or unknown entries.
The current baseline after removing `br` is 87 kinds, 60 accepted by the built-in switch, but these numbers are descriptive and are not completion criteria.


Every property applicable to every kind needs a recorded behavior or an explicit host exception.
The scalar masks in `schema_generated.go` establish neither per-kind legality nor rendered behavior.
Preserve the protocol as the authority for legal parent/child relationships and values.
Generate additional metadata from canonical inputs or export authoritative metadata rather than creating a second manually maintained validator.

## API optimization decisions to freeze before implementation

These are bounded design decisions, not authorization for broad breaking renames.
Preserve existing public names and behavior unless a demonstrated inconsistency requires migration.

| Area | Proposed contract | Compatibility and decision required |
| --- | --- | --- |
| Controlled values | Text, checked/selected/expanded state, split values, selected pages and popup presence remain model-owned; widgets emit proposals. | Specify immediate toolkit edits versus accepted reducer values, including rejection and normalization. |
| Ephemeral state | Caret, IME composition, hover, pressed state, roving focus, drag progress and measurement caches belong to the host unless explicitly exposed. | Preserve these through moves of the same retained identity and reset them on disposal or replacement. |
| Collection tuning | Keep `virtual_list ?overscan ?item_extent` public arguments and promote their semantic data attributes into typed protocol properties. | Freeze final property names; read the old `data-overscan` and `data-item-extent` representation during migration, with explicit typed values taking precedence. |
| Scrolling | Retain target, anchor, token, animation, visible-range and completion semantics across list and virtual-list. | Freeze the complete outcome vocabulary and event ordering from existing Web/Apple contracts before sharing helpers. |
| Anchors | Keep point, target identifier and rectangle forms, with shared exclusivity and finite-value validation. | Centralize normalization without replacing ordinary labelled arguments with a new mandatory configuration object. |
| Tabs and selection | Document trigger roles, selected content, activation policy and keyboard orientation. | Preserve `tabs` composition and `bottom_tab` content semantics; do not silently invent or require a new tab child type. |
| Split and resizable | Keep fraction versus pixel modes explicit and mutually exclusive where the existing API requires it. | A LUI fraction is 0..1 while MyGo percentage helpers use 0..100; preserve existing handle and resize event semantics. |
| Stepper and timeline | Keep progress-sequence `stepper` and activity-entry `timeline` semantics. | Explain their difference from MyGo's numeric Stepper and animation Timeline rather than renaming the public LUI API. |
| Resources | Standardize backend image registration and media-frame publication with ownership, generation and retirement rules. | Reuse existing Web/Apple registration semantics; freeze Go API names after reviewing those hosts. |
| File services | Keep picker request/completion correlation and distinguish file access from OS-owned preview presentation. | Separate mobile sources and preview-service capabilities at feature level rather than removing portable file components. |

## Per-component implementation inventory

Use this grouping to divide work, then generate the final per-kind matrix from the frozen schema.
Each applicable component must have render, update/remove, interaction, identity and disposal coverage, including kinds already accepted today.

| Family | Schema kinds | Implementation route and behavior gate |
| --- | --- | --- |
| Basic layout | `root`, `row`, `column`, `grid`, `spacer` | Direct primitives with measured constraints, growth, spacing, alignment and wrapping. |
| Layered layout | `stack`, `overlay`, `edge-inset`, `view-that-fits` | Overlapping intrinsic grid, local absolute overlays, pinned-edge layout and genuine candidate measurement. |
| Surfaces | `box`, `panel`, `card`, `alert`, `bubble` | Distinct surface variants, content and styling; avoid identical generic-column behavior. |
| Text | `text`, `heading`, `paragraph`, `label`, `kbd`, `link` | Inline content, wrapping/overflow, typography, roles, link activation and event precedence. |
| Buttons and groups | `button`, `toggle-button`, `button-group`, `toggle-group` | Existing behavior bases, child content, selection, keyboard and disabled inheritance. |
| Choice controls | `toggle`, `checkbox`, `switch`, `radio`, `radio-group` | Controlled proposals, group navigation, indicator styling and accessible state. |
| Numeric controls | `slider`, `number-stepper`, `progress` | Range, step, orientation, editing, keyboard behavior and normalized values. |
| Text input | `text-field`, `secure-field`, `input`, `search-field`, `textarea` | IME, selection, focus, read-only state, submission and reducer reconciliation. |
| Picker controls | `select`, `combobox` | Behavior bases reconciled with separately retained model-owned menus and per-item handlers. |
| Tabs | `tabs`, `bottom-tabs`, `bottom-tab` | Roving focus, Home/End/arrows, orientation, controlled selection and correct selected-page content. |
| Lists | `scroll`, `list`, `virtual-list`, `list-item`, `list-section`, `list-section-header`, `list-section-footer` | Persistent scroll/list state, sections, virtualization, row identity and full scrolling event contract. |
| Tables and trees | `table`, `table-row`, `table-cell`, `tree` | Shared column sizing and header semantics, retained cells, expansion/selection and keyboard traversal. |
| Resizing | `split`, `resizable` | Fraction/pixel conversion, constraints, custom handles, pointer/keyboard resizing and transitions. |
| Popup surfaces | `dialog`, `sheet`, `drawer`, `popover` | Distinct placement, focus boundaries, Escape/outside policy, dismissal and restoration. |
| Menus | `dropdown-menu`, `context-menu`, `menu-trigger`, `menu-item` | Native menus where compatible, retained custom-content menus elsewhere, disabled/checked state and submenu navigation. |
| Notifications | `tooltip`, `toast` | Anchor lifecycle, deterministic delay/duration, update without timer reset and exactly-once dismissal. |
| Graphics | `icon`, `image`, `file-image`, `media-surface`, `avatar` | Built-in SVG registry, decoded resources, fallback, fitting/cropping, load events and frame ownership. |
| Structured composites | `stepper`, `step`, `timeline`, `timeline-item`, `accordion` | Progress/activity semantics, connectors, controlled expansion and appropriate roles. |
| Content groups | `input-group`, `input-group-actions`, `breadcrumb`, `pagination`, `toolbar`, `status-bar` | Retained content slots, shared styling, selected/disabled state, focus and navigation. |
| Basic indicators | `spinner`, `divider` | Animation, orientation, sizing, colors and disposal. |
| Row actions | `swipe-actions`, `swipe-action` | Desktop pointer/trackpad semantics plus a discoverable keyboard-accessible action path; no mobile-only exclusion by widget name. |
| File services | `file-picker`, `file-preview` | Request/completion lifecycle and supported OS services, with precise exceptions below. |

## Feature-level exception policy

An absence of a stock MyGo widget, a current adapter limitation or an upstream API gap is never a platform exception.
The completion gate includes composed widgets and necessary upstream work.
Keep exceptions attached to individual capabilities so a portable parent component remains supported.

| Candidate feature | Desktop MyGo disposition | Optional MyGo browser disposition | Evidence and completion requirement |
| --- | --- | --- | --- |
| CSS classes, arbitrary DOM attributes and DOM-specific effects | Explicit host-specific behavior; portable style properties still apply. | Canvas widgets are not DOM nodes; retaining the existing DOM backend preserves these features. | Audit properties individually, especially semantic values currently stored in `data-attrs`. |
| Picker camera and OS photo-library sources | Mobile-source exception where no corresponding desktop service exists. | Requires browser permission/service integration rather than desktop dialog calls. | Cite `LUIFilePickerView.swift`, existing mobile contracts and documented host capability. |
| Mobile safe-area and platform material details | Use meaningful desktop equivalents where defined; document the remaining platform detail. | Define viewport/inset inputs if a browser host is later built. | Do not exclude `edge-inset`, `sheet`, `drawer` or their portable layout semantics. |
| File preview and OS-specific presentation | Portable file preview remains in scope, with explicit supported formats, owned presentation and dismissal; an Apple Quick Look presentation can remain a host extension. | Browser resource presentation needs its own lifecycle/security contract. | No stock MyGo preview API is an implementation gap, not a desktop exception; external `OpenPath` does not fulfill the contract, and unresolved portable preview behavior blocks parity. |
| Native paths, local decoding and system menus | Supported through desktop resources and OS services. | Capability-specific resource handles, user gestures and browser services are required. | These browser restrictions do not justify missing desktop components. |

The table lists decisions to substantiate, not a preapproved blanket exception list.
Record the final accepted scope in `platform/mygo/capabilities.json` and generated `SUPPORT.md` before marking parity complete.

## Phase 1: Freeze contracts and write the red suite

Files: `src/lui_elements.ml`, `src/lui_elements.mli`, `src/lui_protocol.ml`, `src/lui_protocol.mli`, `schema/components.json`, `tooling/generate_component_schema.mjs`, `tooling/generate_mygo_schema.py`, `test/test_lui.ml`, `test/test_audit.ml`, `tooling/test/component_schema_test.mjs`, and new family tests under `platform/mygo/`.

1. Enumerate every final schema kind, its allowed properties, child shapes and event subscriptions into the proposed capability inventory.
2. Freeze the API decisions above by documenting defaults, precedence, invalid combinations and migration behavior.
3. Add constructor/protocol behavior tests for the optimized contract and retain the existing regression tests rejecting removed `br` wire nodes.
4. Add `layout_test.go`, `controls_test.go`, `menus_test.go`, `collections_test.go`, `resources_test.go`, `composites_test.go`, `events_test.go` and `lifecycle_test.go` with acceptance cases for every family in the inventory.
5. Add a test dispatch helper that applies real model responses after the current render/input phase, including a response that removes or replaces the emitting node.
6. Add runtime-event and Gallery integration tests to `runtime_test.go`, expressing required payloads through actual retained subscriptions.
7. Run the focused tests and save the expected missing-behavior assertion failures, separating them from infrastructure failures.
8. Commit the contract and complete behavioral tests before adding implementation behavior.


Run the following checks serially after adding tests:

```sh
rtk proxy python3 tooling/generate_mygo_schema.py --check
rtk proxy node --test tooling/test/component_schema_test.mjs
rtk proxy go -C platform/mygo test -count=1 -run 'Test(Layout|Controls|Menus|Collections|Resources|Composites|Events|Lifecycle)' ./...
```

Expected result: existing checks identify genuine drift if the contract changes, and new behavioral cases fail on missing semantics in the current backend.
Fix test setup, names or fixtures before implementation if failures are caused by an invalid test rather than the intended missing behavior.

## Phase 2: Qualify a released MyGo dependency and runtime startup

Files: `platform/mygo/go.mod`, `platform/mygo/go.sum`, `platform/mygo/runtime.go`, `platform/mygo/runtime_unix.go`, `platform/mygo/runtime_windows.go`, `platform/mygo/runtime_test.go`, `tooling/test_mygo.sh`, `.github/workflows/mygo.yml` and `platform/mygo/README.md`.

1. Use the completed startup tests to compare the current pin and candidate release in isolated package copies and fresh processes.
2. Record exact OS, architecture, Go/MyGo/OCaml/purego versions, native thread registration, signal state and startup crash traces.
3. Investigate the observed `non-Go code disabled sigaltstack` failure with a minimal real OCaml startup reproducer and source-level runtime analysis.
4. Fix the underlying integration defect or qualify a dependency/toolchain combination whose safety is explained by evidence; do not hide the failure using disabled preemption or test skips.
5. Upgrade to a released MyGo version only after the existing and new runtime gates pass, with 0.6.4 and Go 1.27.3 as the researched candidate rather than a permanent version mandate.
6. Reconcile changed input-binding timing so the reducer's controlled value remains authoritative without resetting caret or IME state every frame.
7. Run a documented fresh-process startup soak, including both native libraries in distinct processes, and preserve failures as release blockers.
8. Update documented requirements and CI toolchain selection together, then commit the qualified dependency/runtime change.


Do not treat a few successful retries as resolution of the intermittent signal-stack failure.
If an upstream fix is necessary, record its issue and exact revision, and keep dependency qualification open until the chosen release contains a justified solution.

## Phase 3: Complete protocol, identity and frame-safe event delivery

Files: `platform/mygo/backend.go`, `platform/mygo/wire.go`, `platform/mygo/render.go`, `platform/mygo/runtime.go`, `platform/mygo/schema_generated.go`, `tooling/generate_mygo_schema.py`, `platform/native/lui_ocaml_bridge.c`, `platform/native/lui_caml_dispatch.h` and the corresponding red tests.

1. Implement authoritative per-kind property/value and child validation, including legal `ContextMenu` children beneath otherwise leaf controls.
2. Preserve atomic rollback for invalid batches without committing state creation, resource disposal or queued events from rejected operations.
3. Give retained node incarnations stable keys, persistent `ui.Handle` references and explicit disposal; never retain an `ui.Element` across build passes.
4. Separate reducer-owned values from transient toolkit state and test accepted, rejected and normalized model responses.
5. Replace the view-callback-only queue with a verified safe delivery boundary covering late virtual row builders and multiple layout passes.
6. Keep OCaml callbacks copy-only, with C ABI calls confined to the existing registered runtime worker thread and no render-time reentry.
7. Extend `Event` and runtime bindings for payload-bearing events, validating lengths, finite coordinates, modifiers, button conventions and integer ranges against the shared C ABI.
8. Handle every standard event from the final schema: press variants, long/double press, text/toggle/value/change/submit, dismissal/appearance, pointer variants, scroll events, picker/load and navigation.
9. Honor event subscriptions, once-per-lifecycle/token guarantees, stale node incarnations and unmount during callback delivery.
10. Run focused validation, event and lifecycle tests to green, then commit the runtime foundation before component slices.

## Phase 4: Apply the optimized API with compatibility

Files: `src/lui_elements.ml`, `src/lui_elements.mli`, `src/lui_protocol.ml`, `src/lui_protocol.mli`, `src/lui_json.ml`, `src/lui_json_view.ml`, `src/lui_json_view_parse.ml`, `src/lui_wire_schema.ml`, `platform/web/melange/render/lui_web_props.ml`, `platform/web/melange/widgets/lui_web_virtual.ml`, `platform/apple/Sources/LUIAppleBackend/LUIWireSchema.swift`, `platform/apple/Sources/LUIAppleBackend/LUIWireProtocol.swift`, `platform/apple/Sources/LUIAppleBackend/LUISwiftUIRoot.swift`, `platform/android/lui/src/main/kotlin/dev/lui/LuiWireSchema.kt`, `platform/android/lui/src/main/kotlin/dev/lui/LuiKindRules.kt` and their existing tests.

1. Add only frozen API improvements with demonstrated cross-platform value, beginning with typed virtual-list tuning and shared validation/normalization.
2. Preserve old constructor signatures wherever possible by adding optional arguments or clarifying existing contracts.
3. Decode legacy virtual-list semantic attributes alongside typed properties during migration and test precedence, removal and mixed input.
4. Regenerate artifacts using `rtk proxy make generate-component-schema` and `rtk proxy make generate-json-view` only when their source inputs changed.
5. Update all existing hosts that consume a changed protocol property in the same slice, then run their affected behavior tests.
6. Migrate examples to the preferred representation while keeping compatibility tests for retained legacy input.
7. Document any unavoidable breaking change, schema-version implication and removal timeline; do not silently repurpose an existing wire name.
8. Commit each independently verified contract change without waiting for unrelated components.

## Phase 5: Complete shared properties, layout and resources

Files: `platform/mygo/render.go`, `platform/mygo/theme.go`, new `platform/mygo/layout.go`, new `platform/mygo/resources.go`, new `platform/mygo/icons/`, `platform/web/src/icons/`, `platform/mygo/backend.go` and the red layout/resource tests.

1. Implement and test every applicable shared dimension, alignment, spacing, border, color, opacity, text-flow, role and interaction-state style property.
2. Specify property removal as restoration to inherited/default behavior and verify scoped adaptive tokens across theme changes.
3. Implement stack intrinsic sizing and local overlay sizing separately; do not use a window-global overlay for ordinary LUI layering.
4. Implement all pinned edge children and visibility in `edge-inset`, including content sizing and logical leading/trailing edges.
5. Resolve `view-that-fits` using genuine candidate measurement and selected-axis constraints with side-effect-free probes; use a focused upstream layout extension if needed rather than guessing from window width.
6. Add built-in SVG lookup with canonical icon naming and preserve upstream icon attribution/license files.
7. Implement image registration, asynchronous URI/file decoding, cache limits, cancellation and generation-aware publication on the UI thread.
8. Implement image fitting and source-region cropping with real rendered-pixel assertions, including invalid/missing resources and path changes.
9. Implement media-frame publication with explicit immutable-buffer or copy ownership, replacement and retirement, then complete avatar image/fallback behavior.
10. Run focused tests, assert no stale worker completion touches disposed nodes, and commit coherent layout/resource slices.

## Phase 6: Complete controls, menus, popups and tabs

Files: `platform/mygo/render.go`, new `platform/mygo/controls.go`, new `platform/mygo/menus.go`, new `platform/mygo/overlays.go`, new `platform/mygo/tabs.go` and the corresponding red tests.

1. Reconcile text/numeric/choice controls with controlled state, content slots, ranges, read-only/disabled inheritance, IME and subscribed navigation events.
2. Build group keyboard behavior and accessible state on MyGo bases where compatible, preserving per-node handlers and stable identity.
3. Resolve anchors within the active pass, including anchors built after a popup, rectangle anchors and removed targets.
4. Implement context, dropdown and submenu behavior with native menus only where they preserve the LUI contract; compose retained custom content on MyGo bases otherwise.
5. Complete select and combobox using retained model-owned menus, with correct outside-press policy, search/edit behavior, focus and item activation.
6. Implement tabs with orientation, arrows, Home/End, selected state and disabled items, then implement bottom-tab content panels separately from their triggers.
7. Distinguish dialog, sheet, drawer and popover presentation, modal boundaries, dismissal, focus restoration and nested Escape ordering.
8. Implement tooltip overrides and toast registration/update/removal without resetting timer state on every rebuild.
9. Verify keyboard-only operation, simultaneous surfaces, reducer-delayed removal and disposal during callbacks, then commit each family.

## Phase 7: Complete collections, scrolling and resizing

Files: new `platform/mygo/collections.go`, new `platform/mygo/scroll.go`, new `platform/mygo/split.go`, `platform/mygo/backend.go`, `platform/mygo/render.go`, relevant schema/protocol files if typed tuning is added, and the collection/layout red tests.

1. Implement ordinary scroll/list sections and persistent virtual-list state keyed by retained identity, with finite viewport constraints.
2. Resolve the upstream fixed-overscan/extent gap through a focused public API extension or a backend virtualizer that fulfills the same contract, with complexity and measurement tests.
3. Keep virtualized-out rows distinct from detached nodes so retained state and appearance semantics follow the frozen lifecycle contract.
4. Implement scroll intents using committed geometry, key lookup, anchor modes and request tokens, with cancellation/replacement and missing-target outcomes.
5. Implement visible ranges and scroll-edge notifications from committed viewport intersections rather than overscan construction ranges.
6. Verify animated completion follows settled layout and fires exactly once, including a target removed during animation.
7. Implement table header/column sizing and retained cell construction, choosing MyGo Table only where it preserves the frozen LUI table contract.
8. Implement tree expansion/selection, hierarchical navigation and accessible levels using Tree/Outline bases as appropriate.
9. Implement fraction/pixel split modes, clamping, custom handles, resize callbacks, keyboard access and animation; complete `resizable` as its own documented contract.
10. Run large-list performance and identity tests, then commit each collection/resizing slice after its behavior tests pass.

## Phase 8: Complete composites and file services

Files: new `platform/mygo/composites.go`, new `platform/mygo/files.go`, `platform/mygo/backend.go`, `platform/mygo/render.go`, `platform/mygo/runtime.go`, `examples/gallery/view.ml`, `examples/gallery/model.ml` and the composite/resource/event red tests.

1. Implement stepper/step and timeline/item as progress/activity compositions with their existing selected, active, connector and metadata semantics.
2. Complete accordion, input-group/actions, breadcrumb, pagination, toolbar, status-bar, spinner and divider behavior beyond basic layout.
3. Implement swipe actions with deliberate desktop gestures, cancellation, disabled handling and an accessible action path, preserving retained action handlers.
4. Implement file-picker requests outside view construction and publish completions safely on the UI thread.
5. Preserve scalar request-token echo, filter conversion, directory/multiple modes, completion acknowledgement, cancellation and stale-result rejection.
6. Freeze supported portable preview formats and implement owned desktop preview plus dismissal; isolate optional OS-specific presentation features without excluding the standard component or substituting external-app launching.
7. Add or update Gallery examples for every optimized public API using `reactive`, without introducing standard-component renderer registrations.
8. Run focused behavior tests and live dialog/preview checks, then commit the remaining families.

## Phase 9: Real application integration and cross-platform qualification

Files: `tooling/build_mygo_todos.sh`, new `tooling/build_mygo_components.sh`, `tooling/test_mygo.sh`, `platform/mygo/runtime_test.go`, `platform/mygo/cmd/lui-mygo/main.go`, `.github/workflows/mygo.yml`, `platform/mygo/README.md`, generated `platform/mygo/SUPPORT.md` and the root `README.md`.

1. Build Components using its existing `examples/components/native/liblui_components.dylib` target on macOS and analogous existing archive linking on Linux, without changing Dune files.
2. Make the integration runner launch one process for Todos and another for Components, using separate `LUI_MYGO_TEST_LIBRARY` and `LUI_MYGO_COMPONENTS_LIBRARY` selections.
3. Register only the actual Gallery extension schemas and prove all portable standard nodes work without custom renderers.
4. Drive Gallery navigation and each family through real OCaml subscriptions, including updates, removals, resync and event-induced tree changes.
5. Run headless/race/fuzz/vet/schema checks on macOS, Linux and Windows, adding Linux runtime integration where its native toolchain is available.
6. Run live native-window, IME, file-service and screen-reader smoke checks on all claimed desktop hosts, recording unsupported host features in the capability matrix.
7. Re-run the startup soak after the final dependency and runtime changes, keeping crash evidence rather than retrying failures away.
8. Generate the final support matrix, verify every final-schema portable feature has behavioral evidence, and update usage/testing instructions plus PR description in English.


Existing commands, run serially:

```sh
rtk proxy make test-schema
rtk proxy make test-ocaml
rtk proxy make build-web-css
rtk proxy swift test
rtk proxy /bin/bash -c 'cd platform/android && ./gradlew :lui:testDebugUnitTest --tests dev.lui.LuiWireTest --tests dev.lui.LuiStoreTest --console=plain'
rtk proxy make test-mygo
rtk proxy make test-mygo-integration
rtk proxy go -C platform/mygo test -run '^$' -fuzz FuzzApplyJSON -fuzztime 30s
rtk proxy go -C platform/mygo vet ./...
rtk proxy opam exec -- dune build examples/components/native/liblui_components.dylib
```

Expected result: passing schema/OCaml/DOM regressions, passing Go race and behavioral tests, no fuzz failures, no vet diagnostics and a built Components library on macOS.
The existing `test-mygo-integration` runner covers Todos today; update it before claiming it covers Gallery.


After implementing the new runner, its interface must support this sequence:

```sh
rtk proxy /bin/bash -euc 'lui_todos_library=$(./tooling/build_mygo_todos.sh); LUI_MYGO_TEST_LIBRARY="$lui_todos_library" go -C platform/mygo test -race -count=1 -run "^TestOCamlTodos" ./...'
rtk proxy /bin/bash -euc 'lui_components_library=$(./tooling/build_mygo_components.sh); LUI_MYGO_COMPONENTS_LIBRARY="$lui_components_library" go -C platform/mygo test -race -count=1 -run "^TestOCamlComponents" ./...'
```

Expected result: both real applications pass in independent processes, with neither integration suite silently skipped.
Add runner checks that fail if its required library variable is absent, while preserving a documented unit-only mode for ordinary local Go tests.

## Completion gates

| Gate | Required evidence |
| --- | --- |
| API contract | Documented defaults, ownership, child shapes, events and compatibility behavior; `br` remains removed. |
| Exact coverage | Generated inventory matches the final schema, every portable kind/property/event has behavior tests, and every exception is feature-specific and justified. |
| Built-in behavior | No portable standard component depends on application-provided `Config.Renderers`, and accepted kinds do not hide placeholder behavior. |
| Correct lifecycle | Stable identity across moves, stale completion rejection, safe event delivery through late rows, resource retirement and exactly-once lifecycle/request events. |
| Runtime safety | Explained and corrected signal-stack startup behavior, fresh-process soak and real OCaml integration passing without masking failures. |
| Layout and performance | True fitting/overlay geometry, bounded virtual construction work and no quadratic collection update paths. |
| Host qualification | Passing desktop matrix and recorded live-service, IME and accessibility checks for each claimed platform. |
| User review | Visible GitHub usage instructions, reproducible tests and an accurate PR support summary. |
| Recorded demo | A complete Gallery demo recorded after completion, linked or embedded in the created PR description, covering component families and representative interactions. |

## Testing Details

Behavior tests must drive MyGo's actual input/layout/rendering path and inspect resulting visible content, geometry, focus, accessible state and dispatched model effects.
Protocol tests must demonstrate accepted and rejected operations plus atomic retained-tree behavior, rather than merely comparing generated tables.
Resource tests must inspect actual rendered source regions and asynchronous retirement behavior.
Real OCaml tests must validate the full reducer-to-wire-to-MyGo-to-event-to-reducer loop for Todos and Gallery in separate processes.
Live desktop checks cover OS behavior unavailable to the headless tester and are recorded alongside automated evidence.

## Implementation Details

- Keep LUI's declarative contract and model ownership as the public abstraction.
- Prefer MyGo behavior bases for focus, keyboard and accessibility instead of rebuilding those policies.
- Persist node handles, toolkit state and resources, but never pass-scoped Element values.
- Centralize authoritative validation, controlled-state reconciliation and lifecycle cleanup.
- Build standard composed widgets into the backend rather than outsourcing them to application renderers.
- Preserve the existing DOM backend and treat a future MyGo browser host as a separate runtime integration.
- Resolve upstream fitting/overscan gaps explicitly; do not mark portable semantics platform-exclusive.
- Migrate typed semantic properties compatibly across all affected hosts.
- Keep dependency qualification and signal-stack safety as release gates.
- Generate support claims from exact feature coverage and behavioral evidence.

## Question

Freeze tabs activation policy, scroll outcome vocabulary, typed tuning property names and resource API names in Phase 1 using existing contracts as the default.
Resolve the portable file-preview formats and implementation on every claimed desktop host; only OS-specific presentation features may remain host extensions.
Determine the cause of the intermittent OCaml signal-stack startup failure before selecting the final dependency/toolchain combination.
Decide whether to contribute minimal MyGo measurement and list-tuning APIs upstream or implement equivalent backend primitives without weakening the public LUI contract.
No question above blocks writing tests, auditing contracts or completing independent component families, but unresolved completion-gate items prevent declaring full parity.

---
