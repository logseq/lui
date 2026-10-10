(** Desktop shell services for the native backend on Linux: the status
    (tray) item, menus, user notifications, the clipboard, file dialogs
    and open-url handling.

    The API mirrors [lui_shell] (macOS) wherever the concept ports, so
    the host can pick a shell implementation per platform. The OCaml
    side owns the menu model, image buffers, icon encoding, desktop
    entry bookkeeping and the handler table; the C stubs are a
    transport that binds the platform libraries at load time with
    dlopen — libdbus-1 for the session bus (notifications, the launcher
    entry, URL delivery) and GTK 3 plus the StatusNotifier indicator
    library for the GUI session (clipboard, dialogs, tray menus). No
    development headers and no link-time dependencies are required;
    when a library or the session it talks to is absent the entry
    points degrade to [false]/[None] instead of failing.

    Session tiers: with nothing reachable the transport is [Offline]
    and every call degrades. With a session D-Bus — [Session_bus] —
    notifications, the dock badge and open-url delivery work. With a
    GUI session bound — [Indicator] when the indicator library also
    resolved — status items, tray menus, the clipboard and file dialogs
    work. [gui_available] reports the display half independently of the
    indicator library.

    Event delivery: menu selections, status clicks, notification
    activations and opened URLs are dispatched from [pump] (or from a
    nested dialog run) on the thread that called it — pump on the UI
    thread. Nothing here spawns threads. *)

(** {1 Session} *)

type transport =
  | Offline     (** No session bus, no display: everything degrades *)
  | Session_bus (** Session D-Bus reachable *)
  | Indicator   (** GUI session bound and the StatusNotifier indicator
                    library resolved — the full desktop tier *)

val transport : unit -> transport
(** Best session tier the transport could bind. Probing is lazy: it
    runs on the first call that needs it (or on [pump]) and is cached. *)

val gui_available : unit -> bool
(** Whether GTK bound and opened a display — clipboard, dialogs and
    tray menus are possible regardless of the indicator library. *)

val pump : ?timeout_ms:int -> unit -> int
(** [pump ()] services the session once: it lets pending D-Bus traffic
    and GLib main-context work run, then dispatches every queued event
    (menu selections, status clicks, notification activations, opened
    URLs) to its handler on the calling thread. Returns the number of
    dispatched events. [timeout_ms] bounds the wait for new traffic;
    the default does not block. No-op offline. *)

(** {1 App identity} *)

type activation_policy =
  | Regular     (** a normal app *)
  | Accessory   (** an agent app: no launcher/taskbar presence asked *)
  | Prohibited  (** no UI presence at all *)

val set_activation_policy : activation_policy -> bool
(** Records the policy. Linux has no app-level activation switch: the
    policy is advisory state the host's window layer consults (skip
    taskbar hints and the like). Always reports [true]. *)

val activation_policy : unit -> activation_policy option
(** The recorded policy. *)

val set_app_name : string -> unit
(** The human-readable application name: sent as the notification
    app_name and used as the desktop entry's [Name=]. *)

val app_name : unit -> string

val set_dock_badge : string option -> unit
(** Badge text on the launcher entry ([Some "3"]); [None] clears it.
    Carried by the freedesktop/Unity launcher-entry signal — the docks
    that implement it (KDE Plasma, Dash to Dock, Plank) show a count
    parsed from the text. No-op offline. *)

val request_user_attention : ?critical:bool -> unit -> int
(** Sets the launcher entry's urgent flag, the attention request the
    desktop understands. [critical] is accepted for parity and maps to
    the same flag — the desktop decides how urgency is shown and there
    is no "bounce once" variant. Returns the request id, or [(-1)]
    offline. *)

val set_window_title : string -> bool
(** Stores the title for the window layer to apply; reports [false]:
    the shell owns no window to retitle. *)

(** {1 Images} *)

type image
(** An icon built from raw pixels. Carries the RGBA buffer; it is
    encoded to PNG lazily where the session needs a file (tray icons
    are theme lookups on disk). *)

val image_of_rgba : width:int -> height:int -> bytes -> image option
(** [image_of_rgba ~width ~height px] builds an image from [px], a
    non-premultiplied RGBA buffer of [width * height * 4] bytes.
    [None] on non-positive dimensions or a wrongly sized buffer —
    checked before any platform call, on every OS. *)

val image_size : image -> float * float
(** The image's pixel size. *)

val image_png : image -> bytes
(** The PNG encoding used for theme icons. Pure OCaml, on every OS. *)

(** {1 Menus} *)

type item_spec = {
  label : string;
  id : int;      (** delivered to the menu handler on selection *)
  enabled : bool;
  checked : bool;
}

type menu_item =
  | Item of item_spec
  | Separator
  | Submenu of submenu_spec

and submenu_spec = {
  label : string;
  enabled : bool;
  items : menu_item list;
}

type menu_row_kind = Row_item | Row_separator | Row_submenu

type menu_row = {
  depth : int;              (** nesting level, [0] = top level *)
  kind : menu_row_kind;
  label : string;
  id : int;                 (** item ids; [-1] on separators/submenus *)
  enabled : bool;
  checked : bool;
}
(** One flattened menu entry in depth-first order. *)

type menu = private { title : string; rows : menu_row array }
(** A compiled menu: [rows] is what the platform turns into a native
    menu; [title] labels it in the app menu model. *)

val menu : ?title:string -> menu_item list -> menu
(** [menu items] flattens the tree depth-first; each [Submenu] row is
    followed by its children at [depth + 1]. Pure OCaml, works on
    every platform. *)

val menu_rows : menu -> menu_row array

val set_menu_handler : (int -> unit) option -> unit
(** Registers the single handler that receives selected items' [id]s.
    Dispatch runs inside [pump] (or a dialog's nested loop) on the
    calling thread. *)

val app_menu_insert : menu -> at:int -> bool
(** Inserts [menu] into the app menu model at [at] (clamped into
    range; negative counts back from the end). Linux has no app-owned
    global menu bar: the model is authoritative — the host renders it
    and tray/status surfaces realize it — so this reports whether the
    model accepted the insert, which is [true] unless the rows are
    malformed (never, since [menu] builds them). *)

val app_menu_remove : at:int -> bool
(** Removes the menu at [at]. [false] when out of range. *)

val app_menu_count : unit -> int
(** Number of menus in the model. *)

val app_menus : unit -> menu array
(** The model itself, for the host to render. *)

(** {1 Status item} *)

type status_item = private { handle : Obj.t; tag : int }
(** One status (tray) item; [tag] is what click dispatch reports. *)

val status_item_supported : unit -> bool
(** Whether the StatusNotifier indicator library bound. Without it
    status items are inert: [status_item_create] still succeeds and
    setters no-op. *)

val status_item_create : ?tag:int -> unit -> status_item
(** Creates a status item. Safe in any session: with no indicator
    service the item exists but is inert ([status_item_live] is
    [false]) and every setter no-ops. The item only displays once it
    has a menu — per the StatusNotifier contract, a menu is what makes
    it visible. *)

val status_item_live : status_item -> bool
(** Whether the item is backed by a live indicator object. *)

val status_item_remove : status_item -> unit
(** Removes the item (marks it passive and drops the indicator). *)

val status_item_set_title : status_item -> string -> unit
(** The item's label — most panels show icons; the label rides along
    for those that do and for accessibility. *)

val status_item_set_image : status_item -> image option -> unit
(** Sets the icon ([None] restores the default). Encoded to a PNG in
    the per-app icon dir and installed as a theme icon, which is how
    StatusNotifier items take pixels. *)

val status_item_set_menu : status_item -> menu option -> unit
(** Attaches a menu ([None] detaches). A menu wins over the click
    action: with one attached, the primary click opens the menu. *)

val status_item_set_on_click : status_item -> bool -> unit
(** With [true] and no menu attached, activation dispatches [tag] to
    the status handler. StatusNotifier items only offer the secondary
    (middle-click) activation to the app — the primary click belongs
    to the menu. *)

val set_status_handler : (int -> unit) option -> unit
(** Single handler receiving activated status items' [tag]s, from
    [pump] on the calling thread. *)

(** {1 Notifications} *)

val notify : id:string -> title:string -> ?subtitle:string ->
  body:string -> unit -> bool * string
(** [notify ~id ~title ~body ()] posts a freedesktop notification;
    activating it dispatches [id] to the notification handler.
    [subtitle] folds into the body — the spec has one summary and one
    body.

    Returns [(posted, detail)]: [(false, reason)] offline or when the
    notification service is missing — reported, never raised.
    [detail] names the path taken when posted. *)

val set_notification_handler : (string -> unit) option -> unit
(** Single handler receiving activated notifications' [id]s, from
    [pump] on the calling thread. *)

(** {1 Clipboard} *)

val clipboard_write : string -> bool
(** Writes a plain string to the CLIPBOARD selection; [false] when no
    clipboard exists. *)

val clipboard_read : unit -> string option
(** The current plain string, if any. *)

val clipboard_clear : unit -> int
(** Empties the selection; returns the new change count, [(-1)] when
    no clipboard exists. *)

val clipboard_change_count : unit -> int
(** A counter that increments on every write (ours and external
    owners', seen via the owner-change signal) — poll it to detect
    outside changes. [(-1)] when no clipboard exists. External changes
    are observed inside [pump]. *)

(** {1 Dialogs} *)

val can_present_dialogs : unit -> bool
(** Whether dialogs can run: a display is bound. When [false], the
    dialogs below return [None] immediately instead of blocking. *)

val open_dialog : ?dirs:bool -> ?files:bool -> ?multi:bool ->
  ?filters:string list -> unit -> string list option
(** File/directory picker. [files] defaults to [true], [dirs] and
    [multi] to [false]. [filters] restricts to extensions (["md"]),
    any string when empty. [Some paths] when the user confirms —
    the confirmed selection even if it is empty — [None] on cancel or
    when dialogs cannot run. Uses the native chooser, which the portal
    serves where it exists. *)

val save_dialog : ?default_name:string -> unit -> string option
(** Save-as dialog. [Some path] on confirm, [None] on cancel or when
    dialogs cannot run. *)

(** {1 Open-url} *)

val open_url : string -> bool
(** Opens a URL in its associated handler. Reports whether a launch
    was attempted ([false] offline or with nothing to launch through). *)

val install_open_url_handler : scheme:string -> ?id:string ->
  ?name:string -> unit -> bool
(** Claims [scheme] links for this app: writes the hidden
    [.url-handler.desktop] entry under [XDG_DATA_HOME]/applications
    (accumulating schemes across calls), makes it the default
    [x-scheme-handler/<scheme>] application in mimeapps.list, and —
    with a session bus — registers the matching bus name and
    org.freedesktop.Application object so a running instance receives
    [Open] calls; without one, desktops fall back to the entry's Exec.

    [id] defaults to the executable name; it names the desktop file
    and the bus name. [name] defaults to [app_name]. Reports whether
    the registration could be attempted (file + mime always written;
    bus delivery needs [Session_bus]). *)

val set_open_url_handler : (string -> unit) option -> unit
(** Single handler receiving opened URL strings, from [pump] on the
    calling thread. *)

(** {1 Internals exposed for tests}

    The pure halves — icon encoding, XDG/desktop-entry plumbing, event
    translation — so the suite can exercise them without a session.
    Unstable; hosts should not use them. *)
module Private : sig
  val png_of_rgba : width:int -> height:int -> bytes -> bytes
  val desktop_name : string -> string
  val entry_string : string -> string
  val exec_arg : string -> string
  val handler_desktop_entry : name:string -> exe:string ->
    string list -> string
  val handler_schemes : string -> string list
  val handler_entry : string -> string * string
  val mimeapps_list : unit -> string
  val mime_default : string -> string option
  val set_mime_default : string -> string -> string -> unit
  val bus_name_of_desktop_id : string -> string
  val object_path_of_bus_name : string -> string
  val fnv1a32 : string -> int
  val launcher_path : string -> string
  val session_bus_address : unit -> string
  val desktop_entry_id : unit -> string
  val dispatch_event : int * int * string -> unit
  val window_title : unit -> string
end
