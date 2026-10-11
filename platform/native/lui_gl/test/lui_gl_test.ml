(* Tests for lui_gl: the pure parts (instance packing, scissor
   clamping, atlas upload planning, effect source composition) run
   everywhere; the GL tests need a context, made through a hidden SDL
   window — they skip where a GL3 context cannot be had. *)

open Lui_scene
module Gl = Tgl3.Gl

let atlas ~bpp = Atlas.create ~bpp ~w:64 ~h:64

let make_scene ~w ~h =
  let s =
    create ~mask_atlas:(atlas ~bpp:1) ~color_atlas:(atlas ~bpp:4)
  in
  reset s ~width:w ~height:h ~scale:1. ~clear:(color 255 255 255 255);
  s

let fill_op ?(x = 4.) ?(y = 4.) ?(w = 24.) ?(h = 24.) ?(radii = (4., 4., 4., 4.))
    ?(c = color 255 0 0 255) () : op =
  Fill
    { frect = rect x y w h;
      fradii = radii;
      fcontinuous = false;
      fcolor = c;
      fpaint = Solid;
      fcolor2 = color 0 0 0 0;
      fgradient = (0., 0., 0., 0.);
      fborder = (0., 0., 0., 0.);
      fborder_color = color 0 0 0 0;
      fdashed = false;
      fwide = 0;
      fopacity = 1. }

let clip_op r : op =
  Push_clip { crect = r; cradii = (0., 0., 0., 0.); ccontinuous = false }

(* {1 Instance packing} *)

let test_pack_offsets () =
  Alcotest.(check int) "attribute count" 15 Lui_gl.attribute_count;
  Alcotest.(check int) "instance bytes" 240 Lui_gl.instance_bytes;
  Alcotest.(check int) "attr 0 of first" 0 (Lui_gl.attribute_offset 0 0);
  Alcotest.(check int) "attr 10 of first" 160 (Lui_gl.attribute_offset 0 10);
  Alcotest.(check int) "attr 0 of second" 240 (Lui_gl.attribute_offset 1 0);
  Alcotest.(check int) "attr 3 of second" 288 (Lui_gl.attribute_offset 1 3)

let test_pack_batches () =
  let s = make_scene ~w:64 ~h:64 in
  s.ops <- [ fill_op () ];
  let batches = Lui_gpu.build s in
  let pack = Lui_gl.pack_batches batches in
  Alcotest.(check int) "one batch" 1 (List.length batches);
  Alcotest.(check int) "one instance" 60
    (Bigarray.Array1.dim pack.data);
  let st, n = pack.spans.(0) in
  Alcotest.(check int) "start" 0 st;
  Alcotest.(check int) "count" 1 n;
  (* rect is floats 0-3; params floats 40-43: kind, flag, paint,
     opacity *)
  Alcotest.(check (float 0.001)) "rect x" 4. pack.data.{0};
  Alcotest.(check (float 0.001)) "rect y" 4. pack.data.{1};
  Alcotest.(check (float 0.001)) "rect w" 24. pack.data.{2};
  Alcotest.(check (float 0.001)) "rect h" 24. pack.data.{3};
  Alcotest.(check (float 0.001)) "kind fill" Lui_gpu.kind_fill
    pack.data.{40};
  Alcotest.(check (float 0.001)) "opacity" 1. pack.data.{43}

(* Batch splitting on scissor change: two fills, the second inside a
   clip — two spans in one packed buffer. *)
let test_pack_spans () =
  let s = make_scene ~w:64 ~h:64 in
  s.ops <-
    [ fill_op ();
      clip_op (rect 8. 8. 20. 20.);
      fill_op ~x:10. ~y:10. ~w:4. ~h:4. ();
      Lui_scene.Pop_clip;
      fill_op ~x:40. ~y:40. ~w:8. ~h:8. () ];
  let batches = Lui_gpu.build s in
  let pack = Lui_gl.pack_batches batches in
  Alcotest.(check int) "batches" 3 (List.length batches);
  Alcotest.(check int) "spans" 3 (Array.length pack.spans);
  Alcotest.(check (pair int int)) "span 0" (0, 1) pack.spans.(0);
  Alcotest.(check (pair int int)) "span 1" (1, 1) pack.spans.(1);
  Alcotest.(check (pair int int)) "span 2" (2, 1) pack.spans.(2);
  (* batch 1's scissor is the clip's *)
  let b1 = List.nth batches 1 in
  Alcotest.(check int) "clip left" 8 b1.Lui_gpu.scissor.left;
  Alcotest.(check int) "clip right" 28 b1.Lui_gpu.scissor.right

(* {1 Scissor clamping} *)

let test_clamp_scissor () =
  let sc : Lui_gpu.scissor = { left = -5; top = -3; right = 100; bottom = 40 } in
  let c = Lui_gl.clamp_scissor sc ~w:64 ~h:32 in
  Alcotest.(check int) "left" 0 c.left;
  Alcotest.(check int) "top" 0 c.top;
  Alcotest.(check int) "right" 64 c.right;
  Alcotest.(check int) "bottom" 32 c.bottom

(* {1 Atlas upload planning} *)

let test_atlas_plan () =
  let a = atlas ~bpp:1 in
  (* A texture already tracking this exact state uploads nothing. *)
  (match Lui_gl.atlas_plan ~gen:a.gen ~ver:a.version ~w:a.w ~h:a.h a with
   | Lui_gl.Nothing -> ()
   | _ -> Alcotest.fail "expected Nothing");
  (* A changed rectangle uploads just it. *)
  Atlas.put a ~x:2 ~y:3 ~w:4 ~h:4 ~src:(Bytes.make 16 '\xAB') ~stride:4;
  (match Lui_gl.atlas_plan ~gen:a.gen ~ver:0 ~w:a.w ~h:a.h a with
   | Lui_gl.Upload [ r ] ->
     Alcotest.(check int) "x0" 2 r.x0;
     Alcotest.(check int) "y0" 3 r.y0;
     Alcotest.(check int) "x1" 7 r.x1;
     Alcotest.(check int) "y1" 8 r.y1
   | _ -> Alcotest.fail "expected Upload of the changed rect");
  (* A generation change or a size change recreates the texture. *)
  Atlas.changed_all a;
  (match Lui_gl.atlas_plan ~gen:1 ~ver:a.version ~w:a.w ~h:a.h a with
   | Lui_gl.Recreate -> ()
   | _ -> Alcotest.fail "expected Recreate on gen change");
  (match Lui_gl.atlas_plan ~gen:a.gen ~ver:a.version ~w:128 ~h:a.h a with
   | Lui_gl.Recreate -> ()
   | _ -> Alcotest.fail "expected Recreate on size change")

(* {1 Effect source} *)

let contains_sub hay needle =
  let n = String.length hay and m = String.length needle in
  let rec go i =
    i + m <= n && (String.sub hay i m = needle || go (i + 1))
  in
  go 0

let test_effect_source () =
  let src = Lui_gl.effect_source "vec4 effect(vec2 p, Effect e) { return e.p0; }" in
  let has sub = Alcotest.(check bool) sub true (contains_sub src sub) in
  has "#define EFFECT";
  has "uniform sampler2D uBackdrop";
  has "struct Effect";
  has "vec3 sampleBackdrop(Effect e, vec2 q)";
  has "vec4 effect(vec2 p, Effect e) { return e.p0; }";
  has "fragColor = effect(p, e)"

(* {1 GL} *)

(* A GL3 core context on a hidden SDL window, or None where that
   cannot be had (headless CI). *)
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
      Sdl.create_window "lui_gl test" ~w:64 ~h:64
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

(* A scene exercising fills, a clip, a hole, an image and a
   backdrop-reading effect. *)
let gl_scene ~w ~h =
  let s = make_scene ~w ~h in
  let img =
    new_image ~w:4 ~h:4 (Bytes.make (4 * 4 * 4) '\xFF')
  in
  let fx =
    { ename = "test_fx";
      ebackdrop = true;
      eglsl =
        "vec4 effect(vec2 p, Effect e) {\n\
         \treturn vec4(sampleBackdrop(e, p).rgb, 0.5);\n\
         }";
      epixels =
        (fun () ->
          { begin_effect = (fun _ _ _ -> ());
            color_at = (fun _ _ _ -> (0., 0., 0.)) }) }
  in
  s.effects <- [ { ee = fx; eblur = 4.;
                   eparams = [| (0., 0., 0., 0.); (0., 0., 0., 0.);
                                (0., 0., 0., 0.); (0., 0., 0., 0.);
                                (0., 0., 0., 0.) |] } ];
  s.ops <-
    [ fill_op ~x:0. ~y:0. ~w:(float w) ~h:(float h) ~radii:(0., 0., 0., 0.)
        ~c:(color 200 200 200 255) ();
      fill_op ~x:8. ~y:8. ~w:32. ~h:32. ();
      clip_op (rect 12. 12. 24. 24.);
      fill_op ~x:16. ~y:16. ~w:16. ~h:16. ~c:(color 0 255 0 255) ();
      Lui_scene.Pop_clip;
      Hole { hrect = rect 40. 4. 12. 12.;
             hradii = (0., 0., 0., 0.); hcontinuous = false;
             hopacity = 1. };
      Image { irect2 = rect 44. 44. 8. 8.;
              iradii = (0., 0., 0., 0.); icontinuous = false;
              iimage = img; isrc = rect 0. 0. 4. 4.;
              igrayscale = false; iopacity = 1. };
      Effect { edrect = rect 4. 40. 24. 20.;
               edradii = (0., 0., 0., 0.); edcontinuous = false;
               edindex = 0; edopacity = 1. } ];
  s

let test_gl_render () =
  match sdl_gl_context () with
  | None ->
    Alcotest.(check pass) "GL context unavailable; test skipped" () ()
  | Some (win, ctx) -> (
    match Lui_gl.init () with
    | Error e ->
      release_gl (win, ctx);
      Alcotest.failf "init failed: %s" e
    | Ok r ->
      let dw, dh = Tsdl.Sdl.gl_get_drawable_size win in
      let s = gl_scene ~w:dw ~h:dh in
      Lui_gl.render r s;
      let f1 = Lui_gl.read_frame dw dh in
      Lui_gl.render r s;
      let f2 = Lui_gl.read_frame dw dh in
      Alcotest.(check bool) "same scene, same pixels" true
        (Bytes.equal f1 f2);
      Alcotest.(check int) "frame size" (4 * dw * dh) (Bytes.length f1);
      (* A pixel inside the red fill at (8,8)+(32,32), outside the
         clip's green: red is byte 2 of premultiplied BGRA. *)
      let cx = 10 and cy = 10 in
      if cx < dw && cy < dh then
        let d = 4 * (cy * dw + cx) in
        Alcotest.(check int) "red fill center" 255
          (Char.code (Bytes.get f1 (d + 2)));
      (* Something other than the clear color was drawn. *)
      let differs =
        let rec go i =
          i < Bytes.length f1
          && (Bytes.get f1 i <> '\xFF' || go (i + 1))
        in
        go 0
      in
      Alcotest.(check bool) "non-blank frame" true differs;
      Lui_gl.release r;
      release_gl (win, ctx))

let () =
  Alcotest.run "lui_gl"
    [ ( "packing",
        [ Alcotest.test_case "attribute offsets" `Quick test_pack_offsets;
          Alcotest.test_case "batch packing" `Quick test_pack_batches;
          Alcotest.test_case "batch spans" `Quick test_pack_spans ] );
      ( "scissor",
        [ Alcotest.test_case "clamp to frame" `Quick test_clamp_scissor ] );
      ( "atlas",
        [ Alcotest.test_case "upload planning" `Quick test_atlas_plan ] );
      ( "effects",
        [ Alcotest.test_case "effect source" `Quick test_effect_source ] );
      ( "gl",
        [ Alcotest.test_case "render checksum" `Quick test_gl_render ] ) ]
