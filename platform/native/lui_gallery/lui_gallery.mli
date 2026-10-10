(* Headless visual-exercise gallery for the native backend.

   Builds one retained tree that exercises every standard LUI kind's
   painted form (plus one registered extension kind), lays it out with
   the real flex engine through [Lui_host], paints it with [Lui_paint],
   rasterizes with [Lui_raster] and writes PNG evidence files: one
   labelled master grid plus one PNG per cell.

   Determinism: every host-facing hook is a deterministic stub (text
   becomes little glyph-shaped rectangles, images are a fixed generated
   bitmap, theme names resolve through a fixed table), so the same
   input produces byte-identical pixels on any platform. A real text
   engine can replace the stub via [hooks_of] for prettier output. *)

open Lui_protocol
open Lui_scene

(* ---------- node specs ---------- *)

(* A declarative node template: kind, props, children and the per-node
   hook state the paint pass reads back. [cov] marks the node whose
   kind is claimed for coverage; [tag] names the node so the driver
   can recover its store id and layout rect. *)
type spec = {
  nk : node_kind option;      (* None with [ext] -> extension node *)
  ext : string option;        (* extension identifier *)
  props : (property * wire_value) list;
  xprops : (string * wire_value) list; (* extension prop names, e.g. "border-style" *)
  kids : spec list;
  st : Lui_paint.state option;   (* forced interaction state for hooks.state_of *)
  scroll : Lui_paint.scroll_metrics option; (* scrollbar fractions *)
  img : bool;                    (* hooks.image_of answers the test bitmap *)
  tag : string option;
  cov : bool;
}

(* ---------- emitted manifest ---------- *)

type emitted = {
  mutable ops : patch_op list;
  ids : (string, int) Hashtbl.t;      (* tag -> node id *)
  mutable covered : (string * int) list; (* wire kind name -> tagged node id *)
  states : (int, Lui_paint.state) Hashtbl.t;
  scrolls : (int, Lui_paint.scroll_metrics) Hashtbl.t;
  images : (int, unit) Hashtbl.t;
}

(* ---------- cell manifest ---------- *)

type cell = {
  cname : string;   (* file slug, unique *)
  ckind : string;   (* headline kind for the report *)
  cnote : string;   (* one-line description *)
  cnode : spec;     (* cell subtree: caption + stage + subject *)
}

type gallery = {
  root : spec;
  cells : cell list;
  columns : int;
  frame_w : int;
}

(* ---------- spec helpers ---------- *)

val sv : string -> wire_value
val fv : float -> wire_value
val iv : int -> wire_value
val bv : bool -> wire_value

val n :
  node_kind ->
  ?props:(property * wire_value) list ->
  ?xprops:(string * wire_value) list ->
  ?kids:spec list ->
  ?st:Lui_paint.state ->
  ?scroll:Lui_paint.scroll_metrics ->
  ?img:bool ->
  ?tag:string ->
  ?cov:bool ->
  unit -> spec

val spec_node_kind : spec -> string

(* Emit a spec forest as one patch batch; fills the [emitted] maps. *)
val emit : spec -> emitted

(* Deterministic per-node test bitmap (premultiplied RGBA, 24x24). *)
val test_image : image

(* Deterministic hooks: theme table, fixed states/scrolls/images, the
   glyph-rectangle text stub and the real shadow parser. *)
val color_of : string -> color option
val stub_text_ops : int -> rect -> color -> string -> op list
val stub_measure : Lui_host.text_measure

val hooks_of :
  ?text_ops:(int -> rect -> color -> string -> op list) ->
  emitted -> Lui_paint.hooks

(* ---------- cell catalog ---------- *)

(* Every cell in the gallery, in paint order. The subject of each cell
   is tagged ["subject:<cname>"]; the node claimed for kind coverage
   carries the wire kind name in [emitted.covered]. *)
val cells : cell list

(* Wrap a cell's subject into the caption + stage cell shell. *)
val wrap_cell : cell -> spec

(* The whole gallery root spec: page column -> category sections ->
   4-column grids of wrapped cells. *)
val build_gallery : unit -> gallery

(* ---------- render pipeline ---------- *)

type frame = {
  host : Lui_host.t;
  emitted : emitted;
  mutable img : Lui_raster.Image.t option;
  mutable fwidth : int;
  mutable fheight : int;
}

(* Build the store, lay out at a probe height, measure the content
   bottom, re-layout at the exact frame height and render.
   [~text_ops]/[~measure] swap the deterministic text stub for a real
   engine. [~workers] drives raster row teams; 1 is the deterministic
   default. *)
val render :
  ?text_ops:(int -> rect -> color -> string -> op list) ->
  ?measure:Lui_host.text_measure ->
  ?post_create:(Lui_host.t -> unit) ->
  ?workers:int ->
  unit -> frame

val cell_rect : frame -> cell -> rect
val stage_rect : frame -> cell -> rect

(* ---------- image conversion ---------- *)

(* Premultiplied BGRA frame -> straight RGBA8 bytes (w*4 per row). *)
val rgba_bytes : Lui_raster.Image.t -> Bytes.t

(* Crop a rect (device px, clamped to the image) out of RGBA bytes. *)
val crop : Bytes.t -> w:int -> rect -> int * int * Bytes.t

(* PNG encode straight RGBA8 through imagelib and write [path]. *)
val write_png : string -> w:int -> h:int -> Bytes.t -> unit

val mkdir_p : string -> unit

(* ---------- output ---------- *)

(* Write the master grid PNG, one PNG per cell and the markdown
   manifest into [out_dir]. Returns the file list (relative names). *)
val write_gallery : frame -> out_dir:string -> string list

(* Paint each standard kind alone (no props, no children, fixed
   96x36 rect) and count the ops it emits — the "own chrome" probe
   backing the no-visual-output report. *)
val probe_own_ops : unit -> (string * int) list
