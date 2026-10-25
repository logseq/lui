# MyGo capabilities and LUI component parity

Research date: 2026-10-25. Updated after removal of the `br` component. This is a source and behavior investigation, not a
claim that the adapter implements the capabilities described below.

## Findings

MyGo supplies substantially more functionality than the current LUI adapter
uses. Virtual collections, tables, native context menus, anchored popups,
tabs, images, SVG icons and file dialogs already have framework APIs. Other
portable components can be composed inside the backend using its layout,
drawing and input primitives. Application-provided renderers should remain
an extension mechanism, not a requirement for standard portable LUI nodes.
The official [component catalog](https://mygo.egoist.dev/docs/ui) and
[base widgets](https://mygo.egoist.dev/docs/ui/custom-widgets) establish these
capabilities; implementation feasibility still requires matching LUI semantics.

The current schema contains **87 node kinds, including root, 186 properties,
and 25 event variants**. The adapter accepts **60** kinds without a custom
renderer and rejects **27**. Acceptance is not semantic parity: several of
the accepted kinds currently use generic rows, buttons or containers.
Sources: [schema](../../schema/components.json),
[rendering](../../platform/mygo/render.go), and
[protocol contracts](../../src/lui_protocol.ml).

The target remains all portable LUI components, properties and interactions.
An absent MyGo convenience widget is not evidence that a LUI component is
exclusive to Web, SwiftUI or Kotlin.

## Versions studied

| Item | Version |
| --- | --- |
| Current LUI dependency | `v0.4.9-0.20261013132844-43c624d77fdb`, Go 1.27.2 |
| Current official release | `v0.6.4`, commit `6255ea40139d06e0762a7c4a32626148ba410478` |
| Release toolchain requirement | Go 1.27.3 |

Verified against the [release](https://github.com/egoist/mygo/releases/tag/v0.6.4),
its [go.mod](https://github.com/egoist/mygo/blob/v0.6.4/go.mod), the downloaded
release source, and the source at the adapter's pinned commit. Website pages
can show different cached version footers; tagged source resolves API questions.

The newer release provides percentage split APIs and a deterministic Tester
clock. Its input binding also applies user edits before constructors return;
the older source applies pending input through response queries and after
construction. Review controlled bindings and callback timing when upgrading.
See [split](https://mygo.egoist.dev/docs/ui/split),
[testing](https://mygo.egoist.dev/docs/ui/testing), and the
[migration guide](https://mygo.egoist.dev/docs/ui/migration).

Recommendation: target a released version for parity work, with 0.6.4 as a
candidate. Resolve the observed OCaml startup instability before calling the
upgrade validated. This research does not change the repository's dependency
or toolchain requirement.

## Architecture constraints for the adapter

MyGo native UI draws its own controls; native desktop windows do not require
a web frontend. OS APIs, such as system menus and file dialogs, are a separate
layer. `App.Run` belongs on the process's initial main thread, where MyGo
builds views and delivers native events. Keep the existing dedicated OCaml
runtime thread and copy bridge results back before applying tree mutations.
See [architecture](https://mygo.egoist.dev/docs/architecture).

A window has a stable Context, but an Element expires at the next build pass,
including another pass in the same frame. Persistent node state may hold
Handle, ListState and resources; it must not retain Element values. Bind
identity before constructing stateful controls. Worker completions publish
through Window.Update. References: [views](https://mygo.egoist.dev/docs/ui/views)
and [Handle source](https://github.com/egoist/mygo/blob/v0.6.4/ui/ref.go).

Callbacks can safely change model collections after construction. Virtual
lists also construct rows during layout, after the main view callback has
returned. The existing `Backend.View` event queue covers only that callback;
adding virtualization requires a frame-safe delivery boundary for late row
builders and appearance events. This must be solved before dispatching OCaml
mutations from those builders. See
[list construction](https://github.com/egoist/mygo/blob/v0.6.4/ui/list.go).

## Complete node inventory

`M` means accepted by the current built-in kind list; it does **not** mean
all properties or behaviors are implemented. `U` means a renderer registration
is currently required. Every schema kind appears once below. Routes describe
the intended backend implementation, with unresolved points called out.

| LUI kinds | Now | MyGo route and remaining semantic work |
| --- | --- | --- |
| `root`, `row`, `column`, `grid` | M | Column, Row, Grid; extend shared property handling and constraints. |
| `stack` | U | Overlapping grid cells can size to the largest child; preserve stable child identities. |
| `edge-inset` | U | Layout main content with all following pinned children at the named edge; visibility and surface styling apply to the pinned region. |
| `overlay` | U | First child sets intrinsic size; other children use local absolute positioning and alignment. MyGo's window-global Overlay is a different operation. |
| `view-that-fits` | U | First candidate fitting the selected axis. No public arbitrary-subtree measurement hook found; needs further layout API work, not a window-width heuristic. |
| `box`, `panel`, `card`, `alert`, `bubble` | M | Styled containers; audit content slots, variants and interaction rather than treating every surface identically. |
| `text`, `heading`, `paragraph`, `label`, `kbd` | M | Text and RichText; preserve nested inline content, typography, heading roles and wrapping. |
| `button` | M | ButtonBase/Button; preserve child content, inline icons and pointer details. |
| `link` | M | Link and inline text primitives; preserve URL activation, child content, disabled behavior and press handlers. |
| `button-group`, `toggle-group`, `toggle-button` | M | Group layout and Toggle/Segmented bases where semantics match; keyboard and selection must follow LUI. |
| `toggle`, `checkbox`, `switch`, `radio`, `radio-group` | M | Native controls/bases; controlled values, indicator styles and disabled inheritance need explicit coverage. |
| `slider`, `progress` | M | SliderBase and Progress; honor applicable ranges, steps, orientation and styling. |
| `number-stepper` | M | NumberInput or numeric Stepper; range, step, keyboard editing and callbacks. |
| `text-field`, `secure-field`, `input`, `search-field`, `textarea` | M | TextInput/TextArea/SearchField and bases; audit read-only state, IME, submission, selection and focus. |
| `select`, `combobox` | M | Triggers/input plus retained menu nodes. Preserve model-owned menu lifetime and chosen-item events; plain input/trigger coverage is incomplete. |
| `tabs` | M | TabsBase behavior on the retained tab controls: roving focus, arrows, Home/End and orientation. Current generic Row is insufficient. |
| `bottom-tabs`, `bottom-tab` | M | Tab controls plus selected content panel; BottomTab children are page content, not the button's contents. |
| `scroll` | M | Scroll/ScrollHorizontal and ScrollState; add target intents and subscribed scroll events. |
| `list`, `list-item`, `list-section`, `list-section-header`, `list-section-footer` | M | Scroll or List as appropriate; preserve sections, item content, row events and nonvisual action children. |
| `virtual-list` | U | List and persistent ListState keyed by retained IDs; bridge visible ranges, target keys and scroll tokens. Overscan, extent hints and animated completion need additional work. |
| `table` | U | Table with retained row/cell adapters; check header conventions and shared column widths before choosing built-in versus composed grid. |
| `table-row`, `table-cell` | M | Preserve node identity, cell text/style, selection and events within the table adapter. Standalone row/text rendering does not provide a table. |
| `tree` | M | TreeItem or Outline according to LUI role/level structure; current Tree wrapper does not implement expansion and row navigation. |
| `accordion` | M | CollapsibleBase; map expanded state, trigger, content, events and keyboard behavior. |
| `split`, `resizable` | U | Split/SplitPercent plus backend resize primitives where required; preserve pixel-versus-ratio modes and custom handle properties. |
| `drawer` | U | Main content plus selected drawer panel, using split or modal overlay primitives; controlled toggle events and focus restoration. |
| `dialog`, `sheet` | M | DialogBase/Modal with distinct presentation styles; audit dismissal, placement and interaction boundaries. |
| `popover` | U | PopoverBase/AttachTo with node or rectangle anchors; model-owned presence, collisions and dismissal. |
| `tooltip` | U | TooltipBase or composed timing where LUI overrides it; resolve retained anchor and description. |
| `toast` | U | ToastViewportBase/ToastBase with retained content and duration; register/update/remove once per lifecycle, not on every render. |
| `dropdown-menu`, `context-menu`, `menu-trigger` | U | Native Menu for compatible system menus; retained in-window menu primitives for custom content and model-owned popups/submenus. |
| `menu-item` | M | Menu item checked/disabled/selected state and keyboard activation; a generic button alone is incomplete. |
| `icon` | U | ParseSVG/Icon with a built-in LUI asset registry and attribution. |
| `image` | U | Image plus backend resource lookup; fit modes, source rectangles, asynchronous loads and Load events. |
| `file-image` | U | Decode local image off-thread, constrain/cache decoding, publish bitmap and preserve path-update identity. |
| `media-surface` | U | Registered Bitmap updated on the UI thread; frames, cropping, fit, ownership and disposal. This is a portable resource API. |
| `avatar` | M | Avatar with decoded image/resource and text fallback; current text-only mapping is partial. |
| `stepper`, `step` | U | Compose a progress sequence with active index and connectors. MyGo's numeric Stepper is not this component. |
| `timeline`, `timeline-item` | U | Compose indicators, connector, title, description and metadata. MyGo Timeline coordinates animation, not activity entries. |
| `input-group`, `input-group-actions` | M | Compose textarea and action slots; audit shared surfaces, padding and focus behavior. |
| `breadcrumb`, `pagination` | M | Compose retained links/buttons with selected/disabled states and keyboard behavior. |
| `toolbar`, `status-bar` | M | Toolbar/container/text primitives with roles, item content and native styling. |
| `spacer`, `spinner`, `divider` | M | Direct primitives; verify orientation, sizing and state properties. |
| `swipe-actions`, `swipe-action` | U | Draggable/input primitives can compose row actions; decide desktop gestures and full interaction contract. Existing mobile implementation alone does not justify exclusion. |
| `file-picker` | U | Dialog.Open plus request/completion state machine and Picked/Dismiss bridge. Photo-library/camera sources need separate platform treatment. |
| `file-preview` | U | Existing native contract is an owned OS preview presentation with dismissal. MyGo has no equivalent identified; default-app OpenPath does not preserve that contract. |

LUI semantics above come from [elements](../../src/lui_elements.ml),
[Apple layout implementations](../../platform/apple/Sources/LUIAppleBackend/LUISwiftUIRoot.swift),
[drawer](../../platform/apple/Sources/LUIAppleBackend/LUIDrawerView.swift),
[Web styles](../../platform/web/src/lui.css), and
[Web node construction](../../platform/web/melange/nodes/lui_web_nodes.ml).
MyGo routes were checked against its
[grid](https://mygo.egoist.dev/docs/ui/grid),
[tabs](https://mygo.egoist.dev/docs/ui/tabs),
[table](https://mygo.egoist.dev/docs/ui/table),
[tree](https://mygo.egoist.dev/docs/ui/tree),
[outline](https://mygo.egoist.dev/docs/ui/outline),
[image](https://mygo.egoist.dev/docs/ui/image),
[text](https://mygo.egoist.dev/docs/ui/text), and
[context-menu](https://mygo.egoist.dev/docs/ui/context-menu) APIs.

## Specific mismatches to resolve

### Collections and scrolling

List virtualizes only with a finite viewport. Persist its ListState and use
retained node identities as keys so reordering does not move editor state to
another item. Visible returns inclusive first/last indices from the committed
frame, with last below first for an empty range; reading it requests another
build when the range changes. Map these semantics explicitly to LUI's events.
See [List](https://mygo.egoist.dev/docs/ui/list).

The source fixes overscan at two rows per side and exposes no overscan or
initial item-extent field. LUI transports these settings through `data-attrs`;
they cannot be dismissed as Web styling. The public ScrollTo request does
not expose LUI's completion token/outcome contract. Completion must follow
committed geometry, handle replacement/cancellation and missing targets,
and fire once per token. Animation needs separate validation. Sources:
[MyGo list state](https://github.com/egoist/mygo/blob/v0.6.4/ui/list.go) and
[LUI virtual scrolling](../../platform/web/melange/widgets/lui_web_virtual.ml).

### Menus, overlays and model ownership

LUI's gallery mounts select/combobox triggers and their menus as separate
retained nodes. Do not replace this with an independently controlled picker
that loses per-item handlers or stops reflecting the reducer. Build on
SelectBase/ComboboxBase only where their ownership model can be reconciled.
See [gallery usage](../../examples/gallery/view.ml),
[Select](https://mygo.egoist.dev/docs/ui/select), and
[Combobox](https://mygo.egoist.dev/docs/ui/combobox).

Overlay primitives already handle modal focus, Escape ordering, outside
presses and restoring focus. Popovers permit outside-click pass-through;
select popups consume that press. Preserve the correct behavior for each
LUI surface. Anchor Element references must be resolved within the current
pass, even when an anchor is built after its popup in retained order.
See [overlays](https://mygo.egoist.dev/docs/ui/overlays) and
[Popover](https://mygo.egoist.dev/docs/ui/popover).

TooltipBase uses framework timing; LUI-specific delay overrides still need
an implementation decision. Toast IDs must survive updates without resetting
their timer every frame, and detaching nodes must retire their toast state.
See [Tooltip](https://mygo.egoist.dev/docs/ui/tooltip) and
[Toast](https://mygo.egoist.dev/docs/ui/toast).

### Resources and files

Bitmap.Update reuses image storage/textures for changing frames.
Painter.ImageRegion exposes source-rectangle cropping, including in the
current pinned source. RegisterImage/PresentMediaSurfaceFrame-style backend
APIs can therefore support portable resource nodes without an app renderer.
Retain immutable pixels or follow Bitmap.Update's ownership rules; do not
mutate a supplied RGBA buffer while it remains in use. Sources:
[Bitmap](https://github.com/egoist/mygo/blob/v0.6.4/ui/bitmap.go) and
[ImageRegion](https://github.com/egoist/mygo/blob/v0.6.4/ui/paint.go).

Dialog.Open blocks until the system answers, so initiate it outside view
construction and publish the result on the UI thread. FilePicker must echo
the scalar request token in Picked JSON, retain the operation until matching
completion or disposal, and ignore stale results. Convert LUI content types
to platform filters deliberately; filename extensions and UTIs are different
formats. Sources: [desktop dialogs](https://mygo.egoist.dev/docs/native#dialogs)
and [LUI picker contract](../../platform/apple/Sources/LUIAppleBackend/LUIFilePickerView.swift).

### Properties, validation and events

Generated wire scalar tables do not establish per-kind legality or rendering
coverage. Mirror the protocol's parent/child rules: some leaf controls may
host ContextMenu, despite `container: false`; Table, BottomTabs, Stepper,
Timeline and MenuTrigger also have restricted children. The current generic
container check does not implement this full contract.

Audit all 186 properties against the host contract. Shared portable omissions
include interaction-state styling, roles, text overflow/whitespace, shadows,
transitions, several alignment modes and control-specific configuration.
CSS class names and DOM attributes can be Web-specific, but `data-attrs`
also carries semantic virtual-list settings and cannot be ignored wholesale.

The current renderer emits only a subset of the 25 standard events. The
runtime binds more than the renderer emits, but still lacks payload-bearing
events needed for full parity. Sources:
[rendering](../../platform/mygo/render.go),
[runtime dispatch](../../platform/mygo/runtime.go),
[shared C bridge](../../platform/native/lui_ocaml_bridge.c), and
[protocol](../../src/lui_protocol.ml).

| Events | Work to verify or add |
| --- | --- |
| Press, PressModifiers, TextChanged, ToggleChanged, ValueChanged, Change, Submit | Verify enabled subscriptions, controlled updates, modifiers and exactly-once dispatch for each applicable control. |
| Dismiss, Appear | Preserve model ownership; cover repeated passes, late virtual rows and node disposal. |
| LongPress, DoublePress, PointerEnter, PointerLeave | Runtime has corresponding node calls; renderer still needs behavior/subscription coverage. |
| PressDetail, PointerDown, PointerUp, ContextMenuPress | Add pointer payload and ABI bindings; translate local coordinates and button/modifier conventions. |
| ScrollCompleted, VisibleRange, ScrollEdges | Add payloads and ABI bindings; report committed state and honor subscriptions. |
| Picked, Load | File/image lifecycle events, request association and stale-result checks. |
| NavigatePrevious, NavigateNext, NavigationKey | Audit applicable native controls and transport; do not silently consume subscribed navigation events. |

MyGo's HandleInput supplies pointer coordinates, click counts, modifiers and
event times. Base widgets supply roles, keyboard behavior and accessible
states; composed widgets must preserve these too. See
[input source](https://github.com/egoist/mygo/blob/v0.6.4/ui/handler.go) and
[accessibility](https://mygo.egoist.dev/docs/ui/accessibility).

## Platform exceptions need precise boundaries

No entire missing component family has been approved for exclusion by this
investigation. The following are specific cases to document before finalizing
the support contract:

- FilePicker's `camera` and platform photo-library source are distinct from
  portable desktop file selection. The existing Apple backend explicitly
  treats camera as iOS-only.
- FilePreview currently owns Quick Look/document preview and receives its
  dismissal. Opening the default external app cannot reproduce that lifecycle.
  An OS integration or a precisely documented platform exception is needed.
- Safe-area/material details and browser-only attributes can vary by host.
  Their portable parent components remain in scope.

ViewThatFits, virtual-list tuning and custom split-handle behavior are
implementation/API gaps. They are not established platform exceptions.

## Behavior checks performed

Used an isolated copy of the Go package with MyGo 0.6.4 and Go 1.27.3; the
repository's go.mod/go.sum and implementation were left unchanged.

- Existing package tests passed with `go test -mod=mod -race -count=1 -v ./...`.
  The initial run skipped OCaml integration because its library variable was
  unset; a separate run against the real library is recorded below.
- A 10,000-row List in a 240 by 120 viewport initially built 10 rows across
  its settling passes, reporting visible range 0..4. Jumping to row 9,999
  reported 9,995..9,999, with 25 total row-builder invocations. This confirms
  viewport construction and distant scrolling, not full LUI list parity.
- Two grid children in the same cell, sized 50 by 20 and 80 by 90, produced
  an 80 by 90 parent. A separate local overlay with a 120 by 60 base and a
  400 by 90 absolute child kept its parent at 120 by 60.
- A source-rectangle drawing probe selected the blue half of a red/blue
  bitmap and verified the rendered center pixel was blue.

Real OCaml integration was tested against the existing Todos dylib on macOS
arm64. The first isolated 0.6.4/Go 1.27.3 run crashed at runtime startup with
`signal 16 received on thread with no signal stack` and
`non-Go code disabled sigaltstack`. Three subsequent focused fresh-process runs
and one complete-suite run with the real library passed.
The current dependency passed its comparison run on Go 1.27.2 and four runs
on Go 1.27.3. This does not isolate the cause to MyGo or to a toolchain change;
it establishes an intermittent native-runtime startup failure that needs
investigation. Do not suppress preemption or skip the real integration test
to call an upgrade successful.

These checks establish useful building blocks. They do not validate OS file
dialogs, live screen-reader behavior, all desktop platforms, or the missing
LUI event mappings.

The [observed results](review-probes/2026-10-25/observed-results.txt), capability
probes and isolated runner are checked in under
[review-probes/2026-10-25](review-probes/2026-10-25/run_mygo.py). From the repository
root:

```sh
# Only capability probes; downloads the released module/toolchain if necessary.
python3 docs/agent-guide/review-probes/2026-10-25/run_mygo.py

# Existing adapter tests plus probes; real OCaml test is skipped without a library.
python3 docs/agent-guide/review-probes/2026-10-25/run_mygo.py --all

# Build the real library separately, then include OCaml integration.
library=$(./tooling/build_mygo_todos.sh)
python3 docs/agent-guide/review-probes/2026-10-25/run_mygo.py --all --library "$library"
```

The runner copies the module to a temporary directory and pins MyGo 0.6.4 and
Go 1.27.3 there. It never edits the repository's dependency files. Its probes
measure individual framework capabilities, not the adapter's future support.

## Implementation and acceptance order

1. Upgrade a released dependency with existing race tests and real OCaml
   integration; preserve the toolchain requirement in usage and CI docs.
2. Complete protocol validation, event payload/ABI coverage and frame-safe
   delivery; introduce persistent per-node handles and disposal where needed.
3. Add resource registration, images/icons/media and local layered layouts.
4. Implement menus, popup surfaces and tabs with model-controlled lifetime,
   correct focus behavior and no application renderer requirement.
5. Implement collection adapters, visible-range/scroll contracts, split and
   composed controls; resolve the identified upstream layout/list API gaps.
6. Exercise the real OCaml gallery as well as Todos. Document exact host
   exceptions and verify every remaining standard kind without custom renderers.

For each family, write behavior tests first: initial rendering, property
updates/removal, child mutation, pointer/keyboard interactions, event payloads,
focus, disposal and disabled behavior. Test timer behavior with Tester.Advance,
not wall-clock sleeps. Collection tests must also assert viewport work,
prepend/reorder identity, distant targets, missing/cancelled requests and
exactly-once completion. Native dialogs and accessibility require desktop
smoke tests in addition to headless coverage.

A node-name smoke test alone is never the completion criterion. Completion
means the portable component's documented properties and interactions work
through the real OCaml runtime, with usage and reproducible test instructions.
