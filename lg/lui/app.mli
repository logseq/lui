(* ns lui.app *)

type app_lifecycle =
  | Running
  | Disposing
  | Disposed

type ('model, 'action) reloadable_view_state = { reload_model_source : 'model signal ; reload_view_scope : scope ref ; reload_state_scope : scope ; reload_state_scopes : (string, scope) Lg_runtime.Runtime_map.t ref ; reload_view_node : int ref ; reload_session : (ui_context -> 'model signal -> ('action -> bool) -> int) hot_reload_session }

type ('model, 'action) reducer_app = { app_scheduler : scheduler ; app_runtime : application ; app_scope : scope ; app_read_model : unit -> 'model ; app_send_action : 'action -> bool ; app_root_node : int ; app_lifecycle_state : app_lifecycle ref ; app_reload_state : ('model, 'action) reloadable_view_state option }

val reduce_bang : 'model state -> ('model -> 'action -> 'model) -> 'action -> bool

val restore_state_scopes_bang : (string, scope) Lg_runtime.Runtime_map.t ref -> (string, scope) Lg_runtime.Runtime_map.t -> bool

val prune_state_scopes_bang : (string, scope) Lg_runtime.Runtime_map.t ref -> (string, bool) Lg_runtime.Runtime_map.t -> bool

val start_bang : ('model, 'action) reducer_app -> bool

val flush_bang : ('model, 'action) reducer_app -> bool

val dispose_bang : ('model, 'action) reducer_app -> bool

val disposed_ : ('model, 'action) reducer_app -> bool

val root_node : ('model, 'action) reducer_app -> int

val runtime : ('model, 'action) reducer_app -> application

val dispatch_event_bang : ('model, 'action) reducer_app -> event -> bool

val request_reload_bang : ('model, 'action) reducer_app -> int

val reload_view_bang : ('model, 'action) reducer_app -> int -> string -> string -> (ui_context -> 'model signal -> ('action -> bool) -> int) -> int -> reload_status

