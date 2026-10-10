(** macOS accessibility bridge.

    Mirrors a [Lui_a11y] semantic tree as NSAccessibilityElement objects
    so assistive technology (VoiceOver) sees a self-drawn app: roles,
    names, values, focus and actions. The ObjC side keeps a flat
    node-id -> element table; each [sync] pushes attribute sets for the
    nodes Lui_a11y reports changed and posts AX notifications.

    The host view exposes the elements by delegating its accessibility
    container methods to the C helpers declared in [lui_ax.h]
    ([LuiAxTopElements], [LuiAxHitTest], [LuiAxFocusedElement]).

    Call everything on the host's UI thread. *)

type rect = { x : float; y : float; w : float; h : float }
(** A rect in the host view's coordinate space (points). *)

type native_view = nativeint
(** A raw NSView pointer. *)

type t
(** An attached bridge: one [Lui_a11y] tree on one view. *)

val attach : frame_of:(int -> rect option) -> Lui_a11y.t ->
  native_view -> t
(** [attach ~frame_of a11y view] creates the element mirror and posts an
    initial AXLayoutChanged on [view]. [frame_of id] returns the node's
    rect in the view's coordinate space (points); the bridge converts it
    to screen coordinates. When the view is not flipped ([isFlipped]
    false), flip layout rects into its space with {!y_flip}. *)

val detach : t -> unit
(** Destroys every element (posting AXUIElementDestroyed) and frees the
    bridge. *)

val a11y : t -> Lui_a11y.t
val view : t -> native_view
val bridge_id : t -> int

val sync : t -> int list
(** [sync t] drains the store's dirty set through {!Lui_a11y.sync},
    pushes the changed nodes, and posts the selected notifications.
    Returns the changed ids. *)

val refresh_frames : t -> unit
(** Re-pushes every element's frame — call after scroll/resize, which
    moves elements without touching their a11y records. *)

val set_focused : t -> int -> unit
val clear_focused : t -> unit
(** Route focus through {!Lui_a11y} and push the resulting changes. *)

(** {2 VoiceOver actions} *)

type action =
  | Press
  | Increment
  | Decrement
  | Focus
  | Set_value of string
  | Scroll_to_visible
  | Expand
  | Collapse

val drain_actions : t -> (int * action) list
(** Actions VoiceOver performed on the elements since the last call —
    press, increment/decrement on ranged controls, focus, text set on
    fields, expand/collapse on outline rows. Poll each event-loop turn. *)

(** {2 Role mapping} *)

val ax_role_table : (Lui_a11y.role * (string * string)) list
(** Every a11y role mapped to [(AX role, AX subrole)]; [""] = no
    subrole. *)

val ax_role_of : Lui_a11y.node_a11y -> string * string
(** Like the table plus the state-dependent subroles (password fields
    become secure text fields). *)

val actions_of : Lui_a11y.node_a11y -> int
(** Bitmask of the actions a node offers: 1 press, 2 increment,
    4 decrement, 8 focus, 16 set-value, 32 scroll-to-visible,
    64 disclose. *)

(** {2 Notification selection} *)

type notify_target =
  | On_element  (** post on the node's element *)
  | On_parent   (** post on the a11y parent's element (view if none) *)
  | On_view     (** post on the host view *)

val notifications_of :
  old:Lui_a11y.node_a11y option ->
  cur:Lui_a11y.node_a11y option -> (string * notify_target) list
(** AX notifications a node change warrants: destroyed, value, title,
    focused, selected-rows and expanded changes. *)

val structure_changed :
  old:Lui_a11y.node_a11y option ->
  cur:Lui_a11y.node_a11y option -> bool
(** Whether a node change alters the tree (add/remove/reparent/children
    list/role swap) — these feed the single AXLayoutChanged on the
    view. *)

val notif_destroyed : string
val notif_value : string
val notif_title : string
val notif_focused : string
val notif_selected_rows : string
val notif_expanded : string

(** {2 Pure helpers} *)

val y_flip : container_height:float -> rect -> rect
(** [y_flip ~container_height r] maps [r] between a top-left-origin
    space and a bottom-left-origin space of the same height:
    [y' = container_height - y - h]. *)

val utf16_length : string -> int
(** Length of a UTF-8 string in UTF-16 code units — what
    AXNumberOfCharacters counts. *)
