(* Perf runner: executes every scenario and prints a markdown table —
   `dune exec platform/native/perf/main.exe`. [--small] runs the
   reduced-size variant the alcotest suite uses. *)

open Lui_perf

let () =
  let small =
    Array.exists (fun a -> a = "--small" || a = "-s") Sys.argv
  in
  let rows = Scenarios.all ~scale_sizes:small () in
  print_string (Scenarios.to_markdown rows)
