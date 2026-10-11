(* Tests for the gamepad plugin service: a fake backend feeds the
   shared tracker and the JSON methods are checked over the plugin
   registry. *)

open Lui_gamepad

let fake_source queue =
  { Lui_gamepad.name = "fake";
    init = (fun () -> Ok ());
    refresh =
      (fun trk ->
        (* Drain the scripted frames: each element is applied to the
           tracker and its events returned. *)
        let out =
          List.concat_map
            (fun f -> f trk)
            !queue
        in
        queue := [];
        out) }

let frames = ref []

let connect id name st trk =
  tracker_connected trk { id; name; kind = Gamepad } st

let setup () =
  frames := [];
  Lui_plugin.reset ();
  Lui_gamepad.Private.set_source (fake_source frames);
  match Lui_plugin.use [ Lui_plugin_gamepad.plugin ] with
  | Ok () -> ()
  | Error e -> Alcotest.fail e

let call m payload =
  Lui_plugin.call ~service:"plugin:gamepad" ~method_:m payload

let test_list_and_events () =
  setup ();
  (* Queue a connect frame with one pressed button. *)
  frames :=
    [ connect 5 "Fake Pad"
        { pressed = [ A ]; axes = [ (Left_x, 0.25) ] } ];
  let ev = call "events" "{}" in
  (match ev with
   | Ok s ->
     let j = Yojson.Safe.from_string s in
     let open Yojson.Safe.Util in
     let evs = j |> member "events" |> to_list in
     (* Connected + initial Button press + initial axis reading *)
     Alcotest.(check int) "three events" 3 (List.length evs);
     Alcotest.(check string) "first type" "connected"
       (List.hd evs |> member "type" |> to_string);
     Alcotest.(check string) "name" "Fake Pad"
       (List.hd evs |> member "name" |> to_string);
     Alcotest.(check string) "button" "a"
       (List.nth evs 1 |> member "button" |> to_string);
     Alcotest.(check string) "axis" "leftx"
       (List.nth evs 2 |> member "axis" |> to_string)
   | Error e -> Alcotest.fail e);
  let lst = call "list" "{}" in
  (match lst with
   | Ok s ->
     let j = Yojson.Safe.from_string s in
     let open Yojson.Safe.Util in
     let cs = j |> member "controllers" |> to_list in
     Alcotest.(check int) "one controller" 1 (List.length cs);
     let c = List.hd cs in
     Alcotest.(check int) "id" 5 (c |> member "id" |> to_int);
     Alcotest.(check string) "kind" "gamepad"
       (c |> member "kind" |> to_string);
     Alcotest.(check string) "btn" "a"
       (c |> member "state" |> member "buttons" |> to_list
        |> List.hd |> to_string)
   | Error e -> Alcotest.fail e);
  (* state for that id *)
  (match call "state" {|{"id":5}|} with
   | Ok s ->
     let j = Yojson.Safe.from_string s in
     let open Yojson.Safe.Util in
     Alcotest.(check bool) "axis" true
       (Float.abs
          ((j |> member "axes" |> member "leftx" |> to_float) -. 0.25)
        < 1e-6)
   | Error e -> Alcotest.fail e);
  (* disconnect on the next frame *)
  frames := [ (fun trk -> tracker_disconnected trk 5) ];
  (match call "events" "{}" with
   | Ok s ->
     let j = Yojson.Safe.from_string s in
     let open Yojson.Safe.Util in
     let evs = j |> member "events" |> to_list in
     Alcotest.(check string) "type" "disconnected"
       (List.hd evs |> member "type" |> to_string);
     Alcotest.(check int) "id" 5
       (List.hd evs |> member "id" |> to_int)
   | Error e -> Alcotest.fail e);
  match call "state" {|{"id":5}|} with
  | Error _ -> ()
  | Ok _ -> Alcotest.fail "state should error for gone controller"

let test_map_and_bad_input () =
  setup ();
  (match call "map"
           {|{"mapping":"deadbeef,Pad,a:b0,platform:Linux,"}|} with
   | Ok s ->
     Alcotest.(check bool) "added" true
       (String.length s > 0)
   | Error e -> Alcotest.fail e);
  (match call "map" {|{"mapping":"not-a-mapping"}|} with
   | Error _ -> ()
   | Ok _ -> Alcotest.fail "bad mapping should error");
  (match call "list" "not json" with
   | Error _ -> ()
   | Ok _ -> Alcotest.fail "bad json should error");
  match Lui_plugin.call ~service:"plugin:gamepad" ~method_:"bogus" "{}"
  with
  | Error _ -> ()
  | Ok _ -> Alcotest.fail "unknown method should error"

let () =
  Alcotest.run "lui_plugin_gamepad"
    [ ( "service",
        [ Alcotest.test_case "list/events/state" `Quick
            test_list_and_events;
          Alcotest.test_case "map + errors" `Quick
            test_map_and_bad_input ] ) ]
