(* Terminal widget facade: VT parser + grid + renderer + PTY + input.
   Plain library API (no plugin registry exists yet): the host creates
   a [t], feeds child output through [feed]/[pump], paints via [view]
   and routes host input events through [handle_input]. *)

module Vt = Terminal_vt
module G = Terminal_grid
module A = Terminal_attrs
module P = Terminal_pty
module K = Terminal_keys
module L = Terminal_links
module R = Terminal_render

type t

val create : ?cols:int -> ?rows:int -> ?max_scrollback:int ->
  ?font_size:float -> ?scale:float -> ?theme:A.theme ->
  ?families:string list -> unit -> t

val grid : t -> G.t
val renderer : t -> Lui_text.font R.t

(* Output from the child (or any source) into the grid. *)
val feed : t -> string -> unit
val feed_bytes : t -> bytes -> int -> int -> unit

(* PTY service: spawn/write/read-events/resize/close. *)
val spawn : t -> argv:string array -> env:string array -> cwd:string ->
  unit
val close_pty : t -> unit
val pty_alive : t -> bool
val pty_poll : t -> int option
val pump : t -> Vt.action list
(** Per-frame: flush queued input, drain the pty, apply actions.
    Returns the actions raised by new output. *)

val write : t -> string -> unit
(** Queue bytes for the child; flushed by [pump] (or the host's own
    write loop). *)

val resize : t -> cols:int -> rows:int -> unit
val resize_pixels : t -> w:int -> h:int -> unit
val cols_for : t -> int -> int
val rows_for : t -> int -> int

val cell_w : t -> int
val cell_h : t -> int

val view : t -> ?blink_on:bool -> Lui_scene.t -> w:int -> h:int -> unit
(** Append the terminal's paint ops to the frame's scene. *)

val handle_input : t -> Lui_window.Input.t -> bool
(** Consume a host input event; [true] when it produced pty bytes or
    viewport changes. *)

val selection_text : t -> string
val clear_selection : t -> unit
val has_selection : t -> bool
val mouse_sel : t -> int -> int -> G.sel_kind -> unit
val sel_extend : t -> int -> int -> unit
val scroll_view : t -> int -> unit
val link_at : t -> row:int -> col:int -> L.hit option
val link_uri : t -> int -> string
val hover_link : t -> int -> unit

(** {1 The plugin service} *)

val plugin : Lui_plugin.t
(** The ["plugin:terminal"] service descriptor: methods ["spawn"],
    ["write"], ["read_events"], ["resize"] and ["close"], each taking
    a JSON object and returning a JSON object.  Terminals are keyed by
    the integer ["id"] that ["spawn"] returns.  Register with
    [Lui_plugin.use \[plugin\]]. *)
