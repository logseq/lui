(* ns todos.flutter-bridge *)

val send_patch_bang : string -> bool

val operating_system : int -> operating_system

val app : unit -> (todo_model, todo_action) reducer_app

val initialize : int -> int -> string

val appear : int -> string

val press : int -> string

val text_changed : int -> string -> string

val toggle_changed : int -> bool -> string

val radio_changed : int -> string

val slider_changed : int -> float -> string

val dispose : unit -> string

val root_node : unit -> int

