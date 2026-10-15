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
  Alcotest.(check bool) "offscreen renderer is ready" true (Lui_metal.ready r);
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

let test_frame_size_changes (r : Lui_metal.t) =
  List.iter
    (fun (w, h) ->
       check_scene r (Printf.sprintf "resized frame %dx%d" w h)
         (scene ~w ~h []) Exact;
       let outside_frame_rejected =
         try
           ignore (Lui_metal.read_frame r ~w:(w + 1) ~h);
           false
         with Failure _ -> true
       in
       Alcotest.(check bool) "readback respects current frame bounds"
         true outside_frame_rejected)
    [160, 144; 73, 61; 192, 160]

let test_retained_allocations r =
  let s = scene ~w:128 ~h:128
    (List.init 1000 (fun index ->
       ifill (rect (float (index mod 100)) (float (index / 100)) 2. 2.) black)) in
  Lui_metal.render r s;
  ignore (Lui_metal.read_frame r ~w:s.width ~h:s.height);
  let allocated = ref 0. in
  for _ = 1 to 20 do
    let before = Gc.minor_words () in
    Lui_metal.render r s;
    allocated := !allocated +. (Gc.minor_words () -. before) *. 8.;
    ignore (Lui_metal.read_frame r ~w:s.width ~h:s.height)
  done;
  let per_frame = !allocated /. 20. in
  Alcotest.(check bool)
    (Printf.sprintf "Retained Metal submission allocates %.0f bytes per frame" per_frame)
    true (per_frame < 8192.)

let test_retained_invalidation r =
  let image = new_image ~w:1 ~h:1 (Bytes.of_string "\255\000\000\255") in
  let s = scene ~w:32 ~h:32
    [iimage (rect 4. 4. 16. 16.) image (rect 0. 0. 1. 1.)] in
  check_scene r "retained image first" s Exact;
  for _ = 1 to 70 do
    Lui_metal.render r s;
    ignore (Lui_metal.read_frame r ~w:s.width ~h:s.height)
  done;
  Bytes.blit_string "\000\000\255\255" 0 image.ipix 0 4;
  image_changed image;
  check_scene r "retained image update after 70 frames" s Exact;
  s.ops <- [ifill (rect 8. 8. 16. 16.) black];
  touch s;
  check_scene r "retained display list update" s Exact;
  s.width <- 48;
  s.height <- 40;
  s.clear <- color 0 255 0 255;
  check_scene r "retained viewport and clear update" s Exact

let test_fill_budget r =
  let s = scene ~w:2880 ~h:1800
    (List.init 3 (fun _ -> ifill (rect 0. 0. 2880. 1800.) (color 245 245 245 255))) in
  for _ = 1 to 3 do
    Lui_metal.render r s;
    ignore (Lui_metal.read_frame r ~w:s.width ~h:s.height)
  done;
  let elapsed = Lui_metal.gpu_ms r in
  Alcotest.(check bool) (Printf.sprintf "solid frame GPU %.2fms fits 120 Hz budget" elapsed)
    true (elapsed > 0. && elapsed < 8.33)

let test_rounded_budget r =
  let s = scene ~w:2880 ~h:1800
    (List.init 3 (fun _ -> ifill ~radii:(radii 16.) (rect 0. 0. 2880. 1800.) (color 245 245 245 255))) in
  for _ = 1 to 3 do
    Lui_metal.render r s;
    ignore (Lui_metal.read_frame r ~w:s.width ~h:s.height)
  done;
  let elapsed = Lui_metal.gpu_ms r in
  Alcotest.(check bool) (Printf.sprintf "rounded frame GPU %.2fms fits 120 Hz budget" elapsed)
    true (elapsed > 0. && elapsed < 8.33)

let test_shadow_budget r =
  let s = scene ~w:2880 ~h:1800
    (List.init 2 (fun index ->
      ishadow ~cast:(rect 0. 0. 2880. 1800.) ~blur:20.
        (rect 0. (float (index + 1) *. 4.) 2880. 1800.) (color 0 0 0 64))) in
  for _ = 1 to 3 do
    Lui_metal.render r s;
    ignore (Lui_metal.read_frame r ~w:s.width ~h:s.height)
  done;
  let elapsed = Lui_metal.gpu_ms r in
  Alcotest.(check bool) (Printf.sprintf "outset shadow GPU %.2fms fits 120 Hz budget" elapsed)
    true (elapsed > 0. && elapsed < 8.33)

let test_native_chrome_budget r =
  let s = scene ~w:2880 ~h:1800
    [ishadow ~radii:(radii 12.) ~cast:(rect 0. 0. 2880. 1800.)
       ~blur:20. (rect 0. 8. 2880. 1800.) (color 0 0 0 26);
     ishadow ~radii:(radii 12.) ~cast:(rect 0. 0. 2880. 1800.)
       ~blur:20. (rect 0. 4. 2880. 1800.) (color 0 0 0 26);
     ifill (rect 0. 0. 2880. 1800.) (color 0 0 0 0)] in
  for _ = 1 to 5 do
    Lui_metal.render r s;
    ignore (Lui_metal.read_frame r ~w:s.width ~h:s.height)
  done;
  let elapsed = Lui_metal.gpu_ms r in
  Alcotest.(check bool) (Printf.sprintf "native chrome GPU %.2fms fits 120 Hz budget" elapsed)
    true (elapsed > 0. && elapsed < 8.33)

let test_captured_scene r =
  match Sys.getenv_opt "LUI_METAL_BENCH_SCENE" with
  | None -> ()
  | Some path ->
      let channel = open_in_bin path in
      let captured : Lui_scene.t = Fun.protect ~finally:(fun () -> close_in channel)
        (fun () -> Marshal.from_channel channel) in
      Printf.printf "capture: %dx%d, %d ops, %d glyphs\n%!"
        captured.width captured.height (List.length captured.ops) (List.length captured.glyphs);
      List.iter (function
        | Fill f when f.frect.w *. f.frect.h > 1000000. ->
            let a,b,c,d = f.fradii in
            Printf.printf "large fill: %.0f,%.0f %.0fx%.0f r=%g,%g,%g,%g cont=%b alpha=%d opacity=%g\n%!"
              f.frect.x f.frect.y f.frect.w f.frect.h a b c d f.fcontinuous f.fcolor.a f.fopacity
        | _ -> ()) captured.ops;
      let measure name keep =
        let s = {captured with ops=List.filter keep captured.ops} in
        for _ = 1 to 5 do
          Lui_metal.render r s;
          ignore (Lui_metal.read_frame r ~w:s.width ~h:s.height)
        done;
        let timings = Array.init 120 (fun _ ->
          Lui_metal.render r s;
          ignore (Lui_metal.read_frame r ~w:s.width ~h:s.height);
          Lui_metal.gpu_ms r) in
        Array.sort Float.compare timings;
        Printf.printf "capture %s: GPU p50=%.3f p95=%.3f ms\n%!" name timings.(60) timings.(114);
        timings.(114)
      in
      let full = measure "full" (fun _ -> true) in
      ignore (measure "without fills" (function Fill _ -> false | _ -> true));
      ignore (measure "without shadows" (function Shadow _ -> false | _ -> true));
      ignore (measure "without glyphs" (function Glyphs _ -> false | _ -> true));
      Alcotest.(check bool) "actual captured scene fits 120 Hz GPU budget" true (full <= 1000. /. 120.)

let test_modal_budget r =
  (* Preserve the expensive composition from the native search capture without
     storing graph content or requiring a local capture file. *)
  let frame = rect 0. 0. 2880. 1800. in
  let panel = rect 720. 180. 1440. 1200. in
  let mask = Atlas.create ~bpp:1 ~w:16 ~h:16 in
  Atlas.put mask ~x:0 ~y:0 ~w:16 ~h:16
    ~src:(Bytes.make 256 '\255') ~stride:16;
  let glyphs = List.init 640 (fun index ->
    glyph ~x:(760. +. float (index mod 40) *. 30.)
      ~y:(240. +. float (index / 40) *. 60.) ~w:16. ~h:24.
      ~u:0 ~v:0 ~uw:16 ~vh:16 black) in
  let rows = List.init 20 (fun index ->
    ifill ~cont:true ~radii:(radii 8.)
      (rect 752. (220. +. float index *. 54.) 1376. 48.)
      (color 240 240 240 255)) in
  let s = scene ~w:2880 ~h:1800 ~mask ~glyphs
    ([ ifill frame white;
       ishadow ~cast:frame ~blur:20. (rect 0. 8. 2880. 1800.)
         (color 0 0 0 26);
       ifill frame (color 0 0 0 128);
       ishadow ~cont:true ~radii:(radii 16.) ~cast:panel
         ~cradii:(radii 16.) ~ccont:true ~blur:20.
         (rect 720. 188. 1440. 1200.) (color 0 0 0 64);
       ifill ~cont:true ~radii:(radii 16.) panel white;
       ifill ~cont:true ~radii:(radii 16.) ~bw:(uniform 2.)
         ~bc:(color 180 180 180 255) panel transparent ]
     @ rows @ [iglyphs 0 640]) in
  let measure name scene =
    for _ = 1 to 5 do
      Lui_metal.render r scene;
      ignore (Lui_metal.read_frame r ~w:scene.width ~h:scene.height)
    done;
    let timings = Array.init 120 (fun _ ->
      Lui_metal.render r scene;
      ignore (Lui_metal.read_frame r ~w:scene.width ~h:scene.height);
      Lui_metal.gpu_ms r) in
    Array.sort Float.compare timings;
    Printf.printf "modal fixture %s GPU p50=%.3f p95=%.3f ms\n%!"
      name timings.(60) timings.(114);
    timings.(114)
  in
  let full = measure "full" s in
  if full > 1000. /. 120. then begin
    ignore (measure "without shadows"
      {s with ops=List.filter (function Shadow _ -> false | _ -> true) s.ops});
    ignore (measure "without fills"
      {s with ops=List.filter (function Fill _ -> false | _ -> true) s.ops})
  end;
  Alcotest.(check bool) "native modal GPU p95 fits 120 Hz budget"
    true (full > 0. && full <= 1000. /. 120.)

(* {1 Entry} *)

let test_trim_offscreen r =
  let s = scene ~w:96 ~h:64
    [ifill (rect 4. 8. 60. 40.) (color 37 99 235 255)] in
  Lui_metal.render r s;
  let before = Lui_metal.read_frame r ~w:s.width ~h:s.height in
  Alcotest.(check bool) "offscreen pixels retain an owned target" true
    (Lui_metal.owned_target_bytes r > 0);
  Alcotest.(check int) "offscreen renderer has no drawable pool" 0
    (Lui_metal.drawable_count r);
  Alcotest.(check bool) "offscreen renderer has no window dimensions" true
    (Lui_metal.drawable_size r = None);
  Lui_metal.trim r;
  Alcotest.(check bytes) "trimming preserves offscreen pixels" before
    (Lui_metal.read_frame r ~w:s.width ~h:s.height)

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
            [ Alcotest.test_case "rounded frame budget" `Quick (fun () -> test_rounded_budget r);
              Alcotest.test_case "native chrome budget" `Quick (fun () -> test_native_chrome_budget r);
              Alcotest.test_case "captured scene budget" `Quick (fun () -> test_captured_scene r);
              Alcotest.test_case "native modal budget" `Quick (fun () -> test_modal_budget r);
              Alcotest.test_case "outset shadow budget" `Quick (fun () -> test_shadow_budget r);
              Alcotest.test_case "solid frame budget" `Quick (fun () -> test_fill_budget r);
              Alcotest.test_case "parity corpus" `Quick (fun () -> test_parity r);
              Alcotest.test_case "determinism" `Quick (fun () -> test_determinism r);
              Alcotest.test_case "offscreen trimming" `Quick (fun () -> test_trim_offscreen r);
              Alcotest.test_case "atlas update" `Quick (fun () -> test_atlas_update r);
              Alcotest.test_case "frame size changes" `Quick
                (fun () -> test_frame_size_changes r);
              Alcotest.test_case "retained allocations" `Quick
                (fun () -> test_retained_allocations r);
              Alcotest.test_case "retained invalidation" `Quick
                (fun () -> test_retained_invalidation r) ] ) ]
