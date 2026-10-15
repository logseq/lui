(* IME composition state machine — see lui_ime.mli for the contract.
   Pure transitions over an immutable record; every platform quirk
   (event delivery, text-input start/stop, candidate window) lives in
   the driver, which is the only side that can observe them. *)

type state = {
  active : bool;
  marked_text : string;
  cursor : int;
  sel_len : int;
  caret_rect : Lui_scene.rect option;
}

let initial =
  { active = false; marked_text = ""; cursor = 0; sel_len = 0;
    caret_rect = None }

let composing st = st.marked_text <> ""

type input =
  [ `Editing of string * int * int
  | `Commit of string
  | `Focus of bool
  | `Caret of Lui_scene.rect ]

type action =
  [ `Begin_composition
  | `Update_composition of string * int
  | `Commit_text of string
  | `Cancel
  | `Move_candidate of Lui_scene.rect ]

(* SDL reports the selection in IME-dependent units; the only hard
   bound we can enforce is non-negative and within the text's byte
   length so downstream consumers never read out of range. *)
let clamp_sel text start len =
  let n = String.length text in
  let start = max 0 (min start n) in
  (start, max 0 (min len (n - start)))

let clear st = { st with active = false; marked_text = "";
                         cursor = 0; sel_len = 0 }

let feed_event st ev =
  match ev with
  | `Editing (text, start, len) ->
    let cursor, sel_len = clamp_sel text start len in
    if text = "" then
      (* Empty preedit: clear the displayed marked text but keep the
         session open — a resumed preedit must not re-Begin. *)
      if st.marked_text = "" then (st, [])
      else
        ( { st with marked_text = ""; cursor = 0; sel_len = 0 },
          [ `Update_composition ("", 0) ] )
    else if
      st.active && st.marked_text = text && st.cursor = cursor
      && st.sel_len = sel_len
    then (st, []) (* identical report: dedup IME churn *)
    else begin
      let st' =
        { st with active = true; marked_text = text;
                  cursor; sel_len }
      in
      let open_acts =
        if st.active then []
        else
          `Begin_composition
          :: (match st.caret_rect with
              | Some r -> [ `Move_candidate r ]
              | None -> [])
      in
      (st', open_acts @ [ `Update_composition (text, cursor) ])
    end
  | `Commit text ->
    if text = "" then
      (* An empty commit ends the session with nothing committed —
         that is a cancellation. *)
      if st.active || st.marked_text <> "" then (clear st, [ `Cancel ])
      else (st, [])
    else (clear st, [ `Commit_text text ])
  | `Focus false ->
    (* Focus loss cancels the composition first; marked text was never
       dispatched so clearing it locally is the whole rollback. *)
    if st.active || st.marked_text <> "" then (clear st, [ `Cancel ])
    else (st, [])
  | `Focus true -> (st, [])
  | `Caret r ->
    let st' = { st with caret_rect = Some r } in
    if st.active && st.caret_rect <> Some r then
      (st', [ `Move_candidate r ])
    else (st', [])

let string_of_action = function
  | `Begin_composition -> "begin"
  | `Update_composition (s, c) -> Printf.sprintf "update(%S,%d)" s c
  | `Commit_text s -> Printf.sprintf "commit(%S)" s
  | `Cancel -> "cancel"
  | `Move_candidate (r : Lui_scene.rect) ->
    Printf.sprintf "move(%g,%g,%g,%g)" r.x r.y r.w r.h
