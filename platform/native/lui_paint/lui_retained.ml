(* Retained scene fragments: a per-node paint cache sitting between the
   store and {!Lui_scene}.

   A full [Lui_paint.paint] re-plans every mounted node each frame —
   prop lookups, state/style resolution, chrome op construction — even
   when nothing changed. This module caches what each node emitted (its
   own chrome ops plus the glyph/wide/effect records they index, all
   local to the fragment) and replays the store's op journal plus
   host-supplied move/state hints to repaint only the fragments whose
   inputs actually changed. Clean frames skip assembly entirely; a
   single-node update pays for that node, while the materialize pass
   still walks the fragment tree to rebuild the flat scene buffers the
   renderers consume.

   Correctness contract: anything a node paints derives from (a) the
   store — tracked by the journal, (b) its layout hook answer — the
   engine reports moved rects, and (c) host interaction state — the
   caller reports touched ids via [~hints]. Hooks whose answers change
   silently outside those channels must be poked through hints. *)

open Lui_scene

(* One node's cached emission. [pre]/[post] are the node's own ops in
   paint order (before/after the point children emit), self-contained:
   [Glyphs.gstart]/[gend] index [glyphs], [fwide]/[gwide2]/[swide]/
   [gwide] index [wide] (1-based, 0 = none), [edindex] indexes [fx].
   Materialize re-bases them onto the frame buffers. *)
type frag = {
  mutable pre : op list;
  mutable post : op list;
  mutable glyphs : glyph array;
  mutable wide : wide_colors array;
  mutable fx : effect_op array;
  (* Children in paint order, split by stacking contract: [pkids]
     defer to the overlay drain like the full pass's deferred queue. *)
  mutable kids : int list;
  mutable pkids : int list;
  (* Inherited inputs the fragment was painted under. *)
  mutable alpha_in : float;
  mutable parent_r : rect;
  (* Results handed to children. *)
  mutable alpha_out : float;
  mutable child_parent : rect;
  mutable show_kids : bool;
  mutable born : bool;
  mutable repaint : bool;
  mutable rekids : bool;
}

type retained = {
  frags : (int, frag) Hashtbl.t;
  (* The parent whose kids list last contained the id — lets drop/move
     ops re-derive the right child list when the op only names the
     child. *)
  fparent : (int, int) Hashtbl.t;
  (* Store revision the journal has been replayed through. *)
  mutable rev : int;
  mutable vp : rect;
  mutable scale : float;
  (* Any mark since the last materialize. *)
  mutable dirty : bool;
  (* Instrumentation for tests/benchmarks. *)
  mutable stat_repaints : int;
  mutable stat_visits : int;
}

let create () =
  { frags = Hashtbl.create 256; fparent = Hashtbl.create 256;
    rev = -1; vp = rect 0. 0. 0. 0.; scale = 1.;
    dirty = false; stat_repaints = 0; stat_visits = 0 }

let invalidate (rt : retained) =
  Hashtbl.reset rt.frags;
  rt.dirty <- true

let stat_repaints (rt : retained) = rt.stat_repaints
let stat_visits (rt : retained) = rt.stat_visits

let fresh_frag () =
  { pre = []; post = []; glyphs = [||]; wide = [||]; fx = [||];
    kids = []; pkids = []; alpha_in = 0.; parent_r = rect 0. 0. 0. 0.;
    alpha_out = 0.; child_parent = rect 0. 0. 0. 0.; show_kids = false;
    born = false; repaint = false; rekids = false }

let frag_of (rt : retained) id =
  match Hashtbl.find_opt rt.frags id with
  | Some f -> f
  | None ->
    let f = fresh_frag () in
    Hashtbl.replace rt.frags id f;
    f

let mark_repaint rt id =
  let f = frag_of rt id in
  f.repaint <- true;
  rt.dirty <- true

let mark_rekids rt id =
  let f = frag_of rt id in
  f.rekids <- true;
  rt.dirty <- true

(* The paint-parent of [id] — whoever last listed it as a child — or
   the live store parent when paint never saw it. *)
let paint_parent rt store id =
  match Hashtbl.find_opt rt.fparent id with
  | Some p when p <> 0 -> Some p
  | _ -> Lui_store.parent store id

let mark_parent_rekids rt store id =
  match paint_parent rt store id with
  | Some p -> mark_rekids rt p
  | None -> ()

let rec purge_frag rt id =
  match Hashtbl.find_opt rt.frags id with
  | Some f ->
    Hashtbl.remove rt.frags id;
    List.iter (purge_frag rt) f.kids;
    List.iter (purge_frag rt) f.pkids
  | None -> ()

(* Replay the store ops since [rt.rev], translating them into fragment
   marks. Mirrors the layout engine's incremental contract: the
   journal is the single source of truth for what the store saw. *)
let advance rt store =
  match Lui_store.changes_since store rt.rev with
  | None ->
    (* Journal truncated past our cursor — resync wholesale. *)
    invalidate rt;
    rt.rev <- Lui_store.revision store
  | Some ops ->
    List.iter
      (fun (op : Lui_protocol.patch_op) ->
        match op with
        | SetProp (id, p, _) | RemoveProp (id, p) -> (
          let name = Lui_wire_schema.property_name p in
          let m = Lui_store.mask_of_prop name in
          if m land Lui_store.d_paint <> 0 then mark_repaint rt id;
          (* Structure-classified props (display) change the node's
             deferral in the parent's child list; a z-index change
             reorders it. Both re-derive the parent's kids. *)
          if
            m land Lui_store.d_structure <> 0 || name = "z-index"
          then mark_parent_rekids rt store id)
        | SetExtensionProp (id, _, _) | RemoveExtensionProp (id, _) ->
          (* Unknown semantics: repaint the node and re-derive its
             slot under the parent. *)
          mark_repaint rt id;
          mark_parent_rekids rt store id
        | CreateNode (id, _) | CreateExtension (id, _, _) ->
          (* A reused id may still carry a stale fragment. *)
          mark_repaint rt id
        | DropNode id | DetachSubtree id ->
          mark_parent_rekids rt store id;
          purge_frag rt id
        | InsertChild (p, c, _) ->
          mark_rekids rt p;
          (* The store silently unlinks [c] from its old parent — the
             journal names only the new one, so the recorded
             paint-parent must rebuild its kid list too. *)
          mark_parent_rekids rt store c
        | RemoveChild (p, _) -> mark_rekids rt p
        | MoveChild (p, c, _) ->
          mark_rekids rt p;
          mark_parent_rekids rt store c)
      ops;
    (* [rt.dirty] only follows real marks — a semantics-only op leaves
       the frame alone. *)
    rt.rev <- Lui_store.revision store

(* The node's own emission, captured into [f]: the same decisions
   [Lui_paint.paint_node_body] makes — shown/cull/state/alpha/clip —
   minus the child walk, which the materialize drives itself through
   [f.kids]/[f.pkids]. Ops land in the scene's swapped-in fresh buffers
   so every buffer index they carry is fragment-local. *)
let repaint_frag ctx store (scene : Lui_scene.t) (f : frag) id kind ~parent_r ~alpha_in =
  f.alpha_in <- alpha_in;
  f.parent_r <- parent_r;
  let saved_ops = scene.ops
  and saved_glyphs = scene.glyphs
  and saved_wide = scene.wide
  and saved_fx = scene.effects in
  scene.ops <- [];
  scene.glyphs <- [];
  scene.wide <- [];
  scene.effects <- [];
  let pre = ref [] and post = ref [] in
  let show_kids = ref false in
  let child_parent = ref parent_r and alpha_out = ref alpha_in in
  if Lui_paint.node_shown store id then begin
    let contents = Lui_paint.unboxed store id in
    let p = ctx.Lui_paint.hooks.layout id in
    let r = Lui_paint.resolve_in ctx store id kind p parent_r in
    let misses_viewport =
      (not contents)
      && (not (rect_empty r))
      && rect_empty (rect_intersect r ctx.Lui_paint.viewport)
    in
    if not misses_viewport then begin
      let st = Lui_paint.effective_state ctx.hooks store id in
      let rs = Lui_paint.resolve_style store id st in
      let alpha =
        if contents then alpha_in
        else alpha_in *. rs.rs_opacity *. Lui_paint.disabled_alpha store id st
      in
      (* display:contents generates no box: children keep the parent's
         containing block and its alpha, exactly like the full pass. *)
      child_parent := (if contents then parent_r else r);
      alpha_out := alpha;
      if alpha > 0. then begin
        show_kids := true;
        let clip =
          (not contents)
          && Lui_paint.clips kind store id
          && ((not (rect_empty r))
              || (match Lui_store.parent store id with
                 | Some pid -> Lui_store.kind store pid = "split"
                 | None -> false))
        in
        if clip then
          Lui_paint.emit1 scene
            (Push_clip
               { crect = r;
                 cradii = corners r (Lui_paint.radii_of ctx store id) false;
                 ccontinuous = false });
        if not contents then
          Lui_paint.emit scene
            (Lui_paint.paint_own ctx store id st kind r rs alpha);
        pre := List.rev scene.ops;
        scene.ops <- [];
        if Lui_paint.scrollable kind store id && not contents then
          Lui_paint.emit scene
            (Lui_paint.scrollbar_ops ctx store id r alpha);
        if clip then Lui_paint.emit1 scene Pop_clip;
        post := List.rev scene.ops
      end
    end
  end;
  f.pre <- !pre;
  f.post <- !post;
  f.glyphs <- Array.of_list (List.rev scene.glyphs);
  f.wide <- Array.of_list (List.rev scene.wide);
  f.fx <- Array.of_list scene.effects;
  f.child_parent <- !child_parent;
  f.alpha_out <- !alpha_out;
  f.show_kids <- !show_kids;
  f.born <- true;
  f.repaint <- false;
  scene.ops <- saved_ops;
  scene.glyphs <- saved_glyphs;
  scene.wide <- saved_wide;
  scene.effects <- saved_fx

(* Re-derive the child list from the store: z-ordered like the full
   pass, popup kinds (except display:contents) split into the deferred
   set so the overlay drain can paint them last. *)
let build_kids rt store (f : frag) id =
  let old = f.kids @ f.pkids in
  let kids, pkids =
    List.fold_left
      (fun (ks, ps) (c : Lui_store.node) ->
        let cid = Lui_store.node_id c in
        if
          Lui_paint.popup_kind (Lui_store.node_kind c)
          && not (Lui_paint.unboxed store cid)
        then (ks, cid :: ps)
        else (cid :: ks, ps))
      ([], []) (Lui_paint.ordered_children store id)
  in
  f.kids <- List.rev kids;
  f.pkids <- List.rev pkids;
  (* Re-point parent links: entries this list dropped keep whatever
     parent claimed them since (a reparent op already marked it). *)
  List.iter
    (fun k ->
      match Hashtbl.find_opt rt.fparent k with
      | Some p when p = id -> Hashtbl.remove rt.fparent k
      | _ -> ())
    old;
  List.iter (fun k -> Hashtbl.replace rt.fparent k id) (f.kids @ f.pkids);
  f.rekids <- false

(* Materialize-threaded state: running buffer bases plus the popup
     drain. *)
type mat = {
  m_ctx : Lui_paint.ctx;
  mutable gcount : int;
  mutable wcount : int;
  mutable ecount : int;
  mutable gbase : int;
  mutable wbase : int;
  mutable ebase : int;
  mutable fx_rev : effect_op list;
  deferred : (int * rect * float * bool) Queue.t;
}

(* Append a fragment's local buffers to the frame's, recording the
   bases its ops need. Glyph records carry their own [gwide] link into
   [scene.wide] — re-based here. *)
let push_buffers (scene : Lui_scene.t) m (f : frag) =
  let wbase = m.wcount in
  Array.iter (fun w -> scene.wide <- w :: scene.wide) f.wide;
  m.wcount <- wbase + Array.length f.wide;
  let ebase = m.ecount in
  Array.iter (fun e -> m.fx_rev <- e :: m.fx_rev) f.fx;
  m.ecount <- ebase + Array.length f.fx;
  let gbase = m.gcount in
  Array.iter
    (fun g ->
      scene.glyphs <-
        (if g.gwide > 0 then { g with gwide = g.gwide + wbase } else g)
        :: scene.glyphs)
    f.glyphs;
  m.gcount <- gbase + Array.length f.glyphs;
  m.gbase <- gbase;
  m.wbase <- wbase;
  m.ebase <- ebase

(* Re-base a fragment-local op onto the frame buffers. Ops without
   buffer links are shared unchanged. *)
let rebase m (op : op) : op =
  match op with
  | Glyphs g ->
    Glyphs
      { g with
        gstart = g.gstart + m.gbase;
        gend = g.gend + m.gbase;
        gwide2 = (if g.gwide2 > 0 then g.gwide2 + m.wbase else 0) }
  | Fill f when f.fwide > 0 -> Fill { f with fwide = f.fwide + m.wbase }
  | Shadow s when s.swide > 0 -> Shadow { s with swide = s.swide + m.wbase }
  | Effect e -> Effect { e with edindex = e.edindex + m.ebase }
  | op -> op

let emit_ops (scene : Lui_scene.t) m ops =
  List.iter (fun op -> scene.ops <- rebase m op :: scene.ops) ops

let rec visit rt store scene m id kind ~parent_r ~alpha_in ~force =
  rt.stat_visits <- rt.stat_visits + 1;
  let f = frag_of rt id in
  if f.rekids || not f.born then build_kids rt store f id;
  if force then
    (* A forcibly moved subtree (e.g. scroll): descendants under a
       culled branch keep their repaint mark for when they surface. *)
    List.iter
      (fun k -> (frag_of rt k).repaint <- true)
      (f.kids @ f.pkids);
  if
    force || f.repaint || (not f.born)
    || f.alpha_in <> alpha_in || f.parent_r <> parent_r
  then begin
    rt.stat_repaints <- rt.stat_repaints + 1;
    repaint_frag m.m_ctx store scene f id kind ~parent_r ~alpha_in
  end;
  push_buffers scene m f;
  emit_ops scene m f.pre;
  if f.show_kids then begin
    let cp = f.child_parent and a = f.alpha_out in
    List.iter
      (fun k ->
        visit rt store scene m k (Lui_store.kind store k) ~parent_r:cp
          ~alpha_in:a ~force)
      f.kids;
    List.iter
      (fun k -> Queue.add (k, cp, a, force) m.deferred)
      f.pkids
  end;
  emit_ops scene m f.post

let paint_retained rt hooks store (scene : Lui_scene.t) ?moved ?hints
    ~width ~height ~scale ~clear () =
  let vp = rect 0. 0. (float width) (float height) in
  if vp <> rt.vp || scale <> rt.scale then begin
    (* Culling and fixed-position resolution key on the frame. *)
    invalidate rt;
    rt.vp <- vp;
    rt.scale <- scale
  end;
  if Lui_store.revision store <> rt.rev then advance rt store;
  (match moved with
   | Some mv -> Hashtbl.iter (fun id () -> mark_repaint rt id) mv
   | None -> ());
  (match hints with
   | Some h -> Hashtbl.iter (fun id () -> mark_repaint rt id) h
   | None -> ());
  if rt.dirty then begin
    rt.dirty <- false;
    Lui_scene.reset scene ~width ~height ~scale ~clear;
    (* Buffer bases + the ctx the repaints run against. The deferred
       queue on the ctx is vestigial — the fragment pass defers by
       classification, not emission. *)
    let m =
      { m_ctx =
          { Lui_paint.hooks; scale; viewport = vp;
            deferred = Queue.create () };
        gcount = 0; wcount = 0; ecount = 0;
        gbase = 0; wbase = 0; ebase = 0;
        fx_rev = []; deferred = Queue.create () }
    in
    List.iter
      (fun id ->
        Hashtbl.replace rt.fparent id 0;
        visit rt store scene m id (Lui_store.kind store id) ~parent_r:vp
          ~alpha_in:1. ~force:false)
      (Lui_store.root_ids store);
    (* Popups (and popups nested inside them) emit after the inline
       forest, preserving the full pass's drain order. *)
    while not (Queue.is_empty m.deferred) do
      let id, parent_r, alpha_in, force = Queue.pop m.deferred in
      visit rt store scene m id (Lui_store.kind store id) ~parent_r
        ~alpha_in ~force
    done;
    scene.ops <- List.rev scene.ops;
    scene.glyphs <- List.rev scene.glyphs;
    scene.wide <- List.rev scene.wide;
    scene.effects <- List.rev m.fx_rev
  end
  else begin
    (* Nothing the fragments depend on moved — the buffers stand.
       Frame identity still tracks the caller's size/clear so later
       consumers read current dimensions. *)
    scene.width <- width;
    scene.height <- height;
    scene.scale <- scale;
    scene.clear <- clear
  end
