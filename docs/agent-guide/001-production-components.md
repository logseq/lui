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

### Picker contract

The first picker slice uses four semantic retained elements and keeps their
composition explicit:

- `select` is a leaf trigger with `text`, `placeholder`, `disabled`,
  `on-press`, and `on-dismiss`;
- `combobox` is an editable leaf with `text`, `placeholder`, `disabled`,
  `on-input`, `on-submit`, `on-press`, and `on-dismiss`;
- `dropdown-menu` is a sibling of its trigger inside `stack`. It accepts
  `anchor` (`above` or `below`), `anchor-alignment` (`start`, `center`, `end`,
  or `stretch`), floating-point `anchor-offset`, admitted common size props,
  and `on-dismiss`;
- `menu-item` is a text-bearing leaf with `icon`, `selected`, `disabled`, and
  `on-press`.

The application owns selected value, combobox query, and open menu identity as
Signals. A menu is mounted with `:if` only while open, so dismissal disposes
that dynamic segment without replacing the trigger or unrelated siblings.
Selected value and host-owned keyboard highlight are separate state: a native
focus move does not commit model selection until activation.

Web uses retained native DOM controls, Tailwind component selectors, anchored
positioning, Escape handling, and outside-pointer dismissal. Flutter uses
Material controls plus a composited `OverlayPortal`; the stack keeps one stable
widget shape while the portal is shown or hidden, preserving the trigger and
text controller identities. Apple uses SwiftUI controls and material menu
surfaces in the same retained node model. Platform-native focus, animation,
menu tracking, and input composition remain backend-owned.

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

### Tabs contract

`tabs` is the reference's horizontal TabsList container, not a page-content
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
Button children to `tab` semantics. SwiftUI and Flutter use retained native
Button controls with platform tab-strip presentation and selected semantics.
Enter or Space activates the focused trigger through the Button's normal
platform behavior. Like the pinned reference, Tabs adds no separate arrow-key
selection protocol or runtime-owned mutual exclusion.

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
- dialog, drawer, sheet, resizable and split;
- native platform presentation, dismissal, focus restoration and drag behavior.

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
