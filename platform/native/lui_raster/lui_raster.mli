(* CPU renderer: evaluates a Lui_scene.t into a premultiplied BGRA
   pixel buffer. Coverage comes from the same signed-distance math the
   GPU evaluator's shaders use, so the two agree pixel-for-pixel. *)

module Image : sig
  type t = {
    mutable w : int;
    mutable h : int;
    mutable stride : int; (* bytes per row, 4*w *)
    mutable pix : Bytes.t; (* premultiplied BGRA *)
  }

  val create : w:int -> h:int -> t
  val resize : t -> w:int -> h:int -> unit
  val rgba : t -> Bytes.t (* the pixels as premultiplied RGBA *)
end

(* The rectangles of a scene that differ from the one before. *)
module Damage : sig
  type t

  val create : unit -> t
  val invalidate : t -> unit
  val update : t -> Lui_scene.t -> Lui_scene.irect list
  val whole : t -> bool (* update found the whole scene must redraw *)
  val rects : t -> Lui_scene.irect list
  val bounds : t -> Lui_scene.irect array (* where each op of the last scene drew *)
end

val render : ?workers:int -> scene:Lui_scene.t -> unit -> Image.t
val render_into :
  ?workers:int ->
  image:Image.t ->
  scene:Lui_scene.t ->
  ?area:Lui_scene.irect ->
  ?bounds:Lui_scene.irect array ->
  unit ->
  unit

(* A renderer that draws successive scenes into one image, redrawing
   only where a scene differs from the one before. *)
module Renderer : sig
  type t

  val create : unit -> t
  val render : ?workers:int -> t -> Lui_scene.t -> Lui_scene.irect list
  val image : t -> Image.t
  val whole : t -> bool
  val invalidate : t -> unit
  val release : t -> unit
end
