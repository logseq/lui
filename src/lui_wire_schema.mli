(* Generated from schema/components.json. Do not edit by hand. *)


open Lui_protocol

val node_kind_name : node_kind -> string
val standard_node_name : string -> bool
val property_name : property -> string
val kind_property_matrix : node_kind -> property list option
val kind_extra_properties : node_kind -> property list
val all_node_kinds : node_kind list
val all_properties : property list


type view_value =
  | ViewString | ViewBool | ViewInt | ViewFloat
  | ViewEnum of string list
  | ViewIcon of string list
  | ViewToken | ViewAttributes | ViewFloatTuple of int

type view_children = ViewList of string | ViewArguments of string list

type 'property view_contract = {
  view_result : string;
  view_children : view_children;
  view_properties : ('property * view_value * bool) list;
  view_events : string list;
  view_slots : (string * string * bool) list;
}

val view_contract : node_kind -> property view_contract option
val extension_view_contract : string -> string view_contract option
