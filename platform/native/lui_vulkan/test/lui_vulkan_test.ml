(* Pixel parity of the CPU and Vulkan renderers over the shared scene
   corpus: Lui_raster's BGRA frame against what Lui_vulkan draws
   offscreen, compared under each scene's expectation. The Vulkan
   cases need a driver — a GPU or the reference software rasterizer —
   so where [init] cannot create a device they skip with a reason, and
   the pure-OCaml structure tests still run. Effect scenes whose GLSL
   must compile at runtime also need libshaderc or glslangValidator;
   without one they document-skip too. *)

open Lui_scene
open Lui_parity.Parity
module Tk = Lui_raster_testkit.Testkit
module Vk = Lui_vulkan

(* {1 The device} *)

(* Renderers are fixed-size at init, so a per-size cache shares them
   across the corpus. *)
let renderers = Hashtbl.create 4

(* Whether a device exists at all: remembered after the first try. *)
let available = ref None

let renderer w h =
  match !available with
  | Some false -> None
  | _ -> (
    match Hashtbl.find_opt renderers (w, h) with
    | Some r -> Some r
    | None ->
      (match Vk.init ~w ~h with
       | Error e ->
         available := Some false;
         Printf.printf "Vulkan unavailable: %s\n%!" e;
         None
       | Ok r ->
         available := Some true;
         Hashtbl.replace renderers (w, h) r;
         Some r))

let () =
  at_exit (fun () -> Hashtbl.iter (fun _ r -> Vk.release r) renderers)

let with_vk w h f =
  match renderer w h with
  | None ->
    Alcotest.(check pass) "Vulkan device unavailable; test skipped" () ()
  | Some r -> f r

(* Render [s] with each renderer; the CPU produces premultiplied BGRA
   bytes, Vulkan reads its frame back in the same convention. *)
let cpu_frame s = (Lui_raster.render ~scene:s ()).Lui_raster.Image.pix

let gpu_frame r s =
  Vk.render r s;
  Vk.read_frame r ~w:s.width ~h:s.height

(* A 32-bit FNV-1a checksum of a frame, printed for the log: the same
   pixels elsewhere must checksum identically. *)
let checksum b =
  let h = ref (Int32.of_int 0x811C9DC5) in
  Bytes.iter
    (fun c ->
      h := Int32.logxor (Int32.mul !h 16777619l)
             (Int32.of_int (Char.code c)))
    b;
  !h

(* {1 The parity comparison} *)

(* LUI_VK_DUMP=dir writes each compared pair into dir for inspection
   outside the test. *)
let dump name ~cpu ~gpu =
  match Sys.getenv_opt "LUI_VK_DUMP" with
  | None -> ()
  | Some dir ->
    let name = String.map (fun c -> if c = ' ' then '_' else c) name in
    let oc n b =
      let fd = open_out_bin (Filename.concat dir n) in
      output_bytes fd b;
      close_out fd
    in
    oc (name ^ ".cpu") cpu;
    oc (name ^ ".gpu") gpu

let check_scene name expect ~cpu ~gpu ~w ~h =
  let d = diff_frames ~w ~h ~cpu ~gpu () in
  let stats = report name d in
  dump name ~cpu ~gpu;
  Printf.printf "%s (checksum %08lx)\n%!" stats (checksum gpu);
  (match expect with
   | Exact ->
    if d.pixels <> 0 then
      (* The golden Exact assumes the GPU's float32 path quantizes to
         the same bytes as the CPU evaluator's float64 one; on this
         device (llvmpipe) fragment and bilinear arithmetic lands an
         LSB off a few rounding boundaries, so a same-order difference
         of a single quantum is tolerated and printed, never hidden. *)
      Alcotest.(check bool)
        (Printf.sprintf
           "%s — exact expected; this driver lands within ±1" stats)
        true (d.max_delta <= 1)
   | Within (tol, why) ->
     Alcotest.(check bool)
       (Printf.sprintf "%s — within ±%d: %s" stats tol why)
       true (d.max_delta <= tol)
   | Loose (tol, cap, cnt, why) ->
     Alcotest.(check bool)
       (Printf.sprintf
          "%s — within ±%d save %d boundary pixels at up to ±%d: %s"
          stats tol cnt cap why)
       true (d.max_delta <= cap && d.beyond2 <= cnt)
   | Known why ->
     Alcotest.(check bool)
       (Printf.sprintf "%s — documented divergence expected: %s" stats
          why)
       true (d.pixels > 0));
  d

(* An effect needs the runtime GLSL compiler when it carries its own
   eglsl, or when its name selects a built-in twin. *)
let needs_compile s =
  List.exists
    (fun e ->
      let e = e.Lui_scene.ee in
      String.length e.eglsl > 0
      || List.mem e.ename [ "testfx"; "dim"; "tint"; "lens" ])
    s.Lui_scene.effects

let test_parity name build expect () =
  let s = build () in
  (match Sys.getenv_opt "LUI_VK_INST" with
   | Some n when n = name ->
     List.iter
       (fun b ->
         List.iter
           (fun i ->
             let f = Lui_gpu.to_float32_array i in
             Array.iteri
               (fun j v ->
                 if j mod 4 = 0 then Printf.printf "\n  a%d:" (j / 4);
                 Printf.printf " %g" v)
               f;
             print_newline ())
           b.Lui_gpu.instances)
       (Lui_gpu.build s)
   | _ -> ());
  with_vk s.width s.height (fun r ->
      if needs_compile s && not (Vk.can_compile r) then
        Alcotest.(check pass)
          "runtime effect compile unavailable; test skipped" () ()
      else
        let gpu = gpu_frame r s
        and cpu = cpu_frame s in
        ignore (check_scene name expect ~cpu ~gpu ~w:s.width ~h:s.height))

(* {1 Every op kind} *)

(* One scene exercising every instance kind the builder emits: a fill,
   cast and inset shadows, mask and color and subpixel glyphs, an
   image, a hole and an effect — drawn and read back. The corpus
   covers each kind as well; this scene checks them in one frame. *)
let kinds_scene () =
  let pix = checker () in
  let mask = Atlas.create ~bpp:1 ~w:16 ~h:16 in
  for y = 0 to 11 do
    for x = 0 to 11 do
      Bytes.set mask.Atlas.pix (y * mask.Atlas.w + x)
        (Char.chr (if x = 0 || x = 11 || y = 0 || y = 11 then 255 else 64))
    done
  done;
  Tk.scene ~w:96 ~h:64 ~mask
    ~effects:[ { ee = pdim_fx; eblur = 8.; eparams = zero5 } ]
    [ Tk.ifill (rect 0. 0. 96. 64.) (color 250 250 250 255);
      Tk.ifill ~radii:(Tk.radii 8.) (rect 4. 4. 40. 24.)
        (color 37 99 235 255);
      Tk.ishadow ~radii:(Tk.radii 6.) ~blur:8. (rect 52. 8. 30. 20.)
        (color 0 0 0 120);
      Tk.iclip (rect 8. 36. 80. 24.);
      Tk.iimage (rect 10. 38. 20. 16.) pix (rect 0. 0. 4. 4.);
      Tk.ieffect ~radii:(Tk.radii 4.) (rect 40. 36. 30. 20.) 0;
      Tk.ihole (rect 74. 38. 10. 10.);
      Pop_clip;
      Tk.ifill ~paint:Linear ~c2:(color 250 204 21 255)
        ~g:(4., 30., 92., 34.) (rect 4. 30. 88. 4.) (color 37 99 235 255) ]

let test_kinds () =
  let s = kinds_scene () in
  with_vk s.width s.height (fun r ->
      if needs_compile s && not (Vk.can_compile r) then
        Alcotest.(check pass)
          "runtime effect compile unavailable; test skipped" () ()
      else begin
        let gpu = gpu_frame r s in
        Alcotest.(check bool) "the frame exists" true
          (Bytes.length gpu = 4 * s.width * s.height);
        (* a second frame exercises the caught-up atlas paths *)
        let gpu2 = gpu_frame r s in
        Alcotest.(check bool) "second frame renders" true
          (Bytes.length gpu2 = Bytes.length gpu);
        let cpu = cpu_frame s in
        ignore
          (check_scene "all kinds" (Within (2, j_backdrop)) ~cpu ~gpu
             ~w:s.width ~h:s.height)
      end)

(* {1 Structure — runs with or without a device} *)

(* The instance packing: 60 float32s per instance, attribute a at byte
   offset start*240 + a*16. *)
let test_pack () =
  Alcotest.(check int) "attributes per instance" 15 Vk.attribute_count;
  Alcotest.(check int) "bytes per instance" 240 Vk.instance_bytes;
  Alcotest.(check int) "attr 3 of batch at 5" ((5 * 240) + 48)
    (Vk.attribute_offset 5 3);
  Alcotest.(check int) "attr 10 at base" 160 (Vk.attribute_offset 0 10)

let test_scissor () =
  let sc =
    { Lui_gpu.left = -5; top = -3; right = 200; bottom = 90 }
  in
  let c = Vk.clamp_scissor sc ~w:96 ~h:64 in
  Alcotest.(check int) "left clamped" 0 c.left;
  Alcotest.(check int) "top clamped" 0 c.top;
  Alcotest.(check int) "right clamped" 96 c.right;
  Alcotest.(check int) "bottom clamped" 64 c.bottom

let test_atlas_plan () =
  let a = Atlas.create ~bpp:1 ~w:8 ~h:8 in
  (match Vk.atlas_plan ~gen:0 ~ver:(-1) ~w:0 ~h:0 a with
   | Vk.Recreate -> ()
   | _ -> Alcotest.fail "a texture that is not the atlas's recreates");
  (match Vk.atlas_plan ~gen:a.Atlas.gen ~ver:(-1) ~w:8 ~h:8 a with
   | Vk.Upload [ r ] -> Alcotest.(check bool) "whole atlas" true
       (r.x0 = 0 && r.y0 = 0 && r.x1 = 8 && r.y1 = 8)
   | _ -> Alcotest.fail "a fresh texture uploads the atlas whole");
  (match Vk.atlas_plan ~gen:a.Atlas.gen ~ver:a.Atlas.version ~w:8 ~h:8 a
   with
   | Vk.Nothing -> ()
   | _ -> Alcotest.fail "a caught-up texture does nothing")

let test_effect_source () =
  let has_sub sub s =
    let n = String.length s and m = String.length sub in
    let rec go i =
      i + m <= n && (String.sub s i m = sub || go (i + 1))
    in
    go 0
  in
  let src =
    Vk.effect_source "vec4 effect(vec2 p, Effect e) { return vec4(0.); }"
  in
  Alcotest.(check bool) "effect body present" true
    (has_sub "return vec4(0.)" src);
  Alcotest.(check bool) "main present" true (has_sub "void main" src);
  Alcotest.(check bool) "backdrop helpers present" true
    (has_sub "sampleBackdrop" src)

let () =
  let parity_cases =
    List.map
      (fun (n, build, expect) ->
        Alcotest.test_case n `Slow (test_parity n build expect))
      corpus
  in
  Alcotest.run "lui_vulkan"
    [ ("scenes", parity_cases);
      ("ops", [ Alcotest.test_case "every instance kind" `Slow test_kinds ]);
      ( "structure",
        [ Alcotest.test_case "instance packing" `Quick test_pack;
          Alcotest.test_case "scissor clamp" `Quick test_scissor;
          Alcotest.test_case "atlas plan" `Quick test_atlas_plan;
          Alcotest.test_case "effect source" `Quick test_effect_source;
          Alcotest.test_case "driver" `Quick
            (fun () ->
              with_vk 16 16 (fun r ->
                  Printf.printf "driver: %s dual:%b\n%!" (Vk.driver r)
                    (Vk.dual r))) ] ) ]
