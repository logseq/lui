(* Generated from schema/components.json. Do not edit by hand. *)


open Lui_protocol

val node_kind_name : node_kind -> string
val standard_node_name : string -> bool
val property_name : property -> string
val kind_property_matrix : node_kind -> property list option
val kind_extra_properties : node_kind -> property list
val all_node_kinds : node_kind list
val all_properties : property list
