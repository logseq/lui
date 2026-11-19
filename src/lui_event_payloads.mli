(* Generated from schema/components.json. Do not edit by hand. *)

type pointer_detail = Lui_protocol.pointer_detail
type toggle_detail = { checked : bool; modifiers : int }
type navigation_key = { key : string; shift : bool }
type scroll_completed = { token : int; outcome : string }
type range = { first : int; last : int }
type scroll_edges = { at_start : bool; at_end : bool }
type navigation = Previous | Next | Key of navigation_key
type visible_range = Range of range | Edges of scroll_edges

val on_press : Lui_protocol.event -> unit option
val on_long_press : Lui_protocol.event -> unit option
val on_double_press : Lui_protocol.event -> unit option
val on_change : Lui_protocol.event -> unit option
val on_input : Lui_protocol.event -> string option
val on_submit : Lui_protocol.event -> unit option
val on_toggle : Lui_protocol.event -> bool option
val on_toggle_detail : Lui_protocol.event -> toggle_detail option
val on_dismiss : Lui_protocol.event -> unit option
val on_picked : Lui_protocol.event -> string option
val on_load : Lui_protocol.event -> unit option
val on_appear : Lui_protocol.event -> unit option
val on_resize : Lui_protocol.event -> float option
val on_value_changed : Lui_protocol.event -> float option
val on_navigate : Lui_protocol.event -> navigation option
val on_navigation_key : Lui_protocol.event -> navigation_key option
val on_scroll_completed : Lui_protocol.event -> scroll_completed option
val on_visible_range : Lui_protocol.event -> visible_range option
val on_press_detail : Lui_protocol.event -> pointer_detail option
val on_pointer_down : Lui_protocol.event -> pointer_detail option
val on_pointer_up : Lui_protocol.event -> pointer_detail option
val on_pointer_move : Lui_protocol.event -> pointer_detail option
val on_pointer_cancel : Lui_protocol.event -> pointer_detail option
val on_context_menu : Lui_protocol.event -> pointer_detail option
val on_pointer_enter : Lui_protocol.event -> unit option
val on_pointer_leave : Lui_protocol.event -> unit option
val on_focus_within : Lui_protocol.event -> bool option
