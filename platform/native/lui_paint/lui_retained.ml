(* Retained scene fragments: a per-node paint cache sitting between
   the store and {!Lui_scene}.

   A full [Lui_paint.paint] re-plans every mounted node each frame —
   prop lookups, state/style resolution, chrome op construction — even
   when nothing changed. This module caches, per node:

   - its own emitted ops (split around the point children paint),
     self-contained against fragment-local glyph/wide/effect buffers;
   - [kids]: the store children in paint order, popup kinds flagged
     for the overlay drain;
   - [seg]: the subtree's emission as a piece list — own ops inline,
     children as [Sub] references — so a child's content change never
     touches its ancestors' segment lists. Ancestors re-derive only
     when a child's *emit-status* flips (shown ↔ silent) or the child
     set/order changes;
   - [sub_pops]: the popup nodes this subtree contributes to the
     overlay drain, in preorder.

   Marks come from three channels: the store op journal (replayed at
   a paint-owned cursor), engine rect changes ([~moved]), and host
   interaction hints ([~hints]). A dirty frame processes three
   worklists — kid lists, repaints, then segment rebuilds deepest
   first — and materializes the flat buffers at O(emitted ops).
   Clean frames skip assembly entirely.

   Correctness contract: hooks whose answers change outside those
   channels (a theme swap, a decoded image) must be poked through
   hints or {!invalidate}. *)

open Lui_scene

(* A subtree piece: an op of the owning frag, or a reference to a
   child's memoized segment. References keep a child's content edits
   out of the parent's list — only emit-status flips and membership
   churn rebuild it. *)
type piece = Own of frag * op | Sub of frag

and frag = {
  self : int;
  mutable kind : string;
  mutable pre : op list;
  mutable post : op list;
  mutable glyphs : glyph array;
  mutable wide : wide_colors array;
  mutable fx : effect_op array;
  (* Store children in paint order as (id, defers-to-overlay). *)
  mutable kids : (int * bool) list;
  (* Memoized subtree emission (inline children only) and the popup
     nodes below it, both rebuilt on [seg_dirty]. [emitted] is
     [seg <> []] at last build — the emit-status the parent folded. *)
  mutable seg : piece list;
  mutable sub_pops : frag list;
  mutable emitted : bool;
  (* Inherited inputs the fragment was painted under, and the results
     children resolve against. *)
  mutable alpha_in : float;
  mutable parent_r : rect;
  mutable alpha_out : float;
  mutable child_parent : rect;
  mutable show_kids : bool;
  mutable born : bool;
  mutable repaint : bool;
  mutable rekids : bool;
  mutable seg_dirty : bool;
  (* Buffer bases assigned while materializing the current frame. *)
  mutable gen : int;
  mutable gbase : int;
  mutable wbase : int;
  mutable ebase : int;
}

type retained = {
  frags : (int, frag) Hashtbl.t;
  (* The parent whose kids list last contained the id — lets drop/move
     ops re-derive the right child list when the op only names the
     child. *)
  fparent : (int, int) Hashtbl.t;
  (* Open work the next materialize must process. *)
  pend_repaint : (int, unit) Hashtbl.t;
  pend_kids : (int, unit) Hashtbl.t;
  pend_segs : (int, unit) Hashtbl.t;
  (* Store revision the journal has been replayed through. *)
  mutable rev : int;
  mutable vp : rect;
  mutable scale : float;
  (* Any mark since the last materialize. *)
  mutable dirty : bool;
  (* Materialize generation — fragments record which frame last
     pushed their buffers. *)
  mutable mgen : int;
  (* Instrumentation for tests/benchmarks. *)
  mutable stat_repaints : int;
  mutable stat_visits : int;
}

let create () =
  { frags = Hashtbl.create 256; fparent = Hashtbl.create 256;
    pend_repaint = Hashtbl.create 64; pend_kids = Hashtbl.create 16;
    pend_segs = Hashtbl.create 64;
    rev = -1; vp = rect 0. 0. 0. 0.; scale = 1.;
    dirty = false; mgen = 0; stat_repaints = 0; stat_visits = 0 }

let invalidate (rt : retained) =
  Hashtbl.reset rt.frags;
  rt.dirty <- true

let stat_repaints (rt : retained) = rt.stat_repaints
let stat_visits (rt : retained) = rt.stat_visits

let fresh_frag id =
  { self = id; kind = ""; pre = []; post = [];
    glyphs = [||]; wide = [||]; fx = [||];
    kids = []; seg = []; sub_pops = []; emitted = false;
    alpha_in = 0.; parent_r = rect 0. 0. 0. 0.;
    alpha_out = 0.; child_parent = rect 0. 0. 0. 0.;
    show_kids = false; born = false;
    repaint = false; rekids = false; seg_dirty = true;
    gen = -1; gbase = 0; wbase = 0; ebase = 0 }

let frag_of (rt : retained) id =
  match Hashtbl.find_opt rt.frags id with
  | Some f -> f
  | None ->
    let f = fresh_frag id in
    Hashtbl.replace rt.frags id f;
    f

(* The paint-parent of [id] — whoever last listed it as a child — or
   the live store parent when paint never saw it. *)
let paint_parent rt store id =
  match Hashtbl.find_opt rt.fparent id with
  | Some p when p <> 0 -> Some p
  | _ -> Lui_store.parent store id

let mark_seg rt id =
  let f = frag_of rt id in
  if not f.seg_dirty then begin
    f.seg_dirty <- true;
    Hashtbl.replace rt.pend_segs id ()
  end

let mark_repaint rt id =
  let f = frag_of rt id in
  if not f.repaint then begin
    f.repaint <- true;
    Hashtbl.replace rt.pend_repaint id ()
  end;
  mark_seg rt id;
  rt.dirty <- true

let mark_rekids rt id =
  let f = frag_of rt id in
  if not f.rekids then begin
    f.rekids <- true;
    Hashtbl.replace rt.pend_kids id ()
  end;
  mark_seg rt id;
  rt.dirty <- true

let mark_parent_rekids rt store id =
  match paint_parent rt store id with
  | Some p -> mark_rekids rt p
  | None -> ()

(* [f]'s emit-status moved — its slot in the parent's piece list is
   stale. Culled parents carry no child slots to update: when they
   surface, their own rebuild enumerates children fresh. *)
let flip_to_parent rt store f =
  match paint_parent rt store f.self with
  | Some p ->
    let pf = frag_of rt p in
    if pf.show_kids then mark_seg rt p
  | None -> ()

let rec purge_frag rt id =
  match Hashtbl.find_opt rt.frags id with
  | Some f ->
    Hashtbl.remove rt.frags id;
    List.iter (fun (k, _) -> purge_frag rt k) f.kids
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

(* Re-derive the child list from the store: z-ordered like the full
   pass, popup kinds (except display:contents) flagged for the overlay
   drain. *)
let build_kids rt store (f : frag) id =
  let old = f.kids in
  f.kids <-
    List.map
      (fun (c : Lui_store.node) ->
        let cid = Lui_store.node_id c in
        ( cid,
          Lui_paint.popup_kind (Lui_store.node_kind c)
          && not (Lui_paint.unboxed store cid) ))
      (Lui_paint.ordered_children store id);
  (* Re-point parent links: entries this list dropped keep whatever
     parent claimed them since (a reparent op already marked it). *)
  List.iter
    (fun (k, _) ->
      match Hashtbl.find_opt rt.fparent k with
      | Some p when p = id -> Hashtbl.remove rt.fparent k
      | _ -> ())
    old;
  List.iter (fun (k, _) -> Hashtbl.replace rt.fparent k id) f.kids;
  f.rekids <- false

(* The node's own emission, captured into [f]: the same decisions
   [Lui_paint.paint_node_body] makes — shown/cull/state/alpha/clip —
   minus the child walk, which the segment build drives through
   [f.kids]. Ops land in the scene's swapped-in fresh buffers so every
   buffer index they carry is fragment-local. Afterwards, children
   whose inherited context actually moved get re-marked (the alpha
   and containing-block cascades). *)
let repaint_frag rt ctx store scene (f : frag) id kind ~parent_r
    ~alpha_in =
  let old_alpha = f.alpha_out and old_cp = f.child_parent in
  f.alpha_in <- alpha_in;
  f.parent_r <- parent_r;
  f.kind <- kind;
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
        else
          alpha_in *. rs.rs_opacity
          *. Lui_paint.disabled_alpha store id st
      in
      (* display:contents generates no box: children keep the
         parent's containing block and its alpha, exactly like the
         full pass. *)
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
                 cradii =
                   corners r (Lui_paint.radii_of ctx store id) false;
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
  rt.stat_repaints <- rt.stat_repaints + 1;
  scene.ops <- saved_ops;
  scene.glyphs <- saved_glyphs;
  scene.wide <- saved_wide;
  scene.effects <- saved_fx;
  (* Inherited-context cascade: children painted under the old values
     must re-derive when either moved. *)
  if f.alpha_out <> old_alpha || f.child_parent <> old_cp then
    List.iter (fun (k, _) -> mark_repaint rt k) f.kids

(* Parent context for a pending repaint, painting the parent first so
   the inherited alpha/containing-block are current. [None] while the
   parent's subtree is culled — the child keeps its marks for when
   the branch surfaces. *)
let rec parent_ctx rt store ctx scene vp id =
  match paint_parent rt store id with
  | Some p -> (
    let pf = frag_of rt p in
    ignore (ensure_painted rt store ctx scene vp pf);
    if pf.show_kids then Some (pf.child_parent, pf.alpha_out) else None)
  | None -> Some (vp, 1.)

(* Paint [f] if it is marked or unborn — parent context first so the
   inherited values are current. Returns whether [f] holds fresh ops
   afterwards (false only while an ancestor culls it). *)
and ensure_painted rt store ctx scene vp (f : frag) : bool =
  if f.repaint || not f.born then begin
    if not (Lui_store.mem store f.self) then begin
      (* Marked after the node died — drop the fragment. *)
      Hashtbl.remove rt.frags f.self;
      false
    end
    else
      match parent_ctx rt store ctx scene vp f.self with
      | None -> false
      | Some (parent_r, alpha_in) ->
        repaint_frag rt ctx store scene f f.self
          (Lui_store.kind store f.self) ~parent_r ~alpha_in;
        true
  end
  else f.born

(* Materialize-threaded state: running buffer bases plus the frame
   generation that makes each fragment's buffers append once. *)
type mat = {
  m_ctx : Lui_paint.ctx;
  m_gen : int;
  mutable gcount : int;
  mutable wcount : int;
  mutable ecount : int;
  mutable fx_rev : effect_op list;
}

(* Bring one child current — repaint under this parent's resolved
   context, rebuild its own segment — then let the fold read its
   emit-status. Culled parents skip this entirely: the marks persist
   and surface when the branch does. *)
let rec ensure_kid rt store scene m (f : frag) (k, _d) =
  let kf = frag_of rt k in
  if kf.rekids then build_kids rt store kf k;
  if kf.repaint || not kf.born then begin
    if Lui_store.mem store k then
      repaint_frag rt m.m_ctx store scene kf k
        (Lui_store.kind store k)
        ~parent_r:f.child_parent ~alpha_in:f.alpha_out
  end;
  if kf.born && kf.seg_dirty then rebuild_seg rt store scene m kf

(* Rebuild [f.seg]/[f.sub_pops] from the current pieces, descending
   into dirty children first so every kid's emit-status is fresh when
   the fold reads it. Clean kids contribute their memoized pieces for
   free; culled kids are not enumerated at all. *)
and rebuild_seg rt store scene m (f : frag) =
  rt.stat_visits <- rt.stat_visits + 1;
  f.seg_dirty <- false;
  let own ops = List.map (fun o -> Own (f, o)) ops in
  if f.show_kids then begin
    List.iter (ensure_kid rt store scene m f) f.kids;
    f.seg <-
      own f.pre
      @ List.filter_map
          (fun (k, deferred) ->
            let kf = frag_of rt k in
            if deferred || not kf.emitted then None
            else Some (Sub kf))
          f.kids
      @ own f.post;
    f.sub_pops <-
      List.concat_map
        (fun (k, deferred) ->
          let kf = frag_of rt k in
          if deferred then kf :: kf.sub_pops else kf.sub_pops)
        f.kids
  end
  else begin
    f.seg <- own f.pre @ own f.post;
    f.sub_pops <- []
  end;
  (* Emit-status flips re-derive the parent's piece list. *)
  let e = f.seg <> [] in
  if e <> f.emitted then begin
    f.emitted <- e;
    flip_to_parent rt store f
  end

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
  f.gbase <- gbase;
  f.wbase <- wbase;
  f.ebase <- ebase;
  f.gen <- m.m_gen

(* Re-base a fragment-local op onto the frame buffers. Ops without
   buffer links are shared unchanged. *)
let rebase (f : frag) (op : op) : op =
  match op with
  | Glyphs g ->
    Glyphs
      { g with
        gstart = g.gstart + f.gbase;
        gend = g.gend + f.gbase;
        gwide2 = (if g.gwide2 > 0 then g.gwide2 + f.wbase else 0) }
  | Fill fl when fl.fwide > 0 ->
    Fill { fl with fwide = fl.fwide + f.wbase }
  | Shadow s when s.swide > 0 ->
    Shadow { s with swide = s.swide + f.wbase }
  | Effect e -> Effect { e with edindex = e.edindex + f.ebase }
  | op -> op

(* Emit a segment: each [Sub] reference descends into the child's own
     memoized pieces — only emitting nodes are ever visited. *)
let rec emit_seg (scene : Lui_scene.t) m (f : frag) =
  List.iter
    (fun piece ->
      match piece with
      | Own (g, op) ->
        if g.gen <> m.m_gen then push_buffers scene m g;
        scene.ops <- rebase g op :: scene.ops
      | Sub g -> emit_seg scene m g)
    f.seg

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
    let m =
      { m_ctx =
          { Lui_paint.hooks; scale; viewport = vp;
            deferred = Queue.create () };
        m_gen =
          (rt.mgen <- rt.mgen + 1; rt.mgen);
        gcount = 0; wcount = 0; ecount = 0; fx_rev = [] }
    in
    Lui_scene.reset scene ~width ~height ~scale ~clear;
    (* Kid lists first: parent links must be current before repaints
       resolve their context. *)
    Hashtbl.iter
      (fun id () ->
        match Hashtbl.find_opt rt.frags id with
        | Some f when f.rekids -> build_kids rt store f id
        | _ -> ())
      rt.pend_kids;
    (* Repaints can re-mark children (alpha/containing-block moves) —
       drain until the worklist empties. *)
    while Hashtbl.length rt.pend_repaint > 0 do
      let ids =
        Hashtbl.fold (fun id () acc -> id :: acc) rt.pend_repaint []
      in
      Hashtbl.reset rt.pend_repaint;
      List.iter
        (fun id ->
          match Hashtbl.find_opt rt.frags id with
          | Some f ->
            ignore (ensure_painted rt store m.m_ctx scene vp f)
          | None -> ())
        ids
    done;
    (* Roots anchor the paint tree — link them. Dirty subtrees
       rebuild through the worklist; emit-status flips re-mark
       parents into it. Marks under a culled branch are skipped —
       their flags persist and the ancestor's own rebuild descends
       into them when the branch surfaces. *)
    let roots = Lui_store.root_ids store in
    List.iter (fun id -> Hashtbl.replace rt.fparent id 0) roots;
    while Hashtbl.length rt.pend_segs > 0 do
      let ids =
        Hashtbl.fold (fun id () acc -> id :: acc) rt.pend_segs []
      in
      Hashtbl.reset rt.pend_segs;
      List.iter
        (fun id ->
          match Hashtbl.find_opt rt.frags id with
          | Some f when f.seg_dirty -> (
            match paint_parent rt store id with
            | Some p ->
              let pf = frag_of rt p in
              if (not pf.born) || pf.show_kids then
                if ensure_painted rt store m.m_ctx scene vp f then
                  rebuild_seg rt store scene m f
            | None ->
              if ensure_painted rt store m.m_ctx scene vp f then
                rebuild_seg rt store scene m f)
          | _ -> ())
        ids
    done;
    (* Clean roots need no rebuild — their piece lists hold [Sub]
       references that already point at the fresh child segments. *)
    List.iter
      (fun id ->
        let f = frag_of rt id in
        if f.seg_dirty || f.repaint || not f.born then
          if ensure_painted rt store m.m_ctx scene vp f then
            rebuild_seg rt store scene m f)
      roots;
    List.iter (emit_seg scene m) (List.map (frag_of rt) roots);
    (* Overlay drain: subtree popups in preorder — each emits its own
       memoized segment. *)
    List.iter
      (fun id ->
        List.iter (emit_seg scene m) (frag_of rt id).sub_pops)
      roots;
    while not (Queue.is_empty m.m_ctx.Lui_paint.deferred) do
      (Queue.pop m.m_ctx.Lui_paint.deferred) ()
    done;
    scene.ops <- List.rev scene.ops;
    scene.glyphs <- List.rev scene.glyphs;
    scene.wide <- List.rev scene.wide;
    scene.effects <- List.rev m.fx_rev;
    (* Marks raised while materializing were consumed through the
       same frame's worklists — nothing may leak a phantom dirty into
       the next frame. Fragment flags persist independently for
       culled branches. *)
    Hashtbl.reset rt.pend_repaint;
    Hashtbl.reset rt.pend_kids;
    Hashtbl.reset rt.pend_segs;
    rt.dirty <- false
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
