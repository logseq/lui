(* Hot reload session bookkeeping: generation tracking, preflight checks,
   and an event log for applied/rejected reloads. *)

type reload_status =
  | ReloadApplied of int
  | ReloadUnchanged of int
  | ReloadStale of int
  | ReloadRejected of int * string
  | ReloadRestartRequired of int * string

type 'root committed_root = {
  committed_root_value : 'root;
  committed_root_source_hash : string;
  committed_root_generation : int;
}

type reload_event = {
  reload_event_generation : int;
  reload_event_source_hash : string;
  reload_event_status : reload_status;
  reload_event_elapsed_ms : int;
}

type 'root hot_reload_session = {
  hot_reload_committed_root : 'root committed_root ref;
  hot_reload_contract_hash : string;
  hot_reload_requested_generation : int ref;
  hot_reload_completed_generation : int ref;
  hot_reload_events : reload_event list ref;
}

let create source_hash contract_hash root =
  {
    hot_reload_committed_root =
      ref
        {
          committed_root_value = root;
          committed_root_source_hash = source_hash;
          committed_root_generation = 0;
        };
    hot_reload_contract_hash = contract_hash;
    hot_reload_requested_generation = ref 0;
    hot_reload_completed_generation = ref 0;
    hot_reload_events = ref [];
  }

let request session =
  incr session.hot_reload_requested_generation;
  !(session.hot_reload_requested_generation)

let committed_root session = !(session.hot_reload_committed_root)

let source_hash session =
  (committed_root session).committed_root_source_hash

let preflight session request candidate_source_hash contract_hash =
  let requested = !(session.hot_reload_requested_generation) in
  let completed = !(session.hot_reload_completed_generation) in
  if request <= 0 || request > requested then
    Some (ReloadRejected (request, "candidate generation was not requested"))
  else if request < requested || request <= completed then
    Some (ReloadStale request)
  else if contract_hash <> session.hot_reload_contract_hash then
    Some (ReloadRestartRequired (request, "root contract changed"))
  else if candidate_source_hash = source_hash session then
    Some (ReloadUnchanged request)
  else None

let record_event session request source_hash status elapsed_ms =
  session.hot_reload_events :=
    !(session.hot_reload_events)
    @ [
        {
          reload_event_generation = request;
          reload_event_source_hash = source_hash;
          reload_event_status = status;
          reload_event_elapsed_ms = elapsed_ms;
        };
      ];
  status

let record_completed_event session request source_hash status elapsed_ms =
  session.hot_reload_completed_generation := request;
  record_event session request source_hash status elapsed_ms

let reject session request source_hash message elapsed_ms =
  record_completed_event session request source_hash
    (ReloadRejected (request, message)) elapsed_ms

let validate_and_publish session request source_hash root validate
    elapsed_ms =
  try
    match validate root with
    | Some message -> reject session request source_hash message elapsed_ms
    | None ->
      session.hot_reload_committed_root :=
        {
          committed_root_value = root;
          committed_root_source_hash = source_hash;
          committed_root_generation = request;
        };
      record_completed_event session request source_hash
        (ReloadApplied request) elapsed_ms
  with Invalid_argument message ->
    reject session request source_hash message elapsed_ms

let publish session request candidate_source_hash contract_hash root
    validate elapsed_ms =
  match preflight session request candidate_source_hash contract_hash with
  | Some status ->
    (match status with
    | ReloadRejected (_generation, message) ->
      record_event session request candidate_source_hash
        (ReloadRejected (request, message)) elapsed_ms
    | ReloadStale _generation ->
      record_event session request candidate_source_hash
        (ReloadStale request) elapsed_ms
    | ReloadRestartRequired (_generation, message) ->
      record_completed_event session request candidate_source_hash
        (ReloadRestartRequired (request, message)) elapsed_ms
    | ReloadUnchanged _generation ->
      record_completed_event session request candidate_source_hash
        (ReloadUnchanged request) elapsed_ms
    | ReloadApplied _generation ->
      invalid_arg "applied status cannot be preflighted")
  | None ->
    validate_and_publish session request candidate_source_hash root
      validate elapsed_ms

let current_root session = (committed_root session).committed_root_value

let generation session =
  (committed_root session).committed_root_generation

let events session = !(session.hot_reload_events)

let latest_event session =
  match List.rev !(session.hot_reload_events) with
  | [] -> None
  | latest :: _ -> Some latest
