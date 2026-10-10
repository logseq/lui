(* The Direct3D 11 backend of the native renderer, as lui_gl is the
   OpenGL one: it draws the instance batches Lui_gpu computes for a
   scene into a render target, for a window (a DXGI swapchain on an
   HWND) or offscreen (a BGRA8 render-target texture read_frame reads
   back). The same instance encoding and the same signed-distance math
   as the other renderers, so the pixels match. *)

module A1 = Bigarray.Array1
open Lui_scene

type f32_ba = (float, Bigarray.float32_elt, Bigarray.c_layout) A1.t

exception Error of string

let error fmt = Printf.ksprintf (fun m -> raise (Error m)) fmt

(* {1 The C side} *)

type ctx

external c_init : nativeint -> int -> int -> string -> ctx
  = "lui_d3d11_init"
(* [c_init hwnd w h source] makes the device (hardware first, WARP as
   fallback), compiles the shader's five entry points (vs, ps, passvs,
   downps, blurps) and, with [hwnd] nonzero, the swapchain, otherwise a
   [w]×[h] offscreen BGRA8 render target. Raises [Failure] on error. *)

external c_warp : ctx -> bool = "lui_d3d11_warp"
external c_release : ctx -> unit = "lui_d3d11_release"

external c_begin : ctx -> int -> int -> float -> float -> float -> float ->
  unit = "lui_d3d11_begin_byte" "lui_d3d11_begin"
(* Binds the render target (resizing the swapchain first if needed),
   clears it to the premultiplied color, sets the viewport and the
   whole instance pipeline state. *)

external c_state : ctx -> int -> int -> unit = "lui_d3d11_state"
(* Rebinds the pipeline state after a backdrop pass, with the
   backdrop's texture on sampler slot 3. *)

external c_instances : ctx -> f32_ba -> unit = "lui_d3d11_instances"
external c_shader : ctx -> int -> unit = "lui_d3d11_shader"
external c_hole : ctx -> bool -> unit = "lui_d3d11_hole"

external c_scissor : ctx -> int -> int -> int -> int -> unit
  = "lui_d3d11_scissor"

external c_draw : ctx -> int -> int -> unit = "lui_d3d11_draw"

external c_grab : ctx -> int -> int -> int -> int -> unit
  = "lui_d3d11_grab"
(* Copies the area of the render target into the grab texture and
   switches to the pass pipeline. *)

external c_pass : ctx -> int -> int -> int -> int array -> float -> int ->
  int -> unit = "lui_d3d11_pass_byte" "lui_d3d11_pass"
(* [c_pass ctx shader src dst ints sigma w h] runs the down (shader 0)
   or blur (1) pass, reading texture [src] into texture [dst] —
   0 = grab, 1/2 = the backdrop ping-pong pair — writing the [w]×[h]
   texels at the start of [dst]. [ints] holds the pass record's origin,
   limit, shift, dir, down and radius, and [sigma] its Gaussian. *)

external c_fit : ctx -> int -> int -> int -> int -> unit
  = "lui_d3d11_fit"
(* [c_fit ctx gw gh bw bh] grows the grab texture to at least gw×gh and
   the backdrop pair to bw×bh. *)

external c_atlas : ctx -> int -> int -> int -> bytes -> unit
  = "lui_d3d11_atlas"
(* [c_atlas ctx slot w h pix] recreates atlas texture [slot]
   (0 = R8 mask, 1 = RGBA8 color) with [pix]. *)

external c_atlas_region : ctx -> int -> int -> int -> int -> int ->
  bytes -> int -> int -> unit
  = "lui_d3d11_atlas_region_byte" "lui_d3d11_atlas_region"
(* [c_atlas_region ctx slot x0 y0 x1 y1 pix offset pitch] uploads the
   rectangle's rows. *)

external c_image : ctx -> int -> int -> int -> int -> int -> bytes -> unit
  = "lui_d3d11_image_byte" "lui_d3d11_image"
(* [c_image ctx iid ver w h frame pix] creates or refreshes the texture
   of image [iid] and stamps it used at [frame]. *)

external c_bind_image : ctx -> int -> unit = "lui_d3d11_bind_image"
external c_image_free : ctx -> int -> unit = "lui_d3d11_image_free"
external c_present : ctx -> unit = "lui_d3d11_present"
external c_read : ctx -> bytes = "lui_d3d11_read"
external c_compile : ctx -> string -> int = "lui_d3d11_compile"
external c_last_error : ctx -> string = "lui_d3d11_last_error"
external c_window : int -> int -> nativeint = "lui_d3d11_window"
external c_window_destroy : nativeint -> unit = "lui_d3d11_window_destroy"

(* {1 Shaders} *)

let shader_source = Hlsl_source.source

(* The GLSL effect bodies of the scene carry over: the shim maps the
   names and intrinsics they use to HLSL, so a body written for one
   backend works here. *)
let glsl_compat =
  {|
#define vec2 float2
#define vec3 float3
#define vec4 float4
#define ivec2 int2
#define ivec3 int3
#define ivec4 int4
#define mix lerp
#define fract frac
#define inversesqrt rsqrt
#define dFdx ddx
#define dFdy ddy
#define uMask maskTex
#define uColor colorTex
#define uImage imageTex
#define uBackdrop backdropTex
#define texture(t, u) t.Sample(samp, u)
#define texelFetch(t, u, l) t.Load(int3(u, 0))
#define mediump
#define highp
|}

let effect_head =
  {|Texture2D backdropTex : register(t3);

struct Effect {
	float4 rect;
	float4 radii;
	float4 p0, p1, p2, p3, p4;
	float4 area;
	float down;
};

float3 backdropAt(int2 p, int2 size) {
	return backdropTex.Load(int3(clamp(p, int2(0, 0), size - 1), 0)).rgb;
}

float3 sampleBackdrop(Effect e, float2 q) {
	float2 u = (q - e.area.xy) / e.down - 0.5;
	float2 f = floor(u);
	float2 w = u - f;
	int2 p = int2(f);
	int2 size = int2(e.area.zw);
	float3 top = lerp(backdropAt(p, size), backdropAt(p + int2(1, 0), size), w.x);
	float3 bot = lerp(backdropAt(p + int2(0, 1), size), backdropAt(p + int2(1, 1), size), w.x);
	return lerp(top, bot, w.y);
}
|}

let effect_tail =
  {|
PSOut ps(VSOut i) {
	Effect e;
	e.rect = i.rect;
	e.radii = abs(i.radii);
	e.p0 = i.inner;
	e.p1 = i.color;
	e.p2 = i.color2;
	e.p3 = i.border;
	e.p4 = i.grad;
	e.area = i.widths;
	e.down = i.params.z;
	PSOut o;
	o.color = effect(i.p.xy, e) * (rectCoverage(i.p.xy, i.rect, i.radii) *
		rectCoverage(i.p.xy, i.clip, i.clipRadii) * i.params.w);
	o.alpha = o.color.aaaa;
	return o;
}
|}

let effect_source eglsl =
  "#define EFFECT\n" ^ shader_source ^ effect_head ^ glsl_compat ^ eglsl
  ^ effect_tail

(* {1 Instance packing} *)

type pack = { data : f32_ba; spans : (int * int) array }

let attribute_count = Lui_gpu.instance_floats / 4
let instance_bytes = Lui_gpu.instance_floats * 4

let attribute_offset start attr =
  start * instance_bytes + attr * 16

let pack_batches batches =
  let total =
    List.fold_left (fun n b -> n + List.length b.Lui_gpu.instances) 0 batches
  in
  let data =
    A1.create Bigarray.float32 Bigarray.c_layout
      (total * Lui_gpu.instance_floats)
  in
  let spans = Array.make (List.length batches) (0, 0) in
  let ofs = ref 0 in
  List.iteri
    (fun bi b ->
      let start = !ofs / Lui_gpu.instance_floats in
      List.iter
        (fun inst ->
          let floats = Lui_gpu.to_float32_array inst in
          Array.iteri (fun j v -> data.{!ofs + j} <- v) floats;
          ofs := !ofs + Lui_gpu.instance_floats)
        b.Lui_gpu.instances;
      spans.(bi) <- (start, List.length b.Lui_gpu.instances))
    batches;
  { data; spans }

(* {1 Textures} *)

(* What a texture tracking an atlas must do to catch up. *)
type atlas_plan = Recreate | Upload of irect list | Nothing

(* A different pixel buffer with the same generation is a different
   atlas: generations only say what changed inside one buffer. *)
let atlas_plan ~gen ~ver ~w ~h ~pix (a : Atlas.t) =
  if gen <> a.Atlas.gen || w <> a.Atlas.w || h <> a.Atlas.h
     || not (pix == a.Atlas.pix)
  then Recreate
  else
    match Atlas.changes a ~gen ~version:ver with
    | _, true -> Upload [ irect 0 0 a.Atlas.w a.Atlas.h ]
    | [], false -> Nothing
    | rects, false -> Upload rects

(* The renderer: the device context plus its bookkeeping. *)
type t = {
  ctx : ctx;
  warp : bool;
  rt_w : int;
  rt_h : int;
  mutable frame : int;
  mask : texture;
  color : texture;
  images : (int, int * int) Hashtbl.t; (* iid -> (version, last frame) *)
  mutable grab : int * int;
  mutable backdrop_tex : int * int;
  mutable effects : (fx * int) list;
}
and texture =
  { mutable gen : int; mutable ver : int; mutable w : int;
    mutable h : int; mutable pix : Bytes.t }

let texture () = { gen = -1; ver = -1; w = 0; h = 0; pix = Bytes.empty }

let max_size = 16384

(* Sync the texture of slot (0 mask, 1 color) to the atlas a. *)
let sync_atlas r slot t (a : Atlas.t) =
  if a.Atlas.w > max_size || a.Atlas.h > max_size then
    error "a %d\xD7%d atlas is larger than textures can be" a.Atlas.w
      a.Atlas.h;
  if t.w = 0 then (
    c_atlas r.ctx slot a.Atlas.w a.Atlas.h a.Atlas.pix;
    t.w <- a.Atlas.w;
    t.h <- a.Atlas.h;
    t.gen <- a.Atlas.gen;
    t.pix <- a.Atlas.pix;
    t.ver <- a.Atlas.version)
  else (
    (match atlas_plan ~gen:t.gen ~ver:t.ver ~w:t.w ~h:t.h ~pix:t.pix a with
     | Recreate ->
       c_atlas r.ctx slot a.Atlas.w a.Atlas.h a.Atlas.pix;
       t.w <- a.Atlas.w;
       t.h <- a.Atlas.h;
       t.gen <- a.Atlas.gen;
       t.pix <- a.Atlas.pix
     | Upload rects ->
       let bpp = a.Atlas.bpp and pitch = a.Atlas.w * a.Atlas.bpp in
       List.iter
         (fun (r' : irect) ->
           c_atlas_region r.ctx slot r'.x0 r'.y0 r'.x1 r'.y1 a.Atlas.pix
             ((r'.y0 * pitch) + (r'.x0 * bpp)) pitch)
         rects
     | Nothing -> ());
    t.ver <- a.Atlas.version)

(* Upload the image when its version changed; false when larger than
   textures can be. *)
let image_sync r (img : image) =
  if img.iw > max_size || img.ih > max_size then false
  else (
    (match Hashtbl.find_opt r.images img.iid with
     | Some (ver, _) when ver = img.iversion -> ()
     | _ ->
       c_image r.ctx img.iid img.iversion img.iw img.ih r.frame img.ipix);
    Hashtbl.replace r.images img.iid (img.iversion, r.frame);
    true)

(* Drop the textures of images not drawn for 240 frames; the table is
   the bookkeeping, so entries and textures die together. *)
let gc_images r =
  if r.frame mod 120 = 0 then
    let dead =
      Hashtbl.fold
        (fun k (_, last) acc -> if r.frame - last > 240 then k :: acc else acc)
        r.images []
    in
    List.iter
      (fun k -> c_image_free r.ctx k; Hashtbl.remove r.images k) dead

(* {1 Scissor} *)

let clamp_scissor (sc : Lui_gpu.scissor) ~w ~h : Lui_gpu.scissor =
  { left = max sc.left 0;
    top = max sc.top 0;
    right = min sc.right w;
    bottom = min sc.bottom h }

(* {1 Programs} *)

(* The program of an effect, compiled the first time it is drawn;
   -1 for one that does not compile, which draws nothing. *)
let effect_program r (e : fx) =
  match List.find_opt (fun (x, _) -> x == e) r.effects with
  | Some (_, p) -> p
  | None ->
    let p = c_compile r.ctx (effect_source e.eglsl) in
    if p < 0 then begin
      let err = Printf.sprintf "the effect %s: %s" e.ename (c_last_error r.ctx) in
      prerr_endline err
    end;
    r.effects <- (e, p) :: r.effects;
    p

(* {1 Backdrop passes} *)

(* Make the textures of backdrops as large as the batches need, and the
   texture the area read is copied to. *)
let fit_backdrop r batches =
  let w, h = Lui_gpu.backdrop_size batches in
  let aw, ah =
    List.fold_left
      (fun (aw, ah) b ->
        match b.Lui_gpu.backdrop with
        | None -> (aw, ah)
        | Some bk ->
          (max aw (irect_w bk.barea), max ah (irect_h bk.barea)))
      (0, 0) batches
  in
  let gw, gh = fst r.grab, snd r.grab in
  if aw > gw || ah > gh then (
    (* Somewhat larger, so that growth does not make it again every
       frame. *)
    let nw = min (max (aw + aw / 4) gw) max_size
    and nh = min (max (ah + ah / 4) gh) max_size in
    c_fit r.ctx nw nh (fst r.backdrop_tex) (snd r.backdrop_tex);
    r.grab <- (nw, nh));
  let bw, bh = fst r.backdrop_tex, snd r.backdrop_tex in
  if w > bw || h > bh then (
    let nw = min (max (w + w / 4) bw) max_size
    and nh = min (max (h + h / 4) bh) max_size in
    c_fit r.ctx (fst r.grab) (snd r.grab) nw nh;
    r.backdrop_tex <- (nw, nh))

(* Run the pass p of src into the w×h texels at the start of dst,
   textures numbered 0 = grab, 1/2 = backdrop ping-pong. *)
let run_pass r (p : Lui_gpu.pass) shader src dst w h =
  let ox, oy = p.origin and lx, ly = p.limit
  and sx, sy = p.shift and dx, dy = p.dir in
  c_pass r.ctx shader src dst
    [| ox; oy; lx; ly; sx; sy; dx; dy; p.down; p.radius |]
    p.sigma w h

(* Compute the backdrop bk into backdrop texture 1: copy the area into
   grab (whose rows go down as the frame's do), average its squares and
   blur them. *)
let read_backdrop r (bk : backdrop) =
  let w, h = backdrop_size bk in
  c_grab r.ctx bk.barea.x0 bk.barea.y0 bk.barea.x1 bk.barea.y1;
  run_pass r
    (Lui_gpu.down_pass bk ~shift:(bk.barea.x0, bk.barea.y0))
    0 0 1 w h;
  if bk.bradius > 0 then (
    run_pass r (Lui_gpu.blur_pass bk (1, 0)) 1 1 2 w h;
    run_pass r (Lui_gpu.blur_pass bk (0, 1)) 1 2 1 w h)

(* {1 Drawing} *)

let draw_batch r s pack bi (b : Lui_gpu.batch) bound program hole =
  let start, count = pack.spans.(bi) in
  let sc = clamp_scissor b.Lui_gpu.scissor ~w:s.width ~h:s.height in
  if count > 0 && not (Lui_gpu.scissor_empty sc) then (
    let want =
      match b.Lui_gpu.fx with
      | None -> 0
      | Some fx -> effect_program r fx
    in
    if want >= 0 then (
      (match b.Lui_gpu.backdrop with
       | Some bk ->
         (* The effect shows what is drawn so far. *)
         read_backdrop r bk;
         c_state r.ctx s.width s.height;
         bound := -1;
         program := 0;
         hole := false
       | None -> ());
      if b.Lui_gpu.hole <> !hole then (
        hole := b.Lui_gpu.hole;
        c_hole r.ctx !hole);
      if want <> !program then (
        program := want;
        c_shader r.ctx want);
      (match b.Lui_gpu.image with
       | Some img ->
         let iid = if image_sync r img then img.iid else -1 in
         if iid <> !bound then (
           bound := iid;
           c_bind_image r.ctx iid)
       | None -> ());
      (* Instances draw from the batch's first: DrawInstanced starts at
         it in the instance buffer. *)
      c_scissor r.ctx sc.left sc.top sc.right sc.bottom;
      c_draw r.ctx start count))

let render r s =
  let w, h = s.width, s.height in
  if w > 0 && h > 0 then (
    r.frame <- r.frame + 1;
    sync_atlas r 0 r.mask s.mask_atlas;
    sync_atlas r 1 r.color s.color_atlas;
    let batches = Lui_gpu.build s in
    fit_backdrop r batches;
    let cr, cg, cb, ca = premul s.clear 1. in
    c_begin r.ctx w h cr cg cb ca;
    let pack = pack_batches batches in
    if A1.dim pack.data > 0 then (
      c_instances r.ctx pack.data;
      let bound = ref (-1) and program = ref 0 and hole = ref false in
      List.iteri (fun i b -> draw_batch r s pack i b bound program hole)
        batches);
    c_present r.ctx;
    gc_images r)

(* {1 Renderer setup} *)

let init hwnd ~w ~h =
  match
    try Ok (c_init hwnd w h shader_source) with Failure m -> Error m
  with
  | Error _ as e -> e
  | Ok ctx ->
    Ok
      { ctx;
        warp = c_warp ctx;
        rt_w = w;
        rt_h = h;
        frame = 0;
        mask = texture ();
        color = texture ();
        images = Hashtbl.create 16;
        grab = (0, 0);
        backdrop_tex = (0, 0);
        effects = [] }

let init_offscreen ~w ~h = init 0n ~w ~h

let init_hwnd hwnd ~w ~h = init hwnd ~w ~h

let warp r = r.warp

let read_frame r ~w ~h =
  if w <> r.rt_w || h <> r.rt_h then
    error "read_frame %d\xD7%d of a %d\xD7%d target" w h r.rt_w r.rt_h
  else c_read r.ctx

let release r = c_release r.ctx

let create_window ~w ~h = c_window w h
let destroy_window = c_window_destroy
