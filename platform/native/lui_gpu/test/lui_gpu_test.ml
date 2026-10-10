open Lui_scene
open Alcotest
module G = Lui_gpu

(* ---------- helpers ---------- *)

let arr4 (a, b, c, d) = [| a; b; c; d |]
let eq4 e a = check (array (float 1e-6)) "f4" (arr4 e) (arr4 a)

let scissor_t =
  testable
    (fun f (s : G.scissor) ->
      Format.fprintf f "(%d,%d,%d,%d)" s.left s.top s.right s.bottom)
    (fun a b -> a = b)

let red = color 255 0 0 255
let green = color 0 255 0 255
let black = color 0 0 0 0

let scene ?(w = 200) ?(h = 100) () =
  let s =
    create
      ~mask_atlas:(Atlas.create ~bpp:1 ~w:64 ~h:32)
      ~color_atlas:(Atlas.create ~bpp:4 ~w:32 ~h:16)
  in
  reset s ~width:w ~height:h ~scale:1. ~clear:black;
  s

let glyph ?(x = 10.4) ?(y = 20.6) ?(u = 16) ?(v = 8) ?(uw = 8) ?(vh = 9)
    ?(c = red) ?(wide = 0) ?(colored = false) ?(subpixel = false)
    ?(thin = false) () =
  { gx = x; gy = y; gw = Float.of_int uw; gh = Float.of_int vh; gu = u; gv = v;
    guw = uw; gvh = vh; gcolor = c; gwide = wide; gcolored = colored;
    gsubpixel = subpixel; gthin = thin }

let fill ?(r = rect 1. 1. 10. 10.) ?(radii = (0., 0., 0., 0.))
    ?(c = red) ?(bw = (0., 0., 0., 0.)) ?(bc = black) ?(dashed = false)
    ?(paint = Solid) ?(c2 = red) ?(grad = (0., 0., 0., 0.)) ?(wide = 0)
    ?(op = 1.) () =
  Fill
    { frect = r; fradii = radii; fcontinuous = false; fcolor = c;
      fpaint = paint; fcolor2 = c2; fgradient = grad; fborder = bw;
      fborder_color = bc; fdashed = dashed; fwide = wide; fopacity = op }

let image_op img ?(r = rect 0. 0. 4. 4.) ?(src = rect 0. 0. 0. 0.)
    ?(gray = false) () =
  Image
    { irect2 = r; iradii = (0., 0., 0., 0.); icontinuous = false;
      iimage = img; isrc = src; igrayscale = gray; iopacity = 0. }

let all_insts = List.concat_map (fun (b : G.batch) -> b.instances)
let scissors = List.map (fun (b : G.batch) -> b.scissor)
let holes = List.map (fun (b : G.batch) -> b.hole)
let sc l t r b : G.scissor = { left = l; top = t; right = r; bottom = b }
let image_iid (b : G.batch) = match b.image with Some i -> i.iid | None -> -1

(* ---------- the build pass ---------- *)

let test_build () =
  let img1 = new_image ~w:2 ~h:2 (Bytes.make 16 '\000') in
  let img2 = new_image ~w:2 ~h:2 (Bytes.make 16 '\000') in
  let s = scene () in
  s.glyphs <- [ glyph () ];
  s.ops <-
    [ fill ~r:(rect 1. 2. 30. 20.) ~radii:(50., 50., 50., 50.)
        ~bw:(uniform_border 2.) ~bc:red ();
      Shadow
        { srect = rect 5. 5. 10. 10.; sradii = (0., 0., 0., 0.);
          scontinuous = false; scolor = red; sblur = 8.; sinset = false;
          scast = rect 0. 0. 0. 0.; scast_radii = (0., 0., 0., 0.);
          scast_continuous = false; swide = 0; sopacity = 0. };
      Push_clip
        { crect = rect 10.5 10. 100. 50.; cradii = (6., 6., 6., 6.);
          ccontinuous = false };
      Glyphs
        { gstart = 0; gend = 1; gpaint = Solid; gcolor = red;
          gcolor2 = red; ggradient = (0., 0., 0., 0.); gwide2 = 0;
          gopacity = 0. };
      image_op img1 ~src:(rect 0. 0. 2. 2.) ();
      image_op img2 ~src:(rect 0. 0. 1. 2.) ();
      Push_clip
        { crect = rect 500. 500. 10. 10.; cradii = (0., 0., 0., 0.);
          ccontinuous = false };
      fill ~r:(rect 500. 500. 5. 5.) ();
      Pop_clip;
      Pop_clip;
      fill ~r:(rect 0. 0. 0. 5.) ();
      Shadow
        { srect = rect 5. 5. 10. 10.; sradii = (0., 0., 0., 0.);
          scontinuous = false; scolor = red; sblur = 0.5; sinset = false;
          scast = rect 4. 3. 10. 10.; scast_radii = (20., 0., 0., 0.);
          scast_continuous = false; swide = 0; sopacity = 0.5 } ];
  let batches = G.build s in
  let insts = all_insts batches in
  check int "instances" 6 (List.length insts);
  let fill_i, shadow_i, glyph_i, im1, im2, hard =
    match insts with
    | [ a; b; c; d; e; f ] -> (a, b, c, d, e, f)
    | _ -> failwith "instance order"
  in
  (* A fill: border widths in uv, fitted radii, border inner radii. *)
  eq4 (0., 0., 0., 1.) fill_i.params;
  eq4 (2., 2., 2., 2.) fill_i.uv;
  eq4 (10., 10., 10., 10.) fill_i.radii;
  eq4 (8., 8., 8., 8.) fill_i.inner;
  eq4 (1., 0., 0., 1.) fill_i.color;
  (* Root clip: a huge rect, no radii. *)
  check bool "root clip huge" true (let _, _, w, _ = fill_i.clip in w > 1e5);
  eq4 (0., 0., 0., 0.) fill_i.clip_radii;
  (* A shadow: kind 1, sigma blur/2, no cast box. *)
  eq4 (1., 0., 4., 1.) shadow_i.params;
  eq4 (0., 0., 0., 0.) shadow_i.uv;
  (* A mask glyph: origin rounded, uv normalized by the mask atlas. *)
  eq4 (10., 21., 8., 9.) glyph_i.rect;
  eq4 (0.25, 0.25, 0.375, 0.53125) glyph_i.uv;
  eq4 (2., 0., 0., 1.) glyph_i.params;
  eq4 (10.5, 10., 100., 50.) glyph_i.clip;
  eq4 (6., 6., 6., 6.) glyph_i.clip_radii;
  (* Images: kind 4, uv the source rect normalized by image size. *)
  eq4 (0., 0., 1., 1.) im1.uv;
  eq4 (4., 0., 0., 1.) im1.params;
  eq4 (0., 0., 0.5, 1.) im2.uv;
  (* A shadow without blur carries sigma 0; the cast box goes to
     uv/inner with fitted radii. *)
  eq4 (1., 0., 0., 0.5) hard.params;
  eq4 (4., 3., 10., 10.) hard.uv;
  eq4 (10., 0., 0., 0.) hard.inner;
  (* Batches: scissor splits on the clip, image splits on texture. *)
  check int "batches" 4 (List.length batches);
  check (list scissor_t) "scissors"
    [ sc 0 0 200 100;
      sc 10 10 111 60;
      sc 10 10 111 60;
      sc 0 0 200 100 ]
    (scissors batches);
  check (list int) "counts" [ 2; 2; 1; 1 ]
    (List.map (fun (b : G.batch) -> List.length b.instances) batches);
  (* The batch of a glyph and an image adopts the image's texture. *)
  check int "batch1 image" img1.iid (image_iid (List.nth batches 1));
  check int "batch2 image" img2.iid (image_iid (List.nth batches 2));
  check int "batch0 image" (-1) (image_iid (List.nth batches 0));
  check (list bool) "no holes" [ false; false; false; false ]
    (holes batches)

(* ---------- clip stack ---------- *)

let test_nested_clips () =
  let s = scene () in
  s.ops <-
    [ Push_clip
        { crect = rect 20. 20. 100. 60.; cradii = (4., 4., 4., 4.);
          ccontinuous = false };
      Push_clip
        { crect = rect 40. 40. 40. 40.; cradii = (8., 8., 8., 8.);
          ccontinuous = false };
      fill ~r:(rect 50. 50. 10. 10.) ();
      Pop_clip;
      fill ~r:(rect 25. 25. 5. 5.) () ];
  let batches = G.build s in
  check int "batches" 2 (List.length batches);
  (* The scissor follows the intersected clip bounds; the shader's clip
     fields follow the innermost clip only. *)
  check (list scissor_t) "scissors"
    [ sc 40 40 80 80;
      sc 20 20 120 80 ]
    (scissors batches);
  let inner, outer =
    match all_insts batches with
    | [ a; b ] -> (a, b)
    | _ -> failwith "instances"
  in
  eq4 (40., 40., 40., 40.) inner.clip;
  eq4 (8., 8., 8., 8.) inner.clip_radii;
  eq4 (20., 20., 100., 60.) outer.clip;
  eq4 (4., 4., 4., 4.) outer.clip_radii

let test_empty_clip_skips () =
  let s = scene () in
  s.ops <-
    [ Push_clip
        { crect = rect (-100.) (-100.) 10. 10.; cradii = (0., 0., 0., 0.);
          ccontinuous = false };
      fill ~r:(rect 1. 1. 10. 10.) ();
      Pop_clip;
      fill ~r:(rect 25. 25. 5. 5.) () ];
  let batches = G.build s in
  check int "instances" 1 (List.length (all_insts batches));
  check (list scissor_t) "frame scissor"
    [ sc 0 0 200 100 ]
    (scissors batches)

let test_clip_off_frame () =
  let s = scene () in
  s.ops <-
    [ Push_clip
        { crect = rect (-50.) (-50.) 100. 100.; cradii = (2., 2., 2., 2.);
          ccontinuous = false };
      fill ~r:(rect 0. 0. 10. 10.) () ];
  let batches = G.build s in
  (* The clip's own rect reaches the shader; its intersection with the
     frame is the scissor. *)
  check (list scissor_t) "intersected"
    [ sc 0 0 50 50 ]
    (scissors batches);
  eq4 (-50., -50., 100., 100.) (List.hd (all_insts batches)).clip

(* ---------- holes ---------- *)

let test_holes () =
  let s = scene () in
  s.ops <-
    [ fill ~r:(rect 1. 1. 10. 10.) ();
      Hole
        { hrect = rect 10. 10. 5. 5.; hradii = (0., 0., 0., 0.);
          hcontinuous = false; hopacity = 1. };
      Hole
        { hrect = rect 20. 20. 5. 5.; hradii = (1., 2., 3., 4.);
          hcontinuous = false; hopacity = 0.5 };
      fill ~r:(rect 2. 2. 3. 3.) () ];
  let batches = G.build s in
  check int "batches" 3 (List.length batches);
  check (list bool) "hole flags" [ false; true; false ] (holes batches);
  let hb = List.nth batches 1 in
  check int "holes merge" 2 (List.length hb.instances);
  let h1, h2 = match hb.instances with [ a; b ] -> (a, b) | _ -> failwith "holes" in
  (* A hole is an opaque fill whose coverage is taken away. *)
  eq4 (0., 0., 0., 1.) h1.color;
  eq4 (0., 0., 0., 1.) h1.params;
  eq4 (0., 0., 0., 0.5) h2.params;
  (* Radii are fitted to the rect: 4+3 overflows the 5px height, so all
     corners scale by 5/7. *)
  eq4 (5. /. 7., 10. /. 7., 15. /. 7., 20. /. 7.) h2.radii;
  check (list scissor_t) "same scissor"
    (List.map (fun _ -> sc 0 0 200 100) [ 0; 1; 2 ])
    (scissors batches)

(* ---------- effects ---------- *)

let dummy_fx ename ebackdrop =
  { ename; ebackdrop; eglsl = "";
    epixels =
      (fun () ->
        { begin_effect = (fun _ _ _ -> ());
          color_at = (fun _ _ _ -> (0., 0., 0.)) }) }

let test_effect_backdrop () =
  let s = scene () in
  let fx = dummy_fx "glass" true in
  let flat = dummy_fx "flat" false in
  let params = [| (1., 2., 3., 4.); (0.5, 0.25, 0.75, 1.); (6., 7., 8., 9.);
                  (0.1, 0.2, 0.3, 0.4); (9., 8., 7., 6.) |] in
  s.effects <-
    [ { ee = fx; eblur = 10.; eparams = params };
      { ee = flat; eblur = 0.; eparams = params } ];
  s.ops <-
    [ fill ~r:(rect 0. 0. 200. 100.) ();
      Effect
        { edrect = rect 10. 10. 40. 40.; edradii = (2., 2., 2., 2.);
          edcontinuous = false; edindex = 0; edopacity = 0.8 };
      Effect
        { edrect = rect 50. 50. 20. 20.; edradii = (0., 0., 0., 0.);
          edcontinuous = false; edindex = 1; edopacity = 1. };
      fill ~r:(rect 1. 1. 5. 5.) () ];
  let batches = G.build s in
  (* Fill, effect1 in its own batch, effect2 in its own, trailing fill. *)
  check int "batches" 4 (List.length batches);
  let b1 = List.nth batches 1 and b2 = List.nth batches 2 in
  check int "effect batch size" 1 (List.length b1.instances);
  check string "effect" "glass"
    (match b1.fx with Some e -> e.ename | None -> "none");
  check string "effect2" "flat"
    (match b2.fx with Some e -> e.ename | None -> "none");
  (match b1.backdrop with
   | None -> fail "backdrop missing"
   | Some bk ->
     check (list int) "area" [ 0; 0; 86; 86 ]
       [ bk.barea.x0; bk.barea.y0; bk.barea.x1; bk.barea.y1 ];
     check int "down" 4 bk.bdown;
     check int "radius" 8 bk.bradius;
     check (float 1e-3) "sigma" 2.4833 bk.bsigma);
  check bool "no backdrop" true (b2.backdrop = None);
  let e1 = List.hd b1.instances and e2 = List.hd b2.instances in
  (* The effect's params fill inner/color/color2/border/grad; uv holds
     the backdrop's area origin and size in texels. *)
  eq4 (1., 2., 3., 4.) e1.inner;
  eq4 (0.5, 0.25, 0.75, 1.) e1.color;
  eq4 (9., 8., 7., 6.) e1.grad;
  eq4 (0., 0., 22., 22.) e1.uv;
  eq4 (6., 0., 4., 0.8) e1.params;
  eq4 (6., 0., 1., 1.) e2.params;
  eq4 (2., 2., 2., 2.) e1.radii;
  let w, h = G.backdrop_size batches in
  check (list int) "texture size" [ 22; 22 ] [ w; h ];
  (* down and blur passes over the backdrop. *)
  let bk = match b1.backdrop with Some b -> b | None -> failwith "bk" in
  let dp = G.down_pass bk ~shift:(0, 0) in
  check (list int) "down pass" [ 0; 0; 85; 85 ]
    [ fst dp.origin; snd dp.origin; fst dp.limit; snd dp.limit ];
  check int "down factor" 4 dp.down;
  let bp = G.blur_pass bk (0, 1) in
  check int "blur radius" 8 bp.radius;
  check (float 1e-3) "blur sigma" 2.4833 bp.sigma

(* ---------- glyph kinds ---------- *)

let test_glyph_kinds () =
  let s = scene () in
  s.text <-
    { gamma_ratios = (0.1, 0.2, 0.3, 0.4); contrast = 0.7;
      subpixel_contrast = 1.3 };
  s.glyphs <-
    [ glyph ~u:16 ~v:8 ~uw:8 ~vh:9 ();
      glyph ~u:4 ~v:4 ~uw:4 ~vh:4 ~colored:true ();
      glyph ~u:2 ~v:2 ~uw:6 ~vh:3 ~subpixel:true ~thin:true () ];
  s.ops <-
    [ Glyphs
        { gstart = 0; gend = 3; gpaint = Solid; gcolor = red;
          gcolor2 = red; ggradient = (0., 0., 0., 0.); gwide2 = 0;
          gopacity = 0. } ];
  let insts = all_insts (G.build s) in
  check int "glyphs" 3 (List.length insts);
  let mask_i, color_i, sub_i =
    match insts with [ a; b; c ] -> (a, b, c) | _ -> failwith "glyphs"
  in
  eq4 (2., 0., 0., 1.) mask_i.params;
  eq4 (0.25, 0.25, 0.375, 0.53125) mask_i.uv;
  eq4 (0.7, 0., 0., 0.) mask_i.inner;
  eq4 (0.1, 0.2, 0.3, 0.4) mask_i.radii;
  (* Color glyphs read the color atlas. *)
  eq4 (3., 0., 0., 1.) color_i.params;
  eq4 (0.125, 0.25, 0.25, 0.5) color_i.uv;
  (* Subpixel glyphs use the subpixel contrast and the thin boost. *)
  eq4 (5., 0., 0., 1.) sub_i.params;
  eq4 (1.3, 0.5, 0., 0.) sub_i.inner;
  eq4 (0.0625, 0.125, 0.25, 0.3125) sub_i.uv

let test_gradient_glyphs () =
  let s = scene () in
  s.glyphs <- [ glyph (); glyph ~colored:true () ];
  s.ops <-
    [ Glyphs
        { gstart = 0; gend = 2; gpaint = Oklab; gcolor = green;
          gcolor2 = red; ggradient = (1., 2., 3., 4.); gwide2 = 0;
          gopacity = 0.5 } ];
  let insts = all_insts (G.build s) in
  let mask_i, color_i =
    match insts with [ a; b ] -> (a, b) | _ -> failwith "glyphs"
  in
  (* Mask glyphs take the run's gradient colors and opacity. *)
  eq4 (0., 1., 0., 1.) mask_i.color;
  eq4 (1., 0., 0., 1.) mask_i.color2;
  eq4 (1., 2., 3., 4.) mask_i.grad;
  eq4 (2., 0., 2., 0.5) mask_i.params;
  (* Color glyphs keep their own color. *)
  eq4 (1., 0., 0., 1.) color_i.color;
  eq4 (0., 0., 0., 0.) color_i.color2;
  eq4 (3., 0., 0., 1.) color_i.params

(* ---------- wide gamut ---------- *)

let test_wide () =
  let wg = (-0.2, 1.1, -0.1, 1.) and wr = (1.1, -0.2, -0.1, 1.) in
  let s = scene ~w:100 ~h:100 () in
  s.wide <-
    [ { wcolor = wg; wcolor2 = (0., 0., 0., 0.); wborder = wr;
        wset = Lui_scene.wide_color lor Lui_scene.wide_border };
      { wcolor = wr; wcolor2 = (0., 0., 0., 0.); wborder = (0., 0., 0., 0.);
        wset = Lui_scene.wide_color };
      { wcolor = wg; wcolor2 = wr; wborder = (0., 0., 0., 0.);
        wset = Lui_scene.wide_color lor Lui_scene.wide_color2 } ];
  s.glyphs <- [ glyph ~c:red ~wide:2 (); glyph ~c:green () ];
  s.ops <-
    [ fill ~r:(rect 0. 0. 10. 10.) ~c:green ~c2:red
        ~bw:(uniform_border 1.) ~bc:red ~wide:1 ();
      Shadow
        { srect = rect 0. 0. 10. 10.; sradii = (0., 0., 0., 0.);
          scontinuous = false; scolor = red; sblur = 4.; sinset = false;
          scast = rect 0. 0. 0. 0.; scast_radii = (0., 0., 0., 0.);
          scast_continuous = false; swide = 2; sopacity = 0. };
      Glyphs
        { gstart = 0; gend = 2; gpaint = Solid; gcolor = red;
          gcolor2 = red; ggradient = (0., 0., 0., 0.); gwide2 = 0;
          gopacity = 0. };
      Glyphs
        { gstart = 0; gend = 2; gpaint = Oklab; gcolor = green;
          gcolor2 = red; ggradient = (0., 0., 0., 0.); gwide2 = 3;
          gopacity = 0. } ];
  let colors wide =
    List.map
      (fun (i : G.instance) -> (i.color, i.color2, i.border))
      (all_insts (G.build ~wide s))
  in
  let srgb_green = (0., 1., 0., 1.) and srgb_red = (1., 0., 0., 1.) in
  let zero4 = (0., 0., 0., 0.) in
  let compare expect got =
    check int "instance count" (List.length expect) (List.length got);
    List.iter2
      (fun (e_c, e_c2, e_b) (a_c, a_c2, a_b) ->
        eq4 e_c a_c; eq4 e_c2 a_c2; eq4 e_b a_b)
      expect got
  in
  compare
    [ (srgb_green, srgb_red, srgb_red); (srgb_red, zero4, zero4);
      (srgb_red, zero4, zero4); (srgb_green, zero4, zero4);
      (srgb_green, srgb_red, zero4); (srgb_green, srgb_red, zero4) ]
    (colors false);
  compare
    [ (wg, srgb_red, wr); (wr, zero4, zero4); (wr, zero4, zero4);
      (srgb_green, zero4, zero4); (wg, wr, zero4); (wg, wr, zero4) ]
    (colors true)

(* ---------- packing ---------- *)

let test_float32_packing () =
  let inst : G.instance =
    { rect = (0.1, 2., 3., 4.); radii = (5., 6., 7., 8.);
      inner = (9., 10., 11., 12.); color = (13., 14., 15., 16.);
      color2 = (17., 18., 19., 20.); border = (21., 22., 23., 24.);
      grad = (25., 26., 27., 28.); uv = (29., 30., 31., 32.);
      clip = (33., 34., 35., 36.); clip_radii = (37., 38., 39., 40.);
      params = (41., 42., 43., 44.) }
  in
  let a = G.to_float32_array inst in
  check int "stride" 44 G.instance_floats;
  check int "len" 44 (Array.length a);
  check (float 0.) "field order" 41. a.(40);
  check (float 0.) "radii start" 5. a.(4);
  check (float 0.) "params end" 44. a.(43);
  (* float32 rounding at the boundary. *)
  check (float 0.) "f32 rounding" 0.100000001490116119384765625 a.(0)

let test_shader_source () =
  check bool "shader embedded" true
    (String.length G.shader_source > 1000
     && String.sub G.shader_source 0 2 = "//")

let () =
  run "lui_gpu"
    [ ( "build",
        [ test_case "ops to batches" `Quick test_build;
          test_case "nested clips" `Quick test_nested_clips;
          test_case "empty clip skips" `Quick test_empty_clip_skips;
          test_case "clip off frame" `Quick test_clip_off_frame;
          test_case "holes" `Quick test_holes;
          test_case "effect with backdrop" `Quick test_effect_backdrop;
          test_case "glyph atlas kinds" `Quick test_glyph_kinds;
          test_case "gradient glyphs" `Quick test_gradient_glyphs;
          test_case "wide gamut" `Quick test_wide ] );
      ( "packing",
        [ test_case "to_float32_array" `Quick test_float32_packing;
          test_case "shader source" `Quick test_shader_source ] ) ]
