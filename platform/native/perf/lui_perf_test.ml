(* Regression bounds for the perf suite. Two kinds:

   - structural: machine-independent invariants (a scrolled virtual
     list only renders the viewport's worth of rows; one color flip
     damages a handful of rects; damage-limited raster is not slower
     than a full pass).
   - absolute: generous wall-clock ceilings, ~3x the values measured
     on the reference machine (see PERF.md) so ordinary dev machines
     and CI variance stay green; never tight. *)

open Lui_perf
module H = Harness

let height = 800

(* Look a metric's value up in the scenario table. *)
let find rows ~scenario ~metric =
  match
    List.find_opt
      (fun (r : Scenarios.row) -> r.scenario = scenario && r.metric = metric)
      rows
  with
  | Some r -> float_of_string r.value
  | None -> Alcotest.failf "no row %s / %s" scenario metric

(* Small-suite rows, shared by every check so the suite runs once. *)
let rows = lazy (Scenarios.all ~scale_sizes:true ())

(* ---------- structural ---------- *)

let test_visible_window () =
  let rows = Lazy.force rows in
  let visible = find rows ~scenario:"vlist-10k" ~metric:"visible children" in
  let capacity = float_of_int height /. 28. +. 2. in
  Alcotest.(check bool) "visible bounded" true
    (visible > 0. && visible <= capacity);
  (* The milestone's structural bound: 10k logical rows mount only the
     viewport + overscan — nowhere near the item count. *)
  let mounted = find rows ~scenario:"vlist-10k" ~metric:"mounted rows" in
  Alcotest.(check bool) "mounted bounded" true
    (mounted > 0. && mounted <= 200.);
  let ops = find rows ~scenario:"vlist-10k" ~metric:"scene ops/frame" in
  Alcotest.(check bool) "ops emitted" true (ops > visible)

let test_damage_bounded () =
  let rows = Lazy.force rows in
  let rects = find rows ~scenario:"damage-5k" ~metric:"damaged rects" in
  Alcotest.(check bool) "damage is small" true (rects >= 1. && rects <= 64.);
  let limited = find rows ~scenario:"damage-5k" ~metric:"damaged raster p50" in
  let full = find rows ~scenario:"damage-5k" ~metric:"full raster p50" in
  Alcotest.(check bool) "damage not slower" true (limited <= full *. 3. +. 5.)

(* ---------- absolute bounds (generous: ~3x measured, see PERF.md) ---------- *)

let bound scenario metric ceiling =
  let rows = Lazy.force rows in
  let v = find rows ~scenario ~metric in
  Alcotest.(check bool)
    (Printf.sprintf "%s %s < %gms" scenario metric ceiling)
    true (v <= ceiling)

let test_frame_bounds () =
  (* Ceilings are ~3x the small-suite values measured on the reference
     machine (PERF.md): vlist frame ~280ms, first frame ~40ms, text
     stages <10ms, flip apply ~0ms, the 20k mount apply ~4.3s. *)
  bound "vlist-10k" "frame total p50" 1000.;
  bound "first-frame-10k" "total" 500.;
  bound "text-500" "layout+measure" 50.;
  bound "text-500" "paint+shape" 50.;
  bound "damage-5k" "flip apply p50" 50.;
  bound "rss-100k" "patch apply" 15000.

let () =
  Alcotest.run "lui_perf"
    [
      ( "structure",
        [
          Alcotest.test_case "visible window" `Slow test_visible_window;
          Alcotest.test_case "damage limited" `Slow test_damage_bounded;
        ] );
      ( "bounds",
        match Sys.getenv_opt "GITHUB_ACTIONS" with
        (* Stage ceilings are calibrated to a reference machine; shared
           CI runners are several times slower and bounce, so bound
           checks are meaningless there. *)
        | Some _ -> []
        | None -> [ Alcotest.test_case "stage ceilings" `Slow test_frame_bounds ] );
    ]
