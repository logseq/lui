(* Shared-model multi-window application: one scheduler + one model
   state + one shared payload, with a runtime/scope/context triple per
   window surface. See the .mli for the semantics. *)

type lifecycle_state =
  | Running
  | Disposing
  | Disposed

type ('model, 'action, 'shared) t = {
  app_scheduler : Signal.scheduler;
  app_registry : Lui_extension.extension_registry;
  app_model : 'model Signal.state;
  app_reducer : 'model -> 'action -> 'model;
  app_view : ('model, 'action, 'shared) view;
  app_shared : 'shared;
  app_scope : Signal.scope;
  app_lifecycle : lifecycle_state ref;
  app_surfaces : (int, ('model, 'action, 'shared) surface) Hashtbl.t;
  mutable app_order : ('model, 'action, 'shared) surface list;
  app_next_surface : int ref;
}

and ('model, 'action, 'shared) view =
  ('model, 'action, 'shared) surface ->
  Lui_ui.ui_context ->
  'model Signal.signal ->
  ('action -> bool) ->
  Lui_elements.t

and ('model, 'action, 'shared) surface = {
  surface_id : int;
  surface_app : ('model, 'action, 'shared) t;
  surface_backend : Lui_protocol.backend;
  surface_runtime : Lui_runtime.application;
  surface_scope : Signal.scope;
  surface_context : Lui_ui.ui_context;
  mutable surface_root : int;
  mutable surface_state : lifecycle_state;
}

let create ?(registry = Lui_extension.registry ()) ~shared initial_model
    reducer view =
  let scheduler = Signal.scheduler () in
  {
    app_scheduler = scheduler;
    app_registry = registry;
    app_model = Signal.state scheduler initial_model;
    app_reducer = reducer;
    app_view = view;
    app_shared = shared;
    app_scope = Signal.scope "multi-window-app";
    app_lifecycle = ref Running;
    app_surfaces = Hashtbl.create 4;
    app_order = [];
    app_next_surface = ref 0;
  }

let shared t = t.app_shared

let scheduler t = t.app_scheduler

let model t = Signal.get_state t.app_model

let model_signal t = Signal.value t.app_model

let send t action =
  if !(t.app_lifecycle) = Running then begin
    Signal.update t.app_model (fun current -> t.app_reducer current action);
    true
  end
  else false

let open_window ?view t backend =
  if !(t.app_lifecycle) <> Running then
    invalid_arg "application is not running";
  let id = !(t.app_next_surface) in
  incr t.app_next_surface;
  let runtime =
    Lui_runtime.create_with_extensions t.app_scheduler backend
      t.app_registry
  in
  let scope =
    Signal.child_scope ("window-" ^ string_of_int id) t.app_scope
  in
  let context = Lui_ui.context runtime scope in
  let surface =
    {
      surface_id = id;
      surface_app = t;
      surface_backend = backend;
      surface_runtime = runtime;
      surface_scope = scope;
      surface_context = context;
      surface_root = -1;
      surface_state = Running;
    }
  in
  let view = Option.value ~default:t.app_view view in
  let send_action action = send t action in
  (* An explicit Root node owns theme props and keeps the view's root
     replaceable, matching the reloadable-app layout. *)
  let root = Lui_runtime.create_node runtime Lui_protocol.Root in
  let view_node =
    (view surface context (Signal.value t.app_model) send_action)
      context None
  in
  Lui_runtime.insert_child runtime root view_node 0;
  surface.surface_root <- root;
  Hashtbl.replace t.app_surfaces id surface;
  t.app_order <- t.app_order @ [ surface ];
  Signal.mount scope;
  surface

let close_window surface =
  match surface.surface_state with
  | Running ->
    surface.surface_state <- Disposing;
    let t = surface.surface_app in
    Hashtbl.remove t.app_surfaces surface.surface_id;
    t.app_order <-
      List.filter (fun other -> not (other == surface)) t.app_order;
    Signal.dispose_scope surface.surface_scope;
    Lui_runtime.drop_subtree surface.surface_runtime surface.surface_root;
    ignore (Lui_runtime.flush surface.surface_runtime);
    surface.surface_state <- Disposed;
    true
  | Disposing | Disposed -> false

let surfaces t = t.app_order

let surface_count t = Hashtbl.length t.app_surfaces

let surface_id surface = surface.surface_id

let surface_application surface = surface.surface_app

let surface_runtime surface = surface.surface_runtime

let surface_context surface = surface.surface_context

let surface_root surface = surface.surface_root

let surface_backend surface = surface.surface_backend

let surface_closed surface = surface.surface_state <> Running

let dispatch surface event =
  if
    surface.surface_state = Running
    && !(surface.surface_app.app_lifecycle) = Running
  then Lui_runtime.dispatch surface.surface_runtime event
  else false

let flush_surface surface =
  match surface.surface_state with
  | Running -> Lui_runtime.flush surface.surface_runtime
  | Disposing | Disposed -> true

let flush t =
  if !(t.app_lifecycle) = Disposed then true
  else begin
    List.iter (fun surface -> ignore (flush_surface surface)) t.app_order;
    true
  end

let set_theme t tokens =
  List.iter
    (fun surface ->
       Lui_runtime.set_prop surface.surface_runtime surface.surface_root
         Lui_protocol.ThemeValue
         (Lui_protocol.StringValue (Lui_ui.theme_tokens_json tokens)))
    t.app_order

let set_theme_mode t mode =
  List.iter
    (fun surface ->
       Lui_runtime.set_prop surface.surface_runtime surface.surface_root
         Lui_protocol.ThemeMode
         (Lui_protocol.StringValue (Lui_ui.theme_mode_value mode)))
    t.app_order

let dispose t =
  match !(t.app_lifecycle) with
  | Disposed -> true
  | Running | Disposing ->
    t.app_lifecycle := Disposing;
    List.iter (fun surface -> ignore (close_window surface)) t.app_order;
    Signal.dispose_scope t.app_scope;
    t.app_lifecycle := Disposed;
    true

let disposed t = !(t.app_lifecycle) = Disposed
