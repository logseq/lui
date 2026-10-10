(* Pixel parity of the CPU renderer and the Metal renderer over the
   shared scene corpus: Lui_raster's BGRA frame against Lui_metal's
   readback, compared under each scene's expectation. The Metal cases
   need a device — where there is none the suite skips. *)

open Lui_scene
open Lui_raster_testkit
open Lui_parity.Parity
open Testkit

(* {1 MSL effect twins}

   A scene's effect slot holds source in the renderer's own shading
   language: the corpus's effects carry GLSL for the GL renderer or
   the empty string, so here the same bodies are written in MSL (the
   effect signature also takes the backdrop texture — MSL functions
   cannot reach a bound texture the way GLSL can a uniform). Each is
   the line-for-line translation of the CPU twin, like the GLSL one. *)

let msl_test =
  "float4 effect(float2 p, Effect e, texture2d<float> bd) {\n\
   \  return float4(p.x / 100.0, p.y / 80.0, 0.6, 1.0);\n\
   }"

let msl_dim =
  "float4 effect(float2 p, Effect e, texture2d<float> bd) {\n\
   \  return float4(sampleBackdrop(bd, e, p) * 0.5, 1.0);\n\
   }"

let msl_tint =
  "float4 effect(float2 p, Effect e, texture2d<float> bd) {\n\
   \  return float4(e.p1.rgb * e.p1.a, 1.0);\n\
   }"

let msl_lens =
  "float4 effect(float2 p, Effect e, texture2d<float> bd) {\n\
   \  float d = max(8.0 + sdRoundRect(p, e.rect, e.radii), 0.0) * e.p0.x;\n\
   \  float3 c = sampleBackdrop(bd, e, float2(p.x + d, p.y));\n\
   \  return float4(c + (e.p1.rgb - c) * e.p1.a, 1.0);\n\
   }"

(* The MSL body of an effect, chosen by name like the renderer's
   built-in twins of the named test effects. *)
let msl_of = function
  | "testfx" | "pgrad" -> msl_test
  | "dim" | "pdim" -> msl_dim
  | "lens" | "plens" -> msl_lens
  | "tint" | "ptint" -> msl_tint
  | n -> invalid_arg ("no MSL twin for effect " ^ n)

let patch_effects (s : Lui_scene.t) =
  s.effects <-
    List.map
      (fun e -> { e with ee = { e.ee with eglsl = msl_of e.ee.ename } })
      s.effects

(* {1 The comparison} *)

let stats = ref []

(* One scene through both renderers, diffed under its expectation; a
   fresh Metal renderer keeps atlas tracking honest between unrelated
   scenes, as the shared suite does. *)
let check_scene (r : Lui_metal.t) name (s : Lui_scene.t) expect =
  Lui_metal.render r s;
  let gpu = Lui_metal.read_frame r ~w:s.width ~h:s.height in
  let cpu = (Lui_raster.render ~scene:s ()).Lui_raster.Image.pix in
  let d =
    diff_frames ~ignore:(margin_ignores s) ~w:s.width ~h:s.height ~cpu
      ~gpu ()
  in
  let line = report name d in
  stats := line :: !stats;
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

(* {1 Suites} *)

let test_parity (r : Lui_metal.t) =
  List.iter
    (fun (name, build, expect) ->
       let s = build () in
       patch_effects s;
       check_scene r name s expect)
    corpus

let test_determinism (r : Lui_metal.t) =
  (* The same scene rendered twice gives the same frame — atlas and
     image bookkeeping must not perturb the output. *)
  let s =
    scene ~w:96 ~h:64
      [ ifill ~radii:(radii 12.) ~bw:(uniform 2.) ~bc:black
          (rect 12.25 10.5 60. 40.) (color 37 99 235 255);
        ishadow ~blur:6. (rect 20. 30. 40. 20.) (color 0 0 0 160);
        ihole ~radii:(radii 4.) ~opacity:1. (rect 30. 34. 16. 12.) ]
  in
  Lui_metal.render r s;
  let a = Lui_metal.read_frame r ~w:96 ~h:64 in
  Lui_metal.render r s;
  let b = Lui_metal.read_frame r ~w:96 ~h:64 in
  Alcotest.(check bool) "frame repeat is stable" true (a = b)

let test_atlas_update (r : Lui_metal.t) =
  (* Growing an atlas between renders takes the incremental upload
     path (same generation, later version); the new glyph must show. *)
  let mask = Atlas.create ~bpp:1 ~w:64 ~h:32 in
  let src =
    Bytes.init 144 (fun i -> Char.chr (if (i / 12 + i mod 12) mod 2 = 0 then 255 else 0))
  in
  Atlas.put mask ~x:2 ~y:2 ~w:12 ~h:12 ~src ~stride:12;
  let mk n =
    scene ~w:64 ~h:32 ~mask
      ~glyphs:(List.init n (fun i ->
                   glyph ~x:(8. +. float i *. 20.) ~y:8. ~w:12. ~h:12.
                     ~u:2 ~v:2 ~uw:12 ~vh:12 black))
      [ iglyphs 0 n ]
  in
  check_scene r "atlas first" (mk 1) Exact;
  Atlas.put mask ~x:20 ~y:2 ~w:12 ~h:12 ~src ~stride:12;
  let s2 =
    scene ~w:64 ~h:32 ~mask
      ~glyphs:[ glyph ~x:8. ~y:8. ~w:12. ~h:12. ~u:2 ~v:2 ~uw:12 ~vh:12 black;
                glyph ~x:30. ~y:8. ~w:12. ~h:12. ~u:20 ~v:2 ~uw:12 ~vh:12
                  (color 200 30 30 255) ]
      [ iglyphs 0 2 ]
  in
  check_scene r "atlas updated" s2 Exact

(* {1 Entry} *)

let () =
  match Lui_metal.init_offscreen ~w:128 ~h:128 with
  | Error e ->
      (* No usable Metal device: report the suite as skipped rather
         than failed. *)
      Printf.eprintf "lui_metal tests skipped: %s\n" e
  | Ok r ->
      at_exit (fun () -> Lui_metal.release r);
      Alcotest.run "lui_metal"
        [ ( "render",
            [ Alcotest.test_case "parity corpus" `Quick (fun () -> test_parity r);
              Alcotest.test_case "determinism" `Quick (fun () -> test_determinism r);
              Alcotest.test_case "atlas update" `Quick (fun () -> test_atlas_update r) ] ) ]
