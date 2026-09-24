(** UI runtime bridge: the [ui_context] carried through element mounts,
    node creation helpers ([row], [column], ...), property setters, and event
    registration against the platform [Lui_protocol.backend]. *)

type ui_context = {
  ui_application : Lui_runtime.application;
  ui_scheduler : Signal.scheduler;
  ui_scope : Signal.scope;
  ui_state_scope : Signal.scope;
  ui_state_scopes : (string, Signal.scope) Hashtbl.t;
  ui_active_state_paths : (string, bool) Hashtbl.t;
  ui_state_path : string;
  ui_profile : Lui_protocol.platform_profile;
}
val make_context :
  Lui_runtime.application ->
  Signal.scope ->
  Signal.scope ->
  (string, Signal.scope) Hashtbl.t ->
  (string, bool) Hashtbl.t -> string -> ui_context
val context : Lui_runtime.application -> Signal.scope -> ui_context
val context_with_state_scope :
  Lui_runtime.application -> Signal.scope -> Signal.scope -> ui_context
val context_with_state_registry :
  Lui_runtime.application ->
  Signal.scope ->
  Signal.scope ->
  (string, Signal.scope) Hashtbl.t -> (string, bool) Hashtbl.t -> ui_context
val child_context : ui_context -> string -> ui_context
val node_kind : ui_context -> int -> Lui_protocol.node_kind
val profile : ui_context -> Lui_protocol.platform_profile
val platform : ui_context -> Lui_protocol.operating_system
val host : ui_context -> Lui_protocol.host_kind
val extension : ui_context -> string -> int
val platform_tweak : ui_context -> string -> int
val key : ui_context -> int -> string -> unit
val extension_property :
  ui_context ->
  int -> Lui_protocol.String_map.key -> Lui_protocol.wire_value -> unit
val extension_property_signal :
  ui_context ->
  int ->
  Lui_protocol.String_map.key ->
  Lui_protocol.wire_value Signal.signal -> unit
val create : ui_context -> Lui_protocol.node_kind -> int
val row : ui_context -> int
val column : ui_context -> int
val grid : ui_context -> int
val stack : ui_context -> int
val panel : ui_context -> int
val card : ui_context -> int
val alert : ui_context -> int
val bubble : ui_context -> int
val box : ui_context -> int
val scroll : ui_context -> int
val list : ui_context -> int
val virtual_list : ui_context -> int
val tabs : ui_context -> int
val bottom_tabs : ui_context -> int
val bottom_tab : ui_context -> int
val button_group : ui_context -> int
val toggle_group : ui_context -> int
val breadcrumb : ui_context -> int
val pagination : ui_context -> int
val table : ui_context -> int
val table_row : ui_context -> int
val table_cell : ui_context -> int
val tree : ui_context -> int
val resizable : ui_context -> int
val drawer : ui_context -> int
val status_bar : ui_context -> int
val toolbar : ui_context -> int
val spacer : ui_context -> int
val spinner : ui_context -> int
val text_field : ui_context -> int
val secure_field : ui_context -> int
val input : ui_context -> int
val search_field : ui_context -> int
val textarea : ui_context -> int
val select : ui_context -> int
val combobox : ui_context -> int
val dropdown_menu : ui_context -> int
val context_menu : ui_context -> int
val dialog : ui_context -> int
val sheet : ui_context -> int
val tooltip : ui_context -> int
val toast : ui_context -> int
val accordion : ui_context -> int
val menu_item : ui_context -> int
val list_item : ui_context -> int
val avatar : ui_context -> int
val image : ui_context -> int
val media_surface : ui_context -> int
val stepper : ui_context -> int
val step : ui_context -> int
val timeline : ui_context -> int
val timeline_item : ui_context -> int
val input_group : ui_context -> int
val input_group_actions : ui_context -> int
val button : ui_context -> int
val toggle_button : ui_context -> int
val toggle : ui_context -> int
val radio_group : ui_context -> int
val radio : ui_context -> int
val checkbox : ui_context -> int
val switch_control : ui_context -> int
val bind_float_prop :
  ui_context ->
  int -> Lui_protocol.Property_map.key -> float Signal.signal -> unit
val split : ui_context -> float Signal.signal -> int
val split_literal : ui_context -> float -> int
val icon : ui_context -> string -> int
val text : ui_context -> string -> int
val heading : ui_context -> int -> string -> int
val bind_string_prop :
  ui_context ->
  int -> Lui_protocol.Property_map.key -> string Signal.signal -> unit
val heading_value :
  ui_context -> int -> Lui_protocol.wire_value Signal.signal -> int
val heading_signal : ui_context -> int -> string Signal.signal -> int
val paragraph : ui_context -> string -> int
val paragraph_value :
  ui_context -> Lui_protocol.wire_value Signal.signal -> int
val paragraph_signal : ui_context -> string Signal.signal -> int
val label : ui_context -> string -> int
val label_value : ui_context -> Lui_protocol.wire_value Signal.signal -> int
val label_signal : ui_context -> string Signal.signal -> int
val text_value : ui_context -> Lui_protocol.wire_value Signal.signal -> int
val text_signal : ui_context -> string Signal.signal -> int
val slider : ui_context -> float Signal.signal -> int
val slider_literal : ui_context -> float -> int
val string_property :
  ui_context -> int -> Lui_protocol.Property_map.key -> string -> unit
val string_property_signal :
  ui_context ->
  int -> Lui_protocol.Property_map.key -> string Signal.signal -> unit
val bool_property :
  ui_context -> int -> Lui_protocol.Property_map.key -> bool -> unit
val bool_property_signal :
  ui_context ->
  int -> Lui_protocol.Property_map.key -> bool Signal.signal -> unit
val float_property :
  ui_context -> int -> Lui_protocol.Property_map.key -> float -> unit
val float_property_signal :
  ui_context ->
  int -> Lui_protocol.Property_map.key -> float Signal.signal -> unit
val int_property_signal :
  ui_context ->
  int -> Lui_protocol.Property_map.key -> int Signal.signal -> unit
val int_property :
  ui_context -> int -> Lui_protocol.Property_map.key -> int -> unit
val disabled : ui_context -> int -> bool -> unit
val disabled_signal : ui_context -> int -> bool Signal.signal -> unit
val checked_signal : ui_context -> int -> bool Signal.signal -> unit
val text_property : ui_context -> int -> string -> unit
val text_property_signal : ui_context -> int -> string Signal.signal -> unit
val on_event : ui_context -> int -> (Lui_protocol.event -> unit) -> unit
val progress : ui_context -> float Signal.signal -> int
val progress_literal : ui_context -> float -> int
val separator : ui_context -> string -> int
val size : ui_context -> int -> string -> unit
val style_class : ui_context -> int -> string -> unit
val append : ui_context -> int -> int -> unit
val gap : ui_context -> int -> int -> unit
val main : ui_context -> int -> string -> unit
val cross : ui_context -> int -> string -> unit
val grow : ui_context -> int -> float -> unit
val columns : ui_context -> int -> int -> unit
val padding : ui_context -> int -> int -> unit
val padding_horizontal : ui_context -> int -> int -> unit
val padding_vertical : ui_context -> int -> int -> unit
val background : ui_context -> int -> string -> unit
val foreground : ui_context -> int -> string -> unit
val border_color : ui_context -> int -> string -> unit
val border_width : ui_context -> int -> int -> unit
val corner_radius : ui_context -> int -> int -> unit
val width : ui_context -> int -> int -> unit
val height : ui_context -> int -> int -> unit
val min_width : ui_context -> int -> int -> unit
val max_width : ui_context -> int -> int -> unit
val min_height : ui_context -> int -> int -> unit
val max_height : ui_context -> int -> int -> unit
val container_relative_frame : ui_context -> int -> string -> unit
val container_relative_frame_inset : ui_context -> int -> int -> unit
val placement : ui_context -> int -> string -> unit
val placeholder : ui_context -> int -> string -> unit
val accessibility_label : ui_context -> int -> string -> unit
val accessibility_identifier : ui_context -> int -> string -> unit
