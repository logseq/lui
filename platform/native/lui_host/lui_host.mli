(* Native backend assembly: a Lui_protocol.backend whose apply_batch
   mirrors patches into the store and schedules a repaint, plus the
   paint→render pipeline shared by the window loop and headless tests.

   The window/event loop lives in the app driver; this module is the
   pure part: apply → layout → paint → pixels, so headless tests can
   drive it without a display. *)

(* A renderer evaluates a scene into pixels (CPU today, GL later). *)
type renderer = {
  render : Lui_scene.t -> Bytes.t; (* premultiplied BGRA, width*height*4 *)
  name : string;
}

(* Text measure the host forwards to the layout engine on every sync:
   [id text offered_w offered_h] reports the intrinsic size of [text]
   on node [id] in device px. Offered dims may be NaN when the engine
   leaves the axis unconstrained; [None] means "no intrinsic size". *)
type text_measure = int -> string -> float -> float -> (float * float) option

(* The slice of a layout engine the host drives. [Lui_layout]
   satisfies this signature; declaring it here keeps the host decoupled
   from the concrete engine. *)
module type LAYOUT_ENGINE = sig
  type t

  val create : unit -> t

  val sync :
    ?scale:float -> ?measure:text_measure -> ?hidden:(int -> bool) ->
    ?ctx_anchor:(float * float) ->
    ?vport:(int -> (float * float) option) ->
    width:float -> height:float -> t -> Lui_store.t -> unit

  val invalidate : t -> unit
  (** Drop any cached layout state so the next {!sync} rebuilds — see
      {!Lui_host.invalidate_layout}. *)

  val layout_hook : t -> int -> Lui_paint.placement

  val rect : t -> int -> Lui_scene.rect option

  (* Virtual-list surface: engines without virtualization return
     [[]]/[None] everywhere, which reproduces the unwindowed path. *)
  val vlists : t -> int list
  val mounted_range : t -> int -> (int * int) option
  val mounted_children : t -> int -> int list option
  val virtual_extent : t -> int -> float option
  val virtual_item_rect : t -> int -> index:int -> Lui_scene.rect option
  val virtual_index_of_key : t -> Lui_store.t -> int -> string -> int option
  val virtual_index_of_id : t -> Lui_store.t -> int -> int -> int option
  val virtual_view : t -> int -> (float * float) option

  (** Pending anchor correction in device px, consume-on-read: how far
      the row at the viewport top moved because rows above it measured
      off-estimate. Add it to the list's scroll offset. *)
  val virtual_take_drift : t -> int -> float

  (** Store ids whose absolute rect changed under the last {!sync};
      drained by the paint pass to re-emit only moved subtrees. *)
  val take_rect_changes : t -> (int, unit) Hashtbl.t
end

type t

val create :
  hooks:Lui_paint.hooks ->
  ?layout:(module LAYOUT_ENGINE) ->
  ?measure:text_measure ->
  renderer:renderer -> width:int -> height:int -> scale:float ->
  unit -> t
(** [create ~hooks ~renderer ~width ~height ~scale ()] builds a host
    holding a fresh store and scene.

    Layout: pass [~layout:(module Lui_layout)] — the production path —
    and the host owns an engine it re-syncs inside every {!repaint},
    before {!Lui_paint.paint} runs. Syncing per repaint (not per batch)
    is the cheap-correct choice: several batches may land between
    paints, and resize only marks dirty, so the engine must always see
    the current store and frame size at paint time. [?measure] is
    forwarded to each sync — production callers wire a real text
    measure (e.g. backed by [Lui_text.measure]), tests a deterministic
    stub.

    The engine's placement hook replaces [hooks.layout] only while that
    field is still {!Lui_paint.default_hooks.layout}; an explicitly
    supplied [hooks.layout] always wins, so [~hooks] overrides keep
    working — the engine still syncs, keeping {!layout_rect} fresh.

    Hit-testing (the window driver): do NOT keep a second engine —
    query laid-out rects through {!layout_rect}. Scroll-offset
    composition wraps the same placements, per the engine module's
    documented contract. *)

val store : t -> Lui_store.t
val scene : t -> Lui_scene.t
val wants_repaint : t -> bool

val set_hidden : t -> (int -> bool) option -> unit
(** Host-owned transient visibility: [pred id] returns true for store
    nodes the layout engine should skip entirely (closed menu panels).
    [None] clears the predicate. Marks the host dirty so the change
    lands on the next repaint. *)

val set_ctx_anchor : t -> (unit -> (float * float) option) option -> unit
(** Host-owned popup anchor: the accessor returns the pointer point
    (frame px) an unanchored [context-menu] opens at, read live on each
    repaint. [None] clears it — context menus then fall back to their
    containing block. *)

val invalidate_layout : t -> unit
(** Force the layout engine's next sync to rebuild. Layout memoizes on
    the store's mutation revision plus the frame and input identities,
    so this is only needed when a function input keeps its identity
    but changes its answers — e.g. a text measure whose font stack
    finished loading, or a [hidden] predicate whose captured state
    flipped without going through {!set_hidden}. Store edits never
    need it — every applied op already bumps the revision the memo
    keys on, and sync always runs between batches, so the memo can
    never observe a half-applied tree. *)

val invalidation_count : t -> int
(** Monotonic counter bumped by every host-side input that can move
    layout output without a store revision: {!invalidate_layout},
    {!resize}, {!set_hidden}, {!set_ctx_anchor}. Epoch keys that must
    stay honest about resolved geometry mix it in. *)

val note_paint : t -> int -> unit
(** [note_paint h id] marks a node whose host-side paint inputs
    changed outside the store — interaction state the hooks report,
    an image that finished decoding. The next {!repaint} re-derives
    the fragment instead of replaying its cached ops. *)

val note_paints : t -> int list -> unit

val note_moved : t -> int -> unit
(** [note_moved h id] marks a node whose emitted rect shifted under
    unchanged props and state — a scroll subtree, a translated
    overlay. The next repaint may slide its cached ops instead of
    re-planning them. *)

val note_moveds : t -> int list -> unit

val invalidate_paint : t -> unit
(** Drop every cached paint fragment — the wholesale counterpart of
    {!note_paint} for inputs that moved globally (a theme swap under
    a stable store). *)

val apply_batch : t -> Lui_protocol.patch_batch -> bool

val resize : t -> width:int -> height:int -> scale:float -> unit

val repaint : t -> Bytes.t
(** Syncs the layout engine (when present) on the current store, runs
    the paint pass and renders the scene; clears the dirty flag and
    returns the frame's premultiplied-BGRA bytes. *)

val layout_rect : t -> int -> Lui_scene.rect option
(** [layout_rect h id] is the node's rect from the last engine sync —
    the hit-testing surface for the window driver. [None] when the host
    has no engine or the mirror skipped the id. *)

val set_vport : t -> (int -> (float * float) option) -> unit
(** Install the virtual-list viewport feed: [f id] reports the node's
    content-space visible range (start, extent, device px) — the scroll
    offset for a directly-scrolled list, or the on-screen clip mapped
    into the list's content when an outer scroller clips it. Evaluated
    inside every engine sync, including memo hits. *)

(** {2 Virtual lists}

    Forwards to the layout engine's virtual-list surface; all answer
    [[]]/[None] when no engine is installed. *)

val layout_vlists : t -> int list
val layout_mounted_range : t -> int -> (int * int) option
val layout_mounted_children : t -> int -> int list option
val layout_virtual_extent : t -> int -> float option
val layout_virtual_item : t -> int -> index:int -> Lui_scene.rect option
val layout_virtual_index_of_key : t -> int -> string -> int option
val layout_virtual_index_of_id : t -> int -> int -> int option
val layout_virtual_view : t -> int -> (float * float) option

(** Consume-on-read anchor correction in device px; the driver adds it
    to the list's scroll offset so the top row keeps its screen
    position while variable heights settle. *)
val layout_take_drift : t -> int -> float

val backend : t -> Lui_protocol.platform_profile -> Lui_protocol.backend
