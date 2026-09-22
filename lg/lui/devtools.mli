(* ns lui.devtools *)

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

type source_range = { range_file : string ; range_start_line : int ; range_start_column : int ; range_end_line : int ; range_end_column : int }

type hot_diagnostic = { diagnostic_code : string ; diagnostic_phase : diagnostic_phase ; diagnostic_message : string ; diagnostic_range : source_range option ; diagnostic_related_ranges : source_range Rrbvec.t }

type retained_state_inspection = { inspection_widget_count : int ; inspection_handler_count : int ; inspection_subscription_count : int ; inspection_resource_count : int ; inspection_state_scope_count : int }

type developer_event =
  | DeveloperChangeDetected of int * string Rrbvec.t
  | DeveloperCompilationStarted of int
  | DeveloperDiagnostic of int * hot_diagnostic
  | DeveloperReloadCommitted of int * int * string Rrbvec.t * int Rrbvec.t * retained_state_inspection
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

type overlay_model = { overlay_visible : bool ; overlay_collapsed : bool ; overlay_generation : int ; overlay_title : string ; overlay_detail : string }

type reload_latency_summary = { latency_sample_count : int ; latency_p50_ms : int ; latency_p95_ms : int ; latency_max_ms : int }

type developer_session = { developer_events : developer_event Rrbvec.t ref ; developer_diagnostics : (string, hot_diagnostic) Lg_runtime.Runtime_map.t ref ; developer_latencies : int Rrbvec.t ref ; developer_overlay_visible : bool ref ; developer_overlay_collapsed : bool ref ; developer_overlay_generation : int ref ; developer_overlay_title : string ref ; developer_overlay_detail : string ref }

val create : unit -> developer_session

val record_change_detected_bang : developer_session -> int -> string Rrbvec.t -> bool

val record_compilation_started_bang : developer_session -> int -> bool

val diagnostic_key : hot_diagnostic -> string

val record_diagnostic_bang : developer_session -> int -> hot_diagnostic -> bool

val editor_diagnostics : developer_session -> hot_diagnostic Rrbvec.t

val overlay : developer_session -> overlay_model

val render_overlay_bang : ui_context -> overlay_model -> int

val collapse_overlay_bang : developer_session -> bool

val expand_overlay_bang : developer_session -> bool

val record_latency_bang : developer_session -> int -> bool

val latency_summary : developer_session -> reload_latency_summary

val ingest_reload_bang : developer_session -> reload_event -> string Rrbvec.t -> int Rrbvec.t -> retained_state_inspection -> bool

val record_target_disconnected_bang : developer_session -> string -> bool

val record_migration_required_bang : developer_session -> string -> bool

val record_migration_failed_bang : developer_session -> string -> bool

val ingest_restart_bang : developer_session -> restart_event -> bool

val record_protocol_mismatch_bang : developer_session -> string -> string -> bool

val events : developer_session -> developer_event Rrbvec.t

val latest_event : developer_session -> developer_event option

val percentile : int Rrbvec.t -> int -> int

