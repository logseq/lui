(** Desktop shell services for the native backend on Windows: the
    notification-area (tray) icon, popup menus, balloon/toast
    notifications, the clipboard, file dialogs and open-url handling.

    The real implementation targets Windows (user32, shell32, ole32,
    advapi32). The library still builds on every platform: the pure
    model functions ([menu], [menu_rows], the spec types), the event
    handler registrations and the open-url dispatch all work
    everywhere, and every platform call raises
    [Failure "lui_shell_windows: this backend requires Windows"] off
    Windows.

    Lifetime notes: tray icons and the clipboard need a window station
    but no application run loop, so they work in headless processes
    whenever a desktop session exists and report failure when there is
    none. Events — tray clicks, menu selections, notification clicks —
    are delivered to a hidden message window the library owns on the
    thread that first touches the shell (create it on the OCaml
    thread): they reach OCaml only while that thread pumps messages.
    Any Win32 pump works; [pump_pending] is a minimal one for tests
    and pump-less hosts. Callbacks fire reentrantly on the pumping
    thread, inside the C call that dispatched them.

    [open_dialog] and [save_dialog] are modal and return [None]
    instead of blocking when no interactive desktop can present them
    ([can_present_dialogs]). App-identity calls from the macOS shell
    (activation policy, dock badge, attention bounce, app menu bar)
    have no Windows equivalent and are not part of this interface. *)

(** {1 Images} *)

type image
(** A platform image built from raw pixels (an icon, [HICON], on
    Windows). *)

val image_of_rgba : width:int -> height:int -> bytes -> image option
(** [image_of_rgba ~width ~height px] builds an image from [px], a
    non-premultiplied RGBA buffer of [width * height * 4] bytes.
    [None] on non-positive dimensions or a wrongly sized buffer —
    checked before any platform call, on every OS. *)

val image_size : image -> float * float
(** The image's size in pixels (icons are bitmaps; scale is 1). *)

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
    menu ([HMENU]); [title] is carried for hosts that label menus —
    Windows popups never show it. *)

val menu : ?title:string -> menu_item list -> menu
(** [menu items] flattens the tree depth-first; each [Submenu] row is
    followed by its children at [depth + 1]. Pure OCaml, works on
    every platform. *)

val menu_rows : menu -> menu_row array

val set_menu_handler : (int -> unit) option -> unit
(** Registers the single handler that receives selected items' [id]s.
    Selection is always dispatched on the thread that owns the shell
    window, while it pumps messages. *)

val popup_menu : menu -> int
(** [popup_menu m] shows [m] at the cursor as a synchronous modal
    popup and returns the selected item's [id] — also dispatched to
    the menu handler — or [(-1)] when the menu is dismissed. [(-1)]
    too when no desktop session can show it. *)

(** {1 Status item} *)

type status_item = private { handle : Obj.t; tag : int }
(** One notification-area (tray) icon; [tag] is what click dispatch
    reports. *)

val status_item_create : ?tag:int -> unit -> status_item
(** Creates a tray icon. Safe headless: when the shell cannot take it
    yet the item still exists and later [set_*] calls keep retrying —
    it displays as soon as a desktop session accepts it. *)

val status_item_remove : status_item -> unit
(** Removes the icon from the notification area. *)

val status_item_set_title : status_item -> string -> unit
(** Sets the tooltip text. Windows tray icons cannot show a title
    next to the icon the way a status bar does, so the string becomes
    the hover tooltip. *)

val status_item_set_image : status_item -> image option -> unit
(** Sets the icon ([None] clears it). *)

val status_item_set_menu : status_item -> menu option -> unit
(** Attaches a popup menu ([None] detaches). A right click on the
    icon opens it; a left click dispatches the click action instead —
    the menu wins on the button that opens it. *)

val status_item_set_on_click : status_item -> bool -> unit
(** With [true], left clicks on the icon dispatch [tag] to the status
    handler. *)

val set_status_handler : (int -> unit) option -> unit
(** Single handler receiving clicked status items' [tag]s, always on
    the shell window's thread. *)

(** {1 Notifications} *)

val notify : id:string -> title:string -> ?subtitle:string ->
  body:string -> unit -> bool * string
(** [notify ~id ~title ~body ()] posts a balloon notification —
    shown as a toast on Windows 10 and later; clicking it dispatches
    [id] to the notification handler. The balloon needs a tray icon:
    the first status item not already carrying a notification is
    used, or a temporary icon is created for the balloon and removed
    when it closes.

    Returns [(posted, detail)]: [(false, reason)] when no tray icon
    can be shown (no shell session) — reported, never raised.
    [detail] names the path taken when posted. *)

val set_notification_handler : (string -> unit) option -> unit
(** Single handler receiving activated notifications' [id]s. *)

(** {1 Clipboard} *)

val clipboard_write : string -> bool
(** Writes a plain string ([CF_UNICODETEXT]); [false] when the
    clipboard cannot be opened. *)

val clipboard_read : unit -> string option
(** The current plain string, if any. *)

val clipboard_clear : unit -> int
(** Empties the clipboard; returns the new change count, [(-1)] on
    failure. *)

val clipboard_change_count : unit -> int
(** The clipboard sequence number: it increments on every write, so
    polling it detects outside changes. [(-1)] on failure. *)

val clipboard_write_format : string -> bytes -> bool
(** [clipboard_write_format name data] puts [data] on the clipboard
    under the registered format [name] (a format name such as
    ["PNG"] or ["HTML Format"], or a private one — registered on
    demand). [false] on an empty/[NUL]-carrying name or when the
    clipboard cannot be opened. *)

val clipboard_read_format : string -> bytes option
(** The raw bytes of the format [name], if the clipboard carries
    it. *)

(** {1 Dialogs} *)

val can_present_dialogs : unit -> bool
(** Whether modal dialogs can actually run: an interactive input
    desktop exists on this session. When [false], the dialogs below
    return [None] immediately instead of blocking. *)

val open_dialog : ?dirs:bool -> ?files:bool -> ?multi:bool ->
  ?filters:string list -> unit -> string list option
(** File/directory picker ([IFileOpenDialog]). [files] defaults to
    [true], [dirs] and [multi] to [false] — [dirs:true] makes it a
    folder picker. [filters] restricts to extensions (["md"]), any
    file when empty. [Some paths] when the user confirms, [None] on
    cancel or when dialogs cannot run. *)

val save_dialog : ?default_name:string -> unit -> string option
(** Save-as panel ([IFileSaveDialog]). [Some path] on confirm,
    [None] on cancel or when dialogs cannot run. *)

(** {1 Open-url} *)

val open_url : string -> bool
(** [open_url url] hands [url] to the shell ([ShellExecuteW
    "open"]): the browser for web links, the owning app for other
    schemes. [false] when nothing handles it. *)

val register_url_scheme : scheme:string -> ?name:string -> unit ->
  bool
(** Registers [scheme] for the current user under
    [HKCU\Software\Classes\<scheme>], whose [shell\open\command]
    runs this executable with the URL as its argument. [name] is the
    protocol's display name (["<scheme> URL"] when empty). [false]
    for an invalid scheme ([a-zA-Z0-9+.-], starting with a letter)
    or a registry error. Only [scheme]s registered here are
    delivered by [dispatch_open_url]. *)

val unregister_url_scheme : scheme:string -> unit -> bool
(** Removes [scheme]'s registration. [true] when the key is gone or
    never existed. *)

val install_open_url_handler : unit -> bool
(** Scans the process command line for arguments whose scheme was
    registered by [register_url_scheme] and dispatches each to the
    open-url handler. On Windows a scheme launch starts a new
    process with the URL as an argument — this scan is what
    "installing the handler" means; there is no in-process event
    stream like on macOS. Single-instance apps must forward the
    argument to the running instance themselves, then call
    [dispatch_open_url] there. Pure OCaml, works on every platform.
*)

val dispatch_open_url : string -> bool
(** Delivers [url] to the open-url handler when its scheme is
    registered; [true] when dispatched. This is the entry point for
    URLs reaching the process by any other channel (e.g. a
    single-instance forwarder). Pure OCaml, works on every
    platform. *)

val set_open_url_handler : (string -> unit) option -> unit
(** Single handler receiving opened URL strings. *)

(** {1 Message pump} *)

val pump_pending : unit -> int
(** Dispatches every queued message of the library's hidden window
    and returns the count. Tray and menu events reach OCaml only
    through a message pump on the shell window's thread; an app with
    its own Win32 pump never needs this. *)
