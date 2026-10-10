(** Text engine: font lookup, shaping and glyph rasterization.

    The platform's own text stack implements this interface (this module
    uses DirectWrite, the stack Windows draws with). The engine finds
    fonts, falls back to other fonts for glyphs the requested one lacks,
    breaks paragraphs into lines, and rasterizes glyphs into bitmaps
    ready for [Lui_scene.Atlas.put].

    Units: font sizes, metrics, advances and glyph positions are points
    (density-independent pixels); bitmaps, [left]/[top]/[w]/[h] and
    [scale] are device pixels. Strings are UTF-8: [start], [stop] and
    [cluster] are byte offsets into the string that was shaped. *)

type font
(** A platform font at a fixed size. Fonts are usable as map and hash
    keys: [compare], [=] and [Hashtbl.hash] follow the engine's own font
    identity, so a font and the run font it shaped with compare equal. *)

type metrics = private {
  size : float;
  ascent : float;   (** height above the baseline *)
  descent : float;  (** depth below the baseline *)
  leading : float;  (** extra gap between lines *)
  line_height : float;  (** ascent + descent + leading *)
}

val create : ?families:string list -> ?weight:int -> ?italic:bool ->
  size:float -> unit -> font
(** [create ~size ()] is a font collection at [size]: the first family of
    [families] the system has, at that size, with the rest of the list
    coming before the system's own fallbacks for glyphs it lacks.

    [families] entries are family names (a comma-separated list inside
    one entry is split); the generic names ["system-ui"], ["sans-serif"],
    ["serif"] and ["monospace"] (and their aliases) stand for the
    system's own choices. No usable family means the system font.

    [weight] is a CSS weight (100 thin .. 900 black; 400 regular);
    [italic] asks for the italic face. Returns the same font for the same
    arguments. *)

val system : ?weight:int -> ?italic:bool -> ?monospace:bool ->
  size:float -> unit -> font
(** The system's user-interface font (monospaced when [monospace]). *)

val fallback : font -> string -> font option
(** [fallback f s] is the font the system picks to cover the characters
    of [s] that [f] lacks. It may itself be a fallback chain; [None] when
    nothing can render [s]. *)

val metrics : font -> metrics
val size : font -> float
val family : font -> string
(** Best-effort installed family name ("" when unknown). *)

val is_color : font -> bool
(** [is_color f] holds when [f] is a color-glyph font (e.g. emoji); its
    glyphs rasterize to premultiplied BGRA instead of coverage masks. *)

type glyph = {
  id : int;        (** glyph id within [run]'s font *)
  x : float;       (** drawing origin, points from the line's pen start *)
  y : float;       (** offset below the baseline (shaping offset) *)
  advance : float; (** pen advance, independent of [x] *)
  cluster : int;   (** byte offset of the cluster's first character *)
}

type run = {
  font : font;  (** the font actually used — a fallback may differ *)
  start : int;  (** byte offset of the run's first character *)
  stop : int;   (** byte offset just past the run's last character *)
  rtl : bool;   (** the run is right-to-left *)
  glyphs : glyph array;
}

type line = {
  start : int;    (** byte offset of the line's first character *)
  stop : int;     (** byte offset just past its last; excludes [\n] *)
  width : float;  (** typographic width *)
  ascent : float;
  descent : float;
  leading : float;
  runs : run array;  (** split by font and direction, in paint order *)
}

val shape : ?width:float -> ?rtl:bool -> font -> string -> line array
(** [shape ?width ?rtl f s] lays out [s] as one or more paragraphs
    (embedded ['\n'] ends a paragraph). With [width] > 0 lines wrap at
    [width] points; 0 or omitted gives one line per paragraph. [rtl]
    sets the paragraphs' base direction. Each paragraph's lines carry
    runs of positioned glyphs; byte offsets are relative to [s]. *)

val measure : ?width:float -> ?rtl:bool -> font -> string ->
  float * float
(** [measure ?width ?rtl f s] shapes [s] and returns [(w, h)]: the widest
    line's width and the sum of the lines' heights
    (ascent + descent + leading each). *)

type bitmap = {
  left : int;   (** pixel offset of the box's left edge from the origin *)
  top : int;    (** pixel offset of the box's top edge from the baseline *)
  w : int;
  h : int;
  color : bool;     (** premultiplied BGRA when set, coverage mask else *)
  pixels : bytes;   (** top-first rows: [w*h] mask bytes or [w*h*4] BGRA *)
}
(** A rasterized glyph, ready for the atlas:
    [Atlas.put a ~x ~y ~w:b.w ~h:b.h ~src:b.pixels
      ~stride:(b.w * (if b.color then 4 else 1))].
    Draw the [w]×[h] box with its top-left at
    ([pen_x + left], [baseline + top]). *)

val rasterize : ?scale:float -> ?dx:float -> ?shade:float -> font ->
  int -> bitmap option
(** [rasterize ?scale ?dx ?shade f id] rasterizes glyph [id] of [f] at
    [scale] device pixels per point (default 1), with the glyph's pen
    [dx] (0 ≤ dx < 1) device pixels right of a pixel edge — cache keys
    for atlas entries should include [scale], the quantized [dx] and
    [shade].

    [shade] is the ink's relative luminance (0 black .. 1 white,
    default 1): platforms that thicken glyphs by fill luminance use it.
    [None] when the glyph has no ink or is too large. *)

val subpixel_positions : ?scale:float -> font -> int
(** [subpixel_positions ?scale f] is how many positions within a device
    pixel the platform draws [f]'s glyphs at — quantize fractional pen
    origins to [1/n] of a pixel for atlas reuse. *)

val baseline : float -> float
(** [baseline y] is the whole device pixel the platform draws a baseline
    [y] device pixels from the top at. *)
