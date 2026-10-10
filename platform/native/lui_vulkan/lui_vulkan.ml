(* Vulkan renderer for Lui_scene display lists (Linux). Mirrors the
   GL renderer's architecture — see the .mli for what differs. *)

open Lui_scene

module A1 = Bigarray.Array1

type f32_ba =
  (float, Bigarray.float32_elt, Bigarray.c_layout) A1.t

exception Error of string

let error fmt = Printf.ksprintf (fun s -> raise (Error s)) fmt

(* {1 The stubs} *)

type ctx

external c_create : int -> int -> ctx = "lui_vk_create"
external c_destroy : ctx -> unit = "lui_vk_destroy"
external c_driver : ctx -> string = "lui_vk_driver"
external c_dual : ctx -> bool = "lui_vk_dual"
external c_max_size : ctx -> int = "lui_vk_max_size"
external c_pipeline : ctx -> string -> string -> int -> int
  = "lui_vk_pipeline"
external c_tex_new : ctx -> int -> int -> int -> int = "lui_vk_tex_new"
external c_tex_delete : ctx -> int -> unit = "lui_vk_tex_delete"
external c_bind_atlas : ctx -> int -> int -> unit = "lui_vk_bind_atlas"
external c_bind_backdrop : ctx -> int -> unit = "lui_vk_bind_backdrop"
external c_begin : ctx -> unit = "lui_vk_begin"
external c_tex_upload :
  ctx -> int -> int -> int -> int -> int -> bytes -> unit
  = "lui_vk_tex_upload_bytecode" "lui_vk_tex_upload"
external c_instances : ctx -> f32_ba -> unit = "lui_vk_instances"
external c_frame : ctx -> float -> float -> float -> float -> unit
  = "lui_vk_frame"
external c_rp_end : ctx -> unit = "lui_vk_rp_end"
external c_resume : ctx -> unit = "lui_vk_resume"
external c_draw :
  ctx -> int -> int -> int -> int -> int -> int -> int -> int -> int ->
  unit = "lui_vk_draw_bytecode" "lui_vk_draw"
external c_copy_frame : ctx -> int -> int -> int -> int -> int -> unit
  = "lui_vk_copy_frame_bytecode" "lui_vk_copy_frame"
external c_pass :
  ctx -> int -> int -> int -> int -> int -> int array -> float -> unit
  = "lui_vk_pass_bytecode" "lui_vk_pass"
external c_end_frame : ctx -> unit = "lui_vk_end_frame"
external c_read : ctx -> bytes = "lui_vk_read"
external c_compile : ctx -> string -> string = "lui_vk_compile"

(* {1 Types} *)

(* A texture id and the bookkeeping of what it currently holds: for an
   atlas texture, the generation and version uploaded; for an image,
   the version uploaded and the frame it was last drawn. Id -1 marks
   an uncreated texture; id 0 is the renderer's own empty texture. *)
type texture = {
  mutable tex : int;
  mutable w : int;
  mutable h : int;
  mutable gen : int;
  mutable ver : int;
  mutable last_frame : int;
}

let texture () = { tex = -1; w = 0; h = 0; gen = 0; ver = -1; last_frame = 0 }

type t = {
  ctx : ctx;
  fw : int; (* the frame image's size, which scenes must match *)
  fh : int;
  dual : bool;
  compiler : bool; (* runtime GLSL compile is reachable *)
  max_size : int;
  pipe_scene : int;
  pipe_hole : int;
  pipe_down : int;
  pipe_blur : int;
  mask : texture;
  color : texture;
  images : (int, texture) Hashtbl.t;
  mutable frame : int;
  mutable grab : texture;
  backdrop_tex : texture array; (* two: the blur passes ping-pong *)
  mutable effects : ((fx * bool) * int) list;
  (* effect pipelines keyed by the effect and the hole blend *)
}

type pack = { data : f32_ba; spans : (int * int) array }

(* {1 Instance packing} *)

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

let clamp_scissor (sc : Lui_gpu.scissor) ~w ~h : Lui_gpu.scissor =
  { left = max sc.left 0;
    top = max sc.top 0;
    right = min sc.right w;
    bottom = min sc.bottom h }

(* {1 Textures} *)

(* A scratch buffer of at least n bytes, for uploads' pixel staging. *)
let scratch = ref (Bytes.create 0)

let scratch_buf n =
  if Bytes.length !scratch < n then scratch := Bytes.create n;
  !scratch

(* Texture formats for tex_new: 0 r8, 1 rgba8, 2 bgra8. *)
let tex_r8 = 0
let tex_rgba8 = 1
let tex_bgra8 = 2

(* Upload the rectangle r of atlas a's pixels, staged contiguously. *)
let upload_region r_ctx a tex (r : irect) =
  let bpp = a.Atlas.bpp in
  let rw = r.x1 - r.x0 and rh = r.y1 - r.y0 in
  let row = rw * bpp in
  let b = scratch_buf (row * rh) in
  for j = 0 to rh - 1 do
    Bytes.blit a.Atlas.pix (((r.y0 + j) * a.Atlas.w + r.x0) * bpp) b
      (j * row) row
  done;
  c_tex_upload r_ctx tex r.x0 r.y0 rw rh (Bytes.sub b 0 (row * rh))

(* What a texture tracking an atlas must do to catch up. *)
type atlas_plan = Recreate | Upload of irect list | Nothing

let atlas_plan ~gen ~ver ~w ~h (a : Atlas.t) =
  if gen <> a.Atlas.gen || w <> a.Atlas.w || h <> a.Atlas.h then Recreate
  else
    match Atlas.changes a ~gen ~version:ver with
    | _, true -> Upload [ irect 0 0 a.Atlas.w a.Atlas.h ]
    | [], false -> Nothing
    | rects, false -> Upload rects

let sync_atlas r t (a : Atlas.t) ~fmt ~slot =
  if a.Atlas.w > r.max_size || a.Atlas.h > r.max_size then
    error "a %d\xD7%d atlas is larger than textures can be" a.Atlas.w
      a.Atlas.h;
  match atlas_plan ~gen:t.gen ~ver:t.ver ~w:t.w ~h:t.h a with
  | Recreate ->
    if t.tex >= 0 then c_tex_delete r.ctx t.tex;
    t.tex <-
      c_tex_new r.ctx a.Atlas.w a.Atlas.h fmt;
    t.w <- a.Atlas.w;
    t.h <- a.Atlas.h;
    t.gen <- a.Atlas.gen;
    c_bind_atlas r.ctx slot t.tex;
    upload_region r.ctx a t.tex (irect 0 0 a.Atlas.w a.Atlas.h);
    t.ver <- a.Atlas.version
  | Upload rects ->
    List.iter (upload_region r.ctx a t.tex) rects;
    t.ver <- a.Atlas.version
  | Nothing -> t.ver <- a.Atlas.version

(* The texture of an image, uploaded again when its version changes;
   -1 when it is larger than textures can be. *)
let image_texture r (img : image) =
  if img.iw > r.max_size || img.ih > r.max_size then -1
  else
    match Hashtbl.find_opt r.images img.iid with
    | Some t ->
      if t.ver <> img.iversion then (
        c_tex_upload r.ctx t.tex 0 0 img.iw img.ih img.ipix;
        t.ver <- img.iversion);
      t.last_frame <- r.frame;
      t.tex
    | None ->
      let tex = c_tex_new r.ctx img.iw img.ih tex_rgba8 in
      c_tex_upload r.ctx tex 0 0 img.iw img.ih img.ipix;
      let t =
        { (texture ()) with tex; w = img.iw; h = img.ih;
                            ver = img.iversion; last_frame = r.frame }
      in
      Hashtbl.replace r.images img.iid t;
      tex

(* {1 Effect pipelines} *)

(* An effect's fragment shader: the shared fragment code with EFFECT
   defined, the declarations effects use, the effect's own eglsl, and
   the main that draws its instances. dual adds the second color
   output the blend state reads on a dual-source device; without it
   the pipeline would read undefined SRC1 values. *)
let effect_source ?(dual = false) src =
  "#version 450\n#define EFFECT\n"
  ^ (if dual then "#define DUAL\n" else "")
  ^ Shader_sources.common_src ^ "\n"
  ^ Shader_sources.effect_head_src ^ "\n" ^ src ^ "\n"
  ^ Shader_sources.effect_tail_src

(* The GLSL of an effect without one, for the effects the scene ships
   named: their CPU twins' fixed translation, parameterized by the
   effect's numeric params. *)
let default_effect = function
  | "testfx" ->
    "vec4 effect(vec2 p, Effect e) {\n\
     \treturn vec4(p.x / 100.0, p.y / 80.0, 0.6, 1.0);\n\
     }"
  | "dim" ->
    "vec4 effect(vec2 p, Effect e) {\n\
     \treturn vec4(sampleBackdrop(e, p) * 0.5, 1.0);\n\
     }"
  | "tint" ->
    "vec4 effect(vec2 p, Effect e) {\n\
     \treturn vec4(e.p1.rgb * e.p1.a, 1.0);\n\
     }"
  | "lens" ->
    "vec4 effect(vec2 p, Effect e) {\n\
     \tfloat d = max(8.0 + sdRoundRect(p, e.rect, e.radii), 0.0) * e.p0.x;\n\
     \tvec3 c = sampleBackdrop(e, vec2(p.x + d, p.y));\n\
     \treturn vec4(c + (e.p1.rgb - c) * e.p1.a, 1.0);\n\
     }"
  | _ -> ""

(* The GLSL an effect compiles: its own, or the built-in twin its
   name selects when it ships none. *)
let effect_glsl (e : Lui_scene.fx) =
  if e.eglsl = "" then default_effect e.ename else e.eglsl

(* The pipeline of effect e with the hole blend h, compiled the first
   time it draws; -1 for one that fails, which draws nothing (as the
   GL renderer's failed effects do). *)
let effect_pipeline r e hole =
  match
    List.find_opt (fun ((x, h), _) -> x == e && h = hole) r.effects
  with
  | Some (_, p) -> p
  | None ->
    let p =
      match effect_glsl e with
      | "" -> -1
      | src ->
        (try
           let fs =
             c_compile r.ctx (effect_source ~dual:r.dual src)
           in
           c_pipeline r.ctx Shader_sources.vert_spv fs
             (if hole then 1 else 0)
         with Failure err ->
           prerr_endline
             (Printf.sprintf "the effect %s: %s" e.ename err);
           -1)
    in
    r.effects <- ((e, hole), p) :: r.effects;
    p

(* {1 Backdrop passes} *)

(* The ints a pass pushes: origin, limit, shift and dir pairs, then
   down and radius; sigma is a float argument. *)
let pass_dims (p : Lui_gpu.pass) =
  let ox, oy = p.Lui_gpu.origin and lx, ly = p.Lui_gpu.limit in
  let sx, sy = p.Lui_gpu.shift and dx, dy = p.Lui_gpu.dir in
  [| ox; oy; lx; ly; sx; sy; dx; dy; p.Lui_gpu.down; p.Lui_gpu.radius |]

let pass r pipe src dst w h (p : Lui_gpu.pass) =
  c_pass r.ctx pipe src dst w h (pass_dims p) p.Lui_gpu.sigma

(* Compute the backdrop bk of what the frame holds into
   backdrop_tex.(0): copy the area into grab (top-down, as the frame
   is stored), average its squares and blur them. *)
let read_backdrop r (bk : backdrop) =
  let w, h = backdrop_size bk in
  c_rp_end r.ctx;
  c_copy_frame r.ctx r.grab.tex bk.barea.x0 bk.barea.y0
    (irect_w bk.barea) (irect_h bk.barea);
  (* Rows go down in grab: the frame's row y is its row y - barea.y0. *)
  pass r r.pipe_down r.grab.tex r.backdrop_tex.(0).tex w h
    (Lui_gpu.down_pass bk ~shift:(bk.barea.x0, bk.barea.y0));
  if bk.bradius > 0 then (
    pass r r.pipe_blur r.backdrop_tex.(0).tex r.backdrop_tex.(1).tex w h
      (Lui_gpu.blur_pass bk (1, 0));
    pass r r.pipe_blur r.backdrop_tex.(1).tex r.backdrop_tex.(0).tex w h
      (Lui_gpu.blur_pass bk (0, 1)));
  c_resume r.ctx

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
  if aw > r.grab.w || ah > r.grab.h then (
    (* Somewhat larger, so that growth does not make it again every
       frame. *)
    let nw = min (max (aw + (aw / 4)) r.grab.w) r.max_size
    and nh = min (max (ah + (ah / 4)) r.grab.h) r.max_size in
    if r.grab.tex >= 0 then c_tex_delete r.ctx r.grab.tex;
    r.grab <-
      { (texture ()) with
        tex = c_tex_new r.ctx nw nh tex_bgra8;
        w = nw;
        h = nh });
  if w > r.backdrop_tex.(0).w || h > r.backdrop_tex.(0).h then (
    let nw =
      min (max (w + (w / 4)) r.backdrop_tex.(0).w) r.max_size
    and nh =
      min (max (h + (h / 4)) r.backdrop_tex.(0).h) r.max_size
    in
    Array.iteri
      (fun i t ->
        if t.tex >= 0 then c_tex_delete r.ctx t.tex;
        let nt =
          { (texture ()) with
            tex = c_tex_new r.ctx nw nh tex_bgra8;
            w = nw;
            h = nh }
        in
        r.backdrop_tex.(i) <- nt;
        if i = 0 then c_bind_backdrop r.ctx nt.tex)
      r.backdrop_tex)

(* {1 Drawing} *)

(* Draw batch bi. ds_sel: 0 uses ds_id's own set (an image's), 1 the
   backdrop set. *)
let draw_batch r s pack bi (b : Lui_gpu.batch) =
  let start, count = pack.spans.(bi) in
  let sc = clamp_scissor b.Lui_gpu.scissor ~w:s.width ~h:s.height in
  if count > 0 && not (Lui_gpu.scissor_empty sc) then (
    let hole = b.Lui_gpu.hole in
    let pipe, has_backdrop =
      match b.Lui_gpu.fx with
      | None -> ((if hole then r.pipe_hole else r.pipe_scene), false)
      | Some fx ->
        (effect_pipeline r fx hole, b.Lui_gpu.backdrop <> None)
    in
    if pipe >= 0 then (
      if has_backdrop then
        (* The effect shows what is drawn so far. *)
        read_backdrop r (Option.get b.Lui_gpu.backdrop);
      let ds_sel, ds_id =
        if has_backdrop then (1, 0)
        else
          match b.Lui_gpu.image with
          | Some img ->
            let tex = image_texture r img in
            if tex >= 0 then (0, tex) else (0, 0)
          | None -> (0, 0)
      in
      c_draw r.ctx pipe ds_sel ds_id sc.left sc.top sc.right sc.bottom
        start count))

let gc_images r =
  if r.frame mod 120 = 0 then
    let dead =
      Hashtbl.fold
        (fun k t acc -> if r.frame - t.last_frame > 240 then k :: acc else acc)
        r.images []
    in
    List.iter
      (fun k ->
        c_tex_delete r.ctx (Hashtbl.find r.images k).tex;
        Hashtbl.remove r.images k)
      dead

let render r s =
  let w, h = s.width, s.height in
  if w <= 0 || h <= 0 then ()
  else if w <> r.fw || h <> r.fh then
    error "the scene is %d\xD7%d but the frame is %d\xD7%d" w h r.fw
      r.fh
  else (
    r.frame <- r.frame + 1;
    c_begin r.ctx;
    sync_atlas r r.mask s.mask_atlas ~fmt:tex_r8 ~slot:0;
    sync_atlas r r.color s.color_atlas ~fmt:tex_rgba8 ~slot:1;
    let batches = Lui_gpu.build s in
    (* Uploads record into the frame's command buffer, so every image
       the batches draw is uploaded before the render pass begins. *)
    List.iter
      (fun b ->
        match b.Lui_gpu.image with Some img -> ignore (image_texture r img)
        | None -> ())
      batches;
    fit_backdrop r batches;
    let pack = pack_batches batches in
    if A1.dim pack.data > 0 then c_instances r.ctx pack.data;
    let cr, cg, cb, ca = premul s.clear 1. in
    c_frame r.ctx cr cg cb ca;
    List.iteri (fun bi b -> draw_batch r s pack bi b) batches;
    c_end_frame r.ctx;
    gc_images r)

(* {1 Renderer} *)

let init ~w ~h =
  if w <= 0 || h <= 0 then Stdlib.Error "a size of 0 is not drawable"
  else
    match
      (try Ok (c_create w h) with Failure m -> Stdlib.Error m)
    with
    | Stdlib.Error _ as e -> e
    | Ok ctx ->
      let dual = c_dual ctx in
      let frag =
        if dual then Shader_sources.dual_frag_spv
        else Shader_sources.frag_spv
      in
      (try
         let pipe_scene = c_pipeline ctx Shader_sources.vert_spv frag 0 in
         let pipe_hole = c_pipeline ctx Shader_sources.vert_spv frag 1 in
         let pipe_down =
           c_pipeline ctx Shader_sources.pass_vert_spv
             Shader_sources.down_frag_spv 2
         in
         let pipe_blur =
           c_pipeline ctx Shader_sources.pass_vert_spv
             Shader_sources.blur_frag_spv 2
         in
         (* Whether runtime effect compile works on this machine —
            probed by actually compiling a trivial shader. *)
         let compiler =
           try
             ignore
               (c_compile ctx
                  "#version 450\nlayout(location = 0) out vec4 o;\n\
                   void main() { o = vec4(0.0); }\n");
             true
           with Failure _ -> false
         in
         Stdlib.Ok
           { ctx;
             fw = w;
             fh = h;
             dual;
             compiler;
             max_size = c_max_size ctx;
             pipe_scene;
             pipe_hole;
             pipe_down;
             pipe_blur;
             mask = texture ();
             color = texture ();
             images = Hashtbl.create 16;
             frame = 0;
             grab = texture ();
             backdrop_tex = [| texture (); texture () |];
             effects = [] }
       with
      | Failure m ->
        c_destroy ctx;
        Stdlib.Error m
      | Error m ->
        c_destroy ctx;
        Stdlib.Error m)

let driver r = c_driver r.ctx
let dual r = r.dual
let can_compile r = r.compiler

let read_frame r ~w ~h =
  if w <= 0 || h <= 0 then Bytes.empty
  else c_read r.ctx

let release r =
  c_destroy r.ctx;
  r.effects <- [];
  Hashtbl.clear r.images
