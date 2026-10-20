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
   - [sub_pops]: the popup nodes this subtree promotes to the *next*
     overlay-drain level, in preorder — the same queueing the walk's
     deferred pass produces, so popups nested inside popups surface
     one level at a time.

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
     children resolve against — containing block, alpha and the clip
     context the shared walk threads down. *)
  mutable alpha_in : float;
  mutable parent_r : rect;
  mutable alpha_out : float;
  mutable child_parent : rect;
  mutable clip_out : rect option;
  mutable show_kids : bool;
  mutable born : bool;
  (* [has_box]/[resolved]: the rect ops were painted under, for
     translation reuse. [was_last]: the store-level last-sibling
     status chrome read at paint time — sibling-set churn can flip it
     without touching the node's own props. [hard]: a mark whose
     effect isn't pure geometry — translation is only legal without
     it. *)
  mutable has_box : bool;
  mutable resolved : rect;
  mutable was_last : bool;
  mutable hard : bool;
  mutable repaint : bool;
  mutable rekids : bool;
  mutable seg_dirty : bool;
  (* Buffer bases assigned while materializing the current frame. *)
  mutable gen : int;
  mutable gbase : int;
  mutable wbase : int;
  mutable ebase : int;
}

type surface_easing =
  | Linear
  | Bezier of float * float * float * float
  | Steps of int * [ `Start | `End | `None | `Both ]

type surface_timing = {
  duration : float;
  delay : float;
  easing : surface_easing;
}

type surface_track = {
  from_value : float;
  target_value : float;
  started : float;
  run_duration : float;
  timing : surface_timing;
}

type surface_motion = {
  mutable snapshot : frag;
  mutable bounds : rect;
  mutable opacity : surface_track;
  mutable zoom : surface_track;
  mutable timings : surface_timing * surface_timing;
  mutable declaration : string option;
}

type retained = {
  frags : (int, frag) Hashtbl.t;
  surfaces : (int, surface_motion) Hashtbl.t;
  mutable surface_order : int list;
  mutable now : float option;
  mutable reduced_motion : bool;
  mutable motion_dirty : bool;
  (* The parent whose kids list last contained the id — lets drop/move
     ops re-derive the right child list when the op only names the
     child. *)
  fparent : (int, int) Hashtbl.t;
  (* Open work the next materialize must process: child lists run
     first so parent links are current, then segments — every mark
     lands there since a repaint always perturbs its segment. *)
  pend_kids : (int, unit) Hashtbl.t;
  pend_segs : (int, unit) Hashtbl.t;
  (* Store revision the journal has been replayed through. *)
  mutable rev : int;
  mutable vp : rect;
  mutable scale : float;
  (* Any mark since the last materialize. *)
  mutable dirty : bool;
  mutable resync : bool;
  (* Materialize generation — fragments record which frame last
     pushed their buffers. *)
  mutable mgen : int;
  (* Instrumentation for tests/benchmarks. *)
  mutable stat_repaints : int;
  mutable stat_visits : int;
  (* Virtualized containers: the mounted window each kids list was
     last built from, and the hook answering the current one. A slid
     window re-derives that container's kids. *)
  vwin : (int, int list) Hashtbl.t;
  mutable mounted : int -> int list option;
}

let create () =
  { surfaces = Hashtbl.create 4; surface_order = []; now = None;
    reduced_motion = false; motion_dirty = false;
    frags = Hashtbl.create 256; fparent = Hashtbl.create 256;
    pend_kids = Hashtbl.create 16; pend_segs = Hashtbl.create 64;
    rev = -1; vp = rect 0. 0. 0. 0.; scale = 1.;
    dirty = false; resync = false; mgen = 0; stat_repaints = 0; stat_visits = 0;
    vwin = Hashtbl.create 4; mounted = (fun _ -> None) }

let surface_easing value =
  let invalid () = invalid_arg ("Invalid native transition easing: " ^ value) in
  let arguments prefix =
    let start = String.length prefix in
    String.sub value start (String.length value - start - 1)
    |> String.split_on_char ',' |> List.map String.trim
  in
  match value with
  | "linear" -> Linear
  | "ease" -> Bezier (0.25, 0.1, 0.25, 1.)
  | "ease-in" -> Bezier (0.42, 0., 1., 1.)
  | "ease-out" -> Bezier (0., 0., 0.58, 1.)
  | "ease-in-out" -> Bezier (0.42, 0., 0.58, 1.)
  | "step-start" -> Steps (1, `Start)
  | "step-end" -> Steps (1, `End)
  | _ when String.starts_with ~prefix:"cubic-bezier(" value -> (
      match arguments "cubic-bezier(" |> List.map float_of_string_opt with
      | [ Some x1; Some y1; Some x2; Some y2 ]
        when List.for_all Float.is_finite [ x1; y1; x2; y2 ]
             && x1 >= 0. && x1 <= 1. && x2 >= 0. && x2 <= 1. ->
          Bezier (x1, y1, x2, y2)
      | _ -> invalid ())
  | _ when String.starts_with ~prefix:"steps(" value -> (
      let parts = arguments "steps(" in
      match parts with
      | [ count ] | [ count; "end" ] | [ count; "jump-end" ] -> (
          match int_of_string_opt count with
          | Some n when n > 0 -> Steps (n, `End)
          | _ -> invalid ())
      | [ count; mode ] -> (
          match (int_of_string_opt count, mode) with
          | Some n, ("start" | "jump-start") when n > 0 -> Steps (n, `Start)
          | Some n, "jump-none" when n > 1 -> Steps (n, `None)
          | Some n, "jump-both" when n > 0 -> Steps (n, `Both)
          | _ -> invalid ())
      | _ -> invalid ())
  | _ -> invalid ()

let surface_timings declaration kind =
  match declaration with
  | None ->
      let duration =
        match kind with
        | "dialog" | "alert" | "sheet" | "drawer" -> 0.2
        | _ -> 0.15
      in
      let easing =
        match kind with
        | "dialog" | "alert" | "sheet" | "drawer" -> Bezier (0., 0., 0.58, 1.)
        | _ -> Bezier (0.25, 0.1, 0.25, 1.)
      in
      let timing = { duration; delay = 0.; easing } in
      (timing, timing)
  | Some declaration ->
      let immediate = { duration = 0.; delay = 0.; easing = Linear } in
      List.fold_left
        (fun (opacity, transform) -> function
          | (("opacity" | "transform" | "all") as property) :: tokens ->
              let is_time token = String.ends_with ~suffix:"s" token in
              let times, easings = List.partition is_time tokens in
              let seconds token =
                let millis = String.ends_with ~suffix:"ms" token in
                let suffix = if millis then 2 else 1 in
                float_of_string
                  (String.sub token 0 (String.length token - suffix))
                /. if millis then 1000. else 1.
              in
              let duration, delay =
                match times with
                | [ duration ] -> (seconds duration, 0.)
                | [ duration; delay ] -> (seconds duration, seconds delay)
                | _ -> invalid_arg "Invalid native transition times"
              in
              let easing =
                match easings with
                | [] -> surface_easing "ease"
                | [ value ] -> surface_easing value
                | _ -> invalid_arg "Invalid native transition easing list"
              in
              let timing = { duration; delay; easing } in
              ( (if property = "transform" then opacity else timing),
                if property = "opacity" then transform else timing )
          | _ -> (opacity, transform))
        (immediate, immediate)
        (Lui_protocol.transition_segments declaration)

let easing_value easing progress =
  match easing with
  | Linear -> progress
  | Steps (count, mode) ->
      let step = Float.floor (progress *. float count) in
      let step =
        step +. match mode with `Start | `Both -> 1. | `End | `None -> 0.
      in
      let jumps =
        count + match mode with `None -> -1 | `Both -> 1 | `Start | `End -> 0
      in
      Float.max 0. (Float.min 1. (step /. float jumps))
  | Bezier (x1, y1, x2, y2) ->
      if progress <= 0. then 0.
      else if progress >= 1. then 1.
      else
        let coordinate t a b =
          let other = 1. -. t in
          (3. *. other *. other *. t *. a)
          +. (3. *. other *. t *. t *. b)
          +. (t *. t *. t)
        in
        let rec solve low high remaining =
          let t = (low +. high) /. 2. in
          if remaining = 0 then coordinate t y1 y2
          else if coordinate t x1 x2 < progress then solve t high (remaining - 1)
          else solve low t (remaining - 1)
        in
        solve 0. 1. 20

let surface_track ~now ~from_value ~target_value timing =
  {
    from_value;
    target_value;
    started = now;
    timing;
    (* CSS reversal shortens the run by its remaining endpoint distance. *)
    run_duration =
      timing.duration *. Float.min 1. (Float.abs (target_value -. from_value));
  }

let track_value now track =
  let elapsed = now -. track.started -. track.timing.delay in
  if elapsed < 0. then track.from_value
  else if track.run_duration = 0. || elapsed >= track.run_duration then
    track.target_value
  else
    let eased =
      easing_value track.timing.easing (elapsed /. track.run_duration)
    in
    track.from_value +. ((track.target_value -. track.from_value) *. eased)

let track_active now track =
  track.from_value <> track.target_value
  && now < track.started +. track.timing.delay +. track.run_duration

let surface_alpha now motion =
  Float.max 0. (Float.min 1. (track_value now motion.opacity))

let animating rt =
  match rt.now with
  | None -> false
  | Some now ->
      Hashtbl.fold
        (fun _ motion active ->
          active || track_active now motion.opacity || track_active now motion.zoom)
        rt.surfaces false

let tick rt ~now =
  let was_animating = animating rt in
  rt.now <- Some now;
  if was_animating then rt.motion_dirty <- true;
  was_animating

let set_reduced_motion rt enabled =
  if rt.reduced_motion <> enabled then begin
    rt.reduced_motion <- enabled;
    if enabled && Hashtbl.length rt.surfaces > 0 then begin
      Hashtbl.clear rt.surfaces;
      rt.surface_order <- [];
      rt.motion_dirty <- true
    end
  end

let invalidate (rt : retained) =
  Hashtbl.reset rt.frags;
  Hashtbl.reset rt.fparent;
  Hashtbl.reset rt.pend_kids;
  Hashtbl.reset rt.pend_segs;
  Hashtbl.reset rt.vwin;
  (* Fresh fragments start with no kid list and nothing marks them:
     the next paint must re-derive every node's children, or the tree
     paints as childless roots (an empty frame). *)
  rt.resync <- true;
  rt.dirty <- true

let stat_repaints (rt : retained) = rt.stat_repaints
let stat_visits (rt : retained) = rt.stat_visits

let fresh_frag id =
  { self = id; kind = ""; pre = []; post = [];
    glyphs = [||]; wide = [||]; fx = [||];
    kids = []; seg = []; sub_pops = []; emitted = false;
    alpha_in = 0.; parent_r = rect 0. 0. 0. 0.;
    alpha_out = 0.; child_parent = rect 0. 0. 0. 0.;
    clip_out = None; show_kids = false; born = false;
    has_box = false; resolved = rect 0. 0. 0. 0.;
    was_last = false; hard = true;
    repaint = false; rekids = false; seg_dirty = true;
    gen = -1; gbase = 0; wbase = 0; ebase = 0 }

let frag_of (rt : retained) id =
  try Hashtbl.find rt.frags id with Not_found ->
    let f = fresh_frag id in
    Hashtbl.replace rt.frags id f;
    f

(* The paint-parent of [id] — whoever last listed it as a child — or
   the live store parent when paint never saw it. *)
let paint_parent rt store id =
  match Hashtbl.find_opt rt.fparent id with
  | Some p when p <> 0 -> Some p
  | _ -> Lui_store.parent store id

(* [seg_dirty] and [pend_segs] diverge on purpose: the flag persists
   for branches under a culled ancestor until they surface, while the
   worklist is drained and reset every materialize. A lingering flag
   must never keep a fresh mark off the worklist — a dirty-but-
   unlisted fragment whose parent does not rebuild this frame would
   emit its stale pieces through the parent's memoized [Sub]. *)
let mark_seg rt id =
  let f = frag_of rt id in
  f.seg_dirty <- true;
  Hashtbl.replace rt.pend_segs id ()

let mark_repaint rt id =
  let f = frag_of rt id in
  f.repaint <- true;
  f.hard <- true;
  mark_seg rt id;
  rt.dirty <- true

(* Geometry-only mark: rects moved under unchanged props/state — a
   pure translation may re-derive the fragment without re-planning. *)
let mark_geom rt id =
  let f = frag_of rt id in
  f.repaint <- true;
  mark_seg rt id;
  rt.dirty <- true

(* A parent's child set is about to be re-derived: the store-level
   last-sibling flag chrome reads ([default_chrome]'s divider) can
   flip for a node whose own props never moved. Repaint the current
   last child plus every stale kid that held the flag last paint. *)
let mark_last_flip rt store id =
  (match Lui_store.last_child_id store id with
   | Some l -> mark_repaint rt l
   | None -> ());
  match Hashtbl.find_opt rt.frags id with
  | Some f ->
    List.iter
      (fun (k, _) ->
        match Hashtbl.find_opt rt.frags k with
        | Some kf when kf.was_last -> mark_repaint rt k
        | _ -> ())
      f.kids
  | None -> ()

let mark_rekids rt store id =
  mark_last_flip rt store id;
  let f = frag_of rt id in
  if not f.rekids then begin
    f.rekids <- true;
    Hashtbl.replace rt.pend_kids id ()
  end;
  mark_seg rt id;
  rt.dirty <- true

let mark_parent_rekids rt store id =
  match paint_parent rt store id with
  | Some p -> mark_rekids rt store p
  | None -> ()

(* A composed surface paints its descendants in its own fragment. Child
   mutations must invalidate that owner even when its outer rect stays put. *)
let mark_composed_ancestor rt store id =
  let mark owner =
    match Hashtbl.find_opt rt.frags owner with
     | Some owner when owner.born && owner.has_box && not owner.show_kids ->
       mark_repaint rt owner.self
     | _ -> () in
  let rec above parent =
    if parent <> id then begin
      mark parent;
      Option.iter above (Lui_store.parent store parent)
    end in
  mark id;
  Option.iter above (paint_parent rt store id)

(* [f]'s emit-status moved — its slot in the parent's piece list is
   stale. Culled parents carry no child slots to update: when they
   surface, their own rebuild enumerates children fresh. *)
let flip_to_parent rt store f =
  match paint_parent rt store f.self with
  | Some p ->
    let pf = frag_of rt p in
    if pf.show_kids then mark_seg rt p
  | None -> ()

(* Props whose value a *different* node's paint reads: "foreground"
   inherits down the ancestor chain, a tooltip/alert/bubble parent's
   own "background" flips its direct text children's ink, and an
   extension renderer's contract is unknown. Their journal marks must
   reach every reader, not just the node they landed on. *)
let mark_inherited rt store id name =
  if name = "foreground" then
    List.iter (mark_repaint rt) (Lui_store.preorder ~root:id store)
  else if
    name = "background"
    &&
    (match Lui_store.kind store id with
     | "tooltip" | "alert" | "bubble" -> true
     | _ -> false)
  then List.iter (mark_repaint rt) (Lui_store.child_ids store id)

(* Cached child lists describe the last painted window, not the complete
   disposal topology. A coalesced teardown or a virtual-window change can
   leave retired descendants outside those lists. Prune at structural
   journal boundaries against the authoritative final store. *)
let prune_retired rt store =
  let prune table = Hashtbl.filter_map_inplace (fun id item ->
    if Lui_store.mem store id then Some item else None) table in
  prune rt.frags;
  prune rt.pend_kids;
  prune rt.pend_segs;
  prune rt.vwin;
  Hashtbl.filter_map_inplace (fun id parent ->
    if Lui_store.mem store id && (parent=0 || Lui_store.mem store parent)
    then Some parent else None) rt.fparent


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
    let retired = ref false in
    List.iter
      (fun (op : Lui_protocol.patch_op) ->
        (match op with
         | SetProp (id,_,_) | RemoveProp (id,_) | SetExtensionProp (id,_,_)
         | RemoveExtensionProp (id,_) | CreateNode (id,_) | CreateExtension (id,_,_)
         | DropNode id | DetachSubtree id -> mark_composed_ancestor rt store id
         | InsertChild (parent,child,_) | MoveChild (parent,child,_)
         | RemoveChild (parent,child) ->
           mark_composed_ancestor rt store child;
           mark_composed_ancestor rt store parent);
        match op with
        | SetProp (id, p, _) | RemoveProp (id, p) -> (
          let name = Lui_wire_schema.property_name p in
          let m = Lui_store.mask_of_prop name in
          if m land Lui_store.d_paint <> 0 then mark_repaint rt id;
          mark_inherited rt store id name;
          (* Structure-classified props (display) change the node's
             deferral in the parent's child list; a z-index change
             reorders it. Both re-derive the parent's kids. *)
          if
            m land Lui_store.d_structure <> 0 || name = "z-index"
          then mark_parent_rekids rt store id)
        | SetExtensionProp (id, _, _) | RemoveExtensionProp (id, _) ->
          (* Unknown semantics: repaint the whole subtree — a
             renderer's prop contract can reach its descendants — and
             re-derive the node's slot under the parent. *)
          List.iter (mark_repaint rt) (Lui_store.preorder ~root:id store);
          mark_parent_rekids rt store id
        | CreateNode (id, _) | CreateExtension (id, _, _) ->
          (* A reused id can retire descendants without an explicit drop. *)
          retired := true;
          Hashtbl.remove rt.surfaces id;
          mark_repaint rt id
        | DropNode id | DetachSubtree id ->
          retired := true;
          rt.dirty <- true;
          mark_parent_rekids rt store id;
          (* Cached children may already belong to another live owner.
             Retire this node only; prune_retired removes descendants
             against the final store without discarding moved branches. *)
          Hashtbl.remove rt.frags id
        | InsertChild (p, c, _) ->
          mark_rekids rt store p;
          (* The context [c] resolves against may differ under the new
             parent even when its layout rect happens to coincide, and
             inherited props (foreground, the inverse-surface
             background rule) flow through the whole ancestor chain —
             every descendant can change too. *)
          List.iter (mark_repaint rt) (Lui_store.preorder ~root:c store);
          (* The store silently unlinks [c] from its old parent — the
             journal names only the new one, so the recorded
             paint-parent must rebuild its kid list too. *)
          mark_parent_rekids rt store c
        | RemoveChild (p, c) ->
          mark_rekids rt store p;
          (* An orphaned child becomes a forest root: re-derive it
             under root context (viewport block, alpha 1, no clip) —
             and repaint its subtree, which loses the inherited props
             that used to flow down through it. *)
          List.iter (mark_repaint rt) (Lui_store.preorder ~root:c store)
        | MoveChild (p, c, _) ->
          mark_rekids rt store p;
          mark_repaint rt c;
          mark_parent_rekids rt store c)
      ops;
    if !retired then prune_retired rt store;
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
      (match rt.mounted id with
       | Some ids ->
         Hashtbl.replace rt.vwin id ids;
         Lui_paint.z_ordered store
           (List.filter_map (Lui_store.find_opt store) ids)
       | None ->
         Hashtbl.remove rt.vwin id;
         Lui_paint.ordered_children store id);
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

(* Uniform-translation re-derivation: only these fields carry
   absolute coordinates — gradient vectors are unit-space, [isrc] is
   texture-space, radii/borders/shadow-offsets are relative, and the
   [fx] buffer's shader params are opaque (its presence disables the
   fast path). *)
let shift r dx dy = { r with x = r.x +. dx; y = r.y +. dy }

let translate_op dx dy (op : op) : op =
  match op with
  | Fill fl -> Fill { fl with frect = shift fl.frect dx dy }
  | Shadow s ->
    Shadow
      { s with srect = shift s.srect dx dy;
               scast = shift s.scast dx dy }
  | Image i -> Image { i with irect2 = shift i.irect2 dx dy }
  | Push_clip c -> Push_clip { c with crect = shift c.crect dx dy }
  | Effect e -> Effect { e with edrect = shift e.edrect dx dy }
  | Hole h -> Hole { h with hrect = shift h.hrect dx dy }
  | Glyphs _ | Pop_clip -> op

let translate_frag (f : frag) dx dy =
  f.pre <- List.map (translate_op dx dy) f.pre;
  f.post <- List.map (translate_op dx dy) f.post;
  if Array.length f.glyphs > 0 then
    f.glyphs <-
      Array.map
        (fun g -> { g with gx = g.gx +. dx; gy = g.gy +. dy })
        f.glyphs

(* The node's own emission, captured into [f]: the same decisions the
   shared stacking walk makes for one node — shown, popup promotion,
   dead-clip ghosting, state/alpha, chrome, clip brackets — minus the
   child walk, which the segment build drives through [f.kids].
   Geometry comes from {!Lui_paint.frame_of} and the chrome from
   {!Lui_paint.paint_enter}/{!Lui_paint.paint_leave}, so a fragment
   can never disagree with a full [Lui_paint.paint] about where a
   node sits or what it emits. Ops land in the scene's swapped-in
   fresh buffers so every buffer index they carry is fragment-local.
   Afterwards, children whose inherited context actually moved get
   re-marked (the alpha, containing-block and clip cascades). *)
let repaint_frag rt ctx store scene (f : frag) id kind ~parent_r
    ~alpha_in ~clip_in =
  let old_alpha = f.alpha_out and old_cp = f.child_parent
  and old_clip = f.clip_out in
  f.alpha_in <- alpha_in;
  f.parent_r <- parent_r;
  f.kind <- kind;
  (* Store-level sibling position, refreshed on every repaint —
     [mark_last_flip] consumes it when the parent's child set moves.
     Mirrors [default_chrome]'s [last_sibling] read exactly. *)
  f.was_last <-
    (match Lui_store.parent store id with
     | Some pid -> (
       match Lui_store.last_child_id store pid with
       | Some last -> last = id
       | None -> true)
     | None -> true);
  let vp = ctx.Lui_paint.viewport in
  let no_ops () =
    f.pre <- [];
    f.post <- [];
    f.glyphs <- [||];
    f.wide <- [||];
    f.fx <- [||];
    f.has_box <- false
  in
  if ctx.Lui_paint.hooks.hidden id || not (Lui_paint.node_shown store id) then begin
    (* Hidden: the walk never reaches the node — no chrome, no
       children, no popup search. *)
    no_ops ();
    f.show_kids <- false;
    f.resolved <- rect 0. 0. 0. 0.;
    f.child_parent <- parent_r;
    f.clip_out <- clip_in;
    f.alpha_out <- alpha_in;
    f.born <- true;
    f.repaint <- false;
    f.hard <- false
  end
  else begin
    let contents = Lui_paint.unboxed store id in
    (* A promoted popup escapes the inherited clip entirely: the walk
       re-enters it under a fresh clip context in the overlay drain. *)
    let clip_in =
      if Lui_paint.popup_kind kind && not contents then None
      else clip_in
    in
    let p = ctx.Lui_paint.hooks.layout id in
    let fr, child_clip =
      Lui_paint.frame_of ~scale:ctx.Lui_paint.scale ~viewport:vp store
        id kind p parent_r clip_in
    in
    if Lui_paint.clip_dead ~viewport:vp clip_in then begin
      (* Ghosted by a dead ancestor clip: no chrome, but the subtree
         still walks — a promoted popup inside can escape, and the
         ghost context keeps threading the accumulated alpha down to
         it. *)
      no_ops ();
      f.resolved <- fr.Lui_paint.f_rect;
      f.child_parent <- fr.Lui_paint.f_parent_r;
      f.clip_out <- child_clip;
      f.alpha_out <-
        Lui_paint.paint_ghost_enter ctx store alpha_in id contents;
      f.show_kids <- true;
      f.born <- true;
      f.repaint <- false;
      f.hard <- false
    end
    else begin
      (* Node-not-drawn vs subtree-invisible: only the node's own
         chrome is skipped when its painted area misses the frame;
         the subtree still walks. A pure translation shifts every
         absolute coordinate in the cached ops — no re-plan. *)
      let node_drawn =
        (not fr.Lui_paint.f_contents)
        && (rect_empty fr.Lui_paint.f_rect
            || not
                 (rect_empty
                    (rect_intersect fr.Lui_paint.f_clipped vp)))
      in
      if
        node_drawn && (not f.hard) && f.has_box
        && Array.length f.fx = 0
        && fr.Lui_paint.f_rect.w = f.resolved.w
        && fr.Lui_paint.f_rect.h = f.resolved.h
        && not (Lui_paint.viewport_anchored kind)
      then begin
        translate_frag f
          (fr.Lui_paint.f_rect.x -. f.resolved.x)
          (fr.Lui_paint.f_rect.y -. f.resolved.y);
        f.resolved <- fr.Lui_paint.f_rect;
        f.child_parent <- fr.Lui_paint.f_parent_r;
        f.clip_out <- child_clip;
        (* [alpha_out] and [show_kids] stand: the cached ops were
           painted under them and a geom-only mark cannot have moved
           the alpha channel. *)
        f.repaint <- false;
        f.hard <- false
      end
      else begin
        let saved_ops = scene.ops
        and saved_glyphs = scene.glyphs
        and saved_wide = scene.wide
        and saved_fx = scene.effects in
        scene.ops <- [];
        scene.glyphs <- [];
        scene.wide <- [];
        scene.effects <- [];
        let br = Lui_paint.paint_enter ctx store scene alpha_in fr in
        f.pre <- List.rev scene.ops;
        scene.ops <- [];
        if br.Lui_paint.b_emit then
          Lui_paint.paint_leave ctx store scene br.Lui_paint.b_ctx fr;
        f.post <- List.rev scene.ops;
        f.glyphs <- Array.of_list (List.rev scene.glyphs);
        f.wide <- Array.of_list (List.rev scene.wide);
        f.fx <- Array.of_list scene.effects;
        scene.ops <- saved_ops;
        scene.glyphs <- saved_glyphs;
        scene.wide <- saved_wide;
        scene.effects <- saved_fx;
        f.has_box <- br.Lui_paint.b_emit;
        f.show_kids <- br.Lui_paint.b_down;
        f.alpha_out <- br.Lui_paint.b_ctx;
        f.resolved <- fr.Lui_paint.f_rect;
        f.child_parent <- fr.Lui_paint.f_parent_r;
        f.clip_out <- child_clip;
        f.born <- true;
        f.repaint <- false;
        f.hard <- false;
        rt.stat_repaints <- rt.stat_repaints + 1
      end
    end
  end;
  (* Inherited-context cascade: children painted under the old values
     must re-derive when any moved — alpha moves re-plan, a pure
     containing-block or clip-context shift may only need
     re-positioning. *)
  if f.alpha_out <> old_alpha then
    List.iter (fun (k, _) -> mark_repaint rt k) f.kids
  else if f.child_parent <> old_cp || f.clip_out <> old_clip then
    List.iter (fun (k, _) -> mark_geom rt k) f.kids

(* Parent context for a pending repaint, painting the parent first so
   the inherited alpha/containing-block/clip are current. [None]
   while the parent's subtree is culled — the child keeps its marks
   for when the branch surfaces. *)
let rec parent_ctx rt store ctx scene vp id =
  match paint_parent rt store id with
  | Some p -> (
    let pf = frag_of rt p in
    ignore (ensure_painted rt store ctx scene vp pf);
    if pf.show_kids then Some (pf.child_parent, pf.alpha_out, pf.clip_out)
    else None)
  | None -> Some (vp, 1., None)

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
      | Some (parent_r, alpha_in, clip_in) ->
        repaint_frag rt ctx store scene f f.self
          (Lui_store.kind store f.self) ~parent_r ~alpha_in ~clip_in;
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

(* Physical identity on frag lists — [sub_pops] change detection. *)
let rec same_frags xs ys =
  match (xs, ys) with
  | [], [] -> true
  | x :: xs', y :: ys' -> x == y && same_frags xs' ys'
  | _ -> false

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
        ~clip_in:f.clip_out
  end;
  if kf.born && kf.seg_dirty then rebuild_seg rt store scene m kf

(* Rebuild [f.seg]/[f.sub_pops] from the current pieces, descending
   into dirty children first so every kid's emit-status is fresh when
   the fold reads it. Clean kids contribute their memoized pieces for
   free; culled kids are not enumerated at all. *)
and rebuild_seg rt store scene m (f : frag) =
  rt.stat_visits <- rt.stat_visits + 1;
  f.seg_dirty <- false;
  let old_pops = f.sub_pops in
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
    (* Only the next drain level: a deferred kid contributes itself;
       the popups *it* promotes wait behind it in the drain queue,
       exactly like the walk's deferred thunk enqueuing during the
       drain. *)
    f.sub_pops <-
      List.concat_map
        (fun (k, deferred) ->
          let kf = frag_of rt k in
          if deferred then [ kf ] else kf.sub_pops)
        f.kids
  end
  else begin
    f.seg <- own f.pre @ own f.post;
    f.sub_pops <- []
  end;
  (* Emit-status and next-level promotion flips both re-derive the
     parent's piece/promotion lists. *)
  let e = f.seg <> [] in
  if e <> f.emitted || not (same_frags old_pops f.sub_pops) then begin
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

(* Snapshot only one promoted surface's display list, sharing atlas pixels.
   An exiting snapshot has no store nodes, handlers, or hit-test presence. *)
let capture_surface rt scene m surface =
  let capture =
    Lui_scene.create ~mask_atlas:scene.mask_atlas ~color_atlas:scene.color_atlas
  in
  rt.mgen <- rt.mgen + 1;
  let local =
    { m with m_gen = rt.mgen; gcount = 0; wcount = 0; ecount = 0; fx_rev = [] }
  in
  emit_seg capture local surface;
  let snapshot = fresh_frag surface.self in
  snapshot.pre <- List.rev capture.ops;
  snapshot.glyphs <- Array.of_list (List.rev capture.glyphs);
  snapshot.wide <- Array.of_list (List.rev capture.wide);
  snapshot.fx <- Array.of_list (List.rev local.fx_rev);
  snapshot

let emit_surface scene m viewport motion alpha zoom_progress =
  let zoom = 0.95 +. (0.05 *. zoom_progress) in
  let cx = motion.bounds.x +. (motion.bounds.w /. 2.)
  and cy = motion.bounds.y +. (motion.bounds.h /. 2.) in
  let point_x x = cx +. ((x -. cx) *. zoom)
  and point_y y = cy +. ((y -. cy) *. zoom) in
  let box r =
    { x = point_x r.x; y = point_y r.y; w = r.w *. zoom; h = r.h *. zoom }
  in
  let radii (a, b, c, d) = (a *. zoom, b *. zoom, c *. zoom, d *. zoom) in
  let transform = function
    | Fill f ->
        Fill
          {
            f with
            frect = (if f.frect = viewport then f.frect else box f.frect);
            fradii = radii f.fradii;
            fborder = radii f.fborder;
            fopacity = f.fopacity *. alpha;
          }
    | Shadow s ->
        Shadow
          {
            s with
            srect = box s.srect;
            scast = box s.scast;
            sradii = radii s.sradii;
            scast_radii = radii s.scast_radii;
            sblur = s.sblur *. zoom;
            sopacity = s.sopacity *. alpha;
          }
    | Image i ->
        Image
          {
            i with
            irect2 = box i.irect2;
            iradii = radii i.iradii;
            iopacity = i.iopacity *. alpha;
          }
    | Glyphs g -> Glyphs { g with gopacity = g.gopacity *. alpha }
    | Push_clip c ->
        Push_clip { c with crect = box c.crect; cradii = radii c.cradii }
    | Effect e ->
        Effect
          {
            e with
            edrect = box e.edrect;
            edradii = radii e.edradii;
            edopacity = e.edopacity *. alpha;
          }
    | Hole h ->
        Hole
          {
            h with
            hrect = box h.hrect;
            hradii = radii h.hradii;
            hopacity = h.hopacity *. alpha;
          }
    | Pop_clip -> Pop_clip
  in
  let snapshot = motion.snapshot in
  let visual =
    if zoom_progress = 1. then snapshot
    else
      {
        snapshot with
        glyphs =
          Array.map
            (fun g ->
              {
                g with
                gx = point_x g.gx;
                gy = point_y g.gy;
                gw = g.gw *. zoom;
                gh = g.gh *. zoom;
              })
            snapshot.glyphs;
      }
  in
  push_buffers scene m visual;
  List.iter
    (fun op ->
      let op = if alpha = 1. && zoom_progress = 1. then op else transform op in
      scene.ops <- rebase visual op :: scene.ops)
    snapshot.pre

let present_surfaces rt scene m viewport store ~refresh live =
  let now = Option.get rt.now in
  let seen = Hashtbl.create (List.length live) in
  List.iter
    (fun (surface : frag) ->
      Hashtbl.add seen surface.self ();
      match Hashtbl.find_opt rt.surfaces surface.self with
      | None ->
          let snapshot = capture_surface rt scene m surface in
          let declaration =
            Lui_store.string_prop store surface.self "transition"
          in
          let opacity_timing, zoom_timing =
            surface_timings declaration surface.kind
          in
          Hashtbl.add rt.surfaces surface.self
            {
              snapshot;
              bounds = surface.resolved;
              opacity =
                surface_track ~now ~from_value:0. ~target_value:1.
                  opacity_timing;
              zoom =
                surface_track ~now ~from_value:0. ~target_value:1. zoom_timing;
              timings = (opacity_timing, zoom_timing);
              declaration;
            }
      | Some motion ->
          if refresh then begin
            motion.snapshot <- capture_surface rt scene m surface;
            let declaration =
              Lui_store.string_prop store surface.self "transition"
            in
            if declaration <> motion.declaration then begin
              motion.timings <- surface_timings declaration surface.kind;
              motion.declaration <- declaration
            end
          end;
          motion.bounds <- surface.resolved;
          if motion.opacity.target_value <> 1. then begin
            let opacity_timing, zoom_timing = motion.timings in
            motion.opacity <-
              surface_track ~now ~from_value:(surface_alpha now motion)
                ~target_value:1. opacity_timing;
            motion.zoom <-
              surface_track ~now
                ~from_value:(track_value now motion.zoom)
                ~target_value:1. zoom_timing
          end)
    live;
  Hashtbl.filter_map_inplace
    (fun id motion ->
      if (not (Hashtbl.mem seen id)) && motion.opacity.target_value <> 0. then begin
        let opacity_timing, zoom_timing = motion.timings in
        motion.opacity <-
          surface_track ~now ~from_value:(surface_alpha now motion)
            ~target_value:0. opacity_timing;
        motion.zoom <-
          surface_track ~now
            ~from_value:(track_value now motion.zoom)
            ~target_value:0. zoom_timing
      end;
      if
        motion.opacity.target_value = 0.
        && (not (track_active now motion.opacity))
        && not (track_active now motion.zoom)
      then None
      else Some motion)
    rt.surfaces;
  (* Exiting shells remain behind the current live overlay stack. *)
  let closing =
    List.filter
      (fun id -> (not (Hashtbl.mem seen id)) && Hashtbl.mem rt.surfaces id)
      rt.surface_order
  in
  rt.surface_order <-
    closing @ List.map (fun (surface : frag) -> surface.self) live;
  List.iter
    (fun id ->
      let motion = Hashtbl.find rt.surfaces id in
      emit_surface scene m viewport motion (surface_alpha now motion)
        (track_value now motion.zoom))
    rt.surface_order

let paint_retained rt hooks store (scene : Lui_scene.t) ?moved ?hints ?vlists
    ~width ~height ~scale ~clear () =
  let vp = rect 0. 0. (float width) (float height) in
  if vp <> rt.vp || scale <> rt.scale then begin
    (* Culling and fixed-position resolution key on the frame. *)
    invalidate rt;
    rt.vp <- vp;
    rt.scale <- scale
  end;
  if Lui_store.revision store <> rt.rev then advance rt store;
  rt.mounted <- hooks.Lui_paint.mounted_children;
  if rt.resync then begin
    rt.resync <- false;
    List.iter
      (fun root ->
        List.iter (fun id -> mark_rekids rt store id)
          (Lui_store.preorder ~root store))
      (Lui_store.root_ids store)
  end;
  (* A virtual list whose mounted window slid (scroll, resize) has a
     stale kids list even though no store op named it. *)
  (match vlists with
   | Some ids ->
     List.iter
       (fun id ->
         let now = rt.mounted id in
         let before = Hashtbl.find_opt rt.vwin id in
         if now <> before then mark_rekids rt store id)
       ids
   | None -> ());
  (match moved with
   | Some mv -> Hashtbl.iter (fun id () ->
       if Lui_store.mem store id then mark_geom rt id) mv
   | None -> ());
  (match hints with
   | Some h -> Hashtbl.iter (fun id () ->
       if Lui_store.mem store id then begin
         mark_repaint rt id;
         mark_composed_ancestor rt store id
       end) h
   | None -> ());
  if rt.dirty || rt.motion_dirty then begin
    let refresh_surfaces = rt.dirty in
    rt.motion_dirty <- false;
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
    let root_frags = List.map (frag_of rt) roots in
    (* A root that is itself a popup kind promotes like any other
       node — the walk defers it to the overlay pass too. *)
    let promotes (f : frag) =
      Lui_paint.popup_kind (Lui_store.kind store f.self)
      && not (Lui_paint.unboxed store f.self)
    in
    List.iter
      (fun f -> if not (promotes f) then emit_seg scene m f)
      root_frags;
    (* Overlay drain: the walk's deferred queue — each subtree's
       next-level promotions in forest order, emitting a memoized
       segment apiece and seeding the level behind them. *)
    let drain = Queue.create () in
    List.iter
      (fun f ->
        if promotes f then Queue.add f drain
        else List.iter (fun g -> Queue.add g drain) f.sub_pops)
      root_frags;
    let live = ref [] in
    let motion_enabled = rt.now <> None && not rt.reduced_motion in
    while not (Queue.is_empty drain) do
      let g = Queue.pop drain in
      if motion_enabled then (if g.emitted then live := g :: !live)
      else emit_seg scene m g;
      List.iter (fun h -> Queue.add h drain) g.sub_pops
    done;
    if motion_enabled then present_surfaces rt scene m vp store ~refresh:refresh_surfaces (List.rev !live);
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
