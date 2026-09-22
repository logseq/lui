(* Restart coordinator: capture, rebuild, launch, and restore steps with
   generation bookkeeping and an event log. *)

type step_status =
  | RestartStepCompleted
  | RestartStepRejected of string

type 'context capture_status =
  | RestartContextCaptured of 'context
  | RestartContextRejected of string

type restart_status =
  | RestartStale of int
  | RestartCompleted of int * bool
  | RestartRejected of int * string * string

type restart_event = {
  restart_event_generation : int;
  restart_event_reason : string;
  restart_event_status : restart_status;
}

type ('context, 'reason) restart_coordinator = {
  capture_restart_context : unit -> 'context;
  rebuild_target : 'reason -> unit;
  launch_target : 'context -> unit;
  restore_restart_context : 'context -> unit;
  restart_requested_generation : int ref;
  restart_completed_generation : int ref;
  restart_events : restart_event list ref;
}

let create capture rebuild launch restore =
  {
    capture_restart_context = capture;
    rebuild_target = rebuild;
    launch_target = launch;
    restore_restart_context = restore;
    restart_requested_generation = ref 0;
    restart_completed_generation = ref 0;
    restart_events = ref [];
  }

let request coordinator =
  incr coordinator.restart_requested_generation;
  !(coordinator.restart_requested_generation)

let record_event coordinator generation reason status completed =
  if completed then coordinator.restart_completed_generation := generation;
  coordinator.restart_events :=
    !(coordinator.restart_events)
    @ [
        {
          restart_event_generation = generation;
          restart_event_reason = reason;
          restart_event_status = status;
        };
      ];
  status

let reject coordinator generation reason stage message =
  ignore
    (record_event coordinator generation reason
       (RestartRejected (generation, stage, message)) true);
  RestartRejected (generation, stage, message)

let run_step step argument =
  try
    step argument;
    RestartStepCompleted
  with Invalid_argument message -> RestartStepRejected message

let capture_context coordinator =
  try RestartContextCaptured (coordinator.capture_restart_context ())
  with Invalid_argument message -> RestartContextRejected message

let run coordinator generation reason =
  let requested = !(coordinator.restart_requested_generation) in
  let completed = !(coordinator.restart_completed_generation) in
  if generation < requested || generation <= completed then
    record_event coordinator generation reason (RestartStale generation)
      false
  else if generation <= 0 || generation > requested then
    reject coordinator generation reason "request"
      "restart generation was not requested"
  else
    match capture_context coordinator with
    | RestartContextRejected message ->
      reject coordinator generation reason "capture" message
    | RestartContextCaptured context ->
      (match run_step coordinator.rebuild_target reason with
      | RestartStepRejected message ->
        reject coordinator generation reason "rebuild" message
      | RestartStepCompleted ->
        (match run_step coordinator.launch_target context with
        | RestartStepRejected message ->
          reject coordinator generation reason "launch" message
        | RestartStepCompleted ->
          (match run_step coordinator.restore_restart_context context with
          | RestartStepRejected message ->
            reject coordinator generation reason "restore" message
          | RestartStepCompleted ->
            record_event coordinator generation reason
              (RestartCompleted (generation, true)) true)))

let automatic coordinator reason = run coordinator (request coordinator) reason

let handle_reload coordinator status reason =
  match status with
  | Lui_hot_reload.ReloadRestartRequired (_generation, _message) ->
    Some (automatic coordinator reason)
  | _ -> None

let events coordinator = !(coordinator.restart_events)
