(* Scene to instance compiler: one instanced quad per op, in batches
   sharing a scissor rectangle and an image, for the shader in
   shader.glsl (exposed as [shader_source]).

   Pure OCaml, no GL calls: a renderer consumes [build]'s batches and
   uploads [to_float32_array]'s layout to the instance buffer.

   An effect draws with a pipeline of its own in a batch of its own. One
   reading its backdrop has [backdrop] set on its batch: the renderer
   reads the backdrop's area of what it drew so far, averages it over
   squares (the down pass), blurs along rows then columns (the blur
   passes), keeping 8 bits a channel, and binds it as the backdrop
   texture — the same image the CPU evaluator computes.

   The shader writes a second color for blending, the source's alpha for
   each channel: the alpha of the color for everything but subpixel
   glyphs, whose subpixels cover each channel by its own. Renderers
   blend with dual-source blending: the destination times one minus the
   second color, plus the first.

   A hole is an opaque fill in a batch of its own, which renderers blend
   with none of the source: the destination times one minus the second
   color, its coverage, which leaves it transparent. *)

open Lui_scene

(* A vec4 in the instance layout. *)
type f4 = float * float * float * float

(* Instance: the data of one quad, in device pixels, as the shader reads
   it: eleven float4s.

   Rect is x, y, width, height; Radii the corners' radii (top-left,
   top-right, bottom-right, bottom-left), negative for continuous
   corners, or a glyph's gamma ratios; Inner those of a border's inner
   edge, of the box casting a shadow, or a glyph's contrast and thin
   boost in [inner0] and [inner1].

   Color and Color2 (a gradient's end) and Border are straight RGBA.

   Grad holds a gradient's start and end points, or the stripes' unit
   vector across them, width and period; UV the texture rectangle,
   normalized, a fill's border widths (top, right, bottom, left), or
   the box casting a shadow, which shows only outside it (none when
   empty).

   An effect has its parameters (effect_op.eparams) in Inner, Color,
   Color2, Border and Grad, and in UV where its backdrop's area starts
   in the frame and its size in texels.

   Clip and Clip_radii are the innermost clip; Clip2 and Clip3 the two
   containing it, the everything rectangle where the stack is
   shallower; the shader multiplies their coverages. Deeper clips cut
   by their scissor bounds only.

   Params is the kind (0 fill, 1 shadow, 2 mask glyph, 3 color glyph,
   4 image, 5 subpixel glyph, 6 effect); 1 for a dashed border, a
   grayscale image or an inner shadow, whose box is in Rect and Radii
   and the hole it leaves in UV and Inner (none when empty); the
   shadow's sigma (0 for none), the paint code or the size of the
   squares an effect's backdrop averages; and the opacity. *)
type instance = {
  rect : f4;
  radii : f4;
  inner : f4;
  color : f4;
  color2 : f4;
  border : f4;
  grad : f4;
  uv : f4;
  clip : f4;
  clip_radii : f4;
  params : f4;
  clip2 : f4;
  clip2_radii : f4;
  clip3 : f4;
  clip3_radii : f4;
}

(* The clip fields of an instance stamped later: the everything
   rectangle, zero radii, which covers every pixel. *)
let no_clip = (-1e6, -1e6, 2e6, 2e6)

let no_clip_radii = (0., 0., 0., 0.)

(* Instance kinds, selected by [params0]. *)
let kind_fill = 0.
let kind_shadow = 1.
let kind_mask_glyph = 2.
let kind_color_glyph = 3.
let kind_image = 4.
let kind_subpixel_glyph = 5.
let kind_effect = 6.

(* Floats in the packed layout of one instance. *)
let instance_floats = 60

(* Scissor: a scissor rectangle in device pixels. *)
type scissor = { left : int; top : int; right : int; bottom : int }

let scissor_empty s = s.right <= s.left || s.bottom <= s.top

(* Batch: a run of instances that draw with the same scissor rectangle
   and image.

   [fx] is the effect of the batch's one instance, drawn with a
   pipeline of its own. [backdrop] is the backdrop the renderer
   computes (down pass + blur passes) and binds before drawing the
   batch, when the effect reads one.

   [hole] marks instances that make their shapes transparent: renderers
   blend them with a source factor of zero. *)
type batch = {
  scissor : scissor;
  image : image option;
  fx : fx option;
  backdrop : backdrop option;
  hole : bool;
  instances : instance list;
}

(* Pass: what a pass computing a backdrop reads: down reads the area
   from origin to limit, frame pixels, at their place less shift in its
   source, and averages squares of down pixels a side; blur reads
   texels up to limit, radius of them each way along dir, weighted by a
   Gaussian of standard deviation sigma. pad keeps the layout a whole
   float4. *)
type pass = {
  origin : int * int;
  limit : int * int;
  shift : int * int;
  dir : int * int;
  down : int;
  radius : int;
  sigma : float;
  pad : float;
}

(* The pass averaging the squares of b's area, whose frame pixel
   (x, y) is at (x, y) less shift in the texture it reads. *)
let down_pass (b : backdrop) ~shift =
  { origin = (b.barea.x0, b.barea.y0);
    limit = (b.barea.x1 - 1, b.barea.y1 - 1);
    shift; dir = (0, 0); down = b.bdown; radius = 0; sigma = 0.; pad = 0. }

(* The pass blurring b's texels along rows (dir 1, 0) or columns
   (0, 1). *)
let blur_pass (b : backdrop) dir =
  let w, h = backdrop_size b in
  { origin = (0, 0); limit = (w - 1, h - 1); shift = (0, 0); dir;
    down = 0; radius = b.bradius; sigma = b.bsigma; pad = 0. }

(* How large the textures of the backdrops of batches must be, in
   texels: as the largest. *)
let backdrop_size batches =
  List.fold_left
    (fun (w, h) b ->
      match b.backdrop with
      | None -> (w, h)
      | Some bk ->
        let bw, bh = Lui_scene.backdrop_size bk in
        (max w bw, max h bh))
    (0, 0) batches

let f4_of_rect (r : rect) : f4 = (r.x, r.y, r.w, r.h)

let straight (c : color) : f4 =
  (float c.r /. 255., float c.g /. 255., float c.b /. 255., float c.a /. 255.)

let opacity o = if o = 0. then 1. else o

let paint_code = function Solid -> 0. | Linear -> 1. | Oklab -> 2. | Stripes -> 3.

(* Round half away from zero, for glyph origins. *)
let round f = if f >= 0. then Float.floor (f +. 0.5) else Float.ceil (f -. 0.5)

let shadow_sigma blur =
  let sigma = blur /. 2. in
  if sigma < 0.5 then 0. else sigma

(* One clip of the clip stack: the three innermost clips' rectangles
   and fitted radii go to the shader's clip fields; the intersection
   of all the stack's clip rectangles, bounds, becomes the scissor
   rectangle. *)
type clip_frame = {
  cf_rect : rect;
  cf_radii : f4;
  cf_bounds : rect;
  cf_scissor : scissor;
}

let scissor_of_bounds (b : rect) : scissor =
  if rect_empty b then { left = 0; top = 0; right = 0; bottom = 0 }
  else
    { left = int_of_float (Float.floor b.x);
      top = int_of_float (Float.floor b.y);
      right = int_of_float (Float.ceil (b.x +. b.w));
      bottom = int_of_float (Float.ceil (b.y +. b.h)) }

(* A batch under construction; instances accumulate in reverse. *)
type work_batch = {
  w_scissor : scissor;
  mutable w_image : image option;
  w_fx : fx option;
  w_backdrop : backdrop option;
  w_hole : bool;
  mutable w_insts : instance list;
}

let build ?(wide = false) (s : t) : batch list =
  let glyphs = Array.of_list s.glyphs in
  let effects = Array.of_list s.effects in
  let wides = Array.of_list s.wide in
  let everything = { x = -1e6; y = -1e6; w = 2e6; h = 2e6 } in
  let stack =
    ref
      [ { cf_rect = everything;
          cf_radii = (0., 0., 0., 0.);
          cf_bounds = { x = 0.; y = 0.; w = float s.width; h = float s.height };
          cf_scissor = { left = 0; top = 0; right = s.width; bottom = s.height } } ]
  in
  let open_batch = ref None and done_ = ref [] in
  let close () =
    (match !open_batch with
     | None -> ()
     | Some wb ->
       done_ :=
         { scissor = wb.w_scissor; image = wb.w_image; fx = wb.w_fx;
           backdrop = wb.w_backdrop; hole = wb.w_hole;
           instances = List.rev wb.w_insts }
         :: !done_);
    open_batch := None
  in
  (* Start a fresh batch; the current one, if any, is sealed first. *)
  let start wb = close (); open_batch := Some wb; wb in
  let top () = List.hd !stack in
  let wide_of i =
    if wide && i > 0 && i <= Array.length wides then Some wides.(i - 1) else None
  in
  let wide_col w bit c =
    match w with
    | Some wc when wc.wset land bit <> 0 ->
      if bit = Lui_scene.wide_color then wc.wcolor
      else if bit = Lui_scene.wide_color2 then wc.wcolor2
      else wc.wborder
    | _ -> straight c
  in
  (* with_clip stamps an instance with the innermost three clips of
     the stack: the shader multiplies their coverages, as the CPU
     renderer multiplies all of its clips'; deeper clips, when any,
     cut by their scissor bounds only. *)
  let with_clip inst =
    let of_frame cf = (f4_of_rect cf.cf_rect, cf.cf_radii) in
    let pad = (f4_of_rect everything, (0., 0., 0., 0.)) in
    let rec take n = function
      | cf :: tl when n > 0 -> of_frame cf :: take (n - 1) tl
      | _ -> []
    in
    match take 3 !stack @ [ pad; pad; pad ] with
    | (c1, r1) :: (c2, r2) :: (c3, r3) :: _ ->
      { inst with clip = c1; clip_radii = r1; clip2 = c2;
                  clip2_radii = r2; clip3 = c3; clip3_radii = r3 }
    | _ -> assert false
  in
  (* add appends an instance within the current clip, starting a batch
     when the scissor rectangle or the image changes, or after an
     effect's or a hole batch. *)
  let add inst img =
    let cur = top () in
    if not (scissor_empty cur.cf_scissor) then (
      let inst = with_clip inst in
      let wb =
        match !open_batch with
        | None -> start { w_scissor = cur.cf_scissor; w_image = img;
                          w_fx = None; w_backdrop = None; w_hole = false;
                          w_insts = [] }
        | Some wb ->
          let same_image =
            match img, wb.w_image with
            | Some a, Some b -> a.iid = b.iid
            | _ -> true
          in
          if wb.w_scissor = cur.cf_scissor && wb.w_fx = None
             && not wb.w_hole && same_image
          then (
            (match img with Some _ -> wb.w_image <- img | None -> ());
            wb)
          else start { w_scissor = cur.cf_scissor; w_image = img;
                       w_fx = None; w_backdrop = None; w_hole = false;
                       w_insts = [] }
      in
      wb.w_insts <- inst :: wb.w_insts)
  in
  (* add_effect appends an effect within the current clip, in a batch
     of its own, which reads its backdrop first when it reads one. *)
  let add_effect ed eff =
    let cur = top () in
    if not (scissor_empty cur.cf_scissor) then
      (* A backdrop-reading effect draws nothing where its backdrop is
         empty. *)
      let bk =
        if eff.ee.ebackdrop then
          let b = backdrop_of ed.edrect eff.eblur s.width s.height in
          if irect_empty b.barea then None else Some b
        else None
      in
      match eff.ee.ebackdrop && bk = None with
      | true -> ()
      | false ->
        let p = eff.eparams in
        let uv, down, backdrop =
          match bk with
          | Some b ->
            let tw, th = Lui_scene.backdrop_size b in
            ( (float b.barea.x0, float b.barea.y0, float tw, float th),
              float b.bdown, Some b )
          | None -> ((0., 0., 0., 0.), 1., None)
        in
        let inst =
          { rect = f4_of_rect ed.edrect;
            radii = corners ed.edrect ed.edradii ed.edcontinuous;
            inner = p.(0); color = p.(1); color2 = p.(2); border = p.(3);
            grad = p.(4); uv;
            clip = no_clip; clip_radii = no_clip_radii;
            params = (kind_effect, 0., down, opacity ed.edopacity);
            clip2 = no_clip; clip2_radii = no_clip_radii;
            clip3 = no_clip; clip3_radii = no_clip_radii }
        in
        let inst = with_clip inst in
        ignore
          (start { w_scissor = cur.cf_scissor; w_image = None;
                   w_fx = Some eff.ee; w_backdrop = backdrop;
                   w_hole = false; w_insts = [ inst ] })
  in
  (* add_hole appends a hole within the current clip, in a batch of
     holes: an opaque fill whose coverage the renderers take away. *)
  let add_hole ho =
    let cur = top () in
    if not (scissor_empty cur.cf_scissor) then
      let inst =
        with_clip
          { rect = f4_of_rect ho.hrect;
            radii = corners ho.hrect ho.hradii ho.hcontinuous;
            inner = (0., 0., 0., 0.); color = (0., 0., 0., 1.);
            color2 = (0., 0., 0., 0.); border = (0., 0., 0., 0.);
            grad = (0., 0., 0., 0.); uv = (0., 0., 0., 0.);
            clip = no_clip; clip_radii = no_clip_radii;
            params = (kind_fill, 0., paint_code Solid, opacity ho.hopacity);
            clip2 = no_clip; clip2_radii = no_clip_radii;
            clip3 = no_clip; clip3_radii = no_clip_radii }
      in
      let wb =
        match !open_batch with
        | Some wb when wb.w_hole && wb.w_scissor = cur.cf_scissor -> wb
        | _ ->
          start { w_scissor = cur.cf_scissor; w_image = None; w_fx = None;
                  w_backdrop = None; w_hole = true; w_insts = [] }
      in
      wb.w_insts <- inst :: wb.w_insts
  in
  List.iter
    (fun op ->
      match op with
      | Push_clip c ->
        let tp = top () in
        let bounds = rect_intersect tp.cf_bounds c.crect in
        stack :=
          { cf_rect = c.crect;
            cf_radii = corners c.crect c.cradii c.ccontinuous;
            cf_bounds = bounds; cf_scissor = scissor_of_bounds bounds }
          :: !stack
      | Pop_clip -> (
        match !stack with
        | _ :: (_ :: _ as tl) -> stack := tl
        | _ -> ())
      | Fill f ->
        if not (rect_empty f.frect) then (
          let bw =
            if f.fborder_color.a = 0 then (0., 0., 0., 0.) else f.fborder
          in
          let radii = corners f.frect f.fradii f.fcontinuous in
          let inner =
            if has_border bw then snd (inner_radii f.frect radii bw)
            else (0., 0., 0., 0.)
          in
          let w = wide_of f.fwide in
          add
            { rect = f4_of_rect f.frect; radii; inner;
              color = wide_col w Lui_scene.wide_color f.fcolor;
              color2 = wide_col w Lui_scene.wide_color2 f.fcolor2;
              border = wide_col w Lui_scene.wide_border f.fborder_color;
              grad = f.fgradient; uv = bw;
              clip = no_clip; clip_radii = no_clip_radii;
              params =
                (kind_fill, (if f.fdashed then 1. else 0.),
                 paint_code f.fpaint, opacity f.fopacity);
              clip2 = no_clip; clip2_radii = no_clip_radii;
              clip3 = no_clip; clip3_radii = no_clip_radii }
            None)
      | Shadow sh -> (
        if sh.sinset then (
          (* The box in Rect, the hole in UV and Inner, which an inner
             shadow's 1 in params1 tells. *)
          if not (rect_empty sh.scast) then (
            let inst =
              { rect = f4_of_rect sh.scast;
                radii = corners sh.scast sh.scast_radii sh.scast_continuous;
                inner = (0., 0., 0., 0.);
                color = wide_col (wide_of sh.swide) Lui_scene.wide_color sh.scolor;
                color2 = (0., 0., 0., 0.); border = (0., 0., 0., 0.);
                grad = (0., 0., 0., 0.); uv = (0., 0., 0., 0.);
                clip = no_clip; clip_radii = no_clip_radii;
                params =
                  (kind_shadow, 1., shadow_sigma sh.sblur, opacity sh.sopacity);
                clip2 = no_clip; clip2_radii = no_clip_radii;
                clip3 = no_clip; clip3_radii = no_clip_radii }
            in
            let inst =
              if rect_empty sh.srect then inst
              else
                { inst with uv = f4_of_rect sh.srect;
                            inner = corners sh.srect sh.sradii sh.scontinuous }
            in
            add inst None))
        else if not (rect_empty sh.srect) then (
          let inst =
            { rect = f4_of_rect sh.srect;
              radii = corners sh.srect sh.sradii sh.scontinuous;
              inner = (0., 0., 0., 0.);
              color = wide_col (wide_of sh.swide) Lui_scene.wide_color sh.scolor;
              color2 = (0., 0., 0., 0.); border = (0., 0., 0., 0.);
              grad = (0., 0., 0., 0.); uv = (0., 0., 0., 0.);
              clip = no_clip; clip_radii = no_clip_radii;
              params =
                (kind_shadow, 0., shadow_sigma sh.sblur, opacity sh.sopacity);
              clip2 = no_clip; clip2_radii = no_clip_radii;
              clip3 = no_clip; clip3_radii = no_clip_radii }
          in
          let inst =
            if rect_empty sh.scast then inst
            else
              { inst with uv = f4_of_rect sh.scast;
                          inner = corners sh.scast sh.scast_radii sh.scast_continuous }
          in
          add inst None))
      | Glyphs g ->
        let gradients = g.gpaint = Linear || g.gpaint = Oklab in
        let c1, c2 =
          if gradients then
            let w = wide_of g.gwide2 in
            ( wide_col w Lui_scene.wide_color g.gcolor,
              wide_col w Lui_scene.wide_color2 g.gcolor2 )
          else ((0., 0., 0., 0.), (0., 0., 0., 0.))
        in
        let g0 = max 0 g.gstart and g1 = min (Array.length glyphs) g.gend in
        for i = g0 to g1 - 1 do
          let gl = glyphs.(i) in
          let atlas, kind, contrast =
            if gl.gcolored then (s.color_atlas, kind_color_glyph, s.text.contrast)
            else if gl.gsubpixel then
              (s.color_atlas, kind_subpixel_glyph, s.text.subpixel_contrast)
            else (s.mask_atlas, kind_mask_glyph, s.text.contrast)
          in
          let boost = if gl.gthin then thin_boost else 0. in
          let aw = float atlas.w and ah = float atlas.h in
          let inst =
            { rect = (round gl.gx, round gl.gy, float gl.guw, float gl.gvh);
              radii = s.text.gamma_ratios;
              inner = (contrast, boost, 0., 0.);
              color = straight gl.gcolor; color2 = (0., 0., 0., 0.);
              border = (0., 0., 0., 0.); grad = (0., 0., 0., 0.);
              uv = (float gl.gu /. aw, float gl.gv /. ah,
                    float (gl.gu + gl.guw) /. aw, float (gl.gv + gl.gvh) /. ah);
              clip = no_clip; clip_radii = no_clip_radii;
              params = (kind, 0., 0., 1.);
              clip2 = no_clip; clip2_radii = no_clip_radii;
              clip3 = no_clip; clip3_radii = no_clip_radii }
          in
          let inst =
            match wide_of gl.gwide with
            | Some w -> { inst with color = w.wcolor }
            | None -> inst
          in
          let inst =
            if gradients && not gl.gcolored then
              { inst with color = c1; color2 = c2; grad = g.ggradient;
                          params =
                            (kind, 0., paint_code g.gpaint, opacity g.gopacity) }
            else inst
          in
          add inst None
        done
      | Image io ->
        let img = io.iimage in
        if not (rect_empty io.irect2 || rect_empty io.isrc) && img.iw > 0
           && img.ih > 0
        then (
          let iw = float img.iw and ih = float img.ih in
          (* The texels bilinear taps may read, as the CPU renderer
             clamps them: the source rectangle's, inside the image. *)
          let inner =
            ( float (int_of_float io.isrc.x),
              float (int_of_float io.isrc.y),
              float (min (int_of_float (Float.ceil (io.isrc.x +. io.isrc.w)) - 1)
                       (img.iw - 1)),
              float (min (int_of_float (Float.ceil (io.isrc.y +. io.isrc.h)) - 1)
                       (img.ih - 1)) )
          in
          add
            { rect = f4_of_rect io.irect2;
              radii = corners io.irect2 io.iradii io.icontinuous;
              inner; color = (0., 0., 0., 0.);
              color2 = (0., 0., 0., 0.); border = (0., 0., 0., 0.);
              grad = (0., 0., 0., 0.);
              uv = (io.isrc.x /. iw, io.isrc.y /. ih,
                    (io.isrc.x +. io.isrc.w) /. iw,
                    (io.isrc.y +. io.isrc.h) /. ih);
              clip = no_clip; clip_radii = no_clip_radii;
              params =
                (kind_image, (if io.igrayscale then 1. else 0.), 0.,
                 opacity io.iopacity);
              clip2 = no_clip; clip2_radii = no_clip_radii;
              clip3 = no_clip; clip3_radii = no_clip_radii }
            (Some img))
      | Effect ed ->
        if not (rect_empty ed.edrect) && ed.edindex >= 0
           && ed.edindex < Array.length effects
        then add_effect ed effects.(ed.edindex)
      | Hole ho -> if not (rect_empty ho.hrect) then add_hole ho)
    s.ops;
  close ();
  List.rev !done_

(* The packed layout of one instance for the instance buffer: rect,
   radii, inner, color, color2, border, grad, uv, clip, clip_radii,
   params, clip2, clip2_radii, clip3, clip3_radii, rounded to float32. *)
let to_float32_array (i : instance) : float array =
  let b = Bigarray.(Array1.create float32 c_layout instance_floats) in
  let k = ref 0 in
  let put (x, y, z, w) =
    Bigarray.Array1.set b !k x;
    Bigarray.Array1.set b (!k + 1) y;
    Bigarray.Array1.set b (!k + 2) z;
    Bigarray.Array1.set b (!k + 3) w;
    k := !k + 4
  in
  put i.rect; put i.radii; put i.inner; put i.color; put i.color2;
  put i.border; put i.grad; put i.uv; put i.clip; put i.clip_radii;
  put i.params; put i.clip2; put i.clip2_radii; put i.clip3;
  put i.clip3_radii;
  Array.init instance_floats (fun j -> Bigarray.Array1.get b j)

let shader_source = Shader_source.source
