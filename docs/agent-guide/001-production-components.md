# Production component system

Status: design

## Goal

LUI should cover most daily application UI without forcing applications to
drop into platform code. Components use the retained incremental runtime and
share one LG state and behavior model across platforms. Platform backends
render native controls and may apply scoped platform tweaks.

The Web backend uses real DOM with standalone Vaadin Web Components as its
default interactive component provider. It does not use Vaadin Flow, Java,
React, or a virtual DOM.

## Product principles

- **Native behavior first.** Use native text editing, scrolling, focus,
  accessibility and platform presentation rather than imitating them.
- **Established controls by default.** Web uses Vaadin custom elements, Flutter
  uses Material or Cupertino widgets, UIKit and AppKit use system views and
  controls, and SwiftUI integration uses system views. Custom drawing is
  reserved for semantics the selected provider does not supply or for composed
  styling around native behavior.
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

## State ownership

- Controlled state is represented by a Signal plus an event callback.
- Uncontrolled convenience state is allocated in the component scope and must
  be disposable.
- Components never mirror controlled state into a second platform model.
- Native transient state such as text composition, selection handles, hover,
  pressed state and scroll momentum stays in the backend unless the public
  component contract explicitly exposes it.
- Selection collections use stable keys, not child indices.

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
content while respecting minimum and maximum line constraints when its selected
provider supports that behavior. LUI maps the semantic constraints to Vaadin,
Flutter, UIKit or AppKit; it does not implement a parallel text measurement or
sizing engine. The provider must preserve selection, composition, scroll
position and retained control identity.
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

Web behavior is delegated to Vaadin where a matching component exists, with LUI
verifying the resulting WAI-ARIA behavior. Apple backends use AppKit/UIKit
controls and accessibility APIs. Flutter uses Material/Cupertino-capable
widgets and semantics without rebuilding unrelated retained nodes.

## Backend mapping

| Semantic need | Web | AppKit | UIKit | Flutter |
| --- | --- | --- | --- | --- |
| Text input | `vaadin-text-field` / `vaadin-text-area` | `NSTextField` / `NSTextView` | `UITextField` / `UITextView` | Material/Cupertino `TextField` |
| Toggle | `vaadin-checkbox` / `vaadin-switch` | `NSButton` | `UISwitch` / `UIButton` | Material/Cupertino `Checkbox` / `Switch` |
| Selection | `vaadin-select` / `vaadin-combo-box` | `NSPopUpButton` | `UIMenu` / picker presentation | Material/Cupertino picker |
| Scroll/list | native scroll element | `NSScrollView` | `UIScrollView` / collection view | scroll and sliver widgets |
| Overlay | `vaadin-dialog` / `vaadin-popover` | panel/popover/window APIs | presentation/popover APIs | `Overlay` / `Navigator` |

SwiftUI integration embeds the retained UIKit root. SwiftUI is a host surface,
not a second state or component implementation.

## Web component provider

The Web backend does not reimplement a full component library. It uses three
layers:

1. Native HTML elements provide retained layout, text, image, scrolling and
   other non-control primitives.
2. Standalone [Vaadin Web Components](https://github.com/vaadin/web-components)
   are the default provider for interactive controls, including buttons, text
   fields, text areas, toggles, selection, validation and overlays. They are
   consumed as browser-side npm packages and do not require Java or Vaadin
   Flow. LUI creates the custom elements directly and adapts their properties,
   slots and events. Native form controls are a fallback, not the default
   component layer.
3. The provider boundary remains replaceable. Provider-specific options never
   leak into the shared component contract. Web Awesome is excluded from the
   default provider set, and Spectrum is not selected because the measured
   common-control bundle is substantially larger.

Vaadin is selected because its Apache-licensed core catalog covers the daily
and data-heavy controls LUI needs, its Aura/Lumo themes are usable without a
new design implementation, and its component-level npm imports tree-shake into
a smaller representative bundle than Spectrum. Commercial Vaadin Pro controls
do not define LUI's capability floor.

The Web provider has enforced production budgets:

- an isolated initial text field bundle must not exceed 35 KB gzip;
- Button, TextField, TextArea, Select and Dialog together must not exceed
  55 KB gzip;
- components outside the initial route are imported in lazy chunks;
- builds import component entry points individually and never import an
  all-components bundle.

The provider package owns registration and mapping so the shared protocol and
Web retained tree do not import Vaadin directly. Measurements and the rejected
alternatives are recorded in the companion Vaadin report. The earlier Lion
spike remains useful evidence for retained custom-element identity and focus
behavior, but Lion is not the default visual provider.

## Delivery order

1. Extend the closed protocol with layout, styling, accessibility and focus.
2. Implement Tier 1 primitives consistently in retained, Web, AppKit, UIKit
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

The same LG gallery model and view run in Web, Flutter desktop, AppKit, UIKit,
SwiftUI host and Android host. Platform-specific examples are clearly labeled
and do not replace the shared component example.

No component is considered supported merely because it compiles. Its platform
mapping, incremental invalidation, keyboard/focus behavior, accessibility, and
lifecycle must be verified and listed in the support matrix.
