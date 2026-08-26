# Production cross-platform UI and component showcase

Status: active design and delivery plan

## Outcome

LUI becomes a production-grade retained, incremental UI runtime for Web,
Apple platforms through one SwiftUI backend, and Flutter platforms. A small
showcase in `examples/` demonstrates the complete public component catalog and
platform behavior without becoming a separate complex application.

The supported public UI component API is a deliberate subset of Vercel
Native's UI API. Within that subset, LG changes only the notation and Signal
supplies reactivity; LUI does not invent a second component vocabulary.
Rich-text `span`, `code`, `markdown`, and charting (`chart`/`series`) are
intentionally excluded. The pinned source, exclusions, and exact parity rules
live in
`001-production-components_vercel_native_matrix.md`. The source-level runtime,
backend and Web research behind the implementation strategy lives in
`001-production-components_vercel_native_architecture_report.md`.
Base UI motion, keyboard, pointer, touch, and popup lifecycle contracts for the
Web backend are pinned in
`001-production-components_base-ui_report.md`; implementation must follow that
report before visual tuning.

## Non-negotiable API boundary

- Element names, attributes, defaults, legal values, events and structural
  constraints match the pinned Vercel Native API.
- LG data forms replace Vercel Native markup mechanically.
- Signal sources replace model bindings without changing the property name.
- Invalid or meaningless attributes fail with a useful error.
- No LUI convenience aliases, compound parts or Web breakpoint props are added
  to standard components.
- Provisional LUI APIs may be broken to reach parity; compatibility aliases are
  not kept.
- `span`, `code`, `markdown`, `chart`, and `series` are out of scope; `text`
  remains a plain-text leaf and LUI does not own rich-text or chart rendering
  pipelines.

For example:

```clojure
[:column {:gap 12 :cross "stretch"}
 [:text {:size "heading"} "Account"]
 [:text-field {:placeholder "Email" :on-input set-email}]
 [:row {:gap 8 :main "end"}
  [:button {:variant "primary" :on-press save} "Save"]]]
```

## Runtime architecture

LG owns the declarative tree and component composition. Signal tracks precise
dependencies. The runtime retains typed nodes and emits typed incremental
patches. Each backend preserves platform object identity and changes only the
affected property or child relationship.

There is no JSON-shaped application VDOM and no full-component rerender step.
JSON is only a serialized form of the closed native patch protocol at process
or FFI boundaries.

```text
LG data + Signal
       |
typed retained operations
       |
shared retained tree
       |
Web DOM | SwiftUI model | Flutter model
```

Signal computations may depend on multiple Signals and other computed Signals.
Only consumers of a changed result are scheduled. Backends update retained
platform nodes rather than rebuilding an enclosing component tree.

Structural reactivity uses declaration-ordered dynamic segments. `:if`,
`switch!`, and `:keyed` own only their local child range inside an existing
parent; they do not add wrapper or placeholder nodes. When an earlier segment
grows or shrinks, the runtime adjusts the physical base of every later segment
under that parent. This keeps static siblings and independent dynamic regions
in declaration order while preserving retained identities outside the changed
segment.

`[:if {:test visible-signal} child]` is the LG conditional form. It requires
one `Signal<bool>` and exactly one child. A false branch allocates no retained
node; a true-to-false transition disposes the branch scope, handlers and
subtree before releasing its segment.

## Platform strategy

### Web

LUI renders native DOM directly and does not depend on React. Tailwind is the
primary styling implementation. Component source contains semantic class names,
not long Tailwind utility strings; Tailwind compiles those classes into the
production stylesheet.

Web should use browser primitives and platform APIs before implementing custom
behavior. Headless behavior is implemented only where the Vercel Native
contract requires it and the browser does not provide it.

### Apple

LUI maintains one Apple backend implemented with SwiftUI. It uses SwiftUI
controls, layouts and presentation APIs directly. UIKit and AppKit may appear
behind SwiftUI or inside the framework, but they are not separate public
renderers and do not create a second backend to maintain.

### Flutter

LUI maps the shared contract to existing Flutter widgets and Material platform
APIs. It composes widgets before adding custom render objects.

## Platform-specific tweaks

The standard component API remains identical on every platform. Differences
are expressed through:

1. `platform` and `host` branches around a subtree;
2. design token overrides scoped to an OS or host;
3. a documented platform style escape hatch for capabilities such as Web CSS
   classes that are not component props.

A tweak cannot change the semantic component type, controlled state contract or
accessibility meaning. Backend-specific props are not admitted to the standard
component map.

## Component admission

A Vercel Native element becomes a distinct retained protocol kind when it needs
a distinct native widget, semantics, event contract, transient state or
lifecycle. Pure visual composition may reuse lower primitives internally, but
the public element and validation still match the reference.

Examples:

- `row` and `column` map to native flow layouts.
- `grid` is a distinct contract because `columns` and grid semantics belong
  only to it.
- `button`, text entry, selection controls, scroll regions, menus and dialogs
  preserve native transient state.
- `badge` and `skeleton` can be composed if doing so preserves the complete
  public and accessibility contract.

### Shared semantics, native interaction

Cross-platform reuse stops at the semantic boundary. LG/LUI owns the public
component API, controlled Signal state, validation, retained identity and typed
events. It does not force every host to reproduce Web interaction from shared
layout primitives.

- Presentation composites such as Badge and Card may be implemented entirely
  from LUI primitives.
- Interactive composites such as Select, Dialog, Menu and Combobox remain
  semantic retained nodes.
- SwiftUI and Flutter map those nodes to their platform presentation and
  control APIs whenever the public contract permits it.
- Web may combine native HTML APIs with reusable LUI behavior primitives for
  focus, selection, positioning, typeahead and dismissal.
- Host-owned transient state includes focus traversal, gestures, animation,
  menu tracking and interactive dismissal. Controlled values and visibility
  still flow back through typed events to the shared Signal model.

The consistency target is API, data state, accessibility meaning and core
behavior. Platform-native gestures, transitions and focus conventions should
remain native rather than becoming pixel-identical cross-platform emulations.

## Layout contract

The foundation follows Vercel Native rather than CSS vocabulary:

- `row`, `column`, and `list`: `gap`, `main`, `cross` plus admitted common
  layout attrs;
- `grid`: `columns` and `gap`;
- `stack`, `panel` and `card`: overlay containers where `gap` is invalid;
- `scroll`: one scrolling content box; direct children share that box and
  overlay, so flowing content uses an explicit `list` or `column` child;
- `grow`, `padding`, `width`, `height`, `min-width`, and `max-width` retain the
  same meaning and defaults as the reference.

There is no public `flex`, `grid/col`, `aspect-ratio`, breakpoint-column or
column-span component API. Web responsiveness is external style policy, not
wire protocol vocabulary.

Delivered parity slices:

- one shared component-gallery model, reducer, and Signal view under
  `examples/components/lg`; Web and Flutter hosts reuse it without duplicating
  application state, and the Flutter integration test crosses the real OCaml
  FFI boundary;
- one real Android emulator qualification path builds the shared OCaml/JNI
  library and Flutter APK, installs it, and drives adaptive navigation, touch
  disclosure, retained English and Chinese IME input, recursive menus, native
  Dialog, Sheet, Tooltip long press, Select, Combobox, Checkbox, Switch, Toggle,
  RadioGroup, and Slider interaction through Maestro; stable destination
  identifiers belong to the complete Material navigation item so accessibility
  automation does not depend on merged implementation children;
- one pinned Base UI Web interaction and motion report plus a first mobile
  parity slice: Dialog and Sheet expose enter/exit state attributes and retain
  inert visual shells through CSS transitions, compact Sheet becomes a
  safe-area-aware bottom surface with pointer-identity downward dismissal,
  Context Menu follows the 500 ms/10 px touch long-press contract, and Toast
  uses Pointer Events without stealing gestures from interactive descendants;
  DropdownMenu, Select, Combobox, and Tooltip share the same popup phase
  helpers, retain an inert visual shell through exit, expose 500 ms menu
  typeahead, and reject touch-only Tooltip hover; real-browser E2E covers each
  behavior;
- placeholder-free retained `:if` plus declaration-ordered dynamic segments;
  interleaved static children, switch branches, keyed collections and multiple
  dynamic regions preserve their local ordering and disposal boundaries;
- `row`, `column`, and `grid`, including `main`, `cross`, `grow`, `columns`,
  and `gap` validation;
- direct retained `stack`, `panel`, and `card` overlay nodes on Web, SwiftUI,
  and Flutter;
- direct retained `list` flow nodes and multi-child `scroll` overlay semantics
  on Web, SwiftUI, and Flutter;
- direct retained `spinner` progress leaves with the reference 16/20/24 size
  rungs, native SwiftUI/Flutter indicators, and a reduced-motion Web renderer;
- direct retained `progress` leaves with a model-owned `float` fraction,
  render-time `0..1` clamping, and no range props or compound public parts;
- direct retained `icon` leaves with the 51-name Vercel Native built-in
  vocabulary, 16/18/24 sizing, shared foreground tint, CSS-mask SVGs on Web,
  SF Symbols on SwiftUI, and Material Icons on Flutter, plus immutable
  application-registered `app:` names on every backend;
- direct text-bearing `checkbox` and `switch` controls with model-owned
  `checked`, `disabled`, `label`, and `on-toggle`; their labels and native
  controls form one hit target and one accessibility node;
- direct retained `button` controls with the six reference variants, four
  sizes, inline registry icons, selected/autofocus state, press, 350 ms hold,
  and immediate desktop secondary hold behavior;
- direct retained `toggle-button` controls with Button-compatible variants,
  sizes and inline icons, `on-toggle` activation, optional model-owned
  `selected`, backend-owned selection when that property is absent, and the
  same hold and autofocus behavior;
- direct retained `select`, `combobox`, `dropdown-menu`, and `menu-item`
  picker primitives with model-owned value, query, and visibility Signals,
  typed press/input/submit/dismiss events, anchored native presentation, and
  identity-preserving conditional menu insertion and removal;
- direct retained `tooltip` text leaves with static and runtime-owned anchored
  modes, native focus/hover presentation, delayed hover intent, and a shared
  warm window that never enters application state;
- direct retained `accordion` disclosure containers with the exact
  `text`/`selected`/`on-toggle`/`height` contract, model-owned expansion,
  retained collapsed children, and native Web, SwiftUI, and Flutter controls;
- direct retained `table`, `table-row`, and `table-cell` nodes with strict
  structural nesting, aligned columns, model-owned row selection, pressable
  cells, and identity-preserving text and selection patches;
- direct retained `tree` navigation over ordinary row nodes, with strict
  role/hierarchy metadata, one native roving focus set, model-owned selection
  and disclosure, ARIA keyboard behavior, and local Signal patches on Web,
  SwiftUI, and Flutter;
- direct retained `resizable` stacking surfaces with source-width
  reconciliation, backend-owned drag state, bounded assistive resizing, and
  identity-preserving children on Web, SwiftUI, and Flutter;
- direct retained `split` layouts with exactly two identity-preserving panes,
  a model-owned fraction, pane minimums, native animation and reduced-motion
  handling, plus pointer, keyboard, and assistive resizing on every applicable
  host;
- direct retained `list-item` rows with text-or-children content, inline
  registry icons, model-owned selection, disabled state, immediate press,
  additive double press, Enter submit, and identity-preserving Signal patches;
- stacking containers reject `gap`; `card` supplies the reference 24-point
  default content padding while explicit `padding` overrides it.

### Button contract

`button` follows the pinned Vercel Native control rather than the provisional
Solid-style implementation. Its public attributes are `text`, `variant`,
`size`, `icon`, `icon-placement`, `disabled`, `selected`, `autofocus`, `label`,
`on-press`, and `on-hold`. `icon-placement` is part of the reference schema and
renderer even though the Button page's generated attribute table omits it.

- `variant` is one of `default`, `primary`, `secondary`, `outline`, `ghost`, or
  `destructive`; `link` is not a Button variant.
- `size` is one of `sm`, `default`, `lg`, or `icon`. An icon-sized, icon-only
  button requires an explicit accessible `label`.
- `icon` uses the same built-in or `app:<name>` registry as the `icon` leaf,
  and `icon-placement` is `leading` by default or `trailing`.
- `selected` is model-owned pressed/selected state. Hover, pointer-down, focus,
  and other transient interaction state remain backend-owned.
- `autofocus` is edge-triggered: mount with true or false-to-true requests
  focus once; retaining true must not steal focus again after another update.
- A quick primary activation dispatches `on-press`. A pointer held for about
  350 ms dispatches `on-hold` and suppresses the following press. A desktop
  secondary activation dispatches hold immediately when the route has no
  context menu.
- Literal values and Signal sources share the same attribute names. A Signal
  change patches the retained Button node and never replaces its enclosing
  component or the retained node identity.

Web renders one native `button` and backend-owned inline icon content, styled
through semantic Tailwind selectors and data attributes. SwiftUI renders one
system `Button` with native label/icon composition, control sizing, focus, and
accessibility traits. Flutter uses Material button APIs and native gesture,
focus, semantics, and icon facilities. The internal event-capability bit does
not become a public LG attribute.

### ToggleButton contract

`toggle-button` follows the pinned pressed-button contract. It shares `text`,
`variant`, `size`, `icon`, `icon-placement`, `disabled`, `selected`,
`autofocus`, `label`, and `on-hold` with Button, but primary activation emits
`on-toggle` with the requested next selection instead of `on-press`.

When `selected` is present, its literal or Signal value is the model's
reconciliation channel. Native interaction updates pressed feedback
immediately and the next changed model value corrects it. When `selected` is
absent, selection is backend-owned transient state and survives unrelated
property patches without entering the retained protocol tree. Web uses one
native `button` with `aria-pressed`; SwiftUI and Flutter keep the transient
selection in the identity-preserving native view state associated with that
retained node.

### Application icon registry

The 51 bare icon names are the stable cross-platform built-in vocabulary, not
the full icon ceiling. Application-owned icons use the reference `app:<name>`
namespace and remain host resources:

- LG and the wire protocol carry only the shape-checked semantic name, for
  example `app:wave-pulse`; vector paths, asset names, and `IconData` never
  enter the retained tree;
- Web registers a bare app name to an SVG URL and applies it through the same
  CSS mask channel as built-ins;
- SwiftUI registers a bare app name to either an SF Symbol or an Asset Catalog
  image;
- Flutter registers a bare app name to `IconData`;
- an unregistered but well-shaped `app:` name renders the platform's visible
  missing-icon fallback rather than becoming an invisible gap;
- registration belongs to backend construction and is immutable while a
  retained application is running, so one property patch cannot silently
  change the resource table.

Bare names never consult the app registry and app names never shadow built-ins.
The public component API remains `[:icon {:name "app:wave-pulse"}]`; there is
no backend-specific prop or asset payload in LG.

### Checkbox and switch contract

`checkbox` and `switch` are direct, text-bearing controlled elements. Their
public API is the Vercel Native contract exactly:

- visible text is the single child string, or a reactive `:text` value;
- `:checked` is the model-owned Signal and `:on-toggle` receives the native
  checked transition;
- `:disabled` is an optional Signal;
- `:label` supplies an accessible name without drawing a second label.

The provisional Solid-style API is removed rather than aliased. There are no
public `switch/control`, `switch/thumb`, `switch/label`, description or error
parts, and no `:on-change`, `:indeterminate` or `:invalid` attributes on these
two elements.

Each element remains one retained LUI node. Backend-owned implementation
children do not enter the retained tree: Web uses a native checkbox input in a
semantic label wrapper, SwiftUI uses `Toggle` with the platform checkbox or
switch style, and Flutter composes its native `Checkbox` or `Switch` with the
label. A checked or text patch updates that retained node and must not replace
the platform control.

### Toggle, RadioGroup, Radio and Slider contract

These daily value controls preserve the pinned Vercel Native API:

- `toggle` is text-bearing and accepts `text`, `checked`, `disabled`, `label`
  and `on-toggle`;
- `radio-group` accepts the required accessible `label` and owns one logical
  group across descendant radios at any nesting depth;
- `radio` accepts `text`, either `checked` or `selected`, `disabled`, `label`,
  and the reference event fallback order `on-change`, `on-toggle`, then
  `on-press`;
- `slider` accepts the model-owned fractional `value` as `float` or
  `Signal<float>`, plus `disabled`, `label` and `on-change`; rendered values
  are clamped to `0..1` without changing the model-owned source.

Radio activation emits `on-change` only for a new selection. Activating an
already selected radio may still reach the legacy toggle or press fallback.
Web radios share one native input name per retained group so browser focus and
arrow navigation remain native. Flutter uses `RadioGroup`, and Apple keeps the
same semantic group while rendering platform controls. Slider drag state stays
host-owned during interaction; the applied fraction returns through the typed
event pipeline and the Signal remains the reconciliation source.

### Progress contract

`progress` is one display-only retained leaf. It accepts the model-owned
`value` as `float` or `Signal<float>` and the reference `width` layout
attribute. The typed LG API uses floats for continuous values; a JSON integer
at a wire boundary is normalized once to the canonical float representation.
`min-value`, `max-value`, labels, events and public compound parts are not part
of its API. Values outside `0..1` remain unchanged in the model and are clamped
only when a backend renders the fill. Discrete indexes and counts remain
integers.

Web updates one retained progressbar DOM node and its CSS fill fraction.
SwiftUI uses `ProgressView(value:)`, and Flutter uses
`LinearProgressIndicator`; a Signal patch preserves the platform object and
does not rebuild the gallery section.

## State ownership

- Controlled values are Signal sources plus the corresponding Vercel Native
  event callback.
- Components never copy controlled state into a second model.
- Native transient state such as text composition, selection, hover, pressed
  state, scroll momentum and menu tracking stays in the backend.
- `key` is sibling-scoped identity; `global-key` survives reparenting.
- Collection reconciliation is keyed and incremental.

## Accessibility and input

Accessibility is part of each component contract, not an optional layer.
Interactive controls require an accessible name under the same rules as the
reference. Keyboard navigation, focus order, roving focus, Escape handling,
outside dismissal and platform accessibility actions are implemented with the
component wave that introduces them.

Pointer, mouse, touch, keyboard, IME, clipboard, drag and accessibility actions
enter the same typed event pipeline. Platform gestures remain native when the
public contract does not require app-owned state.

## Text sizing

Text entry is four direct retained leaves: `text-field`, `input`,
`search-field`, and `textarea`. Their shared public attributes are `text`,
`placeholder`, `disabled`, `autofocus`, `label`, `on-input`, and `on-submit`.
`textarea` additionally admits `submit-on-enter`. There are no compound parts,
relationship IDs, input-type aliases, or line-count props.

`on-input` carries the current text and `on-submit` is a separate typed event.
Single-line controls submit on Enter. A default textarea inserts a newline and
submits on the platform primary modifier plus Enter; `submit-on-enter` changes
the common Enter path to submit while Shift+Enter retains newline entry.

Multiline `textarea` grows to its content until constrained by admitted layout
bounds. Auto-sizing is an implementation behavior, not an extra `autoresize`
prop. Web uses native `field-sizing: content`, SwiftUI uses vertical-axis native
text layout, and Flutter uses an unbounded native multiline `TextField`. Signal
text patches preserve the DOM element, SwiftUI model, Flutter controller,
selection, focus, and IME-owned transient state.

### InputGroup contract

`input-group` is the reference composer shape, not a general-purpose layout
container. Its complete public API is `label`, `width`, `height`, `min-width`,
and `grow`. It contains exactly one direct `textarea` as its first child,
followed by at most one direct `input-group-actions`; no other direct children
are legal. The textarea keeps the ordinary LUI text-entry contract, including
Signal-backed text, placeholder, input and submit events, autofocus,
`submit-on-enter`, auto-resize, focus, and selection state.

The group owns one border, background, corner radius, and focus ring for the
whole composer. The nested textarea's default chrome dissolves so it reads as
part of that field, but its editable platform control and retained node identity
remain intact. Focus on the textarea or any accessory control activates the
group's focus-within presentation. Explicit group height is absorbed by the
textarea rather than becoming empty space below the actions.

`input-group-actions` is legal only as the optional second InputGroup child. Its
complete public API is `gap`, defaulting to 6. It is a horizontal accessory row
whose ordinary element children keep their own closed APIs and events; authors
use `spacer` to separate leading actions from trailing submission controls.
Dynamic and keyed children remain ordinary LG retained structure.

Web uses a semantic group and CSS `:focus-within` around the native textarea.
SwiftUI composes the retained text editor and accessory row inside one native
rounded field, and Flutter composes the retained `TextField` and action row
inside one Material input surface. Text changes patch only the existing
textarea node, action swaps patch only the actions segment, and focus chrome is
backend-owned transient state: none of these updates rebuild the InputGroup or
application component.

### Picker contract

The first picker slice uses four semantic retained elements and keeps their
composition explicit:

- `select` is a leaf trigger with `text`, `placeholder`, `disabled`,
  `on-press`, and `on-dismiss`;
- `combobox` is an editable leaf with `text`, `placeholder`, `disabled`,
  `on-input`, `on-submit`, `on-press`, and `on-dismiss`;
- `dropdown-menu` is a sibling of its trigger inside `stack`. It accepts
  `anchor` (`above`, `below`, `left`, or `right`), `anchor-alignment` (`start`, `center`, `end`,
  or `stretch`), floating-point `anchor-offset`, admitted common size props,
  and `on-dismiss`;
- `menu-item` is a text-bearing row with `icon`, `selected`, `disabled`, and
  `on-press`. Instead of an action it may retain one nested `dropdown-menu`;
  nesting is recursive and remains ordinary retained structure.

The application owns selected value, combobox query, and open menu identity as
Signals. A menu is mounted with `:if` only while open, so dismissal disposes
that dynamic segment without replacing the trigger or unrelated siblings.
Selected value and host-owned keyboard highlight are separate state: a native
focus move does not commit model selection until activation.

Web uses retained native DOM controls, Tailwind component selectors, the shared
Base UI-aligned portal, collision handling, keyboard traversal, and pointer
corridors for nested menus. Flutter keeps one stable `MenuAnchor` around the
trigger before and after the model mounts its menu, and maps nested rows to
Material `SubmenuButton`; Material owns overlay placement, focus traversal,
animation, collision handling, and outside dismissal. Apple keeps an equally
stable SwiftUI host. Select and action menus use a native popover, while the
editable Combobox uses a small SwiftUI `Layout` overlay because presenting a
popover resigns the iPhone text field and breaks IME composition. That platform
tweak stays inside the same retained host and changes only the menu child, so
typing never remounts the trigger. SwiftUI `Menu` owns recursive submenu
interaction. Application Signals still own selected value, query, and whether
the retained menu subtree exists on every platform.

### ListItem contract

`list-item` is one semantic retained row, not a styled Card. Its public API is
the pinned reference shape: `text`, `icon`, `selected`, `disabled`,
`on-press`, `on-double-press`, and `on-submit`, plus admitted common layout and
style props. Content is exactly one of:

- a string child or reactive `text` Signal; or
- retained element children for a custom row layout.

Empty rows and rows that mix text with element children are rejected at the
atomic batch boundary. `selected` remains application-owned state; focus,
hover, pointer capture, and click cadence remain backend-owned.

A single pointer release dispatches `on-press` immediately. A second release
within the platform double-click window dispatches its own `on-press` and then
adds `on-double-press`; the first click is never delayed while the backend
waits to disambiguate it. Space dispatches `on-press`. Enter dispatches
`on-submit` when present and otherwise retains the ordinary press behavior.

Web uses one retained native button row, native click/double-click ordering,
and Tailwind component selectors. SwiftUI uses a native Button row with an
additive simultaneous double-tap gesture and return-key handling. Flutter
keeps a native Material `ListTile` and uses a small pointer-release adapter
only for the reference's immediate-plus-additive click contract. All three
retain the row and its custom child subtree when a selection Signal changes.

### Avatar and registered-image contract

`avatar` is a display-only retained leaf. Its exact public component API is
initials text, `image`, `source-x`, `source-y`, `source-width`,
`source-height`, and `label`. It deliberately has no URL, loading, error,
shape, or size prop. The reference's fixed house geometry and circular cover
crop remain backend presentation details.

`image` accepts a Signal whose non-negative integer value is a model-owned
`ImageId`; literals are rejected because the resource may become available
after the view is mounted. `0` is the no-image sentinel. A zero or currently
unregistered id renders the initials fallback without changing node identity.
Registering or unregistering an id invalidates only Avatar nodes that reference
that id, independently of LG patch generations. The registry never becomes
application state and never owns loading policy.

The host registers an already-decoded platform image under a caller-chosen id:
Web uses a URL plus decoded pixel dimensions, SwiftUI uses `CGImage`, and
Flutter uses `dart:ui.Image`. Replacing an existing id is atomic. Unregistering
removes the registry reference and restores initials on every referencing
Avatar. Callers retain responsibility for URL/object-URL lifetime on Web and for any
external references they keep to native image objects. Flutter explicitly
releases its cloned image handles when the backend is disposed. Apple and Web
registry references follow the backend or renderer lifetime. On every
backend, `unregister` immediately removes the registry slot.

Atlas cropping is an all-or-none group. If present, all four source values
must be finite, `source-x` and `source-y` must be non-negative, and
`source-width` and `source-height` must be positive. Backends clip the source
rectangle to the decoded image bounds and draw it with cover fit inside the
same circular Avatar frame. Supplying only part of the group is rejected
atomically rather than silently drawing a different image.

### Image and media-surface contract

`image` and `media-surface` are display-only retained leaves. They accept no
children or events, have no intrinsic size, and admit the common surface
layout and style attributes so callers can size, grow, clip, and round them.
Both accept the pictorial `label`; an empty label explicitly marks decorative
content, while the authoring diagnostics warn when the label is omitted. Their
resource identifiers are model data and therefore must be Signals rather than
markup literals. Updating either Signal patches the same retained node.

`image` requires `image`, a Signal containing a non-negative model-owned
`ImageId`. It uses the same host image registry and id namespace as Avatar;
`0` or an unregistered id draws nothing. The optional `source-x`, `source-y`,
`source-width`, and `source-height` attributes select a decoded-pixel atlas
region. The crop is the same all-or-none, finite, non-negative-origin,
positive-size group as Avatar. Unlike Avatar, Image preserves the selected
pixels by stretching them into the authored frame and has no initials fallback
or fixed shape. This is the pinned reference's default ImageFit; Image adds no
fit-mode prop.

`media-surface` requires `surface`, a Signal containing a non-negative
model-owned `SurfaceId`; `0` is unbound and draws nothing. A nonzero id without
a submitted frame draws a subdued deterministic id-derived placeholder, so
snapshots do not depend on producer timing. Surface ids occupy
an independent registry from image ids. A host producer submits an already
decoded platform frame under a stable id: Web supplies a URL plus decoded
pixel dimensions, SwiftUI a `CGImage`, and Flutter a `dart:ui.Image`.
Submitting another frame atomically replaces the pending frame for that id;
native presentation consumes the latest frame and invalidates only retained
MediaSurface nodes that reference it. Unregistering the surface removes its
frame and returns those nodes to the deterministic placeholder. Submitted
frames stretch into the authored frame, matching the reference's ordinary
producer-owned surface behavior; specialized video composition may add its own
contain fitting above this primitive. The registry is a
presentation resource boundary, not application state, and the producer
retains loading, decoding, pacing, and external-resource lifetime policy.

Live frame contents are intentionally outside deterministic snapshots and
session replay. Tests and Gallery use a fixed registered frame, while
production video, camera, or renderer integrations keep one SurfaceId and
submit replacement frames without emitting LG patch batches.

### Stepper contract

`stepper` is the reference's display-only stage indicator. Its complete public
API is required `active` plus optional `label`; it accepts only direct `step`
children. `active` is a Signal containing a non-negative whole-number index.
Steps before that index are completed, the step at that index is active, and
steps after it are pending. An index equal to or greater than the child count
marks every step completed. Stepper owns no navigation event or mutable
selection state.

`step` has no attributes and contains exactly one non-empty literal label or a
single text Signal. It is legal only as a direct Stepper child. Its position is
structural identity for stage-state derivation, while the retained node id is
still preserved across an `active` patch. Inserting, moving, or removing a Step
recomputes only the affected Stepper's derived presentation and list position
metadata.

The backend presents one horizontal native row with list semantics, numbered
or completed indicators, labels, and connectors. Web uses semantic list items
and Tailwind component selectors; SwiftUI uses retained `HStack` composition;
Flutter uses retained `Row` widgets. Patching `active` updates the existing
Stepper and direct Step presentations without rebuilding their child models or
unrelated nodes.

### Timeline contract

`timeline` is the reference's display-only activity list. Its complete public
API is `gap`, `grow`, and `label`; only direct `timeline-item` children are
legal. It owns no collection model, selection rule, or events. Dynamic and
keyed items remain ordinary LG retained structure, and list semantics and
position metadata derive from the current direct-child order.

`timeline-item` is a retained leaf with required `title` and optional
`description`, `meta`, `indicator`, `icon`, `variant`, `connector`, `selected`,
and `on-press`. These names and defaults match the pinned reference:
`description`, `meta`, and `indicator` default to empty text, `variant` defaults
to `outline`, `connector` defaults to true, and `selected` defaults to false.
`icon`, when present, uses the shared closed icon vocabulary. An empty
indicator and absent icon render a small status dot. `connector` controls the
hairline below that item's indicator; callers clear it on the final item when
they do not want a trailing line. A pressable item binds one event to its root
and adds platform affordance without duplicating handlers on its text.

Web renders one semantic list-item row with Tailwind component selectors.
SwiftUI composes native labels, shapes, and Button behavior; Flutter composes
Material text, icon, and InkWell behavior. Each backend keeps the semantic
TimelineItem as one stable backend node: property Signals patch its internal
native composition in place, and selection or copy changes never reconstruct
the Timeline, sibling items, or application component.

### Tabs contract

`tabs` is the reference's oriented TabsList container, not a page-content
owner. It introduces no selection value, tab identifier, panel part or event.
Direct `button` children are presented as tab triggers; their existing
`selected` Signal and `on-press` callback remain the model-owned controlled
contract. The application composes the selected content beside the strip with
ordinary LG conditionals or keyed dynamic regions. Direct `toggle-button`
children retain toggle-button behavior and are not converted into tab
triggers.

The bare strip hugs its triggers with house spacing and chrome. An explicitly
authored `gap` or padding value wins for that field. A selected trigger changes
only that retained Button node; it does not replace the Tabs node, sibling
triggers or selected content. Web maps the strip to a `tablist` and direct
Button children to `tab` semantics. Its `label` names the tablist for assistive
technology. SwiftUI and Flutter use retained native Button controls with
platform tab-strip presentation and selected semantics. Enter or Space
activates the focused trigger through the Button's normal platform behavior.
On Web, horizontal Left and Right navigation follows computed LTR or RTL
direction; vertical Up and Down navigation follows the authored `orientation`.
Both modes wrap, skip disabled triggers, and support Home and End. Focus owns
the single roving tab stop but does not select or activate the trigger. Like
the pinned reference, Tabs adds no runtime-owned selection or mutual exclusion.

The current compact API has no retained panel relationship, so Web does not
invent `aria-controls`, activation direction, or a moving indicator from DOM
proximity. Those behaviors require an explicit panel association design before
they can be implemented without fragile implicit coupling.

### ButtonGroup and ToggleGroup contract

`button-group` and `toggle-group` are horizontal grouping containers. They
introduce no value, selected item, exclusivity rule or group event. The
application continues to bind each direct `button` or `toggle-button` through
its existing `selected` Signal and `on-press` or `on-toggle` callback. A
controlled exclusive chip row is therefore ordinary model logic; an
uncontrolled ToggleButton keeps its existing backend-owned multi-select state.

Both groups default to the pinned reference's 4px house gap and centered cross
alignment, hug their children when no main-axis alignment or width is authored,
and admit the same `gap`, `main`, `cross` and common surface attributes as the
other horizontal collection containers. An explicit supported layout value
wins for its field. `button-group` gives direct Button and ToggleButton children
the platform's grouped-action presentation. `toggle-group` keeps their normal
Button or ToggleButton presentation; its purpose is semantic grouping and
navigation, not another selection owner. Arbitrary non-control children remain
ordinary children and receive no contextual control behavior.

Direct Button and ToggleButton children in either group participate in the
reference keymap: Left and Right move focus with wrapping, while Home and End
move to the first and last eligible enabled control. Activation remains the
child's native Enter or Space behavior and does not move selection by itself.
Web exposes a labelled `group` with one roving Tab stop, preserves the latest
eligible stop across unrelated retained patches, and implements the keymap by
delegation. SwiftUI and Flutter use retained native controls plus their native
focus systems. Reparenting a retained control into or out of a group updates
only that control's contextual presentation and focus membership.

### Breadcrumb and Pagination contract

`breadcrumb` and `pagination` are retained horizontal composition containers,
not model owners. Neither introduces a value, current item, selection rule or
group event. Both accept `gap`, `main`, `cross`, the common surface attributes
and an accessibility label. They hug their children unless the caller authors
a main-axis size or alignment. Breadcrumb defaults to a 4px gap and Pagination
to a 2px gap; both center children on the cross axis. An explicitly authored
supported value wins for its field.

Breadcrumb follows the pinned reference's plain composition API: muted `text`
ancestors, muted `chevron-right` `icon` separators and an ordinary current-page
Text. Binding `on-press` directly to a Text makes that retained Text pressable;
there is no BreadcrumbItem type. Pressability is a general Text capability, so
pointer, keyboard and accessibility activation use the same callback and do not
replace the Text node. Non-pressable Text remains selectable display text.

Pagination is composed from ordinary Button children and an optional `ellipsis`
Icon. Previous and next actions are ghost Buttons with chevron icons. Page
buttons use the existing `selected` Signal and variants; the model owns the
current page and each Button dispatches its own `on-press`. Updating the current
page patches only affected Button properties and never rebuilds the Pagination
or its siblings.

Direct Button and IconButton children in either container use the pinned
reference keymap: Left and Right move focus with wrapping, while Home and End
move to the first and last eligible enabled control. LUI has no separate public
IconButton element yet, so the current public contract exercises Button
children. Breadcrumb's pressable Text participates in normal sequential focus
and native activation, but not in the reference's Button-only arrow group.
Focus movement never selects or activates a child. Web exposes labelled group
semantics with retained DOM nodes; SwiftUI and Flutter retain native controls
and their native focus objects. Reparenting updates contextual focus membership
without recreating the child.

## Showcase

All examples live under `examples/`. `examples/components/` is a component
gallery, not a product application. It contains one focused section per public
element and covers:

- default appearance;
- variants and sizes;
- disabled, checked, selected, expanded, invalid and loading states where
  applicable;
- keyboard and focus behavior;
- light/dark and platform token differences;
- reactive updates proving retained identity;
- platform-specific tweaks that do not change the standard API.

The same LG showcase source runs on Web, SwiftUI desktop/iOS, and Flutter
desktop/mobile. Host shells stay deliberately small.

The picker and ListItem sections are exercised through the real Web host and
the Flutter host across the OCaml FFI boundary. Integration checks open and
close overlays, commit selection and free-form submission, perform immediate
single selection plus additive double-click activation, and assert that the
retained Select, native text editor, and ListItem content survive their Signal
patches.

## Delivery order

Each large completed wave is committed and pushed independently.

### 1. API parity foundation

- Pin the Vercel Native reference revision.
- Maintain the complete in-scope element/attribute/default parity matrix and
  its explicit exclusions.
- Add closed schema validation so unsupported attributes cannot be ignored.
- Replace provisional Solid-style public APIs instead of aliasing them.

### 2. Retained runtime hardening

- declaration-ordered dynamic segments for placeholder-free conditionals,
  switches, and keyed insert/remove/move operations;
- deterministic lifecycle and scope disposal;
- atomic batch validation and backend failure recovery;
- precise Signal subscriptions and computed dependency propagation;
- instrumentation for nodes, patches, recomputations and frame work.

### 3. Layout and surface primitives

- `row`, `column`, `stack`, `panel`, `card`, `scroll`, `list`, `grid`;
- `gap`, `main`, `cross`, `columns`, `padding`, `grow` and size bounds;
- `text`, `separator`, `spacer`, `badge`, `skeleton`, `spinner`, `icon`;
- native mappings and the first showcase sections.

### 4. Daily controls

- `button`, `toggle-button`, `toggle`, `switch`, `checkbox`, `radio`;
- `text-field`, `input`, `search-field`, `textarea`, `combobox`, `select`;
- `slider`, `progress`, `avatar` and `list-item`;
- focus, IME, clipboard, validation semantics and auto-sizing textarea.

### 5. Collections and navigation

- `tabs`, groups, breadcrumb, pagination, table and tree;
- keyed/virtualized list behavior and grid semantics;
- roving focus and collection accessibility.

### 6. Overlays and advanced interactions

- dropdown and context menus, accordion and tooltip;
- dialog, sheet, resizable and split;
- native platform presentation, dismissal, focus restoration and drag behavior.

#### Resizable contract

`resizable` is one retained stacking surface with a backend-owned horizontal
drag edge. It is not a one-pane `split`: no resize event or model fraction is
exposed. `width` supplies the initial width and a later changed `width` value
resets the native width; unrelated retained patches preserve the user's dragged
width. `min-width` clamps both pointer and assistive resizing. The remaining
admitted attributes are the reference surface vocabulary (`grow`, height and
size bounds, padding, colors, border, radius, style class, and accessible
label). `gap`, flow alignment, selection, and application resize callbacks are
invalid. Children stack; authors put an explicit row or column inside for flow.

Web uses the browser's horizontal resize affordance and Tailwind surface
chrome. SwiftUI and Flutter keep drag width in identity-preserving native view
state keyed by the retained node. A changed source width reconciles that state;
painting, child, or sibling patches do not. Keyboard or assistive increment and
decrement resize by a platform step without creating an LG event. Every backend
clamps the width to `min-width`, retains child identity while dragging, and
disposes its gesture/focus state with the retained node.

#### Split contract

`split` is one retained horizontal two-pane container with exactly two direct
element children and one backend-owned divider. `value` is the model-owned
first-pane fraction; a non-finite or non-positive value lays out at `0.5`, and
positive values clamp to `1.0` before pane minimums are applied. `on-resize`
receives `ValueChanged` with the effective fraction after pointer drag,
keyboard adjustment, or assistive increment. Applications echo that fraction
back into the bound `value`; the backend never inserts divider state into the
LG model. `gap` is the divider hit-band width and defaults to 9 pixels. Each
pane root's `min-width` bounds the effective divider position, including the
degenerate case where the two minimums exceed available width.

The Split-specific animation vocabulary matches the pinned reference:
`resize-duration` is a non-negative millisecond duration, `resize-easing` is
`linear`, `standard`, `emphasized`, or `spring`, and `resize-origin` is the
first mounted fraction. Easing and origin are invalid without a nonzero
duration. A changed bound value snaps when duration is absent or zero; with a
duration it becomes a native animation target, emits the same effective
resize values during presentation, and snaps when the host reports reduced
motion. A direct drag cancels an active animation before applying its value.

The remaining admitted Split attributes are the reference container surface
vocabulary: `grow`, padding, colors, border, radius, width and height bounds,
style class, and accessible label. Flow alignment and selection are invalid.
Web uses a semantic separator with pointer capture, ArrowLeft/ArrowRight and
Home/End. SwiftUI uses a `DragGesture` and adjustable separator semantics;
Flutter uses a `GestureDetector`, resize cursor, and adjustable semantics.
All hosts retain both pane identities across value patches and user resizing,
and reject batches with fewer or more than two children atomically.

#### ContextMenu contract

`context-menu` is retained metadata on its direct interactive parent, not a
flow child and not a visible widget of its own. It takes no attributes. Its
children are a flat ordered list of `menu-item` and bare `separator` elements;
every menu item has exactly one text label, requires `on-press`, and may only
add `disabled`. Icons, selection, nested menus, arbitrary content, and submenu
state are invalid. A host accepts at most one direct ContextMenu. Static menus
must contain a menu item, while dynamic item segments may temporarily produce
an empty menu; in that state a secondary activation has nothing to present.

The ContextMenu attaches to the element that receives the secondary click.
Reference hit-target components are eligible directly; a normally passive
component is eligible only when an admitted interaction handler makes it a hit
target. Conditional content belongs inside the ContextMenu. Conditionally
mounting the ContextMenu itself is invalid because it changes metadata shape
instead of its item list. The deepest eligible retained host on the hit route
wins.

Web presents an anchored menu surface at the pointer, clips it to the viewport,
supports native menu keyboard traversal, and dismisses on Escape, outside
press, item selection, blur, or a newer invocation. SwiftUI uses the system
`contextMenu` presentation. Flutter uses the platform Material popup-menu path
at the secondary-click or long-press position. Disabled items and separators
preserve their declared slots. Selecting an enabled item dispatches that
retained MenuItem's existing typed `Press` event; dismissal and presentation
remain backend-owned and never enter the LG model. ContextMenu and item Signal
patches preserve the host and its visible content identities.

#### Alert, Bubble, Reactions, and StatusBar contract

`alert` and `bubble` are distinct retained surface containers. Their direct
children stack in one content box; authors use an explicit `column` or `row`
when message content should flow. Consequently `gap` is invalid on both.
Alert may carry its chrome title through `text`; Bubble must reject `text`
because that internal channel belongs exclusively to its optional Reactions
pill. Both admit the pinned common surface dimensions, padding, appearance,
variant, and accessibility label. Alert title and all descendants remain
identity-preserving under Signal patches.

`bubble` hugs its message content and caps its implicit width at 80% of the
available conversation width. The `ghost` variant is exempt from that cap,
and an explicit `width` remains authoritative. This is a layout default, not a
public alignment or sender-direction property; callers arrange incoming and
outgoing bubbles with ordinary Row/Column composition.

`reactions` is retained Bubble chrome metadata rather than a visible child or
a separately laid-out widget. A Bubble accepts at most one direct Reactions
declaration. It contains exactly one non-empty plain-text run and admits only
`text-alignment` with `start`, `center`, or `end`; `end` is the default dock.
The pill straddles the Bubble's bottom edge without changing the identity or
child indices of the message subtree. Reactions outside Bubble, nested
elements, events, keys, and layout attributes are invalid. Its literal or
Signal text lowers onto Bubble's closed internal text property at the native
wire boundary, matching the pinned reference rather than minting a public
Bubble `text` attribute.

`status-bar` is one retained plain-text leaf. It accepts exactly one literal
text child or a reactive text source, never element children. It maps to the
platform's subdued status surface and exposes text semantics; its content and
text alignment patch the same retained node. It is not a desktop window
status API and owns no application state or dismissal behavior.

#### Table contract

`table`, `table-row`, and `table-cell` are three retained semantic nodes. A
Table contains only TableRows, a TableRow contains only TableCells, and a
TableCell is a plain-text leaf. The runtime and every process-boundary backend
reject invalid nesting atomically; LG dynamic segments may still insert,
remove, and move valid rows without wrappers.

Table is a vertical collection and TableRow is a horizontal row. Cells in the
same ordinal column align across rows. `gap` applies to row cell spacing;
ordinary admitted layout bounds remain on the element where the pinned
reference allows them. TableRow owns the model-controlled `selected` state.
TableCell owns `text`, `grow`, `size`, `foreground`, `text-alignment`, and
`on-press`; `text-alignment` is `start`, `center`, or `end`. Literal values and
Signals use those same names. Typography sizes `heading` and `display` are
legal on TableCell but remain invalid on control-sized widgets.

Web uses semantic `table`/`tr`/`td` DOM with grid, row, and grid-cell
accessibility semantics. SwiftUI uses `Grid` and `GridRow`. Flutter composes
retained per-row `Table` widgets so a row or cell patch does not rebuild an
enclosing application component. The final row has no divider, selectable rows
receive a full-width highlight, and an enabled pressable cell is one keyboard
and accessibility activation target.

#### Tree contract

`tree` is one retained vertical disclosure container. It introduces no public
`tree-item` element: matching the pinned Vercel Native API, ordinary retained
descendants become rows with `role="treeitem"`. `list-item` is the normal row
surface, while layout containers such as `row` and `panel` may carry the same
role when a composite row is needed. All tree-item descendants, including rows
inside ordinary indentation wrappers, participate in one focus set owned by
their nearest Tree ancestor.

The complete Tree vocabulary is `role`, `tree-level`, `expanded`, `selected`,
`on-toggle`, `on-change`, `on-press`, `gap`, and `label`. `role` is exactly
`treeitem` for rows in this slice. `tree-level` is a positive one-based whole
number for flat sibling rows; when omitted, hierarchy derives from retained
widget nesting. `expanded` and `selected` are model-owned Signals. Expandable
rows opt into `on-toggle`; selection follows focus through `on-change` when it
is present, otherwise keyboard activation uses `on-press`. Leaf rows omit
`expanded` and `on-toggle`. A tree item, its hierarchy metadata, and its event
capabilities are invalid without a nearest Tree ancestor, and malformed batches
are rejected atomically.

Keyboard behavior follows the ARIA tree pattern. Up and Down move through
visible tree items, Home and End move to the edges, Left collapses an expanded
row or moves to its logical parent, Right expands a collapsed row or moves to
its first logical child, and Enter or Space activates the focused row. Printable
characters move focus to the next visible item whose accessible text starts
with the typed prefix; rapid characters share a 500 ms buffer and search wraps.
Disabled rows and descendants of collapsed rows are skipped. Pointer activation
does not create backend-owned selection; every selection and disclosure change
must return through LG and patch the same retained row.

Web uses `role="tree"` and `role="treeitem"` with roving `tabindex`. SwiftUI
uses one retained focus coordinator around native row content and exposes the
same tree/list accessibility semantics on macOS and iOS. Flutter uses a native
`FocusTraversalGroup` plus `Focus`/`Actions` around retained row widgets. None
of the backends creates a parallel tree model or replaces the enclosing LG
component when focus, selection, disclosure, or keyed row order changes.

#### Dialog contract

`dialog` follows the pinned Vercel Native surface contract instead of exposing
backend-specific presentation options. Its public attributes are `text`,
`width`, `height`, `padding`, and `on-dismiss`. Application state owns whether
the node exists, normally through `:if`; dismissal is an event, not an implicit
mutation of application state. Dialog children stack inside the content area,
while the title is rendered by the platform surface chrome.

Every backend presents a dialog relative to the root rather than its declaring
layout container. Web uses the native `dialog` top layer, SwiftUI uses one
declarative modal presentation path for both Apple platforms, and Flutter uses
the platform modal route/widget API. Escape or the platform back action and a
backdrop press emit one `Dismiss` event for the topmost dialog. Presentation
moves focus into the dialog, traps traversal while it is modal, and restores
the previously focused control after removal. Nested declaration must not make
ordinary parent layout or unrelated retained nodes rebuild.

#### Sheet contract

`sheet` extends the same model-owned modal contract as `dialog`. Its public
attributes are exactly `text`, `width`, `height`, `padding`, and `on-dismiss`;
it accepts neither `gap` nor backend-specific presentation options. It is
root-relative even when authored under a nested layout container, and its
children stack in one retained content box beneath platform title chrome.
Application state controls existence through `:if`; native dismissal emits
`Dismiss` once and never mutates the model directly. LUI intentionally has no
`drawer` component because that name maps to incompatible navigation and modal
patterns across Web, Apple, and Material platforms.

Each backend uses its native sheet interaction. SwiftUI uses the system
`.sheet` presentation, including platform swipe, keyboard, accessibility, and
adaptive iPhone/iPad/macOS behavior. Flutter uses the Material modal bottom
sheet route with its native drag, system-back, barrier, safe-area, and focus
behavior. Web follows Base UI's sheet/drawer popup behavior while exposing only
the portable `sheet` name. Platform adaptation must not leak additional public
attributes.

While the sheet is open, changing its title, dimensions, padding, or retained
descendants updates only that presented subtree. It must not replace stable
child controls or re-present the route. Removing the source node closes the
native presentation without emitting a second dismissal. Escape, platform
back, swipe dismissal, or backdrop press target only the topmost presented
surface and restore focus according to the host platform.

#### Tooltip contract

`tooltip` is one retained text leaf. Its complete public API is `text`,
`anchor`, `anchor-alignment`, `anchor-offset`, and `tooltip-delay`; it accepts
no children, events, or common surface attributes. `anchor` is `above` or
`below`. `anchor-alignment` is `start`, `end`, or `stretch`, and it and
`anchor-offset` are legal only beside `anchor`. `tooltip-delay` is a
non-negative whole number of milliseconds, is legal only beside `anchor`, and
defaults to 600 when omitted. An empty text run is invalid.

Without `anchor`, Tooltip is an ordinary static leaf whose existence remains
model-owned, normally through `:if`. With `anchor`, it floats against its
parent's retained frame and consumes no flow space. The backend owns all
visibility state: pointer hover reveals after the delay, keyboard focus reveals
immediately, and pointer leave, focus departure, Escape, trigger press, view
blur, or disposal hide it without sending an LG event. A shown Tooltip remains
open while the pointer crosses the anchor gap into its content.

Only a pointer-leave dismissal starts the shared 400 ms warm window. Hovering a
different Tooltip during that window reveals it immediately; focus, Escape,
press, blur, and disposal clear or leave the window cold. Changing text,
placement, offset, alignment, or delay patches the same retained Tooltip and
must neither replace the trigger nor leak a pending timer or overlay.

Web uses a semantic `role="tooltip"` DOM leaf and a document-scoped hover-intent
coordinator. SwiftUI uses one stateful presenter attached to the retained
trigger subtree and the platform popover/help accessibility path. Flutter
wraps the retained trigger subtree with its native `Tooltip` presentation and a
shared intent coordinator. Placement may auto-flip or adapt at host edges, but
the public edge preference and state boundary stay identical.

#### Accordion contract

`accordion` is one retained disclosure container. Its complete public API is
`text`, `selected`, `on-toggle`, and `height`, matching the pinned Vercel Native
contract. `text` is the required header label, `selected` is the model-owned
expanded state, and `on-toggle` receives the requested next state. Children are
the disclosure content; they stay retained while collapsed so reopening never
recreates the subtree. `height` is the sole sizing override and otherwise the
control uses its native intrinsic size. Accordion does not introduce item,
template, group, animation, or multi-selection APIs: a group is ordinary
`column` composition and one-open-at-a-time behavior belongs in the model.

Each backend keeps native disclosure semantics and controlled state. Web uses a
real button trigger linked to a retained `region` panel. Activation emits one
`ToggleChanged` event and the model's subsequent `selected` patch controls the
open state. The panel measures its content and uses the Base UI 150 ms
height-transition contract for opening and closing; reduced motion settles
synchronously. SwiftUI uses `DisclosureGroup` with a model-backed binding.
Flutter uses `ExpansionTile` with model-owned expansion and a stable retained
key. Property patches update the same native node and never remount its child
models. Collapsing hides content visually but does not remove it from LUI's
retained tree.

### 7. Media and data display

- image and media surfaces;
- stepper and timeline;
- input group and remaining reference composites.

### 8. Production qualification

- cold reproducible builds and packaged host apps;
- performance budgets and long-running mutation tests;
- accessibility audits and keyboard-only passes;
- Web browser matrix, Apple desktop/iOS and Flutter desktop/Android coverage;
- component gallery parity audit against the pinned reference.

Runtime performance is qualified separately from deterministic correctness
tests with `make test-performance`. The native retained runtime must keep these
default warm-build budgets on the reference Apple Silicon development host:

- one local text patch in a 1,000-node tree: 10 ms;
- 60 local typing patches with 10,000 retained nodes: 250 ms;
- one 1,000-item keyed reorder or middle edit: 25 ms each;
- one retained scroll background patch: 10 ms;
- 10,000 sustained local Signal mutations: 1,000 ms.

The sustained workload also requires constant retained-node pressure and one
property operation per mutation. CI or slower qualification hosts may override
an individual ceiling through the corresponding `LUI_PERF_*_MS_MAX`
environment variable; correctness and incremental-work assertions are never
disabled.

The Web gallery also has a real-browser keyboard-only qualification suite. It
covers modal focus containment and restoration, Tree disclosure and roving
focus, Select and Combobox listbox navigation, recursive menus, keyboard-opened
ContextMenu, Toolbar roving focus, Tooltip hover/focus/Escape behavior, and
Toast focus, pause, close, and swipe interactions.

The Android gallery has a real-emulator touch qualification suite over a freshly
built and installed APK. It covers adaptive drawer navigation, retained Tree
disclosure, English and Chinese IME editing, recursive Material menus, native
Dialog and bottom Sheet presentation, Tooltip long press, Select and Combobox
selection, control semantics, and direct Slider input.

Reference evidence captured on 2026-08-26 with an Apple M3 MacBook Air,
macOS 26.4, arm64, and OCaml 5.5.0:

| Workload | Result | Budget |
| --- | ---: | ---: |
| local text patch in 1,000 nodes | 0.174 ms | 10 ms |
| 60 typing patches in 10,000 nodes | 68.136 ms | 250 ms |
| keyed 1,000-item reorder | 0.878 ms | 25 ms |
| keyed 1,000-item middle edit | 0.910 ms | 25 ms |
| scroll background patch | 0.002 ms | 10 ms |
| 10,000 sustained local mutations | 13.945 ms | 1,000 ms |

## Definition of done

The goal is complete only when:

- the parity matrix has no unimplemented in-scope element or attribute and
  keeps every deliberate exclusion explicit;
- the public API contains no LUI-only standard component props;
- updates are retained and incremental on all three backends;
- the shared showcase demonstrates every component and meaningful state;
- platform-native behavior, accessibility and input are verified;
- clean builds, tests and packaging pass from a cold checkout;
- production diagnostics and performance evidence are documented.

Passing a demo or one backend test is not sufficient evidence of completion.
