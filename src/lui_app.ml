(* Application driver: wires scheduler + runtime + reducer + view into a
   reducer-app record, plus reloadable app state. *)

type lifecycle_state =
  | Running
  | Disposing
  | Disposed

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

let reduce model_state reducer action =
  Signal.update model_state (fun current -> reducer current action)

let restore_state_scopes state_scopes saved =
  Hashtbl.iter
    (fun path scope ->
       if not (Hashtbl.mem saved path) then Signal.dispose_scope scope)
    state_scopes;
  Hashtbl.reset state_scopes;
  Hashtbl.iter (Hashtbl.replace state_scopes) saved;
  true

let prune_state_scopes state_scopes active =
  let retained =
    Hashtbl.fold
      (fun path scope result ->
         if Hashtbl.mem active path then begin
           Hashtbl.replace result path scope;
           result
         end
         else begin
           Signal.dispose_scope scope;
           result
         end)
      state_scopes (Hashtbl.create 16)
  in
  Hashtbl.reset state_scopes;
  Hashtbl.iter (Hashtbl.replace state_scopes) retained;
  true

let create_with_extensions backend registry initial_model reducer view =
  let scheduler = Signal.scheduler () in
  let application =
    Lui_runtime.create_with_extensions scheduler backend registry
  in
  let scope = Signal.scope "app" in
  let context = Lui_ui.context application scope in
  let model_state = Signal.state scheduler initial_model in
  let lifecycle = ref Running in
  let send_action action =
    if !(lifecycle) = Running then begin
      reduce model_state reducer action;
      true
    end
    else false
  in
  let root =
    (view context (Signal.value model_state) send_action) context None
  in
  {
    app_scheduler = scheduler;
    app_runtime = application;
    app_scope = scope;
    app_read_model = (fun () -> Signal.get_state model_state);
    app_send_action = send_action;
    app_root_node = root;
    app_lifecycle_state = lifecycle;
    app_reload_state = None;
  }

let create backend initial_model reducer view =
  let scheduler = Signal.scheduler () in
  let application = Lui_runtime.create scheduler backend in
  let scope = Signal.scope "app" in
  let context = Lui_ui.context application scope in
  let model_state = Signal.state scheduler initial_model in
  let lifecycle = ref Running in
  let send_action action =
    if !(lifecycle) = Running then begin
      reduce model_state reducer action;
      true
    end
    else false
  in
  let root =
    (view context (Signal.value model_state) send_action) context None
  in
  {
    app_scheduler = scheduler;
    app_runtime = application;
    app_scope = scope;
    app_read_model = (fun () -> Signal.get_state model_state);
    app_send_action = send_action;
    app_root_node = root;
    app_lifecycle_state = lifecycle;
    app_reload_state = None;
  }

let create_reloadable_with_extensions backend registry source_hash
    contract_hash initial_model reducer view =
  let scheduler = Signal.scheduler () in
  let application =
    Lui_runtime.create_with_extensions scheduler backend registry
  in
  let scope = Signal.scope "app" in
  let view_scope = Signal.child_scope "app-view-0" scope in
  let state_scope = Signal.child_scope "app-view-state" scope in
  let state_scopes = Hashtbl.create 16 in
  let active_state_paths = Hashtbl.create 16 in
  let context =
    Lui_ui.context_with_state_registry application view_scope state_scope
      state_scopes active_state_paths
  in
  let model_state = Signal.state scheduler initial_model in
  let lifecycle = ref Running in
  let reducer_root = ref reducer in
  let send_action action =
    if !(lifecycle) = Running then begin
      reduce model_state !(reducer_root) action;
      true
    end
    else false
  in
  let root = Lui_runtime.create_node application Lui_protocol.Root in
  let view_node =
    (view context (Signal.value model_state) send_action) context None
  in
  let session = Lui_hot_reload.create source_hash contract_hash view in
  let app =
    {
      app_scheduler = scheduler;
      app_runtime = application;
      app_scope = scope;
      app_read_model = (fun () -> Signal.get_state model_state);
      app_send_action = send_action;
      app_root_node = root;
      app_lifecycle_state = lifecycle;
      app_reload_state =
        Some
          {
            reload_model_source = Signal.value model_state;
            reload_view_scope = ref view_scope;
            reload_state_scope = state_scope;
            reload_state_scopes = state_scopes;
            reload_view_node = ref view_node;
            reload_session = session;
          };
    }
  in
  Lui_runtime.insert_child application root view_node 0;
  app

let create_reloadable backend source_hash contract_hash initial_model
    reducer view =
  let scheduler = Signal.scheduler () in
  let application = Lui_runtime.create scheduler backend in
  let scope = Signal.scope "app" in
  let view_scope = Signal.child_scope "app-view-0" scope in
  let state_scope = Signal.child_scope "app-view-state" scope in
  let state_scopes = Hashtbl.create 16 in
  let active_state_paths = Hashtbl.create 16 in
  let context =
    Lui_ui.context_with_state_registry application view_scope state_scope
      state_scopes active_state_paths
  in
  let model_state = Signal.state scheduler initial_model in
  let lifecycle = ref Running in
  let send_action action =
    if !(lifecycle) = Running then begin
      reduce model_state reducer action;
      true
    end
    else false
  in
  let root = Lui_runtime.create_node application Lui_protocol.Root in
  let view_node =
    (view context (Signal.value model_state) send_action) context None
  in
  let session = Lui_hot_reload.create source_hash contract_hash view in
  let app =
    {
      app_scheduler = scheduler;
      app_runtime = application;
      app_scope = scope;
      app_read_model = (fun () -> Signal.get_state model_state);
      app_send_action = send_action;
      app_root_node = root;
      app_lifecycle_state = lifecycle;
      app_reload_state =
        Some
          {
            reload_model_source = Signal.value model_state;
            reload_view_scope = ref view_scope;
            reload_state_scope = state_scope;
            reload_state_scopes = state_scopes;
            reload_view_node = ref view_node;
            reload_session = session;
          };
    }
  in
  Lui_runtime.insert_child application root view_node 0;
  app

let start app =
  if !(app.app_lifecycle_state) = Running then begin
    Signal.mount app.app_scope;
    (match app.app_reload_state with
    | Some state ->
      Signal.mount state.reload_state_scope;
      Signal.mount !(state.reload_view_scope)
    | None -> ());
    true
  end
  else false

let flush app =
  if !(app.app_lifecycle_state) = Disposed then true
  else Lui_runtime.flush app.app_runtime

let dispose app =
  match !(app.app_lifecycle_state) with
  | Disposed -> true
  | Running ->
    app.app_lifecycle_state := Disposing;
    Signal.dispose_scope app.app_scope;
    Lui_runtime.drop_subtree app.app_runtime app.app_root_node;
    if Lui_runtime.flush app.app_runtime then
      app.app_lifecycle_state := Disposed;
    true
  | Disposing ->
    if Lui_runtime.flush app.app_runtime then
      app.app_lifecycle_state := Disposed;
    true

let disposed app = !(app.app_lifecycle_state) = Disposed

let model app = app.app_read_model ()

let root_node app = app.app_root_node

let runtime app = app.app_runtime

let send app action = app.app_send_action action

let dispatch_event app event =
  if !(app.app_lifecycle_state) = Running then
    Lui_runtime.dispatch app.app_runtime event
  else false

let require_reload_state app =
  match app.app_reload_state with
  | Some state -> state
  | None -> invalid_arg "application is not reloadable"

let request_reload app =
  Lui_hot_reload.request (require_reload_state app).reload_session

let reject_view state request source_hash contract_hash view message
    elapsed_ms =
  Lui_hot_reload.publish state.reload_session request source_hash
    contract_hash view
    (fun _candidate -> Some message)
    elapsed_ms

let reload_view app request source_hash contract_hash view elapsed_ms =
  let state = require_reload_state app in
  let session = state.reload_session in
  if !(app.app_lifecycle_state) <> Running then
    reject_view state request source_hash contract_hash view
      "application is not running" elapsed_ms
  else
    match
      Lui_hot_reload.preflight session request source_hash contract_hash
    with
    | Some _status ->
      Lui_hot_reload.publish session request source_hash contract_hash view
        (fun _candidate -> None) elapsed_ms
    | None ->
      let application = app.app_runtime in
      let saved = Lui_runtime.checkpoint application in
      let old_scope = !(state.reload_view_scope) in
      let old_view = !(state.reload_view_node) in
      let saved_state_scopes = Hashtbl.copy state.reload_state_scopes in
      let candidate_active_state_paths = Hashtbl.create 16 in
      let candidate_scope =
        Signal.child_scope
          ("app-view-" ^ string_of_int request)
          app.app_scope
      in
      let candidate_node = ref None in
      let failure =
        try
          let context =
            Lui_ui.context_with_state_registry application candidate_scope
              state.reload_state_scope state.reload_state_scopes
              candidate_active_state_paths
          in
          let node =
            (view context state.reload_model_source app.app_send_action)
              context None
          in
          candidate_node :=
            Some
              (Lui_runtime.reconcile_subtree application saved
                 app.app_root_node old_view node);
          ignore (Lui_runtime.flush application);
          None
        with Invalid_argument message ->
          Lui_runtime.restore application saved;
          ignore
            (restore_state_scopes state.reload_state_scopes
               saved_state_scopes);
          Signal.dispose_scope candidate_scope;
          Some message
      in
      (match failure with
      | Some message ->
        reject_view state request source_hash contract_hash view message
          elapsed_ms
      | None ->
        let node =
          match !(candidate_node) with
          | Some current -> current
          | None ->
            invalid_arg "candidate view did not return a node"
        in
        Lui_runtime.retire_checkpoint_dynamic_segments saved old_view;
        Signal.dispose_scope old_scope;
        ignore
          (prune_state_scopes state.reload_state_scopes
             candidate_active_state_paths);
        Signal.mount candidate_scope;
        state.reload_view_scope := candidate_scope;
        state.reload_view_node := node;
        Lui_hot_reload.publish session request source_hash contract_hash
          view
          (fun _candidate -> None)
          elapsed_ms)
