(* Tests for Lui_plugin: name validation, duplicate/reserved
   rejection, dispatch, setup unwind, and a JSON round-trip through a
   bound service. The registry is process-global, so every case runs
   under a reset. *)

module P = Lui_plugin

let check = Alcotest.check
let bool = Alcotest.bool
let ok_unit = Alcotest.(result unit string)
let ok_string = Alcotest.(result string string)

let with_reset f () =
  P.reset ();
  f ();
  P.reset ()

let echo_service payload =
  match Yojson.Safe.from_string payload with
  | `Assoc fields ->
    let reply =
      `Assoc
        (fields
         @ [ ("echoed", `Bool true) ])
    in
    Ok (Yojson.Safe.to_string reply)
  | _ -> Error "want a JSON object"
  | exception Yojson.Json_error m -> Error m

let test_name_validation () =
  let bad_names =
    [ ""; "Fetch"; "1abc"; "-x"; "a_b"; "a.b"; "a b"; "a/b" ]
  in
  List.iter
    (fun n ->
      match P.use [ P.v n [] ] with
      | Error _ -> ()
      | Ok () -> Alcotest.failf "name %S should be rejected" n)
    bad_names;
  List.iter
    (fun n ->
      check ok_unit ("name " ^ n) (Ok ()) (P.use [ P.v n [] ]))
    [ "a"; "fetch"; "ws-2"; "a1-b2" ]

let test_reserved_name () =
  match P.use [ P.v "lui" [] ] with
  | Error _ -> ()
  | Ok () -> Alcotest.fail "reserved name 'lui' must be rejected"

let test_duplicate_detection () =
  let p = P.v "dup" [ ("m", fun _ -> Ok "{}") ] in
  (* Same name twice inside one batch is rejected. *)
  (match P.use [ p; P.v "dup" [] ] with
   | Error _ -> ()
   | Ok () -> Alcotest.fail "in-batch duplicate not rejected");
  check ok_unit "first bind" (Ok ()) (P.use [ p ]);
  (* The identical descriptor is an idempotent no-op. *)
  check ok_unit "idempotent re-use" (Ok ()) (P.use [ p ]);
  (* A different descriptor under the same name is rejected. *)
  match P.use [ P.v "dup" [] ] with
  | Error _ -> ()
  | Ok () -> Alcotest.fail "conflicting re-registration not rejected"

let test_dispatch_and_unknown_method () =
  let p = P.v "echo" [ ("echo", echo_service) ] in
  check ok_unit "bind" (Ok ()) (P.use [ p ]);
  check ok_string "dispatch via canonical name"
    (Ok {|{"a":1,"echoed":true}|})
    (P.call ~service:"plugin:echo" ~method_:"echo" {|{"a":1}|});
  (* Bare name resolves too. *)
  check bool "bare name resolves" true
    (Result.is_ok (P.call ~service:"echo" ~method_:"echo" "{}"));
  check bool "unknown method" true
    (Result.is_error
       (P.call ~service:"plugin:echo" ~method_:"nope" "{}"));
  check bool "unknown service" true
    (Result.is_error
       (P.call ~service:"plugin:missing" ~method_:"echo" "{}"));
  (* Handler errors surface as Error, handler raises are caught. *)
  check bool "handler error" true
    (Result.is_error
       (P.call ~service:"plugin:echo" ~method_:"echo" "not json"));
  check ok_unit "bind raiser" (Ok ())
    (P.use [ P.v "raiser" [ ("boom", fun _ -> raise Exit) ] ]);
  check bool "handler raise" true
    (Result.is_error
       (P.call ~service:"plugin:raiser" ~method_:"boom" "{}"))

let test_setup_failure_unwinds () =
  let torn_down = ref false in
  let first =
    P.v ~teardown:(fun () -> torn_down := true) "first"
      [ ("m", fun _ -> Ok "{}") ]
  in
  let failing =
    P.v
      ~setup:(fun () -> Error "cannot start")
      "failing" []
  in
  (match P.use [ first; failing ] with
   | Error _ -> ()
   | Ok () -> Alcotest.fail "setup failure must propagate");
  check bool "bound plugin torn down" true !torn_down;
  check bool "first unbound" false (P.mem ~service:"plugin:first");
  check bool "failing unbound" false (P.mem ~service:"plugin:failing");
  check (Alcotest.list Alcotest.string) "registry empty" []
    (P.names ())

let test_json_round_trip () =
  let svc =
    P.v "arith"
      [ ( "sum",
          fun payload ->
            match Yojson.Safe.from_string payload with
            | `Assoc _ as j ->
              let open Yojson.Safe.Util in
              let xs = j |> member "xs" |> to_list |> List.map to_int in
              Ok
                (Yojson.Safe.to_string
                   (`Assoc [ ("sum", `Int (List.fold_left ( + ) 0 xs)) ]))
            | _ -> Error "want object"
            | exception _ -> Error "bad request" );
      ]
  in
  check ok_unit "bind" (Ok ()) (P.use [ svc ]);
  match P.call ~service:"plugin:arith" ~method_:"sum" {|{"xs":[1,2,3]}|}
  with
  | Error e -> Alcotest.fail e
  | Ok reply ->
    let j = Yojson.Safe.from_string reply in
    let open Yojson.Safe.Util in
    check Alcotest.int "sum" 6 (j |> member "sum" |> to_int)

let () =
  Alcotest.run "lui_plugin"
    [ ( "registry",
        [ Alcotest.test_case "name validation" `Quick
            (with_reset test_name_validation);
          Alcotest.test_case "reserved name" `Quick
            (with_reset test_reserved_name);
          Alcotest.test_case "duplicates" `Quick
            (with_reset test_duplicate_detection);
          Alcotest.test_case "dispatch" `Quick
            (with_reset test_dispatch_and_unknown_method);
          Alcotest.test_case "setup unwind" `Quick
            (with_reset test_setup_failure_unwinds);
          Alcotest.test_case "json round-trip" `Quick
            (with_reset test_json_round_trip);
        ] );
    ]
