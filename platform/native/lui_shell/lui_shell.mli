(** Desktop shell services for the native backend: app identity, the
    status-bar (tray) item, native menus, user notifications, the
    clipboard, file dialogs and open-url handling.

    The real implementation targets macOS (AppKit). The library still
    builds on every platform: the pure model functions ([menu],
    [menu_rows], the spec types) work everywhere, and every platform
    call raises [Failure "lui_shell: this backend requires macOS"] off
    macOS.

    Lifetime notes: most calls act on objects AppKit creates lazily and
    are safe without a running app (headless). Anything that must show
    UI to the user degrades instead of blocking: [open_dialog] and
    [save_dialog] return [None] when no run loop can present them,
    [notify] reports [(false, reason)] outside an [.app] bundle. *)

(** {1 App identity} *)

type activation_policy =
  | Regular     (** dock icon and menu bar; a normal app *)
  | Accessory   (** no dock icon; menu bar only while active (agent app) *)
  | Prohibited  (** no UI presence at all *)

val set_activation_policy : activation_policy -> bool
(** Whether AppKit accepted the policy. Safe headless. *)

val activation_policy : unit -> activation_policy option
(** The current policy, or [None] when no application object exists. *)

val set_app_name : string -> unit
(** Retitles the application menu (the bold first menu). The dock label
    itself always follows the bundle's name. Creates a minimal menu bar
    when none exists yet. *)

val set_dock_badge : string option -> unit
(** Badge text on the dock tile ([Some "3"]); [None] clears it. *)

val request_user_attention : ?critical:bool -> unit -> int
(** Bounces the dock icon. [critical] keeps bouncing until the app
    activates; the default bounces once. Returns the request id, or
    [(-1)] when the platform could not take the request. *)

val set_window_title : string -> bool
(** Sets the title of the app's main (or first) window. [false] when
    the app has no windows yet. *)

(** {1 Images} *)

type image
(** A platform image built from raw pixels (NSImage on macOS). *)

val image_of_rgba : width:int -> height:int -> bytes -> image option
(** [image_of_rgba ~width ~height px] builds an image from [px], a
    non-premultiplied RGBA buffer of [width * height * 4] bytes.
    [None] on non-positive dimensions or a wrongly sized buffer —
    checked before any platform call, on every OS. *)

val image_size : image -> float * float
(** The image's point size (matches [width]/[height] at scale 1). *)

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
    menu; [title] labels it when inserted into the menu bar. *)

val menu : ?title:string -> menu_item list -> menu
(** [menu items] flattens the tree depth-first; each [Submenu] row is
    followed by its children at [depth + 1]. Pure OCaml, works on
    every platform. *)

val menu_rows : menu -> menu_row array

val set_menu_handler : (int -> unit) option -> unit
(** Registers the single handler that receives selected items' [id]s.
    Menu selection is always dispatched on the main thread. *)

val app_menu_insert : menu -> at:int -> bool
(** Inserts [menu] as a top-level menu in the app's menu bar at [at]
    (clamped into range; negative counts back from the end). Creates
    the menu bar when missing. [false] without an application object. *)

val app_menu_remove : at:int -> bool
(** Removes the top-level menu at [at]. *)

val app_menu_count : unit -> int
(** Number of top-level menus ([0] when there is no menu bar). *)

(** {1 Status item} *)

type status_item = private { handle : Obj.t; tag : int }
(** One status-bar (tray) item; [tag] is what click dispatch reports. *)

val status_item_create : ?tag:int -> unit -> status_item
(** Creates a variable-length status item. Safe headless: the item is
    real but only displays with a window-server session. *)

val status_item_remove : status_item -> unit
(** Removes the item from the status bar. *)

val status_item_set_title : status_item -> string -> unit

val status_item_set_image : status_item -> image option -> unit
(** Sets a template-friendly icon ([None] clears it). *)

val status_item_set_menu : status_item -> menu option -> unit
(** Attaches a menu ([None] detaches). A menu wins over the click
    action: with one attached, clicks open the menu. *)

val status_item_set_on_click : status_item -> bool -> unit
(** With [true] and no menu attached, clicks dispatch [tag] to the
    status handler. *)

val set_status_handler : (int -> unit) option -> unit
(** Single handler receiving clicked status items' [tag]s, always on
    the main thread. *)

(** {1 Notifications} *)

val notify : id:string -> title:string -> ?subtitle:string ->
  body:string -> unit -> bool * string
(** [notify ~id ~title ~body ()] posts a notification; activating it
    dispatches [id] to the notification handler. Uses the modern
    notification API when the OS has it, the legacy one otherwise.

    Returns [(posted, detail)]: [(false, reason)] when the app is not
    bundled (delivery needs a bundle id) — reported, never raised.
    [detail] names the path taken when posted. *)

val set_notification_handler : (string -> unit) option -> unit
(** Single handler receiving activated notifications' [id]s. *)

(** {1 Clipboard} *)

val clipboard_write : string -> bool
(** Writes a plain string; [false] when no pasteboard exists. *)

val clipboard_read : unit -> string option
(** The current plain string, if any. *)

val clipboard_clear : unit -> int
(** Empties the pasteboard; returns the new change count. *)

val clipboard_change_count : unit -> int
(** The pasteboard's change counter: it increments on every write, so
    polling it detects outside changes. [(-1)] when no pasteboard. *)

(** {1 Dialogs} *)

val can_present_dialogs : unit -> bool
(** Whether modal panels can actually run: the call is on the main
    thread and the application is running. When [false], the dialogs
    below return [None] immediately instead of blocking. *)

val open_dialog : ?dirs:bool -> ?files:bool -> ?multi:bool ->
  ?filters:string list -> unit -> string list option
(** File/directory picker. [files] defaults to [true], [dirs] and
    [multi] to [false]. [filters] restricts to extensions (["md"]),
    any string when empty. [Some paths] when the user confirms —
    the confirmed selection even if it is empty — [None] on cancel or
    when panels cannot run. *)

val save_dialog : ?default_name:string -> unit -> string option
(** Save-as panel. [Some path] on confirm, [None] on cancel or when
    panels cannot run. *)

(** {1 Open-url} *)

val install_open_url_handler : unit -> bool
(** Registers a get-url Apple-event handler that forwards the URL to
    the open-url handler. Once installed, scheme links delivered to
    the process reach [set_open_url_handler]'s callback. *)

val set_open_url_handler : (string -> unit) option -> unit
(** Single handler receiving opened URL strings, always on the main
    thread. *)
