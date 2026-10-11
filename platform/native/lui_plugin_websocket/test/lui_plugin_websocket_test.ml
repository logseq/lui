(* Tests for lui_plugin_websocket. Unit cases cover the handshake
   math and frame codec; the e2e cases spawn a real python websocket
   echo server and drive the full JSON service contract through
   Lui_plugin.call — real frame round-trips both ways, plus the
   close handshake. *)

module W = Lui_plugin_websocket
module P = Lui_plugin

let check = Alcotest.check
let bool = Alcotest.bool
let int = Alcotest.int
let string = Alcotest.string

(* ---- unit: handshake math + framing ---- *)

(* RFC 6455 worked example. *)
let test_accept_vector () =
  check string "accept key" "s3pPLMBiTxaQ9kYGzzhZRbK+xOo="
    (W.Private.accept_key "dGhlIHNhbXBsZSBub25jZQ==")

let test_sha1 () =
  let hex digest =
    String.concat ""
      (List.init (String.length digest) (fun i ->
           Printf.sprintf "%02x" (Char.code digest.[i])))
  in
  check string "sha1 abc" "a9993e364706816aba3e25717850c26c9cd0d89d"
    (hex (W.Private.sha1 "abc"))

let test_frame_encode () =
  let frame = W.Private.encode_frame ~mask:true ~opcode:0x1 "hi" in
  check int "fin+opcode" 0x81 (Char.code frame.[0]);
  check bool "masked" true (Char.code frame.[1] land 0x80 <> 0);
  check int "len" 2 (Char.code frame.[1] land 0x7f);
  let mask = String.sub frame 2 4 in
  check string "masked payload" "hi"
    (String.init 2 (fun i ->
         Char.chr (Char.code frame.[6 + i] lxor Char.code mask.[i])));
  let unmasked = W.Private.encode_frame ~mask:false ~opcode:0x2 "x" in
  check int "binary opcode" 0x82 (Char.code unmasked.[0]);
  check int "unmasked flag" 0 (Char.code unmasked.[1] land 0x80)

(* ---- e2e plumbing (same pattern as lui_updater) ---- *)

let free_port () =
  let sock = Unix.socket Unix.PF_INET Unix.SOCK_STREAM 0 in
  Unix.bind sock (Unix.ADDR_INET (Unix.inet_addr_loopback, 0));
  let port =
    match Unix.getsockname sock with
    | Unix.ADDR_INET (_, p) -> p
    | _ -> assert false
  in
  Unix.close sock;
  port

let python_bin () =
  List.find_opt
    (fun name ->
      let ic =
        Unix.open_process_in ("command -v " ^ name ^ " 2>/dev/null")
      in
      let line = try input_line ic with End_of_file -> "" in
      ignore (Unix.close_process_in ic);
      line <> "")
    [ "python3"; "python" ]

let server_ready port =
  let s = Unix.socket Unix.PF_INET Unix.SOCK_STREAM 0 in
  match Unix.connect s (Unix.ADDR_INET (Unix.inet_addr_loopback, port)) with
  | () ->
    Unix.close s;
    true
  | exception _ ->
    Unix.close s;
    false

let with_server f () =
  match python_bin () with
  | None -> Printf.printf "python3 not found, skipping\n%!"
  | Some python ->
    let port = free_port () in
    let devnull = Unix.openfile "/dev/null" [ Unix.O_RDWR ] 0 in
    let pid =
      Unix.create_process python
        [| python; "ws_echo_server.py"; string_of_int port |]
        devnull devnull devnull
    in
    Unix.close devnull;
    let deadline = Unix.gettimeofday () +. 5.0 in
    while (not (server_ready port)) && Unix.gettimeofday () < deadline do
      Unix.sleepf 0.05
    done;
    if not (server_ready port) then Alcotest.fail "server did not start";
    Fun.protect
      ~finally:(fun () ->
        (try Unix.kill pid Sys.sigterm with _ -> ());
        ignore (Unix.waitpid [] pid))
      (fun () -> f port)

(* ---- service helpers ---- *)

let call method_ payload =
  P.call ~service:"plugin:websocket" ~method_ payload

let conn_open port =
  match
    call "open"
      (Printf.sprintf {|{"url":"ws://127.0.0.1:%d/"}|} port)
  with
  | Error e -> Alcotest.fail e
  | Ok reply -> (
    let j = Yojson.Safe.from_string reply in
    let open Yojson.Safe.Util in
    match j |> member "conn_id" with
    | `Int n -> n
    | _ -> Alcotest.fail "no conn_id")

let conn_send id opcode data =
  let b64 = W.Private.b64_encode data in
  match
    call "send"
      (Printf.sprintf
         {|{"conn_id":%d,"opcode":%d,"payload_b64":"%s"}|} id opcode
         b64)
  with
  | Ok _ -> ()
  | Error e -> Alcotest.fail e

let events_of reply =
  let j = Yojson.Safe.from_string reply in
  let open Yojson.Safe.Util in
  j |> member "events" |> to_list

(* Poll until a predicate matches an event or the deadline passes. *)
let rec poll_until id pred deadline =
  match call "poll" (Printf.sprintf {|{"conn_id":%d}|} id) with
  | Error e -> Alcotest.fail e
  | Ok reply ->
    let evs = events_of reply in
    if List.exists pred evs then evs
    else if Unix.gettimeofday () > deadline then
      Alcotest.fail "timed out waiting for event"
    else begin
      Unix.sleepf 0.02;
      poll_until id pred deadline
    end

let is_message j =
  let open Yojson.Safe.Util in
  match j |> member "kind" with `String "message" -> true | _ -> false

let is_close j =
  let open Yojson.Safe.Util in
  match j |> member "kind" with `String "close" -> true | _ -> false

let deadline s = Unix.gettimeofday () +. s

(* A local decoder — deliberately not the library's, so the e2e
   base64 path is checked independently. *)
let b64_decode s =
  let tbl = Array.make 256 (-1) in
  String.iteri
    (fun i c -> tbl.(Char.code c) <- i)
    "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
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
  if !ok then Ok (Buffer.contents b) else Error "bad base64"

let b64_field j name =
  let open Yojson.Safe.Util in
  match b64_decode (j |> member name |> to_string) with
  | Ok d -> d
  | Error e -> Alcotest.fail e

(* ---- e2e cases ---- *)

let test_echo port =
  let id = conn_open port in
  conn_send id 1 "hello websocket";
  let evs = poll_until id is_message (deadline 5.0) in
  let msg = List.find is_message evs in
  let open Yojson.Safe.Util in
  check string "opcode" "text" (msg |> member "opcode" |> to_string);
  check string "echoed" "hello websocket" (b64_field msg "data")

let test_binary_echo port =
  let id = conn_open port in
  let payload = "\x00\x01\x02\xff\xfe binary" in
  conn_send id 2 payload;
  let evs = poll_until id is_message (deadline 5.0) in
  let msg = List.find is_message evs in
  let open Yojson.Safe.Util in
  check string "opcode" "binary" (msg |> member "opcode" |> to_string);
  check string "binary echoed" payload (b64_field msg "data")

let test_large_echo port =
  let id = conn_open port in
  (* Exercises the 16-bit extended payload length both ways. *)
  let payload = String.make 1000 'x' ^ "end" in
  conn_send id 1 payload;
  let evs = poll_until id is_message (deadline 5.0) in
  let msg = List.find is_message evs in
  check string "large echoed" payload (b64_field msg "data")

let test_close_handshake port =
  let id = conn_open port in
  (match
     call "close" (Printf.sprintf {|{"conn_id":%d,"code":1000}|} id)
   with
   | Ok _ -> ()
   | Error e -> Alcotest.fail e);
  (* The peer's echoed close frame was drained during close(); the
     event is delivered by the next poll. *)
  let evs = poll_until id is_close (deadline 5.0) in
  let cl = List.find is_close evs in
  let open Yojson.Safe.Util in
  check int "close code" 1000 (cl |> member "code" |> to_int)

let test_open_refused () =
  match
    call "open"
      {|{"url":"ws://127.0.0.1:1/","timeout_ms":2000}|}
  with
  | Error _ -> ()
  | Ok _ -> Alcotest.fail "open on a dead port must fail"

let test_bad_scheme () =
  match call "open" {|{"url":"wss://example.com/"}|} with
  | Error _ -> ()
  | Ok _ -> Alcotest.fail "wss must be rejected"

let () =
  P.reset ();
  (match P.use [ W.plugin ] with
   | Ok () -> ()
   | Error e -> Alcotest.fail e);
  Alcotest.run "lui_plugin_websocket"
    [
      ( "codec",
        [
          Alcotest.test_case "sha1" `Quick test_sha1;
          Alcotest.test_case "accept vector" `Quick test_accept_vector;
          Alcotest.test_case "frame encode" `Quick test_frame_encode;
        ] );
      ( "loopback",
        [
          Alcotest.test_case "text echo" `Quick (with_server test_echo);
          Alcotest.test_case "binary echo" `Quick
            (with_server test_binary_echo);
          Alcotest.test_case "large echo" `Quick
            (with_server test_large_echo);
          Alcotest.test_case "close handshake" `Quick
            (with_server test_close_handshake);
          Alcotest.test_case "open refused" `Quick test_open_refused;
          Alcotest.test_case "wss rejected" `Quick test_bad_scheme;
        ] );
    ]
