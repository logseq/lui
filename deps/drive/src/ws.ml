(* Minimal WebSocket (RFC 6455) server-side plumbing: enough for a
   browser page to dial `drive --ws-listen` and speak the live line
   protocol. One text message per frame in both directions; no
   fragmentation, compression, or TLS. *)

let read_line ic =
  let b = Buffer.create 64 in
  let rec loop () =
    match input_char ic with
    | '\r' -> (
      match input_char ic with
      | '\n' -> Some (Buffer.contents b)
      | c ->
        Buffer.add_char b c;
        loop ())
    | c ->
      Buffer.add_char b c;
      loop ()
    | exception End_of_file -> None
  in
  loop ()

let request_headers ic =
  let rec loop acc =
    match read_line ic with
    | None -> None
    | Some "" -> Some (List.rev acc)
    | Some line -> loop (line :: acc)
  in
  loop []

let header_value headers name =
  let name = String.lowercase_ascii name in
  List.find_map
    (fun h ->
      match String.index_opt h ':' with
      | Some i
        when String.lowercase_ascii
               (String.sub h 0 i |> String.trim)
             = name ->
        Some (String.sub h (i + 1) (String.length h - i - 1) |> String.trim)
      | _ -> None)
    headers

(* --- SHA-1 (handshake only) --- *)

let sha1 msg =
  let rol v n = Int32.logor (Int32.shift_left v n) (Int32.shift_right_logical v (32 - n)) in
  let len = String.length msg in
  let pad_len = ((56 - (len + 1)) mod 64 + 64) mod 64 + 1 in
  let total = len + pad_len + 8 in
  let buf = Bytes.make total '\x00' in
  Bytes.blit_string msg 0 buf 0 len;
  Bytes.set buf len '\x80';
  let bitlen = Int64.mul (Int64.of_int len) 8L in
  for i = 0 to 7 do
    Bytes.set buf (total - 1 - i)
      (Char.chr Int64.(to_int (logand (shift_right bitlen (8 * i)) 0xffL)))
  done;
  let hh = [| 0x67452301l; 0xefcdab89l; 0x98badcfel; 0x10325476l; 0xc3d2e1f0l |] in
  let w = Array.make 80 0l in
  for chunk = 0 to (total / 64) - 1 do
    for i = 0 to 15 do
      let o = (chunk * 64) + (i * 4) in
      w.(i) <-
        Int32.logor
          (Int32.shift_left (Int32.of_int (Char.code (Bytes.get buf o))) 24)
          (Int32.logor
             (Int32.shift_left (Int32.of_int (Char.code (Bytes.get buf (o + 1)))) 16)
             (Int32.logor
                (Int32.shift_left (Int32.of_int (Char.code (Bytes.get buf (o + 2)))) 8)
                (Int32.of_int (Char.code (Bytes.get buf (o + 3))))))
    done;
    for i = 16 to 79 do
      w.(i) <- rol (Int32.logxor w.(i - 3) (Int32.logxor w.(i - 8) (Int32.logxor w.(i - 14) w.(i - 16)))) 1
    done;
    let a = ref hh.(0) and b = ref hh.(1) and c = ref hh.(2) and d = ref hh.(3) and e = ref hh.(4) in
    for i = 0 to 79 do
      let f, k =
        if i < 20 then (Int32.logor (Int32.logand !b !c) (Int32.logand (Int32.lognot !b) !d), 0x5a827999l)
        else if i < 40 then (Int32.logxor !b (Int32.logxor !c !d), 0x6ed9eba1l)
        else if i < 60 then (Int32.logor (Int32.logand !b !c) (Int32.logor (Int32.logand !b !d) (Int32.logand !c !d)), 0x8f1bbcdcl)
        else (Int32.logxor !b (Int32.logxor !c !d), 0xca62c1d6l)
      in
      let tmp = Int32.add (Int32.add (Int32.add (Int32.add (rol !a 5) f) !e) k) w.(i) in
      e := !d;
      d := !c;
      c := rol !b 30;
      b := !a;
      a := tmp
    done;
    hh.(0) <- Int32.add hh.(0) !a;
    hh.(1) <- Int32.add hh.(1) !b;
    hh.(2) <- Int32.add hh.(2) !c;
    hh.(3) <- Int32.add hh.(3) !d;
    hh.(4) <- Int32.add hh.(4) !e
  done;
  let out = Bytes.create 20 in
  Array.iteri
    (fun i v ->
      Bytes.set out (i * 4) (Char.chr (Int32.(to_int (logand (shift_right_logical v 24) 0xffl))));
      Bytes.set out ((i * 4) + 1) (Char.chr (Int32.(to_int (logand (shift_right_logical v 16) 0xffl))));
      Bytes.set out ((i * 4) + 2) (Char.chr (Int32.(to_int (logand (shift_right_logical v 8) 0xffl))));
      Bytes.set out ((i * 4) + 3) (Char.chr (Int32.(to_int (logand v 0xffl)))))
    hh;
  Bytes.unsafe_to_string out

let base64 =
  let table =
    "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
  in
  fun s ->
    let len = String.length s in
    let b = Buffer.create ((len + 2) / 3 * 4) in
    let emit i n =
      let v =
        (Char.code s.[i] lsl 16)
        lor (if n > 1 then Char.code s.[i + 1] lsl 8 else 0)
        lor if n > 2 then Char.code s.[i + 2] else 0
      in
      Buffer.add_char b table.[v lsr 18 land 63];
      Buffer.add_char b table.[v lsr 12 land 63];
      Buffer.add_char b (if n > 1 then table.[v lsr 6 land 63] else '=');
      Buffer.add_char b (if n > 2 then table.[v land 63] else '=')
    in
    let rec loop i =
      if i + 3 <= len then begin
        emit i 3;
        loop (i + 3)
      end
      else if i < len then emit i (len - i)
    in
    loop 0;
    Buffer.contents b

let websocket_guid = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"

(* Server-side handshake: consumes the HTTP Upgrade request on [ic],
   writes the 101 response on [oc]. Returns unit on success. *)
let accept_handshake ic oc =
  match request_headers ic with
  | None -> false
  | Some (_request_line :: _ as headers) -> (
    match header_value headers "sec-websocket-key" with
    | None -> false
    | Some key ->
      let accept = base64 (sha1 (key ^ websocket_guid)) in
      Printf.fprintf oc
        "HTTP/1.1 101 Switching Protocols\r\n\
         Upgrade: websocket\r\n\
         Connection: Upgrade\r\n\
         Sec-WebSocket-Accept: %s\r\n\r\n"
        accept;
      flush oc;
      true)
  | Some [] -> false

(* --- frame codec --- *)

let read_exact ic n =
  let b = Bytes.create n in
  really_input ic b 0 n;
  Bytes.unsafe_to_string b

(* Read one client frame. `Text/`Cont carry (payload, fin) — browsers
   fragment large messages, so callers must accumulate `Cont payloads
   until fin is true. Also returns [`Close | `Ping s | `Pong | `Skip]
   or `Eof. *)
let read_frame ic =
  match read_exact ic 2 with
  | exception End_of_file -> `Eof
  | hdr ->
    let b0 = Char.code hdr.[0] and b1 = Char.code hdr.[1] in
    let fin = b0 land 0x80 <> 0 in
    let opcode = b0 land 0x0f in
    let masked = b1 land 0x80 <> 0 in
    let len0 = b1 land 0x7f in
    let len =
      if len0 < 126 then len0
      else if len0 = 126 then
        let e = read_exact ic 2 in
        (Char.code e.[0] lsl 8) lor Char.code e.[1]
      else
        let e = read_exact ic 8 in
        Int64.to_int
          (Bytes.get_int64_be (Bytes.of_string e) 0)
    in
    let mask = if masked then read_exact ic 4 else "" in
    let payload = if len > 0 then read_exact ic len else "" in
    let payload =
      if masked then
        String.init len (fun i ->
            Char.chr
              (Char.code payload.[i]
              lxor Char.code mask.[i land 3]))
      else payload
    in
    (match opcode with
     | 0x1 -> `Text (payload, fin)
     | 0x0 -> `Cont (payload, fin)
     | 0x8 -> `Close
     | 0x9 -> `Ping payload
     | 0xA -> `Pong
     | _ -> `Skip)

let write_frame oc ?(opcode = 1) s =
  let len = String.length s in
  let hdr =
    if len < 126 then
      String.init 2 (fun i -> if i = 0 then Char.chr (0x80 lor opcode) else Char.chr len)
    else if len <= 0xffff then
      String.init 4 (fun i ->
          match i with
          | 0 -> Char.chr (0x80 lor opcode)
          | 1 -> '\x7e'
          | 2 -> Char.chr (len lsr 8)
          | _ -> Char.chr (len land 0xff))
    else begin
      let b = Bytes.create 10 in
      Bytes.set b 0 (Char.chr (0x80 lor opcode));
      Bytes.set b 1 '\x7f';
      Bytes.set_int64_be b 2 (Int64.of_int len);
      Bytes.unsafe_to_string b
    end
  in
  output_string oc hdr;
  output_string oc s;
  flush oc
