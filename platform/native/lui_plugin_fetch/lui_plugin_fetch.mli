(** HTTP client plugin backed by the platform libcurl (resolved via
    dlopen — no CORS, arbitrary request headers, buffered bodies).

    The OCaml API performs requests directly; the {!plugin} descriptor
    exposes the same call as a ["plugin:fetch"] service method for the
    {!Lui_plugin} registry:

    - ["request"]: argument object
      [{ "url": string, "method"?: string, "headers"?: object | pairs,
         "body"?: string, "body_base64"?: string,
         "redirect"?: bool | int, "timeout_ms"?: int }]
      returns
      [{ "status": int, "headers": [[name, value], ...],
         "body_base64": string, "error": string }].
      Transport failures are reported in-band with [status] 0 and a
      non-empty [error]; malformed arguments produce an [Error]. *)

type request = {
  url : string;
  meth : string;          (** HTTP method, sent verbatim. *)
  headers : (string * string) list;
  body : string;          (** Raw bytes; may be empty. *)
  follow_redirects : bool;
  max_redirects : int;
  timeout_ms : int;       (** 0 = no timeout. *)
}

type response = {
  status : int;           (** Last HTTP status, 0 on transport error. *)
  headers : (string * string) list;  (** Last response's headers, in
                                         wire order. *)
  body : string;
}

val available : unit -> bool
(** Whether a usable libcurl was found at runtime. *)

val perform : request -> (response, string) result
(** Synchronous request. Raises [Failure] on platforms with no
    implementation. *)

val request : string -> request
(** [request url] is a GET with redirects followed (max 20) and a 30s
    timeout. *)

val request_of_yojson : Yojson.Safe.t -> (request, string) result
val response_to_yojson : ?error:string -> response -> Yojson.Safe.t

val plugin : Lui_plugin.t
(** The ["plugin:fetch"] service descriptor: method ["request"]. *)

module Private : sig
  val parse_headers : string -> (string * string) list
  val b64_encode : string -> string
  val b64_decode : string -> (string, string) result
end
