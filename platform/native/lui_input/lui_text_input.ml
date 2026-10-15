(* Editable text-input state — see lui_text_input.mli for the
   contract. Owns the shadow text buffer (what the app last saw),
   caret/selection anchor, the host-side undo chain and the embedded
   {!Lui_ime} composition machine. Pure transitions: edits return
   [`Dispatch (TextChanged ...)], [`Mirror_text ...] (write the
   shadow into the store prop) and [`Repaint] actions the driver
   performs. *)

open Lui_protocol

type state = {
  node : int;           (* node this session is attached to *)
  session : int;
      (* session id — bumps on every attach, so model responses
         cannot be mistaken across session boundaries *)
  text : string;
      (* latest text value as the app sees it: the store prop lags
         one frame behind dispatched edits, so caret math runs on
         this shadow *)
  local_rev : int;
      (* host-side edit counter — every TextEdit bumps it *)
  model_rev : int;
      (* count of model-side texts adopted — every Correction and
         Reset bumps it *)
  model : string;
      (* the store prop as last observed — the baseline that tells
         an Ack (model echoing our mirror) from a genuine
         model-side change *)
  dirty_since_model : bool;
      (* local edits exist that the model has not echoed yet *)
  response : [ `None | `Ack | `Correction | `Reset ];
      (* the last model response classification — see
         {!sync_model}; observability for the revision protocol *)
  caret : int;          (* byte offset into [text] *)
  anchor : int;         (* selection anchor; selection is
                           [min anchor caret .. max anchor caret) *)
  undo : (string * int * int) list;
      (* (text, caret, anchor) snapshots; reset on focus change *)
  redo : (string * int * int) list;
  ime : Lui_ime.state;
      (* composition state machine; marked text rides here, never
         dispatched, until commit lands through the normal path *)
}

let initial =
  { node = 0; session = 0; text = ""; local_rev = 0; model_rev = 0;
    model = ""; dirty_since_model = false; response = `None;
    caret = 0; anchor = 0;
    undo = []; redo = []; ime = Lui_ime.initial }

let node st = st.node
let session_id st = st.session
let text st = st.text
let caret st = st.caret
let anchor st = st.anchor
let local_revision st = st.local_rev
let model_revision st = st.model_rev
let model_response st = st.response
let ime st = st.ime
let marked st = st.ime.Lui_ime.marked_text
let composing st = Lui_ime.composing st.ime
let sel_lo st = min st.anchor st.caret
let sel_hi st = max st.anchor st.caret

(* Whether the node's focused field accepts edits — admits
   TextChanged. *)
let editable store node =
  node <> 0 && Lui_query.event_supported store node (TextChanged (node, ""))

(* Session ids — every attach starts a new session so model
   responses to one session cannot leak into the next. *)
let session_seq = ref 0

(* Re-attach the session to a node on focus change: the composition
   machine hears the focus transition (a live composition cancels
   silently — its actions are dropped here because the driver marks
   the frame anyway), the shadow takes the node's text and the
   caret lands at its end. Selection, undo and the revision
   counters reset — the model baseline is the attached prop. *)
let attach st ~node ~text =
  incr session_seq;
  let ime, _ = Lui_ime.feed_event st.ime (`Focus false) in
  let ime, _ = Lui_ime.feed_event ime (`Focus (node <> 0)) in
  let caret = if node = 0 then 0 else String.length text in
  { node; session = !session_seq; text; local_rev = 0; model_rev = 0;
    model = text; dirty_since_model = false; response = `None;
    caret; anchor = caret; undo = []; redo = []; ime }

let set_caret st ~off ~extend =
  if st.caret = off && (extend || st.anchor = off) then st
  else
    { st with caret = off;
              anchor = (if extend then st.anchor else off) }

(* Splice [ins] over the current selection, pushing undo and
   emitting the resulting TextChanged. *)
let splice st ins =
  let cur = st.text in
  let lo = min (sel_lo st) (String.length cur)
  and hi = min (sel_hi st) (String.length cur) in
  let next =
    String.sub cur 0 lo ^ ins
    ^ String.sub cur hi (String.length cur - hi)
  in
  let caret' = lo + String.length ins in
  if next = cur then
    ({ st with caret = caret'; anchor = caret' }, [])
  else begin
    let undo =
      match st.undo with
      | (s, _, _) :: _ when s = cur -> st.undo
      | _ ->
        let u = (cur, st.caret, st.anchor) :: st.undo in
        (* bound the chain *)
        if List.length u > 64 then
          List.rev (List.tl (List.rev u))
        else u
    in
    ( { st with text = next; caret = caret'; anchor = caret';
                local_rev = st.local_rev + 1;
                dirty_since_model = true;
                undo; redo = [] },
      [ `Dispatch (TextChanged (st.node, next));
        `Mirror_text (st.node, next);
        `Repaint ] )
  end

let delete_between st lo hi =
  splice { st with anchor = lo; caret = hi } ""

let insert st s = splice st s

(* Host-side undo/redo of shadow edits — each replay is a local
   edit in revision terms. *)
let undo st ~shift =
  match shift, st.undo, st.redo with
  | false, (s, c, a) :: tl, _ ->
    ( { st with redo = (st.text, st.caret, st.anchor) :: st.redo;
                undo = tl; text = s; caret = c; anchor = a;
                local_rev = st.local_rev + 1;
                dirty_since_model = true },
      [ `Dispatch (TextChanged (st.node, s));
        `Mirror_text (st.node, s);
        `Repaint ] )
  | true, _, (s, c, a) :: tl ->
    ( { st with undo = (st.text, st.caret, st.anchor) :: st.undo;
                redo = tl; text = s; caret = c; anchor = a;
                local_rev = st.local_rev + 1;
                dirty_since_model = true },
      [ `Dispatch (TextChanged (st.node, s));
        `Mirror_text (st.node, s);
        `Repaint ] )
  | _ -> (st, [])

let select_all st =
  ({ st with anchor = 0; caret = String.length st.text }, [ `Repaint ])

(* Click on the editable: click sets the caret, shift-click extends,
   double/triple click selects word/paragraph. *)
let press hooks store rects st ~x ~y ~clicks ~shift =
  let off =
    Lui_query.offset_at_point hooks store rects st.node ~x ~y st.text
  in
  let st =
    if shift then { st with caret = off }
    else if clicks >= 3 then
      let a, b = Lui_query.line_bounds st.text off in
      { st with anchor = a; caret = b }
    else if clicks = 2 then
      let a, b = Lui_query.word_bounds st.text off in
      { st with anchor = a; caret = b }
    else { st with caret = off; anchor = off }
  in
  (st, [])

(* Drag-extend the editable selection: the caret follows the
   pointer. *)
let point_move hooks store rects st ~x ~y =
  ( { st with
      caret =
        Lui_query.offset_at_point hooks store rects st.node ~x ~y
          st.text },
    [ `Repaint ] )

(* Editing keys: submit, deletion, caret motion (prim = Cmd/Ctrl for
   line-bound jumps, Alt for word jumps, Shift to extend). When the
   driver wired a [caret_ops] hook the moves run on the same laid-out
   text the painter resolves — grapheme clusters horizontally,
   visual (soft-wrapped) lines vertically; the codepoint/paragraph
   fallbacks keep tests text-engine free. *)
let key hooks store rects st ~(k : Lui_input.key)
    ~(mods : Lui_input.mods) ~prim =
  let n = st.node in
  let ops =
    match hooks.Lui_query.caret_ops with
    | Some f ->
      let r = Lui_query.Rects.get rects n in
      Some (f store n st.text ~lw:r.Lui_scene.w ~lh:r.Lui_scene.h)
    | None -> None
  in
  let cur = st.text in
  let caret = min st.caret (String.length cur) in
  let prev i =
    match ops with
    | Some o -> o.Lui_query.c_before i
    | None -> Lui_query.utf8_prev cur i
  and next i =
    match ops with
    | Some o -> o.Lui_query.c_after i
    | None -> Lui_query.utf8_next cur i
  and vmove dir =
    match ops with
    | Some o -> if dir < 0 then o.c_up caret else o.c_down caret
    | None -> Lui_query.move_caret_line hooks store n cur caret dir
  in
  match k with
  | Lui_input.Return ->
    ( st,
      (match Lui_query.kind_name store n with
       | "textarea" ->
         if (Lui_store.bool_prop store n "submit-on-enter" && not mods.shift)
            || mods.ctrl || mods.meta
         then Lui_query.submit store n else []
       | _ -> Lui_query.submit store n) )
  | Lui_input.Backspace ->
    if sel_hi st > sel_lo st then splice st ""
    else if caret > 0 then delete_between st (prev caret) caret
    else (st, [])
  | Lui_input.Delete ->
    if sel_hi st > sel_lo st then splice st ""
    else if caret < String.length cur then
      delete_between st caret (next caret)
    else (st, [])
  | Lui_input.Arrow_left ->
    let dest =
      if prim then fst (Lui_query.line_bounds cur caret)
      else if mods.alt then Lui_query.word_left cur caret
      else if not mods.shift && sel_hi st > sel_lo st then sel_lo st
      else prev caret
    in
    (set_caret st ~off:dest ~extend:mods.shift, [ `Repaint ])
  | Lui_input.Arrow_right ->
    let dest =
      if prim then snd (Lui_query.line_bounds cur caret)
      else if mods.alt then Lui_query.word_right cur caret
      else if not mods.shift && sel_hi st > sel_lo st then sel_hi st
      else next caret
    in
    (set_caret st ~off:dest ~extend:mods.shift, [ `Repaint ])
  | Lui_input.Arrow_up ->
    (set_caret st ~off:(vmove (-1)) ~extend:mods.shift, [ `Repaint ])
  | Lui_input.Arrow_down ->
    (set_caret st ~off:(vmove 1) ~extend:mods.shift, [ `Repaint ])
  | Lui_input.Home ->
    (set_caret st ~off:0 ~extend:mods.shift, [ `Repaint ])
  | Lui_input.End ->
    ( set_caret st ~off:(String.length st.text) ~extend:mods.shift,
      [ `Repaint ] )
  | _ -> (st, [])

(* Translate one lui_ime action into domain actions plus the state
   updates they imply. [`Commit_text] splices through the exact path
   raw text input used before composition existed. *)
let apply_ime store st actions =
  let st = ref st in
  let out =
    List.concat_map
      (fun a ->
         match a with
         | `Move_candidate r -> [ `Ime_rect r ]
         | `Commit_text s ->
           (* a commit marks the frame even when it splices to
              nothing or finds no editable target *)
           (match !st.node with
            | 0 -> [ `Repaint ]
            | n when Lui_query.node_enabled store n && editable store n ->
              let st', acts = splice !st s in
              st := st';
              `Repaint :: acts
            | _ -> [ `Repaint ])
         | `Begin_composition | `Update_composition _ | `Cancel ->
           [ `Repaint ])
      actions
  in
  (!st, out)

(* Feed one IME event into the embedded state machine and apply what
   it asks for. *)
let feed_ime store st ev =
  let ime, actions = Lui_ime.feed_event st.ime ev in
  let st, acts = apply_ime store { st with ime } actions in
  (st, acts)

(* Model-side text sync — the revision protocol. The host's own
   edits mirror into the store prop immediately, so a prop equal to
   the shadow is the model's Ack of a local edit (or simply no
   change): the dirty flag clears and nothing else moves — local
   typing never waits on the model round trip. A prop equal to the
   last observed baseline is a no-op re-read. Anything else is a
   genuine model-side change: a Correction when local edits were in
   flight, a Reset when clean. Either way the model is canonical:
   adopt it, clamp caret/anchor onto UTF-8 boundaries, drop the
   undo chain, and cancel any live composition — marked text was
   never dispatched, so rolling it back is the only stable answer
   to a changed base. *)
let sync_model _store st ~model_text =
  if model_text = st.text then
    ({ st with model = model_text; dirty_since_model = false;
               response = `Ack }, [])
  else if model_text = st.model then (st, [])
  else
    let response =
      if st.dirty_since_model then `Correction else `Reset
    in
    let ime, _ = Lui_ime.feed_event st.ime (`Focus false) in
    let ime, _ = Lui_ime.feed_event ime (`Focus (st.node <> 0)) in
    ( { st with
        text = model_text; model = model_text;
        caret = Lui_query.clamp_boundary model_text st.caret;
        anchor = Lui_query.clamp_boundary model_text st.anchor;
        model_rev = st.model_rev + 1;
        dirty_since_model = false;
        response;
        undo = []; redo = []; ime },
      [ `Repaint ] )
