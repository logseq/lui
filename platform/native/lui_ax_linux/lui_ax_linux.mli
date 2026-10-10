(* AT-SPI accessibility bridge for the native backend on Linux.

   Serves the [Lui_a11y] semantic tree to assistive technologies over the
   accessibility bus (AT-SPI/D-Bus): objects are registered under
   [/org/a11y/atspi/accessible/], the app's own tree root sits at
   [/org/a11y/atspi/accessible/root] implementing [Application], and
   every served node implements the [Accessible] and [Component]
   interfaces plus [Action], [Text] or [Value] when its role calls for
   them.

   Two layers, on purpose:

   - Protocol semantics live in pure OCaml: role/state/action mapping,
     object path wiring, method-call dispatch ([handle_call]), reply
     marshalling values ([dvalue]), introspection XML and the diff ->
     event translation. All of it is testable without a bus.
   - Transport lives in C stubs: a capability-probed D-Bus client that
     connects to the a11y bus when the platform provides it and carries
     the marshalled messages. On this VM the development headers are
     absent, so the transport binds the runtime library at load time
     (dlopen); when the library or a bus is unreachable the bridge stays
     correct — events queue and [flush] reports zero sent. *)

(** {2 Served values} *)

(** A marshalled D-Bus value: the one type the OCaml layer hands to the
    transport for method replies and event payloads.  The declaration
    order fixes the wire tag numbering used by the C marshalling — do
    not reorder without updating [lui_ax_linux_stubs.c]. *)
type dvalue =
  | DStr of string                        (** STRING *)
  | DInt of int                           (** INT32 *)
  | DUInt of int                          (** UINT32 *)
  | DN16 of int                           (** INT16 *)
  | DBool of bool                         (** BOOLEAN *)
  | DDbl of float                         (** DOUBLE *)
  | DObj of string                        (** OBJECT_PATH *)
  | DVar of string * dvalue               (** VARIANT: signature, payload *)
  | DArr of string * dvalue list          (** ARRAY: element sig, items *)
  | DStruct of dvalue list                (** STRUCT (e.g. (so)) *)
  | DDict of string * (string * dvalue) list
      (** ARRAY of DICT_ENTRY: container sig ("{sv}" or "{ss}") plus
          (key, value) pairs — the value must already be a [DVar] for
          "{sv}" dicts. *)

(** An object reference: (bus name, object path).  The AT-SPI null
    object is [("", "/org/a11y/atspi/null")]. *)
type obj_ref = string * string

(** {2 Wire constants} *)

val null_ref : obj_ref
val root_path : string
val cache_path : string
val path_prefix : string

val path_of : int -> string
(** [path_of id] is ["/org/a11y/atspi/accessible/<id>"]. *)

val id_of_path : string -> int option
(** Inverse of [path_of]; [None] for paths outside our object space. *)

(** {2 Role mapping} *)

val role_map : (Lui_a11y.role * int * string) list
(** Complete mapping table: every [Lui_a11y.role], exactly once, to the
    AT-SPI role number and the AT-SPI role-name string.  Roles AT-SPI
    lacks map to the closest semantic role (documented in the .ml). *)

val atspi_role_of : Lui_a11y.role -> int
val atspi_role_name : Lui_a11y.role -> string
(** Human-readable role name matching AT-SPI conventions ("push button",
    "toggle button", ...). *)

val role_application : int
val role_frame : int
val role_password_text : int
(** Sentinels used by the bridge itself (the synthetic application root,
    top-level windows, and password fields whose role is derived from
    state rather than kind). *)

(** {2 State translation} *)

val stateset_of : Lui_a11y.role option -> Lui_a11y.node_a11y -> int list
(** [stateset_of parent_role node] translates the node's flags into the
    AT-SPI state set: ENABLED+SENSITIVE unless disabled, VISIBLE+SHOWING
    (only unhidden nodes are served), OPAQUE, FOCUSABLE/FOCUSED,
    SELECTABLE by parent role, SELECTED, CHECKABLE/CHECKED/INDETERMINATE
    for tri-states, EXPANDABLE+EXPANDED/COLLAPSED, REQUIRED, READ_ONLY or
    EDITABLE for text roles, SINGLE_LINE/MULTI_LINE, HAS_POPUP for
    popups/combos, ACTIVE for the top window.  Sorted ascending. *)

val state_names : (int * string) list
(** AT-SPI state number -> detail name used in StateChanged events. *)

val state_name : int -> string

(** {2 Interfaces, actions, attributes} *)

val interfaces_of : Lui_a11y.node_a11y -> string list
(** The AT-SPI interface names an object claims: always Accessible and
    Component, then Action/Text/Value/Application per the node's role.
    Interface claims are honest: methods of unclaimed interfaces answer
    with a D-Bus error. *)

type action = { name : string; description : string }

val actions_of : Lui_a11y.node_a11y -> action list
(** Named actions a node exposes: role activation ("press"/"toggle")
    first, then expansion state ("expand"/"contract"). *)

val text_of : Lui_a11y.node_a11y -> string option
(** The string an object serves through the Text interface: the value's
    text when present, else the accessible name. *)

val text_range : ?offset:int -> string -> int -> int -> int * int * int
(** [text_range ?offset s kind dir] resolves a Text-granularity query:
    [kind] is the AT-SPI boundary type (0 char, 1 word-start, 2
    word-end, 3 sentence-start, 4 sentence-end, 5 line-start, 6
    line-end); [dir] is 0 = at offset, <0 = before, >0 = after.
    Returns (byte_start, byte_end, char_start): the byte range into [s]
    plus the character offset of [start]. *)

val char_offset_of_byte : string -> int -> int
(** [char_offset_of_byte s byte] counts Unicode code points before byte
    offset [byte].  AT-SPI offsets are character (code-point) offsets —
    matching the atk/glib convention Orca implements — so the bridge
    translates at the boundary. *)

val byte_of_char_offset : string -> int -> int
(** Inverse of [char_offset_of_byte]: byte offset of the [n]th code
    point, clamped to the string end. *)

val char_at : string -> int -> int
(** [char_at s n] is the code point at character offset [n] (-1 out of
    range). *)

val attributes_of : Lui_a11y.node_a11y -> (string * string) list
(** Attribute dict contents for GetAttributes: kind and ext-id are
    exposed as toolkit attributes; empty for most nodes. *)

(** {2 Introspection} *)

val introspection_xml : app_name:string -> string list -> string
(** [introspection_xml ~app_name ifaces] is the org.freedesktop reply
    XML declaring exactly the members this bridge implements for the
    given interfaces.  Only implemented members are declared — an AT
    sees no method the bridge cannot answer. *)

(** {2 The bridge} *)

type t
(** A serving bridge: bound to one [Lui_a11y.t] at [attach], it mirrors
    the a11y forest as registered objects and translates updates into
    AT-SPI events. *)

type transport =
  | Offline       (** No bus connection; events queue in-memory *)
  | Session_bus   (** Serving on the session bus (a11y bus missing) *)
  | A11y_bus      (** Serving on the accessibility bus *)

val create : ?toolkit_name:string -> ?toolkit_version:string -> unit -> t
(** [create ()] is a bridge with no tree attached and no bus.  Pure:
    never touches the transport, so it works on every platform. *)

val attach : t -> Lui_a11y.t -> unit
(** [attach t a11y] binds the forest: every node becomes a served object
    under [path_prefix], the forest roots become children of the
    synthetic application root (AT-SPI role APPLICATION), and a
    Cache:Ready + per-object AddAccessible batch is queued.  Pure —
    call [connect] to start serving. *)

val a11y : t -> Lui_a11y.t option
val update : t -> int list -> unit
(** [update t changed] applies one [Lui_a11y.update] result (the ids
    whose records changed) to the served objects and queues the
    resulting events: ChildrenChanged add/remove on parents,
    AddAccessible/RemoveAccessible on the cache, StateChanged,
    PropertyChange (name/description/value/parent/role) and
    TextChanged/TextCaretMoved where the payloads changed. *)

val sync : t -> unit
(** [sync t] drains the bound store's dirty set through
    [Lui_a11y.sync] then [update]. *)

val set_focus : t -> int -> unit
(** [set_focus t id] moves focus: FOCUSED leaves the old object,
    enters the new one (StateChanged events), and a Focus signal is
    queued on the focused object's path. *)

val clear_focus : t -> unit
val focused : t -> int option

(** {2 Events} *)

(** One queued outbound signal.  [member] is the CamelCase D-Bus member
    (StateChanged, ChildrenChanged, TextChanged, PropertyChange, Focus,
    ...); [any] is the typed variant payload. *)
type event_data =
  | D_unit          (** variant "i" 0 — events with no payload *)
  | D_int of int    (** variant "i" *)
  | D_str of string (** variant "s" — e.g. inserted text *)
  | D_ref of string (** variant "(so)" — object path; bus name is ours *)

type cache_item = {
  path : string;
  parent_path : string option;  (** [None] = null parent reference *)
  index_in_parent : int;
  child_count : int;
  interfaces : string list;
  name : string;
  role : int;
  description : string;
  states : int list;
}

type object_event = {
  path : string;
  iface : string;
  member : string;
  detail : string;
  detail1 : int;
  detail2 : int;
  any : event_data;
}

type event =
  | Object_event of object_event
  | Cache_add of cache_item
  | Cache_remove of string          (** object path *)
  | Cache_ready
  | Focus_event of string           (** focused object's path *)
  | Window_event of string * string (** path, major name *)

val drain_events : t -> event list
(** Drains the queued-outbox (returns and removes pending events). *)

val pending_count : t -> int

(** {2 Incoming calls} *)

(** A decoded incoming method call as the transport delivers it; args
    land in the typed arrays in argument order ([iargs]: ints/uints/
    bools, [fargs]: doubles, [sargs]: strings/object-paths/variant
    scalars decoded by kind). *)
type call = {
  serial : int;
  path : string;
  iface : string;
  member : string;
  iargs : int array;
  fargs : float array;
  sargs : string array;
}

type reply =
  | Value of dvalue list   (** out arguments, in order *)
  | Error of string * string  (** error name, message *)

val handle_call : t -> call -> reply
(** [handle_call t c] resolves the call against the served objects and
    the interface tables — the complete protocol contract, exercised by
    the unit tests without a bus. *)

(** {2 Callbacks} *)

val on_action : t -> (int -> string -> unit) -> unit
(** [on_action t f] registers the host's action invoker: AT-triggered
    DoAction on node id calls [f id action_name]. *)

val on_focus_request : t -> (int -> unit) -> unit
(** Called when an AT asks the bridge to move focus to a node
    (Component:GrabFocus, or the focus action). *)

val on_caret_request : t -> (int -> int -> bool) -> unit
(** Called when an AT asks to move the caret of a text node; returning
    [true] accepts (SetCaretOffset answer). *)

val on_value_request : t -> (int -> float -> bool) -> unit
(** Called when an AT asks to set a numeric value (Value:SetCurrentValue);
    returning [true] accepts and the served record updates on the next
    [update]. *)

(** {2 Transport} *)

val connect : t -> transport
(** [connect t] opens the transport: on Linux it binds libdbus at load
    time, resolves the a11y-bus address via the session bus's
    org.a11y.Bus service and registers the application root with
    Socket:Embed; when the a11y bus is missing it falls back to the
    session bus; when no bus is reachable it reports [Offline] and all
    emission APIs keep queueing.  Requires Linux. *)

val transport : t -> transport
val disconnect : t -> unit
val flush : t -> int
(** [flush t] sends every queued event over the bus; returns how many
    were transmitted.  No-op when [transport t] is [Offline]. *)

val dispatch : t -> int
(** [dispatch t] pumps the bus once: incoming method calls are answered
    through [handle_call].  Returns the number handled.  No-op offline. *)

val set_bus_name : t -> string -> unit
(** The unique connection name (":1.xxx"), set by [connect]; used in
    every (so) object reference the bridge emits. *)

val desktop_ref : t -> obj_ref option
(** The registry/desktop object reference Socket:Embed returned —
    served as the application root's parent. *)

val set_desktop_ref : t -> obj_ref -> unit
val app_id : t -> int
(** The application Id the registry assigned (Properties.Set on
    Application), or 0. *)

val destroy : t -> unit
(** Disconnects the transport and drops the served tree. *)
