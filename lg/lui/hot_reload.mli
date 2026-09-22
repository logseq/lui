(* ns lui.hot-reload *)

type reload_status =
  | ReloadApplied of int
  | ReloadUnchanged of int
  | ReloadRejected of int * string
  | ReloadStale of int
  | ReloadRestartRequired of int * string

type reload_event = { reload_event_generation : int ; reload_event_source_hash : string ; reload_event_status : reload_status ; reload_event_elapsed_ms : int }

type 'root committed_root = { committed_root_value : 'root ; committed_root_source_hash : string ; committed_root_generation : int }

type 'root hot_reload_session = { hot_reload_committed_root : 'root committed_root ref ; hot_reload_contract_hash : string ; hot_reload_requested_generation : int ref ; hot_reload_completed_generation : int ref ; hot_reload_events : reload_event Rrbvec.t ref }

val create : string -> string -> 'root -> 'root hot_reload_session

val request_bang : 'root hot_reload_session -> int

val preflight : 'root hot_reload_session -> int -> string -> string -> reload_status option

val publish_bang : 'root hot_reload_session -> int -> string -> string -> 'root -> ('root -> string option) -> int -> reload_status

val current_root : 'root hot_reload_session -> 'root

val generation : 'root hot_reload_session -> int

val source_hash : 'root hot_reload_session -> string

val events : 'root hot_reload_session -> reload_event Rrbvec.t

val latest_event : 'root hot_reload_session -> reload_event option

