(** Text engine: font lookup, shaping and glyph rasterization.

    The platform's own text stack implements this interface (this module
    uses DirectWrite, the stack Windows draws with). The engine finds
    fonts, falls back to other fonts for
    glyphs the requested one lacks, breaks paragraphs into lines, and
    rasterizes glyphs into bitmaps ready for [Lui_scene.Atlas.put].

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
  rcolor : int option;  (** ink color a {!span} set, packed
                            [0xRRGGBBAA]; [None] keeps the caller's
                            default *)
  under : int;  (** underline style a {!span} set (0 none, 1 single,
                    2 thick, 9 double); painting it is the caller's
                    job *)
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

(** {2 Editing model: spans, graphemes, layout, carets}

    The rest of this module is what editable text needs: grapheme
    cluster segmentation, styled spans, a laid-out view of a string
    ([layout]) that hit-testing, caret placement and selection
    highlights all agree on, UTF-16 index mapping, truncation, and a
    bounded layout cache.

    Only [graphemes], [shape_spans] and [truncate] are engine hooks.
    Everything else works on the [line]/[run]/[glyph] records above,
    so a Pango or DirectWrite backend reuses the whole model by
    implementing the same hooks behind its own module.

    Not covered yet (each needs machinery beyond the current engine
    surface): OpenType feature settings (a feature vocabulary and
    per-span feature dicts), strikethrough (no engine attribute —
    paint it as an overlay), a mutable text buffer (its own
    subsystem), and bidi caret affinity (one byte index maps to two
    visual caret spots at a direction boundary — [caret_rect] picks
    the position before the following unit). *)

(** {3 Span styling} *)

type span_style = {
  sfont : font option;  (** replaces the base font (size is a font
                            property, so size changes come through it) *)
  scolor : int option;  (** ink color packed [0xRRGGBBAA] *)
  skern : float;  (** extra advance after each glyph, points —
                      letter-spacing *)
  sunder : int;  (** underline style: 0 none, 1 single, 2 thick,
                     9 double *)
}

val default_style : span_style
(** No overrides. *)

type span = {
  text : string;      (** the string the spans describe — shared by
                          every span of one [shape_spans] call *)
  style : span_style;
  range : int * int;  (** byte range [start, stop) of [text] *)
}
(** A styled byte range of a paragraph. *)

val span_text : span list -> string
(** The shared text of a span list ([""] when empty). *)

val shape_spans : ?width:float -> ?rtl:bool -> font -> span list ->
  line array
(** [shape_spans ?width ?rtl f spans] lays out [span_text spans] like
    {!shape}, then applies each span's style to its byte range.
    Uncovered bytes use [f] and no color/underline; ranges may overlap,
    later spans win per attribute. Runs coming back carry the
    effective {!run.rcolor} and {!run.under} per range, and their
    [font] is the span's [sfont] where set. *)

(** {3 Grapheme clusters} *)

val graphemes : string -> int array
(** [graphemes s] is the sorted array of byte offsets where grapheme
    clusters start or end: it holds [0] and [String.length s], so
    consecutive entries delimit the clusters. Caret positions and hit
    results always land on these boundaries — combining marks, emoji
    ZWJ chains, regional indicator pairs and Hangul syllables are
    never split. *)

(** {3 Layout} *)

type rect = { rx : float; ry : float; rw : float; rh : float }
(** A rectangle in layout coordinates, points. (Every record below
    uses its own field names: OCaml resolves an unannotated label to
    the newest record defining it, so shared names would misdirect
    callers.) *)

type cunit = private {
  cs : int;   (** byte start *)
  ce : int;   (** byte stop *)
  cx0 : float;  (** left edge of the drawn interval, line coords *)
  cx1 : float;  (** right edge *)
  crtl : bool;  (** direction of the run that produced it *)
  cnl : bool;   (** the trailing newline pseudo-unit *)
}
(** An indivisible caret unit: a byte range the caret enters only at
    its edges. Units exist where a grapheme boundary and a
    shaping-cluster boundary coincide, so a ligature (several
    graphemes, one glyph cluster) and a multi-glyph grapheme (an emoji
    drawn by several glyphs) both stay whole. *)

type line_layout = private {
  ll_line : line;      (** the shaped line *)
  ll_top : float;      (** its top edge in layout coordinates *)
  ll_height : float;   (** ascent + descent + leading *)
  ll_baseline : float; (** its baseline's y in layout coordinates *)
  ll_units : cunit array;  (** caret units, byte-sorted; a trailing
                               [cnl] unit, when present, covers the
                               line's [\n] *)
}

type layout = private {
  lay_text : string;
  lay_wrap : float;     (** the wrap width the lines were shaped at *)
  lay_rtl : bool;       (** base direction *)
  lay_base : font;      (** the base font *)
  lay_lines : line_layout array;
  lay_width : float;    (** widest line width *)
  lay_height : float;   (** total of the lines' heights *)
  lay_breaks : int array;  (** the grapheme boundaries the units were
                               built against *)
}
(** A string laid out for editing: the shaped lines stacked with
    vertical positions, plus the caret units hit-testing and
    selection use. All coordinates are points from the layout's
    top-left; they stay fractional so subpixel glyph positions drive
    hit-testing exactly. *)

val layout : ?width:float -> ?rtl:bool -> ?breaks:int array -> font ->
  string -> layout
(** [layout f s] shapes [s] ({!width}/{!rtl} as in {!shape}) and stacks
    its lines. [breaks] overrides the cluster table (tests and
    foreign segmenters); default is {!graphemes}. *)

val layout_spans : ?width:float -> ?rtl:bool -> ?breaks:int array ->
  font -> span list -> layout
(** [layout_spans f spans] is {!layout} over {!shape_spans}. *)

val layout_of_lines : ?breaks:int array -> ?width:float -> ?rtl:bool ->
  font -> string -> line array -> layout
(** [layout_of_lines f s lines] stacks already-shaped [lines] — what
    caches and tests use to reuse a [shape] result. *)

(** {3 Caret, hit-testing, selection} *)

val hit_test : layout -> float * float -> int
(** [hit_test lay (x, y)] is the byte index a caret would take at
    point [(x, y)]: the grapheme boundary nearest the point inside the
    line containing [y]. Points outside resolve to the nearest line
    and the nearest unit edge — the result is always a valid caret
    position, never inside a cluster. *)

val caret_rect : layout -> int -> rect
(** [caret_rect lay i] is the zero-width rect of the caret at byte
    index [i] (clamped to the text): inside a cluster it snaps to the
    nearer edge; at a wrapped line's shared bound it lands on the next
    line. [x] is fractional. *)

val selection_rects : layout -> int * int -> rect list
(** [selection_rects lay (a, b)] is the highlight of the byte range
    [a, b]: one or more rects per line. Covered units merge while
    their intervals touch, so a unit left out between two covered ones
    — a bidi gap — stays a gap. A selection reaching a line's [\n]
    extends a half-em rect past the line's end. *)

(** {3 Caret movement} *)

val caret_before : layout -> int -> int
(** [caret_before lay i] is the caret position before [i] — the
    previous grapheme boundary, across cluster interiors and newlines. *)

val caret_after : layout -> int -> int
(** [caret_after lay i] is the caret position after [i]. *)

val caret_up : layout -> int -> int
val caret_down : layout -> int -> int
(** [caret_up]/[caret_down] move to the caret position on the
    previous/next line that keeps the caret's x; at the document
    edges they clamp to the string's ends. *)

(** {3 UTF-16 index mapping} *)

val utf16_length : string -> int
(** [utf16_length s] is the length of [s] in UTF-16 code units. *)

val utf16_of_byte : string -> int -> int
(** [utf16_of_byte s i] is the UTF-16 code-unit offset of byte [i]
    (clamped). Malformed bytes count as one U+FFFD each, matching the
    engine's decoder. *)

val byte_of_utf16 : string -> int -> int
(** [byte_of_utf16 s u] is the byte offset of the character owning
    UTF-16 code unit [u] (a surrogate's second half maps to its
    character's start; [u] past the end maps to the string's length). *)

(** {3 Truncation} *)

val truncate : ?mode:[ `End | `Start | `Middle ] -> ?rtl:bool ->
  width:float -> font -> string -> line option
(** [truncate ~width f s] is [s]'s first paragraph shrunk to one line
    of at most [width] points, with the engine's ellipsis token
    spliced where [mode] says ([`End] default). [None] for an empty
    string or non-positive width. Token glyphs report a [cluster] at
    the string's end. *)

(** {3 Bounded layout cache} *)

module Cache : sig
  type t
  (** An LRU over (text, wrap, direction, font, span signature) →
      {!layout}. Measure-first: {!measure} populates the same entry a
      later {!layout} reuses, so the common editing path
      (measure on every frame, layout when painted) pays one shape. *)

  val create : ?max_bytes:int -> int -> t
  (** [create cap] bounds the cache to [cap] entries. Entries whose
      text exceeds [max_bytes] (default 64 KiB) are built but not
      kept: a giant paragraph can't evict everything else. *)

  val layout : t -> ?rtl:bool -> ?width:float -> font -> string ->
    layout
  val layout_spans : t -> ?rtl:bool -> ?width:float -> font ->
    span list -> layout
  (** The cached builders; on a miss they shape like the top-level
      functions. *)

  val measure : t -> ?rtl:bool -> ?width:float -> font -> string ->
    float * float
  (** [measure] is the entry's extent — a hit costs no shaping. *)

  val set_version : t -> int -> unit
  (** [set_version c v] drops every entry when [v] differs from the
      cache's version — bump it when the glyph atlas version changes,
      since entries hold glyph identities the atlas invalidated. *)

  val version : t -> int
  (** The atlas version the entries were built against. *)

  val stats : t -> int * int
  (** (hits, misses). *)

  val length : t -> int
  (** Live entries. *)

  val clear : t -> unit
end
