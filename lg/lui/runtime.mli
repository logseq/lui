(* ns lui.runtime *)

type event_handler = { handler_id : int ; handler_callback : event -> bool }

type dynamic_segment = { dynamic_segment_id : int ; dynamic_segment_parent : int ; dynamic_segment_base : int ref ; dynamic_segment_size : int ref ; dynamic_segment_active : bool ref }

type flush_status =
  | NotFlushed
  | NoBatch
  | Applied
  | Rejected

type flush_diagnostics = { flush_status : flush_status ; flush_generation : int ; flush_operation_count : int ; flush_pending_operation_count : int ; flush_mounted_node_count : int ; flush_handler_count : int ; flush_dynamic_segment_count : int ; flush_signal_generation : int ; flush_signal_round_count : int ; flush_signal_effect_count : int ; flush_signal_dirty_task_count : int }

type runtime_checkpoint = { checkpoint_generation : int ; checkpoint_next_node_id : int ; checkpoint_mounted_nodes : (int, node_kind) Lg_runtime.Runtime_map.t ; checkpoint_extension_nodes : (int, string) Lg_runtime.Runtime_map.t ; checkpoint_properties : (int, (property, wire_value) Lg_runtime.Runtime_map.t) Lg_runtime.Runtime_map.t ; checkpoint_extension_properties : (int, (string, wire_value) Lg_runtime.Runtime_map.t) Lg_runtime.Runtime_map.t ; checkpoint_children : (int, int Rrbvec.t) Lg_runtime.Runtime_map.t ; checkpoint_parents : (int, int) Lg_runtime.Runtime_map.t ; checkpoint_pending_ops : patch_op Rrbvec.t ; checkpoint_next_handler_id : int ; checkpoint_event_handlers : (int, event_handler Rrbvec.t) Lg_runtime.Runtime_map.t ; checkpoint_next_dynamic_segment_id : int ; checkpoint_dynamic_segments : (int, dynamic_segment Rrbvec.t) Lg_runtime.Runtime_map.t ; checkpoint_reload_keys : (int, string) Lg_runtime.Runtime_map.t ; checkpoint_node_aliases : (int, int) Lg_runtime.Runtime_map.t ; checkpoint_handler_count : int ; checkpoint_dynamic_segment_count : int ; checkpoint_extension_dirty : bool }

type render_tree_snapshot = { render_mounted_nodes : (int, node_kind) Lg_runtime.Runtime_map.t ; render_extension_nodes : (int, string) Lg_runtime.Runtime_map.t ; render_properties : (int, (property, wire_value) Lg_runtime.Runtime_map.t) Lg_runtime.Runtime_map.t ; render_extension_properties : (int, (string, wire_value) Lg_runtime.Runtime_map.t) Lg_runtime.Runtime_map.t ; render_children : (int, int Rrbvec.t) Lg_runtime.Runtime_map.t ; render_reload_keys : (int, string) Lg_runtime.Runtime_map.t }

type application = { runtime_scheduler : scheduler ; runtime_backend : backend ; runtime_extension_registry : extension_registry ; next_node_id : int ref ; mounted_nodes : (int, node_kind) Lg_runtime.Runtime_map.t ref ; runtime_extension_nodes : (int, string) Lg_runtime.Runtime_map.t ref ; runtime_properties : (int, (property, wire_value) Lg_runtime.Runtime_map.t) Lg_runtime.Runtime_map.t ref ; runtime_extension_properties : (int, (string, wire_value) Lg_runtime.Runtime_map.t) Lg_runtime.Runtime_map.t ref ; runtime_children : (int, int Rrbvec.t) Lg_runtime.Runtime_map.t ref ; runtime_parents : (int, int) Lg_runtime.Runtime_map.t ref ; pending_ops : patch_op Rrbvec.t ref ; runtime_generation : int ref ; runtime_diagnostics : flush_diagnostics ref ; next_handler_id : int ref ; event_handlers : (int, event_handler Rrbvec.t) Lg_runtime.Runtime_map.t ref ; next_dynamic_segment_id : int ref ; dynamic_segments : (int, dynamic_segment Rrbvec.t) Lg_runtime.Runtime_map.t ref ; runtime_reload_keys : (int, string) Lg_runtime.Runtime_map.t ref ; runtime_node_aliases : (int, int) Lg_runtime.Runtime_map.t ref ; runtime_handler_count : int ref ; runtime_dynamic_segment_count : int ref ; runtime_extension_dirty : bool ref }

val create : scheduler -> backend -> application

val create_with_extensions : scheduler -> backend -> extension_registry -> application

val checkpoint : application -> runtime_checkpoint

val render_tree_snapshot : application -> render_tree_snapshot

val restore_bang : application -> runtime_checkpoint -> bool

val reconcile_subtree_bang : application -> runtime_checkpoint -> int -> int -> int -> int

val map_node : (int, int) Lg_runtime.Runtime_map.t -> int -> int

val node_compatible_ : application -> runtime_checkpoint -> int -> int -> bool

val keyed_children : int Rrbvec.t -> (int, string) Lg_runtime.Runtime_map.t -> (string, int) Lg_runtime.Runtime_map.t

val collect_node_mapping : application -> runtime_checkpoint -> int -> int -> (int, int) Lg_runtime.Runtime_map.t -> (int, int) Lg_runtime.Runtime_map.t

val collect_subtree_nodes : (int, int Rrbvec.t) Lg_runtime.Runtime_map.t -> int -> int Rrbvec.t

val retire_checkpoint_dynamic_segments_bang : runtime_checkpoint -> int -> bool

val remove_node_keys : (int, 'value) Lg_runtime.Runtime_map.t -> int Rrbvec.t -> (int, 'value) Lg_runtime.Runtime_map.t

val remap_node_values : (int, 'value) Lg_runtime.Runtime_map.t -> int Rrbvec.t -> (int, int) Lg_runtime.Runtime_map.t -> (int, 'value) Lg_runtime.Runtime_map.t -> (int, 'value) Lg_runtime.Runtime_map.t

val remap_children : (int, int Rrbvec.t) Lg_runtime.Runtime_map.t -> int Rrbvec.t -> (int, int) Lg_runtime.Runtime_map.t -> (int, int Rrbvec.t) Lg_runtime.Runtime_map.t -> (int, int Rrbvec.t) Lg_runtime.Runtime_map.t

val rebuild_parents : (int, int Rrbvec.t) Lg_runtime.Runtime_map.t -> (int, int) Lg_runtime.Runtime_map.t

val index_map : int Rrbvec.t -> (int, int) Lg_runtime.Runtime_map.t

val shift_right : int Rrbvec.t -> (int, int) Lg_runtime.Runtime_map.t -> int -> int -> int -> (int Rrbvec.t * (int, int) Lg_runtime.Runtime_map.t)

val emit_child_diff_bang : application -> int -> int Rrbvec.t -> int Rrbvec.t -> bool

val emit_dropped_subtree_bang : application -> runtime_checkpoint -> (int, bool) Lg_runtime.Runtime_map.t -> int -> bool

val emit_property_diff_bang : application -> int -> (property, wire_value) Lg_runtime.Runtime_map.t -> (property, wire_value) Lg_runtime.Runtime_map.t -> bool

val emit_extension_property_diff_bang : application -> int -> (string, wire_value) Lg_runtime.Runtime_map.t -> (string, wire_value) Lg_runtime.Runtime_map.t -> bool

val empty_ops : unit -> patch_op Rrbvec.t

val empty_handlers : unit -> event_handler Rrbvec.t

val empty_dynamic_segments : unit -> (int, dynamic_segment Rrbvec.t) Lg_runtime.Runtime_map.t

val empty_extension_nodes : unit -> (int, string) Lg_runtime.Runtime_map.t

val empty_extension_properties : unit -> (int, (string, wire_value) Lg_runtime.Runtime_map.t) Lg_runtime.Runtime_map.t

val enqueue_bang : application -> patch_op -> bool

val find_child_index : int Rrbvec.t -> int -> int option

val remove_at : int Rrbvec.t -> int -> int Rrbvec.t

val insert_at : int Rrbvec.t -> int -> int -> int Rrbvec.t

val move_at : int Rrbvec.t -> int -> int -> int Rrbvec.t

val descendant_ : application -> int -> int -> bool

val extension_identifier : application -> int -> string option

val require_extension_schema : application -> int -> extension_component_schema

val require_node_bang : application -> int -> bool

val create_node_bang : application -> node_kind -> int

val create_extension_node_bang : application -> string -> int

val create_tweak_node_bang : application -> string -> int

val set_reload_key_bang : application -> int -> string -> bool

val drop_node_bang : application -> int -> bool

val drop_subtree_bang : application -> int -> bool

val set_prop_bang : application -> int -> property -> wire_value -> bool

val remove_prop_bang : application -> int -> property -> bool

val set_extension_prop_bang : application -> int -> string -> wire_value -> bool

val remove_extension_prop_bang : application -> int -> string -> bool

val standard_extension_container_ : node_kind -> bool

val identifier_allowed_ : string Rrbvec.t -> string -> bool

val child_supported_ : application -> int -> int -> bool

val insert_child_bang : application -> int -> int -> int -> bool

val remove_child_bang : application -> int -> int -> bool

val move_child_bang : application -> int -> int -> int -> bool

val bind_prop_bang : scope -> application -> int -> property -> wire_value signal -> subscription

val bind_extension_prop_bang : scope -> application -> int -> string -> wire_value signal -> subscription

val on_event_bang : scope -> application -> int -> (event -> bool) -> bool

val remove_handler_bang : application -> int -> int -> bool

val dispatch_bang : application -> event -> bool

val validate_extension_nodes_bang : application -> bool

val handler_count : application -> int

val dynamic_segment_count : application -> int

val record_diagnostics_bang : application -> flush_status -> int -> int -> bool

val apply_pending_batch_bang : application -> patch_batch -> int -> int -> bool

val flush_bang : application -> bool

val diagnostics : application -> flush_diagnostics

val generation : application -> int

val mounted_count : application -> int

val child_count : application -> int -> int

val children : application -> int -> int Rrbvec.t

val find_dynamic_segment_index : dynamic_segment Rrbvec.t -> int -> int option

val register_dynamic_segment_bang : application -> int -> dynamic_segment

val dynamic_segment_index : dynamic_segment -> int -> int

val dynamic_segment_insert_index : dynamic_segment -> int -> int

val resize_dynamic_segment_bang : application -> dynamic_segment -> int -> bool

val unregister_dynamic_segment_bang : application -> dynamic_segment -> bool

