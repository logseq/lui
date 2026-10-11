(** Lui_webapp — webview-shell host for web-asset apps.

    A webapp is a directory of web assets ({!spec.web_dir}) with an
    HTML {!spec.entry} page, described by a declarative {!spec} that
    ships as a JSON document ([webapp.json]) next to the launcher
    executable — the same shape an Electron app's [package.json] +
    [index.html] pair takes, without a bundled browser engine.

    {!boot} opens a native window whose whole content is a webview
    showing [web_dir/entry] over a [file://] URL, wires the JS ↔ native
    bridge surface (an eval channel plus a message hook — the channel
    the webview backend exposes) and the window lifecycle, then blocks
    until the window closes.

    {b The webview is pluggable.} {!set_webview} installs a provider
    implementing {!WEBVIEW} — the contract the native webview backend
    (WKWebView on macOS, WebView2 on Windows, WebKitGTK on Linux)
    fulfills. When no provider is installed {!boot} degrades: it opens
    the entry's [file://] URL in the system default browser and reports
    the degradation on stderr. When even that fallback cannot run —
    no webview and no browser opener — [boot] raises [Failure] with a
    clear message. *)

(** {1 Specification} *)

type window = {
  width : int;
  height : int;
  resizable : bool;
  min_width : int;
  min_height : int;
}
(** Initial window geometry; [min_*] bounds apply when [resizable]. *)

type permissions = {
  file_access : bool;
    (** the page may load [file://] subresources and read local files *)
  remote_content : bool;
    (** the page may navigate to http(s) origins *)
  dev_tools : bool;
    (** an inspector/devtools surface is available to the page *)
}

type spec = {
  app_id : string;     (** bundle id, e.g. ["com.example.app"] *)
  name : string;       (** display name; window title and bundle name *)
  version : string;    (** semver *)
  web_dir : string;    (** asset root; relative paths resolve against
                           the spec file's directory (packaged layout:
                           ["web"]) *)
  entry : string;      (** page inside [web_dir], e.g. ["index.html"] *)
  window : window;
  icon : string option;  (** source PNG (square), consumed by the
                             packager; resolved like [web_dir] *)
  permissions : permissions;
}

val default_window : window
val default_permissions : permissions

(** {1 JSON format}

    A spec file ([webapp.json]) reads:

    {[
      {
        "app_id": "com.example.app",
        "name": "Example",
        "version": "1.0.0",
        "web_dir": "web",
        "entry": "index.html",
        "window": { "width": 1024, "height": 768,
                    "resizable": true,
                    "min_width": 320, "min_height": 240 },
        "icon": "icon.png",                        // optional
        "permissions": { "file_access": true,
                         "remote_content": false,
                         "dev_tools": false }       // optional
      }
    ]}

    [app_id], [name], [version], [web_dir] and [entry] are required;
    [window], [icon] and [permissions] default when absent. Extra keys
    are ignored so newer fields stay forward-compatible. *)

val spec_to_json : spec -> Yojson.Safe.t
val spec_of_json : Yojson.Safe.t -> (spec, string) result
val spec_to_string : spec -> string
val spec_of_string : string -> (spec, string) result

val read_spec : string -> (spec, string) result
(** [read_spec path] loads and parses a spec file; the result keeps
    [web_dir]/[icon] relative — resolve them with {!resolve} against
    [Filename.dirname path]. *)

val write_spec : spec -> string -> (unit, string) result
(** [write_spec spec path] serializes [spec] to [path]. *)

val validate : spec -> (unit, string) result
(** Required-field and shape checks: non-empty ids, a relative [entry]
    that cannot escape [web_dir], positive dimensions. *)

val resolve : base:string -> spec -> spec
(** Absolutizes [web_dir] and [icon] against [base] (already-absolute
    paths pass through). *)

val entry_path : spec -> string
(** [web_dir/entry]; the spec should be {!resolve}d first. *)

val file_url : string -> string
(** [file_url path] builds the [file://] URL for an absolute path —
    forward slashes, percent-escaped bytes outside the URL-safe set. *)

(** {1 The webview provider contract}

    The surface a native webview backend implements. A window [t]
    shows one page; [run] drives the platform event loop until the
    window closes. All functions may report errors through their
    [result]s instead of raising. *)

module type WEBVIEW = sig
  type t

  val create :
    window:window -> title:string -> permissions:permissions ->
    (t, string) result
  val load_url : t -> string -> (unit, string) result

  val eval : t -> string -> unit
  (** JS → page: evaluates a snippet in the page context. *)

  val set_message_handler : t -> (string -> unit) -> unit
  (** page → JS: page messages (e.g. a posted JSON string) arrive on
      the handler, on the main thread. *)

  val set_close_handler : t -> (unit -> unit) -> unit

  val run : t -> unit
  (** Blocks until the window is closed (or {!close} is called). *)

  val close : t -> unit
end

val set_webview : (module WEBVIEW) option -> unit
(** Installs (or clears) the process-wide webview provider. *)

val webview : unit -> (module WEBVIEW) option

(** {1 Boot} *)

type prepared = {
  prep_spec : spec;      (** the resolved spec actually used *)
  entry_file : string;   (** absolute path of web_dir/entry *)
  url : string;          (** its [file://] URL *)
}

val prepare : ?base:string -> spec -> (prepared, string) result
(** Validates the spec, resolves relative paths against [base]
    (default: cwd), and checks the entry file exists. *)

val open_in_browser : string -> (unit, string) result
(** Opens a URL in the system default browser: [open] on macOS,
    [xdg-open] on Linux, [start] via cmd on Windows. [Error] names the
    missing tool or the failed spawn. *)

val boot :
  ?base:string ->
  ?webview:(module WEBVIEW) ->
  ?fallback_browser:bool ->
  ?on_message:(string -> unit) ->
  ?on_ready:(eval:(string -> unit) -> unit) ->
  spec -> unit
(** [boot spec] prepares the app ({!prepare}), then:

    - with a webview provider ([?webview] or {!set_webview}): creates
      the window from [spec.window] titled [spec.name], loads the
      entry URL, registers [?on_message] as the JS → native message
      hook, hands the eval channel to [?on_ready], and runs the event
      loop until the window closes;
    - without one and [fallback_browser] (default [true]): opens the
      entry URL in the default browser and reports the degradation on
      stderr;
    - without one and [~fallback_browser:false], or when the browser
      cannot be opened: raises [Failure] with the reason. *)

(** {1 Packaged-spec discovery}

    The launcher finds its spec beside the executable in every
    platform layout:

    - [<exe>/webapp.json] — flat dirs and the Windows portable layout;
    - [<exe>/../Resources/webapp.json] — a macOS [.app]'s
      [Contents/MacOS] → [Contents/Resources];
    - [<exe>/../share/<app>/webapp.json] — a Linux AppDir's
      [usr/bin] → [usr/share/<app>]. *)

val spec_file_name : string
(** ["webapp.json"]. *)

val embedded_spec_candidates : exe:string -> string list
(** Candidate spec paths in probe order (first two always; Linux
    share-dir matches appended when such a directory exists). *)

val find_embedded_spec : exe:string -> string option
(** First existing candidate, or [None]. *)
