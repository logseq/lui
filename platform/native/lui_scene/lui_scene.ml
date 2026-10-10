(* Display list: the IR the paint pass produces and the renderers draw.
   The CPU and GPU renderers evaluate the same list and must agree
   pixel-for-pixel, so the geometry and coverage math here is shared.
   Geometry is in device pixels, origin top-left. *)

type color = { r : int; g : int; b : int; a : int } (* straight sRGB, 0-255 *)

let color r g b a = { r; g; b; a }

let premul c opacity =
  let a = float c.a /. 255. *. opacity in
  (float c.r /. 255. *. a, float c.g /. 255. *. a, float c.b /. 255. *. a, a)

type rect = { x : float; y : float; w : float; h : float }

let rect x y w h = { x; y; w; h }
let rect_empty r = r.w <= 0. || r.h <= 0.
let rect_intersect r o =
  let x0 = max r.x o.x and y0 = max r.y o.y in
  let x1 = min (r.x +. r.w) (o.x +. o.w) and y1 = min (r.y +. r.h) (o.y +. o.h) in
  if x1 <= x0 || y1 <= y0 then rect x0 y0 0. 0. else rect x0 y0 (x1 -. x0) (y1 -. y0)

let rect_contains r px py = px >= r.x && py >= r.y && px < r.x +. r.w && py < r.y +. r.h

(* Integer rectangle, used by atlas change tracking and backdrops. *)
type irect = { x0 : int; y0 : int; x1 : int; y1 : int }

let irect x0 y0 x1 y1 = { x0; y0; x1; y1 }
let irect_empty r = r.x1 <= r.x0 || r.y1 <= r.y0
let irect_intersect r o =
  irect (max r.x0 o.x0) (max r.y0 o.y0) (min r.x1 o.x1) (min r.y1 o.y1)
let irect_union r o =
  if irect_empty r then o else if irect_empty o then r
  else irect (min r.x0 o.x0) (min r.y0 o.y0) (max r.x1 o.x1) (max r.y1 o.y1)
let irect_w r = r.x1 - r.x0
let irect_h r = r.y1 - r.y0

type paint = Solid | Linear | Oklab | Stripes

let uniform_border w = (w, w, w, w)
let has_border (t, r, b, l) = t > 0. || r > 0. || b > 0. || l > 0.

(* FitRadii: scale corner radii so adjacent ones fit along each side. *)
let fit_radii r (tl, tr, br, bl) =
  let f = ref 1. in
  let clamp a b size =
    let s = a +. b in
    if s > size && s > 0. then f := min !f (size /. s)
  in
  clamp tl tr r.w; clamp bl br r.w; clamp tl bl r.h; clamp tr br r.h;
  let s = !f in
  (max (tl *. s) 0., max (tr *. s) 0., max (br *. s) 0., max (bl *. s) 0.)

(* Corners: fitted radii, negated for continuous corners. *)
let corners r radii continuous =
  let (tl, tr, br, bl) = fit_radii r radii in
  if continuous then (~-. tl, ~-. tr, ~-. br, ~-. bl) else (tl, tr, br, bl)

(* InnerRadii: inner edge of a border of widths w inside the rounded rect. *)
let inner_radii r radii (wt, wr, wb, wl) =
  let inner =
    { x = r.x +. wl; y = r.y +. wt; w = r.w -. wr -. wl; h = r.h -. wt -. wb }
  in
  let (rtl, rtr, rbr, rbl) = radii in
  let continuous = rtl < 0. || rtr < 0. || rbr < 0. || rbl < 0. in
  let abs_r = Float.abs in
  let out_tl = max (abs_r rtl -. max wt wl) 0. in
  let out_tr = max (abs_r rtr -. max wt wr) 0. in
  let out_br = max (abs_r rbr -. max wb wr) 0. in
  let out_bl = max (abs_r rbl -. max wb wl) 0. in
  (inner, corners inner (out_tl, out_tr, out_br, out_bl) continuous)

(* Glyph: a bitmap copied from an atlas into a frame. *)
type glyph = {
  gx : float; gy : float; gw : float; gh : float;
  gu : int; gv : int; guw : int; gvh : int;
  gcolor : color;
  gwide : int; (* 1 + index into scene wide colors, 0 = none *)
  gcolored : bool; (* ColorAtlas *)
  gsubpixel : bool; (* ColorAtlas, per-channel coverage *)
  gthin : bool;
}

(* Colors outside the sRGB gamut, kept separately for wide-gamut
   render targets. *)
type wide_colors = {
  wcolor : float * float * float * float;
  wcolor2 : float * float * float * float;
  wborder : float * float * float * float;
  wset : int; (* bits: 1 color, 2 color2, 4 border *)
}

let wide_color = 1 and wide_color2 = 2 and wide_border = 4

(* Effects: custom drawing with a GLSL shader plus a CPU twin that must
   produce the same pixels. *)
type effect_pixels = {
  begin_effect : effect_op -> rect -> float * float * float * float -> unit;
  color_at : float -> float -> backdrop_image option -> float * float * float;
}

and fx = {
  ename : string;
  ebackdrop : bool;
  eglsl : string;
  epixels : unit -> effect_pixels;
}

and effect_op = {
  ee : fx;
  eblur : float;
  eparams : (float * float * float * float) array; (* 5 params *)
}

and backdrop = { barea : irect; bdown : int; bsigma : float; bradius : int }

and backdrop_image = {
  bd : backdrop;
  bw : int; bh : int;
  bpix : float array; (* premultiplied RGBA, 4 per texel *)
}

let backdrop_size b = ((irect_w b.barea + b.bdown - 1) / b.bdown, (irect_h b.barea + b.bdown - 1) / b.bdown)

let blur_weight i sigma =
  if sigma <= 0. then 1. else
  let x = float i in
  exp (~-. (x *. x) /. (2. *. sigma *. sigma))

let backdrop_of r blur w h =
  let blur = max blur 0. in
  let down = ref 1 in
  while !down < 8 && blur /. float (2 * !down) >= 2. do down := !down * 2 done;
  let d = !down in
  let sigma =
    if blur = 0. then 0.
    else sqrt (max (blur *. blur -. float (d * d) /. 12.) 0.) /. float d
  in
  let radius = int_of_float (ceil (3. *. sigma)) in
  let reach = float (radius * d + d) in
  let area =
    irect
      (int_of_float (floor (r.x -. reach)))
      (int_of_float (floor (r.y -. reach)))
      (int_of_float (ceil (r.x +. r.w +. reach)))
      (int_of_float (ceil (r.y +. r.h +. reach)))
  in
  { barea = irect_intersect area (irect 0 0 w h); bdown = d; bsigma = sigma; bradius = radius }

(* Bilinear sample of a CPU-computed backdrop at frame pixel (x, y). *)
let backdrop_sample b x y =
  let k = float b.bd.bdown in
  let u = (x -. float b.bd.barea.x0) /. k -. 0.5 in
  let v = (y -. float b.bd.barea.y0) /. k -. 0.5 in
  let fu = floor u and fv = floor v in
  let tx = u -. fu and ty = v -. fv in
  let ix f = min (max (int_of_float f) 0) (b.bw - 1) in
  let iy f = min (max (int_of_float f) 0) (b.bh - 1) in
  let x0 = ix fu and x1 = ix (fu +. 1.) in
  let y0 = iy fv and y1 = iy (fv +. 1.) in
  let p i j c = b.bpix.(4 * (j * b.bw + i) + c) in
  let c ch =
    let top = p x0 y0 ch *. (1. -. tx) +. p x1 y0 ch *. tx in
    let bot = p x0 y1 ch *. (1. -. tx) +. p x1 y1 ch *. tx in
    top *. (1. -. ty) +. bot *. ty
  in
  (c 0, c 1, c 2)

(* SDRoundRect: signed distance to a fitted rounded rect, negative inside. *)
let sd_round_rect r (rtl, rtr, rbr, rbl) px py =
  let hx = r.w /. 2. and hy = r.h /. 2. in
  let qx = px -. r.x -. hx and qy = py -. r.y -. hy in
  let rad =
    if qx < 0. && qy < 0. then rtl
    else if qx >= 0. && qy < 0. then rtr
    else if qx >= 0. then rbr
    else rbl
  in
  let ax = Float.abs qx -. hx +. rad and ay = Float.abs qy -. hy +. rad in
  let mx = max ax 0. and my = max ay 0. in
  sqrt (mx *. mx +. my *. my) +. min (max ax ay) 0. -. rad

(* Atlas: shelf packing of small bitmaps (glyph masks / color bitmaps).
   Lasting bitmaps fill shelves from the top; transient ones from the
   bottom and are freed by reset_transient, so they never crowd the
   lasting ones out. Renderers read the change log to upload only the
   rectangles that changed. *)
module Atlas = struct
  type shelf = { mutable sy : int; sh : int; mutable sx : int }

  type t = {
    bpp : int;
    mutable w : int;
    mutable h : int;
    mutable pix : Bytes.t;
    mutable gen : int;
    mutable version : int;
    mutable log : (int * irect) list;
    mutable shelves : shelf list;
    mutable transient : shelf list;
    mutable bottom : int;
    mutable top : int;
  }

  let max_size = 4096
  let log_limit = 512

  let create ~bpp ~w ~h =
    { bpp; w; h; pix = Bytes.make (w * h * bpp) '\000';
      gen = 1; version = 0; log = []; shelves = []; transient = [];
      bottom = 0; top = h }

  let reset_transient a = a.transient <- []; a.top <- a.h

  let changed_all a = a.gen <- a.gen + 1; a.version <- a.version + 1; a.log <- []

  (* changes since [version] of generation [gen]: (rects, full) *)
  let changes a ~gen ~version =
    if gen <> a.gen then ([], true)
    else if version = a.version then ([], false)
    else
      match a.log with
      | [] -> ([], true)
      | (v0, _) :: _ when v0 > version + 1 -> ([], true)
      | _ ->
        let rects, union =
          List.fold_left
            (fun (rs, u) (v, r) ->
              if v > version then (r :: rs, irect_union u r) else (rs, u))
            ([], irect 0 0 0 0) a.log
        in
        if List.length rects > 32 then ([union], false) else (rects, false)

  (* Allocate a lasting w×h rect; false when the atlas is full. *)
  let alloc a ~up w h =
    let pw = w + 1 and ph = h + 1 in
    if pw > a.w || ph > a.h then None
    else
      let shelves = if up then a.transient else a.shelves in
      let best =
        List.fold_left
          (fun (best, i) s ->
            (if s.sh >= ph && s.sh <= ph + ph / 4 + 2 && a.w - s.sx >= pw
                && (best < 0 || s.sh < (List.nth shelves best).sh)
             then i else best), i + 1)
          (-1, 0) shelves
        |> fst
      in
      let shelves =
        if best < 0 then (
          if a.bottom + ph > a.top then None
          else
            let step = max 4 (ph / 8) in
            let sh = min (((ph + step - 1) / step) * step) (a.top - a.bottom) in
            let y = if up then (a.top <- a.top - sh; a.top) else a.bottom in
            if not up then a.bottom <- a.bottom + sh;
            let s = { sy = y; sh; sx = 0 } in
            if up then a.transient <- shelves @ [ s ] else a.shelves <- shelves @ [ s ];
            Some s)
        else Some (List.nth shelves best)
      in
      match shelves with
      | None -> None
      | Some s -> let x = s.sx in s.sx <- s.sx + pw; Some (x, s.sy)

  let alloc_last a w h = alloc a ~up:false w h
  let alloc_transient a w h = alloc a ~up:true w h

  (* Copy a w×h bitmap (rows of [stride] bytes) to (x,y) + clear padding. *)
  let put a ~x ~y ~w ~h ~src ~stride =
    let bpp = a.bpp in
    let row = w * bpp in
    for j = 0 to h - 1 do
      let i = ((y + j) * a.w + x) * bpp in
      Bytes.blit src (j * stride) a.pix i row;
      if x + w < a.w then Bytes.fill a.pix (i + row) bpp '\000'
    done;
    let r = irect x y (min (x + w + 1) a.w) (min (y + h + 1) a.h) in
    if y + h < a.h then (
      let i = ((y + h) * a.w + x) * bpp in
      Bytes.fill a.pix i (irect_w r * bpp) '\000');
    a.version <- a.version + 1;
    a.log <- (a.version, r) :: a.log;
    if List.length a.log > log_limit then
      a.log <- List.filteri (fun i _ -> i < log_limit / 2) a.log

  let grow a =
    if a.w >= max_size && a.h >= max_size then false
    else
      let w = min (a.w * 2) max_size and h = min (a.h * 2) max_size in
      let pix = Bytes.make (w * h * a.bpp) '\000' in
      for j = 0 to a.bottom - 1 do
        Bytes.blit a.pix (j * a.w * a.bpp) pix (j * w * a.bpp) (a.w * a.bpp)
      done;
      a.w <- w; a.h <- h; a.pix <- pix;
      reset_transient a; changed_all a; true

  (* Repack lasting rects, tallest first; returns new positions. *)
  let repack a rects =
    let order = Array.of_list (List.mapi (fun i _ -> i) rects) in
    Array.sort
      (fun i j ->
        let ri = List.nth rects i and rj = List.nth rects j in
        let c = compare (irect_h rj) (irect_h ri) in
        if c <> 0 then c else compare (irect_w rj) (irect_w ri))
      order;
    let plan = { a with pix = a.pix; shelves = []; transient = []; bottom = 0; top = a.h } in
    let pos = Array.map (fun i ->
      let r = List.nth rects i in
      alloc_last plan (irect_w r) (irect_h r)) order
    in
    if Array.exists Option.is_none pos then None
    else
      let saved =
        List.map
          (fun r ->
            let row = irect_w r * a.bpp in
            let b = Bytes.make (row * irect_h r) '\000' in
            for j = 0 to irect_h r - 1 do
              Bytes.blit a.pix (((r.y0 + j) * a.w + r.x0) * a.bpp) b (j * row) row
            done;
            b)
          rects
      in
      Bytes.fill a.pix 0 (Bytes.length a.pix) '\000';
      List.iteri
        (fun i r ->
          match pos.(i) with
          | None -> ()
          | Some (px, py) ->
            let row = irect_w r * a.bpp and src = List.nth saved i in
            for j = 0 to irect_h r - 1 do
              Bytes.blit src (j * row) a.pix (((py + j) * a.w + px) * a.bpp) row
            done)
        rects;
      a.shelves <- plan.shelves; a.bottom <- plan.bottom;
      reset_transient a; changed_all a;
      Some (Array.to_list (Array.map Option.get pos))

  let reset a =
    Bytes.fill a.pix 0 (Bytes.length a.pix) '\000';
    a.shelves <- []; a.bottom <- 0;
    reset_transient a; changed_all a
end

(* TextParams: coverage correction for mask and subpixel glyphs. *)
type text_params = {
  gamma_ratios : float * float * float * float;
  contrast : float;
  subpixel_contrast : float;
}

let default_text_params =
  { gamma_ratios = (0., 0., 0., 0.); contrast = 0.; subpixel_contrast = 0. }

(* Alpha correction ratios for gamma in 1.0..2.2. *)
let gamma_ratios gamma =
  let table =
    [| (0., 0., 0., 0.);
       (0.0166, -0.0807, 0.2227, -0.0751);
       (0.0350, -0.1760, 0.4325, -0.1370);
       (0.0543, -0.2821, 0.6302, -0.1876);
       (0.0739, -0.3963, 0.8167, -0.2287);
       (0.0933, -0.5161, 0.9926, -0.2616);
       (0.1121, -0.6395, 1.1588, -0.2877);
       (0.1300, -0.7649, 1.3159, -0.3080);
       (0.1469, -0.8911, 1.4644, -0.3234);
       (0.1627, -1.0170, 1.6051, -0.3347);
       (0.1773, -1.1420, 1.7385, -0.3476);
       (0.1908, -1.2652, 1.8650, -0.3476);
       (0.2031, -1.3864, 1.9851, -0.3501) |]
  in
  let i = min (max (int_of_float (gamma *. 10. +. 0.5)) 10) 22 - 10 in
  let norm13 = 0x10000. /. (255. *. 255. *. 4.) in
  let norm24 = 0x100. /. 255. *. 4. in
  let (r0, r1, r2, r3) = table.(i) in
  (norm13 *. r0 /. 4., norm24 *. r1 /. 4., norm13 *. r2 /. 4., norm24 *. r3 /. 4.)

let thin_boost = 0.5

(* Coverage correction for a mask glyph of straight color c. *)
let text_coverage a (cr, cg, cb) ~contrast ~boost (g0, g1, g2, g3) =
  let k = contrast *. min (max (3. -. 4. *. (0.30 *. cr +. 0.59 *. cg +. 0.11 *. cb)) 0.) 1. +. boost in
  let a = a *. (k +. 1.) /. (a *. k +. 1.) in
  let f = 0.25 *. cr +. 0.5 *. cg +. 0.25 *. cb in
  min (max (a +. a *. (1. -. a) *. ((g0 *. f +. g1) *. a +. (g2 *. f +. g3))) 0.) 1.

let subpixel_coverage (ar, ag, ab) (cr, cg, cb) ~contrast ~boost g =
  let k = contrast *. min (max (3. -. 4. *. (0.30 *. cr +. 0.59 *. cg +. 0.11 *. cb)) 0.) 1. +. boost in
  let adj a c =
    let v = a *. (k +. 1.) /. (a *. k +. 1.) in
    let (g0, g1, g2, g3) = g in
    min (max (v +. v *. (1. -. v) *. ((g0 *. c +. g1) *. v +. (g2 *. c +. g3))) 0.) 1.
  in
  (adj ar cr, adj ag cg, adj ab cb)

(* Image: a bitmap a scene draws; renderers keep one texture per
   image and re-upload it when iversion changes. *)
type image = {
  iid : int;
  mutable iversion : int;
  iw : int; ih : int;
  ipix : Bytes.t; (* premultiplied RGBA, 4*W per row *)
}

let last_image_id = ref 0
let new_image ~w ~h pix =
  incr last_image_id;
  { iid = !last_image_id; iversion = 1; iw = w; ih = h; ipix = pix }
let image_changed i = i.iversion <- i.iversion + 1

(* Ops — the display list, in paint order. *)
type op =
  | Fill of fill_op
  | Shadow of shadow_op
  | Glyphs of glyphs_op
  | Image of image_op
  | Push_clip of clip_op
  | Pop_clip
  | Effect of effect_draw
  | Hole of hole_op

and fill_op = {
  frect : rect;
  fradii : float * float * float * float;
  fcontinuous : bool;
  fcolor : color;
  fpaint : paint;
  fcolor2 : color;
  fgradient : float * float * float * float;
  fborder : float * float * float * float;
  fborder_color : color;
  fdashed : bool;
  fwide : int;
  fopacity : float;
}

and shadow_op = {
  srect : rect;
  sradii : float * float * float * float;
  scontinuous : bool;
  scolor : color;
  sblur : float;
  sinset : bool;
  scast : rect;
  scast_radii : float * float * float * float;
  scast_continuous : bool;
  swide : int;
  sopacity : float;
}

and glyphs_op = {
  gstart : int; gend : int;
  gpaint : paint;
  gcolor : color;
  gcolor2 : color;
  ggradient : float * float * float * float;
  gwide2 : int;
  gopacity : float;
}

and image_op = {
  irect2 : rect;
  iradii : float * float * float * float;
  icontinuous : bool;
  iimage : image;
  isrc : rect;
  igrayscale : bool;
  iopacity : float;
}

and clip_op = {
  crect : rect;
  cradii : float * float * float * float;
  ccontinuous : bool;
}

and effect_draw = { edrect : rect; edradii : float * float * float * float; edcontinuous : bool; edindex : int; edopacity : float }

and hole_op = { hrect : rect; hradii : float * float * float * float; hcontinuous : bool; hopacity : float }

(* Scene: one frame's display list. *)
type t = {
  mutable width : int;
  mutable height : int;
  mutable scale : float;
  mutable clear : color;
  mutable ops : op list; (* reversed paint order at build; reversed at seal *)
  mutable glyphs : glyph list;
  mutable effects : effect_op list;
  mutable wide : wide_colors list;
  mutable text : text_params;
  mask_atlas : Atlas.t;
  color_atlas : Atlas.t;
}

let create ~mask_atlas ~color_atlas =
  { width = 0; height = 0; scale = 1.; clear = color 0 0 0 0;
    ops = []; glyphs = []; effects = []; wide = [];
    text = default_text_params; mask_atlas; color_atlas }

let reset s ~width ~height ~scale ~clear =
  s.width <- width; s.height <- height; s.scale <- scale; s.clear <- clear;
  s.ops <- []; s.glyphs <- []; s.effects <- []; s.wide <- []

let add_wide s wc = s.wide <- s.wide @ [ wc ]; List.length s.wide
