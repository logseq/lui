# Reachable Logseq NSH provider rejections

This source audit follows production Logseq callers into explicit NSH preflight
rejections. It does not claim that these interactions were executed or that this
is a complete component inventory. The initial application startup gate exercises
the journal and sidebars; successful startup does not cover these branches.

Reviewed revisions:

- LUI: `ac3ecf75580144d93c97dfcd4d3d7a0ff0ad5cfd`.
- Logseq NSH host: `9b883dbc80b6af46d9d05d9a7ad760b3f50635bd`.
- NSH: `bfa15d0c843c0d6f5bf3a2a230e8ca56b876b61c`.

Line references below are relative to those checkouts. Logseq paths start at
`deps/ui/`; LUI paths start at `platform/nsh/src/`.

## 1. Editing markup: inline delimiters and relative code size

`src/editor/edit_view.ml:437` publishes standard Text `display="inline"` when a
markup delimiter is shown, and `none` when hidden. This branch is mounted by
`src/editor/editor_surface.ml:86`. Independently, `frag_binds` at
`edit_view.ml:399` publishes `font-size="0.9em"` for code fragments; the binds are
applied to actual Text at lines 432, 443, 455 and 477. The clipboard inspection
result also authors `0.85em` in `src/pages/bug_report.ml:107`.

LUI `style.rs:848` explicitly rejects Inline, InlineBlock and InlineFlex because
there is no native inline-flow provider. `FontSize::native` at `style.rs:779`
rejects relative em scaling other than inheritance at 1em. These are two distinct
failures in an important interaction, grouped here rather than counted as two
component gaps.

The existing NSH text/style engine should remain the rendering owner. Its public
`Styled::text_size` takes `Length`; it does not supply the inherited parent font
metric needed to turn 0.9em into points. A fixed 16-point multiplication would
change the contract. Similarly, replacing every inline delimiter with a generic
block is not a demonstrated inline-flow implementation. Prefer a narrow editor
run composition using the existing authoritative editor geometry, or a scoped
inherited-font resolution addition, before claiming fidelity.

The cheapest positive build check is an actual private-graph edit scenario that
reveals emphasis/code delimiters and retains a code fragment, then inspects the
native body and edit continuity. Generated Display exhaustiveness already catches
new enum variants, but an explicit `Err` arm still compiles. Open FontSize strings
are not a canonical closed enum; compiler-only enum checks cannot validate them.

## 2. Property and table menus remain externally anchored menus

Actual callers outside the header More menu include:

- `src/properties/properties_menu.ml:605` creates a menu-role Popover;
  `:629` opens the anchored configuration menu.
- `src/properties/properties_value.ml:1179` mounts the extends picker as a
  menu-role Popover.
- `src/views/views_popup.ml:330`, `:359` and `:537` mount table/view menus.

LUI `render.rs:1703` rejects `popover` with `role="menu"`. The header More producer
conversion being developed separately does not cover these callers. Pinned NSH
`MenuProps` (`nsh-base/src/menu.rs:1299`) has controlled `open` and a trigger Slot,
but no external ElementRef/rectangle anchor. Menu creates its private anchor at
`:1415`, attaches it only to the trigger at `:1492`, and places its private menu
surface at `:1519`. MenuItem consumes private MenuContext. A core Overlay alone
therefore cannot provide the native menu traversal/focus contract.

For a permanently present property trigger, native Menu with its real trigger
Slot is the smallest existing composition, provided actual form/input children
and controlled dismissal are preserved. Arbitrary service-created externally
anchored menus remain a public composition gap; do not fabricate a second menu
focus manager. Add a positive build scenario opening an actual property config
menu and a view menu, traversing native items and dismissing by Escape. Rejecting
the enum value exhaustively is insufficient evidence that used menus work.

## 3. Date-time property editing emits a rejected time input

`src/properties/properties_value.ml:930` calls the shared calendar with
`datetime=is_datetime`. The datetime branch at
`src/shared/ui_components.ml:1446` creates Input with `kind=time`, live HH:MM text,
`submit_on_blur=true` and a submit handler. `inputs.rs:7` explicitly rejects
`input-type=time`.

NSH already supplies `TimeFieldProps` (`nsh-base/src/time_field.rs:341`) with a
controlled `Option<TimeOfDay>` and `TimeFieldEvent::Change` at `:381`. Reuse this
semantic field for time segments/parsing, with an explicit adapter for the LUI
text/change and actual commit-on-blur contract. Do not silently turn Change into
Submit or discard the used blur behavior. A positive build scenario opens a real
datetime property's calendar, edits time, blurs and checks the committed value.
The canonical input-type enum can make provider decisions exhaustive, while this
scenario checks that the admitted used branch actually succeeds.

## 4. Appearance and icon popups require cross-axis offsets

`src/settings/settings_page.ml:1436` authors `anchor_alignment_offset=-5.5` for the
Appearance popup. `src/icon/icon_picker.ml:582` calls
`Properties_popup.open_anchored_right`; `src/properties/properties_popup.ml:31`
sets the corresponding cross-axis offset to -4. LUI `render.rs:1706` rejects every
nonzero alignment offset, including these dialog-role popovers.

Public core Overlay supports ElementRef/content/bounds anchoring and main-axis
`offset`, but its `OverlayConfig` has no cross-axis offset
(`nsh-core/src/overlay.rs:135`). `element/host.rs:1212` exposes `anchor_bounds`;
`:1229` exposes main-axis `offset`. For native-aligned design, a deliberate caller
migration can omit the old browser arrow compensation. If that compensation is
required, compose the existing genuine bounds measurement with native Overlay
collision handling, without a second placement/focus system. Exercise actual
Appearance and icon-picker opening during qualification, including anchor motion.
These values are open numeric options, not new enum variants; a type alone cannot
prove that nonzero values are implemented.

## 5. A remote URL gallery cover still requests browser-only image options

The native twin `native/asset_dom.ml` already omits lazy/referrer options for local
asset images and gallery assets. It is not an outstanding caller. A separate,
shared remote-URL branch in `src/views/views_table.ml:1840-1843` directly creates
Image with `loading=lazy` and `referrer_policy=no_referrer`; it bypasses that twin.
`images.rs:66` rejects lazy loading, and `:69` rejects any referrer-policy property.

Reuse the existing NSH Image and its native loader/cache. Pinned public Image
binds a source (`nsh-core/src/element/builder.rs:2515`), without a lazy prop. The
loader already owns bounded concurrency, cancellation and cache lifetime. Its
cache explicitly documents URL-only keys and no per-source request headers
(`image/cache.rs:29`); adding another loader/cache to imitate browser options
would be disproportionate. A native eager-loading caller policy needs explicit
migration and a transport check that no page Referer is sent, before admitting the
used no-referrer semantics. A positive build scenario must select a real URL
column as a gallery cover; testing only native asset gallery covers misses it.

## Checks and exclusions

The cheapest shared prevention is to extend the existing actual-application
Headless qualification scenarios before staged publication, reusing the same
canonical wire and pure native preflight. This adds no second contract table or
runtime tree. Keep generated closed-domain matches exhaustive, and also require
positive tests for every used explicit rejection that is being retired.

A future producer literal check must be scoped to the actual NSH target and wired
into a build that runs it. A standalone unused PPX option or text search is not a
compiler gate. Dynamic CSS variables, app state and numeric option values still
need resolved preflight and positive branch coverage. This audit deliberately
excludes Web-only shell inert/split branches, the shadowed Web Asset_dom image
calls, host-guarded Ui_parts inline-flex helpers, Graph View and generic unused
LUI APIs. No source behavior was changed and no builds were run for this audit.
