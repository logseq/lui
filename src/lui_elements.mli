(** Element DSL: typed constructors returning mount closures
    [t = ui_context -> int option -> int], e.g. [row ~gap:4 \[ child \]].
    Every prop has a static [~p] and a reactive [~p_signal] twin; [dyn],
    [if_], and [keyed] mount reactive structure, while [~p_signal] updates
    props in place. With [lui_ppx] enabled, [reactive] is the single
    reactive form: [~p:(reactive f s)] rewrites to a prop signal and a
    [reactive f s] expression in a children list rewrites to [dyn f s]. *)

type t = Lui_ui.ui_context -> int option -> int

type pointer_detail = Lui_protocol.pointer_detail
type toggle_detail = Lui_event_payloads.toggle_detail = { checked : bool; modifiers : int }
type navigation_key = Lui_event_payloads.navigation_key = { key : string; shift : bool }
type scroll_completed = Lui_event_payloads.scroll_completed = { token : int; outcome : string }
type range = Lui_event_payloads.range = { first : int; last : int }
type scroll_edges = Lui_event_payloads.scroll_edges = { at_start : bool; at_end : bool }
type navigation = Lui_event_payloads.navigation = Previous | Next | Key of navigation_key
type visible_range = Lui_event_payloads.visible_range = Range of range | Edges of scroll_edges

(** Closed vocabularies from the wire schema: every parameter that only
    accepts a fixed set of values is a polymorphic variant so wrong values
    fail [dune build] instead of erroring inside [emit_patch]. *)

type variant =
  [ `default | `primary | `secondary | `outline | `ghost | `destructive ]

type button_size = [ `default | `sm | `lg ]
type control_size = [ button_size | `icon ]
type text_size = [ `heading | `display ]

(** [table_cell] accepts control sizes and text sizes on its [~size]. *)
type cell_size = [ control_size | text_size ]

type main_alignment = [ `start | `center | `end_ | `space_between ]
type cross_alignment = [ `stretch | `start | `center | `end_ ]
type image_fit = [ `fit | `fill ]

type text_alignment = [ `start | `center | `end_ ]
type orientation = [ `horizontal | `vertical ]
type icon_placement = [ `leading | `trailing | `top ]
type anchor = [ `above | `below | `left | `right ]
type anchor_alignment = [ `start | `center | `end_ | `stretch ]

type edge = [ `top | `bottom | `leading | `trailing ]

(** Two-dimensional alignment for [overlay] content: a corner, an edge
    center, or [center]. *)
type alignment =
  [ `top_leading | `top | `top_trailing
  | `leading | `center | `trailing
  | `bottom_leading | `bottom | `bottom_trailing ]

type frame_axes =
  [ `horizontal | `vertical | `both
  | `min_horizontal | `min_vertical | `min_both ]

type resize_easing = [ `linear | `standard | `emphasized | `spring ]
type role = [ `treeitem | `navigation | `navigation_heading ]
type list_style = [ `plain | `inset | `inset_grouped ]

(** CSS [list-style] marker for [list]/[virtual_list]/[list_item] —
    distinct from [list_style], the SwiftUI-style container appearance
    passed as [~style]. *)
type list_marker = [ `none | `disc | `decimal ]
type scroll_anchor = [ `top | `center | `bottom | `nearest ]
type separator_visibility = [ `visible | `hidden ]

(** Platform vocabulary re-exported from {!Lui_protocol} so view code can
    match on {!Lui_ui.platform} / {!Lui_ui.host} results without opening
    the wire-protocol module. *)
type operating_system = Lui_protocol.operating_system =
  | GenericOS
  | WebOS
  | MacOS
  | IOS
  | AndroidOS
  | LinuxOS
  | WindowsOS

type host_kind = Lui_protocol.host_kind =
  | GenericHost
  | WebHost
  | SwiftUIHost
  | KotlinHost

type image_loading = [ `eager | `lazy_ ]

type referrer_policy =
  [ `no_referrer | `origin | `strict_origin_when_cross_origin | `unsafe_url ]

type link_target = [ `self_ | `blank ]

type display =
  [ `contents | `none | `block | `inline | `inline_block | `inline_flex ]

type flex_wrap = [ `nowrap | `wrap ]
type input_kind = [ `text | `color | `time ]
type popover_role = [ `dialog | `menu ]
type swipe_edge = [ `leading | `trailing ]

(** [~as_] semantic element-tag overrides on web. Textual kinds admit
    phrasing-appropriate tags; columns admit [div], [ul], [ol], and rows
    admit [div], [li]. Layout and child contracts remain unchanged. See
    {!Lui_protocol.element_tag_supported}; the per-family types match that predicate, and native hosts ignore the prop. *)
type heading_level = [ `h1 | `h2 | `h3 | `h4 | `h5 | `h6 ]
type toolbar_placement = [ `automatic | `bottom | `navigation | `principal | `primary_action | `secondary_action | `status | `confirmation_action | `cancellation_action | `destructive_action | `top_bar_leading | `top_bar_trailing ]
type sheet_sizing = [ `form | `fitted | `page ]
type font_style = [ `normal | `italic | `oblique ]
type white_space = [ `normal | `nowrap | `pre_wrap | `pre_line ]
type text_overflow = [ `clip | `ellipsis ]
type overflow = [ `visible | `hidden | `auto ]
type phrasing_tag = [ `Span | `Em | `Strong | `B | `I | `U | `S | `Del | `Mark | `Small | `Code | `Kbd | `Sub | `Sup | `Pre ]
type heading_tag = [ `H1 | `H2 | `H3 | `H4 | `H5 | `H6 ]
type paragraph_tag = [ `P | `Span | `Div | `Pre ]
type label_tag = [ `Label | `Span | `Div ]
type list_container_tag = [ `Div | `Ul | `Ol ]
type row_tag = [ `Div | `Li ]

type anchor_source =
  | Parent
  | Target of string
  | Rect of { x : float; y : float; width : float; height : float }

type popover_target =
  | Cover
  | At of float * float
  | Anchor of {
      side : anchor;
      source : anchor_source;
      align : anchor_alignment;
      offset : float;
      align_offset : float;
    }

type split_sizing = Fraction of float | First_width of float

type split_motion = {
  duration_ms : int;
  easing : resize_easing;
  origin : float option;
}


(** [~source] of {!file_picker}: [`files] presents a document importer,
    [`photos] the photo library, [`camera] live capture (iOS only —
    other platforms answer the request with a dismiss event). *)
type file_picker_source = [ `files | `photos | `camera ]

(** [~request] / [~completion] of {!file_picker}: an opaque token echoed
    back in [picked] payloads. String tokens cover UUID-style identifiers;
    int tokens cover counters. *)
type file_picker_token = [ `String of string | `Int of int ]

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
type swipe_action_el

(** Empty type: [leaf] constructors take a [nothing list] children slot, so
    [] compiles and any real child is a type error. *)
type nothing = |
val mount : 'a -> ?parent:'b -> ('a -> 'b option -> 'c) -> 'c
val scoped : (Lui_ui.ui_context -> t) -> t
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

type error_diagnostic = {
  exception_ : exn;
  message : string;
  state_path : string;
  phase : [ `Mount | `Update ];
}

(** Isolate mount and owned reactive view failures behind a transparent box.
    The failed child scope is disposed and runtime writes are rolled back
    before mounting [fallback]. The fallback is latched until this boundary
    is remounted; later source publications do not retry the failed child.
    Fallback failures propagate to an enclosing boundary (or the caller).
    External signal producers, event handlers and backend failures are not
    intercepted. *)
val error_boundary : fallback:(error_diagnostic -> t) -> t -> t
val enable :
  Lui_ui.ui_context -> int -> Lui_protocol.Property_map.key -> unit
val mount_children : 'a -> 'b -> ('a -> 'b option -> 'c) list -> unit
val dynamic : (Lui_ui.ui_context -> int -> 'a) -> t

(** Physical equality followed by structural equality, treating incomparable
    functional values as changed. Used by children-position [reactive]. *)
val default_subtree_equal : 'a -> 'a -> bool

(** [dyn ?equal f source] mounts [f model] under the parent node and
    remounts it whenever the published model differs under [equal]
    (default [default_subtree_equal]). A remount reconciles the new branch against the old
    one: nodes of the same kind at the same position keep their ids
    (platform views stay alive, scroll/focus state survives) and receive
    prop diffs instead of drop+create churn. Structural changes remount
    only the divergent nodes.

    Implementation detail: [lui_ppx] expands a children-position
    [reactive f s] into this call — write [reactive f s ~equal:eq]
    instead of calling [dyn] directly. *)
val dyn :
  ?equal:('a -> 'a -> bool) -> ('a -> t) -> 'a Signal.signal -> t

(** [if_ ~test child] mounts [child] under the parent while
    [test] publishes [true] and removes it on [false]. *)
val if_ : test:bool Signal.signal -> t -> t

(** [keyed ~source ~key ~cmp ~mount] renders one mounted child
    per item of [source], keyed by [key item] and diffed with
    [cmp] — a three-way comparator returning [int] like {!Stdlib.compare}
    ([~cmp:Stdlib.compare] for most cases), not a less-than predicate. *)
val keyed :
  source:'a list Signal.signal ->
  key:('a -> 'b) ->
  cmp:('b -> 'b -> int) ->
  mount:('a Signal.signal -> t) -> t

(** A viewport-managed keyed source. Use as the sole child of
    {!virtual_list}. Business data remains in [source]; only the requested
    window and active interaction pins own mounted row scopes. Persistent
    editor state belongs in the application model. [scroll_key] maps the
    existing string scroll targets to source items and is required when a
    lazy parent has a nonempty scroll target. Older hosts render eagerly. *)
val virtual_rows :
  ?scroll_key:('a -> string) ->
  source:'a list Signal.signal ->
  key:('a -> 'b) ->
  cmp:('b -> 'b -> int) ->
  mount:('a Signal.signal -> t) -> unit -> t

(** [keyed_*] are {!keyed} specialised to the abstract child types: a
    keyed collection mounts its items directly under the restricted
    parent node, so each variant can sit in the corresponding [_el list]
    child slot — e.g. [radio_group [keyed_radio ~mount:(fun s -> radio ...)]] —
    while [~mount] is still checked to produce that element kind. *)
val keyed_step :
  source:'a list Signal.signal ->
  key:('a -> 'b) ->
  cmp:('b -> 'b -> int) ->
  mount:('a Signal.signal -> step_el) -> step_el
val keyed_timeline_item :
  source:'a list Signal.signal ->
  key:('a -> 'b) ->
  cmp:('b -> 'b -> int) ->
  mount:('a Signal.signal -> timeline_item_el) -> timeline_item_el
val keyed_bottom_tab :
  source:'a list Signal.signal ->
  key:('a -> 'b) ->
  cmp:('b -> 'b -> int) ->
  mount:('a Signal.signal -> bottom_tab_el) -> bottom_tab_el
val keyed_table_row :
  source:'a list Signal.signal ->
  key:('a -> 'b) ->
  cmp:('b -> 'b -> int) ->
  mount:('a Signal.signal -> table_row_el) -> table_row_el
val keyed_table_cell :
  source:'a list Signal.signal ->
  key:('a -> 'b) ->
  cmp:('b -> 'b -> int) ->
  mount:('a Signal.signal -> table_cell_el) -> table_cell_el
val keyed_radio :
  source:'a list Signal.signal ->
  key:('a -> 'b) ->
  cmp:('b -> 'b -> int) ->
  mount:('a Signal.signal -> radio_el) -> radio_el
val keyed_swipe_action :
  source:'a list Signal.signal ->
  key:('a -> 'b) ->
  cmp:('b -> 'b -> int) ->
  mount:('a Signal.signal -> swipe_action_el) -> swipe_action_el

(** Event-handler builders: element [~on_*] parameters take a
    payload-specific callback and imply their enable flags automatically
    (never pass [*-enabled] props yourself). [press send action] dispatches
    [action] on press — e.g. [~on_press:(press send Save)]. *)
val press : ('a -> bool) -> 'a -> unit -> unit

(** [on_input send wrap] builds a text-input handler: dispatches
    [wrap text] — e.g.
    [~on_input:(on_input send (fun s -> Changed s))]. *)
val on_input :
  ('a -> bool) -> (string -> 'a) -> string -> unit

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
val is_navigate : Lui_protocol.event -> bool
val is_submit : Lui_protocol.event -> bool
val is_toggle : Lui_protocol.event -> bool
val is_dismiss : Lui_protocol.event -> bool
val is_appear : Lui_protocol.event -> bool
val is_resize : Lui_protocol.event -> bool
val register_press :
  Lui_ui.ui_context -> int -> (unit -> unit) -> unit
val register_long_press :
  Lui_ui.ui_context -> int -> (unit -> unit) -> unit
val register_double_press :
  Lui_ui.ui_context -> int -> (unit -> unit) -> unit
val register_change :
  Lui_ui.ui_context -> int -> (unit -> unit) -> unit
val register_input :
  Lui_ui.ui_context -> int -> (string -> unit) -> unit
val register_submit :
  Lui_ui.ui_context -> int -> (unit -> unit) -> unit

(** Text inputs opt in to unmodified Up/Down as
    [NavigatePrevious]/[NavigateNext]. Buttons opt in to arrow, Home/End and
    PageUp/PageDown [NavigationKey] events, retaining the Shift flag.
    Other modifier combinations keep their shortcut behavior.
    For text inputs, Window and Web hosts retain focus and the text selection;
    modified arrows and IME composition keep their editing behavior. *)
val register_navigate :
  Lui_ui.ui_context -> int -> (navigation -> unit) -> unit
val register_toggle :
  Lui_ui.ui_context -> int -> (bool -> unit) -> unit
val register_dismiss :
  Lui_ui.ui_context -> int -> (unit -> unit) -> unit
val appear_handler :
  Lui_ui.ui_context -> int -> (unit -> unit) -> unit
val register_resize :
  Lui_ui.ui_context -> int -> (float -> unit) -> unit

(** [~data_attrs] / [~data_attrs_signal] attach raw DOM attributes —
    [data-*], [aria-*], [role], [tabindex] and [draggable] only
    ([Lui_protocol.data_attr_name_ok] is enforced at call time). This is
    a web DOM contract for delegated-event readers, CSS attribute
    selectors and e2e locators; native hosts parse-ignore the prop. *)
val row :
  ?as_:row_tag ->
  ?key:string ->
  ?gap:int ->
  ?main:main_alignment ->
  ?cross:cross_alignment ->
  ?grow:float ->
  ?shrink:float ->
  ?orientation:orientation ->
  ?orientation_signal:orientation Signal.signal ->
  ?padding:int ->
  ?padding_horizontal:int ->
  ?padding_vertical:int ->
  ?margin:int ->
  ?margin_horizontal:int ->
  ?margin_vertical:int ->
  ?margin_top:int ->
  ?margin_right:int ->
  ?margin_bottom:int ->
  ?margin_left:int ->
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
  ?data_attrs:(string * string) list ->
  ?data_attrs_signal:(string * string) list Signal.signal ->
  ?on_focus_within:(bool -> unit) ->
  ?on_appear:(unit -> unit) ->
  ?on_pointer_enter:(unit -> unit) ->
  ?on_pointer_leave:(unit -> unit) ->
  ?pointer_capture:bool ->
  ?on_pointer_down:(pointer_detail -> unit) ->
  ?on_pointer_move:(pointer_detail -> unit) ->
  ?on_pointer_up:(pointer_detail -> unit) ->
  ?on_pointer_cancel:(pointer_detail -> unit) ->
  ?on_navigation_key:(navigation_key -> unit) ->
  ?opacity:float ->
  ?opacity_signal:float Signal.signal ->
  ?display:display ->
  ?flex_wrap:flex_wrap ->
  ?transition:string -> t list -> t
val column :
  ?as_:list_container_tag ->
  ?key:string ->
  ?gap:int ->
  ?main:main_alignment ->
  ?cross:cross_alignment ->
  ?grow:float ->
  ?shrink:float ->
  ?grow_signal:float Signal.signal ->
  ?padding:int ->
  ?padding_horizontal:int ->
  ?padding_vertical:int ->
  ?margin:int ->
  ?margin_horizontal:int ->
  ?margin_vertical:int ->
  ?margin_top:int ->
  ?margin_right:int ->
  ?margin_bottom:int ->
  ?margin_left:int ->
  ?background:string ->
  ?foreground:string ->
  ?border_color:string ->
  ?border_width:int ->
  ?corner_radius:int ->
  ?width:int ->
  ?height:int ->
  ?min_width:int ->
  ?min_width_signal:int Signal.signal ->
  ?max_width:int ->
  ?max_width_signal:int Signal.signal ->
  ?min_height:int ->
  ?max_height:int ->
  ?container_relative_frame:frame_axes ->
  ?container_relative_frame_inset:int ->
  ?accessibility_identifier:string ->
  ?accessibility_identifier_signal:string Signal.signal ->
  ?foreground_signal:string Signal.signal ->
  ?background_signal:string Signal.signal ->
  ?style_class:string ->
  ?data_attrs:(string * string) list ->
  ?data_attrs_signal:(string * string) list Signal.signal ->
  ?on_focus_within:(bool -> unit) ->
  ?on_appear:(unit -> unit) ->
  ?on_pointer_enter:(unit -> unit) ->
  ?on_pointer_leave:(unit -> unit) ->
  ?on_press_detail:(pointer_detail -> unit) ->
  ?on_pointer_down:(pointer_detail -> unit) ->
  ?on_pointer_up:(pointer_detail -> unit) ->
  ?opacity:float ->
  ?opacity_signal:float Signal.signal ->
  ?display:display ->
  ?display_signal:display Signal.signal ->
  ?flex_wrap:flex_wrap ->
  ?transition:string -> t list -> t
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
  ?margin:int ->
  ?margin_horizontal:int ->
  ?margin_vertical:int ->
  ?margin_top:int ->
  ?margin_right:int ->
  ?margin_bottom:int ->
  ?margin_left:int ->
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
  ?data_attrs:(string * string) list ->
  ?data_attrs_signal:(string * string) list Signal.signal ->
  ?on_appear:(unit -> unit) ->
  ?on_pointer_enter:(unit -> unit) ->
  ?on_pointer_leave:(unit -> unit) ->
  ?opacity:float ->
  ?opacity_signal:float Signal.signal ->
  ?transition:string -> t list -> t
val stack :
  ?key:string ->
  ?grow:float ->
  ?padding:int ->
  ?padding_horizontal:int ->
  ?padding_vertical:int ->
  ?margin:int ->
  ?margin_horizontal:int ->
  ?margin_vertical:int ->
  ?margin_top:int ->
  ?margin_right:int ->
  ?margin_bottom:int ->
  ?margin_left:int ->
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
  ?data_attrs:(string * string) list ->
  ?data_attrs_signal:(string * string) list Signal.signal ->
  ?on_appear:(unit -> unit) ->
  ?on_pointer_enter:(unit -> unit) ->
  ?on_pointer_leave:(unit -> unit) ->
  ?opacity:float ->
  ?opacity_signal:float Signal.signal ->
  ?transition:string -> t list -> t

(** [edge_inset ~edge \[content; pinned; ...\]] pins every child after the
    first to [edge] while [content] fills the view and scrolls beneath
    (`.safeAreaInset`). [~visible:false] hides the pinned children in place
    (animated) without unmounting them; [~visible_signal] toggles it
    reactively. The element's own surface props style the pinned region, so
    e.g. [~background:"bar"] gives a material chrome bar. [~gap] sets the
    spacing between [content] and the pinned children (default 0). *)
val edge_inset :
  ?key:string ->
  ?gap:int ->
  ?grow:float ->
  ?padding:int ->
  ?padding_horizontal:int ->
  ?padding_vertical:int ->
  ?margin:int ->
  ?margin_horizontal:int ->
  ?margin_vertical:int ->
  ?margin_top:int ->
  ?margin_right:int ->
  ?margin_bottom:int ->
  ?margin_left:int ->
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
  ?data_attrs:(string * string) list ->
  ?data_attrs_signal:(string * string) list Signal.signal ->
  ?on_appear:(unit -> unit) ->
  ?on_pointer_enter:(unit -> unit) ->
  ?on_pointer_leave:(unit -> unit) ->
  edge:edge ->
  ?visible:bool ->
  ?visible_signal:bool Signal.signal ->
  ?opacity:float ->
  ?opacity_signal:float Signal.signal ->
  ?transition:string -> t list -> t

(** [overlay \[base; overlay_child; ...\]] renders the children after the
    first floating over [base] without affecting its layout. Each overlay
    child positions itself by its own [alignment] hint (set with {!align}),
    falling back to the [overlay]'s [~alignment] (default [`center]). *)
val overlay :
  ?key:string ->
  ?grow:float ->
  ?padding:int ->
  ?padding_horizontal:int ->
  ?padding_vertical:int ->
  ?margin:int ->
  ?margin_horizontal:int ->
  ?margin_vertical:int ->
  ?margin_top:int ->
  ?margin_right:int ->
  ?margin_bottom:int ->
  ?margin_left:int ->
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
  ?data_attrs:(string * string) list ->
  ?data_attrs_signal:(string * string) list Signal.signal ->
  ?on_appear:(unit -> unit) ->
  ?on_pointer_enter:(unit -> unit) ->
  ?on_pointer_leave:(unit -> unit) ->
  ?alignment:alignment ->
  ?opacity:float ->
  ?opacity_signal:float Signal.signal ->
  ?transition:string -> t list -> t

(** [align a child] sets [child]'s [alignment] hint, honored when [child]
    is mounted as an [overlay] child — e.g.
    [overlay \[base; align `top_trailing controls\]]. Inert elsewhere. *)
val align : alignment -> t -> t

(** [view_that_fits \[first; fallback; ...\]] renders the first child that
    fits along [~orientation] (default [`horizontal`]; [ViewThatFits]). *)
val view_that_fits :
  ?key:string ->
  ?grow:float ->
  ?padding:int ->
  ?padding_horizontal:int ->
  ?padding_vertical:int ->
  ?margin:int ->
  ?margin_horizontal:int ->
  ?margin_vertical:int ->
  ?margin_top:int ->
  ?margin_right:int ->
  ?margin_bottom:int ->
  ?margin_left:int ->
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
  ?data_attrs:(string * string) list ->
  ?data_attrs_signal:(string * string) list Signal.signal ->
  ?on_appear:(unit -> unit) ->
  ?on_pointer_enter:(unit -> unit) ->
  ?on_pointer_leave:(unit -> unit) ->
  ?orientation:orientation ->
  ?opacity:float ->
  ?opacity_signal:float Signal.signal ->
  ?transition:string -> t list -> t
val panel :
  ?key:string ->
  ?gap:int ->
  ?main:main_alignment ->
  ?cross:cross_alignment ->
  ?grow:float ->
  ?padding:int ->
  ?padding_horizontal:int ->
  ?padding_vertical:int ->
  ?margin:int ->
  ?margin_horizontal:int ->
  ?margin_vertical:int ->
  ?margin_top:int ->
  ?margin_right:int ->
  ?margin_bottom:int ->
  ?margin_left:int ->
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
  ?data_attrs:(string * string) list ->
  ?data_attrs_signal:(string * string) list Signal.signal ->
  ?on_appear:(unit -> unit) ->
  ?on_pointer_enter:(unit -> unit) ->
  ?on_pointer_leave:(unit -> unit) ->
  ?opacity:float ->
  ?opacity_signal:float Signal.signal ->
  ?transition:string -> t list -> t
val card :
  ?key:string ->
  ?gap:int ->
  ?main:main_alignment ->
  ?cross:cross_alignment ->
  ?grow:float ->
  ?padding:int ->
  ?padding_horizontal:int ->
  ?padding_vertical:int ->
  ?margin:int ->
  ?margin_horizontal:int ->
  ?margin_vertical:int ->
  ?margin_top:int ->
  ?margin_right:int ->
  ?margin_bottom:int ->
  ?margin_left:int ->
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
  ?data_attrs:(string * string) list ->
  ?data_attrs_signal:(string * string) list Signal.signal ->
  ?on_appear:(unit -> unit) ->
  ?on_pointer_enter:(unit -> unit) ->
  ?on_pointer_leave:(unit -> unit) ->
  ?opacity:float ->
  ?opacity_signal:float Signal.signal ->
  ?transition:string -> t list -> t
val alert :
  ?key:string ->
  ?grow:float ->
  ?padding:int ->
  ?padding_horizontal:int ->
  ?padding_vertical:int ->
  ?margin:int ->
  ?margin_horizontal:int ->
  ?margin_vertical:int ->
  ?margin_top:int ->
  ?margin_right:int ->
  ?margin_bottom:int ->
  ?margin_left:int ->
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
  ?data_attrs:(string * string) list ->
  ?data_attrs_signal:(string * string) list Signal.signal ->
  ?on_appear:(unit -> unit) ->
  ?on_pointer_enter:(unit -> unit) ->
  ?on_pointer_leave:(unit -> unit) ->
  ?text:string ->
  ?text_signal:string Signal.signal ->
  ?variant:variant -> ?label:string ->
  ?opacity:float ->
  ?opacity_signal:float Signal.signal ->
  ?transition:string -> t list -> t
val bubble :
  ?key:string ->
  ?grow:float ->
  ?padding:int ->
  ?padding_horizontal:int ->
  ?padding_vertical:int ->
  ?margin:int ->
  ?margin_horizontal:int ->
  ?margin_vertical:int ->
  ?margin_top:int ->
  ?margin_right:int ->
  ?margin_bottom:int ->
  ?margin_left:int ->
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
  ?data_attrs:(string * string) list ->
  ?data_attrs_signal:(string * string) list Signal.signal ->
  ?on_appear:(unit -> unit) ->
  ?on_pointer_enter:(unit -> unit) ->
  ?on_pointer_leave:(unit -> unit) ->
  ?text:string ->
  ?text_signal:string Signal.signal ->
  ?variant:variant -> ?label:string ->
  ?opacity:float ->
  ?opacity_signal:float Signal.signal ->
  ?transition:string -> t list -> t

(** [inert] suspends Web DOM and OCaml native subtree interaction while
    retaining layout and paint. Floating surfaces keep their own lifecycle. *)
val box :
  ?key:string ->
  ?gap:int ->
  ?main:main_alignment ->
  ?cross:cross_alignment ->
  ?grow:float ->
  ?shrink:float ->
  ?padding:int ->
  ?padding_horizontal:int ->
  ?padding_vertical:int ->
  ?margin:int ->
  ?margin_horizontal:int ->
  ?margin_vertical:int ->
  ?margin_top:int ->
  ?margin_right:int ->
  ?margin_bottom:int ->
  ?margin_left:int ->
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
  ?data_attrs:(string * string) list ->
  ?data_attrs_signal:(string * string) list Signal.signal ->
  ?on_focus_within:(bool -> unit) ->
  ?on_appear:(unit -> unit) ->
  ?on_pointer_enter:(unit -> unit) ->
  ?on_pointer_leave:(unit -> unit) ->
  ?pointer_capture:bool ->
  ?on_pointer_down:(pointer_detail -> unit) ->
  ?on_pointer_move:(pointer_detail -> unit) ->
  ?on_pointer_up:(pointer_detail -> unit) ->
  ?on_pointer_cancel:(pointer_detail -> unit) ->
  ?on_navigation_key:(navigation_key -> unit) ->
  ?opacity:float ->
  ?opacity_signal:float Signal.signal ->
  ?display:display ->
  ?flex_wrap:flex_wrap ->
  ?inert:bool ->
  ?inert_signal:bool Signal.signal ->
  ?transition:string -> t list -> t
val scroll :
  ?virtual_owner:Lui_virtual.owner ->
  ?key:string ->
  ?gap:int ->
  ?grow:float ->
  ?padding:int ->
  ?padding_horizontal:int ->
  ?padding_vertical:int ->
  ?margin:int ->
  ?margin_horizontal:int ->
  ?margin_vertical:int ->
  ?margin_top:int ->
  ?margin_right:int ->
  ?margin_bottom:int ->
  ?margin_left:int ->
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
  ?data_attrs:(string * string) list ->
  ?data_attrs_signal:(string * string) list Signal.signal ->
  ?on_appear:(unit -> unit) ->
  ?on_pointer_enter:(unit -> unit) ->
  ?on_pointer_leave:(unit -> unit) ->
  ?orientation:orientation ->
  ?opacity:float ->
  ?opacity_signal:float Signal.signal ->
  ?transition:string -> t list -> t
val list :
  ?key:string ->
  ?gap:int ->
  ?main:main_alignment ->
  ?cross:cross_alignment ->
  ?grow:float ->
  ?padding:int ->
  ?padding_horizontal:int ->
  ?padding_vertical:int ->
  ?margin:int ->
  ?margin_horizontal:int ->
  ?margin_vertical:int ->
  ?margin_top:int ->
  ?margin_right:int ->
  ?margin_bottom:int ->
  ?margin_left:int ->
  ?background:string ->
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
  ?background_signal:string Signal.signal ->
  ?style_class:string ->
  ?data_attrs:(string * string) list ->
  ?data_attrs_signal:(string * string) list Signal.signal ->
  ?on_appear:(unit -> unit) ->
  ?on_pointer_enter:(unit -> unit) ->
  ?on_pointer_leave:(unit -> unit) ->
  ?style:list_style ->
  ?scroll_target:string ->
  ?scroll_anchor:scroll_anchor ->
  ?scroll_token:int ->
  ?scroll_target_signal:string Signal.signal ->
  ?scroll_token_signal:int Signal.signal ->
  ?scroll_animated:bool ->
  ?track_visible_range:bool ->
  ?on_scroll_completed:(scroll_completed -> unit) ->
  ?on_visible_range:(visible_range -> unit) ->
   (* Receives [VisibleRange] (intersecting row indices — overscan and
      focus-retained rows excluded) and [ScrollEdges] (whether the
      scroll viewport touches its top/bottom edges — the typed signal
      for tail pinning). *)
  ?opacity:float ->
  ?opacity_signal:float Signal.signal ->
  ?list_marker:list_marker ->
  ?transition:string -> t list -> t
(* [virtual_list] keeps all children in the model but materializes
   only the visible window plus [?overscan] rows (backends that
   virtualize — web and native). [?item_extent] is the estimated row
   main extent in logical px, used to size unmeasured rows on the
   virtualizing host. Typed properties take precedence over legacy
   [data-overscan]/[data-item-extent] attributes. Zero overscan is valid;
   item extents must be positive finite logical pixels. The scroll contract
   ([?scroll_target]/[?scroll_anchor]/[?scroll_token],
   [?track_visible_range]/[?on_visible_range]/[?on_scroll_completed])
   matches {!list} and is implemented on the web backend; native
   backends currently parse-accept these props without scrolling. *)
val virtual_list :
  ?viewport:Lui_virtual.source ->
  ?key:string ->
  ?overscan:int ->
  ?item_extent:float ->
  ?gap:int ->
  ?main:main_alignment ->
  ?cross:cross_alignment ->
  ?grow:float ->
  ?padding:int ->
  ?padding_horizontal:int ->
  ?padding_vertical:int ->
  ?margin:int ->
  ?margin_horizontal:int ->
  ?margin_vertical:int ->
  ?margin_top:int ->
  ?margin_right:int ->
  ?margin_bottom:int ->
  ?margin_left:int ->
  ?background:string ->
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
  ?background_signal:string Signal.signal ->
  ?style_class:string ->
  ?data_attrs:(string * string) list ->
  ?data_attrs_signal:(string * string) list Signal.signal ->
  ?on_appear:(unit -> unit) ->
  ?on_pointer_enter:(unit -> unit) ->
  ?on_pointer_leave:(unit -> unit) ->
  ?scroll_target:string ->
  ?scroll_anchor:scroll_anchor ->
  ?scroll_token:int ->
  ?scroll_target_signal:string Signal.signal ->
  ?scroll_token_signal:int Signal.signal ->
  ?scroll_animated:bool ->
  ?track_visible_range:bool ->
  ?on_scroll_completed:(scroll_completed -> unit) ->
  ?on_visible_range:(visible_range -> unit) ->
   (* Receives [VisibleRange] (intersecting row indices — overscan and
      focus-retained rows excluded) and [ScrollEdges] (whether the
      scroll viewport touches its top/bottom edges — the typed signal
      for tail pinning). *)
  ?opacity:float ->
  ?opacity_signal:float Signal.signal ->
  ?list_marker:list_marker ->
  ?transition:string -> t list -> t
val tabs :
  ?key:string ->
  ?gap:int ->
  ?main:main_alignment ->
  ?cross:cross_alignment ->
  ?grow:float ->
  ?padding:int ->
  ?padding_horizontal:int ->
  ?padding_vertical:int ->
  ?margin:int ->
  ?margin_horizontal:int ->
  ?margin_vertical:int ->
  ?margin_top:int ->
  ?margin_right:int ->
  ?margin_bottom:int ->
  ?margin_left:int ->
  ?background:string ->
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
  ?background_signal:string Signal.signal ->
  ?style_class:string ->
  ?data_attrs:(string * string) list ->
  ?data_attrs_signal:(string * string) list Signal.signal ->
  ?on_appear:(unit -> unit) ->
  ?on_pointer_enter:(unit -> unit) ->
  ?on_pointer_leave:(unit -> unit) ->
  ?label:string -> ?orientation:orientation ->
  ?transition:string -> t list -> t
val bottom_tabs :
  ?key:string ->
  ?grow:float ->
  ?width:int ->
  ?height:int ->
  ?min_width:int ->
  ?max_width:int ->
  ?min_height:int ->
  ?max_height:int ->
  ?accessibility_identifier:string ->
  ?accessibility_identifier_signal:string Signal.signal ->
  ?style_class:string ->
  ?data_attrs:(string * string) list ->
  ?data_attrs_signal:(string * string) list Signal.signal ->
  ?on_appear:(unit -> unit) ->
  ?on_pointer_enter:(unit -> unit) ->
  ?on_pointer_leave:(unit -> unit) ->
  label:string -> bottom_tab_el list -> t
val bottom_tab :
  ?key:string ->
  ?accessibility_identifier:string ->
  ?accessibility_identifier_signal:string Signal.signal ->
  ?on_appear:(unit -> unit) ->
  ?on_pointer_enter:(unit -> unit) ->
  ?on_pointer_leave:(unit -> unit) ->
  title:string ->
  ?icon:icon ->
  ?icon_signal:icon Signal.signal ->
  ?selected:bool ->
  ?selected_signal:bool Signal.signal ->
  ?enabled:bool ->
  ?enabled_signal:bool Signal.signal ->
  on_press:(unit -> unit) ->
  ?on_press_detail:(pointer_detail -> unit) ->
  ?on_pointer_down:(pointer_detail -> unit) ->
  ?on_pointer_up:(pointer_detail -> unit) -> t list -> bottom_tab_el
val button_group :
  ?key:string ->
  ?gap:int ->
  ?main:main_alignment ->
  ?cross:cross_alignment ->
  ?grow:float ->
  ?padding:int ->
  ?padding_horizontal:int ->
  ?padding_vertical:int ->
  ?margin:int ->
  ?margin_horizontal:int ->
  ?margin_vertical:int ->
  ?margin_top:int ->
  ?margin_right:int ->
  ?margin_bottom:int ->
  ?margin_left:int ->
  ?background:string ->
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
  ?background_signal:string Signal.signal ->
  ?style_class:string ->
  ?data_attrs:(string * string) list ->
  ?data_attrs_signal:(string * string) list Signal.signal ->
  ?on_appear:(unit -> unit) ->
  ?on_pointer_enter:(unit -> unit) ->
  ?on_pointer_leave:(unit -> unit) -> ?label:string ->
  ?transition:string -> t list -> t
val toggle_group :
  ?key:string ->
  ?gap:int ->
  ?main:main_alignment ->
  ?cross:cross_alignment ->
  ?grow:float ->
  ?padding:int ->
  ?padding_horizontal:int ->
  ?padding_vertical:int ->
  ?margin:int ->
  ?margin_horizontal:int ->
  ?margin_vertical:int ->
  ?margin_top:int ->
  ?margin_right:int ->
  ?margin_bottom:int ->
  ?margin_left:int ->
  ?background:string ->
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
  ?background_signal:string Signal.signal ->
  ?style_class:string ->
  ?data_attrs:(string * string) list ->
  ?data_attrs_signal:(string * string) list Signal.signal ->
  ?on_appear:(unit -> unit) ->
  ?on_pointer_enter:(unit -> unit) ->
  ?on_pointer_leave:(unit -> unit) -> ?label:string ->
  ?transition:string -> t list -> t
val breadcrumb :
  ?key:string ->
  ?gap:int ->
  ?main:main_alignment ->
  ?cross:cross_alignment ->
  ?grow:float ->
  ?padding:int ->
  ?padding_horizontal:int ->
  ?padding_vertical:int ->
  ?margin:int ->
  ?margin_horizontal:int ->
  ?margin_vertical:int ->
  ?margin_top:int ->
  ?margin_right:int ->
  ?margin_bottom:int ->
  ?margin_left:int ->
  ?background:string ->
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
  ?background_signal:string Signal.signal ->
  ?style_class:string ->
  ?data_attrs:(string * string) list ->
  ?data_attrs_signal:(string * string) list Signal.signal ->
  ?on_appear:(unit -> unit) ->
  ?on_pointer_enter:(unit -> unit) ->
  ?on_pointer_leave:(unit -> unit) -> ?label:string ->
  ?transition:string -> t list -> t
val pagination :
  ?key:string ->
  ?gap:int ->
  ?main:main_alignment ->
  ?cross:cross_alignment ->
  ?grow:float ->
  ?padding:int ->
  ?padding_horizontal:int ->
  ?padding_vertical:int ->
  ?margin:int ->
  ?margin_horizontal:int ->
  ?margin_vertical:int ->
  ?margin_top:int ->
  ?margin_right:int ->
  ?margin_bottom:int ->
  ?margin_left:int ->
  ?background:string ->
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
  ?background_signal:string Signal.signal ->
  ?style_class:string ->
  ?data_attrs:(string * string) list ->
  ?data_attrs_signal:(string * string) list Signal.signal ->
  ?on_appear:(unit -> unit) ->
  ?on_pointer_enter:(unit -> unit) ->
  ?on_pointer_leave:(unit -> unit) -> ?label:string ->
  ?transition:string -> t list -> t
val table :
  ?key:string ->
  ?grow:float ->
  ?padding:int ->
  ?padding_horizontal:int ->
  ?padding_vertical:int ->
  ?margin:int ->
  ?margin_horizontal:int ->
  ?margin_vertical:int ->
  ?margin_top:int ->
  ?margin_right:int ->
  ?margin_bottom:int ->
  ?margin_left:int ->
  ?background:string ->
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
  ?background_signal:string Signal.signal ->
  ?style_class:string ->
  ?data_attrs:(string * string) list ->
  ?data_attrs_signal:(string * string) list Signal.signal ->
  ?on_appear:(unit -> unit) ->
  ?on_pointer_enter:(unit -> unit) ->
  ?on_pointer_leave:(unit -> unit) ->
  ?transition:string -> table_row_el list -> t
val table_row :
  ?key:string ->
  ?gap:int ->
  ?grow:float ->
  ?padding:int ->
  ?padding_horizontal:int ->
  ?padding_vertical:int ->
  ?margin:int ->
  ?margin_horizontal:int ->
  ?margin_vertical:int ->
  ?margin_top:int ->
  ?margin_right:int ->
  ?margin_bottom:int ->
  ?margin_left:int ->
  ?background:string ->
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
  ?background_signal:string Signal.signal ->
  ?style_class:string ->
  ?data_attrs:(string * string) list ->
  ?data_attrs_signal:(string * string) list Signal.signal ->
  ?on_appear:(unit -> unit) ->
  ?on_pointer_enter:(unit -> unit) ->
  ?on_pointer_leave:(unit -> unit) ->
  ?selected:bool -> ?selected_signal:bool Signal.signal ->
  ?transition:string -> table_cell_el list -> table_row_el
val table_cell :
  ?key:string ->
  ?grow:float ->
  ?padding:int ->
  ?padding_horizontal:int ->
  ?padding_vertical:int ->
  ?margin:int ->
  ?margin_horizontal:int ->
  ?margin_vertical:int ->
  ?margin_top:int ->
  ?margin_right:int ->
  ?margin_bottom:int ->
  ?margin_left:int ->
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
  ?data_attrs:(string * string) list ->
  ?data_attrs_signal:(string * string) list Signal.signal ->
  ?on_appear:(unit -> unit) ->
  ?on_pointer_enter:(unit -> unit) ->
  ?on_pointer_leave:(unit -> unit) ->
  ?text:string ->
  ?text_signal:string Signal.signal ->
  ?font_size:string ->
  ?font_weight:int ->
  ?line_height:string ->
  ?size:cell_size ->
  ?text_alignment:text_alignment ->
  ?on_press:(unit -> unit) ->
  ?on_press_detail:(pointer_detail -> unit) ->
  ?on_pointer_down:(pointer_detail -> unit) ->
  ?on_pointer_up:(pointer_detail -> unit) ->
  ?on_context_menu:(pointer_detail -> unit) ->
  ?transition:string -> t list -> table_cell_el
val tree :
  ?key:string ->
  ?gap:int ->
  ?grow:float ->
  ?padding:int ->
  ?padding_horizontal:int ->
  ?padding_vertical:int ->
  ?margin:int ->
  ?margin_horizontal:int ->
  ?margin_vertical:int ->
  ?margin_top:int ->
  ?margin_right:int ->
  ?margin_bottom:int ->
  ?margin_left:int ->
  ?background:string ->
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
  ?background_signal:string Signal.signal ->
  ?style_class:string ->
  ?data_attrs:(string * string) list ->
  ?data_attrs_signal:(string * string) list Signal.signal ->
  ?on_appear:(unit -> unit) ->
  ?on_pointer_enter:(unit -> unit) ->
  ?on_pointer_leave:(unit -> unit) ->
  label:string ->
  ?transition:string -> t list -> t
val resizable :
  ?key:string ->
  ?grow:float ->
  ?padding:int ->
  ?padding_horizontal:int ->
  ?padding_vertical:int ->
  ?margin:int ->
  ?margin_horizontal:int ->
  ?margin_vertical:int ->
  ?margin_top:int ->
  ?margin_right:int ->
  ?margin_bottom:int ->
  ?margin_left:int ->
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
  ?data_attrs:(string * string) list ->
  ?data_attrs_signal:(string * string) list Signal.signal ->
  ?on_appear:(unit -> unit) ->
  ?on_pointer_enter:(unit -> unit) ->
  ?on_pointer_leave:(unit -> unit) ->
  ?label:string -> ?resizable_width:int ->
  ?transition:string -> t list -> t

(** A horizontal split controlled by either [value] (a track fraction) or
    [first_width] (logical pixels, native OCaml and Web backends).
    These inputs are mutually exclusive.
    [gap] reserves layout space between panes. [resize_handle_width] controls
    the independent hit area; by default it uses the gap, or three logical
    pixels for a zero gap. [resize_handle_offset] moves its center from the
    gap center toward the second pane, without changing either pane width.
    [on_resize] reports [ValueChanged] in the units of the chosen input.
    Pane minima and maxima constrain user resizing; controlled closure may
    reach zero so opening and closing animations can complete.
    A controlled split retains its pane layout and animation when
    [resize_handle_width] is zero; its divider then accepts no input. *)
val split :
  ?key:string ->
  ?gap:int ->
  ?grow:float ->
  ?padding:int ->
  ?padding_horizontal:int ->
  ?padding_vertical:int ->
  ?margin:int ->
  ?margin_horizontal:int ->
  ?margin_vertical:int ->
  ?margin_top:int ->
  ?margin_right:int ->
  ?margin_bottom:int ->
  ?margin_left:int ->
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
  ?data_attrs:(string * string) list ->
  ?data_attrs_signal:(string * string) list Signal.signal ->
  ?on_appear:(unit -> unit) ->
  ?on_pointer_enter:(unit -> unit) ->
  ?on_pointer_leave:(unit -> unit) ->
  ?sizing:split_sizing ->
  ?sizing_signal:split_sizing Signal.signal ->
  ?resize_handle_width:int ->
  ?resize_handle_width_signal:int Signal.signal ->
  ?resize_handle_offset:float ->
  ?resize_handle_offset_signal:float Signal.signal ->
  ?motion:split_motion ->
  ?label:string -> ?on_resize:(float -> unit) ->
  ?transition:string -> t -> t -> t
val drawer :
  ?key:string ->
  ?padding:int ->
  ?padding_horizontal:int ->
  ?padding_vertical:int ->
  ?margin:int ->
  ?margin_horizontal:int ->
  ?margin_vertical:int ->
  ?margin_top:int ->
  ?margin_right:int ->
  ?margin_bottom:int ->
  ?margin_left:int ->
  ?width:int ->
  ?height:int ->
  ?accessibility_identifier:string ->
  ?accessibility_identifier_signal:string Signal.signal ->
  ?style_class:string ->
  ?data_attrs:(string * string) list ->
  ?data_attrs_signal:(string * string) list Signal.signal ->
  ?on_appear:(unit -> unit) ->
  ?on_pointer_enter:(unit -> unit) ->
  ?on_pointer_leave:(unit -> unit) ->
  ?selected:bool ->
  ?selected_signal:bool Signal.signal ->
  ?disabled:bool ->
  ?disabled_signal:bool Signal.signal ->
  ?label:string -> ?on_toggle:(bool -> unit) ->
  ?transition:string -> t -> t -> t
val status_bar :
  ?key:string ->
  ?grow:float ->
  ?padding:int ->
  ?padding_horizontal:int ->
  ?padding_vertical:int ->
  ?margin:int ->
  ?margin_horizontal:int ->
  ?margin_vertical:int ->
  ?margin_top:int ->
  ?margin_right:int ->
  ?margin_bottom:int ->
  ?margin_left:int ->
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
  ?data_attrs:(string * string) list ->
  ?data_attrs_signal:(string * string) list Signal.signal ->
  ?on_appear:(unit -> unit) ->
  ?on_pointer_enter:(unit -> unit) ->
  ?on_pointer_leave:(unit -> unit) ->
  ?value:string ->
  ?value_signal:string Signal.signal -> ?text_alignment:text_alignment ->
  ?transition:string -> nothing list -> t
val spacer :
  ?key:string ->
  ?grow:float ->
  ?padding:int ->
  ?padding_horizontal:int ->
  ?padding_vertical:int ->
  ?margin:int ->
  ?margin_horizontal:int ->
  ?margin_vertical:int ->
  ?margin_top:int ->
  ?margin_right:int ->
  ?margin_bottom:int ->
  ?margin_left:int ->
  ?background:string ->
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
  ?background_signal:string Signal.signal ->
  ?style_class:string ->
  ?data_attrs:(string * string) list ->
  ?data_attrs_signal:(string * string) list Signal.signal ->
  ?on_appear:(unit -> unit) ->
  ?on_pointer_enter:(unit -> unit) ->
  ?on_pointer_leave:(unit -> unit) ->
  ?transition:string -> nothing list -> t
val spinner :
  ?key:string ->
  ?grow:float ->
  ?padding:int ->
  ?padding_horizontal:int ->
  ?padding_vertical:int ->
  ?margin:int ->
  ?margin_horizontal:int ->
  ?margin_vertical:int ->
  ?margin_top:int ->
  ?margin_right:int ->
  ?margin_bottom:int ->
  ?margin_left:int ->
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
  ?data_attrs:(string * string) list ->
  ?data_attrs_signal:(string * string) list Signal.signal ->
  ?on_appear:(unit -> unit) ->
  ?on_pointer_enter:(unit -> unit) ->
  ?on_pointer_leave:(unit -> unit) -> ?size:control_size ->
  ?transition:string -> nothing list -> t
val icon :
  ?key:string ->
  ?grow:float ->
  ?padding:int ->
  ?padding_horizontal:int ->
  ?padding_vertical:int ->
  ?margin:int ->
  ?margin_horizontal:int ->
  ?margin_vertical:int ->
  ?margin_top:int ->
  ?margin_right:int ->
  ?margin_bottom:int ->
  ?margin_left:int ->
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
  ?data_attrs:(string * string) list ->
  ?data_attrs_signal:(string * string) list Signal.signal ->
  ?on_appear:(unit -> unit) ->
  ?on_pointer_enter:(unit -> unit) ->
  ?on_pointer_leave:(unit -> unit) ->
  name:icon ->
  ?name_signal:icon Signal.signal -> ?size:control_size ->
  ?point_size:int ->
  ?tooltip:string ->
  ?tooltip_signal:string Signal.signal ->
  ?shortcut_hint:string ->
  ?shortcut_hint_signal:string Signal.signal ->
  ?transition:string -> nothing list -> t
val text :
  ?key:string ->
  ?grow:float ->
  ?padding:int ->
  ?padding_horizontal:int ->
  ?padding_vertical:int ->
  ?margin:int ->
  ?margin_horizontal:int ->
  ?margin_vertical:int ->
  ?margin_top:int ->
  ?margin_right:int ->
  ?margin_bottom:int ->
  ?margin_left:int ->
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
  ?data_attrs:(string * string) list ->
  ?data_attrs_signal:(string * string) list Signal.signal ->
  ?as_:phrasing_tag ->
  ?on_appear:(unit -> unit) ->
  ?on_pointer_enter:(unit -> unit) ->
  ?on_pointer_leave:(unit -> unit) ->
  ?value:string ->
  ?value_signal:string Signal.signal ->
  ?text_alignment:text_alignment ->
  ?font_size:string ->
  ?font_weight:int ->
  ?line_height:string ->
  ?letter_spacing:float ->
  ?font_family:string ->
  ?font_style:font_style ->
  ?text_decoration:string ->
  ?white_space:white_space -> ?line_clamp:int ->
  ?text_overflow:text_overflow ->
  ?overflow:overflow ->
  ?on_press:(unit -> unit) ->
  ?on_press_detail:(pointer_detail -> unit) ->
  ?on_pointer_down:(pointer_detail -> unit) ->
  ?on_pointer_up:(pointer_detail -> unit) ->
  ?on_context_menu:(pointer_detail -> unit) ->
  ?transition:string -> t list -> t
val heading :
  ?key:string ->
  ?grow:float ->
  ?padding:int ->
  ?padding_horizontal:int ->
  ?padding_vertical:int ->
  ?margin:int ->
  ?margin_horizontal:int ->
  ?margin_vertical:int ->
  ?margin_top:int ->
  ?margin_right:int ->
  ?margin_bottom:int ->
  ?margin_left:int ->
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
  ?data_attrs:(string * string) list ->
  ?data_attrs_signal:(string * string) list Signal.signal ->
  ?as_:heading_tag ->
  ?on_appear:(unit -> unit) ->
  ?on_pointer_enter:(unit -> unit) ->
  ?on_pointer_leave:(unit -> unit) ->
  ?level:heading_level ->
  ?value:string -> ?value_signal:string Signal.signal ->
  ?text_alignment:text_alignment ->
  ?font_size:string ->
  ?font_weight:int ->
  ?line_height:string ->
  ?letter_spacing:float ->
  ?font_family:string ->
  ?font_style:font_style ->
  ?text_decoration:string ->
  ?white_space:white_space -> ?line_clamp:int ->
  ?text_overflow:text_overflow ->
  ?overflow:overflow ->
  ?transition:string -> t list -> t
val paragraph :
  ?key:string ->
  ?grow:float ->
  ?padding:int ->
  ?padding_horizontal:int ->
  ?padding_vertical:int ->
  ?margin:int ->
  ?margin_horizontal:int ->
  ?margin_vertical:int ->
  ?margin_top:int ->
  ?margin_right:int ->
  ?margin_bottom:int ->
  ?margin_left:int ->
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
  ?data_attrs:(string * string) list ->
  ?data_attrs_signal:(string * string) list Signal.signal ->
  ?as_:paragraph_tag ->
  ?on_appear:(unit -> unit) ->
  ?on_pointer_enter:(unit -> unit) ->
  ?on_pointer_leave:(unit -> unit) ->
  ?value:string -> ?value_signal:string Signal.signal ->
  ?text_alignment:text_alignment ->
  ?font_size:string ->
  ?font_weight:int ->
  ?line_height:string ->
  ?letter_spacing:float ->
  ?font_family:string ->
  ?font_style:font_style ->
  ?text_decoration:string ->
  ?white_space:white_space -> ?line_clamp:int ->
  ?text_overflow:text_overflow ->
  ?overflow:overflow ->
  ?transition:string -> t list -> t
val label :
  ?key:string ->
  ?grow:float ->
  ?padding:int ->
  ?padding_horizontal:int ->
  ?padding_vertical:int ->
  ?margin:int ->
  ?margin_horizontal:int ->
  ?margin_vertical:int ->
  ?margin_top:int ->
  ?margin_right:int ->
  ?margin_bottom:int ->
  ?margin_left:int ->
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
  ?data_attrs:(string * string) list ->
  ?data_attrs_signal:(string * string) list Signal.signal ->
  ?as_:label_tag ->
  ?on_appear:(unit -> unit) ->
  ?on_pointer_enter:(unit -> unit) ->
  ?on_pointer_leave:(unit -> unit) ->
  ?value:string -> ?value_signal:string Signal.signal ->
  ?font_size:string ->
  ?font_weight:int ->
  ?line_height:string ->
  ?letter_spacing:float ->
  ?font_family:string ->
  ?font_style:font_style ->
  ?text_decoration:string ->
  ?white_space:white_space -> ?line_clamp:int ->
  ?text_overflow:text_overflow ->
  ?overflow:overflow ->
  ?transition:string -> t list -> t
val kbd :
  ?key:string ->
  ?grow:float ->
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
  ?accessibility_identifier:string ->
  ?accessibility_identifier_signal:string Signal.signal ->
  ?foreground_signal:string Signal.signal ->
  ?background_signal:string Signal.signal ->
  ?style_class:string ->
  ?data_attrs:(string * string) list ->
  ?data_attrs_signal:(string * string) list Signal.signal ->
  ?on_appear:(unit -> unit) ->
  ?on_pointer_enter:(unit -> unit) ->
  ?on_pointer_leave:(unit -> unit) ->
  ?value:string -> ?value_signal:string Signal.signal ->
  ?transition:string -> nothing list -> t

(** A text button. [text] is the initial value; [text_signal], when supplied,
    wins. Children remain supported. Use [icon_button] for icon-only content. *)
val button :
  ?key:string ->
  ?gap:int ->
  ?main:main_alignment ->
  ?cross:cross_alignment ->
  ?grow:float ->
  ?padding:int ->
  ?padding_horizontal:int ->
  ?padding_vertical:int ->
  ?margin:int ->
  ?margin_horizontal:int ->
  ?margin_vertical:int ->
  ?margin_top:int ->
  ?margin_right:int ->
  ?margin_bottom:int ->
  ?margin_left:int ->
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
  ?data_attrs:(string * string) list ->
  ?data_attrs_signal:(string * string) list Signal.signal ->
  ?on_appear:(unit -> unit) ->
  ?on_pointer_enter:(unit -> unit) ->
  ?on_pointer_leave:(unit -> unit) ->
  text:string ->
  ?text_signal:string Signal.signal ->
  ?variant:variant ->
  ?size:button_size ->
  ?icon:icon ->
  ?icon_signal:icon Signal.signal ->
  ?icon_placement:icon_placement ->
  ?label:string ->
  ?text_alignment:text_alignment ->
  ?selected:bool ->
  ?selected_signal:bool Signal.signal ->
  ?autofocus:bool ->
  ?disabled:bool ->
  ?disabled_signal:bool Signal.signal ->
  ?on_navigate:(navigation -> unit) ->
  ?on_press:(unit -> unit) ->
  ?on_long_press:(unit -> unit) ->
  ?on_press_detail:(pointer_detail -> unit) ->
  ?on_pointer_down:(pointer_detail -> unit) ->
  ?on_pointer_up:(pointer_detail -> unit) ->
  ?on_context_menu:(pointer_detail -> unit) ->
  ?tooltip:string ->
  ?tooltip_signal:string Signal.signal ->
  ?shortcut_hint:string ->
  ?shortcut_hint_signal:string Signal.signal ->
  ?transition:string -> t list -> t

(** An icon-only button with a mandatory accessible [label]. Uses the same
    wire kind, defaults, events and children slot as [button]. *)
val icon_button :
  ?key:string ->
  ?gap:int ->
  ?main:main_alignment ->
  ?cross:cross_alignment ->
  ?grow:float ->
  ?padding:int ->
  ?padding_horizontal:int ->
  ?padding_vertical:int ->
  ?margin:int ->
  ?margin_horizontal:int ->
  ?margin_vertical:int ->
  ?margin_top:int ->
  ?margin_right:int ->
  ?margin_bottom:int ->
  ?margin_left:int ->
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
  ?data_attrs:(string * string) list ->
  ?data_attrs_signal:(string * string) list Signal.signal ->
  ?on_appear:(unit -> unit) ->
  ?on_pointer_enter:(unit -> unit) ->
  ?on_pointer_leave:(unit -> unit) ->
  ?variant:variant ->
  ?size:control_size ->
  icon:icon ->
  ?icon_signal:icon Signal.signal ->
  ?icon_placement:icon_placement ->
  label:string ->
  ?text_alignment:text_alignment ->
  ?selected:bool ->
  ?selected_signal:bool Signal.signal ->
  ?autofocus:bool ->
  ?disabled:bool ->
  ?disabled_signal:bool Signal.signal ->
  ?on_navigate:(navigation -> unit) ->
  ?on_press:(unit -> unit) ->
  ?on_long_press:(unit -> unit) ->
  ?on_press_detail:(pointer_detail -> unit) ->
  ?on_pointer_down:(pointer_detail -> unit) ->
  ?on_pointer_up:(pointer_detail -> unit) ->
  ?on_context_menu:(pointer_detail -> unit) ->
  ?tooltip:string ->
  ?tooltip_signal:string Signal.signal ->
  ?shortcut_hint:string ->
  ?shortcut_hint_signal:string Signal.signal ->
  ?transition:string -> t list -> t
val toggle_button :
  ?key:string ->
  ?grow:float ->
  ?padding:int ->
  ?padding_horizontal:int ->
  ?padding_vertical:int ->
  ?margin:int ->
  ?margin_horizontal:int ->
  ?margin_vertical:int ->
  ?margin_top:int ->
  ?margin_right:int ->
  ?margin_bottom:int ->
  ?margin_left:int ->
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
  ?data_attrs:(string * string) list ->
  ?data_attrs_signal:(string * string) list Signal.signal ->
  ?on_appear:(unit -> unit) ->
  ?on_pointer_enter:(unit -> unit) ->
  ?on_pointer_leave:(unit -> unit) ->
  ?text:string ->
  ?text_signal:string Signal.signal ->
  ?variant:variant ->
  ?size:control_size ->
  ?icon:icon ->
  ?icon_signal:icon Signal.signal ->
  ?icon_placement:icon_placement ->
  ?label:string ->
  ?text_alignment:text_alignment ->
  ?selected:bool ->
  ?checked:bool ->
  ?checked_signal:bool Signal.signal ->
  ?autofocus:bool ->
  ?disabled:bool ->
  ?disabled_signal:bool Signal.signal ->
  ?on_toggle:(bool -> unit) ->
  ?on_long_press:(unit -> unit) ->
  ?on_context_menu:(pointer_detail -> unit) ->
  ?transition:string -> t list -> t
val checkbox :
  ?key:string ->
  ?gap:int ->
  ?main:main_alignment ->
  ?cross:cross_alignment ->
  ?grow:float ->
  ?padding:int ->
  ?padding_horizontal:int ->
  ?padding_vertical:int ->
  ?margin:int ->
  ?margin_horizontal:int ->
  ?margin_vertical:int ->
  ?margin_top:int ->
  ?margin_right:int ->
  ?margin_bottom:int ->
  ?margin_left:int ->
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
  ?data_attrs:(string * string) list ->
  ?data_attrs_signal:(string * string) list Signal.signal ->
  ?on_appear:(unit -> unit) ->
  ?on_pointer_enter:(unit -> unit) ->
  ?on_pointer_leave:(unit -> unit) ->
  ?text:string ->
  ?text_signal:string Signal.signal ->
  ?checked:bool ->
  ?checked_signal:bool Signal.signal ->
  ?indeterminate:bool ->
  ?indeterminate_signal:bool Signal.signal ->
  ?label:string ->
  ?disabled:bool ->
  ?disabled_signal:bool Signal.signal ->
  ?on_toggle:(bool -> unit) ->
  ?on_toggle_detail:(toggle_detail -> unit) ->
  ?on_context_menu:(pointer_detail -> unit) ->
  ?transition:string -> t list -> t
val switch_ :
  ?key:string ->
  ?grow:float ->
  ?padding:int ->
  ?padding_horizontal:int ->
  ?padding_vertical:int ->
  ?margin:int ->
  ?margin_horizontal:int ->
  ?margin_vertical:int ->
  ?margin_top:int ->
  ?margin_right:int ->
  ?margin_bottom:int ->
  ?margin_left:int ->
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
  ?data_attrs:(string * string) list ->
  ?data_attrs_signal:(string * string) list Signal.signal ->
  ?on_appear:(unit -> unit) ->
  ?on_pointer_enter:(unit -> unit) ->
  ?on_pointer_leave:(unit -> unit) ->
  ?text:string ->
  ?text_signal:string Signal.signal ->
  ?checked:bool ->
  ?checked_signal:bool Signal.signal ->
  ?label:string ->
  ?disabled:bool ->
  ?disabled_signal:bool Signal.signal ->
  ?on_toggle:(bool -> unit) ->
  ?on_context_menu:(pointer_detail -> unit) ->
  ?transition:string -> t list -> t
val toggle :
  ?key:string ->
  ?grow:float ->
  ?padding:int ->
  ?padding_horizontal:int ->
  ?padding_vertical:int ->
  ?margin:int ->
  ?margin_horizontal:int ->
  ?margin_vertical:int ->
  ?margin_top:int ->
  ?margin_right:int ->
  ?margin_bottom:int ->
  ?margin_left:int ->
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
  ?data_attrs:(string * string) list ->
  ?data_attrs_signal:(string * string) list Signal.signal ->
  ?on_appear:(unit -> unit) ->
  ?on_pointer_enter:(unit -> unit) ->
  ?on_pointer_leave:(unit -> unit) ->
  ?text:string ->
  ?text_signal:string Signal.signal ->
  ?checked:bool ->
  ?checked_signal:bool Signal.signal ->
  ?label:string ->
  ?disabled:bool ->
  ?disabled_signal:bool Signal.signal ->
  ?on_toggle:(bool -> unit) ->
  ?on_context_menu:(pointer_detail -> unit) ->
  ?transition:string -> t list -> t
val radio_group :
  ?key:string ->
  ?grow:float ->
  ?padding:int ->
  ?padding_horizontal:int ->
  ?padding_vertical:int ->
  ?margin:int ->
  ?margin_horizontal:int ->
  ?margin_vertical:int ->
  ?margin_top:int ->
  ?margin_right:int ->
  ?margin_bottom:int ->
  ?margin_left:int ->
  ?background:string ->
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
  ?background_signal:string Signal.signal ->
  ?style_class:string ->
  ?data_attrs:(string * string) list ->
  ?data_attrs_signal:(string * string) list Signal.signal ->
  ?on_appear:(unit -> unit) ->
  ?on_pointer_enter:(unit -> unit) ->
  ?on_pointer_leave:(unit -> unit) -> label:string ->
  ?transition:string -> radio_el list -> t
val radio :
  ?key:string ->
  ?gap:int ->
  ?main:main_alignment ->
  ?cross:cross_alignment ->
  ?grow:float ->
  ?padding:int ->
  ?padding_horizontal:int ->
  ?padding_vertical:int ->
  ?margin:int ->
  ?margin_horizontal:int ->
  ?margin_vertical:int ->
  ?margin_top:int ->
  ?margin_right:int ->
  ?margin_bottom:int ->
  ?margin_left:int ->
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
  ?data_attrs:(string * string) list ->
  ?data_attrs_signal:(string * string) list Signal.signal ->
  ?on_appear:(unit -> unit) ->
  ?on_pointer_enter:(unit -> unit) ->
  ?on_pointer_leave:(unit -> unit) ->
  ?text:string ->
  ?text_signal:string Signal.signal ->
  ?checked:bool ->
  ?checked_signal:bool Signal.signal ->
  ?selected:bool ->
  ?label:string ->
  ?disabled:bool ->
  ?disabled_signal:bool Signal.signal ->
  ?on_change:(unit -> unit) ->
  ?on_toggle:(bool -> unit) ->
  ?on_press:(unit -> unit) ->
  ?on_press_detail:(pointer_detail -> unit) ->
  ?on_pointer_down:(pointer_detail -> unit) ->
  ?on_pointer_up:(pointer_detail -> unit) ->
  ?on_context_menu:(pointer_detail -> unit) ->
  ?transition:string -> t list -> radio_el
val slider :
  ?key:string ->
  ?grow:float ->
  ?padding:int ->
  ?padding_horizontal:int ->
  ?padding_vertical:int ->
  ?margin:int ->
  ?margin_horizontal:int ->
  ?margin_vertical:int ->
  ?margin_top:int ->
  ?margin_right:int ->
  ?margin_bottom:int ->
  ?margin_left:int ->
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
  ?data_attrs:(string * string) list ->
  ?data_attrs_signal:(string * string) list Signal.signal ->
  ?on_appear:(unit -> unit) ->
  ?on_pointer_enter:(unit -> unit) ->
  ?on_pointer_leave:(unit -> unit) ->
  value:float ->
  ?value_signal:float Signal.signal ->
  label:string ->
  ?disabled:bool ->
  ?disabled_signal:bool Signal.signal ->
  ?on_change:(float -> unit) ->
  ?on_context_menu:(pointer_detail -> unit) ->
  ?transition:string -> t list -> t
val number_stepper :
  ?key:string ->
  ?grow:float ->
  ?padding:int ->
  ?padding_horizontal:int ->
  ?padding_vertical:int ->
  ?margin:int ->
  ?margin_horizontal:int ->
  ?margin_vertical:int ->
  ?margin_top:int ->
  ?margin_right:int ->
  ?margin_bottom:int ->
  ?margin_left:int ->
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
  ?data_attrs:(string * string) list ->
  ?data_attrs_signal:(string * string) list Signal.signal ->
  ?on_appear:(unit -> unit) ->
  ?on_pointer_enter:(unit -> unit) ->
  ?on_pointer_leave:(unit -> unit) ->
  ?value:float ->
  ?value_signal:float Signal.signal ->
  ?min:float ->
  ?max:float ->
  ?step:float ->
  ?text:string ->
  ?text_signal:string Signal.signal ->
  ?label:string ->
  ?enabled:bool ->
  ?enabled_signal:bool Signal.signal ->
  ?on_value_changed:(float -> unit) ->
  ?on_context_menu:(pointer_detail -> unit) ->
  ?transition:string -> t list -> t
val progress :
  ?key:string ->
  ?grow:float ->
  ?padding:int ->
  ?padding_horizontal:int ->
  ?padding_vertical:int ->
  ?margin:int ->
  ?margin_horizontal:int ->
  ?margin_vertical:int ->
  ?margin_top:int ->
  ?margin_right:int ->
  ?margin_bottom:int ->
  ?margin_left:int ->
  ?background:string ->
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
  ?background_signal:string Signal.signal ->
  ?style_class:string ->
  ?data_attrs:(string * string) list ->
  ?data_attrs_signal:(string * string) list Signal.signal ->
  ?on_appear:(unit -> unit) ->
  ?on_pointer_enter:(unit -> unit) ->
  ?on_pointer_leave:(unit -> unit) ->
  value:float -> ?value_signal:float Signal.signal ->
  ?transition:string -> nothing list -> t
val divider :
  ?key:string ->
  ?grow:float ->
  ?padding:int ->
  ?padding_horizontal:int ->
  ?padding_vertical:int ->
  ?margin:int ->
  ?margin_horizontal:int ->
  ?margin_vertical:int ->
  ?margin_top:int ->
  ?margin_right:int ->
  ?margin_bottom:int ->
  ?margin_left:int ->
  ?background:string ->
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
  ?background_signal:string Signal.signal ->
  ?style_class:string ->
  ?data_attrs:(string * string) list ->
  ?data_attrs_signal:(string * string) list Signal.signal ->
  ?on_appear:(unit -> unit) ->
  ?on_pointer_enter:(unit -> unit) ->
  ?on_pointer_leave:(unit -> unit) ->
  ?orientation:orientation ->
  ?transition:string -> nothing list -> t
val separator :
  ?key:string ->
  ?grow:float ->
  ?padding:int ->
  ?padding_horizontal:int ->
  ?padding_vertical:int ->
  ?margin:int ->
  ?margin_horizontal:int ->
  ?margin_vertical:int ->
  ?margin_top:int ->
  ?margin_right:int ->
  ?margin_bottom:int ->
  ?margin_left:int ->
  ?background:string ->
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
  ?background_signal:string Signal.signal ->
  ?style_class:string ->
  ?data_attrs:(string * string) list ->
  ?data_attrs_signal:(string * string) list Signal.signal ->
  ?on_appear:(unit -> unit) ->
  ?on_pointer_enter:(unit -> unit) ->
  ?on_pointer_leave:(unit -> unit) ->
  ?orientation:orientation ->
  ?transition:string -> nothing list -> t

(* Text-entry constructors can opt into Submit on focus loss with
   [submit_on_blur]. Unfinished composition never submits on blur. *)
val text_field :
  ?key:string ->
  ?grow:float ->
  ?padding:int ->
  ?padding_horizontal:int ->
  ?padding_vertical:int ->
  ?margin:int ->
  ?margin_horizontal:int ->
  ?margin_vertical:int ->
  ?margin_top:int ->
  ?margin_right:int ->
  ?margin_bottom:int ->
  ?margin_left:int ->
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
  ?data_attrs:(string * string) list ->
  ?data_attrs_signal:(string * string) list Signal.signal ->
  ?on_appear:(unit -> unit) ->
  ?on_pointer_enter:(unit -> unit) ->
  ?on_pointer_leave:(unit -> unit) ->
  ?text:string ->
  ?text_signal:string Signal.signal ->
  ?placeholder:string ->
  ?placeholder_signal:string Signal.signal ->
  ?label:string ->
  ?autofocus:bool ->
  ?submit_on_blur:bool ->
  ?read_only:bool ->
  ?read_only_signal:bool Signal.signal ->
  ?disabled:bool ->
  ?disabled_signal:bool Signal.signal ->
  ?on_input:(string -> unit) ->
  ?on_submit:(unit -> unit) ->
  ?on_navigate:(navigation -> unit) ->
  ?on_context_menu:(pointer_detail -> unit) ->
  ?transition:string -> t list -> t
val secure_field :
  ?key:string ->
  ?grow:float ->
  ?padding:int ->
  ?padding_horizontal:int ->
  ?padding_vertical:int ->
  ?margin:int ->
  ?margin_horizontal:int ->
  ?margin_vertical:int ->
  ?margin_top:int ->
  ?margin_right:int ->
  ?margin_bottom:int ->
  ?margin_left:int ->
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
  ?data_attrs:(string * string) list ->
  ?data_attrs_signal:(string * string) list Signal.signal ->
  ?on_appear:(unit -> unit) ->
  ?on_pointer_enter:(unit -> unit) ->
  ?on_pointer_leave:(unit -> unit) ->
  ?text:string ->
  ?text_signal:string Signal.signal ->
  ?placeholder:string ->
  ?placeholder_signal:string Signal.signal ->
  ?label:string ->
  ?autofocus:bool ->
  ?submit_on_blur:bool ->
  ?read_only:bool ->
  ?read_only_signal:bool Signal.signal ->
  ?disabled:bool ->
  ?disabled_signal:bool Signal.signal ->
  ?on_input:(string -> unit) ->
  ?on_submit:(unit -> unit) ->
  ?on_navigate:(navigation -> unit) ->
  ?on_context_menu:(pointer_detail -> unit) ->
  ?transition:string -> t list -> t
val input :
  ?key:string ->
  ?grow:float ->
  ?padding:int ->
  ?padding_horizontal:int ->
  ?padding_vertical:int ->
  ?margin:int ->
  ?margin_horizontal:int ->
  ?margin_vertical:int ->
  ?margin_top:int ->
  ?margin_right:int ->
  ?margin_bottom:int ->
  ?margin_left:int ->
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
  ?data_attrs:(string * string) list ->
  ?data_attrs_signal:(string * string) list Signal.signal ->
  ?on_appear:(unit -> unit) ->
  ?on_pointer_enter:(unit -> unit) ->
  ?on_pointer_leave:(unit -> unit) ->
  ?text:string ->
  ?text_signal:string Signal.signal ->
  ?placeholder:string ->
  ?placeholder_signal:string Signal.signal ->
  ?label:string ->
  ?autofocus:bool ->
  ?submit_on_blur:bool ->
  ?read_only:bool ->
  ?read_only_signal:bool Signal.signal ->
  ?disabled:bool ->
  ?disabled_signal:bool Signal.signal ->
  ?on_input:(string -> unit) ->
  ?on_submit:(unit -> unit) ->
  ?on_navigate:(navigation -> unit) ->
  ?on_context_menu:(pointer_detail -> unit) ->
  ?kind:input_kind ->
  ?transition:string -> t list -> t
val search_field :
  ?key:string ->
  ?grow:float ->
  ?padding:int ->
  ?padding_horizontal:int ->
  ?padding_vertical:int ->
  ?margin:int ->
  ?margin_horizontal:int ->
  ?margin_vertical:int ->
  ?margin_top:int ->
  ?margin_right:int ->
  ?margin_bottom:int ->
  ?margin_left:int ->
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
  ?data_attrs:(string * string) list ->
  ?data_attrs_signal:(string * string) list Signal.signal ->
  ?on_appear:(unit -> unit) ->
  ?on_pointer_enter:(unit -> unit) ->
  ?on_pointer_leave:(unit -> unit) ->
  ?text:string ->
  ?text_signal:string Signal.signal ->
  ?placeholder:string ->
  ?placeholder_signal:string Signal.signal ->
  ?label:string ->
  ?autofocus:bool ->
  ?submit_on_blur:bool ->
  ?read_only:bool ->
  ?read_only_signal:bool Signal.signal ->
  ?disabled:bool ->
  ?disabled_signal:bool Signal.signal ->
  ?on_input:(string -> unit) ->
  ?on_submit:(unit -> unit) ->
  ?on_navigate:(navigation -> unit) ->
  ?on_context_menu:(pointer_detail -> unit) ->
  ?transition:string -> t list -> t
val textarea :
  ?key:string ->
  ?grow:float ->
  ?padding:int ->
  ?padding_horizontal:int ->
  ?padding_vertical:int ->
  ?margin:int ->
  ?margin_horizontal:int ->
  ?margin_vertical:int ->
  ?margin_top:int ->
  ?margin_right:int ->
  ?margin_bottom:int ->
  ?margin_left:int ->
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
  ?data_attrs:(string * string) list ->
  ?data_attrs_signal:(string * string) list Signal.signal ->
  ?on_appear:(unit -> unit) ->
  ?on_pointer_enter:(unit -> unit) ->
  ?on_pointer_leave:(unit -> unit) ->
  ?text:string ->
  ?text_signal:string Signal.signal ->
  ?placeholder:string ->
  ?placeholder_signal:string Signal.signal ->
  ?label:string ->
  ?autofocus:bool ->
  ?submit_on_enter:bool ->
  ?submit_on_blur:bool ->
  ?read_only:bool ->
  ?read_only_signal:bool Signal.signal ->
  ?disabled:bool ->
  ?disabled_signal:bool Signal.signal ->
  ?on_input:(string -> unit) ->
  ?on_submit:(unit -> unit) ->
  ?on_navigate:(navigation -> unit) ->
  ?on_context_menu:(pointer_detail -> unit) ->
  ?transition:string -> t list -> t
val input_group :
  ?key:string ->
  ?grow:float ->
  ?width:int ->
  ?height:int ->
  ?min_width:int ->
  ?accessibility_identifier:string ->
  ?accessibility_identifier_signal:string Signal.signal ->
  ?on_appear:(unit -> unit) ->
  ?on_pointer_enter:(unit -> unit) ->
  ?on_pointer_leave:(unit -> unit) -> ?label:string -> ?actions:input_group_actions_el -> t -> t
val input_group_actions :
  ?key:string ->
  ?gap:int ->
  ?accessibility_identifier:string ->
  ?accessibility_identifier_signal:string Signal.signal ->
  ?on_appear:(unit -> unit) ->
  ?on_pointer_enter:(unit -> unit) ->
  ?on_pointer_leave:(unit -> unit) -> t list -> input_group_actions_el
val select :
  ?key:string ->
  ?gap:int ->
  ?grow:float ->
  ?padding:int ->
  ?padding_horizontal:int ->
  ?padding_vertical:int ->
  ?margin:int ->
  ?margin_horizontal:int ->
  ?margin_vertical:int ->
  ?margin_top:int ->
  ?margin_right:int ->
  ?margin_bottom:int ->
  ?margin_left:int ->
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
  ?data_attrs:(string * string) list ->
  ?data_attrs_signal:(string * string) list Signal.signal ->
  ?on_appear:(unit -> unit) ->
  ?on_pointer_enter:(unit -> unit) ->
  ?on_pointer_leave:(unit -> unit) ->
  ?label:string ->
  ?text:string ->
  ?text_signal:string Signal.signal ->
  ?placeholder:string ->
  ?placeholder_signal:string Signal.signal ->
  ?disabled:bool ->
  ?disabled_signal:bool Signal.signal ->
  ?on_press:(unit -> unit) ->
  ?on_dismiss:(unit -> unit) ->
  ?on_press_detail:(pointer_detail -> unit) ->
  ?on_pointer_down:(pointer_detail -> unit) ->
  ?on_pointer_up:(pointer_detail -> unit) ->
  ?on_context_menu:(pointer_detail -> unit) ->
  ?transition:string -> t list -> t
val combobox :
  ?key:string ->
  ?gap:int ->
  ?grow:float ->
  ?padding:int ->
  ?padding_horizontal:int ->
  ?padding_vertical:int ->
  ?margin:int ->
  ?margin_horizontal:int ->
  ?margin_vertical:int ->
  ?margin_top:int ->
  ?margin_right:int ->
  ?margin_bottom:int ->
  ?margin_left:int ->
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
  ?data_attrs:(string * string) list ->
  ?data_attrs_signal:(string * string) list Signal.signal ->
  ?on_appear:(unit -> unit) ->
  ?on_pointer_enter:(unit -> unit) ->
  ?on_pointer_leave:(unit -> unit) ->
  ?text:string ->
  ?text_signal:string Signal.signal ->
  ?placeholder:string ->
  ?placeholder_signal:string Signal.signal ->
  ?read_only:bool ->
  ?read_only_signal:bool Signal.signal ->
  ?disabled:bool ->
  ?disabled_signal:bool Signal.signal ->
  ?on_press:(unit -> unit) ->
  ?on_input:(string -> unit) ->
  ?on_submit:(unit -> unit) ->
  ?on_dismiss:(unit -> unit) ->
  ?on_press_detail:(pointer_detail -> unit) ->
  ?on_pointer_down:(pointer_detail -> unit) ->
  ?on_pointer_up:(pointer_detail -> unit) ->
  ?on_context_menu:(pointer_detail -> unit) ->
  ?transition:string -> t list -> t

(** Menu surface mounted in the popup portal. Anchoring is either implicit
    — the element under the menu's retained parent ([~anchor],
    [~anchor_alignment], [~anchor_offset]) — or programmatic:
    [~at:(x, y)] ([~at_signal]) opens the menu at a viewport point, clamped
    like {!Lui_elements.popover}, with no DOM anchor required. [~at] and
    [~anchor] are mutually exclusive (rejected at validation). *)
val dropdown_menu :
  ?key:string ->
  ?gap:int ->
  ?grow:float ->
  ?padding:int ->
  ?padding_horizontal:int ->
  ?padding_vertical:int ->
  ?margin:int ->
  ?margin_horizontal:int ->
  ?margin_vertical:int ->
  ?margin_top:int ->
  ?margin_right:int ->
  ?margin_bottom:int ->
  ?margin_left:int ->
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
  ?data_attrs:(string * string) list ->
  ?data_attrs_signal:(string * string) list Signal.signal ->
  ?on_appear:(unit -> unit) ->
  ?on_pointer_enter:(unit -> unit) ->
  ?on_pointer_leave:(unit -> unit) ->
  ?at:float * float ->
  ?at_signal:(float * float) Signal.signal ->
  ?anchor:anchor ->
  ?anchor_alignment:anchor_alignment ->
  ?anchor_offset:float ->
  ?on_dismiss:(unit -> unit) ->
  ?transition:string -> t list -> t
val context_menu :
  ?key:string ->
  ?accessibility_identifier:string ->
  ?accessibility_identifier_signal:string Signal.signal ->
  ?on_appear:(unit -> unit) ->
  ?on_pointer_enter:(unit -> unit) ->
  ?on_pointer_leave:(unit -> unit) ->
  ?on_dismiss:(unit -> unit) -> t list -> t
val menu_trigger :
  ?key:string ->
  ?accessibility_identifier:string ->
  ?accessibility_identifier_signal:string Signal.signal ->
  ?foreground:string ->
  ?foreground_signal:string Signal.signal ->
  ?style_class:string ->
  ?data_attrs:(string * string) list ->
  ?data_attrs_signal:(string * string) list Signal.signal ->
  ?text:string ->
  ?text_signal:string Signal.signal ->
  ?icon:icon ->
  ?icon_signal:icon Signal.signal ->
  ?label:string ->
  ?disabled:bool ->
  ?disabled_signal:bool Signal.signal -> t list -> t
val menu :
  ?key:string ->
  ?accessibility_identifier:string ->
  ?foreground:string ->
  ?style_class:string ->
  ?data_attrs:(string * string) list ->
  ?data_attrs_signal:(string * string) list Signal.signal ->
  ?text:string ->
  ?text_signal:string Signal.signal ->
  ?icon:icon ->
  ?icon_signal:icon Signal.signal ->
  ?label:string ->
  ?disabled:bool ->
  ?disabled_signal:bool Signal.signal ->
  ?on_dismiss:(unit -> unit) -> t list -> t
val submenu :
  ?key:string ->
  ?text:string ->
  ?icon:icon ->
  ?label:string ->
  ?disabled:bool ->
  ?disabled_signal:bool Signal.signal ->
  ?on_dismiss:(unit -> unit) -> t list -> t
val dialog :
  ?key:string ->
  ?gap:int ->
  ?padding:int ->
  ?padding_horizontal:int ->
  ?padding_vertical:int ->
  ?margin:int ->
  ?margin_horizontal:int ->
  ?margin_vertical:int ->
  ?margin_top:int ->
  ?margin_right:int ->
  ?margin_bottom:int ->
  ?margin_left:int ->
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
  ?accessibility_identifier:string ->
  ?accessibility_identifier_signal:string Signal.signal ->
  ?foreground_signal:string Signal.signal ->
  ?background_signal:string Signal.signal ->
  ?style_class:string ->
  ?data_attrs:(string * string) list ->
  ?data_attrs_signal:(string * string) list Signal.signal ->
  ?on_appear:(unit -> unit) ->
  ?on_pointer_enter:(unit -> unit) ->
  ?on_pointer_leave:(unit -> unit) ->
  ?text:string ->
  ?text_signal:string Signal.signal ->
  ?description:string ->
  ?description_signal:string Signal.signal ->
  ?on_dismiss:(unit -> unit) ->
  ?transition:string -> t list -> t
val sheet :
  ?key:string ->
  ?padding:int ->
  ?padding_horizontal:int ->
  ?padding_vertical:int ->
  ?margin:int ->
  ?margin_horizontal:int ->
  ?margin_vertical:int ->
  ?margin_top:int ->
  ?margin_right:int ->
  ?margin_bottom:int ->
  ?margin_left:int ->
  ?width:int ->
  ?height:int ->
  ?accessibility_identifier:string ->
  ?accessibility_identifier_signal:string Signal.signal ->
  ?style_class:string ->
  ?data_attrs:(string * string) list ->
  ?data_attrs_signal:(string * string) list Signal.signal ->
  ?on_appear:(unit -> unit) ->
  ?on_pointer_enter:(unit -> unit) ->
  ?on_pointer_leave:(unit -> unit) ->
  title:string ->
  ?title_signal:string Signal.signal ->
  ?detents:string ->
  ?detents_signal:string Signal.signal ->
  ?sizing:sheet_sizing ->
  ?sizing_signal:sheet_sizing Signal.signal ->
  ?on_dismiss:(unit -> unit) ->
  ?transition:string -> t list -> t
val tooltip :
  ?key:string ->
  ?container_relative_frame:frame_axes ->
  ?container_relative_frame_inset:int ->
  ?accessibility_identifier:string ->
  ?accessibility_identifier_signal:string Signal.signal ->
  ?on_appear:(unit -> unit) ->
  ?on_pointer_enter:(unit -> unit) ->
  ?on_pointer_leave:(unit -> unit) ->
  ?text:string ->
  ?text_signal:string Signal.signal ->
  ?anchor:anchor ->
  ?anchor_alignment:anchor_alignment ->
  ?anchor_offset:float -> ?tooltip_delay:int -> nothing list -> t
val toast :
  ?key:string ->
  ?padding:int ->
  ?padding_horizontal:int ->
  ?padding_vertical:int ->
  ?margin:int ->
  ?margin_horizontal:int ->
  ?margin_vertical:int ->
  ?margin_top:int ->
  ?margin_right:int ->
  ?margin_bottom:int ->
  ?margin_left:int ->
  ?accessibility_identifier:string ->
  ?accessibility_identifier_signal:string Signal.signal ->
  ?style_class:string ->
  ?data_attrs:(string * string) list ->
  ?data_attrs_signal:(string * string) list Signal.signal ->
  ?on_appear:(unit -> unit) ->
  ?on_pointer_enter:(unit -> unit) ->
  ?on_pointer_leave:(unit -> unit) ->
  ?duration:int ->
  ?label:string ->
  ?toast_class:string ->
  ?on_dismiss:(unit -> unit) -> t list -> t

(** Non-visual element that presents the platform file/photo/camera picker
    when [~request] changes to a new token. [~on_picked] receives a JSON
    payload echoing the request token plus a [files] array of
    [{path, name, content-type}]; [~on_dismiss] fires when the picker is
    cancelled. The backend retains security-scoped file access for picked
    URLs until [~completion] echoes the request token (or the node is
    dropped). [~types] is a comma-separated list of UTIs; [~source]
    selects files (default), photo library, or camera; [~multiple] allows
    multi-selection; [~disabled] gates presentation. *)
val file_picker :
  ?key:string ->
  ?accessibility_identifier:string ->
  ?accessibility_identifier_signal:string Signal.signal ->
  ?on_appear:(unit -> unit) ->
  ?on_pointer_enter:(unit -> unit) ->
  ?on_pointer_leave:(unit -> unit) ->
  ?source:file_picker_source ->
  ?request:file_picker_token ->
  ?request_signal:file_picker_token Signal.signal ->
  ?types:string ->
  ?types_signal:string Signal.signal ->
  ?multiple:bool ->
  ?multiple_signal:bool Signal.signal ->
  ?disabled:bool ->
  ?disabled_signal:bool Signal.signal ->
  ?completion:file_picker_token ->
  ?completion_signal:file_picker_token Signal.signal ->
  ?on_picked:(string -> unit) ->
  ?on_dismiss:(unit -> unit) ->
  ?accept:string ->
  ?accept_signal:string Signal.signal ->
  ?directory:bool ->
  ?directory_signal:bool Signal.signal ->
  t list -> t

(** Portal-mounted positioned surface for menus, pickers and fixed
    cover views. On web it renders as
    [div.lui-popup-positioner > div.lui-popover] appended to the popup
    portal; the positioner is [position:fixed]-style anchored while the
    inner element re-enables pointer events and carries the popup's own
    styling.

    Positioning is one of three modes:

    - [~at:(x, y)] — point positioning (pointer-anchored menus), clamped
      to the viewport with [--lui-popup-available-width/height] set.
    - [~anchor:`below] (optional [~anchor_alignment], [~anchor_offset]) —
      anchored to the element under the popover's retained parent, with
      viewport flipping and scroll/resize tracking.
      [~anchor_target] names a retained control's accessibility identifier when
      the popover lives outside that control's subtree. It requires [~anchor]
      and uses the target's current geometry and ownership.
      [~anchor_rect:(x, y, width, height)] uses a frozen viewport rectangle
      in logical pixels, including after its source control unmounts.
      It requires [~anchor] and is exclusive with [~anchor_target] and [~at].
      Hosts retain alignment, viewport collision handling and resize tracking.
      [~anchor_alignment_offset] shifts the cross axis in logical pixels.
      Positive values move toward the start for end alignment and toward
      the end for start/stretch alignment; negative values reverse that shift.
      It requires [~anchor], defaults to zero, and remains viewport-clamped.
    - neither — cover mode: the positioner spans the viewport
      ([data-cover], inset:0) for fullscreen surfaces.

    [~available_height] bounds the popup's max-height together with the
    positioner's measured collision space. [~role:`menu] sets role=menu on the
    inner element (other roles go through [~data_attrs], which also
    covers data-keep-selection). [~on_dismiss] fires on outside-press or
    Escape while open. *)
val popover :
  ?key:string ->
  ?gap:int ->
  ?main:main_alignment ->
  ?cross:cross_alignment ->
  ?grow:float ->
  ?padding:int ->
  ?padding_horizontal:int ->
  ?padding_vertical:int ->
  ?margin:int ->
  ?margin_horizontal:int ->
  ?margin_vertical:int ->
  ?margin_top:int ->
  ?margin_right:int ->
  ?margin_bottom:int ->
  ?margin_left:int ->
  ?background:string ->
  ?foreground:string ->
  ?border_color:string ->
  ?border_width:int ->
  ?corner_radius:int ->
  ?width:int ->
  ?height:int ->
  ?min_width:int ->
  ?max_width:int ->
  ?max_width_signal:int Signal.signal ->
  ?min_height:int ->
  ?max_height:int ->
  ?container_relative_frame:frame_axes ->
  ?container_relative_frame_inset:int ->
  ?accessibility_identifier:string ->
  ?accessibility_identifier_signal:string Signal.signal ->
  ?foreground_signal:string Signal.signal ->
  ?background_signal:string Signal.signal ->
  ?style_class:string ->
  ?data_attrs:(string * string) list ->
  ?data_attrs_signal:(string * string) list Signal.signal ->
  ?on_appear:(unit -> unit) ->
  ?on_pointer_enter:(unit -> unit) ->
  ?on_pointer_leave:(unit -> unit) ->
  ?opacity:float ->
  ?opacity_signal:float Signal.signal ->
  ?target:popover_target ->
  ?target_signal:popover_target Signal.signal ->
  ?available_height:float ->
  ?available_height_signal:float Signal.signal ->
  ?role:popover_role ->
  ?on_dismiss:(unit -> unit) ->
  ?transition:string -> t list -> t
val toolbar :
  ?key:string ->
  ?gap:int ->
  ?padding:int ->
  ?background:string ->
  ?border_width:int ->
  ?corner_radius:int ->
  ?height:int ->
  ?accessibility_identifier:string ->
  ?accessibility_identifier_signal:string Signal.signal ->
  ?background_signal:string Signal.signal ->
  ?style_class:string ->
  ?data_attrs:(string * string) list ->
  ?data_attrs_signal:(string * string) list Signal.signal ->
  ?on_appear:(unit -> unit) ->
  ?on_pointer_enter:(unit -> unit) ->
  ?on_pointer_leave:(unit -> unit) ->
  ?orientation:orientation ->
  label:string -> ?toolbar_gap:int -> ?toolbar_class:string -> ?placement:toolbar_placement -> t list -> t
val accordion :
  ?key:string ->
  ?height:int ->
  ?accessibility_identifier:string ->
  ?accessibility_identifier_signal:string Signal.signal ->
  ?style_class:string ->
  ?on_appear:(unit -> unit) ->
  ?on_pointer_enter:(unit -> unit) ->
  ?on_pointer_leave:(unit -> unit) ->
  title:string ->
  ?title_signal:string Signal.signal ->
  ?selected:bool ->
  ?selected_signal:bool Signal.signal ->
  ?accordion_height:int ->
  ?on_toggle:(bool -> unit) ->
  ?on_context_menu:(pointer_detail -> unit) -> t list -> t
val menu_item :
  ?key:string ->
  ?gap:int ->
  ?main:main_alignment ->
  ?cross:cross_alignment ->
  ?grow:float ->
  ?padding:int ->
  ?padding_horizontal:int ->
  ?padding_vertical:int ->
  ?margin:int ->
  ?margin_horizontal:int ->
  ?margin_vertical:int ->
  ?margin_top:int ->
  ?margin_right:int ->
  ?margin_bottom:int ->
  ?margin_left:int ->
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
  ?data_attrs:(string * string) list ->
  ?data_attrs_signal:(string * string) list Signal.signal ->
  ?on_appear:(unit -> unit) ->
  ?on_pointer_enter:(unit -> unit) ->
  ?on_pointer_leave:(unit -> unit) ->
  ?text:string ->
  ?text_signal:string Signal.signal ->
  ?icon:icon ->
  ?icon_signal:icon Signal.signal ->
  ?selection_placement:icon_placement ->
  ?variant:variant ->
  ?size:control_size ->
  ?selected:bool ->
  ?checked:bool ->
  ?selected_signal:bool Signal.signal ->
  ?checked_signal:bool Signal.signal ->
  ?disabled:bool ->
  ?disabled_signal:bool Signal.signal ->
  ?on_press:(unit -> unit) ->
  ?on_press_detail:(pointer_detail -> unit) ->
  ?on_pointer_down:(pointer_detail -> unit) ->
  ?on_pointer_up:(pointer_detail -> unit) ->
  ?on_context_menu:(pointer_detail -> unit) ->
  ?tooltip:string ->
  ?tooltip_signal:string Signal.signal ->
  ?shortcut_hint:string ->
  ?shortcut_hint_signal:string Signal.signal ->
  ?transition:string -> t list -> t
val list_item :
  ?key:string ->
  ?main:main_alignment ->
  ?cross:cross_alignment ->
  ?grow:float ->
  ?padding:int ->
  ?padding_horizontal:int ->
  ?padding_vertical:int ->
  ?margin:int ->
  ?margin_horizontal:int ->
  ?margin_vertical:int ->
  ?margin_top:int ->
  ?margin_right:int ->
  ?margin_bottom:int ->
  ?margin_left:int ->
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
  ?data_attrs:(string * string) list ->
  ?data_attrs_signal:(string * string) list Signal.signal ->
  ?on_appear:(unit -> unit) ->
  ?on_pointer_enter:(unit -> unit) ->
  ?on_pointer_leave:(unit -> unit) ->
  ?text:string ->
  ?text_signal:string Signal.signal ->
  ?icon:icon ->
  ?icon_signal:icon Signal.signal ->
  ?icon_placement:icon_placement ->
  ?role:role ->
  ?tree_level:int ->
  ?expanded:bool ->
  ?expanded_signal:bool Signal.signal ->
  ?selected:bool ->
  ?selected_signal:bool Signal.signal ->
  ?disabled:bool ->
  ?disabled_signal:bool Signal.signal ->
  ?on_press:(unit -> unit) ->
  ?on_long_press:(unit -> unit) ->
  ?on_double_press:(unit -> unit) ->
  ?on_submit:(unit -> unit) ->
  ?on_toggle:(bool -> unit) ->
  ?separator:separator_visibility ->
  ?swipe_actions:swipe_action_el list ->
  ?on_press_detail:(pointer_detail -> unit) ->
  ?on_pointer_down:(pointer_detail -> unit) ->
  ?on_pointer_up:(pointer_detail -> unit) ->
  ?on_context_menu:(pointer_detail -> unit) ->
  ?list_marker:list_marker ->
  ?transition:string -> t list -> t

(** A named group of rows inside a {!list}: [~header]/[~footer] take any
    element and mount it in a dedicated slot node, [~key] sets both the
    reload key and the wire [key] identity used by scroll targeting. *)
val list_section :
  ?key:string ->
  ?accessibility_identifier:string ->
  ?separator:separator_visibility ->
  ?header:t -> ?footer:t -> t list -> t
val swipe_actions :
  ?key:string ->
  ?accessibility_identifier:string -> swipe_action_el list -> t
val swipe_action :
  ?key:string ->
  ?accessibility_identifier:string ->
  ?text:string ->
  ?text_signal:string Signal.signal ->
  ?icon:icon ->
  ?icon_signal:icon Signal.signal ->
  ?variant:variant ->
  ?edge:swipe_edge ->
  ?background:string ->
  ?disabled:bool ->
  ?on_press:(unit -> unit) ->
  ?on_press_detail:(pointer_detail -> unit) ->
  ?on_pointer_down:(pointer_detail -> unit) ->
  ?on_pointer_up:(pointer_detail -> unit) -> nothing list -> swipe_action_el
val avatar :
  ?key:string ->
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
  ?data_attrs:(string * string) list ->
  ?data_attrs_signal:(string * string) list Signal.signal ->
  ?on_appear:(unit -> unit) ->
  ?on_pointer_enter:(unit -> unit) ->
  ?on_pointer_leave:(unit -> unit) ->
  ?text:string ->
  ?text_signal:string Signal.signal ->
  ?image:int ->
  ?image_signal:int Signal.signal ->
  ?source_x:float ->
  ?source_y:float ->
  ?source_width:float -> ?source_height:float -> ?label:string ->
  ?transition:string -> nothing list -> t
val image :
  ?key:string ->
  ?grow:float ->
  ?padding:int ->
  ?padding_horizontal:int ->
  ?padding_vertical:int ->
  ?margin:int ->
  ?margin_horizontal:int ->
  ?margin_vertical:int ->
  ?margin_top:int ->
  ?margin_right:int ->
  ?margin_bottom:int ->
  ?margin_left:int ->
  ?background:string ->
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
  ?background_signal:string Signal.signal ->
  ?style_class:string ->
  ?data_attrs:(string * string) list ->
  ?data_attrs_signal:(string * string) list Signal.signal ->
  ?on_appear:(unit -> unit) ->
  ?on_pointer_enter:(unit -> unit) ->
  ?on_pointer_leave:(unit -> unit) ->
  ?image:int ->
  ?image_signal:int Signal.signal ->
  ?url:string ->
  ?url_signal:string Signal.signal ->
  ?alt:string ->
  ?loading:image_loading ->
  ?referrer_policy:referrer_policy ->
  ?on_load:(unit -> unit) ->
  ?source_x:float ->
  ?source_y:float ->
  ?source_width:float -> ?source_height:float -> ?label:string ->
  ?transition:string -> nothing list -> t
val media_surface :
  ?key:string ->
  ?grow:float ->
  ?padding:int ->
  ?padding_horizontal:int ->
  ?padding_vertical:int ->
  ?margin:int ->
  ?margin_horizontal:int ->
  ?margin_vertical:int ->
  ?margin_top:int ->
  ?margin_right:int ->
  ?margin_bottom:int ->
  ?margin_left:int ->
  ?background:string ->
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
  ?background_signal:string Signal.signal ->
  ?style_class:string ->
  ?data_attrs:(string * string) list ->
  ?data_attrs_signal:(string * string) list Signal.signal ->
  ?on_appear:(unit -> unit) ->
  ?on_pointer_enter:(unit -> unit) ->
  ?on_pointer_leave:(unit -> unit) ->
  ?surface:int ->
  ?surface_signal:int Signal.signal -> ?label:string ->
  ?transition:string -> nothing list -> t

(** A semantic URL link. An optional [on_press] owns primary activation while
    retaining the URL for context menus and alternate navigation. *)
val link :
  ?key:string ->
  ?main:main_alignment ->
  ?cross:cross_alignment ->
  ?grow:float ->
  ?padding:int ->
  ?padding_horizontal:int ->
  ?padding_vertical:int ->
  ?margin:int ->
  ?margin_horizontal:int ->
  ?margin_vertical:int ->
  ?margin_top:int ->
  ?margin_right:int ->
  ?margin_bottom:int ->
  ?margin_left:int ->
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
  ?data_attrs:(string * string) list ->
  ?data_attrs_signal:(string * string) list Signal.signal ->
  ?on_appear:(unit -> unit) ->
  ?on_pointer_enter:(unit -> unit) ->
  ?on_pointer_leave:(unit -> unit) ->
  ?url:string ->
  ?url_signal:string Signal.signal ->
  ?target:link_target ->
  ?text:string ->
  ?text_signal:string Signal.signal ->
  ?icon:icon ->
  ?icon_signal:icon Signal.signal ->
  ?icon_placement:icon_placement ->
  ?label:string ->
  ?disabled:bool -> ?disabled_signal:bool Signal.signal ->
  ?on_press:(unit -> unit) ->
  ?transition:string -> t list -> t

(** Local file image. Fit preserves the whole image by default; fill crops to
    its frame while preserving the original aspect ratio. *)
val file_image :
  ?key:string ->
  ?grow:float ->
  ?padding:int ->
  ?padding_horizontal:int ->
  ?padding_vertical:int ->
  ?margin:int ->
  ?margin_horizontal:int ->
  ?margin_vertical:int ->
  ?margin_top:int ->
  ?margin_right:int ->
  ?margin_bottom:int ->
  ?margin_left:int ->
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
  ?data_attrs:(string * string) list ->
  ?data_attrs_signal:(string * string) list Signal.signal ->
  ?on_appear:(unit -> unit) ->
  ?on_pointer_enter:(unit -> unit) ->
  ?on_pointer_leave:(unit -> unit) ->
  ?path:string ->
  ?path_signal:string Signal.signal ->
  ?max_pixel_size:int ->
  ?fit:image_fit ->
  ?label:string ->
  ?on_press:(unit -> unit) ->
  ?on_press_detail:(pointer_detail -> unit) ->
  ?on_pointer_down:(pointer_detail -> unit) ->
  ?on_pointer_up:(pointer_detail -> unit) ->
  ?transition:string -> nothing list -> t
val file_preview :
  ?key:string ->
  ?path:string ->
  ?path_signal:string Signal.signal ->
  ?accessibility_identifier:string ->
  ?accessibility_identifier_signal:string Signal.signal ->
  ?on_dismiss:(unit -> unit) -> nothing list -> t
val stepper :
  ?key:string ->
  ?accessibility_identifier:string ->
  ?accessibility_identifier_signal:string Signal.signal ->
  ?on_appear:(unit -> unit) ->
  ?on_pointer_enter:(unit -> unit) ->
  ?on_pointer_leave:(unit -> unit) ->
  active:int ->
  ?active_signal:int Signal.signal -> ?label:string -> step_el list -> t
val step :
  ?key:string ->
  ?accessibility_identifier:string ->
  ?accessibility_identifier_signal:string Signal.signal ->
  ?on_appear:(unit -> unit) ->
  ?on_pointer_enter:(unit -> unit) ->
  ?on_pointer_leave:(unit -> unit) ->
  text:string -> ?text_signal:string Signal.signal -> nothing list -> step_el
val timeline :
  ?key:string ->
  ?gap:int ->
  ?grow:float ->
  ?accessibility_identifier:string ->
  ?accessibility_identifier_signal:string Signal.signal ->
  ?on_appear:(unit -> unit) ->
  ?on_pointer_enter:(unit -> unit) ->
  ?on_pointer_leave:(unit -> unit) -> ?label:string -> timeline_item_el list -> t
val timeline_item :
  ?key:string ->
  ?accessibility_identifier:string ->
  ?accessibility_identifier_signal:string Signal.signal ->
  ?on_appear:(unit -> unit) ->
  ?on_pointer_enter:(unit -> unit) ->
  ?on_pointer_leave:(unit -> unit) ->
  title:string ->
  ?title_signal:string Signal.signal ->
  ?description:string ->
  ?meta:string ->
  ?indicator:string ->
  ?icon:icon ->
  ?icon_signal:icon Signal.signal ->
  ?variant:variant ->
  ?connector:bool ->
  ?selected:bool -> ?on_press:(unit -> unit) ->
  ?on_press_detail:(pointer_detail -> unit) ->
  ?on_pointer_down:(pointer_detail -> unit) ->
  ?on_pointer_up:(pointer_detail -> unit) -> nothing list -> timeline_item_el

(** Wraps an element so its subtree resolves semantic color names against
    the given token table, merging over the platform defaults, and
    optionally overrides light/dark appearance. *)
val themed :
  ?tokens:(string * Lui_ui.theme_token_value) list ->
  ?tokens_signal:
    (string * Lui_ui.theme_token_value) list Signal.signal ->
  ?mode:Lui_ui.theme_mode ->
  ?mode_signal:Lui_ui.theme_mode Signal.signal -> t -> t
