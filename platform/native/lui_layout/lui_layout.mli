(* Glue between the retained store and the flex engine: mirrors a
   [Lui_store.t] into a [Lui_flex] tree, runs layout, and serves the
   placement hook that [Lui_paint.hooks.layout] consumes.

   Coordinate space: the returned placements are device px in the frame
   coordinate space — the same space the scene and paint use. Wire
   lengths are logical px and are multiplied by the frame [scale] as
   they become flex style values, so flex output lands in device px
   already and paint can use each [p_rect] unmodified (see
   [resolve_rect] in lui_paint.ml: with [p_override = None] and no
   position/inset props, [p_rect] is the emitted scene rect; the
   children of a node are resolved against that same absolute rect).

   Only new files live in this directory; nothing else is touched. *)

(** Text measure function the host injects: [id text offered_w
    offered_h] reports the intrinsic size of [text] on node [id] in
    device px. Offered dims may be NaN when the engine leaves the axis
    unconstrained; [None] means "no intrinsic size" (layout falls back
    to a zero box). *)
type text_measure = int -> string -> float -> float -> (float * float) option

(** A flex mirror of a store plus the rects the last layout produced.
    The mirror is rebuilt wholesale by {!sync} — the store is small and
    rebuild-per-sync keeps invalidation trivial. *)
type t

val create : unit -> t

(** [style_of ?scale ?viewport store id] translates the node's wire kind
    and props into a flex style. Parent-driven adjustments (overlay
    children, grid cells, edge-inset ordering) are applied by {!sync},
    not here — this function only sees the node's own kind and props.
    [viewport] is the frame size in device px, used to resolve the
    [*-viewport] props; without it they degrade to parent-relative
    percents. *)

val style_of :
  ?scale:float -> ?viewport:float * float ->
  Lui_store.t -> int -> Lui_flex.style

(** [measure_of tm ~id ~text] builds the flex [measure] callback for one
    text leaf. The flex callback hands back only the engine's own node,
    which carries no store id, so the builder binds the store id and the
    string being measured per leaf. Modes map onto the offered dims:
    [Measure_undefined] surfaces as an undefined offered value; the
    other modes pass the engine's inner size through. *)

val measure_of :
  text_measure -> id:int -> text:string -> Lui_flex.measure

(** [sync ?scale ?measure ~width ~height t store] rebuilds the flex
    mirror from the store's current structure and runs layout for a
    [width]x[height] device-px frame. Root-level nodes that are not
    popup surfaces get [flex_grow = 1] so they fill the frame;
    [display:none] nodes are skipped entirely and [display:contents]
    nodes lift their children into the parent flow. *)

val sync :
  ?scale:float -> ?measure:text_measure ->
  width:float -> height:float -> t -> Lui_store.t -> unit

(** [compute t ~width ~height] re-runs layout on the current mirror —
    the cheap path when only the frame size changed. [*-viewport]
    props keep the resolution from the last {!sync}; call {!sync} on
    resize when any node uses them. *)

val compute : t -> width:float -> height:float -> unit

(** [layout_hook t id] is the [Lui_paint.hooks.layout] implementation:
    the node's computed rect in frame device px, [p_override = None].
    Unknown ids (dropped nodes, [display:none]) get a zero rect. *)

val layout_hook : t -> int -> Lui_paint.placement

(** [rect t id] is the node's current layout rect — the hit-testing
    surface. [None] for ids the mirror skipped. *)

val rect : t -> int -> Lui_scene.rect option

(** [run ?scale store ~measure ~width ~height] is the one-shot hook for
    [Lui_host]: mirror + layout + the placement function. The
    [~measure] here is the id-keyed host form; the mirror picks the
    string itself ([text], falling back to [placeholder] when text is
    empty or absent). Hosts that also want {!rect} for hit-testing keep
    a [t] and go through {!create}/{!sync}/{!layout_hook} instead. *)

val run :
  ?scale:float -> Lui_store.t ->
  measure:(int -> float -> float -> (float * float) option) ->
  width:float -> height:float -> (int -> Lui_paint.placement)

(* Scroll offset composition (documented contract — this module does
   not apply scroll offsets):

   Layout rects are content-space positions: a scroll container's
   children are laid out where they would sit with zero scroll. The
   paint pass clips them to the container's clip rect, so scrolling is
   purely a translation of the subtree. To implement it, the host wraps
   [layout_hook]: for a node inside a scroll container, subtract the
   container's current scroll offset (device px) from the placement —
   i.e. shift [p_rect.y] (or [x] for horizontal scrollers) by the
   offset each ancestor scroll container reports. The scrollbar chrome
   comes from [hooks.scroll_of], whose fractions the host derives from
   the same two numbers this module exposes: the container's own rect
   (viewport size) and the laid-out content extent of its subtree
   (union of the descendant rects) — [sm_extent = viewport / content],
   [sm_offset = offset / (content - viewport)]. *)
