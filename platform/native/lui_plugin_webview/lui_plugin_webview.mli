(** Native web views behind the ["plugin:webview"] service.

    Methods (JSON object payloads):

    - ["create"]: [{ "host_sdl"?: string, "host"?: string,
      "x","y","w","h": number, "url" | "html" | "file": string,
      "base_url"?: string, "user_agent"?: string, "zoom"?: number,
      "transparent"?: bool }] returns [{ "id": int }]. [host_sdl] is an
      [SDL_Window*] pointer string, [host] a raw platform window
      handle; with neither, the main window is used.
    - ["navigate"]: [{ "id": int, "url" | "html" | "file": string } |
      { "id": int, "op": "back"|"forward"|"reload"|"stop" }] returns [{}].
    - ["eval"]: [{ "id": int, "js": string }] runs the script, returns [{}].
    - ["call"]: [{ "id": int, "js": string }] runs [js] as an async
      function body and returns [{ "result": string }] once the engine
      answers (bounded wait).
    - ["layout"]: [{ "id": int, "x","y","w","h": number }] — the
      per-frame placement contract — returns [{}].
    - ["state"]: [{ "id": int }] returns
      [{ "url": string, "is_loading": bool, "can_go_back": bool,
         "can_go_forward": bool, "frame": [x,y,w,h],
         "backend": string }].
    - ["capture"]: [{ "id": int }] returns
      [{ "png_base64": string }].
    - ["destroy"]: [{ "id": int }] returns [{}] and releases the view.

    All calls run on the host UI thread, like {!Lui_webview}. *)

val plugin : Lui_plugin.t
(** The ["plugin:webview"] service descriptor. *)

module Private : sig
  val views : (int, Lui_webview.t) Hashtbl.t
  val b64_encode : string -> string
  val teardown : unit -> unit
end
