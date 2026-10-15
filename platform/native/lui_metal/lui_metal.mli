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
    [init_window] draws directly into an SDL window's Metal drawable,
    acquired and encoded on a background queue. When the
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
(** [render r scene] draws [scene] into the offscreen target or queues a
    window frame. Check [ready] before submitting a window frame. *)

val present : t -> unit
(** [present r] presents the queued window frame and waits for completion. *)

val ready : t -> bool
(** Whether a window has completed its render and drawable acquisition.
    Check before rendering to bound in-flight work without blocking input. *)

val present_async : t -> unit
(** Request a queued window presentation without blocking the input thread.
    Repeated requests coalesce. *)

val trim : t -> unit
(** Release unused window drawables while retaining the visible frame and
    rendered target. The next render restores the scene's drawable dimensions.
    Offscreen renderers have no drawable pool to trim. *)

val presented_frames : t -> int
(** Number of frames reported as displayed by Metal's presented handler. *)

val presentation_samples : t -> int * float array
(** Total measured display intervals and the latest 240 intervals in milliseconds,
    ordered oldest first. Uses drawable presentation timestamps, not callback
    delivery times. Offscreen renderers have no presentation samples. *)

val set_frame_rate : t -> int -> unit
(** Request the window display cadence on macOS 14 or later. The system
    chooses a cadence supported by the attached display. *)

val read_frame : t -> w:int -> h:int -> bytes
(** [read_frame r ~w ~h] is the target's pixels: premultiplied BGRA
    rows, top row first, [4*w] bytes a row. For tests and pixel-parity
    checks. *)

val release : t -> unit
(** [release r] releases the renderer's Metal objects. *)

(** {1 Internals exposed for tests} *)

val drawable_count : t -> int
(** Configured window drawable capacity, or zero for an offscreen renderer. *)

val drawable_size : t -> (int * int) option
(** Current window drawable dimensions, absent for an offscreen renderer. *)

val owned_target_bytes : t -> int
(** Allocated bytes in a private frame target, excluding window drawables. *)

val attribute_count : int
(** Float4 vertex attributes per instance (15). *)

val instance_bytes : int
(** Bytes per packed instance (60 float32s, 240). *)

val attribute_offset : int -> int -> int
(** [attribute_offset start attr] is the byte offset of attribute
    [attr]'s first component in the instance buffer, for a batch whose
    instances start at index [start]. *)

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

val gpu_ms : t -> float
(** Execution time in milliseconds of the last completed GPU render. *)
