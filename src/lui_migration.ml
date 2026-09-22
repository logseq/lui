(* Snapshot capture/apply for soft restarts across a model migration. *)

type 'payload model_snapshot = {
  snapshot_version : int;
  snapshot_fingerprint : string;
  snapshot_payload : 'payload;
}

type ('model, 'payload) capture_result =
  | SnapshotCaptured of 'payload model_snapshot
  | SnapshotCaptureRejected of string

type ('model, 'payload) migration_plan = {
  migration_source_version : int;
  migration_source_fingerprint : string;
  migration_target_fingerprint : string;
  migrate_snapshot : 'payload -> 'model;
  validate_model : 'model -> string option;
}

type 'model migration_result =
  | MigrationApplied of 'model
  | MigrationRejected of string
  | MigrationRestartRequired of string

type 'target soft_restart_result =
  | SoftRestartApplied of 'target
  | SoftRestartRejected of string
  | SoftRestartRequired of string

type 'value queued_message = {
  message_generation : int;
  message_fingerprint : string;
  message_value : 'value;
}

type 'value message_drain = {
  compatible_messages : 'value list;
  discarded_message_count : int;
}

let capture version fingerprint model encode =
  if version < 0 || fingerprint = "" then
    SnapshotCaptureRejected "snapshot contract is invalid"
  else
    try
      SnapshotCaptured
        {
          snapshot_version = version;
          snapshot_fingerprint = fingerprint;
          snapshot_payload = encode model;
        }
    with Invalid_argument message -> SnapshotCaptureRejected message

let apply plan snapshot =
  if snapshot.snapshot_version <> plan.migration_source_version then
    MigrationRestartRequired "snapshot version changed"
  else if snapshot.snapshot_fingerprint <> plan.migration_source_fingerprint
  then MigrationRestartRequired "snapshot fingerprint changed"
  else if plan.migration_target_fingerprint = "" then
    MigrationRestartRequired "target fingerprint is missing"
  else
    try
      let model = plan.migrate_snapshot snapshot.snapshot_payload in
      match plan.validate_model model with
      | Some message -> MigrationRejected message
      | None -> MigrationApplied model
    with Invalid_argument message -> MigrationRejected message

let soft_restart migration start activate discard retire_old =
  match migration with
  | MigrationRejected message -> SoftRestartRejected message
  | MigrationRestartRequired message -> SoftRestartRequired message
  | MigrationApplied model ->
    let candidate =
      try Some (start model) with Invalid_argument _ -> None
    in
    (match candidate with
    | None -> SoftRestartRejected "candidate start failed"
    | Some target ->
      let activated =
        try activate target with Invalid_argument _ -> false
      in
      if not activated then begin
        discard target;
        SoftRestartRejected "candidate activation failed"
      end
      else if retire_old () then SoftRestartApplied target
      else SoftRestartRequired "old application retirement failed")

let drain_compatible messages generation fingerprint =
  List.fold_left
    (fun result message ->
       if
         message.message_generation = generation
         && message.message_fingerprint = fingerprint
       then
         {
           compatible_messages =
             result.compatible_messages @ [ message.message_value ];
           discarded_message_count = result.discarded_message_count;
         }
       else
         {
           compatible_messages = result.compatible_messages;
           discarded_message_count = result.discarded_message_count + 1;
         })
    { compatible_messages = []; discarded_message_count = 0 }
    messages
