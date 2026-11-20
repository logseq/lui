# ADR 0008: Typed API ergonomics, compile-time completeness, and runtime hardening

Status: proposed

Date: 2026-11-21

## Context

[ADR 0007](0007-component-api-safety-and-default-aesthetics.md) landed across
PRs #386–#398 and delivered substantial safety and aesthetic improvements:
schema-backed per-kind property and event admission, mandatory identity and
algebraic sum types (`popover_target`, `split_sizing`), closed polymorphic
variants, anchorless dynamic segments inside restricted parents, runtime
numeric clamping, closure-safe reactive switches, cross-backend token parity,
and the three-tier `Lui.Ui` / `Lui.Elements` / `Lui.Raw` façade.

A post-landing review of `src/lui_elements.ml`, `src/lui_elements.mli`,
`src/lui_dynamic.ml`, `src/lui_ui_composites.ml`, `src/lui_tokens.ml`,
`src/lui_protocol.ml`, `src/lui_json_view.ml`, `ppx/lui_ppx.ml`,
`ppx/lui_nesting.ml`, and `tooling/test/component_schema_test.mjs` revealed
nine concrete follow-up gaps — spanning compile-time safety regressions,
PPX resolution holes, reactive patch-diffing inefficiencies, API surface
duplication, and Tier-1 / token adoption gaps — that should be resolved before
downstream apps (`logseq/mobile`, `logseq/logseq_journal`) standardize on the
typed surface.

### Observed gaps after ADR 0007

#### P1 — Safety regressions, PPX bugs, and runtime patch overhead

1. **`Slot_style` re-introduces runtime `Invalid_argument` exceptions.**
   `Slot_style.t` (`src/lui_elements.ml:1012-1017`) carries an untyped list of
   `(Lui_protocol.property * applier)` pairs and validates admission at mount
   time via `Lui_protocol.property_supported kind property`, raising
   `Invalid_argument "Slot_style: property is unsupported on this kind"`.
   `tooling/test/component_schema_test.mjs:62` explicitly skips `style` during
   signature auditing. The actual admission matrix varies significantly across
   the 18 constructors that accept `?style`:
   - `button`, `menu_item`, `text` reject `collision_padding`;
   - `button_group`, `toggle_group`, `switch`, `radio_group` reject typography
     properties (`font_size`, `font_weight`, `font_style`, `white_space`,
     `text_overflow`), `user_select`, and `collision_padding`;
   - `checkbox`, `toggle`, `select`, `combobox`, `text_field`, `secure_field`,
     `input`, `search_field` reject `white_space`, `text_overflow`, and
     `collision_padding`;
   - `dropdown_menu`, `popover` reject `white_space` and `text_overflow`.
   Any call passing one of those properties through `Slot_style.make` compiles
   cleanly and crashes at mount time.

2. **PPX fails to recognize the public `Lui.*` façade paths.**
   - `ppx/lui_ppx.ml:286-289` only recognizes `Slot_style.make` and
     `Lui_elements.Slot_style.make`, not `Lui.Elements.Slot_style.make` (or
     local module aliases to `Slot_style`). Reactive arguments inside
     `Lui.Elements.Slot_style.make ~opacity:(reactive ...) ()` fall through to
     the generic `scoped` adapter and fail to type-check.
   - `ppx/lui_nesting.ml:102-114` only maps `Lui_elements` and `Lui_ui`, not
     `Lui.Elements`, `Lui.Ui`, or `Lui.Raw`. Views written against the
     recommended `Lui.Elements` façade silently bypass compile-time nesting
     checks.
   - `ppx/lui_ppx.ml:186-189` (`structural_constructor`) only matches
     unqualified names and `Lui_elements.*`, missing `Lui.Elements.*`.

3. **`apply_popover_target` churns properties on every signal tick; `split`
   emits redundant initial sizing.**
   - `apply_popover_target` (`src/lui_elements.ml:1524-1543`) unconditionally
     calls `remove_properties` on all 8 positioning keys (`PopupX`, `PopupY`,
     `AnchorValue`, `AnchorTarget`, `AnchorRect`, `AnchorAlignmentValue`,
     `AnchorOffset`, `AnchorAlignmentOffset`) before re-setting the active
     keys on every update of `target_signal`, generating noisy remove+set
     patch thrash on every frame (the exact pattern already fixed for
     `apply_split_sizing` in commit `dc6377d0`).
   - `split` (`src/lui_elements.ml:1549-1550`) unconditionally applies the
     default `Fraction 0.5` before mounting `sizing_signal`, emitting an
     extraneous `ProgressValue 0.5` followed immediately by `RemoveProp` when
     `sizing_signal` starts in `First_width`.

4. **`keyed_range` checkpoints the entire parent subtree and lacks legacy
   `keyed` optimizations.**
   - `keyed_range` (`src/lui_dynamic.ml:910-952`) runs
     `Lui_runtime.checkpoint_subtree application parent parent` on every signal
     emission, deep-cloning the parent and all sibling subtrees even when the
     keyed list is unchanged or only updates item payloads.
   - Unlike legacy `keyed`, `keyed_range` has no unchanged-order fast path, no
     O(n log n) minimal-move reconciliation (Fenwick / LIS), and appends newly
     mounted items at the end of the parent before issuing `MoveChild`
     (an earlier attempt in `729d2ed2` had to be reverted in `bb18c67d`).

#### P2 — Ergonomics, API surface inflation, and partial Tier-1 / token adoption

5. **Monomorphic slot types inflate `Lui_elements` and break uniform `reactive`
   authoring.**
   ADR 0007 proposed polymorphic phantom element types (`'kind el`), whereas
   Phase 3c landed 14 separate monomorphic abstract types (`toolbar_item`,
   `menu_entry`, `context_menu_entry`, `list_section_entry`, `tree_item`,
   `table_row`, `radio`, etc.). This produced:
   - 37 duplicated slot constructors (`toolbar_button`, `toolbar_icon_button`,
     `toolbar_text`, `toolbar_spacer`, ...);
   - 41 duplicated dynamic combinators (`if_toolbar_item`, `keyed_toolbar_item`,
     `reactive_toolbar_item`, `scoped_toolbar_item`, ...);
   - broken uniform `reactive (fun m -> ...) m_s` syntax inside restricted
     parents (callers must discover per-slot `reactive_*` functions);
   - a hand-maintained 5,598-line `src/lui_elements.mli` that already has
     copy-paste documentation drift (for example, `src/lui_elements.mli:5472-5475`).

6. **`Lui.Tokens` is only partially wired into `Lui.Elements` and `Lui.Ui`.**
   `Lui.Elements` still accepts raw `string` for `~background` / `~foreground`
   / `~border_color` and raw `int` for spacing and corner radius rather than
   `Tokens.color` / `Tokens.space` / `Tokens.radius` (and `Lui.Ui` only uses
   `Tokens.space` on `hstack` / `vstack`, leaving `color` and `radius` unused
   in public parameters). Furthermore, `Tokens.space_value` returns hardcoded
   pixel integers instead of platform-adaptive rhythm metrics.

7. **`Lui.Ui` (`src/lui_ui_composites.ml`) leaks low-level `Lui_ui`, lacks a
   `.mli`, and has inconsistent dynamic semantics.**
   - `src/lui_ui_composites.ml:1` does `include Lui_ui`, mixing raw
     `int`-returning node builders (`Ui.row`, `Ui.column`, `Ui.text`,
     `Ui.create`) into the Tier-1 façade alongside `Lui_elements.t`-returning
     composites (`Ui.hstack`, `Ui.vstack`, `Ui.page`, `Ui.form_sheet`).
   - There is no `src/lui_ui_composites.mli` to pin the Tier-1 public contract.
   - `Ui.form_section` returns plain `Lui_elements.t` rather than a restricted
     section entry and is not registered in `Lui_nesting_schema`.
   - `Ui.form_section` (`src/lui_ui_composites.ml:40-44`) and `Ui.data_list`
     (`src/lui_ui_composites.ml:82-87`) eagerly map every child into a static
     `list_section_item [column [child]]`, leaving empty wrapper rows when a
     child is `if_` or collapsing multi-item `keyed` children into one row.
   - Parameter types are asymmetric between static and reactive forms:
     `Ui.form_sheet` exposes both `?confirm_disabled` and
     `?confirm_disabled_signal` with the same `bool Signal.t` type (rejecting
     a plain `bool`), while `Ui.form_field` takes `?error:string` vs
     `?error_signal:string option Signal.t` (and same for `?help` /
     `?help_signal`).

#### P3 — Subtle precedence, consistency, and wire-normalization rough edges

8. **Style precedence and overlay API inconsistencies in `Lui.Elements`.**
   - `text` (`src/lui_elements.ml:1673-1686`) executes `Slot_style.apply`
     *after* `apply_text_recipe`, allowing `~style` to clobber `~truncate:true`
     (`white-space`, `text-overflow`, `min-width`) or `~role` defaults.
   - `menu`, `submenu`, and `popover` omit `?style` where sibling overlay/menu
     primitives accept it.
   - `dropdown_menu` still takes flat `?at` / `?anchor` parameters instead of
     the sum-typed `popover_target` used by `popover`.

9. **Wire normalization and JSON decoder inconsistencies.**
   - `Lui_protocol.normalize_property_value` (`src/lui_protocol.ml:1628-1645`)
     does not clamp newer non-negative numeric properties (`CollisionPadding`,
     `FirstPaneWidth`, `AvailableHeight`, `GrowValue`, `ShrinkValue`,
     `TreeLevel`).
   - `Lui_json_view` splits enum error handling: older enum decoders return
     `None` on invalid input, while newer ADR 0007 decoders raise
     `Invalid_argument`.

## Decision

LUI will harden and complete the ADR 0007 typed architecture across four
targeted workstreams, all implemented in the shared OCaml layer and backed by
generated schema contracts and automated tests.

### 1. Zero-exception compile-time `Slot_style` and PPX façade parity

#### Capability-indexed `Slot_style`

Replace the single untyped `Slot_style.t` with phantom-capability-indexed slot
styles derived directly from `schema/components.json`:

```ocaml
module Slot_style : sig
  type -'caps t

  val empty : 'caps t
  val merge : 'caps t -> 'caps t -> 'caps t

  (* Universal slot properties admitted by all styleable kinds *)
  val make :
    ?opacity:float ->
    ?opacity_signal:float Signal.t ->
    ?label_opacity:float ->
    ?label_opacity_signal:float Signal.t ->
    ?hover_opacity:float ->
    ?hover_opacity_signal:float Signal.t ->
    ?pressed_opacity:float ->
    ?pressed_opacity_signal:float Signal.t ->
    ?disabled_opacity:float ->
    ?disabled_opacity_signal:float Signal.t ->
    ?max_height_viewport:float ->
    ?max_height_viewport_signal:float Signal.t ->
    unit ->
    [> ] t

  (* Capability-gated constructors / combinators *)
  val typography :
    ?font_size:int ->
    ?font_weight:font_weight ->
    ?font_style:font_style ->
    ?user_select:user_select ->
    unit ->
    [> `typography ] t

  val text_flow :
    ?white_space:white_space ->
    ?text_overflow:text_overflow ->
    unit ->
    [> `text_flow ] t

  val collision :
    ?collision_padding:int ->
    ?collision_padding_signal:int Signal.t ->
    unit ->
    [> `collision ] t
end
```

Each constructor in `Lui_elements.mli` constrains `?style` to the exact closed
capability set admitted by its `node_kind` (for example,
`button ?style:[ `typography | `text_flow ] Slot_style.t`,
`checkbox ?style:[ `typography ] Slot_style.t`,
`popover ?style:[ `typography | `collision ] Slot_style.t`,
`switch ?style:unit_caps Slot_style.t`). `Slot_style.apply` retains the
defensive check internally only as an invariant assertion, while
`tooling/test/component_schema_test.mjs` removes its `style` exemption and
verifies every capability bucket against `schema/property-admission.json`.

#### Full `Lui.*` module resolution in `lui_ppx` and `lui_nesting`

- Teach `ppx/lui_nesting.ml` (`module_kind`) and `ppx/lui_ppx.ml`
  (`structural_constructor` and `Slot_style` detection) to resolve:
  - `Lui.Elements` (including `module E = Lui.Elements` and `open Lui.Elements`),
  - `Lui.Ui` (including `module Ui = Lui.Ui`),
  - `Lui.Raw`,
  - `Lui.Elements.Slot_style.*`, `Lui_elements.Slot_style.*`, and local
    aliases (`module S = Lui.Elements.Slot_style`).
- Add PPX and nesting test fixtures written exclusively against `Lui.Elements`
  and `Lui.Ui` (without referencing internal `Lui_elements` directly) so façade
  regressions fail `dune runtest`.

### 2. Minimal-diff reactive positioning and fast `keyed_range`

#### Diff-aware `apply_popover_target` and single-emit `split`

- Track the previous `popover_target` mode per node (or remove only the keys
  absent from the new variant, matching `apply_split_sizing`):
  - `Cover` removes all positioning keys only when transitioning away from
    `At` or `Anchor`;
  - `At (x, y)` removes anchor keys only when transitioning from `Anchor` and
    updates `PopupX`/`PopupY` in place;
  - `Anchor { source; ... }` removes `PopupX`/`PopupY` only when transitioning
    from `At`, removes `AnchorTarget` or `AnchorRect` only when `source`
    changes variant, and updates the active anchor keys in place.
- In `split`, apply the default `Fraction 0.5` only when `sizing_signal` is
  `None` (and when explicit `?sizing` is omitted); when `sizing_signal` is
  provided, let its initial subscription emit the authoritative initial sizing
  without a spurious `ProgressValue 0.5` write.

#### Scoped checkpoints and O(n log n) reconciliation in `keyed_range`

- Replace parent-wide `checkpoint_subtree application parent parent` in
  `keyed_range` with segment-scoped rollback (tracking only the segment's
  child-id slice and newly allocated nodes, or checkpointing only on the
  exception-capable mount path without cloning sibling subtrees).
- Add an unchanged-key-order fast path (zero `MoveChild` / reorder work when
  the key sequence is identical, dispatching only item signal updates).
- Port the O(n log n) minimal-move reconciliation (LIS / Fenwick index tracking)
  and direct positional insertion (mounting new items at their target slot
  anchor rather than append-then-move) into `keyed_range`, backed by stress
  tests verifying patch counts, rollback isolation on mount exceptions, and
  duplicate-key disambiguation.

### 3. Polymorphic phantom elements (`'kind el`) and schema-generated `.mli`

#### Unify the 14 monomorphic slot types onto polymorphic `'kind el`

Converge `Lui_elements` on a single phantom-typed element representation:

```ocaml
type +'kind el

type general = [ `general ]
type t = general el
```

- Restricted containers declare the exact polymorphic-variant capability set
  they accept (for example, `toolbar : ... -> [ `toolbar_item ] el list -> t`,
  `dropdown_menu : ... -> [ `menu_entry ] el list -> t`,
  `context_menu : ... -> [ `context_menu_entry ] el list -> t`,
  `list_section : ... -> [ `list_section_entry ] el list -> t`).
- Elements valid in multiple containers return open/union phantom types (for
  example, `[ `general | `toolbar_item ] el` for standard buttons and text
  items where protocol admission allows, and narrower types such as
  `[ `menu_entry | `context_menu_entry ] el` for `menu_item`), eliminating
  duplicate `toolbar_*` / `menu_*` constructors where signatures are identical
  and keeping dedicated constructors only when wire admission genuinely differs
  (such as `context_menu` item restrictions).
- Polymorphic dynamic combinators (`if_ : test:bool Signal.t -> 'k el -> 'k el`,
  `keyed : ... -> ('a Signal.t -> 'k el) -> 'k el`,
  `scoped : (context -> 'k el) -> 'k el`, and bare `reactive (fun v -> ...) s`)
  automatically preserve `'k` inside any restricted parent, retiring the 41
  monomorphic `if_*` / `keyed_*` / `reactive_*` / `scoped_*` duplicates.
- Generate `src/lui_elements.mli` (or its per-kind signature sections) directly
  from `schema/components.json` via `tooling/generate_component_schema.mjs`
  with a CI freshness check, eliminating hand-edited 5,500-line `.mli` drift
  and copy-paste doc errors.

Compatibility aliases for the Phase 3c monomorphic type names and `*_toolbar_item`
helpers will be kept in a deprecated transition layer for one release window
and documented in `docs/api-migrations.md`.

### 4. Clean `Lui.Ui` Tier-1 contract, token adoption, and wire consistency

#### Explicit `src/lui_ui_composites.mli` without `include Lui_ui`

- Remove `include Lui_ui` from `src/lui_ui_composites.ml` and add an explicit
  `src/lui_ui_composites.mli` exporting only `Lui_elements.t`-returning Tier-1
  composites and `Tokens`. Low-level imperative `int`-returning node builders
  remain under `Lui_ui` (and `Lui.Raw` where appropriate), never shadowed into
  `Lui.Ui`.
- Harmonize static vs reactive parameters across `Lui.Ui`:
  - `Ui.form_sheet`: `?confirm_disabled:bool -> ?confirm_disabled_signal:bool Signal.t`
    (so static `~confirm_disabled:true` and PPX
    `~confirm_disabled:(reactive f s)` both type-check cleanly).
  - `Ui.form_field`: `?error:string option -> ?error_signal:string option Signal.t`
    (or accept `?error:string` while allowing PPX `~error:(reactive f s)` on
    `string option Signal.t` with documented symmetry and `?help` matching).
- Fix dynamic children in `Ui.form_section` and `Ui.data_list`:
  - Accept `[ `list_section_entry ] el list` (or expose explicit
    `Ui.form_row` / `Ui.data_row` builders that produce section entries) so
    `if_` and `keyed` mount/unmount real section rows without empty wrapper
    shells, and register `Ui.form_section` in `Lui_nesting_schema`.

#### First-class `Lui.Tokens` adoption and platform-adaptive metrics

- Expose typed token parameters (`?background:Tokens.color`,
  `?foreground:Tokens.color`, `?border_color:Tokens.color`,
  `?gap:Tokens.space`, `?padding:Tokens.space`, `?corner_radius:Tokens.radius`,
  plus reactive counterparts where admitted) across `Lui.Ui` composites first
  and via typed helpers / constructors in `Lui.Elements`, keeping raw pixel/CSS
  strings under explicit `` `px n `` / `` `token s `` constructors.
- Move `Tokens.space` resolution from hardcoded static integers in
  `src/lui_tokens.ml` to platform-adaptive semantic metrics (preserving exact
  desktop vs touch density across macOS, iOS, Android, and Web).

#### Style precedence, overlay consistency, and wire normalization

- In `text`, `heading`, `paragraph`, and `label`, apply `Slot_style.apply`
  *before* `apply_text_recipe` (or merge `truncate` invariants after user
  slot styles) so `~truncate:true` cannot be silently broken by `~style`.
- Add capability-checked `?style` to `menu`, `submenu`, and `popover`, and
  migrate `dropdown_menu` from flat `?at` / `?anchor` to `popover_target`
  (with a documented migration entry).
- Extend `Lui_protocol.normalize_property_value` to clamp `CollisionPadding`,
  `FirstPaneWidth`, `AvailableHeight`, `GrowValue`, `ShrinkValue` (`>= 0`,
  finite fallback on non-finite floats with diagnostic warning), and
  `TreeLevel` (`>= 1`).
- Unify `Lui_json_view` enum parsing so invalid enum values consistently
  return `None` (with structured diagnostic reporting) rather than mixing
  `None` and `Invalid_argument`.

## Consequences

### Positive

- Eliminates the last compile-time-accepted `Invalid_argument` hole in
  `Lui.Elements` (`Slot_style`), closing the `component_schema_test.mjs`
  exemption.
- Views authored exclusively against the public `Lui.Elements` / `Lui.Ui`
  façade get full PPX reactive rewrites and static nesting checks.
- Reactive popovers, splits, and dynamic keyed lists inside restricted parents
  emit minimal patch batches without parent-wide subtree checkpoint overhead.
- Unifying onto polymorphic `'kind el` removes ~78 redundant slot constructors
  and dynamic adapters, restores uniform `reactive` syntax inside restricted
  parents, and replaces hand-maintained `src/lui_elements.mli` with
  schema-generated signatures.
- `Lui.Ui` presents a clean, self-contained Tier-1 `.mli` surface with
  dynamic-safe `form_section` / `data_list` rows and consistent static/signal
  parameter types.

### Negative

- Changing `Slot_style.t` to capability-indexed `-'caps Slot_style.t`,
  migrating `dropdown_menu` to `popover_target`, removing `include Lui_ui`
  from `Lui.Ui`, and changing `Ui.form_sheet ~confirm_disabled` are source
  breaking changes that require staged aliases and entries in
  `docs/api-migrations.md`.
- Refactoring the 14 monomorphic slot types to polymorphic `'kind el` touches
  `Lui_elements`, `ppx/lui_ppx.ml`, `ppx/lui_nesting.ml`, `Lui_ui_composites`,
  and example/test suites; polymorphic variant type errors require clear type
  aliases in generated `.mli` files so compiler diagnostics remain readable.
- Implementing O(n log n) positional reconciliation in `keyed_range` must
  carefully preserve multi-node segment invariants and rollback guarantees
  (avoiding the regression that caused `729d2ed2` to be reverted in `bb18c67d`).

## Rejected alternatives

### Keep `Slot_style.t` untyped and rely on runtime validation or silent drops

Rejected for the same reason ADR 0007 rejected `apply_universal`: silently
dropping style properties hides bugs, while throwing `Invalid_argument` at
mount time violates ADR 0007's core guarantee that invalid `(kind, property)`
pairs fail `dune build`.

### Keep the 14 monomorphic slot types and auto-generate all 41 dynamic adapters

Rejected because code generation would only mask the maintenance cost while
leaving callers with poor ergonomics: users and AI agents would still have to
memorize per-slot `if_*` / `keyed_*` / `reactive_*` names and could not use
uniform `reactive` syntax inside `toolbar`, `dropdown_menu`, or `list_section`.

### Rewrite `keyed_range` by re-introducing wrapper `box ~display:contents` anchors

Rejected because ADR 0007 specifically eliminated wrapper anchors so dynamic
children work inside restricted native parents (`toolbar`, `dropdown_menu`,
`context_menu`, `table`, `list_section`) on Apple SwiftUI and Android Compose.
Reconciliation improvements must stay anchorless.

## Delivery sequence

Every public API, wire-contract, default, or event behavior change must be
recorded in `docs/api-migrations.md` with concrete before/after examples.

1. **Phase 1 — P1 safety, PPX façade parity, and reactive diff fixes (low-risk, high-impact).**
   - Fix `ppx/lui_ppx.ml` and `ppx/lui_nesting.ml` to resolve `Lui.Elements`,
     `Lui.Ui`, `Lui.Raw`, and `Lui.Elements.Slot_style.make` (+ aliases), with
     dedicated façade tests.
   - Make `apply_popover_target` diff-aware and prevent `split` from emitting
     spurious default `Fraction 0.5` when `sizing_signal` is supplied.
   - Replace `Slot_style.t` with capability-indexed `-'caps Slot_style.t`,
     remove the `style` exemption from `tooling/test/component_schema_test.mjs`,
     and fix `text` `Slot_style` vs `~truncate` ordering.
   - Extend `Lui_protocol.normalize_property_value` for the missing numeric
     properties and unify `Lui_json_view` enum decoding.

2. **Phase 2 — Anchorless `keyed_range` performance and rollback isolation.**
   - Replace parent-wide `checkpoint_subtree` with segment-scoped rollback.
   - Add unchanged-order fast path, direct positional insertion, and O(n log n)
     minimal-move reconciliation with regression tests covering mount failures,
     reordering, insertions, removals, and duplicate keys.

3. **Phase 3 — Polymorphic `'kind el` unification and generated `src/lui_elements.mli`.**
   - Unify the 14 monomorphic slot types onto `'kind el` with polymorphic
     `if_` / `keyed` / `scoped` / `reactive` combinators (retaining temporary
     deprecated aliases during migration).
   - Generate `Lui_elements.mli` per-kind signatures from
     `schema/components.json` with a CI freshness check.
   - Align `menu` / `submenu` / `popover` `?style` and migrate `dropdown_menu`
     to `popover_target`.

4. **Phase 4 — Clean `Lui.Ui` Tier-1 contract and full `Lui.Tokens` adoption.**
   - Remove `include Lui_ui` from `src/lui_ui_composites.ml` and add
     `src/lui_ui_composites.mli`.
   - Fix `Ui.form_sheet` / `Ui.form_field` static vs reactive parameter
     symmetry and make `Ui.form_section` / `Ui.data_list` dynamic-child safe
     (registered in `Lui_nesting_schema`).
   - Wire `Tokens.color` / `Tokens.space` / `Tokens.radius` into `Lui.Ui` and
     `Lui.Elements` with platform-adaptive spacing metrics across Web, Apple,
     Android, and Native.

## Acceptance criteria

- `tooling/test/component_schema_test.mjs` audits every parameter including
  `?style` with zero exemptions; passing an unsupported slot style property to
  any constructor fails `dune build`.
- Views written exclusively with `Lui.Elements`, `Lui.Ui`, and
  `Lui.Elements.Slot_style.make` receive identical PPX reactive expansion and
  static nesting diagnostics as views written with `Lui_elements`.
- Updating `popover ~target:(reactive ...)` within the same mode emits zero
  redundant `RemoveProp` operations; mounting `split ~sizing:(reactive ...)`
  in `First_width` emits zero spurious `ProgressValue 0.5` operations.
- Reconciling a `keyed_range` with unchanged order or single-item insertion
  does not clone sibling subtrees and emits optimal positional inserts/moves,
  while still rolling back cleanly if a child mount raises.
- Restricted parents (`toolbar`, `dropdown_menu`, `context_menu`,
  `list_section`, `tree`, `table`, `radio_group`) accept uniform `if_`,
  `keyed`, `scoped`, and `reactive` expressions without per-slot adapter names,
  and `src/lui_elements.mli` is schema-verified in CI.
- `Lui.Ui` exposes a dedicated `.mli` with zero raw `int`-returning `Lui_ui`
  leaks, dynamic-safe `form_section` / `data_list`, symmetric static/reactive
  parameters, and platform-adaptive `Lui.Tokens` across all maintained backends.
