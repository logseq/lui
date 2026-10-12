(* Retained mirror of LUI patch batches for the native backend. *)

type node
type t

val create : unit -> t
val node_count : t -> int
val generation : t -> int
val revision : t -> int

(** {1 Typed dirty tracking} *)

type dirty_mask = int

val d_structure : dirty_mask (* produced child set/order changed *)
val d_layout : dirty_mask (* own flex style or measure inputs changed *)
val d_paint : dirty_mask (* scene ops changed *)
val d_semantics : dirty_mask (* a11y tree *)
val d_input : dirty_mask (* focus/selection/interactive state *)
val d_layout_kids : dirty_mask
(* a prop that rewrites the styles or order of the node's produced
   children (grid [columns], split [value], edge-inset [edge]) *)
val d_all : dirty_mask

val mask_has : dirty_mask -> dirty_mask -> bool

(** [mask_of_prop name] classifies a wire prop name into the stages it
    feeds. Unknown names return the conservative layout|paint default. *)
val mask_of_prop : string -> dirty_mask

(** Bumped by every op that can move geometry (structure, layout or
    layout-kids masks). Pure paint churn leaves it untouched — the
    layout memo keys on it so a background flip never rebuilds the
    flex mirror. *)
val layout_rev : t -> int

(** [changes_since t rev] replays the ops applied after store revision
    [rev], oldest first, or [None] when the bounded journal no longer
    reaches that far back (consumer must resync wholesale). *)
val changes_since : t -> int -> Lui_protocol.patch_op list option

val find_opt : t -> int -> node option
val mem : t -> int -> bool
val node_id : node -> int
val node_kind : node -> string
val node_ext_id : node -> string option
val node_parent : node -> int option
val node_children : node -> int list
val node_prop : node -> string -> Lui_protocol.wire_value option
val node_revision : node -> int
val node_child_count : node -> int

val apply_batch : t -> Lui_protocol.patch_batch -> unit
val apply_op : t -> Lui_protocol.patch_op -> unit

(* Incremental invalidation: ids touched since the last drain,
   sorted ascending. A drop marks the removed id and its old parent. *)
val drain_dirty : t -> int list

(** Same drain, with the OR-ed mask of everything that touched the id. *)
val drain_dirty_masked : t -> (int * dirty_mask) list

val peek_dirty : t -> int -> bool

(** [peek_dirty_mask t id] is the pending mask for [id] (0 when clean). *)
val peek_dirty_mask : t -> int -> dirty_mask

val kind : t -> int -> string

(** Editable text kinds have an intrinsic line height even when empty. *)
val is_editable_text_kind : string -> bool

val ext_id : t -> int -> string option
val parent : t -> int -> int option
val children : t -> int -> node list
val child_ids : t -> int -> int list
val last_child_id : t -> int -> int option
val child_count : t -> int -> int
val prop : t -> int -> string -> Lui_protocol.wire_value option
val bool_prop : t -> int -> string -> bool
val string_prop : t -> int -> string -> string option
val float_prop : t -> int -> string -> float option
val int_prop : t -> int -> string -> int option
val depth : t -> int -> int
val root_ids : t -> int list
val preorder : ?root:int -> t -> int list
val all_nodes : t -> node list
