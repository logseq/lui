(** Windows accessibility bridge.

    Mirrors a [Lui_a11y] semantic tree as UI Automation providers so
    assistive technology (Narrator, NVDA) sees a self-drawn app:
    control types, names, values, patterns, focus and actions.

    The C side keeps one [IRawElementProviderSimple] COM object per
    a11y node, wired into a fragment tree: children implement
    [IRawElementProviderFragment] for navigation and the control
    patterns their role offers; the root additionally implements
    [IRawElementProviderFragmentRoot]. The host window answers
    WM_GETOBJECT through {!wm_getobject}, which hands the root to UI
    Automation via [UiaReturnRawElementProvider]. Assistive-technology
    actions are enqueued on the C side and polled here via
    {!drain_actions} — no platform code ever calls back into the
    runtime.

    Call everything on the host's UI thread, the same discipline the
    window procedure expects. *)

type rect = { x : float; y : float; w : float; h : float }
(** A rect in the host window's client coordinate space (points). *)

type native_window = nativeint
(** A raw HWND. *)

type t
(** An attached bridge: one [Lui_a11y] tree on one window. *)

val attach : frame_of:(int -> rect option) -> Lui_a11y.t ->
  native_window -> t
(** [attach ~frame_of a11y hwnd] creates the provider tree and
    registers [hwnd] so WM_GETOBJECT answers with it. [frame_of id]
    returns the node's rect in client coordinates (points); the bridge
    converts it to screen pixels with the window's DPI. *)

val detach : t -> unit
(** Disconnects every provider (UIA clients see them die) and frees
    the bridge. *)

val a11y : t -> Lui_a11y.t
val window : t -> native_window
val bridge_id : t -> int

val sync : t -> int list
(** [sync t] drains the store's dirty set through {!Lui_a11y.sync},
    pushes the changed nodes, and raises the selected UIA events.
    Returns the changed ids. *)

val refresh_frames : t -> unit
(** Re-pushes every element's frame — call after scroll/resize, which
    moves elements without touching their a11y records. *)

val set_focused : t -> int -> unit
val clear_focused : t -> unit
(** Route focus through {!Lui_a11y} and push the resulting changes. *)

val wm_getobject : native_window -> nativeint -> nativeint ->
  nativeint
(** The window procedure's answer to WM_GETOBJECT: returns the LRESULT
    [UiaReturnRawElementProvider] produces for UIA object ids on a
    window with an attached bridge, or [0n] when the request is not
    for this bridge — the host then defers to [DefWindowProc]. *)

(** {2 Assistive-technology actions} *)

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
(** Actions assistive technology performed on the elements since the
    last call — invoke/toggle presses, range increments and
    decrements, focus, text set on fields, expand/collapse on tree
    items and combo boxes, scroll-into-view. Poll each event-loop
    turn. *)

(** {2 Control type mapping} *)

val control_type_table : (Lui_a11y.role * int) list
(** Every a11y role mapped to a UIA_ControlTypeId. *)

val control_type_of : Lui_a11y.node_a11y -> int
(** The control type of a node — the table lookup. *)

val localized_type_of : Lui_a11y.node_a11y -> string
(** The LocalizedControlType override for nodes whose control type
    alone reads wrong (a switch is a "toggle switch", not a button);
    [""] means the control type's own localized name. *)

val patterns_of : Lui_a11y.node_a11y -> int
(** Bitmask of the control patterns a node offers: 1 Invoke,
    2 Toggle, 4 SelectionItem, 8 Selection, 16 RangeValue, 32 Value,
    64 ExpandCollapse, 128 ScrollItem. *)

val toggle_state_of : Lui_a11y.node_a11y -> int
(** ToggleState for toggle-pattern nodes: 0 off, 1 on, 2 indeterminate;
    [-1] when the node does not toggle. *)

val expand_state_of : Lui_a11y.node_a11y -> int
(** ExpandCollapseState for expand-collapse nodes: 0 collapsed,
    1 expanded, 3 leaf node (expandable role without children);
    [-1] when the node does not expand. *)

val actions_of : Lui_a11y.node_a11y -> int
(** Bitmask of the actions a node offers: 1 press, 2 increment,
    4 decrement, 8 focus, 16 set-value, 32 scroll-to-visible,
    64 expand, 128 collapse. *)

(** {2 Event selection} *)

(** A property value in UIA's terms (VARIANT). *)
type variant =
  | V_empty
  | V_int of int
  | V_num of float
  | V_bool of bool
  | V_str of string

(** What a change warrants telling UIA clients. *)
type notify =
  | Prop of int * variant * variant
      (** UIA_PropertyId with the old and new values *)
  | Event of int  (** UIA_EventId to raise on the element *)

type notify_target =
  | On_element  (** raise on the node's provider *)
  | On_parent   (** raise on the a11y parent's provider (root if none) *)
  | On_root     (** raise on the fragment root *)

val notifications_of :
  old:Lui_a11y.node_a11y option ->
  cur:Lui_a11y.node_a11y option -> (notify * notify_target) list
(** UIA notifications a node change warrants: name/enabled/value/
    toggle/selection/expand property changes plus focus and selection
    events. *)

val structure_changed :
  old:Lui_a11y.node_a11y option ->
  cur:Lui_a11y.node_a11y option -> bool
(** Whether a node change alters the tree (add/remove/reparent/children
    list/role swap) — these feed StructureChanged events. *)

val struct_invalidations :
  old:Lui_a11y.node_a11y option ->
  cur:Lui_a11y.node_a11y option -> int list
(** The node ids whose children a change invalidated — the providers a
    [UiaRaiseStructureChangedEvent] with ChildrenInvalidated belongs
    on. [-1] means the fragment root (no a11y parent). *)

(** {2 Property and event ids (UIA_* constants)} *)

val prop_name : int
val prop_control_type : int
val prop_localized_type : int
val prop_is_enabled : int
val prop_has_keyboard_focus : int
val prop_is_keyboard_focusable : int
val prop_is_password : int
val prop_is_required_for_form : int
val prop_is_dialog : int
val prop_help_text : int
val prop_full_description : int
val prop_live_setting : int
val prop_position_in_set : int
val prop_size_of_set : int
val prop_level : int
val prop_value : int
val prop_range_value : int
val prop_toggle_state : int
val prop_is_selected : int
val prop_expand_state : int

val event_focus_changed : int
val event_element_selected : int
val event_added_to_selection : int
val event_removed_from_selection : int

(** {2 Pattern ids (UIA_*PatternId constants)} *)

val pattern_invoke : int
val pattern_selection : int
val pattern_value : int
val pattern_range_value : int
val pattern_expand_collapse : int
val pattern_selection_item : int
val pattern_toggle : int
val pattern_scroll_item : int

(** {2 Pure helpers} *)

val utf16_length : string -> int
(** Length of a UTF-8 string in UTF-16 code units — what UIA text
    properties count. *)

val utf16_encode : string -> int array
(** The UTF-16 code units of a UTF-8 string, as integers — astral
    code points become surrogate pairs, invalid bytes become [0xFFFD]. *)

(** {2 UIA client probes (in-process verification)}

    Wrappers over the UI Automation client API used by the test suite
    to enumerate the provider tree the way a real screen reader would:
    [UiaNodeFromProvider] upgrades a raw provider into a client
    [HUIANODE], [UiaNavigate] walks the tree, [UiaGetPropertyValue] and
    [UiaGetRuntimeId] read it, and [UiaHasServerSideProvider] proves the
    window answers WM_GETOBJECT. Pattern calls go straight to the
    provider's COM objects — the same calls UIA marshals for a client.
    Probe handles and pattern actions only work on Windows; on other
    platforms every probe raises [Failure]. *)

val probe_has_provider : t -> bool
(** [UiaHasServerSideProvider] on the bridge's window — the real
    WM_GETOBJECT round trip. *)

val probe_node_of_root : t -> nativeint
(** A client-side [HUIANODE] for the bridge's fragment root, obtained
    via [UiaNodeFromProvider]. [0n] on failure; free with
    {!probe_free}. *)

val probe_find : t -> int -> nativeint
(** A client-side [HUIANODE] for the element with the given node id,
    found by walking the client tree from the root. [0n] when absent;
    free with {!probe_free}. *)

val probe_free : nativeint -> unit
(** Releases a client node ([UiaNodeRelease]). *)

val probe_children : nativeint -> int array
(** The runtime ids of a client node's children, in order — the
    client-API view of the fragment's first-child/next-sibling walk. *)

val probe_runtime_id : nativeint -> int
(** The node id in a client node's runtime id ([-1] when the node is
    the root, which the window identifies). *)

val probe_prop_int : nativeint -> int -> int
(** An integer property of a client node via [UiaGetPropertyValue];
    [-1] when the property is empty or not an int. *)

val probe_prop_bool : nativeint -> int -> bool
(** A boolean property of a client node; [false] when absent. *)

val probe_prop_str : nativeint -> int -> string
(** A string property of a client node; [""] when absent. *)

val probe_prop_num : nativeint -> int -> float
(** A numeric property of a client node; [nan] when absent. *)

val probe_pattern : t -> int -> int -> bool
(** Whether the element [id] offers the pattern id (through
    [GetPatternProvider]). *)

val probe_invoke : t -> int -> unit
(** Performs the node's Invoke pattern — enqueues an action. *)

val probe_toggle : t -> int -> unit
(** Performs the node's Toggle pattern — enqueues an action. *)

val probe_select : t -> int -> unit
(** Performs the node's SelectionItem.Select — enqueues an action. *)

val probe_set_range : t -> int -> float -> unit
(** Performs the node's RangeValue.SetValue — enqueues a set-value
    action whose text is the requested number. *)

val probe_set_value : t -> int -> string -> unit
(** Performs the node's Value.SetValue — enqueues a set-value action. *)

val probe_expand : t -> int -> unit
val probe_collapse : t -> int -> unit
(** Performs the node's ExpandCollapse.Expand/Collapse. *)

val probe_scroll_into_view : t -> int -> unit
(** Performs the node's ScrollItem.ScrollIntoView. *)

val probe_hit_test : t -> float -> float -> int
(** [probe_hit_test t x y] asks the fragment root which element sits
    at the client-space point [(x, y)] (points, like [frame_of]
    rects). Returns its node id, or [-1]. *)

val probe_focused : t -> int
(** The node id the fragment root reports as focused, or [-1]. *)
