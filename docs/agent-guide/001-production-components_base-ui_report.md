# Base UI Web interaction and motion report

Status: implementation in progress

## Scope and reference

This report defines how LUI's Web backend should use Base UI as its behavior
and motion reference without adding React or copying Base UI's public compound
component API. The reference is the local Base UI checkout at commit
`1e208a9`, together with the official component and animation documentation.

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

Select selected-item alignment and Combobox empty-result semantics are now
implemented. The remaining work in this report is the collection/control
matrix below, plus localized application-owned wording for asynchronous
Combobox loading states when LUI gains a corresponding product requirement.

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
| `dialog` | Portal, backdrop dismissal, Escape, modal focus trap, focus restoration, enter and exit phases; no swipe gesture | Focus behavior exists, but opening and removal are instantaneous and expose only a private modal state attribute | Add the shared popup transition lifecycle. Keep Dialog non-gestural. |
| `sheet` | Use Drawer behavior: edge presentation, swipe dismissal, scroll-edge arbitration, pointer/touch distinction, safe handling of interactive descendants and software keyboards | It is a permanently right-sided Dialog with no responsive bottom-sheet layout, gesture state, or exit animation | Keep the public name Sheet. Use a right sheet on wide screens and a bottom sheet on phones. Add downward touch swipe only on the compact layout. Do not add Drawer snap-point or nesting API. |
| `dropdown-menu` | Tap/press and keyboard open, outside/Escape dismissal, roving highlight, typeahead, nested submenu keyboard behavior and pointer grace corridor, collision-aware placement, transition phases | Basic arrows and nested hover exist. Close is immediate, placement has no collision fallback, hover timeout has no pointer corridor, and typeahead is absent | Add shared popup phases, typeahead, collision placement, touch-safe press ordering, and a submenu grace polygon. Preserve recursive LUI menus. |
| `context-menu` | Right click, keyboard ContextMenu/Shift+F10, and 500 ms long press; cancel long press after more than 10 px movement; same menu behavior as Menu | Point placement, movement cancellation, and keyboard restoration are covered. Closed menus no longer intercept document-level Escape/Home/End keys | Keep keyboard handling gated by the model-owned open menu. Always keep a visible primary route to the same actions. |
| `select` | Listbox semantics, typeahead, selected-item alignment for mouse/keyboard, ordinary anchored placement for touch, safe press-release selection, scrolling active item, complete keyboard navigation | Keyboard/mouse selected-item alignment, touch-safe anchored placement, collision fallback, typeahead, and press-release ordering are covered | Keep the implementation internal to Web and preserve the compact cross-platform API. |
| `combobox` | Editable input with `aria-activedescendant`, filtered listbox, composition-safe input, arrows/Home/End/Enter/Escape, touch trigger handling, live status where needed | Native composition, retained input identity, Signal filtering, empty/recovery state, active-descendant cleanup, live status, touch opening, popup lifecycle, and collision behavior are covered | Preserve the native input and composition buffer. Application-specific asynchronous or localized status wording can be added only when required; never replace editing with a contenteditable surface. |
| `tooltip` | Delayed pointer hover and immediate keyboard focus. Escape dismisses. A tooltip is not a touch or screen-reader discovery mechanism; the trigger needs its own accessible name | Hover/focus behavior exists, but display changes instantly | Add start/end transition phases. Do not invent Web long-press tooltip behavior. Ensure icon-only triggers remain independently named. |
| `toast` | F6 focus transfer, pause on interaction, stack variables, pointer-event swipe, direction lock, threshold/velocity behavior, and interactive descendants excluded from swiping | F6 and pause exist. Swipe is mouse-only, uses inline transform and a fixed threshold, and can steal interaction from descendants | Use Pointer Events, pointer identity/capture, Base UI-style swipe variables and state attributes, interactive-target exclusion, directional damping, and down/right dismissal. |

### Collections and controls

| LUI element | Base UI contract to match | Current Web gap | Required decision |
| --- | --- | --- | --- |
| `accordion` | Native button trigger, independent tab stops, controlled disclosure, retained content for exit/size animation, `data-panel-open` | Uses `details`/`summary` but cancels its native toggle. Content has no measured/open-close transition attributes | Keep controlled state, expose button-quality semantics, and animate a retained content wrapper without roving focus. |
| `tabs` | Roving focus with orientation, disabled-item skipping and wrapping. Default arrow keys move focus only; Enter/Space activates. Indicator and panels may animate with activation direction | Horizontal focus exists but has no orientation-aware vertical path, panel semantics, direction, or indicator lifecycle | Preserve focus-only arrows. Add orientation, activation direction, tabpanel linkage, and CSS indicator/panel transitions without changing selection on focus. |
| `toolbar` | One tab stop, orientation-aware roving focus, Home/End, disabled-but-focusable controls, nested groups, and careful input arrow handling | Native input focus targets, select-all-on-entry, composition, selection, modifier, caret-boundary, and RTL handling are covered. Disabled-but-focusable items and nested group metadata remain incomplete | Match Base UI focusability rules. A horizontal toolbar may contain at most one text input and it should be last; input editing keys win while focus is inside it. |
| `toggle-group`, `button-group` | Orientation-aware roving focus and wrapping; toggle group has single/multiple selection semantics | Only horizontal keys are handled | Add vertical orientation behavior where the public orientation property is admitted. Keep activation separate from focus. |
| `tree` | ARIA tree roving focus, disclosure and selection keys, disabled handling, typeahead where labels exist | Core arrows/Home/End and disclosure now work | Add typeahead and mobile hit-target qualification; no popup animation applies. |
| `slider` | Native pointer/touch drag and keyboard behavior including arrows, Home/End, PageUp/PageDown and Shift+Arrow large steps | Native range input already supplies single-thumb behavior | Continue using native range input. Test the native key/touch contract; do not port Base UI's multi-thumb machinery because it is outside LUI's public API. |
| checkbox, switch, radio, toggle, buttons | Native activation, focus-visible behavior, disabled semantics, and local state animation | Semantics mostly exist; hold uses parallel mouse/touch listeners and local state motion/reduced-motion coverage is inconsistent | Prefer Pointer Events for hold tracking, cancel on movement/capture loss, and add reduced-motion rules. Keep native input/button activation. |
| text inputs and textarea | Native editing, selection, clipboard, IME composition, mobile keyboard, and textarea auto-size | Composition and auto-size foundations exist; Chinese composition is covered in Combobox, but not yet inside Sheet during visual viewport changes | Retain native controls and add the remaining Sheet regression. Motion must never write the input value or recreate it. |

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
10. A mobile viewport gallery pass for every interactive component, followed
    by the existing Web E2E suite and the full repository test suite.

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
