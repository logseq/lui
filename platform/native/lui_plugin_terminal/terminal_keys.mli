(* Input events to pty bytes: keys, committed text, bracketed paste,
   focus reports and mouse reports. *)

val key_bytes : appcursor:bool -> Lui_window.Input.key ->
  Lui_window.Input.mods -> string option
(** [key_bytes ~appcursor k m] is the wire encoding of a key press, or
    [None] when the key produces no sequence (host should still route
    any resulting text input). *)

val text_bytes : ?alt:bool -> string -> string
(** Committed text; [~alt] prepends ESC. *)

val paste_bytes : bracketed:bool -> string -> string
(** Wraps the payload in the bracketed-paste markers when [bracketed]. *)

val focus_bytes : inside:bool -> string
(** Focus-in/out reports (mode 1004). *)

type mouse_ev =
  | Btn of int          (* press; 0 left, 1 middle, 2 right *)
  | Release             (* button release *)
  | Drag of int         (* motion with button [n] held *)
  | Wheel of int        (* 64 up, 65 down, 66 left, 67 right *)

val mouse_bytes : fmt:int -> x:int -> y:int ->
  Lui_window.Input.mods -> mouse_ev -> string option
(** [fmt] selects the encoding: 0 X10 bytes, 1 UTF-8 extended (same
    bytes here), 2 SGR 1006, 3 pixels (returns [None]: the caller does
    pixel scaling and re-encodes itself), 4 also SGR. *)
