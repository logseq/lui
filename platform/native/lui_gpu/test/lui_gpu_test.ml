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

let test_transparent_fills () =
  let s = scene () in
  s.ops <- [fill ~c:black ~c2:black (); fill ~op:0. ();
            fill ~c:black ~c2:black ~bw:(uniform_border 2.) ~bc:red ();
            fill ~c:black ~c2:red ~paint:Linear (); fill ()];
  let instances = all_insts (G.build s) in
  check int "transparent fill consumes no GPU work; zero opacity keeps legacy semantics" 4 (List.length instances);
  check bool "visible border survives" true
    (List.exists (fun (i : G.instance) -> i.uv = uniform_border 2.) instances)

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
          color_at = (fun _ _ _ -> (0., 0., 0., 0.)) }) }

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
      params = (41., 42., 43., 44.);
      clip2 = (45., 46., 47., 48.); clip2_radii = (49., 50., 51., 52.);
      clip3 = (53., 54., 55., 56.); clip3_radii = (57., 58., 59., 60.) }
  in
  let a = G.to_float32_array inst in
  check int "stride" 60 G.instance_floats;
  check int "len" 60 (Array.length a);
  check (float 0.) "field order" 41. a.(40);
  check (float 0.) "radii start" 5. a.(4);
  check (float 0.) "params end" 44. a.(43);
  check (float 0.) "clip3 end" 60. a.(59);
  (* float32 rounding at the boundary. *)
  check (float 0.) "f32 rounding" 0.100000001490116119384765625 a.(0)

let test_clip_allocations () =
  let s = scene () in
  let fills = List.init 1000 (fun _ -> fill ()) in
  let clip = Push_clip {crect = rect 0. 0. 200. 100.; cradii = (3., 3., 3., 3.); ccontinuous = false} in
  let allocate ops =
    s.ops <- ops;
    let before = Gc.minor_words () in
    let batches = G.build s in
    let words = Gc.minor_words () -. before in
    check int "all visible instances survive clipping" 1000
      (List.fold_left (fun count (b : G.batch) -> count + List.length b.instances) 0 batches);
    words *. 8.
  in
  let plain = allocate fills in
  let clipped = allocate (clip :: clip :: clip :: clip :: fills) in
  let extra = clipped -. plain in
  check bool (Printf.sprintf "Nested clipping allocates %.0f extra bytes" extra)
    true (extra < 32000.)

let test_pack_allocations () =
  let s = scene () in
  s.ops <- [fill ()];
  let inst = List.hd (all_insts (G.build s)) in
  let dst = Bigarray.(Array1.create float32 c_layout (G.instance_floats * 1000)) in
  let before = Gc.minor_words () in
  for index = 0 to 999 do
    G.pack_instance inst dst ~ofs:(index * G.instance_floats)
  done;
  let allocated = (Gc.minor_words () -. before) *. 8. in
  check bool (Printf.sprintf "Packing allocates %.0f bytes for 1000 instances" allocated)
    true (allocated < 16000.);
  check (float 0.) "last packed rectangle" 1.
    (Bigarray.Array1.get dst (999 * G.instance_floats))

let test_shader_source () =
  check bool "shader embedded" true
    (String.length G.shader_source > 1000
     && String.sub G.shader_source 0 2 = "//")

(* ---------- scene batch cache ---------- *)

let ops_scene ?(w = 200) ?(h = 100) ops =
  let s = scene ~w ~h () in
  s.ops <- ops;
  s

let frame3 c ?(wide = false) s = G.frame ~wide c s

let test_cache_hit () =
  let s = ops_scene [ fill () ] in
  let c = G.batch_cache () in
  let b1, p1, r1 = frame3 c s in
  check bool "first builds" true r1;
  let b2, p2, r2 = frame3 c s in
  check bool "second reuses" false r2;
  check bool "same batches" true (b1 == b2);
  check bool "same buffer" true (p1.data == p2.data);
  check int "rebuilds" 1 (G.stat_rebuilds c);
  check int "reuses" 1 (G.stat_reuses c)

let test_cache_touch () =
  let s = ops_scene [ fill () ] in
  let c = G.batch_cache () in
  let b1, _, _ = frame3 c s in
  s.ops <- [ fill ~r:(rect 5. 5. 20. 20.) () ];
  (* Writers that mutate outside reset must touch: the cache only
     rebuilds because the revision moved. *)
  Lui_scene.touch s;
  let b2, _, r = frame3 c s in
  check bool "touch rebuilds" true r;
  check bool "fresh batches" true (b1 != b2);
  check int "rebuilds" 2 (G.stat_rebuilds c)

(* A scene object the cache has never compiled always rebuilds, even
   one byte-identical to the compiled scene — the key pairs identity
   with revision. *)
let test_cache_identity () =
  let ops () = [ fill () ] in
  let s1 = ops_scene (ops ()) and s2 = ops_scene (ops ()) in
  let c = G.batch_cache () in
  ignore (frame3 c s1);
  let _, _, r2 = frame3 c s2 in
  check bool "another scene rebuilds" true r2;
  let _, _, r3 = frame3 c s2 in
  check bool "then reuses" false r3;
  let _, _, r4 = frame3 c s1 in
  check bool "back to first rebuilds" true r4

(* The inputs build folds into instances that the revision does not
   capture — frame size, text coverage, atlas size, the gamut flag —
   are in the key: each change recompiles. *)
let test_cache_key_inputs () =
  let s = scene ~w:200 ~h:100 () in
  s.glyphs <- [ glyph () ];
  s.ops <-
    [ Glyphs
        { gstart = 0; gend = 1; gpaint = Solid; gcolor = red;
          gcolor2 = red; ggradient = (0., 0., 0., 0.); gwide2 = 0;
          gopacity = 0. } ];
  let c = G.batch_cache () in
  let _, _, r0 = frame3 c s in
  check bool "build" true r0;
  s.width <- 300;
  let _, _, r1 = frame3 c s in
  check bool "width rebuilds" true r1;
  let _, _, r1b = frame3 c s in
  check bool "width then reuses" false r1b;
  s.text <- { s.text with contrast = 1.5 };
  let _, _, r2 = frame3 c s in
  check bool "text params rebuild" true r2;
  ignore (Atlas.grow s.mask_atlas);
  let _, p, r3 = frame3 c s in
  check bool "atlas growth rebuilds" true r3;
  (* Glyph UVs are baked over the doubled atlas: 16/128 = 0.125.
     [uv] is the instance's eighth float4, floats 28-31. *)
  check (float 1e-3) "uv re-based" 0.125 p.data.{28};
  let _, _, r4 = frame3 ~wide:true c s in
  check bool "wide flag rebuilds" true r4;
  let _, _, r5 = frame3 ~wide:true c s in
  check bool "wide then reuses" false r5

(* The staging buffer is grow-only: a smaller later scene reuses it
   with a shorter live prefix. *)
let test_cache_buffer_growth () =
  let s = ops_scene [ fill (); fill (); fill () ] in
  let c = G.batch_cache () in
  let _, p1, _ = frame3 c s in
  check int "three instances" (3 * G.instance_floats) p1.floats;
  let cap = Bigarray.Array1.dim p1.data in
  s.ops <- [ fill () ];
  Lui_scene.touch s;
  let _, p2, _ = frame3 c s in
  check int "one instance" G.instance_floats p2.floats;
  check bool "same buffer" true (p1.data == p2.data);
  check bool "capacity kept" true (Bigarray.Array1.dim p2.data = cap)

(* ---------- cache benchmark ---------- *)

(* What the GPU marshalling pays per frame on a glyph-heavy scene, the
   text-500 profile: 500 Glyphs ops indexing 24k glyph records.
   Reports uncached build+pack against cached frames, hit and miss. *)
let bench_cache () =
  let n_ops, n_glyphs = 500, 48 in
  let s = scene ~w:1280 ~h:800 () in
  s.glyphs <-
    List.init (n_ops * n_glyphs) (fun i ->
        glyph ~x:(Float.of_int (i mod 1000))
          ~y:(Float.of_int ((i / 50) mod 700)) ());
  s.ops <-
    List.init n_ops (fun i ->
        Glyphs
          { gstart = i * n_glyphs; gend = (i + 1) * n_glyphs;
            gpaint = Solid; gcolor = red; gcolor2 = red;
            ggradient = (0., 0., 0., 0.); gwide2 = 0; gopacity = 0. });
  let insts =
    List.fold_left
      (fun n (b : G.batch) -> n + List.length b.instances)
      0 (G.build s)
  in
  let iters = 200 in
  let timed f =
    let t0 = Sys.time () in
    ignore (f ());
    (Sys.time () -. t0) *. 1000. /. Float.of_int iters
  in
  let uncached =
    timed (fun () ->
        for _ = 1 to iters do
          ignore (G.pack_batches (G.build s))
        done)
  in
  let c = G.batch_cache () in
  ignore (frame3 c s);
  let hit =
    timed (fun () ->
        for _ = 1 to iters do
          ignore (frame3 c s)
        done)
  in
  let c2 = G.batch_cache () in
  let miss =
    timed (fun () ->
        for _ = 1 to iters do
          (* Every frame a repaint: touch, compile, pack. *)
          Lui_scene.touch s;
          ignore (frame3 c2 s)
        done)
  in
  Printf.printf
    "\n  gpu-frame cache, %d instances/frame\n\
    \  build+pack uncached : %8.3f ms\n\
    \  cache hit           : %8.4f ms\n\
    \  cache miss          : %8.3f ms\n\
    %!"
    insts uncached hit miss;
  check int "one hit per frame" iters (G.stat_reuses c);
  check int "misses rebuild" iters (G.stat_rebuilds c2)

let test_hover_glyph_allocation () =
  let s = scene ~w:1280 ~h:800 () in
  s.glyphs <- List.init 1000 (fun i -> glyph ~x:(Float.of_int (i mod 100)*.10.)
    ~y:(Float.of_int (i/100)*.20.) ());
  let text = Glyphs {gstart=0;gend=1000;gpaint=Solid;gcolor=red;gcolor2=red;
    ggradient=(0.,0.,0.,0.);gwide2=0;gopacity=1.} in
  s.ops <- [fill ();text];
  let cache = G.batch_cache () in
  ignore (frame3 cache s);
  let before = Gc.allocated_bytes () in
  for i=1 to 20 do
    s.ops <- [fill ~c:(if i mod 2=0 then red else green) ();text];
    touch s;
    ignore (frame3 cache s)
  done;
  let allocated = (Gc.allocated_bytes () -. before) /. 20. in
  Printf.printf "hover scene with 1000 stable glyphs allocated %.0f bytes/frame\n%!" allocated;
  check bool "Changing one hover fill must not regenerate all stable glyph instances"
    true (allocated < 131072.);
  check bool "Cached hover scene changed instance values" true
    (all_insts (let b,_,_ = frame3 cache s in b) = all_insts (G.build s))

let test_glyph_reuse_inputs () =
  let s = scene () and cache = G.batch_cache () in
  s.glyphs <- [glyph ~wide:1 (); glyph ~subpixel:true (); glyph ~colored:true ()];
  let text = {gstart=0;gend=3;gpaint=Solid;gcolor=red;gcolor2=green;
    ggradient=(1.,2.,3.,4.);gwide2=1;gopacity=0.6} in
  let check_frame ~wide message =
    touch s;
    let batches,_,_ = frame3 ~wide cache s in
    check bool message true (all_insts batches = all_insts (G.build ~wide s)) in
  s.ops <- [Glyphs text];
  s.wide <- [{wcolor=(0.8,0.2,0.1,1.);wcolor2=(0.1,0.3,0.8,1.);
    wborder=(0.,0.,0.,0.);wset=wide_color lor wide_color2}];
  check_frame ~wide:false "cold glyphs";
  check_frame ~wide:false "retained glyphs";
  s.text <- {gamma_ratios=(0.1,0.2,0.3,0.4);contrast=0.8;subpixel_contrast=1.2};
  check_frame ~wide:false "changed text coverage";
  check bool "mask atlas grew" true (Atlas.grow s.mask_atlas);
  check bool "color atlas grew" true (Atlas.grow s.color_atlas);
  check_frame ~wide:false "changed atlas dimensions";
  s.ops <- [Push_clip {crect=rect 0. 0. 80. 60.;cradii=(1.,2.,3.,4.);
    ccontinuous=false};Glyphs {text with gpaint=Linear};Pop_clip];
  check_frame ~wide:true "gradient and rounded clipping";
  s.wide <- [{wcolor=(0.2,0.4,0.6,1.);wcolor2=(0.6,0.4,0.2,1.);
    wborder=(0.,0.,0.,0.);wset=wide_color lor wide_color2}];
  check_frame ~wide:true "changed wide colors";
  s.ops <- [Glyphs {text with gpaint=Oklab;gopacity=0.2;ggradient=(4.,3.,2.,1.)}];
  check_frame ~wide:false "changed gradient and opacity";
  s.glyphs <- [glyph ~x:35. ~y:45. ~c:green ()];
  s.ops <- [Glyphs {text with gend=1}];
  check_frame ~wide:false "replaced glyph geometry and color"

let test_glyph_reuse_lifetime () =
  let cache = G.batch_cache () in
  let weak =
    let s = scene () and weak = Weak.create 1 in
    let original = glyph () in
    Weak.set weak 0 (Some original);
    s.glyphs <- [original];
    s.ops <- [Glyphs {gstart=0;gend=1;gpaint=Solid;gcolor=red;gcolor2=red;
      ggradient=(0.,0.,0.,0.);gwide2=0;gopacity=1.}];
    ignore (frame3 cache s);
    weak in
  let empty = scene () in
  ignore (frame3 cache empty);
  Gc.full_major (); Gc.full_major ();
  check bool "Removed text must not remain alive through the GPU cache" false (Weak.check weak 0)

let test_replaced_glyph_cache_bound () =
  (* Other retained snapshots may still own old glyphs. That must not
     make this renderer keep compiled data for every historical frame. *)
  let snapshots = Array.init 100 (fun _ ->
    List.init 400 (fun i -> glyph ~x:(Float.of_int (i mod 80) *. 10.)
      ~y:(Float.of_int (i / 80) *. 20.) ())) in
  let s = scene ~w:1280 ~h:800 () and cache = G.batch_cache () in
  s.ops <- [Glyphs {gstart=0;gend=400;gpaint=Solid;gcolor=red;gcolor2=red;
    ggradient=(0.,0.,0.,0.);gwide2=0;gopacity=1.}];
  Gc.full_major (); Gc.full_major ();
  let baseline = (Gc.stat ()).Gc.live_words in
  Array.iter (fun glyphs -> s.glyphs <- glyphs; touch s; ignore (frame3 cache s)) snapshots;
  Gc.full_major (); Gc.full_major ();
  let retained = ((Gc.stat ()).Gc.live_words - baseline) * (Sys.word_size / 8) in
  Printf.printf "replaced glyphs retained %d bytes of renderer data\n%!" retained;
  check bool "Historical text snapshots accumulated compiled GPU instances"
    true (retained < 1048576);
  check bool "Replacement changed the current rendered text" true
    (all_insts (let b,_,_ = frame3 cache s in b) = all_insts (G.build s));
  ignore (Sys.opaque_identity snapshots)

let () =
  run "lui_gpu"
    [ ( "build",
        [ test_case "ops to batches" `Quick test_build;
          test_case "transparent fills" `Quick test_transparent_fills;
          test_case "nested clips" `Quick test_nested_clips;
          test_case "nested clip allocations" `Quick test_clip_allocations;
          test_case "empty clip skips" `Quick test_empty_clip_skips;
          test_case "clip off frame" `Quick test_clip_off_frame;
          test_case "holes" `Quick test_holes;
          test_case "effect with backdrop" `Quick test_effect_backdrop;
          test_case "glyph atlas kinds" `Quick test_glyph_kinds;
          test_case "gradient glyphs" `Quick test_gradient_glyphs;
          test_case "wide gamut" `Quick test_wide ] );
      ( "packing",
        [ test_case "to_float32_array" `Quick test_float32_packing;
          test_case "packing allocations" `Quick test_pack_allocations;
          test_case "shader source" `Quick test_shader_source ] );
      ( "batch cache",
        [ test_case "hit reuses" `Quick test_cache_hit;
          test_case "touch rebuilds" `Quick test_cache_touch;
          test_case "scene identity" `Quick test_cache_identity;
          test_case "key inputs" `Quick test_cache_key_inputs;
          test_case "buffer growth" `Quick test_cache_buffer_growth;
          test_case "stable glyph hover allocations" `Quick test_hover_glyph_allocation;
          test_case "glyph reuse inputs" `Quick test_glyph_reuse_inputs;
          test_case "glyph reuse lifetime" `Quick test_glyph_reuse_lifetime;
          test_case "replaced glyph cache bound" `Quick test_replaced_glyph_cache_bound;
          test_case "bench" `Quick bench_cache ] ) ]
