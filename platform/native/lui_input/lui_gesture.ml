(* Gesture and list-navigation state — see lui_gesture.mli for the
   contract. Owns the highlighted list-item, the typeahead prefix
   buffer and the scroll scope arrow/typeahead keys drive, plus the
   keyboard activation of non-editable controls (slider stepping,
   radio groups, Space/Return press). Pure transitions. *)

open Lui_protocol

type state = {
  list_scope : int;
      (* scroll container that owns highlight/typeahead nav *)
  hl : int;             (* highlighted list-item *)
  typeahead : string;   (* type-to-select prefix buffer *)
}

let initial = { list_scope = 0; hl = 0; typeahead = "" }

let hl st = st.hl
let typeahead st = st.typeahead
let reset_typeahead st = { st with typeahead = "" }

(* Press context: the innermost scrollable ancestor with items under
   the pointer owns typeahead/arrows; a pressed list-item becomes the
   highlight. Unmatched paths keep the previous scope/highlight. *)
let note_list_context store st ~path =
  let st =
    match
      List.find_opt
        (fun i ->
           Lui_scroll.scrollable store i
           && List.exists
                (fun c -> Lui_query.kind_name store c = "list-item")
                (Lui_store.preorder ~root:i store))
        path
    with
    | Some id -> { st with list_scope = id }
    | None -> st
  in
  match
    List.find_opt
      (fun i -> Lui_query.kind_name store i = "list-item") path
  with
  | Some it -> { st with hl = it }
  | None -> st

(* Keyboard routing is part of the modal focus scope: [scope] is the
   top modal overlay's id (0 = none). While a modal surface is top, a
   list outside its subtree does not answer keyboard input — the
   background list keeps its highlight and items untouched. *)
let in_scope store ~scope id =
  scope = 0 || id = scope || Lui_query.is_desc store id scope

let list_scope_live store st ~scope =
  st.list_scope <> 0 && Lui_store.mem store st.list_scope
  && in_scope store ~scope st.list_scope

let list_items store st ~scope =
  if not (list_scope_live store st ~scope) then []
  else
    List.filter
      (fun id -> Lui_query.kind_name store id = "list-item")
      (Lui_store.preorder ~root:st.list_scope store)

(* Highlight [items.(i)] and scroll it into view. *)
let hl_index _store st items i =
  if items = [] then (st, [])
  else begin
    let i = min (max 0 i) (List.length items - 1) in
    let hl = List.nth items i in
    ({ st with hl }, [ `Repaint; `Scroll_show hl ])
  end

let move_hl store st ~scope delta =
  let items = list_items store st ~scope in
  match Lui_query.index_of st.hl items with
  | Some i -> hl_index store st items (i + delta)
  | None ->
    hl_index store st items (if delta > 0 then 0 else List.length items - 1)

(* First list-item in scope whose text starts with the typeahead
   buffer (case-insensitive). *)
let typeahead_match store st ~scope =
  let buf = String.lowercase_ascii st.typeahead in
  List.find_opt
    (fun id ->
       let s = String.lowercase_ascii (Lui_query.string_prop store id "text") in
       String.length s >= String.length buf
       && String.sub s 0 (String.length buf) = buf)
    (list_items store st ~scope)

(* Slider/stepper value stepping, bounded by min/max props. *)
let step_value store n dir =
  let cur =
    match Lui_store.prop store n "value" with
    | Some (FloatValue v) -> v
    | Some (IntValue i) -> float i
    | _ -> 0.
  in
  let step =
    match Lui_store.prop store n "step" with
    | Some (FloatValue v) -> v
    | Some (IntValue i) -> float i
    | _ -> 0.05
  in
  let lo, hi =
    ( (match Lui_store.prop store n "min" with
       | Some (FloatValue v) -> v | Some (IntValue i) -> float i
       | _ -> 0.),
      (match Lui_store.prop store n "max" with
       | Some (FloatValue v) -> v | Some (IntValue i) -> float i
       | _ -> 1.) )
  in
  let v = Float.max lo (Float.min hi (cur +. dir *. step)) in
  if v <> cur && Lui_query.event_supported store n (ValueChanged (n, v))
  then [ `Dispatch (ValueChanged (n, v)) ] else []

(* Arrow keys move inside a radio group: sibling radios of the same
   parent, focus follows the change. *)
let radio_step store st n dir =
  match Lui_store.parent store n with
  | None -> (st, [])
  | Some p ->
    let siblings =
      List.filter
        (fun c ->
           Lui_query.kind_name store c = "radio"
           && Lui_query.node_enabled store c)
        (Lui_store.child_ids store p)
    in
    (match Lui_query.index_of n siblings with
     | Some i ->
       let i' = min (max 0 (i + dir)) (List.length siblings - 1) in
       let tgt = List.nth siblings i' in
       if tgt <> n then
         (st,
          `Focus (tgt, true) :: Lui_query.primary_press store tgt)
       else (st, [])
     | None -> (st, []))

(* Keyboard on a focused non-editable control: sliders/steppers
   step, radios arrow within their group, Space/Return presses. *)
let control_key store st ~node ~key ~mods:_ =
  match Lui_query.kind_name store node, key with
  | ("slider" | "number-stepper"), Lui_input.Arrow_left
  | ("slider" | "number-stepper"), Lui_input.Arrow_down ->
    (st, step_value store node (-1.))
  | ("slider" | "number-stepper"), Lui_input.Arrow_right
  | ("slider" | "number-stepper"), Lui_input.Arrow_up ->
    (st, step_value store node 1.)
  | "radio", (Lui_input.Arrow_left | Lui_input.Arrow_up) ->
    radio_step store st node (-1)
  | "radio", (Lui_input.Arrow_right | Lui_input.Arrow_down) ->
    radio_step store st node 1
  | "link", Lui_input.Space -> (st, [])
  | _, (Lui_input.Return | Lui_input.Space) ->
    (st, Lui_query.primary_press store node)
  | _ -> (st, [])

(* Keyboard on lists with no focused widget: arrows move the
   highlight, PgUp/PgDn page the scope, chars typeahead-jump and
   Return/Space activates the highlighted item. [content_rect] is the
   driver's content-space rect hook used for page sizing. *)
let list_key store st ~scope ~content_rect ~key ~mods =
  match key with
  | Lui_input.Arrow_down -> move_hl store st ~scope 1
  | Lui_input.Arrow_up -> move_hl store st ~scope (-1)
  | Lui_input.Home -> hl_index store st (list_items store st ~scope) 0
  | Lui_input.End ->
    hl_index store st (list_items store st ~scope)
      (List.length (list_items store st ~scope) - 1)
  | Lui_input.Page_down | Lui_input.Page_up ->
    let dir = if key = Lui_input.Page_down then 1. else -1. in
    (match
       (if list_scope_live store st ~scope then Some st.list_scope
        else None)
     with
     | Some a ->
       let ar = content_rect a in
       if Lui_scene.rect_empty ar then (st, [])
       else (st, [ `Scroll_by (Lui_scroll.Y, a, dir *. 0.9 *. ar.Lui_scene.h) ])
     | None -> (st, []))
  | Lui_input.Return | Lui_input.Space ->
    if st.hl <> 0 && Lui_query.node_enabled store st.hl
       && List.mem st.hl (list_items store st ~scope)
    then (st, Lui_query.primary_press store st.hl) else (st, [])
  | Lui_input.Other sc ->
    (match Lui_input.char_of_scancode ~shift:mods.Lui_input.shift sc with
     | Some c ->
       let st = { st with typeahead = st.typeahead ^ String.make 1 c } in
       (match typeahead_match store st ~scope with
        | Some it -> ({ st with hl = it }, [ `Repaint; `Scroll_show it ])
        | None -> (st, []))
     | None -> (st, []))
  | _ -> (st, [])

(* Menus own their enabled rows, excluding separately presented submenus. *)
let menu_has_items store menu =
  let rec contains id =
    if id <> menu && Lui_query.presented_overlay store id then false
    else
      Lui_query.kind_name store id = "menu-item"
      || List.exists contains (Lui_store.child_ids store id)
  in
  contains menu

let menu_items store menu =
  let rec collect acc id =
    if (id <> menu && Lui_query.presented_overlay store id)
       || Lui_store.prop store id "visible" = Some (BoolValue false)
       || Lui_store.string_prop store id "display" = Some "none" then acc
    else
      let acc =
        if
          Lui_query.kind_name store id = "menu-item"
          && Lui_query.node_enabled store id
        then id :: acc
        else acc
      in
      List.fold_left collect acc (Lui_store.child_ids store id)
  in
  List.rev (collect [] menu)

let menu_open store ~menu =
  let items = menu_items store menu in
  let hl =
    match List.find_opt (fun id -> Lui_store.bool_prop store id "selected") items with
    | Some id -> id
    | None -> (match items with [] -> 0 | id :: _ -> id)
  in
  { list_scope = menu; hl; typeahead = "" }

let menu_state st menu =
  if st.list_scope = menu then st
  else { list_scope = menu; hl = 0; typeahead = "" }

let menu_hover store st ~menu path =
  match
    List.find_opt
      (fun id ->
        Lui_query.kind_name store id = "menu-item"
        && Lui_query.node_enabled store id
        && Lui_query.is_desc store id menu)
      path
  with
  | Some id when st.list_scope <> menu || st.hl <> id ->
      { list_scope = menu; hl = id; typeahead = "" }
  | _ -> st

let menu_text store st ~menu text =
  let st = menu_state st menu in
  let prefix = String.lowercase_ascii (st.typeahead ^ text) in
  let matches id =
    String.starts_with ~prefix
      (String.lowercase_ascii (Lui_query.text_of store id))
  in
  let st = { st with typeahead = prefix } in
  match List.find_opt matches (menu_items store menu) with
  | None -> (st, [])
  | Some id -> ({ st with hl = id }, [ `Repaint; `Scroll_show id ])

let menu_key store st ~menu ~rect_of ~scale ~key ~mods =
  let st = menu_state st menu in
  let items = menu_items store menu in
  let move index = hl_index store { st with typeahead = "" } items index in
  let count = List.length items in
  let step delta =
    let index =
      match Lui_query.index_of st.hl items with
      | Some index -> (index + delta + count) mod count
      | None -> if delta > 0 then 0 else count - 1
    in
    move index
  in
  match key with
  | Lui_input.Arrow_down when count > 0 -> step 1
  | Lui_input.Arrow_up when count > 0 -> step (-1)
  | Lui_input.Home -> move 0
  | Lui_input.End -> move (count - 1)
  | (Lui_input.Return | Lui_input.Space) when List.mem st.hl items ->
      let r = rect_of st.hl in
      let detail =
        Lui_query.detail_of store st.hl
          ((r.Lui_scene.x +. (r.w /. 2.)) /. scale)
          ((r.y +. (r.h /. 2.)) /. scale)
          mods 0
      in
      let event = PressDetail (st.hl, detail) in
      let details =
        if Lui_query.event_supported store st.hl event then [ `Dispatch event ]
        else []
      in
      (st, details @ Lui_query.primary_press store st.hl)
  | Lui_input.Page_down | Lui_input.Page_up ->
      let r = rect_of menu in
      let direction = if key = Lui_input.Page_down then 1. else -1. in
      ( st,
        [ `Scroll_by (Lui_scroll.Y, menu, direction *. 0.9 *. r.Lui_scene.h) ]
      )
  | _ -> (st, [])
