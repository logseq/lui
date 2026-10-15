(* WebSocket client (RFC 6455), pure OCaml over Unix TCP sockets.

   ws:// only — there is no TLS transport yet. Client-to-server frames
   are always masked; inbound frames are accepted masked or unmasked
   (the RFC forbids server masking, being lenient costs nothing). Ping
   is answered with pong automatically; fragmentation is reassembled
   across continuation frames. *)

(* ---- SHA-1 (needed for the Sec-WebSocket-Accept handshake) ---- *)

let sha1 s =
  let h0 = ref 0x67452301l
  and h1 = ref 0xEFCDAB89l
  and h2 = ref 0x98BADCFEl
  and h3 = ref 0x10325476l
  and h4 = ref 0xC3D2E1F0l in
  let len = String.length s in
  let bitlen = Int64.shift_left (Int64.of_int len) 3 in
  let padlen = (55 - len) mod 64 + 64 in
  let padlen = padlen mod 64 in
  let total = len + 1 + padlen + 8 in
  let msg = Bytes.make total '\x00' in
  Bytes.blit_string s 0 msg 0 len;
  Bytes.set msg len '\x80';
  for i = 0 to 7 do
    Bytes.set msg (total - 8 + i)
      (Char.chr
         (Int64.to_int
            (Int64.logand
               (Int64.shift_right_logical bitlen (8 * (7 - i)))
               0xffL)))
  done;
  let w = Array.make 80 0l in
  let rotl x n =
    Int32.logor (Int32.shift_left x n)
      (Int32.shift_right_logical x (32 - n))
  in
  for off = 0 to total / 64 - 1 do
    let base = off * 64 in
    for i = 0 to 15 do
      let j = base + (i * 4) in
      let b k = Int32.of_int (Char.code (Bytes.get msg (j + k))) in
      w.(i) <-
        Int32.logor (Int32.shift_left (b 0) 24)
          (Int32.logor (Int32.shift_left (b 1) 16)
             (Int32.logor (Int32.shift_left (b 2) 8) (b 3)))
    done;
    for i = 16 to 79 do
      let x =
        Int32.logxor
          (Int32.logxor w.(i - 3) w.(i - 8))
          (Int32.logxor w.(i - 14) w.(i - 16))
      in
      w.(i) <- rotl x 1
    done;
    let a = ref !h0 and b = ref !h1 and c = ref !h2 and d = ref !h3
    and e = ref !h4 in
    for i = 0 to 79 do
      let f, k =
        if i < 20 then
          ( Int32.logor (Int32.logand !b !c)
              (Int32.logand (Int32.lognot !b) !d),
            0x5A827999l )
        else if i < 40 then
          (Int32.logxor !b (Int32.logxor !c !d), 0x6ED9EBA1l)
        else if i < 60 then
          ( Int32.logor (Int32.logand !b !c)
              (Int32.logor (Int32.logand !b !d)
                 (Int32.logand !c !d)),
            0x8F1BBCDCl )
        else (Int32.logxor !b (Int32.logxor !c !d), 0xCA62C1D6l)
      in
      let t =
        Int32.add
          (Int32.add (Int32.add (Int32.add (rotl !a 5) f) !e) k)
          w.(i)
      in
      e := !d;
      d := !c;
      c := rotl !b 30;
      b := !a;
      a := t
    done;
    h0 := Int32.add !h0 !a;
    h1 := Int32.add !h1 !b;
    h2 := Int32.add !h2 !c;
    h3 := Int32.add !h3 !d;
    h4 := Int32.add !h4 !e
  done;
  let out = Bytes.create 20 in
  List.iteri
    (fun i h ->
      for k = 0 to 3 do
        Bytes.set out ((i * 4) + k)
          (Char.chr
             (Int32.to_int
                (Int32.logand
                   (Int32.shift_right_logical h (8 * (3 - k)))
                   0xffl)))
      done)
    [ !h0; !h1; !h2; !h3; !h4 ];
  Bytes.unsafe_to_string out

(* ---- base64 ---- *)

module B64 = struct
  let alphabet =
    "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

  let encode s =
    let n = String.length s in
    let b = Buffer.create ((n + 2) / 3 * 4) in
    let i = ref 0 in
    while !i < n do
      let get j = if j < n then Char.code s.[j] else 0 in
      let v = (get !i lsl 16) lor (get (!i + 1) lsl 8) lor get (!i + 2) in
      let pad = if !i + 2 >= n then if !i + 1 >= n then 2 else 1 else 0 in
      Buffer.add_char b alphabet.[(v lsr 18) land 63];
      Buffer.add_char b alphabet.[(v lsr 12) land 63];
      Buffer.add_char b
        (if pad >= 2 then '=' else alphabet.[(v lsr 6) land 63]);
      Buffer.add_char b
        (if pad >= 1 then '=' else alphabet.[v land 63]);
      i := !i + 3
    done;
    Buffer.contents b

  let decode s =
    let tbl = Array.make 256 (-1) in
    String.iteri (fun i c -> tbl.(Char.code c) <- i) alphabet;
    let b = Buffer.create (String.length s / 4 * 3) in
    let acc = ref 0 and bits = ref 0 and ok = ref true in
    String.iter
      (fun c ->
        if c <> '=' then
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
end

let ws_guid = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"

let accept_key key = B64.encode (sha1 (key ^ ws_guid))

(* ---- randomness: masking keys and the handshake nonce ---- *)

let random_bytes n =
  try
    let fd = Unix.openfile "/dev/urandom" [ Unix.O_RDONLY ] 0 in
    Fun.protect
      ~finally:(fun () -> try Unix.close fd with _ -> ())
      (fun () ->
        let b = Bytes.create n in
        let rec loop off =
          if off < n then
            match Unix.read fd b off (n - off) with
            | 0 -> raise End_of_file
            | k -> loop (off + k)
        in
        loop 0;
        Bytes.unsafe_to_string b)
  with _ ->
    Random.self_init ();
    String.init n (fun _ -> Char.chr (Random.bits () land 0xff))

(* ---- connection state ---- *)

type event =
  | Message of int * string
  | Close of int * string
  | Ev_error of string

type conn = {
  sock : Unix.file_descr;
  inbuf : Buffer.t;
  mutable eof : bool;
  mutable closed : bool;
  mutable sent_close : bool;
  mutable frag_op : int;
  frag_buf : Buffer.t;
  pending : event Queue.t;
}

let safe_close fd = try Unix.close fd with _ -> ()

let write_all sock b =
  let n = Bytes.length b in
  let rec loop off =
    if off < n then
      match Unix.write sock b off (n - off) with
      | 0 -> raise (Unix.Unix_error (Unix.EPIPE, "write", ""))
      | k -> loop (off + k)
  in
  loop 0

let read_once conn =
  let tmp = Bytes.create 65536 in
  match Unix.read conn.sock tmp 0 (Bytes.length tmp) with
  | 0 -> conn.eof <- true
  | n -> Buffer.add_subbytes conn.inbuf tmp 0 n
  | exception Unix.Unix_error _ -> conn.eof <- true

(* Drain whatever the kernel already holds, without blocking. *)
let fill conn =
  let rec loop i =
    if i > 0 && not conn.eof then
      match Unix.select [ conn.sock ] [] [] 0.0 with
      | _ :: _, _, _ ->
        read_once conn;
        loop (i - 1)
      | _ -> ()
      | exception Unix.Unix_error _ -> conn.eof <- true
  in
  loop 64

(* ---- frame codec ---- *)

let encode_frame ~mask ~opcode payload =
  let n = String.length payload in
  let b = Buffer.create (n + 14) in
  Buffer.add_char b (Char.chr (0x80 lor opcode));
  let len_hdr first =
    Buffer.add_char b
      (Char.chr ((if mask then 0x80 else 0) lor first))
  in
  if n < 126 then len_hdr n
  else if n < 65536 then begin
    len_hdr 126;
    Buffer.add_char b (Char.chr ((n lsr 8) land 0xff));
    Buffer.add_char b (Char.chr (n land 0xff))
  end
  else begin
    len_hdr 127;
    for i = 7 downto 0 do
      Buffer.add_char b (Char.chr ((n lsr (8 * i)) land 0xff))
    done
  end;
  if mask then begin
    let m = random_bytes 4 in
    Buffer.add_string b m;
    for i = 0 to n - 1 do
      Buffer.add_char b
        (Char.chr (Char.code payload.[i] lxor Char.code m.[i land 3]))
    done
  end
  else Buffer.add_string b payload;
  Buffer.contents b

let drop buf n =
  let rest = Buffer.sub buf n (Buffer.length buf - n) in
  Buffer.reset buf;
  Buffer.add_string buf rest

(* Pop one complete frame, or None when the buffer holds only a
   partial one. *)
let next_frame conn =
  let n = Buffer.length conn.inbuf in
  if n < 2 then None
  else begin
    let b0 = Char.code (Buffer.nth conn.inbuf 0)
    and b1 = Char.code (Buffer.nth conn.inbuf 1) in
    let ln0 = b1 land 0x7f in
    let hdrlen = if ln0 < 126 then 2 else if ln0 = 126 then 4 else 10 in
    if n < hdrlen then None
    else begin
      let be i = Char.code (Buffer.nth conn.inbuf i) in
      let ln =
        if ln0 < 126 then ln0
        else if ln0 = 126 then (be 2 lsl 8) lor be 3
        else begin
          let v = ref 0 in
          for i = 2 to 9 do
            v := (!v lsl 8) lor be i
          done;
          !v
        end
      in
      let masked = b1 land 0x80 <> 0 in
      let moff = hdrlen + (if masked then 4 else 0) in
      if n < moff + ln then None
      else begin
        let mask =
          if masked then Buffer.sub conn.inbuf hdrlen 4 else ""
        in
        let payload = Bytes.of_string (Buffer.sub conn.inbuf moff ln) in
        if masked then
          for i = 0 to ln - 1 do
            Bytes.set payload i
              (Char.chr
                 (Char.code (Bytes.get payload i)
                  lxor Char.code mask.[i land 3]))
          done;
        drop conn.inbuf (moff + ln);
        Some (b0 land 0x80 <> 0, b0 land 0x0f, Bytes.unsafe_to_string payload)
      end
    end
  end

let try_send conn ~opcode payload =
  try
    write_all conn.sock
      (Bytes.of_string (encode_frame ~mask:true ~opcode payload));
    Ok ()
  with
  | Unix.Unix_error (e, _, _) -> Error (Unix.error_message e)
  | _ -> Error "send failed"

let rec drain_frames conn =
  match next_frame conn with
  | None -> ()
  | Some (fin, op, payload) ->
    handle_frame conn fin op payload;
    if not conn.closed then drain_frames conn

and handle_frame conn fin op payload =
  match op with
  | 0x8 ->
    let code, reason =
      if String.length payload >= 2 then
        ( (Char.code payload.[0] lsl 8) lor Char.code payload.[1],
          String.sub payload 2 (String.length payload - 2) )
      else (1005, "")
    in
    if not conn.sent_close then
      ignore (try_send conn ~opcode:0x8 payload);
    conn.closed <- true;
    safe_close conn.sock;
    Queue.add (Close (code, reason)) conn.pending
  | 0x9 -> ignore (try_send conn ~opcode:0xA payload)
  | 0xA -> ()
  | 0x0 ->
    Buffer.add_string conn.frag_buf payload;
    if fin then begin
      Queue.add
        (Message (conn.frag_op, Buffer.contents conn.frag_buf))
        conn.pending;
      Buffer.reset conn.frag_buf;
      conn.frag_op <- 0
    end
  | 0x1 | 0x2 ->
    if fin then Queue.add (Message (op, payload)) conn.pending
    else begin
      conn.frag_op <- op;
      Buffer.reset conn.frag_buf;
      Buffer.add_string conn.frag_buf payload
    end
  | _ ->
    Queue.add
      (Ev_error (Printf.sprintf "unsupported frame opcode %d" op))
      conn.pending

(* ---- HTTP upgrade handshake ---- *)

let parse_url url =
  let lower = String.lowercase_ascii url in
  if String.length lower >= 6 && String.sub lower 0 6 = "wss://" then
    Error "wss:// URLs are not supported (no TLS transport yet)"
  else if not (String.length lower >= 5 && String.sub lower 0 5 = "ws://") then
    Error (Printf.sprintf "unsupported scheme in %S (want ws://)" url)
  else begin
    let rest = String.sub url 5 (String.length url - 5) in
    let slash =
      match String.index_opt rest '/' with
      | Some i -> i
      | None -> String.length rest
    in
    let hostport = String.sub rest 0 slash in
    let resource =
      if slash < String.length rest then
        String.sub rest slash (String.length rest - slash)
      else "/"
    in
    let host, port =
      match String.rindex_opt hostport ':' with
      | Some i ->
        let p =
          try
            int_of_string
              (String.sub hostport (i + 1) (String.length hostport - i - 1))
          with _ -> 0
        in
        (String.sub hostport 0 i, if p > 0 then p else 80)
      | None -> (hostport, 80)
    in
    let host =
      if String.length host >= 2 && host.[0] = '['
         && host.[String.length host - 1] = ']'
      then String.sub host 1 (String.length host - 2)
      else host
    in
    if host = "" then Error "empty host in url"
    else Ok (host, port, resource)
  end

let find_header_end s =
  let n = String.length s in
  let rec scan i =
    if i + 4 > n then None
    else if
      s.[i] = '\r' && s.[i + 1] = '\n' && s.[i + 2] = '\r'
      && s.[i + 3] = '\n'
    then Some (i + 4)
    else scan (i + 1)
  in
  scan 0

let token_present ~token s =
  s |> String.lowercase_ascii |> String.split_on_char ','
  |> List.exists (fun t -> String.trim t = token)

(* Parse "HTTP/1.1 101 ..." plus headers; check upgrade + accept. *)
let validate_response head key =
  match String.split_on_char '\n' head with
  | [] -> Error "empty handshake response"
  | status_line :: rest ->
    let status_code =
      match String.index_opt status_line ' ' with
      | Some i ->
        let tail =
          String.sub status_line (i + 1)
            (String.length status_line - i - 1)
        in
        let token =
          match String.index_opt tail ' ' with
          | Some j -> String.sub tail 0 j
          | None -> String.trim tail
        in
        (try int_of_string token with _ -> 0)
      | None -> 0
    in
    let hdrs =
      List.filter_map
        (fun line ->
          let line = String.trim line in
          if line = "" || String.length line < 3 then None
          else
            match String.index_opt line ':' with
            | Some i ->
              Some
                ( String.lowercase_ascii
                    (String.trim (String.sub line 0 i)),
                  String.trim
                    (String.sub line (i + 1) (String.length line - i - 1))
                )
            | None -> None)
        rest
    in
    if status_code <> 101 then
      Error
        (Printf.sprintf "websocket upgrade refused (status %d)"
           status_code)
    else if
      not
        (match List.assoc_opt "upgrade" hdrs with
         | Some v -> String.lowercase_ascii v = "websocket"
         | None -> false)
    then Error "missing Upgrade: websocket response header"
    else if
      not
        (match List.assoc_opt "connection" hdrs with
         | Some v -> token_present ~token:"upgrade" v
         | None -> false)
    then Error "missing Connection: Upgrade response header"
    else if
      (match List.assoc_opt "sec-websocket-accept" hdrs with
       | Some v -> v <> accept_key key
       | None -> true)
    then Error "bad Sec-WebSocket-Accept"
    else Ok ()

let handshake sock ~host ~port ~resource ~headers ~timeout_ms =
  let key = B64.encode (random_bytes 16) in
  let b = Buffer.create 512 in
  Buffer.add_string b ("GET " ^ resource ^ " HTTP/1.1\r\n");
  Buffer.add_string b
    ("Host: " ^ host
    ^ (if port = 80 then "" else ":" ^ string_of_int port)
    ^ "\r\n");
  Buffer.add_string b "Upgrade: websocket\r\n";
  Buffer.add_string b "Connection: Upgrade\r\n";
  Buffer.add_string b ("Sec-WebSocket-Key: " ^ key ^ "\r\n");
  Buffer.add_string b "Sec-WebSocket-Version: 13\r\n";
  List.iter
    (fun (k, v) -> Buffer.add_string b (k ^ ": " ^ v ^ "\r\n"))
    headers;
  Buffer.add_string b "\r\n";
  write_all sock (Bytes.of_string (Buffer.contents b));
  let deadline =
    Unix.gettimeofday () +. (float_of_int timeout_ms /. 1000.)
  in
  let raw = Buffer.create 4096 in
  let rec loop () =
    match find_header_end (Buffer.contents raw) with
    | Some _ -> Ok ()
    | None ->
      let left = deadline -. Unix.gettimeofday () in
      if left <= 0. then Error "handshake timed out"
      else if Buffer.length raw > 65536 then
        Error "handshake response too long"
      else
        match Unix.select [ sock ] [] [] left with
        | _ :: _, _, _ -> (
          let tmp = Bytes.create 4096 in
          match Unix.read sock tmp 0 (Bytes.length tmp) with
          | 0 -> Error "connection closed during handshake"
          | n ->
            Buffer.add_subbytes raw tmp 0 n;
            loop ()
          | exception Unix.Unix_error (e, _, _) ->
            Error (Unix.error_message e))
        | _ -> loop ()
  in
  match loop () with
  | Error e -> Error e
  | Ok () ->
    let contents = Buffer.contents raw in
    let hend = Option.get (find_header_end contents) in
    let head = String.sub contents 0 hend in
    (match validate_response head key with
     | Error e -> Error e
     | Ok () ->
       let inbuf = Buffer.create 4096 in
       (* Frames that followed the header block in the same read. *)
       Buffer.add_string inbuf
         (String.sub contents hend (String.length contents - hend));
       Ok inbuf)

let connect ~url ?(headers = []) ?(timeout_ms = 5000) () =
  match parse_url url with
  | Error e -> Error e
  | Ok (host, port, resource) -> (
    try
      let ais =
        Unix.getaddrinfo host (string_of_int port)
          [ Unix.AI_SOCKTYPE Unix.SOCK_STREAM ]
      in
      let rec try_addrs last = function
        | [] ->
          Error
            (Printf.sprintf "cannot connect to %s:%d (%s)" host port
               last)
        | ai :: tl ->
          let sock = Unix.socket ai.Unix.ai_family Unix.SOCK_STREAM 0 in
          (match Unix.connect sock ai.Unix.ai_addr with
           | () -> Ok sock
           | exception Unix.Unix_error (e, _, _) ->
             safe_close sock;
             try_addrs (Unix.error_message e) tl)
      in
      match try_addrs "no address" ais with
      | Error e -> Error e
      | Ok sock -> (
        match
          handshake sock ~host ~port ~resource ~headers ~timeout_ms
        with
        | Error e ->
          safe_close sock;
          Error e
        | Ok inbuf ->
          Ok
            {
              sock;
              inbuf;
              eof = false;
              closed = false;
              sent_close = false;
              frag_op = 0;
              frag_buf = Buffer.create 256;
              pending = Queue.create ();
            })
    with
    | Unix.Unix_error (e, _, _) -> Error (Unix.error_message e)
    | Not_found -> Error (Printf.sprintf "cannot resolve %s" host)
    | Failure e -> Error e)

let send conn ~opcode payload =
  if conn.closed || conn.eof then Error "connection closed"
  else try_send conn ~opcode payload

let poll conn =
  if not conn.closed then begin
    fill conn;
    drain_frames conn;
    if conn.eof && not conn.closed then begin
      conn.closed <- true;
      Queue.add (Close (1006, "")) conn.pending;
      safe_close conn.sock
    end
  end;
  let rec drain acc =
    if Queue.is_empty conn.pending then List.rev acc
    else drain (Queue.take conn.pending :: acc)
  in
  drain []

let close conn ?(code = 1000) ?(reason = "") () =
  if not conn.closed then begin
    let payload =
      let b = Bytes.create 2 in
      Bytes.set b 0 (Char.chr ((code lsr 8) land 0xff));
      Bytes.set b 1 (Char.chr (code land 0xff));
      Bytes.unsafe_to_string b ^ reason
    in
    if not conn.sent_close then begin
      ignore (try_send conn ~opcode:0x8 payload);
      conn.sent_close <- true
    end;
    (* Give the peer a bounded window to echo its close frame; the
       echo (and any trailing messages) stays queued for [poll]. *)
    let deadline = Unix.gettimeofday () +. 0.5 in
    (try
       while not conn.closed do
         let left = deadline -. Unix.gettimeofday () in
         if left <= 0. then raise Exit;
         match Unix.select [ conn.sock ] [] [] left with
         | _ :: _, _, _ ->
           read_once conn;
           drain_frames conn;
           if conn.eof then raise Exit
         | _ -> raise Exit
         | exception Unix.Unix_error _ -> raise Exit
       done
     with _ -> ());
    conn.closed <- true;
    safe_close conn.sock
  end

(* ---- service layer: conn table + JSON methods ---- *)

module Service = struct
  let lock = Mutex.create ()
  let conns : (int, conn) Hashtbl.t = Hashtbl.create 8
  let counter = ref 0

  let register conn =
    Mutex.lock lock;
    incr counter;
    let id = !counter in
    Hashtbl.replace conns id conn;
    Mutex.unlock lock;
    id

  let find id =
    Mutex.lock lock;
    let c = Hashtbl.find_opt conns id in
    Mutex.unlock lock;
    c

  let remove id =
    Mutex.lock lock;
    Hashtbl.remove conns id;
    Mutex.unlock lock

  let headers_of_yojson j =
    match j with
    | `Assoc ks ->
      List.filter_map
        (fun (k, v) -> match v with `String s -> Some (k, s) | _ -> None)
        ks
    | `List ps ->
      List.filter_map
        (function
          | `List [ `String k; `String v ] -> Some (k, v)
          | _ -> None)
        ps
    | _ -> []

  let conn_id_of j =
    let open Yojson.Safe.Util in
    match j |> member "conn_id" with
    | `Int n -> Ok n
    | _ -> Error "missing \"conn_id\""

  let with_conn j f =
    match conn_id_of j with
    | Error e -> Error e
    | Ok id -> (
      match find id with
      | None -> Error (Printf.sprintf "unknown connection %d" id)
      | Some conn -> f id conn)

  let opcode_of_yojson = function
    | `Int n -> Some n
    | `String s -> (
      match String.lowercase_ascii s with
      | "text" -> Some 1
      | "binary" -> Some 2
      | "close" -> Some 8
      | "ping" -> Some 9
      | "pong" -> Some 10
      | _ -> None)
    | _ -> None

  let event_to_yojson = function
    | Message (op, data) ->
      `Assoc
        [
          ("kind", `String "message");
          ( "opcode",
            `String
              (match op with
               | 1 -> "text"
               | 2 -> "binary"
               | n -> string_of_int n) );
          ("data", `String (B64.encode data));
        ]
    | Close (code, reason) ->
      `Assoc
        [
          ("kind", `String "close");
          ("code", `Int code);
          ("reason", `String reason);
        ]
    | Ev_error e ->
      `Assoc [ ("kind", `String "error"); ("data", `String e) ]

  let to_json payload =
    try Ok (Yojson.Safe.from_string payload)
    with Yojson.Json_error e -> Error ("invalid JSON: " ^ e)

  let m_open payload =
    match to_json payload with
    | Error e -> Error e
    | Ok j -> (
      let open Yojson.Safe.Util in
      match j |> member "url" with
      | `String url ->
        let headers = headers_of_yojson (member "headers" j) in
        let timeout_ms =
          match j |> member "timeout_ms" with
          | `Int n -> n
          | _ -> 5000
        in
        (match connect ~url ~headers ~timeout_ms () with
         | Error e -> Error e
         | Ok conn ->
           Ok
             (Yojson.Safe.to_string
                (`Assoc [ ("conn_id", `Int (register conn)) ])))
      | _ -> Error "missing \"url\"")

  let m_send payload =
    match to_json payload with
    | Error e -> Error e
    | Ok j ->
      with_conn j (fun _id conn ->
          let open Yojson.Safe.Util in
          match opcode_of_yojson (member "opcode" j) with
          | None -> Error "missing or bad \"opcode\""
          | Some opcode -> (
            let raw =
              match j |> member "payload_b64" with
              | `String s -> Some s
              | _ -> (
                match j |> member "data" with
                | `String s -> Some s
                | _ -> None)
            in
            match raw with
            | None -> Error "missing \"payload_b64\""
            | Some b64 -> (
              match B64.decode b64 with
              | Error e -> Error e
              | Ok data -> (
                match send conn ~opcode data with
                | Ok () -> Ok "{}"
                | Error e -> Error e))))

  let m_poll payload =
    match to_json payload with
    | Error e -> Error e
    | Ok j ->
      with_conn j (fun id conn ->
          let evs = poll conn in
          (* A closed conn that delivered everything is dropped. *)
          if conn.closed && Queue.is_empty conn.pending then remove id;
          Ok
            (Yojson.Safe.to_string
               (`Assoc
                 [ ("events", `List (List.map event_to_yojson evs)) ])))

  let m_close payload =
    match to_json payload with
    | Error e -> Error e
    | Ok j ->
      with_conn j (fun _id conn ->
          let open Yojson.Safe.Util in
          let code =
            match j |> member "code" with `Int n -> n | _ -> 1000
          and reason =
            match j |> member "reason" with `String s -> s | _ -> ""
          in
          close conn ~code ~reason ();
          Ok "{}")
end

let plugin : Lui_plugin.t =
  Lui_plugin.v "websocket"
    [
      ("open", Service.m_open);
      ("send", Service.m_send);
      ("poll", Service.m_poll);
      ("close", Service.m_close);
    ]

module Private = struct
  let sha1 = sha1
  let b64_encode = B64.encode
  let accept_key = accept_key
  let encode_frame = encode_frame
end
