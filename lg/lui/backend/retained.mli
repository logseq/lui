(* ns lui.backend.retained *)

type retained_semantic_kind =
  | StandardSemantic of node_kind
  | ExtensionSemantic of string * string

type 'platform retained_node = { platform_node : 'platform ; semantic_kind : retained_semantic_kind ; retained_parent : int option ; retained_properties : (property, wire_value) Lg_runtime.Runtime_map.t ; retained_extension_properties : (string, wire_value) Lg_runtime.Runtime_map.t ; retained_children : int Rrbvec.t }

type 'platform retained_store = { retained_nodes : (int, 'platform retained_node) Lg_runtime.Runtime_map.t ref ; retained_batches : patch_batch Rrbvec.t ref ; retained_generation : int ref }

val create_store : unit -> 'platform retained_store

val empty_batches : unit -> patch_batch Rrbvec.t

val find_child_index : int Rrbvec.t -> int -> int option

val remove_at : 'value Rrbvec.t -> int -> 'value Rrbvec.t

val insert_at : 'value Rrbvec.t -> int -> 'value -> 'value Rrbvec.t

val move_at : 'value Rrbvec.t -> int -> int -> 'value Rrbvec.t

val update_node : (int, 'platform retained_node) Lg_runtime.Runtime_map.t -> int -> 'platform retained_node -> (property, wire_value) Lg_runtime.Runtime_map.t -> (string, wire_value) Lg_runtime.Runtime_map.t -> int Rrbvec.t -> (int, 'platform retained_node) Lg_runtime.Runtime_map.t

val update_parent : (int, 'platform retained_node) Lg_runtime.Runtime_map.t -> int -> 'platform retained_node -> int option -> (int, 'platform retained_node) Lg_runtime.Runtime_map.t

val descendant_ : (int, 'platform retained_node) Lg_runtime.Runtime_map.t -> int -> int -> bool

val standard_kind : 'platform retained_node -> node_kind option

val extension_identity : 'platform retained_node -> (string * string) option

val standard_kind_ : 'platform retained_node -> node_kind -> bool

val extension_schema : extension_registry -> string -> extension_component_schema

val retained_child_supported_ : extension_registry -> (int, 'platform retained_node) Lg_runtime.Runtime_map.t -> 'platform retained_node -> 'platform retained_node -> bool

val unsupported_child_message : 'platform retained_node -> 'platform retained_node -> string

val apply_op_with_extensions : (int, 'platform retained_node) Lg_runtime.Runtime_map.t -> (node_kind -> 'platform) -> (int -> string -> 'platform) -> extension_registry -> patch_op -> (int, 'platform retained_node) Lg_runtime.Runtime_map.t

val unavailable_extension_platform : int -> string -> 'platform

val unavailable_standard_platform : node_kind -> 'platform

val has_ancestor_kind_ : (int, 'platform retained_node) Lg_runtime.Runtime_map.t -> int option -> node_kind -> bool

val apply_op : (int, 'platform retained_node) Lg_runtime.Runtime_map.t -> (node_kind -> 'platform) -> patch_op -> (int, 'platform retained_node) Lg_runtime.Runtime_map.t

val validate_nodes_bang : (int, 'platform retained_node) Lg_runtime.Runtime_map.t -> extension_registry -> bool

val apply_operations_with_extensions : (int, 'platform retained_node) Lg_runtime.Runtime_map.t -> (node_kind -> 'platform) -> (int -> string -> 'platform) -> extension_registry -> patch_batch -> (int, 'platform retained_node) Lg_runtime.Runtime_map.t

val apply_operations : (int, 'platform retained_node) Lg_runtime.Runtime_map.t -> (node_kind -> 'platform) -> patch_batch -> (int, 'platform retained_node) Lg_runtime.Runtime_map.t

val apply_batch_with_bang : 'platform retained_store -> (node_kind -> 'platform) -> (patch_batch -> bool) -> patch_batch -> bool

val commit_batch_bang : 'platform retained_store -> (node_kind -> 'platform) -> (int -> string -> 'platform) -> extension_registry -> (patch_batch -> bool) -> patch_batch -> bool

val apply_batch_with_extensions_bang : 'platform retained_store -> (node_kind -> 'platform) -> (int -> string -> 'platform) -> extension_registry -> (patch_batch -> bool) -> patch_batch -> bool

val apply_batch_bang : 'platform retained_store -> (node_kind -> 'platform) -> patch_batch -> bool

val apply_extension_batch_bang : 'platform retained_store -> (int -> string -> 'platform) -> extension_registry -> patch_batch -> bool

val node : 'platform retained_store -> int -> 'platform retained_node option

val nodes : 'platform retained_store -> (int, 'platform retained_node) Lg_runtime.Runtime_map.t

val platform_node : 'platform retained_store -> int -> 'platform option

val property : 'platform retained_store -> int -> property -> wire_value option

val extension_identifier : 'platform retained_store -> int -> string option

val extension_property : 'platform retained_store -> int -> string -> wire_value option

val children : 'platform retained_store -> int -> int Rrbvec.t

val node_count : 'platform retained_store -> int

val batches : 'platform retained_store -> patch_batch Rrbvec.t

val generation : 'platform retained_store -> int

