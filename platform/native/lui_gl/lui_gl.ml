(* OpenGL renderer for Lui_scene display lists, through tgls: every op
   of a scene is an instanced quad drawn by the one shader
   (Lui_gpu.shader_source) from the instances Lui_gpu.build produces;
   clips are scissor rectangles, with the innermost rounded clip
   computed in the shader.

   The renderer uploads the atlases' changed rectangles, keeps a
   texture per image (re-uploaded when its version changes, dropped
   when unused), computes the backdrops of effects with downsample and
   blur passes into offscreen textures, and blends premultiplied
   colors, with dual-source blending where available. Effects get a
   program of their own, compiled from their GLSL the first time each
   is drawn.

   init must be called with a GL context current (OpenGL 3.3 core or
   OpenGL ES 3.0); every call on a renderer needs that context
   current. *)

open Tgl3
open Lui_scene

exception Error of string
let error fmt = Printf.ksprintf (fun s -> raise (Error s)) fmt

module A1 = Bigarray.Array1

type char_ba =
  (char, Bigarray.int8_unsigned_elt, Bigarray.c_layout) Bigarray.Array1.t
type f32_ba =
  (float, Bigarray.float32_elt, Bigarray.c_layout) Bigarray.Array1.t

external blit_bytes_to_ba :
  Bytes.t -> int -> char_ba -> int -> int -> unit = "lui_gl_blit_bytes_to_ba"

(* {1 GL object helpers} *)

let i32 n = Bigarray.(Array1.create int32 c_layout n)

let gen1 f =
  let b = i32 1 in
  f 1 b;
  Int32.to_int b.{0}

let del1 f id =
  if id <> 0 then (
    let b = i32 1 in
    b.{0} <- Int32.of_int id;
    f 1 b)

let get_integer pname =
  let b = i32 1 in
  Gl.get_integerv pname b;
  Int32.to_int b.{0}

let info_log ~get ~read id =
  let len = i32 1 in
  get id Gl.info_log_length len;
  let n = Int32.to_int len.{0} in
  if n <= 1 then "no log"
  else (
    let b = Bigarray.(Array1.create char c_layout n) in
    read id n None b;
    String.trim (Gl.string_of_bigarray b))

let compile_shader kind src =
  let s = Gl.create_shader kind in
  Gl.shader_source s src;
  Gl.compile_shader s;
  let ok = i32 1 in
  Gl.get_shaderiv s Gl.compile_status ok;
  if ok.{0} = 0l then (
    let log = info_log ~get:Gl.get_shaderiv ~read:Gl.get_shader_info_log s in
    Gl.delete_shader s;
    Stdlib.Error ("cannot compile the shader: " ^ log))
  else Stdlib.Ok s

let link_program ~vs_src ~fs_src =
  match compile_shader Gl.vertex_shader vs_src with
  | Stdlib.Error _ as e -> e
  | Stdlib.Ok vs -> (
    match compile_shader Gl.fragment_shader fs_src with
    | Stdlib.Error _ as e ->
      Gl.delete_shader vs;
      e
    | Stdlib.Ok fs ->
      let prog = Gl.create_program () in
      Gl.attach_shader prog vs;
      Gl.attach_shader prog fs;
      Gl.link_program prog;
      Gl.delete_shader vs;
      Gl.delete_shader fs;
      let ok = i32 1 in
      Gl.get_programiv prog Gl.link_status ok;
      if ok.{0} = 0l then (
        let log =
          info_log ~get:Gl.get_programiv ~read:Gl.get_program_info_log prog
        in
        Gl.delete_program prog;
        Stdlib.Error ("cannot link the shader: " ^ log))
      else Stdlib.Ok prog)

(* {1 Version and extensions} *)

(* "4.1 Metal - ..." / "3.3" / "OpenGL ES 3.0 ..." *)
let parse_version s =
  let es, s =
    if String.length s >= 10 && String.sub s 0 10 = "OpenGL ES " then
      (true, String.sub s 10 (String.length s - 10))
    else (false, s)
  in
  let scan i =
    let j = ref i in
    while !j < String.length s && s.[!j] >= '0' && s.[!j] <= '9' do
      incr j
    done;
    (int_of_string_opt (String.sub s i (!j - i)), !j)
  in
  let major, i = scan 0 in
  let minor =
    if i < String.length s && s.[i] = '.' then fst (scan (i + 1)) else None
  in
  (es, Option.value ~default:0 major, Option.value ~default:0 minor)

let has_extension name =
  let n = get_integer Gl.num_extensions in
  let rec loop i =
    if i >= n then false
    else
      match Gl.get_stringi Gl.extensions i with
      | Some s when s = name -> true
      | _ -> loop (i + 1)
  in
  loop 0

(* The version header the shaders start with: DUAL selects dual-source
   blending, where the shader's second output gives the source's alpha
   per channel. *)
let shader_header ~es ~dual =
  if not es then "#version 330 core\n" ^ if dual then "#define DUAL\n" else ""
  else
    "#version 300 es\n"
    ^ (if dual then
         "#extension GL_EXT_blend_func_extended : require\n#define DUAL\n"
       else "")
    ^ "precision highp float;\nprecision highp int;\n"

(* {1 Effect shaders} *)

(* An effect's fragment shader: the shared shader with EFFECT defined,
   the declarations effects use (the sampler of the backdrop the
   renderer computes, the Effect record of the instance's fields, the
   bilinear sample over it), the effect's own GLSL, and the main that
   draws its instances with it. *)
let effect_head =
  "uniform sampler2D uBackdrop;\n\
   \n\
   // What an effect reads of its instance.\n\
   struct Effect {\n\
   \tvec4 rect;  // x, y, width, height in pixels\n\
   \tvec4 radii; // top-left, top-right, bottom-right, bottom-left, circular\n\
   \tvec4 p0, p1, p2, p3, p4;\n\
   \tvec4 area;  // where the backdrop's area starts in the frame, and its \
   size in texels\n\
   \tfloat down; // the size of the squares the backdrop averages\n\
   };\n\
   \n\
   vec3 backdropAt(ivec2 p, ivec2 size) {\n\
   \treturn texelFetch(uBackdrop, clamp(p, ivec2(0), size - 1), 0).rgb;\n\
   }\n\
   \n\
   // sampleBackdrop returns the backdrop at q, in the frame's pixels,\n\
   // premultiplied, filtered bilinearly from its texels as\n\
   // scene.backdrop_sample does.\n\
   vec3 sampleBackdrop(Effect e, vec2 q) {\n\
   \tvec2 u = (q - e.area.xy) / e.down - 0.5;\n\
   \tvec2 f = floor(u);\n\
   \tvec2 w = u - f;\n\
   \tivec2 p = ivec2(f);\n\
   \tivec2 size = ivec2(e.area.zw);\n\
   \tvec3 top = backdropAt(p, size) * (1.0 - w.x)\n\
   \t\t + backdropAt(p + ivec2(1, 0), size) * w.x;\n\
   \tvec3 bot = backdropAt(p + ivec2(0, 1), size) * (1.0 - w.x)\n\
   \t\t + backdropAt(p + ivec2(1, 1), size) * w.x;\n\
   \treturn top * (1.0 - w.y) + bot * w.y;\n\
   }\n"

let effect_tail =
  "\n\
   void main() {\n\
   \tvec2 p = vPoint.xy;\n\
   \tEffect e = Effect(vRect, abs(vRadii), vInner, vColor, vColor2,\n\
   \t\tvBorder, vGrad, vWidths, vParams.z);\n\
   \tfragColor = effect(p, e) * (rectCoverage(p, vRect, vRadii)\n\
   \t\t * clipCoverage(p) * vParams.w);\n\
   #ifdef DUAL\n\
   \tfragAlpha = fragColor.aaaa;\n\
   #endif\n\
   }\n"

let effect_source src =
  "#define EFFECT\n" ^ Lui_gpu.shader_source ^ "\n" ^ effect_head ^ "\n" ^ src
  ^ "\n" ^ effect_tail

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
let effect_glsl e = if e.eglsl = "" then default_effect e.ename else e.eglsl

(* {1 Types} *)

(* A GL texture and the bookkeeping of what it currently holds: for an
   atlas texture, the generation and version uploaded; for an image,
   the version uploaded and the frame it was last drawn. *)
type texture = {
  mutable tex : int;
  mutable w : int;
  mutable h : int;
  mutable gen : int;
  mutable ver : int;
  mutable last_frame : int;
}

let texture () = { tex = 0; w = 0; h = 0; gen = 0; ver = -1; last_frame = 0 }

(* The program of a down or blur pass computing backdrops, with its
   uniforms' locations. *)
type pass_program = {
  pprog : int;
  pu_origin : int;
  pu_limit : int;
  pu_shift : int;
  pu_dir : int;
  pu_down : int;
  pu_radius : int;
  pu_sigma : int;
}

(* An effect's program and its uSize location; eprog 0 for an effect
   that failed to compile, which draws nothing. *)
type effect_program = { eprog : int; eu_size : int }

type t = {
  dual : bool;
  (* The context blends with the shader's second color: the source's
     alpha for each channel. *)
  max_size : int;
  program : int;
  u_size : int;
  vao : int;
  buf : int;
  mask : texture;
  color : texture;
  empty : int; (* a texture to bind where there is none *)
  images : (int, texture) Hashtbl.t;
  mutable frame : int;
  down : pass_program;
  blur : pass_program;
  pass_vao : int;
  mutable grab : texture;
  backdrop_tex : texture array; (* two: the blur passes ping-pong *)
  backdrop_fb : int array;
  header : string;
  mutable effects : (fx * effect_program) list;
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

(* {1 Textures} *)

let scratch = ref (A1.create Bigarray.char Bigarray.c_layout 0)

(* A scratch buffer of at least n bytes, for uploads' pixel staging. *)
let scratch_buf n : char_ba =
  if A1.dim !scratch < n then
    scratch := A1.create Bigarray.char Bigarray.c_layout n;
  !scratch

let bytes_to_ba b : char_ba =
  let n = Bytes.length b in
  let ba = scratch_buf n in
  blit_bytes_to_ba b 0 ba 0 n;
  A1.sub ba 0 n

let tex_params () =
  Gl.tex_parameteri Gl.texture_2d Gl.texture_min_filter Gl.linear;
  Gl.tex_parameteri Gl.texture_2d Gl.texture_mag_filter Gl.linear;
  Gl.tex_parameteri Gl.texture_2d Gl.texture_wrap_s Gl.clamp_to_edge;
  Gl.tex_parameteri Gl.texture_2d Gl.texture_wrap_t Gl.clamp_to_edge

let new_texture ~internal ~format ~w ~h (data : char_ba option) =
  let tex = gen1 Gl.gen_textures in
  Gl.bind_texture Gl.texture_2d tex;
  tex_params ();
  Gl.pixel_storei Gl.unpack_alignment 1;
  Gl.pixel_storei Gl.unpack_row_length 0;
  let data = match data with None -> `Offset 0 | Some b -> `Data b in
  Gl.tex_image2d Gl.texture_2d 0 internal w h 0 format Gl.unsigned_byte data;
  Gl.pixel_storei Gl.unpack_alignment 4;
  tex

(* Upload the rectangle r of atlas a's pixels, staged contiguously. *)
let upload_region a ~format (r : irect) =
  let bpp = a.Atlas.bpp in
  let rw = r.x1 - r.x0 and rh = r.y1 - r.y0 in
  let row = rw * bpp in
  let ba = scratch_buf (row * rh) in
  for j = 0 to rh - 1 do
    blit_bytes_to_ba a.Atlas.pix (((r.y0 + j) * a.Atlas.w + r.x0) * bpp) ba
      (j * row) row
  done;
  Gl.pixel_storei Gl.unpack_alignment 1;
  Gl.pixel_storei Gl.unpack_row_length 0;
  Gl.tex_sub_image2d Gl.texture_2d 0 r.x0 r.y0 rw rh format Gl.unsigned_byte
    (`Data (A1.sub ba 0 (row * rh)))

(* What a texture tracking an atlas must do to catch up. *)
type atlas_plan = Recreate | Upload of irect list | Nothing

let atlas_plan ~gen ~ver ~w ~h (a : Atlas.t) =
  if gen <> a.Atlas.gen || w <> a.Atlas.w || h <> a.Atlas.h then Recreate
  else
    match Atlas.changes a ~gen ~version:ver with
    | _, true -> Upload [ irect 0 0 a.Atlas.w a.Atlas.h ]
    | [], false -> Nothing
    | rects, false -> Upload rects

let full_upload ~internal ~format ~w ~h pix =
  new_texture ~internal ~format ~w ~h (Some (bytes_to_ba pix))

let sync_atlas r t (a : Atlas.t) ~internal ~format =
  if a.Atlas.w > r.max_size || a.Atlas.h > r.max_size then
    error "a %d\xD7%d atlas is larger than textures can be" a.Atlas.w
      a.Atlas.h;
  if t.tex = 0 then (
    t.tex <- full_upload ~internal ~format ~w:a.Atlas.w ~h:a.Atlas.h a.Atlas.pix;
    t.w <- a.Atlas.w;
    t.h <- a.Atlas.h;
    t.gen <- a.Atlas.gen;
    t.ver <- a.Atlas.version)
  else (
    (match atlas_plan ~gen:t.gen ~ver:t.ver ~w:t.w ~h:t.h a with
     | Recreate ->
       del1 Gl.delete_textures t.tex;
       t.tex <-
         full_upload ~internal ~format ~w:a.Atlas.w ~h:a.Atlas.h a.Atlas.pix;
       t.w <- a.Atlas.w;
       t.h <- a.Atlas.h;
       t.gen <- a.Atlas.gen
     | Upload rects ->
       Gl.bind_texture Gl.texture_2d t.tex;
       List.iter (upload_region a ~format) rects
     | Nothing -> ());
    t.ver <- a.Atlas.version)

let upload_whole ~w ~h pix =
  Gl.pixel_storei Gl.unpack_alignment 1;
  Gl.pixel_storei Gl.unpack_row_length 0;
  Gl.tex_sub_image2d Gl.texture_2d 0 0 0 w h Gl.rgba Gl.unsigned_byte
    (`Data (bytes_to_ba pix));
  Gl.pixel_storei Gl.unpack_alignment 4

(* The texture of an image, uploaded again when its version changes;
   0 when it is larger than textures can be. *)
let image_texture r (img : image) =
  if img.iw > r.max_size || img.ih > r.max_size then 0
  else
    match Hashtbl.find_opt r.images img.iid with
    | Some t ->
      if t.ver <> img.iversion then (
        Gl.bind_texture Gl.texture_2d t.tex;
        upload_whole ~w:img.iw ~h:img.ih img.ipix;
        t.ver <- img.iversion);
      t.last_frame <- r.frame;
      t.tex
    | None ->
      let t =
        { tex =
            new_texture ~internal:Gl.rgba8 ~format:Gl.rgba ~w:img.iw ~h:img.ih
              (Some (bytes_to_ba img.ipix));
          w = img.iw;
          h = img.ih;
          gen = 0;
          ver = img.iversion;
          last_frame = r.frame }
      in
      Hashtbl.add r.images img.iid t;
      t.tex

(* {1 Scissor} *)

let clamp_scissor (sc : Lui_gpu.scissor) ~w ~h : Lui_gpu.scissor =
  { left = max sc.left 0;
    top = max sc.top 0;
    right = min sc.right w;
    bottom = min sc.bottom h }

(* {1 Programs} *)

let pass_link ~header name =
  match
    link_program
      ~vs_src:(header ^ "#define PASS_VERTEX\n" ^ Lui_gpu.shader_source)
      ~fs_src:(header ^ "#define " ^ name ^ "\n" ^ Lui_gpu.shader_source)
  with
  | Stdlib.Error _ as e -> e
  | Stdlib.Ok prog ->
    Gl.use_program prog;
    Gl.uniform1i (Gl.get_uniform_location prog "uSrc") 0;
    let loc n = Gl.get_uniform_location prog n in
    Gl.use_program 0;
    Stdlib.Ok
      { pprog = prog;
        pu_origin = loc "uOrigin";
        pu_limit = loc "uLimit";
        pu_shift = loc "uShift";
        pu_dir = loc "uDir";
        pu_down = loc "uDown";
        pu_radius = loc "uRadius";
        pu_sigma = loc "uSigma" }

(* The program of an effect, compiled the first time it is drawn; 0
   for one that does not compile, which draws nothing. *)
let effect_program r e =
  match List.find_opt (fun (x, _) -> x == e) r.effects with
  | Some (_, p) -> p
  | None ->
    let p =
      match
        link_program
          ~vs_src:(r.header ^ "#define VERTEX\n" ^ Lui_gpu.shader_source)
          ~fs_src:(r.header ^ effect_source (effect_glsl e))
      with
      | Stdlib.Error err ->
        let err = Printf.sprintf "the effect %s: %s" e.ename err in
        prerr_endline err;
        { eprog = 0; eu_size = 0 }
      | Stdlib.Ok prog ->
        Gl.use_program prog;
        let eu_size = Gl.get_uniform_location prog "uSize" in
        Gl.uniform1i (Gl.get_uniform_location prog "uBackdrop") 3;
        { eprog = prog; eu_size }
    in
    r.effects <- (e, p) :: r.effects;
    p

(* {1 Renderer setup} *)

let init () =
  match Gl.get_string Gl.version with
  | None -> Stdlib.Error "no current GL context"
  | Some version -> (
    let es, major, minor = parse_version version in
    if (es && (major < 3 || (major = 3 && minor < 0)))
       || ((not es) && (major < 3 || (major = 3 && minor < 3)))
    then
      Stdlib.Error
        (Printf.sprintf "OpenGL %d.%d is too old (%s)" major minor version)
    else (
      let dual = (not es) || has_extension "GL_EXT_blend_func_extended" in
      let header = shader_header ~es ~dual in
      match
        link_program
          ~vs_src:(header ^ "#define VERTEX\n" ^ Lui_gpu.shader_source)
          ~fs_src:(header ^ "#define FRAGMENT\n" ^ Lui_gpu.shader_source)
      with
      | Stdlib.Error _ as e -> e
      | Stdlib.Ok program -> (
        Gl.use_program program;
        let u_size = Gl.get_uniform_location program "uSize" in
        Gl.uniform1i (Gl.get_uniform_location program "uMask") 0;
        Gl.uniform1i (Gl.get_uniform_location program "uColor") 1;
        Gl.uniform1i (Gl.get_uniform_location program "uImage") 2;
        Gl.use_program 0;
        match pass_link ~header "DOWN" with
        | Stdlib.Error _ as e ->
          Gl.delete_program program;
          e
        | Stdlib.Ok down -> (
          match pass_link ~header "BLUR" with
          | Stdlib.Error _ as e ->
            Gl.delete_program program;
            Gl.delete_program down.pprog;
            e
          | Stdlib.Ok blur ->
            let pass_vao = gen1 Gl.gen_vertex_arrays in
            (* The instance buffer feeds eleven float4 attributes per
               instance; draws point them at their batch's instances. *)
            let vao = gen1 Gl.gen_vertex_arrays in
            let buf = gen1 Gl.gen_buffers in
            Gl.bind_vertex_array vao;
            Gl.bind_buffer Gl.array_buffer buf;
            for i = 0 to attribute_count - 1 do
              Gl.enable_vertex_attrib_array i;
              Gl.vertex_attrib_divisor i 1
            done;
            Gl.bind_vertex_array 0;
            Gl.bind_buffer Gl.array_buffer 0;
            let empty =
              new_texture ~internal:Gl.rgba8 ~format:Gl.rgba ~w:1 ~h:1
                (Some
                   (A1.sub
                      (A1.create Bigarray.char Bigarray.c_layout 4)
                      0 4))
            in
            if Gl.get_error () <> Gl.no_error then
              Stdlib.Error "setting up failed"
            else
              Stdlib.Ok
                { dual;
                  max_size = get_integer Gl.max_texture_size;
                  program;
                  u_size;
                  vao;
                  buf;
                  mask = texture ();
                  color = texture ();
                  empty;
                  images = Hashtbl.create 16;
                  frame = 0;
                  down;
                  blur;
                  pass_vao;
                  grab = texture ();
                  backdrop_tex = [| texture (); texture () |];
                  backdrop_fb = [| 0; 0 |];
                  header;
                  effects = [] }))))

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
  if aw > r.grab.w || ah > r.grab.h then (
    (* Somewhat larger, so that growth does not make it again every
       frame. *)
    let nw = min (max (aw + aw / 4) r.grab.w) r.max_size
    and nh = min (max (ah + ah / 4) r.grab.h) r.max_size in
    del1 Gl.delete_textures r.grab.tex;
    r.grab <-
      { (texture ()) with
        tex = new_texture ~internal:Gl.rgba8 ~format:Gl.rgba ~w:nw ~h:nh None;
        w = nw;
        h = nh });
  if w > r.backdrop_tex.(0).w || h > r.backdrop_tex.(0).h then (
    let nw =
      min (max (w + w / 4) r.backdrop_tex.(0).w) r.max_size
    and nh =
      min (max (h + h / 4) r.backdrop_tex.(0).h) r.max_size
    in
    Array.iteri
      (fun i t ->
        del1 Gl.delete_textures t.tex;
        let nt =
          { (texture ()) with
            tex =
              new_texture ~internal:Gl.rgba8 ~format:Gl.rgba ~w:nw ~h:nh None;
            w = nw;
            h = nh }
        in
        r.backdrop_tex.(i) <- nt;
        if r.backdrop_fb.(i) = 0 then
          r.backdrop_fb.(i) <- gen1 Gl.gen_framebuffers;
        let fb = get_integer Gl.framebuffer_binding in
        Gl.bind_framebuffer Gl.framebuffer r.backdrop_fb.(i);
        Gl.framebuffer_texture2d Gl.framebuffer Gl.color_attachment0
          Gl.texture_2d nt.tex 0;
        let done_ =
          Gl.check_framebuffer_status Gl.framebuffer = Gl.framebuffer_complete
        in
        Gl.bind_framebuffer Gl.framebuffer fb;
        if not done_ then
          error "cannot draw into a %d\xD7%d backdrop texture" nw nh)
      r.backdrop_tex)

(* Use the program with the uniforms of a pass. *)
let set_pass pp (p : Lui_gpu.pass) =
  Gl.use_program pp.pprog;
  let u2i loc (x, y) = Gl.uniform2i loc x y in
  u2i pp.pu_origin p.Lui_gpu.origin;
  u2i pp.pu_limit p.Lui_gpu.limit;
  u2i pp.pu_shift p.Lui_gpu.shift;
  u2i pp.pu_dir p.Lui_gpu.dir;
  Gl.uniform1i pp.pu_down p.Lui_gpu.down;
  Gl.uniform1i pp.pu_radius p.Lui_gpu.radius;
  Gl.uniform1f pp.pu_sigma p.Lui_gpu.sigma

(* Draw the program in use into the w×h texels at the start of
   backdrop_tex.(i), reading the texture bound to unit 0. *)
let pass r i w h =
  Gl.bind_framebuffer Gl.framebuffer r.backdrop_fb.(i);
  Gl.viewport 0 0 r.backdrop_tex.(i).w r.backdrop_tex.(i).h;
  Gl.scissor 0 0 w h;
  Gl.draw_arrays_instanced Gl.triangle_strip 0 4 1

(* Compute the backdrop bk of what the framebuffer fb holds, a frame
   height pixels high, into backdrop_tex.(0): copy the area into grab
   (whose rows go up as GL's), average its squares and blur them. *)
let read_backdrop r fb height (bk : backdrop) =
  let w, h = backdrop_size bk in
  Gl.disable Gl.blend;
  Gl.bind_framebuffer Gl.framebuffer fb;
  Gl.active_texture Gl.texture0;
  Gl.bind_texture Gl.texture_2d r.grab.tex;
  Gl.copy_tex_sub_image2d Gl.texture_2d 0 0 0 bk.barea.x0
    (height - bk.barea.y1)
    (irect_w bk.barea) (irect_h bk.barea);
  Gl.bind_vertex_array r.pass_vao;
  (* Rows go up in grab: the frame's row y is its row barea.y1-1-y. *)
  set_pass r.down (Lui_gpu.down_pass bk ~shift:(bk.barea.x0, bk.barea.y1 - 1));
  pass r 0 w h;
  if bk.bradius > 0 then (
    set_pass r.blur (Lui_gpu.blur_pass bk (1, 0));
    Gl.bind_texture Gl.texture_2d r.backdrop_tex.(0).tex;
    pass r 1 w h;
    set_pass r.blur (Lui_gpu.blur_pass bk (0, 1));
    Gl.bind_texture Gl.texture_2d r.backdrop_tex.(1).tex;
    pass r 0 w h)

(* {1 Drawing} *)

(* Blend premultiplied colors over what is drawn, or for a hole, take
   their coverage away. *)
let blend_func r hole =
  let src = if hole then Gl.zero else Gl.one in
  if r.dual then
    Gl.blend_func_separate src Gl.one_minus_src1_color src
      Gl.one_minus_src1_alpha
  else Gl.blend_func src Gl.one_minus_src_alpha

(* The state the instances of s draw with; texture unit 2, the
   images', stays active. *)
let bind_state r s =
  Gl.use_program r.program;
  Gl.uniform2f r.u_size (float s.width) (float s.height);
  Gl.bind_vertex_array r.vao;
  Gl.bind_buffer Gl.array_buffer r.buf;
  let tex_of t = if t.tex <> 0 then t.tex else r.empty in
  List.iteri
    (fun unit tex ->
      Gl.active_texture (Gl.texture0 + unit);
      Gl.bind_texture Gl.texture_2d tex)
    [ tex_of r.mask; tex_of r.color; r.empty; r.empty ];
  Gl.active_texture (Gl.texture0 + 2);
  Gl.enable Gl.blend;
  blend_func r false;
  Gl.enable Gl.scissor_test

let draw_batch r s fb pack bi (b : Lui_gpu.batch) bound program hole =
  let start, count = pack.spans.(bi) in
  let sc = clamp_scissor b.Lui_gpu.scissor ~w:s.width ~h:s.height in
  if count > 0 && not (Lui_gpu.scissor_empty sc) then (
    let want =
      match b.Lui_gpu.fx with
      | None -> r.program
      | Some fx ->
        let p = effect_program r fx in
        if p.eprog = 0 then -1 else p.eprog
    in
    if want >= 0 then (
      (match b.Lui_gpu.backdrop with
       | Some bk ->
         (* The effect shows what is drawn so far. *)
         read_backdrop r fb s.height bk;
         Gl.bind_framebuffer Gl.framebuffer fb;
         Gl.viewport 0 0 s.width s.height;
         bind_state r s;
         Gl.active_texture (Gl.texture0 + 3);
         Gl.bind_texture Gl.texture_2d r.backdrop_tex.(0).tex;
         Gl.active_texture (Gl.texture0 + 2);
         bound := r.empty;
         program := r.program;
         hole := false
       | None -> ());
      if b.Lui_gpu.hole <> !hole then (
        hole := b.Lui_gpu.hole;
        blend_func r !hole);
      if want <> !program then (
        program := want;
        Gl.use_program !program;
        match b.Lui_gpu.fx with
        | Some fx ->
          let p = effect_program r fx in
          Gl.uniform2f p.eu_size (float s.width) (float s.height)
        | None -> ());
      (match b.Lui_gpu.image with
       | Some img ->
         let tex = image_texture r img in
         if tex <> 0 && tex <> !bound then (
           bound := tex;
           Gl.bind_texture Gl.texture_2d !bound)
       | None -> ());
      (* Instances draw from the batch's first: the attributes start
         there. *)
      for i = 0 to attribute_count - 1 do
        Gl.vertex_attrib_pointer i 4 Gl.float false instance_bytes
          (`Offset (attribute_offset start i))
      done;
      (* GL's scissor rectangles start at the bottom. *)
      Gl.scissor sc.left (s.height - sc.bottom) (sc.right - sc.left)
        (sc.bottom - sc.top);
      Gl.draw_arrays_instanced Gl.triangle_strip 0 4 count))

let teardown () =
  Gl.disable Gl.scissor_test;
  Gl.disable Gl.blend;
  for unit = 0 to 3 do
    Gl.active_texture (Gl.texture0 + unit);
    Gl.bind_texture Gl.texture_2d 0
  done;
  Gl.active_texture Gl.texture0;
  Gl.bind_buffer Gl.array_buffer 0;
  Gl.bind_vertex_array 0;
  Gl.use_program 0

let gc_images r =
  if r.frame mod 120 = 0 then
    let dead =
      Hashtbl.fold
        (fun k t acc -> if r.frame - t.last_frame > 240 then k :: acc else acc)
        r.images []
    in
    List.iter
      (fun k ->
        del1 Gl.delete_textures (Hashtbl.find r.images k).tex;
        Hashtbl.remove r.images k)
      dead

let render r s =
  let w, h = s.width, s.height in
  if w > 0 && h > 0 then (
    r.frame <- r.frame + 1;
    Gl.active_texture Gl.texture0;
    sync_atlas r r.mask s.mask_atlas ~internal:Gl.r8 ~format:Gl.red;
    sync_atlas r r.color s.color_atlas ~internal:Gl.rgba8 ~format:Gl.rgba;
    let batches = Lui_gpu.build s in
    fit_backdrop r batches;
    (* The framebuffer drawn into, which the backdrop passes leave for
       their own. *)
    let fb = get_integer Gl.framebuffer_binding in
    Gl.viewport 0 0 w h;
    Gl.disable Gl.scissor_test;
    let cr, cg, cb, ca = premul s.clear 1. in
    Gl.clear_color cr cg cb ca;
    Gl.clear Gl.color_buffer_bit;
    let pack = pack_batches batches in
    if A1.dim pack.data > 0 then (
      Gl.bind_buffer Gl.array_buffer r.buf;
      Gl.buffer_data Gl.array_buffer
        (Gl.bigarray_byte_size pack.data)
        (Some pack.data) Gl.stream_draw;
      bind_state r s;
      let bound = ref r.empty
      and program = ref r.program
      and hole = ref false in
      List.iteri (fun bi b -> draw_batch r s fb pack bi b bound program hole)
        batches;
      teardown ();
      gc_images r);
    if Gl.get_error () <> Gl.no_error then error "drawing failed")

let read_frame w h =
  if w <= 0 || h <= 0 then Bytes.empty
  else (
    let ba =
      A1.create Bigarray.char Bigarray.c_layout (4 * w * h)
    in
    Gl.pixel_storei Gl.pack_alignment 1;
    Gl.read_pixels 0 0 w h Gl.rgba Gl.unsigned_byte (`Data ba);
    Gl.pixel_storei Gl.pack_alignment 4;
    if Gl.get_error () <> Gl.no_error then
      error "reading the framebuffer failed";
    (* GL's rows go up, and its bytes are RGBA: flip and swizzle to the
       top-down premultiplied BGRA the CPU renderer produces. *)
    let out = Bytes.make (4 * w * h) '\000' in
    for y = 0 to h - 1 do
      let src = 4 * w * (h - 1 - y) and dst = 4 * w * y in
      for x = 0 to w - 1 do
        let s = src + 4 * x and d = dst + 4 * x in
        Bytes.set out (d + 0) ba.{s + 2};
        Bytes.set out (d + 1) ba.{s + 1};
        Bytes.set out (d + 2) ba.{s + 0};
        Bytes.set out (d + 3) ba.{s + 3}
      done
    done;
    out)

let release r =
  Hashtbl.iter (fun _ t -> del1 Gl.delete_textures t.tex) r.images;
  Hashtbl.clear r.images;
  List.iter
    (fun tex -> del1 Gl.delete_textures tex)
    [ r.mask.tex; r.color.tex; r.empty; r.grab.tex;
      r.backdrop_tex.(0).tex; r.backdrop_tex.(1).tex ];
  Array.iter (fun fb -> del1 Gl.delete_framebuffers fb) r.backdrop_fb;
  List.iter
    (fun (_, p) -> if p.eprog <> 0 then Gl.delete_program p.eprog)
    r.effects;
  List.iter (fun p -> if p <> 0 then Gl.delete_program p)
    [ r.down.pprog; r.blur.pprog ];
  del1 Gl.delete_vertex_arrays r.pass_vao;
  del1 Gl.delete_buffers r.buf;
  del1 Gl.delete_vertex_arrays r.vao;
  if r.program <> 0 then Gl.delete_program r.program;
  r.effects <- []
