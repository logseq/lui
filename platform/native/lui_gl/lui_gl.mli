(** OpenGL renderer for {!Lui_scene} display lists, through tgls.

    Every op of a scene is an instanced quad drawn by the shader in
    {!Lui_gpu.shader_source}; clips are scissor rectangles, with the
    innermost rounded clip computed in the shader. The renderer consumes
    {!Lui_gpu.build}'s batches: it uploads the scene's atlas changes and
    its images, binds each batch's scissor, image and program, and draws
    the batch's instances with premultiplied blending. Effects get a
    program of their own, compiled the first time each is drawn; an
    effect that reads its backdrop makes the renderer copy the area of
    the frame drawn so far and run downsample and blur passes into an
    offscreen texture first.

    {b GL context.} [init] must be called with a GL context current:
    OpenGL 3.3 core profile, or OpenGL ES 3.0 (with
    [GL_EXT_blend_func_extended] for dual-source blending; without it
    subpixel glyphs blend with their mean coverage). With SDL, the
    caller sets [SDL_GL_CONTEXT_MAJOR_VERSION=3],
    [SDL_GL_CONTEXT_MINOR_VERSION=3],
    [SDL_GL_CONTEXT_PROFILE_MASK=SDL_GL_CONTEXT_PROFILE_CORE] and
    [SDL_GL_DOUBLEBUFFER=1], and the window's [SDL_WINDOW_OPENGL] flag.
    Every call on a [t] needs that context current on the calling
    thread. *)

type t
(** A renderer, bound to the context [init] ran with. *)

exception Error of string
(** [Error] is raised for GL failures: too old a context, a shader that
    does not compile or link, an atlas or image larger than
    [GL_MAX_TEXTURE_SIZE], or a GL error left by drawing. *)

val init : unit -> (t, string) result
(** [init ()] compiles the shaders and creates the buffers and textures
    of a renderer in the current GL context. *)

val render : t -> Lui_scene.t -> unit
(** [render r scene] draws [scene] into the framebuffer currently bound,
    which must be [scene.width]×[scene.height] device pixels. *)

val release : t -> unit
(** [release r] deletes the renderer's GL objects; the context must be
    current. *)

val read_frame : int -> int -> bytes
(** [read_frame w h] is the bound framebuffer's pixels: premultiplied
    BGRA rows, top row first. For tests and pixel-parity checks. *)

(** {1 Internals exposed for tests} *)

val attribute_count : int
(** Float4 vertex attributes per instance (11). *)

val instance_bytes : int
(** Bytes per packed instance (44 float32s, 176). *)

val attribute_offset : int -> int -> int
(** [attribute_offset start attr] is the byte offset of attribute
    [attr]'s first component in the instance buffer, for a batch whose
    instances start at index [start]. *)

type pack = {
  data : (float, Bigarray.float32_elt, Bigarray.c_layout) Bigarray.Array1.t;
  spans : (int * int) array;
}
(** A frame's instances packed for one buffer upload: [data] is the
    float32 buffer and [spans.(i)] is the (first index, count) of
    batch [i]'s instances in it. *)

val pack_batches : Lui_gpu.batch list -> pack
(** [pack_batches batches] packs every batch's instances into one
    float32 bigarray. *)

val clamp_scissor : Lui_gpu.scissor -> w:int -> h:int -> Lui_gpu.scissor
(** [clamp_scissor sc ~w ~h] is [sc] clamped to the frame's pixels. *)

type atlas_plan = Recreate | Upload of Lui_scene.irect list | Nothing
(** What a texture tracking an atlas must do to catch up. *)

val atlas_plan :
  gen:int -> ver:int -> w:int -> h:int -> Lui_scene.Atlas.t -> atlas_plan
(** [atlas_plan ~gen ~ver ~w ~h atlas] decides the upload for a texture
    whose pixels are [atlas]' at generation [gen] and version [ver],
    sized [w]×[h]. *)

val effect_source : string -> string
(** [effect_source eglsl] is an effect's fragment shader: the shared
    shader with [EFFECT] defined, the declarations effects use, the
    effect's own [eglsl], and the [main] that draws its instances. *)
