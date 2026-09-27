# Web backend port: conventions

The OCaml/Melange port of the deleted LG web backend (`/tmp/lui-web-ref/web.cljc`,
6379 lines; interface contract in `/tmp/lui-web-ref/web.mli`; retained mirror in
`/tmp/lui-web-ref/retained.cljc`, already ported in `core/lui_web_store.ml`).

## Module map (dependency order, bottom → top)

| Module | File | Owns |
|---|---|---|
| types | `core/lui_web_types.ml` | all records (done) |
| util | `core/lui_web_util.ml` | DOM helpers, coercions, CSS (done) |
| store | `core/lui_web_store.ml` | retained mirror + validations + store queries (done) |
| nodes | `nodes/lui_web_nodes.ml` | base-class table, element factories, `platform_node`, `dom_node`, dropdown anchor/side/offset |
| position | `popup/lui_web_position.ml` | popup geometry, transitions, submenu corridor |
| widgets | `widgets/lui_web_widgets.ml` | avatar/image/media-surface/icon/stepper/timeline/bottom-tabs/progress/select-display |
| widgets | `widgets/lui_web_split.ml` | split render/reconcile/update + pointer events |
| focus | `focus/lui_web_focus.ml` | tree, horizontal groups, tabs roving, toolbar, radio, restore-focus |
| overlay | `popup/lui_web_overlay.ml` | modal (stack/inert/focus-trap), tooltip, toast |
| menu | `popup/lui_web_menu.ml` | dropdown, picker/combobox, context-menu |
| props | `render/lui_web_props.ml` | `apply_property!`/`remove_property!`/class refresh |
| events | `events/lui_web_events.ml` | `attach_events!` dispatch + control listeners |
| apply | `shell/lui_web_apply.ml` | `apply_dom_op!`/`apply_dom_batch!`, cleanup, structured refresh |
| simulator | `shell/lui_web_simulator.ml` | device emulation |
| top | `shell/lui_web.ml` | `create*`, `backend`, `mount!`, `root_sections`, extension plumbing, query API |

Modules may only call modules strictly below them. `apply` may call all;
`events` may call popup/focus/widgets; `props` may call widgets/focus/nodes.

## Rules

- Never `Obj.magic`. For DOM type narrowing use the `%identity` externals in
  `core/lui_web_util.ml` (same mechanism melange-webapi itself uses); add new
  ones there only, with the JS property name visible.
- Every function ≤64 lines. Factor shared logic up into the lowest layer that
  can host it (util for pure DOM, store for mirror queries).
- Keep the exact DOM structure the LG code produced: same tags, same class
  names (`base_class_name`), same attributes and child order.
- Do NOT touch dune files, git, or files owned by another module. Do NOT
  `git commit`.

## Translation cheatsheet

- `atom` → `ref`; `deref` → `!`; `reset!` → `:=`; `swap!` → `:= f !x`.
- `hash-map`/maps on `retained_properties` → `Lui_protocol.Property_map`
  (persistent, `find_opt`/`add`/`remove`/`mem`); extension props → `String_map`.
- vectors (`Rrbvec`, `[]`) → `list`; `conj` → append; `nth` → `List.nth`.
- `(if-some [x e] a b)` → `match e with Some x -> a | None -> b`.
- `(raise (Invalid_argument m))` → `invalid_arg m`.
- Event emit: `((deref (:web-event-handler renderer)) (proto/Press node))`
  → `ignore (!(renderer.web_event_handler) (Press node))`
  (open `Lui_protocol` for the event variants).
- `addEventListener` handlers take `Dom.event -> unit`; typed helpers exist
  (`addClickEventListener`, `addKeyDownEventListener`, `addFocusInEventListener`
  …). For pointer events use `addEventListener "pointerdown"` +
  `Lui_web_util.as_pointer_event` / `pointer_type` / `pointer_id`.
- webapi arg order differs per function — check signatures:
  `setAttribute name value el`, `setClassName el name`,
  `HtmlCollection.item index col`, `insertBefore new ref parent`,
  `Element.addEventListener "type" handler el`.
- `Js.Global.setTimeout`, `Webapi.requestAnimationFrame` are available.

## Verify

From repo root: `opam exec --switch=default -- dune build` must compile the
whole `lui.web.dom` library (other modules are still `failwith` stubs — keep
stub signatures compatible: names and arity as listed in your stub file).
