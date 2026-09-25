# Native Menu Trigger Node

Status: implemented

## Problem

Popup menus were expressed by reusing `menu-item` as the trigger:

```text
menu-item (text, icon, width, size, ...)
  └─ dropdown-menu
       └─ menu-item × N   (the actual entries)
```

The reuse created two concrete mismatches (the driving consumer is
`logseq_journal`'s account menu, mounted from `app/journal_header.ml` via
`V.Menu.create`):

1. `menu-item requires text` (wire validation), so an icon-only trigger
   needed a whitespace `text:" "` placeholder.
2. Consumers pinned a fixed `width` on icon-only triggers to stop the
   label `HStack` stretching inside bar capsules; a hard-coded frame on a
   scalable SF Symbol can clip the icon at large accessibility text
   sizes.

## Decision

A dedicated `menu-trigger` node kind models the SwiftUI shape
`Menu { entries } label: { label }`: trigger label and menu content are
different nodes, icon-only labels need no placeholder text, and the
accessibility label lives on the trigger.

### Wire schema

- `menu-trigger` is a container kind (`schema/components.json`,
  generated into `LUINodeKind.menuTrigger` / `Lui_protocol.MenuTrigger`).
- Its restrictive property matrix is
  `text`, `icon`, `accessibility-label`, `enabled`, `foreground`,
  `style-class` (+ always-allowed `accessibility-identifier`). No
  `width`/`size`: the native `Menu` label self-sizes.
- Children rules: `menu-trigger` accepts exactly one `dropdown-menu`
  child. `dropdown-menu` accepts `menu-item`/`menu-trigger`/`divider` —
  in-menu submenu triggers are `menu-trigger` nodes. `menu-item`
  accepts only `context-menu` metadata; `context-menu` keeps its strict
  `menu-item`/`divider`-only children.
- `menu-trigger` requires `text` or `icon`; an icon-only trigger
  requires `accessibility-label`. `text` doubles as the accessible name
  when present. Toolbar children include `menu-trigger`.

### OCaml API

- `Lui_ui.menu_trigger` creates the node.
- `Lui_elements.menu` composes `menu-trigger` + `dropdown_menu` in one
  call; `Lui_elements.submenu` mounts the same pair for in-menu
  submenus. `Lui_elements.menu_trigger` mounts the raw pair when a
  custom `dropdown-menu` (anchor props etc.) is needed.
- `menu_item`, `check_menu_item`, and `separator` are unchanged; menu
  entries keep `variant` roles, `on_press`, and checkmarks.
- `submenu`'s former `menu_item`-trigger signature dropped
  `role`/`variant`/`selected`/`checked` (meaningless on a trigger) and
  gained `label` (accessibility label) and `disabled_signal`.
- `lui_json_view` maps `"menu-trigger"` (and `"submenu"`) onto the new
  constructors.

### Apple backend

- `LUIMenuTriggerView` renders `Menu { LUINativeMenuActions(menu) }
  label: { icon? + text? }` with `.disabled(!isEnabled)`,
  `.accessibilityLabel(text ?? accessibilityLabel)`, and
  `.accessibilityIdentifier` — no fixed frame.
- `LUINativeMenuActions` renders `.menuTrigger` children as nested
  `Menu`s (submenus); the `.menuItem` branch is Button-only.
- `LUIMenuItemView` lost its submenu `Menu` branch (menu-item can no
  longer host a `dropdown-menu`).
- `isToolbarChild` and the toolbar run grouping include `menuTrigger`,
  so triggers join native toolbar control runs.
- Validation: `menu-trigger` accepts only a `dropdown-menu` child and
  requires text-or-icon (+ `accessibility-label` when icon-only), and
  exactly one `dropdown-menu` child; `menu-item`/`dropdown-menu` parent
  rules match the OCaml side.
- iOS `confirmationDialog` menus containing `menu-trigger` fall back to
  the anchored popover (sheets cannot nest menus) via
  `LUIMenuPresentationPolicy`.

### Flutter

Parity is deferred: `menuTrigger` lands in the generated shared schema,
but `lui_flutter_backend` does not render it yet. Consumers that run on
Flutter keep working because nothing mounts `menu-trigger` there.

## Migration

- `menu_item [ dropdown_menu entries ]` → `submenu ... entries` (or
  `menu`/`menu_trigger`).
- Icon-only triggers: `menu ~icon:(`app "...") ~label:"<spoken name>"
  entries` — drop `text:" "` and fixed `width`.
- `examples/gallery` mounts `submenu` for its two in-menu submenus.

## Alternatives considered

### Keep `menu-item` + whitespace placeholder

Keeps a schema lie and the fixed-width clip risk; rejected.

### Model the trigger as a plain button plus manual menu state

Re-creates what SwiftUI `Menu` already provides; rejected.

### Only relax `menu-item`'s text requirement or adjust sizing

Partial mitigation; the kind still conflates trigger and item.

### Extend `dropdown-menu` itself with trigger label semantics

Merges trigger and content concerns; `dropdown-menu` is also mounted
standalone for anchored popovers where no trigger label exists.

### Allow arbitrary label subtrees on the trigger

`menu-item`'s text+icon vocabulary covers every real trigger; keeping
the vocabulary identical lets validation and backends reuse the same
label rules.

## Consequences

- `menu-trigger` and `menu-item` are distinct kinds end to end; a
  `dropdown-menu` child under `menu-item` is rejected in OCaml and
  Swift validation.
- Icon-only triggers mount without `text` placeholders and render the
  native `Menu { } label: { Image }` form; no `width`/`size` exists on
  the trigger, so nothing can clip the scalable icon.
- `submenu` is a breaking API change: callers pass `label`/`disabled`
  instead of the old `role`/`variant`/`selected`/`checked` props.
- Consumers on Flutter cannot mount `menu-trigger` yet; the parity
  pass is deferred.
- `dune build @all`, `dune runtest`, `dune build @fmt`, `swift test`,
  and the schema generator tests pass with the change.
