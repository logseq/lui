(* Pixel parity of the CPU renderer and the Metal renderer over the
   glass corpus: Lui_raster's BGRA frame against Lui_metal's readback,
   compared under each scene's expectation. The effect bodies the
   corpus carries are read here as MSL — the same single source the
   GL frontend reads as GLSL — so no per-name translation is needed.
   Where there is no Metal device the suite skips. *)

open Lui_parity.Parity

let check_scene (r : Lui_metal.t) name (s : Lui_scene.t) expect =
  Lui_metal.render r s;
  let gpu = Lui_metal.read_frame r ~w:s.Lui_scene.width ~h:s.Lui_scene.height in
  let cpu = (Lui_raster.render ~scene:s ()).Lui_raster.Image.pix in
  let d =
    diff_frames ~w:s.Lui_scene.width ~h:s.Lui_scene.height ~cpu ~gpu ()
  in
  let line = report name d in
  Printf.printf "%s\n%!" line;
  match expect with
  | Exact -> Alcotest.(check int) line 0 d.pixels
  | Within (tol, why) ->
      Alcotest.(check bool)
        (Printf.sprintf "%s — within ±%d: %s" line tol why)
        true (d.max_delta <= tol)
  | Loose (tol, cap, cnt, why) ->
      Alcotest.(check bool)
        (Printf.sprintf
           "%s — within ±%d save %d boundary pixels at up to ±%d: %s"
           line tol cnt cap why)
        true (d.max_delta <= cap && d.beyond2 <= cnt)
  | Known why ->
      Alcotest.(check bool)
        (Printf.sprintf "%s — documented divergence expected: %s" line why)
        true (d.pixels > 0)

let test_parity (r : Lui_metal.t) =
  List.iter
    (fun (name, build, expect) -> check_scene r name (build ()) expect)
    Lui_parity_glass.Parity_glass.corpus

let () =
  match Lui_metal.init_offscreen ~w:128 ~h:128 with
  | Error e -> Printf.eprintf "lui_metal glass tests skipped: %s\n" e
  | Ok r ->
      at_exit (fun () -> Lui_metal.release r);
      Alcotest.run "lui_parity_glass_metal"
        [ ( "scenes",
            [ Alcotest.test_case "glass corpus" `Slow (fun () -> test_parity r) ] ) ]
