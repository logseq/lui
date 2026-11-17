(** WebSocket client plugin (RFC 6455), pure OCaml over Unix TCP
    sockets. [ws://] only — there is no TLS transport yet, so [wss://]
    URLs are rejected.

    The OCaml API manages live connections directly; the {!plugin}
    descriptor exposes it as the ["plugin:websocket"] service:

    - ["open"]    [{ "url": string, "headers"?: object | pairs,
                     "timeout_ms"?: int }] -> [{ "conn_id": int }]
    - ["send"]    [{ "conn_id": int, "opcode": "text"|"binary"|"ping"|
                     "pong"|"close"|int, "payload_b64": string }] -> [{}]
    - ["poll"]    [{ "conn_id": int }] ->
      [{ "events": [ { "kind": "message", "opcode": "text"|"binary",
                       "data": base64 },
                     { "kind": "close", "code": int, "reason": string },
                     { "kind": "error", "data": string } ] }]
    - ["close"]   [{ "conn_id": int, "code"?: int, "reason"?: string }]
      -> [{}]

    [poll] is non-blocking: it drains whatever complete frames the
    kernel already holds and queues them as events. Ping frames are
    answered with pong automatically; pong frames are consumed
    silently. When the peer closes (or the socket dies) a single
    ["close"] event is queued and the socket is released. *)

type conn

type event =
  | Message of int * string  (** opcode (1 = text, 2 = binary), payload *)
  | Close of int * string    (** status code, reason *)
  | Ev_error of string

val connect :
  url:string -> ?headers:(string * string) list -> ?timeout_ms:int ->
  unit -> (conn, string) result

val send : conn -> opcode:int -> string -> (unit, string) result
(** [send conn ~opcode payload] frames [payload] with masking
    (client-to-server must mask). Opcodes: 1 text, 2 binary, 9 ping,
    10 pong, 8 close. *)

val poll : conn -> event list
(** Non-blocking event drain; see the service contract above. *)

val close : conn -> ?code:int -> ?reason:string -> unit -> unit
(** Send a close frame, drain the peer's close reply briefly, and
    release the socket. Idempotent. *)

val plugin : Lui_plugin.t
(** The ["plugin:websocket"] service descriptor. *)

module Private : sig
  (** Raw 20-byte digest. *)
  val sha1 : string -> string
  val b64_encode : string -> string
  val accept_key : string -> string
  val encode_frame : mask:bool -> opcode:int -> string -> string
end
