# Native Menu Trigger Node

Status: exploring

## Problem

Popup menus are expressed today by reusing `menu-item` as the trigger:

```text
menu-item (text, icon, width, size, ...)
  └─ dropdown-menu
       └─ menu-item × N   (the actual entries)
```

`LUIWireProtocol` recognizes this idiom — a `menu-item` whose only child is
a `dropdown-menu` renders as a native popup (`LUIMenuItemView` →
`Menu { LUINativeMenuActions } label: { itemLabel }`). The shape works, but
the trigger is semantically not a menu entry, and the reuse creates two
concrete mismatches (the driving consumer is `logseq_journal`'s account
menu, mounted from `app/journal_header.ml` via `V.Menu.create`):

1. `menu-item requires text` (wire validation), so an icon-only trigger
   cannot omit `text`. Consumers work around it with a whitespace
   placeholder (`text:" "`). Standard SwiftUI imposes no such requirement;
   `Menu { } label: { Image }` is a first-class form.
2. Consumers pin a fixed `width` on icon-only triggers to stop the label
   `HStack` (icon + `Text`) from stretching inside bar capsules. A
   hard-coded frame on a scalable SF Symbol can clip the icon — system
   images scale with Dynamic Type, and at large accessibility text sizes
   the rendered glyph can exceed a fixed point box.

The target semantic is the standard SwiftUI shape:

```swift
Menu {
    Button("Diagnostics") {}
    ...
} label: {
    Image(systemName: "person.crop.circle")
}
.accessibilityLabel("Account menu")
```

i.e. trigger label and menu content are different things, an icon-only
label needs no placeholder text, and the accessibility label lives on the
trigger rather than on a hidden text run.

## Proposal

Introduce a dedicated menu-trigger node kind (working name `menu-trigger`,
see Questions) in the wire schema, OCaml API, and backends:

- `menu-trigger` carries the trigger's label semantics — icon, optional
  text, accessibility label — and owns exactly one `dropdown-menu` child
  containing the menu entries. `text` is optional when `icon` is present,
  which removes the whitespace placeholder.
- On the Apple backend, `menu-trigger` maps directly to
  `Menu { entries } label: { label }`, preserving native popup presentation,
  dismissal, and toolbar placement (`isToolbarChild` must accept the new
  kind so triggers stay in native chrome).
- Wire validation distinguishes trigger from item: `dropdown-menu`
  children remain `menu-item`/`separator`-only; `menu-trigger` accepts
  only the `dropdown-menu` child (plus label content per the open question
  below).
- Consumers mount the menu through the new node and drop placeholder text
  and hard-coded trigger frames (whether sizing stays exposed on the
  trigger or defers to the native label is an open question). The
  accessibility label keeps flowing through the standard
  `accessibility-label` property.
- Existing behavior is preserved: menu entries keep their `variant` roles
  (including destructive), `on_press` callbacks, and `check_menu_item`
  checkmarks; `submenu` and `context-menu` paths that legitimately use
  `menu-item` children are unaffected unless the Questions section moves
  them too.

This is a coordinated change: it lands in LUI's wire schema, `Lui_ui`/
`Lui_elements` constructors, `LUIWireProtocol` validation, and the Apple
(and likely Flutter) backend; consumer apps then adapt their mount sites.

## Alternatives considered

### Keep `menu-item` + whitespace placeholder

Zero work and currently functional, but it keeps a schema lie: a
non-semantic whitespace run passes validation as a label, the trigger's
kind misdescribes its role, and the fixed-width clip risk stays. The
placeholder is also a magnet for future layout surprises (e.g. a backend
that trims or measures the label text).

### Model the trigger as a plain button plus manual menu state

Re-creates what SwiftUI `Menu` already provides (anchoring, dismissal,
popover placement, toolbar integration) in consumer code, and conflicts
with the native-first approach. Rejected.

### Only relax `menu-item`'s text requirement or adjust sizing

Making `text` optional when a `dropdown-menu` child is present, or
widening/removing the fixed frame, addresses only the symptoms. The node
kind still conflates trigger and item, and validation still cannot
distinguish "menu row" from "popup trigger" — it is a partial mitigation,
not the decision.

### Introduce a distinct `menu-trigger` node

Chosen direction above: the wire accurately models trigger vs. item,
icon-only labels become valid without placeholders, and the fix
generalizes to any future icon-only menu. Cost: a cross-repo coordinated
change plus a Flutter backend decision.

## Acceptance criteria

- The trigger and the menu items are distinct node kinds on the wire; a
  `menu-item` no longer serves as a popup trigger.
- An icon-only trigger mounts without any `text` placeholder and renders
  the native `Menu { } label: { Image }` form.
- The trigger icon is not clipped at default, compact, or large
  accessibility text sizes.
- The trigger's accessibility label (e.g. `"Account menu"`) is preserved
  and announced.
- Existing entries, their icons, destructive roles, and `on_press`
  callbacks behave as today; `check_menu_item` checkmarks still render.
- Menus work in portrait and landscape, inside compact toolbars, and
  under large accessibility text.
- Backend validation tests cover the new node kind: children rules, label
  requirements, toolbar membership.
- `dune build @all`, `dune runtest`, and `dune build @fmt` pass in LUI
  after the change.

## Risks

- **Cross-repo coordination.** The wire kind, OCaml constructor, protocol
  validation, and backend rendering land here in LUI; consumers must wait
  on a published LUI rev. Intermediate states can fail validation
  (`dropdown-menu` parent rules, `isToolbarChild`, `menu-item requires
  text`) or drop menus entirely.
- **Flutter backend parity.** `lui_flutter_backend` consumes the same
  wire; the new kind needs a Flutter equivalent (e.g. `PopupMenuButton`)
  or a defined fallback, or the Flutter host regresses.
- **Existing submenu users.** `Lui_elements.submenu` is the same
  `menu-item` + `dropdown-menu` nesting used inside menus; whether nested
  triggers migrate to the new node or keep `menu-item` affects validation
  on both sides.
- **Context menus.** `context-menu` shares `menu-item` semantics with its
  own strict rules (press support, property allowlist); widening or
  splitting `menu-item` roles must not weaken those rules.
- **Accessibility regression.** Removing the visible text run makes the
  trigger icon-only; if `accessibility-label` lands on the wrong node or
  is dropped by property support checks, assistive technologies lose the
  trigger name.

## Questions

- Should the new node be named `menu-trigger`, or should `dropdown-menu`
  itself be extended to carry trigger label semantics (no new kind)?
- Should the trigger accept arbitrary label content (a child view
  subtree) or stay limited to text+icon like `menu-item`?
- Which property carries the spoken label — `accessibility-label` on the
  trigger, or should `text` double as the accessibility label when
  present?
- Do submenus keep reusing `menu-item` as their in-menu trigger, or does
  the submenu trigger also migrate to the new node kind?
- Does `lui_flutter_backend` need a synchronized implementation in the
  same change, or is a later parity pass acceptable?
- Should `width`/`size` remain exposed on the trigger, or should the
  native `Menu` label size itself and the pins be dropped?
