(** Element DSL: typed constructors returning mount closures
    [t = ui_context -> int option -> int], e.g. [row ~gap:4 \[ child \]].
    Every prop has a static [~p] and a reactive [~p_signal] twin; [dyn],
    [if_], and [keyed] mount reactive structure, while [~p_signal] updates
    props in place. *)

type t = Lui_ui.ui_context -> int option -> int

(** Closed vocabularies from the wire schema: every parameter that only
    accepts a fixed set of values is a polymorphic variant so wrong values
    fail [dune build] instead of erroring inside [emit_patch]. *)

type variant =
  [ `default | `primary | `secondary | `outline | `ghost | `destructive ]

type control_size = [ `default | `sm | `lg | `icon ]
type text_size = [ `heading | `display ]

(** [table_cell] accepts control sizes and text sizes on its [~size]. *)
type cell_size = [ control_size | text_size ]

type main_alignment = [ `start | `center | `end_ | `space_between ]
type cross_alignment = [ `stretch | `start | `center | `end_ ]
type text_alignment = [ `start | `center | `end_ ]
type orientation = [ `horizontal | `vertical ]
type icon_placement = [ `leading | `trailing | `top ]
type anchor = [ `above | `below | `left | `right ]
type anchor_alignment = [ `start | `end_ | `stretch ]

type frame_axes =
  [ `horizontal | `vertical | `both
  | `min_horizontal | `min_vertical | `min_both ]

type resize_easing = [ `linear | `standard | `emphasized | `spring ]
type role = [ `treeitem | `navigation | `navigation_heading ]

(** [~icon]/[~name] values: the schema icon names, or [`app "name"] for an
    application-registered icon ([app:name] on the wire). *)
type icon =
  [ `alert | `archive | `arrow_down | `arrow_right | `arrow_up | `check | `check_circle | `chevron_down | `chevron_left | `chevron_right | `chevron_up | `circle_dot | `clock | `copy | `download | `edit | `ellipsis | `external_link | `eye | `file_text | `folder | `folder_open | `git_branch | `git_merge | `git_pull_request | `info | `menu | `mic | `moon | `music | `panel_left | `panel_right | `pause | `play | `plus | `refresh_cw | `repeat | `save | `search | `send | `settings | `shuffle | `skip_back | `skip_forward | `sun | `terminal | `trash | `volume | `wrench | `x | `x_circle
  | `app of string ]

(** Element kinds the schema restricts to specific parents. These are
    abstract so illegal nesting fails at compile time: [step_el] inside
    [stepper], [timeline_item_el] inside [timeline], [bottom_tab_el] inside
    [bottom_tabs], [table_row_el] inside [table], [table_cell_el] inside
    [table_row], [radio_el] inside [radio_group], and
    [input_group_actions_el] as the optional [~actions] of [input_group]. *)

type step_el
type timeline_item_el
type bottom_tab_el
type table_row_el
type table_cell_el
type radio_el
type input_group_actions_el

(** Empty type: [leaf] constructors take a [nothing list] children slot, so
    [] compiles and any real child is a type error. *)
type nothing = |
val mount : 'a -> ?parent:'b -> ('a -> 'b option -> 'c) -> 'c
val reactive : ('a -> 'b) -> 'a Signal.signal -> 'b Signal.signal
val map : ('a -> 'b) -> 'a Signal.signal -> 'b Signal.signal
val sample : 'a Signal.signal -> 'a
val ( >|= ) : 'a Signal.signal -> ('a -> 'b) -> 'b Signal.signal

(** [get sig] reads a signal's current value without subscribing — alias of
    {!Signal.sample}. Use {!get_state} on a [Signal.state]. *)
val get : 'a Signal.signal -> 'a

(** [get_state st] reads a state's current value — {!get} of
    {!Signal.value} [st]. *)
val get_state : 'a Signal.state -> 'a
val attach : Lui_ui.ui_context -> int option -> int -> unit
val enable :
  Lui_ui.ui_context -> int -> Lui_protocol.Property_map.key -> unit
val mount_children : 'a -> 'b -> ('a -> 'b option -> 'c) list -> unit
val dynamic : (Lui_ui.ui_context -> int -> 'a) -> t

(** [dyn ~equal f source] mounts [f model] under the parent node and remounts
    it whenever the published model differs under [equal]. There is no
    default: always pass a structural or field-wise equality (e.g. [(=)] or
    [fun a b -> a.id = b.id]) so the subtree is left untouched when the change
    does not affect this branch. A remount reconciles the new branch against
    the old one: nodes of the same kind at the same position keep their ids
    (platform views stay alive, scroll/focus state survives) and receive prop
    diffs instead of drop+create churn. Structural changes remount only the
    divergent nodes. *)
val dyn :
  equal:('a -> 'a -> bool) -> ('a -> t) -> 'a Signal.signal -> t
val if_ : test:bool Signal.signal -> t -> t

(** [keyed ~source ~key ~cmp ~mount] renders one mounted child per item of
    [source], keyed by [key item] and diffed with [cmp] — a three-way
    comparator returning [int] like {!Stdlib.compare}
    ([~cmp:Stdlib.compare] for most cases), not a less-than predicate. *)
val keyed :
  source:'a list Signal.signal ->
  key:('a -> 'b) ->
  cmp:('b -> 'b -> int) ->
  mount:('a Signal.signal -> t) -> t

(** Event-handler builders: element [~on_*] parameters take an
    [event -> unit] callback and imply their enable flags automatically
    (never pass [*-enabled] props yourself). [press send action] dispatches
    [action] on press — e.g. [~on_press:(press send Save)]. *)
val press : ('a -> bool) -> 'a -> Lui_protocol.event -> unit

(** [on_input send wrap] builds a text-input handler: decodes the
    [TextChanged] payload and dispatches [wrap text] — e.g.
    [~on_input:(on_input send (fun s -> Changed s))]. *)
val on_input :
  ('a -> bool) -> (string -> 'a) -> Lui_protocol.event -> unit

(** [on_event ctx node filter handler] registers [handler] for raw events
    matching [filter] (see {!is_press}, {!is_input}, ...) — the low-level
    escape hatch when the [~on_*] parameters are not enough. *)
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
  main:main_alignment option ->
  cross:cross_alignment option ->
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
  container_relative_frame:frame_axes option ->
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
  ?main:main_alignment ->
  ?cross:cross_alignment ->
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
  ?container_relative_frame:frame_axes ->
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
  ?main:main_alignment ->
  ?cross:cross_alignment ->
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
  ?container_relative_frame:frame_axes ->
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
  ?main:main_alignment ->
  ?cross:cross_alignment ->
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
  ?container_relative_frame:frame_axes ->
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
  ?main:main_alignment ->
  ?cross:cross_alignment ->
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
  ?container_relative_frame:frame_axes ->
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
  ?main:main_alignment ->
  ?cross:cross_alignment ->
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
  ?container_relative_frame:frame_axes ->
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
  ?main:main_alignment ->
  ?cross:cross_alignment ->
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
  ?container_relative_frame:frame_axes ->
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
  ?main:main_alignment ->
  ?cross:cross_alignment ->
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
  ?container_relative_frame:frame_axes ->
  ?container_relative_frame_inset:int ->
  ?accessibility_identifier:string ->
  ?accessibility_identifier_signal:string Signal.signal ->
  ?foreground_signal:string Signal.signal ->
  ?background_signal:string Signal.signal ->
  ?style_class:string ->
  ?on_appear:(Lui_protocol.event -> unit) ->
  ?text:string ->
  ?text_signal:string Signal.signal ->
  ?variant:variant -> ?text_alignment:text_alignment -> ?label:string -> t list -> t
val bubble :
  ?key:string ->
  ?gap:int ->
  ?main:main_alignment ->
  ?cross:cross_alignment ->
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
  ?container_relative_frame:frame_axes ->
  ?container_relative_frame_inset:int ->
  ?accessibility_identifier:string ->
  ?accessibility_identifier_signal:string Signal.signal ->
  ?foreground_signal:string Signal.signal ->
  ?background_signal:string Signal.signal ->
  ?style_class:string ->
  ?on_appear:(Lui_protocol.event -> unit) ->
  ?text:string ->
  ?text_signal:string Signal.signal ->
  ?variant:variant -> ?label:string -> t list -> t
val box :
  ?key:string ->
  ?gap:int ->
  ?main:main_alignment ->
  ?cross:cross_alignment ->
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
  ?container_relative_frame:frame_axes ->
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
  ?main:main_alignment ->
  ?cross:cross_alignment ->
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
  ?container_relative_frame:frame_axes ->
  ?container_relative_frame_inset:int ->
  ?accessibility_identifier:string ->
  ?accessibility_identifier_signal:string Signal.signal ->
  ?foreground_signal:string Signal.signal ->
  ?background_signal:string Signal.signal ->
  ?style_class:string ->
  ?on_appear:(Lui_protocol.event -> unit) ->
  ?orientation:orientation -> t list -> t
val list :
  ?key:string ->
  ?gap:int ->
  ?main:main_alignment ->
  ?cross:cross_alignment ->
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
  ?container_relative_frame:frame_axes ->
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
  ?main:main_alignment ->
  ?cross:cross_alignment ->
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
  ?container_relative_frame:frame_axes ->
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
  ?main:main_alignment ->
  ?cross:cross_alignment ->
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
  ?container_relative_frame:frame_axes ->
  ?container_relative_frame_inset:int ->
  ?accessibility_identifier:string ->
  ?accessibility_identifier_signal:string Signal.signal ->
  ?foreground_signal:string Signal.signal ->
  ?background_signal:string Signal.signal ->
  ?style_class:string ->
  ?on_appear:(Lui_protocol.event -> unit) ->
  ?label:string -> ?orientation:orientation -> t list -> t
val bottom_tabs :
  ?key:string ->
  ?gap:int ->
  ?main:main_alignment ->
  ?cross:cross_alignment ->
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
  ?container_relative_frame:frame_axes ->
  ?container_relative_frame_inset:int ->
  ?accessibility_identifier:string ->
  ?accessibility_identifier_signal:string Signal.signal ->
  ?foreground_signal:string Signal.signal ->
  ?background_signal:string Signal.signal ->
  ?style_class:string ->
  ?on_appear:(Lui_protocol.event -> unit) ->
  ?label:string -> bottom_tab_el list -> t
val bottom_tab :
  ?key:string ->
  ?gap:int ->
  ?main:main_alignment ->
  ?cross:cross_alignment ->
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
  ?container_relative_frame:frame_axes ->
  ?container_relative_frame_inset:int ->
  ?accessibility_identifier:string ->
  ?accessibility_identifier_signal:string Signal.signal ->
  ?foreground_signal:string Signal.signal ->
  ?background_signal:string Signal.signal ->
  ?style_class:string ->
  ?on_appear:(Lui_protocol.event -> unit) ->
  ?title:string ->
  ?icon:icon ->
  ?selected:bool ->
  ?selected_signal:bool Signal.signal ->
  ?enabled:bool ->
  ?enabled_signal:bool Signal.signal ->
  ?on_press:(Lui_protocol.event -> unit) -> t list -> bottom_tab_el
val button_group :
  ?key:string ->
  ?gap:int ->
  ?main:main_alignment ->
  ?cross:cross_alignment ->
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
  ?container_relative_frame:frame_axes ->
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
  ?main:main_alignment ->
  ?cross:cross_alignment ->
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
  ?container_relative_frame:frame_axes ->
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
  ?main:main_alignment ->
  ?cross:cross_alignment ->
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
  ?container_relative_frame:frame_axes ->
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
  ?main:main_alignment ->
  ?cross:cross_alignment ->
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
  ?container_relative_frame:frame_axes ->
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
  ?main:main_alignment ->
  ?cross:cross_alignment ->
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
  ?container_relative_frame:frame_axes ->
  ?container_relative_frame_inset:int ->
  ?accessibility_identifier:string ->
  ?accessibility_identifier_signal:string Signal.signal ->
  ?foreground_signal:string Signal.signal ->
  ?background_signal:string Signal.signal ->
  ?style_class:string ->
  ?on_appear:(Lui_protocol.event -> unit) -> table_row_el list -> t
val table_row :
  ?key:string ->
  ?gap:int ->
  ?main:main_alignment ->
  ?cross:cross_alignment ->
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
  ?container_relative_frame:frame_axes ->
  ?container_relative_frame_inset:int ->
  ?accessibility_identifier:string ->
  ?accessibility_identifier_signal:string Signal.signal ->
  ?foreground_signal:string Signal.signal ->
  ?background_signal:string Signal.signal ->
  ?style_class:string ->
  ?on_appear:(Lui_protocol.event -> unit) ->
  ?selected:bool -> ?selected_signal:bool Signal.signal -> table_cell_el list -> table_row_el
val table_cell :
  ?key:string ->
  ?gap:int ->
  ?main:main_alignment ->
  ?cross:cross_alignment ->
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
  ?container_relative_frame:frame_axes ->
  ?container_relative_frame_inset:int ->
  ?accessibility_identifier:string ->
  ?accessibility_identifier_signal:string Signal.signal ->
  ?foreground_signal:string Signal.signal ->
  ?background_signal:string Signal.signal ->
  ?style_class:string ->
  ?on_appear:(Lui_protocol.event -> unit) ->
  ?text:string ->
  ?text_signal:string Signal.signal ->
  ?size:cell_size ->
  ?text_alignment:text_alignment ->
  ?on_press:(Lui_protocol.event -> unit) -> t list -> table_cell_el
val tree :
  ?key:string ->
  ?gap:int ->
  ?main:main_alignment ->
  ?cross:cross_alignment ->
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
  ?container_relative_frame:frame_axes ->
  ?container_relative_frame_inset:int ->
  ?accessibility_identifier:string ->
  ?accessibility_identifier_signal:string Signal.signal ->
  ?foreground_signal:string Signal.signal ->
  ?background_signal:string Signal.signal ->
  ?style_class:string ->
  ?on_appear:(Lui_protocol.event -> unit) ->
  ?label:string ->
  ?role:role ->
  ?tree_level:int ->
  ?expanded:bool ->
  ?expanded_signal:bool Signal.signal ->
  ?on_press:(Lui_protocol.event -> unit) ->
  ?on_change:(Lui_protocol.event -> unit) ->
  ?on_toggle:(Lui_protocol.event -> unit) -> t list -> t
val resizable :
  ?key:string ->
  ?gap:int ->
  ?main:main_alignment ->
  ?cross:cross_alignment ->
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
  ?container_relative_frame:frame_axes ->
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
  ?main:main_alignment ->
  ?cross:cross_alignment ->
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
  ?container_relative_frame:frame_axes ->
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
  ?resize_easing:resize_easing ->
  ?resize_origin:float ->
  ?label:string -> ?on_resize:(Lui_protocol.event -> unit) -> t -> t -> t
val drawer :
  ?key:string ->
  ?gap:int ->
  ?main:main_alignment ->
  ?cross:cross_alignment ->
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
  ?container_relative_frame:frame_axes ->
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
  ?label:string -> ?on_toggle:(Lui_protocol.event -> unit) -> t -> t -> t
val status_bar :
  ?key:string ->
  ?gap:int ->
  ?main:main_alignment ->
  ?cross:cross_alignment ->
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
  ?container_relative_frame:frame_axes ->
  ?container_relative_frame_inset:int ->
  ?accessibility_identifier:string ->
  ?accessibility_identifier_signal:string Signal.signal ->
  ?foreground_signal:string Signal.signal ->
  ?background_signal:string Signal.signal ->
  ?style_class:string ->
  ?on_appear:(Lui_protocol.event -> unit) ->
  ?value:string ->
  ?value_signal:string Signal.signal -> ?text_alignment:text_alignment -> nothing list -> t
val spacer :
  ?key:string ->
  ?gap:int ->
  ?main:main_alignment ->
  ?cross:cross_alignment ->
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
  ?container_relative_frame:frame_axes ->
  ?container_relative_frame_inset:int ->
  ?accessibility_identifier:string ->
  ?accessibility_identifier_signal:string Signal.signal ->
  ?foreground_signal:string Signal.signal ->
  ?background_signal:string Signal.signal ->
  ?style_class:string ->
  ?on_appear:(Lui_protocol.event -> unit) -> nothing list -> t
val spinner :
  ?key:string ->
  ?gap:int ->
  ?main:main_alignment ->
  ?cross:cross_alignment ->
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
  ?container_relative_frame:frame_axes ->
  ?container_relative_frame_inset:int ->
  ?accessibility_identifier:string ->
  ?accessibility_identifier_signal:string Signal.signal ->
  ?foreground_signal:string Signal.signal ->
  ?background_signal:string Signal.signal ->
  ?style_class:string ->
  ?on_appear:(Lui_protocol.event -> unit) -> ?size:control_size -> nothing list -> t
val icon :
  ?key:string ->
  ?gap:int ->
  ?main:main_alignment ->
  ?cross:cross_alignment ->
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
  ?container_relative_frame:frame_axes ->
  ?container_relative_frame_inset:int ->
  ?accessibility_identifier:string ->
  ?accessibility_identifier_signal:string Signal.signal ->
  ?foreground_signal:string Signal.signal ->
  ?background_signal:string Signal.signal ->
  ?style_class:string ->
  ?on_appear:(Lui_protocol.event -> unit) ->
  ?name:icon ->
  ?name_signal:icon Signal.signal -> ?size:control_size ->
  ?point_size:int -> nothing list -> t
val text :
  ?key:string ->
  ?gap:int ->
  ?main:main_alignment ->
  ?cross:cross_alignment ->
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
  ?container_relative_frame:frame_axes ->
  ?container_relative_frame_inset:int ->
  ?accessibility_identifier:string ->
  ?accessibility_identifier_signal:string Signal.signal ->
  ?foreground_signal:string Signal.signal ->
  ?background_signal:string Signal.signal ->
  ?style_class:string ->
  ?on_appear:(Lui_protocol.event -> unit) ->
  ?value:string ->
  ?value_signal:string Signal.signal ->
  ?text_alignment:text_alignment ->
  ?on_press:(Lui_protocol.event -> unit) -> t list -> t
val heading :
  ?key:string ->
  ?gap:int ->
  ?main:main_alignment ->
  ?cross:cross_alignment ->
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
  ?container_relative_frame:frame_axes ->
  ?container_relative_frame_inset:int ->
  ?accessibility_identifier:string ->
  ?accessibility_identifier_signal:string Signal.signal ->
  ?foreground_signal:string Signal.signal ->
  ?background_signal:string Signal.signal ->
  ?style_class:string ->
  ?on_appear:(Lui_protocol.event -> unit) ->
  ?level:int ->
  ?value:string -> ?value_signal:string Signal.signal -> nothing list -> t
val paragraph :
  ?key:string ->
  ?gap:int ->
  ?main:main_alignment ->
  ?cross:cross_alignment ->
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
  ?container_relative_frame:frame_axes ->
  ?container_relative_frame_inset:int ->
  ?accessibility_identifier:string ->
  ?accessibility_identifier_signal:string Signal.signal ->
  ?foreground_signal:string Signal.signal ->
  ?background_signal:string Signal.signal ->
  ?style_class:string ->
  ?on_appear:(Lui_protocol.event -> unit) ->
  ?value:string -> ?value_signal:string Signal.signal -> nothing list -> t
val label :
  ?key:string ->
  ?gap:int ->
  ?main:main_alignment ->
  ?cross:cross_alignment ->
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
  ?container_relative_frame:frame_axes ->
  ?container_relative_frame_inset:int ->
  ?accessibility_identifier:string ->
  ?accessibility_identifier_signal:string Signal.signal ->
  ?foreground_signal:string Signal.signal ->
  ?background_signal:string Signal.signal ->
  ?style_class:string ->
  ?on_appear:(Lui_protocol.event -> unit) ->
  ?value:string -> ?value_signal:string Signal.signal -> nothing list -> t
val button :
  ?key:string ->
  ?gap:int ->
  ?main:main_alignment ->
  ?cross:cross_alignment ->
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
  ?container_relative_frame:frame_axes ->
  ?container_relative_frame_inset:int ->
  ?accessibility_identifier:string ->
  ?accessibility_identifier_signal:string Signal.signal ->
  ?foreground_signal:string Signal.signal ->
  ?background_signal:string Signal.signal ->
  ?style_class:string ->
  ?on_appear:(Lui_protocol.event -> unit) ->
  ?text:string ->
  ?text_signal:string Signal.signal ->
  ?variant:variant ->
  ?size:control_size ->
  ?icon:icon ->
  ?icon_placement:icon_placement ->
  ?label:string ->
  ?text_alignment:text_alignment ->
  ?selected:bool ->
  ?autofocus:bool ->
  ?disabled:bool ->
  ?disabled_signal:bool Signal.signal ->
  ?on_press:(Lui_protocol.event -> unit) ->
  ?on_long_press:(Lui_protocol.event -> unit) -> t list -> t
val toggle_button :
  ?key:string ->
  ?gap:int ->
  ?main:main_alignment ->
  ?cross:cross_alignment ->
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
  ?container_relative_frame:frame_axes ->
  ?container_relative_frame_inset:int ->
  ?accessibility_identifier:string ->
  ?accessibility_identifier_signal:string Signal.signal ->
  ?foreground_signal:string Signal.signal ->
  ?background_signal:string Signal.signal ->
  ?style_class:string ->
  ?on_appear:(Lui_protocol.event -> unit) ->
  ?text:string ->
  ?text_signal:string Signal.signal ->
  ?variant:variant ->
  ?size:control_size ->
  ?icon:icon ->
  ?icon_placement:icon_placement ->
  ?label:string ->
  ?text_alignment:text_alignment ->
  ?selected:bool ->
  ?checked:bool ->
  ?checked_signal:bool Signal.signal ->
  ?autofocus:bool ->
  ?disabled:bool ->
  ?disabled_signal:bool Signal.signal ->
  ?on_press:(Lui_protocol.event -> unit) ->
  ?on_toggle:(Lui_protocol.event -> unit) ->
  ?on_long_press:(Lui_protocol.event -> unit) -> t list -> t
val checkbox :
  ?key:string ->
  ?gap:int ->
  ?main:main_alignment ->
  ?cross:cross_alignment ->
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
  ?container_relative_frame:frame_axes ->
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
  ?main:main_alignment ->
  ?cross:cross_alignment ->
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
  ?container_relative_frame:frame_axes ->
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
  ?main:main_alignment ->
  ?cross:cross_alignment ->
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
  ?container_relative_frame:frame_axes ->
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
  ?main:main_alignment ->
  ?cross:cross_alignment ->
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
  ?container_relative_frame:frame_axes ->
  ?container_relative_frame_inset:int ->
  ?accessibility_identifier:string ->
  ?accessibility_identifier_signal:string Signal.signal ->
  ?foreground_signal:string Signal.signal ->
  ?background_signal:string Signal.signal ->
  ?style_class:string ->
  ?on_appear:(Lui_protocol.event -> unit) -> ?label:string -> radio_el list -> t
val radio :
  ?key:string ->
  ?gap:int ->
  ?main:main_alignment ->
  ?cross:cross_alignment ->
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
  ?container_relative_frame:frame_axes ->
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
  ?on_press:(Lui_protocol.event -> unit) -> t list -> radio_el
val slider :
  ?key:string ->
  ?gap:int ->
  ?main:main_alignment ->
  ?cross:cross_alignment ->
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
  ?container_relative_frame:frame_axes ->
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
  ?main:main_alignment ->
  ?cross:cross_alignment ->
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
  ?container_relative_frame:frame_axes ->
  ?container_relative_frame_inset:int ->
  ?accessibility_identifier:string ->
  ?accessibility_identifier_signal:string Signal.signal ->
  ?foreground_signal:string Signal.signal ->
  ?background_signal:string Signal.signal ->
  ?style_class:string ->
  ?on_appear:(Lui_protocol.event -> unit) ->
  ?value:float -> ?value_signal:float Signal.signal -> nothing list -> t
val divider :
  ?key:string ->
  ?gap:int ->
  ?main:main_alignment ->
  ?cross:cross_alignment ->
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
  ?container_relative_frame:frame_axes ->
  ?container_relative_frame_inset:int ->
  ?accessibility_identifier:string ->
  ?accessibility_identifier_signal:string Signal.signal ->
  ?foreground_signal:string Signal.signal ->
  ?background_signal:string Signal.signal ->
  ?style_class:string ->
  ?on_appear:(Lui_protocol.event -> unit) ->
  ?orientation:orientation -> nothing list -> t
val separator :
  ?key:string ->
  ?gap:int ->
  ?main:main_alignment ->
  ?cross:cross_alignment ->
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
  ?container_relative_frame:frame_axes ->
  ?container_relative_frame_inset:int ->
  ?accessibility_identifier:string ->
  ?accessibility_identifier_signal:string Signal.signal ->
  ?foreground_signal:string Signal.signal ->
  ?background_signal:string Signal.signal ->
  ?style_class:string ->
  ?on_appear:(Lui_protocol.event -> unit) ->
  ?orientation:orientation -> nothing list -> t
val text_field :
  ?key:string ->
  ?gap:int ->
  ?main:main_alignment ->
  ?cross:cross_alignment ->
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
  ?container_relative_frame:frame_axes ->
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
  ?main:main_alignment ->
  ?cross:cross_alignment ->
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
  ?container_relative_frame:frame_axes ->
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
  ?main:main_alignment ->
  ?cross:cross_alignment ->
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
  ?container_relative_frame:frame_axes ->
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
  ?main:main_alignment ->
  ?cross:cross_alignment ->
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
  ?container_relative_frame:frame_axes ->
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
  ?main:main_alignment ->
  ?cross:cross_alignment ->
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
  ?container_relative_frame:frame_axes ->
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
  ?main:main_alignment ->
  ?cross:cross_alignment ->
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
  ?container_relative_frame:frame_axes ->
  ?container_relative_frame_inset:int ->
  ?accessibility_identifier:string ->
  ?accessibility_identifier_signal:string Signal.signal ->
  ?foreground_signal:string Signal.signal ->
  ?background_signal:string Signal.signal ->
  ?style_class:string ->
  ?on_appear:(Lui_protocol.event -> unit) -> ?label:string -> ?actions:input_group_actions_el -> t -> t
val input_group_actions :
  ?key:string ->
  ?gap:int ->
  ?main:main_alignment ->
  ?cross:cross_alignment ->
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
  ?container_relative_frame:frame_axes ->
  ?container_relative_frame_inset:int ->
  ?accessibility_identifier:string ->
  ?accessibility_identifier_signal:string Signal.signal ->
  ?foreground_signal:string Signal.signal ->
  ?background_signal:string Signal.signal ->
  ?style_class:string ->
  ?on_appear:(Lui_protocol.event -> unit) -> t list -> input_group_actions_el
val select :
  ?key:string ->
  ?gap:int ->
  ?main:main_alignment ->
  ?cross:cross_alignment ->
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
  ?container_relative_frame:frame_axes ->
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
  ?main:main_alignment ->
  ?cross:cross_alignment ->
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
  ?container_relative_frame:frame_axes ->
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
  ?main:main_alignment ->
  ?cross:cross_alignment ->
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
  ?container_relative_frame:frame_axes ->
  ?container_relative_frame_inset:int ->
  ?accessibility_identifier:string ->
  ?accessibility_identifier_signal:string Signal.signal ->
  ?foreground_signal:string Signal.signal ->
  ?background_signal:string Signal.signal ->
  ?style_class:string ->
  ?on_appear:(Lui_protocol.event -> unit) ->
  ?anchor:anchor ->
  ?anchor_alignment:anchor_alignment ->
  ?anchor_offset:float ->
  ?on_press:(Lui_protocol.event -> unit) ->
  ?on_input:(Lui_protocol.event -> unit) ->
  ?on_submit:(Lui_protocol.event -> unit) ->
  ?on_dismiss:(Lui_protocol.event -> unit) -> t list -> t
val context_menu :
  ?key:string ->
  ?gap:int ->
  ?main:main_alignment ->
  ?cross:cross_alignment ->
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
  ?container_relative_frame:frame_axes ->
  ?container_relative_frame_inset:int ->
  ?accessibility_identifier:string ->
  ?accessibility_identifier_signal:string Signal.signal ->
  ?foreground_signal:string Signal.signal ->
  ?background_signal:string Signal.signal ->
  ?style_class:string ->
  ?on_appear:(Lui_protocol.event -> unit) ->
  ?disabled:bool -> ?disabled_signal:bool Signal.signal -> t list -> t
val submenu :
  ?key:string ->
  ?text:string ->
  ?icon:icon ->
  ?role:role ->
  ?variant:variant ->
  ?selected:bool ->
  ?checked:bool ->
  ?disabled:bool ->
  ?on_dismiss:(Lui_protocol.event -> unit) -> t list -> t
val dialog :
  ?key:string ->
  ?gap:int ->
  ?main:main_alignment ->
  ?cross:cross_alignment ->
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
  ?container_relative_frame:frame_axes ->
  ?container_relative_frame_inset:int ->
  ?accessibility_identifier:string ->
  ?accessibility_identifier_signal:string Signal.signal ->
  ?foreground_signal:string Signal.signal ->
  ?background_signal:string Signal.signal ->
  ?style_class:string ->
  ?on_appear:(Lui_protocol.event -> unit) ->
  ?text:string ->
  ?text_signal:string Signal.signal ->
  ?description:string ->
  ?description_signal:string Signal.signal ->
  ?on_dismiss:(Lui_protocol.event -> unit) -> t list -> t
val sheet :
  ?key:string ->
  ?gap:int ->
  ?main:main_alignment ->
  ?cross:cross_alignment ->
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
  ?container_relative_frame:frame_axes ->
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
  ?main:main_alignment ->
  ?cross:cross_alignment ->
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
  ?container_relative_frame:frame_axes ->
  ?container_relative_frame_inset:int ->
  ?accessibility_identifier:string ->
  ?accessibility_identifier_signal:string Signal.signal ->
  ?foreground_signal:string Signal.signal ->
  ?background_signal:string Signal.signal ->
  ?style_class:string ->
  ?on_appear:(Lui_protocol.event -> unit) ->
  ?text:string ->
  ?text_signal:string Signal.signal ->
  ?anchor:anchor ->
  ?anchor_alignment:anchor_alignment ->
  ?anchor_offset:float -> ?tooltip_delay:int -> nothing list -> t
val toast :
  ?key:string ->
  ?gap:int ->
  ?main:main_alignment ->
  ?cross:cross_alignment ->
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
  ?container_relative_frame:frame_axes ->
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
  ?main:main_alignment ->
  ?cross:cross_alignment ->
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
  ?container_relative_frame:frame_axes ->
  ?container_relative_frame_inset:int ->
  ?accessibility_identifier:string ->
  ?accessibility_identifier_signal:string Signal.signal ->
  ?foreground_signal:string Signal.signal ->
  ?background_signal:string Signal.signal ->
  ?style_class:string ->
  ?on_appear:(Lui_protocol.event -> unit) ->
  ?orientation:orientation ->
  ?label:string -> ?toolbar_gap:int -> ?toolbar_class:string -> t list -> t
val accordion :
  ?key:string ->
  ?gap:int ->
  ?main:main_alignment ->
  ?cross:cross_alignment ->
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
  ?container_relative_frame:frame_axes ->
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
  ?main:main_alignment ->
  ?cross:cross_alignment ->
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
  ?container_relative_frame:frame_axes ->
  ?container_relative_frame_inset:int ->
  ?accessibility_identifier:string ->
  ?accessibility_identifier_signal:string Signal.signal ->
  ?foreground_signal:string Signal.signal ->
  ?background_signal:string Signal.signal ->
  ?style_class:string ->
  ?on_appear:(Lui_protocol.event -> unit) ->
  ?text:string ->
  ?text_signal:string Signal.signal ->
  ?icon:icon ->
  ?role:role ->
  ?variant:variant ->
  ?size:control_size ->
  ?tree_level:int ->
  ?expanded:bool ->
  ?selected:bool ->
  ?checked:bool ->
  ?selected_signal:bool Signal.signal ->
  ?checked_signal:bool Signal.signal ->
  ?disabled:bool ->
  ?disabled_signal:bool Signal.signal ->
  ?on_press:(Lui_protocol.event -> unit) ->
  ?on_input:(Lui_protocol.event -> unit) ->
  ?on_submit:(Lui_protocol.event -> unit) ->
  ?on_dismiss:(Lui_protocol.event -> unit) -> t list -> t
val list_item :
  ?key:string ->
  ?gap:int ->
  ?main:main_alignment ->
  ?cross:cross_alignment ->
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
  ?container_relative_frame:frame_axes ->
  ?container_relative_frame_inset:int ->
  ?accessibility_identifier:string ->
  ?accessibility_identifier_signal:string Signal.signal ->
  ?foreground_signal:string Signal.signal ->
  ?background_signal:string Signal.signal ->
  ?style_class:string ->
  ?on_appear:(Lui_protocol.event -> unit) ->
  ?text:string ->
  ?text_signal:string Signal.signal ->
  ?icon:icon ->
  ?icon_placement:icon_placement ->
  ?role:role ->
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
  ?main:main_alignment ->
  ?cross:cross_alignment ->
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
  ?container_relative_frame:frame_axes ->
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
  ?source_width:float -> ?source_height:float -> ?label:string -> nothing list -> t
val image :
  ?key:string ->
  ?gap:int ->
  ?main:main_alignment ->
  ?cross:cross_alignment ->
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
  ?container_relative_frame:frame_axes ->
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
  ?source_width:float -> ?source_height:float -> ?label:string -> nothing list -> t
val media_surface :
  ?key:string ->
  ?gap:int ->
  ?main:main_alignment ->
  ?cross:cross_alignment ->
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
  ?container_relative_frame:frame_axes ->
  ?container_relative_frame_inset:int ->
  ?accessibility_identifier:string ->
  ?accessibility_identifier_signal:string Signal.signal ->
  ?foreground_signal:string Signal.signal ->
  ?background_signal:string Signal.signal ->
  ?style_class:string ->
  ?on_appear:(Lui_protocol.event -> unit) ->
  ?surface:int ->
  ?surface_signal:int Signal.signal -> ?label:string -> nothing list -> t
val stepper :
  ?key:string ->
  ?gap:int ->
  ?main:main_alignment ->
  ?cross:cross_alignment ->
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
  ?container_relative_frame:frame_axes ->
  ?container_relative_frame_inset:int ->
  ?accessibility_identifier:string ->
  ?accessibility_identifier_signal:string Signal.signal ->
  ?foreground_signal:string Signal.signal ->
  ?background_signal:string Signal.signal ->
  ?style_class:string ->
  ?on_appear:(Lui_protocol.event -> unit) ->
  ?active:int ->
  ?active_signal:int Signal.signal -> ?label:string -> step_el list -> t
val step :
  ?key:string ->
  ?gap:int ->
  ?main:main_alignment ->
  ?cross:cross_alignment ->
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
  ?container_relative_frame:frame_axes ->
  ?container_relative_frame_inset:int ->
  ?accessibility_identifier:string ->
  ?accessibility_identifier_signal:string Signal.signal ->
  ?foreground_signal:string Signal.signal ->
  ?background_signal:string Signal.signal ->
  ?style_class:string ->
  ?on_appear:(Lui_protocol.event -> unit) ->
  ?text:string -> ?text_signal:string Signal.signal -> nothing list -> step_el
val timeline :
  ?key:string ->
  ?gap:int ->
  ?main:main_alignment ->
  ?cross:cross_alignment ->
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
  ?container_relative_frame:frame_axes ->
  ?container_relative_frame_inset:int ->
  ?accessibility_identifier:string ->
  ?accessibility_identifier_signal:string Signal.signal ->
  ?foreground_signal:string Signal.signal ->
  ?background_signal:string Signal.signal ->
  ?style_class:string ->
  ?on_appear:(Lui_protocol.event -> unit) -> ?label:string -> timeline_item_el list -> t
val timeline_item :
  ?key:string ->
  ?gap:int ->
  ?main:main_alignment ->
  ?cross:cross_alignment ->
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
  ?container_relative_frame:frame_axes ->
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
  ?icon:icon ->
  ?variant:variant ->
  ?connector:bool ->
  ?selected:bool -> ?on_press:(Lui_protocol.event -> unit) -> nothing list -> timeline_item_el
