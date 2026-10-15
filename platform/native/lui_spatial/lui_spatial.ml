(* Spatial index over resolved node rects (P2-2): per-node subtree
   bounds plus per-parent interval-ordered child arrays, shared by
   hit-testing and the paint pass's viewport cull.

   The index is a pure snapshot: [build] folds the store's shown tree
   over a rect source (the hit mirror's resolved, scroll-shifted and
   snapped rects — the same geometry [Lui_paint.walk] produces), and
   the walk consumes it to skip subtrees that cannot contribute to the
   query. Point queries (hit-testing) answer "which subtree could
   contain this point"; region queries (paint) answer "which subtree
   could intersect the viewport". Both preserve the walk's exact
   semantics — z-ordered visit, promoted popups escaping ancestor
   clips, display:contents pass-through, hidden subtrees skipped — so
   the index records three facts per node:

   - [b]: union of the shown subtree's non-empty resolved rects.
     Every clipped subtree area is a subrect of [b] ∩ clip, so a
     point outside [b] (or a region disjoint from it) prunes safely.
   - [eb]: the clip-escaping part of [b] — bounds of promoted popups,
     which paint and hit-test above and outside their ancestors'
     clip contexts. A point inside [eb] keeps the subtree alive even
     when the current clip excludes it.
   - [z]: the subtree contains a zero-area node. Empty rects still
     run the emission path today (degenerate ops, split-pane clip
     brackets), so a region query must keep such subtrees to stay
     op-identical; point queries can ignore them — an empty rect
     contains nothing.

   Wide parents (>= [kid_threshold] children) additionally get an
   interval index: children sorted by bound top with a prefix-max
   bottom table, so a query touches O(log n + candidates) siblings
   instead of every child. *)

open Lui_scene

(** What a consumer is looking for. *)
type query =
  | Point of float * float  (** hit-testing: containment semantics *)
  | Region of rect          (** paint culling: intersection semantics *)

(** Per-node subtree facts; [b] and [eb] may be empty rects. *)
type info = { b : rect; eb : rect; z : bool }

(* One child inside a wide parent's interval index. [k_esc] mirrors
   the walk's promotion rule ([popup_kind && not unboxed]) so queries
   decide clip escape without fetching the node; [k_rank] is the
   child's position in paint order so filtered results revisit
   siblings exactly as the unindexed walk would. *)
type kid = { k_id : int; k_rank : int; k_esc : bool; ki : info }

(* [ka]: children whose subtrees carry no zero-area node, sorted by
   bound top — the interval-scanned array. [kmax]: prefix max over
   [ka]'s bound bottoms — the scan stops once no earlier sibling can
   reach the query band. [kz]: zero-subtree children, in paint order.
   Region queries keep every [kz] child unconditionally (zero-area
   nodes still run the emission path — clip brackets, degenerate
   fills); point queries check them linearly since a zero-descendant
   says nothing about the child's own bound. The split is disjoint:
   a z-child in [ka] could be lost to the band cutoff a region query
   must not apply to it. *)
type kids_arr = { ka : kid array; kmax : float array; kz : kid array }

type t = {
  info : (int, info) Hashtbl.t;
  kids : (int, kids_arr) Hashtbl.t;
  roots : int list;
      (* the forest's roots, captured at build so the walk can start
         without a fresh [Lui_store.root_ids] scan — the index is a
         snapshot, so its roots are exactly the ones the caller should
         visit. *)
}

let empty =
  { info = Hashtbl.create 8; kids = Hashtbl.create 2; roots = [] }

let roots t = t.roots

(* Above this child count a parent gets the sorted interval arrays;
   below it the walk falls back to a per-child [keep] lookup. *)
let kid_threshold = 32

(** The store/paint predicates [build] needs, supplied by the caller
    so this module stays free of Lui_paint dependencies: [shown] is
    the walk's visibility gate, [promotes] is its clip-escape rule
    (popup kind and not display:contents), [ordered] yields children
    in paint order. *)
type env = {
  shown : Lui_store.t -> int -> bool;
  promotes : Lui_store.t -> int -> bool;
  ordered : Lui_store.t -> int -> Lui_store.node list;
}

let info t id = Hashtbl.find_opt t.info id

let empty_rect = rect 0. 0. 0. 0.
let empty_info = {b=empty_rect; eb=empty_rect; z=false}

(* Most wrappers have the same bounds as their child. Reuse immutable
   rectangles when the union already exists, including negative bounds. *)
let union_bounds a b =
  if rect_empty b then a
  else begin
    let no_bounds = rect_empty a in
    let x0 = if no_bounds || b.x<a.x then b.x else a.x in
    let y0 = if no_bounds || b.y<a.y then b.y else a.y in
    let x1 = if no_bounds || b.x+.b.w>a.x+.a.w then b.x+.b.w else a.x+.a.w in
    let y1 = if no_bounds || b.y+.b.h>a.y+.a.h then b.y+.b.h else a.y+.a.h in
    let w = x1-.x0 and h = y1-.y0 in
    if a.x=x0 && a.y=y0 && a.w=w && a.h=h then a
    else if b.x=x0 && b.y=y0 && b.w=w && b.h=h then b
    else rect x0 y0 w h
  end

(* Post-order fold over shown nodes: [b] unions every non-empty
   resolved rect in the subtree, [eb] unions the bounds of children
   that promote (their whole subtree escapes this node's clip
   context; non-promoting children contribute only their own
   escapees upward), [z] flags zero-area rects a region query must
   keep visiting. *)
let build env store ~rect_of =
  let roots = Lui_store.root_ids store in
  let idx =
    { info = Hashtbl.create 256; kids = Hashtbl.create 16; roots }
  in
  let rec visit id =
    if not (env.shown store id) then empty_info
    else begin
      let b = ref empty_rect and eb = ref empty_rect in
      let z = ref false in
      let children = ref (Lui_store.children store id) in
      while !children <> [] do
        match !children with
        | [] -> ()
        | node :: rest ->
          let cid = Lui_store.node_id node in
          let child = visit cid in
          b := union_bounds !b child.b;
          (* A promoting child's whole bound escapes the clip context
             this node's children share; a non-promoting child passes
             only its own escapees upward. *)
          eb := union_bounds !eb (if env.promotes store cid then child.b else child.eb);
          if child.z then z := true;
          children := rest
      done;
      let r = rect_of id in
      b := union_bounds !b r;
      let zero = !z || rect_empty r in
      let facts = {b= !b; eb= !eb; z=zero} in
      Hashtbl.replace idx.info id facts;
      if Lui_store.child_count store id >= kid_threshold then
        build_kids id;
      facts
    end
  and build_kids id =
    (* Paint-order positions are ranks; [ka] sorts by bound top for
       the interval scan. Hidden children never entered [info], so
       they drop out of both arrays. *)
    let arr =
      env.ordered store id
      |> List.mapi (fun rank n -> (rank, Lui_store.node_id n))
      |> List.filter_map (fun (rank, cid) ->
             match Hashtbl.find_opt idx.info cid with
             | None -> None
             | Some ki ->
               Some
                 { k_id = cid; k_rank = rank;
                   k_esc = env.promotes store cid; ki })
      |> Array.of_list
    in
    let ka =
      let a =
        Array.of_list
          (List.filter (fun k -> not k.ki.z) (Array.to_list arr))
      in
      Array.sort (fun x c -> Float.compare x.ki.b.y c.ki.b.y) a;
      a
    in
    let kmax = Array.make (Array.length ka) 0. in
    Array.iteri
      (fun i k ->
        let bot = k.ki.b.y +. k.ki.b.h in
        kmax.(i) <- (if i = 0 then bot else Float.max kmax.(i - 1) bot))
      ka;
    let kz = Array.of_list
      (List.filter (fun k -> k.ki.z) (Array.to_list arr)) in
    Hashtbl.replace idx.kids id { ka; kmax; kz }
  in
  List.iter (fun id -> ignore (visit id)) roots;
  idx

(* The keep-test shared by the per-child fallback and the interval
   arrays. [i] is the child's subtree facts; [esc] whether the child
   itself promotes (its frame then runs clip-free); [clip] the clip
   context its subtree is visited under. *)
let ok i ~esc ~clip q =
  match q with
  | Region r -> i.z || not (rect_empty (rect_intersect i.b r))
  | Point (x, y) ->
    (esc && rect_contains i.b x y)
    || rect_contains i.eb x y
    || (rect_contains i.b x y
        &&
        match clip with
        | Some c -> rect_contains c x y
        | None -> true)

(* May the subtree of node [id] contribute to [q] under clip context
   [clip]? Absent info means a hidden subtree — the walk skips it
   wholesale either way. *)
let keep t ~clip ~esc q id =
  match Hashtbl.find_opt t.info id with
  | None -> false
  | Some i -> ok i ~esc ~clip q

(* Count of [ka] entries whose bound top precedes [ylimit] ([<] for
   regions — a touching band is an empty intersection — [<=] for
   points). Entries past it start below the query band. *)
let band_end (ka : kid array) ~inclusive ylimit =
  let n = Array.length ka in
  let rec go lo hi =
    if lo >= hi then lo
    else
      let mid = (lo + hi) / 2 in
      if ka.(mid).ki.b.y < ylimit
         || (inclusive && ka.(mid).ki.b.y = ylimit)
      then go (mid + 1) hi
      else go lo mid
  in
  go 0 n

(* Children of [pid] that can contribute to [q], in paint order.
   [None] when the parent has no interval index — the caller falls
   back to per-child [keep] tests. *)
let children t ~clip q pid : int list option =
  match Hashtbl.find_opt t.kids pid with
  | None -> None
  | Some karr ->
    let hits =
      match q with
      | Point (_, y) ->
        (* Candidates need b.y <= y < b.bottom: scan the prefix of
           tops <= y while the prefix-max bottom still reaches y. *)
        let hi = band_end karr.ka ~inclusive:true y in
        let acc = ref [] in
        let rec back i =
          if i >= 0 && karr.kmax.(i) > y then begin
            let k = karr.ka.(i) in
            if ok k.ki ~esc:k.k_esc ~clip q then acc := k :: !acc;
            back (i - 1)
          end
        in
        back (hi - 1);
        Array.fold_left
          (fun acc k -> if ok k.ki ~esc:k.k_esc ~clip q then k :: acc
            else acc)
          !acc karr.kz
      | Region r ->
        let hi = band_end karr.ka ~inclusive:false (r.y +. r.h) in
        let acc = ref [] in
        let rec back i =
          if i >= 0 && karr.kmax.(i) > r.y then begin
            let k = karr.ka.(i) in
            if ok k.ki ~esc:k.k_esc ~clip q then acc := k :: !acc;
            back (i - 1)
          end
        in
        back (hi - 1);
        (* Zero-subtree children always stay reachable for emission;
           merge them into the ranked result. *)
        Array.fold_left (fun acc k -> k :: acc) !acc karr.kz
    in
    (* Re-establish paint order: ranks sort the candidates exactly as
       ordered_children would list them. *)
    let sorted =
      List.sort (fun a c -> compare a.k_rank c.k_rank) hits
    in
    Some (List.map (fun k -> k.k_id) sorted)
