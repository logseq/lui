# Logseq refactor/lui production API audit

## Decision and snapshot

`logseq/logseq` on branch `refactor/lui`, commit
`29dcb60fdc976dcda1da6ec984057bbf79d88612`, is a required downstream application.
Absence in mobile and Journal alone is insufficient to justify a desktop API
change. This report extends, and narrows the authority of, the earlier
[two-repository decision record](../2026-11-11/downstream-nsh-semantics.md).

The comparison baseline is LUI `71379462538239514b816acf76d210e6a31ddf28`.
It is a source audit, not a successful NSH launch of Logseq. Concurrent fixes
made after that baseline must be qualified and recorded separately. No Logseq
source, Dune file or backend dependency was changed, and no build or test ran
for this audit.

The most consequential new requirement is Split's mixed unit contract: the
left sidebar consumes absolute points, while the right sidebar consumes a
normalized fraction. Logseq also uses Shift checkbox callbacks, captured pointer
drags, input navigation and blur submission, application SVG icons, hidden and
transparent structural hosts, and registered native extensions. A routed kind
with default NSH behavior does not establish compatibility with these uses.

## Scope and source routing

Read `../logseq/AGENTS.md` and `.agents/skills/logseq-lui/SKILL.md`. Inspected all
production OCaml source under `deps/ui/src`, `deps/ui/native` and
`deps/ui/js_app`; searched the repository's OCaml, CLJS/CLJC and JSON sources for
qualified LUI APIs and JSON facade references. Tests, generated build products,
package caches and schemas were not counted as production component usage.
No production CLJS/JSON caller of `Lui_elements`, `Lui_ui`, `Lui_json_view` or
`Lui_protocol` was found. CLJS notifications and plugin data are not themselves
canonical LUI constructor calls.

The native build routing is decisive:

- `deps/ui/src/dune:15` builds the Web/Melange library.
- `deps/ui/src/shared/dune:3` builds `logseq_ui_shared` for bytecode, native and
  Melange. `Ui_components`, `Ui_parts`, `Icons` and theme helpers in this directory
  are native production dependencies, not Web-only wrappers.
- `deps/ui/native/dune:27` onward explicitly copies portable sources, including
  `edit_view`, `tree`, `properties_value`, `settings_page`, `views_table` and
  `views_popup`, into the native library at line270.
- `deps/ui/native/chrome.ml` replaces `src/shell/chrome.ml` on native. Similarly,
  native `asset_dom`, `logseq_el`, `pdf_annotation` and service modules replace
  the corresponding Web implementations. A Web-only option in those replaced
  files is not automatically a native requirement.

The [machine-readable source index](logseq-lui-production-usage.json) records
101 relevant source files with hashes and build scopes, 1,803 direct constructor
candidates, 1,198 wrapper references, 1,050 property/writer references and 14,352
named-argument lexemes. It includes all discovered call locations, not just the
examples below. Constructor indexing strips nested OCaml comments and strings,
follows `open Lui_elements` and direct module aliases, and excludes locally
shadowed unqualified names. Named arguments are collected at the constructor's
leading delimiter depth. Wrapper references and direct property writers are
indexed independently so `Ui_components.with_props`, `Ui_parts.class_signal`,
`Prop` aliases and `arm_press` are not mistaken for absent constructor options.

These are lexical evidence counts, not runtime node counts or a typechecked
whole-program call graph. Locally forwarded unqualified wrapper calls and
dynamic plugin markup require the separate wrapper/extension review. The
machine index labels these limits explicitly; zero index hits alone is not a
proof that an external plugin can never request a behavior.

## Previously changed native routes

All Logseq paths in this report are relative to the audited repository.

| Route | Actual production evidence | Required behavior and decision |
| --- | --- | --- |
| Split | Native `deps/ui/native/chrome.ml:324`, `:333`, `:346`; Web counterparts `src/shell/chrome.ml:916`, `:939` | Preserve both absolute first width and fractional value, including native sidebar hiding/revealing and callback units. Existing NSH rejection of fraction/handle/motion options prevents this application from mounting these calls. |
| Toast | `deps/ui/src/toasts/toasts_view.ml:28`–`:79`, copied to native | Error/code notifications use duration0; other notifications use1500/2000ms. `on_dismiss` removes the model notification. No veto callback exists. Keep native lifecycle and explicit persistent duration while preserving dismissal cleanup and retained content. |
| Tree | No canonical `tree`/`tree_item`, raw `Lui_ui.tree`, Tree creation enum or `treeitem` role found in production UI | Native NSH Tree remains appropriate for unused canonical Tree. `src/blocks/tree.ml` renders the outliner using rows, text, icons and the editor extension. `views_builder`'s `~tree` is query data, not a Tree UI call. Do not integrate the archived custom Tree focus coordinator. |
| MediaSurface | No canonical `media_surface`, raw kind or `~surface` resource call found | Native Video URL semantics are not contradicted by a static Logseq canonical call. This does not qualify Logseq's separate raw video/asset extensions. |
| FilePicker | No canonical `file_picker` constructor/raw kind found | `native/asset_dom.ml:155` uses `Browser_ui.open_file_picker`; `native/ui_dom_native.ml:375` forwards accept/multiple/directory to that host service. Preserve that service contract separately; changing canonical FilePicker does not automatically migrate uploads. |
| FileImage/FilePreview | No canonical calls found in this Logseq snapshot | Mobile/Journal requirements remain authoritative; Logseq's native PDF/assets services are separate. |
| ViewThatFits | No Logseq constructor found | Journal remains the actual use. The separately qualified retained adapter is still required. |

### Complete Split call contract

| Native call | Sizing source | Handle/motion options | Completion consumer |
| --- | --- | --- | --- |
| `native/chrome.ml:324`, sidebar reveal | Reactive `first_width`: closed0; small window74% of window; otherwise stored width | `container_relative_frame=both`, handle width0, gap0, duration300, easingstandard | No resize callback; this is an animated reveal/shade pair. |
| `native/chrome.ml:333`, left dock | Reactive `first_width`: stored points when docked, otherwise0 | grow1, gap0, width3, offset0.5, duration300, easingstandard | `src/sidebar/sidebar_state.ml:156` clamps and persists the received absolute point width. |
| `native/chrome.ml:346`, right dock | Reactive `value`: `1-right_fraction` when open, otherwise1 | grow1, gap0, width3, offset2.5, duration300, easingstandard | `sidebar_state.ml:165` computes `1-v` and persists the resulting fraction. |

The Web calls add `min_height=0` and carry the same respective pixel/fraction
semantics. No Split orientation argument is authored. The baseline NSH
`controls/surfaces/native_split.rs:8` rejects `value`, any handle width, nonzero
handle offset, nonzero duration and authored easing/origin. Its resize callback
emits absolute native first-panel points. Removing only the validation would
silently corrupt the right sidebar's stored fraction. A corrective adapter must
convert through actual native panel-group geometry, or migrate the downstream
source and callback together in a reviewed change; it must not relabel points
as fractions.

## Used parameters and current NSH gaps

“Rejected” means an atomic validation refusal at this baseline. “Ignored” means
the property/event can be admitted while the relevant native route has no
corresponding reader or producer. Both require work when the call is used.

| Priority | Used parameter/behavior and source | Baseline NSH result | Corrective action |
| --- | --- | --- | --- |
| P0 | Native extension schemas and runtime: `native/native_embed.ml:427` registers Logseq elements, CodeMirror and editor; `native/logseq_el.ml:33` lists GenericHost on all3OS; editor source at `native/logseq_editor.ml:69` | `platform/nsh/src/store.rs:243` rejects every CreateExtension; line288 rejects extension properties | Provide the actual application extension/service integration or an explicit coordinated downstream migration. Generic TextField is not proof of rich editor, PDF, raw markup or document-event compatibility. |
| P0 | Split pixel/fraction/handle/motion contract above | Rejected; absolute completion is incompatible with right-side fraction consumer | Preserve used source and callback units and qualify sidebar reveal, drag, hide/show and editor identity in the real downstream app. |
| P0 | `submit_on_blur=true`: copied `src/properties/properties_value.ml:572`, `:873`; shared `src/shared/ui_components.ml:1419`; copied `src/settings/settings_page.ml:1184` | `inputs.rs:10` rejects true blur submission | Forward actual native focus loss while preserving ordinary Submit/Enter/composition semantics and avoiding duplicate Enter+blur submission. These are saves/commits, not optional presentation. |
| P0 | Input `on_navigate`: copied `src/properties/properties_select.ml:222`, `views/views_popup.ml:509`, `pages/handbook.ml:303`; shared calendar buttons at `shared/ui_components.ml:1220` | Text controls reject navigate-enabled; generic native Button has no canonical NavigationKey producer | Preserve used picker previous/next and calendar key/modifier navigation through verified public native input/key APIs. Keep their existing callback payloads. |
| P0 | Checkbox `on_toggle_detail`: copied `src/views/views_table.ml:328` uses `ToggleChangedDetail` modifiers bit2 for Shift range selection | Native Checkbox emits unit Toggle only; ToggleDetailEnabled has no producer | Deliver requested checked value and native modifiers once, without issuing a second toggle or replacing the native Checkbox controller. Add actual Shift multi-row selection coverage. |
| P0 | Pointer capture and payload: copied `views/views_table.ml:772`–`:787` column resize; copied `sidebar/left_sidebar_view.ml:661` favorites drag | PointerCapture has no capture reader; raw PressDown/Up currently cannot represent right button, unlike canonical payload. Native mouse movement alone does not establish capture outside the host | Preserve ownership/cancel/outside-release and coordinates for the actual drag workflows using public native capture/gesture mechanisms, with exact event mapping. |
| P0 | Application icons: shared `icons.ml:25` creates `app:<slug>`; native `native_embed.ml:492` sends custom SVGs through `app-icons` host channel | `contract.rs:279` admits app names, but `ui/icons.rs:5` has no app registry lookup and uses its unknown-name fallback; no NSH app-icons host handler found | Resolve bundled Tabler names and registered custom overrides through the actual registry/data channel; qualify native chrome and outliner icons. Accepting an app slug must not silently render the fallback glyph. |
| P1 | Explicit `white_space` on copied `editor/edit_view.ml:525`, `pages/handbook.ml:62`, `views/views_table.ml:411`; shared `Ui_components.Prop.white_space` at `shared/ui_components.ml:169`, `:528` | `style.rs:823` rejects any authored white-space | Preserve pre-wrap/nowrap/normal using the public native text layout configuration, including editor whitespace and truncation. Do not merely delete the option from used views. |
| P1 | Structural transparent host: `native/logseq_el.ml:515` and copied `pages/page.ml:1367`; true inert at `native/chrome.ml:282`, `:322` | `render.rs` rejects Box displaycontents; `style.rs:833` rejects inert=true | Provide identity-safe transparent composition and inherited interaction exclusion using native public semantics; verify hidden sidebars and the raw/document carrier. Inert is not equivalent to opacity0. |
| P1 | Horizontal Scroll: copied `src/views/views_table.ml:1357`, `:1391` | Baseline Scroll uses native vertical default; orientation ignored | Set native horizontal mode for these static calls. Both are literal horizontal; the one reactive orientation at `settings_page.ml:1349` belongs to a Row. Root reported implementing and testing this after the comparison baseline. |
| P1 | MenuItem appearance: shared `core/menu_item.ml:40` forwards ?icon; copied `pages/page_menu.ml:17`, `properties/properties_menu.ml:328` pass actual app icons. Shared `ui_components.ml:1021` applies ghost variant | MenuItem fixed wrapper ignores authored icon/variant/size/placement choices | Bind native MenuItem slots and styles through the shared UI layer; preserve disabled/checked/menu keyboard behavior and retained identity. |
| P1 | Checkbox indicator/label: shared `ui_components.ml:92`–`:93`; copied `views/views_table.ml:319`–`:320`; `settings/settings_page.ml:147` label opacity0.7 | Authored indicator border colors and label opacity are not forwarded | Style the actual native indicator/label parts; distinguish indicator color from the component's outer border. |
| P1 | Typed pointer detail/modifiers: copied `views/views_head.ml:1142` uses Button PressDetail; copied `popups/popups_view.ml:729` uses MenuItem PressDetail coordinates for submenu hit tests | Typed native control roots lack generic pointer detail projection; raw host adapters do not repair Button/MenuItem automatically | Preserve actual modifier and coordinate behavior at the native behavior component boundary. Do not synthesize empty details or add a second activation controller. DOM element-at services also need downstream integration. |
| P1 | `style_class`, reactive class writers and `data_attrs`: native `chrome.ml:188`, copied `blocks/tree.ml:939`, shared `ui_parts.ml:42`; table data hooks in `views_table.ml:1367` | StyleClass has no native compiler reader; DataAttrs is validated but has no rendering reader | Separate application hooks from styling, audit used native host behavior, and bind required typed state/paint/semantic attributes. Web selector rules are evidence of Web behavior, not permission to parse all CSS in NSH. Explicit native props already replace many CSS rules, so assess each hook before adding work. |
| P1 | Gallery Image lazy/referrer policy: copied `views/views_table.ml:1843` | `images.rs:41` rejects lazy and line44 rejects authored referrer policy | Preserve the used loading/network policy or coordinate a documented downstream update with equivalent behavior. These options in `src/assets/asset_dom.ml:501` are Web-only, but the copied table gallery use is a native requirement. |
| P2 | Authored layer alignment | The explicit alignment constructor calls (`editor/jump_state.ml:33`, `export/export_view.ml:192`, `export/publish_view.ml:230`) all target Overlay, whose route supports local alignment | No evidence here requires inventing alignment behavior for unrelated kinds. Keep child `align` overrides and qualify export/resize overlays. |
| P2 | Resource-ID Image/crop/MediaSurface parameters | No canonical resource-ID or crop rectangle production writer found; native `asset_dom.ml:172`, `:185`, `:220` uses Image URLs/path sources. `shared/ui_parts.ml:320` exposes image_fit and `settings/settings_view.ml:141` uses fill | Keep URL fit behavior. This absence does not remove the native asset/PDF/host resource service requirements or mobile/Journal resource calls. |

Additional used Input modes include shared calendar `input kind=time` at
`ui_components.ml:1417` and copied plugin settings `input kind=color` at
`dialogs/plugins_view.ml:636`. Both are explicitly rejected by baseline
`inputs.rs:19`. They need real native component/service behavior, not a silent
text-input substitute. Ordinary textarea Enter handling was already implemented;
that does not establish blur submission or navigation support.

The class audit must retain the distinction between appearance and application
behavior. `resources/css/lui-core.css:1735` and `:1838` target selected outliner
rows/editor runs, while `resources/css/lui-overlay.css:239` targets menu rows.
Native shared code also forwards selected backgrounds explicitly. Therefore
class absence is confirmed, but each class's remaining native impact is a
separate requirement; the report does not claim every Web selector must become
a native stylesheet engine.

## Constructor inventory

The table below is a lexical entry-point inventory, with one source location per
found constructor. The JSON index contains every recorded location and its
leading parameters, plus wrapper references such as `Ui_components.button`.
In particular, the low direct Button/Input counts reflect forwarding through
shared wrappers, not a lack of production buttons or inputs.

| Constructor | Direct lexical sites | Example production location |
| --- | ---: | --- |
| `alert` | 1 | `deps/ui/src/dialogs/login_view.ml:605` |
| `avatar` | 2 | `deps/ui/src/comments/comments_view.ml:292` |
| `box` | 342 | `deps/ui/src/assets/asset_dom.ml:374` |
| `button` | 13 | `deps/ui/src/dialogs/login_view.ml:464` |
| `button_group` | 2 | `deps/ui/src/properties/properties_dialog.ml:730` |
| `card` | 2 | `deps/ui/src/properties/properties_dialog.ml:690` |
| `checkbox` | 2 | `deps/ui/src/shared/ui_components.ml:94` |
| `column` | 359 | `deps/ui/src/assets/asset_dom.ml:678` |
| `dialog` | 6 | `deps/ui/src/pages/handbook.ml:370` |
| `divider` | 8 | `deps/ui/src/blocks/selection_bar.ml:339` |
| `dropdown_menu` | 4 | `deps/ui/src/cards/cards_view.ml:27` |
| `grid` | 5 | `deps/ui/src/dialogs/plugins_view.ml:117` |
| `heading` | 38 | `deps/ui/src/cards/cards_view.ml:287` |
| `icon` | 79 | `deps/ui/src/assets/asset_dom.ml:375` |
| `image` | 16 | `deps/ui/src/assets/asset_dom.ml:498` |
| `input` | 1 | `deps/ui/src/shared/ui_components.ml:67` |
| `kbd` | 3 | `deps/ui/src/cards/cards_view.ml:117` |
| `label` | 10 | `deps/ui/src/blocks/tree.ml:373` |
| `link` | 25 | `deps/ui/src/blocks/tree.ml:307` |
| `list` | 6 | `deps/ui/src/dialogs/plugins_view.ml:342` |
| `list_item` | 10 | `deps/ui/src/dialogs/plugins_view.ml:258` |
| `menu_item` | 51 | `deps/ui/src/cards/cards_view.ml:9` |
| `menu_trigger` | 1 | `deps/ui/src/popups/popups_view.ml:822` |
| `overlay` | 10 | `deps/ui/src/assets/asset_dom.ml:540` |
| `paragraph` | 16 | `deps/ui/src/cards/cards_view.ml:289` |
| `popover` | 31 | `deps/ui/src/blocks/selection_bar.ml:316` |
| `progress` | 1 | `deps/ui/src/shell/chrome.ml:623` |
| `row` | 341 | `deps/ui/src/assets/asset_dom.ml:550` |
| `scroll` | 22 | `deps/ui/src/cards/cards_view.ml:180` |
| `search_field` | 1 | `deps/ui/src/shared/ui_components.ml:81` |
| `secure_field` | 1 | `deps/ui/src/shared/ui_components.ml:76` |
| `select` | 9 | `deps/ui/src/cards/cards_view.ml:55` |
| `separator` | 1 | `deps/ui/src/settings/settings_page.ml:642` |
| `slider` | 2 | `deps/ui/src/dialogs/plugins_view.ml:640` |
| `spacer` | 55 | `deps/ui/src/assets/asset_dom.ml:725` |
| `spinner` | 1 | `deps/ui/src/shell/chrome.ml:593` |
| `split` | 5 | `deps/ui/src/shell/chrome.ml:916` |
| `stack` | 6 | `deps/ui/src/blocks/tree.ml:586` |
| `switch_` | 1 | `deps/ui/src/shared/settings_controls.ml:90` |
| `table` | 1 | `deps/ui/src/sidebar/right_sidebar_view.ml:539` |
| `table_cell` | 1 | `deps/ui/src/sidebar/right_sidebar_view.ml:534` |
| `table_row` | 2 | `deps/ui/src/sidebar/right_sidebar_view.ml:541` |
| `text` | 294 | `deps/ui/src/assets/asset_dom.ml:665` |
| `text_field` | 1 | `deps/ui/src/shared/ui_components.ml:71` |
| `textarea` | 6 | `deps/ui/src/blocks/comments.ml:128` |
| `toast` | 1 | `deps/ui/src/toasts/toasts_view.ml:35` |
| `toggle_button` | 1 | `deps/ui/src/shared/ui_components.ml:922` |
| `toggle_group` | 2 | `deps/ui/src/dialogs/plugins_view.ml:56` |
| `toolbar` | 2 | `deps/ui/src/shared/ui_components.ml:1129` |
| `tooltip` | 1 | `deps/ui/src/views/views_view.ml:266` |
| `virtual_list` | 2 | `deps/ui/src/views/views_table.ml:1594` |

No direct constructor call was found for the following entry points in the
inspected production sources:

`accordion`, `bottom_tab`, `bottom_tabs`, `breadcrumb`, `bubble`, `combobox`, `context_menu`, `drawer`, `edge_inset`, `file_image`, `file_picker`, `file_preview`, `input_group`, `input_group_actions`, `list_section`, `media_surface`, `number_stepper`, `pagination`, `panel`, `radio`, `radio_group`, `resizable`, `sheet`, `status_bar`, `step`, `stepper`, `swipe_action`, `swipe_actions`, `tabs`, `timeline`, `timeline_item`, `toggle`, `tree`, `tree_item`, `view_that_fits`.

This list is Logseq-specific. It does not override mobile/Journal use, and it
does not mean identically named application concepts are absent: the app has
breadcrumb rows, contextual popovers, an outliner and host file pickers without
using the corresponding canonical constructors. The reviewed priority Tree,
FilePicker and MediaSurface absences additionally include raw property/kind and
wrapper searches described above. Unknown plugin-supplied markup or external
runtime registrations remain unknown, rather than being relabeled unused.

## Follow-up qualification order

1. Preserve the three-repository requirement set in the ADR/plan/inventory.
   Correct the Split units and the native extension/icon integration before
   describing Logseq as an NSH-compatible application.
2. Add native regressions for the actual shared Input save/navigation behavior,
   Shift checkbox selection and pointer-captured table/sidebar dragging. These
   must check callback values/order, retained editor identity and composition.
3. Close used text/structure/appearance/network restrictions; audit remaining
   class/data hooks against the native application path rather than Web CSS
   alone.
4. Build and run the actual refactor/lui application on NSH with its worker,
   services, custom resources and extensions. Component/headless fixture gates
   are necessary evidence, but do not replace this downstream integration gate.

No production change in this report is claimed implemented. The post-baseline
Scroll fix reported by root requires its own recorded test evidence. All other
findings above are open requirements until a reviewed change and appropriate
qualification establish otherwise.
