(* Loopback tests for lui_plugin_fetch: a real python HTTP server on
   127.0.0.1 exercises the full JSON service contract — methods,
   arbitrary headers, bodies, redirect following and status codes.

   The transport is libcurl via dlopen; when libcurl or python3 is
   absent the e2e cases report themselves skipped. *)

module F = Lui_plugin_fetch
module P = Lui_plugin

let check = Alcotest.check
let bool = Alcotest.bool
let int = Alcotest.int
let string = Alcotest.string

(* ---- python server plumbing (same pattern as lui_updater) ---- *)

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
  match
    Unix.connect s (Unix.ADDR_INET (Unix.inet_addr_loopback, port))
  with
  | () ->
    Unix.close s;
    true
  | exception _ ->
    Unix.close s;
    false

(* [with_server f] spawns the echo server and calls [f base_url]. *)
let with_server f () =
  match python_bin () with
  | None -> Printf.printf "python3 not found, skipping\n%!"
  | Some python ->
    let port = free_port () in
    let devnull = Unix.openfile "/dev/null" [ Unix.O_RDWR ] 0 in
    let pid =
      Unix.create_process python
        [| python; "fetch_test_server.py"; string_of_int port |]
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
      (fun () -> f (Printf.sprintf "http://127.0.0.1:%d" port))

(* ---- service calls through the plugin registry ---- *)

let request json = P.call ~service:"plugin:fetch" ~method_:"request" json

let response_fields reply =
  let j = Yojson.Safe.from_string reply in
  let open Yojson.Safe.Util in
  let status = j |> member "status" |> to_int in
  let error = j |> member "error" |> to_string in
  let body =
    match F.Private.b64_decode (j |> member "body_base64" |> to_string) with
    | Ok b -> b
    | Error e -> Alcotest.fail e
  in
  let headers =
    j |> member "headers" |> to_list
    |> List.filter_map (function
         | `List [ `String k; `String v ] -> Some (k, v)
         | _ -> None)
  in
  (status, error, headers, body)

let must_call json =
  match request json with
  | Error e -> Alcotest.fail e
  | Ok reply -> response_fields reply

(* ---- cases ---- *)

let test_get base =
  let status, error, headers, body =
    must_call (Printf.sprintf {|{"url":"%s/get"}|} base)
  in
  check int "status" 200 status;
  check string "no error" "" error;
  check string "body" "lui fetch test body\n" body;
  check bool "server header" true
    (List.exists
       (fun (k, v) ->
         String.lowercase_ascii k = "x-test-server" && v = "lui-fetch-test")
       headers)

let test_post_echo base =
  let payload =
    Yojson.Safe.to_string
      (`Assoc
        [
          ("url", `String (base ^ "/echo"));
          ("method", `String "POST");
          ("headers", `Assoc [ ("X-Custom-Header", `String "lui-1") ]);
          ("body", `String "hello=42&x=y");
        ])
  in
  let status, _, _, body = must_call payload in
  check int "status" 200 status;
  let j = Yojson.Safe.from_string body in
  let open Yojson.Safe.Util in
  check string "method" "POST" (j |> member "method" |> to_string);
  check string "echoed body" "hello=42&x=y" (j |> member "body" |> to_string);
  check bool "custom header arrived" true
    (j |> member "headers" |> to_list
    |> List.exists (function
         | `List [ `String "X-Custom-Header"; `String "lui-1" ] -> true
         | _ -> false))

let test_redirect base =
  let status, _, _, body =
    must_call
      (Printf.sprintf {|{"url":"%s/redirect_chain","redirect":true}|} base)
  in
  check int "status after redirects" 200 status;
  check string "final body" "lui fetch test body\n" body

let test_no_redirect base =
  let status, _, _, _ =
    must_call
      (Printf.sprintf {|{"url":"%s/redirect","redirect":false}|} base)
  in
  check int "302 kept" 302 status

let test_status_passthrough base =
  let status, error, _, _ =
    must_call (Printf.sprintf {|{"url":"%s/status/404"}|} base)
  in
  check int "404 passed through" 404 status;
  check string "404 not an error" "" error

let test_transport_error () =
  let status, error, _, _ =
    must_call
      {|{"url":"http://127.0.0.1:1/unreachable","timeout_ms":2000}|}
  in
  check int "status 0" 0 status;
  check bool "error populated" true (error <> "")

let test_bad_args () =
  match request {|{"method":"GET"}|} with
  | Error _ -> ()
  | Ok _ -> Alcotest.fail "missing url must be an error"

let () =
  P.reset ();
  (match P.use [ F.plugin ] with
   | Ok () -> ()
   | Error e -> Alcotest.fail e);
  if F.available () then
    Alcotest.run "lui_plugin_fetch"
      [
        ( "loopback",
          [
            Alcotest.test_case "get" `Quick (with_server test_get);
            Alcotest.test_case "post echo" `Quick
              (with_server test_post_echo);
            Alcotest.test_case "redirect" `Quick (with_server test_redirect);
            Alcotest.test_case "no redirect" `Quick
              (with_server test_no_redirect);
            Alcotest.test_case "status passthrough" `Quick
              (with_server test_status_passthrough);
            Alcotest.test_case "transport error" `Quick test_transport_error;
            Alcotest.test_case "bad args" `Quick test_bad_args;
          ] );
      ]
  else begin
    Printf.printf "libcurl unavailable, e2e skipped\n%!";
    Alcotest.run "lui_plugin_fetch"
      [ ("skip", [ Alcotest.test_case "no libcurl" `Quick (fun () -> ()) ]) ]
  end
