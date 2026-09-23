(** Element DSL: typed constructors returning mount closures
    [t = ui_context -> int option -> int], e.g. [row ~gap:4 \[ child \]].
    Every prop has a static [~p] and a reactive [~p_signal] twin; [dyn],
    [if_], and [keyed] mount reactive structure, while [~p_signal] updates
    props in place. *)

type t = Lui_ui.ui_context -> int option -> int
val mount : 'a -> ?parent:'b -> ('a -> 'b option -> 'c) -> 'c
val reactive : ('a -> 'b) -> 'a Signal.signal -> 'b Signal.signal
val map : ('a -> 'b) -> 'a Signal.signal -> 'b Signal.signal
val sample : 'a Signal.signal -> 'a
val ( >|= ) : 'a Signal.signal -> ('a -> 'b) -> 'b Signal.signal
val get : 'a Signal.state -> 'a
val attach : Lui_ui.ui_context -> int option -> int -> unit
val enable :
  Lui_ui.ui_context -> int -> Lui_protocol.Property_map.key -> unit
val mount_children : 'a -> 'b -> ('a -> 'b option -> 'c) list -> unit
val dynamic : (Lui_ui.ui_context -> int -> 'a) -> t

(** [dyn ?equal f source] mounts [f model] under the parent node and remounts
    it whenever the published model differs under [equal]. The default
    [fun _ _ -> false] remounts on every publish; pass a structural or
    field-wise equality (e.g. [(=)]) to keep the subtree mounted when the
    change does not affect this branch and to avoid re-running mount-time
    effects (focus loss, control echoes, on-appear dispatches). *)
val dyn :
  ?equal:('a -> 'a -> bool) -> ('a -> t) -> 'a Signal.signal -> t
val if_ : test:bool Signal.signal -> t -> t
val keyed :
  source:'a list Signal.signal ->
  key:('a -> 'b) ->
  compare:('b -> 'b -> int) ->
  mount:('a Signal.signal -> t) -> t
val press : ('a -> bool) -> 'a -> Lui_protocol.event -> unit
val on_input :
  ('a -> bool) -> (string -> 'a) -> Lui_protocol.event -> unit
val on_event :
  Lui_ui.ui_context ->
  int -> (Lui_protocol.event -> bool) -> (Lui_protocol.event -> unit) -> unit
val is_press : Lui_protocol.event -> bool
val is_long_press : Lui_protocol.event -> bool
val is_double_press : Lui_protocol.event -> bool
val is_change : Lui_protocol.event -> bool
val is_input : Lui_protocol.event -> bool
val is_submit : Lui_protocol.event -> bool
val is_toggle : Lui_protocol.event -> bool
val is_dismiss : Lui_protocol.event -> bool
val is_appear : Lui_protocol.event -> bool
val is_resize : Lui_protocol.event -> bool
val register_press :
  Lui_ui.ui_context -> int -> (Lui_protocol.event -> unit) -> unit
val register_long_press :
  Lui_ui.ui_context -> int -> (Lui_protocol.event -> unit) -> unit
val register_double_press :
  Lui_ui.ui_context -> int -> (Lui_protocol.event -> unit) -> unit
val register_change :
  Lui_ui.ui_context -> int -> (Lui_protocol.event -> unit) -> unit
val register_input :
  Lui_ui.ui_context -> int -> (Lui_protocol.event -> unit) -> unit
val register_submit :
  Lui_ui.ui_context -> int -> (Lui_protocol.event -> unit) -> unit
val register_toggle :
  Lui_ui.ui_context -> int -> (Lui_protocol.event -> unit) -> unit
val register_dismiss :
  Lui_ui.ui_context -> int -> (Lui_protocol.event -> unit) -> unit
val appear_handler :
  Lui_ui.ui_context -> int -> (Lui_protocol.event -> unit) -> unit
val register_resize :
  Lui_ui.ui_context -> int -> (Lui_protocol.event -> unit) -> unit
val apply_universal :
  Lui_ui.ui_context ->
  int ->
  key:string option ->
  gap:int option ->
  main:string option ->
  cross:string option ->
  grow:float option ->
  columns:int option ->
  padding:int option ->
  padding_horizontal:int option ->
  padding_vertical:int option ->
  background:string option ->
  foreground:string option ->
  border_color:string option ->
  border_width:int option ->
  corner_radius:int option ->
  width:int option ->
  height:int option ->
  min_width:int option ->
  max_width:int option ->
  min_height:int option ->
  max_height:int option ->
  container_relative_frame:string option ->
  container_relative_frame_inset:int option ->
  accessibility_identifier:string option ->
  accessibility_identifier_signal:string Signal.signal option ->
  foreground_signal:string Signal.signal option ->
  background_signal:string Signal.signal option ->
  style_class:string option ->
  on_appear:(Lui_protocol.event -> unit) option -> unit
val row :
  ?key:string ->
  ?gap:int ->
  ?main:string ->
  ?cross:string ->
  ?grow:float ->
  ?columns:int ->
  ?padding:int ->
  ?padding_horizontal:int ->
  ?padding_vertical:int ->
  ?background:string ->
  ?foreground:string ->
  ?border_color:string ->
  ?border_width:int ->
  ?corner_radius:int ->
  ?width:int ->
  ?height:int ->
  ?min_width:int ->
  ?max_width:int ->
  ?min_height:int ->
  ?max_height:int ->
  ?container_relative_frame:string ->
  ?container_relative_frame_inset:int ->
  ?accessibility_identifier:string ->
  ?accessibility_identifier_signal:string Signal.signal ->
  ?foreground_signal:string Signal.signal ->
  ?background_signal:string Signal.signal ->
  ?style_class:string ->
  ?on_appear:(Lui_protocol.event -> unit) -> t list -> t
val column :
  ?key:string ->
  ?gap:int ->
  ?main:string ->
  ?cross:string ->
  ?grow:float ->
  ?columns:int ->
  ?padding:int ->
  ?padding_horizontal:int ->
  ?padding_vertical:int ->
  ?background:string ->
  ?foreground:string ->
  ?border_color:string ->
  ?border_width:int ->
  ?corner_radius:int ->
  ?width:int ->
  ?height:int ->
  ?min_width:int ->
  ?max_width:int ->
  ?min_height:int ->
  ?max_height:int ->
  ?container_relative_frame:string ->
  ?container_relative_frame_inset:int ->
  ?accessibility_identifier:string ->
  ?accessibility_identifier_signal:string Signal.signal ->
  ?foreground_signal:string Signal.signal ->
  ?background_signal:string Signal.signal ->
  ?style_class:string ->
  ?on_appear:(Lui_protocol.event -> unit) -> t list -> t
val grid :
  ?key:string ->
  ?gap:int ->
  ?main:string ->
  ?cross:string ->
  ?grow:float ->
  ?columns:int ->
  ?padding:int ->
  ?padding_horizontal:int ->
  ?padding_vertical:int ->
  ?background:string ->
  ?foreground:string ->
  ?border_color:string ->
  ?border_width:int ->
  ?corner_radius:int ->
  ?width:int ->
  ?height:int ->
  ?min_width:int ->
  ?max_width:int ->
  ?min_height:int ->
  ?max_height:int ->
  ?container_relative_frame:string ->
  ?container_relative_frame_inset:int ->
  ?accessibility_identifier:string ->
  ?accessibility_identifier_signal:string Signal.signal ->
  ?foreground_signal:string Signal.signal ->
  ?background_signal:string Signal.signal ->
  ?style_class:string ->
  ?on_appear:(Lui_protocol.event -> unit) -> t list -> t
val stack :
  ?key:string ->
  ?gap:int ->
  ?main:string ->
  ?cross:string ->
  ?grow:float ->
  ?columns:int ->
  ?padding:int ->
  ?padding_horizontal:int ->
  ?padding_vertical:int ->
  ?background:string ->
  ?foreground:string ->
  ?border_color:string ->
  ?border_width:int ->
  ?corner_radius:int ->
  ?width:int ->
  ?height:int ->
  ?min_width:int ->
  ?max_width:int ->
  ?min_height:int ->
  ?max_height:int ->
  ?container_relative_frame:string ->
  ?container_relative_frame_inset:int ->
  ?accessibility_identifier:string ->
  ?accessibility_identifier_signal:string Signal.signal ->
  ?foreground_signal:string Signal.signal ->
  ?background_signal:string Signal.signal ->
  ?style_class:string ->
  ?on_appear:(Lui_protocol.event -> unit) -> t list -> t
val panel :
  ?key:string ->
  ?gap:int ->
  ?main:string ->
  ?cross:string ->
  ?grow:float ->
  ?columns:int ->
  ?padding:int ->
  ?padding_horizontal:int ->
  ?padding_vertical:int ->
  ?background:string ->
  ?foreground:string ->
  ?border_color:string ->
  ?border_width:int ->
  ?corner_radius:int ->
  ?width:int ->
  ?height:int ->
  ?min_width:int ->
  ?max_width:int ->
  ?min_height:int ->
  ?max_height:int ->
  ?container_relative_frame:string ->
  ?container_relative_frame_inset:int ->
  ?accessibility_identifier:string ->
  ?accessibility_identifier_signal:string Signal.signal ->
  ?foreground_signal:string Signal.signal ->
  ?background_signal:string Signal.signal ->
  ?style_class:string ->
  ?on_appear:(Lui_protocol.event -> unit) -> t list -> t
val card :
  ?key:string ->
  ?gap:int ->
  ?main:string ->
  ?cross:string ->
  ?grow:float ->
  ?columns:int ->
  ?padding:int ->
  ?padding_horizontal:int ->
  ?padding_vertical:int ->
  ?background:string ->
  ?foreground:string ->
  ?border_color:string ->
  ?border_width:int ->
  ?corner_radius:int ->
  ?width:int ->
  ?height:int ->
  ?min_width:int ->
  ?max_width:int ->
  ?min_height:int ->
  ?max_height:int ->
  ?container_relative_frame:string ->
  ?container_relative_frame_inset:int ->
  ?accessibility_identifier:string ->
  ?accessibility_identifier_signal:string Signal.signal ->
  ?foreground_signal:string Signal.signal ->
  ?background_signal:string Signal.signal ->
  ?style_class:string ->
  ?on_appear:(Lui_protocol.event -> unit) -> t list -> t
val alert :
  ?key:string ->
  ?gap:int ->
  ?main:string ->
  ?cross:string ->
  ?grow:float ->
  ?columns:int ->
  ?padding:int ->
  ?padding_horizontal:int ->
  ?padding_vertical:int ->
  ?background:string ->
  ?foreground:string ->
  ?border_color:string ->
  ?border_width:int ->
  ?corner_radius:int ->
  ?width:int ->
  ?height:int ->
  ?min_width:int ->
  ?max_width:int ->
  ?min_height:int ->
  ?max_height:int ->
  ?container_relative_frame:string ->
  ?container_relative_frame_inset:int ->
  ?accessibility_identifier:string ->
  ?accessibility_identifier_signal:string Signal.signal ->
  ?foreground_signal:string Signal.signal ->
  ?background_signal:string Signal.signal ->
  ?style_class:string ->
  ?on_appear:(Lui_protocol.event -> unit) ->
  ?text:string ->
  ?text_signal:string Signal.signal ->
  ?variant:string -> ?text_alignment:string -> ?label:string -> t list -> t
val bubble :
  ?key:string ->
  ?gap:int ->
  ?main:string ->
  ?cross:string ->
  ?grow:float ->
  ?columns:int ->
  ?padding:int ->
  ?padding_horizontal:int ->
  ?padding_vertical:int ->
  ?background:string ->
  ?foreground:string ->
  ?border_color:string ->
  ?border_width:int ->
  ?corner_radius:int ->
  ?width:int ->
  ?height:int ->
  ?min_width:int ->
  ?max_width:int ->
  ?min_height:int ->
  ?max_height:int ->
  ?container_relative_frame:string ->
  ?container_relative_frame_inset:int ->
  ?accessibility_identifier:string ->
  ?accessibility_identifier_signal:string Signal.signal ->
  ?foreground_signal:string Signal.signal ->
  ?background_signal:string Signal.signal ->
  ?style_class:string ->
  ?on_appear:(Lui_protocol.event -> unit) ->
  ?text:string ->
  ?text_signal:string Signal.signal ->
  ?variant:string -> ?label:string -> t list -> t
val box :
  ?key:string ->
  ?gap:int ->
  ?main:string ->
  ?cross:string ->
  ?grow:float ->
  ?columns:int ->
  ?padding:int ->
  ?padding_horizontal:int ->
  ?padding_vertical:int ->
  ?background:string ->
  ?foreground:string ->
  ?border_color:string ->
  ?border_width:int ->
  ?corner_radius:int ->
  ?width:int ->
  ?height:int ->
  ?min_width:int ->
  ?max_width:int ->
  ?min_height:int ->
  ?max_height:int ->
  ?container_relative_frame:string ->
  ?container_relative_frame_inset:int ->
  ?accessibility_identifier:string ->
  ?accessibility_identifier_signal:string Signal.signal ->
  ?foreground_signal:string Signal.signal ->
  ?background_signal:string Signal.signal ->
  ?style_class:string ->
  ?on_appear:(Lui_protocol.event -> unit) -> t list -> t
val scroll :
  ?key:string ->
  ?gap:int ->
  ?main:string ->
  ?cross:string ->
  ?grow:float ->
  ?columns:int ->
  ?padding:int ->
  ?padding_horizontal:int ->
  ?padding_vertical:int ->
  ?background:string ->
  ?foreground:string ->
  ?border_color:string ->
  ?border_width:int ->
  ?corner_radius:int ->
  ?width:int ->
  ?height:int ->
  ?min_width:int ->
  ?max_width:int ->
  ?min_height:int ->
  ?max_height:int ->
  ?container_relative_frame:string ->
  ?container_relative_frame_inset:int ->
  ?accessibility_identifier:string ->
  ?accessibility_identifier_signal:string Signal.signal ->
  ?foreground_signal:string Signal.signal ->
  ?background_signal:string Signal.signal ->
  ?style_class:string ->
  ?on_appear:(Lui_protocol.event -> unit) -> t list -> t
val list :
  ?key:string ->
  ?gap:int ->
  ?main:string ->
  ?cross:string ->
  ?grow:float ->
  ?columns:int ->
  ?padding:int ->
  ?padding_horizontal:int ->
  ?padding_vertical:int ->
  ?background:string ->
  ?foreground:string ->
  ?border_color:string ->
  ?border_width:int ->
  ?corner_radius:int ->
  ?width:int ->
  ?height:int ->
  ?min_width:int ->
  ?max_width:int ->
  ?min_height:int ->
  ?max_height:int ->
  ?container_relative_frame:string ->
  ?container_relative_frame_inset:int ->
  ?accessibility_identifier:string ->
  ?accessibility_identifier_signal:string Signal.signal ->
  ?foreground_signal:string Signal.signal ->
  ?background_signal:string Signal.signal ->
  ?style_class:string ->
  ?on_appear:(Lui_protocol.event -> unit) -> t list -> t
val virtual_list :
  ?key:string ->
  ?gap:int ->
  ?main:string ->
  ?cross:string ->
  ?grow:float ->
  ?columns:int ->
  ?padding:int ->
  ?padding_horizontal:int ->
  ?padding_vertical:int ->
  ?background:string ->
  ?foreground:string ->
  ?border_color:string ->
  ?border_width:int ->
  ?corner_radius:int ->
  ?width:int ->
  ?height:int ->
  ?min_width:int ->
  ?max_width:int ->
  ?min_height:int ->
  ?max_height:int ->
  ?container_relative_frame:string ->
  ?container_relative_frame_inset:int ->
  ?accessibility_identifier:string ->
  ?accessibility_identifier_signal:string Signal.signal ->
  ?foreground_signal:string Signal.signal ->
  ?background_signal:string Signal.signal ->
  ?style_class:string ->
  ?on_appear:(Lui_protocol.event -> unit) -> t list -> t
val tabs :
  ?key:string ->
  ?gap:int ->
  ?main:string ->
  ?cross:string ->
  ?grow:float ->
  ?columns:int ->
  ?padding:int ->
  ?padding_horizontal:int ->
  ?padding_vertical:int ->
  ?background:string ->
  ?foreground:string ->
  ?border_color:string ->
  ?border_width:int ->
  ?corner_radius:int ->
  ?width:int ->
  ?height:int ->
  ?min_width:int ->
  ?max_width:int ->
  ?min_height:int ->
  ?max_height:int ->
  ?container_relative_frame:string ->
  ?container_relative_frame_inset:int ->
  ?accessibility_identifier:string ->
  ?accessibility_identifier_signal:string Signal.signal ->
  ?foreground_signal:string Signal.signal ->
  ?background_signal:string Signal.signal ->
  ?style_class:string ->
  ?on_appear:(Lui_protocol.event -> unit) ->
  ?label:string -> ?orientation:string -> t list -> t
val bottom_tabs :
  ?key:string ->
  ?gap:int ->
  ?main:string ->
  ?cross:string ->
  ?grow:float ->
  ?columns:int ->
  ?padding:int ->
  ?padding_horizontal:int ->
  ?padding_vertical:int ->
  ?background:string ->
  ?foreground:string ->
  ?border_color:string ->
  ?border_width:int ->
  ?corner_radius:int ->
  ?width:int ->
  ?height:int ->
  ?min_width:int ->
  ?max_width:int ->
  ?min_height:int ->
  ?max_height:int ->
  ?container_relative_frame:string ->
  ?container_relative_frame_inset:int ->
  ?accessibility_identifier:string ->
  ?accessibility_identifier_signal:string Signal.signal ->
  ?foreground_signal:string Signal.signal ->
  ?background_signal:string Signal.signal ->
  ?style_class:string ->
  ?on_appear:(Lui_protocol.event -> unit) -> t list -> t
val bottom_tab :
  ?key:string ->
  ?gap:int ->
  ?main:string ->
  ?cross:string ->
  ?grow:float ->
  ?columns:int ->
  ?padding:int ->
  ?padding_horizontal:int ->
  ?padding_vertical:int ->
  ?background:string ->
  ?foreground:string ->
  ?border_color:string ->
  ?border_width:int ->
  ?corner_radius:int ->
  ?width:int ->
  ?height:int ->
  ?min_width:int ->
  ?max_width:int ->
  ?min_height:int ->
  ?max_height:int ->
  ?container_relative_frame:string ->
  ?container_relative_frame_inset:int ->
  ?accessibility_identifier:string ->
  ?accessibility_identifier_signal:string Signal.signal ->
  ?foreground_signal:string Signal.signal ->
  ?background_signal:string Signal.signal ->
  ?style_class:string ->
  ?on_appear:(Lui_protocol.event -> unit) ->
  ?title:string ->
  ?icon:string ->
  ?selected:bool ->
  ?selected_signal:bool Signal.signal ->
  ?enabled:bool ->
  ?enabled_signal:bool Signal.signal ->
  ?on_press:(Lui_protocol.event -> unit) -> t list -> t
val button_group :
  ?key:string ->
  ?gap:int ->
  ?main:string ->
  ?cross:string ->
  ?grow:float ->
  ?columns:int ->
  ?padding:int ->
  ?padding_horizontal:int ->
  ?padding_vertical:int ->
  ?background:string ->
  ?foreground:string ->
  ?border_color:string ->
  ?border_width:int ->
  ?corner_radius:int ->
  ?width:int ->
  ?height:int ->
  ?min_width:int ->
  ?max_width:int ->
  ?min_height:int ->
  ?max_height:int ->
  ?container_relative_frame:string ->
  ?container_relative_frame_inset:int ->
  ?accessibility_identifier:string ->
  ?accessibility_identifier_signal:string Signal.signal ->
  ?foreground_signal:string Signal.signal ->
  ?background_signal:string Signal.signal ->
  ?style_class:string ->
  ?on_appear:(Lui_protocol.event -> unit) -> ?label:string -> t list -> t
val toggle_group :
  ?key:string ->
  ?gap:int ->
  ?main:string ->
  ?cross:string ->
  ?grow:float ->
  ?columns:int ->
  ?padding:int ->
  ?padding_horizontal:int ->
  ?padding_vertical:int ->
  ?background:string ->
  ?foreground:string ->
  ?border_color:string ->
  ?border_width:int ->
  ?corner_radius:int ->
  ?width:int ->
  ?height:int ->
  ?min_width:int ->
  ?max_width:int ->
  ?min_height:int ->
  ?max_height:int ->
  ?container_relative_frame:string ->
  ?container_relative_frame_inset:int ->
  ?accessibility_identifier:string ->
  ?accessibility_identifier_signal:string Signal.signal ->
  ?foreground_signal:string Signal.signal ->
  ?background_signal:string Signal.signal ->
  ?style_class:string ->
  ?on_appear:(Lui_protocol.event -> unit) -> ?label:string -> t list -> t
val breadcrumb :
  ?key:string ->
  ?gap:int ->
  ?main:string ->
  ?cross:string ->
  ?grow:float ->
  ?columns:int ->
  ?padding:int ->
  ?padding_horizontal:int ->
  ?padding_vertical:int ->
  ?background:string ->
  ?foreground:string ->
  ?border_color:string ->
  ?border_width:int ->
  ?corner_radius:int ->
  ?width:int ->
  ?height:int ->
  ?min_width:int ->
  ?max_width:int ->
  ?min_height:int ->
  ?max_height:int ->
  ?container_relative_frame:string ->
  ?container_relative_frame_inset:int ->
  ?accessibility_identifier:string ->
  ?accessibility_identifier_signal:string Signal.signal ->
  ?foreground_signal:string Signal.signal ->
  ?background_signal:string Signal.signal ->
  ?style_class:string ->
  ?on_appear:(Lui_protocol.event -> unit) -> ?label:string -> t list -> t
val pagination :
  ?key:string ->
  ?gap:int ->
  ?main:string ->
  ?cross:string ->
  ?grow:float ->
  ?columns:int ->
  ?padding:int ->
  ?padding_horizontal:int ->
  ?padding_vertical:int ->
  ?background:string ->
  ?foreground:string ->
  ?border_color:string ->
  ?border_width:int ->
  ?corner_radius:int ->
  ?width:int ->
  ?height:int ->
  ?min_width:int ->
  ?max_width:int ->
  ?min_height:int ->
  ?max_height:int ->
  ?container_relative_frame:string ->
  ?container_relative_frame_inset:int ->
  ?accessibility_identifier:string ->
  ?accessibility_identifier_signal:string Signal.signal ->
  ?foreground_signal:string Signal.signal ->
  ?background_signal:string Signal.signal ->
  ?style_class:string ->
  ?on_appear:(Lui_protocol.event -> unit) -> ?label:string -> t list -> t
val table :
  ?key:string ->
  ?gap:int ->
  ?main:string ->
  ?cross:string ->
  ?grow:float ->
  ?columns:int ->
  ?padding:int ->
  ?padding_horizontal:int ->
  ?padding_vertical:int ->
  ?background:string ->
  ?foreground:string ->
  ?border_color:string ->
  ?border_width:int ->
  ?corner_radius:int ->
  ?width:int ->
  ?height:int ->
  ?min_width:int ->
  ?max_width:int ->
  ?min_height:int ->
  ?max_height:int ->
  ?container_relative_frame:string ->
  ?container_relative_frame_inset:int ->
  ?accessibility_identifier:string ->
  ?accessibility_identifier_signal:string Signal.signal ->
  ?foreground_signal:string Signal.signal ->
  ?background_signal:string Signal.signal ->
  ?style_class:string ->
  ?on_appear:(Lui_protocol.event -> unit) -> t list -> t
val table_row :
  ?key:string ->
  ?gap:int ->
  ?main:string ->
  ?cross:string ->
  ?grow:float ->
  ?columns:int ->
  ?padding:int ->
  ?padding_horizontal:int ->
  ?padding_vertical:int ->
  ?background:string ->
  ?foreground:string ->
  ?border_color:string ->
  ?border_width:int ->
  ?corner_radius:int ->
  ?width:int ->
  ?height:int ->
  ?min_width:int ->
  ?max_width:int ->
  ?min_height:int ->
  ?max_height:int ->
  ?container_relative_frame:string ->
  ?container_relative_frame_inset:int ->
  ?accessibility_identifier:string ->
  ?accessibility_identifier_signal:string Signal.signal ->
  ?foreground_signal:string Signal.signal ->
  ?background_signal:string Signal.signal ->
  ?style_class:string ->
  ?on_appear:(Lui_protocol.event -> unit) ->
  ?selected:bool -> ?selected_signal:bool Signal.signal -> t list -> t
val table_cell :
  ?key:string ->
  ?gap:int ->
  ?main:string ->
  ?cross:string ->
  ?grow:float ->
  ?columns:int ->
  ?padding:int ->
  ?padding_horizontal:int ->
  ?padding_vertical:int ->
  ?background:string ->
  ?foreground:string ->
  ?border_color:string ->
  ?border_width:int ->
  ?corner_radius:int ->
  ?width:int ->
  ?height:int ->
  ?min_width:int ->
  ?max_width:int ->
  ?min_height:int ->
  ?max_height:int ->
  ?container_relative_frame:string ->
  ?container_relative_frame_inset:int ->
  ?accessibility_identifier:string ->
  ?accessibility_identifier_signal:string Signal.signal ->
  ?foreground_signal:string Signal.signal ->
  ?background_signal:string Signal.signal ->
  ?style_class:string ->
  ?on_appear:(Lui_protocol.event -> unit) ->
  ?text:string ->
  ?text_signal:string Signal.signal ->
  ?size:string ->
  ?text_alignment:string ->
  ?on_press:(Lui_protocol.event -> unit) -> t list -> t
val tree :
  ?key:string ->
  ?gap:int ->
  ?main:string ->
  ?cross:string ->
  ?grow:float ->
  ?columns:int ->
  ?padding:int ->
  ?padding_horizontal:int ->
  ?padding_vertical:int ->
  ?background:string ->
  ?foreground:string ->
  ?border_color:string ->
  ?border_width:int ->
  ?corner_radius:int ->
  ?width:int ->
  ?height:int ->
  ?min_width:int ->
  ?max_width:int ->
  ?min_height:int ->
  ?max_height:int ->
  ?container_relative_frame:string ->
  ?container_relative_frame_inset:int ->
  ?accessibility_identifier:string ->
  ?accessibility_identifier_signal:string Signal.signal ->
  ?foreground_signal:string Signal.signal ->
  ?background_signal:string Signal.signal ->
  ?style_class:string ->
  ?on_appear:(Lui_protocol.event -> unit) ->
  ?label:string ->
  ?role:string ->
  ?tree_level:int ->
  ?expanded:bool ->
  ?expanded_signal:bool Signal.signal ->
  ?on_press:(Lui_protocol.event -> unit) ->
  ?on_change:(Lui_protocol.event -> unit) ->
  ?on_toggle:(Lui_protocol.event -> unit) -> t list -> t
val resizable :
  ?key:string ->
  ?gap:int ->
  ?main:string ->
  ?cross:string ->
  ?grow:float ->
  ?columns:int ->
  ?padding:int ->
  ?padding_horizontal:int ->
  ?padding_vertical:int ->
  ?background:string ->
  ?foreground:string ->
  ?border_color:string ->
  ?border_width:int ->
  ?corner_radius:int ->
  ?width:int ->
  ?height:int ->
  ?min_width:int ->
  ?max_width:int ->
  ?min_height:int ->
  ?max_height:int ->
  ?container_relative_frame:string ->
  ?container_relative_frame_inset:int ->
  ?accessibility_identifier:string ->
  ?accessibility_identifier_signal:string Signal.signal ->
  ?foreground_signal:string Signal.signal ->
  ?background_signal:string Signal.signal ->
  ?style_class:string ->
  ?on_appear:(Lui_protocol.event -> unit) ->
  ?label:string -> ?resizable_width:int -> t list -> t
val split :
  ?key:string ->
  ?gap:int ->
  ?main:string ->
  ?cross:string ->
  ?grow:float ->
  ?columns:int ->
  ?padding:int ->
  ?padding_horizontal:int ->
  ?padding_vertical:int ->
  ?background:string ->
  ?foreground:string ->
  ?border_color:string ->
  ?border_width:int ->
  ?corner_radius:int ->
  ?width:int ->
  ?height:int ->
  ?min_width:int ->
  ?max_width:int ->
  ?min_height:int ->
  ?max_height:int ->
  ?container_relative_frame:string ->
  ?container_relative_frame_inset:int ->
  ?accessibility_identifier:string ->
  ?accessibility_identifier_signal:string Signal.signal ->
  ?foreground_signal:string Signal.signal ->
  ?background_signal:string Signal.signal ->
  ?style_class:string ->
  ?on_appear:(Lui_protocol.event -> unit) ->
  ?value:float ->
  ?value_signal:float Signal.signal ->
  ?resize_duration:int ->
  ?resize_easing:string ->
  ?resize_origin:float ->
  ?label:string -> ?on_resize:(Lui_protocol.event -> unit) -> t list -> t
val drawer :
  ?key:string ->
  ?gap:int ->
  ?main:string ->
  ?cross:string ->
  ?grow:float ->
  ?columns:int ->
  ?padding:int ->
  ?padding_horizontal:int ->
  ?padding_vertical:int ->
  ?background:string ->
  ?foreground:string ->
  ?border_color:string ->
  ?border_width:int ->
  ?corner_radius:int ->
  ?width:int ->
  ?height:int ->
  ?min_width:int ->
  ?max_width:int ->
  ?min_height:int ->
  ?max_height:int ->
  ?container_relative_frame:string ->
  ?container_relative_frame_inset:int ->
  ?accessibility_identifier:string ->
  ?accessibility_identifier_signal:string Signal.signal ->
  ?foreground_signal:string Signal.signal ->
  ?background_signal:string Signal.signal ->
  ?style_class:string ->
  ?on_appear:(Lui_protocol.event -> unit) ->
  ?selected:bool ->
  ?selected_signal:bool Signal.signal ->
  ?disabled:bool ->
  ?disabled_signal:bool Signal.signal ->
  ?label:string -> ?on_toggle:(Lui_protocol.event -> unit) -> t list -> t
val status_bar :
  ?key:string ->
  ?gap:int ->
  ?main:string ->
  ?cross:string ->
  ?grow:float ->
  ?columns:int ->
  ?padding:int ->
  ?padding_horizontal:int ->
  ?padding_vertical:int ->
  ?background:string ->
  ?foreground:string ->
  ?border_color:string ->
  ?border_width:int ->
  ?corner_radius:int ->
  ?width:int ->
  ?height:int ->
  ?min_width:int ->
  ?max_width:int ->
  ?min_height:int ->
  ?max_height:int ->
  ?container_relative_frame:string ->
  ?container_relative_frame_inset:int ->
  ?accessibility_identifier:string ->
  ?accessibility_identifier_signal:string Signal.signal ->
  ?foreground_signal:string Signal.signal ->
  ?background_signal:string Signal.signal ->
  ?style_class:string ->
  ?on_appear:(Lui_protocol.event -> unit) ->
  ?value:string ->
  ?value_signal:string Signal.signal -> ?text_alignment:string -> t list -> t
val spacer :
  ?key:string ->
  ?gap:int ->
  ?main:string ->
  ?cross:string ->
  ?grow:float ->
  ?columns:int ->
  ?padding:int ->
  ?padding_horizontal:int ->
  ?padding_vertical:int ->
  ?background:string ->
  ?foreground:string ->
  ?border_color:string ->
  ?border_width:int ->
  ?corner_radius:int ->
  ?width:int ->
  ?height:int ->
  ?min_width:int ->
  ?max_width:int ->
  ?min_height:int ->
  ?max_height:int ->
  ?container_relative_frame:string ->
  ?container_relative_frame_inset:int ->
  ?accessibility_identifier:string ->
  ?accessibility_identifier_signal:string Signal.signal ->
  ?foreground_signal:string Signal.signal ->
  ?background_signal:string Signal.signal ->
  ?style_class:string ->
  ?on_appear:(Lui_protocol.event -> unit) -> t list -> t
val spinner :
  ?key:string ->
  ?gap:int ->
  ?main:string ->
  ?cross:string ->
  ?grow:float ->
  ?columns:int ->
  ?padding:int ->
  ?padding_horizontal:int ->
  ?padding_vertical:int ->
  ?background:string ->
  ?foreground:string ->
  ?border_color:string ->
  ?border_width:int ->
  ?corner_radius:int ->
  ?width:int ->
  ?height:int ->
  ?min_width:int ->
  ?max_width:int ->
  ?min_height:int ->
  ?max_height:int ->
  ?container_relative_frame:string ->
  ?container_relative_frame_inset:int ->
  ?accessibility_identifier:string ->
  ?accessibility_identifier_signal:string Signal.signal ->
  ?foreground_signal:string Signal.signal ->
  ?background_signal:string Signal.signal ->
  ?style_class:string ->
  ?on_appear:(Lui_protocol.event -> unit) -> ?size:string -> t list -> t
val icon :
  ?key:string ->
  ?gap:int ->
  ?main:string ->
  ?cross:string ->
  ?grow:float ->
  ?columns:int ->
  ?padding:int ->
  ?padding_horizontal:int ->
  ?padding_vertical:int ->
  ?background:string ->
  ?foreground:string ->
  ?border_color:string ->
  ?border_width:int ->
  ?corner_radius:int ->
  ?width:int ->
  ?height:int ->
  ?min_width:int ->
  ?max_width:int ->
  ?min_height:int ->
  ?max_height:int ->
  ?container_relative_frame:string ->
  ?container_relative_frame_inset:int ->
  ?accessibility_identifier:string ->
  ?accessibility_identifier_signal:string Signal.signal ->
  ?foreground_signal:string Signal.signal ->
  ?background_signal:string Signal.signal ->
  ?style_class:string ->
  ?on_appear:(Lui_protocol.event -> unit) ->
  ?name:string ->
  ?name_signal:string Signal.signal -> ?size:string -> t list -> t
val text :
  ?key:string ->
  ?gap:int ->
  ?main:string ->
  ?cross:string ->
  ?grow:float ->
  ?columns:int ->
  ?padding:int ->
  ?padding_horizontal:int ->
  ?padding_vertical:int ->
  ?background:string ->
  ?foreground:string ->
  ?border_color:string ->
  ?border_width:int ->
  ?corner_radius:int ->
  ?width:int ->
  ?height:int ->
  ?min_width:int ->
  ?max_width:int ->
  ?min_height:int ->
  ?max_height:int ->
  ?container_relative_frame:string ->
  ?container_relative_frame_inset:int ->
  ?accessibility_identifier:string ->
  ?accessibility_identifier_signal:string Signal.signal ->
  ?foreground_signal:string Signal.signal ->
  ?background_signal:string Signal.signal ->
  ?style_class:string ->
  ?on_appear:(Lui_protocol.event -> unit) ->
  ?value:string ->
  ?value_signal:string Signal.signal ->
  ?text_alignment:string ->
  ?on_press:(Lui_protocol.event -> unit) -> t list -> t
val heading :
  ?key:string ->
  ?gap:int ->
  ?main:string ->
  ?cross:string ->
  ?grow:float ->
  ?columns:int ->
  ?padding:int ->
  ?padding_horizontal:int ->
  ?padding_vertical:int ->
  ?background:string ->
  ?foreground:string ->
  ?border_color:string ->
  ?border_width:int ->
  ?corner_radius:int ->
  ?width:int ->
  ?height:int ->
  ?min_width:int ->
  ?max_width:int ->
  ?min_height:int ->
  ?max_height:int ->
  ?container_relative_frame:string ->
  ?container_relative_frame_inset:int ->
  ?accessibility_identifier:string ->
  ?accessibility_identifier_signal:string Signal.signal ->
  ?foreground_signal:string Signal.signal ->
  ?background_signal:string Signal.signal ->
  ?style_class:string ->
  ?on_appear:(Lui_protocol.event -> unit) ->
  ?level:int ->
  ?value:string -> ?value_signal:string Signal.signal -> t list -> t
val paragraph :
  ?key:string ->
  ?gap:int ->
  ?main:string ->
  ?cross:string ->
  ?grow:float ->
  ?columns:int ->
  ?padding:int ->
  ?padding_horizontal:int ->
  ?padding_vertical:int ->
  ?background:string ->
  ?foreground:string ->
  ?border_color:string ->
  ?border_width:int ->
  ?corner_radius:int ->
  ?width:int ->
  ?height:int ->
  ?min_width:int ->
  ?max_width:int ->
  ?min_height:int ->
  ?max_height:int ->
  ?container_relative_frame:string ->
  ?container_relative_frame_inset:int ->
  ?accessibility_identifier:string ->
  ?accessibility_identifier_signal:string Signal.signal ->
  ?foreground_signal:string Signal.signal ->
  ?background_signal:string Signal.signal ->
  ?style_class:string ->
  ?on_appear:(Lui_protocol.event -> unit) ->
  ?value:string -> ?value_signal:string Signal.signal -> t list -> t
val label :
  ?key:string ->
  ?gap:int ->
  ?main:string ->
  ?cross:string ->
  ?grow:float ->
  ?columns:int ->
  ?padding:int ->
  ?padding_horizontal:int ->
  ?padding_vertical:int ->
  ?background:string ->
  ?foreground:string ->
  ?border_color:string ->
  ?border_width:int ->
  ?corner_radius:int ->
  ?width:int ->
  ?height:int ->
  ?min_width:int ->
  ?max_width:int ->
  ?min_height:int ->
  ?max_height:int ->
  ?container_relative_frame:string ->
  ?container_relative_frame_inset:int ->
  ?accessibility_identifier:string ->
  ?accessibility_identifier_signal:string Signal.signal ->
  ?foreground_signal:string Signal.signal ->
  ?background_signal:string Signal.signal ->
  ?style_class:string ->
  ?on_appear:(Lui_protocol.event -> unit) ->
  ?value:string -> ?value_signal:string Signal.signal -> t list -> t
val button :
  ?key:string ->
  ?gap:int ->
  ?main:string ->
  ?cross:string ->
  ?grow:float ->
  ?columns:int ->
  ?padding:int ->
  ?padding_horizontal:int ->
  ?padding_vertical:int ->
  ?background:string ->
  ?foreground:string ->
  ?border_color:string ->
  ?border_width:int ->
  ?corner_radius:int ->
  ?width:int ->
  ?height:int ->
  ?min_width:int ->
  ?max_width:int ->
  ?min_height:int ->
  ?max_height:int ->
  ?container_relative_frame:string ->
  ?container_relative_frame_inset:int ->
  ?accessibility_identifier:string ->
  ?accessibility_identifier_signal:string Signal.signal ->
  ?foreground_signal:string Signal.signal ->
  ?background_signal:string Signal.signal ->
  ?style_class:string ->
  ?on_appear:(Lui_protocol.event -> unit) ->
  ?text:string ->
  ?text_signal:string Signal.signal ->
  ?variant:string ->
  ?size:string ->
  ?icon:string ->
  ?icon_placement:string ->
  ?label:string ->
  ?text_alignment:string ->
  ?selected:bool ->
  ?autofocus:bool ->
  ?disabled:bool ->
  ?disabled_signal:bool Signal.signal ->
  ?on_press:(Lui_protocol.event -> unit) ->
  ?on_long_press:(Lui_protocol.event -> unit) -> t list -> t
val toggle_button :
  ?key:string ->
  ?gap:int ->
  ?main:string ->
  ?cross:string ->
  ?grow:float ->
  ?columns:int ->
  ?padding:int ->
  ?padding_horizontal:int ->
  ?padding_vertical:int ->
  ?background:string ->
  ?foreground:string ->
  ?border_color:string ->
  ?border_width:int ->
  ?corner_radius:int ->
  ?width:int ->
  ?height:int ->
  ?min_width:int ->
  ?max_width:int ->
  ?min_height:int ->
  ?max_height:int ->
  ?container_relative_frame:string ->
  ?container_relative_frame_inset:int ->
  ?accessibility_identifier:string ->
  ?accessibility_identifier_signal:string Signal.signal ->
  ?foreground_signal:string Signal.signal ->
  ?background_signal:string Signal.signal ->
  ?style_class:string ->
  ?on_appear:(Lui_protocol.event -> unit) ->
  ?text:string ->
  ?text_signal:string Signal.signal ->
  ?variant:string ->
  ?size:string ->
  ?icon:string ->
  ?icon_placement:string ->
  ?label:string ->
  ?text_alignment:string ->
  ?selected:bool ->
  ?autofocus:bool ->
  ?disabled:bool ->
  ?disabled_signal:bool Signal.signal ->
  ?on_press:(Lui_protocol.event -> unit) ->
  ?on_toggle:(Lui_protocol.event -> unit) ->
  ?on_long_press:(Lui_protocol.event -> unit) -> t list -> t
val checkbox :
  ?key:string ->
  ?gap:int ->
  ?main:string ->
  ?cross:string ->
  ?grow:float ->
  ?columns:int ->
  ?padding:int ->
  ?padding_horizontal:int ->
  ?padding_vertical:int ->
  ?background:string ->
  ?foreground:string ->
  ?border_color:string ->
  ?border_width:int ->
  ?corner_radius:int ->
  ?width:int ->
  ?height:int ->
  ?min_width:int ->
  ?max_width:int ->
  ?min_height:int ->
  ?max_height:int ->
  ?container_relative_frame:string ->
  ?container_relative_frame_inset:int ->
  ?accessibility_identifier:string ->
  ?accessibility_identifier_signal:string Signal.signal ->
  ?foreground_signal:string Signal.signal ->
  ?background_signal:string Signal.signal ->
  ?style_class:string ->
  ?on_appear:(Lui_protocol.event -> unit) ->
  ?text:string ->
  ?text_signal:string Signal.signal ->
  ?checked:bool ->
  ?checked_signal:bool Signal.signal ->
  ?label:string ->
  ?disabled:bool ->
  ?disabled_signal:bool Signal.signal ->
  ?on_toggle:(Lui_protocol.event -> unit) -> t list -> t
val switch_ :
  ?key:string ->
  ?gap:int ->
  ?main:string ->
  ?cross:string ->
  ?grow:float ->
  ?columns:int ->
  ?padding:int ->
  ?padding_horizontal:int ->
  ?padding_vertical:int ->
  ?background:string ->
  ?foreground:string ->
  ?border_color:string ->
  ?border_width:int ->
  ?corner_radius:int ->
  ?width:int ->
  ?height:int ->
  ?min_width:int ->
  ?max_width:int ->
  ?min_height:int ->
  ?max_height:int ->
  ?container_relative_frame:string ->
  ?container_relative_frame_inset:int ->
  ?accessibility_identifier:string ->
  ?accessibility_identifier_signal:string Signal.signal ->
  ?foreground_signal:string Signal.signal ->
  ?background_signal:string Signal.signal ->
  ?style_class:string ->
  ?on_appear:(Lui_protocol.event -> unit) ->
  ?text:string ->
  ?text_signal:string Signal.signal ->
  ?checked:bool ->
  ?checked_signal:bool Signal.signal ->
  ?label:string ->
  ?disabled:bool ->
  ?disabled_signal:bool Signal.signal ->
  ?on_toggle:(Lui_protocol.event -> unit) -> t list -> t
val toggle :
  ?key:string ->
  ?gap:int ->
  ?main:string ->
  ?cross:string ->
  ?grow:float ->
  ?columns:int ->
  ?padding:int ->
  ?padding_horizontal:int ->
  ?padding_vertical:int ->
  ?background:string ->
  ?foreground:string ->
  ?border_color:string ->
  ?border_width:int ->
  ?corner_radius:int ->
  ?width:int ->
  ?height:int ->
  ?min_width:int ->
  ?max_width:int ->
  ?min_height:int ->
  ?max_height:int ->
  ?container_relative_frame:string ->
  ?container_relative_frame_inset:int ->
  ?accessibility_identifier:string ->
  ?accessibility_identifier_signal:string Signal.signal ->
  ?foreground_signal:string Signal.signal ->
  ?background_signal:string Signal.signal ->
  ?style_class:string ->
  ?on_appear:(Lui_protocol.event -> unit) ->
  ?text:string ->
  ?text_signal:string Signal.signal ->
  ?checked:bool ->
  ?checked_signal:bool Signal.signal ->
  ?label:string ->
  ?disabled:bool ->
  ?disabled_signal:bool Signal.signal ->
  ?on_toggle:(Lui_protocol.event -> unit) -> t list -> t
val radio_group :
  ?key:string ->
  ?gap:int ->
  ?main:string ->
  ?cross:string ->
  ?grow:float ->
  ?columns:int ->
  ?padding:int ->
  ?padding_horizontal:int ->
  ?padding_vertical:int ->
  ?background:string ->
  ?foreground:string ->
  ?border_color:string ->
  ?border_width:int ->
  ?corner_radius:int ->
  ?width:int ->
  ?height:int ->
  ?min_width:int ->
  ?max_width:int ->
  ?min_height:int ->
  ?max_height:int ->
  ?container_relative_frame:string ->
  ?container_relative_frame_inset:int ->
  ?accessibility_identifier:string ->
  ?accessibility_identifier_signal:string Signal.signal ->
  ?foreground_signal:string Signal.signal ->
  ?background_signal:string Signal.signal ->
  ?style_class:string ->
  ?on_appear:(Lui_protocol.event -> unit) -> ?label:string -> t list -> t
val radio :
  ?key:string ->
  ?gap:int ->
  ?main:string ->
  ?cross:string ->
  ?grow:float ->
  ?columns:int ->
  ?padding:int ->
  ?padding_horizontal:int ->
  ?padding_vertical:int ->
  ?background:string ->
  ?foreground:string ->
  ?border_color:string ->
  ?border_width:int ->
  ?corner_radius:int ->
  ?width:int ->
  ?height:int ->
  ?min_width:int ->
  ?max_width:int ->
  ?min_height:int ->
  ?max_height:int ->
  ?container_relative_frame:string ->
  ?container_relative_frame_inset:int ->
  ?accessibility_identifier:string ->
  ?accessibility_identifier_signal:string Signal.signal ->
  ?foreground_signal:string Signal.signal ->
  ?background_signal:string Signal.signal ->
  ?style_class:string ->
  ?on_appear:(Lui_protocol.event -> unit) ->
  ?text:string ->
  ?text_signal:string Signal.signal ->
  ?checked:bool ->
  ?checked_signal:bool Signal.signal ->
  ?selected:bool ->
  ?label:string ->
  ?disabled:bool ->
  ?disabled_signal:bool Signal.signal ->
  ?on_change:(Lui_protocol.event -> unit) ->
  ?on_toggle:(Lui_protocol.event -> unit) ->
  ?on_press:(Lui_protocol.event -> unit) -> t list -> t
val slider :
  ?key:string ->
  ?gap:int ->
  ?main:string ->
  ?cross:string ->
  ?grow:float ->
  ?columns:int ->
  ?padding:int ->
  ?padding_horizontal:int ->
  ?padding_vertical:int ->
  ?background:string ->
  ?foreground:string ->
  ?border_color:string ->
  ?border_width:int ->
  ?corner_radius:int ->
  ?width:int ->
  ?height:int ->
  ?min_width:int ->
  ?max_width:int ->
  ?min_height:int ->
  ?max_height:int ->
  ?container_relative_frame:string ->
  ?container_relative_frame_inset:int ->
  ?accessibility_identifier:string ->
  ?accessibility_identifier_signal:string Signal.signal ->
  ?foreground_signal:string Signal.signal ->
  ?background_signal:string Signal.signal ->
  ?style_class:string ->
  ?on_appear:(Lui_protocol.event -> unit) ->
  ?value:float ->
  ?value_signal:float Signal.signal ->
  ?label:string ->
  ?disabled:bool ->
  ?disabled_signal:bool Signal.signal ->
  ?on_change:(Lui_protocol.event -> unit) -> t list -> t
val progress :
  ?key:string ->
  ?gap:int ->
  ?main:string ->
  ?cross:string ->
  ?grow:float ->
  ?columns:int ->
  ?padding:int ->
  ?padding_horizontal:int ->
  ?padding_vertical:int ->
  ?background:string ->
  ?foreground:string ->
  ?border_color:string ->
  ?border_width:int ->
  ?corner_radius:int ->
  ?width:int ->
  ?height:int ->
  ?min_width:int ->
  ?max_width:int ->
  ?min_height:int ->
  ?max_height:int ->
  ?container_relative_frame:string ->
  ?container_relative_frame_inset:int ->
  ?accessibility_identifier:string ->
  ?accessibility_identifier_signal:string Signal.signal ->
  ?foreground_signal:string Signal.signal ->
  ?background_signal:string Signal.signal ->
  ?style_class:string ->
  ?on_appear:(Lui_protocol.event -> unit) ->
  ?value:float -> ?value_signal:float Signal.signal -> t list -> t
val divider :
  ?key:string ->
  ?gap:int ->
  ?main:string ->
  ?cross:string ->
  ?grow:float ->
  ?columns:int ->
  ?padding:int ->
  ?padding_horizontal:int ->
  ?padding_vertical:int ->
  ?background:string ->
  ?foreground:string ->
  ?border_color:string ->
  ?border_width:int ->
  ?corner_radius:int ->
  ?width:int ->
  ?height:int ->
  ?min_width:int ->
  ?max_width:int ->
  ?min_height:int ->
  ?max_height:int ->
  ?container_relative_frame:string ->
  ?container_relative_frame_inset:int ->
  ?accessibility_identifier:string ->
  ?accessibility_identifier_signal:string Signal.signal ->
  ?foreground_signal:string Signal.signal ->
  ?background_signal:string Signal.signal ->
  ?style_class:string ->
  ?on_appear:(Lui_protocol.event -> unit) ->
  ?orientation:string -> t list -> t
val separator :
  ?key:string ->
  ?gap:int ->
  ?main:string ->
  ?cross:string ->
  ?grow:float ->
  ?columns:int ->
  ?padding:int ->
  ?padding_horizontal:int ->
  ?padding_vertical:int ->
  ?background:string ->
  ?foreground:string ->
  ?border_color:string ->
  ?border_width:int ->
  ?corner_radius:int ->
  ?width:int ->
  ?height:int ->
  ?min_width:int ->
  ?max_width:int ->
  ?min_height:int ->
  ?max_height:int ->
  ?container_relative_frame:string ->
  ?container_relative_frame_inset:int ->
  ?accessibility_identifier:string ->
  ?accessibility_identifier_signal:string Signal.signal ->
  ?foreground_signal:string Signal.signal ->
  ?background_signal:string Signal.signal ->
  ?style_class:string ->
  ?on_appear:(Lui_protocol.event -> unit) ->
  ?orientation:string -> t list -> t
val text_field :
  ?key:string ->
  ?gap:int ->
  ?main:string ->
  ?cross:string ->
  ?grow:float ->
  ?columns:int ->
  ?padding:int ->
  ?padding_horizontal:int ->
  ?padding_vertical:int ->
  ?background:string ->
  ?foreground:string ->
  ?border_color:string ->
  ?border_width:int ->
  ?corner_radius:int ->
  ?width:int ->
  ?height:int ->
  ?min_width:int ->
  ?max_width:int ->
  ?min_height:int ->
  ?max_height:int ->
  ?container_relative_frame:string ->
  ?container_relative_frame_inset:int ->
  ?accessibility_identifier:string ->
  ?accessibility_identifier_signal:string Signal.signal ->
  ?foreground_signal:string Signal.signal ->
  ?background_signal:string Signal.signal ->
  ?style_class:string ->
  ?on_appear:(Lui_protocol.event -> unit) ->
  ?text:string ->
  ?text_signal:string Signal.signal ->
  ?placeholder:string ->
  ?label:string ->
  ?autofocus:bool ->
  ?submit_on_enter:bool ->
  ?disabled:bool ->
  ?disabled_signal:bool Signal.signal ->
  ?on_input:(Lui_protocol.event -> unit) ->
  ?on_submit:(Lui_protocol.event -> unit) -> t list -> t
val secure_field :
  ?key:string ->
  ?gap:int ->
  ?main:string ->
  ?cross:string ->
  ?grow:float ->
  ?columns:int ->
  ?padding:int ->
  ?padding_horizontal:int ->
  ?padding_vertical:int ->
  ?background:string ->
  ?foreground:string ->
  ?border_color:string ->
  ?border_width:int ->
  ?corner_radius:int ->
  ?width:int ->
  ?height:int ->
  ?min_width:int ->
  ?max_width:int ->
  ?min_height:int ->
  ?max_height:int ->
  ?container_relative_frame:string ->
  ?container_relative_frame_inset:int ->
  ?accessibility_identifier:string ->
  ?accessibility_identifier_signal:string Signal.signal ->
  ?foreground_signal:string Signal.signal ->
  ?background_signal:string Signal.signal ->
  ?style_class:string ->
  ?on_appear:(Lui_protocol.event -> unit) ->
  ?text:string ->
  ?text_signal:string Signal.signal ->
  ?placeholder:string ->
  ?label:string ->
  ?autofocus:bool ->
  ?submit_on_enter:bool ->
  ?disabled:bool ->
  ?disabled_signal:bool Signal.signal ->
  ?on_input:(Lui_protocol.event -> unit) ->
  ?on_submit:(Lui_protocol.event -> unit) -> t list -> t
val input :
  ?key:string ->
  ?gap:int ->
  ?main:string ->
  ?cross:string ->
  ?grow:float ->
  ?columns:int ->
  ?padding:int ->
  ?padding_horizontal:int ->
  ?padding_vertical:int ->
  ?background:string ->
  ?foreground:string ->
  ?border_color:string ->
  ?border_width:int ->
  ?corner_radius:int ->
  ?width:int ->
  ?height:int ->
  ?min_width:int ->
  ?max_width:int ->
  ?min_height:int ->
  ?max_height:int ->
  ?container_relative_frame:string ->
  ?container_relative_frame_inset:int ->
  ?accessibility_identifier:string ->
  ?accessibility_identifier_signal:string Signal.signal ->
  ?foreground_signal:string Signal.signal ->
  ?background_signal:string Signal.signal ->
  ?style_class:string ->
  ?on_appear:(Lui_protocol.event -> unit) ->
  ?text:string ->
  ?text_signal:string Signal.signal ->
  ?placeholder:string ->
  ?label:string ->
  ?autofocus:bool ->
  ?submit_on_enter:bool ->
  ?disabled:bool ->
  ?disabled_signal:bool Signal.signal ->
  ?on_input:(Lui_protocol.event -> unit) ->
  ?on_submit:(Lui_protocol.event -> unit) -> t list -> t
val search_field :
  ?key:string ->
  ?gap:int ->
  ?main:string ->
  ?cross:string ->
  ?grow:float ->
  ?columns:int ->
  ?padding:int ->
  ?padding_horizontal:int ->
  ?padding_vertical:int ->
  ?background:string ->
  ?foreground:string ->
  ?border_color:string ->
  ?border_width:int ->
  ?corner_radius:int ->
  ?width:int ->
  ?height:int ->
  ?min_width:int ->
  ?max_width:int ->
  ?min_height:int ->
  ?max_height:int ->
  ?container_relative_frame:string ->
  ?container_relative_frame_inset:int ->
  ?accessibility_identifier:string ->
  ?accessibility_identifier_signal:string Signal.signal ->
  ?foreground_signal:string Signal.signal ->
  ?background_signal:string Signal.signal ->
  ?style_class:string ->
  ?on_appear:(Lui_protocol.event -> unit) ->
  ?text:string ->
  ?text_signal:string Signal.signal ->
  ?placeholder:string ->
  ?label:string ->
  ?autofocus:bool ->
  ?submit_on_enter:bool ->
  ?disabled:bool ->
  ?disabled_signal:bool Signal.signal ->
  ?on_input:(Lui_protocol.event -> unit) ->
  ?on_submit:(Lui_protocol.event -> unit) -> t list -> t
val textarea :
  ?key:string ->
  ?gap:int ->
  ?main:string ->
  ?cross:string ->
  ?grow:float ->
  ?columns:int ->
  ?padding:int ->
  ?padding_horizontal:int ->
  ?padding_vertical:int ->
  ?background:string ->
  ?foreground:string ->
  ?border_color:string ->
  ?border_width:int ->
  ?corner_radius:int ->
  ?width:int ->
  ?height:int ->
  ?min_width:int ->
  ?max_width:int ->
  ?min_height:int ->
  ?max_height:int ->
  ?container_relative_frame:string ->
  ?container_relative_frame_inset:int ->
  ?accessibility_identifier:string ->
  ?accessibility_identifier_signal:string Signal.signal ->
  ?foreground_signal:string Signal.signal ->
  ?background_signal:string Signal.signal ->
  ?style_class:string ->
  ?on_appear:(Lui_protocol.event -> unit) ->
  ?text:string ->
  ?text_signal:string Signal.signal ->
  ?placeholder:string ->
  ?label:string ->
  ?autofocus:bool ->
  ?submit_on_enter:bool ->
  ?disabled:bool ->
  ?disabled_signal:bool Signal.signal ->
  ?on_input:(Lui_protocol.event -> unit) ->
  ?on_submit:(Lui_protocol.event -> unit) -> t list -> t
val input_group :
  ?key:string ->
  ?gap:int ->
  ?main:string ->
  ?cross:string ->
  ?grow:float ->
  ?columns:int ->
  ?padding:int ->
  ?padding_horizontal:int ->
  ?padding_vertical:int ->
  ?background:string ->
  ?foreground:string ->
  ?border_color:string ->
  ?border_width:int ->
  ?corner_radius:int ->
  ?width:int ->
  ?height:int ->
  ?min_width:int ->
  ?max_width:int ->
  ?min_height:int ->
  ?max_height:int ->
  ?container_relative_frame:string ->
  ?container_relative_frame_inset:int ->
  ?accessibility_identifier:string ->
  ?accessibility_identifier_signal:string Signal.signal ->
  ?foreground_signal:string Signal.signal ->
  ?background_signal:string Signal.signal ->
  ?style_class:string ->
  ?on_appear:(Lui_protocol.event -> unit) -> ?label:string -> t list -> t
val input_group_actions :
  ?key:string ->
  ?gap:int ->
  ?main:string ->
  ?cross:string ->
  ?grow:float ->
  ?columns:int ->
  ?padding:int ->
  ?padding_horizontal:int ->
  ?padding_vertical:int ->
  ?background:string ->
  ?foreground:string ->
  ?border_color:string ->
  ?border_width:int ->
  ?corner_radius:int ->
  ?width:int ->
  ?height:int ->
  ?min_width:int ->
  ?max_width:int ->
  ?min_height:int ->
  ?max_height:int ->
  ?container_relative_frame:string ->
  ?container_relative_frame_inset:int ->
  ?accessibility_identifier:string ->
  ?accessibility_identifier_signal:string Signal.signal ->
  ?foreground_signal:string Signal.signal ->
  ?background_signal:string Signal.signal ->
  ?style_class:string ->
  ?on_appear:(Lui_protocol.event -> unit) -> t list -> t
val select :
  ?key:string ->
  ?gap:int ->
  ?main:string ->
  ?cross:string ->
  ?grow:float ->
  ?columns:int ->
  ?padding:int ->
  ?padding_horizontal:int ->
  ?padding_vertical:int ->
  ?background:string ->
  ?foreground:string ->
  ?border_color:string ->
  ?border_width:int ->
  ?corner_radius:int ->
  ?width:int ->
  ?height:int ->
  ?min_width:int ->
  ?max_width:int ->
  ?min_height:int ->
  ?max_height:int ->
  ?container_relative_frame:string ->
  ?container_relative_frame_inset:int ->
  ?accessibility_identifier:string ->
  ?accessibility_identifier_signal:string Signal.signal ->
  ?foreground_signal:string Signal.signal ->
  ?background_signal:string Signal.signal ->
  ?style_class:string ->
  ?on_appear:(Lui_protocol.event -> unit) ->
  ?label:string ->
  ?text:string ->
  ?text_signal:string Signal.signal ->
  ?placeholder:string ->
  ?disabled:bool ->
  ?disabled_signal:bool Signal.signal ->
  ?on_press:(Lui_protocol.event -> unit) ->
  ?on_input:(Lui_protocol.event -> unit) ->
  ?on_submit:(Lui_protocol.event -> unit) ->
  ?on_dismiss:(Lui_protocol.event -> unit) -> t list -> t
val combobox :
  ?key:string ->
  ?gap:int ->
  ?main:string ->
  ?cross:string ->
  ?grow:float ->
  ?columns:int ->
  ?padding:int ->
  ?padding_horizontal:int ->
  ?padding_vertical:int ->
  ?background:string ->
  ?foreground:string ->
  ?border_color:string ->
  ?border_width:int ->
  ?corner_radius:int ->
  ?width:int ->
  ?height:int ->
  ?min_width:int ->
  ?max_width:int ->
  ?min_height:int ->
  ?max_height:int ->
  ?container_relative_frame:string ->
  ?container_relative_frame_inset:int ->
  ?accessibility_identifier:string ->
  ?accessibility_identifier_signal:string Signal.signal ->
  ?foreground_signal:string Signal.signal ->
  ?background_signal:string Signal.signal ->
  ?style_class:string ->
  ?on_appear:(Lui_protocol.event -> unit) ->
  ?text:string ->
  ?text_signal:string Signal.signal ->
  ?placeholder:string ->
  ?disabled:bool ->
  ?disabled_signal:bool Signal.signal ->
  ?on_press:(Lui_protocol.event -> unit) ->
  ?on_input:(Lui_protocol.event -> unit) ->
  ?on_submit:(Lui_protocol.event -> unit) ->
  ?on_dismiss:(Lui_protocol.event -> unit) -> t list -> t
val dropdown_menu :
  ?key:string ->
  ?gap:int ->
  ?main:string ->
  ?cross:string ->
  ?grow:float ->
  ?columns:int ->
  ?padding:int ->
  ?padding_horizontal:int ->
  ?padding_vertical:int ->
  ?background:string ->
  ?foreground:string ->
  ?border_color:string ->
  ?border_width:int ->
  ?corner_radius:int ->
  ?width:int ->
  ?height:int ->
  ?min_width:int ->
  ?max_width:int ->
  ?min_height:int ->
  ?max_height:int ->
  ?container_relative_frame:string ->
  ?container_relative_frame_inset:int ->
  ?accessibility_identifier:string ->
  ?accessibility_identifier_signal:string Signal.signal ->
  ?foreground_signal:string Signal.signal ->
  ?background_signal:string Signal.signal ->
  ?style_class:string ->
  ?on_appear:(Lui_protocol.event -> unit) ->
  ?anchor:string ->
  ?anchor_alignment:string ->
  ?anchor_offset:float ->
  ?on_press:(Lui_protocol.event -> unit) ->
  ?on_input:(Lui_protocol.event -> unit) ->
  ?on_submit:(Lui_protocol.event -> unit) ->
  ?on_dismiss:(Lui_protocol.event -> unit) -> t list -> t
val context_menu :
  ?key:string ->
  ?gap:int ->
  ?main:string ->
  ?cross:string ->
  ?grow:float ->
  ?columns:int ->
  ?padding:int ->
  ?padding_horizontal:int ->
  ?padding_vertical:int ->
  ?background:string ->
  ?foreground:string ->
  ?border_color:string ->
  ?border_width:int ->
  ?corner_radius:int ->
  ?width:int ->
  ?height:int ->
  ?min_width:int ->
  ?max_width:int ->
  ?min_height:int ->
  ?max_height:int ->
  ?container_relative_frame:string ->
  ?container_relative_frame_inset:int ->
  ?accessibility_identifier:string ->
  ?accessibility_identifier_signal:string Signal.signal ->
  ?foreground_signal:string Signal.signal ->
  ?background_signal:string Signal.signal ->
  ?style_class:string ->
  ?on_appear:(Lui_protocol.event -> unit) ->
  ?disabled:bool -> ?disabled_signal:bool Signal.signal -> t list -> t
val dialog :
  ?key:string ->
  ?gap:int ->
  ?main:string ->
  ?cross:string ->
  ?grow:float ->
  ?columns:int ->
  ?padding:int ->
  ?padding_horizontal:int ->
  ?padding_vertical:int ->
  ?background:string ->
  ?foreground:string ->
  ?border_color:string ->
  ?border_width:int ->
  ?corner_radius:int ->
  ?width:int ->
  ?height:int ->
  ?min_width:int ->
  ?max_width:int ->
  ?min_height:int ->
  ?max_height:int ->
  ?container_relative_frame:string ->
  ?container_relative_frame_inset:int ->
  ?accessibility_identifier:string ->
  ?accessibility_identifier_signal:string Signal.signal ->
  ?foreground_signal:string Signal.signal ->
  ?background_signal:string Signal.signal ->
  ?style_class:string ->
  ?on_appear:(Lui_protocol.event -> unit) ->
  ?text:string ->
  ?text_signal:string Signal.signal ->
  ?on_dismiss:(Lui_protocol.event -> unit) -> t list -> t
val sheet :
  ?key:string ->
  ?gap:int ->
  ?main:string ->
  ?cross:string ->
  ?grow:float ->
  ?columns:int ->
  ?padding:int ->
  ?padding_horizontal:int ->
  ?padding_vertical:int ->
  ?background:string ->
  ?foreground:string ->
  ?border_color:string ->
  ?border_width:int ->
  ?corner_radius:int ->
  ?width:int ->
  ?height:int ->
  ?min_width:int ->
  ?max_width:int ->
  ?min_height:int ->
  ?max_height:int ->
  ?container_relative_frame:string ->
  ?container_relative_frame_inset:int ->
  ?accessibility_identifier:string ->
  ?accessibility_identifier_signal:string Signal.signal ->
  ?foreground_signal:string Signal.signal ->
  ?background_signal:string Signal.signal ->
  ?style_class:string ->
  ?on_appear:(Lui_protocol.event -> unit) ->
  ?text:string ->
  ?text_signal:string Signal.signal ->
  ?on_dismiss:(Lui_protocol.event -> unit) -> t list -> t
val tooltip :
  ?key:string ->
  ?gap:int ->
  ?main:string ->
  ?cross:string ->
  ?grow:float ->
  ?columns:int ->
  ?padding:int ->
  ?padding_horizontal:int ->
  ?padding_vertical:int ->
  ?background:string ->
  ?foreground:string ->
  ?border_color:string ->
  ?border_width:int ->
  ?corner_radius:int ->
  ?width:int ->
  ?height:int ->
  ?min_width:int ->
  ?max_width:int ->
  ?min_height:int ->
  ?max_height:int ->
  ?container_relative_frame:string ->
  ?container_relative_frame_inset:int ->
  ?accessibility_identifier:string ->
  ?accessibility_identifier_signal:string Signal.signal ->
  ?foreground_signal:string Signal.signal ->
  ?background_signal:string Signal.signal ->
  ?style_class:string ->
  ?on_appear:(Lui_protocol.event -> unit) ->
  ?text:string ->
  ?text_signal:string Signal.signal ->
  ?anchor:string ->
  ?anchor_alignment:string ->
  ?anchor_offset:float -> ?tooltip_delay:int -> t list -> t
val toast :
  ?key:string ->
  ?gap:int ->
  ?main:string ->
  ?cross:string ->
  ?grow:float ->
  ?columns:int ->
  ?padding:int ->
  ?padding_horizontal:int ->
  ?padding_vertical:int ->
  ?background:string ->
  ?foreground:string ->
  ?border_color:string ->
  ?border_width:int ->
  ?corner_radius:int ->
  ?width:int ->
  ?height:int ->
  ?min_width:int ->
  ?max_width:int ->
  ?min_height:int ->
  ?max_height:int ->
  ?container_relative_frame:string ->
  ?container_relative_frame_inset:int ->
  ?accessibility_identifier:string ->
  ?accessibility_identifier_signal:string Signal.signal ->
  ?foreground_signal:string Signal.signal ->
  ?background_signal:string Signal.signal ->
  ?style_class:string ->
  ?on_appear:(Lui_protocol.event -> unit) ->
  ?duration:int ->
  ?label:string ->
  ?toast_class:string ->
  ?on_dismiss:(Lui_protocol.event -> unit) -> t list -> t
val toolbar :
  ?key:string ->
  ?gap:int ->
  ?main:string ->
  ?cross:string ->
  ?grow:float ->
  ?columns:int ->
  ?padding:int ->
  ?padding_horizontal:int ->
  ?padding_vertical:int ->
  ?background:string ->
  ?foreground:string ->
  ?border_color:string ->
  ?border_width:int ->
  ?corner_radius:int ->
  ?width:int ->
  ?height:int ->
  ?min_width:int ->
  ?max_width:int ->
  ?min_height:int ->
  ?max_height:int ->
  ?container_relative_frame:string ->
  ?container_relative_frame_inset:int ->
  ?accessibility_identifier:string ->
  ?accessibility_identifier_signal:string Signal.signal ->
  ?foreground_signal:string Signal.signal ->
  ?background_signal:string Signal.signal ->
  ?style_class:string ->
  ?on_appear:(Lui_protocol.event -> unit) ->
  ?orientation:string ->
  ?label:string -> ?toolbar_gap:int -> ?toolbar_class:string -> t list -> t
val accordion :
  ?key:string ->
  ?gap:int ->
  ?main:string ->
  ?cross:string ->
  ?grow:float ->
  ?columns:int ->
  ?padding:int ->
  ?padding_horizontal:int ->
  ?padding_vertical:int ->
  ?background:string ->
  ?foreground:string ->
  ?border_color:string ->
  ?border_width:int ->
  ?corner_radius:int ->
  ?width:int ->
  ?height:int ->
  ?min_width:int ->
  ?max_width:int ->
  ?min_height:int ->
  ?max_height:int ->
  ?container_relative_frame:string ->
  ?container_relative_frame_inset:int ->
  ?accessibility_identifier:string ->
  ?accessibility_identifier_signal:string Signal.signal ->
  ?foreground_signal:string Signal.signal ->
  ?background_signal:string Signal.signal ->
  ?style_class:string ->
  ?on_appear:(Lui_protocol.event -> unit) ->
  ?text:string ->
  ?text_signal:string Signal.signal ->
  ?selected:bool ->
  ?accordion_height:int ->
  ?on_toggle:(Lui_protocol.event -> unit) -> t list -> t
val menu_item :
  ?key:string ->
  ?gap:int ->
  ?main:string ->
  ?cross:string ->
  ?grow:float ->
  ?columns:int ->
  ?padding:int ->
  ?padding_horizontal:int ->
  ?padding_vertical:int ->
  ?background:string ->
  ?foreground:string ->
  ?border_color:string ->
  ?border_width:int ->
  ?corner_radius:int ->
  ?width:int ->
  ?height:int ->
  ?min_width:int ->
  ?max_width:int ->
  ?min_height:int ->
  ?max_height:int ->
  ?container_relative_frame:string ->
  ?container_relative_frame_inset:int ->
  ?accessibility_identifier:string ->
  ?accessibility_identifier_signal:string Signal.signal ->
  ?foreground_signal:string Signal.signal ->
  ?background_signal:string Signal.signal ->
  ?style_class:string ->
  ?on_appear:(Lui_protocol.event -> unit) ->
  ?text:string ->
  ?text_signal:string Signal.signal ->
  ?icon:string ->
  ?role:string ->
  ?tree_level:int ->
  ?expanded:bool ->
  ?disabled:bool ->
  ?disabled_signal:bool Signal.signal ->
  ?on_press:(Lui_protocol.event -> unit) ->
  ?on_input:(Lui_protocol.event -> unit) ->
  ?on_submit:(Lui_protocol.event -> unit) ->
  ?on_dismiss:(Lui_protocol.event -> unit) -> t list -> t
val list_item :
  ?key:string ->
  ?gap:int ->
  ?main:string ->
  ?cross:string ->
  ?grow:float ->
  ?columns:int ->
  ?padding:int ->
  ?padding_horizontal:int ->
  ?padding_vertical:int ->
  ?background:string ->
  ?foreground:string ->
  ?border_color:string ->
  ?border_width:int ->
  ?corner_radius:int ->
  ?width:int ->
  ?height:int ->
  ?min_width:int ->
  ?max_width:int ->
  ?min_height:int ->
  ?max_height:int ->
  ?container_relative_frame:string ->
  ?container_relative_frame_inset:int ->
  ?accessibility_identifier:string ->
  ?accessibility_identifier_signal:string Signal.signal ->
  ?foreground_signal:string Signal.signal ->
  ?background_signal:string Signal.signal ->
  ?style_class:string ->
  ?on_appear:(Lui_protocol.event -> unit) ->
  ?text:string ->
  ?text_signal:string Signal.signal ->
  ?icon:string ->
  ?icon_placement:string ->
  ?role:string ->
  ?tree_level:int ->
  ?expanded:bool ->
  ?selected:bool ->
  ?selected_signal:bool Signal.signal ->
  ?disabled:bool ->
  ?disabled_signal:bool Signal.signal ->
  ?on_press:(Lui_protocol.event -> unit) ->
  ?on_long_press:(Lui_protocol.event -> unit) ->
  ?on_double_press:(Lui_protocol.event -> unit) ->
  ?on_submit:(Lui_protocol.event -> unit) ->
  ?on_input:(Lui_protocol.event -> unit) ->
  ?on_toggle:(Lui_protocol.event -> unit) -> t list -> t
val avatar :
  ?key:string ->
  ?gap:int ->
  ?main:string ->
  ?cross:string ->
  ?grow:float ->
  ?columns:int ->
  ?padding:int ->
  ?padding_horizontal:int ->
  ?padding_vertical:int ->
  ?background:string ->
  ?foreground:string ->
  ?border_color:string ->
  ?border_width:int ->
  ?corner_radius:int ->
  ?width:int ->
  ?height:int ->
  ?min_width:int ->
  ?max_width:int ->
  ?min_height:int ->
  ?max_height:int ->
  ?container_relative_frame:string ->
  ?container_relative_frame_inset:int ->
  ?accessibility_identifier:string ->
  ?accessibility_identifier_signal:string Signal.signal ->
  ?foreground_signal:string Signal.signal ->
  ?background_signal:string Signal.signal ->
  ?style_class:string ->
  ?on_appear:(Lui_protocol.event -> unit) ->
  ?text:string ->
  ?text_signal:string Signal.signal ->
  ?image:int ->
  ?image_signal:int Signal.signal ->
  ?source_x:float ->
  ?source_y:float ->
  ?source_width:float -> ?source_height:float -> ?label:string -> t list -> t
val image :
  ?key:string ->
  ?gap:int ->
  ?main:string ->
  ?cross:string ->
  ?grow:float ->
  ?columns:int ->
  ?padding:int ->
  ?padding_horizontal:int ->
  ?padding_vertical:int ->
  ?background:string ->
  ?foreground:string ->
  ?border_color:string ->
  ?border_width:int ->
  ?corner_radius:int ->
  ?width:int ->
  ?height:int ->
  ?min_width:int ->
  ?max_width:int ->
  ?min_height:int ->
  ?max_height:int ->
  ?container_relative_frame:string ->
  ?container_relative_frame_inset:int ->
  ?accessibility_identifier:string ->
  ?accessibility_identifier_signal:string Signal.signal ->
  ?foreground_signal:string Signal.signal ->
  ?background_signal:string Signal.signal ->
  ?style_class:string ->
  ?on_appear:(Lui_protocol.event -> unit) ->
  ?image:int ->
  ?image_signal:int Signal.signal ->
  ?source_x:float ->
  ?source_y:float ->
  ?source_width:float -> ?source_height:float -> ?label:string -> t list -> t
val media_surface :
  ?key:string ->
  ?gap:int ->
  ?main:string ->
  ?cross:string ->
  ?grow:float ->
  ?columns:int ->
  ?padding:int ->
  ?padding_horizontal:int ->
  ?padding_vertical:int ->
  ?background:string ->
  ?foreground:string ->
  ?border_color:string ->
  ?border_width:int ->
  ?corner_radius:int ->
  ?width:int ->
  ?height:int ->
  ?min_width:int ->
  ?max_width:int ->
  ?min_height:int ->
  ?max_height:int ->
  ?container_relative_frame:string ->
  ?container_relative_frame_inset:int ->
  ?accessibility_identifier:string ->
  ?accessibility_identifier_signal:string Signal.signal ->
  ?foreground_signal:string Signal.signal ->
  ?background_signal:string Signal.signal ->
  ?style_class:string ->
  ?on_appear:(Lui_protocol.event -> unit) ->
  ?surface:int ->
  ?surface_signal:int Signal.signal -> ?label:string -> t list -> t
val stepper :
  ?key:string ->
  ?gap:int ->
  ?main:string ->
  ?cross:string ->
  ?grow:float ->
  ?columns:int ->
  ?padding:int ->
  ?padding_horizontal:int ->
  ?padding_vertical:int ->
  ?background:string ->
  ?foreground:string ->
  ?border_color:string ->
  ?border_width:int ->
  ?corner_radius:int ->
  ?width:int ->
  ?height:int ->
  ?min_width:int ->
  ?max_width:int ->
  ?min_height:int ->
  ?max_height:int ->
  ?container_relative_frame:string ->
  ?container_relative_frame_inset:int ->
  ?accessibility_identifier:string ->
  ?accessibility_identifier_signal:string Signal.signal ->
  ?foreground_signal:string Signal.signal ->
  ?background_signal:string Signal.signal ->
  ?style_class:string ->
  ?on_appear:(Lui_protocol.event -> unit) ->
  ?active:int ->
  ?active_signal:int Signal.signal -> ?label:string -> t list -> t
val step :
  ?key:string ->
  ?gap:int ->
  ?main:string ->
  ?cross:string ->
  ?grow:float ->
  ?columns:int ->
  ?padding:int ->
  ?padding_horizontal:int ->
  ?padding_vertical:int ->
  ?background:string ->
  ?foreground:string ->
  ?border_color:string ->
  ?border_width:int ->
  ?corner_radius:int ->
  ?width:int ->
  ?height:int ->
  ?min_width:int ->
  ?max_width:int ->
  ?min_height:int ->
  ?max_height:int ->
  ?container_relative_frame:string ->
  ?container_relative_frame_inset:int ->
  ?accessibility_identifier:string ->
  ?accessibility_identifier_signal:string Signal.signal ->
  ?foreground_signal:string Signal.signal ->
  ?background_signal:string Signal.signal ->
  ?style_class:string ->
  ?on_appear:(Lui_protocol.event -> unit) ->
  ?text:string -> ?text_signal:string Signal.signal -> t list -> t
val timeline :
  ?key:string ->
  ?gap:int ->
  ?main:string ->
  ?cross:string ->
  ?grow:float ->
  ?columns:int ->
  ?padding:int ->
  ?padding_horizontal:int ->
  ?padding_vertical:int ->
  ?background:string ->
  ?foreground:string ->
  ?border_color:string ->
  ?border_width:int ->
  ?corner_radius:int ->
  ?width:int ->
  ?height:int ->
  ?min_width:int ->
  ?max_width:int ->
  ?min_height:int ->
  ?max_height:int ->
  ?container_relative_frame:string ->
  ?container_relative_frame_inset:int ->
  ?accessibility_identifier:string ->
  ?accessibility_identifier_signal:string Signal.signal ->
  ?foreground_signal:string Signal.signal ->
  ?background_signal:string Signal.signal ->
  ?style_class:string ->
  ?on_appear:(Lui_protocol.event -> unit) -> ?label:string -> t list -> t
val timeline_item :
  ?key:string ->
  ?gap:int ->
  ?main:string ->
  ?cross:string ->
  ?grow:float ->
  ?columns:int ->
  ?padding:int ->
  ?padding_horizontal:int ->
  ?padding_vertical:int ->
  ?background:string ->
  ?foreground:string ->
  ?border_color:string ->
  ?border_width:int ->
  ?corner_radius:int ->
  ?width:int ->
  ?height:int ->
  ?min_width:int ->
  ?max_width:int ->
  ?min_height:int ->
  ?max_height:int ->
  ?container_relative_frame:string ->
  ?container_relative_frame_inset:int ->
  ?accessibility_identifier:string ->
  ?accessibility_identifier_signal:string Signal.signal ->
  ?foreground_signal:string Signal.signal ->
  ?background_signal:string Signal.signal ->
  ?style_class:string ->
  ?on_appear:(Lui_protocol.event -> unit) ->
  ?title:string ->
  ?title_signal:string Signal.signal ->
  ?description:string ->
  ?meta:string ->
  ?indicator:string ->
  ?icon:string ->
  ?variant:string ->
  ?connector:bool ->
  ?selected:bool -> ?on_press:(Lui_protocol.event -> unit) -> t list -> t
