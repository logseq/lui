# Base UI Web interaction and motion report

Status: implemented and qualified within the pinned LUI public API

## Problem

LUI's interactive Web elements need a defined behavior and motion contract —
portal lifecycle, focus, keyboard, pointer, dismissal, and transitions —
without adding React or copying Base UI's public compound component API.

## Decision

LUI's Web backend uses Base UI as its behavior and motion reference: it copies
contracts, not framework architecture. This report defines that usage. The
reference is the local Base UI checkout at commit
`1e208a9`, together with the official component and animation documentation.

## Scope and reference

The comparison applies to LUI's interactive Web elements. Pure layout and
display elements keep native DOM semantics and do not need a Base UI state
machine. SwiftUI and Flutter continue to use their native controls and
presentation APIs; this report does not make Web behavior a cross-platform
implementation detail.

Primary references:

- [Animation](https://base-ui.com/react/handbook/animation)
- [Accessibility](https://base-ui.com/react/overview/accessibility)
- [Dialog](https://base-ui.com/react/components/dialog)
- [Drawer](https://base-ui.com/react/components/drawer)
- [Menu](https://base-ui.com/react/components/menu)
- [Select](https://base-ui.com/react/components/select)
- [Combobox](https://base-ui.com/react/components/combobox)
- [Context Menu](https://base-ui.com/react/components/context-menu)
- [Popover](https://base-ui.com/react/components/popover)
- [Tooltip](https://base-ui.com/react/components/tooltip)
- [Toast](https://base-ui.com/react/components/toast)
- [Accordion](https://base-ui.com/react/components/accordion)
- [Tabs](https://base-ui.com/react/components/tabs)
- [Toolbar](https://base-ui.com/react/components/toolbar)
- [Slider](https://base-ui.com/react/components/slider)

## Implemented foundation

The Web backend now has one LG-owned popup phase implementation for
DropdownMenu, Select, Combobox, and Tooltip. Opening exposes `data-open` and a
one-frame `data-starting-style`; logical close exposes `data-closed` and
`data-ending-style`, disables pointer interaction, and retains dynamically
removed popup shells until their CSS transition completes. A shared one-shot
coordinator listens for both `transitionend` and `transitioncancel`, ignores
bubbled child transitions, removes its listeners and fallback timer exactly
once, and completes synchronously when the platform requests reduced motion.
The bounded timer remains only as a safety path for browsers or test hosts that
do not emit transition events.

Menu and Select list navigation includes case-insensitive, enabled-item-only
typeahead with Base UI's 500 ms reset window. Tooltip pointer hover ignores
touch input while focus remains an immediate accessible opening route. These
contracts are exercised through the real Gallery browser host rather than a
mock DOM.

Dialog and Sheet now use the same coordinator to remove their visual portal
shells while releasing modal ownership and restoring focus immediately.
Interrupted retained Tooltip and submenu exits cannot clear a reopened
component's open phase.

Compact Sheet gesture arbitration now locks the first intentional axis, leaves
form controls and non-edge scroll containers native, captures trusted pointers,
tracks the backdrop with the sheet, and dismisses on either sufficient distance
or downward velocity. Toast uses the Base UI default down/right directions,
damps opposite movement, locks one axis, excludes interactive descendants, and
resets cancelled gestures without dismissing model-owned state.

Native Sheet inputs now have a real mobile viewport regression that covers
Chinese composition, focus, value, and retained DOM identity. Button long press uses
one Pointer Events lifecycle for mouse, pen, and touch; movement, capture loss,
detachment, cancellation, and retained-node cleanup all cancel pending timers.

Anchored DropdownMenu, Select, Combobox, and Tooltip surfaces now share one
viewport-aware placement helper. It preserves the requested side when it fits,
flips to the opposite side when that has more usable space, shifts both axes to
an 8 px viewport gutter, exposes the rendered `data-side`, and recomputes after
viewport resize. Picker triggers open on the primary press while their click is
deduplicated; MenuItem activation remains click-qualified, so the release of an
opening touch cannot select an item that appeared beneath it. A touch-opened
Combobox keeps its native input focused.

Nested menus now use the rendered submenu side and the pointer's leave point
to form a directional grace triangle. Pointer movement through that corridor
refreshes the close intent while movement away leaves the ordinary 120 ms close
delay intact. The same behavior is verified for right-side submenus and for
submenus that collision placement flips to the left.

Select selected-item alignment and Combobox empty-result semantics are
implemented. The collection/control matrix below records the qualified result
and deliberate API exclusions. Localized application-owned wording for
asynchronous Combobox loading remains outside this scope until LUI has a
corresponding product requirement.

## Implementation boundary

LUI copies contracts, not framework architecture. LG owns declarative open,
selected, checked, and value state. The Web backend owns transient focus,
hover intent, pointer tracking, swipe progress, collision placement, and
transition phases. These transient values must not become public properties or
Signal state.

The backend should expose the same observable DOM state that Base UI styling
relies on where it is useful:

- `data-open` while logically open;
- `data-closed` while a closing element remains mounted;
- `data-starting-style` for the first entering frame;
- `data-ending-style` until all relevant exit animations finish;
- component-specific state attributes and CSS variables for gestures and
  placement.

The implementation belongs in reusable LUI Web behavior helpers. Components
must not embed raw JavaScript snippets or each grow an unrelated lifecycle.

## Transition lifecycle

Base UI favors CSS transitions because an interrupted transition reverses from
its current visual value. LUI should use the same lifecycle:

1. Mount the element with `data-open` and `data-starting-style`.
2. Remove `data-starting-style` on the next animation frame.
3. On logical close, release focus traps, outside listeners, modal inert state,
   and application ownership immediately.
4. Keep only the visual DOM shell mounted with `data-closed` and
   `data-ending-style`. It is inert and cannot receive pointer events or focus.
5. Complete on the transition target's own `transitionend` or
   `transitioncancel`, then remove the shell. Ignore bubbled transitions from
   descendants and make completion one-shot.
6. Keep a bounded duration fallback for browsers or tests that do not emit a
   transition event. Reduced motion resolves immediately.

The retained store must not keep a logically deleted node alive. The renderer
owns a small detached exit record containing the DOM shell, completion token,
and cancellation cleanup. Reusing a numeric node identifier must not attach a
new logical node to an old exiting shell.

Backdrop and surface animate independently but unmount as one portal unit. An
interrupted close must never leave the document inert, restore focus twice, or
remove a newly mounted popup.

## Motion language

Base UI leaves visual styling to CSS, so its examples use different durations
for different physical interactions. LUI should preserve that distinction
instead of forcing one global duration:

| Motion | Default | Easing and geometry |
| --- | ---: | --- |
| Menu, Select, Combobox, Context Menu, Tooltip | 100 ms | ease-out, opacity plus `scale(.98)` from the transform origin |
| Dialog | 150 ms backdrop, 100 ms surface | opacity; surface also scales from `.98` |
| Desktop side Sheet | 450 ms | `cubic-bezier(.32,.72,0,1)`, edge translation |
| Mobile bottom Sheet | 450 ms | same physical easing, vertical translation |
| Toast stack and dismissal | 200 ms | transform and opacity; direct tracking has zero duration |
| Accordion chevron/content and Tabs indicator/panel | 150–200 ms | direction-aware transform or measured size |
| Checkbox, Switch, Toggle, Progress | 125–150 ms | local color, thumb, indicator, or fill transition |

These values are internal style tokens, not public LUI props. Every animated
selector must have a `prefers-reduced-motion: reduce` rule that removes motion
without delaying unmount or state changes. Gesture tracking always uses zero
transition duration; release animation duration may scale with gesture
strength.

## Interaction matrix

### Popup family

| LUI element | Base UI contract to match | Current Web gap | Required decision |
| --- | --- | --- | --- |
| `dialog` | Portal, backdrop dismissal, Escape, modal focus trap, focus restoration, enter and exit phases; no swipe gesture | Shared portal phases, inert exit shells, focus containment/restoration, interrupted close, backdrop/Escape dismissal, and reduced-motion completion are covered | Keep Dialog non-gestural. |
| `sheet` | Use Drawer behavior: edge presentation, swipe dismissal, scroll-edge arbitration, pointer/touch distinction, safe handling of interactive descendants and software keyboards | Responsive geometry, exit motion, axis locking, scroll-edge arbitration, interactive-target exclusion, pointer capture, distance/velocity dismissal, backdrop tracking, and IME identity through compact visual-viewport changes are covered | Keep the public name Sheet. Use a right sheet on wide screens and a bottom sheet on phones. Keep downward touch swipe only on the compact layout. Do not add Drawer snap-point or nesting API. |
| `dropdown-menu` | Tap/press and keyboard open, outside/Escape dismissal, roving highlight, typeahead, nested submenu keyboard behavior and pointer grace corridor, collision-aware placement, transition phases | Popup phases, typeahead, collision placement, touch-safe press ordering, recursive keyboard traversal, and both right- and left-side submenu grace corridors are covered | Preserve recursive LUI menus without adding Base UI's compound API. |
| `context-menu` | Right click, keyboard ContextMenu/Shift+F10, and 500 ms long press; cancel long press after more than 10 px movement; same menu behavior as Menu | Point placement, movement cancellation, and keyboard restoration are covered. Closed menus no longer intercept document-level Escape/Home/End keys | Keep keyboard handling gated by the model-owned open menu. Always keep a visible primary route to the same actions. |
| `select` | Listbox semantics, typeahead, selected-item alignment for mouse/keyboard, ordinary anchored placement for touch, safe press-release selection, scrolling active item, complete keyboard navigation | Keyboard/mouse selected-item alignment, touch-safe anchored placement, collision fallback, typeahead, and press-release ordering are covered | Keep the implementation internal to Web and preserve the compact cross-platform API. |
| `combobox` | Editable input with `aria-activedescendant`, filtered listbox, composition-safe input, arrows/Home/End/Enter/Escape, touch trigger handling, live status where needed | Native composition, retained input identity, Signal filtering, empty/recovery state, active-descendant cleanup, live status, touch opening, popup lifecycle, and collision behavior are covered | Preserve the native input and composition buffer. Application-specific asynchronous or localized status wording can be added only when required; never replace editing with a contenteditable surface. |
| `tooltip` | Delayed pointer hover and immediate keyboard focus. Escape dismisses. A tooltip is not a touch or screen-reader discovery mechanism; the trigger needs its own accessible name | Delayed hover, immediate focus, Escape, ARIA linkage, popup phases, collision placement, compact viewport edges, and explicit touch-hover rejection are covered | Do not invent Web long-press tooltip behavior. Ensure icon-only triggers remain independently named. |
| `toast` | F6 focus transfer, pause on interaction, stack variables, pointer-event swipe, direction lock, threshold behavior, and interactive descendants excluded from swiping | F6, pause, Pointer Events, capture, cancellation, axis locking, down/right dismissal, opposite-direction damping, state attributes, and interactive-target exclusion are covered | Keep the behavior backend-owned and the public Toast API compact. Do not add Base UI's configurable swipe-direction API. |

### Collections and controls

| LUI element | Base UI contract to match | Current Web gap | Required decision |
| --- | --- | --- | --- |
| `accordion` | Native button trigger, independent tab stops, controlled disclosure, retained content for exit/size animation, `data-panel-open` | Button/region relationships, controlled state, retained identity, measured height phases, cancellation, and reduced motion are covered. The compact API intentionally represents one disclosure rather than Base UI's multi-item root. | Keep grouping and one-open-at-a-time policy in ordinary LUI composition and model state; do not add roving focus or root-level collection properties. |
| `tabs` | Roving focus with orientation, disabled-item skipping and wrapping. Default arrow keys move focus only; Enter/Space activates. Indicator and panels may animate with activation direction | Orientation-aware roving focus, RTL, disabled skipping, wrapping, Home/End, accessible naming, and manual activation are covered. The compact API still has no panel relationship, activation direction, or indicator lifecycle | Preserve focus-only arrows. Design an explicit panel association before adding `aria-controls` or panel motion; keep any future indicator internal and Signal-driven. |
| `toolbar` | One tab stop, orientation-aware roving focus, Home/End, disabled-but-focusable controls, nested groups, and careful input arrow handling | Native input focus targets, select-all-on-entry, composition, selection, modifier, caret-boundary, RTL handling, disabled-but-focusable controls, and flattened nested control groups are covered. Disabled native inputs retain their native identity while activation and editing are blocked | Keep the public API compact. A horizontal toolbar may contain at most one text input and it should be last; input editing keys win while focus is inside it. |
| `toggle-group`, `button-group` | One roving Tab stop, direction-aware horizontal arrows, Home/End, wrapping, and disabled-item skipping | Initial roving state, retained tab-stop refresh, and mixed Button/ToggleButton membership are covered. LUI intentionally keeps both groups horizontal and leaves selection ownership on each child. | Do not add orientation or group-selection properties. Preserve the current tab stop across unrelated retained patches and keep activation separate from focus. |
| `tree` | ARIA tree roving focus, disclosure and selection keys, disabled handling, and wrapped multi-character typeahead over visible rows | Core arrows/Home/End, disclosure, retained selection, disabled skipping, and 500 ms typeahead are covered | Keep mobile hit-target qualification in the gallery pass; no popup animation or public search property applies. |
| `slider` | Native pointer/touch drag and keyboard behavior including arrows, Home/End, PageUp/PageDown and Shift+Arrow large steps | Native range input already supplies single-thumb behavior | Continue using native range input. Test the native key/touch contract; do not port Base UI's multi-thumb machinery because it is outside LUI's public API. |
| checkbox, switch, radio, toggle, buttons | Native activation, focus-visible behavior, disabled semantics, and local state animation | Native semantics and unified Pointer Events long-press tracking are covered, including movement, capture-loss, detachment, and cleanup cancellation. Button, toggle, checkbox, switch, and radio transitions share reduced-motion cancellation, while coarse-pointer controls and interactive rows retain at least a 44 px hit target | Keep native input/button activation and do not add public animation properties. |
| text inputs and textarea | Native editing, selection, clipboard, IME composition, mobile keyboard, and textarea auto-size | Composition, auto-size, Combobox editing, and Sheet visual-viewport identity are covered with native controls | Keep editing browser-owned. Motion and layout code must never write the input value or recreate a focused control. |

Pure display components such as Row, Column, Grid, Stack, Panel, Card, Text,
Badge, Avatar, Table, Timeline, Progress, Skeleton, and Spinner do not acquire
popup behavior. Their only relevant work is consistent focus-visible styling,
local state motion where applicable, and reduced-motion compliance.

## Mobile Sheet gesture subset

LUI should implement the smallest Drawer-compatible subset needed by the
existing Sheet API:

- Only the compact bottom sheet can be dismissed by a downward swipe.
- Record one active touch/pointer and its start, latest position, time, and
  velocity samples.
- Do not begin a swipe from an element marked as swipe-ignored or from native
  form controls. Text selection, range input, pinch zoom, and multi-touch win.
- If content scrolls vertically, the sheet may claim a downward gesture only
  when that scroller is at its top edge. Upward movement remains native scroll.
- Delay axis ownership until movement exceeds a small slop. A clearly
  horizontal gesture remains native content interaction.
- During tracking, set `data-swiping`, update
  `--drawer-swipe-movement-y`, and update backdrop progress without a CSS
  transition.
- On release, dismiss for sufficient distance or downward velocity; otherwise
  animate back to zero. A dismissed Sheet emits the existing typed `Dismiss`
  event exactly once.
- The surface uses `100dvh`, safe-area padding, overscroll containment, and
  visual-viewport/keyboard awareness without moving focus or recreating input
  elements.

Snap points, swipe-to-open, nested drawer indentation, and public gesture
configuration are intentionally excluded. They are Base UI Drawer features,
not part of LUI's pinned public Sheet API.

## Positioning and touch policy

Anchored popups are positioned after they can be measured. They use the
requested side and alignment as preferences, then flip or shift to remain at
least 8 px inside the visual viewport. Position and size are refreshed on
viewport resize, scroll, and relevant layout changes.

Pointer modality is recorded at the trigger. Mouse hover may highlight and
open submenus. Touch does not synthesize hover behavior: a tap opens or
selects, and outside dismissal must not run before the target click commits.
All compact interactive rows have at least a 44 px touch target without
inflating desktop density.

The Select portion of this policy is implemented on Web. Keyboard and mouse
opening focus the selected enabled item and align its label with the retained
trigger value. Touch opening opts out, and triggers within 20 px of a viewport
edge use the ordinary flip-and-shift path. The implementation remains internal
to the Web backend and does not expand the cross-platform Select API.

Toolbar input behavior follows Base UI's composite algorithm rather than a
generic roving-focus shortcut. Focus lands on the native control, entering it
selects its text, and editing retains ownership while composing, selecting,
using modifiers, or moving within the text. Only a direction-aware caret
boundary transfers focus to the previous or next toolbar item. Home and End
remain native editing keys for a non-empty input.

Combobox filtering remains application-owned Signal state. The Web backend
derives only transient listbox semantics from the final retained children:
direct items receive option roles, an empty result clears any stale active
descendant, `data-empty` and `data-list-empty` expose styling state, and a
polite atomic status reports empty and recovered result counts. Typing into a
closed Combobox requests the existing model-owned open action before emitting
the query change, so an immediately empty filter cannot race popup mounting.

## Test gates before implementation is accepted

Tests should assert behavior and lifecycle, not only screenshots:

1. Generic popup enter and interrupted exit attributes, delayed removal,
   inert leaving shell, reduced-motion immediate completion, and no stale-node
   removal after rapid reopen.
2. Dialog focus trap/restoration and non-gestural mobile behavior.
3. Compact Sheet downward dismissal, below-threshold snap-back, horizontal
   gesture rejection, scroll-edge arbitration, form-control exclusion, and IME
   identity during visual viewport changes.
4. Menu touch selection, typeahead, nested keyboard traversal, pointer grace
   corridor, outside dismissal ordering, and viewport collision.
5. Context Menu long-press point placement and movement cancellation.
6. Select touch placement and no accidental opening-finger selection;
   Combobox composition plus active-descendant keyboard behavior.
7. Tooltip focus/hover transitions and explicit absence of touch-only opening.
8. Toast touch PointerEvent swipe, cancellation, interactive-child exclusion,
   direction state, F6 focus, and paused timers.
9. Tabs, Toolbar, ToggleGroup, Tree, and Accordion keyboard contracts.
10. A compact viewport pass over all 65 Gallery host pages, including the 64
    public component pages and `NativeExtension`, followed by the existing Web
    E2E suite and the full repository test suite.

## Delivery sequence

1. Add shared Web transition helpers and lifecycle unit tests.
2. Move Dialog, Sheet, DropdownMenu, ContextMenu, Tooltip, Select, and Combobox
   onto that lifecycle without changing the public schema.
3. Implement the compact Sheet gesture subset and responsive geometry.
4. Implement Pointer Event Toast dismissal.
5. Close Menu, Select, Combobox, ContextMenu, Tabs, Toolbar, Accordion, and Tree
   interaction gaps in small tested slices.
6. Tune CSS motion and mobile hit targets, then run reduced-motion and gallery
   visual qualification.

Each large completed slice is committed and pushed independently.

## Alternatives considered

### Adopt Base UI as the runtime

Rejected: Base UI's public API is compound React components. LUI's public API
stays LG element and attribute vocabulary; Base UI is used only as a behavior
and motion reference, so no React, provider state, or DOM abstraction leaks
into the schema.

### Invent LUI-only interaction contracts

Rejected: keyboard, focus, pointer, popup lifecycle, and transition contracts
are already standardized in a maintained, accessibility-reviewed reference.
Copying contracts from Base UI keeps Web behavior predictable and reviewable.

## Consequences

- Web interactive elements follow Base UI's behavior and motion contracts
  inside one LG-owned implementation; platform objects, the retained tree, and
  the schema stay LUI-owned.
- SwiftUI and Flutter keep native controls; this report does not make Web
  behavior a cross-platform detail.
- Interaction gaps close in tested slices; each slice carries its own
  qualification evidence before moving on.
