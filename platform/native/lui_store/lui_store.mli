(* Retained mirror of LUI patch batches for the native backend. *)

type node
type t

val create : unit -> t
val node_count : t -> int
val generation : t -> int
val revision : t -> int

val find_opt : t -> int -> node option
val mem : t -> int -> bool
val node_id : node -> int
val node_kind : node -> string
val node_ext_id : node -> string option
val node_parent : node -> int option
val node_children : node -> int list
val node_prop : node -> string -> Lui_protocol.wire_value option
val node_revision : node -> int

val apply_batch : t -> Lui_protocol.patch_batch -> unit
val apply_op : t -> Lui_protocol.patch_op -> unit

(* Incremental invalidation: ids touched since the last drain,
   sorted ascending. A drop marks the removed id and its old parent. *)
val drain_dirty : t -> int list
val peek_dirty : t -> int -> bool

val kind : t -> int -> string
val ext_id : t -> int -> string option
val parent : t -> int -> int option
val children : t -> int -> node list
val child_ids : t -> int -> int list
val prop : t -> int -> string -> Lui_protocol.wire_value option
val bool_prop : t -> int -> string -> bool
val string_prop : t -> int -> string -> string option
val float_prop : t -> int -> string -> float option
val int_prop : t -> int -> string -> int option
val depth : t -> int -> int
val root_ids : t -> int list
val preorder : ?root:int -> t -> int list
val all_nodes : t -> node list
