(* Discovers every *.json under ../scenarios (copied into the build
   tree by the dune "deps" clause) and runs each as one alcotest case,
   so adding a scenario file is the whole workflow. *)

let scenario_dir = "../scenarios"

let is_scenario f = Filename.check_suffix f ".json"

let virtual_window_event_payload () =
  let module Scenario = Lui_e2e_json.E2e_json_scenario in
  List.iter (fun (node, generation, first, last, pins) ->
    let event = Lui_protocol.VirtualWindow (node, generation, first, last, pins) in
    let expected = `Assoc
      [ "kind", `String "virtual-window"; "node", `Int node;
        "generation", `Int generation; "first", `Int first; "last", `Int last;
        "pins", `List (List.map (fun node -> `Int node) pins) ] in
    List.iter (fun actual ->
      Alcotest.(check string) "typed window payload preserves every integer field"
        (Yojson.Safe.to_string expected) (Yojson.Safe.to_string actual))
      [Scenario.event_json event; Scenario.action_json (Lui_window.Dispatch event)])
    [42, 7, 50_000, 50_009, [17; 23]; 3, 1, 0, 0, []]

let () =
  let files =
    Sys.readdir scenario_dir |> Array.to_list
    |> List.filter is_scenario |> List.sort String.compare
  in
  if files = [] then
    failwith (Printf.sprintf "no scenarios found in %s" scenario_dir);
  Alcotest.run "e2e_json"
    [ ("event serialization", [Alcotest.test_case "virtual window payload" `Quick
        virtual_window_event_payload]);
      ( "scenarios"
      , List.map
          (fun f ->
            Alcotest.test_case f `Quick (fun () ->
                Lui_e2e_json.E2e_json_scenario.run_file
                  (Filename.concat scenario_dir f)))
          files ) ]
