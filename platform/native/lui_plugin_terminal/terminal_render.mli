(* Grid -> Lui_scene ops. Pluggable text engine; never reimplements
   shaping. *)

module A = Terminal_attrs
module G = Terminal_grid

type sg = { sid : int; sx : float; sy : float; sadv : float }
type 'f srun = { sfont : 'f; sgs : sg array }
type sbm = { bleft : int; btop : int; bw : int; bh : int;
             bcolor : bool; bpixels : bytes }

type 'f engine = {
  create : ?families:string list -> ?weight:int -> ?italic:bool ->
    size:float -> unit -> 'f;
  metrics : 'f -> float * float * float * float;
  shape : 'f -> string -> 'f srun array;
  rasterize : ?scale:float -> ?dx:float -> ?shade:float -> 'f -> int ->
    sbm option;
  subpixel : ?scale:float -> 'f -> int;
  baseline : float -> float;
  is_color : 'f -> bool;
}

val engine_of_lui_text : Lui_text.font engine

type 'f t

val create : 'f engine -> ?families:string list -> ?weight:int ->
  size:float -> scale:float -> theme:A.theme -> unit -> 'f t

val cell_w : 'f t -> int
val cell_h : 'f t -> int
val font_size : 'f t -> float
val set_theme : 'f t -> A.theme -> unit
val set_scale : 'f t -> float -> unit
val set_hover_link : 'f t -> int -> unit
val hover_link : 'f t -> int

val render : ?blink_on:bool -> 'f t -> G.t -> Lui_scene.t ->
  w:int -> h:int -> unit
(** Appends the terminal's ops (backgrounds, glyph runs, decorations,
    selection, cursor, scrollbar) to [scene]. *)
