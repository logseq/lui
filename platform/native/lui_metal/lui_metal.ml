(* lui_metal — the Metal backend of the native renderer: it takes what
   Lui_gpu builds for a scene (instanced quads and batches, like the
   other GPU evaluator), encodes one Metal render pass per frame, and
   reads back BGRA bytes in the frame's own top-down order. Its math is
   the GPU's — float32 SDF coverage, gradients and shadows over the
   same 176-byte instances — matching Lui_raster pixel for pixel where
   the formats allow.

   The Metal objects live in lui_metal_stubs.m: a context (device +
   queue + target texture + backdrop textures), compiled libraries,
   pipeline states and textures, each boxed in a custom block. The
   frame is marshalled here: atlas uploads, instance packing, batch
   scissoring, and the backdrop passes an effect needs.

   Frames render into an owned BGRA8 texture, whether offscreen or
   windowed, so read_frame and the backdrop passes never depend on a
   drawable; init_window additionally blits to the layer's drawable on
   present. *)

open Lui_scene

exception Error of string
let error fmt = Printf.ksprintf (fun e -> raise (Error e)) fmt

module A1 = Bigarray.Array1

type f32_ba = (float, Bigarray.float32_elt, Bigarray.c_layout) A1.t

(* A boxed Objective-C object, the shared shape of everything the stubs
   hand out (context, library, pipeline, texture). *)
type obj
type ctx = obj
type lib = obj
type pipe = obj
type tex = obj

type effect_prog = { elib : lib option; epipe : pipe option }

type t = {
  ctx : ctx;
  dual : bool;
  lib : lib;
  pipe_main : pipe;
  pipe_hole : pipe;
  pipe_down : pipe;
  pipe_blur : pipe;
  empty : tex;
  mask : mtex;
  color : mtex;
  images : (int, mtex) Hashtbl.t;
  mutable frame : int;
  mutable effects : (fx * effect_prog) list;
}
(* An atlas or image's texture: gen/version track the source's, so
   uploads are incremental; last_frame lets render release textures
   unseen for a while, as the other GPU evaluator does. *)
and mtex = {
  mutable tex : tex option;
  mutable w : int;
  mutable h : int;
  mutable gen : int;
  mutable ver : int;
  mutable last_frame : int;
}

let new_mtex () = { tex = None; w = 0; h = 0; gen = 0; ver = 0; last_frame = 0 }

(* The blocks metal_render encodes. The C side reads tuple fields by
   position (named record fields would look unused to OCaml), so these
   layouts and the C code's indices change together. *)
type draw_bd =
  int * int * int * int * int * int * float * int * int
(* bx0, by0, bx1, by1, down, radius, sigma, texture w, texture h *)

type draw =
  (int * int * int * int) * int * int * pipe * tex option * draw_bd option
(* scissor left, top, right, bottom; first instance; instance count;
   pipeline; image texture; backdrop *)

type req =
  int * int * (float * float * float * float) * f32_ba * draw array *
  tex * tex * tex * pipe * pipe
(* width, height, clear color, instances, draws, mask atlas, color
   atlas, empty texture, down pipeline, blur pipeline *)

external metal_create_offscreen : int -> int -> (ctx, string) result
  = "lui_metal_create_offscreen"
external metal_create_layer : nativeint -> (ctx, string) result
  = "lui_metal_create_layer"
external metal_compile : ctx -> string -> (lib, string) result
  = "lui_metal_compile"
external metal_pipeline : ctx -> lib -> string -> string -> int -> (pipe, string) result
  = "lui_metal_pipeline"
external metal_texture : ctx -> int -> int -> int -> tex
  = "lui_metal_texture"
external metal_upload : tex -> int * int * int * int -> Bytes.t -> int -> int -> unit
  = "lui_metal_upload"
external metal_render : ctx -> req -> unit = "lui_metal_render"
external metal_read : ctx -> int -> int -> bytes = "lui_metal_read"
external metal_present : ctx -> unit = "lui_metal_present"
external metal_release : obj -> unit = "lui_metal_release"

(* -------------------------------------------------------- internals *)

let attribute_count = 15
let instance_bytes = 240

let attribute_offset start attr = start * instance_bytes + attr * 16

let clamp_scissor (s : Lui_gpu.scissor) ~w ~h =
  { Lui_gpu.left = max 0 (min w s.left);
    top = max 0 (min h s.top);
    right = max 0 (min w s.right);
    bottom = max 0 (min h s.bottom) }

(* A frame's instances packed for one buffer upload: data is the whole
   array, spans the (first, count) instance of each batch. *)
type pack = { data : f32_ba; spans : (int * int) array }

let pack_batches (batches : Lui_gpu.batch list) =
  let spans =
    Array.of_list
      (List.map (fun (b : Lui_gpu.batch) -> (0, List.length b.instances)) batches)
  in
  let total = Array.fold_left (fun n (_, c) -> n + c) 0 spans in
  let data =
    A1.create Bigarray.float32 Bigarray.c_layout (total * Lui_gpu.instance_floats)
  in
  let ofs = ref 0 in
  List.iteri
    (fun i (b : Lui_gpu.batch) ->
       let start = !ofs / Lui_gpu.instance_floats in
       List.iter
         (fun inst ->
            let floats = Lui_gpu.to_float32_array inst in
            Array.iteri (fun j v -> data.{!ofs + j} <- v) floats;
            ofs := !ofs + Lui_gpu.instance_floats)
         b.instances;
       spans.(i) <- (start, !ofs / Lui_gpu.instance_floats - start))
    batches;
  { data; spans }

(* Atlas texture sync: recreate when the atlas grew, upload the changed
   rects when the same atlas was drawn on, skip the upload when it is
   unchanged. *)
type atlas_plan = Recreate | Upload of irect list | Nothing

let atlas_plan ~gen ~ver ~w ~h (a : Atlas.t) =
  if gen <> a.gen || w <> a.w || h <> a.h then Recreate
  else
    let rects, full = Atlas.changes ~gen:a.gen ~version:ver a in
    if full then Recreate
    else if rects = [] then Nothing else Upload rects

let upload_region (a : Atlas.t) (t : tex) (r : irect) =
  let bpp = a.Atlas.bpp in
  metal_upload t (r.x0, r.y0, r.x1 - r.x0, r.y1 - r.y0)
    a.Atlas.pix ((r.y0 * a.Atlas.w + r.x0) * bpp) (a.Atlas.w * bpp)

let sync_atlas t (m : mtex) (a : Atlas.t) ~fmt =
  if a.Atlas.w <= 0 || a.Atlas.h <= 0 then ()
  else
    match atlas_plan ~gen:m.gen ~ver:m.ver ~w:m.w ~h:m.h a with
    | Recreate ->
        (match m.tex with Some o -> metal_release o | None -> ());
        let ntex = metal_texture t.ctx a.Atlas.w a.Atlas.h fmt in
        metal_upload ntex (0, 0, a.Atlas.w, a.Atlas.h) a.Atlas.pix 0
          (a.Atlas.w * a.Atlas.bpp);
        m.tex <- Some ntex; m.w <- a.Atlas.w; m.h <- a.Atlas.h;
        m.gen <- a.Atlas.gen; m.ver <- a.Atlas.version; m.last_frame <- t.frame
    | Upload rects ->
        let ntex =
          match m.tex with
          | Some t -> t
          | None ->
              let ntex = metal_texture t.ctx a.Atlas.w a.Atlas.h fmt in
              m.tex <- Some ntex;
              ntex
        in
        List.iter (upload_region a ntex) rects;
        m.ver <- a.Atlas.version; m.last_frame <- t.frame
    | Nothing -> m.last_frame <- t.frame

(* An image's texture: same bookkeeping, keyed by iid. *)
let image_texture t (i : image) : tex =
  let m =
    match Hashtbl.find_opt t.images i.iid with
    | Some m -> m
    | None ->
        let m = new_mtex () in
        Hashtbl.replace t.images i.iid m;
        m
  in
  (match m.tex with
   | Some _ when m.w = i.iw && m.h = i.ih && m.ver = i.iversion -> ()
   | Some tx ->
       if m.w = i.iw && m.h = i.ih then
         metal_upload tx (0, 0, i.iw, i.ih) i.ipix 0 (i.iw * 4)
       else begin
         metal_release tx;
         let ntex = metal_texture t.ctx i.iw i.ih 1 in
         metal_upload ntex (0, 0, i.iw, i.ih) i.ipix 0 (i.iw * 4);
         m.tex <- Some ntex; m.w <- i.iw; m.h <- i.ih
       end;
       m.ver <- i.iversion
   | None ->
       let ntex = metal_texture t.ctx i.iw i.ih 1 in
       metal_upload ntex (0, 0, i.iw, i.ih) i.ipix 0 (i.iw * 4);
       m.tex <- Some ntex; m.w <- i.iw; m.h <- i.ih; m.ver <- i.iversion);
  m.last_frame <- t.frame;
  match m.tex with Some tx -> tx | None -> t.empty

(* effect_source builds the MSL source of an effect's program: the
   shared shader, the declarations an effect body relies on (struct
   Effect, backdropAt, sampleBackdrop), the effect's own code, and the
   fragment entry. A scene's effect source is read here as MSL — each
   renderer reads the slot in its own shading language. *)
let effect_head = "struct Effect {\n\
                   \  float4 rect;  // x, y, width, height in pixels\n\
                   \  float4 radii; // top-left, top-right, bottom-right, bottom-left\n\
                   \  float4 p0, p1, p2, p3, p4;\n\
                   \  float4 area;  // where the backdrop's area starts, and its size in texels\n\
                   \  float down;   // the size of the squares the backdrop averages\n\
                   };\n\n\
                   float3 backdropAt(texture2d<float> bd, int2 p, int2 size) {\n\
                   \  return bd.read(uint2(clamp(p, int2(0), size - 1))).rgb;\n\
                   }\n\n\
                   float3 sampleBackdrop(texture2d<float> bd, Effect e, float2 q) {\n\
                   \  float2 u = (q - e.area.xy) / e.down - 0.5;\n\
                   \  float2 f = floor(u);\n\
                   \  float2 w = u - f;\n\
                   \  int2 p = int2(f);\n\
                   \  int2 size = int2(e.area.zw);\n\
                   \  float3 top = backdropAt(bd, p, size) * (1.0 - w.x)\n\
                   \           + backdropAt(bd, p + int2(1, 0), size) * w.x;\n\
                   \  float3 bot = backdropAt(bd, p + int2(0, 1), size) * (1.0 - w.x)\n\
                   \           + backdropAt(bd, p + int2(1, 1), size) * w.x;\n\
                   \  return top * (1.0 - w.y) + bot * w.y;\n\
                   }\n"

let effect_tail = "\n\
                   fragment FOut effectFrag(VOut in [[stage_in]],\n\
                   \        texture2d<float> uBackdrop [[texture(3)]],\n\
                   \        sampler smp [[sampler(0)]]) {\n\
                   \  float2 p = in.point.xy;\n\
                   \  Effect e = { in.rect, fabs(in.radii), in.inner, in.color,\n\
                   \               in.color2, in.border, in.grad, in.widths,\n\
                   \               in.params.z };\n\
                   \  float4 res = effect(p, e, uBackdrop) *\n\
                   \    (rectCoverage(p, in.rect, in.radii) *\n\
                   \     clipCoverage(p, in) * in.params.w);\n\
                   \  FOut o;\n\
                   \  o.color = res;\n\
                   #ifdef DUAL\n\
                   \  o.alpha = float4(res.a);\n\
                   #endif\n\
                   \  return o;\n\
                   }\n"

let effect_source ~dual eglsl =
  (if dual then "#define DUAL\n" else "") ^ Metal_source.source
  ^ "\n" ^ effect_head ^ "\n" ^ eglsl ^ effect_tail

(* An effect's program, compiled the first time it is drawn; one that
   does not compile is reported on stderr and draws nothing, as the
   other GPU evaluator does. *)
let effect_pipe t (fx : fx) : pipe option =
  match List.find_opt (fun (x, _) -> x == fx) t.effects with
  | Some (_, p) -> p.epipe
  | None ->
      let prog =
        match metal_compile t.ctx (effect_source ~dual:t.dual fx.eglsl) with
        | Error err ->
            prerr_endline (Printf.sprintf "the effect %s: %s" fx.ename err);
            { elib = None; epipe = None }
        | Ok elib ->
            (match metal_pipeline t.ctx elib "mainVert" "effectFrag"
                     (if t.dual then 0 else 1) with
             | Error err ->
                 prerr_endline (Printf.sprintf "the effect %s: %s" fx.ename err);
                 metal_release elib;
                 { elib = None; epipe = None }
             | Ok epipe -> { elib = Some elib; epipe = Some epipe })
      in
      t.effects <- (fx, prog) :: t.effects;
      prog.epipe

(* -------------------------------------------------------- init *)

(* The 1×1 white texture standing in for absent bindings. *)
let make_empty ctx =
  let tex = metal_texture ctx 1 1 1 in
  metal_upload tex (0, 0, 1, 1) (Bytes.make 4 '\255') 0 4;
  tex

let renderer ctx ~dual ~lib ~pipe_main ~pipe_hole ~pipe_down ~pipe_blur =
  { ctx; dual; lib; pipe_main; pipe_hole; pipe_down; pipe_blur;
    empty = make_empty ctx;
    mask = new_mtex (); color = new_mtex ();
    images = Hashtbl.create 17; frame = 0; effects = [] }

(* With dual-source blending, subpixel glyphs blend each destination
   channel by the coverage of the matching source channel; without it
   they blend by the mean coverage. The single-source program is tried
   when the dual one fails to build. *)
let init_ctx (ctx : ctx) : (t, string) result =
  match metal_compile ctx ("#define DUAL\n" ^ Metal_source.source) with
  | Error e -> Error e
  | Ok lib_dual ->
      (match metal_pipeline ctx lib_dual "mainVert" "mainFrag" 0 with
       | Ok pipe_main ->
           (match metal_pipeline ctx lib_dual "mainVert" "mainFrag" 2,
                  metal_pipeline ctx lib_dual "passVert" "downFrag" 4,
                  metal_pipeline ctx lib_dual "passVert" "blurFrag" 4 with
            | Ok pipe_hole, Ok pipe_down, Ok pipe_blur ->
                Ok (renderer ctx ~dual:true ~lib:lib_dual ~pipe_main
                      ~pipe_hole ~pipe_down ~pipe_blur)
            | _ ->
                metal_release lib_dual;
                Error "pass pipeline creation failed")
       | Error _ ->
           metal_release lib_dual;
           (match metal_compile ctx Metal_source.source with
            | Error e -> Error e
            | Ok lib ->
                (match metal_pipeline ctx lib "mainVert" "mainFrag" 1 with
                 | Error e -> Error e
                 | Ok pipe_main ->
                     (match metal_pipeline ctx lib "mainVert" "mainFrag" 3,
                            metal_pipeline ctx lib "passVert" "downFrag" 4,
                            metal_pipeline ctx lib "passVert" "blurFrag" 4 with
                      | Ok pipe_hole, Ok pipe_down, Ok pipe_blur ->
                          Ok (renderer ctx ~dual:false ~lib ~pipe_main
                                ~pipe_hole ~pipe_down ~pipe_blur)
                      | _ ->
                          metal_release lib;
                          Error "pass pipeline creation failed"))))

let init_ctx_releasing (ctx : ctx) : (t, string) result =
  match init_ctx ctx with
  | Error e ->
      metal_release ctx;
      Error e
  | Ok _ as ok -> ok

let init_offscreen ~w ~h : (t, string) result =
  match metal_create_offscreen w h with
  | Error _ as e -> e
  | Ok ctx -> init_ctx_releasing ctx

let init_window (win : nativeint) : (t, string) result =
  match metal_create_layer win with
  | Error _ as e -> e
  | Ok ctx -> init_ctx_releasing ctx

(* -------------------------------------------------------- render *)

let backdrop_of (b : backdrop) : draw_bd =
  let w, h = Lui_scene.backdrop_size b in
  ( b.barea.x0, b.barea.y0, b.barea.x1, b.barea.y1,
    b.bdown, b.bradius, b.bsigma, w, h )

let render (t : t) (s : Lui_scene.t) : unit =
  let w, h = s.width, s.height in
  if w > 0 && h > 0 then begin
    t.frame <- t.frame + 1;
    sync_atlas t t.mask s.mask_atlas ~fmt:0;
    sync_atlas t t.color s.color_atlas ~fmt:1;
    let batches = Lui_gpu.build s in
    let pack = pack_batches batches in
    (* Drop the image textures unseen for 64 frames. *)
    Hashtbl.filter_map_inplace
      (fun _i (m : mtex) ->
         let keep = m.last_frame > t.frame - 64 in
         if not keep then (match m.tex with Some o -> metal_release o | None -> ());
         if keep then Some m else None)
      t.images;
    let clear = premul s.clear 1. in
    let draws =
      Array.of_list
        (List.mapi
           (fun bi (b : Lui_gpu.batch) ->
              let first, count = pack.spans.(bi) in
              let sc = clamp_scissor b.scissor ~w ~h in
              let pipe =
                match b.fx with
                | Some fx -> effect_pipe t fx
                | None -> Some (if b.hole then t.pipe_hole else t.pipe_main)
              in
              let img =
                match b.image with
                | Some i -> Some (image_texture t i)
                | None -> None
              in
              let bd =
                match b.backdrop, pipe with
                | Some bk, Some _ -> Some (backdrop_of bk)
                | _ -> None
              in
              match pipe with
              | Some pipe ->
                  ( (sc.left, sc.top, sc.right, sc.bottom),
                    first, count, pipe, img, bd )
              | None ->
                  ( (0, 0, 0, 0), first, 0, t.pipe_main, None, None ))
           batches)
    in
    let mask_tex = match t.mask.tex with Some x -> x | None -> t.empty in
    let color_tex = match t.color.tex with Some x -> x | None -> t.empty in
    metal_render t.ctx
      ( w, h, clear, pack.data, draws,
        mask_tex, color_tex, t.empty,
        t.pipe_down, t.pipe_blur )
  end

let present (t : t) : unit = metal_present t.ctx

let read_frame (t : t) ~w ~h : bytes =
  if w <= 0 || h <= 0 then error "read_frame: bad size %d\xC3\x97%d" w h;
  metal_read t.ctx w h

let release (t : t) : unit =
  let rel (m : mtex) = match m.tex with Some o -> metal_release o | None -> () in
  rel t.mask;
  rel t.color;
  Hashtbl.iter (fun _ (m : mtex) -> rel m) t.images;
  Hashtbl.clear t.images;
  metal_release t.empty;
  List.iter (fun (_, (p : effect_prog)) ->
      (match p.epipe with Some o -> metal_release o | None -> ());
      (match p.elib with Some o -> metal_release o | None -> ()))
    t.effects;
  metal_release t.pipe_main;
  metal_release t.pipe_hole;
  metal_release t.pipe_down;
  metal_release t.pipe_blur;
  metal_release t.lib;
  metal_release t.ctx
