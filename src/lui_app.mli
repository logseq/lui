(** Application lifecycle: wires a [Lui_protocol.backend], a reducer over
    your model, and a [view] function into a running application.
    [create backend model reducer view] builds the app, [send] dispatches
    actions through the reducer, [flush] emits pending patch batches, and
    [dispose] tears down signal scopes and the runtime. *)

type lifecycle_state = Running | Disposing | Disposed
type ('model, 'action) reloadable_view_state = {
  reload_model_source : 'model Signal.signal;
  reload_view_scope : Signal.scope ref;
  reload_state_scope : Signal.scope;
  reload_state_scopes : (string, Signal.scope) Hashtbl.t;
  reload_view_node : int ref;
  reload_session :
    (Lui_ui.ui_context -> 'model Signal.signal -> ('action -> bool) ->
     Lui_elements.t)
    Lui_hot_reload.hot_reload_session;
}
type ('model, 'action) reducer_app = {
  app_scheduler : Signal.scheduler;
  app_runtime : Lui_runtime.application;
  app_scope : Signal.scope;
  app_read_model : unit -> 'model;
  app_send_action : 'action -> bool;
  app_root_node : int;
  app_lifecycle_state : lifecycle_state ref;
  app_reload_state : ('model, 'action) reloadable_view_state option;
}
val reduce : 'a Signal.state -> ('a -> 'b -> 'a) -> 'b -> unit
val restore_state_scopes :
  ('a, Signal.scope) Hashtbl.t -> ('a, Signal.scope) Hashtbl.t -> bool
val prune_state_scopes :
  ('a, Signal.scope) Hashtbl.t -> ('a, 'b) Hashtbl.t -> bool
val create_with_extensions :
  Lui_protocol.backend ->
  Lui_extension.extension_registry ->
  'a ->
  ('a -> 'b -> 'a) ->
  (Lui_ui.ui_context -> 'a Signal.signal -> ('b -> bool) -> Lui_elements.t) ->
  ('a, 'b) reducer_app
val create :
  Lui_protocol.backend ->
  'a ->
  ('a -> 'b -> 'a) ->
  (Lui_ui.ui_context -> 'a Signal.signal -> ('b -> bool) -> Lui_elements.t) ->
  ('a, 'b) reducer_app
val create_reloadable_with_extensions :
  Lui_protocol.backend ->
  Lui_extension.extension_registry ->
  string ->
  string ->
  'a ->
  ('a -> 'b -> 'a) ->
  (Lui_ui.ui_context -> 'a Signal.signal -> ('b -> bool) -> Lui_elements.t) ->
  ('a, 'b) reducer_app
val create_reloadable :
  Lui_protocol.backend ->
  string ->
  string ->
  'a ->
  ('a -> 'b -> 'a) ->
  (Lui_ui.ui_context -> 'a Signal.signal -> ('b -> bool) -> Lui_elements.t) ->
  ('a, 'b) reducer_app
val start : ('a, 'b) reducer_app -> bool
val flush : ('a, 'b) reducer_app -> bool
val dispose : ('a, 'b) reducer_app -> bool
val disposed : ('a, 'b) reducer_app -> bool
val model : ('a, 'b) reducer_app -> 'a
val root_node : ('a, 'b) reducer_app -> int
val runtime : ('a, 'b) reducer_app -> Lui_runtime.application
val send : ('a, 'b) reducer_app -> 'b -> bool
val dispatch_event : ('a, 'b) reducer_app -> Lui_protocol.event -> bool
val require_reload_state :
  ('a, 'b) reducer_app -> ('a, 'b) reloadable_view_state
val request_reload : ('a, 'b) reducer_app -> int
val reject_view :
  ('a, 'b) reloadable_view_state ->
  int ->
  string ->
  string ->
  (Lui_ui.ui_context -> 'a Signal.signal -> ('b -> bool) -> Lui_elements.t) ->
  string -> int -> Lui_hot_reload.reload_status
val reload_view :
  ('a, 'b) reducer_app ->
  int ->
  string ->
  string ->
  (Lui_ui.ui_context -> 'a Signal.signal -> ('b -> bool) -> Lui_elements.t) ->
  int -> Lui_hot_reload.reload_status
