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
    ?scale:float -> ?measure:text_measure ->
    width:float -> height:float -> t -> Lui_store.t -> unit

  val layout_hook : t -> int -> Lui_paint.placement

  val rect : t -> int -> Lui_scene.rect option
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

val backend : t -> Lui_protocol.platform_profile -> Lui_protocol.backend
