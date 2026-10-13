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
  pipe_fill : pipe;
  pipe_mask : pipe;
  pipe_flat : pipe;
  pipe_opaque : pipe;
  pipe_hole : pipe;
  pipe_down : pipe;
  pipe_blur : pipe;
  empty : tex;
  mask : mtex;
  color : mtex;
  images : (int, mtex) Hashtbl.t;
  mutable frame : int;
  mutable effects : (fx * effect_prog) list;
  (* The scene's compiled batches and packed staging; a frame whose
     display list did not move reuses them — the stub still copies
     the staging each render, so the hit saves the OCaml compile
     and pack. *)
  fc : Lui_gpu.batch_cache;
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
external metal_gpu_ms : ctx -> float = "lui_metal_gpu_ms"
external metal_ready : ctx -> bool = "lui_metal_ready"
external metal_present : ctx -> unit = "lui_metal_present"
external metal_present_async : ctx -> unit = "lui_metal_present_async"
external metal_presented_frames : ctx -> int = "lui_metal_presented_frames"
external metal_presentation_samples : ctx -> int * float array = "lui_metal_presentation_samples"
external metal_set_frame_rate : ctx -> int -> unit = "lui_metal_set_frame_rate"
external metal_warm : ctx -> pipe -> unit = "lui_metal_warm"
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
  let pipe_flat = match metal_pipeline ctx lib "flatFillVert" "opaqueFrag" 1 with
    | Ok pipe -> pipe
    | Error message -> failwith ("flat fill pipeline: " ^ message) in
  let pipe_fill = match metal_pipeline ctx lib "mainVert" "fillFrag" (if dual then 0 else 1) with
    | Ok pipe -> pipe
    | Error message -> failwith ("fill pipeline: " ^ message) in
  let pipe_mask = match metal_pipeline ctx lib "mainVert" "maskFrag" (if dual then 0 else 1) with
    | Ok pipe -> pipe
    | Error message -> failwith ("mask glyph pipeline: " ^ message) in
  let pipe_opaque = match metal_pipeline ctx lib "opaqueVert" "opaqueFrag" 4 with
    | Ok pipe -> pipe
    | Error message -> failwith ("opaque fill pipeline: " ^ message) in
  { ctx; dual; lib; pipe_main; pipe_fill; pipe_mask; pipe_flat; pipe_opaque; pipe_hole; pipe_down; pipe_blur;
    empty = make_empty ctx;
    mask = new_mtex (); color = new_mtex ();
    images = Hashtbl.create 17; frame = 0; effects = [];
    fc = Lui_gpu.batch_cache () }

(* With dual-source blending, subpixel glyphs blend each destination
   channel by the coverage of the matching source channel; without it
   they blend by the mean coverage. The single-source program is tried
   when the dual one fails to build. *)
let prof_t0 = Sys.time ()
let prof msg =
  if Sys.getenv_opt "LUI_METAL_PROF" <> None then
    Printf.eprintf "[metal +%.3f] %s\n%!" (Sys.time () -. prof_t0) msg

let init_ctx (ctx : ctx) : (t, string) result =
  prof "init_ctx";
  match metal_compile ctx ("#define DUAL\n" ^ Metal_source.source) with
  | Error e -> Error e
  | Ok lib_dual ->
      prof "dual lib compiled";
      (match metal_pipeline ctx lib_dual "mainVert" "mainFrag" 0 with
       | Ok pipe_main ->
           prof "main pipe";
           (match metal_pipeline ctx lib_dual "mainVert" "mainFrag" 2,
                  metal_pipeline ctx lib_dual "passVert" "downFrag" 4,
                  metal_pipeline ctx lib_dual "passVert" "blurFrag" 4 with
            | Ok pipe_hole, Ok pipe_down, Ok pipe_blur ->
                prof "all pipes";
                (* Deferred-compile warm: issues one degenerate draw so
                   the driver JITs pipe_main off the first frame's
                   critical path. *)
                metal_warm ctx pipe_main;
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
  prof "create_layer";
  match metal_create_layer win with
  | Error _ as e -> prof "create_layer done"; e
  | Ok ctx -> prof "create_layer done"; init_ctx_releasing ctx

(* -------------------------------------------------------- render *)

let backdrop_of (b : backdrop) : draw_bd =
  let w, h = Lui_scene.backdrop_size b in
  ( b.barea.x0, b.barea.y0, b.barea.x1, b.barea.y1,
    b.bdown, b.bradius, b.bsigma, w, h )

let opaque_instance (i : Lui_gpu.instance) =
  let zero = (0., 0., 0., 0.) in
  let aligned (x, y, w, h) =
    List.for_all (fun v -> Float.is_finite v && v = Float.floor v) [x; y; w; h] in
  let kind, _, paint, opacity = i.params in
  let _, _, _, alpha = i.color in
  kind = Lui_gpu.kind_fill && paint = 0. && opacity = 1. && alpha = 1.
  && i.uv = zero && i.radii = zero
  && i.clip_radii = zero && i.clip2_radii = zero && i.clip3_radii = zero
  && aligned i.rect && aligned i.clip && aligned i.clip2 && aligned i.clip3

let outset_scissors (i : Lui_gpu.instance) (sc : Lui_gpu.scissor) =
  let kind, inset, _, _ = i.params in
  let _,_,_,alpha = i.color in
  let x,y,w,h =
    if kind = Lui_gpu.kind_fill && alpha = 0. then
      let x,y,w,h = i.rect in
      let top,right,bottom,left = i.uv in
      x +. left, y +. top, w -. left -. right, h -. top -. bottom
    else i.uv in
  let transparent_border = kind = Lui_gpu.kind_fill && alpha = 0.
    && let _,_,paint,_ = i.params in paint = 0. in
  if (not transparent_border && (kind <> Lui_gpu.kind_shadow || inset <> 0.))
     || w <= 0. || h <= 0. then [sc]
  else
    let a, b, c, d = i.inner in
    let radius = List.fold_left (fun radius v -> max radius (abs_float v)) 0. [a;b;c;d] in
    let extent = if min (min a b) (min c d) < 0. then 1.528665 else 1. in
    let margin = radius *. extent +. 1. in
    let left = max sc.left (int_of_float (Float.ceil (x +. margin)))
    and top = max sc.top (int_of_float (Float.ceil (y +. margin)))
    and right = min sc.right (int_of_float (Float.floor (x +. w -. margin)))
    and bottom = min sc.bottom (int_of_float (Float.floor (y +. h -. margin))) in
    if left >= right || top >= bottom then [sc]
    else
      (* The casting box's interior has coverage one. Leave its curved
         corners and antialiased edges in four nonoverlapping strips. *)
      List.filter (fun (s : Lui_gpu.scissor) -> s.left < s.right && s.top < s.bottom)
        [ {sc with bottom=top}; {sc with top=bottom};
          {sc with top; bottom; right=left}; {sc with top; bottom; left=right} ]

let fill_interior (i : Lui_gpu.instance) (sc : Lui_gpu.scissor) =
  let kind, _, paint, _ = i.params in
  if kind <> Lui_gpu.kind_fill || paint <> 0. || i.uv <> (0.,0.,0.,0.) then None
  else
    let inset sc ((x,y,w,h), (a,b,c,d)) =
      let radius = max (max (abs_float a) (abs_float b)) (max (abs_float c) (abs_float d)) in
      let margin = if radius = 0. then 0. else radius *. 1.528665 +. 1. in
      { Lui_gpu.left=max sc.Lui_gpu.left (int_of_float (Float.ceil (x +. margin)));
        top=max sc.top (int_of_float (Float.ceil (y +. margin)));
        right=min sc.right (int_of_float (Float.floor (x +. w -. margin)));
        bottom=min sc.bottom (int_of_float (Float.floor (y +. h -. margin))) } in
    let inner = List.fold_left inset sc
      [i.rect,i.radii; i.clip,i.clip_radii; i.clip2,i.clip2_radii; i.clip3,i.clip3_radii] in
    if inner.left >= inner.right || inner.top >= inner.bottom then None else Some inner

let render (t : t) (s : Lui_scene.t) : unit =
  let w, h = s.width, s.height in
  if w > 0 && h > 0 then begin
    t.frame <- t.frame + 1;
    (match Sys.getenv_opt "LUI_METAL_CAPTURE" with
       | Some path when t.frame = 30 || Sys.file_exists (path ^ ".request") ->
           if s.effects <> [] then invalid_arg "Scene capture requires serializable effects";
           let channel = open_out_bin path in
           Fun.protect ~finally:(fun () -> close_out channel)
             (fun () -> Marshal.to_channel channel s []);
           if Sys.file_exists (path ^ ".request") then Sys.remove (path ^ ".request")
       | Some _ | None -> ());
    sync_atlas t t.mask s.mask_atlas ~fmt:0;
    sync_atlas t t.color s.color_atlas ~fmt:1;
    let batches, pack, _rebuilt = Lui_gpu.frame t.fc s in
    if t.frame = 30 && Sys.getenv_opt "LUI_METAL_DEBUG" = Some "1" then
      List.iter (fun (b : Lui_gpu.batch) -> List.iter (fun (i : Lui_gpu.instance) ->
        let x,y,w,h = i.rect in
        if w *. h > 100000. then
          let k,_,_,_ = i.params in
          Printf.eprintf "large: kind=%.0f opaque=%b %.0f,%.0f %.0fx%.0f\n%!"
            k (opaque_instance i) x y w h;
          let a,b,c,d = i.radii in let ca,cb,cc,cd = i.color in
          let ba,bb,bc,bd = i.uv in
          Printf.eprintf "  radii=%g,%g,%g,%g color=%g,%g,%g,%g border=%g,%g,%g,%g\n%!"
            a b c d ca cb cc cd ba bb bc bd) b.instances) batches;
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
              let first, count = pack.Lui_gpu.spans.(bi) in
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
                  let draw_at (sc : Lui_gpu.scissor) first count pipe =
                    ((sc.left, sc.top, sc.right, sc.bottom), first, count, pipe, img, bd) in
                  let draw first count pipe = draw_at sc first count pipe in
                  if b.hole || b.fx <> None then [draw first count pipe]
                  else begin
                    let rec runs offset current length acc = function
                      | [] -> List.rev (if length = 0 then acc else draw offset length current :: acc)
                      | (instance : Lui_gpu.instance) :: rest ->
                        let kind, _, _, _ = instance.params in
                        let next = if opaque_instance instance then t.pipe_opaque
                          else if kind = Lui_gpu.kind_fill then t.pipe_fill
                          else if kind = Lui_gpu.kind_mask_glyph then t.pipe_mask else pipe in
                        let strips = outset_scissors instance sc in
                        match fill_interior instance sc with
                        | Some inner when next != t.pipe_opaque ->
                          let acc = if length = 0 then acc else draw offset length current :: acc in
                          let index = offset + length in
                          let strips =
                            [ {sc with bottom=inner.top}; {sc with top=inner.bottom};
                              {sc with top=inner.top; bottom=inner.bottom; right=inner.left};
                              {sc with top=inner.top; bottom=inner.bottom; left=inner.right} ] in
                          let _, _, _, alpha = instance.color in
                          let _, _, _, opacity = instance.params in
                          let interior_pipe = if alpha = 1. && opacity = 1.
                            then t.pipe_opaque else t.pipe_flat in
                          let acc = draw_at inner index 1 interior_pipe :: acc in
                          let acc = List.fold_left (fun acc strip ->
                            if strip.Lui_gpu.left < strip.right && strip.top < strip.bottom
                            then draw_at strip index 1 next :: acc else acc) acc strips in
                          runs (index + 1) pipe 0 acc rest
                        | Some _ | None -> if strips <> [sc] then begin
                          let acc = if length = 0 then acc else draw offset length current :: acc in
                          let index = offset + length in
                          let acc = List.fold_left (fun acc strip -> draw_at strip index 1 next :: acc) acc strips in
                          runs (index + 1) pipe 0 acc rest
                        end else if length = 0 || next == current then
                          runs offset next (length + 1) acc rest
                        else runs (offset + length) next 1 (draw offset length current :: acc) rest
                    in
                    runs first pipe 0 [] b.instances
                  end
              | None -> [] )
           batches |> List.fold_left (fun acc draws -> List.rev_append draws acc) [] |> List.rev)
    in
    let mask_tex = match t.mask.tex with Some x -> x | None -> t.empty in
    let color_tex = match t.color.tex with Some x -> x | None -> t.empty in
    metal_render t.ctx
      ( w, h, clear, A1.sub pack.data 0 pack.floats, draws,
        mask_tex, color_tex, t.empty,
        t.pipe_down, t.pipe_blur )
  end

let gpu_ms (t : t) = metal_gpu_ms t.ctx
let ready (t : t) = metal_ready t.ctx
let present (t : t) : unit = metal_present t.ctx
let present_async (t : t) : unit = metal_present_async t.ctx
let presented_frames (t : t) = metal_presented_frames t.ctx
let presentation_samples (t : t) = metal_presentation_samples t.ctx
let set_frame_rate (t : t) fps =
  if fps <= 0 then invalid_arg "frame rate must be positive";
  metal_set_frame_rate t.ctx fps

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
  metal_release t.pipe_fill;
  metal_release t.pipe_mask;
  metal_release t.pipe_flat;
  metal_release t.pipe_opaque;
  metal_release t.pipe_hole;
  metal_release t.pipe_down;
  metal_release t.pipe_blur;
  metal_release t.lib;
  metal_release t.ctx
