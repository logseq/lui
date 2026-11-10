(* lui-agent on Web. The shared OCaml agent answers in-process; this module
   exposes it as window.__luiAgent and, when the page URL carries
   ?lui-agent=ws://127.0.0.1:PORT, dials tooling/lui_agent.mjs --ws-listen
   and answers each text frame with one reply frame. *)

let refused message =
  let buffer = Buffer.create 128 in
  Buffer.add_string buffer "{\"ok\":false,\"refused\":true,\"error\":";
  Lui_wire.add_quoted buffer message;
  Buffer.add_string buffer
    ",\"diagnostic\":{\"bridge\":\"web\",\"phase\":\"agent\",\"message\":";
  Lui_wire.add_quoted buffer message;
  Buffer.add_string buffer "}}";
  Buffer.contents buffer

(* Web has no C boundary and drops no patches, so a raising handler needs no
   resync; the script still gets a refusal instead of an uncaught error. *)
let message_of error =
  match error with
  | Js.Exn.Error js -> (
    match Js.Exn.message js with
    | Some message -> message
    | None -> Printexc.to_string error)
  | _ -> Printexc.to_string error

let answer target request =
  try Lui_agent.handle target request with
  | error ->
    let message = message_of error in
    Js.Console.error ("lui-agent: " ^ message);
    refused message

type search_params

external search_params : string -> search_params = "URLSearchParams"
[@@mel.new]

external search_param : search_params -> string -> string Js.Nullable.t
  = "get"
[@@mel.send]

let loopback_prefixes = [ "ws://127.0.0.1:"; "ws://localhost:" ]

let is_port text =
  text <> ""
  && String.length text <= 5
  && String.for_all (fun c -> c >= '0' && c <= '9') text
  && int_of_string text <= 65535

(* Only a loopback socket may drive the page: a link that names another host
   is ignored. *)
let dial_url search =
  match Js.Nullable.toOption (search_param (search_params search) "lui-agent") with
  | None -> None
  | Some url ->
    List.find_map
      (fun prefix ->
         let length = String.length prefix in
         if String.length url > length && String.sub url 0 length = prefix then
           let port = String.sub url length (String.length url - length) in
           if is_port port then Some url else None
         else None)
      loopback_prefixes

type web_socket
type message_event

external web_socket : string -> web_socket = "WebSocket" [@@mel.new]

external set_onmessage : web_socket -> (message_event -> unit) -> unit
  = "onmessage"
[@@mel.set]

external message_data : message_event -> string = "data" [@@mel.get]
external send : web_socket -> string -> unit = "send" [@@mel.send]

external set_global_agent : Dom.window -> (string -> string) -> unit
  = "__luiAgent"
[@@mel.set]

external window : Dom.window = "window"
external location_search : string = "search" [@@mel.scope "window", "location"]

let install target =
  set_global_agent window (answer target);
  match dial_url location_search with
  | None -> ()
  | Some url ->
    let socket = web_socket url in
    set_onmessage socket (fun event ->
      send socket (answer target (message_data event)))
