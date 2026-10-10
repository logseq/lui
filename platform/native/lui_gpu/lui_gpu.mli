(** Scene to instance compiler: one instanced quad per op, in batches
    sharing a scissor rectangle and an image, for the shader in
    shader.glsl ([shader_source]). Pure OCaml — no GL calls; a renderer
    consumes [build]'s batches. *)

type f4 = float * float * float * float
(** A vec4 in the instance layout. *)

(** The data of one quad, in device pixels, as the shader reads it:
    fifteen float4s.

    [rect] is x, y, width, height; [radii] the corners' radii (top-left,
    top-right, bottom-right, bottom-left), negative for continuous
    corners, or a glyph's gamma ratios; [inner] those of a border's
    inner edge, of the box casting a shadow, a glyph's contrast and
    thin boost, or an image's source-texel clamp.

    [color], [color2] (a gradient's end) and [border] are straight RGBA.

    [grad] holds a gradient's start and end points, or the stripes'
    unit vector across them, width and period; [uv] the texture
    rectangle, normalized, a fill's border widths (top, right, bottom,
    left), or the box casting a shadow (none when empty).

    An effect has its parameters (effect_op.eparams) in [inner],
    [color], [color2], [border] and [grad], and in [uv] where its
    backdrop's area starts in the frame and its size in texels.

    [clip] and [clip_radii] are the innermost clip, [clip2] and
    [clip3] the two containing it (the everything rectangle where the
    stack is shallower); the shader multiplies their coverages, and
    clips deeper than three cut by their scissor bounds only.

    [params] is (kind, flag, aux, opacity): kind as below; flag is 1 for
    a dashed border, a grayscale image or an inner shadow (whose box is
    in [rect]/[radii] and the hole it leaves in [uv]/[inner]); aux is
    the shadow's sigma (0 for none), the paint code, or the side of the
    squares an effect's backdrop averages. *)
type instance = {
  rect : f4;
  radii : f4;
  inner : f4;
  color : f4;
  color2 : f4;
  border : f4;
  grad : f4;
  uv : f4;
  clip : f4;
  clip_radii : f4;
  params : f4;
  clip2 : f4;
  clip2_radii : f4;
  clip3 : f4;
  clip3_radii : f4;
}

(** Instance kinds, selected by [params] component 0. *)
val kind_fill : float
val kind_shadow : float
val kind_mask_glyph : float
val kind_color_glyph : float
val kind_image : float
val kind_subpixel_glyph : float
val kind_effect : float

val instance_floats : int
(** Floats in the packed layout of one instance (60). *)

(** A scissor rectangle in device pixels. *)
type scissor = { left : int; top : int; right : int; bottom : int }

val scissor_empty : scissor -> bool
(** Whether the rectangle has no pixels. *)

(** A run of instances that draw with the same scissor rectangle and
    image.

    [fx] is the effect of the batch's one instance, drawn with a
    pipeline of its own. [backdrop] is the backdrop the renderer
    computes and binds before drawing the batch, when the effect reads
    one. [hole] marks instances that make their shapes transparent:
    renderers blend them with a source factor of zero. *)
type batch = {
  scissor : scissor;
  image : Lui_scene.image option;
  fx : Lui_scene.fx option;
  backdrop : Lui_scene.backdrop option;
  hole : bool;
  instances : instance list;
}

(** What a pass computing a backdrop reads: down reads the area from
    [origin] to [limit], frame pixels, at their place less [shift] in
    its source, and averages squares of [down] pixels a side; blur
    reads texels up to [limit], [radius] of them each way along [dir],
    weighted by a Gaussian of standard deviation [sigma]. [pad] keeps
    the layout a whole float4. *)
type pass = {
  origin : int * int;
  limit : int * int;
  shift : int * int;
  dir : int * int;
  down : int;
  radius : int;
  sigma : float;
  pad : float;
}

val down_pass : Lui_scene.backdrop -> shift:int * int -> pass
(** The pass averaging the squares of the backdrop's area, whose frame
    pixel (x, y) is at (x, y) less [shift] in the texture it reads. *)

val blur_pass : Lui_scene.backdrop -> int * int -> pass
(** The pass blurring the backdrop's texels along rows (dir 1, 0) or
    columns (0, 1). *)

val backdrop_size : batch list -> int * int
(** How large the textures of the batches' backdrops must be, in
    texels: as the largest. *)

val build : ?wide:bool -> Lui_scene.t -> batch list
(** Turn the ops of a scene into batches of instances.

    [wide] (default false) draws the colors of ops and glyphs outside
    the sRGB gamut (the scene's wide list) in place of their nearest
    sRGB colors, for a target that keeps them. *)

val to_float32_array : instance -> float array
(** The packed layout of one instance for the instance buffer — rect,
    radii, inner, color, color2, border, grad, uv, clip, clip_radii,
    params, clip2, clip2_radii, clip3, clip3_radii — rounded to
    float32. *)

val shader_source : string
(** The shader of shader.glsl, verbatim, as data. *)
