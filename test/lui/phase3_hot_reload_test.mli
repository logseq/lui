(* ns lui.phase3-hot-reload-test *)

type migrated_counter = { counter_value : int ; counter_label : string }

val migrate_counter : int -> migrated_counter

val validate_counter : migrated_counter -> string option

val apply_counter : (int, migrated_counter) migration_plan -> int model_snapshot -> migrated_counter migration_result

