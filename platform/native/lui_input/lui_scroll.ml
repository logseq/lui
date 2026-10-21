(* Scroll interaction state for the window host — see lui_scroll.mli
   for the contract. Immutable record of per-container offsets and
   ranges plus the visible-range reporting memo; every transition
   returns the next state and the actions the driver performs. *)

open Lui_scene
open Lui_protocol

module IdMap = Map.Make (Int)

(* Scroll axes: y is the established vertical path; x adds
   horizontal range for wheel-x / shift+wheel and horizontal
   reveal. *)
type axis = X | Y

type state = {
  off : float IdMap.t;
      (* vertical scroll offset per container id, device px *)
  cap : float IdMap.t;
      (* vertical scrollable range per container id, device px *)
  off_x : float IdMap.t;  (* horizontal counterparts *)
  cap_x : float IdMap.t;
  epoch : int;
      (* bumped whenever a scroll offset moves — drivers memoize
         ancestor-offset sums against it *)
  tokens : int IdMap.t;
      (* scroll-token values already handled per list *)
  vrange : (int * int) IdMap.t;
      (* last VisibleRange emitted per tracked list *)
  vrange_key : (int * float * int) IdMap.t;
      (* (store revision, scroll offset, layout epoch) each range
         was computed at — identical inputs mean the scan still
         stands *)
  lists : int list;
      (* tracked-list ids found by the last store scan *)
}

(* Layout-engine forwards for virtual-list math: item counts,
   content-space item rects (mounted or not), key → index lookup and
   the last fed viewport — the pieces scroll-target, visible-range
   and reveal logic need on logical items that may not be mounted. *)
type vlist = {
  vh_count : int -> int option;
  vh_item : int -> index:int -> rect option;
  vh_index_of_key : int -> string -> int option;
  vh_view : int -> (float * float) option;
}

type env = {
  content_rect : int -> rect;
      (* unshifted (content-space) rect — the driver's layout view *)
  rects_epoch : int;
      (* layout epoch; bumped whenever the rects feeding
         [content_rect] were recomputed *)
  vlist : vlist option;
      (* extent model for "virtual-list" containers; [None] keeps the
         mounted-children path, which is also what engines without
         virtualization answer *)
}

let initial =
  { off = IdMap.empty; cap = IdMap.empty;
    off_x = IdMap.empty; cap_x = IdMap.empty;
    epoch = 0;
    tokens = IdMap.empty; vrange = IdMap.empty;
    vrange_key = IdMap.empty; lists = [] }

(* Same scrollable rule as the paint pass: a scroll-kind node, or
   anything opting in through its overflow prop. *)
let scrollable store id =
  Lui_paint.scrollable (Lui_store.kind store id) store id

let offset st axis id =
  let t = match axis with Y -> st.off | X -> st.off_x in
  Option.value ~default:0. (IdMap.find_opt id t)

let cap st axis id =
  let t = match axis with Y -> st.cap | X -> st.cap_x in
  Option.value ~default:0. (IdMap.find_opt id t)

let epoch st = st.epoch

let set_cap st axis id c =
  let st =
    match axis with
    | Y -> { st with cap = IdMap.add id c st.cap }
    | X -> { st with cap_x = IdMap.add id c st.cap_x }
  in
  (* A shrinking cap (content removed, window grown) clamps any
     offset it left dangling past the new range. *)
  let off = offset st axis id in
  if off > c then
    let st =
      match axis with
      | Y -> { st with off = IdMap.add id c st.off }
      | X -> { st with off_x = IdMap.add id c st.off_x }
    in
    ({ st with epoch = st.epoch + 1 }, [ `Repaint ])
  else (st, [])

(* Recompute the visible list-item range of a tracked container and
   emit VisibleRange when it changed. *)
let report_vrange env store st id =
  (* VisibleRange is admissible on ListContainer ("list") only. The
     range is a pure function of (store revision, scroll offset,
     layout epoch): memoize the inputs — an identical triple means
     the last scan's result still stands, so a scroll-less sync on
     a tracked list costs a hashtable hit instead of an item walk. *)
  if Lui_query.kind_name store id = "list"
     && Lui_store.bool_prop store id "track-visible-range"
  then
    let key =
      (Lui_store.revision store, offset st Y id, env.rects_epoch)
    in
    match IdMap.find_opt id st.vrange_key with
    | Some k when k = key -> (st, [])
    | _ -> begin
      let st = { st with vrange_key = IdMap.add id key st.vrange_key } in
      let cr = env.content_rect id in
      if rect_empty cr || cr.Lui_scene.h <= 0. then (st, [])
      else
        let off = offset st Y id in
        let y0 = cr.Lui_scene.y +. off
        and y1 = cr.Lui_scene.y +. off +. cr.Lui_scene.h in
        let items =
          List.filter
            (fun c -> Lui_query.kind_name store c = "list-item")
            (Lui_store.preorder ~root:id store)
        in
        let rec scan i f l = function
          | [] -> (f, l)
          | it :: tl ->
            let r = env.content_rect it in
            let vis =
              (not (rect_empty r))
              && r.Lui_scene.y +. r.Lui_scene.h > y0
              && r.Lui_scene.y < y1
            in
            scan (i + 1) (if vis && f < 0 then i else f)
              (if vis then i else l) tl
        in
        let f, l = scan 0 (-1) (-1) items in
        let f = max 0 f in
        (match IdMap.find_opt id st.vrange with
         | Some (f', l') when f' = f && l' = l -> (st, [])
         | _ ->
           ( { st with vrange = IdMap.add id (f, l) st.vrange },
             [ `Dispatch (VisibleRange (id, f, l)) ] ))
    end
  else if Lui_query.kind_name store id = "virtual-list" then
    (* Same report over the extent model: the fed viewport and a
       binary search on item rects — no item walk at any size. *)
    match
      ( env.vlist,
        Lui_query.data_attr store id "data-track-visible-range" )
    with
    | Some vh, Some "true" -> (
      match (vh.vh_view id, vh.vh_count id) with
      | Some (vs, ve), Some n when n > 0 ->
        let key = (Lui_store.revision store, vs, env.rects_epoch) in
        (match IdMap.find_opt id st.vrange_key with
         | Some k when k = key -> (st, [])
         | _ ->
           let st =
             { st with vrange_key = IdMap.add id key st.vrange_key }
           in
           let cr = env.content_rect id in
           if rect_empty cr then (st, [])
           else begin
             (* Largest index whose content-space top is ≤ y; -1
                before the first item. *)
             let item_at y =
               let rec go lo hi =
                 if lo > hi then hi
                 else
                   let mid = (lo + hi) / 2 in
                   match vh.vh_item id ~index:mid with
                   | Some r when r.Lui_scene.y -. cr.Lui_scene.y <= y ->
                     go (mid + 1) hi
                   | _ -> go lo (mid - 1)
               in
               go 0 (n - 1)
             in
             let f = max 0 (item_at vs) in
             let l = max 0 (item_at (vs +. ve -. 0.001)) in
             match IdMap.find_opt id st.vrange with
             | Some (f', l') when f' = f && l' = l -> (st, [])
             | _ ->
               ( { st with vrange = IdMap.add id (f, l) st.vrange },
                 [ `Dispatch (VisibleRange (id, f, l)) ] )
           end)
      | _ -> (st, []))
    | _ -> (st, [])
  else (st, [])

let set_offset env store st axis id off =
  let c = cap st axis id in
  let off' = Float.max 0. (Float.min c off) in
  let st, acts =
    if Float.abs (off' -. offset st axis id) > 0.001 then begin
      let st =
        match axis with
        | Y -> { st with off = IdMap.add id off' st.off }
        | X -> { st with off_x = IdMap.add id off' st.off_x }
      in
      ({ st with epoch = st.epoch + 1 }, [ `Repaint ])
    end else (st, [])
  in
  (* VisibleRange is a row concept — reported on y moves only. *)
  if axis = Y then
    let st, acts' = report_vrange env store st id in
    (st, acts @ acts')
  else (st, acts)

let scroll_to ?(axis = Y) env store st id off =
  set_offset env store st axis id off

let scroll_by ?(axis = Y) env store st id d =
  set_offset env store st axis id (offset st axis id +. d)

(* Nearest scrollable ancestor-or-self of [id]. *)
let scroll_ancestor store id =
  let rec go cur =
    if scrollable store cur then Some cur
    else
      match Lui_store.parent store cur with
      | Some p -> go p
      | None -> None
  in
  go id

(* Reveal [id] inside its nearest scrollable ancestor — minimal
   reveal on both axes (a clipped column scrolls horizontally too). *)
let scroll_show env store st id =
  match scroll_ancestor store id with
  | None -> (st, [])
  | Some a ->
    let ar = env.content_rect a and nr = env.content_rect id in
    if rect_empty ar || rect_empty nr then (st, [])
    else begin
      let reveal lo hi off view =
        if lo < off then lo
        else if hi > off +. view then hi -. view
        else off
      in
      let top = nr.Lui_scene.y -. ar.Lui_scene.y in
      let left = nr.Lui_scene.x -. ar.Lui_scene.x in
      let st, a1 =
        set_offset env store st Y a
          (reveal top (top +. nr.Lui_scene.h)
             (offset st Y a) ar.Lui_scene.h)
      in
      let st, a2 =
        set_offset env store st X a
          (reveal left (left +. nr.Lui_scene.w)
             (offset st X a) ar.Lui_scene.w)
      in
      (st, a1 @ a2)
    end

(* scroll-anchor aligned reveal for scroll-target requests. *)
let scroll_align env store st a it anchor =
  let ar = env.content_rect a and nr = env.content_rect it in
  if rect_empty ar || rect_empty nr then (st, [])
  else
    let top = nr.Lui_scene.y -. ar.Lui_scene.y in
    let off' =
      match anchor with
      | "top" -> top
      | "center" -> top -. ((ar.Lui_scene.h -. nr.Lui_scene.h) /. 2.)
      | "bottom" -> top +. nr.Lui_scene.h -. ar.Lui_scene.h
      | _ ->
        (* "nearest" / unset: minimal reveal. *)
        let off = offset st Y a in
        if top < off then top
        else if top +. nr.Lui_scene.h > off +. ar.Lui_scene.h then
          top +. nr.Lui_scene.h -. ar.Lui_scene.h
        else off
    in
    set_offset env store st Y a off'

(* Wheel deltas scroll the deepest scrollable ancestor under the
   pointer per axis — a +x delta scrolls right, a +y delta scrolls
   content up (SDL convention), and Shift turns the vertical delta
   horizontal (the desktop's wheel-x gesture). Each container consumes
   its available range and passes unused distance to its ancestors
   on the same axis, stopping at the current presented overlay. *)
let wheel env store st ~path ~scale ~dx ~dy ~(mods : Lui_input.mods) =
  let ix = dx +. if mods.Lui_input.shift then -.dy else 0. in
  let iy = if mods.Lui_input.shift then 0. else -.dy in
  if ix = 0. && iy = 0. then (st, [])
  else begin
    let scroll_axis axis intent (st, acts) =
      let rec consume st acts remaining = function
        | [] -> (st, acts)
        | _ when abs_float remaining <= 0.001 -> (st, acts)
        | id :: rest ->
            let rest =
              if Lui_query.presented_overlay store id then [] else rest
            in
            let before = offset st axis id in
            if
              scrollable store id
              &&
              if remaining > 0. then before < cap st axis id -. 0.001
              else before > 0.001
            then
              let st', next =
                set_offset env store st axis id (before +. remaining)
              in
              let consumed = offset st' axis id -. before in
              consume st'
                (List.rev_append next acts)
                (remaining -. consumed) rest
            else consume st acts remaining rest
      in
      consume st acts (intent *. 44. *. scale) path
    in
    let st, acts = (st, []) |> scroll_axis X ix |> scroll_axis Y iy in
    (st, List.rev acts)
  end

(* Store-sync half: handle scroll-target requests on list containers
   and refresh the tracked-list id set. Runs inside the caller's
   store-revision gate — everything here is store-derived. *)
let sync env store st =
  let st = ref st in
  let acts = ref [] in
  Lui_store.iter_preorder store
    (fun id ->
       if Lui_query.kind_name store id = "list" then
         match Lui_store.int_prop store id "scroll-token" with
         | Some tok ->
           (match IdMap.find_opt id !st.tokens with
            | Some prev when prev = tok -> ()
            | _ ->
              st := { !st with tokens = IdMap.add id tok !st.tokens };
              let target = Lui_query.string_prop store id "scroll-target" in
              let item =
                if target = "" then None
                else
                  List.find_opt
                    (fun c -> Lui_query.string_prop store c "key" = target)
                    (Lui_store.preorder ~root:id store)
              in
              (match item with
               | Some it ->
                 let anchor =
                   Lui_query.string_prop store id "scroll-anchor" in
                 let st', a = scroll_align env store !st id it anchor in
                 st := st';
                 acts := List.rev_append a !acts;
                 acts :=
                   `Dispatch (ScrollCompleted (id, tok, "succeeded"))
                   :: !acts
               | None ->
                 acts :=
                   `Dispatch (ScrollCompleted (id, tok, "missing-target"))
                   :: !acts))
         | None -> ()
         else if Lui_query.kind_name store id = "virtual-list" then
           (* The schema wires scroll-target on ListContainer only;
              virtual lists take the same triple over data-attrs and
              resolve the key through the extent model — the target
              row does not need to be mounted. *)
           match
             ( Option.bind
                 (Lui_query.data_attr store id "data-scroll-token")
                 (fun s -> int_of_string_opt (String.trim s)),
               Lui_query.data_attr store id "data-scroll-target",
               env.vlist )
           with
           | Some tok, Some target, Some vh when target <> "" -> (
             match IdMap.find_opt id !st.tokens with
             | Some prev when prev = tok -> ()
             | _ ->
               st := { !st with tokens = IdMap.add id tok !st.tokens };
               (match vh.vh_index_of_key id target with
                | Some i ->
                  let cid = Lui_store.child_id_at store id i in
                  if cid >= 0 then begin
                    let anchor =
                      match
                        Lui_query.data_attr store id "data-scroll-anchor"
                      with
                      | Some a -> a
                      | None -> ""
                    in
                    let st', a =
                      scroll_align env store !st id cid anchor
                    in
                    st := st';
                    acts := List.rev_append a !acts;
                    acts :=
                      `Dispatch (ScrollCompleted (id, tok, "succeeded"))
                      :: !acts
                  end
                  else
                    acts :=
                      `Dispatch
                        (ScrollCompleted (id, tok, "missing-target"))
                      :: !acts
                | None ->
                  acts :=
                    `Dispatch (ScrollCompleted (id, tok, "missing-target"))
                    :: !acts))
           | _ -> ());
  (* The tracked-list ids are store-derived too — refreshed under
     the same gate so the per-sync report loop only walks actual
     VisibleRange producers, not the whole tree. *)
  let lists = ref [] in
  Lui_store.iter_preorder store (fun id ->
    let kind = Lui_query.kind_name store id in
    if (kind = "list" && Lui_store.bool_prop store id "track-visible-range")
       || (kind = "virtual-list"
           && Lui_query.data_attr store id "data-track-visible-range" = Some "true")
    then lists := id :: !lists);
  st := { !st with lists = List.rev !lists };
  (!st, List.rev !acts)

(* Visible-range reports follow scroll offsets, which live here
   rather than the store, so they run on every sync — report_vrange
   memoizes on its own inputs. *)
let report_tracked env store st =
  let st = ref st in
  let acts = ref [] in
  List.iter
    (fun id ->
       let st', a = report_vrange env store !st id in
       st := st';
       acts := List.rev_append a !acts)
    !st.lists;
  (!st, List.rev !acts)
