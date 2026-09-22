(* ns lui.wire *)

val escape_json : string -> string

val quoted : string -> string

val encode_value : wire_value -> string

val encode_op : patch_op -> string

val encode_ops : patch_op Rrbvec.t -> string

val encode_batch : patch_batch -> string

