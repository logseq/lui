(* ns lui.restart *)

type text_selection = { selection_start : int ; selection_end : int }

type window_context = { window_key : string ; window_x : float ; window_y : float ; window_width : float ; window_height : float ; window_active : bool }

type restart_context = { restart_route : string option ; restart_selected_tabs : (string, string) Lg_runtime.Runtime_map.t ; restart_focused_reload_key : string option ; restart_selection : text_selection option ; restart_scroll_offsets : (string, float) Lg_runtime.Runtime_map.t ; restart_windows : window_context Rrbvec.t }

type restart_reason =
  | ModelTypeChanged
  | PackageGraphChanged
  | FfiChanged
  | HostAbiChanged
  | CompilerOptionsChanged
  | CompilerCrashed
  | TargetDisconnected
  | MigrationFailed of string

type restart_step_result =
  | RestartStepCompleted
  | RestartStepRejected of string

type restart_capture_result =
  | RestartContextCaptured of restart_context
  | RestartContextRejected of string

type restart_status =
  | RestartCompleted of int * bool
  | RestartRejected of int * string * string
  | RestartStale of int

type restart_event = { restart_event_generation : int ; restart_event_reason : restart_reason ; restart_event_status : restart_status }

type restart_coordinator = { capture_restart_context : unit -> restart_context ; rebuild_target : restart_reason -> restart_step_result ; launch_target : restart_context -> restart_step_result ; restore_restart_context : restart_context -> restart_step_result ; restart_requested_generation : int ref ; restart_completed_generation : int ref ; restart_events : restart_event Rrbvec.t ref }

val create : (unit -> restart_context) -> (restart_reason -> restart_step_result) -> (restart_context -> restart_step_result) -> (restart_context -> restart_step_result) -> restart_coordinator

val request_bang : restart_coordinator -> int

val run_step : ('argument -> restart_step_result) -> 'argument -> restart_step_result

val capture_context : restart_coordinator -> restart_capture_result

val run_bang : restart_coordinator -> int -> restart_reason -> restart_status

val automatic_bang : restart_coordinator -> restart_reason -> restart_status

val handle_reload_bang : restart_coordinator -> reload_status -> restart_reason -> restart_status option

val events : restart_coordinator -> restart_event Rrbvec.t

