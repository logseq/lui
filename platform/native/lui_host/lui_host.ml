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
    ?scale:float -> ?measure:text_measure -> ?hidden:(int -> bool) ->
    ?ctx_anchor:(float * float) ->
    width:float -> height:float -> t -> Lui_store.t -> unit

  val invalidate : t -> unit

  val layout_hook : t -> int -> Lui_paint.placement

  val rect : t -> int -> Lui_scene.rect option
end

(* An instantiated engine: what (module LAYOUT_ENGINE) becomes once the
   host has built the engine state at create. *)
type layout_state = {
  lsync :
    scale:float -> measure:text_measure -> hidden:(int -> bool) ->
    ctx_anchor:(float * float) option ->
    width:float -> height:float -> Lui_store.t -> unit;
  linvalidate : unit -> unit;
  lhook : int -> Lui_paint.placement;
  lrect : int -> rect option;
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
  mutable hidden : int -> bool; (* host-owned transient visibility *)
  (* Pointer point an unanchored context-menu opens at — a thunk so the
     accessor reads the live position each repaint. *)
  mutable ctx_anchor : unit -> (float * float) option;
  (* Spatial index provider for the paint pass's viewport cull —
     returns [Some index] only when the caller can prove it matches
     the geometry this repaint resolves (see [Lui_spatial]); [None]
     is always safe: the walk just visits every node. *)
  mutable spatial : unit -> Lui_spatial.t option;
  (* Bumped by every host-side poke that can change layout output
     without a store revision — [invalidate_layout], [resize],
     [set_hidden], [set_ctx_anchor]. Epoch keys mixing it in stay
     honest across external measure/visibility changes. *)
  mutable inv_count : int;
}

let no_measure _id _text _offered_w _offered_h = None

let create ~hooks ?layout ?(measure = no_measure) ~renderer ~width ~height ~scale () =
  let layout =
    match layout with
    | None -> None
    | Some (module L : LAYOUT_ENGINE) ->
      let engine = L.create () in
      Some
        { lsync =
            (fun ~scale ~measure ~hidden ~ctx_anchor ~width ~height store ->
              L.sync ~scale ~measure ~hidden ?ctx_anchor ~width ~height
                engine store);
          linvalidate = (fun () -> L.invalidate engine);
          lhook = L.layout_hook engine;
          lrect = L.rect engine }
  in
  let mask_atlas = Atlas.create ~bpp:1 ~w:512 ~h:512 in
  let color_atlas = Atlas.create ~bpp:4 ~w:512 ~h:512 in
  { store = Lui_store.create ();
    scene = Lui_scene.create ~mask_atlas ~color_atlas;
    hooks; layout; measure; renderer; width; height; scale;
    dirty = false; hidden = (fun _ -> false);
    ctx_anchor = (fun () -> None); spatial = (fun () -> None);
    inv_count = 0 }

let store h = h.store
let scene h = h.scene
let wants_repaint h = h.dirty

let set_hidden h pred =
  h.hidden <- (match pred with Some p -> p | None -> fun _ -> false);
  h.inv_count <- h.inv_count + 1;
  h.dirty <- true

let set_ctx_anchor h accessor =
  h.ctx_anchor <-
    (match accessor with Some f -> f | None -> fun () -> None);
  h.inv_count <- h.inv_count + 1

(* The layout engine memoizes on (store revision, frame, input
   identities); a measure/hidden closure whose answers changed under a
   stable identity — e.g. a font stack that finished loading — needs
   this poke to be seen. *)
let invalidate_layout h =
  h.inv_count <- h.inv_count + 1;
  match h.layout with Some l -> l.linvalidate () | None -> ()

let invalidation_count h = h.inv_count

(* Install the spatial-index provider the paint pass consults; the
   thunk runs inside [repaint] after layout sync, so it sees the
   frame's final geometry inputs. *)
let set_spatial h f = h.spatial <- f

let apply_batch h (batch : Lui_protocol.patch_batch) =
  Lui_store.apply_batch h.store batch;
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
  let hooks =
    match h.layout with
    | None -> h.hooks
    | Some l ->
      (* Rebuilt every repaint, never per batch: the engine must see
         the store as it is NOW (several batches may land between
         paints) and the current frame size — layout is the single
         place that resolves both. *)
      l.lsync ~scale:h.scale ~measure:h.measure ~hidden:h.hidden
        ~ctx_anchor:(h.ctx_anchor ())
        ~width:(float_of_int h.width) ~height:(float_of_int h.height)
        h.store;
      (* The engine hook yields to an explicitly supplied
         hooks.layout; the zero-rect default does. *)
      if h.hooks.layout == Lui_paint.default_hooks.layout
      then { h.hooks with layout = l.lhook }
      else h.hooks
  in
  prof "layout done";
  (* The window clear follows the app theme's "background" token —
     what the web paints on <body>. Regions the tree does not cover
     must not flash the raw framebuffer. *)
  let clear =
    match hooks.color_of "background" with
    | Some c -> c
    | None -> { r = 0; g = 0; b = 0; a = 0 }
  in
  Lui_paint.paint ?spatial:(h.spatial ()) hooks h.store h.scene
    ~width:h.width ~height:h.height ~scale:h.scale ~clear;
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
