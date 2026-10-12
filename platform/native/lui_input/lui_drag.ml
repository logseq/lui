(* Drag & drop (data-attrs) state — see lui_drag.mli for the
   contract. Owns the armed source, the press point the drag
   threshold measures from, the live (source, payload) session, the
   accepting drop target under the pointer and the completed-drop
   record. Host-local by design: the wire carries no drop event. *)

type state = {
  src : int;
      (* grabbed source with the drag threshold still pending *)
  down_x : float;
  down_y : float;
      (* press point (logical px) the threshold measures from *)
  live : (int * string) option;
      (* (source, payload) of an in-flight drag session *)
  target : int;
      (* accepting drop target under the pointer *)
  last : (int * string * int) option;
      (* (target, payload, serial) of the last completed drop *)
  seq : int;
      (* drop serial — the driver polls it to notice a repeat drop
         of an identical payload *)
}

let initial =
  { src = 0; down_x = 0.; down_y = 0.; live = None; target = 0;
    last = None; seq = 0 }

let active st = Option.is_some st.live
let last_drop st = st.last
let target st = st.target
let source st = match st.live with Some (s, _) -> s | None -> 0

(* The press point is recorded even when the press lands on a modal
   surface and gets swallowed — the threshold still measures from
   it. *)
let note_down st ~x ~y = { st with down_x = x; down_y = y }

(* Arm the first draggable node on the hit path (0 = none). Runs
   only for presses the overlay layer let through. *)
let arm store st ~path =
  { st with
    src =
      (match List.find_opt (fun i -> Lui_query.draggable store i) path with
       | Some id -> id
       | None -> 0) }

let clear_arm st = { st with src = 0 }

(* Threshold crossed on the armed source: promote the grab into a
   live drag session. The payload is the data-drag-payload attr,
   falling back to the node's text prop. *)
let promote store st ~x ~y =
  if st.src <> 0
     && Float.abs (x -. st.down_x) +. Float.abs (y -. st.down_y) > 6.
  then begin
    let payload =
      match Lui_query.data_attr store st.src "data-drag-payload" with
      | Some p -> p
      | None ->
        (match Lui_store.prop store st.src "text" with
         | Some (Lui_protocol.StringValue s) -> s
         | _ -> Lui_query.kind_name store st.src)
    in
    Some ({ st with live = Some (st.src, payload) }, [ `Repaint ])
  end
  else None

(* Live drop-target tracking while a drag is in flight. *)
let track store st ~path =
  match st.live with
  | None -> (st, [])
  | Some (_, payload) ->
    let tgt =
      match
        List.find_opt
          (fun id -> Lui_query.drop_accepts store id payload) path
      with
      | Some id -> id
      | None -> 0
    in
    if tgt <> st.target then
      ({ st with target = tgt }, [ `Repaint ])
    else (st, [])

(* Record a completed drop and bump the serial — the driver polls
   the serial so a repeat drop of the same payload is not lost. *)
let record st id payload =
  let seq = st.seq + 1 in
  { st with seq; last = Some (id, payload, seq) }

(* Button release while a drag is live: drop on the accepting target
   under the pointer; the click it rode on is consumed. *)
let drop st =
  let st =
    match st.live with
    | Some (_, payload) when st.target <> 0 ->
      record st st.target payload
    | _ -> st
  in
  ({ st with live = None; src = 0; target = 0 }, [ `Repaint ])

(* Escape cancels the drag: no drop. *)
let cancel st =
  ({ st with live = None; src = 0; target = 0 }, [ `Repaint ])

(* OS-side drops (SDL_DROPFILE/DROPTEXT): land at the pointer's last
   position on the deepest matching target. *)
let os_drop store st ~path ~payload =
  match
    List.find_opt (fun id -> Lui_query.drop_accepts store id payload) path
  with
  | Some id -> (record st id payload, [ `Repaint ])
  | None -> (st, [])
