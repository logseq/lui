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

type t = {
  store : Lui_store.t;
  scene : Lui_scene.t;
  hooks : Lui_paint.hooks;
  renderer : renderer;
  mutable width : int;
  mutable height : int;
  mutable scale : float;
  mutable dirty : bool; (* repaint requested since last present *)
}

let create ~hooks ~renderer ~width ~height ~scale () =
  let mask_atlas = Atlas.create ~bpp:1 ~w:512 ~h:512 in
  let color_atlas = Atlas.create ~bpp:4 ~w:512 ~h:512 in
  { store = Lui_store.create ();
    scene = Lui_scene.create ~mask_atlas ~color_atlas;
    hooks; renderer; width; height; scale; dirty = false }

let store h = h.store
let scene h = h.scene
let wants_repaint h = h.dirty

let apply_batch h (batch : Lui_protocol.patch_batch) =
  Lui_store.apply_batch h.store batch;
  h.dirty <- true;
  true

let resize h ~width ~height ~scale =
  h.width <- width; h.height <- height; h.scale <- scale; h.dirty <- true

(* Paint the current tree and render; returns pixel bytes. *)
let repaint h =
  Lui_paint.paint h.hooks h.store h.scene ~width:h.width ~height:h.height
    ~scale:h.scale ~clear:{ r = 0; g = 0; b = 0; a = 0 };
  h.dirty <- false;
  h.renderer.render h.scene

(* The backend record Lui_app.create consumes. *)
let backend h (profile : Lui_protocol.platform_profile) : Lui_protocol.backend =
  { backend_profile = profile; apply_batch = apply_batch h }
