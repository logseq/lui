(* End-to-end latency runner: executes every scenario and prints a
   markdown table — `dune exec platform/native/latency/main.exe`.
   [--small] runs the reduced-size variant the regression suite uses. *)

open Lui_latency

let () =
  let small =
    Array.exists (fun a -> a = "--small" || a = "-s") Sys.argv
  in
  let rows = Scenarios.all ~scale_sizes:small () in
  print_string (Scenarios.to_markdown rows)
