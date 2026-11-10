(** lui-agent on Web: exposes {!Lui_agent.handle} to scripts driving the
    page. See tooling/lui_agent.mjs. *)

(** One reply for one request. A handler exception is answered with
    [{"ok":false,"refused":true,"diagnostic":{"phase":"agent",...}}]. *)
val answer : Lui_agent.target -> string -> string

(** The [lui-agent] parameter of a [location.search] string when it names a
    loopback WebSocket ([ws://127.0.0.1:PORT] or [ws://localhost:PORT]). *)
val dial_url : string -> string option

(** Sets [window.__luiAgent] and dials {!dial_url} of the page, answering
    each text frame with one reply frame. *)
val install : Lui_agent.target -> unit
