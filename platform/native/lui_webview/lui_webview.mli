(** Native web views embedded as OS subviews over rects of the host
    window.

    A [t] is a real platform web view — WKWebView on macOS, WebKitGTK
    on Linux, WebView2 on Windows — placed over the host window at a
    rect the host's layout engine recomputes every frame
    ({!layout_webview}). The web view is an OS-level overlay: it does
    not rasterize into the host's scene, it simply covers the rect.

    The interface is identical on every platform. Where a platform
    backend cannot provide a feature it degrades, never crashes:
    constructors raise [Failure] naming the missing backend, getters
    return neutral defaults, and {!capture_page} returns [None].

    All calls must run on the host's UI thread (the thread that created
    the window). Events are queued by the platform engine and delivered
    by {!drain}, which the host calls each frame; {!pump} lets
    run-loop-driven engines (WebKitGTK, WebView2) make progress when the
    host owns the main loop.

    {b Placing the view.} [rect] uses logical points with a top-left
    origin — the same space as the host's layout output. The backends
    handle each platform's coordinate flip internally. *)

(** {1 Types} *)

type rect = {
  x : float;
  y : float;
  w : float;
  h : float;
}
(** Top-left origin, logical points. *)

val rect : float -> float -> float -> float -> rect

type host_window = private nativeint
(** A platform window handle: NSWindow* on macOS, an X11 window id on
    Linux, an HWND on Windows. Obtain one from an SDL window with
    {!host_of_sdl_window}. *)

val host_of_sdl_window : nativeint -> host_window
(** [host_of_sdl_window p] takes the raw [SDL_Window*] of an SDL2 host
    window (tsdl: [Sdl.unsafe_ptr_of_window]) and resolves the platform
    window handle via [SDL_GetWindowWMInfo]. Raises [Failure] when SDL
    cannot report a native handle or the window manager is unsupported
    (e.g. Wayland on Linux). *)

val host_main_window : unit -> host_window
(** The app's main window, for single-window hosts that do not keep the
    SDL pointer. Raises [Failure] when no window exists or the platform
    cannot enumerate one. *)

val host_of_native : nativeint -> host_window
(** [host_of_native p] wraps a raw platform window handle ([NSWindow *]
    on macOS, [HWND] on Windows, an X11 window id on Linux) as a host
    token, for callers that already hold one. The handle is validated
    at {!create} time. *)

type source =
  | Url of string
  | Html of string * string  (** (html, base_url); base_url may be "" *)
  | File of string           (** absolute path; read access is the parent dir *)
  | Empty
(** What a web view loads at creation. *)

type opts = {
  source : source;
  user_agent : string;  (** [""] keeps the engine default. *)
  zoom : float;
  transparent : bool;   (** Under-construction page shows through. *)
}
(** Creation options; build with {!opts}. *)

val opts :
  ?user_agent:string -> ?zoom:float -> ?transparent:bool -> source -> opts

type t
(** A web view handle. Not thread-safe: all calls run on the UI thread. *)

(** {2 Events}

    Platform engines report asynchronously. Each [t] owns a queue that
    {!drain} empties every frame; [set_on_event] dispatches the same
    events to a handler. *)

type event =
  | Did_navigate of string  (** provisional navigation started (url) *)
  | Did_commit of string    (** navigation committed (url) *)
  | Did_finish of string    (** navigation finished (url) *)
  | Load_error of string * string  (** (url, engine error text) *)
  | Script_message of string (** [window.webkit.messageHandlers.lui_wv]
                                 payload, JSON-encoded *)

(** {1 Construction} *)

val create : host_window -> rect -> opts -> t
(** [create host frame o] attaches a web view covering [frame] inside
    [host]. [opts.source] starts loading immediately. Raises [Failure]
    when the platform backend is unavailable. *)

val backend_name : unit -> string
(** ["wkwebview"], ["webkit2gtk"], ["webview2"], or ["none"]. *)

val destroy : t -> unit
(** Detaches and releases the view. Idempotent; the handle must not be
    used afterwards (a handle dropped without [destroy] is finalized,
    but engines release faster when asked). *)

(** {1 Navigation} *)

val load_url : t -> string -> unit
val load_html : t -> ?base_url:string -> string -> unit
val load_file : t -> string -> unit
val reload : t -> unit
val stop : t -> unit
val go_back : t -> unit
val go_forward : t -> unit
val can_go_back : t -> bool
val can_go_forward : t -> bool
val url : t -> string
(** Currently committed URL, or the last one requested. [""] when none. *)

val is_loading : t -> bool

(** {1 Scripts} *)

val eval : t -> string -> unit
(** [eval t js] runs [js] and discards the result. *)

val call_async : t -> string -> (string -> unit) -> unit
(** [call_async t body cb] runs [body] as an async function body
    ([return] gives the result) and later delivers the JSON-encoded
    result string to [cb]. [cb] runs inside {!drain}. *)

(** {1 View state} *)

val set_zoom : t -> float -> unit
val zoom : t -> float
val set_user_agent : t -> string -> unit
val user_agent : t -> string
val set_visible : t -> bool -> unit

val layout_webview : t -> rect -> unit
(** The placement contract: the host calls this every frame with the
    rect layout assigned to the view. Cheap when unchanged. *)

val set_frame : t -> rect -> unit
(** Alias of {!layout_webview}. *)

val frame : t -> rect
(** The native view's current frame in top-left logical points —
    readback for tests and debugging. *)

val capture_page : t -> bytes option
(** [capture_page t] snapshots the visible page as PNG bytes. Pumps the
    platform event loop internally until the engine answers (bounded);
    [None] when the platform cannot capture or the snapshot failed. *)

(** {1 Event pump} *)

val set_on_event : t -> (event -> unit) -> unit
val drain : t -> event list
(** [drain t] delivers every queued event to the [set_on_event] handler
    and to {!call_async} waiters, and returns them. Call once per frame. *)

val pump : unit -> unit
(** [pump ()] runs pending work of the platform event loop without
    blocking (CFRunLoop turn on macOS, GTK main-context iteration on
    Linux, a Win32 message pump step on Windows). Hosts driving their
    own frame loop call this so navigation and script callbacks make
    progress; a no-op where the engine has its own loop. *)
