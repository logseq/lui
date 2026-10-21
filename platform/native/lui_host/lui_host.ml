(* Native backend assembly: a Lui_protocol.backend whose apply_batch
   mirrors patches into the store and schedules a repaint, plus the
   paint→render pipeline shared by the window loop and headless tests.

   The window/event loop lives in the app driver (tsdl); this module is
   the pure part: apply → layout → paint → pixels, so headless tests can
   drive it without a display. *)

open Lui_scene

(* A renderer evaluates a scene into pixels (CPU today, GL later). *)
type renderer = {
  render : t -> Bytes.t; (* premultiplied BGRA, width*height*4 *)
  name : string;
}

type text_measure = int -> string -> float -> float -> (float * float) option

(* The slice of a layout engine the host drives — Lui_layout satisfies
   this signature. Declared here so the host stays decoupled from the
   concrete engine. *)
module type LAYOUT_ENGINE = sig
  type t

  val create : unit -> t

  val sync :
    ?scale:float -> ?measure:text_measure ->
    ?text_flow:(int -> float -> Lui_paint.text_flow_layout option) ->
    ?image_measure:(int -> (float * float) option) -> ?hidden:(int -> bool) ->
    ?ctx_anchor:(float * float) ->
    ?vport:(int -> (float * float) option) ->
    ?anchor_shift:(int -> float * float) ->
    width:float -> height:float -> t -> Lui_store.t -> unit

  val invalidate : t -> unit

  val layout_hook : t -> int -> Lui_paint.placement

  val rect : t -> int -> Lui_scene.rect option

  (* Virtual-list surface: engines without virtualization return
     [[]]/[None] everywhere, which reproduces the unwindowed path. *)
  val vlists : t -> int list
  val mounted_range : t -> int -> (int * int) option
  val mounted_children : t -> int -> int list option
  val virtual_extent : t -> int -> float option
  val virtual_item_rect : t -> int -> index:int -> Lui_scene.rect option
  val virtual_index_of_key : t -> Lui_store.t -> int -> string -> int option
  val virtual_index_of_id : t -> Lui_store.t -> int -> int -> int option
  val virtual_view : t -> int -> (float * float) option
  val virtual_take_drift : t -> int -> float

  (** Store ids whose absolute rect changed under the last {!sync};
      drained by the paint pass to re-emit only moved subtrees. *)
  val take_rect_changes : t -> (int, unit) Hashtbl.t
end

(* An instantiated engine: what (module LAYOUT_ENGINE) becomes once the
   host has built the engine state at create. *)
type layout_state = {
  lsync :
    scale:float -> measure:text_measure -> hidden:(int -> bool) ->
    ctx_anchor:(float * float) option ->
    vport:(int -> (float * float) option) ->
    anchor_shift:(int -> float * float) ->
    width:float -> height:float -> Lui_store.t -> unit;
  linvalidate : unit -> unit;
  lhook : int -> Lui_paint.placement;
  lrect : int -> rect option;
  llists : unit -> int list;
  lrange : int -> (int * int) option;
  lchildren : int -> int list option;
  lextent : int -> float option;
  litem : int -> index:int -> rect option;
  lkey : int -> string -> int option;
  lid : int -> int -> int option;
  lview : int -> (float * float) option;
  ldrift : int -> float;
  lchanges : unit -> (int, unit) Hashtbl.t;
}

type transition = {
  property : Lui_protocol.property;
  from_value : float;
  target : float;
  started : float;
  duration : float;
  easing : string;
}

type t = {
  store : Lui_store.t;
  scene : Lui_scene.t;
  hooks : Lui_paint.hooks;
  layout : layout_state option;
  measure : text_measure;
  renderer : renderer;
  mutable width : int;
  mutable height : int;
  mutable scale : float;
  mutable dirty : bool; (* repaint requested since last present *)
  mutable animation_time : float option;
  mutable reduced_motion : bool;
  transitions : (int, transition) Hashtbl.t;
  retained : Lui_retained.retained;
  (* Ids whose host-side paint inputs (interaction state, async
     resources) changed since the last repaint — the fragment pass's
     third dirty channel, next to the store journal and moved rects. *)
  paint_hints : (int, unit) Hashtbl.t;
  (* Soft hints: ids whose rects translated under unchanged
     props/state — the fragment pass may shift cached ops instead of
     re-planning. *)
  moved_hints : (int, unit) Hashtbl.t;
  mutable hidden : int -> bool; (* host-owned transient visibility *)
  (* Pointer point an unanchored context-menu opens at — a thunk so the
     accessor reads the live position each repaint. *)
  mutable ctx_anchor : unit -> (float * float) option;
  (* Bumped by every host-side poke that can change layout output
     without a store revision — [invalidate_layout], [resize],
     [set_hidden], [set_ctx_anchor]. Epoch keys mixing it in stay
     honest across external measure/visibility changes. *)
  mutable inv_count : int;
  (* Virtual-list viewport feed: node id → content-space visible range
     (start, extent) evaluated during every layout sync. *)
  mutable vport : int -> (float * float) option;
  mutable anchor_shift : int -> float * float;
}

let no_measure _id _text _offered_w _offered_h = None

let create ~hooks ?layout ?(measure = no_measure) ~renderer ~width ~height ~scale () =
  let store = Lui_store.create () in
  let image_measure id = Option.map (fun image ->
    float_of_int image.iw,float_of_int image.ih) (hooks.Lui_paint.image_of id) in
  let layout =
    match layout with
    | None -> None
    | Some (module L : LAYOUT_ENGINE) ->
      let engine = L.create () in
      Some
        { lsync =
            (fun ~scale ~measure ~hidden ~ctx_anchor ~vport ~anchor_shift ~width ~height store ->
              L.sync ~scale ~measure ~text_flow:hooks.text_flow ~image_measure ~hidden ?ctx_anchor ~vport ~anchor_shift ~width ~height
                engine store);
          linvalidate = (fun () -> L.invalidate engine);
          lhook = L.layout_hook engine;
          lrect = L.rect engine;
          llists = (fun () -> L.vlists engine);
          lrange = (fun id -> L.mounted_range engine id);
          lchildren = (fun id -> L.mounted_children engine id);
          lextent = (fun id -> L.virtual_extent engine id);
          litem = (fun id ~index -> L.virtual_item_rect engine id ~index);
          lkey = (fun id key -> L.virtual_index_of_key engine store id key);
          lid = (fun id cid -> L.virtual_index_of_id engine store id cid);
          lview = (fun id -> L.virtual_view engine id);
          ldrift = (fun id -> L.virtual_take_drift engine id);
          lchanges = (fun () -> L.take_rect_changes engine) }
  in
  let mask_atlas = Atlas.create ~bpp:1 ~w:512 ~h:512 in
  let color_atlas = Atlas.create ~bpp:4 ~w:512 ~h:512 in
  { store;
    scene = Lui_scene.create ~mask_atlas ~color_atlas;
    hooks; layout; measure; renderer; width; height; scale;
    dirty = false; animation_time = None; reduced_motion = false;
    transitions = Hashtbl.create 4; retained = Lui_retained.create ();
    paint_hints = Hashtbl.create 16;
    moved_hints = Hashtbl.create 16;
    hidden = (fun _ -> false);
    ctx_anchor = (fun () -> None); inv_count = 0;
    vport = (fun _ -> None); anchor_shift = (fun _ -> (0.,0.)) }

let store h = h.store
let scene h = h.scene
let wants_repaint h = h.dirty || Hashtbl.length h.transitions > 0
  || Lui_retained.animating h.retained

let set_hidden h pred =
  h.hidden <- (match pred with Some p -> p | None -> fun _ -> false);
  h.inv_count <- h.inv_count + 1;
  Lui_retained.invalidate h.retained;
  h.dirty <- true

let set_ctx_anchor h accessor =
  h.ctx_anchor <-
    (match accessor with Some f -> f | None -> fun () -> None);
  h.inv_count <- h.inv_count + 1

(* Install the virtual-list viewport feed: [f id] reports the node's
   content-space visible range (start, extent, device px) — scroll
   offset for a directly-scrolled list, the mapped clip for one nested
   in an outer scroller. Evaluated inside every layout sync. *)
let set_vport h f = h.vport <- f
let set_anchor_shift h read =
  h.anchor_shift <- read;
  h.inv_count <- h.inv_count + 1;
  h.dirty <- true


(* Virtual-list queries the driver needs for hit-test slicing, scroll
   caps and scroll-to-item: all forward to the layout engine and
   answer [[]]/[None] when no engine is installed. *)
let layout_vlists h =
  match h.layout with Some l -> l.llists () | None -> []

let layout_mounted_range h id =
  match h.layout with Some l -> l.lrange id | None -> None

let layout_mounted_children h id =
  match h.layout with Some l -> l.lchildren id | None -> None

let layout_virtual_extent h id =
  match h.layout with Some l -> l.lextent id | None -> None

let layout_virtual_item h id ~index =
  match h.layout with Some l -> l.litem id ~index | None -> None

let layout_virtual_index_of_key h id key =
  match h.layout with Some l -> l.lkey id key | None -> None

let layout_virtual_index_of_id h id cid =
  match h.layout with Some l -> l.lid id cid | None -> None

let layout_virtual_view h id =
  match h.layout with Some l -> l.lview id | None -> None

(* Consume-on-read scroll correction from virtual-list measurement
   drift — the driver adds it to the list's scroll offset. *)
let layout_take_drift h id =
  match h.layout with Some l -> l.ldrift id | None -> 0.

(* The layout engine memoizes on (store revision, frame, input
   identities); a measure/hidden closure whose answers changed under a
   stable identity — e.g. a font stack that finished loading — needs
   this poke to be seen. *)
let invalidate_layout h =
  h.inv_count <- h.inv_count + 1;
  match h.layout with Some l -> l.linvalidate () | None -> ()

let invalidation_count h = h.inv_count

(* Host-side paint inputs the store cannot see (interaction state,
     images that finished decoding): the next repaint re-derives these
     fragments instead of replaying stale ops. *)
let note_paint h id = Hashtbl.replace h.paint_hints id ()

let note_paints h ids = List.iter (note_paint h) ids

(* Geometry-only change — a scroll offset that shifted a subtree.
     Marks like a moved rect: the fragment pass may reuse ops under a
     uniform translation instead of re-planning. *)
let note_moved h id = Hashtbl.replace h.moved_hints id ()

let note_moveds h ids = List.iter (note_moved h) ids

(* The retained fragment cache — tests invalidate it wholesale when
   their hooks change under a stable store (e.g. a theme swap). *)
let invalidate_paint h = Lui_retained.invalidate h.retained

let eased easing progress =
  if easing = "linear" then progress
  else begin
    let x1,y1,x2,y2 = match easing with
      | "standard" -> 0.42,0.,0.58,1.
      | "emphasized" -> 0.2,0.,0.,1.
      | "spring" -> 0.16,1.2,0.3,1.
      | _ -> invalid_arg "Unknown split easing" in
    let coordinate a b t =
      let inv = 1. -. t in
      3. *. inv *. inv *. t *. a +. 3. *. inv *. t *. t *. b +. t *. t *. t in
    let low = ref 0. and high = ref 1. in
    for _ = 1 to 16 do
      let middle = (!low +. !high) /. 2. in
      if coordinate x1 x2 middle < progress then low := middle else high := middle
    done;
    coordinate y1 y2 ((!low +. !high) /. 2.)
  end

let set_transition_value h id property value =
  Lui_store.apply_op h.store (Lui_protocol.SetProp
    (id,property,Lui_protocol.FloatValue value));
  h.dirty <- true

let tick h ~now =
  if not (Float.is_finite now) then invalid_arg "Invalid native animation time";
  (match h.animation_time with
   | Some previous when now < previous -> invalid_arg "Native animation clock moved backwards"
   | _ -> ());
  h.animation_time <- Some now;
  if Lui_retained.tick h.retained ~now then h.dirty <- true;
  if Hashtbl.length h.transitions > 0 then
    Hashtbl.filter_map_inplace (fun id motion ->
      if not (Lui_store.mem h.store id) then None
      else begin
        let progress = min 1. ((now -. motion.started) /. motion.duration) in
        let value = if progress >= 1. then motion.target
          else motion.from_value +.
            (motion.target -. motion.from_value) *. eased motion.easing progress in
        let value = if motion.property = Lui_protocol.ProgressValue
          then max 0. (min 1. value) else max 0. value in
        set_transition_value h id motion.property value;
        if progress >= 1. then None else Some motion
      end) h.transitions

let set_reduced_motion h enabled =
  if h.reduced_motion <> enabled then h.dirty <- true;
  Lui_retained.set_reduced_motion h.retained enabled;
  h.reduced_motion <- enabled;
  if enabled && Hashtbl.length h.transitions > 0 then begin
    Hashtbl.iter (fun id motion ->
      if Lui_store.mem h.store id then set_transition_value h id motion.property motion.target) h.transitions;
    Hashtbl.clear h.transitions
  end

let apply_batch ?(animate_resize=true) h (batch : Lui_protocol.patch_batch) =
  let previous = Hashtbl.create 4 and created = Hashtbl.create 4 in
  List.iter (function
    | Lui_protocol.CreateNode (id,_) | CreateExtension (id,_,_)
    | DropNode id | DetachSubtree id ->
        Hashtbl.replace created id ();
        Hashtbl.remove previous id;
        Hashtbl.remove h.transitions id
    | RemoveProp (id, (ProgressValue | FirstPaneWidth)) ->
        Hashtbl.remove previous id;
        Hashtbl.remove h.transitions id
    | SetProp (id, ((ProgressValue | FirstPaneWidth) as property), _) when not (Hashtbl.mem created id)
        && Lui_store.kind h.store id = "split" ->
        if not animate_resize then Hashtbl.remove h.transitions id;
        if not (Hashtbl.mem previous id) then
          (match Lui_store.float_prop h.store id (Lui_wire_schema.property_name property) with
           | Some value -> Hashtbl.add previous id (property, value)
           | None -> ())
    | _ -> ()) batch.ops;
  Lui_store.apply_batch h.store batch;
  Hashtbl.filter_map_inplace (fun id motion ->
    if Lui_store.mem h.store id then Some motion else None) h.transitions;
  Hashtbl.iter (fun id (property, from_value) ->
    match h.animation_time, Lui_store.prop h.store id (Lui_wire_schema.property_name property) with
    | Some started, Some (Lui_protocol.FloatValue target)
        when animate_resize && not h.reduced_motion && from_value <> target ->
        let duration = Option.value ~default:0 (Lui_store.int_prop h.store id "resize-duration") in
        if duration > 0 then begin
          let easing = Option.value ~default:"standard"
            (Lui_store.string_prop h.store id "resize-easing") in
          (match Hashtbl.find_opt h.transitions id with
           | Some motion when motion.property = property && motion.target = target -> ()
           | _ -> Hashtbl.replace h.transitions id
               {property;from_value;target;started;duration=float duration /. 1000.;easing});
          set_transition_value h id property from_value
        end else Hashtbl.remove h.transitions id
    | _ -> Hashtbl.remove h.transitions id) previous;
  h.dirty <- true;
  true

let resize h ~width ~height ~scale =
  h.width <- width;
  h.height <- height;
  h.scale <- scale;
  h.inv_count <- h.inv_count + 1;
  h.dirty <- true

let prof_t0 = Sys.time ()
let prof msg =
  if Sys.getenv_opt "LUI_HOST_PROF" <> None then
    Printf.eprintf "[host +%.3f] %s\n%!" (Sys.time () -. prof_t0) msg

(* Paint the current tree and render; returns pixel bytes. *)
let repaint h =
  prof "repaint begin";
  let hooks, moved =
    match h.layout with
    | None -> (h.hooks, None)
    | Some l ->
      (* Rebuilt every repaint, never per batch: the engine must see
         the store as it is NOW (several batches may land between
         paints) and the current frame size — layout is the single
         place that resolves both. *)
      l.lsync ~scale:h.scale ~measure:h.measure ~hidden:h.hidden
        ~ctx_anchor:(h.ctx_anchor ()) ~vport:h.vport ~anchor_shift:h.anchor_shift
        ~width:(float_of_int h.width) ~height:(float_of_int h.height)
        h.store;
      (* The engine hook yields to an explicitly supplied
         hooks.layout; the zero-rect default does. *)
      let hooks =
        if h.hooks.layout == Lui_paint.default_hooks.layout
        then { h.hooks with layout = l.lhook }
        else h.hooks
      in
      let mv = l.lchanges () in
      Hashtbl.iter
        (fun id () -> Hashtbl.replace mv id ())
        h.moved_hints;
      (hooks, Some mv)
  in
  let hooks = { hooks with Lui_paint.hidden = h.hidden } in
  prof "layout done";
  (* The window clear follows the app theme's "background" token —
     what the web paints on <body>. Regions the tree does not cover
     must not flash the raw framebuffer. *)
  let clear =
    match hooks.color_of "background" with
    | Some c -> c
    | None -> { r = 0; g = 0; b = 0; a = 0 }
  in
  let vlists =
    match h.layout with Some l -> Some (l.llists ()) | None -> None
  in
  Lui_retained.paint_retained h.retained hooks h.store h.scene ?moved
    ?vlists
    ~hints:h.paint_hints ~width:h.width ~height:h.height ~scale:h.scale
    ~clear ();
  Hashtbl.reset h.paint_hints;
  Hashtbl.reset h.moved_hints;
  prof "paint done";
  h.dirty <- false;
  let bytes = h.renderer.render h.scene in
  prof "render done";
  bytes

let layout_rect h id =
  match h.layout with
  | Some l -> l.lrect id
  | None -> None

(* The backend record Lui_app.create consumes. *)
let backend h (profile : Lui_protocol.platform_profile) : Lui_protocol.backend =
  { backend_profile = profile; apply_batch = apply_batch h }
