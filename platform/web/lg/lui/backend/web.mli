(* ns lui.backend.web *)

type web_node = Dom.element

type web_extension_adapter = { web_extension_create : int -> Dom.document -> (string -> (string, wire_value) Lg_runtime.Runtime_map.t -> unit) -> web_node ; web_extension_set_property : web_node -> string -> wire_value -> unit ; web_extension_remove_property : web_node -> string -> unit ; web_extension_cleanup : web_node -> unit }

type web_image_resource = { web_image_url : string ; web_image_width : float ; web_image_height : float }

type web_split_state = { web_split_source : float ; web_split_current : float }

type root_section = { root_section_node : int ; root_section_title : string }

type web_simulator_form_factor =
  | SimulatorPhone
  | SimulatorTablet

type web_simulator_orientation =
  | SimulatorPortrait
  | SimulatorLandscape

type web_simulator_pointer =
  | SimulatorTouch
  | SimulatorHybrid

type web_simulator_device = { simulator_device_platform : operating_system ; simulator_device_form_factor : web_simulator_form_factor ; simulator_device_orientation : web_simulator_orientation ; simulator_device_pointer : web_simulator_pointer ; simulator_device_width : int ; simulator_device_height : int ; simulator_device_scale : float ; simulator_device_safe_top : int ; simulator_device_safe_right : int ; simulator_device_safe_bottom : int ; simulator_device_safe_left : int ; simulator_device_keyboard_height : int }

type web_renderer = { web_store : web_node retained_store ; web_document : Dom.document ; web_host : web_node ; web_portal_root : web_node ; web_simulator_platform : operating_system option ref ; web_simulator_device : web_simulator_device option ref ; web_simulator_keyboard_visible : bool ref ; web_toast_viewport : web_node ; web_event_handler : (event -> bool) ref ; web_app_icons : (string, string) Lg_runtime.Runtime_map.t ; web_images : (int, web_image_resource) Lg_runtime.Runtime_map.t ref ; web_media_surfaces : (int, web_image_resource) Lg_runtime.Runtime_map.t ref ; web_cleanups : (int, (unit -> unit)) Lg_runtime.Runtime_map.t ref ; web_modal_stack : int Rrbvec.t ref ; web_modal_return_focus : web_node option ref ; web_open_tooltip : int option ref ; web_tooltip_warm : bool ref ; web_open_context_menu : int option ref ; web_splits : (int, web_split_state) Lg_runtime.Runtime_map.t ref ; web_extension_registry : extension_registry ; web_extension_adapters : (string, web_extension_adapter) Lg_runtime.Runtime_map.t }

val create : (Dom.element -> web_renderer) * ((Dom.element -> (string, string) Lg_runtime.Runtime_map.t -> web_renderer) * unit)

val create_with_extensions : Dom.element -> (string, string) Lg_runtime.Runtime_map.t -> extension_registry -> (string, web_extension_adapter) Lg_runtime.Runtime_map.t -> web_renderer

val create_simulator : (Dom.element -> operating_system -> web_renderer) * ((Dom.element -> operating_system -> (string, string) Lg_runtime.Runtime_map.t -> web_renderer) * unit)

val create_simulator_with_extensions : Dom.element -> operating_system -> (string, string) Lg_runtime.Runtime_map.t -> extension_registry -> (string, web_extension_adapter) Lg_runtime.Runtime_map.t -> web_renderer

val simulator_platform_name : operating_system -> string

val simulator_form_factor_name : web_simulator_form_factor -> string

val simulator_orientation_name : web_simulator_orientation -> string

val simulator_pointer_name : web_simulator_pointer -> string

val simulator_device : operating_system -> web_simulator_form_factor -> web_simulator_orientation -> web_simulator_device

val set_simulator_device_bang : web_renderer -> web_simulator_device -> bool

val set_simulator_form_factor_bang : web_renderer -> web_simulator_form_factor -> bool

val rotate_simulator_bang : web_renderer -> bool

val set_simulator_keyboard_visible_bang : web_renderer -> bool -> bool

val set_simulator_platform_bang : web_renderer -> operating_system -> bool

val apply_simulator_device_to_scope_bang : web_node -> web_simulator_device -> bool -> unit

val simulator_text_entry_ : web_node -> bool

val compact_sheet_ : web_renderer -> bool

val attach_simulator_keyboard_events_bang : web_renderer -> bool

val pointer_mouse_event : Dom._baseClass Dom.event_like -> Dom.mouseEvent

val pointer_type : Dom._baseClass Dom.event_like -> string

val pointer_id : Dom._baseClass Dom.event_like -> int

val standard_kind : 'platform retained_node -> node_kind

val standard_kind_ : 'platform retained_node -> node_kind -> bool

val extension_adapter : web_renderer -> string -> web_extension_adapter

val extension_platform_node : web_renderer -> int -> string -> web_node

val apply_extension_property_bang : web_renderer -> int -> string -> wire_value -> unit

val remove_extension_property_bang : web_renderer -> int -> string -> unit

val cleanup_extension_node_bang : web_renderer -> (int, web_node retained_node) Lg_runtime.Runtime_map.t -> int -> unit

val set_event_handler_bang : web_renderer -> (event -> bool) -> bool

val create_dropdown_node : web_renderer -> web_node

val dropdown_node_ : (int, web_node retained_node) Lg_runtime.Runtime_map.t -> int -> bool

val modal_node_ : (int, web_node retained_node) Lg_runtime.Runtime_map.t -> int -> bool

val toast_node_ : (int, web_node retained_node) Lg_runtime.Runtime_map.t -> int -> bool

val modal_layer_node : web_node -> web_node

val anchored_tooltip_ : web_node retained_node -> bool

val anchored_tooltip_node_ : (int, web_node retained_node) Lg_runtime.Runtime_map.t -> int -> bool

val dropdown_anchor_node : web_renderer -> int -> web_node

val dropdown_side : web_node -> string

val dropdown_offset : web_renderer -> int -> float

val dropdown_listbox_ : web_renderer -> int -> bool

val position_dropdown_bang : web_renderer -> int -> unit

val point_in_triangle_ : float -> float -> float -> float -> float -> float -> float -> float -> bool

val submenu_corridor_ : web_node -> web_node -> float -> float -> float -> float -> bool

val set_dropdown_open_bang : web_renderer -> int -> bool -> unit

val mount_dropdown_bang : web_renderer -> int -> unit

val refresh_modal_host_inert_bang : web_renderer -> bool

val tooltip_delay : web_renderer -> int -> int

val clamp_popup_axis : float -> float -> float -> float

val resolved_popup_side : string -> Dom.domRect -> float -> float -> float -> float -> float -> string

val position_anchored_bang : Dom.document -> web_node -> web_node -> Dom.domRect -> string -> string -> float -> unit

val position_tooltip_bang : web_renderer -> int -> unit

val set_tooltip_open_bang : web_renderer -> int -> bool -> unit

val mount_tooltip_bang : web_renderer -> int -> web_node -> unit

val toast_duration : web_renderer -> int -> int

val first_toast_node_ : web_renderer -> web_node -> bool

val mount_toast_bang : web_renderer -> int -> web_node -> unit

val refresh_horizontal_group_roving_bang : web_renderer -> int -> node_kind -> bool

val update_all_horizontal_group_roving_bang : web_renderer -> bool

val register_image_bang : web_renderer -> int -> string -> float -> float -> bool

val unregister_image_bang : web_renderer -> int -> bool

val present_media_surface_frame_bang : web_renderer -> int -> string -> float -> float -> bool

val unregister_media_surface_bang : web_renderer -> int -> bool

val avatar_float : web_renderer -> int -> property -> float -> float

val registered_avatar_image : web_renderer -> int -> web_image_resource option

val media_size : web_renderer -> int -> property -> float -> float

val registered_image : web_renderer -> int -> web_image_resource option

val update_avatar_bang : web_renderer -> int -> web_node -> unit

val refresh_image_id_bang : web_renderer -> int -> bool

val update_image_bang : web_renderer -> int -> web_node -> unit

val update_media_surface_bang : web_renderer -> int -> web_node -> unit

val refresh_media_surface_id_bang : web_renderer -> int -> bool

val platform_node : web_renderer -> node_kind -> web_node

val create_split_node : web_renderer -> web_node

val create_step_node : web_renderer -> web_node

val create_timeline_item_node : web_renderer -> web_node

val create_bottom_tabs_node : web_renderer -> web_node

val dom_node : web_renderer -> int -> web_node

val dom_node_before : web_renderer -> (int, web_node retained_node) Lg_runtime.Runtime_map.t -> int -> web_node

val attach_events_bang : web_renderer -> int -> node_kind -> web_node -> unit

val attach_modal_events_bang : web_renderer -> int -> web_node -> unit

val attach_text_events_bang : web_renderer -> int -> node_kind -> web_node -> unit

val attach_toggle_event_bang : web_renderer -> int -> node_kind -> web_node -> unit

val attach_radio_event_bang : web_renderer -> int -> web_node -> unit

val attach_slider_event_bang : web_renderer -> int -> web_node -> unit

val attach_split_events_bang : web_renderer -> int -> web_node -> unit

val attach_picker_press_event_bang : web_renderer -> int -> web_node -> unit

val attach_picker_trigger_events_bang : web_renderer -> int -> web_node -> unit

val attach_accordion_event_bang : web_renderer -> int -> web_node -> unit

val attach_pressable_text_events_bang : web_renderer -> int -> web_node -> unit

val event_capability_ : web_renderer -> int -> property -> bool

val treeitem_ : web_renderer -> int -> bool

val tree_ancestor : web_renderer -> int -> int option

val tree_items_under : web_renderer -> int -> int Rrbvec.t

val tree_focus_items_under : web_renderer -> int -> int Rrbvec.t

val derived_tree_item_level : web_renderer -> int -> int -> int -> int

val tree_item_level : web_renderer -> int -> int -> int

val update_tree_roving_bang : web_renderer -> int -> unit

val refresh_tree_item_accessibility_bang : web_renderer -> int -> int -> unit

val update_all_tree_roving_bang : web_renderer -> bool

val dispatch_tree_selection_bang : web_renderer -> int -> unit

val attach_tree_item_events_bang : web_renderer -> int -> node_kind -> web_node -> unit

val attach_list_item_events_bang : web_renderer -> int -> web_node -> unit

val horizontal_group_child_ : node_kind -> node_kind -> bool

val enabled_node_ : web_renderer -> int -> bool

val horizontal_focus_children : web_renderer -> int -> node_kind -> int Rrbvec.t

val focused_child_index : web_renderer -> int Rrbvec.t -> Dom.element -> int -> int option

val horizontal_focus_index : string -> int option -> int -> int option

val attach_horizontal_focus_bang : web_renderer -> int -> node_kind -> web_node -> unit

val toolbar_item_kind_ : node_kind -> bool

val toolbar_all_items_under : web_renderer -> int -> int Rrbvec.t

val toolbar_items_under : web_renderer -> int -> int Rrbvec.t

val refresh_toolbar_roving_bang : web_renderer -> int -> bool

val update_all_toolbar_roving_bang : web_renderer -> bool

val attach_toolbar_events_bang : web_renderer -> int -> web_node -> unit

val attach_dropdown_events_bang : web_renderer -> int -> web_node -> unit

val direct_dropdown_menu : web_renderer -> int -> int option

val context_menu_focus_items : web_renderer -> int -> int Rrbvec.t

val focus_context_menu_item_bang : web_renderer -> int -> int -> unit

val cleanup_node_bang : web_renderer -> int -> unit

val set_state_attribute_bang : web_node -> string -> bool -> unit

val web_color_value : string -> string

val update_icon_name_bang : web_renderer -> web_node -> string -> unit

val bottom_tab_trigger_id : int -> string

val bottom_tabs_pages_node : web_node -> web_node

val bottom_tabs_bar_node : web_node -> web_node

val bottom_tab_trigger : web_renderer -> int -> web_node option

val bottom_tab_string_property : web_renderer -> int -> property -> string

val refresh_bottom_tabs_bang : web_renderer -> int -> unit

val create_bottom_tab_trigger_bang : web_renderer -> int -> int -> int -> web_node

val refresh_node_class_bang : web_renderer -> int -> node_kind -> web_node -> unit

val apply_property_bang : web_renderer -> int -> node_kind -> web_node -> property -> wire_value -> unit

val progress_float : web_renderer -> int -> float

val update_progress_bang : web_renderer -> int -> web_node -> unit

val string_property : web_renderer -> int -> property -> string

val update_stepper_bang : web_renderer -> int -> unit

val update_stepper_parent_bang : web_renderer -> int -> unit

val update_timeline_bang : web_renderer -> int -> unit

val set_optional_text_bang : web_node -> string -> unit

val update_timeline_indicator_bang : web_renderer -> int -> web_node -> unit

val split_base_fraction : float -> float

val split_int_property : web_renderer -> int -> property -> int -> int

val split_child_minimum : web_renderer -> int -> int -> int

val split_timing_function : web_renderer -> int -> string

val effective_split_fraction : web_renderer -> int -> float -> float

val render_split_bang : web_renderer -> int -> web_node -> float -> bool -> unit

val reconcile_split_bang : web_renderer -> int -> web_node -> float -> unit

val update_split_bang : web_renderer -> int -> unit

val update_splits_under_bang : web_renderer -> int -> unit

val insert_dom_child_bang : web_node -> web_node -> int -> unit

val content_container : node_kind -> web_node -> web_node

val radio_group_ancestor : web_renderer -> int -> int option

val update_radio_group_bang : web_renderer -> int -> unit

val refresh_structured_children_bang : web_renderer -> int -> unit

val apply_dom_op_bang : web_renderer -> (int, web_node retained_node) Lg_runtime.Runtime_map.t -> patch_op -> unit

val apply_dom_batch_bang : web_renderer -> (int, web_node retained_node) Lg_runtime.Runtime_map.t -> patch_batch -> unit

val backend : web_renderer -> backend

val mount_bang : web_renderer -> int -> Dom.element -> unit

val root_sections : web_renderer -> int -> root_section Rrbvec.t

val some_node : web_node -> web_node option

val node : web_renderer -> int -> web_node option

val property : web_renderer -> int -> property -> wire_value option

val children : web_renderer -> int -> int Rrbvec.t

val node_count : web_renderer -> int

val batches : web_renderer -> patch_batch Rrbvec.t

