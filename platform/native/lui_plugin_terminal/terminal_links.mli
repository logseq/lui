(* Regex link detection over row text: URLs, paths, file:line[:col]. *)

type kind = Url | Path | File_line of int * int (* line, col *)

type hit = { x0 : int; x1 : int; kind : kind; text : string }

val find_in_row : string -> hit list
(** Scan one row's text. *)

val find : Terminal_grid.t -> row:int -> hit list
(** Scan a viewport row (translates the scrollback viewport offset). *)

val at : Terminal_grid.t -> row:int -> col:int -> hit option
(** The hit under a viewport cell, if any. *)
