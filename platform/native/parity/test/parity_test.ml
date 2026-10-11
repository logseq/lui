(* Pixel parity of the CPU and GL renderers over the shared scene
   corpus: Lui_raster's BGRA frame against the framebuffer Lui_gl
   draws, compared under each scene's expectation. The GL cases need
   a context from a hidden SDL window — where that cannot be had they
   skip with a reason, and the CPU-only structure tests still run. *)

open Lui_scene
open Lui_parity.Parity
module Tk = Lui_raster_testkit.Testkit
module Gl = Tgl3.Gl

(* {1 GL context} *)

(* A GL3 core context on a hidden SDL window — the recipe the lui_gl
   tests use — or None where it cannot be had (headless CI). *)
let sdl_gl_context () =
  match Tsdl.Sdl.init Tsdl.Sdl.Init.(video + events) with
  | Error _ -> None
  | Ok () -> (
    let open Tsdl in
    ignore (Sdl.gl_set_attribute Sdl.Gl.context_major_version 3);
    ignore (Sdl.gl_set_attribute Sdl.Gl.context_minor_version 3);
    ignore
      (Sdl.gl_set_attribute Sdl.Gl.context_profile_mask
         Sdl.Gl.context_profile_core);
    ignore (Sdl.gl_set_attribute Sdl.Gl.doublebuffer 1);
    match
      Sdl.create_window "lui parity test" ~w:64 ~h:64
        Sdl.Window.(opengl + hidden)
    with
    | Error _ ->
      Sdl.quit ();
      None
    | Ok win -> (
      match Sdl.gl_create_context win with
      | Error _ ->
        Sdl.destroy_window win;
        Sdl.quit ();
        None
      | Ok ctx -> (
        match Sdl.gl_make_current win ctx with
        | Error _ ->
          Sdl.gl_delete_context ctx;
          Sdl.destroy_window win;
          Sdl.quit ();
          None
        | Ok () ->
          (* Without a GPU driver WGL silently falls back to the GDI
             software rasterizer (GL 1.1): context creation succeeds
             but the driver reports an unusably old version. *)
          let gl3 =
            match Gl.get_string Gl.version with
            | Some v -> (
              match String.split_on_char '.' v with
              | m :: _ -> (
                match int_of_string_opt m with
                | Some n -> n >= 3
                | None -> false)
              | [] -> false)
            | None -> false
          in
          if not gl3 then begin
            Sdl.gl_delete_context ctx;
            Sdl.destroy_window win;
            Sdl.quit ();
            None
          end
          else Some (win, ctx))))

let release_gl (win, ctx) =
  Tsdl.Sdl.gl_delete_context ctx;
  Tsdl.Sdl.destroy_window win;
  Tsdl.Sdl.quit ()

(* The context once for the suite; it stays current on this thread. *)
let gl_context = lazy (sdl_gl_context ())

let () =
  at_exit (fun () ->
      if Lazy.is_val gl_context then
        match Lazy.force gl_context with
        | Some c -> release_gl c
        | None -> ())

let with_gl f =
  match Lazy.force gl_context with
  | None -> Alcotest.(check pass) "GL context unavailable; test skipped" () ()
  | Some _ -> f ()

(* {1 Frame capture} *)

let gen1 f =
  let b = Bigarray.(Array1.create int32 c_layout 1) in
  f 1 b;
  Int32.to_int b.{0}

let del1 f id =
  if id <> 0 then (
    let b = Bigarray.(Array1.create int32 c_layout 1) in
    b.{0} <- Int32.of_int id;
    f 1 b)

(* An RGBA8 texture as a framebuffer's color attachment, bound for the
   duration of [f]; Lui_gl renders into whatever is bound. *)
let with_framebuffer w h f =
  let tex = gen1 Gl.gen_textures in
  Gl.bind_texture Gl.texture_2d tex;
  Gl.tex_parameteri Gl.texture_2d Gl.texture_min_filter Gl.nearest;
  Gl.tex_parameteri Gl.texture_2d Gl.texture_mag_filter Gl.nearest;
  Gl.pixel_storei Gl.unpack_alignment 1;
  Gl.tex_image2d Gl.texture_2d 0 Gl.rgba8 w h 0 Gl.rgba Gl.unsigned_byte
    (`Offset 0);
  let fb = gen1 Gl.gen_framebuffers in
  Gl.bind_framebuffer Gl.framebuffer fb;
  Gl.framebuffer_texture2d Gl.framebuffer Gl.color_attachment0
    Gl.texture_2d tex 0;
  if Gl.check_framebuffer_status Gl.framebuffer <> Gl.framebuffer_complete
  then Alcotest.fail "test framebuffer incomplete";
  Fun.protect f ~finally:(fun () ->
      Gl.bind_framebuffer Gl.framebuffer 0;
      del1 Gl.delete_framebuffers fb;
      del1 Gl.delete_textures tex)

(* Render [s] with each renderer; the CPU produces premultiplied BGRA
   bytes, the GPU is read back through Lui_gl.read_frame in the same
   convention. A fresh Lui_gl renderer per scene keeps atlas tracking
   honest between unrelated scenes. *)
let cpu_frame s = (Lui_raster.render ~scene:s ()).Lui_raster.Image.pix

let gpu_frame s =
  with_framebuffer s.width s.height (fun () ->
      match Lui_gl.init () with
      | Error e -> Alcotest.failf "Lui_gl.init: %s" e
      | Ok r ->
        Fun.protect
          (fun () ->
            Lui_gl.render r s;
            Lui_gl.read_frame s.width s.height)
          ~finally:(fun () -> Lui_gl.release r))

(* {1 The parity comparison} *)

(* LUI_PARITY_DUMP=dir writes each compared pair and a diff map into
   dir for inspection outside the test. *)
let dump_dir = Sys.getenv_opt "LUI_PARITY_DUMP"

let dump name ~cpu ~gpu ~w ~h d =
  match dump_dir with
  | None -> ()
  | Some dir ->
    let name = String.map (fun c -> if c = ' ' then '_' else c) name in
    let base n = Filename.concat dir n in
    let oc name bytes =
      let fd = open_out_bin (base name) in
      output_bytes fd bytes;
      close_out fd
    in
    oc (name ^ ".cpu") cpu;
    oc (name ^ ".gpu") gpu;
    let map = Bytes.make (4 * w * h) '\x00' in
    for y = 0 to h - 1 do
      for x = 0 to w - 1 do
        let i = 4 * ((y * w) + x) in
        let dlt = ref 0 in
        for c = 0 to 3 do
          let dc =
            Int.abs
              (Char.code (Bytes.get cpu (i + c))
              - Char.code (Bytes.get gpu (i + c)))
          in
          if dc > !dlt then dlt := dc
        done;
        if !dlt > 0 then begin
          Bytes.set map (i + 0) (Char.chr (min !dlt 255));
          Bytes.set map (i + 3) '\xFF'
        end
      done
    done;
    oc (name ^ ".diff") map;
    let meta =
      Printf.sprintf "%d %d %d %d %d %d\n" w h d.pixels d.max_delta
        (fst d.first) (snd d.first)
    in
    let fd = open_out_bin (base (name ^ ".meta")) in
    output_string fd meta;
    close_out fd

let check_scene ?(ignore = fun _ _ -> false) name expect ~cpu ~gpu ~w
    ~h =
  let d = diff_frames ~ignore ~w ~h ~cpu ~gpu () in
  let stats = report name d in
  dump name ~cpu ~gpu ~w ~h d;
  Printf.printf "%s\n%!" stats;
  (match expect with
   | Exact -> Alcotest.(check int) stats 0 d.pixels
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
       (Printf.sprintf "%s — documented divergence expected: %s" stats why)
       true (d.pixels > 0));
  d

(* One line per op for diagnosing a divergence: which draw is
   missing or misplaced. *)
let describe_ops s =
  List.iteri
    (fun i o ->
      let k, r =
        match o with
        | Fill f -> ("fill", f.frect)
        | Shadow sh -> ("shadow", sh.srect)
        | Glyphs _ -> ("glyphs", rect 0. 0. 0. 0.)
        | Image im -> ("image", im.irect2)
        | Push_clip c -> ("push_clip", c.crect)
        | Pop_clip -> ("pop_clip", rect 0. 0. 0. 0.)
        | Effect e -> ("effect", e.edrect)
        | Hole ho -> ("hole", ho.hrect)
      in
      Printf.printf "  op %d %s (%.1f,%.1f %.1fx%.1f)\n%!" i k r.x r.y
        r.w r.h)
    s.ops

let test_parity name build expect () =
  with_gl (fun () ->
      let s = build () in
      let cpu = cpu_frame s and gpu = gpu_frame s in
      ignore (check_scene name expect ~cpu ~gpu ~w:s.width ~h:s.height))

(* {1 Damage parity}

   The CPU renderer's incremental output — each frame composited from
   the previous buffer and the damaged rectangles — must equal a full
   GL redraw of the same scene. The random scene builder mutates ops,
   atlas tiles and image pixels, exercising every damage kind. *)

let j_damage =
  "damage-composited CPU frames vs full GL redraws of random scenes; \
   ±2 covers the accumulated blend and sampling rounding of a whole \
   random scene, the documented quad-margin strips of fractional \
   image/glyph rects are masked, and a handful of pixels may flip \
   across coverage boundaries at fractional edges — "
  ^ j_boundary

let test_damage () =
  with_gl (fun () ->
      for seed = 0 to 3 do
        let m = Tk.Maker.make seed in
        let s = Tk.Maker.scene m in
        let w = s.width and h = s.height in
        let dr = Lui_raster.Renderer.create () in
        with_framebuffer w h (fun () ->
            match Lui_gl.init () with
            | Error e -> Alcotest.failf "Lui_gl.init: %s" e
            | Ok r ->
              Fun.protect
                (fun () ->
                  for step = 0 to 7 do
                    if step > 0 then ignore (Tk.Maker.change m s);
                    ignore (Lui_raster.Renderer.render dr s);
                    let cpu = (Lui_raster.Renderer.image dr).Lui_raster.Image.pix in
                    Lui_gl.render r s;
                    let gpu = Lui_gl.read_frame w h in
                    let dd =
                      diff_frames ~w ~h ~cpu ~gpu
                        ~ignore:(margin_ignores s) ()
                    in
                    if dd.max_delta > 2 then describe_ops s;
                    ignore
                      (check_scene
                         ~ignore:(margin_ignores s)
                         (Printf.sprintf "damage seed %d step %d" seed step)
                         (Loose (2, 8, 64, j_damage))
                         ~cpu ~gpu ~w ~h)
                  done)
                ~finally:(fun () -> Lui_gl.release r))
      done)

(* A deterministic damage case for the backdrop path: mutating a fill
   inside an effect's backdrop must regrow the damage to the effect's
   area on the CPU, while the GPU just reblurs its frame. *)
let test_damage_backdrop () =
  with_gl (fun () ->
      let w, h = (96, 64) in
      let s =
        Tk.scene ~w ~h
          ~effects:[ { ee = pdim_fx; eblur = 8.; eparams = zero5 } ]
          [ Tk.ifill (rect 0. 0. 96. 64.) (color 37 99 235 255);
            Tk.ifill (rect 20. 10. 40. 30.) (color 250 204 21 255);
            Tk.ieffect ~radii:(Tk.radii 6.) (rect 12. 8. 60. 40.) 0 ]
      in
      let dr = Lui_raster.Renderer.create () in
      with_framebuffer w h (fun () ->
          match Lui_gl.init () with
          | Error e -> Alcotest.failf "Lui_gl.init: %s" e
          | Ok r ->
            Fun.protect
              (fun () ->
                for step = 0 to 1 do
                  (* step 1 changes the fill inside the backdrop *)
                  if step = 1 then
                    s.ops <-
                      [ Tk.ifill (rect 0. 0. 96. 64.) (color 37 99 235 255);
                        Tk.ifill (rect 20. 10. 40. 30.) (color 220 38 38 255);
                        Tk.ieffect ~radii:(Tk.radii 6.) (rect 12. 8. 60. 40.) 0 ];
                  ignore (Lui_raster.Renderer.render dr s);
                  let cpu =
                    (Lui_raster.Renderer.image dr).Lui_raster.Image.pix
                  in
                  Lui_gl.render r s;
                  let gpu = Lui_gl.read_frame w h in
                  ignore
                    (check_scene
                       (Printf.sprintf "backdrop damage step %d" step)
                       (Within (2, j_backdrop))
                       ~cpu ~gpu ~w ~h)
                done)
              ~finally:(fun () -> Lui_gl.release r)))

(* {1 Structure — runs with or without GL} *)

(* The corpus has unique names and every builder produces a sized
   scene. *)
let test_corpus () =
  let names = List.map (fun (n, _, _) -> n) corpus in
  let uniq = List.sort_uniq String.compare names in
  Alcotest.(check int)
    "corpus names unique" (List.length names) (List.length uniq);
  List.iter
    (fun (n, build, _) ->
      let s = build () in
      Alcotest.(check bool)
        (Printf.sprintf "%s: scene is sized" n)
        true (s.width > 0 && s.height > 0))
    corpus

(* The corpus still covers every golden scene: adding one to the CPU
   suite without an expectation here is a loud failure, not a silent
   gap. *)
let test_golden_sync () =
  List.iter
    (fun (n, _) ->
      Alcotest.(check bool)
        (Printf.sprintf "golden scene %s is in the corpus" n)
        true
        (List.exists (fun (cn, _, _) -> cn = n) corpus))
    Tk.golden_scenes

(* The comparison itself: pixel count, max channel delta, first
   coordinate. *)
let test_diff () =
  let w, h = (4, 2) in
  let a = Bytes.make (4 * w * h) '\x00' in
  let b = Bytes.copy a in
  Bytes.set b 0 '\x01';
  Bytes.set b ((4 * ((1 * w) + 2)) + 3) '\xFE';
  let d = diff_frames ~w ~h ~cpu:a ~gpu:b () in
  Alcotest.(check int) "divergent pixels" 2 d.pixels;
  Alcotest.(check int) "max delta" 254 d.max_delta;
  Alcotest.(check int) "first x" 0 (fst d.first);
  Alcotest.(check int) "first y" 0 (snd d.first)

(* Every corpus scene except the deliberately blank ones draws
   something on the CPU — catches a corpus entry that accidentally
   builds a blank frame. [empty] is a clear-only scene and
   [image_empty_src] draws nothing on the CPU by design. *)
let test_draws () =
  List.iter
    (fun (n, build, _) ->
      if n <> "empty" && n <> "image_empty_src" then begin
        let s = build () in
        let img = (Lui_raster.render ~scene:s ()).Lui_raster.Image.pix in
        let b0 = Bytes.get img 0 in
        let varies = Bytes.exists (fun c -> c <> b0) img in
        Alcotest.(check bool)
          (Printf.sprintf "%s draws pixels" n)
          true varies
      end)
    corpus

(* Parity effects carry both halves — an empty shader would draw
   nothing on the GPU and the comparison would lie. *)
let test_twins () =
  List.iter
    (fun fx ->
      Alcotest.(check bool)
        (Printf.sprintf "%s carries GLSL" fx.ename)
        true (String.length fx.eglsl > 0))
    [ pgrad_fx; pdim_fx; ptint_fx; plens_fx ]

let () =
  let parity_cases =
    List.map
      (fun (n, build, expect) ->
        Alcotest.test_case n `Slow (test_parity n build expect))
      corpus
  in
  Alcotest.run "lui_parity"
    [ ("scenes", parity_cases);
      ( "damage",
        [ Alcotest.test_case "random scenes" `Slow test_damage;
          Alcotest.test_case "backdrop" `Slow test_damage_backdrop ] );
      ( "structure",
        [ Alcotest.test_case "corpus sanity" `Quick test_corpus;
          Alcotest.test_case "golden sync" `Quick test_golden_sync;
          Alcotest.test_case "diff stats" `Quick test_diff;
          Alcotest.test_case "scenes draw" `Quick test_draws;
          Alcotest.test_case "effect twins" `Quick test_twins ] ) ]
