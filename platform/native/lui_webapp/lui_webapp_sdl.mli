(** The real webview backend for {!Lui_webapp.boot}: an SDL window
    whose whole content area is a single {!Lui_webview} web view.

    This is the default backend whenever {!Lui_webview} reports a
    usable engine — no provider module needs registering. The
    {!Lui_webapp.WEBVIEW} seam remains for tests and custom hosts. *)

type window = {
  width : int;
  height : int;
  resizable : bool;
  min_width : int;
  min_height : int;
}
(** Initial window geometry — mirrors {!Lui_webapp.window} so this
    module stays a low-level shell the spec layer calls into. *)

val available : unit -> bool
(** Whether the platform webview backend can actually create a view —
    [Lui_webview.backend_name () <> "none"]. Does not initialize SDL. *)

val run :
  window:window ->
  title:string ->
  entry_file:string ->
  on_message:(string -> unit) ->
  on_ready:(eval:(string -> unit) -> unit) ->
  (unit, string) result
(** [run ~window ~title ~entry_file ~on_message ~on_ready] opens a
    native window sized by [window], attaches a web view covering the
    whole client area, and loads [entry_file] via
    [loadFileURL:allowingReadAccessToURL:] (the view can read the
    entry's directory, so sibling assets resolve). Blocks until the
    window closes, then tears everything down and returns [Ok ()].

    The JS → native bridge is the same channel the webview exposes:
    page code posts through
    [window.webkit.messageHandlers.lui_wv.postMessage(payload)] and the
    JSON-encoded payload reaches [on_message]. [on_ready] fires once,
    after the first committed load finishes, with [eval] running JS in
    the page (result discarded — the native → JS direction).

    Returns [Error] when the window or view cannot be created (no
    display, no backend) or the entry's initial load fails. A caller
    honoring the browser fallback should use that; with
    [~fallback_browser:false] {!Lui_webapp.boot} raises it as a
    [Failure]. *)
