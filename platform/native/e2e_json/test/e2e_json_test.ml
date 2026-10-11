(* Discovers every *.json under ../scenarios (copied into the build
   tree by the dune "deps" clause) and runs each as one alcotest case,
   so adding a scenario file is the whole workflow. *)

let scenario_dir = "../scenarios"

let is_scenario f = Filename.check_suffix f ".json"

let () =
  let files =
    Sys.readdir scenario_dir |> Array.to_list
    |> List.filter is_scenario |> List.sort String.compare
  in
  if files = [] then
    failwith (Printf.sprintf "no scenarios found in %s" scenario_dir);
  Alcotest.run "e2e_json"
    [ ( "scenarios"
      , List.map
          (fun f ->
            Alcotest.test_case f `Quick (fun () ->
                Lui_e2e_json.E2e_json_scenario.run_file
                  (Filename.concat scenario_dir f)))
          files ) ]
