(* Liquid-glass materials as scene effects, ported from the reference
   plugin: a glass pane that blurs, lenses and rim-lights what shows
   through, a plain backdrop blur that can fade along a mask, and a
   scroll-edge wash over content scrolling under a bar.

   Each material is a Lui_scene.fx effect: one shading source that
   every GPU backend compiles (as GLSL on OpenGL and Vulkan, mapped to
   HLSL by the Direct3D shim, and to the Metal language where
   __METAL_VERSION__ is defined), plus a CPU twin the raster runs. The
   helpers append the effects' draw ops to a scene's display list; the
   scene's own Effect op carries the material in its five params, so
   the instance encoding needs nothing new. *)

open Lui_scene

let fmin = min and fmax = max
let fclamp lo hi v = fmin (fmax v lo) hi
let sgn v = if v > 0. then 1. else if v < 0. then -1. else 0.
let transparent = color 0 0 0 0
let pi2 = Float.pi /. 2.

(* {1 Shared shading prelude}

   The backends differ in two places: Metal names its float types
   float2/3/4 and hands the effect its backdrop texture as an argument,
   where the others keep a global uBackdrop sampler (which the Direct3D
   shim then maps to its Texture2D). FX_BD adds the texture parameter
   to signatures, FX_BD_ARG passes it at call sites, and BD_RGB samples
   it RGB; vec2-style names keep the bodies single-sourced, as the
   Direct3D shim does on its side. *)
let shader_prelude =
  "#ifdef __METAL_VERSION__\n\
   #  define vec2 float2\n\
   #  define vec3 float3\n\
   #  define vec4 float4\n\
   #  define ivec2 int2\n\
   #  define abs fabs\n\
   #  define FX_BD , texture2d<float> fxBd\n\
   #  define FX_BD_ARG , fxBd\n\
   #  define BD_RGB(e, q) sampleBackdrop(fxBd, e, q)\n\
   #else\n\
   #  define FX_BD\n\
   #  define FX_BD_ARG\n\
   #  define BD_RGB(e, q) sampleBackdrop(e, q)\n\
   #endif\n"

(* {1 The glass effect}

   What is behind the pane, blurred, sampled within the bezel where the
   curved surface refracts it, mapped from its lightness (tone), tinted,
   and lit along the rim. p0 is the bezel, the refraction, the rim and
   its width; p1 the tint; p2 the low, high, curve and saturation; p3
   the light's direction. *)
let glass_glsl =
  shader_prelude
  ^ "\n\
     float glassLens(float t, float bezel) {\n\
     \tif (bezel <= 0.0 || t >= bezel) {\n\
     \t\treturn 0.0;\n\
     \t}\n\
     \tfloat u = 1.0 - max(t, 0.0) / bezel;\n\
     \tfloat v = 1.0 - u * u * u * u;\n\
     \tfloat a = sqrt(v * sqrt(v));\n\
     \tfloat b = u * u * u;\n\
     \tfloat n = sqrt(a * a + b * b);\n\
     \tfloat s = b / n;\n\
     \tfloat c = a / n;\n\
     \tfloat st = s / 1.5;\n\
     \tfloat ct = sqrt(1.0 - st * st);\n\
     \treturn (s * ct - c * st) / (c * ct + s * st) / 1.1180340;\n\
     }\n\n\
     vec2 glassNormal(vec2 p, vec4 rect, vec4 radii) {\n\
     \tvec2 h = rect.zw * 0.5;\n\
     \tvec2 q = p - rect.xy - h;\n\
     \tfloat r = q.x < 0.0 ? (q.y < 0.0 ? radii.x : radii.w) : (q.y < 0.0 ? radii.y : radii.z);\n\
     \tr = min(r * 1.5, min(h.x, h.y));\n\
     \tvec2 a = abs(q) - (h - r);\n\
     \tif (a.x > 0.0 || a.y > 0.0) {\n\
     \t\tvec2 m = max(a, vec2(0.0));\n\
     \t\treturn sign(q) * m / sqrt(m.x * m.x + m.y * m.y);\n\
     \t}\n\
     \treturn a.x > a.y ? vec2(sign(q.x), 0.0) : vec2(0.0, sign(q.y));\n\
     }\n\n\
     vec3 glassTone(vec3 c, vec4 tone) {\n\
     \tfloat l = 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b;\n\
     \tfloat t = tone.x + (tone.y - tone.x) * (1.0 - pow(max(1.0 - l, 0.0), tone.z));\n\
     \tfloat k = (tone.y - tone.x) * tone.w;\n\
     \treturn clamp(t + (c - l) * k, 0.0, 1.0);\n\
     }\n\n\
     vec4 effect(vec2 p, Effect e FX_BD) {\n\
     \tfloat t = max(-sdRoundRect(p, e.rect, e.radii), 0.0);\n\
     \tfloat bezel = e.p0.x;\n\
     \tfloat rimWidth = e.p0.w;\n\
     \tvec2 n = vec2(0.0);\n\
     \tif (t < bezel || t < 3.0 * rimWidth) {\n\
     \t\tn = glassNormal(p, e.rect, e.radii);\n\
     \t}\n\
     \tvec2 q = p;\n\
     \tif (t < bezel) {\n\
     \t\tq -= n * (e.p0.y * glassLens(t, bezel));\n\
     \t}\n\
     \tvec3 c = glassTone(BD_RGB(e, q), e.p2);\n\
     \tc += (e.p1.rgb - c) * e.p1.a;\n\
     \tif (e.p0.z > 0.0 && t < 3.0 * rimWidth) {\n\
     \t\tfloat r = t / rimWidth;\n\
     \t\tfloat a = e.p0.z * exp(-r * r);\n\
     \t\tfloat l = abs(n.x * e.p3.x + n.y * e.p3.y);\n\
     \t\tc += (l - c) * a;\n\
     \t}\n\
     \treturn vec4(c, 1.0);\n\
     }\n"

(* {1 The blur effect}

   One level of a blur: what is behind it, blurred, by how much the
   level shows at each pixel along the mask's band. p0 is the mask
   line's From and To points, p1 the blur at each end and the level's
   lo/hi band, p2 the tone (saturation, offset, mix), p3 the mix's
   color. *)
let blur_glsl =
  shader_prelude
  ^ "\n\
     vec4 blurAt(ivec2 p, ivec2 size FX_BD) {\n\
     #ifdef __METAL_VERSION__\n\
     \treturn fxBd.read(uint2(clamp(p, int2(0), size - 1)));\n\
     #else\n\
     \treturn texelFetch(uBackdrop, clamp(p, ivec2(0), size - 1), 0);\n\
     #endif\n\
     }\n\n\
     vec4 blurSample(Effect e, vec2 q FX_BD) {\n\
     \tvec2 u = (q - e.area.xy) / e.down - 0.5;\n\
     \tvec2 f = floor(u);\n\
     \tvec2 w = u - f;\n\
     \tivec2 p = ivec2(f);\n\
     \tivec2 size = ivec2(e.area.zw);\n\
     \tvec4 top = blurAt(p, size FX_BD_ARG) * (1.0 - w.x)\n\
     \t         + blurAt(p + ivec2(1, 0), size FX_BD_ARG) * w.x;\n\
     \tvec4 bot = blurAt(p + ivec2(0, 1), size FX_BD_ARG) * (1.0 - w.x)\n\
     \t         + blurAt(p + ivec2(1, 1), size FX_BD_ARG) * w.x;\n\
     \treturn top * (1.0 - w.y) + bot * w.y;\n\
     }\n\n\
     vec4 effect(vec2 p, Effect e FX_BD) {\n\
     \tvec2 d = e.p0.zw - e.p0.xy;\n\
     \tfloat l = d.x * d.x + d.y * d.y;\n\
     \tfloat t = 0.0;\n\
     \tif (l > 0.0) {\n\
     \t\tt = clamp(((p.x - e.p0.x) * d.x + (p.y - e.p0.y) * d.y) / max(l, 0.0001), 0.0, 1.0);\n\
     \t}\n\
     \tfloat blur = e.p1.x * (1.0 - t) + e.p1.y * t;\n\
     \tfloat w = clamp((blur - e.p1.z) / (e.p1.w - e.p1.z), 0.0, 1.0);\n\
     \tif (w <= 0.0) {\n\
     \t\treturn vec4(0.0);\n\
     \t}\n\
     \tvec4 c = blurSample(e, p FX_BD_ARG);\n\
     \tfloat lum = 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b;\n\
     \tc.rgb = clamp(lum + (c.rgb - lum) * (1.0 + e.p2.x) + e.p2.y * c.a, vec3(0.0), vec3(c.a));\n\
     \tc += (vec4(e.p3.rgb, 1.0) - c) * e.p2.z;\n\
     \treturn c * w;\n\
     }\n"

(* {1 CPU twins}

   The raster draws effects through these, and the parity harness
   requires them to match the shaders to within a channel step. The
   glass twin keeps its tone curve in a table, its power being slow on
   the CPU: 1024 lightnesses the segments between which stay within
   3e-5 of the curve. *)

let tone_steps = 1024

let glass_lens t bezel =
  if bezel <= 0. || t >= bezel then 0.
  else begin
    let u = 1. -. fmax t 0. /. bezel in
    let v = 1. -. u *. u *. u *. u in
    let a = sqrt (v *. sqrt v) in
    let b = u *. u *. u in
    let n = sqrt (a *. a +. b *. b) in
    let s = b /. n and c = a /. n in
    let st = s /. 1.5 in
    let ct = sqrt (1. -. st *. st) in
    (s *. ct -. c *. st) /. (c *. ct +. s *. st) /. 1.1180340
  end

(* The direction of the edge's normal at a pixel center, smoothed: as of
   the rectangle with corners half again as round, so that it turns
   gradually around a corner. Zero on the lines through the middle. *)
let glass_normal x y r (rtl, rtr, rbr, rbl) =
  let hx = r.w /. 2. and hy = r.h /. 2. in
  let cx = x -. r.x -. hx and cy = y -. r.y -. hy in
  let rad =
    if cx < 0. && cy < 0. then rtl
    else if cx >= 0. && cy < 0. then rtr
    else if cx >= 0. then rbr
    else rbl
  in
  let rad = fmin (rad *. 1.5) (fmin hx hy) in
  let qx = Float.abs cx -. (hx -. rad) and qy = Float.abs cy -. (hy -. rad) in
  if qx > 0. || qy > 0. then begin
    let mx = fmax qx 0. and my = fmax qy 0. in
    let n = sqrt (mx *. mx +. my *. my) in
    (sgn cx *. mx /. n, sgn cy *. my /. n)
  end
  else if qx > qy then (sgn cx, 0.)
  else (0., sgn cy)

let luminance (r, g, b) = 0.2126 *. r +. 0.7152 *. g +. 0.0722 *. b

(* The premultiplied RGBA of a CPU backdrop at pixel center (x, y), as
   backdrop_sample does it for RGB alone. *)
let backdrop_sample4 b x y =
  let k = float b.bd.bdown in
  let u = (x -. float b.bd.barea.x0) /. k -. 0.5 in
  let v = (y -. float b.bd.barea.y0) /. k -. 0.5 in
  let fu = floor u and fv = floor v in
  let tx = u -. fu and ty = v -. fv in
  let ix f = fmin (fmax (int_of_float f) 0) (b.bw - 1) in
  let iy f = fmin (fmax (int_of_float f) 0) (b.bh - 1) in
  let x0 = ix fu and x1 = ix (fu +. 1.) in
  let y0 = iy fv and y1 = iy (fv +. 1.) in
  let p i j c = b.bpix.(4 * (j * b.bw + i) + c) in
  let c ch =
    let top = p x0 y0 ch *. (1. -. tx) +. p x1 y0 ch *. tx in
    let bot = p x0 y1 ch *. (1. -. tx) +. p x1 y1 ch *. tx in
    top *. (1. -. ty) +. bot *. ty
  in
  (c 0, c 1, c 2, c 3)

(* The glass twin's material and fitted shape. *)
type glass_state = {
  mutable gbezel : float;
  mutable grefrac : float;
  mutable grim : float;
  mutable grimw : float;
  mutable gtint : float * float * float * float;
  mutable glow : float;
  mutable ghigh : float;
  mutable gsat : float;
  mutable glx : float;
  mutable gly : float;
  mutable grect : rect;
  mutable gradii : float * float * float * float;
  mutable glinear : bool;
  gtable : float array;
}

let glass_begin st e r radii =
  let p = e.eparams in
  let (bz, rf, rm, rw) = p.(0) in
  let (lo, hi, cu, sa) = p.(2) in
  let (lx, ly, _, _) = p.(3) in
  st.gbezel <- bz;
  st.grefrac <- rf;
  st.grim <- rm;
  st.grimw <- rw;
  st.gtint <- p.(1);
  st.glow <- lo;
  st.ghigh <- hi;
  st.gsat <- sa;
  st.glx <- lx;
  st.gly <- ly;
  st.grect <- r;
  st.gradii <- radii;
  st.glinear <- cu = 1.;
  if not st.glinear then
    for i = 0 to tone_steps do
      st.gtable.(i) <-
        1. -. (1. -. float i /. float tone_steps) ** cu
    done

let glass_tone st c =
  let l = luminance c in
  let v =
    if st.glinear then fclamp 0. 1. l
    else begin
      let x = fclamp 0. 1. l *. float tone_steps in
      let i = fmin (int_of_float x) (tone_steps - 1) in
      let f = x -. float i in
      st.gtable.(i) +. (st.gtable.(i + 1) -. st.gtable.(i)) *. f
    end
  in
  let t = st.glow +. (st.ghigh -. st.glow) *. v in
  let k = (st.ghigh -. st.glow) *. st.gsat in
  let (cr, cg, cb) = c in
  (fclamp 0. 1. (t +. (cr -. l) *. k),
   fclamp 0. 1. (t +. (cg -. l) *. k),
   fclamp 0. 1. (t +. (cb -. l) *. k))

let glass_color st x y = function
  | None -> (0., 0., 0., 1.)
  | Some b ->
    let t = fmax (~-.(sd_round_rect st.grect st.gradii x y)) 0. in
    let nx, ny =
      if t < st.gbezel || t < 3. *. st.grimw then
        glass_normal x y st.grect st.gradii
      else (0., 0.)
    in
    let sx, sy =
      if t < st.gbezel then begin
        let d = st.grefrac *. glass_lens t st.gbezel in
        (x -. nx *. d, y -. ny *. d)
      end
      else (x, y)
    in
    let cr, cg, cb = glass_tone st (backdrop_sample b sx sy) in
    let (tr, tg, tb, ta) = st.gtint in
    let cr = cr +. (tr -. cr) *. ta
    and cg = cg +. (tg -. cg) *. ta
    and cb = cb +. (tb -. cb) *. ta in
    let cr, cg, cb =
      if st.grim > 0. && t < 3. *. st.grimw then begin
        let r = t /. st.grimw in
        let a = st.grim *. exp (~-.(r *. r)) in
        let l = Float.abs (nx *. st.glx +. ny *. st.gly) in
        (cr +. (l -. cr) *. a, cg +. (l -. cg) *. a, cb +. (l -. cb) *. a)
      end
      else (cr, cg, cb)
    in
    (cr, cg, cb, 1.)

let glass_pixels () =
  let st =
    { gbezel = 0.; grefrac = 0.; grim = 0.; grimw = 0.;
      gtint = (0., 0., 0., 0.); glow = 0.; ghigh = 0.;
      gsat = 0.; glx = 0.; gly = 0.; grect = rect 0. 0. 0. 0.;
      gradii = (0., 0., 0., 0.); glinear = true;
      gtable = Array.make (tone_steps + 1) 0. }
  in
  { begin_effect = (fun e r radii -> glass_begin st e r radii);
    color_at = (fun x y b -> glass_color st x y b) }

let glass_fx =
  { ename = "glass"; ebackdrop = true; eglsl = glass_glsl;
    epixels = glass_pixels }

(* {1 The blur twin} *)

type blur_state = {
  mutable bline : float * float * float * float;
  mutable bband : float * float * float * float;
  mutable btone : float * float * float * float;
  mutable bcolor : float * float * float * float;
}

(* How much the level shows at the pixel center: how far the blur there,
   along the mask, is into its band. *)
let blur_weight_at st x y =
  let (l0x, l0y, l1x, l1y) = st.bline in
  let (at0, at1, lo, hi) = st.bband in
  let dx = l1x -. l0x and dy = l1y -. l0y in
  let t =
    let d = dx *. dx +. dy *. dy in
    if d > 0. then
      fclamp 0. 1. (((x -. l0x) *. dx +. (y -. l0y) *. dy) /. fmax d 0.0001)
    else 0.
  in
  let blur = at0 *. (1. -. t) +. at1 *. t in
  fclamp 0. 1. ((blur -. lo) /. (hi -. lo))

let blur_color st x y = function
  | None -> (0., 0., 0., 0.)
  | Some b ->
    let w = blur_weight_at st x y in
    if w <= 0. then (0., 0., 0., 0.)
    else begin
      let (r, g, bb, a) = backdrop_sample4 b x y in
      let l = luminance (r, g, bb) in
      let (sat, off, mx, _) = st.btone in
      let tc c = fclamp 0. a (l +. (c -. l) *. (1. +. sat) +. off *. a) in
      let cr = tc r and cg = tc g and cb = tc bb in
      let (mr, mg, mb, _) = st.bcolor in
      let r2 = cr +. (mr -. cr) *. mx
      and g2 = cg +. (mg -. cg) *. mx
      and b2 = cb +. (mb -. cb) *. mx
      and a2 = a +. (1. -. a) *. mx in
      (r2 *. w, g2 *. w, b2 *. w, a2 *. w)
    end

let blur_pixels () =
  let st =
    { bline = (0., 0., 0., 0.); bband = (0., 0., 0., 0.);
      btone = (0., 0., 0., 0.); bcolor = (0., 0., 0., 0.) }
  in
  { begin_effect =
      (fun e _ _ ->
        st.bline <- e.eparams.(0);
        st.bband <- e.eparams.(1);
        st.btone <- e.eparams.(2);
        st.bcolor <- e.eparams.(3));
    color_at = (fun x y b -> blur_color st x y b) }

let blur_fx =
  { ename = "blur"; ebackdrop = true; eglsl = blur_glsl;
    epixels = blur_pixels }

(* {1 Materials} *)

type style = Regular | Clear

type material = {
  mstyle : style;
  mtint : color;
  minteractive : bool;
  mdark : bool;
}

let material ?(style = Regular) ?(tint = transparent) ?(interactive = false)
    ?(dark = false) () =
  { mstyle = style; mtint = tint; minteractive = interactive; mdark = dark }

(* A blur level: one pass over the backdrop, blurred by lblur pixels,
   showing where the wanted blur is more than llo by how far it is
   toward lhi, and wholly from lhi. *)
type blur_level = { lblur : float; llo : float; lhi : float }

(* The most the first level of a varying blur blurs, in pixels. *)
let finest_level = 2.

(* The levels of a blur varying from least to most pixels: the levels'
   his halve from the most down, so a pixel shows the blurs of at most
   two mixed, and blurs add up as their variances do, which is why each
   level blurs by sqrt(hi^2 - lo^2) more. *)
let blur_levels least most =
  let least = fmax least 0. in
  if most <= least then
    if least <= 0. then [] else [ { lblur = least; llo = -1.; lhi = 0. } ]
  else begin
    let his = ref [ most ] in
    let h = ref most in
    while !h > finest_level && !h /. 2. > least do
      h := !h /. 2.;
      his := !h :: !his
    done;
    let _, lv =
      List.fold_left
        (fun (lo, acc) hi ->
          (hi, { lblur = sqrt (fmax (hi *. hi -. lo *. lo) 0.);
                 llo = lo; lhi = hi }
               :: acc))
        (least, []) !his
    in
    (if least > 0. then [ { lblur = least; llo = -1.; lhi = 0. } ] else [])
    @ List.rev lv
  end

(* A progressive blur's mask: the blur's weight fades from the From
   alpha to the To alpha along a line through the element at angle,
   CSS-linear-gradient style; start and stop place the ends along it. *)
type fade = {
  ffrom : float;
  fto : float;
  fangle : float;
  fstart : float;
  fstop : float;
}

let fade ~from ~to_ ?(angle = 180.) ?(start = 0.) ?(stop = 1.) () =
  { ffrom = from; fto = to_; fangle = angle; fstart = start; fstop = stop }

(* Where the mask's From and To are, in pixels, along a line through
   the element's middle at the gradient's angle, as long as its corners
   are apart along it. *)
let mask_line r f =
  let a = f.fangle *. Float.pi /. 180. in
  let dx = sin a and dy = ~-.(cos a) in
  let half = (Float.abs (r.w *. dx) +. Float.abs (r.h *. dy)) /. 2. in
  let cx = r.x +. r.w /. 2. and cy = r.y +. r.h /. 2. in
  let x0 = cx -. dx *. half and y0 = cy -. dy *. half in
  let x1 = cx +. dx *. half and y1 = cy +. dy *. half in
  let start = f.fstart and stop = f.fstop in
  let start, stop =
    if start = 0. && stop = 0. then (0., 1.) else (start, stop)
  in
  let sx = x0 +. (x1 -. x0) *. start and sy = y0 +. (y1 -. y0) *. start in
  let ex, ey =
    if stop -. start < 0.5 /. fmax (2. *. half) 1. then
      (sx +. dx *. 0.5, sy +. dy *. 0.5)
    else (x0 +. (x1 -. x0) *. stop, y0 +. (y1 -. y0) *. stop)
  in
  (sx, sy, ex, ey)

(* The bounds, in whole pixels, of the part of r where the blur along
   line, from at0 at its start to at1 at its end, is more than lo —
   or nothing, for a level that shows nowhere on the element. *)
let blur_wanted r line at0 at1 lo =
  if at0 = at1 then if at0 > lo then Some r else None
  else begin
    let (l0x, l0y, l1x, l1y) = line in
    let dx = l1x -. l0x and dy = l1y -. l0y in
    let tc = (lo -. at0) /. (at1 -. at0) in
    let nx, ny, c =
      let c = l0x *. dx +. l0y *. dy +. tc *. (dx *. dx +. dy *. dy) in
      if at1 < at0 then (~-.dx, ~-.dy, ~-.c) else (dx, dy, c)
    in
    let corners =
      [| (r.x, r.y); (r.x +. r.w, r.y); (r.x +. r.w, r.y +. r.h);
         (r.x, r.y +. r.h) |]
    in
    let x0 = ref Float.infinity and y0 = ref Float.infinity in
    let x1 = ref Float.neg_infinity and y1 = ref Float.neg_infinity in
    let add x y =
      x0 := fmin !x0 x;
      y0 := fmin !y0 y;
      x1 := fmax !x1 x;
      y1 := fmax !y1 y
    in
    for i = 0 to 3 do
      let ax, ay = corners.(i) in
      let bx, by = corners.((i + 1) mod 4) in
      let fa = nx *. ax +. ny *. ay -. c
      and fb = nx *. bx +. ny *. by -. c in
      if fa > 0. then add ax ay;
      if (fa > 0.) <> (fb > 0.) then begin
        let k = fa /. (fa -. fb) in
        add (ax +. (bx -. ax) *. k) (ay +. (by -. ay) *. k)
      end
    done;
    if !x0 > !x1 || !y0 > !y1 then None
    else begin
      let x0 = fmax (floor !x0) r.x and y0 = fmax (floor !y0) r.y in
      let x1 = fmin (ceil !x1) (r.x +. r.w)
      and y1 = fmin (ceil !y1) (r.y +. r.h) in
      if x1 <= x0 || y1 <= y0 then None
      else Some (rect x0 y0 (x1 -. x0) (y1 -. y0))
    end
  end

(* What a blur level does to the colors it shows: saturation more
   saturation (0 for as is), offset added to each channel, and mix of
   the opaque color over it — a scroll edge's hard frost. *)
type tone = {
  tsat : float;
  toff : float;
  tmix : float;
  tcolor : float * float * float;
}

let toned (r, g, b) sat off =
  let l = 0.2126 *. r +. 0.7152 *. g +. 0.0722 *. b in
  let f c = fclamp 0. 1. (l +. (c -. l) *. sat +. off) in
  (f r, f g, f b)

(* {1 Emitting ops}

   An effect's draw op references its effect_op by position in
   scene.effects; the helpers append to both lists. *)

let emit s ee ~eblur eparams ?(radii = (0., 0., 0., 0.))
    ?(continuous = false) ?(opacity = 0.) rc =
  s.effects <- s.effects @ [ { ee; eblur; eparams } ];
  s.ops <-
    s.ops
    @ [ Effect
          { edrect = rc; edradii = radii; edcontinuous = continuous;
            edindex = List.length s.effects - 1; edopacity = opacity } ]

let emit_fill s ?(radii = (0., 0., 0., 0.)) ?(continuous = false)
    ?(paint_ = Solid) ?(c2 = transparent) ?(g = (0., 0., 0., 0.)) rc c1 =
  s.ops <-
    s.ops
    @ [ Fill
          { frect = rc; fradii = radii; fcontinuous = continuous;
            fcolor = c1; fpaint = paint_; fcolor2 = c2; fgradient = g;
            fborder = (0., 0., 0., 0.); fborder_color = transparent;
            fdashed = false; fwide = 0; fopacity = 0. } ]

(* A pane of glass over rect, rounded by radii: what was painted under
   it shows through, blurred and lensed and rim-lit per the material.
   rect and radii are device pixels; scale is the DIPs they stand for
   (the material's own sizes are DIPs). grow is how far an interactive
   pane is pressed, 0 to 1: the pane swells by about 1.1 DIPs left and
   right and 0.45 above and below, its corners with it. *)
let glass ~scene ?(radii = (0., 0., 0., 0.)) ?(continuous = false)
    ?(scale = scene.scale) ?(grow = 0.) rc m =
  if rect_empty rc then ()
  else begin
    let s = fmax scale 0.0001 in
    let dx, dy =
      if m.minteractive && grow > 0. then (1.1 *. grow, 0.45 *. grow)
      else (0., 0.)
    in
    let rc =
      rect (rc.x -. dx *. s) (rc.y -. dy *. s)
        (rc.w +. 2. *. dx *. s) (rc.h +. 2. *. dy *. s)
    in
    let radii =
      if dy > 0. then begin
        let (tl, tr, br, bl) = radii in
        let g r = if r > 0. then r +. dy *. s else r in
        (g tl, g tr, g br, g bl)
      end
      else radii
    in
    let m_dip = fmin rc.w rc.h /. s in
    let bezel_d = fmin 36. (m_dip /. 2.) in
    let bezel = bezel_d *. s in
    let blur, low, high, curve, sat =
      match m.mstyle with
      | Clear -> (s, 0.125, 1.082, 1., 1.)
      | Regular ->
        let b = fmin (fmax (m_dip *. 0.035) 1.) 10. *. s in
        if m.mdark then (b, 0.15, 0.51, 2., 2.2)
        else (b, 0.541, 1., 1.2, 1.)
    in
    let tint =
      if m.mtint.a > 0 then
        (float m.mtint.r /. 255., float m.mtint.g /. 255.,
         float m.mtint.b /. 255., float m.mtint.a /. 255. *. 0.88)
      else (0., 0., 0., 0.)
    in
    let eparams =
      [| (bezel, 1.6 *. bezel, 0.35, 1.);
         tint;
         (low, high, curve, sat);
         (cos pi2, sin pi2, 0., 0.);
         tint |]
    in
    emit scene glass_fx ~eblur:blur eparams ~radii ~continuous rc
  end

(* A backdrop blur over rect: what was painted under it shows through
   blurred by radius device pixels (the standard deviation of the
   Gaussian). With a mask the blur fades along it, which takes one
   effect op per level (blur_levels); each reads the backdrop as the
   levels before it left it. *)
let blur ~scene ?(radii = (0., 0., 0., 0.)) ?(continuous = false)
    ?mask ?tone ~radius rc =
  if rect_empty rc || radius <= 0. then ()
  else begin
    let square = radii = (0., 0., 0., 0.) in
    let line, at0, at1 =
      match mask with
      | None -> ((0., 0., 0., 0.), radius, radius)
      | Some f ->
        (mask_line rc f, radius *. f.ffrom, radius *. f.fto)
    in
    let p2, p3 =
      match tone with
      | None -> ((0., 0., 0., 0.), (0., 0., 0., 0.))
      | Some t ->
        let (r, g, b) = t.tcolor in
        ((t.tsat, t.toff, t.tmix, 0.), (r, g, b, 1.))
    in
    List.iter
      (fun l ->
        let wanted =
          if square && l.llo >= 0. then
            blur_wanted rc line at0 at1 l.llo
          else Some rc
        in
        match wanted with
        | None -> ()
        | Some lr ->
          let eparams = [| line; (at0, at1, l.llo, l.lhi); p2; p3;
                           (0., 0., 0., 0.) |] in
          emit scene blur_fx ~eblur:l.lblur eparams ~radii ~continuous lr)
      (blur_levels (fmin at0 at1) (fmax at0 at1))
  end

(* The scroll edge of the platform's own look: over content scrolling
   under a bar of controls, so that they stand out from it. Soft, the
   background washes the content away, its alpha 0.85 at the bar's edge
   falling linearly to none at the other, no blur; hard, the content is
   blurred by about 6 DIPs, saturated and lightened, under about 82% of
   the background evenly, with a hairline along the far edge. bottom
   puts the bar at the element's bottom. bg is what the content scrolls
   over; dark picks the light-on-dark hairline. *)
let soft_edge = 0.85
let hard_edge_blur = 6.4

let scroll_edge ~scene ?(radii = (0., 0., 0., 0.)) ?(continuous = false)
    ?(scale = scene.scale) ?(hard = false) ?(bottom = false) ?(bg = transparent)
    ?(dark = false) rc =
  if rect_empty rc then ()
  else if not hard then begin
    let angle = if bottom then 0. else 180. in
    let f = fade ~from:soft_edge ~to_:0. ~angle () in
    let gline = mask_line rc f in
    let a8 v = fmin (fmax (int_of_float (v *. 255. +. 0.5)) 0) 255 in
    emit_fill scene ~radii ~continuous ~paint_:Linear
      ~c2:{ bg with a = 0 } ~g:gline rc
      { bg with a = a8 (float bg.a /. 255. *. soft_edge) }
  end
  else begin
    let s = fmax scale 0.0001 in
    let b = hard_edge_blur *. s in
    let c =
      toned
        (float bg.r /. 255., float bg.g /. 255., float bg.b /. 255.)
        0.947 0.03
    in
    let tone =
      { tsat = 0.25; toff = 0.03; tmix = 0.8245; tcolor = c }
    in
    blur ~scene ~radii ~continuous ~tone ~radius:b rc;
    (* The hairline along the far edge, outside the element, half a
       DIP: black at 10% in light mode, white at 7% in dark. *)
    let hdip = fmax 0.5 (1. /. s) in
    let base_a = if dark then 0.07 *. 255. else 0.1 *. 255. in
    let a8 v = fmin (fmax (int_of_float (v +. 0.5)) 0) 255 in
    let line_c =
      if dark then color 255 255 255 (a8 (base_a *. 0.5 /. hdip))
      else color 0 0 0 (a8 (base_a *. 0.5 /. hdip))
    in
    let h = hdip *. s in
    let y = if bottom then rc.y -. h else rc.y +. rc.h in
    emit_fill scene (rect rc.x y rc.w h) line_c
  end

(* {1 The plugin service}

   The ["plugin:glass"] service of the {!Lui_plugin} registry: each
   method runs the helper of the same name on a scratch scene and
   answers with the ops and effect slots it emitted, as JSON, so a
   host replays them against its own scene. The arguments are the
   helper's: [rect] and [radii] as [x,y,w,h] and [tl,tr,br,bl] arrays
   (a bare number for a uniform radius), [tint] and [bg] as [r,g,b,a]
   byte arrays, a tone's [color] as straight-sRGB floats, and the rest
   ([scale], [grow], [style], [dark], [interactive], [continuous],
   [radius], [mask], [tone], [hard], [bottom]) by name. *)

let num = function
  | `Int i -> float i
  | `Float f -> f
  | `Intlit s -> (
    try float_of_string s with _ -> invalid_arg "number expected")
  | _ -> invalid_arg "number expected"

let jnum j name = num (Yojson.Safe.Util.member name j)

let onum j name d =
  match Yojson.Safe.Util.member name j with `Null -> d | v -> num v

let obool j name d =
  match Yojson.Safe.Util.member name j with `Bool b -> b | _ -> d

let jrect j =
  match Yojson.Safe.Util.to_list j with
  | [ x; y; w; h ] -> rect (num x) (num y) (num w) (num h)
  | _ -> invalid_arg "rect wants [x, y, w, h]"

let jrects j = jrect (Yojson.Safe.Util.member "rect" j)

let jradii j =
  match Yojson.Safe.Util.member "radii" j with
  | `Null -> (0., 0., 0., 0.)
  | `List [ a; b; c; d ] -> (num a, num b, num c, num d)
  | v ->
    let r = num v in
    (r, r, r, r)

let i8 v = fmin (fmax (int_of_float (num v)) 0) 255

let jcolor4 j =
  match Yojson.Safe.Util.to_list j with
  | [ r; g; b; a ] -> color (i8 r) (i8 g) (i8 b) (i8 a)
  | _ -> invalid_arg "color wants [r, g, b, a]"

(* The emitted scene as {"ops": [...], "effects": [...]}: ops in paint
   order, an effect op naming its slot by index. *)
let ops_json (s : t) =
  let f4 (a, b, c, d) = `List [ `Float a; `Float b; `Float c; `Float d ] in
  let rj (r : rect) =
    `List [ `Float r.x; `Float r.y; `Float r.w; `Float r.h ]
  in
  let cj (c : color) = `List [ `Int c.r; `Int c.g; `Int c.b; `Int c.a ] in
  let pj = function
    | Solid -> "solid"
    | Linear -> "linear"
    | Oklab -> "oklab"
    | Stripes -> "stripes"
  in
  let op_json = function
    | Fill f ->
      Some
        (`Assoc
           [ ("op", `String "fill"); ("rect", rj f.frect);
             ("radii", f4 f.fradii); ("continuous", `Bool f.fcontinuous);
             ("color", cj f.fcolor); ("paint", `String (pj f.fpaint));
             ("color2", cj f.fcolor2); ("gradient", f4 f.fgradient) ])
    | Effect e ->
      Some
        (`Assoc
           [ ("op", `String "effect"); ("rect", rj e.edrect);
             ("radii", f4 e.edradii); ("continuous", `Bool e.edcontinuous);
             ("effect", `Int e.edindex); ("opacity", `Float e.edopacity) ])
    | _ -> None
  in
  let fx_json eo =
    `Assoc
      [ ("name", `String eo.ee.ename); ("eblur", `Float eo.eblur);
        ("params", `List (List.map f4 (Array.to_list eo.eparams))) ]
  in
  `Assoc
    [ ("ops", `List (List.filter_map op_json s.ops));
      ("effects", `List (List.map fx_json s.effects)) ]

let scratch () =
  create
    ~mask_atlas:(Atlas.create ~bpp:1 ~w:8 ~h:8)
    ~color_atlas:(Atlas.create ~bpp:4 ~w:8 ~h:8)

let answer f payload =
  try
    let j = Yojson.Safe.from_string payload in
    let s = scratch () in
    f j s;
    Ok (Yojson.Safe.to_string (ops_json s))
  with e -> Error (Printexc.to_string e)

let material_call payload =
  answer
    (fun j s ->
      let m =
        material
          ~style:
            (match Yojson.Safe.Util.member "style" j with
            | `String "clear" -> Clear
            | _ -> Regular)
          ~tint:
            (match Yojson.Safe.Util.member "tint" j with
            | `Null -> transparent
            | v -> jcolor4 v)
          ~interactive:(obool j "interactive" false)
          ~dark:(obool j "dark" false)
          ()
      in
      glass ~scene:s ~radii:(jradii j)
        ~continuous:(obool j "continuous" false)
        ~scale:(onum j "scale" s.scale)
        ~grow:(onum j "grow" 0.) (jrects j) m)
    payload

let blur_call payload =
  answer
    (fun j s ->
      let mask =
        match Yojson.Safe.Util.member "mask" j with
        | `Null -> None
        | m ->
          Some
            (fade ~from:(jnum m "from") ~to_:(jnum m "to")
               ~angle:(onum m "angle" 180.) ~start:(onum m "start" 0.)
               ~stop:(onum m "stop" 1.) ())
      in
      let tone =
        match Yojson.Safe.Util.member "tone" j with
        | `Null -> None
        | t ->
          let c =
            match Yojson.Safe.Util.member "color" t with
            | `List [ r; g; b ] -> (num r, num g, num b)
            | _ -> (0., 0., 0.)
          in
          Some
            { tsat = onum t "saturation" 0.; toff = onum t "offset" 0.;
              tmix = onum t "mix" 0.; tcolor = c }
      in
      blur ~scene:s ~radii:(jradii j)
        ~continuous:(obool j "continuous" false) ?mask ?tone
        ~radius:(jnum j "radius") (jrects j))
    payload

let scroll_edge_call payload =
  answer
    (fun j s ->
      let bg =
        match Yojson.Safe.Util.member "bg" j with
        | `Null -> transparent
        | v -> jcolor4 v
      in
      scroll_edge ~scene:s ~radii:(jradii j)
        ~continuous:(obool j "continuous" false)
        ~scale:(onum j "scale" s.scale)
        ~hard:(obool j "hard" false)
        ~bottom:(obool j "bottom" false) ~bg
        ~dark:(obool j "dark" false)
        (jrects j))
    payload

let plugin : Lui_plugin.t =
  Lui_plugin.v "glass"
    [ ("material", material_call); ("blur", blur_call);
      ("scroll_edge", scroll_edge_call) ]
