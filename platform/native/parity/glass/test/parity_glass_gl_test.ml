(* Pixel parity of the CPU and GL renderers over the glass corpus:
   Lui_raster's BGRA frame against the framebuffer Lui_gl draws,
   compared under each scene's expectation. The GL cases need a
   context from a hidden SDL window — where that cannot be had they
   skip with a reason, and the CPU-only structure tests still run.
   The effect bodies the corpus carries are GLSL on this side (the
   same source the Metal and Direct3D frontends read through their
   dialect shims). *)

open Lui_parity.Parity
module Tk = Lui_raster_testkit.Testkit
module Gl = Tgl3.Gl

(* {1 GL context — the recipe the shared parity suite uses} *)

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
      Sdl.create_window "lui glass parity" ~w:64 ~h:64
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

let cpu_frame s = (Lui_raster.render ~scene:s ()).Lui_raster.Image.pix

let gpu_frame s =
  with_framebuffer s.Lui_scene.width s.Lui_scene.height (fun () ->
      match Lui_gl.init () with
      | Error e -> Alcotest.failf "Lui_gl.init: %s" e
      | Ok r ->
        Fun.protect
          (fun () ->
            Lui_gl.render r s;
            Lui_gl.read_frame s.Lui_scene.width s.Lui_scene.height)
          ~finally:(fun () -> Lui_gl.release r))

let test_parity name build expect () =
  with_gl (fun () ->
      let s = build () in
      let cpu = cpu_frame s and gpu = gpu_frame s in
      let d =
        diff_frames ~w:s.Lui_scene.width ~h:s.Lui_scene.height ~cpu ~gpu
          ()
      in
      let stats = report name d in
      Printf.printf "%s\n%!" stats;
      match expect with
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
          (Printf.sprintf "%s — documented divergence expected: %s" stats
             why)
          true (d.pixels > 0))

(* {1 Structure — runs with or without GL} *)

let test_twins () =
  List.iter
    (fun fx ->
      Alcotest.(check bool)
        (Printf.sprintf "%s carries its shader" fx.Lui_scene.ename)
        true (String.length fx.Lui_scene.eglsl > 0))
    [ Lui_plugin_glass.glass_fx; Lui_plugin_glass.blur_fx ]

let test_draws () =
  List.iter
    (fun (n, build, _) ->
      let s = build () in
      let img = (Lui_raster.render ~scene:s ()).Lui_raster.Image.pix in
      let b0 = Bytes.get img 0 in
      Alcotest.(check bool)
        (Printf.sprintf "%s draws pixels" n)
        true (Bytes.exists (fun c -> c <> b0) img))
    Lui_parity_glass.Parity_glass.corpus

let () =
  let cases =
    List.map
      (fun (n, build, expect) ->
        Alcotest.test_case n `Slow (test_parity n build expect))
      Lui_parity_glass.Parity_glass.corpus
  in
  Alcotest.run "lui_parity_glass_gl"
    [ ("scenes", cases);
      ( "structure",
        [ Alcotest.test_case "effect twins" `Quick test_twins;
          Alcotest.test_case "scenes draw" `Quick test_draws ] ) ]
