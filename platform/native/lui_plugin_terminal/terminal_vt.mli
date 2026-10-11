(* Byte-driven VT parser that applies sequences to a Terminal_grid. *)

module G = Terminal_grid

type t

val create : ?max_scrollback:int -> cols:int -> rows:int -> unit -> t

val grid : t -> G.t

(* Outward actions a host may need; [Reply] payloads are written back
   to the pty. *)
type action =
  | Title of int * string          (* OSC 0 icon+title / 1 icon / 2 title *)
  | Pwd of string                  (* OSC 7 *)
  | Bell
  | Clipboard of string            (* OSC 52 payload *)
  | Reply of string
  | Palette_set of int * Lui_scene.color   (* OSC 4 *)
  | Ink_set of Lui_scene.color             (* OSC 10 *)
  | Paper_set of Lui_scene.color           (* OSC 11 *)
  | Cursor_ink_set of Lui_scene.color      (* OSC 12 *)

val feed : t -> string -> int -> int -> action list
(** [feed t s off len] consumes bytes; returns actions raised. *)

val feed_string : t -> string -> action list

val link_uri : t -> int -> string
(** [link_uri t id] resolves a cell's link id to its URI ("" when none). *)

val cur_link : t -> int
