(** Liquid-glass materials as {!Lui_scene} effects.

    Three materials, all drawn by the scene's [Effect] op: a {b glass}
    pane that blurs, lenses and rim-lights what shows through, a plain
    {b blur} that can fade along a mask (the progressive blur under a
    bar content scrolls beneath), and a {b scroll edge} wash that pairs
    the blur with a background gradient.

    Each material is a {!Lui_scene.fx}: its [eglsl] is one source every
    GPU backend compiles — as GLSL on OpenGL and Vulkan, mapped to HLSL
    by the Direct3D shim, and to the Metal language where
    [__METAL_VERSION__] is defined — and its [epixels] is the CPU twin
    the raster draws, which the parity harness holds to within a
    channel step of the shaders. The draw ops the helpers emit carry
    the material in the effect op's five params, so the instance
    encoding needs nothing new.

    The helpers are usable two ways: directly against a {!Lui_scene.t}
    under construction (they append to [scene.ops] and [scene.effects]),
    and as the ["plugin:glass"] service of the {!Lui_plugin} registry
    ({!plugin} below), which answers with the ops the helpers emit as
    JSON for a host to replay. The exported
    {!Lui_plugin_glass.glass_fx}/{!Lui_plugin_glass.blur_fx} records and
    the param layout below are the contract either way:

    - glass: [p0] = (bezel, refraction, rim, rim_width), [p1] = tint as
      straight sRGB floats, [p2] = (low, high, curve, saturation),
      [p3] = (light_x, light_y, 0, 0);
    - blur: [p0] = the mask line's From and To points, [p1] = (blur at
      From, blur at To, level lo, level hi), [p2] = tone (saturation,
      offset, mix, 0), [p3] = mix color (r, g, b, 1).

    Wire-level note: {!Lui_paint} has no free prop slot for materials
    (the only extension prop it reads today is [border-style]; data
    attrs belong to the host), so no mapping was added there — the
    materials are exposed through this module's API and the
    ["plugin:glass"] service, and any future protocol prop should map
    to the same param layout. *)

open Lui_scene

(** {1 The effects} *)

val glass_fx : fx
(** The glass effect: ename ["glass"], reads its backdrop. *)

val blur_fx : fx
(** The blur effect (one level of it per draw op): ename ["blur"],
    reads its backdrop. *)

(** {1 Glass} *)

type style =
  | Regular  (** Frosted; lightens in light mode, darkens in dark. *)
  | Clear  (** Barely blurs nor tones, for glass over photos. *)

type material = {
  mstyle : style;
  mtint : color;  (** Straight sRGB; applies at 88% of its alpha. *)
  minteractive : bool;
  mdark : bool;
}
(** The glass's material: its style, an optional tint, whether it
    grows when pressed, and the light or dark tone ramp for [Regular]. *)

val material :
  ?style:style ->
  ?tint:color ->
  ?interactive:bool ->
  ?dark:bool ->
  unit ->
  material

val glass :
  scene:t ->
  ?radii:float * float * float * float ->
  ?continuous:bool ->
  ?scale:float ->
  ?grow:float ->
  rect ->
  material ->
  unit
(** [glass ~scene ~radii ~scale ~grow rect m] appends a glass pane over
    [rect] (device pixels), rounded by per-corner [radii]. [scale] is
    the DIP-to-pixel factor, defaulting to [scene.scale] — the material's
    own sizes (bezel at most 36 DIPs, blur at most 10) are DIPs. [grow]
    is how far an interactive pane is pressed, 0 to 1; ignored unless
    [m.interactive]. *)

(** {1 Blur} *)

type fade = {
  ffrom : float;  (** Alpha at the gradient's start, 0-1. *)
  fto : float;  (** Alpha at its end, 0-1. *)
  fangle : float;  (** Degrees, CSS-linear-gradient direction. *)
  fstart : float;  (** Start along the line, 0-1. *)
  fstop : float;  (** End along the line, 0-1. *)
}
(** A progressive blur's mask: where the gradient is opaque the blur is
    full, where transparent none, by the gradient colors' alpha. *)

val fade :
  from:float ->
  to_:float ->
  ?angle:float ->
  ?start:float ->
  ?stop:float ->
  unit ->
  fade

type tone = {
  tsat : float;  (** Extra saturation, 0 for none. *)
  toff : float;  (** Added to each channel. *)
  tmix : float;  (** How much of [tcolor] mixes over. *)
  tcolor : float * float * float;  (** Straight sRGB floats. *)
}
(** What a blur level does to the colors it shows; [None] leaves them. *)

val blur :
  scene:t ->
  ?radii:float * float * float * float ->
  ?continuous:bool ->
  ?mask:fade ->
  ?tone:tone ->
  radius:float ->
  rect ->
  unit
(** [blur ~scene ~mask ~tone ~radius rect] appends a backdrop blur over
    [rect] (device pixels), of [radius] pixels standard deviation. With
    [mask] the blur fades along it and the helper emits one effect op
    per level of the fade — each reading the backdrop as the levels
    before it left it, which is what makes the fade smooth. *)

(** {1 Scroll edge} *)

val soft_edge : float
(** The background's alpha at the bar's edge, 0.85. *)

val hard_edge_blur : float
(** The hard edge's blur, 6.4 DIPs. *)

val scroll_edge :
  scene:t ->
  ?radii:float * float * float * float ->
  ?continuous:bool ->
  ?scale:float ->
  ?hard:bool ->
  ?bottom:bool ->
  ?bg:color ->
  ?dark:bool ->
  rect ->
  unit
(** [scroll_edge ~scene ~hard ~bottom ~bg ~dark rect] appends the
    scroll-edge effect over [rect]. Soft (default): a gradient of [bg]
    from 85% alpha at the bar's edge to none; hard: the content frosted
    by a toned blur under ~82% of [bg], plus a hairline along the far
    edge (black 10% light mode, white 7% dark). [bottom] puts the bar
    at the element's bottom. *)

(** {1 Math exposed for tests} *)

type blur_level = { lblur : float; llo : float; lhi : float }

val blur_levels : float -> float -> blur_level list
(** The levels of a blur varying from least to most pixels. *)

val mask_line : rect -> fade -> float * float * float * float

val blur_wanted :
  rect -> float * float * float * float -> float -> float -> float ->
  rect option
(** The whole-pixel bounds of the part of a rect where the blur along
    the mask is more than the level's lo. *)

val glass_lens : float -> float -> float
val glass_normal :
  float -> float -> rect -> float * float * float * float -> float * float
val luminance : float * float * float -> float
val toned : float * float * float -> float -> float -> float * float * float
val backdrop_sample4 : backdrop_image -> float -> float -> float * float * float * float

(** {1 The plugin service} *)

val plugin : Lui_plugin.t
(** The ["plugin:glass"] service descriptor: methods ["material"],
    ["blur"] and ["scroll_edge"], each running the OCaml helper of the
    same name and answering with the ops it emitted. Arguments are the
    helper's, as a JSON object — [rect] and [radii] as [x,y,w,h] and
    [tl,tr,br,bl] arrays (a bare number for a uniform radius), [tint]
    and [bg] as [r,g,b,a] byte arrays, a tone's [color] as straight
    sRGB floats, the rest by name — and the answer is
    [{"ops": [fill|effect op objects in paint order], "effects":
    [{name, eblur, params}]}], an effect op's ["effect"] being its slot
    index into ["effects"]. A host replays the doc against its own
    scene; the param layout above is the effect contract. *)
