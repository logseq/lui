(* ns lui.migration *)

type 'payload model_snapshot = { snapshot_version : int ; snapshot_fingerprint : string ; snapshot_payload : 'payload }

type 'payload snapshot_capture_result =
  | SnapshotCaptured of 'payload model_snapshot
  | SnapshotCaptureRejected of string

type ('payload, 'model) migration_plan = { migration_source_version : int ; migration_source_fingerprint : string ; migration_target_fingerprint : string ; migrate_snapshot : 'payload -> 'model ; validate_model : 'model -> string option }

type 'model migration_result =
  | MigrationApplied of 'model
  | MigrationRejected of string
  | MigrationRestartRequired of string

type 'target soft_restart_status =
  | SoftRestartApplied of 'target
  | SoftRestartRejected of string
  | SoftRestartRequired of string

type 'message generation_message = { message_generation : int ; message_fingerprint : string ; message_value : 'message }

type 'message message_drain = { compatible_messages : 'message Rrbvec.t ; discarded_message_count : int }

val capture : int -> string -> 'model -> ('model -> 'payload) -> 'payload snapshot_capture_result

val apply : ('payload, 'model) migration_plan -> 'payload model_snapshot -> 'model migration_result

val soft_restart_bang : 'model migration_result -> ('model -> 'target) -> ('target -> bool) -> ('target -> bool) -> (unit -> bool) -> 'target soft_restart_status

val drain_compatible : 'message generation_message Rrbvec.t -> int -> string -> 'message message_drain

