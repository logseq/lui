# ADR 0007: Component API safety and default aesthetics

Status: proposed

Date: 2026-11-19

## Context

LUI's standard component catalog targets four maintained and experimental host
surfaces — Apple SwiftUI (macOS and iOS), Android Compose/JNI, Web/Melange
(browser and OCaml-owned WebView desktop), and the experimental self-drawn
OCaml native backend — from a single shared OCaml reactive model.

An audit of `src/lui_elements.mli`, `src/lui_protocol.ml`, `ppx/`,
`src/lui_element_combine.ml`, and the four host backends shows two systemic
problems:

1. **Compile-time permissiveness paired with zero-tolerance runtime exceptions.**
   Invalid states that could be rejected during `dune build` are admitted by
   the OCaml signatures, while both `Lui_runtime` and host stores respond to
   violations by throwing `Invalid_argument` or rejecting the entire atomic
   patch batch. On native bridges (`Lui_native_bridge`), an uncaught exception
   during `boot` or `dispatch_event` clears pending patches and leaves a blank
   or desynchronized screen unless the host coordinates an explicit `resync`.
2. **Good visual defaults depend on undocumented string conventions and
   drifting host tables.** Calling raw `Lui_elements` primitives without
   hand-tuned spacing, alignment, magic `style_class` strings, and platform
   conditionals produces cramped or overlapping layouts, while semantic color
   and typography tokens resolve inconsistently across Web, Apple, Android, and
   Native.

### Observed runtime-failure hazards

- **Over-broad constructor signatures (`apply_universal`).** Out of 84 public
  constructors in `src/lui_elements.mli`, 78 (92.9%) expose labelled parameters
  that `Lui_protocol.property_supported` rejects at runtime — 650 illegal
  `(constructor, ~prop)` pairs in total (572 excluding `?columns`, which is
  admitted only on `grid` yet exposed on every constructor). Examples such as
  `context_menu ~padding:8`, `tooltip ~background:"surface"`,
  `stepper ~gap:8`, and `accordion ~padding:12` compile without warning and
  raise `Invalid_argument` inside `Lui_runtime.set_prop`.
- **Dead event parameters.** Constructors expose event callbacks that
  `Lui_protocol.event_supported` rejects unconditionally at mount time via
  `require_event_supported`, including `toggle_button ~on_press`,
  `select ~on_input` and `~on_submit`, `dropdown_menu ~on_press`,
  `~on_input`, and `~on_submit`, `menu_item ~on_input`, `~on_submit`, and
  `~on_dismiss`, `list_item ~on_input`, and seven row-level handlers on the
  `tree` container (`~on_press`, `~on_change`, `~on_toggle`, and pointer
  handlers).
- **Mandatory wire properties typed as optional (`?`).** Only 1 of 84
  constructors (`edge_inset ~edge`) requires a non-optional parameter in
  `src/lui_elements.mli`, whereas `Lui_protocol.node_properties_supported` and
  host validators require mandatory properties or mutually exclusive modes on
  more than 24 node kinds (`icon`, `button`, `toggle_button`, `toggle`,
  `radio`, `radio_group`, `slider`, `number_stepper`, `progress`, `select`,
  `combobox`, `menu_item`, `menu_trigger`, `swipe_action`, `accordion`,
  `drawer`, `sheet`, `tooltip`, `avatar`, `image`, `file_image`,
  `file_preview`, `media_surface`, `stepper`, `step`, `timeline_item`, `tree`,
  `toolbar`, `bottom_tabs`, `bottom_tab`, `split`, `list_item`). Calls such as
  `icon []`,   ``button ~icon:`plus ~on_press:f []`` (missing `~label`),
  `slider ~value:0.5 []`, `sheet [body]`, `split left right`, and
  ``popover ~at:(0., 0.) ~anchor:`below [menu]`` compile cleanly and reject the
  patch batch at runtime.
- **Stringly-typed vocabularies and brittle numeric bounds.** Parameters with
  closed domains — `toolbar ?placement`, `sheet ?sizing`, `text ?font_style`,
  `?white_space`, `?text_overflow`, `?overflow`, `?text_decoration`, shared
  `?as_:element_tag` across inline and block kinds, and unvalidated
  `` `app of string `` icon slugs — fail at emit time. Responsive layout math
  that transiently produces a negative size (`avail - sidebar < 0`), a narrow
  `max_width < min_width` (`Lui_protocol.size_axis_supported`), or floating
  rounding outside `[0.0, 1.0]` for `opacity` aborts the entire render batch
  instead of clamping.
- **Reactive and batch-recovery hazards.**
  - Children-position `reactive` expands to an internal switch whose default
    comparator is polymorphic structural equality `Stdlib.(=)`. When a signal
    carries any record or variant containing a closure, lazy value, or nested
    signal, the second signal publication raises
    `Invalid_argument "compare: functional value"`.
  - `keyed` raises `Invalid_argument "keyed collection contains a duplicate key"`
    during `Signal.stabilize` when upstream data contains duplicate IDs.
  - `Lui_runtime.apply_pending_batch` re-queues rejected operations ahead of
    newer operations in `pending_ops`, poisoning subsequent `flush` calls until
    an external `resync` occurs.
  - Nested dynamic branches (`if_` or `reactive` inside `reactive`) mount an
    anchor ``box ~display:`contents``, which escapes static `lui_nesting` checks
    across module boundaries and fails child-kind validation inside restricted
    parents (`toolbar`, `dropdown_menu`, `context_menu`, `table`).
- **Cross-host admission drift.** Web-only properties (`~shrink`,
  `~on_focus_within`) raise `Invalid_argument` on `SwiftUIHost` and
  `KotlinHost`. Android's hand-written `LuiKindRules.kt` omits `grid`,
  `checkbox`, and `radio` from `isMainCrossKind` and `drawer` from
  `modalSurfaceKinds`, rejecting patches that OCaml, Web, and Apple admit.
  Apple's `LUIWireProtocol.swift` enforces `2...5` children on `bottom_tabs`
  and a restricted property whitelist on `context_menu` items that Web and
  `Lui_protocol` do not enforce.

### Observed default-aesthetics gaps

- **Z-stacked surface containers.** `card` and `panel` take `t list -> t` like
  `column`, but Web (`.lui-card > * { grid-area: 1 / 1 }`) and Android
  (`LuiStackLike`) stack multiple children on top of one another unless the
  caller wraps them in an explicit `column ~gap:12`. `panel` also defaults to
  zero padding, pressing text directly against its border.
- **Cross-backend semantic token and typography drift.**
  - `~background:"surface"` (used by `Lui_element_combine.settings_section`,
    `action_toolbar`, and `suggestion_list`) is defined on Android and Native,
    absent from `LUIThemePolicy.swift` on Apple, and absent from
    `lui_web_util.ml` on Web (emitting invalid CSS `background: surface`).
  - `~foreground:"secondary"` (used by `Lui_element_combine.labeled_row` and
    `feedback_banner`) resolves to `onSurfaceVariant` on Android, but maps to
    `--color-secondary` (`oklch(0.97 0 0)`) on Web light mode — rendering
    near-white text on a white background.
  - `~background:"card"` resolves on Web and Native, returns `nil` on Apple,
    and falls through to `Color.Transparent` on Android.
  - Typography classes used throughout `Lui_element_combine` and `Lui_ai`
    (`"headline"`, `"caption"`, `"semibold"`, `"single-line"`) are parsed on
    Apple and Android but have no corresponding rules in `platform/web/src/lui.css`.
- **Undocumented `style_class` handshakes and raw pixel boilerplate.** Native
  form sheets require five coordinated `style_class` tokens
  (`navigation-form`, `navigation-inline-title`, `form`, `navigation-actions`,
  `cancellation-action` / `confirmation-action`). Applications repeat manual
  `match platform with ...` pixel tables, manually pass `~min_width:0` to avoid
  flex overflow, and tune `row` (`gap = 0`, `cross = stretch` by default) on
  nearly every horizontal group.

Dynamic extensions ([ADR 0002](0002-dynamic-components.md)), platform tweaks
([ADR 0003](0003-platform-tweaks.md)), and the OCaml Web desktop host
([ADR 0005](0005-ocaml-web-desktop-host.md)) remain orthogonal and are
preserved by this decision.

## Decision

LUI will restructure its component authoring API around three rules:

1. **Composite-first authoring with typed design tokens** so idiomatic product
   views look native and balanced across macOS, iOS, Android, and Web with
   zero manual pixel or `style_class` plumbing.
2. **Schema-generated compile-time contracts** so unsupported properties,
   unsupported events, missing required labels, and illegal parent-child edges
   fail `dune build` rather than `emit_patch`.
3. **Clamp-and-recover runtime semantics** so dynamic data, window-resize math,
   closure-bearing signals, and transient host rejections degrade predictably
   without crashing or wedging the application.

All reusable component composition, validation normalization, and token schemas
live in the shared OCaml layer, preserving the Apple Swift packages, Android
Gradle/JNI backend, Web/Melange target, OCaml WebView desktop host, and
experimental self-drawn native backend.

### 1. Three-tier public API architecture

```text
Tier 1: Lui.Ui (opinionated semantic composites — ~90% of product & agent code)
    -> page, section, form_sheet, form_field, settings_section, confirm_dialog,
       hstack, vstack, action_toolbar, sidebar, composer, empty_state, loading

Tier 2: Lui.Elements (schema-generated typed primitives — ~9% custom layouts)
    -> per-kind constructors, typed tokens, phantom child kinds, typed events

Tier 3: Lui.Raw / Lui.Extension (explicit escape hatches — ~1% host integration)
    -> data_attrs, inline CSS variables, ADR 0002 extensions, ADR 0003 tweaks
```

- **Tier 1 (`Lui.Ui`, evolving `Lui_element_combine`)** becomes the primary
  recommended surface for applications and AI agents. Composites accept
  semantic content, state signals, and typed callbacks while owning spacing,
  touch targets, platform density, accessibility roles, and host presentation
  recipes internally.
- **Tier 2 (`Lui.Elements`)** exposes the closed standard node catalog with
  exact per-kind parameter lists generated from `schema/components.json`.
- **Tier 3 (`Lui.Raw` / `Lui.Extension`)** isolates web-specific DOM attributes
  (`data_attrs`) and registered native extensions/tweaks so low-level escape
  hatches do not pollute standard element autocompletion.

### 2. Compile-time elimination of illegal states

#### Schema-generated per-kind constructors

`tooling/generate_component_schema.mjs` becomes the single authority for
`Lui_elements` signatures as well as wire tables and host admission manifests:

- `apply_universal` is retired from the public signature; each constructor
  accepts only the properties and events admitted for its `node_kind`.
- Dead event parameters (`toggle_button ~on_press`, `select ~on_input`,
  `list_item ~on_input`, `dropdown_menu ~on_press`, `tree ~on_toggle`, etc.)
  are removed; tree-row properties and events move to dedicated `tree_item`
  constructors.
- Event handlers use payload-specific types (`unit -> unit`, `string -> unit`,
  `bool -> unit`, `float -> unit`) instead of raw `Lui_protocol.event -> unit`,
  with explicit `*_detail` parameters (`pointer_detail -> unit`) when modifier
  or coordinate metadata is needed.
- One generated admission manifest (`schema/property-admission.json`) drives
  OCaml, Web, Apple, and Android store checks, replacing hand-maintained
  per-kind predicates in `LuiKindRules.kt` and aligning child/count rules
  across hosts. Layout hints unsupported by a native host (`shrink`,
  `focus_within`) either live under explicit web-only escape hatches or degrade
  to documented no-ops rather than raising `Invalid_argument` on mobile.

#### Mandatory identity and algebraic sum types for exclusive modes

Constructors encode wire invariants in their parameter types:

```ocaml
(* Text buttons and icon-only buttons separate accessible-name obligations *)
val button :
  text:string ->
  ?icon:icon ->
  ?icon_placement:icon_placement ->
  ?variant:variant ->
  ?size:[ `default | `sm | `lg ] ->
  ?disabled:bool ->
  ?on_press:(unit -> unit) ->
  unit ->
  'p el

val icon_button :
  icon:icon ->
  label:string ->
  ?variant:variant ->
  ?size:[ `default | `sm | `lg | `icon ] ->
  ?disabled:bool ->
  ?on_press:(unit -> unit) ->
  unit ->
  'p el

(* Mutually exclusive positioning and split modes become sum types *)
type anchor_source =
  | Parent
  | Target of string
  | Rect of { x : float; y : float; width : float; height : float }

type popover_target =
  | Cover
  | At of float * float
  | Anchor of {
      side : anchor;
      source : anchor_source;
      align : anchor_alignment;
      offset : float;
      align_offset : float;
    }

type split_sizing =
  | Fraction of float
  | First_width of float

type split_motion = {
  duration_ms : int;
  easing : resize_easing;
  origin : float option;
}
```

Similarly, mandatory labels/values on `icon` (`~name`), `slider` (`~label`,
`~value`), `progress` (`~value`), `sheet` (`~title`), `accordion` (`~title`),
`toolbar` (`~label`), `radio_group` (`~label`), `tree` (`~label`), `stepper`
(`~active`), `step` (`~text`), `timeline_item` (`~title`), `bottom_tabs`
(`~label`), and `bottom_tab` (`~title`, `~on_press`) become non-optional (each
paired with `reactive` support through `lui_ppx`).

#### Closed variants for all enumerated domains

Remaining stringly-typed or integer-bounded domains become closed polymorphic
variants:

- ``heading_level = [ `h1 | `h2 | `h3 | `h4 | `h5 | `h6 ]``
- ``toolbar_placement = [ `automatic | `bottom | `navigation | `principal | `primary_action | `secondary_action | `status | `confirmation_action | `cancellation_action | `destructive_action | `top_bar_leading | `top_bar_trailing ]``
- ``sheet_sizing = [ `form | `fitted | `page ]``
- ``font_style = [ `normal | `italic | `oblique ]``
- ``white_space = [ `normal | `nowrap | `pre_wrap | `pre_line ]``
- ``text_overflow = [ `clip | `ellipsis ]``
- ``overflow = [ `visible | `hidden | `auto ]``
- Per-family semantic tags (`phrasing_tag` on `text`, `heading_tag` on
  `heading`, `list_container_tag` on `column`, `row_tag` on `row`) instead of a
  shared `element_tag` that fails at emit.

#### Phantom child kinds and anchorless dynamic segments

- Phantom element capabilities (`'kind el`) extend beyond `table_row_el` and
  `radio_el` to cover `dropdown_menu`, `context_menu` (statically excluding
  nested submenus and unsupported item props), `toolbar`, `list_section`,
  `menu_trigger`, and `tree`, guaranteeing cross-module type safety where
  file-local PPX AST inspection sees opaque values.
- Dynamic combinators (`if_`, `reactive`, `keyed`) mounted inside restricted
  parents allocate nested runtime dynamic segments directly against the parent
  node rather than inserting an intermediate ``box ~display:`contents`` node.

### 3. Runtime resilience: clamp, isolate, and self-heal

Dynamic values computed at runtime must never crash the process or permanently
wedge patch delivery:

- **Deterministic numeric clamping.**
  - Non-negative integer/float properties (`width`, `height`, `min_*`, `max_*`,
    `gap`, `padding_*`, `border_width`, `corner_radius`, `tooltip_delay`,
    `duration`, `resize_duration`) clamp negative inputs to `0`.
  - Size-axis conflicts follow CSS/SwiftUI precedence:
    `effective_max = max min_size max_size` and
    `effective_fixed = clamp fixed ~min:min_size ~max:effective_max`. Narrow
    window resizes never reject a batch.
  - Unit-interval floats (`opacity`, `hover_opacity`, `pressed_opacity`,
    `disabled_opacity`) clamp to `[0.0, 1.0]`; non-finite floats (`nan`,
    `infinity`) fall back to the property default and emit a structured
    diagnostic warning.
  - `tree_level` accepts 0-based or 1-based depth via a typed helper (normalizing
    wire levels to `>= 1`).
  - `bottom_tabs` degrades gracefully when dynamic tab counts fall outside
    `2...5` instead of throwing in `LUIWireProtocol.swift`.
- **Closure-safe reactive branch comparison.** Subtree `reactive` switches must
  never call raw `Stdlib.(=)` unguarded on arbitrary `'a`. When no custom
  `~equal` is supplied, the runtime uses physical equality `(==)` with a
  guarded structural fallback that catches `Invalid_argument _` (treating
  incomparable functional values as changed without raising), while encouraging
  narrow projections (`reactive (fun tab -> ...) (reactive Model.tab model_s)`).
- **Duplicate-key recovery in `keyed` and `virtual_rows`.** Duplicate keys emit
  a diagnostic with the offending key and state path and deterministically
  disambiguate subsequent entries rather than raising mid-stabilization.
- **Subtree `error_boundary` and automatic `resync`.**
  - `error_boundary ~fallback:(fun diagnostic -> view) child` checkpoints the
    subtree during mount and reactive updates; if user view code raises, the
    runtime restores the subtree checkpoint, logs the diagnostic, and mounts
    `fallback`.
  - If a host backend rejects a `PatchBatch`, `Lui_runtime` does not re-prepend
    the rejected delta onto `pending_ops`; instead, it marks the session for
    authoritative `resync_batch` recovery on the next synchronization turn.

### 4. Default aesthetics and cross-backend token parity

#### Canonical design tokens with CI parity checks

Colors, spacing, radii, and typography roles become typed vocabularies backed
by a canonical cross-platform specification:

```ocaml
type color =
  [ `background | `surface | `surface_raised | `card
  | `foreground | `muted_foreground
  | `primary | `secondary | `accent | `muted
  | `destructive | `warning | `success | `info
  | `border | `input | `ring | `glass | `bar | `transparent
  | `hex of int
  | `token of string ]

type space = [ `none | `xs | `sm | `md | `lg | `xl | `page | `px of int ]
type radius = [ `none | `sm | `md | `lg | `xl | `full | `px of int ]
type text_role =
  [ `display | `title | `headline | `subheadline | `body | `caption | `footnote | `code ]
```

- **Slot-aware contrast resolution.** Semantic tokens resolve according to
  their property slot (`background` vs `foreground` vs `border`). Selecting a
  container token in a foreground slot (or vice versa) is either statically
  disallowed by splitting `bg_color` / `ink_color` or mapped to its legible
  `on-*` counterpart on every backend, eliminating white-on-white text on Web
  and `Color.Transparent` fallbacks on Android.
- **Mandatory four-backend token parity test.** Every canonical `color`,
  `space`, `radius`, and `text_role` value must resolve on Web (`lui.css` and
  `lui_web_util.ml`), Apple (`LUIThemePolicy.swift`), Android (`LuiTheme.kt`),
  and Native (`lui_theme.ml`). A schema test (alongside extension fingerprint
  checks) fails CI if any backend omits a token or typography role.
- **Platform-adaptive rhythm.** Named spacing tokens (`` `page ``, `` `section ``,
  `` `md ``) resolve to platform-appropriate metrics (compact desktop density on
  macOS and desktop WebView; comfortable touch spacing and 44pt/48dp minimum
  hit targets on iOS and Android) without `match platform with ...` boilerplate
  in application views.

#### Intuitive container and text defaults

- **Vertical flow on `card` and `panel`.** Both `card` and `panel` lay out
  multiple children vertically (`column` semantics with default `gap = md`,
  `card` padding `lg`, and `panel` padding `md`), reserving Z-axis stacking for
  `stack` and `overlay`.
- **Ergonomic flex primitives.** `hstack` defaults to ``~cross:`center``,
  ``~gap:`sm``, and `min-width: 0` child shrink safety; `vstack` defaults to
  ``~cross:`stretch``, ``~gap:`md``, and `min-height: 0` scroll safety.
- **First-class text truncation and wrapping.** `text`, `heading`, `paragraph`,
  and `label` gain `~role:text_role` and `~truncate:bool` (setting single-line
  ellipsis + `min-width: 0` consistently across Web, Apple, Android, and
  Native).

#### Composite-first forms, sheets, and chrome (`Lui.Ui`)

Magic `style_class` combinations are replaced by typed `Lui.Ui` composites:

```ocaml
Ui.form_sheet
  ~title:"Edit profile"
  ~on_dismiss:(fun () -> send Close)
  ~cancel:("Cancel", fun () -> send Close)
  ~confirm:("Save", fun () -> send Save)
  ~confirm_disabled:(reactive (fun m -> String.trim m.name = "") model_s)
  [ Ui.form_section ~title:"Identity"
      [ Ui.form_field ~label:"Display name"
          ~error:(reactive Model.name_error model_s)
          (Elements.text_field
             ~text:(reactive Model.name model_s)
             ~placeholder:"Your name"
             ~on_input:(fun s -> send (SetName s)) ()) ] ]
```

`Ui.form_sheet`, `Ui.form_section`, `Ui.form_field`, `Ui.page`, `Ui.data_list`,
and `Ui.nav_bar` emit the required native presentation metadata internally so
iOS renders inset-grouped forms and inline navigation bars, Android renders
Material 3 Expressive sheets and outlined/filled surfaces, and Web renders
accessible, keyboard-navigable dialogs and forms from identical OCaml source.

## Consequences

### Positive

- 650+ illegal `(constructor, ~prop)` pairs, 10+ dead event handlers, and 24+
  missing-required-property failures move from runtime `Invalid_argument`
  crashes to instant `dune build` type errors.
- Dynamic layout calculations, narrow viewports, closure-carrying signals, and
  duplicate upstream keys no longer crash or permanently desynchronize hosts.
- Product and AI-generated views achieve consistent native aesthetics by
  default without memorizing magic `style_class` strings, hex codes, or
  per-OS pixel tables.
- Cross-backend drift between OCaml, Web, Apple, Android, and Native is caught
  automatically in CI through shared generated admission and token manifests.

### Negative

- Tightening `Lui_elements` signatures is a breaking source change for existing
  OCaml callers and requires staged migration aliases and entries in
  `docs/api-migrations.md`.
- Changing `card` and `panel` from Z-stack to vertical flow requires auditing
  existing callers that relied on implicit Z-stacking (migrating those sites to
  `stack` or `overlay`).
- Generating `Lui_elements` signatures and multi-host token/admission tables
  increases the scope of `tooling/generate_component_schema.mjs`.
- Phantom element types slightly lengthen compiler error messages when an
  element is placed in an incompatible container, requiring clear type aliases
  and documentation.

## Rejected alternatives

### Keep `apply_universal` and silently ignore unsupported properties at runtime

Rejected because silently dropping authored props (for example `tooltip ~width:200`
or `toggle_button ~on_press:save`) hides dead code, misleads authors and AI
agents about component capabilities, and causes subtle behavioral bugs. Static
rejection in `.mli` gives immediate feedback at authoring time.

### Disable runtime and host store validation

Rejected because untyped wire consumers (`Lui_json_view`, remote/plugin payloads,
and FFI boundaries) still cross the wire protocol. Clamping dynamic numeric
ranges while keeping structural/wire invariants validated preserves host safety
without crashing on benign layout math.

### Standardize on Tailwind/CSS class strings across all backends

Rejected for the same reasons as [ADR 0003](0003-platform-tweaks.md): CSS
classes have Web-specific cascade semantics and force SwiftUI and Compose
renderers to string-match ad-hoc class names (`"caption semibold single-line"`),
which already drifted across Web, Apple, and Android. Typed tokens and semantic
composites give every backend clean, exhaustive inputs.

### Implement high-level composites separately in Swift, Kotlin, and JavaScript

Rejected because duplicating product-level component logic across host
languages violates LUI's shared-OCaml architecture and multiplies behavioral
drift. Hosts own platform rendering chrome, accessibility bridges, and native
animations; composition and state live once in OCaml.

## Delivery sequence

Every public API, wire-contract, default-layout, or event change below must be
recorded in `docs/api-migrations.md` with before/after migration examples.

1. **Phase 1 — Runtime resilience and cross-host bug fixes (non-breaking).**
   - Replace unguarded `Stdlib.(=)` in reactive subtree switches with
     closure-safe equality.
   - Clamp negative geometry, `min`/`max` axis inversions, and `[0.0, 1.0]`
     opacity bounds across `Lui_protocol` and all host stores.
   - Make `keyed` / `virtual_rows` deduplicate duplicate keys with structured
     diagnostics, and replace `pending_ops` re-queueing on batch rejection with
     coordinated `resync_batch` recovery.
   - Generate Android property/kind admission from the shared schema manifest
     and degrade web-only layout hints safely on native hosts.
2. **Phase 2 — Cross-backend token and typography parity (non-breaking).**
   - Add missing `surface`, `muted`, `card`, and slot-aware `secondary`
     foreground mappings plus `.headline`, `.caption`, `.semibold`, and
     `.single-line` rules across Web, Apple, Android, and Native, gated by a
     CI token-parity test.
   - Add `error_boundary` to `Lui_elements`.
3. **Phase 3 — Schema-generated typed primitives (`Lui.Elements`).**
   - Generate per-kind `Lui_elements` constructors from
     `schema/components.json`, removing unsupported `apply_universal` props and
     dead event parameters.
   - Introduce `icon_button`, sum-typed `popover_target` and `split_sizing`,
     closed polymorphic variants for all enumerated props, typed event
     callbacks, phantom container child types, and anchorless nested dynamic
     segments.
4. **Phase 4 — Composite-first `Lui.Ui` kit and container defaults.**
   - Default `card` and `panel` to padded vertical flow (migrating Z-stack
     callers to `stack` / `overlay`), introduce `hstack`, `vstack`,
     `~role:text_role`, `~truncate:bool`, and typed `color` / `space` /
     `radius` tokens, and expand `Lui.Ui` (`page`, `form_sheet`,
     `form_section`, `form_field`, `data_list`) across Gallery and examples.

## Acceptance criteria

- Zero constructors in `Lui_elements.mli` expose a property or event callback
  rejected by `Lui_protocol.property_supported` or `event_supported` (verified
  by `tooling/test/component_schema_test.mjs`).
- Omitting a mandatory accessible name, value, or addressing mode on standard
  elements fails `dune build` rather than throwing during `flush`.
- Passing closure-bearing records through `reactive`, duplicate keys into
  `keyed`, or narrow/negative resize dimensions into layout props completes
  `flush` without uncaught exceptions or host generation desynchronization.
- Every canonical `color`, `space`, `radius`, and `text_role` token resolves to
  a visible, contrast-checked value on Web, Apple SwiftUI, Android Compose, and
  experimental Native, verified by automated CI parity tests.
- Authoring a multi-field edit sheet, settings page, or card layout via
  `Lui.Ui` requires zero raw `style_class` strings and zero per-OS pixel
  branches while preserving native Apple, Android, and Web presentation.
