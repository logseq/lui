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

Recursive menus now add a Base UI-style pointer grace corridor without exposing
new component properties. Each submenu derives a directional triangle from its
actual post-collision side, the trigger leave point, and the popup edge. Pointer
movement toward the popup refreshes close intent; movement away preserves the
normal close delay. Browser tests cover both right-side and flipped-left paths.

Select now records the opening modality without adding a public property.
Mouse and keyboard opening focus the current selected item and align its text
center and inline start with the trigger value, matching Base UI's default
selected-item placement. Touch keeps ordinary anchored placement. Alignment
falls back to shared collision placement near viewport edges or whenever the
exact aligned popup would leave the 8 px viewport gutter.

Text controls now keep native IME composition local until `compositionend`.
Combobox navigation and dismissal keys do not run while composition is active,
the retained input keeps its DOM identity and focus, and the final committed
value fans out through the shared Signal before ordinary option navigation
resumes. The Web backend resolves wrapped controls by their actual `INPUT` or
`TEXTAREA` tag instead of relying on melange-webapi's generic Element cast.

Tabs now follows Base UI's manual-activation composite behavior. One direct
enabled Button owns the roving tab stop; arrows move focus without changing the
model-owned selection, while native Enter or Space activation invokes the
existing Button event. Horizontal navigation follows computed LTR or RTL
direction, vertical navigation uses Up and Down, and both modes wrap, skip
disabled triggers, and support Home and End. The tablist accepts an accessible
label and exposes its orientation. Panel relationships and indicator motion
remain intentionally deferred until the compact API has an explicit retained
panel association.

Accordion now uses a real button trigger and a linked `region` panel instead of
intercepting a `details`/`summary` control. The panel remains mounted while
collapsed, measures its retained content into an internal height variable, and
follows Base UI's 150 ms ease-out starting and ending phases. Transition
cancellation cannot let a stale phase hide a reopened panel, and reduced-motion
preference closes it synchronously. The public API remains the compact,
model-owned single-disclosure contract.

ButtonGroup and ToggleGroup now initialize and maintain one roving Tab stop
across retained batches. Their fixed horizontal keymap wraps, follows document
direction, supports Home and End, and excludes disabled controls. ToggleGroup
includes both Button and ToggleButton children, matching the shared LUI and
Vercel Native contract; activating either child still returns through its own
model callback instead of introducing group-owned selection state.

Tree now adds delegated WAI-ARIA typeahead to its existing retained roving
focus model. Printable input searches the next visible enabled row with
wrapping, rapid characters form one 500 ms prefix, and focus movement continues
to return selection through the existing LG callback. Modifier shortcuts,
unmatched prefixes, disabled rows, and descendants removed by collapsed
branches do not become search targets. The timer is released with the retained
Tree node.

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

## Browser qualification

Chromium remains the complete behavioral gate: 37 browser tests cover portals,
focus, keyboard and typeahead, pointer and touch gestures, collision handling,
motion cancellation, retained identity, IME composition, and every compact
Gallery page. A pinned Playwright Firefox gate separately renders all 65 pages
at the mobile viewport and exercises the highest-risk retained interactions:
Dialog portal/focus restoration, Tree keyboard navigation, Dropdown typeahead,
and Chinese composition in a retained Sheet input. The identical contract also
runs on pinned Playwright WebKit 26.5. Playwright and its browser runtimes are
development-only and do not enter the release bundle.

WebKit does not focus a native button for ordinary pointer activation. The Web
backend therefore records a Button as a potential modal return target only for
the current event-loop turn. A synchronously mounted controlled Dialog or Sheet
consumes that target when `document.activeElement` is still `body`; otherwise
the candidate expires without changing normal WebKit button focus behavior.
Modal cleanup uses the shared guarded focus-restoration path, so an unrelated
focus change is never overwritten by a delayed retry.

Safari remains an explicit qualification gap. The system Safari driver on the
current macOS host requires the user-controlled Allow Remote Automation setting;
LUI does not weaken or bypass that OS boundary.

## Historical measurements

The rejected provider experiment measured a minified common set of Button,
TextField, TextArea, Select, and Dialog at 48.3 KB gzip for Vaadin 25.2.8 and
93.7 KB gzip for Spectrum 1.12.2. These numbers remain useful comparison data,
but they are not LUI's bundle budget.
