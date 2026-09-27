(* Shared types for the LUI web (DOM) backend. *)

open Lui_protocol

type web_node = Dom.element

(** JS-side adapter for extension components. [web_extension_create node_id
    document emit] builds the host element; [emit name payload] forwards an
    extension event back into the LUI runtime. *)
type web_extension_adapter = {
  web_extension_create :
    int -> Dom.document -> (string -> wire_value String_map.t -> unit) -> web_node;
  web_extension_set_property : web_node -> string -> wire_value -> unit;
  web_extension_remove_property : web_node -> string -> unit;
  web_extension_cleanup : web_node -> unit;
}

type web_image_resource = {
  web_image_url : string;
  web_image_width : float;
  web_image_height : float;
}

type web_split_state = {
  web_split_source : float;
  web_split_current : float;
}

type root_section = {
  root_section_node : int;
  root_section_title : string;
}

type web_simulator_form_factor =
  | SimulatorPhone
  | SimulatorTablet

type web_simulator_orientation =
  | SimulatorPortrait
  | SimulatorLandscape

type web_simulator_pointer =
  | SimulatorTouch
  | SimulatorHybrid

type web_simulator_device = {
  simulator_device_platform : operating_system;
  simulator_device_form_factor : web_simulator_form_factor;
  simulator_device_orientation : web_simulator_orientation;
  simulator_device_pointer : web_simulator_pointer;
  simulator_device_width : int;
  simulator_device_height : int;
  simulator_device_scale : float;
  simulator_device_safe_top : int;
  simulator_device_safe_right : int;
  simulator_device_safe_bottom : int;
  simulator_device_safe_left : int;
  simulator_device_keyboard_height : int;
}

(** What a retained node semantically is: either a standard LUI element or an
    extension node carrying its identifier and the schema fingerprint it was
    created with. *)
type semantic_kind =
  | StandardSemantic of node_kind
  | ExtensionSemantic of string * string

(** Backend-side mirror of a runtime node. Properties live in the runtime's
    own persistent maps so updates stay cheap and snapshot-friendly. *)
type 'platform retained_node = {
  platform_node : 'platform;
  semantic_kind : semantic_kind;
  mutable retained_parent : int option;
  mutable retained_properties : wire_value Property_map.t;
  mutable retained_extension_properties : wire_value String_map.t;
  mutable retained_children : int list;
}

(** Mirror of the runtime tree plus the history needed for generation checks
    and query APIs. Node records are updated functionally (the table entry is
    replaced); the table itself is mutable. *)
type 'platform retained_store = {
  retained_nodes : (int, 'platform retained_node) Hashtbl.t;
  mutable retained_batches : patch_batch list;
  mutable retained_generation : int;
}

type web_renderer = {
  web_store : web_node retained_store;
  web_document : Dom.document;
  web_host : web_node;
  web_portal_root : web_node;
  web_simulator_platform : operating_system option ref;
  web_simulator_device : web_simulator_device option ref;
  web_simulator_keyboard_visible : bool ref;
  web_toast_viewport : web_node;
  web_event_handler : (event -> bool) ref;
  web_app_icons : string String_map.t;
  web_images : (int, web_image_resource) Hashtbl.t;
  web_media_surfaces : (int, web_image_resource) Hashtbl.t;
  web_cleanups : (int, unit -> unit) Hashtbl.t;
  web_modal_stack : int list ref;
  web_modal_return_focus : web_node option ref;
  web_open_tooltip : int option ref;
  web_tooltip_warm : bool ref;
  web_open_context_menu : int option ref;
  web_splits : (int, web_split_state) Hashtbl.t;
  web_extension_registry : Lui_extension.extension_registry;
  web_extension_adapters : (string, web_extension_adapter) Hashtbl.t;
}
