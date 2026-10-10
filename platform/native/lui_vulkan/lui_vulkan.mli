(** Vulkan renderer for {!Lui_scene} display lists (Linux).

    Every op of a scene is an instanced quad drawn by the SPIR-V
    compiled from the shaders in [shader/] — the same signed-distance
    math every backend evaluates over {!Lui_gpu}'s instance encoding.
    Clips are scissor rectangles, with the innermost rounded clip
    computed in the shader. The renderer consumes {!Lui_gpu.build}'s
    batches: it uploads the scene's atlas changes and its images, binds
    each batch's scissor, image and pipeline, and draws the batch's
    instances with premultiplied blending. Effects get a pipeline of
    their own, compiled the first time each is drawn; an effect that
    reads its backdrop makes the renderer copy the area of the frame
    drawn so far and run downsample and blur passes into offscreen
    textures first.

    {b Headless device.} v1 is offscreen rendering and readback — the
    CI-able parity path — not window presentation: [init] creates a
    Vulkan instance, a device (with [dualSrcBlend] if the driver
    supports it; without it subpixel glyphs blend with their mean
    coverage, as the other backends do), and a BGRA8 image the size
    given, with no surface. The library loads [libvulkan.so.1] with
    [dlopen] at init, so it builds and runs without a Vulkan SDK; on
    machines with no driver it simply reports failure from [init].

    The frame is stored top-down: the negative-viewport-height trick
    flips Vulkan's clip-space y, so the shared shader math is unchanged
    and [read_frame] returns rows in the frame's order, BGRA, with no
    swizzle. *)

type t
(** A renderer, bound to its Vulkan device and frame image. *)

exception Error of string
(** [Error] is raised for runtime failures: an atlas or image larger
    than [maxImageDimension2D], a failed pipeline, or lost device. *)

val init : w:int -> h:int -> (t, string) result
(** [init ~w ~h] creates a renderer drawing into an offscreen image of
    [w]×[h] pixels. It fails when no Vulkan driver is present. *)

val render : t -> Lui_scene.t -> unit
(** [render r scene] draws [scene] into the frame image. The scene's
    [width]×[height] must be the size [init] was given. *)

val release : t -> unit
(** [release r] destroys the renderer's Vulkan objects. *)

val read_frame : t -> w:int -> h:int -> bytes
(** [read_frame r ~w ~h] is the frame image's pixels: premultiplied
    BGRA rows, top row first. For tests and pixel-parity checks. *)

val driver : t -> string
(** [driver r] names the physical device found at [init] — which GPU,
    or a CPU device such as the reference software rasterizer — for
    the test logs. *)

val dual : t -> bool
(** [dual r] is whether the device blends with the shader's second
    color output (per-channel subpixel coverage). *)

val can_compile : t -> bool
(** [can_compile r] is whether effect GLSL compiles at runtime: a
    libshaderc library or a [glslangValidator] executable was
    reachable at [init], probed by compiling a trivial shader. *)

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

val effect_source : ?dual:bool -> string -> string
(** [effect_source ~dual eglsl] is an effect's fragment shader source:
    the shared fragment code with [EFFECT] defined (and [DUAL] when
    [dual] is, so the shader emits the second color output the blend
    state reads), the declarations effects use, the effect's own
    [eglsl], and the [main] that draws its instances. *)
