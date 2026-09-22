(* Developer session: event log, editor diagnostics, overlay model, and
   reload latency summaries. *)

type diagnostic_phase =
  | ReaderDiagnostic
  | ParseDiagnostic
  | TypeDiagnostic
  | LowerDiagnostic
  | OcamlDiagnostic
  | ResourceDiagnostic
  | MigrationDiagnostic
  | InfrastructureDiagnostic
  | ProtocolDiagnostic

type source_range = {
  range_file : string;
  range_start_line : int;
  range_start_column : int;
  range_end_line : int;
  range_end_column : int;
}

type hot_diagnostic = {
  diagnostic_code : string;
  diagnostic_phase : diagnostic_phase;
  diagnostic_message : string;
  diagnostic_range : source_range option;
  diagnostic_related_ranges : source_range list;
}

type retained_state_inspection = {
  inspection_widget_count : int;
  inspection_handler_count : int;
  inspection_subscription_count : int;
  inspection_resource_count : int;
  inspection_state_scope_count : int;
}

type restart_reason = string

type developer_event =
  | DeveloperChangeDetected of int * string list
  | DeveloperCompilationStarted of int
  | DeveloperDiagnostic of int * hot_diagnostic
  | DeveloperReloadCommitted of
      int * int * string list * int list * retained_state_inspection
  | DeveloperReloadUnchanged of int * int
  | DeveloperReloadRejected of int * string
  | DeveloperReloadStale of int
  | DeveloperRestartRequired of int * string
  | DeveloperMigrationRequired of string
  | DeveloperMigrationFailed of string
  | DeveloperRestartStarted of int * restart_reason
  | DeveloperRestartCompleted of int * bool
  | DeveloperRestartRejected of int * string * string
  | DeveloperRestartStale of int
  | DeveloperTargetDisconnected of string
  | DeveloperProtocolMismatch of string * string

type overlay_model = {
  overlay_visible : bool;
  overlay_collapsed : bool;
  overlay_generation : int;
  overlay_title : string;
  overlay_detail : string;
}

type reload_latency_summary = {
  latency_sample_count : int;
  latency_p50_ms : int;
  latency_p95_ms : int;
  latency_max_ms : int;
}

type developer_session = {
  developer_events : developer_event list ref;
  developer_diagnostics : (string, hot_diagnostic) Hashtbl.t;
  developer_latencies : int list ref;
  developer_overlay_visible : bool ref;
  developer_overlay_collapsed : bool ref;
  developer_overlay_generation : int ref;
  developer_overlay_title : string ref;
  developer_overlay_detail : string ref;
}

let create () =
  {
    developer_events = ref [];
    developer_diagnostics = Hashtbl.create 16;
    developer_latencies = ref [];
    developer_overlay_visible = ref false;
    developer_overlay_collapsed = ref false;
    developer_overlay_generation = ref 0;
    developer_overlay_title = ref "";
    developer_overlay_detail = ref "";
  }

let diagnostic_key diagnostic =
  diagnostic.diagnostic_code ^ "\x00" ^ diagnostic.diagnostic_message
  ^ "\x00"
  ^
  match diagnostic.diagnostic_range with
  | Some location ->
    location.range_file ^ ":"
    ^ string_of_int location.range_start_line
    ^ ":"
    ^ string_of_int location.range_start_column
    ^ ":"
    ^ string_of_int location.range_end_line
    ^ ":"
    ^ string_of_int location.range_end_column
  | None -> ""

let record_event session event =
  session.developer_events := !(session.developer_events) @ [ event ];
  true

let show_overlay session generation title detail =
  session.developer_overlay_visible := true;
  session.developer_overlay_generation := generation;
  session.developer_overlay_title := title;
  session.developer_overlay_detail := detail;
  true

let hide_overlay session =
  session.developer_overlay_visible := false;
  session.developer_overlay_collapsed := false;
  true

let record_change_detected session generation paths =
  record_event session (DeveloperChangeDetected (generation, paths))

let record_compilation_started session generation =
  record_event session (DeveloperCompilationStarted generation)

let record_diagnostic session generation diagnostic =
  Hashtbl.replace session.developer_diagnostics
    (diagnostic_key diagnostic) diagnostic;
  ignore
    (show_overlay session generation diagnostic.diagnostic_code
       diagnostic.diagnostic_message);
  record_event session (DeveloperDiagnostic (generation, diagnostic))

let editor_diagnostics session =
  Hashtbl.fold
    (fun _key diagnostic result -> diagnostic :: result)
    session.developer_diagnostics []
  |> List.rev

let overlay session =
  {
    overlay_visible = !(session.developer_overlay_visible);
    overlay_collapsed = !(session.developer_overlay_collapsed);
    overlay_generation = !(session.developer_overlay_generation);
    overlay_title = !(session.developer_overlay_title);
    overlay_detail = !(session.developer_overlay_detail);
  }

let render_overlay context model =
  let toast = Lui_ui.toast context in
  let title = Lui_ui.text context model.overlay_title in
  Lui_ui.append context toast title;
  if not model.overlay_collapsed then
    Lui_ui.append context toast (Lui_ui.text context model.overlay_detail);
  toast

let collapse_overlay session =
  session.developer_overlay_collapsed := true;
  true

let expand_overlay session =
  session.developer_overlay_collapsed := false;
  true

let record_latency session elapsed_ms =
  if elapsed_ms < 0 then invalid_arg "reload latency cannot be negative";
  session.developer_latencies := !(session.developer_latencies) @ [ elapsed_ms ];
  true

let percentile sorted_latencies percent =
  match sorted_latencies with
  | [] -> 0
  | _ ->
    let sample_count = List.length sorted_latencies in
    let rank = (sample_count * percent + 99) / 100 in
    let index = max 1 rank - 1 in
    List.nth sorted_latencies index

let latency_summary session =
  let sorted_latencies = List.sort compare !(session.developer_latencies) in
  let sample_count = List.length sorted_latencies in
  {
    latency_sample_count = sample_count;
    latency_p50_ms = percentile sorted_latencies 50;
    latency_p95_ms = percentile sorted_latencies 95;
    latency_max_ms =
      (if sample_count = 0 then 0
       else List.nth sorted_latencies (sample_count - 1));
  }

let ingest_reload session event affected_roots invalidated_nodes inspection =
  let generation = event.Lui_hot_reload.reload_event_generation in
  let elapsed_ms = event.reload_event_elapsed_ms in
  match event.reload_event_status with
  | Lui_hot_reload.ReloadApplied _generation ->
    Hashtbl.reset session.developer_diagnostics;
    ignore (record_latency session elapsed_ms);
    ignore (hide_overlay session);
    record_event session
      (DeveloperReloadCommitted
         (generation, elapsed_ms, affected_roots, invalidated_nodes,
          inspection))
  | Lui_hot_reload.ReloadUnchanged _generation ->
    Hashtbl.reset session.developer_diagnostics;
    ignore (record_latency session elapsed_ms);
    ignore (hide_overlay session);
    record_event session (DeveloperReloadUnchanged (generation, elapsed_ms))
  | Lui_hot_reload.ReloadRejected (_generation, message) ->
    ignore (show_overlay session generation "Reload rejected" message);
    record_event session (DeveloperReloadRejected (generation, message))
  | Lui_hot_reload.ReloadStale _generation ->
    record_event session (DeveloperReloadStale generation)
  | Lui_hot_reload.ReloadRestartRequired (_generation, message) ->
    ignore (show_overlay session generation "Restart required" message);
    record_event session (DeveloperRestartRequired (generation, message))

let record_target_disconnected session message =
  ignore (show_overlay session 0 "Target disconnected" message);
  record_event session (DeveloperTargetDisconnected message)

let record_migration_required session message =
  ignore (show_overlay session 0 "Migration required" message);
  record_event session (DeveloperMigrationRequired message)

let record_migration_failed session message =
  ignore (show_overlay session 0 "Migration failed" message);
  record_event session (DeveloperMigrationFailed message)

let ingest_restart session event =
  let generation = event.Lui_restart.restart_event_generation in
  let reason = event.restart_event_reason in
  match event.restart_event_status with
  | Lui_restart.RestartStale _generation ->
    record_event session (DeveloperRestartStale generation)
  | Lui_restart.RestartCompleted (_generation, restored) ->
    ignore
      (record_event session (DeveloperRestartStarted (generation, reason)));
    ignore (hide_overlay session);
    record_event session (DeveloperRestartCompleted (generation, restored))
  | Lui_restart.RestartRejected (_generation, stage, message) ->
    ignore
      (record_event session (DeveloperRestartStarted (generation, reason)));
    ignore
      (show_overlay session generation
         ("Restart failed during " ^ stage)
         message);
    record_event session
      (DeveloperRestartRejected (generation, stage, message))

let record_protocol_mismatch session expected actual =
  ignore
    (show_overlay session 0 "Protocol mismatch"
       ("expected " ^ expected ^ ", got " ^ actual));
  record_event session (DeveloperProtocolMismatch (expected, actual))

let events session = !(session.developer_events)

let latest_event session =
  match List.rev !(session.developer_events) with
  | [] -> None
  | latest :: _ -> Some latest
