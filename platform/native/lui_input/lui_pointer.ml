(* Pointer tracking state — see lui_pointer.mli for the contract.
   Owns the last pointer position, hover/hover-detail tracking and
   press capture. Pure transitions: they consume a precomputed hit
   path and return actions for the driver. *)

open Lui_protocol

type state = {
  x : float;          (* last pointer position, logical px *)
  y : float;
  hovered : int;      (* topmost hit node under the pointer *)
  detail : int;       (* node holding PointerEnter *)
  pressed : int;      (* activation target captured on button down *)
  press_detail : int; (* node that received PointerDown *)
}

let initial =
  { x = 0.; y = 0.; hovered = 0; detail = 0; pressed = 0;
    press_detail = 0 }

let position st = (st.x, st.y)
let hovered st = st.hovered
let detail st = st.detail
let pressed st = st.pressed
let press_detail st = st.press_detail
let note_pos st ~x ~y = { st with x; y }

(* Hover move: update position, hovered node and the PointerEnter
   target, emitting Leave/Enter on the boundary. *)
let move store st ~path ~x ~y =
  let hover = match path with id :: _ -> id | [] -> 0 in
  let detail =
    match
      Lui_query.detail_target store path (fun id -> PointerEnter id)
    with
    | Some id -> id
    | None -> 0
  in
  let acts =
    if detail <> st.detail then
      (if st.detail <> 0
          && Lui_query.node_enabled store st.detail
          && Lui_query.event_supported store st.detail
               (PointerLeave st.detail)
       then [ `Dispatch (PointerLeave st.detail) ]
       else [])
      @ (if detail <> 0 then [ `Dispatch (PointerEnter detail) ] else [])
    else []
  in
  let changed = hover <> st.hovered || detail <> st.detail in
  let st = { st with x; y; hovered = hover; detail } in
  (st, if changed then acts @ [ `Repaint ] else acts)

(* Button down: record position, capture the press-detail and
   activation targets, emit PointerDown / DoublePress /
   ContextMenuPress dispatches. *)
let down store st ~path ~x ~y ~button ~clicks ~mods =
  let st = note_pos st ~x ~y in
  match button with
  | Lui_input.Left ->
    let down_acts, press_detail =
      match
        Lui_query.detail_target store path (fun id ->
            PointerDown (id, Lui_query.dummy_detail))
      with
      | Some id ->
        ( [ `Dispatch
              (PointerDown
                 (id, Lui_query.detail_of store id x y mods 0)) ],
          id )
      | None -> ([], 0)
    in
    let pressed =
      match Lui_query.press_target store path with
      | Some id -> id
      | None -> 0
    in
    let double =
      if clicks = 2 then
        match
          Lui_query.pick store path (fun s id ->
              Lui_query.event_supported s id (DoublePress id))
        with
        | Some id -> [ `Dispatch (DoublePress id) ]
        | None -> []
      else []
    in
    ({ st with press_detail; pressed }, down_acts @ double)
  | Lui_input.Right ->
    ( st,
      (match
         Lui_query.detail_target store path (fun id ->
             ContextMenuPress (id, Lui_query.dummy_detail))
       with
       | Some id ->
         [ `Dispatch
             (ContextMenuPress
                (id, Lui_query.detail_of store id x y mods 2)) ]
       | None -> []) )
  | _ -> (st, [])

(* Button up: emit PointerUp for the detail target and drop it.
   [pressed] survives — the driver's click step needs the captured
   activation target; it clears it with {!clear_press} afterwards. *)
let up store st ~x ~y ~button ~mods =
  let st = note_pos st ~x ~y in
  match button with
  | Lui_input.Left ->
    let acts =
      if st.press_detail <> 0
         && Lui_query.node_enabled store st.press_detail
         && Lui_query.event_supported store st.press_detail
              (PointerUp (st.press_detail, Lui_query.dummy_detail))
      then
        [ `Dispatch
            (PointerUp
               (st.press_detail,
                Lui_query.detail_of store st.press_detail x y mods 0)) ]
      else []
    in
    ({ st with press_detail = 0 }, acts)
  | _ -> (st, [])

(* Release press capture without emitting — after click handling, or
   on a completed/cancelled drag. *)
let clear_press st = { st with pressed = 0; press_detail = 0 }
