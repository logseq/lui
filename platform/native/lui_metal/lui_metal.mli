(** Metal renderer for {!Lui_scene} display lists, the macOS backend.

    Every op of a scene is an instanced quad drawn by the module's
    shader (a port of {!Lui_gpu.shader_source}'s math); clips are
    scissor rectangles, with the innermost rounded clip computed in the
    shader. The renderer consumes {!Lui_gpu.build}'s batches: it uploads
    the scene's atlas changes and its images, binds each batch's
    scissor, image and pipeline state, and draws the batch's instances
    with premultiplied blending. Effects get a pipeline of their own,
    compiled the first time each is drawn; an effect that reads its
    backdrop makes the renderer end the frame pass and run downsample
    and blur passes over the area drawn so far into an offscreen
    texture first.

    {b Metal device.} [init_offscreen] makes a renderer with its own
    BGRA8Unorm target texture — the testable path, needing no window.
    [init_window] wraps an SDL window's Metal layer, and additionally
    blits the frame to the layer's drawable on [present]. When the
    device supports dual-source blending, subpixel glyphs blend each
    destination channel by the coverage of the matching source channel;
    otherwise they blend by the mean coverage. *)

type t
(** A renderer, bound to its Metal device and target. *)

exception Error of string
(** [Error] is raised for failures outside initialization results:
    bad sizes, released objects, Metal command errors. *)

val init_offscreen : w:int -> h:int -> (t, string) result
(** [init_offscreen ~w ~h] creates a device, queue and [w]×[h] target
    texture, and compiles the shaders. *)

val init_window : nativeint -> (t, string) result
(** [init_window win] creates a renderer presenting on the SDL window
    whose address [win] is (an [SDL_Window *], e.g. obtained with
    [SDL_Metal_CreateView]'s conventions; see lui_window). *)

val render : t -> Lui_scene.t -> unit
(** [render r scene] draws [scene] into the renderer's target texture,
    which must be [scene.width]×[scene.height] device pixels. *)

val present : t -> unit
(** [present r] blits the frame to the window's drawable. A no-op for
    an offscreen renderer. *)

val read_frame : t -> w:int -> h:int -> bytes
(** [read_frame r ~w ~h] is the target's pixels: premultiplied BGRA
    rows, top row first, [4*w] bytes a row. For tests and pixel-parity
    checks. *)

val release : t -> unit
(** [release r] releases the renderer's Metal objects. *)

(** {1 Internals exposed for tests} *)

val attribute_count : int
(** Float4 vertex attributes per instance (15). *)

val instance_bytes : int
(** Bytes per packed instance (60 float32s, 240). *)

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

val effect_source : dual:bool -> string -> string
(** [effect_source ~dual emsl] is an effect's fragment shader: the
    shared shader (with [DUAL] defined when [dual] holds), the
    declarations effects use, the effect's own MSL text, and the
    fragment entry that draws its instances. *)
