(* Regression suite for the e2e latency harness. Two kinds:

   - structural: machine-independent invariants (every scenario emits
     the full metric set; app-driven frames emit real patches; a
     scroll frame emits none; frame stamps are monotone).
   - absolute: generous wall-clock ceilings, ~3x the values measured
     on the reference machine (see LATENCY.md) so ordinary dev machines
     and CI variance stay green; never tight. *)

open Alcotest
open Lui_latency
module H = Harness

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

let test_metric_coverage () =
  let rows = Lazy.force rows in
  let wanted =
    [
      "action_to_patch p50";
      "patch_to_layout p50";
      "layout_to_scene p50";
      "scene_to_present p50";
      "dirty_to_present p50";
      "dirty_to_present p95";
      "signal_stabilize p50";
      "patch_apply p50";
      "patch ops p50";
    ]
  in
  List.iter
    (fun scenario ->
      List.iter
        (fun metric -> ignore (find rows ~scenario ~metric))
        wanted)
    [
      "typing";
      "toggle";
      "hover";
      "blocks-2k-text";
      "blocks-2k-insert";
      "vlist-10k-scroll";
      "collapse-expand";
      "ime-compose";
    ]

let test_patches_flow () =
  let rows = Lazy.force rows in
  let ops scenario = find rows ~scenario ~metric:"patch ops p50" in
  (* Action-driven scenarios must emit a real patch each frame. *)
  List.iter
    (fun scenario ->
      check bool (scenario ^ " patches") true (ops scenario >= 1.))
    [ "typing"; "toggle"; "hover"; "ime-compose" ];
  (* A single text edit stays a small patch — one SetProp, not a
     subtree rewrite. *)
  check bool "edit patch small" true (ops "blocks-2k-text" <= 8.);
  check bool "insert patch small" true (ops "blocks-2k-insert" <= 16.);
  (* Scroll emits no patch at all: the offset lives host-side. *)
  check bool "scroll patch-free" true (ops "vlist-10k-scroll" = 0.)

(* The frame pipeline is exercised end to end by the scenarios; this
   guards the harness itself: a typing frame must emit a patch and its
   stage stamps must be monotone from action to presented. *)
let test_frame_stamps () =
  let t = H.create ~width:640 ~height:480 ~scale:1. () in
  let app =
    Lui_app.create
      (H.backend t (Lui_protocol.generic_profile ()))
      Scenarios.Draft.initial Scenarios.Draft.update Scenarios.Draft.view
  in
  check bool "start" true (Lui_app.start app);
  check bool "initial flush" true (Lui_app.flush app);
  let fid = H.find_kind (H.store t) "text-field" in
  let s =
    H.run_frame t app ~act:(fun () ->
        ignore
          (Lui_app.dispatch_event app (Lui_protocol.TextChanged (fid, "abc"))))
  in
  check bool "patch emitted" true (s.H.patch_ops > 0);
  check bool "action <= stabilized" true (s.action <= s.stabilized);
  check bool "stabilized <= patch" true (s.stabilized <= s.patch_generated);
  check bool "patch <= applied" true (s.patch_generated <= s.backend_applied);
  check bool "applied <= layout" true (s.backend_applied <= s.layout_done);
  check bool "layout <= scene" true (s.layout_done <= s.scene_ready);
  check bool "scene <= present" true (s.scene_ready <= s.present_submitted);
  check bool "present <= presented" true (s.present_submitted <= s.presented)

(* ---------- absolute bounds (generous: ~3x measured, see LATENCY.md) ---------- *)

let bound scenario metric ceiling =
  let rows = Lazy.force rows in
  let v = find rows ~scenario ~metric in
  check bool
    (Printf.sprintf "%s %s < %gms" scenario metric ceiling)
    true (v <= ceiling)

let test_frame_bounds () =
  (* Ceilings are ~3x the small-suite values measured on the reference
     machine (LATENCY.md): tiny-tree scenarios ~0.1ms, 2k edit ~22ms,
     10k scroll ~9ms, collapse ~1ms. *)
  bound "typing" "dirty_to_present p50" 1.;
  bound "toggle" "dirty_to_present p50" 1.;
  bound "hover" "dirty_to_present p50" 1.;
  bound "ime-compose" "dirty_to_present p50" 1.;
  bound "blocks-2k-text" "dirty_to_present p50" 75.;
  bound "blocks-2k-insert" "dirty_to_present p50" 75.;
  bound "vlist-10k-scroll" "dirty_to_present p50" 75.;
  bound "collapse-expand" "dirty_to_present p50" 30.

let () =
  run "lui_latency"
    [
      ( "pipeline",
        [ test_case "typing frame stamps + patch" `Quick test_frame_stamps ] );
      ( "structure",
        [
          test_case "metric coverage" `Slow test_metric_coverage;
          test_case "patches flow" `Slow test_patches_flow;
        ] );
      ( "bounds",
        match Sys.getenv_opt "GITHUB_ACTIONS" with
        (* Stage ceilings are calibrated to a reference machine; shared
           CI runners are several times slower and bounce, so bound
           checks are meaningless there. *)
        | Some _ -> []
        | None -> [ test_case "stage ceilings" `Slow test_frame_bounds ] );
    ]
