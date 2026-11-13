# LUI API migration guide

## Unreleased: Apple grouped controls host anchored popovers

Named popover targets inside a button group now mount the same presentation
host and frame reporting as standalone nodes. For example, a Popover with
`anchor-target: "group-action"` can target that button's accessibility identifier
inside a `button-group`; group keyboard navigation keeps its existing behavior.

## Unreleased: Apple sibling paint order and transparent inline wrappers

Row, Column and Box now place flow and absolute children in one sibling paint
scope. Their integer `z-index` values order complete child surfaces; equal values
retain wire child order. Absolute children still contribute no intrinsic extent,
gap or grow weight. For example, a Text with `z-index: 1` paints above an opaque
absolute selection layer with an omitted (zero) z-index. No client mutation or
selection transparency change is needed. Stack children also honor `z-index`.

Inside Text, `display: contents` wrappers now contribute their Text descendants
to the same committed TextKit document, recursively inheriting typography and
foreground. A label containing `text [box ~display:"contents" [text "Nov"]]`
therefore renders "Nov" instead of an empty label. The wrapper creates no native
box or reported frame; leaf Text nodes retain their ranges and geometry.
This inline behavior does not flatten wrappers in Row/Column flow layouts.

## Unreleased: `display: none` leaves flow layout on Apple

`display: none` children are now removed from the parent's flow
enumeration entirely — no frame slot, no `gap`/`space-between` spacing,
no `grow` absorption, and no `main: center|end` spacer suppression on
`row`, `column`, `box`, `stack` and the horizontal group kinds. Auxiliary
slots (menus, tooltips) and extension children are unchanged. Hidden
nodes still report no frames. Clients already treating `display: none`
as "not rendered" only lose the previously stray spacing; no migration
required.

## Unreleased: Apple macOS native split divider replaces the overlay handle

On macOS, native `split` columns (`NavigationSplitView`) now use the system
divider: held-pointer drags resize the sidebar natively and emit the existing
split value-change event, matching the iOS behavior. The detail-leading
overlay divider handle is removed, including its arrow-key and
`accessibilityAdjustableAction` stepping; keyboard and assistive
adjustments now go through the system control.

Model-driven `fraction` changes still resize the column programmatically:
the backend applies the requested width once per push through the
NSSplitView's public position API and tracks the rendered width locally.
Programmatic applies do not emit a `value-change` event — pushes were
never echoed back before. The divider keeps its flexible bounds
throughout, so drags are never locked.

Native resize events use the backing `NSSplitView` arranged pane width,
observed through its public resize notification. A child with `max-width`
no longer stops `value-change` events as the divider moves beyond that
child's width. Model-driven width applications remain silent.

Collapse and reopen through window chrome behave as before, including the
hairline-fraction value change reported on collapse and the rendered-width
report on reopen.

## Unreleased: macOS `requestFocus` accepts `button` and `menu-item`

`LUIAppleBackend.requestFocus(nodeID:)` previously accepted only text
inputs. On macOS it now also accepts `button` and `menu-item` nodes,
using the same contract: latest request wins, the pending request is
consumed once by the retained node it was issued for (including nodes
still awaiting mount), and `focusedNodeID` reports whichever control —
text input or generic — currently owns focus. Items rendered into real
`NSMenu`s (e.g. menu-bar menus) cannot take programmatic focus and never
consume a request. iOS behavior is unchanged: `requestFocus` still accepts
text inputs only there.

A focused macOS `menu-item` view now activates its existing `press` action on
Return, including an item focused through `requestFocus(nodeID:)`. Disabled or
replaced retained nodes do not activate. Real `NSMenu` items keep native handling.

## Unreleased: Apple parent-anchored submenus and hidden subtrees

A Popover with `anchor` but no `anchor-target` or explicit rectangle now attaches
to its retained parent. For example, a menu item's Popover child with
`anchor: "right"` opens beside that item in a native presentation; its child
buttons receive their own press events instead of becoming inactive label
content inside the parent button. Existing explicit targets and rectangles keep
their behavior. Presentation sides select SwiftUI's attachment edge: `right`
uses its trailing edge, and `below` uses its bottom edge. Popovers without
positioning props retain inline rendering.

On macOS, native popup arrows now target the trigger's cross-axis center.
AppKit controls body placement and screen-edge collision handling; its public
popover API cannot independently align the body and arrow. `start`/`end` no
longer pre-shift the attachment by the content size, which displaced the arrow
from its trigger. For example, `anchor: "below", anchor-alignment: "end"`
keeps its arrow over the trigger; it does not promise a trailing-aligned body
for an interior trigger. `stretch` still sets the minimum trigger width and
`anchor-alignment-offset` still shifts the actual attachment by the requested
points. iOS retains its content-extent alignment behavior.

`display: "none"` now omits a node's native subtree from rendering, layout and
frame reporting while keeping its retained identity and properties. Restoring
the display property mounts the subtree from those properties. Hidden ancestors
also suppress descendant popovers. For example, a hidden drag-instruction Box
remains available in the retained tree without painting its text over a table.

## Unreleased: Apple semantic color variable fallbacks

Color props now resolve nested `var(--name, fallback)` references against the
inherited `luiSemanticColors` dictionary. Registering either `--ls-primary-text-color`
or `var(--ls-primary-text-color)` satisfies the fallback in
`var(--ls-caret-color, var(--ls-primary-text-color))`; hosts do not need to add
each complete expression to the dictionary. Exact expression overrides retain
precedence, followed by the named variable and then its fallback. Fallbacks may
use existing semantic names or supported hex colors. A missing variable without
a usable fallback remains unresolved, preserving the property's existing default.

## Unreleased: Apple absolute children in flow containers

Box, Row and Column children with `position: absolute` are now excluded from normal
flow sizing, grow detection and gap distribution. Their typed edge insets use
the sized parent surface as the containing block, including opposing-inset
stretching. Adding or removing an overlay preserves the normal children's
control identities. For example, ``column [text "Draft"; column ~position:`absolute
~inset:0. [caret]]`` keeps the text's intrinsic height instead of stacking the
caret overlay below it. Backgrounds, rounded clipping and committed text
rendering remain unchanged.

A Box's positioned resize handle also stays outside normal flow. For example,
a 32-point header button and a 32-point absolute handle share the header surface
instead of creating a 64-point stack that can clip the header text.

An omitted Row/Column `gap` now means zero, matching the canonical flow default.
Applications relying on SwiftUI's previous implicit spacing should set an
explicit value, for example `column ~gap:8 children`.

Wire `opacity` applies to the complete node surface, including its background,
border and absolute children. An opacity-zero caret keeps its geometry but
does not paint its background; applications should continue emitting their
normal opacity updates for blinking.

## Unreleased: Apple retained popover presentation and menu child content

Apple popovers with `anchor-target`, `anchor-rect`, or `at` now use native
popover presentation. For example, ``~anchor_target:"pages-more" ~anchor:`below
~anchor_alignment:`end_`` attaches to the retained node whose
`accessibility-identifier` is `pages-more`; it no longer occupies an inline
layout slot. Named targets can mount later and can be standard or extension
nodes. Explicit rectangles and `at` use window coordinates. Native attachment
edges, alignment offsets and spacing follow the existing anchor properties;
on macOS the arrow remains at the trigger center and AppKit determines body
placement as described above. The platform performs screen collision handling.
Popovers without positioning properties retain their inline behavior.

Native dismissal emits the existing `dismiss` event for the popover, so
applications should handle `~on_dismiss` by removing its retained subtree.
Updates to a dismissed retained identity do not reopen it. Removing and
recreating it presents a new identity, including when the numeric ID is reused;
late native callbacks cannot dismiss that replacement. Programmatic removal
does not synthesize another dismissal event.

Menu items render their retained child content when supplied (including rows
with Text and icons). Items without children use their own text, then their
accessible name. Existing menu-item press events keep the menu item's ID.

## Unreleased: Apple input focus, native sidebar synchronization and safe resync

Apple hosts can call `backend.requestFocus(nodeID:) -> Bool` for standard
`text-field`, `secure-field`, `input`, `search-field` and `textarea` controls.
True means the request was accepted, including before the control mounts;
false means the node is unknown, disabled or not one of those controls.
The latest request wins and is consumed once through the existing SwiftUI
focus binding. Requests belong to the retained node identity: dropping and
recreating the same numeric ID never transfers an old request. For example:

```swift
guard backend.requestFocus(nodeID: inputID) else {
    throw HostError.invalidFocusTarget(inputID)
}
// When routing a later key event, identify the focused standard text input.
let targetID = backend.focusedNodeID
```

`focusedNodeID` is read-only and reports the focused standard text input, or
nil when none is focused. Extension controls keep their host-owned focus
registries. Existing autofocus, draft composition and wire events are
unchanged; hosts do not need to rewrite retained properties to repeat a focus
request. Replacing a retained input identity remounts its control, so a reused
numeric ID cannot carry the previous node's native draft or focus binding.
Focus requests materialize pending coalesced model commits before classifying
the target; a newly accepted retained input is focusable before its view mounts.

On macOS, a native sidebar nested directly in a manual split now reconciles
retained fraction changes with the parent's target pane proposal, including
during animation. Closing an outer right pane no longer caches a sidebar
width calculated from the previous, narrower parent. Ordinary window-only
resizing still preserves the native sidebar's width in points.

`applySnapshot(json:)` validates the replacement against a fresh retained tree
before clearing or publishing anything. A rejected snapshot throws and leaves
the existing tree, pending commits, generation and mounted identities intact;
the same generation can be retried with a valid authoritative snapshot.
Accepted snapshots keep their existing replacement semantics. Incremental
`apply` failure generation handling is unchanged.

Apple menu items now accept a nonempty `accessibility-label` without an own
`text` property, matching canonical admission. Native menu titles fall back
to their accessible content label when own text is absent. Existing text and
named-child forms remain supported; unnamed menu items still fail validation.
Committed TextKit foreground colors are resolved in the actual SwiftUI
environment before conversion to native colors, preserving semantic colors
across light and dark appearance.

## Unreleased: Apple typography variables, inline text and absolute stack children

Apple hosts can supply their current theme snapshot with the additive
`View.luiStyleVariables([String: String])` modifier or the matching
`EnvironmentValues.luiStyleVariables` key. For example:

```swift
LUISwiftUIRoot(backend: backend, rootID: rootID)
    .luiStyleVariables(["--ls-page-title-size": "36px", "--ls-page-text-size": "16px"])
```

The existing `font-size`, `font-family` and `line-height` properties now resolve
`var(...)` chains and nested fallbacks against this environment. For example,
`font-size: var(--ls-page-title-size, 32px)` uses the supplied 36-point title
size, or 32 points when the variable is missing. Custom property names are
case-sensitive. Missing or cyclic references use the referring fallback;
otherwise that typography facet leaves the inherited value unchanged. Literal
typography keeps its existing parsing and inheritance. Supported length units
are unchanged; this does not add CSS calculations or a stylesheet engine.
Updating the environment re-resolves references, including in committed
TextKit rendering. Raw retained properties stay unchanged, and the variable
environment is carried into sheet and custom-dialog presentation.

Nested `text` children now draw as inline runs in a shared native TextKit
layout instead of disappearing when the parent has no own `text` value. Each
run inherits typography and can override it with its own typed properties.
Wrapping and insertion positions come from the same layout that draws the
whole line. `textGeometry(nodeID:)` also works for those child runs and zero-width
U+200B pads: returned ranges and offsets are local to that child's UTF-16 text,
and its frame encloses its laid-out fragments in window-content coordinates.
Frame reporting includes these inline descendants. Snapshots still expire on
patches, layout changes, scrolling and unmounting; queried leaf text keeps its
existing API and presentation. For example, hosts can query each child of
`text [text "Hello"; text "\u{200B}"]` without inventing caret metrics or
turning inline runs into separate horizontal stacks.

The inline renderer handles Text descendants, including Text inside transparent
`display: contents` wrappers. Place icons and controls in sibling layout
containers; other non-Text inline children remain unsupported.

Apple `stack`, `panel` and `card` children with `position: absolute` now honor
their numeric `inset`, `inset-top`, `inset-right`, `inset-bottom` and `inset-left`
properties. For example, a 32-by-32 help button with `inset-right: 32` and
`inset-bottom: 45` stays that distance from its containing stack's right and
bottom edges as it resizes. Left/right remain physical edges in RTL layouts.
Opposing insets stretch an automatic dimension; explicit width/height keep
their existing constraints. Positioned children do not contribute to intrinsic
stack size; finite parent proposals define the containing block. Stacks without
absolute children keep their existing layout. Other positioning modes retain
their existing fallback behavior; hosts do not need to rewrite this wire data.

## Unreleased: Apple growing layout, collapsed splits and custom dialogs

Growing children in Apple rows now receive remaining width before flexible
containers with `grow: 0` (including the default when grow is absent). Empty
rows, slot boxes and closed columns no longer divide the main content width.
For example, `row [scroll ~grow:1. content; column [spacer ()]]` gives the scroll
the available width rather than half of it. Nested growing title content also
fills the space beside empty action/tag rows. Intrinsic single-line content
keeps its higher priority, growing siblings keep equal priority, and existing
explicit sizes and maximum widths still constrain layout. Hosts can keep their
typed grow and max-width properties; no extra host widths are needed.
Scroll content now takes its cross-axis minimum from the current viewport
proposal, so shrinking a window also shrinks a vertical scroll's content width
(or a horizontal scroll's content height) instead of retaining the old minimum.

Apple now admits `dialog` nodes without a `text` property, matching the canonical
OCaml protocol. A dialog may supply its heading and body through its retained
children. Previously, Apple rejected these batches with
`invalidBatch("modal surface requires text")` before the custom content could
mount. Existing native alert/action-sheet dialogs and titled sheets keep their
presentation and dismissal behavior; `sheet` still requires a nonempty `text`
property under the canonical contract.

For example, `dialog [column [heading "Create graph"; input (); button "Create"]]`
may omit the dialog's own title. Apple presents the existing custom SwiftUI
surface for this subtree, preserving its retained root and modal ownership.
Hosts do not need to inject a title into the wire batch or replace the modal
renderer.

Apple manual splits now omit the divider, focus target and resize interactions
when either pane has zero rendered width or `resize-handle-width` is zero.
For example, a right dock using `value: 1.0` and `gap: 0` no longer leaves a
focusable vertical line after the trailing pane closes. Expanded panes keep the
existing resize and accessibility behavior; reopening a dock uses the model's
existing split width/value update.

## Unreleased: desktop backend removal (breaking)

The native Go desktop backend, its Go module, host commands, capabilities,
generated contract manifest, exporters, build/test scripts and CI workflow have
been removed. There is no compatibility backend or alias.

Downstream hosts must use `platform/apple` for macOS/iOS SwiftUI,
`platform/android` for Android, or `platform/web` for Web/Melange.
Logseq keeps Electron for Windows/Linux desktop builds; LUI does not provide a
native Windows/Linux desktop backend.

The removed OCaml host constructor is no longer part of `host_kind` in
`Lui_protocol` or `Lui_elements`. Remove its match arms and select
`SwiftUIHost`, `KotlinHost` or `WebHost` for the actual host. Native host code
`5` is retired: it resolves to `GenericHost` and grants no bounded-row
capability. Rebuild downstream OCaml code; serialized OCaml values containing
the removed constructor are not compatible. Maintained host codes remain
`1` (Web), `2`/`258` (SwiftUI) and `4`/`260` (Kotlin).

For example, migrate a macOS host profile to:

```ocaml
let backend = {
  Lui_protocol.backend_profile =
    Lui_protocol.profile Lui_protocol.MacOS Lui_protocol.SwiftUIHost;
  apply_batch;
}
```

Build the Apple backend through the root Swift package:

```sh
swift build
# Shared OCaml gallery library for the maintained Apple host:
opam exec --switch=5.5.0 -- dune build examples/components/native/liblui_components.dylib
LUI_COMPONENTS_NATIVE_LINK_INPUTS="$PWD/_build/default/examples/components/native/liblui_components.dylib" \
  swift build --package-path examples/components/ios-swiftui --product LUIComponentsApp
```

Keep `platform/bridge`, `platform/services`, existing reducers and views, and
the mobile build tooling. Maintained host wire contracts, schemas and extension
fingerprints are unchanged. `shrink` and `on_focus_within` remain Web-only;
SwiftUI/Kotlin/Generic profiles continue to reject those opt-ins. Run
`make generate-component-schema` to regenerate the remaining shared, Apple and
Android schema artifacts; no desktop Go contract is generated.

## Unreleased: Apple desktop host resources, committed text and schema admission

`LUIAppleBackend` adds these main-actor APIs on macOS 14 and iOS 17:

```swift
func registerIcon(name: String, svg: Data) throws
func unregisterIcon(name: String)
func naturalImageSize(nodeID: Int) -> CGSize?
func textGeometry(nodeID: Int) -> LUICommittedTextGeometry?
func isCurrent(_ geometry: LUICommittedTextGeometry) -> Bool
func setScrollTop(nodeID: Int, top: CGFloat) -> Bool
func scrollIntoView(nodeID: Int) -> Bool
func scrollMetrics(nodeID: Int) -> (offset: CGFloat, contentSize: CGSize, viewportSize: CGSize)?
```

Register a complete SVG under a canonical `app:slug` name, for example
`try backend.registerIcon(name: "app:graph", svg: Data(contentsOf: iconURL))`.
Registration replaces the previous icon and invalidates mounted uses; a failed
validation leaves the previous registration intact. Unregistering an unknown
name is harmless. SVG data must describe a finite positive intrinsic size and
fit within 1 MiB. Both Swift packages pin SwiftDraw 0.24.0. Existing initial
icon sources and the public `LUIAppleIconSource` enum are unchanged.

`naturalImageSize` returns decoded source pixel dimensions before layout
scaling, thumbnail downsampling or source cropping, or nil until decoding
completes. It supports image, avatar and file-image nodes. Registered images
keep precedence over URL images. Changing the source or reusing a node ID
cannot return an earlier source's dimensions.

`LUICommittedTextGeometry` contains `nodeID: Int`, `generation: Int64`,
`incarnation: UInt64`, `text: String`, `frame: CGRect`, and
`lineRanges: [NSRange]`. The frame uses window-content, top-left-origin logical
points. `caretRect(atUTF16Offset:)`, `selectionRects(in:)` and `offset(at:)`
use text-local logical points and UTF-16 offsets. Display text, headings,
paragraphs and labels opt into native TextKit drawing when first queried, then
expose that same committed layout. Existing hosts that do not use this API keep
their original SwiftUI Text rendering on iPhone, iPad and Mac; editable controls
retain their existing native editing behavior.
Uncommitted, hidden and unmounted text returns nil. Retained snapshots remain
immutable; `isCurrent` rejects stale generations, source/layout changes,
scrolling, unmounting and node reincarnation.
Zero-width U+200B empty-block pads commit TextKit's actual line/caret metrics
during native layout even when drawing is culled; `caretRect(atUTF16Offset: 0)`
remains available without a synthetic font box.

Enable existing frame reports to retry pending resource/geometry queries:

```swift
backend.frameReportingEnabled = true
backend.onFramesReport = { [weak backend] _ in
    guard let backend, let geometry = backend.textGeometry(nodeID: blockID),
          backend.isCurrent(geometry) else { return }
    let caret = geometry.caretRect(atUTF16Offset: utf16Offset)
    // Add geometry.frame.origin to translate caret into window coordinates.
    _ = caret
}
```

Hosts storing UTF-8 byte offsets must translate them through their source run
spans before calling these native UTF-16 APIs. Search-match previews expose the
displayed excerpt as `geometry.text`.

The scroll controls bind to mounted native views without replacing the
ScrollView, its delegates or gestures. `setScrollTop` accepts a retained `scroll`
node and clamps a top-origin logical-point offset to its content range.
`scrollIntoView` reveals any mounted standard node in its nearest enclosing
native scroll viewport; it also returns true when already visible. For a
`scroll` node itself, this reveals its viewport in an enclosing scroll.
The methods return false for an unavailable target/viewport; missing IDs,
non-scroll `setScrollTop` targets and nonfinite offsets are flagged by false.
No exceptions or deferred commands are produced. `scrollMetrics` returns nil
for missing, non-scroll and unmounted nodes. Sizes are logical points; UIKit's
adjusted insets are excluded from the viewport and normalized out of offset.
Probes mount lazily on the first call, so even an already displayed node may
initially return false/nil. Retry using `onFramesReport`, guard pending requests
against node incarnation, and discard requests when their node is replaced.

```swift
backend.onFramesReport = { [weak backend] _ in
    guard let backend, let metrics = backend.scrollMetrics(nodeID: scrollID) else { return }
    if hasPendingScroll && backend.setScrollTop(nodeID: scrollID, top: requestedTop) {
        hasPendingScroll = false
    }
    updateScrollHeight(metrics.contentSize.height)
}
```

Vertical retained ScrollView content now fills at least its viewport width;
horizontal content fills at least the viewport height. Content can still exceed
that minimum. This fixes centered, growing columns collapsing to intrinsic text
width and applies consistently on macOS and iOS without changing scrolling axes.

Apple property admission now uses a matrix evaluated from canonical
`Lui_protocol.property_supported` and checked against the schema, instead of
limiting admission to rendered features. Schema-valid but unimplemented visual
hints are retained and may be ignored by rendering; they do not reject an
otherwise valid batch. Malformed values and graph invariants still fail
atomically. This admits, among others, button gap, icon opacity, shrink,
focus-within-enabled, zero-width resize handles and viewport anchor rectangles.
After changing canonical admission, run
`python3 tooling/generate_apple_admission.py --export`, followed by
`node tooling/generate_component_schema.mjs`; `--check` detects stale exports.

Split accepts exactly one sizing mode: `value` is a fraction, while
`first-pane-width` is an absolute logical-point width (including zero).
For example, replace a rejected `first-pane-width: 246` batch directly without
adding a synthetic `value`; do not send both properties. Absolute width stays
fixed as its container resizes, honors pane minimum widths, and emits
`value-changed` in logical points. Fractional mode emits fractions. Resize
origin uses the selected mode's units. The macOS fractional path without custom
handle properties continues to use `NavigationSplitView`; custom handles and
absolute sizing use the existing manual split path.

## Unreleased: native navigation sheet action foregrounds

Apple navigation sheet toolbar actions honor the button's existing `foreground`
property. For example, set `button ~style_class:"confirmation-action"
~foreground:"foreground" ~text:"Done" []` to use the current semantic foreground
for the title. The native toolbar placement, styling and disabled behavior stay
in effect. With no resolvable explicit foreground, the system default remains.
No wire-format or handler changes are required.

## Unreleased: shared iOS input surface

Standalone iOS text, secure, search, and combo box inputs use a padded field
with a semantic fill and a visible focus outline. Grouped text controls, native
form rows, multiline editors, and other backends keep their existing rendering.
The wire schema, edit events, and focus behavior are unchanged.

The fill resolves `input`, `surface`, then `muted` before the system fallback.
The focus outline resolves `input-focus`, then `primary` before the system
accent. Native SwiftUI extensions can use the same surface without changing
their own keyboard or submission configuration:

```swift
TextField("Email address", text: $email)
    .keyboardType(.emailAddress)
    .focused($focused)
    .luiInputSurface(isFocused: focused)
```

## Unreleased: one lui-agent protocol on every host

Scripts and coding agents can now drive a running app the same way on
Apple, Android and Web. The shared OCaml runtime answers every request, so
each host only carries strings.

A request is one flat JSON object with an `op`. The reply is one JSON object
with `ok`:

```json
{"op":"press","selector":"prop:accessibility-identifier=save"}
{"ok":true,"op":"press","node":42}
```

The protocol has these parts:

- **Ops.** `hello`, `tree`, `dump`, `find`, `prop`, `press`, `long-press`,
  `double-press`, `submit`, `dismiss`, `appear`, `change`, `type`, `toggle`,
  `value`, `key` and `ext`. `hello` reports `protocol` (`"lui-agent"`),
  `version` (`1`), `host`, `generation` and `ops`.
- **Selectors.** They use the Drive scenario grammar: `id:N`, `kind:name`,
  `ext:identifier`, `text:needle`, `prop:name=value` and `prop:name=prefix*`,
  joined with `&`. A bare number is an id and a bare word is a text needle.
- **Gestures.** `press`, `long-press` and `double-press` go to the nearest
  ancestor that handles them. Every other action requires the selected node
  itself to handle the event.
- **Rejected requests.** A malformed request, unknown op, missing node or
  unsupported event gets `{"ok":false,"error":...}` and changes nothing.
- **Refused requests.** If an application handler raises, the call is refused
  in phase `agent`, the same way a refused native event is. Hosts answer
  `{"ok":false,"refused":true,"error":...,"diagnostic":{...}}`.
- **Patches.** An action's patch batches reach the host's normal patch path
  before the reply.
- **Clock.** An action may arm or cancel application-clock timers, so every
  native host re-reads the clock's next delay after each agent request, as it
  does after an event.

The new APIs, by layer:

- **OCaml.** `Lui_agent.handle`, `Lui_agent.app_target` and `Lui_agent.target`.
  `Lui_native_bridge.agent bridge request` answers through a started bridge,
  and `register` adds `<prefix>_agent` (for example `lui_kotlin_agent`).
- **C ABI.** Two new exports:

  ```c
  int32_t lui_ocaml_agent_utf8(const char *request, int32_t length,
                               void (*reply)(const char *json));
  int32_t lui_ocaml_agent(const char *request, void (*reply)(const char *json));
  ```

  Both return `1` when answered, including `{"ok":false}` replies. They return
  `0` when refused; in that case read `lui_ocaml_last_error` and resync as
  after any refused call. The batches go to the patch callback given to
  `lui_ocaml_start`, then `reply` receives the reply object.
- **Android.**
  - `LuiBridge.agent(request): String` blocks until the OCaml thread answers
    and queues the batches for the sink.
  - The JNI library exports `nativeAgent`.
  - `LuiAgentServer.start(port, answer)` serves the same line protocol on loopback. `answer` defaults to `LuiBridge.agent`.
  - The Components app starts it only in debug builds launched with
    `--ei lui-agent-port PORT`. The debug manifest adds `INTERNET`.
    Reach it with `adb forward tcp:PORT tcp:PORT`.

  ```kotlin
  val server = LuiAgentServer.start(port = 49380)  // after LuiBridge.start
  ```

- **Apple.**
  - `LUINativeAgent(library:recovery:)` (or `init(agent:recovery:)` with an
    `@_silgen_name` closure) answers requests and recovers refusals.
  - `LUIAgentServer.startFromEnvironment(answer:)` serves loopback TCP on the
    main queue when `LUI_AGENT_LISTEN` is set.
  - `LUINativeRefusalRecovery.recover(_:)` is `check(_:)` returning the
    failure.
  - The Todos, Split, Markdown, Components and Navigation hosts start the
    server in DEBUG builds. On the simulator, pass
    `SIMCTL_CHILD_LUI_AGENT_LISTEN=127.0.0.1:PORT` to `simctl launch`.

  ```swift
  let agent = LUINativeAgent(library: handle, recovery: recovery)
  agentServer = try LUIAgentServer.startFromEnvironment { agent.answer($0) }
  ```

- **Web.**
  - `Lui_web_agent.install target` sets `window.__luiAgent`.
  - When the page URL carries `?lui-agent=ws://127.0.0.1:PORT` (or
    `ws://localhost:PORT`), it dials that socket and answers each text frame.
    Other hosts are ignored.
  - A raising handler is answered as a refusal rather than thrown.
  - The Components and Chat pages install it.

  ```ocaml
  Lui_web_agent.install (Lui_agent.app_target ~host:"web" app)
  ```

### Refusing to drive a stale build

`tooling/lui_agent.mjs` is the client for every host. It accepts
`--tcp HOST:PORT` or `--ws-listen PORT`, and runs Drive-vocabulary script lines
(`press`, `type`, `toggle`, `expect`, `wait`, `expect-prop`, `dump`, …),
reporting every failing line.

The build scripts now write `<artifact>.lui-build.json`. It holds the
artifact digest and the sha256 of every input file. The scripts that write it
are:

- the Android and iOS Components builds;
- the Navigation simulator build;
- the macOS `build-app.sh` scripts;
- `build_web_release.mjs`.

`--artifact PATH` refuses to drive a build whose receipt is missing, or whose
artifact or inputs changed. It names the command that rebuilds it and exits
with code `3`. `--unchecked` skips the check. `node tooling/lui_build_receipt.mjs
check --artifact PATH` runs the check alone.

```sh
OPAMSWITCH=5.5.0 bash examples/todos/macos-appkit/build-app.sh
LUI_AGENT_LISTEN=127.0.0.1:49380 examples/todos/macos-appkit/.build/debug/LUITodos.app/Contents/MacOS/LUITodos &
node tooling/lui_agent.mjs --tcp 127.0.0.1:49380 --artifact examples/todos/macos-appkit/.build/debug/LUITodos.app \
  'hello' 'tree'
```

### Compatibility

Every server is opt-in and listens on loopback only, so apps that do not set
`LUI_AGENT_LISTEN`, pass the Android extra or call `install` behave as before.

The wire format, events and existing exports are unchanged. Hosts that load
the library with `dlopen` resolve `lui_ocaml_agent_utf8` optionally; a
`LUINativeAgent` without it answers every request with an error.

## Unreleased: wire batches skip unknown nested fields

`Lui_wire.decode_batch` still rejects malformed tokens, unknown operations,
unknown node kinds, and unknown properties. Extra object fields — on the
batch or on an operation — are now ignored when their names are not part of
the operation schema, including nested objects, arrays, and null. Previously
only extra scalars were skipped, so a newer encoder's object field failed
the OCaml decoder.

Canonical encoder bytes are unchanged. Required fields stay scalars:
`"value": {"nested": true}` is still rejected. Duplicate keys are unchanged
(the first operation field wins; the last `generation` wins). Hosts should not
emit duplicate keys; the shared fixtures use unique keys.

```ocaml
let batch =
  Lui_wire.decode_batch
    {|{"schemaVersion":1,"meta":{"nested":[1]},"generation":1,"ops":[{"op":"drop-node","id":1,"trace":{"ok":true}}]}|}
(* generation = 1, ops = [DropNode 1] *)
```

## Unreleased: controllable application clock

Views schedule time-based work with `Lui_ui.after context ms action` and
`Lui_ui.every context ms action`. Both return a `Lui_clock.timer`, run on the
application's `Lui_clock.t` (`Lui_app.clock app`) and are cancelled when the
owning view scope is disposed; `Lui_clock.cancel` stops one earlier. Actions run
on the runtime thread like event handlers, so they may `send` directly:

```ocaml
let upload_button send : t =
  scoped (fun context ->
    let timer = ref None in
    button ~text:"Simulate upload"
      ~on_press:(fun _ ->
        Option.iter Lui_clock.cancel !timer;
        timer := Some (Lui_ui.every context 300. (fun () ->
          ignore (send Advance))))
      [])
```

Replace host-side `setTimeout`/`DispatchQueue`/`Handler` loops that only feed
actions back into the model with these timers: they become deterministic under
Drive and tests. Existing apps need no changes; a clock without timers costs
nothing and never wakes a host.

Time is in milliseconds (float). Host time only moves forward; the first
`Lui_clock.tick` anchors the clock without firing anything. `Lui_clock.pause`
makes host ticks no-ops, `Lui_clock.advance clock ms` moves simulated time and
fires due timers even while paused, and `Lui_clock.settle` fires every pending
timer (raising after 10,000 firings to stop runaway `every` loops). Time cannot
move from inside a timer action (`Invalid_argument`).

Host contract, implemented by every maintained host in this release:

- Native C ABI: new exports `lui_ocaml_clock_tick(double now_ms)`,
  `lui_ocaml_clock_advance(double ms)`, `lui_ocaml_clock_set_paused(int32_t)`
  and `double lui_ocaml_clock_next_delay(void)` (negative when nothing is due,
  paused or not started). After every call into the runtime the host reads
  `next_delay`, arms one wakeup and calls `clock_tick` with monotonic
  milliseconds when it fires. Bridges built with `Lui_native_bridge.register`
  get the OCaml side automatically.
- Android: `LuiBridge` reschedules a `Handler.postAtTime` wakeup on the
  `lui-ocaml` thread after every dispatch, ticking with
  `SystemClock.uptimeMillis()`. New JNI exports `nativeClockTick`,
  `nativeClockAdvance`, `nativeClockSetPaused`, `nativeClockNextDelay` and
  public `LuiBridge.advanceClock(ms)` / `LuiBridge.setClockPaused(paused)`.
  Custom JNI libraries must compile the updated `lui_jni_bridge.c`.
- Apple: new `LUIRuntimeClock` in `LUIAppleBackend`. Create it with
  `LUIRuntimeClock(library: handle)` for `dlopen` hosts or
  `LUIRuntimeClock(tick:nextDelay:)` with `@_silgen_name` functions, call
  `reschedule()` after starting the runtime and after every runtime call
  (typically `defer { clock.reschedule() }` at the top of `backend.onEvent`),
  and `cancel()` before `lui_ocaml_stop`:

  ```swift
  let clock = LUIRuntimeClock(library: handle)
  backend.onEvent = { event in
      defer { clock.reschedule() }
      // existing dispatch
  }
  ```

- Web/Melange: call `Lui_web.drive_clock app` once after `Lui_app.start`. It
  ticks from `performance.now()` with one armed timeout and flushes after each
  tick, using the new `Lui_clock.set_wakeup` hook.
- A timer action that raises is a refused call with phase `clock`: every
  native host routes tick results through its existing refusal recovery
  (diagnostic plus resync), exactly as for a refused event.
- In-process apps (tests, custom hosts) call `Lui_app.tick_clock app ~now` or
  `Lui_app.advance_clock app ms`, then `Lui_app.flush`, or register a
  `Lui_clock.set_wakeup` callback.

Drive scenarios gain `clock pause`, `clock resume`, `clock advance <duration>`
(`250`, `250ms`, `1.5s`) and `clock settle`. In-process sessions support all
four; FFI targets support all but `settle` and report the missing exports for
libraries built before this release; live websocket targets report the
command as unsupported.

## Unreleased: native bridge reports refused calls

When OCaml raises while a native bridge boots, dispatches an event, resyncs or
disposes, the C entry still returns `0` and delivers no batch. The bridge now
also records a diagnostic, and the new export returns it:

```c
int32_t lui_ocaml_last_error(void (*receiver)(const char *json));
```

It hands `receiver` one JSON object, clears it, and returns `1`; it returns `0`
when no diagnostic is pending. A later accepted call also clears it.

```json
{"bridge":"Todos","phase":"dispatch","node":42,
 "message":"invalid property value ...","recovery":"resync"}
```

`phase` is `boot`, `dispatch`, `resync` or `dispose`; `node` is present for a
dispatch. Batches recorded before the exception are discarded, so the host
mirror is stale: report the message, then call `lui_ocaml_resync` and apply its
snapshot rather than keep rendering what mounted before the throw. The bridge
still prints the exception to stderr.

The wire format, existing exports and return codes are unchanged. A host that
does not adopt the export keeps its old behavior. Resolve the symbol
optionally to stay compatible with older libraries. A `0` without a pending
diagnostic is argument validation in C, which records no patches and needs no
resync. OCaml callers can read the same record with
`Lui_native_bridge.last_failure` and `take_failure`. Bridges registered with
`Lui_native_bridge.register` gain `<prefix>_last_error` automatically, so
`lui_kotlin_last_error` exists for JNI.

Every maintained host now consumes it:

- **Android**: `LuiBridge` logs the failure, requests a snapshot through the
  existing resync path and notifies the optional `LuiBridge.failureListener` on
  the main thread with a `LuiRuntimeFailure`. A failed `start` reports its
  diagnostic the same way. The JNI library exports `nativeLastError()`.

  ```kotlin
  LuiBridge.failureListener = LuiBridge.FailureListener { failure ->
      showError("${failure.phase} failed: ${failure.message}")
  }
  ```

- **Apple**: `LUIAppleBackend.applySnapshot(json:)` replaces the retained tree
  with a `lui_ocaml_resync` batch. `apply(json:)` drops that batch as stale
  because it reuses the current generation. `LUINativeRefusalRecovery` wraps the
  two exports for hosts that load the C ABI themselves, and the Todos, Split,
  Markdown, Components and Navigation hosts use it. Hosts that resync outside
  this helper must use `applySnapshot` as well.

  ```swift
  let recovery = LUINativeRefusalRecovery(library: handle)  // or closures over @_silgen_name exports
  recovery.check(pressFunction(Int64(node)))

  func apply(json: String) throws {
      if recovery.isReceivingSnapshot {
          try backend.applySnapshot(json: json)
      } else {
          try backend.apply(json: json)
      }
  }
  ```

- **Drive**: the FFI driver fails the scenario line with the diagnostic, for
  example `target refused dispatch at node #1: …`, and rebuilds its model from
  a resync snapshot. `Drive.Model.clear` empties a model before a snapshot.

- **Web/Melange** runs OCaml in-process and has no C boundary. Exceptions
  still surface as uncaught JavaScript errors and no patches are dropped, so
  nothing changes there.

## Unreleased: independent flex shrink on Web

`row`, `column` and `box` accept `?shrink:float`. The typed `ShrinkValue`
property uses wire name `shrink` and accepts only finite, nonnegative floats.
Only these three standard kinds admit it. Web maps it to CSS `flex-shrink`.
Generic, SwiftUI and Kotlin profiles reject explicit shrink values; Apple and
Android also reject direct standard wire patches rather than ignoring them.
Extensions/raw markup do not gain a shrink property or escape hatch.

Omitting or removing shrink preserves/restores the existing default factor 1.
Setting or removing it does not change `grow` or flex basis. Existing callers
need no changes. New callers must use a host supporting this property and a
LUI version that knows the new wire name; older hosts reject that opt-in.

For a bounded, clipped single-line strip, opt in on each direct pill container:

```ocaml
row ~flex_wrap:`nowrap
  [row ~shrink:0. [text ~value:"First" []];
   row ~shrink:0. [text ~value:"Second" []]]
```

Use the existing typed overflow property on the strip for clipping. Shrink on
the strip itself does not disable shrinking its children. Remove unnecessary
child `grow` props to keep intrinsic sizing; do not substitute `grow:0` for
`shrink:0`.

## Unreleased: opt-in container focus-within observation (Web)

`row`, `column` and `box` accept `?on_focus_within:(bool -> unit)` on
Web/Melange. Installing the callback enables the new boolean
`focus-within-enabled` property and receives `FocusWithinChanged (node, within)`.
Without the callback/property, observation is off and existing views are unchanged.
The callback does not make the container focusable or change keyboard traversal.

After mount/enable settles, the observer publishes one current snapshot, then
only distinct transitions. True means focus is on the container or inside its
rendered subtree. Moving between descendants does not emit an exit/reentry pair.
Web coalesces local `focusin`/`focusout` checks at the microtask boundary, also
checking after retained child removal. Web does not treat a popup/portal outside
the subtree as inside merely because it is attached to a trigger.
Window activation is not a second condition
on retained focus membership; this is not an application-activation callback.

Web can observe focus within transparent boxes through their retained DOM subtree.

Disabled/inert ancestors normalize membership to false, including a terminal
false for a previously focused subtree. Re-enabling observes current membership
again. The last value is recorded before dispatch, so reducer patches do not
cause repeated feedback. Same-node reconciliation retains the observation;
opt-out or node retirement discards it. A new incarnation receives a fresh
snapshot. Unmount cancels delayed checks without dispatching to a dead node.

SwiftUI, Kotlin and Generic host profiles explicitly reject this property,
including explicit false; Apple and Android raw-wire hosts reject it too.
Cross-platform applications must omit the callback on those paths, not expect
silent no-event support. No Apple/Android focus framework or focusable group is
introduced. Their existing focus behavior and appearance properties are unchanged.
Rebuild the shared OCaml application and Web host together for the added
event constructor and native `lui_ocaml_focus_within_changed` bool callback.
Older native libraries remain usable without this opt-in; attempting to deliver
the new event to a library without its callback fails explicitly.

For example, replace per-control focus handlers with one row-owned signal:

```ocaml
row ~on_focus_within:(fun within -> Signal.set toolbar_focused within)
  [comment_body; reactions; toolbar]
```

Combine that signal with the existing hover state to drive typed toolbar opacity.
No new focus-within opacity property or data migration is needed.

## Unreleased: Android editable Combobox menu focus

Android suggestion menus anchored beside a `combobox` retain keyboard focus in
the input while the menu is open, so edits continue to emit text changes and
filter the shared model-owned options. The native Material popup no longer
takes input focus from an editable anchor, and the anchor stays mounted when
its menu appears or disappears. Other dropdown and context menus keep their
existing focus and dismissal behavior.

Existing `stack [combobox ...; dropdown_menu ...]` integrations need no API or
wire changes; keep the query and filtered options in the shared model rather
than manually refocusing or remounting the input after each edit. Apple and Web
behavior is unchanged.

## Unreleased: Android growing content and Gallery navigation

Android columns apply `grow` only when their vertical extent is bounded.
Inside a vertical scroll viewport, growing children retain their authored
height or intrinsic content height instead of collapsing and overlapping
following controls. Bounded columns still distribute remaining height;
applications do not need to remove `grow` from scroll-contained textareas.
Android dialogs also render the existing `description` property above their
retained body. Neither correction changes the wire format or event ABI.

The native Android component Gallery now derives a Material navigation drawer
from the retained page roots and renders one selected page at a time. Shared
OCaml model state remains authoritative across page switches; navigation is
host-only and introduces no public LUI component. Its mobile E2E runner uses
the checked-in `platform/android/gradlew` wrapper.

## Unreleased: preserve Apple and Android backends

Apple/iOS and Android remain maintained backends alongside macOS SwiftUI and
Web/Melange. Their backend sources, packages, example hosts, mobile tooling,
Drive probes and CI jobs are restored after their unintended removal.

Downstream applications such as `logseq/mobile` and `logseq/logseq_journal`
must keep their native backend dependencies:

- SwiftPM consumers retain the `LUIAppleBackend` or `LUIAppleBackendStatic`
  product from the root package or `platform/apple` package. For example,
  Journal can continue using `JOURNAL_LUI_PACKAGE_PATH=../lui/platform/apple`.
- Android consumers retain the `platform/android/lui` Gradle module and its
  JNI bridge. The optional `platform/android/drive` instrumentation module
  remains debug-only.
- Schema generation emits `LUIWireSchema.swift` and `LuiWireSchema.kt` as
  well as the shared OCaml/PPX artifacts. Regenerate all of them from the
  current schema, including the modal transition declarations below.
- Mobile build/test scripts, Maestro flows, Apple/Android CI and
  `make test-apple` remain supported. See the
  [component gallery guide](../examples/components/README.md) for commands.

Restoration does not rename public APIs, change host defaults or event
semantics, or change wire batches and capability negotiation. Keep existing
SwiftUI/Kotlin host integrations. The separate desktop migration still relocates
the shared C bridge to `platform/bridge`
as described below; it does not restore the retired SDL renderer.

## Unreleased: modal surface transitions

`dialog`, `drawer`, and `sheet` now accept `~transition:string`, like
`popover`. The wire `Transition` property is admitted on these modal kinds;
`Root` and `Tooltip` remain excluded, and transition values retain the same
validated CSS shorthand grammar.

Pass the transition to the surface constructor rather than a post-mount
property bind or a child container:

```ocaml
dialog ~transition:"opacity 200ms ease-out, transform 200ms ease-out"
  [text ~value:"Content" []]
```

Web applies this declaration to the real retained modal surface, preserving
its opening/closing animation, focus restoration, and exit-paint lifecycle.
Omitted transitions keep the existing host defaults.

## Unreleased: retired SDL renderer and portable host services

The former
`platform/native` OCaml/SDL renderer, its executables, packaging tools,
renderer-specific plugins and native test jobs are removed, not deprecated.
There are no compatibility aliases or fallback renderer. Web/Melange and
the Apple/Android hosts remain supported; mobile backend retirement is not
part of this desktop migration.

The shared `lui_ocaml_*` C ABI moved byte-for-byte to
`platform/bridge/lui_ocaml_bridge.c` and
`platform/bridge/lui_caml_dispatch.h`. Symbols, event dispatch, ownership,
capability negotiation and wire batches are unchanged. Update source/header
dependencies and include paths in downstream build rules; keep application
bridge callbacks and `examples/*/native` libraries. These directories contain
shared OCaml applications, not the removed renderer. The GC runner is now
`opam exec -- sh platform/bridge/stress/run.sh`.

Exactly two former native libraries remain, under `platform/services`:

| Public library | Module | Dependencies and runtime |
| --- | --- | --- |
| `lui.plugin` | `Lui_plugin` | OCaml standard library (`Mutex`); unchanged registry API |
| `lui.plugin_fetch` | `Lui_plugin_fetch` | `yojson` and `lui_plugin`; runtime libcurl on macOS/Linux and libdl on Linux |

Their public names and modules are unchanged; no SDL or renderer dependency
is required. Fetch keeps its existing unsupported-platform error outside
macOS/Linux; this move does not add Windows HTTP transport.

Every other public library formerly supplied by `platform/native` is removed:

- Renderer/layout/resources: `lui.backend`, `lui.blit`, `lui.d3d11`,
  `lui.flex`, `lui.gl`, `lui.gpu`, `lui.host`, `lui.image`, `lui.layout`,
  `lui.media`, `lui.metal`, `lui.paint`, `lui.retained`, `lui.raster`,
  `lui.resource`, `lui.resource_loaders`, `lui.scene`, `lui.spatial`,
  `lui.store`, `lui.svg`, `lui.text`, `lui.text_dwrite`, `lui.text_pango`,
  `lui.theme`, `lui.vulkan`.
- Input/platform services: `lui.a11y`, `lui.ax`, `lui.ax_linux`,
  `lui.ax_windows`, `lui.gamepad`, `lui.ime`, `lui.input`, `lui.resilience`,
  `lui.shell`, `lui.shell_linux`, `lui.shell_windows`, `lui.updater`,
  `lui.webapp`, `lui.webview`, `lui.window`, `lui.window_linux`,
  `lui.window_windows`.
- Tools/plugins: `lui.cli`, `lui.e2e`, `lui.e2e_json`, `lui.ed25519`,
  `lui.pkg`, `lui.pkg_linux`, `lui.pkg_webapp`, `lui.pkg_windows`,
  `lui.plugin_gamepad`, `lui.plugin_glass`, `lui.plugin_sqlite`,
  `lui.plugin_terminal`, `lui.plugin_updater_ui`, `lui.plugin_websocket`,
  `lui.plugin_webview`, and the `lui_pkg` executable.

The shared `lui` runtime/element API remains. Keep reducers, signals and views
in OCaml and embed the shared application library with `platform/apple` on
macOS/iOS, `platform/android` on Android, or `platform/web` for Web output.
Replace renderer-specific Dune libraries with `lui` and only the portable
services actually used. Replace custom
`../../../platform/native/lui_ocaml_bridge.c` and adjacent header dependencies
with `../../../platform/bridge/...` at the same relative depth.

The old `examples/components/webview-shell` depended on removed `lui.webapp`
and `lui.webview` and is deleted; use the Apple Components host or the existing
Web build described in [the Component gallery guide](../examples/components/README.md).

Historical entries below describing the removed renderer record previous
releases; they do not promise those APIs remain available. Build and schema
checks do not establish visual parity or native interaction acceptance.

## Unreleased: Apple minimum scroll viewport reference

Apple hosts may set the optional `EnvironmentValues.luiMinimumScrollViewport`
to a scene-global `CGRect` measured outside navigation keyboard avoidance and
editor safe-area insets. Windowed `virtual-list` first-section minimum heights
use the reference's bottom edge minus the scroll view's top edge, rather than
the already-reduced local viewport. Actual scrolling and visible-range tracking
are unchanged. With the default `nil`, existing local viewport measurement is
preserved; no wire-format change is required.

For example, measure a `NavigationStack` background using
`GeometryReader` with `.ignoresSafeArea(.all, edges: .bottom)`, then pass
`.environment(\.luiMinimumScrollViewport, measuredFrame)` to the stack.
The background reports `proxy.frame(in: .global)` without changing keyboard
avoidance on the interactive content. Update the frame on geometry changes so
rotation and split-view resizing still change the minimum height normally.

## Unreleased: Apple virtual-list first-section height retention

The legacy windowed `virtual-list` keeps `data-first-section-count` and
`data-first-section-inset` as a minimum viewport height for its first section.
The remaining space now belongs to the last real row instead of a synthetic
lazy-list slot. Scrolling, pinned editing and scroll requests therefore retain
the same logical row positions while row measurements survive recycling.
Content taller than the minimum still grows normally; it is never clipped.

No wire or application changes are required. For example, a source with
`data-first-section-count=2` and `data-first-section-inset=136` still reserves
at least the unobscured viewport height minus 136 points for its first two
rows. `data-scroll-index=2` continues to address the third logical row, without
an application-supplied padding offset. Sparse virtual-list sources are unchanged.

## Unreleased: Native dialog transitions keep a fixed zoom origin

Retained enter/exit motion no longer re-reads a surface's resolved rect
each frame while a track is running. The zoom anchor stays where the
transition started, so dialogs whose layout is still settling no longer
drift or shake during the fade/zoom. No view or wire changes are required.

## Unreleased: Android Drive sample safe drawing insets

The optional `:drive-sample` Activity now explicitly enables edge-to-edge and
wraps `backend.Content()` in `Box(Modifier.safeDrawingPadding())`. Controls
respect current system-bar, display-cutout and IME insets instead of relying on
fixed content padding. This changes only the sample's host layout; renderer
defaults, native protocol v1, measured-coordinate conversion and strict
occlusion checks are unchanged.

Applications that copied the sample should call `enableEdgeToEdge()` and
apply Compose safe-drawing insets at their content boundary, or use their
existing screen-specific inset handling. Do not compensate by shifting Drive
coordinates or allowing input through SystemUI windows. See
[`platform/android/drive/README.md`](../platform/android/drive/README.md).

## Unreleased: DEBUG iOS read-only Drive probe

DEBUG iOS builds add `LUIAppleBackend.debugDriveSnapshot()` and
`LUIDriveSnapshotProbe.startIfEnabled(backend:window:environment:)`. These APIs
are absent in Release and on other platforms. Retain the probe after the
single foreground key window is ready, and call `stop()` during host teardown.
Wrap host references in `#if DEBUG`:

```swift
#if DEBUG
driveProbe = try LUIDriveSnapshotProbe.startIfEnabled(
    backend: backend, window: window
)
#endif
```

No listener opens unless `LUI_DRIVE_PROBE=1` is explicitly supplied. The probe
temporarily enables frame collection and restores its settings without
replacing existing callbacks. It binds only IPv4 loopback (default port 49378)
and accepts versioned read-only snapshot requests; it has no Drive action or
semantic event endpoint. This is debug access for trusted local processes,
not authentication against other local applications.

Native input belongs to the separate Drive XCTest UI-testing target, never
the app binary. Selector actions require explicit stable native accessibility
identifiers and do not fall back to labels, coordinates or semantic events.
Frame coordinates are window-local logical points, not screenshot pixels.
Existing production event behavior and transport contracts do not change.
See [`platform/apple/DriveProbe.md`](../platform/apple/DriveProbe.md) for a
complete host hookup, protocol and lifecycle example. Apple-SDK compilation
and Simulator/device input verification are separate integration gates.

## Unreleased: Optional Android native Drive host

Android renderer defaults and existing semantic integrations are unchanged.
`LuiBackend.inspect()` is a new opt-in, UI-thread-only read-only inspection
API. Close its `LuiInspection` handle to remove inspection semantics and
layout observers. Snapshots copy retained nodes and carry host-local
incarnation guards; native targeting requires attached, visible geometry.

For an API 30+ debuggable test variant, add
`debugImplementation(project(":drive"))`, register
`DriveTarget.attach(activity, backend)` after `setContent` behind an explicit
debug intent flag, and close the handle in `onDestroy`. Declare
`dev.lui.drive.DriveInstrumentation` only in the debug manifest. Keep the
optional library, INTERNET permission, runner and test IME out of release
artifacts. The sample supplies separate debug/release hooks.

```sh
# The debug app must already be installed; this clears its Activity task.
adb forward tcp:49377 tcp:49377
adb shell am instrument -w -e drive true \
  -e activity your.debug.package/.MainActivity \
  your.debug.package/dev.lui.drive.DriveInstrumentation
# In another terminal, with a Drive version supporting loopback TCP:
drive --tcp 127.0.0.1:49377 --input native scenario.drive
# After the run:
adb forward --remove tcp:49377
```

Native protocol v1 is unchanged: initial hello, full frames, then ops establish
readiness; fresh ops and full frames precede each correlated result. Wire
coordinates/deltas are content-viewport dp, converted to screen pixels at OS
MotionEvent/KeyEvent injection. No action falls back to LUI semantic events.

Text replacement uses a real InputConnection and requires deliberately
selecting the test-device IME; `type` is not advertised otherwise. The host
never enables/selects an IME itself. Preserve and restore the original IME,
or use the explicit `--test-device` sample launcher. Missing selection or
geometry, stale incarnations, disabled/hidden targets, detectable native
occlusion and unsupported input fail explicitly. Offscreen targets need
native scrolling; there is no selector auto-scroll.

Settling is bounded model/layout/draw/accessibility quiet, not application or
network idle, or proof of every render-thread animation. Accessibility cannot
prove the behavior of arbitrary invisible custom touch interceptors;
unmeasured modals/extensions and system UI need separate instrumentation.
Already running input cannot be rolled back. Compile/protocol/lint checks
are not device-input evidence. See
[`platform/android/drive/README.md`](../platform/android/drive/README.md)
for complete integration, input and cleanup limits.

## Unreleased: Native icon prop paints above state backgrounds

On the retained Native host, an `icon` prop on `menu-item` and
`number-stepper` now paints with the node's content — after its
`background`, `hover-background`, and `pressed-background` fills —
instead of in the default chrome layer underneath them. A hovered or
pressed control keeps its glyph visible; previously any declared state
background covered the icon. No view or wire changes are required.


## Unreleased: Native menu keyboard navigation

The retained Native window host opens a focused menu trigger with Return or
Space. Menu keyboard traversal includes enabled submenu triggers. Right,
Return, or Space opens the highlighted submenu. Left or Escape closes that
submenu and returns focus to its trigger. Menu typeahead clears its prefix
after 500 milliseconds of inactivity.

For example, a menu with a regular item followed by
`submenu ~text:"Type" entries` now reaches Type with Down and opens it with
Right. Hosts should keep forwarding native keyboard events and advancing the
existing window clock. This uses the existing menu constructors and wire
events.


## Unreleased: Web submenu placement through layout wrappers

Web dropdowns owned by a `menu-trigger` or `menu-item` now find their semantic
menu container through layout wrappers before choosing a default side. A
`context-menu`, non-picker `dropdown-menu`, or ``popover ~role:`menu`` qualifies.
For example, the following opens the submenu at logical inline-end (right in
LTR, left in RTL), rather than below its trigger over the following row:

```ocaml
popover ~role:`menu [column [submenu ~text:"Property type" entries]]
```

Top-level `menu` and `submenu` calls without a semantic menu ancestor retain
their below-trigger default. Listbox dropdowns and popovers without typed
``role:`menu`` stop the lookup; a DOM `role` data attribute is not a substitute.
Applications that use popovers as menu containers should pass the existing
typed ``~role:`menu`` only on those containers, not on ordinary dialogs.

Explicit `anchor` values, viewport collision handling, pointer corridors, hover
and keyboard behavior are unchanged. No constructor, wire, schema or native-host changes are required.

## Unreleased: Web nested-layer Escape ownership

Web layers now route Escape from their content through the shared topmost-layer
dispatcher before application document shortcuts run, even when those shortcuts
were registered before the layer opened. With a popover inside a dialog, the
first Escape dismisses only the popover; the next dismisses the dialog. This also
works when focus remains on the popover trigger inside the dialog. Target-local
handlers still run first, and `defaultPrevented` and composition guards remain
unchanged. Consumed Escape does not reach document shortcuts.

Applications should keep `dialog ~on_dismiss:close_dialog` and
`popover ~on_dismiss:close_popover` as the owners of dismissal rather than closing
both in a document Escape shortcut. No constructor, wire, native-host or other
keyboard behavior changes are required.

## Unreleased: Apple closed drawer visibility

An overlay drawer's retained panel is hidden once closed. On iOS the panel uses
a retained hosting controller inside a plain UIKit container. Closing sets the
container's `accessibilityElementsHidden`, then detaches the hosted view from the
window when the animation completes. Reopening attaches the same hosted view.
The hosting controller and its SwiftUI content remain retained throughout;
hidden hosting views can otherwise leave virtual accessibility proxies in the
window despite SwiftUI and UIKit visibility flags.
The panel remains mounted after its first reveal, preserving scroll position,
native state and the inherited SwiftUI environment when reopened. Pinned
split-view drawers, wire props and drawer events are unchanged; no application
migration is required.

## Unreleased: Android button labels in horizontal scrolls

Android icon/label buttons measure their natural content width before allocating
space to the label. Both leading and trailing icon groups therefore retain their
text in horizontal scroll containers instead of reducing a weighted label to zero
width. Explicitly constrained buttons still reserve icon space and ellipsize long
labels; no application workaround or new props are required. Other hosts and
press events are unchanged.

## Unreleased: Android list and menu content padding

Android `list-item` and `menu-item` apply authored padding inside their native
Material controls, replacing native padding on each specified edge rather than
adding a second outer inset. Unspecified edges retain Material defaults. An
authored fixed height removes unspecified native vertical padding so compact
nested controls do not consume the label's entire height.

Compact selection rows can keep their existing geometry:

```ocaml
list_item ~height:44 ~padding_vertical:0 [
  menu_item ~height:44 ~padding_vertical:0 ~text:"Choice" ~selected:true []
]
```

Remove explicit padding or height to use the corresponding Material defaults.
Native selection, press events, disabled states and other hosts are unchanged;
no wire or schema migration is required.

This guide records changes applications must consider when updating LUI.
Keep it alongside the implementation: every public constructor, wire contract,
default, event or compatibility change must receive an entry before release.
Changes below are unreleased work following PR #271.

## Unreleased: Android button content alignment

Android buttons center their label or icon/label group using the native Material
control. Custom child content now honors child `grow`; descendant text inherits
the button's `text-alignment` (center by default) unless it declares its own.
Icon/label pairs reserve space for either leading or trailing icons and ellipsize
long labels within the remaining width. Other hosts and press events are unchanged.

`text-alignment` no longer implicitly expands a label or its button to the full
available width. Adjacent aligned buttons therefore keep their natural widths.
Use explicit sizing when expansion is intended:

```ocaml
button ~grow:1.0 ~text_alignment:`center ~text:"Continue" []
button ~grow:1.0 [text ~grow:1.0 ~value:"Continue" []]
```

An explicit child `text_alignment` still takes precedence. No wire/schema
migration is required.

## Unreleased: Compile-time element nesting diagnostics

With `lui.ppx` enabled, statically resolved illegal element nesting now fails
during compilation with a `LUI nesting:` diagnostic, the parent/child kinds and
the offending source location. Admission rules are generated from the existing
runtime protocol; valid constructors, node IDs, events and wire batches do not
change. Applications without the PPX retain the existing runtime checks.

For example, replace `context_menu [button ~text:"Copy" []]` with
`context_menu [menu_item ~text:"Copy" []]`. A `tree` needs row containers, so
replace `tree [text ~value:"Item" []]` with
`tree [row [text ~value:"Item" []]]`. Menu/toolbar restrictions also apply through
statically resolved local values, nonrecursive helpers, `List.map`/`concat_map`,
list concatenation, conditional/match/exception branches and structural wrappers.
`separator`, `menu` and `submenu` use their actual underlying node contracts.

Correlated branches over immutable booleans or `Lui_ui.host context` retain their
relationship, including aliases, negation and boolean matches. For example,
`let child = if android then dropdown_menu [] else context_menu [] in
if android then menu_trigger [child] else button [child]` remains valid.
Separate effectful condition calls are not assumed to return the same value.

Structural `reactive`, `if_` and `keyed` callbacks mount without an anchor; when
one returns another structural primitive, the runtime creates a transparent Box.
The checker accounts for that Box rather than treating every dynamic wrapper as
transparent. For example, avoid nesting `if_` inside `reactive` under a
`context_menu`: choose the `menu_item` branch directly instead. `virtual_rows`
requires a direct `virtual_list` parent and must be its sole child; use
`virtual_list [virtual_rows ~source ~key ~cmp ~mount ()]`, not a sibling row or a
structural wrapper around `virtual_rows`.

This is a bounded source-level check, not a replacement for the type checker or
runtime validation. Unknown external functions/modules, recursive results,
runtime signals and expressions beyond the analysis budget can still require
runtime checks. Lexically shadowed constructor/module names are not assumed to
be LUI nodes. No type casts or protocol migration are required.

## Unreleased: Android text wrapping and overflow

Android text, labels and paragraphs now honor the existing `white-space` and
`text-overflow` properties. For example, `text ~white_space:"nowrap"
~text_overflow:"ellipsis" ~value:"Long title" []` stays on one ellipsized line
inside a constrained row. `pre` disables soft wrapping while preserving explicit
line breaks; omitted properties retain wrapping and clipping. Existing
`line-clamp` limits remain supported. No wire/schema migration is required;
other hosts are unchanged.

## Unreleased: Android sheets expand for text input

Android sheets that support the medium detent now expand when the software
keyboard is visible, keeping form fields and actions above the IME. Hiding the
keyboard leaves the sheet expanded; dismissal and explicit height constraints
are unchanged. Existing `sheet ~detents:"medium,large" [...]` forms need no
application workaround or wire/API migration. Apple and other hosts are unchanged.

## Unreleased: Web component defaults and interruptible Accordion motion

Web buttons without `size` now use the same height and padding as `size:default`.
On the iOS simulator profile, small buttons retain a smaller label while icon
buttons have a square 44px target. Separators without `orientation` now render
horizontally; vertical separators stretch across their row and have a one-em
minimum height when their parent has no definite height. Explicit typed sizes
and spacing remain supported; set `~min_height:0` when intentionally requesting
a shorter vertical separator. For example, `button ~text:"Save" []`
no longer needs ``~size:`default``, and `separator []` no longer needs
``~orientation:`horizontal`` to be visible. Remove padding or separator-height
workarounds added only to compensate for the missing defaults.

Web dialogs now separate their title and body, use the theme border color and
respect the simulated device width rather than the desktop browser width.
Explicit dialog heights remain supported and scroll when content does not fit;
omit `~height` for content-sized forms, as in `dialog ~width:380 ~padding:24 [...]`.
The gallery's rename form now follows this content-sized pattern. Simulated
keyboard space is still reserved while a field has focus, but is labelled as a
noninteractive placeholder instead of displaying striped keyboard chrome.
Use the host keyboard for text entry; this is not a software keyboard or IME.

Accordion expansion and collapse now transition from the current rendered
height, including when reversed mid-animation. Completion callbacks from an
older transition cannot hide or resize a newer one. The retained panel and
children, controlled `selected`/`on_toggle` behavior, linked accessibility
semantics and reduced-motion behavior are unchanged. Panel padding now belongs
to an internal `.lui-accordion-body` wrapper, allowing the animated panel to reach
zero height without a final padding jump. Applications styling that internal
panel's padding should move it to their content or the body wrapper. No OCaml
constructor, event payload or wire-schema migration is required.

## Unreleased: Apple drawer SDK compatibility

The Apple drawer builds with the existing Xcode 26 / Swift 6.2 toolchain again.
Its iOS 27.1 vertical-bar scene reader is compiled only when the SDK supplies
SwiftUI 8.1 or later, excluding Mac Catalyst, whose SDK lacks these iOS-only APIs.
The existing runtime iOS 27.1 availability check still applies. Older SDK builds
and Mac Catalyst retain the standard drawer presentation, even when run on a
newer OS; builds using a supported SDK retain the vertical-bar-aware presentation.

No constructor, wire schema, event or application source migration is required.
For example, an existing `drawer ~selected:is_open main sidebar` is unchanged;
rebuild its Apple host with the iOS 27.1 SDK or later to enable vertical-bar
adaptation on supported devices.

## Unreleased: Apple native button styles on OS 26

On iOS/iPadOS 26 and macOS 26, independent `button` and `toggle_button`
controls use the system's Liquid Glass button styles: absent/default, outline
and secondary variants use `.glass` (secondary keeps its secondary tint), while
primary and destructive use `.glassProminent` (destructive keeps its red tint).
Prominent labels retain readable white foreground ink when the application
sets an inherited foreground style. Standalone icon-only default buttons also
use `.glass`, rather than the former borderless style. The native styles supply
the glass material and interaction; applications should remove custom action
backgrounds, corner radii and padding that would cover the system treatment.

Ghost/content buttons remain borderless. Tab triggers keep their tab styling;
the default whole-row Form action remains automatic, and default icon-only
controls in native List rows remain borderless. Hoisted toolbar children retain
the system toolbar style, while cells inside an existing glass capsule remain unadorned
instead of drawing a second glass surface. Button actions, disabled/focus state,
selection tint and declared hit-target dimensions are unchanged. Earlier Apple
OS releases retain their existing bordered/borderless/automatic mapping. This
is a host presentation change only: there is no OCaml constructor, wire schema
or fingerprint migration. For example, existing
``button ~variant:`primary ~text:"Save" ~on_press:save []`` needs no source
change; remove any separately supplied background to see native prominent glass.

## Unreleased: Apple wrapping rows

Apple now honors the existing `row` property `flex-wrap: "wrap"`. Previously it
was decoded but rows always used a single HStack. No constructor, wire schema or
extension fingerprint changes. Rebuild the Apple host to enable the behavior;
existing ``row ~flex_wrap:`wrap ~gap:16 children`` needs no source migration.
Absent/`nowrap` retains the existing HStack path. This change is row-only: it
does not implement wrapping for `box` or `column`.

A finite width proposal (including zero) bounds each line; nil/infinite width
uses one natural-width line. Children are measured before breaking lines, and
an oversized child is remeasured with the bounded proposal. An explicitly fixed
child that cannot shrink occupies its own line and may overflow that line; it
does not widen the reported bounded row. Empty rows have zero size. `gap` is the
minimum space between items and between lines; no gap precedes the first item or
follows the last line.

`main` start/center/end/space_between applies independently to each line, with
logical horizontal placement mirrored in RTL. `cross` start/center/end/stretch
uses that line's maximum measured height. Positive `grow` shares remaining line
width proportionally after intrinsic bases and gaps; a `spacer` has a zero basis
and grow at least one. Growing children are remeasured at their allocated width
before line heights are finalized. Unbounded proposals do not allocate infinite
grow space. There is no geometry-to-state feedback or application-specific grid.

## Unreleased: Android pointer event capability checks

Android now checks the existing shared node-kind contract before emitting
`PointerDown` or `PointerUp`. The `pointer-enabled` property is also set by
ordinary input, submit, toggle and hover subscriptions; it does not grant every
pointer event to every node kind. Text fields and other unsupported kinds no
longer emit a rejected down/up pair before their native interaction. Supported
pointer kinds and the existing `role="treeitem"` opt-in continue to receive
down/up events when `pointer-enabled` is true. Disabled nodes remain inactive.

For example, an existing `text_field ~on_input:handle_input []` requires no
application change: native editing still emits `TextChanged`, without synthetic
down/up events. Existing `row ~on_pointer_down:handle_down
~on_pointer_up:handle_up []` handlers keep their shared event contract. Context
menu position observation remains independent of down/up capability, so an
attached context menu still observes its long-press location on a text control.

Pointer input restarts when the down/up capability changes. `PointerUp` is sent
only after the observed gesture releases, not from coroutine cancellation during
recomposition or removal. The shared receiver's strict unsupported-event checks,
wire schema, handler subscriptions and other platforms are unchanged. Rebuild
the Android host with this renderer; no source or wire migration is required.

## Unreleased: Web scoped theme mode

The Melange DOM backend now consumes the existing `theme-mode` property instead
of rejecting it during DOM application. `light` and `dark` select the default
Web palette and native control color scheme for the node's subtree; `system`
follows `prefers-color-scheme`, even inside a forced light or dark ancestor.
Nested modes override outer modes, including an explicit `light` mode under a
host `.dark` class. Removing the property restores the nearest enclosing mode
or the existing host appearance when no enclosing mode is present. Unthemed
hosts keep their existing default appearance.

For example, keep sending
`{"op":"set-prop","id":1,"property":"theme-mode","value":"dark"}`
to switch a mounted root to dark mode, or use `"light"` / `"system"` for the
other modes. Send
`{"op":"remove-prop","id":1,"property":"theme-mode"}`
to stop overriding its inherited mode. No wire, schema or application API
migration is required. Rebuild and deploy the Web stylesheet together with the
Melange backend; updating only the DOM code does not provide the scoped palette.

Open sheets and other portals follow their retained logical ancestry across
mode updates, property removal and reparenting, rather than the portal's physical
DOM parent. An explicitly themed portal keeps its own mode, and a detached
portal retains its last mode while exiting. Theme mode only selects palette
tokens: it does not rewrite explicit foregrounds, author colors, disabled states
or responsive styles. Custom token tables (`theme`) are a separate contract and
remain outside this Web receiver change.

## Unreleased: Android inherited foreground and scoped appearance

Android now applies a container's `foreground` to uncolored plain text in its
subtree, with the nearest explicit container color winning. An explicit text
leaf `foreground` still wins; an absent, empty, or whitespace-only value
inherits rather than resolving to transparent. Use `foreground: "transparent"`
or `"#00000000"` when transparency is intentional. Node colors resolve after
the node's own `theme` tokens and effective appearance, so a foreground token
on the same node uses the newly supplied palette. Removing a container's
`foreground` restores the nearest ancestor's color without remounting.

For example, set `{"op":"set-prop","id":2,"property":"foreground","value":"#EAE4DA"}`
on a Night tools column to color uncolored descendant text, and use
`{"op":"remove-prop","id":2,"property":"foreground"}` to resume inheritance.
Applications that relied on uncolored child text ignoring a container's
foreground should set a color explicitly on those leaves. This does not apply
the inherited color to every `TextStyle` or override Material buttons' native
enabled, disabled, selected, focus, and accessibility behavior.

Android `theme-mode: "dark"` and `"light"` now switch the scoped Material 3
color scheme as well as adaptive semantic tokens. `"system"` restores the
host's effective appearance, even under an explicitly dark/light parent;
removing `theme-mode` inherits the nearest parent again. Scoped schemes retain
the host's custom `LuiTheme(light = ..., darkScheme = ...)` palettes rather than
replacing them with defaults. For example, set a child node to `"system"` to
use the host palette inside a dark subtree, then remove that property to return
to the parent's dark palette. Applications that relied on an explicit `system`
silently inheriting the parent should remove that property instead. Material
controls and sheet chrome now follow the effective scoped scheme; their native
state colors remain owned by Material. No shared schema, wire format, or event
contract changes are required.

## Unreleased: Android text line clamps

Android now accepts the existing positive-integer `line-clamp` property on
`text`, `heading`, `paragraph` and `label`, matching the shared OCaml contract,
and passes it to those Compose text nodes as `maxLines`. Previously the Android
validator rejected this property, including in authoritative snapshots, and the
renderer had no line-limit consumer. This is not a numeric normalization change.

For example, keep sending
`{"op":"set-prop","id":2,"property":"line-clamp","value":1}`
to limit a text node to one line. Sending
`{"op":"remove-prop","id":2,"property":"line-clamp"}`
restores its original unlimited-line default. Nodes without the property keep
their previous behavior; button labels, text controls and other text consumers
are unchanged. No shared schema, wire, event or application rewrite is required.

## Unreleased: Android single-line text placeholders

Android placeholders now follow their control's line policy: `text-field`,
`secure-field`, `input`, `search-field` and `combobox` keep placeholders on one
line and ellipsize overflow. `textarea` placeholders continue to wrap. Previously
a narrow or zero-width field could wrap its placeholder character by character,
inflating a single-line control and its containing row to hundreds of dp even
though the editable text itself was single-line.

The wire format, default control height and `grow` behavior are unchanged. For
example, keep sending `{"op":"set-prop","id":2,"property":"placeholder","value":"Search this book…"}`;
no fixed height or placeholder rewrite is necessary. Applications must still
provide usable width or responsive toolbar alternatives: this correction does
not make a field usable when other row children consume all available width.

## Unreleased: Apple normalizes all floating wire properties

Apple now normalizes integral JSON numbers to its floating retained value for
every shared `FloatValue` property, not just the previously covered subset.
JSONDecoder can decode `2.0` or `2e0` as an integer; previously, for example,
`{"op":"set-prop","id":4,"property":"letter-spacing","value":2.0}`
rejected the entire batch even though the OCaml producer emitted a valid float.

Existing normalization remains for `item-extent`, `grow`, `anchor-offset`,
`anchor-alignment-offset`, `source-x`, `source-y`, `source-width`, `source-height`,
`value`, `min`, `max`, and `step`.
Newly covered properties are `first-pane-width`, `resize-origin`,
`resize-handle-offset`, `opacity`, `label-opacity`, `letter-spacing`, `inset`,
`inset-top`, `inset-right`, `inset-bottom`, `inset-left`, `hover-opacity`,
`pressed-opacity`, `disabled-opacity`, `width-viewport`, `height-viewport`,
`min-width-viewport`, `max-width-viewport`, `min-height-viewport`,
`max-height-viewport`, `popup-x`, `popup-y`, `available-height`, and
`collision-padding`.

No application migration or JSON rewriting is needed: continue emitting numeric
values, including integral floats such as `letter-spacing: 2.0` or `opacity: 1.0`.
Fractional numbers keep their existing behavior. Boolean and string values are
not converted; integer-only properties are unchanged. Property/kind admission,
finite-value checks, numeric bounds, and atomic batch rollback are unchanged.
The OCaml protocol and generic native ABI are unchanged.

## Unreleased: Android accepts wrapping preserved text

Android's retained text-flow validator now accepts `white-space: "pre-wrap"`,
matching the existing shared OCaml and Apple vocabulary for this mode. Previously
a valid batch such as `{"op":"set-prop","id":2,"property":"white-space","value":"pre-wrap"}`
was rejected atomically, including authoritative snapshots, even though Compose
`Text` already preserves the supplied text and wraps by default.

No application wire rewrite is required: keep sending `pre-wrap` for canonical
text whose whitespace must be retained. This only corrects validation; it does
not add CSS whitespace processing or change rendering of `normal`/`nowrap`.
Android still rejects `pre-line`, `pre`, unknown strings and non-string values.

## Unreleased: Linux native clipboard ownership result

`Lui_shell_linux.clipboard_write : string -> bool` keeps its signature but
now returns the synchronous `gtk_clipboard_set_with_data` ownership result.
Previously `true` only meant a GTK clipboard object existed after calling
the void `gtk_clipboard_set_text` function. It was not an ownership ACK.
There is no new checked/compatibility API or wire change. Existing
platform-selected `Shell.clipboard_write` callers keep compiling; callers
that ignore the result still do not receive a guarantee.

On Linux, `false` means missing clipboard support, ownership refusal,
allocation failure, or rejected text: invalid UTF-8, embedded NUL, or
`INT_MAX` bytes or more. The maximum accepted length is `INT_MAX - 1` bytes.
Rejected text is not silently truncated. Empty text is valid. The
implementation copies the entire accepted UTF-8 string before
acquisition, advertises GTK's text targets, serves requests through that
owned copy, and frees it on ownership loss/clear/replacement. Failed
acquisition frees the new copy immediately without first clearing the
clipboard. The result is not inferred from a readback, change counter,
transport enqueue, or SDL return value.

Replace an unchecked destructive continuation:

```ocaml
ignore (Shell.clipboard_write selected_text);
delete_selected_text ()
```

with an ownership-gated continuation using the existing platform-selected
Shell module:

```ocaml
if Shell.clipboard_write selected_text then
  delete_selected_text ()
else
  report_clipboard_write_failure ()
```

If the application forwards this result asynchronously, its success
continuation must additionally revalidate the original editor/selection
owner before deleting; an ownership result does not authorize a stale edit.
Keep failure handling explicit and never acknowledge an unhandled request.

Call the Linux Shell on the GTK UI thread and continue running `Shell.pump`
there while owning the selection, including when no frame needs repainting.
The existing pump iterates GLib's default main context and serves the data
and clear callbacks; no extra loop, thread, or event API is introduced.
`true` does not promise external paste success, indefinite ownership, or
clipboard-manager persistence after exit. Successful acquisition retains
the old `gtk_clipboard_set_text` helper's `gtk_clipboard_set_can_store`
hint; that void capability hint is not a persistence ACK. No explicit
store/manager handoff is added. macOS retains its existing
`NSPasteboard.setString` BOOL result; other backends and their input limits
are unchanged and are not newly qualified by this Linux change.

## Unreleased: shared component API

### Apple drawer swipes can interrupt transitions

Compact Apple drawers now accept a reverse swipe while an opening or closing
animation is in progress. Previously, those swipes were discarded until the
transition completed. The new drag owns the interaction lock, so completion
callbacks and delayed model acknowledgements from the previous transition cannot
unlock descendant controls during it. Vertical gestures and outward swipes keep
their existing rejection rules.

No wire or application code migration is required. Continue acknowledging each
`ToggleChanged` event through the drawer's controlled `selected` property. For
example, after an opening gesture emits `checked=true`, publishing `selected=true`
while the user has begun closing acknowledges that opening gesture without
restarting its animation or cancelling the closing drag.

### Owned pointer gestures on Row and Box

`row` and `box` now accept `?pointer_capture:bool`, `?on_pointer_down`,
`?on_pointer_move`, `?on_pointer_up` and `?on_pointer_cancel`. Capture defaults
to false. The new wire property is `pointer-capture`; the new events are
`PointerMove (node, detail)` and `PointerCancel (node, detail)`. Both use the
existing `pointer_detail` payload and client-space coordinates. Its modifier
mask is unchanged: Ctrl=1, Shift=2, Meta=4, secondary pointer button=8.

With capture enabled, an admitted primary down owns movement and completion
outside the handle. `PointerUp` means successful release; Escape, host blur,
capture loss, pointer cancellation, disablement and removal cancel instead.
A captured gesture does not activate Press, PressDetail or a context menu.
Handle cancellation by discarding the preview, never by committing it:

```ocaml
box ~pointer_capture:true
  ~on_pointer_down:begin_preview
  ~on_pointer_move:update_preview
  ~on_pointer_up:commit_preview
  ~on_pointer_cancel:discard_preview []
```

Applications should also discard owned preview state when their view unmounts;
a removed node cannot receive subsequent application events. Existing nodes
without capture retain their pointer/press behavior and do not subscribe to
movement or cancellation. The feature is implemented on Web; adding
the shared vocabulary does not qualify other native hosts for captured gestures.

The Web DOM setter now accepts `pointer-capture` and clears its capability marker
on removal. The retained property continues to control gesture ownership;
changing or removing it resynchronizes the existing pointer listeners and cancels
any active preview. Native DOM capture still begins only on an admitted trusted
primary down, not when the property is applied. Existing typed handles, including
the example above, require no migration or application fallback.

Row and Box also admit `NavigationKey` when `?on_navigation_key` is provided:
arrows, Home/End, PageUp/PageDown, Enter, Space and Escape, preserving Shift.
No handler means no navigation subscription. Keyboard focus still belongs to
the application's normal typed focus/role configuration.

### Row and Box navigation focus ownership

On Web, Row/Box navigation callbacks only receive keys owned by that focused
container, never keys from a descendant checkbox or editor. Web stops
propagation after an admitted navigation event. Disabled and inert ancestors
block navigation. Other controls retain their existing navigation behavior;
no handler still means no subscription. Applications can replace a container's
raw keydown bridge with `row ~on_navigation_key:handle_row_key ...` without
intercepting keys typed inside child controls. Web containers retain the
application's normal focus configuration, such as `~data_attrs:["tabindex", "0"]`.

Native OCaml makes navigation-enabled Row/Box containers focusable for pointer
and Tab focus. Only the actually focused node receives navigation; child
checkboxes and editors keep their default keys. Disabled/inert ancestors,
hidden containers, modal scope and IME composition block container navigation.
Ctrl/Meta/Alt combinations remain outside this navigation subscription; Shift
is preserved. Existing button navigation and Enter/Space activation are unchanged.

### Checkbox mixed state and modifier-aware proposals

Checkbox gains `?indeterminate:bool` and its reactive binding, defaulting to
false. The wire property is `indeterminate`. This is presentation and
accessibility state; it never changes accepted `checked`. Activating a mixed
checkbox proposes true. The next model update decides whether to retain or
clear the mixed state.

`?on_toggle_detail` opts in to `ToggleChangedDetail (node, checked, modifiers)`
through `toggle-detail-enabled`. Its independent physical-key modifier mask is
Ctrl=1, Shift=2, Meta=4, Alt=8; it must not be interpreted as the legacy
PressModifiers/pointer mask, whose bit 8 denotes a secondary pointer button.
The existing `?on_toggle`, bool `checked`, and `ToggleChanged` event are
unchanged. If both handlers are installed each receives one proposal; do not
apply the same state transition twice. With no detail handler no detail event
is emitted.

The Web DOM setter now accepts `toggle-detail-enabled` and clears its capability
marker on removal. This fixes a render failure for typed `~on_toggle_detail`
subscriptions; existing consumers require no migration or event fallback.

Mixed rendering and accessibility state are currently implemented only on Web.
Web also implements mixed-to-true proposals and
`ToggleChangedDetail` events.
Apple and Android recognize the shared property vocabulary and perform typed
admission; this does not qualify them for these behaviors.

The Native OCaml window input path now supports mixed-to-true proposals and
opt-in `ToggleChangedDetail` for primary clicks and focused Enter/Space
activation, including the physical Ctrl/Shift/Meta/Alt mask above. It does not
mutate accepted `checked` or `indeterminate`; a model echo decides the state.
Disabled/inert ancestors suppress checkbox activation. Legacy bool-event
admission is preserved, and without `toggle-detail-enabled=true` no detail event
is emitted. This qualifies only the window pointer/keyboard input contract,
not native mixed painting, accessibility state or accessibility-action producers.
Native consumers can use the typed `~on_toggle_detail` example below without
an application-level event fallback; handlers that also subscribe to `~on_toggle`
must still avoid applying the proposal twice.

```ocaml
checkbox ~checked:all_selected ~indeterminate:some_selected
  ~on_toggle_detail:(function
    | ToggleChangedDetail (_, checked, modifiers) ->
        select_rows ~range:(modifiers land 2 <> 0) checked
    | _ -> ()) []
```

### Pending-aware application model reads

`Lui_app.model app` now returns the latest reduced model even before a pending
signal update is published. This applies to regular, extension-enabled and
reloadable application constructors. Reading the model does not flush the
scheduler, run view updates or emit patches; view signals keep their existing
batched publication semantics.

An async context fence can capture `(Lui_app.model app).context_revision` before
starting a request and read it again before accepting the response. The revision
must be incremented by the reducer for every context publication, including an
A-to-B-to-A sequence in one flush. A published view signal cannot replace this
fresh read because intermediate updates may be coalesced. Existing callers that
read after `Lui_app.flush` require no changes; callers that intentionally need a
published view snapshot must read their borrowed model signal instead.

### Bounded row generation for virtual lists

`virtual_list` continues to accept literal children and `keyed` sources. Those
forms retain every LUI row even when the host virtualizes its views. Applications
with large collections can opt into `virtual_rows` as the sole direct child:

```ocaml
(* Before: every item owns a mounted LUI row. *)
virtual_list ~height:400 [
  keyed ~source:rows ~key:(fun row -> row.id) ~cmp:Int.compare ~mount:row_view
]

(* After: the host requests a window of rows. *)
virtual_list ~height:400 ~overscan:5 ~item_extent:32. [
  virtual_rows ~source:rows ~key:(fun row -> row.id) ~cmp:Int.compare
    ~scroll_key:(fun row -> Printf.sprintf "row-%d" row.id)
    ~mount:row_view ()
]
```

The business data source and its key index remain complete. On Web,
SwiftUI and Kotlin hosts that advertise window feedback,
only requested rows, overscan and active interaction pins own mounted scopes,
signals, handlers and host controls. Overlapping windows preserve row identity;
eviction disposes the row and a later visit creates a fresh incarnation.
Store persistent editor values, selection and other row state in application
data and bind them as controlled values. Late events cannot target a replacement
incarnation. Source reorders preserve still-existing mounted keys until the host
acknowledges the new source generation.

The source signal is borrowed. A `reactive` derivation passed as `~source` is
created and disposed per mount by the PPX, following the same ownership rule as
`keyed`. Rebuild the PPX together with LUI. `scroll_key` is optional unless a
lazy parent uses a nonempty `scroll_target`; it resolves targets without mounting
intermediate rows. Duplicate item keys or scroll keys are errors.

Updated SwiftUI and Kotlin hosts implement the same bounded source contract.
Literal children and the older application-managed window conventions retain
their existing behavior. An individual row may still own a large descendant
subtree, and host geometry caches may scale with source size.
Virtual rows require positive logical geometry: a zero-height or empty root
keeps a positive estimate or a host minimum of one pixel. This avoids
repeatedly expanding the mounted window when blank rows collapse during layout;
positive compact rows retain their measured heights.

SwiftUI and Kotlin retain their semantic platform profiles, including native
extension selection. Their native startup handshake uses these codes:

| Host | Legacy code | Bounded-row code |
| --- | --- | --- |
| SwiftUI | 2 | 258 |
| Kotlin | 4 | 260 |

The new C export `lui_ocaml_virtual_rows_version()` returns 1 and is safe to
probe before starting the runtime. Updated Swift loaders select code 258 only
when this optional export is available. The Android JNI bridge exposes the
corresponding optional version probe before selecting code 260. Older libraries
and older host clients keep codes 2/4 and receive the complete eager collection.
Rebuild the OCaml application, native bridge and updated host together to enable
bounded rows. An unrelated or unknown host code does not enable this capability.

`Lui_app.create`, `create_with_extensions`, `create_reloadable` and
`create_reloadable_with_extensions`, and both `Lui_runtime.create` constructors,
accept an optional `~virtual_rows:bool` override. The default is true for Web,
SwiftUI and Kotlin profiles and false for Generic. The override is fixed
before mounting the view and persists through reload without changing the host
profile. Custom native initializers must pass the negotiated capability:

```ocaml
let host_profile = Lui_native_bridge.profile platform_code host_code in
Lui_app.create
  ~virtual_rows:(Lui_native_bridge.virtual_rows_supported host_code)
  (Lui_native_bridge.backend bridge host_profile)
  initial_model reducer view
```

A custom Generic host may explicitly opt in after implementing the complete
window protocol. Passing false preserves eager behavior on any semantic host.
Code constructing a runtime record directly must account for its new immutable
`runtime_virtual_rows` capability; prefer the runtime constructors.

Custom Swift event switches and Kotlin sealed-event handlers must forward the
new `virtualWindow` / `VirtualWindow` maintenance event to the native window
entry point, independently of application visible-range subscriptions.
Apple's legacy C event callback appends kind 20 with legacy node argument 0;
its JSON object carries authoritative integer `node`, `generation`, `first`,
`last` and `pins` fields so IDs are never narrowed to the callback's Int32 node.
The typed Swift event and the native OCaml window ABI retain full native integer
precision. Existing ordinary callback kinds remain unchanged.

Sparse wire producers set `virtual-total-count`, `virtual-generation` and
`virtual-indices` together on the existing `virtual-list` node. The indices are
a canonical JSON integer vector parallel to committed children, strictly
increasing and within the logical count. Optional `virtual-scroll-index` is -1
for a missing target or a valid logical index. Invalid final metadata rejects
the entire batch. Internal `VirtualWindow` feedback uses a half-open interval
and direct row node IDs for pins. Public `VisibleRange` keeps its inclusive
range convention. The new event precedes `ExtensionEvent`; native consumers of
raw OCaml variant tags must rebuild for its shifted extension-event tag.

### Native host compatibility

Updated Apple hosts accept the existing `navigate-enabled` flag on buttons and
the canonical text-entry kinds. Updated Kotlin hosts accept the existing
`navigation` and `navigation-heading` list-item roles, with native selected-item
and heading accessibility semantics. These properties already come from LUI
constructors and the shared Gallery; applications need no source changes.
Custom native validators must preserve the canonical finite kind and role sets
when accepting sparse virtual-list metadata.

Kotlin ordinary lists use intrinsic column layout when their parent provides
unbounded vertical space, preserving the outer scroll owner. Finite viewports
retain native lazy-list scrolling and row targets. Applications can keep an
ordinary list inside `scroll` without adding an artificial fixed height.
Authored compact list-item heights preserve readable text by removing native
vertical content padding while retaining horizontal insets and native input.
Sparse Kotlin collections expose the supported native forward/backward scroll
actions on their viewport even when interactive rows cover its content.

The Apple C bridge now closes its ARC-owned window safely during reset.
The existing reset entry point and application lifecycle API are unchanged.

### Large-batch encoder memory

The shared OCaml encoder processes large batches without retaining
per-operation JSON copies. Wire bytes, integer precision and application APIs
are unchanged. Rebuild application libraries to include the encoder improvement.

### Nested toolbar focus ownership

On Web, a toolbar owns one keyboard Tab stop across its nested button and toggle
groups. Group refreshes no longer create additional stops after model updates;
arrow navigation continues through the complete toolbar sequence. Standalone
groups retain their own roving focus behavior. Applications need no source change.

### Toast keyboard dismissal

On Web, Escape now dismisses the open toast containing keyboard focus. Escape outside a toast, during IME composition, or after another handler
consumes the event leaves notifications open. Applications should handle the
existing dismiss event by removing that toast from their model. Independent
notifications retain their own lifetimes.

The Gallery now demonstrates one notification per activation and disables its
trigger while open. Its four-second duration is demo configuration; component
defaults are unchanged.

### Virtual-list configuration becomes typed

The OCaml constructor keeps its existing optional arguments:

```ocaml
virtual_list ~overscan:0 ~item_extent:32. rows
```

Previously these arguments generated `data-overscan` and `data-item-extent`
attributes inside `data-attrs`. They now generate the `overscan` integer and
`item-extent` float properties. `overscan` must be nonnegative; zero disables
extra rows. `item-extent` must be positive and finite and estimates unmeasured
rows; actual row measurements remain authoritative.

Applications using the constructor need no source change. Custom hosts and
wire consumers must recognize the two new properties. Legacy semantic
attributes remain readable during migration. Explicit typed properties take
precedence; removing a typed property restores the legacy attribute or host
default. Removing both restores the host default.

Prefer constructor arguments over hand-written semantic attributes:

```ocaml
(* Before *)
virtual_list ~data_attrs:[ "data-overscan", "3" ] rows

(* Preferred *)
virtual_list ~overscan:3 rows
```

### Read-only editing is distinct from disabled editing

`text_field`, `secure_field`, `input`, `search_field`, `textarea` and `combobox`
gain `?read_only:bool` and reactive `?read_only_signal` bindings. The default is
false. Read-only controls preserve focus, selection, copying and navigation;
they reject user edits and do not emit text-change proposals. Application model
updates can still replace their displayed value. `disabled` continues to block
interaction.

Secure fields retain their password-copy restrictions in read-only mode.

```ocaml
text_field ~text:"Reference value" ~read_only:true []
textarea ~text:(reactive Model.notes model)
  ~read_only:(reactive Model.locked model) []
```

JSON views use `"read-only": true`; custom hosts must decode the `read-only`
boolean property. Removing it restores editable behavior. Applications that
used `disabled` solely to prevent edits may switch to `read_only` when users
should retain selection and copying.

### Tabs, lifecycle and scroll results

Ordinary `tabs` keep their application-owned content. Arrow keys activate the
new focused tab, respecting orientation and disabled items. `bottom_tabs`
renders the selected retained tab's page. Applications must keep `selected`
under model control.

Scroll completion outcomes are `succeeded`, `cancelled` and `missing-target`.
Visible ranges use inclusive `first`/`last` indices and `0`/`-1` for an empty
viewport. Request tokens and appearance events are scoped to a node incarnation;
reusing an ID after removal does not revive old queued callbacks. Scroll request
tokens preserve exact OCaml integers, including neighboring values above 2^53;
each distinct token starts a new request.

### Complete native event payloads

The shared native C ABI includes length-carrying `lui_ocaml_*_utf8` pointer
exports for `target_class` without truncation. Existing C-string pointer
exports remain available. Custom native bridge loaders using these exports
must link the matching rebuilt application library.

## PR #271: removed line-break component

The `br` component, OCaml constructor and standard wire kind were removed.
Replace separate-line content with a `column`, or use a newline inside one text
value when it belongs to the same text run. Do not register a custom standard
`br` renderer: it does not restore a removed protocol kind. Raw HTML extensions
keep their independent HTML element rules.

## Upgrade checks for application maintainers

1. Update generated wire schemas and custom host decoders together with LUI.
2. Replace uses of `br` and invalid retained child shapes.
3. Prefer typed virtual-list arguments; test any legacy attribute overrides.
4. Review disabled editors that should allow copying.
5. Exercise model rejection/normalization, keyboard navigation, resource
   replacement and stale async callbacks on each host the application ships.

The Web/Melange backend remains available for browser hosts.

## Apple virtual-list viewport changes

Apple virtual lists now recompute row visibility when the viewport height changes,
even when the row's frame stays unchanged. Initial layout and keyboard/viewport
transitions no longer leave visible top rows outside the emitted `VisibleRange`.
The event shape and virtual-window metadata are unchanged; applications need no
API migration. Applications with bounded windows should verify initial page load
and keyboard transitions without scrolling to repair the visible window.

## Apple search input traits

Apple `search-field` controls disable automatic capitalization and spelling
correction so a literal query is not silently changed by the keyboard. Inline
controls use the Search return key; navigation/list-hosted native search retains
its existing search submission. Ordinary `text-field` and `textarea` behavior is
unchanged. No schema, event, query normalization or matching semantics change.

Applications should use `Lui_elements.search_field ~on_submit:run_search []` for
search rather than `text_field`. Keep `on_input` bound to the shared query and
`on_submit` to the search action. Do not set `submit_on_enter` on either
single-line kind; that property belongs only to `textarea`.

## Web virtual-list resize measurements

Web virtual lists process TanStack ResizeObserver measurements in an animation
frame rather than synchronously inside the observer callback. Rendering a
measured row can resize an intrinsically sized list; deferring that render avoids
ResizeObserver delivery loops when switching views or changing row dimensions.
Initial layout, wire properties and event payloads are unchanged. Resize-driven
visible ranges and virtual windows can arrive on the next animation frame.

Applications should continue to use `virtual_list ~item_extent:320. rows` and
respond to `on_visible_range` rather than expecting the DOM range to change
synchronously with a browser resize notification. No API or schema migration is
required; other hosts are unchanged.

## Primary pointer capture retains non-primary events

Web Row/Box `pointer-capture` no longer filters out non-primary
`PointerDown`/`PointerUp`. The LUI handler does not start or end its primary drag
state for those buttons.

Applications can keep `~pointer_capture:true` for primary dragging and handle
`PointerUp (_, detail)` with `detail.button = 1` for middle-click actions. Do not
assume that a captured control filters out non-primary releases. No property,
event payload or primary drag/cancellation API changes are required.
