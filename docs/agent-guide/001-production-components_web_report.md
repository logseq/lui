# LUI-native Web component decision

Date: 2026-08-25

Status: active Web implementation decision

The public component API remains bounded by
`001-production-components_vercel_native_matrix.md`. Base UI defines the Web
visual and interaction reference; it does not define LUI's public API.

## Decision

LUI implements its own Web component layer on retained native DOM. It does not
ship React, Base UI, Solid, Vaadin, Lion, Web Awesome, or another UI runtime.

Base UI revision `1e208a97f0339b617e70dadbc4abda32b48ea063` is the
pinned Web reference. Its official component demos define visual output,
including typography, spacing, icons, borders, shadows, animation, responsive
behavior, and state styling. Its documentation, source, and tests define
observable interaction behavior, including ARIA, focus, keyboard, pointer,
dismissal, positioning, and transition lifecycles. The local reference checkout
is `/Users/tiensonqin/Code/projects/base-ui`.

LUI reproduces those results with its own declarative elements, Signal graph,
and retained incremental scheduler. It does not copy Base UI's React parts,
hooks, render-prop API, detached-trigger machinery, or framework compatibility
layers.

Tailwind 4.1.4 is used only as a locked build-time compiler for LUI semantic
classes. The generated, minified CSS is shipped; Tailwind JavaScript and utility
class strings are not part of the LUI runtime or cross-platform authoring API.

## Runtime boundary

- Native HTML owns text editing, selection, composition, forms, scrolling, and
  accessibility semantics.
- Declarative LUI components and Signals own component structure and portable
  interaction state.
- The Web backend owns retained element identity, typed property/event
  translation, and browser capabilities that cannot be expressed by a retained
  LUI tree: portal mounting, geometry and collision measurement, focus and
  pointer primitives, visual viewport integration, and native text input.
- LUI components own tokens and finished visual styling.
- Applications consume components as library APIs instead of copying generated
  source into each project.

## Why not a provider

Provider experiments showed that third-party custom elements can preserve LUI
retained identity, but they add another component lifecycle, theming contract,
and baseline bundle. Vaadin was briefly selected for its catalog and measured
size, then explicitly removed from the product direction. Lion requires LUI to
create nearly all visual styling. Spectrum imposes a larger bundle and Adobe's
design language. Base UI requires React as a dependency, so LUI uses it as a
source-level behavioral and visual reference rather than a runtime provider.

Implementing LUI's styled layer directly makes platform tweaks, semantic tokens,
and incremental diagnostics part of one cross-platform component contract.

## Implementation rules

1. Use the most specific semantic HTML element available.
2. Patch properties in place; never replace a control to update its value or
   appearance.
3. Preserve composition, selection, focus, and scroll position during external
   value patches and keyed moves.
4. Prefer browser layout and presentation APIs over JavaScript measurement.
5. Keep behaviors headless and components composable through the reference
   element grammar.
6. Express visual state through theme tokens, semantic classes, and data-state
   attributes, not inline provider-specific options.
7. Use one shared popup layer for Menu, Context Menu, Popover, Dialog, Sheet,
   Select, Combobox, Tooltip, and Toast. It owns portal stacking,
   positioning, dismissal, focus restoration, and transition state.
8. The application layout root uses `isolation: isolate`; popup portals mount
   outside that stacking context. The document body is positioned for visual
   viewport backdrops on iOS 26+ Safari.
9. Model transitions with cancellable `data-starting-style` and
   `data-ending-style` states. Keep an exiting popup mounted until its CSS
   transitions finish, and honor reduced motion.
10. Implement component structure and state machines in LUI. Do not add
    component-specific `createElement`, `appendChild`, or attribute-setting code
    when the same result can be represented by ordinary LUI elements and the
    generic property patcher.
11. Public names and attributes follow the Vercel Native parity matrix unless a
    separately approved component, such as Toast or Toolbar, extends it.
12. Test keyboard and accessibility contracts in a real browser.
13. Measure generated LUI JavaScript and CSS from the component gallery and fail
    production builds when agreed budgets regress.

The shared transition lifecycle is now implemented for Dialog, Sheet,
DropdownMenu, Select, Combobox, and Tooltip. Exit shells complete from their
own `transitionend` or `transitioncancel` event, with one-shot cleanup, a
bounded no-event fallback, and immediate completion under reduced motion.
Retained popup reopening removes the stale ending phase without replacing its
DOM identity.

Anchored popups also share collision placement now: requested top/bottom or
left/right placement flips when necessary, both axes shift to an 8 px viewport
gutter, the rendered side is exposed for motion styling, and an open popup
tracks viewport resize. Select and Combobox triggers open on primary mousedown
with the following click deduplicated, while MenuItem still requires a complete
click. This keeps touch opening responsive without allowing the opening release
to commit an option that was not present at press start.

## Base UI parity scope

Behavioral parity applies to LUI components that overlap Base UI: Accordion,
Avatar, Button, Checkbox, Combobox, Context Menu, Dialog, Input, Menu, Sheet,
Progress, Radio Group, Scroll, Select, Separator, Slider, Switch, Tabs, Toggle,
Toggle Group, Tooltip, Toast, and Toolbar.

The shared minimum contract is:

- correct semantic element, role, accessible name, relationships, and state;
- keyboard navigation according to the relevant WAI-ARIA Authoring Practice;
- automatic initial focus, focus containment where modal, and final focus
  restoration;
- pointer, touch, hover-intent, outside-press, Escape, and native dismissal;
- portal stacking, viewport collision handling, RTL-aware placement, and
  responsive mobile presentation;
- cancellable enter/exit transitions with stable retained identity;
- official Base UI demo typography, spacing, icons, surfaces, state styling,
  and motion.

Menu additionally supports arbitrarily nested submenus. Each level is a popup
in the shared portal layer. Arrow keys traverse levels, typeahead and Home/End
operate within the current level, sibling branches close, and a pointer corridor
prevents an open submenu from collapsing while the pointer moves from its
trigger into its popup.

Toast uses one application-level Signal queue rendered through a declarative
LUI viewport. It supports timed dismissal, pause on hover or focus, close and
action controls, stacked expansion, swipe dismissal, F6 landmark focus, and
stable updates by id. Toolbar is a retained container composed from existing
controls. It supplies the toolbar role, orientation-aware roving focus, groups,
and separators; component-specific toolbar button and input node kinds are not
required.

## Historical measurements

The rejected provider experiment measured a minified common set of Button,
TextField, TextArea, Select, and Dialog at 48.3 KB gzip for Vaadin 25.2.8 and
93.7 KB gzip for Spectrum 1.12.2. These numbers remain useful comparison data,
but they are not LUI's bundle budget.
