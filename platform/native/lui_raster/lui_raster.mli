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

(* A window presenter retains copied bands; the renderer retains only staging
   pixels. Shader effects require the whole-image Renderer above. *)
module Tile_renderer : sig
  type t
  val band_height : int
  val create : unit -> t
  val invalidate : t -> unit
  val release : t -> unit
  (* Number of resident producer domains, including parked producers. *)
  val background_domains : t -> int
  (* [workers] is between one and eight, including the caller's rendering
     work. Each worker owns one staging band;
     [emit] runs on the caller's domain and must consume or copy its borrowed
     pixels before returning. The first row corresponds to the rectangle's
     [y0]. Failed uploads invalidate damage and join every worker before
     propagating the exception. *)
  val render : ?workers:int -> t -> Lui_scene.t -> emit:(Lui_scene.irect -> Image.t -> unit) -> unit
end
