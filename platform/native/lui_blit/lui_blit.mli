(* SDL software present path for CPU-rendered frames.

   A blit target wraps an SDL renderer + one streaming texture covering
   the whole drawable.  [present] uploads a premultiplied BGRA frame
   (Lui_raster.Image layout) and swaps it on screen; [update_region]
   pushes only the damaged rows for incremental repaint.

   The window code creates this only when the GPU path is off, since a
   window without the OpenGL flag cannot serve a GL context anyway. *)

type t

val create : Tsdl.Sdl.window -> w:int -> h:int -> (t, string) result
(** Software renderer + streaming BGRA texture, [w]x[h] device pixels. *)

val resize : t -> w:int -> h:int -> (unit, string) result
(** Recreate the texture after a drawable resize. *)

val update : t -> pix:Bytes.t -> stride:int -> (unit, string) result
(** Upload the full frame.  [stride] is pixels per row of [pix]
    ([pix] length = stride*h*4). *)

val update_region :
  t -> x0:int -> y0:int -> x1:int -> y1:int -> pix:Bytes.t ->
  stride:int -> (unit, string) result
(** Upload one rectangle of the frame (damage path).  [x0,y0) to
    [x1,y1) is in texture pixels and clipped to the texture bounds;
    [pix] is the FULL frame — only the rect's rows are read. *)

val present : t -> unit
(** RenderCopy + RenderPresent. *)

val name : string
