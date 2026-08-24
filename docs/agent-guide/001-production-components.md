# Production component system

Status: design

## Goal

LUI should cover most daily application UI without forcing applications to
drop into platform code. Components use the retained incremental runtime and
share one LG state and behavior model across platforms. Platform backends
render native controls and may apply scoped platform tweaks.

The Web backend uses retained real DOM and native HTML controls. LUI owns its
component API, headless behaviors and visual system. It does not require a
third-party UI runtime, React, Solid or a virtual DOM. Tailwind is a pinned
build-time CSS compiler only and ships no JavaScript runtime.

## Product principles

- **Native behavior first.** Use native text editing, scrolling, focus,
  accessibility and platform presentation rather than imitating them.
- **Platform controls by default.** Web uses semantic HTML controls, Flutter
  uses Material or Cupertino widgets, and Apple platforms share one SwiftUI
  backend built from standard SwiftUI controls. LUI composes and styles those
  controls instead of replacing text editing, scrolling, focus or accessibility
  engines.
- **Useful by default, replaceable by design.** Components ship with a quiet,
  coherent visual theme, while behavior and visual parts remain separable.
- **One semantic contract.** A component may look platform-native without
  changing its LG model, events or accessibility meaning.
- **Local updates.** A property or state change invalidates only the retained
  node or behavior scope that owns it.
- **Composition over flags.** Complex components expose named parts instead of
  accumulating platform-specific boolean options.
- **Capabilities are explicit.** Unsupported native behavior is reported by a
  backend capability; it is not silently replaced with unrelated behavior.

## Visual language and tokens

The default theme is neutral and content-first. It should look intentional in
a new app without forcing Material, Cupertino or Web styling onto every host.
Platform profiles may tune density, typography metrics and presentation.

The theme contract contains semantic tokens rather than component-specific
colors:

- color: canvas, surface, elevated surface, text, muted text, border, accent,
  accent text, danger, focus ring and disabled;
- typography: body, label, caption, heading and monospace roles;
- spacing: a small integer scale used by gap, padding and control density;
- shape: small, medium and large radius plus border width;
- elevation: none, raised and overlay;
- motion: fast, normal and reduced-motion behavior.

Applications can replace the theme at the root. Individual components accept
semantic variants and part-level style overrides. Platform tweaks run after
theme resolution and before backend patch emission, so a tweak remains typed
and scoped rather than becoming arbitrary host code.

## Authoring shape

Primitive tags stay compact:

```clojure
[:column {:gap 12 :padding 16 :max-width 640}
 [:heading {:level 1} "Profile"]
 [:text-field {:label "Name"
               :value name
               :on-change change-name}]
 [:button {:variant :primary :on-press save} "Save"]]
```

Composite components expose named parts when applications need visual control:

```clojure
[:dialog {:open open? :on-open-change set-open}
 [:dialog/trigger [:button "Edit"]]
 [:dialog/content
  [:dialog/title "Edit profile"]
  [:dialog/description "Changes are saved locally."]
  [:dialog/actions ...]]]
```

Convenience forms may supply default parts, but the part-based form is the
semantic source of truth. Qualified application components continue to use
`defelement` without changing the central dispatcher.

### Label and TextField contract

The implemented TextField family follows Solid UI's compound anatomy:

```clojure
[:text-field
 [:text-field/label "Email"]
 [:text-field/input
  {:value email
   :type "email"
   :invalid invalid?
   :on-change change-email}]
 [:text-field/description "Used for account notifications."]
 [:text-field/error-message "Enter a valid email address."]]
```

`:text-field/input` and `:text-field/text-area` are alternative controls; a
root associates its label, description and error with its control through the
typed `LabelledBy`, `DescribedBy` and `ErrorMessageBy` retained properties.
`InputType` is a closed HTML-compatible value on text input, and `Invalid` is
a Signal-bindable boolean. An invalid patch updates the existing native
control; it does not rebuild the TextField root or replace editing state.

Web renders `label`, `input` and `textarea`, establishes `for`,
`aria-labelledby`, conditional `aria-describedby`, `aria-invalid` and
`data-invalid`, and preserves native focus and selection. Apple platforms use
SwiftUI `TextField`, `SecureField` and `TextEditor`; Flutter uses `TextField`
plus `Semantics`. Descriptions are always exposed; error text joins the
accessible description only while the control is invalid.

CLJC component code emits only stable semantic classes such as
`lui-text-field-input`. Solid UI utility combinations live exclusively in
`platform/web/src/lui.css` as Tailwind `@apply` rules and compile to static
CSS. Cross-platform behavior must never depend on a Tailwind utility string.

### Checkbox and Switch contract

Checkbox follows Solid UI's single public root while Switch preserves its
compound parts:

```clojure
[:checkbox
 {:checked completed?
  :indeterminate partially-completed?
  :accessibility-label "Complete all tasks"
  :on-change change-completed}]

[:switch
 {:checked notifications?
  :disabled notifications-locked?
  :invalid notifications-invalid?
  :on-change change-notifications}
 [:switch/control
  [:switch/thumb]]
 [:switch/label "Email notifications"]
 [:switch/description "Receive one summary each day."]
 [:switch/error-message "Choose a notification preference."]]
```

`Checked`, `Indeterminate` and `Invalid` are typed, Signal-bindable retained
properties. Checkbox and Switch emit `ToggleChanged(node, checked)` rather
than a generic click, so the application receives the native control's next
value without sampling a second platform model. Indeterminate applies only to
Checkbox and clears through the same retained property path. Activating an
indeterminate Checkbox consistently emits `ToggleChanged(node, true)` before
the controlled Signal supplies the retained state patch.

The Switch root owns controlled state, matching Solid UI. Its component macro
passes that state to the semantic `/control`, then associates `/label`,
`/description` and `/error-message` with the control. `/thumb` is a retained
visual child on Web; native backends keep it in the semantic tree but render
the platform switch's built-in thumb instead of layering a custom control over
it.

Web uses native checkbox input and switch semantics, real focus, keyboard
activation, `aria-checked` (including `mixed`), `aria-invalid`, and matching
`data-checked`, `data-indeterminate` and `data-disabled` selectors. Apple uses
SwiftUI `Toggle` and `Button` control APIs, and Flutter uses `Checkbox` and
`Switch` with native Semantics. All backends preserve control identity when
Signals patch checked, disabled, indeterminate or invalid state.

## State ownership

- Controlled state is represented by a Signal plus an event callback.
- Uncontrolled convenience state is allocated in the component scope and must
  be disposable.
- Components never mirror controlled state into a second platform model.
- Native transient state such as text composition, selection handles, hover,
  pressed state and scroll momentum stays in the backend unless the public
  component contract explicitly exposes it.
- Selection collections use stable keys, not child indices.

## Primitive admission and composition

A public component does not automatically become a retained protocol node.
Add a semantic primitive only when at least one backend needs a distinct
platform object to preserve native behavior, accessibility, events, transient
state or lifecycle. `TextField`, `Switch` and the progress control satisfy this
rule. Visual families such as Badge, Card and Skeleton do not.

Composition still uses each platform's provided UI APIs. A composed `Row` is a
real flex container on Web, `HStack` on Apple platforms and `Row` on Flutter.
Backgrounds, insets, borders and corner radii map to CSS, SwiftUI modifiers and
Flutter decoration APIs. Composition never means implementing a parallel
renderer or drawing system.

The first reusable Surface property set is:

- `WidthValue`, `HeightValue`, `MinWidth`, `MaxWidth`, `MinHeight` and
  `MaxHeight`, expressed in platform logical points;
- `PaddingHorizontal` and `PaddingVertical`, expressed in platform logical
  points;
- `ForegroundValue` and `BackgroundValue`, resolved from semantic color names;
- `BorderColorValue`, `BorderWidth` and `CornerRadius`.

Numeric surface values are non-negative. These properties apply to retained
primitives and patch the existing platform object. Component-specific classes
remain Web-only visual selectors and are not interpreted as native styling.

Omitted size properties preserve native intrinsic sizing. A minimum must not
exceed its corresponding maximum, and a fixed width or height must fall inside
the supplied range. The complete patch batch is rejected before commit when
those constraints conflict. Web maps them to inline CSS size constraints,
SwiftUI applies fixed and constrained `frame` modifiers, and Flutter composes
`SizedBox` with `ConstrainedBox`. Percentages, viewport units, content keywords
and unbounded fill are separate typed capabilities; they are not encoded as
magic integers or arbitrary strings.

Skeleton validates the composed Surface path: it is a Box with semantic
background and radius defaults plus caller-supplied typed size constraints.
Web adds only the Solid-style pulse through its semantic class and disables it
for reduced-motion users; SwiftUI and Flutter render the same retained Surface
without introducing a Skeleton-specific native node.

### Component extension paths

Adding a component and adding a primitive are deliberately different jobs:

1. The default component path changes only its LG composition, semantic Web
   Tailwind rules, and `examples/components/` gallery. It does not extend the
   wire protocol or any native backend. Card, Badge, Skeleton and most Solid UI
   families follow this path.
2. The primitive path is reserved for a reusable semantic capability that
   requires a distinct native object, event, accessibility contract or
   transient state. It extends the closed protocol once and maps that primitive
   in every backend. Multiple public components must reuse it.

A Web component must not acquire a new protocol node merely to obtain a tag or
CSS selector. Conversely, the primitive path must not be replaced with an
arbitrary DOM/JSON escape hatch, because that would remove cross-platform type
safety and create a second Web-only UI model.

Component definitions have three explicit levels:

```clojure
(defcomponent card :box {:class "lui-card"})

(defcompound text-field
  {:root :box
   :class "lui-text-field"
   :controls [:text-field/input :text-field/text-area]
   :relations
   [[:labelled-by :text-field/label]
    [:described-by :text-field/description]
    [:error-message-by :text-field/error-message]]})
```

- `defcomponent` is the default. It composes one existing primitive, merges
  default and caller attributes once, preserves both semantic classes, mounts
  children and applies the shared Surface property set.
- `defcompound` additionally declares control parts, root attributes forwarded
  to those controls, and accessibility relationships. It owns the repeated
  node and property plumbing for compound families.
- `defelement` is the protocol-boundary escape hatch for implementing an actual
  semantic primitive or a component with genuinely custom retained wiring. It
  is not the normal component authoring API.

Unqualified non-primitive tags follow a namespace convention: `:card` resolves
to `lui.card/card`, while qualified application tags keep their exact namespace.
The consuming namespace requires the component namespace explicitly. A new
component file under `lg/lui/` is discovered through the existing LUI compile
state; no Dune file list or central dispatcher registration is updated.

The complete default Web component workflow is therefore:

1. record the public anatomy, states and platform behavior in this design;
2. define the root and parts together in `lg/lui/<component>.cljc` with
   `defcomponent` or `defcompound`;
3. add semantic `lui-*` Tailwind component rules to the Web stylesheet;
4. add contract assertions and one `examples/components/` gallery section.

Protocol, wire, Web backend, SwiftUI and Flutter changes happen only when step
1 proves that a reusable native semantic primitive is missing. Dune never
changes merely because a component source file was added.

### Badge contract

Badge proves the composition boundary: it is a retained `Row` containing its
content primitives and never introduces a `Badge` node kind. It matches Solid
UI's `default`, `secondary`, `outline`, `success`, `warning` and `error`
variants plus `round` and `class` overrides:

```clojure
[:badge "Default"]
[:badge {:variant "success" :round true} "Synchronized"]
```

Web visuals come from `lui-badge`, `lui-badge--<variant>` and
`lui-badge--round` Tailwind component rules. Native backends receive the same
variant as reusable Surface properties on the Row and foreground styling on
its text content. Flutter uses `Row`, `Container` decoration and `Text`; Apple
uses `HStack`, standard shape modifiers and `Text`. Both keep the same LUI node
identities rather than maintaining another Badge state tree.

### Separator contract

Separator matches Solid UI's single-root family and its horizontal-default
orientation contract:

```clojure
[:separator]
[:separator {:orientation "vertical"}]
```

The public Separator lowers to the shared `Divider` leaf primitive because
orientation affects native layout and separator accessibility semantics.
`OrientationValue` is a closed `"horizontal"` or `"vertical"` property and
defaults to horizontal. Invalid orientation values reject the complete patch
batch before any backend state changes. A Divider never accepts children and
can be reused by future component families.

Web renders a semantic `hr` with `role="separator"`, `aria-orientation`, and a
matching `data-orientation` style state. Its `lui-separator` Tailwind component
rule uses a full-width one-pixel horizontal rule or a full-height one-pixel
vertical rule, matching Solid UI. Apple uses SwiftUI `Divider`, constrained on
the axis selected by the retained property. Flutter uses `Divider` or
`VerticalDivider`. Patching orientation updates the existing retained node and
does not replace its stable LUI identity.

### Progress contract

Progress keeps Solid UI's public family while reserving a distinct retained
primitive for the native progress object:

```clojure
[:progress {:value completed :min-value 0 :max-value 10}
 [:progress/label "Processing..."]
 [:progress/value-label {:value completed-label}]]
```

The public `:progress` root is a composed `Column`. It appends the optional
`/label` and `/value-label` parts followed by one automatically-created
`ProgressControl`; applications do not address that internal control directly.
`ProgressValue` is Signal-bindable, while `MinValue` and `MaxValue` define its
range and default to 0 and 100. The maximum must be greater than the minimum.
Backends clamp the presented and accessible value to that range without
mutating application state.

`/label` is structurally associated with the control through `LabelledBy`.
Web exposes the same `progressbar` role, `aria-valuemin`, `aria-valuemax` and
`aria-valuenow` semantics as Solid UI and renders its track and fill with
semantic Tailwind component rules. Apple uses SwiftUI `ProgressView`, and
Flutter uses `LinearProgressIndicator`. A value Signal patches only the
retained `ProgressControl`; the composed root, labels and platform control keep
their identity. Indeterminate progress is a separate state and is not inferred
from a missing value.

## Primitive protocol design

The retained protocol grows by semantic capability rather than one node kind
per styled component:

| Primitive | Responsibility |
| --- | --- |
| Box, Row, Column, Stack | containment, flex/overlay layout and style |
| ScrollView | native scrolling and one retained content root |
| Text, Image, Icon, Divider | non-interactive content semantics |
| Button, Link | activation semantics and disabled state |
| TextField, TextArea | editing, composition, selection and focus |
| Toggle, Slider, SelectControl | native value input and value-change events |
| OverlayRoot | ordered presentation, dismissal and focus restoration |

Protocol properties cover size constraints, flex, alignment, spacing, visual
tokens, enabled/readonly/selected/checked state, accessible name/description,
focus request and component-specific values. Wire values remain a closed typed
sum; no arbitrary JSON or dynamic property bag is introduced.

Events are validated against node kind before entering the Signal scheduler.

Text uses intrinsic content measurement by default and updates its measured
size when content, typography or available width changes. TextArea grows with
content while respecting minimum and maximum line constraints. LUI maps those
constraints to native HTML, Flutter or SwiftUI measurement APIs; it does
not implement a parallel glyph layout engine. Backends preserve selection,
composition, scroll position and retained control identity.
Focus, key activation, value changes, selection changes and dismissal use typed
events. Backends reject invalid property/value and parent/child combinations
transactionally.

## Design influences

- [GPUI](https://github.com/zed-industries/zed/tree/main/crates/gpui) informs
  the split between high-level declarative views and extensible low-level
  elements, plus explicit application context and actions.
- [Vercel Native](https://github.com/vercel-labs/native) informs the practical
  built-in catalog, useful defaults, model/message separation, and platform
  support matrix.
- [Base UI](https://base-ui.com/react/overview/about) informs headless,
  composable behavior and accessibility contracts. LUI does not adopt Base
  UI's React runtime.
- [Solid UI](https://www.solid-ui.com/) defines the Web component contract:
  component names, named parts, props, variants, sizes, state attributes,
  accessibility behavior, examples and default visuals stay in parity.
  Its local reference checkout is kept outside this repository. LUI implements
  the contract with retained LG components rather than Solid JSX, Kobalte,
  or Corvu. Solid UI utility combinations are compiled behind LUI semantic
  classes with Tailwind rather than exposed through the cross-platform DSL.

## Layers

1. **Semantic primitives** are retained protocol nodes implemented by every
   backend. They own platform identity, layout, input, focus, accessibility,
   and native event translation.
2. **Headless behaviors** implement selection, dismissal, roving focus,
   keyboard navigation, validation, and overlay state in LG.
3. **Components** compose primitives and behaviors with useful theme defaults.
   Applications can replace visual parts without reimplementing behavior.
4. **Platform tweaks** adjust density, placement, native presentation, or an
   individual part through `platform` and `host` profiles. Shared semantic
   state remains the source of truth.

## Required catalog

The Web catalog corresponds one for one with the 54 UI registry entries in
Solid UI revision `21ba4fa`. The authoritative names, public parts, behavior
substrates and delivery waves are listed in
`001-production-components_solid_ui_matrix.md`. A component is not counted as
corresponding merely because it has the same name; it must satisfy the
conformance rules in that matrix.

### Tier 1: daily foundations

- Layout: Box, Row, Column, Stack, ScrollView, Spacer, Divider.
- Content: Text, Heading, Icon, Image, Link.
- Actions and forms: Button, TextField, TextArea, Checkbox, Switch,
  RadioGroup, Select, Slider.
- Feedback: Badge, Progress, Spinner.
- Styling: size constraints, flex growth, alignment, gap, padding, foreground,
  background, border, radius, opacity, disabled and selected states.

### Tier 2: common application structure

- Card, FormField, Toolbar, Tabs, Breadcrumb.
- Dialog, Sheet, Popover, Tooltip, Menu and Toast.
- Overlay placement, escape/outside dismissal, focus trapping and restoration.

### Tier 3: data-heavy workflows

- Combobox and Autocomplete.
- Keyed List, VirtualList, Table and Tree.
- Command palette and basic date picker.

## Behavior contract

Every interactive component must define and verify:

- controlled and uncontrolled state ownership;
- enabled, disabled, readonly, selected, checked and indeterminate states as
  applicable;
- focus request, visible focus indication, traversal order and restoration;
- keyboard activation and navigation;
- accessible role, name, value, description and error association;
- pointer/touch interaction without making hover mandatory;
- retained identity across property patches, keyed moves and parent rebuilds;
- lifecycle cleanup for handlers, overlays, controllers and native resources.

Web uses semantic HTML and browser focus, form, dialog and popover behavior
where it matches the contract. LUI headless behaviors fill semantic gaps and
are verified against WAI-ARIA interaction patterns. The Apple backend uses
SwiftUI controls and accessibility modifiers. Flutter uses Material/Cupertino
widgets and semantics without rebuilding unrelated retained nodes.

## Backend mapping

| Semantic need | Web | Apple SwiftUI | Flutter |
| --- | --- | --- | --- |
| Text input | `input` / `textarea` | `TextField` / `SecureField` / vertical-axis `TextField` | Material/Cupertino `TextField` |
| Toggle | `input[type=checkbox]` | `Toggle` / `Button` | Material/Cupertino `Checkbox` / `Switch` |
| Selection | `select` plus LUI combobox behavior | `Picker` / `Menu` | Material/Cupertino picker |
| Scroll/list | native scroll element | `ScrollView` / `List` | scroll and sliver widgets |
| Overlay | `dialog` / Popover API plus LUI behavior | sheet, popover and window scenes | `Overlay` / `Navigator` |

### Single Apple backend

Apple platforms have one renderer, implemented in SwiftUI. LUI does not keep
parallel UIKit and AppKit node trees or property mappers. The wire decoder and
retained `NodeStore` are platform-neutral Swift. Each retained node owns one
independent observable model; a property patch mutates only that model, while
a structural patch mutates only the affected parent child list. Recursive
SwiftUI node views observe their own model and use stable LUI node IDs for
dynamic children. The backend object itself is not a global observable, so a
leaf patch cannot invalidate the whole root.

SwiftUI `body` evaluation is treated as incremental projection, not as LUI's
source of truth. LG Signals and the retained NodeStore remain authoritative.
Patch batches validate completely before observable models are committed, and
all commits run on the main actor in one transaction. Tests record node model
revision changes and preserve per-node object identity across property patches
and keyed moves. Instruments' SwiftUI update lane is the runtime verification
for unexpected wide invalidation.

`UIViewRepresentable` or `NSViewRepresentable` is allowed only as a local
escape hatch for a capability SwiftUI cannot expose. Such a wrapper belongs to
the corresponding semantic node view and must not introduce a second backend,
tree, protocol decoder or styling implementation.

## LUI Web component system

The Web implementation has no external component runtime:

1. **Retained DOM primitives** create `button`, `input`, `textarea`, `select`,
   `dialog`, semantic text and layout elements directly. Property patches set
   DOM properties without replacing focused nodes.
2. **LUI behaviors** implement only the missing reusable interaction state:
   roving focus, selection models, escape/outside dismissal, focus restoration,
   overlay placement and validation relationships.
3. **LUI components** compose primitives and behaviors into the polished daily
   catalog. They use semantic classes, data-state attributes and CSS custom
   properties generated from the shared theme tokens. A pinned Tailwind CLI
   resolves component `@apply` rules into minified static CSS at build time.

The Solid UI reference defines component anatomy and visual output, but not the
runtime architecture. Solid props, contexts and headless runtime state become
one LG Signal graph. LUI components are library code, not source copied into
each application. A Signal change patches only the retained primitive
properties and keyed children that changed.

Native CSS capabilities are preferred for layout, focus indication, color
schemes, reduced motion and content-sized fields. A small backend adapter may
bridge a browser capability gap, but it must preserve the native element and
must not become a general layout or text engine.

The Web production budget is measured against LUI's generated JavaScript and
CSS, with no baseline npm UI runtime dependency. Tailwind remains a development
dependency and its generated CSS is the only shipped artifact. Tier 2 and Tier
3 code remains separately reachable so applications only ship components they use. Bundle
budgets are set from the first gallery build rather than inherited from a
third-party provider experiment.

## Delivery order

1. Extend the closed protocol with layout, styling, accessibility and focus.
2. Implement Tier 1 primitives consistently in retained, Web, Apple SwiftUI
   and Flutter backends.
3. Add headless selection and overlay behaviors in LG.
4. Build Tier 2 components and verify focus/dismissal behavior per platform.
5. Add virtualized/data-heavy Tier 3 components after measurement APIs and
   scrolling behavior are stable.

## Component gallery

`examples/components/` is a dedicated cross-platform gallery, separate from
the Todo application. It groups components by Foundations, Forms, Navigation,
Overlays, Feedback and Data.

Each component page shows:

- default and themed appearance;
- enabled, disabled, readonly, selected, error and loading states where valid;
- pointer/touch and keyboard interaction;
- focus order and visible focus behavior;
- long text, empty data, large text and compact viewport cases;
- the platform and host profile currently active;
- an incremental diagnostic showing which retained node revisions changed.

The same LG gallery model and view run in Web, Flutter desktop, Apple SwiftUI
on iOS and macOS, and Flutter on Android. Platform-specific examples are
clearly labeled and do not replace the shared component example.

No component is considered supported merely because it compiles. Its platform
mapping, incremental invalidation, keyboard/focus behavior, accessibility, and
lifecycle must be verified and listed in the support matrix.
