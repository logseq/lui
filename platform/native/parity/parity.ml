(* The shared scene corpus and pixel comparison behind the parity
   suite: the CPU evaluator and the GL renderer must draw the same
   Lui_scene.t to the same pixels, so this module owns the scenes both
   sides render, the byte comparison, and what each scene's
   comparison may show. *)

open Lui_scene
module Tk = Lui_raster_testkit.Testkit

(* {1 Frame comparison} *)

(* How two premultiplied-BGRA frames of [w]*[h] pixels differ.
   [masked] counts differing pixels [ignore]d by the caller — pixels
   the comparison is told cannot match (see [margin_ignores]). *)
type diff = {
  pixels : int;      (* pixels with any channel apart *)
  masked : int;      (* of those, pixels excluded via [ignore] *)
  beyond2 : int;     (* pixels beyond a delta of 2 — outside the rounding class *)
  max_delta : int;   (* largest per-channel delta *)
  first : int * int; (* first differing pixel, (-1, -1) when none *)
}

let diff_frames ~w ~h ~cpu ~gpu ?(ignore = fun _ _ -> false) () =
  let pixels = ref 0 and max_delta = ref 0 and first = ref (-1, -1) in
  let masked = ref 0 and beyond2 = ref 0 in
  for y = 0 to h - 1 do
    for x = 0 to w - 1 do
      let i = 4 * ((y * w) + x) in
      let d = ref 0 in
      for c = 0 to 3 do
        let dc =
          Int.abs
            (Char.code (Bytes.get cpu (i + c))
            - Char.code (Bytes.get gpu (i + c)))
        in
        if dc > !d then d := dc
      done;
      if !d > 0 then
        if ignore x y then incr masked
        else begin
          incr pixels;
          if !d > 2 then incr beyond2;
          if !d > !max_delta then max_delta := !d;
          if fst !first < 0 then first := (x, y)
        end
    done
  done;
  { pixels = !pixels; masked = !masked; beyond2 = !beyond2;
    max_delta = !max_delta; first = !first }

let report name { pixels; masked; beyond2; max_delta; first = (x, y) } =
  let tail =
    (if masked > 0 then
       Printf.sprintf "; +%d in unreachable quad-margin strips" masked
     else "")
    ^
    if beyond2 > 0 then Printf.sprintf "; %d beyond ±2" beyond2
    else ""
  in
  Printf.sprintf "%s: %d pixels differ (max delta %d, first at %d,%d%s)"
    name pixels max_delta x y tail

(* Pixels the GL rasterizer cannot draw: an image or a glyph quad has
   no margin, so where a rect's edge sits between pixel centers the
   partial-coverage strip outside is never rasterized — the CPU
   renderer's edge pixels there have no GPU counterpart. The strip is
   exactly the half-pixel ring outside each such rect. *)
let margin_ignores s =
  let ring rc =
    let x = rc.Lui_scene.x and y = rc.Lui_scene.y in
    let w = rc.Lui_scene.w and h = rc.Lui_scene.h in
    fun px py ->
      (px >= x -. 0.5 && px < x +. w +. 0.5 && py >= y -. 0.5
      && py < y +. h +. 0.5)
      && not (px >= x && px < x +. w && py >= y && py < y +. h)
  in
  let rings =
    List.concat_map
      (fun o ->
        match o with
        | Lui_scene.Image i -> [ ring i.Lui_scene.irect2 ]
        | Lui_scene.Glyphs g ->
          let rec loop k acc =
            if k >= g.Lui_scene.gend - g.Lui_scene.gstart then acc
            else
              let gl = List.nth s.Lui_scene.glyphs (g.Lui_scene.gstart + k) in
              loop (k + 1)
                (ring (Lui_scene.rect gl.Lui_scene.gx gl.Lui_scene.gy
                          gl.Lui_scene.gw gl.Lui_scene.gh)
                 :: acc)
          in
          loop 0 []
        | _ -> [])
      s.Lui_scene.ops
  in
  fun x y ->
    let px = float x +. 0.5 and py = float y +. 0.5 in
    List.exists (fun ring -> ring px py) rings

(* {1 What a comparison may show}

   [Exact]: the two renderers evaluate the same math and must agree
   byte for byte.  [Within (tol, why)]: the same math is evaluated in
   different precision or order — the CPU evaluator works in float64
   and quantizes through integer blending, the GPU evaluates in
   float32 and quantizes through the framebuffer's blending — so a
   channel may land an LSB either side of a rounding boundary and
   [why] says which computation earns the budget.  [Known why]: the
   renderers are documented to diverge, so differing pixels are
   required — agreement would mean the documented gap silently closed
   and the expectation should be tightened. *)

type expect =
  | Exact
  | Within of int * string
  | Loose of int * int * int * string
  (* strict tolerance, hard cap, max count beyond the tolerance, why *)
  | Known of string

(* The justifications. *)
let j_round =
  "same math at float64 (CPU) vs float32 (shader), with different \
   8-bit rounding at coverage and blend boundaries"

let j_grad =
  "gradient interpolation and the oklab power chain evaluate at \
   float32 in the shader vs float64 on the CPU"

let j_shadow =
  "the gaussian shadow falloff evaluates erf/pow at float32 in the \
   shader vs float64 on the CPU"

let j_subpix =
  "subpixel coverage convolves three taps per channel and the text \
   correction curve evaluates at different precision on each side"

let j_backdrop =
  "the downsampled blur is quantized to 8-bit after each pass on both \
   sides, but sums weights at different precision and order"

let j_effect =
  "the effect's GLSL twin computes at float32 what its CPU twin \
   computes at float64"

let j_boundary =
  "coverage at a fractional shape or clip edge is a steep function of \
   position, so a float32-vs-float64 boundary flip multiplies the \
   per-LSB rounding by the color contrast — a bounded few pixels"

(* {1 Parity effects}

   The golden scenes' test effects carry no GLSL, so parity keeps its
   own effects with both halves — the CPU twin ([epixels]) and its
   GLSL translation ([eglsl]) — which must produce the same pixels.
   The GLSL runs with [vec4 effect(vec2 p, Effect e)]; the Effect
   record carries the draw rect, fitted radii, the five params, the
   backdrop area and downsample, and sampleBackdrop reads the
   blurred backdrop. *)

let zero5 = [| Tk.no4; Tk.no4; Tk.no4; Tk.no4; Tk.no4 |]

let pgrad_fx =
  { ename = "pgrad"; ebackdrop = false;
    eglsl =
      "vec4 effect(vec2 p, Effect e) {\n\
       \treturn vec4(p.x / 100.0, p.y / 80.0, 0.6, 1.0);\n\
       }";
    epixels =
      (fun () ->
        { begin_effect = (fun _ _ _ -> ());
          color_at = (fun x y _ -> (x /. 100., y /. 80., 0.6, 1.)) }) }

let pdim_fx =
  { ename = "pdim"; ebackdrop = true;
    eglsl =
      "vec4 effect(vec2 p, Effect e) {\n\
       \treturn vec4(sampleBackdrop(e, p) * 0.5, 1.0);\n\
       }";
    epixels =
      (fun () ->
        { begin_effect = (fun _ _ _ -> ());
          color_at = (fun x y b ->
            match b with
            | Some b ->
              let r, g, bl = backdrop_sample b x y in
              (r *. 0.5, g *. 0.5, bl *. 0.5, 1.)
            | None -> (0., 0., 0., 0.)) }) }

let ptint_fx =
  { ename = "ptint"; ebackdrop = false;
    eglsl =
      "vec4 effect(vec2 p, Effect e) {\n\
       \treturn vec4(e.p1.rgb * e.p1.a, 1.0);\n\
       }";
    epixels =
      (fun () ->
        let op = ref zero5 in
        { begin_effect = (fun e _ _ -> op := e.eparams);
          color_at = (fun _ _ _ ->
            let t0, t1, t2, t3 = !op.(1) in
            (t0 *. t3, t1 *. t3, t2 *. t3, 1.)) }) }

let plens_fx =
  { ename = "plens"; ebackdrop = true;
    eglsl =
      "vec4 effect(vec2 p, Effect e) {\n\
       \tfloat d = max(8.0 + sdRoundRect(p, e.rect, e.radii), 0.0) * e.p0.x;\n\
       \tvec3 c = sampleBackdrop(e, vec2(p.x + d, p.y));\n\
       \treturn vec4(c + (e.p1.rgb - c) * e.p1.a, 1.0);\n\
       }";
    epixels =
      (fun () ->
        let op = ref zero5 in
        let rc = ref (rect 0. 0. 0. 0.) and ra = ref (0., 0., 0., 0.) in
        { begin_effect = (fun e r radii ->
            op := e.eparams;
            rc := r;
            ra := radii);
          color_at = (fun x y b ->
            match b with
            | Some b ->
              let k, _, _, _ = !op.(0) in
              let d =
                Float.max (8. +. sd_round_rect !rc !ra x y) 0. *. k
              in
              let c0, c1, c2 = backdrop_sample b (x +. d) y in
              let t0, t1, t2, t3 = !op.(1) in
              ( c0 +. ((t0 -. c0) *. t3),
                c1 +. ((t1 -. c1) *. t3),
                c2 +. ((t2 -. c2) *. t3), 1. )
            | None -> (0., 0., 0., 0.)) }) }

(* {1 Scenes authored for parity}

   What the golden scenes do not cover: wide-gamut fields (both
   renderers read the sRGB fallback of a wide color), a nested rounded
   clip, an image whose source rectangle is interior, glyph origins
   both renderers snap to integers, effects whose GLSL twins run on
   the GPU, and degenerate ops that draw nothing. *)

let checker () =
  (* a 4x4 image whose texels differ enough that sampling outside the
     source rectangle is visible *)
  let b = Bytes.create 64 in
  for y = 0 to 3 do
    for x = 0 to 3 do
      let i = 4 * ((y * 4) + x) in
      Bytes.set b i (Char.chr (40 + (50 * x)));
      Bytes.set b (i + 1) (Char.chr (200 - (40 * y)));
      Bytes.set b (i + 2) (Char.chr (60 + (30 * (x + y))));
      Bytes.set b (i + 3) '\255'
    done
  done;
  new_image ~w:4 ~h:4 b

let mask_atlas () =
  (* like the golden glyph scenes: an opaque block in one tile, a
     checkerboard in another *)
  let mask = Atlas.create ~bpp:1 ~w:64 ~h:16 in
  for y = 0 to 11 do
    for x = 0 to 11 do
      let v = if x < 2 || x > 9 || y < 2 || y > 9 then 255 else 0 in
      Bytes.set mask.Atlas.pix ((y * mask.Atlas.w) + x) (Char.chr v)
    done
  done;
  for y = 4 to 15 do
    for x = 20 to 31 do
      let m = if (x - 20 + y - 4) mod 4 < 2 then 255 else 0 in
      Bytes.set mask.Atlas.pix ((y * mask.Atlas.w) + x) (Char.chr m)
    done
  done;
  mask

let authored : (string * (unit -> Lui_scene.t) * expect) list =
  [ ( "fill_wide",
      (fun () ->
        let s = Tk.scene ~w:96 ~h:64 [] in
        let w =
          add_wide s
            { wcolor = (1.2, 0.4, 0.1, 1.); wcolor2 = Tk.no4;
              wborder = Tk.no4; wset = wide_color }
        in
        s.ops <-
          [ Fill
              { frect = rect 12. 10. 60. 40.; fradii = Tk.radii 8.;
                fcontinuous = false; fcolor = color 37 99 235 255;
                fpaint = Solid; fcolor2 = color 37 99 235 255;
                fgradient = Tk.no4; fborder = Tk.no4;
                fborder_color = Tk.transparent; fdashed = false;
                fwide = w; fopacity = 0. } ];
        s),
      Within (1, j_round) );
    ( "shadow_wide",
      (fun () ->
        let s = Tk.scene ~w:96 ~h:64 [] in
        let w =
          add_wide s
            { wcolor = Tk.no4; wcolor2 = Tk.no4;
              wborder = (0.9, 0.2, 0.6, 0.8); wset = wide_border }
        in
        s.ops <-
          [ Shadow
              { srect = rect 24. 18. 48. 32.; sradii = Tk.radii 8.;
                scontinuous = false; scolor = color 0 0 0 90;
                sblur = 8.; sinset = false; scast = rect 0. 0. 0. 0.;
                scast_radii = Tk.no4; scast_continuous = false;
                swide = w; sopacity = 0. } ];
        s),
      Within (1, j_shadow) );
    ( "glyph_wide",
      (fun () ->
        let mask = mask_atlas () in
        let s =
          Tk.scene ~w:64 ~h:48 ~mask [ Tk.iglyphs 0 1 ]
        in
        let w =
          add_wide s
            { wcolor = (1.1, 0.3, 0.7, 1.); wcolor2 = Tk.no4;
              wborder = Tk.no4; wset = wide_color }
        in
        s.glyphs <-
          [ { (Tk.glyph ~x:10. ~y:8. ~w:12. ~h:12. ~u:0 ~v:0 ~uw:12 ~vh:12
                 Tk.black)
              with gwide = w } ];
        s),
      Within (1, j_round) );
    ( "clip_nested_round",
      (fun () ->
        Tk.scene ~w:96 ~h:64
          [ Tk.iclip ~radii:(Tk.radii 18.) (rect 8. 8. 80. 48.);
            Tk.iclip ~radii:(Tk.radii 6.) (rect 0. 0. 44. 44.);
            Tk.ifill (rect 0. 0. 96. 64.) (color 37 99 235 255);
            Pop_clip;
            Tk.ifill (rect 0. 0. 96. 64.) (color 16 185 129 110);
            Pop_clip ]),
      Within (1, j_round) );
    ( "image_interior",
      (fun () ->
        Tk.scene ~w:96 ~h:64
          [ Tk.iimage (rect 10. 10. 60. 40.) (checker ()) (rect 1. 1. 2. 2.) ]),
      Within (1, j_round) );
    ( "image_frac",
      (fun () ->
        Tk.scene ~w:96 ~h:64
          [ Tk.iimage (rect 22.8 36.4 32.9 22.6) (checker ())
              (rect 0. 0. 4. 4.) ]),
      Within (1, j_boundary) );
    ( "image_empty_src",
      (fun () ->
        Tk.scene ~w:96 ~h:64
          [ Tk.iimage (rect 10. 10. 60. 40.) (checker ()) (rect 0. 0. 0. 0.) ]),
      Exact );
    ( "glyph_frac",
      (fun () ->
        let mask = mask_atlas () in
        Tk.scene ~w:64 ~h:48 ~mask
          ~glyphs:
            [ Tk.glyph ~x:10.4 ~y:8.6 ~w:12. ~h:12. ~u:0 ~v:0 ~uw:12 ~vh:12
                Tk.black;
              Tk.glyph ~x:24.6 ~y:6.3 ~w:12. ~h:12. ~u:20 ~v:4 ~uw:12 ~vh:12
                (color 200 30 30 160) ]
          [ Tk.iglyphs 0 2 ]),
      Within (1, j_round) );
    ( "clip_frac",
      (fun () ->
        Tk.scene ~w:96 ~h:64
          [ Tk.iclip (rect 10.5 10.25 76. 44.);
            Tk.ifill (rect 0. 0. 96. 64.) (color 37 99 235 255);
            Pop_clip ]),
      Within (1, j_round) );
    ( "degenerate",
      (fun () ->
        Tk.scene ~w:64 ~h:48 ~clear:(color 12 20 30 255)
          [ Tk.ifill (rect 20. 20. 0. 0.) (color 255 0 0 255);
            Tk.ihole ~opacity:0. (rect 8. 8. 10. 10.);
            Tk.ishadow ~blur:0. (rect 30. 30. 10. 8.) (color 0 0 0 200);
            Tk.iclip (rect 200. 200. 5. 5.);
            Tk.ifill (rect 0. 0. 64. 48.) (color 0 255 0 255);
            Pop_clip;
            Tk.ifill ~radii:Tk.no4 (rect 8. 8. 20. 12.) (color 40 40 200 255) ]),
      Exact );
    ( "empty",
      (fun () -> Tk.scene ~w:64 ~h:48 ~clear:(color 30 60 90 255) []),
      Exact );
    ( "fx_grad",
      (fun () ->
        Tk.scene ~w:96 ~h:64
          ~effects:[ { ee = pgrad_fx; eblur = 0.; eparams = zero5 } ]
          [ Tk.ifill (rect 0. 0. 96. 64.) (color 250 230 200 255);
            Tk.ieffect ~radii:(Tk.radii 8.) (rect 18. 10. 60. 44.) 0 ]),
      Within (1, j_effect) );
    ( "fx_tint",
      (fun () ->
        Tk.scene ~w:96 ~h:64
          ~effects:
            [ { ee = ptint_fx; eblur = 0.;
                eparams =
                  [| Tk.no4; (0.2, 0.5, 0.9, 0.5); Tk.no4; Tk.no4; Tk.no4 |] } ]
          [ Tk.ifill (rect 0. 0. 96. 64.) (color 240 240 255 255);
            Tk.ieffect ~radii:(Tk.radii 6.) (rect 16. 8. 64. 48.) 0 ]),
      Within (1, j_effect) );
    ( "fx_dim",
      (fun () ->
        Tk.scene ~w:96 ~h:64
          ~effects:[ { ee = pdim_fx; eblur = 8.; eparams = zero5 } ]
          [ Tk.ifill (rect 0. 0. 96. 64.) (color 37 99 235 255);
            Tk.ifill (rect 20. 10. 40. 30.) (color 250 204 21 255);
            Tk.ieffect ~radii:(Tk.radii 6.) (rect 12. 8. 60. 40.) 0 ]),
      Within (2, j_backdrop) );
    ( "fx_lens",
      (fun () ->
        Tk.scene ~w:96 ~h:64
          ~effects:
            [ { ee = plens_fx; eblur = 6.;
                eparams =
                  [| (0.6, 0., 0., 0.); (0.9, 0.3, 0.2, 0.35); Tk.no4;
                     Tk.no4; Tk.no4 |] } ]
          [ Tk.ifill (rect 0. 0. 96. 64.) (color 16 185 129 255);
            Tk.ifill (rect 30. 8. 44. 30.) (color 220 38 38 255);
            Tk.ieffect ~radii:(Tk.radii 10.) (rect 16. 8. 64. 44.) 0 ]),
      Within (2, j_backdrop) );
    ( "fx_two",
      (fun () ->
        Tk.scene ~w:96 ~h:64
          ~effects:
            [ { ee = pgrad_fx; eblur = 0.; eparams = zero5 };
              { ee = pdim_fx; eblur = 6.; eparams = zero5 } ]
          [ Tk.ifill (rect 0. 0. 96. 64.) (color 240 240 255 255);
            Tk.ieffect (rect 8. 8. 24. 24.) 0;
            Tk.ifill (rect 40. 20. 30. 20.) (color 200 100 40 255);
            Tk.ieffect ~radii:(Tk.radii 6.) (rect 56. 30. 24. 24.) 1 ]),
      Within (2, j_backdrop) ) ]

(* {1 The corpus}

   The golden scenes of the CPU test suite — the same Lui_scene.t
   values on both sides — plus the authored scenes above. The golden
   effect scenes stay: their empty GLSL selects the renderer's
   built-in twin of the effect's name, which the CPU twin computes on
   the other side. *)

let golden : (string * expect) list =
  [ ("fill_round", Within (1, j_round));
    ("fill_square", Within (1, j_round));
    ("fill_cont", Within (1, j_boundary));
    ("fill_cont_pill", Within (1, j_boundary));
    ("fill_linear", Within (1, j_grad));
    ("fill_oklab", Within (2, j_grad));
    ("fill_linear_t", Within (1, j_grad));
    ("fill_stripes", Within (1, j_round));
    ("fill_dashed", Within (1, j_round));
    ("shadow_cast", Within (1, j_shadow));
    ("shadow_caster", Within (1, j_shadow));
    ("shadow_inset", Within (1, j_shadow));
    ("clip_nested", Within (1, j_round));
    ("clip_cont", Within (1, j_boundary));
    ("hole", Within (1, j_round));
    ("image_ops", Within (1, j_round));
    ("glyphs", Within (1, j_round));
    ("glyphs_color", Within (2, j_subpix));
    ("glyphs_text", Within (1, j_subpix));
    ("effect", Within (1, j_boundary));
    ("effect_backdrop", Within (2, j_backdrop));
    ("edges", Within (1, j_round));
    ("two_effects", Within (1, j_boundary)) ]

let corpus : (string * (unit -> Lui_scene.t) * expect) list =
  List.map
    (fun (n, build) -> (n, build, List.assoc n golden))
    Tk.golden_scenes
  @ authored
