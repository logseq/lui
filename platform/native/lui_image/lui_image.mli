(* Image decoding and color-atlas management for the native backend.

   Decoded pixels are stored as premultiplied RGBA8 (channel order
   R,G,B,A, four bytes per pixel, rows tightly packed) — the same pixel
   convention the scene IR and the renderers use, so images can be
   sampled or composited without further conversion.

   Everything here is headless: no GL, no window system. *)

open Bigarray

(* Formats the decoder can identify. [Jpeg] is detected but not decoded:
   the bundled pure-OCaml decoder only reports JPEG dimensions. *)
type format = Png | Gif | Bmp | Pnm | Jpeg

(* Decoded image. Pixels are premultiplied RGBA8. *)
type image

val width : image -> int
val height : image -> int

(* Byte size of the decoded pixel buffer (4 * width * height). *)
val size_bytes : image -> int

(* The encoded format the image was decoded from. *)
val format : image -> format

(* Premultiplied RGBA8 pixels, [4 * width] bytes per row. Shares the
   image's internal storage — callers must not mutate it. *)
val pixels : image -> (int, int8_unsigned_elt, c_layout) Array1.t

(* Same pixels as a [Bytes.t] — a fresh copy, safe to hand to
   [Lui_scene.Atlas.put] or [Lui_scene.new_image]. *)
val pixels_bytes : image -> Bytes.t

(* Bridge to the scene IR's standalone image record used by [Image] ops. *)
val to_scene_image : image -> Lui_scene.image

(* ------------------------------------------------------------------ *)
(* Decoding                                                            *)

(* Identify the encoded format from magic bytes, if recognized. *)
val sniff : bytes -> format option

(* Decode [bytes] into a premultiplied RGBA8 image.
   PNG, GIF (first frame), BMP and PNM are decoded; JPEG returns an
   unsupported-format error. Errors are returned, never raised. *)
val decode : bytes -> (image, string) result

(* ------------------------------------------------------------------ *)
(* Object-fit sizing                                                   *)

type fit =
  | Contain  (* scale to fit inside, preserve aspect ratio *)
  | Cover    (* scale to cover, preserve aspect ratio *)
  | Fill     (* stretch to the target exactly *)
  | Natural  (* unscaled ("none") *)

(* [fit_rect f ~iw ~ih ~x ~y ~w ~h] returns [(x, y, w, h)] — the image
   rect of kind [f] for an [iw]x[ih] source centered in target
   [x,y,w,h]. All math is integer: scaled sizes round half-up, and the
   centering offset truncates toward zero, so odd slack lands on the
   right/bottom. Degenerate inputs (non-positive source or target)
   return an empty rect [(x, y, 0, 0)]. *)
val fit_rect :
  fit -> iw:int -> ih:int -> x:int -> y:int -> w:int -> h:int ->
  int * int * int * int

(* ------------------------------------------------------------------ *)
(* Color-atlas upload                                                  *)

(* A region of a color atlas ([bpp = 4]) holding one uploaded image.
   [gen] is the atlas generation at upload time; a renderer holding
   this entry must re-acquire it once the atlas generation moves on. *)
type entry = {
  ex : int;
  ey : int;
  ew : int;
  eh : int;
  egen : int;
  etransient : bool;
}

(* Allocate a region in a color [atlas] and write the image's
   premultiplied pixels into it. [~transient:true] (default) allocates
   from the atlas's transient space, reclaimed by
   [Lui_scene.Atlas.reset_transient]; [~transient:false] allocates a
   lasting region. Grows the atlas on demand; fails only when the
   region cannot fit even at the atlas's maximum size. *)
val upload :
  ?transient:bool -> Lui_scene.Atlas.t -> image -> (entry, string) result

(* ------------------------------------------------------------------ *)
(* Cache                                                               *)

(* Decoded-image cache keyed by content digest, with memoized atlas
   uploads. Bounded by decoded pixel bytes; least-recently-used entries
   are evicted on insertion. Transient atlas bookkeeping is dropped on
   [begin_frame] — call it whenever the renderer resets the atlas's
   transient space (entries are re-uploaded lazily on next use). *)
module Cache : sig
  type t

  (* [max_bytes] counts decoded pixels (4*w*h each). Default 64 MiB. *)
  val create : ?max_bytes:int -> unit -> t

  (* Memoized decode: hits return the same [image] value. *)
  val decode : t -> bytes -> (image, string) result

  (* Whether [bytes] is currently cached (does not decode). *)
  val mem : t -> bytes -> bool

  (* Memoized decode + memoized atlas upload: repeated calls for the
     same bytes and atlas return the same region without re-writing
     pixels. A cached transient entry is re-uploaded after
     [begin_frame]; any entry is re-uploaded after the atlas generation
     changes (grow / repack / reset). *)
  val atlas_entry :
    ?transient:bool -> t -> Lui_scene.Atlas.t -> bytes ->
    (entry, string) result

  (* Invalidate every transient entry (pairs with
     [Lui_scene.Atlas.reset_transient]). Lasting entries survive. *)
  val begin_frame : t -> unit

  (* Drop all entries. *)
  val clear : t -> unit

  val length : t -> int      (* live cached images *)
  val bytes_used : t -> int  (* decoded pixel bytes held *)
end
