(* LUI web (DOM) backend — public API. *)

open Lui_protocol
open Lui_web_types

val create_with_extensions :
  web_node ->
  string String_map.t ->
  Lui_extension.extension_registry ->
  web_extension_adapter String_map.t ->
  web_renderer

val create_simulator_with_extensions :
  web_node ->
  operating_system ->
  string String_map.t ->
  Lui_extension.extension_registry ->
  web_extension_adapter String_map.t ->
  web_renderer

val create_simulator :
  ?app_icons:string String_map.t -> web_node -> operating_system -> web_renderer

val create : ?app_icons:string String_map.t -> web_node -> web_renderer

val set_event_handler : web_renderer -> (event -> bool) -> bool

val extension_adapter : web_renderer -> string -> web_extension_adapter
val extension_platform_node : web_renderer -> int -> string -> web_node
val apply_extension_property :
  web_renderer -> int -> string -> wire_value -> unit
val remove_extension_property : web_renderer -> int -> string -> unit
val cleanup_extension_node :
  web_renderer -> (int, web_node retained_node) Hashtbl.t -> int -> unit

val backend : web_renderer -> backend
val mount : web_renderer -> int -> web_node -> unit
val root_sections : web_renderer -> int -> root_section list

val some_node : web_node -> web_node option
val node : web_renderer -> int -> web_node option
val property : web_renderer -> int -> property -> wire_value option
val children : web_renderer -> int -> int list
val node_count : web_renderer -> int
val batches : web_renderer -> patch_batch list
