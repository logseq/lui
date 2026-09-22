(* ns components.flutter-bridge *)

val send_patch_bang : string -> bool

val operating_system : int -> operating_system

val host_kind : int -> host_kind

val app : unit -> (gallery_model, gallery_action) reducer_app

val initialize : int -> int -> string

val appear : int -> string

val press : int -> string

val long_press : int -> string

val text_changed : int -> string -> string

val toggle_changed : int -> bool -> string

val radio_changed : int -> string

val slider_changed : int -> float -> string

val dispose : unit -> string

val root_node : unit -> int

