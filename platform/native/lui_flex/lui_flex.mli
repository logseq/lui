(* Flexbox layout engine for the native backend.

   A node tree with per-node style inputs is built with {!create};
   {!compute_layout} resolves every node to a concrete rectangle.
   Leaf nodes may carry a {!measure} callback so external systems
   (text shaping, images) can report intrinsic sizes. *)

(** Undefined dimension sentinel. Every size that was not specified
    in a style or yielded by layout is [undefined] (NaN). *)
val undefined : float

val is_undefined : float -> bool
val is_defined : float -> bool

(** A length specification: [Auto] defers to the algorithm (and on
    margins means "absorb a share of the free space"), [Pt v] is a
    concrete value, [Percent p] resolves against the containing
    block's inner size, [Unset] is no value at all. *)
type length =
  | Unset
  | Auto
  | Pt of float
  | Percent of float

(** Per-edge spacing specification (margin/padding/border) plus the
    position offsets [top]/[right]/[bottom]/[left]. *)
type edges = {
  left : length;
  right : length;
  top : length;
  bottom : length;
  start : length;
  end_ : length;
  horizontal : length;
  vertical : length;
  all : length;
}

val edges_auto : edges
val edges_all : length -> edges
val edges_xy : h:length -> v:length -> edges
val edges_ltrb : left:length -> top:length -> right:length -> bottom:length -> edges

type direction =
  | Inherit
  | Ltr
  | Rtl

type flex_direction =
  | Column
  | Column_reverse
  | Row
  | Row_reverse

type justify =
  | Justify_flex_start
  | Justify_center
  | Justify_flex_end
  | Justify_space_between
  | Justify_space_around
  | Justify_space_evenly

type align =
  | Align_auto
  | Align_flex_start
  | Align_center
  | Align_flex_end
  | Align_stretch

type position_type =
  | Relative
  | Absolute

type wrap_type =
  | No_wrap
  | Wrap

type overflow =
  | Visible
  | Hidden
  | Scroll

(** Measure modes handed to a {!measure} callback: [Measure_undefined]
    means the leaf may pick any size, [Measure_exactly] forces the
    given size, [Measure_at_most] caps it. [Measure_invalid] only marks
    internal cache entries and is never passed to a callback. *)
type measure_mode =
  | Measure_undefined
  | Measure_exactly
  | Measure_at_most
  | Measure_invalid

type dims = {
  width : float;
  height : float;
}

type rect = {
  x : float;
  y : float;
  w : float;
  h : float;
}

(** The complete style input for one node. *)
type style = {
  direction : direction;
  flex_direction : flex_direction;
  justify_content : justify;
  align_content : align;
  align_items : align;
  align_self : align;
  position_type : position_type;
  flex_wrap : wrap_type;
  overflow : overflow;
  flex_grow : float;
  flex_shrink : float;
  flex_basis : length;
  width : length;
  height : length;
  min_width : length;
  min_height : length;
  max_width : length;
  max_height : length;
  margin : edges;
  padding : edges;
  border : edges;
  position : edges;
  row_gap : length;
  column_gap : length;
}

val default_style : style

type node

(** [measure node ~width ~width_mode ~height ~height_mode] reports the
    leaf's intrinsic size for the offered size and modes. *)
type measure =
  node -> width:float -> width_mode:measure_mode ->
  height:float -> height_mode:measure_mode -> dims

(** [create ?style ?measure children] builds a node. A measure node
    must be a leaf: [measure] with a non-empty children list raises
    [Invalid_argument]. *)
val create : ?style:style -> ?measure:measure -> node list -> node

val children : node -> node list
val parent : node -> node option
val set_style : node -> style -> unit
val mark_dirty : node -> unit
val has_new_layout : node -> bool
val clear_new_layout : node -> unit

(** [compute_layout node ~width ~height ?direction] runs the full
    layout pass on [node]'s subtree. [width]/[height] are the offered
    size (pass [undefined] to measure it). *)
val compute_layout :
  node -> width:float -> height:float -> ?direction:direction -> unit -> unit

(** The node's resolved box relative to its parent's content box. *)
val layout : node -> rect

(** The node's resolved box in absolute coordinates, relative to the
    tree root's content box origin. *)
val absolute_layout : node -> rect

val iter : (node -> unit) -> node -> unit
