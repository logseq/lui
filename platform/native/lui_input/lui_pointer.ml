(* Pointer tracking state — see lui_pointer.mli for the contract.
   Owns the last pointer position, hover/hover-detail tracking and
   press capture. Pure transitions: they consume a precomputed hit
   path and return actions for the driver. *)

open Lui_protocol

module Nodes = Set.Make (Int)

type split_resize = { node : int; origin : float; fraction : float; span : float }

type state = {
  resize : split_resize option;
  x : float;          (* last pointer position, logical px *)
  y : float;
  hovered : int;      (* topmost hit node under the pointer *)
  details : int list; (* pointer-enabled hovered ancestors, deepest first *)
  targets : Nodes.t;
  revision : int;
  pressed : int;      (* activation target captured on button down *)
  press_detail : int; (* node that received PointerDown *)
}

let initial =
  { resize = None; x = 0.; y = 0.; hovered = 0; details = [];
    targets = Nodes.empty; revision = -1; pressed = 0; press_detail = 0 }

let position st = (st.x, st.y)
let hovered st = st.hovered
let detail st = match st.details with id :: _ -> id | [] -> 0
let pressed st = st.pressed
let press_detail st = st.press_detail
let note_pos st ~x ~y = { st with x; y }

let resizing st = Option.is_some st.resize

let start_resize st ~node ~x ~fraction ~span =
  if not (Float.is_finite span) || span <= 0. then
    invalid_arg "Split resize requires a positive finite track";
  { st with pressed = 0; press_detail = 0;
    resize = Some {node; origin=x; fraction; span} }

let resize store st ~x =
  match st.resize with
  | None -> st,None
  | Some drag when not (Lui_store.mem store drag.node)
      || not (Lui_query.node_enabled store drag.node)
      || Lui_store.int_prop store drag.node "resize-handle-width" = Some 0 ->
      {st with resize=None},None
  | Some drag ->
    let value = max 0. (min 1. (drag.fraction +. (x -. drag.origin) /. drag.span)) in
    if Lui_store.float_prop store drag.node "value" = Some value then st,None
    else st,Some (drag.node,value)

(* Pointer enter/leave belongs to every opted-in ancestor, as on Web.
   Cache the chain until the hit node or store changes: coordinate-only moves
   must not rebuild ancestor collections or repeat event eligibility checks. *)
let move store st ~path ~x ~y =
  let hover = match path with id :: _ -> id | [] -> 0 in
  let revision = Lui_store.revision store in
  if hover = st.hovered && revision = st.revision then
    ({ st with x; y }, [])
  else
    let details = List.filter (fun id ->
      Lui_query.pointer_enabled store id && Lui_query.node_enabled store id
      && Lui_query.event_supported store id (PointerEnter id)) path in
    let targets, acts =
      if details = st.details then st.targets, []
      else
        let targets = List.fold_left (fun nodes id -> Nodes.add id nodes) Nodes.empty details in
        let leaves = List.filter_map (fun id ->
          if not (Nodes.mem id targets) && Lui_query.node_enabled store id
             && Lui_query.event_supported store id (PointerLeave id)
          then Some (`Dispatch (PointerLeave id)) else None) st.details in
        let enters = List.fold_left (fun actions id ->
          if Nodes.mem id st.targets then actions
          else `Dispatch (PointerEnter id) :: actions) [] details in
        targets, leaves @ enters
    in
    let changed = hover <> st.hovered || details <> st.details in
    let st = { st with x; y; hovered = hover; details; targets; revision } in
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
let clear_press st = { st with pressed = 0; press_detail = 0; resize = None }
