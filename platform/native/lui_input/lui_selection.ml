(* Static text selection — see lui_selection.mli for the contract.
   Owns the focus-independent user-select=text selection and the
   pointer-drag extension state. Byte offsets index into each node's
   [text] prop. Pure transitions; glyph measurement arrives through
   {!Lui_query.text_hooks}. *)


type state = {
  text : (int * int * int * int) option;
      (* (anchor node, anchor byte, focus node, focus byte) — the
         focus endpoint may sit on a sibling text node of the
         anchor's container (cross-node selection) *)
  drag_id : int;
      (* node whose selection a pointer drag extends — a static
         text node or the focused editable *)
}

let initial = { text = None; drag_id = 0 }

let text st = st.text
let drag_id st = st.drag_id
let clear st = { st with text = None }
let arm_drag st id = { st with drag_id = id }
let clear_drag st = { st with drag_id = 0 }

(* Selectable text nodes under [id]'s parent, in child order — the
   bound a cross-node selection may span. Siblings that do not opt
   into selection simply stay outside the range. *)
let siblings store id =
  match Lui_store.parent store id with
  | None -> []
  | Some p ->
    List.filter
      (fun c -> Lui_query.selectable_text store c)
      (Lui_store.child_ids store p)

(* The focus endpoint a drag at [(x,y)] (device px) extends to.
   The selection stays inside the anchor's container: the pointer
   maps onto the sibling band by y — inside a node to its byte
   offset, above the first sibling to its start, below the last to
   its end, inside a gap to the start of the next sibling. *)
let extend hooks store rects anchor ~x ~y =
  let rec go last = function
    | [] ->
      (match last with
       | Some l ->
         Some (l, String.length (Lui_query.text_of store l))
       | None -> None)
    | id :: tl ->
      let r = Lui_query.Rects.get rects id in
      if Lui_scene.rect_empty r then go last tl
      else if y <= r.Lui_scene.y +. r.Lui_scene.h then
        let off =
          if y < r.Lui_scene.y then 0
          else
            Lui_query.offset_at_point hooks store rects id ~x ~y
              (Lui_query.text_of store id)
        in
        Some (id, off)
      else go (Some id) tl
  in
  go None (siblings store anchor)

(* Static-text branch of a primary press: click sets the endpoints,
   shift-click extends the recorded anchor (possibly onto a sibling
   text node), double/triple click selects word/paragraph. *)
let press hooks store rects st ~path ~clicks ~shift ~x ~y =
  match List.find_opt (fun i -> Lui_query.selectable_text store i) path with
  | None -> (st, [])
  | Some id ->
    let text = Lui_query.text_of store id in
    let off =
      Lui_query.offset_at_point hooks store rects id ~x ~y text
    in
    let st =
      match shift, st.text with
      | true, Some (an, ao, _, _)
        when Lui_store.parent store an = Lui_store.parent store id ->
        (* shift-click extends the recorded anchor onto a
           sibling text node *)
        { st with text = Some (an, ao, id, off) }
      | _ ->
        let a, b =
          if clicks >= 3 then Lui_query.line_bounds text off
          else if clicks = 2 then Lui_query.word_bounds text off
          else (off, off)
        in
        { st with text = Some (id, a, id, b) }
    in
    ({ st with drag_id = id }, [ `Repaint ])

(* Drag-extend: the focus endpoint follows the pointer across the
   anchor's selectable siblings. *)
let drag_move hooks store rects st ~x ~y =
  match st.text with
  | Some (an, a, _, _) ->
    (match extend hooks store rects an ~x ~y with
     | Some (nid, off) ->
       ({ st with text = Some (an, a, nid, off) }, [ `Repaint ])
     | None -> (st, [ `Repaint ]))
  | None -> (st, [ `Repaint ])

(* The selected text in document order: a same-node selection takes
   the usual substring; a spanning selection takes the start
   endpoint's suffix, every whole middle sibling and the end
   endpoint's prefix, joined with newlines. Endpoints in different
   containers (out of bound) yield nothing. *)
let selected_text store st =
  match st.text with
  | None -> None
  | Some (an, ao, fn, fo) ->
    if an = fn then begin
      let s = Lui_query.text_of store an in
      let lo = min ao fo
      and hi = min (max ao fo) (String.length s) in
      if hi > lo then Some (String.sub s lo (hi - lo)) else None
    end else
      (match
         (Lui_store.parent store an, Lui_store.parent store fn)
       with
       | Some pa, Some pf when pa = pf ->
         let sibs = siblings store an in
         (match Lui_query.index_of an sibs, Lui_query.index_of fn sibs with
          | Some ai, Some fi ->
            let lo_i, hi_i = min ai fi, max ai fi in
            (* ordered endpoints: (start off, end off) *)
            let s_lo, s_hi =
              if ai <= fi then (ao, fo) else (fo, ao)
            in
            let parts =
              List.mapi
                (fun i id ->
                   if i < lo_i || i > hi_i then None
                   else
                     let s = Lui_query.text_of store id in
                     let len = String.length s in
                     if i = lo_i then
                       let o = min s_lo len in
                       Some (String.sub s o (len - o))
                     else if i = hi_i then
                       Some (String.sub s 0 (min s_hi len))
                     else Some s)
                sibs
            in
            let s =
              String.concat "\n"
                (List.filter_map Fun.id parts)
            in
            if s = "" then None else Some s
          | _ -> None)
       | _ -> None)

(* Select-all on a static selection: every selectable sibling in the
   anchor's container (or just the anchor node when alone). *)
let select_all store st =
  match st.text with
  | Some (an, _, _, _) ->
    (match siblings store an with
     | first :: _ as sibs ->
       let last = List.nth sibs (List.length sibs - 1) in
       ( { st with
           text =
             Some
               (first, 0, last,
                String.length (Lui_query.text_of store last)) },
         [ `Repaint ] )
     | [] ->
       ( { st with
           text =
             Some (an, 0, an,
                   String.length (Lui_query.text_of store an)) },
         [ `Repaint ] ))
  | None -> (st, [])

(* Press on non-selectable content drops the selection unless shift
   extends it. *)
let press_none st ~shift =
  if shift then st else { st with text = None }
