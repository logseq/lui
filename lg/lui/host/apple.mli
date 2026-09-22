(* ns lui.host.apple *)

type apple_host = { apple_apply_json : string -> int ; apple_show_window : unit -> unit ; apple_reset_host : unit -> unit ; apple_perform_action : int -> int ; apple_event_callback : int -> (int -> (string -> unit)) }

val connect : string -> (event -> unit) -> apple_host

val apply_json_bang : apple_host -> string -> bool

val show_bang : apple_host -> unit

val reset_host_bang : apple_host -> unit

val perform_action_bang : apple_host -> int -> bool

