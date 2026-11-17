(* Webview service: JSON-in/JSON-out native web views by integer id.

   Methods (payloads are JSON objects):
     create   { "host": "<native-window ptr>" | "host_sdl": "<SDL_Window ptr>",
                "x":0,"y":0,"w":0,"h":0,
                "url"|"html"(+"base_url")|"file", "user_agent"?,
                "zoom"?, "transparent"? }                    -> {"id": n}
     navigate { "id": n, "url" | "html"(+"base_url") | "file" |
                "op": "back"|"forward"|"reload"|"stop" }     -> {}
     eval     { "id": n, "js": "<expression|body>" }         -> {}
     call     { "id": n, "js": "<async fn body>" }           -> {"result": "..."}
                (pumps the run loop until the engine answers; ~5s cap)
     layout   { "id": n, "x":0,"y":0,"w":0,"h":0 }            -> {}
     state    { "id": n }                                    -> {"url","is_loading",
                "can_go_back","can_go_forward","frame":[x,y,w,h]}
     capture  { "id": n }                                    -> {"png_base64": "..."}
     destroy  { "id": n }                                    -> {}
*)

module W = Lui_webview

(* ---- views by id ---- *)

let views : (int, W.t) Hashtbl.t = Hashtbl.create 8
let next_id = ref 0

let add t =
  incr next_id;
  Hashtbl.replace views !next_id t;
  !next_id

let view j =
  let open Yojson.Safe.Util in
  match j |> member "id" with
  | `Int n -> (
    match Hashtbl.find_opt views n with
    | Some t -> Ok t
    | None -> Error (Printf.sprintf "no webview %d" n))
  | _ -> Error "missing \"id\""

(* ---- JSON helpers ---- *)

let member k j = Yojson.Safe.Util.member k j

let float_field k j ~default =
  match member k j with
  | `Int n -> float_of_int n
  | `Float f -> f
  | `Null -> default
  | _ -> default

let rect_of j =
  W.rect (float_field "x" j ~default:0.) (float_field "y" j ~default:0.)
    (float_field "w" j ~default:0.) (float_field "h" j ~default:0.)

let source_of j =
  let open Yojson.Safe.Util in
  match j |> member "url" with
  | `String u when u <> "" -> Ok (W.Url u)
  | `String _ -> Error "empty \"url\""
  | _ -> (
    match j |> member "html" with
    | `String h ->
      let base =
        match j |> member "base_url" with `String b -> b | _ -> ""
      in
      Ok (W.Html (h, base))
    | `Null -> (
      match j |> member "file" with
      | `String p when p <> "" -> Ok (W.File p)
      | `String _ -> Error "empty \"file\""
      | _ -> Ok W.Empty)
    | _ -> Error "\"html\" must be a string")

let host_of j =
  let open Yojson.Safe.Util in
  match j |> member "host_sdl" with
  | `String p ->
    (try Ok (W.host_of_sdl_window (Nativeint.of_string p))
     with Failure e -> Error e | _ -> Error "bad \"host_sdl\"")
  | `Null -> (
    match j |> member "host" with
    | `String p ->
      (try Ok (W.host_of_native (Nativeint.of_string p))
       with _ -> Error "bad \"host\"")
    | `Null -> (
      try Ok (W.host_main_window ()) with Failure e -> Error e)
    | _ -> Error "\"host\" must be a pointer string")
  | _ -> Error "\"host_sdl\" must be a pointer string"

let b64_encode =
  let enc =
    "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
  in
  fun s ->
    let n = String.length s in
    let b = Buffer.create ((n + 2) / 3 * 4) in
    let i = ref 0 in
    while !i < n do
      let get j = if j < n then Char.code s.[j] else 0 in
      let v = (get !i lsl 16) lor (get (!i + 1) lsl 8) lor get (!i + 2) in
      let pad = if !i + 2 >= n then if !i + 1 >= n then 2 else 1 else 0 in
      Buffer.add_char b enc.[(v lsr 18) land 63];
      Buffer.add_char b enc.[(v lsr 12) land 63];
      Buffer.add_char b (if pad >= 2 then '=' else enc.[(v lsr 6) land 63]);
      Buffer.add_char b (if pad >= 1 then '=' else enc.[v land 63]);
      i := !i + 3
    done;
    Buffer.contents b

let parse payload =
  match (try Ok (Yojson.Safe.from_string payload)
         with Yojson.Json_error e -> Error e) with
  | Error e -> Error ("invalid JSON: " ^ e)
  | Ok j -> Ok j

let ok json = Ok (Yojson.Safe.to_string json)
let obj () = `Assoc []

(* ---- methods ---- *)

let m_create payload =
  match parse payload with
  | Error _ as e -> e
  | Ok j -> (
    match host_of j with
    | Error _ as e -> e
    | Ok host -> (
      match source_of j with
      | Error _ as e -> e
      | Ok src -> (
        let o =
          W.opts ?user_agent:(match member "user_agent" j with
                              | `String s -> Some s | _ -> None)
            ?zoom:(match member "zoom" j with
                   | `Float f -> Some f | `Int n -> Some (float_of_int n)
                   | _ -> None)
            ?transparent:(match member "transparent" j with
                          | `Bool b -> Some b | _ -> None)
            src
        in
        match (try Ok (W.create host (rect_of j) o)
               with Failure e -> Error e) with
        | Error _ as e -> e
        | Ok t -> ok (`Assoc [ ("id", `Int (add t)) ]))))

let m_navigate payload =
  match parse payload with
  | Error _ as e -> e
  | Ok j -> (
    match view j with
    | Error _ as e -> e
    | Ok t -> (
      match member "op" j with
      | `String op -> (
        match op with
        | "back" -> W.go_back t; ok (obj ())
        | "forward" -> W.go_forward t; ok (obj ())
        | "reload" -> W.reload t; ok (obj ())
        | "stop" -> W.stop t; ok (obj ())
        | _ -> Error ("unknown op " ^ op))
      | _ -> (
        match source_of j with
        | Error _ as e -> e
        | Ok (W.Url u) -> W.load_url t u; ok (obj ())
        | Ok (W.Html (h, b)) -> W.load_html t ~base_url:b h; ok (obj ())
        | Ok (W.File p) -> W.load_file t p; ok (obj ())
        | Ok W.Empty -> ok (obj ()))))

let m_eval payload =
  match parse payload with
  | Error _ as e -> e
  | Ok j -> (
    match (view j, member "js" j) with
    | Error _ as e, _ -> e
    | Ok t, `String js -> W.eval t js; ok (obj ())
    | _, _ -> Error "missing \"js\"")

let m_call payload =
  match parse payload with
  | Error _ as e -> e
  | Ok j -> (
    match (view j, member "js" j) with
    | Error _ as e, _ -> e
    | Ok t, `String js ->
      let got = ref None in
      (try W.call_async t js (fun s -> got := Some s)
       with Failure e ->
         got := Some (Yojson.Safe.to_string (`String ("Error: " ^ e))));
      (* Pump the engine + drain until the reply arrives; ~5s bound. *)
      let deadline = Unix.gettimeofday () +. 5.0 in
      while !got = None && Unix.gettimeofday () < deadline do
        W.pump ();
        ignore (W.drain t);
        Unix.sleepf 0.01
      done;
      (match !got with
       | Some r -> ok (`Assoc [ ("result", `String r) ])
       | None -> Error "call timed out")
    | _, _ -> Error "missing \"js\"")

let m_layout payload =
  match parse payload with
  | Error _ as e -> e
  | Ok j -> (
    match view j with
    | Error _ as e -> e
    | Ok t -> W.layout_webview t (rect_of j); ok (obj ()))

let m_state payload =
  match parse payload with
  | Error _ as e -> e
  | Ok j -> (
    match view j with
    | Error _ as e -> e
    | Ok t ->
      let f = W.frame t in
      ok
        (`Assoc
           [ ("url", `String (W.url t));
             ("is_loading", `Bool (W.is_loading t));
             ("can_go_back", `Bool (W.can_go_back t));
             ("can_go_forward", `Bool (W.can_go_forward t));
             ( "frame",
               `List [ `Float f.x; `Float f.y; `Float f.w; `Float f.h ]
             );
             ("backend", `String (W.backend_name ())) ]))

let m_capture payload =
  match parse payload with
  | Error _ as e -> e
  | Ok j -> (
    match view j with
    | Error _ as e -> e
    | Ok t ->
      (match W.capture_page t with
       | Some png ->
         ok (`Assoc [ ("png_base64", `String (b64_encode
                       (Bytes.to_string png))) ])
       | None -> Error "capture unavailable"))

let m_destroy payload =
  match parse payload with
  | Error _ as e -> e
  | Ok j -> (
    match view j with
    | Error _ as e -> e
    | Ok t ->
      let open Yojson.Safe.Util in
      (match j |> member "id" with
       | `Int n -> Hashtbl.remove views n
       | _ -> ());
      W.destroy t;
      ok (obj ()))

let teardown () =
  Hashtbl.iter (fun _ t -> try W.destroy t with _ -> ()) views;
  Hashtbl.reset views

let plugin : Lui_plugin.t =
  Lui_plugin.v ~teardown "webview"
    [ ("create", m_create);
      ("navigate", m_navigate);
      ("eval", m_eval);
      ("call", m_call);
      ("layout", m_layout);
      ("state", m_state);
      ("capture", m_capture);
      ("destroy", m_destroy) ]

module Private = struct
  let views = views
  let b64_encode = b64_encode
  let teardown = teardown
end
