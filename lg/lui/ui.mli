(* ns lui.ui *)

type ui_context = { ui_application : application ; ui_scheduler : scheduler ; ui_scope : scope ; ui_state_scope : scope ; ui_state_scopes : (string, scope) Lg_runtime.Runtime_map.t ref ; ui_active_state_paths : (string, bool) Lg_runtime.Runtime_map.t ref ; ui_state_path : string ; ui_profile : platform_profile }

val context : application -> scope -> ui_context

val make_context : application -> scope -> scope -> (string, scope) Lg_runtime.Runtime_map.t ref -> (string, bool) Lg_runtime.Runtime_map.t ref -> string -> ui_context

val context_with_state_scope : application -> scope -> scope -> ui_context

val context_with_state_registry : application -> scope -> scope -> (string, scope) Lg_runtime.Runtime_map.t ref -> (string, bool) Lg_runtime.Runtime_map.t ref -> ui_context

val child_context : ui_context -> string -> ui_context

val profile : ui_context -> platform_profile

val platform : ui_context -> operating_system

val host : ui_context -> host_kind

val extension_bang : ui_context -> string -> int

val platform_tweak_bang : ui_context -> string -> int

val key_bang : ui_context -> int -> string -> bool

val extension_property_bang : ui_context -> int -> string -> wire_value -> bool

val extension_property_signal_bang : ui_context -> int -> string -> wire_value signal -> bool

val row_bang : ui_context -> int

val column_bang : ui_context -> int

val grid_bang : ui_context -> int

val stack_bang : ui_context -> int

val panel_bang : ui_context -> int

val card_bang : ui_context -> int

val alert_bang : ui_context -> int

val bubble_bang : ui_context -> int

val box_bang : ui_context -> int

val scroll_bang : ui_context -> int

val list_bang : ui_context -> int

val virtual_list_bang : ui_context -> int

val tabs_bang : ui_context -> int

val bottom_tabs_bang : ui_context -> int

val bottom_tab_bang : ui_context -> int

val button_group_bang : ui_context -> int

val toggle_group_bang : ui_context -> int

val breadcrumb_bang : ui_context -> int

val pagination_bang : ui_context -> int

val table_bang : ui_context -> int

val table_row_bang : ui_context -> int

val table_cell_bang : ui_context -> int

val tree_bang : ui_context -> int

val resizable_bang : ui_context -> int

val split_bang : ui_context -> float signal -> int

val split_literal_bang : ui_context -> float -> int

val drawer_bang : ui_context -> int

val status_bar_bang : ui_context -> int

val toolbar_bang : ui_context -> int

val spacer_bang : ui_context -> int

val spinner_bang : ui_context -> int

val icon_bang : ui_context -> string -> int

val text_bang : ui_context -> string -> int

val heading_bang : ui_context -> int -> string -> int

val heading_value_bang : ui_context -> int -> wire_value signal -> int

val heading_signal_bang : ui_context -> int -> string signal -> int

val paragraph_bang : ui_context -> string -> int

val paragraph_value_bang : ui_context -> wire_value signal -> int

val paragraph_signal_bang : ui_context -> string signal -> int

val label_bang : ui_context -> string -> int

val label_value_bang : ui_context -> wire_value signal -> int

val label_signal_bang : ui_context -> string signal -> int

val text_signal_bang : ui_context -> string signal -> int

val text_value_bang : ui_context -> wire_value signal -> int

val text_field_bang : ui_context -> int

val secure_field_bang : ui_context -> int

val input_bang : ui_context -> int

val search_field_bang : ui_context -> int

val textarea_bang : ui_context -> int

val select_bang : ui_context -> int

val combobox_bang : ui_context -> int

val dropdown_menu_bang : ui_context -> int

val context_menu_bang : ui_context -> int

val dialog_bang : ui_context -> int

val sheet_bang : ui_context -> int

val tooltip_bang : ui_context -> int

val toast_bang : ui_context -> int

val accordion_bang : ui_context -> int

val menu_item_bang : ui_context -> int

val list_item_bang : ui_context -> int

val avatar_bang : ui_context -> int

val image_bang : ui_context -> int

val media_surface_bang : ui_context -> int

val stepper_bang : ui_context -> int

val step_bang : ui_context -> int

val timeline_bang : ui_context -> int

val timeline_item_bang : ui_context -> int

val input_group_bang : ui_context -> int

val input_group_actions_bang : ui_context -> int

val button_bang : ui_context -> int

val toggle_button_bang : ui_context -> int

val toggle_bang : ui_context -> int

val radio_group_bang : ui_context -> int

val radio_bang : ui_context -> int

val slider_bang : ui_context -> float signal -> int

val slider_literal_bang : ui_context -> float -> int

val string_property_bang : ui_context -> int -> property -> string -> bool

val string_property_signal_bang : ui_context -> int -> property -> string signal -> bool

val bool_property_bang : ui_context -> int -> property -> bool -> bool

val bool_property_signal_bang : ui_context -> int -> property -> bool signal -> bool

val float_property_bang : ui_context -> int -> property -> float -> bool

val float_property_signal_bang : ui_context -> int -> property -> float signal -> bool

val int_property_signal_bang : ui_context -> int -> property -> int signal -> bool

val int_property_bang : ui_context -> int -> property -> int -> bool

val disabled_bang : ui_context -> int -> bool -> bool

val disabled_signal_bang : ui_context -> int -> bool signal -> bool

val checked_signal_bang : ui_context -> int -> bool signal -> bool

val text_property_bang : ui_context -> int -> string -> bool

val text_property_signal_bang : ui_context -> int -> string signal -> bool

val on_event_bang : ui_context -> int -> (event -> bool) -> bool

val checkbox_bang : ui_context -> int

val switch_control_bang : ui_context -> int

val progress_bang : ui_context -> float signal -> int

val progress_literal_bang : ui_context -> float -> int

val separator_bang : ui_context -> string -> int

val size_bang : ui_context -> int -> string -> bool

val style_class_bang : ui_context -> int -> string -> bool

val append_bang : ui_context -> int -> int -> bool

val gap_bang : ui_context -> int -> int -> bool

val main_bang : ui_context -> int -> string -> bool

val cross_bang : ui_context -> int -> string -> bool

val grow_bang : ui_context -> int -> float -> bool

val columns_bang : ui_context -> int -> int -> bool

val padding_bang : ui_context -> int -> int -> bool

val padding_horizontal_bang : ui_context -> int -> int -> bool

val padding_vertical_bang : ui_context -> int -> int -> bool

val background_bang : ui_context -> int -> string -> bool

val foreground_bang : ui_context -> int -> string -> bool

val border_color_bang : ui_context -> int -> string -> bool

val border_width_bang : ui_context -> int -> int -> bool

val corner_radius_bang : ui_context -> int -> int -> bool

val width_bang : ui_context -> int -> int -> bool

val height_bang : ui_context -> int -> int -> bool

val min_width_bang : ui_context -> int -> int -> bool

val max_width_bang : ui_context -> int -> int -> bool

val min_height_bang : ui_context -> int -> int -> bool

val max_height_bang : ui_context -> int -> int -> bool

val container_relative_frame_bang : ui_context -> int -> string -> bool

val container_relative_frame_inset_bang : ui_context -> int -> int -> bool

val placeholder_bang : ui_context -> int -> string -> bool

val accessibility_label_bang : ui_context -> int -> string -> bool

val accessibility_identifier_bang : ui_context -> int -> string -> bool

