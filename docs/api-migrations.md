# LUI API migration guide

This guide records changes applications must consider when updating LUI.
Keep it alongside the implementation: every public constructor, wire contract,
default, event or compatibility change must receive an entry before release.
Changes below are unreleased work following PR #271; host qualification is
tracked in [the MyGo parity plan](agent-guide/004-component-api-mygo-parity.md).

The Native OCaml renderer is outside this parity update except for the
input contracts explicitly qualified below. Its paint-property
inventory check is temporarily deferred until that inventory recognizes
`read-only`, `overscan` and `item-extent`; these features are not qualified on
that renderer. The MyGo, Web, Apple, Android and shared ABI regressions remain
covered separately.

## Unreleased: component API and MyGo parity

### Host commands on standard MyGo text editors

MyGo `Config` now accepts two optional, typed hooks:

```go
InputValue   func(Node, *string)
InputControl func(Node, ui.Element, string)
```

`InputValue` runs after ordinary model text reconciliation and immediately
before constructing the native `TextInput` or `TextArea`. It may update that
build's text through the pointer. `InputControl` runs after construction and
input-handler setup, receiving the resulting text for focus and selection
binding. It runs before the existing focus-transition sample, retained handle
binding and autofocus logic; their relative order is unchanged.

Both hooks run synchronously on the UI thread during live construction, never
in `view-that-fits` measurement probes. Do not retain the text pointer, Element
or its Context beyond the call. Nodes are detached read snapshots. Hooks cover
the text-editing paths of `text-field`, `secure-field`, `input`, `search-field`,
`textarea` and `combobox`. They do not run for specialized ColorWell/TimeInput
branches or custom renderers that replace the standard control. Nil hooks
preserve existing behavior; wire vocabulary and other platforms are unchanged.
Existing keyed Config literals need no changes; positional literals must be
updated for the added fields, preferably by switching to keyed initialization.

An imperative value command does not synthesize `OnChange`, `TextChanged` or
Dispatch, and does not persist a new model value. Keep the existing controlled
reducer and ordinary text reconciliation. The host still owns command queues,
node incarnation/epoch checks, invalidation and post-layout `AfterFrame`
acknowledgement/retirement. Publish and apply a node's creation before sending
commands for it; these hooks do not buffer missing references or repair message
ordering. Apply selection to the actual Element during construction. MyGo
selection offsets count runes: DOM-style UTF-16 offsets must be converted by
the host against the text passed to `InputControl`, without splitting surrogate
pairs. Any returned DOM offsets are build-time observations, not a substitute
for querying the native selection during an input event.

For a host with existing incarnation-scoped helpers, configure the standard
renderer rather than copying it or adding component-specific exceptions:

```go
backend := luimygo.New(luimygo.Config{
    Dispatch: runtime.Dispatch,
    InputValue: services.BindInputValue,
    InputControl: func(n luimygo.Node, e ui.Element, text string) {
        services.BindInputControl(n, e, text)
    },
})
```

Here `BindInputValue` has signature `func(luimygo.Node, *string)` and
`BindInputControl` may return UTF-16 `(start, end int)`; the closure deliberately
discards those results. Existing raw/extension renderers retain their own
bindings; the hooks do not duplicate their dispatch or command ownership.

### Bounded and content-sized Stacks on MyGo

The MyGo `stack` adapter now passes its allocated width and height through
each synthetic layer wrapper to its children. A bounded Stack no longer lets
an automatic content-height floor enlarge a nested Stack beyond that allocation.
Stacks without a bounded size still measure to their largest intrinsic child,
and removing that child lets the Stack shrink. Explicit child sizes, minimums,
maximums and margins remain effective; layer order, `z-index`, pointer
pass-through and retained child identity are unchanged.

Keep the finite shell constraint on the outer Stack, and use `grow: 1` and
`min-height: 0` on the inner flow Column and Scroll that share its height.
For example, an outer Stack with `height-viewport: 1` in an 897-DIP viewport,
containing a nested Stack and a Column with a 48-DIP header, now gives its
growing Scroll the remaining 849 DIPs even when the Scroll content is 1280
DIPs tall. Do not repeat the full viewport height on the Scroll: that would
ignore the header's share. Applications that require a content-sized Stack
should continue to leave its size unconstrained rather than add viewport
or fill constraints. No wire vocabulary or other host behavior changes.

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
movement or cancellation. The feature is implemented on Web and MyGo; adding
the shared vocabulary does not qualify other native hosts for captured gestures.

MyGo's toolkit adds `HandleCapturedPointer` and `InputPointerCancel`. Use this
handler instead of `HandleInput` when successful release must differ from
cancellation. A primary down returning true owns the gesture. Existing
`HandleInput` consumers retain their legacy synthetic-release deactivation
behavior; they are not silently migrated to cancellation.

Row and Box also admit `NavigationKey` when `?on_navigation_key` is provided:
arrows, Home/End, PageUp/PageDown, Enter, Space and Escape, preserving Shift.
No handler means no navigation subscription. Keyboard focus still belongs to
the application's normal typed focus/role configuration.

### Row and Box navigation focus ownership

On Web, MyGo and the Native OCaml window hosts, Row/Box navigation callbacks
only receive keys owned by that focused container, never keys from a descendant
checkbox or editor.
Web stops propagation after an admitted navigation event. MyGo makes an
interactive navigation-enabled container focusable and registers shortcuts
only while its handle owns focus; filtering only inside a subtree shortcut
callback would still consume the child's default key behavior.
Disabled and inert ancestors block navigation. Other controls retain their
existing navigation behavior; no handler still means no subscription.
Applications can replace a container's raw keydown bridge with
`row ~on_navigation_key:handle_row_key ...` without intercepting keys typed
inside child controls. Web containers retain the application's normal
focus configuration, such as `~data_attrs:["tabindex", "0"]`.

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

Mixed rendering and accessibility state are currently implemented only on Web
and MyGo. Those hosts also implement mixed-to-true proposals and
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

### MyGo transparent dynamic anchors

`box` nodes with `display="contents"` now render their children directly into
the current native parent, without creating a MyGo `Column` or consuming a
native element key. These are the transparent structural anchors emitted when
reactive, conditional or keyed branches nest. For example, the retained tree
`text -> box(display=contents) -> text` renders as inline text rather than
panicking when MyGo encounters a box inside a text paragraph.

The retained anchor, parent links, descendant order and incarnation keys remain
intact. Appearance still dispatches once per committed incarnation, never from
an unselected fitting probe; hidden anchors suppress their subtree and retired
incarnations remain stale. The anchor has no native bounds, focus target or
independent pointer surface. Box layout and paint properties do not create a
surface for it; put those properties and direct native interactions on a real
container or descendant instead. Retained ancestry remains available to hosts
and continues to enforce disabled/inert event filtering.

No OCaml API, wire format, dependency pin or application migration is required
for generated dynamic anchors. Do not replace the enclosing `text` with a
column or flatten arbitrary boxes as a workaround. A real `box`, `icon` or
other non-text child remains invalid inside native text, even through a contents
anchor; put it beside the text in a typed row. This change applies specifically
to structural `box` anchors, not to all component kinds with a display prop.

### MyGo authored switch chrome

Switches with authored dimensions, padding, foreground, background, border or
corner radius now use MyGo's public `SwitchBase` for their input, focus and
accessibility behavior. The shared renderer sizes the thumb inside the authored
padding and resolves its color from `foreground`, including scoped theme tokens
and existing state foreground overrides. The track continues to consume the
ordinary background, border and radius properties. Layout-only placement and
semantic class names do not select this rendering path.

For example, a `switch` with `width=32`, `height=18`, `padding=3` and
`foreground="var(--background)"` now has a 12-DIP thumb painted in the resolved
background color, rather than MyGo's default white thumb. Its checked state,
`toggle-enabled` subscription, disabled behavior and `toggle-changed` proposal
and acknowledgement contract are unchanged. Removing the authored chrome
properties restores the default MyGo `Switch`; switches without those properties
retain their existing native look. No wire or dependency-pin changes are needed.

### MyGo spacer hit transparency

`spacer` is a layout void and no longer owns pointer hits, matching the Native
and Web hosts. Internal `stack` and `overlay` placement wrappers are also
hit-transparent; real descendants still receive input normally. This fixes
full-window placeholders covering otherwise active controls. No wire or event
subscription changes are required. For example, `stack [button; spacer []]`
now lets the button receive native activation and document click capture;
preventing that capture still cancels the activation.

Ordinary transparent `box` nodes retain their existing hit behavior. Do not use
`spacer` as an interactive surface; use a container or control instead.

### MyGo inherited pointer policy

The MyGo adapter now maps the existing `pointer-enabled` protocol to MyGo's
public `Element.PointerEvents(bool)`: false suppresses the entire native
subtree, including internal captions; unset descendants inherit; explicit true
opts a subtree back in. This applies to standard nodes and raw extensions
bound with `Backend.BindHostElement`. No wire changes or Logseq-specific
workarounds are needed.

As on Native, presented `dialog`, `sheet`, `popover`, `dropdown-menu`,
`context-menu`, `toast` and drawers without a `selected` prop default to enabled
below a disabled ancestor. Explicit false still wins, and a permanent host
marked `data-overlay-layer=true` never implicitly opts in. For example,
`overlay ~pointer_enabled:false [button ~pointer_enabled:true ...]` accepts
input only in the opted-in button; other controls and native labels remain
transparent. Existing ordinary containers without a pointer policy retain
their previous hit behavior. Capture returning true still cancels activation;
paint, layout and keyboard focus are unchanged by the pointer policy.

Embedding hosts must select the same MyGo fork version as this adapter in
their root `go.mod`; Go does not inherit dependency replacements. The fork
must provide both `Element.PointerEvents` and the bounded-row
`ListState.Requested`/`SetKeyIndex` APIs. The integrated pin retains both
contracts, plain-hit document click capture and the native handle-lifetime
fixes; choosing an older pointer-only or bounded-row-only candidate is not a
compatible substitute.

### MyGo decoded image dimensions

Embedding hosts can call `Backend.NaturalImageSize(id)` on the UI goroutine to
read `(width, height, ready)` for standard `image`, `file-image` and `avatar`
nodes. Dimensions come from the current decoded pixels, including any
`max-pixel-size` downsampling, not layout size, cropping or avatar placeholders.
URL/path assets must match the current retained node's source and decode limit;
drop/recreation and snapshots discard that node's decoded state. Host-registered
images use the current image registration only when no URL takes precedence.

The query performs no I/O and starts no decode. Pending, lazy/unloaded, failed,
stale, unsupported, missing and closed resources return `(0, 0, false)`. Query
again after a frame processes the renderer's normal decode completion; do not
acknowledge an unavailable result as a guessed size or decode the source again.

### MyGo host theme defaults and authored variables

Embedding hosts can install per-window defaults with
`Backend.SetThemeDefaults(map[string]string)` between frames on the UI goroutine.
The map is copied and replaces previous host defaults; `nil` clears it. These
defaults do not change model-owned nodes or emit patches. Scoped `theme` props
override them only inside that subtree. Native widget semantic slots now use
the same defaults as explicit typed paint properties, including focus/status
colors. No application migration is required when host defaults are unused.

`ComputeThemeVariables(parent, declarations)` computes custom properties before
inheritance, invalidates cycles (including unused fallback references), and
handles `initial`, `inherit` and `unset`. `ResolveThemeValue(value, computed)`
substitutes nested `var()` expressions and empty fallbacks. These APIs process
declarations, not selectors, layout, utility classes or a stylesheet cascade.
Hosts must supply their authored palette and application layers explicitly.

Custom renderers can call `Backend.ResolveColor(context, value)` during their
build to use the current scoped tokens, adaptive colors and functional CSS
colors. Unknown values/cycles return an error rather than a successful default.
The existing internal fallback for unresolved standard paint values is unchanged.

Authored `font-family`, `font-size` and `line-height` now substitute `var()`
against those same scoped tokens before calling native typography APIs. This
includes nested fallbacks and adaptive values. Invalid substitutions leave the
native inherited/default typography unchanged instead of passing unresolved
expressions as font names. No host API or wire changes are required.

MyGo also accepts `em` typography lengths on the existing native 16-DIP baseline,
matching its `rem` handling and the OCaml native text adapter. These units are
not browser-style ancestor-relative computed lengths. Unitless `line-height`
remains a font-size multiplier; `px`, `em` and `rem` line heights are fixed DIPs.

### MyGo document input capture

Hosts can install `ui.Context.CaptureInput` once per view build and resolve its
opaque target with `Backend.InputNode`. This matches the actual committed focus
or hit ancestry, including internal children of standard controls and extension
elements registered with `BindHostElement`; it never infers targets from boxes.
The resulting `InputNode.Node` is a snapshot. Check `InputNode.Current()` before
using a saved press or deferred event: removing and remounting the same numeric
node ID invalidates it. Use only on the UI thread. The MyGo target itself expires
as soon as its capture callback returns.

This API needs MyGo's public `CaptureInput`/`InputTarget.Distance` API. Hosts must
update that dependency alongside this change. Existing element input callbacks
continue to run unless capture returns true. Observational capture must return
false so focused controls retain editing, IME, clipboard and native menu commands.
Do not also forward the same DOM event from a local extension handler: dispatch
once through the application's existing document capture/bubble implementation.

The pinned MyGo also reports one capture-only `InputClick` on ordinary live hits
without native gestures, such as a `column` or a bound raw `ui.Box`. The same
committed hit incarnation must remain enabled and hit-testable through release;
a drag, prevented down/up, window blur, removed capture or retired hit cancels
the candidate. Native buttons retain their existing activation/default rules.
Hosts that synthesized clicks for plain nodes or attached placeholder `OnClick`
handlers solely for document delegation must remove those workarounds. Keep one
`CaptureInput` -> `Backend.InputNode` -> document dispatch route; do not add native
press/focus semantics to ordinary content just to observe its click. Embedding
root modules must select the adapter's updated MyGo replacement as well.

The pinned MyGo also keeps built-in inspector input private to developer tools.
Application `CaptureInput` no longer observes inspector-focused key down/up,
text, composition or commands, or pointer/scroll hits in the committed inspector
subtree. A press on an inspector control stays isolated when moving or releasing
outside the panel. Inspector native controls still receive their input even if
application capture would prevent it; application targets retain their normal
capture and default-prevention behavior. Remove host-side forwarding of inspector
input to document shortcuts; do not install application handlers on the inspector
to work around this boundary. No LUI wire schema or host callback change is needed.
As Go does not inherit replacements, embedding applications must update their
root `go.mod` along with this adapter, for example:

```go
replace github.com/egoist/mygo => github.com/logseq/mygo v0.0.0-20261026012209-183f6afcb33a
```

### MyGo committed menu owners and scroll observation

`Backend.OpenMenuOwners(c)` returns unique, ID-sorted `InputNode` snapshots for
actual still-open native menus, retained context menus, dropdowns and popovers.
Call after final layout (for example in `AfterFrame`) or between frames on the
UI thread. An `AfterFrame` callback may be registered before `Backend.View`;
reading committed ownership does not depend on text-record callback ordering.
Only actual presentation builders register candidates; the query
checks native active/committed-pending presentation state or retained dismissal
state plus committed panel and owner identities. It does not scan the retained
tree, infer opening from widget existence, measure bounds, or change input.
Probes, omitted panels, hidden/inert/disabled owners, closed presentations and
retired incarnations do not resolve. Before a changed model has committed, the
query returns no owners rather than mixing model and presentation generations.

Native/context menus report their host. Dropdowns report the actual trigger or
placement anchor; a popover's `anchor-target` resolves outside its portal too.
A coordinate-only popup has no retained external anchor, so its own retained
popup node is the presentation owner. Supply a real `anchor-target` when a host
must protect a triggering row; coordinates never imply that row's identity.
Do not retain the result as an open-state cache: query each committed frame and
check `InputNode.Current()` before using a saved snapshot. Same-ID recreation
does not revive an earlier incarnation. Protect only the returned owners and
their actual retained ancestors, not every menu/widget node or the whole tree:

```go
c.AfterFrame(func() {
    for _, owner := range backend.OpenMenuOwners(c) {
        if owner.Current() {
            pinRetainedAncestors(owner.Node.ID)
        }
    }
})
```

`Backend.CommittedScrollOffset(c, id)` returns `(x, y float32, known bool)` for
any actual committed scroll host, including a normal `box` with `overflow:auto`.
It reads MyGo's public `Handle.ScrollOffset(c)`, not private engine state or
geometry differences. Call after layout on the UI thread. Non-scrollers,
probes, hidden, missing, stale and uncommitted hosts report `known == false`;
zero with `known == true` is a real scroll start. The axes match `ScrollState`.
Do not infer scroll end from an unknown value:

```go
if x, y, known := backend.CommittedScrollOffset(c, containerID); known {
    observeCommittedOffset(containerID, x, y)
}
```

The older `Backend.ScrollOffset(id)` still reads retained typed scroll state,
including an unapplied `ScrollTo`; its errors and all scroll command/token
semantics are unchanged. Migrate viewport observations to the new committed
query, but do not replace command handling. These APIs need the adapter's new
MyGo pin (`Context.NativeMenuOpen` and `Handle.ScrollOffset`); embedding root
modules must update their replacement too, since Go does not inherit it. No
LUI wire schema, default input or event forwarding changes are required.

The same MyGo pin finalizes Handle identity only after actual committed layout,
including deferred `view-that-fits` and virtual rows. Hosts can read public
`Bounds`/`FocusWithin` from `AfterFrame` without replaying input or focus, eagerly
building rejected candidates, or fabricating geometry. Omitted bindings and
same-ID recreated owners cannot keep an old committed identity alive.

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

The business data source and its key index remain complete. On Web, MyGo,
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

Custom hosts must recognize the new `MyGoHost` case when matching
`host_kind`. Existing host cases keep their order; native host code 5 selects
MyGo. The MyGo loader selects that profile only if the optional
`lui_ocaml_virtual_window(node,generation,first,last,pins,count)` export exists;
older application libraries keep the Generic eager profile.

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
MyGo, SwiftUI and Kotlin profiles and false for Generic. The override is fixed
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

### Large-batch memory and handle ownership

The shared OCaml encoder and MyGo decoder now process large batches without
retaining per-operation JSON copies. MyGo applies JSON operations directly in
its rollback journal instead of retaining a complete operation array, and the
native receiver reads its owned wire string without another full byte copy.
Duplicate fields, final generation checks and complete-document validation
retain their existing atomic semantics. Wire bytes, integer precision and
application APIs are unchanged. Rebuild application libraries to include the
encoder improvement.

MyGo also releases abandoned handle bindings while preserving live hidden
handles and pending focus. Embedded Go applications must update their root
replacement to `github.com/logseq/mygo@v0.0.0-20261025230925-e952b021e9be`, as shown
in the [embedding guide](../platform/mygo/README.md#embed-a-backend). The upstream
module path and application imports remain unchanged.

### Nested toolbar focus ownership

On Web, a toolbar owns one keyboard Tab stop across its nested button and toggle
groups. Group refreshes no longer create additional stops after model updates;
arrow navigation continues through the complete toolbar sequence. Standalone
groups retain their own roving focus behavior. Applications need no source change.

### Toast keyboard dismissal

On Web, Escape now dismisses the open toast containing keyboard focus, matching
MyGo. Escape outside a toast, during IME composition, or after another handler
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
default. Removing both restores the default. The MyGo default overscan is five
rows on either side; the fallback item estimate is 32 logical pixels.

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

### Controlled proposals require model acknowledgement

MyGo controls now reconcile after each input callback, including callbacks that
produce no patch. If an application leaves `text`, `value`, `checked`, `selected`
or expansion state unchanged, its proposal is rejected and the control restores
that value. Accepted or normalized model values become the next displayed value.
Caret, focus and active IME composition remain host-owned.

Applications that previously relied on a no-op callback to keep a toolkit edit
must store the proposal in their model and bind the corresponding property.
For example, use `~on_input:(on_input send (fun text -> SetText text))` together
with `~text:(reactive Model.text model)` rather than a no-op input callback.

### MyGo validates complete final node contracts

MyGo now follows canonical LUI per-kind property and child rules, including
required labels, finite values, paired anchors, complete image crop regions,
consistent size/range constraints and exclusive split sizing modes. Validation
occurs against the final batch state, so property order and temporary
incompleteness inside a batch remain valid. Rejected batches preserve the live
tree and control identity.

Custom wire producers must fix invalid batches previously accepted by the
MyGo adapter. Examples: a button needs nonempty text or an accessibility label;
a table contains rows and each row contains cells; a text field may host a
context menu but cannot contain arbitrary controls; a split cannot set both
`value` and `first-pane-width`. Public constructors continue to supply the
appropriate interaction flags. Their validation now matches canonical event
support for text, numeric and toggle controls.

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

### MyGo image and media ownership

The Go host registers ordinary pixels with `RegisterImage` and video frames
with `PresentMediaSurfaceFrame`. IDs must be positive and pixels non-nil. Both
methods copy caller buffers before publication. Calls belong to the UI
goroutine. Invalid replacements preserve the previous valid resource;
`UnregisterImage` and `UnregisterMediaSurface` retire it. Standard image and
media nodes no longer need application renderer registrations.

### MyGo compatibility module and custom icons

The desktop adapter pins the [logseq/mygo compatibility fork](https://github.com/logseq/mygo/tree/lui-bounded-virtual-rows)
for measured fitting, tunable lists, frame completion and native lifecycle
behavior. The fork preserves the upstream `github.com/egoist/mygo` module path,
Go imports and upstream documentation links. Existing Go and OCaml application
imports are unchanged.

The adapter selects the immutable fork version with a Go `replace` directive.
Go does not inherit dependency replacements: applications embedding this adapter
must copy its MyGo replacement into their own root `go.mod`. See the exact
[embedding commands](../platform/mygo/README.md#embed-a-backend). No vendored
source checkout is required.

Canonical icons remain built in. Custom `app:slug` icons use
`RegisterIcon(name,svg)` and `UnregisterIcon(name)`. Registration copies and parses
SVG data; invalid replacements preserve the previous icon. These are host
resource APIs and do not require a component renderer override.

### MyGo host disposal and file services

Go hosts must call `Backend.Close()` on the UI goroutine after closing their
OCaml `Runtime` session. Closing is idempotent. Committed node removal and
snapshots cancel node-owned asynchronous work immediately; failed batches do
not cancel live work. Host-registered image/media IDs survive snapshots and
are released by explicit unregister calls or backend closure.

The optional `Config.FileServices` interface replaces only the operating-system
file dialog boundary; the default implementation uses MyGo native dialogs.
Standard picker and preview nodes need no application renderers. Picker request
and completion tokens keep their original string/integer type and exact value;
applications acknowledge a result by setting `completion` to its request token.
Tokens already acknowledged on mount do not launch another dialog.

Desktop file previews are owned LUI presentations with dismissal, selectable
UTF-8 text, raster images and paginated PDF rendering. They do not launch an
external application. Unsupported or missing files show an owned error view.
Native macOS dialog cancellation has been verified against a real NSOpenPanel.
Other host live-service qualification remains tracked in the support inventory.

### Complete native event payloads

The MyGo bridge now carries pointer details, navigation keys, scroll completion,
visible ranges, scroll edges and picker payloads through the actual OCaml event
subscriptions. Strings preserve UTF-8 and embedded NULs; integers preserve values
above JavaScript's exact-number range. Invalid coordinates, modifier/button
values, ranges and native integer/length overflows are rejected before native
entry.

Existing C-string pointer exports remain available to existing hosts. New
length-carrying `lui_ocaml_*_utf8` pointer exports carry `target_class` without
truncation. Custom native bridge loaders targeting the new MyGo host must link
the matching rebuilt application library rather than an older cached binary.

## PR #271: removed line-break component

The `br` component, OCaml constructor and standard wire kind were removed.
Replace separate-line content with a `column`, or use a newline inside one text
value when it belongs to the same text run. Do not register a custom standard
`br` renderer: it does not restore a removed protocol kind. Raw HTML extensions
keep their independent HTML element rules.

## MyGo production host services

Desktop adapters can use `Backend.Bounds`, `RequestFocus`, `ScrollTo` and
`ScrollOffset` on the UI thread instead of relying on demo-only geometry hooks
or inspecting backend state. `Bounds(c, id)` reports window DIPs from committed
layout, with `false` for missing, hidden, unmounted or closed nodes. Measure
after a committed frame; do not treat unavailable geometry as a zero rectangle.

`RequestFocus(id)` requests focus for the current retained node, including before
its first render. It is not a focus acknowledgement. Unknown or dropped nodes
are errors; requests do not survive drop/recreation or a replacement snapshot.
`ScrollTo(id, x, y)` accepts finite DIPs on scroll/list/virtual-list nodes and
clamps to the content at layout. It rejects an active token-controlled scroll;
replace those requests through the standard scroll-token protocol instead.

Extensions and custom renderers opt into host services by binding their primary
control during rendering:

```go
element := ui.Box(c).Focusable()
if err := backend.BindHostElement(node.ID, element); err != nil {
    // Propagate this adapter error; do not claim a focus or geometry result.
    panic(err)
}
```

Standard nodes are already bound. Existing extension renderer signatures and
wire schemas do not change. No model-controlled text/selection is mutated by
these services; editors must obtain source and selection from their model.

## MyGo committed text geometry

`Backend.TextGeometry(context, nodeID)` exposes the retained text actually
painted by MyGo, including a text node's range in a rich inline paragraph.
Use it after layout (`Context.AfterFrame`) or between frames on the UI thread.
It returns `(ui.CommittedText, bool)`: missing, hidden, unmounted, closed or
patched-but-not-committed nodes report false. The value expires at the next
MyGo build; every query then reports false. Do not retain it across builds.

`Text`, `Caret`, `SelectionRects`, `IndexAt` and `Lines` use rune offsets
relative to the bound text node, and window-space DIPs including scrolling
and transforms. Applications with UTF-8 byte or UTF-16 model offsets must
convert at their own boundary, and map atomic/decorative runs explicitly.
The API never shapes a second approximation or owns an editable document.
Requires MyGo's public `Handle.TextGeometry` / `CommittedText` API.
`Backend.CommittedBounds(context, nodeID)` follows the same generation guard
and reports the transformed window-space box for non-text container origins.

## MyGo live native-input snapshots

`Backend.InputTextSnapshot(context, nodeID)` returns `(text, anchor, caret, ok)`
from the actual native TextInput/TextArea edit state. Unlike committed geometry,
it includes already-consumed edits before the next layout/bound-value update.
It does not process queued input, mutate selection, or cache model text. Text
excludes marked/preedit content; anchor/caret count runes, retain direction,
and must be converted explicitly for UTF-8/UTF-16 application protocols.
This trusted host query also reads secure-field text without redaction.

The window-stable `ui.Context` may be retained for this specific UI-thread query
in `CaptureInput` before default handling or `OnChange` after input. This does
not make build APIs or retained `ui.Element` queries safe in callbacks.
Requires MyGo's public `Handle.TextSnapshot` API; no wire schema changes.

```go
if text, anchor, caret, ok := backend.InputTextSnapshot(windowContext, nodeID); ok {
    dispatchInputSnapshot(text, anchor, caret)
}
```

Standard native fields are bound automatically. A raw/custom renderer must call
`backend.BindHostElement(node.ID, input)` on its actual native input each build,
before registering handlers; do not bind an enclosing box or a substitute buffer.
Unavailable, hidden, disabled, retired, remounted-before-commit, non-input and
closed nodes report `ok=false`. There is no stale-model fallback. Ordinary patch
generation changes do not invalidate this live query; drop/recreate and snapshot
replacement retire the binding immediately. Re-render to bind the new incarnation.

## Upgrade checks for application maintainers

1. Update generated wire schemas and custom host decoders together with LUI.
2. Replace uses of `br` and invalid retained child shapes.
3. Prefer typed virtual-list arguments; test any legacy attribute overrides.
4. Review disabled editors that should allow copying.
5. Exercise model rejection/normalization, keyboard navigation, resource
   replacement and stale async callbacks on each host the application ships.

The existing DOM backend remains available. MyGo's browser renderer requires a
separate browser runtime bridge; the desktop dynamic-library bridge cannot be
used directly in a browser.
