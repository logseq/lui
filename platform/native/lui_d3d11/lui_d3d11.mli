(** The Direct3D 11 backend of the native renderer: it draws the
    instance batches [Lui_gpu] computes for a scene into a render target,
    for a window (a DXGI swapchain on a [nativeint] HWND) or offscreen
    (a plain BGRA8 render-target texture [read_frame] reads back, for
    parity testing against [Lui_raster]).

    The module builds on every system: outside Windows its entry points
    raise [Error]. Tests and callers gate on [Sys.os_type = "Win32"]. *)

type t
(** A device and its pipeline state. *)

exception Error of string

val init_offscreen : w:int -> h:int -> (t, string) result
(** [init_offscreen ~w ~h] creates a D3D11 device (hardware first,
    WARP — the software rasterizer — when no hardware driver answers)
    and a [w]×[h] BGRA8 render-target texture, without any window.
    This is the CI-able pixel-parity path. *)

val init_hwnd : nativeint -> w:int -> h:int -> (t, string) result
(** [init_hwnd hwnd ~w ~h] creates a device and a flip-model DXGI
    swapchain on the window [hwnd], sized [w]×[h]; [render] presents to
    it and resizes the swapchain buffers when the scene size changes. *)

val warp : t -> bool
(** [warp r] holds when [r]'s device is the WARP software rasterizer
    rather than a hardware one. *)

val render : t -> Lui_scene.t -> unit
(** [render r s] draws [s]. *)

val read_frame : t -> w:int -> h:int -> bytes
(** [read_frame r ~w ~h] is the render target's pixels as [w*h*4]
    premultiplied BGRA bytes, top row first — the layout [Lui_raster]'s
    [Image.pix] has. [(w, h)] must be the render target's size. *)

val release : t -> unit
(** [release r] frees the device and everything it created. *)

(** {2 Testing} *)

val create_window : w:int -> h:int -> nativeint
(** [create_window ~w ~h] makes a hidden popup window for [init_hwnd]
    on machines without a desktop session — for tests. *)

val destroy_window : nativeint -> unit

val shader_source : string
(** The HLSL of shader.hlsl, verbatim, as data. *)

val effect_source : string -> string
(** [effect_source body] is the shader an effect program compiles: the
    shared part of [shader_source], the effect's [Effect] struct and
    backdrop sampling (the texture is bound to slot 3), the GLSL
    compatibility shim, the caller's [body], and the [ps] entry point. *)

(** {2 Internals exposed for tests} *)

val attribute_count : int
(** The instance's attribute count (11 float4s). *)

val instance_bytes : int
(** Bytes of one instance ([176]). *)

val attribute_offset : int -> int -> int
(** [attribute_offset index attribute] is the byte offset of [attribute]
    of instance [index]. *)

type pack = {
  data : (float, Bigarray.float32_elt, Bigarray.c_layout) Bigarray.Array1.t;
  spans : (int * int) array;  (** instance (start, count) per batch *)
}

val pack_batches : Lui_gpu.batch list -> pack
(** The instance data of [batches], packed as the vertex shader reads
    them, plus each batch's span. *)

val clamp_scissor : Lui_gpu.scissor -> w:int -> h:int -> Lui_gpu.scissor

type atlas_plan = Recreate | Upload of Lui_scene.irect list | Nothing

val atlas_plan :
  gen:int -> ver:int -> w:int -> h:int -> pix:Bytes.t ->
  Lui_scene.Atlas.t -> atlas_plan
(** What an atlas texture must do to catch up with a scene's atlas
    given the tracked generation, version, size and pixel buffer —
    a different pixel buffer with the same generation is a different
    atlas, since generations only describe changes inside one
    buffer. *)
