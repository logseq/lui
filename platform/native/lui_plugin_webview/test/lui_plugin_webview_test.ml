(* JSON-contract tests for the webview service. Window-bound paths are
   covered by lui_webview's own macOS suite; here we verify the
   registry plumbing, id handling and error shapes — all display-free. *)

let svc = "plugin:webview"

let call meth payload =
  Lui_plugin.call ~service:svc ~method_:meth payload

let test_register () =
  Lui_plugin.reset ();
  match Lui_plugin.use [ Lui_plugin_webview.plugin ] with
  | Error e -> Alcotest.fail e
  | Ok () ->
    Alcotest.(check bool) "bound" true
      (List.mem svc (Lui_plugin.names ()))

let test_bad_json () =
  match call "state" "not json" with
  | Error e ->
    Alcotest.(check bool) "invalid JSON" true
      (String.length e > 0)
  | Ok _ -> Alcotest.fail "expected error"

let test_unknown_id () =
  match call "destroy" {|{"id": 999}|} with
  | Error e -> Alcotest.(check bool) "no webview" true (e <> "")
  | Ok _ -> Alcotest.fail "expected error"

let test_missing_id () =
  match call "navigate" {|{"url": "https://example.com"}|} with
  | Error e -> Alcotest.(check bool) "missing id" true (e <> "")
  | Ok _ -> Alcotest.fail "expected error"

let test_nav_bad_op () =
  match call "navigate" {|{"id": 1, "op": "sideways"}|} with
  (* Unknown id is reported before the op is checked. *)
  | Error e -> Alcotest.(check bool) "error" true (e <> "")
  | Ok _ -> Alcotest.fail "expected error"

let test_create_empty_payload () =
  (* No window exists in the test process; create must fail with a
     host error, not crash. *)
  match call "create" {|{"x":0,"y":0,"w":10,"h":10}|} with
  | Error e -> Alcotest.(check bool) "host error" true (e <> "")
  | Ok r ->
    (* If a display-less host still created a view, clean it up. *)
    (match Yojson.Safe.from_string r |> Yojson.Safe.Util.member "id" with
     | `Int n ->
       ignore
         (call "destroy" (Printf.sprintf {|{"id": %d}|} n));
       Alcotest.fail "create unexpectedly succeeded"
     | _ -> ())

let test_b64 () =
  Alcotest.(check string) "b64" "aGVsbG8="
    (Lui_plugin_webview.Private.b64_encode "hello")

let () =
  Alcotest.run "lui_plugin_webview"
    [ ( "service",
        [ Alcotest.test_case "register" `Quick test_register;
          Alcotest.test_case "bad json" `Quick test_bad_json;
          Alcotest.test_case "unknown id" `Quick test_unknown_id;
          Alcotest.test_case "missing id" `Quick test_missing_id;
          Alcotest.test_case "nav bad op" `Quick test_nav_bad_op;
          Alcotest.test_case "create no host" `Quick
            test_create_empty_payload;
          Alcotest.test_case "b64" `Quick test_b64 ] ) ]
