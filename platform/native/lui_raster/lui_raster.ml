(* CPU renderer: evaluates a Lui_scene.t into a premultiplied BGRA
   pixel buffer. Coverage comes from signed distances to rounded
   rectangles, so edges, corners and clips are anti-aliased the way the
   GPU evaluator's shader computes them; both evaluate the same scene and
   must agree pixel-for-pixel.

   A large area is drawn on several cores at once, in bands of rows that
   each worker takes in turn, as rows differ in how much they draw: no
   pixel depends on another, so the result is identical to drawing the
   area at once. *)

open Lui_scene

(* ---------- float and byte helpers ---------- *)

let fmin a b = if Float.is_nan a || Float.is_nan b then Float.nan else Float.min a b
let fmax a b = if Float.is_nan a || Float.is_nan b then Float.nan else Float.max a b
let clamp01 v = fmin (fmax v 0.) 1.
let to8 v = if v <= 0. then 0 else if v >= 1. then 255 else int_of_float (v *. 255. +. 0.5)

(* A channel of a byte-coded texture value, rounded as a texture holds it. *)
let texel v = float (to8 v) /. 255.
let byte_f p i = float (Char.code (Bytes.get p i)) /. 255.
let byte_at p i = Char.code (Bytes.get p i)
let ifloor v = int_of_float (Float.floor v)
let iceil v = int_of_float (Float.ceil v)
let iround v = int_of_float (Float.round v)

let irect_overlaps a b = a.x0 < b.x1 && b.x0 < a.x1 && a.y0 < b.y1 && b.y0 < a.y1
let irect_in a b =
  irect_empty a || (a.x0 >= b.x0 && a.y0 >= b.y0 && a.x1 <= b.x1 && a.y1 <= b.y1)

let outset rc d =
  irect (ifloor (rc.x -. d)) (ifloor (rc.y -. d))
    (iceil (rc.x +. rc.w +. d)) (iceil (rc.y +. rc.h +. d))

(* ---------- pixels ---------- *)

(* Premultiplied BGRA, the layout most window systems' frame buffers
   take: stride = 4*w bytes a row. *)
module Image = struct
  type t = { mutable w : int; mutable h : int; mutable stride : int; mutable pix : Bytes.t }

  let create ~w ~h = { w; h; stride = 4 * w; pix = Bytes.make (4 * w * h) '\000' }

  let resize t ~w ~h =
    let n = 4 * w * h in
    if Bytes.length t.pix < n then t.pix <- Bytes.make n '\000'
    else if Bytes.length t.pix > n then t.pix <- Bytes.sub t.pix 0 n;
    t.w <- w; t.h <- h; t.stride <- 4 * w

  (* The pixels as premultiplied RGBA. *)
  let rgba t =
    let out = Bytes.make (4 * t.w * t.h) '\000' in
    for y = 0 to t.h - 1 do
      for x = 0 to t.w - 1 do
        let s = y * t.stride + 4 * x and d = y * 4 * t.w + 4 * x in
        Bytes.set out d (Bytes.get t.pix (s + 2));
        Bytes.set out (d + 1) (Bytes.get t.pix (s + 1));
        Bytes.set out (d + 2) (Bytes.get t.pix s);
        Bytes.set out (d + 3) (Bytes.get t.pix (s + 3))
      done
    done;
    out
end

(* ---------- compositing ---------- *)

(* A premultiplied RGBA color with coverage cov over a BGRA pixel. *)
let blend p i (r_, g_, b_, a_) cov =
  let a = a_ *. cov in
  if a <= 0. then ()
  else begin
    let inv = 1. -. a in
    Bytes.set p i (Char.chr (to8 (b_ *. cov +. byte_f p i *. inv)));
    Bytes.set p (i + 1) (Char.chr (to8 (g_ *. cov +. byte_f p (i + 1) *. inv)));
    Bytes.set p (i + 2) (Char.chr (to8 (r_ *. cov +. byte_f p (i + 2) *. inv)));
    Bytes.set p (i + 3) (Char.chr (to8 (a +. byte_f p (i + 3) *. inv)))
  end

(* A straight color over a pixel with a coverage of its own for each
   channel of the destination, times w: subpixel glyphs blend each
   destination channel by the coverage of the matching source channel. *)
let blend_subpixel p i (cr, cg, cb) (ar, ag, ab) w =
  let wr = ar *. w and wg = ag *. w and wb = ab *. w in
  let wa = (wr +. wg +. wb) /. 3. in
  Bytes.set p i (Char.chr (to8 (cb *. wb +. byte_f p i *. (1. -. wb))));
  Bytes.set p (i + 1) (Char.chr (to8 (cg *. wg +. byte_f p (i + 1) *. (1. -. wg))));
  Bytes.set p (i + 2) (Char.chr (to8 (cr *. wr +. byte_f p (i + 2) *. (1. -. wr))));
  Bytes.set p (i + 3) (Char.chr (to8 (wa +. byte_f p (i + 3) *. (1. -. wa))))

(* The straight color of a premultiplied one. *)
let unpremul (r, g, b, a) = if a <= 0. then (0., 0., 0.) else (r /. a, g /. a, b /. a)

(* src + dst*inv/255, rounded, for 8-bit premultiplied channels. *)
let over src dst inv =
  let t = dst * inv + 128 in
  min (src + ((t + (t lsr 8)) lsr 8)) 255

let mix_mask src dst cov =
  let v = src * cov + dst * (255 - cov) + 128 in
  (v + (v lsr 8)) lsr 8

(* Take the coverage cov of a premultiplied pixel away. *)
let erase p i cov =
  let inv = 1. -. cov in
  for k = 0 to 3 do
    Bytes.set p (i + k) (Char.chr (to8 (byte_f p (i + k) *. inv)))
  done

(* A premultiplied color with coverage cov over a run of pixels. *)
let blend_span p row x0 x1 (r_, g_, b_, a_) cov =
  if x1 > x0 then begin
    let a = a_ *. cov in
    if a > 0. then begin
      let pb = to8 (b_ *. cov) and pg = to8 (g_ *. cov) and pr = to8 (r_ *. cov) and pa = to8 a in
      if pa = 255 then begin
        let pb = Char.chr pb and pg = Char.chr pg and pr = Char.chr pr in
        for x = x0 to x1 - 1 do
          let i = row + 4 * x in
          Bytes.set p i pb;
          Bytes.set p (i + 1) pg;
          Bytes.set p (i + 2) pr;
          Bytes.set p (i + 3) '\255'
        done
      end
      else begin
        let inv = 255 - pa in
        for x = x0 to x1 - 1 do
          let i = row + 4 * x in
          Bytes.set p i (Char.chr (over pb (byte_at p i) inv));
          Bytes.set p (i + 1) (Char.chr (over pg (byte_at p (i + 1)) inv));
          Bytes.set p (i + 2) (Char.chr (over pr (byte_at p (i + 2)) inv));
          Bytes.set p (i + 3) (Char.chr (over pa (byte_at p (i + 3)) inv))
        done
      end
    end
  end

(* ---------- continuous corners ---------- *)

(* Continuous corners bend gradually from further out than quarter
   circles, computed as the GPU evaluator's supercircle distance field
   computes them.

   In a corner's own terms, u and v are how far a point is inside its
   vertical and horizontal edges, r its radius and e = cont_extent*r how
   far from the corner the curve leaves the edges. With a = max(0,
   1 - (u,v)/e) the point's place in the box of the curve, and rho the
   ratio of a's smaller coordinate to its larger, the curve is where

     |a| + 1 - 1/(1 - rho^2 * min(|a|,1) * P(rho)) = 1,

   P a quartic: a quarter circle of radius r around the diagonal, which
   bends less and less toward the edges. Where a side is too short for
   both of its corners' curves, the curves blend along it toward the
   quarter circles by the side's clamp factor: 0 while the curves fit, 1
   once the side is no longer than two of their mean radius, as a pill's
   ends; a circle's corners, clamped both ways, are quarter circles. The
   shape is the intersection of its corners' (the largest of their
   values), so a curve may reach past the middle of a side whose other
   corner is smaller, and edges are antialiased by the value over the sum
   of its derivatives. *)
let cont_extent = 1.528665

(* A continuous corner of radius r, whose curve leaves the edges e from
   the corner, blended toward a quarter circle by cx along its horizontal
   edge and cy along its vertical one; eff is where the curve's box ends
   as clamped. *)
type cont_corner = { cr : float; ce : float; ceff : float; ccx : float; ccy : float }

(* The corner of radius r of a rectangle w*h whose horizontal edge it
   shares with a corner of radius rh, and its vertical one with one of
   radius rv. *)
let new_cont_corner r rh rv w h =
  let cl side ra rb = clamp01 ((cont_extent -. side /. (ra +. rb)) /. (cont_extent -. 1.)) in
  let cx = cl w r rh and cy = cl h r rv in
  let e = cont_extent *. r in
  { cr = r; ce = e; ceff = e +. (r -. e) *. fmax cx cy; ccx = cx; ccy = cy }

(* The corner's value at the point u inside its vertical edge and v
   inside its horizontal one: about the signed distance to its edge near
   it, positive outside. *)
let corner_dist c u v =
  let ax = fmax 0. (1. -. u /. c.ce) and ay = fmax 0. (1. -. v /. c.ce) in
  let l = sqrt (ax *. ax +. ay *. ay) in
  let hi = fmax ax ay and lo = fmin ax ay in
  let rho = if hi > 0. then fmin (lo /. hi) 1. else 0. in
  let p = (((-0.926054 *. rho +. 3.15601) *. rho -. 3.64122) *. rho +. 1.26803) *. rho +. 0.268531 in
  let f1 = l +. 1. -. 1. /. (1. -. rho *. rho *. fmin l 1. *. p) in
  let qx = fmax 0. (ax *. cont_extent -. (cont_extent -. 1.)) in
  let qy = fmax 0. (ay *. cont_extent -. (cont_extent -. 1.)) in
  let f2 = sqrt (qx *. qx +. qy *. qy) *. 0.654166 +. 0.345834 in
  (* The clamp along the edge the point is nearer to, blended across the
     diagonal. *)
  let s = if ay > ax then 1. else -1. in
  let w = clamp01 (0.5 -. s +. s *. rho) in
  let fx = f1 +. (f2 -. f1) *. c.ccx and fy = f1 +. (f2 -. f1) *. c.ccy in
  let f = fx +. (fy -. fx) *. w in
  fmin (fmax (c.ceff -. u) (c.ceff -. v)) 0. +. c.ce *. (f -. 1.)

(* How far inside its vertical edge the corner's edge is v inside its
   horizontal one, and a bound at least as far: where dist is 0, which
   lies between the quarter circles of radius r and e, found by regula
   falsi (Illinois) within a hundredth of a pixel at radii of a few
   hundred. *)
let corner_inset c v =
  if v >= c.ce || c.cr <= 0. then (0., 0.)
  else begin
    let circle r = if v >= r then 0. else r -. sqrt (v *. (2. *. r -. v)) in
    let lo = ref (circle c.cr) and hi = ref (circle c.ce) in
    let dlo = ref (corner_dist c !lo v) and dhi = ref (corner_dist c !hi v) in
    if !dlo <= 0. then (!lo, !lo)
    else if !dhi >= 0. then (!hi, !hi)
    else begin
      let side = ref 0 in
      for _ = 1 to 5 do
        let m = (!lo *. !dhi -. !hi *. !dlo) /. (!dhi -. !dlo) in
        let dm = corner_dist c m v in
        if dm > 0. then begin
          lo := m;
          dlo := dm;
          if !side = 1 then dhi := !dhi /. 2.;
          side := 1
        end
        else begin
          hi := m;
          dhi := dm;
          if !side = -1 then dlo := !dlo /. 2.;
          side := -1
        end
      done;
      ((!lo *. !dhi -. !hi *. !dlo) /. (!dhi -. !dlo), !hi)
    end
  end

(* ---------- shapes and coverage ---------- *)

(* A rounded rectangle, with radii as Lui_scene.corners gives them
   (negative for continuous corners), as the renderer draws it, with its
   continuous corners, which every pixel near an edge needs, worked out
   once. *)
let r4_get (a, b, c, d) i = match i with 0 -> a | 1 -> b | 2 -> c | _ -> d
let has_radii (a, b, c, d) = a <> 0. || b <> 0. || c <> 0. || d <> 0.

type shape = {
  sr : rect;
  sradii : float * float * float * float; (* positive, continuous or not *)
  scont : bool;
  scorners : cont_corner array;
}

let new_shape rc (r0, r1, r2, r3) =
  if r0 >= 0. && r1 >= 0. && r2 >= 0. && r3 >= 0. then
    { sr = rc; sradii = (r0, r1, r2, r3); scont = false; scorners = [||] }
  else begin
    let ar = (Float.abs r0, Float.abs r1, Float.abs r2, Float.abs r3) in
    let rad i = r4_get ar i in
    let hr = [| 1; 0; 3; 2 |] and vr = [| 3; 2; 1; 0 |] in
    let scorners =
      Array.init 4 (fun i -> new_cont_corner (rad i) (rad hr.(i)) (rad vr.(i)) rc.w rc.h)
    in
    { sr = rc; sradii = ar; scont = true; scorners }
  end

(* The area of the pixel centered at (px, py) inside the rectangle, near
   square corners: exact for lines thinner than a pixel too. *)
let area_coverage rc px py =
  let cx = fmin (rc.x +. rc.w) (px +. 0.5) -. fmax rc.x (px -. 0.5) in
  let cy = fmin (rc.y +. rc.h) (py +. 0.5) -. fmax rc.y (py -. 0.5) in
  clamp01 cx *. clamp01 cy

(* The value of a shape with continuous corners at (px, py): the largest
   of its corners' and the rectangle's signed distances, and whether a
   corner's curve reaches it. *)
let cont_dist s px py =
  let rc = s.sr in
  let left = px -. rc.x and right = rc.x +. rc.w -. px in
  let top = py -. rc.y and bottom = rc.y +. rc.h -. py in
  let d = ref (fmax (fmax (-.left) (-.right)) (fmax (-.top) (-.bottom))) in
  let curved = ref false in
  List.iter2
    (fun i (u, v) ->
      let c = s.scorners.(i) in
      if c.cr > 0. && u < c.ce && v < c.ce then begin
        d := fmax !d (corner_dist c u v);
        curved := true
      end)
    [ 0; 1; 2; 3 ] [ (left, top); (right, top); (right, bottom); (left, bottom) ];
  (!d, !curved)

(* Coverage with continuous corners: away from their curves, the area of
   the pixel inside the rectangle; near them, the shape's value over the
   sum of its derivatives. *)
let cont_coverage s px py =
  let d, curved = cont_dist s px py in
  if not curved then area_coverage s.sr px py
  else if Float.abs d > 2. then (if d < 0. then 1. else 0.)
  else begin
    let h = 1. /. 16. in
    let dx, _ = cont_dist s (px +. h) py in
    let dy, _ = cont_dist s px (py +. h) in
    clamp01 (0.5 -. d *. h /. fmax (Float.abs (dx -. d) +. Float.abs (dy -. d)) 1e-6)
  end

(* How much of the pixel centered at (px, py) the rounded rectangle
   covers, from the signed distance to its edge. *)
let coverage s px py =
  if s.scont then cont_coverage s px py
  else begin
    let (r0, r1, r2, r3) = s.sradii in
    let rc = s.sr in
    let hx = rc.w /. 2. and hy = rc.h /. 2. in
    let qx = px -. rc.x -. hx and qy = py -. rc.y -. hy in
    let rad =
      if qx < 0. && qy < 0. then r0
      else if qx >= 0. && qy < 0. then r1
      else if qx >= 0. then r2
      else r3
    in
    if rad <= 0. then area_coverage rc px py
    else begin
      let ax = Float.abs qx -. hx +. rad and ay = Float.abs qy -. hy +. rad in
      let d =
        if ax > 0. && ay > 0. then sqrt (ax *. ax +. ay *. ay) -. rad
        else fmax ax ay -. rad
      in
      clamp01 (0.5 -. d)
    end
  end

(* How far corner i of the rounded rectangle narrows a row v pixels from
   its horizontal edge, at the least. *)
let shape_inset s i v =
  if s.scont then snd (corner_inset s.scorners.(i) v)
  else begin
    let rad = r4_get s.sradii i in
    if rad <= 0. || v >= rad then 0.
    else if v <= 0. then rad
    else begin
      let dy = rad -. v in
      rad -. sqrt (rad *. rad -. dy *. dy)
    end
  end

(* The pixels of the row between y0 and y1 that the rounded rectangle
   covers entirely; lo >= hi when there are none. *)
let solid_span s y0 y1 =
  let rc = s.sr in
  if y0 < rc.y || y1 > rc.y +. rc.h then (0, 0)
  else begin
    (* The corners narrow the row the most at its edge nearer to theirs. *)
    let top = y0 -. rc.y and bottom = rc.y +. rc.h -. y1 in
    let left = rc.x +. fmax (shape_inset s 0 top) (shape_inset s 3 bottom) in
    let right = rc.x +. rc.w -. fmax (shape_inset s 1 top) (shape_inset s 2 bottom) in
    (iceil left, ifloor right)
  end

(* ---------- colors ---------- *)

let to_linear c = if c <= 0.04045 then c /. 12.92 else ((c +. 0.055) /. 1.055) ** 2.4
let to_srgb c = if c <= 0.0031308 then c *. 12.92 else 1.055 *. (fmax c 0.) ** (1. /. 2.4) -. 0.055

(* An sRGB color to Oklab, as the shader does. *)
let oklab c =
  let r = to_linear (float c.r /. 255.) and g = to_linear (float c.g /. 255.) and b = to_linear (float c.b /. 255.) in
  let l = Float.cbrt (0.4122214708 *. r +. 0.5363325363 *. g +. 0.0514459929 *. b) in
  let m = Float.cbrt (0.2119034982 *. r +. 0.6806995451 *. g +. 0.1073969566 *. b) in
  let s = Float.cbrt (0.0883024619 *. r +. 0.2817188376 *. g +. 0.6299787005 *. b) in
  (0.2104542553 *. l +. 0.7936177850 *. m -. 0.0040720468 *. s,
   1.9779984951 *. l -. 2.4285922050 *. m +. 0.4505937099 *. s,
   0.0259040371 *. l +. 0.7827717662 *. m -. 0.8086757660 *. s)

(* An Oklab color to sRGB components, unclamped. *)
let from_oklab (la, aa, ab) =
  let l = la +. 0.3963377774 *. aa +. 0.2158037573 *. ab in
  let m = la -. 0.1055613458 *. aa -. 0.0638541728 *. ab in
  let s = la -. 0.0894841775 *. aa -. 1.2914855480 *. ab in
  let l = l *. l *. l and m = m *. m *. m and s = s *. s *. s in
  (to_srgb (4.0767416621 *. l -. 3.3077115913 *. m +. 0.2309699292 *. s),
   to_srgb (-1.2684380046 *. l +. 2.6097574011 *. m -. 0.3413193965 *. s),
   to_srgb (-0.0041960863 *. l -. 0.7034186147 *. m +. 1.7076147010 *. s))

(* ---------- painter: fills and gradients ---------- *)

(* The fill of an op at pixel centers: its color, or its gradient or
   stripes, premultiplied and times the op's opacity. *)
type painter = {
  ppaint : paint;
  pc1 : float * float * float * float; (* premultiplied *)
  pc2 : float * float * float * float;
  plab1 : float * float * float; (* premultiplied Oklab *)
  plab2 : float * float * float;
  pg : float * float * float * float;
  pox : float;
  poy : float;
}

let new_painter ~paint_ ~c1 ~c2 ~g ~ox ~oy ~opacity =
  let pc1 = premul c1 opacity and pc2 = premul c2 opacity in
  let plab1, plab2 =
    if paint_ = Oklab then begin
      let (l1, a1, b1) = oklab c1 and (l2, a2, b2) = oklab c2 in
      let (_, _, _, al1) = pc1 and (_, _, _, al2) = pc2 in
      ((l1 *. al1, a1 *. al1, b1 *. al1), (l2 *. al2, a2 *. al2, b2 *. al2))
    end
    else ((0., 0., 0.), (0., 0., 0.))
  in
  { ppaint = paint_; pc1; pc2; plab1; plab2; pg = g; pox = ox; poy = oy }

let painter_solid p = p.ppaint = Solid
let painter_visible p =
  let (_, _, _, a1) = p.pc1 and (_, _, _, a2) = p.pc2 in
  a1 > 0. || (not (painter_solid p)) && a2 > 0.

(* The fill at a pixel center. *)
let painter_at p px py =
  match p.ppaint with
  | Solid -> p.pc1
  | Stripes ->
    let (g0, g1, g2, g3) = p.pg in
    let s = (px -. p.pox) *. g0 +. (py -. p.poy) *. g1 in
    let period = g3 in
    let phase = s -. period *. Float.floor (s /. period) in
    let cov = clamp01 (0.5 -. fmin (fmax (-.phase) (phase -. g2)) (period -. phase)) in
    let (r1, g1_, b1, a1) = p.pc1 and (r2, g2_, b2, a2) = p.pc2 in
    (r1 *. cov +. r2 *. (1. -. cov), g1_ *. cov +. g2_ *. (1. -. cov),
     b1 *. cov +. b2 *. (1. -. cov), a1 *. cov +. a2 *. (1. -. cov))
  | Linear | Oklab ->
    let (g0, g1, g2, g3) = p.pg in
    let dx = g2 -. g0 and dy = g3 -. g1 in
    let t = ref 0. in
    let l = dx *. dx +. dy *. dy in
    if l > 0. then t := clamp01 (((px -. g0) *. dx +. (py -. g1) *. dy) /. fmax l 0.0001);
    let (r1, g1_, b1, a1) = p.pc1 and (r2, g2_, b2, a2) = p.pc2 in
    let a = a1 *. (1. -. !t) +. a2 *. !t in
    if p.ppaint = Linear then
      (r1 *. (1. -. !t) +. r2 *. !t, g1_ *. (1. -. !t) +. g2_ *. !t,
       b1 *. (1. -. !t) +. b2 *. !t, a)
    else if a <= 0. then (0., 0., 0., 0.)
    else begin
      let (l1, aa1, ab1) = p.plab1 and (l2, aa2, ab2) = p.plab2 in
      let lab =
        ((l1 *. (1. -. !t) +. l2 *. !t) /. a,
         (aa1 *. (1. -. !t) +. aa2 *. !t) /. a,
         (ab1 *. (1. -. !t) +. ab2 *. !t) /. a)
      in
      let (r, g, b) = from_oklab lab in
      (clamp01 r *. a, clamp01 g *. a, clamp01 b *. a, a)
    end

(* ---------- dashed borders ---------- *)

(* How much of a dashed border of widths w (top, right, bottom, left)
   around r shows at a pixel center, as the shader computes it: each
   side, which the pixel belongs to when it is nearest that side's edge
   in widths of its border, has an odd number of dashes and gaps of equal
   length, about three widths, starting and ending with a dash. *)
let dash r (wt, wr, wb, wl) px py =
  let qx = px -. r.x and qy = py -. r.y in
  let d dist width = if width > 0. then dist /. width else 1e9 in
  let dt = d qy wt and dr = d (r.w -. qx) wr and db = d (r.h -. qy) wb and dl = d qx wl in
  let s, length, bw =
    if dt <= dr && dt <= db && dt <= dl then (qx, r.w, wt)
    else if dr <= db && dr <= dl then (qy, r.h, wr)
    else if db <= dl then (r.w -. qx, r.w, wb)
    else (r.h -. qy, r.h, wl)
  in
  let n = fmax 1. (Float.floor ((length /. (3. *. bw) +. 1.) *. 0.5 +. 0.5)) in
  let seg = length /. (2. *. n -. 1.) in
  let k = Float.floor (s /. seg) in
  let f = s -. k *. seg in
  let edge = fmin f (seg -. f) in
  let edge = if k -. 2. *. Float.floor (k *. 0.5) < 0.5 then -.edge else edge in
  clamp01 (0.5 -. edge)

(* ---------- the renderer ---------- *)

let no_span = min_int

type clip = { cshape : shape; cround : bool; cspans : int }

(* Per-worker scratch: the band's clip stack and the bounds their
   rectangles make, the shadow profile and the buffer holding the solid
   spans a continuous clip computed for its rows. *)
type renderer = {
  mutable dst : Image.t;
  mutable rarea : irect; (* the part of dst to draw, in whole pixels *)
  mutable rx0 : int;
  mutable ry0 : int;
  mutable rx1 : int;
  mutable ry1 : int;
  mutable rclips : clip list; (* innermost last *)
  mutable profile : float array;
  mutable span_buf : int array; (* lo,hi pairs, no_span until found *)
  mutable span_len : int;
}

let new_renderer () = {
  dst = Image.create ~w:0 ~h:0;
  rarea = irect 0 0 0 0;
  rx0 = 0; ry0 = 0; rx1 = 0; ry1 = 0;
  rclips = []; profile = [||]; span_buf = [||]; span_len = 0;
}

let ensure_span_buf r n =
  if Array.length r.span_buf < n then
    r.span_buf <- Array.make (max n (2 * Array.length r.span_buf + 8)) no_span

let update_bounds r =
  r.rx0 <- r.rarea.x0; r.ry0 <- r.rarea.y0; r.rx1 <- r.rarea.x1; r.ry1 <- r.rarea.y1;
  List.iter
    (fun c ->
      r.rx0 <- max r.rx0 (ifloor c.cshape.sr.x);
      r.ry0 <- max r.ry0 (ifloor c.cshape.sr.y);
      r.rx1 <- min r.rx1 (iceil (c.cshape.sr.x +. c.cshape.sr.w));
      r.ry1 <- min r.ry1 (iceil (c.cshape.sr.y +. c.cshape.sr.h)))
    r.rclips

(* The pixels a rectangle touches within the clips. *)
let pixel_bounds r rc =
  (max r.rx0 (ifloor rc.x), max r.ry0 (ifloor rc.y),
   min r.rx1 (iceil (rc.x +. rc.w)), min r.ry1 (iceil (rc.y +. rc.h)))

(* How much of pixel (x, y) the clips let through, given the clip
   rectangles' pixel bounds already apply. *)
let clip_coverage r x y =
  let cov = ref 1. in
  let px = float x +. 0.5 and py = float y +. 0.5 in
  List.iter
    (fun c ->
      if !cov <> 0. then
        cov :=
          !cov
          *.
          (if c.cround then coverage c.cshape px py
           else
             (* Partial pixels at fractional clip edges. *)
             clamp01 (fmin (px -. c.cshape.sr.x) (c.cshape.sr.x +. c.cshape.sr.w -. px) +. 0.5)
             *. clamp01 (fmin (py -. c.cshape.sr.y) (c.cshape.sr.y +. c.cshape.sr.h -. py) +. 0.5)))
    r.rclips;
  !cov

(* The pixels of row y that the clips let through entirely, so that
   clipCoverage need not run for them. *)
let clip_solid r y =
  let lo = ref r.rx0 and hi = ref r.rx1 in
  List.iter
    (fun c ->
      let l, h =
        if c.cspans >= 0 && y >= r.rarea.y0 && y < r.rarea.y1 then begin
          let k = c.cspans + 2 * (y - r.rarea.y0) in
          if r.span_buf.(k) = no_span then begin
            let l, h = solid_span c.cshape (float y) (float (y + 1)) in
            r.span_buf.(k) <- l;
            r.span_buf.(k + 1) <- h;
            (l, h)
          end
          else (r.span_buf.(k), r.span_buf.(k + 1))
        end
        else solid_span c.cshape (float y) (float (y + 1))
      in
      lo := max !lo l;
      hi := min !hi h)
    r.rclips;
  (!lo, !hi)

(* ---------- per-op drawing ---------- *)

let blend_at r x y c cov = blend r.dst.Image.pix (y * r.dst.Image.stride + 4 * x) c cov

(* A rounded rectangle filled with the op's paint, with a border of
   widths around its inner edge, dashed or not. *)
let r_fill r (op : fill_op) =
  if not (rect_empty op.frect) then begin
    let opacity = if op.fopacity = 0. then 1. else op.fopacity in
    let radii = corners op.frect op.fradii op.fcontinuous in
    let outer = new_shape op.frect radii in
    let pt = new_painter ~paint_:op.fpaint ~c1:op.fcolor ~c2:op.fcolor2
        ~g:op.fgradient ~ox:op.frect.x ~oy:op.frect.y ~opacity in
    let border = premul op.fborder_color opacity in
    let bw = if op.fborder_color.a = 0 then (0., 0., 0., 0.) else op.fborder in
    let has_border = Lui_scene.has_border bw in
    let inner =
      if has_border then begin
        let ir, iradii = inner_radii op.frect radii bw in
        new_shape ir iradii
      end
      else outer
    in
    let has_fill = painter_visible pt and solid = painter_solid pt in
    let x0, y0, x1, y1 = pixel_bounds r op.frect in
    for y = y0 to y1 - 1 do
      let row = y * r.dst.Image.stride in
      let py = float y +. 0.5 in
      let cl, ch = clip_solid r y in
      let ol, oh = solid_span outer (float y) (float (y + 1)) in
      let il, ih =
        if has_border then
          if rect_empty inner.sr then (0, 0) else solid_span inner (float y) (float (y + 1))
        else (ol, oh)
      in
      (* The middle run, inside the clips, the shape and its border, is
         plain fill. *)
      let sl = max (max il cl) x0 and sh = min (min ih ch) x1 in
      if sl < sh && has_fill && solid then blend_span r.dst.Image.pix row sl sh pt.pc1 1.;
      let x = ref x0 in
      while !x < x1 do
        if !x >= sl && !x < sh then begin
          if (not has_fill) || solid then x := sh - 1 (* past the run, which is done *)
          else blend_at r !x y (painter_at pt (float !x +. 0.5) py) 1.
        end
        else begin
          let px = float !x +. 0.5 in
          let clip_cov = if !x < cl || !x >= ch then clip_coverage r !x y else 1. in
          if clip_cov <> 0. then begin
            let oc = if !x < ol || !x >= oh then coverage outer px py else 1. in
            if oc <> 0. then begin
              if has_fill then blend_at r !x y (painter_at pt px py) (oc *. clip_cov);
              if has_border then begin
                let ic = if rect_empty inner.sr then 0. else coverage inner px py in
                let bc = oc -. ic in
                let bc = if bc > 0. && op.fdashed then bc *. dash op.frect bw px py else bc in
                if bc > 0. then blend_at r !x y border (bc *. clip_cov)
              end
            end
          end
        end;
        incr x
      done
    done
  end

(* A rounded rectangle made transparent within the clips: each pixel
   keeps what its coverage leaves of it, as renderers blend with a
   destination factor of one minus the coverage and none of the source. *)
let r_hole r (op : hole_op) =
  if not (rect_empty op.hrect) then begin
    let opacity = if op.hopacity = 0. then 1. else op.hopacity in
    let sh = new_shape op.hrect (corners op.hrect op.hradii op.hcontinuous) in
    let x0, y0, x1, y1 = pixel_bounds r op.hrect in
    for y = y0 to y1 - 1 do
      let row = y * r.dst.Image.stride in
      let py = float y +. 0.5 in
      let cl, ch = clip_solid r y in
      let ol, oh = solid_span sh (float y) (float (y + 1)) in
      let sl = max (max ol cl) x0 and shi = min (min oh ch) x1 in
      if sl < shi then begin
        if opacity >= 1. then Bytes.fill r.dst.Image.pix (row + 4 * sl) (4 * (shi - sl)) '\000'
        else
          for x = sl to shi - 1 do
            erase r.dst.Image.pix (row + 4 * x) opacity
          done
      end;
      let x = ref x0 in
      while !x < x1 do
        if !x >= sl && !x < shi then x := shi - 1 (* past the run, which is done *)
        else begin
          let cov = clip_coverage r !x y in
          if cov > 0. then begin
            let cov = if !x < ol || !x >= oh then cov *. coverage sh (float !x +. 0.5) py else cov in
            if cov > 0. then erase r.dst.Image.pix (row + 4 * !x) (cov *. opacity)
          end
        end;
        incr x
      done
    done
  end

let gaussian x sigma = exp (-.(x *. x) /. (2. *. sigma *. sigma)) /. (sqrt (2. *. Float.pi) *. sigma)

(* The error function within 5e-4, as the GPU evaluator approximates it
   (Abramowitz and Stegun 7.1.27). *)
let erf x =
  let a = Float.abs x in
  let t = 1. +. (0.278393 +. (0.230389 +. 0.078108 *. (a *. a)) *. a) *. a in
  let t = t *. t in
  let e = 1. -. 1. /. (t *. t) in
  if x < 0. then -.e else e

(* A Gaussian-blurred rounded rectangle, integrating the blur along y
   numerically and along x exactly, outside the box casting it, if any. *)
let r_shadow r (op : shadow_op) =
  let sigma = op.sblur /. 2. in
  let cast = not (rect_empty op.scast) in
  if sigma < 0.5 && not cast then
    (* Too sharp to tell from the box itself: a plain fill. *)
    r_fill r
      { frect = op.srect; fradii = op.sradii; fcontinuous = op.scontinuous;
        fcolor = op.scolor; fpaint = Solid; fcolor2 = op.scolor;
        fgradient = (0., 0., 0., 0.); fborder = (0., 0., 0., 0.);
        fborder_color = color 0 0 0 0; fdashed = false; fwide = 0;
        fopacity = op.sopacity }
  else begin
    let opacity = if op.sopacity = 0. then 1. else op.sopacity in
    let c = premul op.scolor opacity in
    let radii = corners op.srect op.sradii op.scontinuous in
    let shadow_box = new_shape op.srect radii in
    let caster = new_shape op.scast (corners op.scast op.scast_radii op.scontinuous) in
    (* How much of pixel (x, y) the box casting the shadow leaves to it. *)
    let outside x y = 1. -. coverage caster (float x +. 0.5) (float y +. 0.5) in
    if sigma < 0.5 then begin
      (* The box itself, outside the box casting it. *)
      let x0, y0, x1, y1 = pixel_bounds r op.srect in
      for y = y0 to y1 - 1 do
        for x = x0 to x1 - 1 do
          let v = coverage shadow_box (float x +. 0.5) (float y +. 0.5) *. outside x y in
          if v > 0. then blend_at r x y c (v *. clip_coverage r x y)
        done
      done
    end
    else begin
      let (r0, r1, r2, r3) = radii in
      let corner =
        fmax (Float.abs r0) (fmax (Float.abs r1) (fmax (Float.abs r2) (Float.abs r3)))
      in
      (* Continuous corners narrow the box over the end of their curves. *)
      let continuous = op.scontinuous && corner > 0. in
      let cc = new_cont_corner corner corner corner op.srect.w op.srect.h in
      let ext = 3. *. sigma in
      let box =
        rect (op.srect.x -. ext) (op.srect.y -. ext) (op.srect.w +. 2. *. ext) (op.srect.h +. 2. *. ext)
      in
      let x0, y0, x1, y1 = pixel_bounds r box in
      if x0 < x1 && y0 < y1 then begin
        let cx = op.srect.x +. op.srect.w /. 2. and cy = op.srect.y +. op.srect.h /. 2. in
        let hx = op.srect.w /. 2. and hy = op.srect.h /. 2. in
        let k = sqrt 0.5 /. sigma in
        (* The shadow is the box blurred along y, at four samples, of a
           box blurred exactly along x whose width the corners narrow.
           Where no corner narrows it, a row is one horizontal profile
           scaled, and in the middle of a row, far from the narrowed
           edges, the profile is 1. *)
        if Array.length r.profile < x1 - x0 then r.profile <- Array.make (x1 - x0) 0.;
        let profile = r.profile in
        for x = x0 to x1 - 1 do
          let px = float x +. 0.5 -. cx in
          profile.(x - x0) <- 0.5 *. (erf ((px +. hx) *. k) -. erf ((px -. hx) *. k))
        done;
        let far = 2.6 /. k in (* where erf passes 0.9997 *)
        (* kx0..ky1 are the pixels the box casting the shadow touches. *)
        let kx0, ky0, kx1, ky1 =
          if cast then
            (ifloor op.scast.x, ifloor op.scast.y,
             iceil (op.scast.x +. op.scast.w), iceil (op.scast.y +. op.scast.h))
          else (0, 0, 0, 0)
        in
        for y = y0 to y1 - 1 do
          let py = float y +. 0.5 -. cy in
          let low = py -. hy and high = py +. hy in
          let start = fmin (fmax (-.ext) low) high and fin = fmin (fmax ext low) high in
          let step = (fin -. start) /. 4. in
          let weight = Array.make 4 0. and half = Array.make 4 0. in
          let sum = ref 0. and narrowest = ref hx in
          let yy = ref (start +. step *. 0.5) in
          for i = 0 to 3 do
            weight.(i) <- gaussian !yy sigma *. step;
            sum := !sum +. weight.(i);
            half.(i) <- hx;
            let v = hy -. Float.abs (py -. !yy) in
            if continuous then begin
              if v < cc.ce then begin
                let at, _ = corner_inset cc v in
                half.(i) <- hx -. at;
                narrowest := fmin !narrowest half.(i)
              end
            end
            else begin
              let delta = fmin (hy -. corner -. Float.abs (py -. !yy)) 0. in
              if delta < 0. then begin
                half.(i) <- hx -. corner +. sqrt (fmax 0. (corner *. corner -. delta *. delta));
                narrowest := fmin !narrowest half.(i)
              end
            end;
            yy := !yy +. step
          done;
          if !sum > 0.002 then begin
            let straight = !narrowest = hx in
            let row = y * r.dst.Image.stride in
            let cl, ch = clip_solid r y in
            let ml = max (iceil (cx -. !narrowest +. far -. 0.5)) (max x0 cl) in
            let mh = min (ifloor (cx +. !narrowest -. far -. 0.5) + 1) (min x1 ch) in
            (* On the row, the box casting the shadow touches kl..kh,
               which the middle leaves out, and hides it in sl..sh. *)
            let kl, kh, sl, sh =
              if cast && y >= ky0 && y < ky1 then begin
                let sl, sh = solid_span caster (float y) (float (y + 1)) in
                (kx0, kx1, sl, sh)
              end
              else (0, 0, 0, 0)
            in
            if kl < kh then begin
              blend_span r.dst.Image.pix row ml (min mh kl) c !sum;
              blend_span r.dst.Image.pix row (max ml kh) mh c !sum
            end
            else blend_span r.dst.Image.pix row ml mh c !sum;
            let x = ref x0 in
            while !x < x1 do
              if !x >= ml && !x < mh && (!x < kl || !x >= kh) then begin
                x := mh - 1;
                if !x < kl then x := min mh kl - 1
              end
              else if !x >= sl && !x < sh then x := sh - 1
              else begin
                let v =
                  if straight then profile.(!x - x0) *. !sum
                  else begin
                    let px = float !x +. 0.5 -. cx in
                    let v = ref 0. in
                    for i = 0 to 3 do
                      v := !v +. weight.(i) *. 0.5 *. (erf ((px +. half.(i)) *. k) -. erf ((px -. half.(i)) *. k))
                    done;
                    !v
                  end
                in
                let v = if !x >= kl && !x < kh then v *. outside !x y else v in
                if v > 0.002 then begin
                  let v = if !x < cl || !x >= ch then v *. clip_coverage r !x y else v in
                  blend_at r !x y c v
                end
              end;
              incr x
            done
          end
        done
      end
    end
  end

(* An inner shadow: inside the box Cast, what the hole Rect, blurred as
   a shadow blurs a box, leaves uncovered. *)
let r_inset_shadow r (op : shadow_op) =
  let x0, y0, x1, y1 = pixel_bounds r op.scast in
  if x0 < x1 && y0 < y1 then begin
    let opacity = if op.sopacity = 0. then 1. else op.sopacity in
    let c = premul op.scolor opacity in
    let box = new_shape op.scast (corners op.scast op.scast_radii op.scontinuous) in
    let radii = corners op.srect op.sradii op.scontinuous in
    let hole = new_shape op.srect radii in
    let empty = rect_empty op.srect in
    let sigma = op.sblur /. 2. in
    if sigma < 0.5 || empty then begin
      for y = y0 to y1 - 1 do
        (* Nothing shows where the hole covers the row's pixels
           entirely, as it does most of a large box. *)
        let sl, sh = if empty then (0, 0) else solid_span hole (float y) (float (y + 1)) in
        let x = ref x0 in
        while !x < x1 do
          if !x >= sl && !x < sh then x := sh - 1
          else begin
            let px = float !x +. 0.5 and py = float y +. 0.5 in
            let v = coverage box px py in
            let v = if empty then v else v *. (1. -. coverage hole px py) in
            if v > 0. then blend_at r !x y c (v *. clip_coverage r !x y)
          end;
          incr x
        done
      done
    end
    else begin
      (* The hole blurred as a shadow blurs a box, four samples along y
         and exactly along x. *)
      let (r0, r1, r2, r3) = radii in
      let corner =
        fmax (Float.abs r0) (fmax (Float.abs r1) (fmax (Float.abs r2) (Float.abs r3)))
      in
      let continuous = op.scontinuous && corner > 0. in
      let cc = new_cont_corner corner corner corner op.srect.w op.srect.h in
      let ext = 3. *. sigma in
      let cx = op.srect.x +. op.srect.w /. 2. and cy = op.srect.y +. op.srect.h /. 2. in
      let hx = op.srect.w /. 2. and hy = op.srect.h /. 2. in
      let k = sqrt 0.5 /. sigma in
      let far = 2.6 /. k in (* where erf passes 0.9997 *)
      for y = y0 to y1 - 1 do
        let py = float y +. 0.5 -. cy in
        let low = py -. hy and high = py +. hy in
        let start = fmin (fmax (-.ext) low) high and fin = fmin (fmax ext low) high in
        let step = (fin -. start) /. 4. in
        let weight = Array.make 4 0. and half = Array.make 4 0. in
        let sum = ref 0. and narrowest = ref hx in
        let yy = ref (start +. step *. 0.5) in
        for i = 0 to 3 do
          weight.(i) <- gaussian !yy sigma *. step;
          sum := !sum +. weight.(i);
          half.(i) <- hx;
          let v = hy -. Float.abs (py -. !yy) in
          if continuous then begin
            if v < cc.ce then begin
              let at, _ = corner_inset cc v in
              half.(i) <- hx -. at;
              narrowest := fmin !narrowest half.(i)
            end
          end
          else begin
            let delta = fmin (hy -. corner -. Float.abs (py -. !yy)) 0. in
            if delta < 0. then begin
              half.(i) <- hx -. corner +. sqrt (fmax 0. (corner *. corner -. delta *. delta));
              narrowest := fmin !narrowest half.(i)
            end
          end;
          yy := !yy +. step
        done;
        let cl, ch = clip_solid r y in
        (* In the middle of the row, far from the hole's edges, the hole
           covers sum of each pixel, and nothing shows where that is
           all. *)
        let ml, mh =
          if 1. -. !sum <= 0.002 then
            (max (iceil (cx -. !narrowest +. far -. 0.5)) x0,
             min (ifloor (cx +. !narrowest -. far -. 0.5) + 1) x1)
          else (x1, x1)
        in
        let x = ref x0 in
        while !x < x1 do
          if !x >= ml && !x < mh then x := mh - 1
          else begin
            let px = float !x +. 0.5 in
            let covered = ref 0. in
            for i = 0 to 3 do
              covered := !covered +. weight.(i) *. 0.5 *. (erf ((px -. cx +. half.(i)) *. k) -. erf ((px -. cx -. half.(i)) *. k))
            done;
            let v = (1. -. !covered) *. coverage box px (float y +. 0.5) in
            if v > 0.002 then begin
              let v = if !x < cl || !x >= ch then v *. clip_coverage r !x y else v in
              blend_at r !x y c v
            end
          end;
          incr x
        done
      done
    end
  end

(* Ordinary opaque mask text blended by integer math: the same result
   the floating-point path gives, without converting every destination
   channel. Rounded clip edges still use the general coverage. *)
let mask_opaque r a (g : glyph) gx gy x0 y0 x1 y1 =
  let c = g.gcolor in
  for y = y0 to y1 - 1 do
    let cl, ch = clip_solid r y in
    let at = (g.gv + y - gy) * a.Atlas.w + g.gu + x0 - gx in
    let row = y * r.dst.Image.stride in
    for i = 0 to x1 - x0 - 1 do
      let m = Char.code (Bytes.get a.Atlas.pix (at + i)) in
      if m <> 0 then begin
        let p = row + 4 * (x0 + i) and x = x0 + i in
        if x < cl || x >= ch then
          blend r.dst.Image.pix p (premul c 1.) (clip_coverage r x y *. (float m /. 255.))
        else if m = 255 then begin
          Bytes.set r.dst.Image.pix p (Char.chr c.b);
          Bytes.set r.dst.Image.pix (p + 1) (Char.chr c.g);
          Bytes.set r.dst.Image.pix (p + 2) (Char.chr c.r);
          Bytes.set r.dst.Image.pix (p + 3) '\255'
        end
        else begin
          Bytes.set r.dst.Image.pix p (Char.chr (mix_mask c.b (byte_at r.dst.Image.pix p) m));
          Bytes.set r.dst.Image.pix (p + 1) (Char.chr (mix_mask c.g (byte_at r.dst.Image.pix (p + 1)) m));
          Bytes.set r.dst.Image.pix (p + 2) (Char.chr (mix_mask c.r (byte_at r.dst.Image.pix (p + 2)) m));
          Bytes.set r.dst.Image.pix (p + 3) (Char.chr (over m (byte_at r.dst.Image.pix (p + 3)) (255 - m)))
        end
      end
    done
  done

let r_glyphs r (op : glyphs_op) s glyphs =
  let pt =
    if op.gpaint = Linear || op.gpaint = Oklab then begin
      let opacity = if op.gopacity = 0. then 1. else op.gopacity in
      Some (new_painter ~paint_:op.gpaint ~c1:op.gcolor ~c2:op.gcolor2
              ~g:op.ggradient ~ox:0. ~oy:0. ~opacity)
    end
    else None
  in
  let text = s.text in
  let gend = min op.gend (Array.length glyphs) in
  for gi = max op.gstart 0 to gend - 1 do
    let g = glyphs.(gi) in
    let atlas = if g.gcolored || g.gsubpixel then s.color_atlas else s.mask_atlas in
    let gx = iround g.gx and gy = iround g.gy in
    let x0 = max gx r.rx0 and y0 = max gy r.ry0 in
    let x1 = min (gx + g.guw) r.rx1 and y1 = min (gy + g.gvh) r.ry1 in
    if x0 < x1 && y0 < y1 then begin
      let tint0 = premul g.gcolor 1. in
      let alpha = float g.gcolor.a /. 255. in
      let contrast = if g.gsubpixel then text.subpixel_contrast else text.contrast in
      let boost = if g.gthin then thin_boost else 0. in
      let (g0, g1, g2, g3) = text.gamma_ratios in
      let correct = contrast <> 0. || boost <> 0. || (g0, g1, g2, g3) <> (0., 0., 0., 0.) in
      if (not g.gcolored) && (not g.gsubpixel) && Option.is_none pt && (not correct) && g.gcolor.a = 255 then
        mask_opaque r atlas g gx gy x0 y0 x1 y1
      else
        for y = y0 to y1 - 1 do
          let row = y * r.dst.Image.stride in
          let cl, ch = clip_solid r y in
          let ay = g.gv + y - gy in
          for x = x0 to x1 - 1 do
            let ax = g.gu + x - gx in
            let cov = if x < cl || x >= ch then clip_coverage r x y else 1. in
            if cov <> 0. then begin
              let p = row + 4 * x in
              if g.gcolored then begin
                let so = (ay * atlas.Atlas.w + ax) * 4 in
                let ch_ i = byte_f atlas.Atlas.pix (so + i) in
                blend r.dst.Image.pix p
                  (ch_ 0 *. alpha, ch_ 1 *. alpha, ch_ 2 *. alpha, ch_ 3 *. alpha) cov
              end
              else if g.gsubpixel then begin
                let so = (ay * atlas.Atlas.w + ax) * 4 in
                let m0 = byte_at atlas.Atlas.pix so
                and m1 = byte_at atlas.Atlas.pix (so + 1)
                and m2 = byte_at atlas.Atlas.pix (so + 2) in
                if m0 lor m1 lor m2 <> 0 then begin
                  let tint =
                    match pt with
                    | Some p -> painter_at p (float x +. 0.5) (float y +. 0.5)
                    | None -> tint0
                  in
                  let c = unpremul tint in
                  let a = (float m0 /. 255., float m1 /. 255., float m2 /. 255.) in
                  let a =
                    if correct then subpixel_coverage a c ~contrast ~boost text.gamma_ratios
                    else a
                  in
                  let (_, _, _, ta) = tint in
                  blend_subpixel r.dst.Image.pix p c a (ta *. cov)
                end
              end
              else begin
                let m = byte_at atlas.Atlas.pix (ay * atlas.Atlas.w + ax) in
                if m <> 0 then begin
                  let tint =
                    match pt with
                    | Some p -> painter_at p (float x +. 0.5) (float y +. 0.5)
                    | None -> tint0
                  in
                  let a = float m /. 255. in
                  let a =
                    if correct then text_coverage a (unpremul tint) ~contrast ~boost text.gamma_ratios
                    else a
                  in
                  blend r.dst.Image.pix p tint (cov *. a)
                end
              end
            end
          done
        done
    end
  done

(* A premultiplied pixel of img at (u, v), bilinear, clamped to src. *)
let sample img u v (src : rect) =
  let u = u -. 0.5 and v = v -. 0.5 in
  let x0 = ifloor u and y0 = ifloor v in
  let tx = u -. float x0 and ty = v -. float y0 in
  let minX = int_of_float src.x and minY = int_of_float src.y in
  let maxX = min (iceil (src.x +. src.w) - 1) (img.iw - 1) in
  let maxY = min (iceil (src.y +. src.h) - 1) (img.ih - 1) in
  let at x y =
    let x = max minX (min x maxX) and y = max minY (min y maxY) in
    (y * img.iw + x) * 4
  in
  let p00 = at x0 y0 and p10 = at (x0 + 1) y0 and p01 = at x0 (y0 + 1) and p11 = at (x0 + 1) (y0 + 1) in
  let ch i =
    let top = byte_f img.ipix (p00 + i) *. (1. -. tx) +. byte_f img.ipix (p10 + i) *. tx in
    let bot = byte_f img.ipix (p01 + i) *. (1. -. tx) +. byte_f img.ipix (p11 + i) *. tx in
    top *. (1. -. ty) +. bot *. ty
  in
  (ch 0, ch 1, ch 2, ch 3)

let r_image r (op : image_op) =
  let img = op.iimage in
  if img.iw <> 0 && img.ih <> 0 && not (rect_empty op.irect2 || rect_empty op.isrc) then begin
    let opacity = if op.iopacity = 0. then 1. else op.iopacity in
    let radii = corners op.irect2 op.iradii op.icontinuous in
    let box = new_shape op.irect2 radii in
    let round = has_radii radii in
    let sx = op.isrc.w /. op.irect2.w and sy = op.isrc.h /. op.irect2.h in
    let x0, y0, x1, y1 = pixel_bounds r op.irect2 in
    for y = y0 to y1 - 1 do
      let py = float y +. 0.5 in
      let cl, ch = clip_solid r y in
      let ol, oh = solid_span box (float y) (float (y + 1)) in
      for x = x0 to x1 - 1 do
        let px = float x +. 0.5 in
        let cov = opacity in
        let cov = if x < ol || x >= oh || not round then cov *. coverage box px py else cov in
        let cov = if x < cl || x >= ch then cov *. clip_coverage r x y else cov in
        if cov > 0. then begin
          let cr, cg, cb, ca =
            sample img (op.isrc.x +. (px -. op.irect2.x) *. sx) (op.isrc.y +. (py -. op.irect2.y) *. sy) op.isrc
          in
          let cr, cg, cb =
            if op.igrayscale then begin
              let l = 0.2126 *. cr +. 0.7152 *. cg +. 0.0722 *. cb in
              (l, l, l)
            end
            else (cr, cg, cb)
          in
          blend_at r x y (cr, cg, cb, ca) cov
        end
      done
    done
  end

(* An effect drawn by its CPU twin px over its backdrop b (None for an
   effect reading none), within its shape, whose corners are continuous
   when the op's are, while the effect works with circular ones. The
   twin gives the premultiplied color at each pixel center. *)
let r_effect r (op : effect_draw) px b =
  if not (rect_empty op.edrect) then begin
    let opacity = if op.edopacity = 0. then 1. else op.edopacity in
    let radii = corners op.edrect op.edradii op.edcontinuous in
    let box = new_shape op.edrect radii in
    let round = has_radii radii in
    let x0, y0, x1, y1 = pixel_bounds r op.edrect in
    for y = y0 to y1 - 1 do
      let py = float y +. 0.5 in
      let cl, ch = clip_solid r y in
      let ol, oh = solid_span box (float y) (float (y + 1)) in
      for x = x0 to x1 - 1 do
        let px0 = float x +. 0.5 in
        let cov = opacity in
        let cov = if x < ol || x >= oh || not round then cov *. coverage box px0 py else cov in
        let cov = if x < cl || x >= ch then cov *. clip_coverage r x y else cov in
        if cov > 0. then begin
          let cr, cg, cb = px.color_at px0 py b in
          let i = y * r.dst.Image.stride + 4 * x in
          if cov >= 1. then begin
            Bytes.set r.dst.Image.pix i (Char.chr (to8 cb));
            Bytes.set r.dst.Image.pix (i + 1) (Char.chr (to8 cg));
            Bytes.set r.dst.Image.pix (i + 2) (Char.chr (to8 cr));
            Bytes.set r.dst.Image.pix (i + 3) '\255'
          end
          else blend r.dst.Image.pix i (cr, cg, cb, 1.) cov
        end
      done
    done
  end

(* ---------- work teams ----------

   The bands of a draw, and the lines of a backdrop pass, split over a
   team of domains: each takes parts in turn, as they differ in cost.
   Every part touches pixels no other writes, so the output is what a
   single worker would draw. *)

let band_rows = 64
let effect_rows = 16
let work_area = 128 lsl 10
let texel_work = 64 lsl 10
let max_workers = 8

(* parts 0..parts-1 of a job, on up to members workers. *)
let run_team members parts f =
  let members = max 1 (min members (min parts max_workers)) in
  if members <= 1 then for p = 0 to parts - 1 do f 0 p done
  else begin
    let next = Atomic.make 0 in
    let rec work member =
      let p = Atomic.fetch_and_add next 1 in
      if p < parts then begin
        f member p;
        work member
      end
    in
    let ds = List.init (members - 1) (fun m -> Domain.spawn (fun () -> work (m + 1))) in
    work 0;
    List.iter Domain.join ds
  end

(* ---------- backdrops ----------

   The backdrop of an effect, as the GPU evaluator's textures compute
   it, rounded to 8 bits at each step: the pixels of its area, averaged
   into texels, blurred along rows and then along columns. *)

let average_pass = 0 and rows_pass = 1 and columns_pass = 2

type backdrop = {
  mutable bimg : backdrop_image; (* what a render gives the effect *)
  mutable bpix : float array; (* capacity behind bimg *)
  mutable btmp : float array; (* rows blurred, before the columns *)
  mutable bweights : float array;
  mutable bdst : Image.t;
  mutable bpass : int;
}

let bd_create () = {
  bimg = { bd = { barea = irect 0 0 0 0; bdown = 1; bsigma = 0.; bradius = 0 };
           bw = 0; bh = 0; bpix = [||] };
  bpix = [||]; btmp = [||]; bweights = [||];
  bdst = Image.create ~w:0 ~h:0; bpass = 0;
}

(* Row j of the averaged texels: the average of each square of the
   area, those along its far edges repeating its last pixels, as a
   texture's edges do. *)
let bd_average bd j =
  let img = bd.bimg in
  let k = img.bd.bdown and dst = bd.bdst in
  let inv = 1. /. float (k * k) in
  for i = 0 to img.bw - 1 do
    let c0 = ref 0. and c1 = ref 0. and c2 = ref 0. and c3 = ref 0. in
    for dy = 0 to k - 1 do
      let y = min (img.bd.barea.y0 + j * k + dy) (img.bd.barea.y1 - 1) in
      let row = y * dst.Image.stride in
      for dx = 0 to k - 1 do
        let x = min (img.bd.barea.x0 + i * k + dx) (img.bd.barea.x1 - 1) in
        let p = row + 4 * x in
        (* BGRA to RGBA. *)
        c0 := !c0 +. byte_f dst.Image.pix (p + 2);
        c1 := !c1 +. byte_f dst.Image.pix (p + 1);
        c2 := !c2 +. byte_f dst.Image.pix p;
        c3 := !c3 +. byte_f dst.Image.pix (p + 3)
      done
    done;
    let o = 4 * (j * img.bw + i) in
    img.bpix.(o) <- texel (!c0 *. inv);
    img.bpix.(o + 1) <- texel (!c1 *. inv);
    img.bpix.(o + 2) <- texel (!c2 *. inv);
    img.bpix.(o + 3) <- texel (!c3 *. inv)
  done

(* Blur line of src into dst: n texels step apart, from line*next,
   clamping at its ends. *)
let bd_blur bd dst src step next n line =
  let rad = bd.bimg.bd.bradius and w = bd.bweights in
  (* Every texel takes every weight, those past the ends on the last
     texel. *)
  let sum = ref w.(0) in
  for o = 1 to rad do
    sum := !sum +. 2. *. w.(o)
  done;
  let base = line * next in
  for i = 0 to n - 1 do
    let po = base + i * step in
    let c = Array.make 4 0. in
    for ch = 0 to 3 do
      c.(ch) <- src.(po + ch) *. w.(0)
    done;
    if i >= rad && i + rad < n then
      for o = 1 to rad do
        let a = base + (i - o) * step and b = base + (i + o) * step in
        let wo = w.(o) in
        for ch = 0 to 3 do
          c.(ch) <- c.(ch) +. (src.(a + ch) +. src.(b + ch)) *. wo
        done
      done
    else
      for o = 1 to rad do
        let a = base + max (i - o) 0 * step and b = base + min (i + o) (n - 1) * step in
        let wo = w.(o) in
        for ch = 0 to 3 do
          c.(ch) <- c.(ch) +. (src.(a + ch) +. src.(b + ch)) *. wo
        done
      done;
    dst.(po) <- texel (c.(0) /. !sum);
    dst.(po + 1) <- texel (c.(1) /. !sum);
    dst.(po + 2) <- texel (c.(2) /. !sum);
    dst.(po + 3) <- texel (c.(3) /. !sum)
  done

let bd_line bd _ i =
  match bd.bpass with
  | 0 -> bd_average bd i
  | 1 -> bd_blur bd bd.btmp bd.bimg.bpix 4 (4 * bd.bimg.bw) bd.bimg.bw i
  | _ -> bd_blur bd bd.bimg.bpix bd.btmp (4 * bd.bimg.bw) 4 bd.bimg.bh i

(* Lines 0 to n-1 of a pass, each work texels times taps, on several
   cores when they are worth it. *)
let bd_run bd pass n work =
  bd.bpass <- pass;
  let workers =
    max 1 (min (Domain.recommended_domain_count ()) (min (n * work / texel_work) max_workers))
  in
  run_team workers n (bd_line bd)

(* The backdrop b of dst. *)
let bd_read bd dst b =
  let w, h = backdrop_size b in
  let n = 4 * w * h in
  (* backdrop_sample's shared clamp can take the texel rows up to w-1:
     the capacity covers the rows past h so they can repeat the last. *)
  let cap = 4 * w * max w h in
  if Array.length bd.bpix < cap then begin
    bd.bpix <- Array.make cap 0.;
    bd.btmp <- Array.make cap 0.
  end;
  bd.bimg <- { bd = b; bw = w; bh = h; bpix = bd.bpix };
  if n > 0 then begin
    bd.bdst <- dst;
    let k = b.bdown in
    bd_run bd average_pass h (w * k * k);
    if b.bradius > 0 then begin
      bd.bweights <- Array.init (b.bradius + 1) (fun i -> blur_weight i b.bsigma);
      let taps = 2 * b.bradius + 1 in
      bd_run bd rows_pass h (w * taps);
      bd_run bd columns_pass w (h * taps)
    end;
    for j = h to w - 1 do
      Array.blit bd.bpix (4 * ((h - 1) * w)) bd.bpix (4 * (j * w)) (4 * w)
    done
  end

(* ---------- the drawer ---------- *)

(* What draw keeps from scene to scene: the renderers of the bands, the
   backdrop of an effect, and the effects' CPU twins. *)
type drawer = {
  mutable rs : renderer array;
  bd : backdrop;
  mutable fx : (fx * effect_pixels) list;
}

let new_drawer () = { rs = [||]; bd = bd_create (); fx = [] }

(* What draws e on the CPU, made the first time. *)
let pixels_of d e =
  let rec find = function
    | [] -> None
    | (k, v) :: _ when k == e -> Some v
    | _ :: rest -> find rest
  in
  match find d.fx with
  | Some p -> p
  | None ->
    let p = e.epixels () in
    d.fx <- (e, p) :: d.fx;
    p

(* The pixels of s within area, operations from to to but those whose
   bounds miss it, over the clear color from the first; those before only
   clip. px draws operation from when it is an effect, over the
   backdrop b. *)
let renderer_render r dst s ops _fxs glyphs area bounds from to_ px b =
  r.dst <- dst;
  r.rclips <- [];
  r.span_len <- 0;
  r.rarea <- irect_intersect area (irect 0 0 dst.Image.w dst.Image.h);
  if not (irect_empty r.rarea) then begin
    if from = 0 then begin
      let pr, pg, pb, pa = premul s.clear 1. in
      let d = r.dst and a = r.rarea in
      let w = a.x1 - a.x0 in
      if w > 0 then begin
        let pb8 = Char.chr (to8 pb) and pg8 = Char.chr (to8 pg)
        and pr8 = Char.chr (to8 pr) and pa8 = Char.chr (to8 pa) in
        let row0 = a.y0 * d.Image.stride + 4 * a.x0 in
        for x = 0 to w - 1 do
          let i = row0 + 4 * x in
          Bytes.set d.Image.pix i pb8;
          Bytes.set d.Image.pix (i + 1) pg8;
          Bytes.set d.Image.pix (i + 2) pr8;
          Bytes.set d.Image.pix (i + 3) pa8
        done;
        for y = a.y0 + 1 to a.y1 - 1 do
          Bytes.blit d.Image.pix row0 d.Image.pix (y * d.Image.stride + 4 * a.x0) (4 * w)
        done
      end
    end;
    update_bounds r;
    let last = min to_ (Array.length ops) in
    for i = 0 to last - 1 do
      match ops.(i) with
      | Push_clip c ->
        (* Clip operations apply wherever they fall, including before
           from: the operations after them draw within them. *)
        let radii = corners c.crect c.cradii c.ccontinuous in
        let cl = { cshape = new_shape c.crect radii; cround = has_radii radii; cspans = -1 } in
        let cspans =
          if cl.cshape.scont then begin
            (* Continuous corners take long to find the spans of, which
               every operation within the clip needs. *)
            let off = r.span_len in
            let n = 2 * irect_h r.rarea in
            ensure_span_buf r (off + n);
            Array.fill r.span_buf off n no_span;
            r.span_len <- off + n;
            off
          end
          else -1
        in
        r.rclips <- { cl with cspans } :: r.rclips;
        update_bounds r
      | Pop_clip -> (
        match r.rclips with
        | c :: rest ->
          if c.cspans >= 0 then r.span_len <- c.cspans;
          r.rclips <- rest;
          update_bounds r
        | [] -> ())
      | op ->
        if i >= from && irect_overlaps bounds.(i) r.rarea then begin
          match op with
          | Fill f -> r_fill r f
          | Shadow sh -> if sh.sinset then r_inset_shadow r sh else r_shadow r sh
          | Glyphs g -> r_glyphs r g s glyphs
          | Image im -> r_image r im
          | Hole h -> r_hole r h
          | Effect ed -> if i = from then (match px with Some p -> r_effect r ed p b | None -> ())
          | Push_clip _ | Pop_clip -> ()
        end
    done
  end

(* Operations from to to of s within area, as draw does, over the pixels
   the operations before them drew, or over the scene's clear color from
   the first; px draws operation from when it is an effect, over the
   backdrop b. *)
let draw_ops d dst s ops fxs glyphs area bounds from to_ px b workers =
  if not (from >= to_ && from > 0) then begin
    let rows = match px with Some _ -> effect_rows | None -> band_rows in
    let dy = irect_h area in
    let bands = (dy + rows - 1) / rows in
    let n =
      match workers with
      | Some w -> w
      | None -> min (Domain.recommended_domain_count ()) (irect_w area * dy / work_area)
    in
    let n = max 1 (min n bands) in
    while Array.length d.rs < n do
      d.rs <- Array.append d.rs [| new_renderer () |]
    done;
    if n <= 1 then renderer_render d.rs.(0) dst s ops fxs glyphs area bounds from to_ px b
    else
      run_team n bands (fun member part ->
        let y0 = area.y0 + part * rows in
        let band = irect area.x0 y0 area.x1 (min (y0 + rows) area.y1) in
        renderer_render d.rs.(member) dst s ops fxs glyphs band bounds from to_ px b)
  end

(* The pixels of s within area: the operations up to each effect drawn
   first, then its backdrop read (an effect reading one sees pixels the
   other bands' operations drew), then the effect and the operations up
   to the next. *)
let draw d dst s area bounds workers =
  let ops = Array.of_list s.ops in
  let fxs = Array.of_list s.effects in
  let glyphs = Array.of_list s.glyphs in
  let area = irect_intersect area (irect 0 0 dst.Image.w dst.Image.h) in
  let from = ref 0 and px = ref None and b = ref None in
  for i = 0 to Array.length ops - 1 do
    match ops.(i) with
    | Effect ed ->
      if ed.edindex >= 0 && ed.edindex < Array.length fxs && irect_overlaps bounds.(i) area then begin
        let efx = fxs.(ed.edindex) in
        let next = pixels_of d efx.ee in
        draw_ops d dst s ops fxs glyphs area bounds !from i !px !b workers;
        b := None;
        if efx.ee.ebackdrop then begin
          bd_read d.bd dst (backdrop_of ed.edrect efx.eblur dst.Image.w dst.Image.h);
          b := Some d.bd.bimg
        end;
        next.begin_effect efx ed.edrect (fit_radii ed.edrect ed.edradii);
        from := i;
        px := Some next
      end
    | _ -> ()
  done;
  draw_ops d dst s ops fxs glyphs area bounds !from (Array.length ops) !px !b workers

(* ---------- op bounds ---------- *)

(* Where each operation of s draws, within the clips around it. *)
let op_bounds s =
  let ops = Array.of_list s.ops in
  let glyphs = Array.of_list s.glyphs in
  let n = Array.length ops in
  let out = Array.make n (irect 0 0 0 0) in
  let clip = ref (irect 0 0 s.width s.height) in
  let stack = ref [] in
  for i = 0 to n - 1 do
    let b =
      match ops.(i) with
      | Fill f -> outset f.frect 1.
      | Image f -> outset f.irect2 1.
      | Effect f -> outset f.edrect 1.
      | Hole f -> outset f.hrect 1.
      | Shadow f ->
        if f.sinset then outset f.scast 1. else outset f.srect (1.5 *. f.sblur +. 1.)
      | Glyphs f ->
        let gend = min f.gend (Array.length glyphs) in
        let b = ref (irect 0 0 0 0) in
        for gi = max f.gstart 0 to gend - 1 do
          let g = glyphs.(gi) in
          b := irect_union !b (outset (rect g.gx g.gy g.gw g.gh) 1.)
        done;
        !b
      | Push_clip f ->
        (* A clip that changes changes everything it cuts. *)
        let b = outset f.crect 1. in
        stack := !clip :: !stack;
        clip := irect_intersect !clip b;
        b
      | Pop_clip -> (
        match !stack with
        | c :: rest ->
          clip := c;
          stack := rest;
          irect 0 0 0 0
        | [] -> irect 0 0 0 0)
    in
    out.(i) <- irect_intersect b !clip
  done;
  out

(* ---------- damage: what of the next scene to repaint ---------- *)

(* The state of an atlas a scene drew from. *)
type atlas_mark = { matlas : Atlas.t; mgen : int; mversion : int }

(* The rectangles of a that changed since the mark, or false when
   everything may have. *)
let mark_changes mark a =
  match mark with
  | None -> ([], false)
  | Some m ->
    if m.matlas == a then begin
      let rects, full = Atlas.changes a ~gen:m.mgen ~version:m.mversion in
      (rects, not full)
    end
    else ([], false)

let mark_set a = Some { matlas = a; mgen = a.Atlas.gen; mversion = a.Atlas.version }

(* A rectangle added to damage, merged with one it nearly touches;
   beyond 8 the rectangles become one. *)
let add_rect damage (b : irect) =
  if irect_empty b then damage
  else begin
    let found = ref false in
    let damage =
      List.map
        (fun d ->
          if (not !found) && irect_overlaps (irect (d.x0 - 8) (d.y0 - 8) (d.x1 + 8) (d.y1 + 8)) b
          then begin
            found := true;
            irect_union d b
          end
          else d)
        damage
    in
    let damage = if !found then damage else damage @ [ b ] in
    if List.length damage > 8 then
      [ List.fold_left irect_union (List.hd damage) (List.tl damage) ]
    else damage
  end

let area_sum = List.fold_left (fun n d -> n + irect_w d * irect_h d) 0

(* What one scene differs from the one before: ops, glyphs, effects,
   atlases and image versions remembered to compare the next with. *)
type damage = {
  mutable valid : bool;
  mutable dw : int;
  mutable dh : int;
  mutable dclear : color;
  mutable prev_ops : op array;
  mutable prev_glyphs : glyph array;
  mutable prev_effects : effect_op array;
  mutable bounds : irect array; (* where each op of the last scene drew *)
  mutable next : irect array; (* where each op of the new scene draws *)
  mutable versions : int array;
  mutable mask_mark : atlas_mark option;
  mutable color_mark : atlas_mark option;
  mutable damage : irect list;
  mutable is_whole : bool;
}

(* One op of the last scene and one of s: whether they draw the same,
   compared on what the CPU reads — the sRGB colors, not the wide-gamut
   ones each scene's own table holds. *)
let op_same prev_effects d ops_a i _s ops_b j glyphs_a glyphs_b fxs_b mask_rects color_rects =
  match (ops_a.(i), ops_b.(j)) with
  | Fill a, Fill b ->
    a.frect = b.frect && a.fradii = b.fradii && a.fcontinuous = b.fcontinuous
    && a.fcolor = b.fcolor && a.fpaint = b.fpaint && a.fcolor2 = b.fcolor2
    && a.fgradient = b.fgradient && a.fborder = b.fborder
    && a.fborder_color = b.fborder_color && a.fdashed = b.fdashed
    && a.fopacity = b.fopacity
  | Shadow a, Shadow b ->
    a.srect = b.srect && a.sradii = b.sradii && a.scontinuous = b.scontinuous
    && a.scolor = b.scolor && a.sblur = b.sblur && a.sinset = b.sinset
    && a.scast = b.scast && a.scast_radii = b.scast_radii
    && a.scast_continuous = b.scast_continuous && a.sopacity = b.sopacity
  | Glyphs a, Glyphs b ->
    a.gpaint = b.gpaint && a.gcolor = b.gcolor && a.gcolor2 = b.gcolor2
    && a.ggradient = b.ggradient && a.gopacity = b.gopacity
    && a.gend - a.gstart = b.gend - b.gstart
    && (let rec loop k =
          if k >= b.gend - b.gstart then true
          else begin
            let ga = glyphs_a.(a.gstart + k) and gb = glyphs_b.(b.gstart + k) in
            (* The glyphs match except perhaps the wide-gamut color they
               point at, and none of their atlas pixels changed. *)
            ga.gx = gb.gx && ga.gy = gb.gy && ga.gw = gb.gw && ga.gh = gb.gh
            && ga.gu = gb.gu && ga.gv = gb.gv && ga.guw = gb.guw && ga.gvh = gb.gvh
            && ga.gcolor = gb.gcolor && ga.gcolored = gb.gcolored
            && ga.gsubpixel = gb.gsubpixel && ga.gthin = gb.gthin
            && (let at = irect gb.gu gb.gv (gb.gu + gb.guw) (gb.gv + gb.gvh) in
                let rects = if gb.gcolored then color_rects else mask_rects in
                not (List.exists (fun c -> irect_overlaps c at) rects))
            && loop (k + 1)
          end
        in
        loop 0)
  | Image a, Image b ->
    a.irect2 = b.irect2 && a.iradii = b.iradii && a.icontinuous = b.icontinuous
    && a.iimage == b.iimage && a.isrc = b.isrc && a.igrayscale = b.igrayscale
    && a.iopacity = b.iopacity && b.iimage.iversion = d.versions.(i)
  | Push_clip a, Push_clip b ->
    a.crect = b.crect && a.cradii = b.cradii && a.ccontinuous = b.ccontinuous
  | Pop_clip, Pop_clip -> true
  | Effect a, Effect b ->
    a.edrect = b.edrect && a.edradii = b.edradii && a.edcontinuous = b.edcontinuous
    && a.edopacity = b.edopacity && a.edindex >= 0
    && a.edindex < Array.length prev_effects && b.edindex >= 0
    && b.edindex < Array.length fxs_b
    && (let ea = prev_effects.(a.edindex) and eb = fxs_b.(b.edindex) in
        ea.ee == eb.ee && ea.eblur = eb.eblur && ea.eparams = eb.eparams)
  | Hole a, Hole b ->
    a.hrect = b.hrect && a.hradii = b.hradii && a.hcontinuous = b.hcontinuous
    && a.hopacity = b.hopacity
  | _ -> false

(* The effects of s that read their backdrops, with those backdrops:
   draw reads a backdrop after drawing the operations before its effect
   within the area drawn, which must hold all of it, and then no other
   area may draw the effect. So the damage becomes rectangles apart from
   each other. *)
let add_backdrops d s ops fxs =
  if Array.length fxs <> 0 && d.damage <> [] then begin
    let changed = ref true in
    while !changed do
      changed := false;
      for i = 0 to Array.length ops - 1 do
        match ops.(i) with
        | Effect ed ->
          if ed.edindex >= 0 && ed.edindex < Array.length fxs && not (irect_empty d.next.(i)) then begin
            let fx = fxs.(ed.edindex) in
            if fx.ee.ebackdrop then begin
              let need =
                irect_union (backdrop_of ed.edrect fx.eblur s.width s.height).barea d.next.(i)
              in
              if List.exists (fun dr -> irect_overlaps dr need && not (irect_in need dr)) d.damage
              then begin
                d.damage <- add_rect d.damage need;
                changed := true
              end
            end
          end
        | _ -> ()
      done;
      (* Rectangles that overlap become one. *)
      let arr = Array.of_list d.damage in
      let n = ref (Array.length arr) in
      let i = ref 0 in
      while !i < !n do
        let j = ref (!i + 1) in
        while !j < !n do
          if irect_overlaps arr.(!i) arr.(!j) then begin
            arr.(!i) <- irect_union arr.(!i) arr.(!j);
            Array.blit arr (!j + 1) arr !j (!n - !j - 1);
            decr n;
            changed := true;
            j := !i
          end;
          incr j
        done;
        incr i
      done;
      d.damage <- List.init !n (fun k -> arr.(k))
    done
  end

(* The damage between the last scene and s, and false when s must be
   drawn whole. *)
let diff d s =
  let mask_rects, ok = mark_changes d.mask_mark s.mask_atlas in
  if not ok then false
  else begin
    let color_rects, ok = mark_changes d.color_mark s.color_atlas in
    if not ok then false
    else begin
      let ops = Array.of_list s.ops in
      let glyphs_a = d.prev_glyphs and glyphs_b = Array.of_list s.glyphs in
      let fxs_b = Array.of_list s.effects in
      let same i j =
        op_same d.prev_effects d d.prev_ops i s ops j glyphs_a glyphs_b fxs_b mask_rects color_rects
      in
      let n = Array.length d.prev_ops and m = Array.length ops in
      let pre = ref 0 in
      while !pre < n && !pre < m && same !pre !pre do
        incr pre
      done;
      let suf = ref 0 in
      while !suf < n - !pre && !suf < m - !pre && same (n - 1 - !suf) (m - 1 - !suf) do
        incr suf
      done;
      d.damage <- [];
      if n = m then
        for k = !pre to n - !suf - 1 do
          if not (same k k) then begin
            d.damage <- add_rect d.damage d.bounds.(k);
            d.damage <- add_rect d.damage d.next.(k)
          end
        done
      else begin
        for i = !pre to n - !suf - 1 do
          d.damage <- add_rect d.damage d.bounds.(i)
        done;
        for j = !pre to m - !suf - 1 do
          d.damage <- add_rect d.damage d.next.(j)
        done
      end;
      add_backdrops d s ops fxs_b;
      (* Past half the window, drawing it whole costs about the same. *)
      area_sum d.damage * 2 < s.width * s.height
    end
  end

(* Keep what the next scene is compared with. *)
let remember d s =
  d.valid <- true;
  d.dw <- s.width;
  d.dh <- s.height;
  d.dclear <- s.clear;
  d.prev_ops <- Array.of_list s.ops;
  d.prev_glyphs <- Array.of_list s.glyphs;
  d.prev_effects <-
    Array.map (fun e -> { e with eparams = Array.copy e.eparams }) (Array.of_list s.effects);
  let t = d.bounds in
  d.bounds <- d.next;
  d.next <- t;
  d.versions <-
    Array.map (function Image im -> im.iimage.iversion | _ -> 0) d.prev_ops;
  d.mask_mark <- mark_set s.mask_atlas;
  d.color_mark <- mark_set s.color_atlas

module Damage = struct
  type t = damage

  let create () = {
    valid = false; dw = 0; dh = 0; dclear = color 0 0 0 0;
    prev_ops = [||]; prev_glyphs = [||]; prev_effects = [||];
    bounds = [||]; next = [||]; versions = [||];
    mask_mark = None; color_mark = None; damage = []; is_whole = true;
  }

  let invalidate d = d.valid <- false
  let bounds d = d.bounds
  let whole d = d.is_whole
  let rects d = d.damage

  (* s against the last scene: the rectangles of it that changed, a
     full-size one when it must be drawn whole. *)
  let update d s =
    d.next <- op_bounds s;
    let whole =
      (not d.valid) || s.width <> d.dw || s.height <> d.dh || s.clear <> d.dclear
      || not (diff d s)
    in
    d.is_whole <- whole;
    if whole then d.damage <- [ irect 0 0 s.width s.height ];
    remember d s;
    d.damage
end

(* ---------- the public entry points ---------- *)

let draw_into ?workers drawer img s area bounds = draw drawer img s area bounds workers

(* The whole scene, into a fresh image. *)
let render ?workers ~scene () =
  let img = Image.create ~w:scene.width ~h:scene.height in
  let d = new_drawer () in
  let bounds = op_bounds scene in
  draw d img scene (irect 0 0 img.w img.h) bounds workers;
  img

let render_into ?workers ~image ~scene ?(area = irect 0 0 image.Image.w image.Image.h)
    ?(bounds = op_bounds scene) () =
  let d = new_drawer () in
  draw d image scene area bounds workers

(* The damage renderer: successive scenes into one Image, redrawing only
   where a scene differs from the one before. *)
module Renderer = struct
  type t = { image : Image.t; drawer : drawer; dmg : Damage.t }

  let create () = { image = Image.create ~w:0 ~h:0; drawer = new_drawer (); dmg = Damage.create () }
  let image t = t.image
  let invalidate t = Damage.invalidate t.dmg
  let whole t = Damage.whole t.dmg
  let release t =
    t.image.pix <- Bytes.make 0 '\000';
    t.image.w <- 0;
    t.image.h <- 0;
    t.image.stride <- 0;
    invalidate t

  (* Draw s, and return the rectangles of the image it changed. *)
  let render ?workers t s =
    let damage = Damage.update t.dmg s in
    if t.image.w <> s.width || t.image.h <> s.height then Image.resize t.image ~w:s.width ~h:s.height;
    List.iter (fun dr -> draw_into ?workers t.drawer t.image s dr (Damage.bounds t.dmg)) damage;
    damage
end
