(* Fetch service: JSON-in/JSON-out HTTP over the platform libcurl.
   The C stub returns (ok, status, error, raw_headers, body); header
   parsing and the JSON contract live here. *)

external c_available : unit -> bool = "lui_fetch_available"

external c_perform :
  string -> string -> string array -> string -> int -> int -> int ->
  bool * int * string * string * string
  = "lui_fetch_perform_bc" "lui_fetch_perform"

type request = {
  url : string;
  meth : string;
  headers : (string * string) list;
  body : string;
  follow_redirects : bool;
  max_redirects : int;
  timeout_ms : int;
  allow_private : bool;
    (** When false (default), refuse file:// and RFC1918 / link-local
        hosts. Loopback remains allowed so local tests work. *)
}

type response = {
  status : int;
  headers : (string * string) list;
  body : string;
}

let available = c_available

let request url =
  {
    url;
    meth = "GET";
    headers = [];
    body = "";
    follow_redirects = true;
    max_redirects = 20;
    timeout_ms = 30_000;
    allow_private = false;
  }

(* ---- URL policy (scheme + host) ---- *)

let url_scheme url =
  match String.index_opt url ':' with
  | None -> ""
  | Some i -> String.lowercase_ascii (String.sub url 0 i)

let url_host url =
  match String.index_opt url ':' with
  | None -> ""
  | Some i ->
    let rest = String.sub url (i + 1) (String.length url - i - 1) in
    if String.length rest < 2 || rest.[0] <> '/' || rest.[1] <> '/' then ""
    else
      let auth = String.sub rest 2 (String.length rest - 2) in
      let hostport =
        match String.index_opt auth '/' with
        | Some j -> String.sub auth 0 j
        | None -> auth
      in
      (* strip userinfo *)
      let hostport =
        match String.rindex_opt hostport '@' with
        | Some at -> String.sub hostport (at + 1) (String.length hostport - at - 1)
        | None -> hostport
      in
      (* strip port; keep [v6] brackets *)
      if hostport <> "" && hostport.[0] = '[' then
        match String.index_opt hostport ']' with
        | Some j -> String.sub hostport 0 (j + 1)
        | None -> hostport
      else
        match String.index_opt hostport ':' with
        | Some k -> String.sub hostport 0 k
        | None -> hostport

let is_loopback host =
  let h = String.lowercase_ascii host in
  h = "localhost" || h = "127.0.0.1" || h = "::1" || h = "[::1]"

let parse_ipv4 host =
  match String.split_on_char '.' host with
  | [ a; b; c; d ] -> (
    try
      let a, b, c, d =
        (int_of_string a, int_of_string b, int_of_string c, int_of_string d)
      in
      if
        List.for_all (fun x -> x >= 0 && x <= 255) [ a; b; c; d ]
      then Some (a, b, c, d)
      else None
    with _ -> None)
  | _ -> None

let is_private_or_link_local host =
  let h = String.lowercase_ascii host in
  if h = "" then true
  else if String.starts_with ~prefix:"fe80:" h || h = "[fe80" || String.starts_with ~prefix:"[fe80:" h
  then true
  else
    match parse_ipv4 h with
    | Some (10, _, _, _) -> true
    | Some (192, 168, _, _) -> true
    | Some (172, b, _, _) when b >= 16 && b <= 31 -> true
    | Some (169, 254, _, _) -> true
    | Some (127, _, _, _) -> false (* loopback handled separately *)
    | Some (0, _, _, _) -> true
    | Some (100, b, _, _) when b >= 64 && b <= 127 -> true (* CGNAT *)
    | _ ->
      (* Hostnames that look like .local / .internal stay blocked unless
         allow_private — callers targeting LAN by name must opt in. *)
      String.ends_with ~suffix:".local" h
      || String.ends_with ~suffix:".internal" h
      || String.ends_with ~suffix:".lan" h

let url_allowed ?(allow_private = false) url =
  match url_scheme url with
  | "https" | "http" ->
    let host = url_host url in
    if host = "" then false
    else if is_loopback host then true
    else if allow_private then true
    else not (is_private_or_link_local host)
  | "file" -> allow_private (* file:// only with the private/opt-in flag *)
  | _ -> false

(* libcurl's header callback concatenates status lines and headers for
   every hop; only the last response's headers are reported. *)
let parse_headers raw =
  let rec go acc cur = function
    | [] -> List.rev cur
    | line :: tl ->
      if line = "" then go acc cur tl
      else if String.length line >= 5 && String.sub line 0 5 = "HTTP/" then
        (* A new response block (redirect/stuff like 100 Continue):
           drop whatever we had. *)
        go acc [] tl
      else begin
        match String.index_opt line ':' with
        | Some i ->
          let name = String.sub line 0 i |> String.trim in
          let value =
            String.sub line (i + 1) (String.length line - i - 1)
            |> String.trim
          in
          if name = "" then go acc cur tl else go acc ((name, value) :: cur) tl
        | None -> go acc cur tl
      end
  in
  go [] [] (String.split_on_char '\n' raw)

let perform (r : request) =
  if not (url_allowed ~allow_private:r.allow_private r.url) then
    Error ("refusing to fetch " ^ r.url)
  else
    let hdrs =
      Array.of_list (List.map (fun (k, v) -> k ^ ": " ^ v) r.headers)
    in
    let ok, status, err, raw_headers, body =
      c_perform r.url r.meth hdrs r.body
        (if r.follow_redirects then 1 else 0)
        r.max_redirects r.timeout_ms
    in
    if not ok then Error (if err = "" then "request failed" else err)
    else Ok { status; headers = parse_headers raw_headers; body }

(* ---- base64 ---- *)

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

let b64_decode s =
  let tbl = Array.make 256 (-1) in
  String.iteri
    (fun i c -> tbl.(Char.code c) <- i)
    "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
  let n = String.length s in
  let b = Buffer.create (n / 4 * 3) in
  let acc = ref 0 and bits = ref 0 in
  let ok = ref true in
  String.iter
    (fun c ->
      if c = '=' then ()
      else
        match tbl.(Char.code c) with
        | -1 -> ok := false
        | v ->
          acc := (!acc lsl 6) lor v;
          bits := !bits + 6;
          if !bits >= 8 then begin
            bits := !bits - 8;
            Buffer.add_char b (Char.chr ((!acc lsr !bits) land 0xff))
          end)
    s;
  if !ok then Ok (Buffer.contents b) else Error "invalid base64"

(* ---- JSON contract ---- *)

let headers_of_yojson j =
  match j with
  | `Assoc ks ->
    List.map
      (fun (k, v) ->
        match v with
        | `String s -> (k, s)
        | `Int i -> (k, string_of_int i)
        | `Bool b -> (k, string_of_bool b)
        | _ -> (k, Yojson.Safe.to_string v))
      ks
  | `List ps ->
    List.filter_map
      (function
        | `List [ `String k; `String v ] -> Some (k, v)
        | _ -> None)
      ps
  | `Null -> []
  | _ -> []

let request_of_yojson j =
  let open Yojson.Safe.Util in
  try
    let url =
      match j |> member "url" with
      | `String s -> s
      | _ -> raise (Invalid_argument "missing \"url\"")
    in
    if url = "" then raise (Invalid_argument "empty \"url\"");
    let meth =
      match j |> member "method" with
      | `String s -> String.uppercase_ascii s
      | `Null -> "GET"
      | _ -> raise (Invalid_argument "\"method\" must be a string")
    in
    let headers = headers_of_yojson (member "headers" j) in
    let body =
      match j |> member "body_base64" with
      | `String s -> (
        match b64_decode s with
        | Ok b -> b
        | Error e -> raise (Invalid_argument e))
      | _ -> (
        match j |> member "body" with
        | `String s -> s
        | _ -> "")
    in
    let follow_redirects, max_redirects =
      match j |> member "redirect" with
      | `Bool b -> (b, 20)
      | `Int n -> (n > 0, max 0 n)
      | `Null -> (true, 20)
      | _ -> raise (Invalid_argument "\"redirect\" must be bool or int")
    in
    let timeout_ms =
      match j |> member "timeout_ms" with
      | `Int n -> max 0 n
      | `Null -> 30_000
      | _ -> raise (Invalid_argument "\"timeout_ms\" must be int")
    in
    let allow_private =
      match j |> member "allow_private" with
      | `Bool b -> b
      | `Null -> false
      | _ -> raise (Invalid_argument "\"allow_private\" must be bool")
    in
    Ok
      {
        url;
        meth;
        headers;
        body;
        follow_redirects;
        max_redirects;
        timeout_ms;
        allow_private;
      }
  with
  | Invalid_argument e -> Error e
  | Yojson.Json_error e -> Error e

let response_to_yojson ?(error = "") r =
  `Assoc
    [
      ("status", `Int r.status);
      ( "headers",
        `List
          (List.map (fun (k, v) -> `List [ `String k; `String v ]) r.headers) );
      ("body_base64", `String (b64_encode r.body));
      ("error", `String error);
    ]

(* ---- service method ---- *)

let request_call payload =
  match
    try Ok (Yojson.Safe.from_string payload)
    with Yojson.Json_error e -> Error e
  with
  | Error e -> Error ("invalid JSON: " ^ e)
  | Ok j -> (
    match request_of_yojson j with
    | Error e -> Error e
    | Ok req -> (
      match perform req with
      | Ok r -> Ok (Yojson.Safe.to_string (response_to_yojson r))
      | Error e ->
        (* Transport errors are reported in-band so callers always get
           a well-formed response document. *)
        Ok
          (Yojson.Safe.to_string
             (response_to_yojson ~error:e
                { status = 0; headers = []; body = "" }))))

let plugin : Lui_plugin.t =
  Lui_plugin.v "fetch" [ ("request", request_call) ]

module Private = struct
  let parse_headers = parse_headers
  let b64_encode = b64_encode
  let b64_decode = b64_decode
  let url_allowed = url_allowed
end
