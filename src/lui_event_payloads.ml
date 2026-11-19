(* Generated from schema/components.json. Do not edit by hand. *)

type pointer_detail = Lui_protocol.pointer_detail
type toggle_detail = { checked : bool; modifiers : int }
type navigation_key = { key : string; shift : bool }
type scroll_completed = { token : int; outcome : string }
type range = { first : int; last : int }
type scroll_edges = { at_start : bool; at_end : bool }
type navigation = Previous | Next | Key of navigation_key
type visible_range = Range of range | Edges of scroll_edges

let on_press : Lui_protocol.event -> unit option = function
  | Lui_protocol.Press _ -> Some (())
  | Lui_protocol.PressModifiers (_, _) -> Some (())
  | _ -> None

let on_long_press : Lui_protocol.event -> unit option = function
  | Lui_protocol.LongPress _ -> Some (())
  | _ -> None

let on_double_press : Lui_protocol.event -> unit option = function
  | Lui_protocol.DoublePress _ -> Some (())
  | _ -> None

let on_change : Lui_protocol.event -> unit option = function
  | Lui_protocol.Change _ -> Some (())
  | _ -> None

let on_input : Lui_protocol.event -> string option = function
  | Lui_protocol.TextChanged (_, value) -> Some (value)
  | _ -> None

let on_submit : Lui_protocol.event -> unit option = function
  | Lui_protocol.Submit _ -> Some (())
  | _ -> None

let on_toggle : Lui_protocol.event -> bool option = function
  | Lui_protocol.ToggleChanged (_, value) -> Some (value)
  | _ -> None

let on_toggle_detail : Lui_protocol.event -> toggle_detail option = function
  | Lui_protocol.ToggleChangedDetail (_, checked, modifiers) -> Some ({ checked; modifiers })
  | _ -> None

let on_dismiss : Lui_protocol.event -> unit option = function
  | Lui_protocol.Dismiss _ -> Some (())
  | _ -> None

let on_picked : Lui_protocol.event -> string option = function
  | Lui_protocol.Picked (_, value) -> Some (value)
  | _ -> None

let on_load : Lui_protocol.event -> unit option = function
  | Lui_protocol.Load _ -> Some (())
  | _ -> None

let on_appear : Lui_protocol.event -> unit option = function
  | Lui_protocol.Appear _ -> Some (())
  | _ -> None

let on_resize : Lui_protocol.event -> float option = function
  | Lui_protocol.ValueChanged (_, value) when Float.is_finite value -> Some (value)
  | _ -> None

let on_value_changed : Lui_protocol.event -> float option = function
  | Lui_protocol.ValueChanged (_, value) when Float.is_finite value -> Some (value)
  | _ -> None

let on_navigate : Lui_protocol.event -> navigation option = function
  | Lui_protocol.NavigatePrevious _ -> Some (Previous)
  | Lui_protocol.NavigateNext _ -> Some (Next)
  | Lui_protocol.NavigationKey (_, key, shift) -> Some (Key { key; shift })
  | _ -> None

let on_navigation_key : Lui_protocol.event -> navigation_key option = function
  | Lui_protocol.NavigationKey (_, key, shift) -> Some ({ key; shift })
  | _ -> None

let on_scroll_completed : Lui_protocol.event -> scroll_completed option = function
  | Lui_protocol.ScrollCompleted (_, token, outcome) -> Some ({ token; outcome })
  | _ -> None

let on_visible_range : Lui_protocol.event -> visible_range option = function
  | Lui_protocol.VisibleRange (_, first, last) -> Some (Range { first; last })
  | Lui_protocol.ScrollEdges (_, at_start, at_end) -> Some (Edges { at_start; at_end })
  | _ -> None

let on_press_detail : Lui_protocol.event -> pointer_detail option = function
  | Lui_protocol.PressDetail (_, value) when Float.is_finite value.Lui_protocol.x && Float.is_finite value.Lui_protocol.y -> Some (value)
  | _ -> None

let on_pointer_down : Lui_protocol.event -> pointer_detail option = function
  | Lui_protocol.PointerDown (_, value) when Float.is_finite value.Lui_protocol.x && Float.is_finite value.Lui_protocol.y -> Some (value)
  | _ -> None

let on_pointer_up : Lui_protocol.event -> pointer_detail option = function
  | Lui_protocol.PointerUp (_, value) when Float.is_finite value.Lui_protocol.x && Float.is_finite value.Lui_protocol.y -> Some (value)
  | _ -> None

let on_pointer_move : Lui_protocol.event -> pointer_detail option = function
  | Lui_protocol.PointerMove (_, value) when Float.is_finite value.Lui_protocol.x && Float.is_finite value.Lui_protocol.y -> Some (value)
  | _ -> None

let on_pointer_cancel : Lui_protocol.event -> pointer_detail option = function
  | Lui_protocol.PointerCancel (_, value) when Float.is_finite value.Lui_protocol.x && Float.is_finite value.Lui_protocol.y -> Some (value)
  | _ -> None

let on_context_menu : Lui_protocol.event -> pointer_detail option = function
  | Lui_protocol.ContextMenuPress (_, value) when Float.is_finite value.Lui_protocol.x && Float.is_finite value.Lui_protocol.y -> Some (value)
  | _ -> None

let on_pointer_enter : Lui_protocol.event -> unit option = function
  | Lui_protocol.PointerEnter _ -> Some (())
  | _ -> None

let on_pointer_leave : Lui_protocol.event -> unit option = function
  | Lui_protocol.PointerLeave _ -> Some (())
  | _ -> None

let on_focus_within : Lui_protocol.event -> bool option = function
  | Lui_protocol.FocusWithinChanged (_, value) -> Some (value)
  | _ -> None
