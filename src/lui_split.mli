(** Bonsplit-style tabbed split panes as LUI extension components.

    The application owns the split tree as ordinary data; each platform
    backend renders it natively (tab strip, draggable dividers, drop
    indicators, animations, keyboard navigation) and reports semantic events
    back so the app can patch the tree.

    Tree shape:
      [split_view
        [ split_branch ~orientation ~ratio [ left; right ]
        | split_pane ~pane_id [ split_tab ~tab_id ~title [content]; ... ] ]]
    A bare [split_pane] may be mounted directly under [split_view] for a
    single-pane surface.

    Identity is app-assigned: [~pane_id] and [~tab_id] are stable strings the
    app uses to track selection and resolve events. *)

val split_view_schema : Lui_extension.extension_component_schema
val split_branch_schema : Lui_extension.extension_component_schema
val split_pane_schema : Lui_extension.extension_component_schema
val split_tab_schema : Lui_extension.extension_component_schema

val register_into : Lui_extension.extension_registry -> unit
(** Register all four split schemas into an existing (unfrozen) extension
    registry, e.g. one shared with application-specific extensions. *)

val registry : unit -> Lui_extension.extension_registry
(** A fresh frozen registry containing only the split schemas. *)

type split_branch_ratio_changed = {
  event_node : int;
  ratio : float;
}
(** Committed divider position; emitted once per drag (on release) and once
    per keyboard nudge. *)

type split_pane_tab_selected = {
  event_node : int;
  tab : string;  (** the tab's [tab-id] *)
}

type split_pane_tab_closed = {
  event_node : int;
  tab : string;
}
(** Close-button click, middle-click, or the platform's close-tab shortcut on
    this tab. *)

type split_pane_tab_moved = {
  event_node : int;  (** the target (dropped-onto) pane *)
  tab : string;
  index : int;  (** insertion index within the target pane's tab list *)
  from_pane : string;  (** source [pane-id]; equals the target's when
                           reordering within one pane *)
}

type split_pane_focused = { event_node : int }

type split_pane_navigate = {
  event_node : int;
  direction : string;  (** "left" | "right" | "up" | "down" *)
}
(** Directional focus request (option/alt-modified arrows). The app maps the
    direction onto a neighbouring pane and sets its [~focused] prop. *)

type split_pane_split_requested = {
  event_node : int;
  orientation : string;  (** "horizontal" | "vertical" *)
}

type split_pane_split_drop = {
  event_node : int;  (** the pane whose edge received the drop *)
  tab : string;
  from_pane : string;
  edge : string;  (** "left" | "right" | "top" | "bottom" *)
}
(** A tab dropped on a pane edge asks the app to split this pane in that
    direction and move the tab into the new pane. *)

type split_pane_pane_closed = { event_node : int }

val decode_split_branch_ratio_changed :
  Lui_protocol.event -> split_branch_ratio_changed option
val decode_split_pane_tab_selected :
  Lui_protocol.event -> split_pane_tab_selected option
val decode_split_pane_tab_closed :
  Lui_protocol.event -> split_pane_tab_closed option
val decode_split_pane_tab_moved :
  Lui_protocol.event -> split_pane_tab_moved option
val decode_split_pane_pane_focused :
  Lui_protocol.event -> split_pane_focused option
val decode_split_pane_navigate :
  Lui_protocol.event -> split_pane_navigate option
val decode_split_pane_split_requested :
  Lui_protocol.event -> split_pane_split_requested option
val decode_split_pane_split_drop :
  Lui_protocol.event -> split_pane_split_drop option
val decode_split_pane_pane_closed :
  Lui_protocol.event -> split_pane_pane_closed option

val split_view :
  ?key:string ->
  ?divider_thickness:float ->
  ?divider_thickness_signal:float Signal.signal ->
  ?animation:bool ->
  ?animation_signal:bool Signal.signal ->
  ?accessibility_identifier:string ->
  ?accessibility_identifier_signal:string Signal.signal ->
  Lui_elements.t list ->
  Lui_elements.t
(** [split_view [root]] mounts the split surface. [~divider_thickness] is the
    divider hit target in points (platforms render a 1-2pt visible line
    centred inside it); [~animation:false] disables spring/transition
    animation. *)

val split_branch :
  ?key:string ->
  orientation:[ `horizontal | `vertical ] ->
  ratio:float ->
  ?ratio_signal:float Signal.signal ->
  ?on_ratio_changed:(split_branch_ratio_changed -> unit) ->
  Lui_elements.t list ->
  Lui_elements.t
(** Internal node with exactly two [split_branch] or [split_pane] children.
    [~orientation:`horizontal] places children side by side (a vertical
    divider); [`vertical] stacks them. [~ratio] is the first child's share of
    the axis (0.0-1.0). *)

val split_pane :
  ?key:string ->
  pane_id:string ->
  ?selected:string ->
  ?selected_signal:string Signal.signal ->
  ?focused:bool ->
  ?focused_signal:bool Signal.signal ->
  ?accessibility_identifier:string ->
  ?on_tab_selected:(split_pane_tab_selected -> unit) ->
  ?on_tab_closed:(split_pane_tab_closed -> unit) ->
  ?on_tab_moved:(split_pane_tab_moved -> unit) ->
  ?on_pane_focused:(split_pane_focused -> unit) ->
  ?on_navigate:(split_pane_navigate -> unit) ->
  ?on_split_requested:(split_pane_split_requested -> unit) ->
  ?on_split_drop:(split_pane_split_drop -> unit) ->
  ?on_pane_closed:(split_pane_pane_closed -> unit) ->
  Lui_elements.t list ->
  Lui_elements.t
(** Leaf pane: a tab strip over the selected tab's content. [~selected] is
    the [tab-id] to show (defaults to the first tab). *)

val split_tab :
  ?key:string ->
  tab_id:string ->
  title:string ->
  ?title_signal:string Signal.signal ->
  ?icon:string ->
  ?icon_signal:string Signal.signal ->
  ?dirty:bool ->
  ?dirty_signal:bool Signal.signal ->
  ?closable:bool ->
  ?accessibility_identifier:string ->
  Lui_elements.t list ->
  Lui_elements.t
(** One tab: [~title]/[~icon]/[~dirty] dress the strip entry; the standard
    children are the tab's content, rendered only while selected. *)

(** The shared controller. Owns the split tree as plain data, applies
    backend events to it, and renders it back into extension nodes, so
    selection/move/split/navigate policy is identical on every platform.
    Apps keep a [Model.t] in their model, dispatch [Model.action] on events
    (usually via the [~dispatch] wired by {!Model.render}), and re-render.

    {[
      let update model = function
        | Split_action action ->
          { model with split = Lui_split.Model.update model.split action }
        | ...
      and view model =
        Lui_split.Model.render model.split ~dispatch:(fun a -> ...)
          ~build:(fun tab -> [ page_content tab ])
    ]} *)
module Model : sig
  type direction =
    [ `left
    | `right
    | `up
    | `down
    ]

  type orientation =
    [ `horizontal
    | `vertical
    ]

  type edge =
    [ `left
    | `right
    | `top
    | `bottom
    ]

  type tab = {
    tab_id : string;
    tab_title : string;
    tab_icon : string option;
    tab_dirty : bool;
    tab_closable : bool;
  }

  val tab :
    ?icon:string ->
    ?dirty:bool ->
    ?closable:bool ->
    tab_id:string ->
    title:string ->
    unit ->
    tab

  type pane = {
    pane_id : string;
    pane_tabs : tab list;
    pane_selected : string option;
  }

  val pane : ?selected:string -> pane_id:string -> tab list -> pane

  type node =
    | Leaf of pane
    | Split of {
        split_id : string;
        split_orientation : orientation;
        split_ratio : float;
        split_first : node;
        split_second : node;
      }

  type t

  val create : ?focused:string -> node -> t
  val root : t -> node
  val focused : t -> string option

  type action =
    | Select_tab of string * string
    | Close_tab of string * string
    | Move_tab of {
        move_tab : string;
        move_from : string;
        move_to : string;
        move_index : int;
      }
    | Split_drop of {
        drop_tab : string;
        drop_from : string;
        drop_target : string;
        drop_edge : edge;
      }
    | Close_pane of string
    | Focus_pane of string
    | Navigate of string * direction
    | Request_split of string * orientation
    | Set_ratio of string * float
  (** Semantic intents decoded from backend events. *)

  val update : t -> action -> t
  (** Policies: moving a tab selects it in the target pane; a tab dropped on
      a pane edge splits that pane (new pane takes the smaller 25% share); a
      pane emptied by a close or move is removed and its split collapses;
      the last pane is never removed. *)

  val render :
    ?key:string ->
    ?divider_thickness:float ->
    ?animation:bool ->
    build:(tab -> Lui_elements.t list) ->
    dispatch:(action -> unit) ->
    t ->
    Lui_elements.t
  (** Renders the tree under one [split-view] node and wires every pane and
      branch event through [pane_action]/decoders into [dispatch]. *)
end
