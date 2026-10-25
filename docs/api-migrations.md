# LUI API migration guide

This guide records changes applications must consider when updating LUI.
Keep it alongside the implementation: every public constructor, wire contract,
default, event or compatibility change must receive an entry before release.
Changes below are unreleased work following PR #271; host qualification is
tracked in [the MyGo parity plan](agent-guide/004-component-api-mygo-parity.md).

The Native OCaml renderer is outside this parity update. Its paint-property
inventory check is temporarily deferred until that inventory recognizes
`read-only`, `overscan` and `item-extent`; these features are not qualified on
that renderer. The MyGo, Web, Apple, Android and shared ABI regressions remain
covered separately.

## Unreleased: component API and MyGo parity

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

The desktop adapter pins the [logseq/mygo compatibility fork](https://github.com/logseq/mygo/tree/lui-component-parity)
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
