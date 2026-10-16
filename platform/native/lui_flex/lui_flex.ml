(* Flexbox layout engine for the native backend.

   A pure-OCaml port of the classic cross-platform flexbox layout
   algorithm. A tree of styled nodes is resolved into pixel rects by
   [compute_layout]; every node then reports its (x, y, w, h) relative to
   its parent's border box through [layout] (or the tree root through
   [absolute_layout]).

   Scalars are floats; [nan] marks an unset value everywhere, which keeps
   every arithmetic operation branch-free and lets the compiler inline
   all dimension math. *)

let undefined = nan
let is_undefined (x : float) : bool = x <> x
let is_defined (x : float) : bool = x = x
let zero = 0.
let negativeOne = -1.
let divideScalarByInt (s : float) (i : int) : float = s /. float_of_int i

type edge =
  | Left
  | Top
  | Right
  | Bottom
  | Start
  | End

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

(* The invalid sentinel is used internally to clear cached measure modes;
   it is never passed to a measure callback. *)
type measure_mode =
  | Measure_undefined
  | Measure_exactly
  | Measure_at_most
  | Measure_invalid

type overflow =
  | Visible
  | Hidden
  | Scroll

type wrap_type =
  | No_wrap
  | Wrap

(* A dimension spec: points, percent of the owning node's inner
   dimension, auto, or unset. On margins, [Auto] additionally means
   "absorb a share of the free space", matching standard flexbox
   auto-margin behavior; [Unset] stays a plain zero margin. *)
type length =
  | Unset
  | Auto
  | Pt of float
  | Percent of float

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

(* Per-edge spec with the usual cascade: a concrete edge wins over its
   axis shorthand ([horizontal]/[vertical]), which wins over [all].
   [start]/[end_] are the logical (direction-dependent) inline edges. *)
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

let edges_auto =
  { left = Unset; right = Unset; top = Unset; bottom = Unset;
    start = Unset; end_ = Unset;
    horizontal = Unset; vertical = Unset; all = Unset }

let edges_all v = { edges_auto with all = v }
let edges_xy ~h ~v = { edges_auto with horizontal = h; vertical = v }
let edges_ltrb ~left ~top ~right ~bottom =
  { edges_auto with left; top; right; bottom }

(* Public style input. [Auto] marks "no value"; [Percent p] resolves
   against the owning node's inner width for width-like and inline
   properties (including vertical margins and padding, per the flexbox
   rules) and against the inner height for height-like properties. *)
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
  (* [row_gap] separates items along a column main axis and wrapped
     lines of a row container; [column_gap] separates items along a row
     main axis and wrapped lines of a column container. *)
  row_gap : length;
  column_gap : length;
}

let default_style : style = {
  direction = Inherit;
  flex_direction = Column;
  justify_content = Justify_flex_start;
  align_content = Align_flex_start;
  align_items = Align_stretch;
  align_self = Align_auto;
  position_type = Relative;
  flex_wrap = No_wrap;
  overflow = Visible;
  flex_grow = 0.;
  flex_shrink = 1.;
  flex_basis = Auto;
  width = Auto;
  height = Auto;
  min_width = Auto;
  min_height = Auto;
  max_width = Auto;
  max_height = Auto;
  margin = edges_auto;
  padding = edges_auto;
  border = edges_auto;
  position = edges_auto;
  row_gap = Pt 0.;
  column_gap = Pt 0.;
}

(* Internal resolved style: every [length] spec reduced to a scalar, plus
   per-field auto-margin flags that keep the edge cascade correct when a
   field is auto (auto fields carry scalar 0 so the cascade still treats
   them as present; readers consult the flags before the values). *)
type istyle = {
  direction : direction;
  flex_direction : flex_direction;
  justify_content : justify;
  align_content : align;
  align_items : align;
  align_self : align;
  position_type : position_type;
  flex_wrap : wrap_type;
  overflow : overflow;
  flex : float;
  flex_grow : float;
  flex_shrink : float;
  mutable flex_basis : float;
  mutable margin : float;
  mutable margin_vertical : float;
  mutable margin_horizontal : float;
  mutable margin_left : float;
  mutable margin_top : float;
  mutable margin_right : float;
  mutable margin_bottom : float;
  mutable margin_start : float;
  mutable margin_end : float;
  mutable margin_auto_all : bool;
  mutable margin_auto_vertical : bool;
  mutable margin_auto_horizontal : bool;
  mutable margin_auto_left : bool;
  mutable margin_auto_top : bool;
  mutable margin_auto_right : bool;
  mutable margin_auto_bottom : bool;
  mutable margin_auto_start : bool;
  mutable margin_auto_end : bool;
  mutable padding : float;
  mutable padding_vertical : float;
  mutable padding_horizontal : float;
  mutable padding_left : float;
  mutable padding_top : float;
  mutable padding_right : float;
  mutable padding_bottom : float;
  mutable padding_start : float;
  mutable padding_end : float;
  mutable border : float;
  mutable border_vertical : float;
  mutable border_horizontal : float;
  mutable border_left : float;
  mutable border_top : float;
  mutable border_right : float;
  mutable border_bottom : float;
  mutable border_start : float;
  mutable border_end : float;
  mutable width : float;
  mutable height : float;
  mutable min_width : float;
  mutable min_height : float;
  mutable max_width : float;
  mutable max_height : float;
  mutable position : float;
  mutable position_vertical : float;
  mutable position_horizontal : float;
  mutable left : float;
  mutable top : float;
  mutable right : float;
  mutable bottom : float;
  mutable start : float;
  mutable endd : float;
}

type cached_measurement = {
  mutable available_width : float;
  mutable available_height : float;
  mutable width_measure_mode : measure_mode;
  mutable height_measure_mode : measure_mode;
  mutable computed_width : float;
  mutable computed_height : float;
}

module Measurement_cache = Hashtbl.Make (struct
  type t = float * float * measure_mode * measure_mode * int
  let equal (w, h, wm, hm, gen) (w', h', wm', hm', gen') =
    gen = gen' && wm = wm' && hm = hm'
    && (w = w' || (Float.is_nan w && Float.is_nan w'))
    && (h = h' || (Float.is_nan h && Float.is_nan h'))
  let hash = Hashtbl.hash
end)

(* Layout output plus the bookkeeping that lets repeated measurements
   inside one layout pass reuse earlier results. *)
type ilayout = {
  mutable direction : direction;
  mutable generation_count : int;
  mutable last_parent_direction : direction option;
  mutable computed_flex_basis : float;
  mutable next_cached_measurements_index : int;
  cached_measurements : cached_measurement array;
  offer_cache : cached_measurement Measurement_cache.t;
  mutable natural_cache : cached_measurement option;
  mutable natural_height : cached_measurement option;
  mutable measured_width : float;
  mutable measured_height : float;
  cached_layout : cached_measurement;
  mutable left : float;
  mutable top : float;
  mutable right : float;
  mutable bottom : float;
  mutable width : float;
  mutable height : float;
}

type node = {
  mutable spec : style;
  mutable style : istyle;
  layout : ilayout;
  mutable line_index : int;
  mutable parent : node;
  mutable next_child : node;
  mutable has_new_layout : bool;
  mutable measure : (node -> width:float -> width_mode:measure_mode
                     -> height:float -> height_mode:measure_mode
                     -> dims) option;
  mutable children : node array;
  mutable children_count : int;
  mutable is_dirty : bool;
  mutable owner_independent : bool option;
  (* Auto margins resolved by the parent during its flex line layout,
     per physical edge. *)
  mutable res_margin_left : float;
  mutable res_margin_top : float;
  mutable res_margin_right : float;
  mutable res_margin_bottom : float;
  (* Resolved-spec fingerprint: owner inputs the current [style]
     scalars reflect. A percent-free spec resolves identically under
     any owner dims. [res_owner_axes] records only the scalar inputs
     used by percentage specs: width=1, height=2, main axis=4. *)
  mutable res_valid : bool;
  mutable res_owner_axes : int;
  mutable res_owner_w : float;
  mutable res_owner_h : float;
  mutable res_owner_main : float;
  (* Resolution generation: bumped every time [resolve_specs] rewrites
     the scalars, so consumers of [fin] can tell whether the offer's
     result is still the one they measured. *)
  mutable res_gen : int;
  mutable fin_gen : int;
  (* Resolution products cached alongside the scalars: non-auto margin
     sums per physical axis and whether any margin edge is auto. *)
  mutable marg_row : float;
  mutable marg_col : float;
  mutable any_auto_margin : bool;
  (* [basis_static] records that the last flex-basis derivation needed
     no owner dims (definite basis), letting it be reused across owner
     size changes. *)
  mutable basis_static : bool;
  (* Whether the last basis came from the single-flex-child zero-basis
     shortcut — contingent on the sibling set, so reuse requires the
     same answer this pass. *)
  mutable was_sflex : bool;
  (* The context the node was last fully laid out under: owner inner
     dims, the owner's offered measure modes, resolved main axis,
     direction, and the owner style bits that enter child
     derivations. *)
  mutable ctx_valid : bool;
  mutable ctx_w : float;
  mutable ctx_h : float;
  mutable ctx_main : float;
  mutable ctx_wm : measure_mode;
  mutable ctx_hm : measure_mode;
  mutable ctx_axis : flex_direction;
  mutable ctx_dir : direction;
  mutable ctx_poverflow : overflow;
  mutable ctx_palign : align;
  (* Position seeds [set_position] last computed (physical slots);
     clean children skip the re-seed and patches apply on top. *)
  mutable pos_seeded : bool;
  mutable pos_seed_l : float;
  mutable pos_seed_t : float;
  mutable pos_seed_r : float;
  mutable pos_seed_b : float;
  (* Per-pass lane markers computed by the parent's child loop. *)
  mutable spec_clean : bool;
  mutable ctx_same : bool;
  (* Container-side record of the last perform pass (nowrap only):
     the final line cross the stretch re-layouts were made against. *)
  mutable pl_valid : bool;
  mutable pl_cross : float;
  (* [fin_*]: offer of the most recent [layout_node_internal] call —
     i.e. the offer whose result [layout.measured_*] currently holds.
     [prev_a_*]/[prev_b_*]: the offers made at the flex-line call
     sites during the last perform pass. *)
  mutable fin_set : bool;
  mutable fin_w : float;
  mutable fin_h : float;
  mutable fin_wm : measure_mode;
  mutable fin_hm : measure_mode;
  mutable fin_pl : bool;
  mutable prev_a_set : bool;
  mutable prev_a_w : float;
  mutable prev_a_h : float;
  mutable prev_a_wm : measure_mode;
  mutable prev_a_hm : measure_mode;
  mutable prev_a_pl : bool;
  mutable prev_b_set : bool;
  mutable prev_b_w : float;
  mutable prev_b_h : float;
}

(* Public measure-callback type (same signature as the node field). *)
type measure = node -> width:float -> width_mode:measure_mode
             -> height:float -> height_mode:measure_mode -> dims

let css_max_cached_result_count = 6

let dummy_cached_measurement : cached_measurement = {
  available_width = zero;
  available_height = zero;
  width_measure_mode = Measure_invalid;
  height_measure_mode = Measure_invalid;
  computed_width = negativeOne;
  computed_height = negativeOne;
}

let create_cached_measurement () : cached_measurement =
  { dummy_cached_measurement with available_width = zero }

let default_istyle : istyle = {
  direction = Inherit;
  flex_direction = Column;
  justify_content = Justify_flex_start;
  align_content = Align_flex_start;
  align_items = Align_stretch;
  align_self = Align_auto;
  position_type = Relative;
  flex_wrap = No_wrap;
  overflow = Visible;
  flex = undefined;
  flex_grow = undefined;
  flex_shrink = undefined;
  flex_basis = undefined;
  margin = undefined;
  margin_vertical = undefined;
  margin_horizontal = undefined;
  margin_left = undefined;
  margin_top = undefined;
  margin_right = undefined;
  margin_bottom = undefined;
  margin_start = undefined;
  margin_end = undefined;
  margin_auto_all = false;
  margin_auto_vertical = false;
  margin_auto_horizontal = false;
  margin_auto_left = false;
  margin_auto_top = false;
  margin_auto_right = false;
  margin_auto_bottom = false;
  margin_auto_start = false;
  margin_auto_end = false;
  padding = undefined;
  padding_vertical = undefined;
  padding_horizontal = undefined;
  padding_left = undefined;
  padding_top = undefined;
  padding_right = undefined;
  padding_bottom = undefined;
  padding_start = undefined;
  padding_end = undefined;
  border = undefined;
  border_vertical = undefined;
  border_horizontal = undefined;
  border_left = undefined;
  border_top = undefined;
  border_right = undefined;
  border_bottom = undefined;
  border_start = undefined;
  border_end = undefined;
  width = undefined;
  height = undefined;
  min_width = undefined;
  min_height = undefined;
  max_width = undefined;
  max_height = undefined;
  position = undefined;
  position_vertical = undefined;
  position_horizontal = undefined;
  left = undefined;
  top = undefined;
  right = undefined;
  bottom = undefined;
  start = undefined;
  endd = undefined;
}

(* The sentinel empty node: parent/next_child point to itself so "null"
   checks are physical equality. *)
let rec null_node : node = {
  spec = default_style;
  style = default_istyle;
  layout = {
    direction = Inherit;
    generation_count = 0;
    last_parent_direction = None;
    computed_flex_basis = undefined;
    next_cached_measurements_index = 0;
    cached_measurements =
      [| dummy_cached_measurement; dummy_cached_measurement;
         dummy_cached_measurement; dummy_cached_measurement;
         dummy_cached_measurement; dummy_cached_measurement |];
    offer_cache = Measurement_cache.create 8;
  natural_cache = None;
  natural_height = None;
    cached_layout = dummy_cached_measurement;
    measured_width = undefined;
    measured_height = undefined;
    left = zero;
    top = zero;
    right = zero;
    bottom = zero;
    width = undefined;
    height = undefined;
  };
  line_index = 0;
  parent = null_node;
  next_child = null_node;
  has_new_layout = true;
  measure = None;
  children = [||];
  children_count = 0;
  is_dirty = false;
  owner_independent = None;
  res_margin_left = zero;
  res_margin_top = zero;
  res_margin_right = zero;
  res_margin_bottom = zero;
  res_valid = false;
  res_owner_axes = 0;
  res_owner_w = zero;
  res_owner_h = zero;
  res_owner_main = zero;
  res_gen = 0;
  fin_gen = -1;
  marg_row = zero;
  marg_col = zero;
  any_auto_margin = false;
  basis_static = false;
  was_sflex = false;
  ctx_valid = false;
  ctx_w = zero;
  ctx_h = zero;
  ctx_main = zero;
  ctx_wm = Measure_invalid;
  ctx_hm = Measure_invalid;
  ctx_axis = Column;
  ctx_dir = Inherit;
  ctx_poverflow = Visible;
  ctx_palign = Align_auto;
  pos_seeded = false;
  pos_seed_l = zero;
  pos_seed_t = zero;
  pos_seed_r = zero;
  pos_seed_b = zero;
  spec_clean = false;
  ctx_same = false;
  pl_valid = false;
  pl_cross = zero;
  fin_set = false;
  fin_w = zero;
  fin_h = zero;
  fin_wm = Measure_invalid;
  fin_hm = Measure_invalid;
  fin_pl = false;
  prev_a_set = false;
  prev_a_w = zero;
  prev_a_h = zero;
  prev_a_wm = Measure_invalid;
  prev_a_hm = Measure_invalid;
  prev_a_pl = false;
  prev_b_set = false;
  prev_b_w = zero;
  prev_b_h = zero;
}

let fresh_layout () : ilayout = {
  direction = Inherit;
  generation_count = 0;
  last_parent_direction = None;
  computed_flex_basis = undefined;
  next_cached_measurements_index = 0;
  cached_measurements =
    [| dummy_cached_measurement; dummy_cached_measurement;
       dummy_cached_measurement; dummy_cached_measurement;
       dummy_cached_measurement; dummy_cached_measurement |];
  offer_cache = Measurement_cache.create 8;
  natural_cache = None;
  natural_height = None;
  cached_layout = create_cached_measurement ();
  measured_width = undefined;
  measured_height = undefined;
  left = zero;
  top = zero;
  right = zero;
  bottom = zero;
  width = undefined;
  height = undefined;
}

let clear_measurement_offers (layout : ilayout) =
  Measurement_cache.clear layout.offer_cache;
  layout.natural_cache <- None;
  layout.natural_height <- None

let invalidate_measurements (layout : ilayout) =
  layout.next_cached_measurements_index <- 0;
  layout.cached_layout.width_measure_mode <- Measure_invalid;
  layout.cached_layout.height_measure_mode <- Measure_invalid;
  layout.cached_layout.computed_width <- negativeOne;
  layout.cached_layout.computed_height <- negativeOne;
  clear_measurement_offers layout

let style_of_spec (s : style) : istyle =
  (* Scalar fields start unresolved; [resolve_specs] fills them in on
     every layout pass once the owning node's dimensions are known.
     Point values still resolve eagerly (they need no basis) so a style
     is inspectable before the first layout. *)
  let dim = function Pt v -> v | _ -> undefined in
  { direction = s.direction;
    flex_direction = s.flex_direction;
    justify_content = s.justify_content;
    align_content = s.align_content;
    align_items = s.align_items;
    align_self = s.align_self;
    position_type = s.position_type;
    flex_wrap = s.flex_wrap;
    overflow = s.overflow;
    flex = undefined;
    flex_grow = (if s.flex_grow = 0. then undefined else s.flex_grow);
    flex_shrink = s.flex_shrink;
    flex_basis = dim s.flex_basis;
    margin = dim s.margin.all;
    margin_vertical = dim s.margin.vertical;
    margin_horizontal = dim s.margin.horizontal;
    margin_left = dim s.margin.left;
    margin_top = dim s.margin.top;
    margin_right = dim s.margin.right;
    margin_bottom = dim s.margin.bottom;
    margin_start = dim s.margin.start;
    margin_end = dim s.margin.end_;
    margin_auto_all = (s.margin.all = Auto);
    margin_auto_vertical = (s.margin.vertical = Auto);
    margin_auto_horizontal = (s.margin.horizontal = Auto);
    margin_auto_left = (s.margin.left = Auto);
    margin_auto_top = (s.margin.top = Auto);
    margin_auto_right = (s.margin.right = Auto);
    margin_auto_bottom = (s.margin.bottom = Auto);
    margin_auto_start = (s.margin.start = Auto);
    margin_auto_end = (s.margin.end_ = Auto);
    padding = dim s.padding.all;
    padding_vertical = dim s.padding.vertical;
    padding_horizontal = dim s.padding.horizontal;
    padding_left = dim s.padding.left;
    padding_top = dim s.padding.top;
    padding_right = dim s.padding.right;
    padding_bottom = dim s.padding.bottom;
    padding_start = dim s.padding.start;
    padding_end = dim s.padding.end_;
    border = dim s.border.all;
    border_vertical = dim s.border.vertical;
    border_horizontal = dim s.border.horizontal;
    border_left = dim s.border.left;
    border_top = dim s.border.top;
    border_right = dim s.border.right;
    border_bottom = dim s.border.bottom;
    border_start = dim s.border.start;
    border_end = dim s.border.end_;
    width = dim s.width;
    height = dim s.height;
    min_width = dim s.min_width;
    min_height = dim s.min_height;
    max_width = dim s.max_width;
    max_height = dim s.max_height;
    position = dim s.position.all;
    position_vertical = dim s.position.vertical;
    position_horizontal = dim s.position.horizontal;
    left = dim s.position.left;
    top = dim s.position.top;
    right = dim s.position.right;
    bottom = dim s.position.bottom;
    start = dim s.position.start;
    endd = dim s.position.end_;
  }

(* Resolve a [length] against an owner dimension. Undefined basis yields
   undefined. *)
let resolve_len (basis : float) (l : length) : float =
  match l with
  | Unset | Auto -> undefined
  | Pt v -> v
  | Percent p -> if is_undefined basis then undefined else basis *. (p /. 100.)

(* Percent values in a node's style always resolve against the owning
   (parent) node's inner dimensions, so it is the parent's job to resolve
   each child's specs right before it consumes them. *)

let fminf (a : float) (b : float) : float =
  if is_undefined b || a < b then a else b
let fmaxf (a : float) (b : float) : float =
  if is_undefined b || a > b then a else b

let get_flex_grow (n : node) : float =
  if is_defined n.style.flex_grow then n.style.flex_grow
  else if is_defined n.style.flex && n.style.flex > zero then n.style.flex
  else zero

let get_flex_shrink (n : node) : float =
  if is_defined n.style.flex_shrink then n.style.flex_shrink
  else if is_defined n.style.flex && n.style.flex < zero then -. n.style.flex
  else zero

let get_flex_basis (n : node) : float =
  if is_defined n.style.flex_basis then n.style.flex_basis
  else if is_defined n.style.flex then
    if n.style.flex > zero then zero else undefined
  else undefined

let leading_edge_for_axis = function
  | Column -> Top
  | Column_reverse -> Bottom
  | Row -> Left
  | Row_reverse -> Right

let trailing_edge_for_axis = function
  | Column -> Bottom
  | Column_reverse -> Top
  | Row -> Right
  | Row_reverse -> Left

(* Effective scalar for an edge of the position group, honoring the
   edge -> axis -> all cascade. *)
let computed_edge_position (st : istyle) (edge : edge) (default_value : float) : float =
  match edge with
  | Start ->
    if is_defined st.start then st.start
    else if is_defined st.position_horizontal then st.position_horizontal
    else if is_defined st.position then st.position
    else undefined
  | End ->
    if is_defined st.endd then st.endd
    else if is_defined st.position_horizontal then st.position_horizontal
    else if is_defined st.position then st.position
    else undefined
  | Left ->
    if is_defined st.left then st.left
    else if is_defined st.position_horizontal then st.position_horizontal
    else if is_defined st.position then st.position
    else default_value
  | Right ->
    if is_defined st.right then st.right
    else if is_defined st.position_horizontal then st.position_horizontal
    else if is_defined st.position then st.position
    else default_value
  | Top ->
    if is_defined st.top then st.top
    else if is_defined st.position_vertical then st.position_vertical
    else if is_defined st.position then st.position
    else default_value
  | Bottom ->
    if is_defined st.bottom then st.bottom
    else if is_defined st.position_vertical then st.position_vertical
    else if is_defined st.position then st.position
    else default_value

let computed_edge_margin (st : istyle) (edge : edge) (default_value : float) : float =
  match edge with
  | Start ->
    if is_defined st.margin_start then st.margin_start
    else if is_defined st.margin_horizontal then st.margin_horizontal
    else if is_defined st.margin then st.margin
    else undefined
  | End ->
    if is_defined st.margin_end then st.margin_end
    else if is_defined st.margin_horizontal then st.margin_horizontal
    else if is_defined st.margin then st.margin
    else undefined
  | Left ->
    if is_defined st.margin_left then st.margin_left
    else if is_defined st.margin_horizontal then st.margin_horizontal
    else if is_defined st.margin then st.margin
    else default_value
  | Right ->
    if is_defined st.margin_right then st.margin_right
    else if is_defined st.margin_horizontal then st.margin_horizontal
    else if is_defined st.margin then st.margin
    else default_value
  | Top ->
    if is_defined st.margin_top then st.margin_top
    else if is_defined st.margin_vertical then st.margin_vertical
    else if is_defined st.margin then st.margin
    else default_value
  | Bottom ->
    if is_defined st.margin_bottom then st.margin_bottom
    else if is_defined st.margin_vertical then st.margin_vertical
    else if is_defined st.margin then st.margin
    else default_value

let computed_edge_border (st : istyle) (edge : edge) (default_value : float) : float =
  match edge with
  | Start ->
    if is_defined st.border_start then st.border_start
    else if is_defined st.border_horizontal then st.border_horizontal
    else if is_defined st.border then st.border
    else undefined
  | End ->
    if is_defined st.border_end then st.border_end
    else if is_defined st.border_horizontal then st.border_horizontal
    else if is_defined st.border then st.border
    else undefined
  | Left ->
    if is_defined st.border_left then st.border_left
    else if is_defined st.border_horizontal then st.border_horizontal
    else if is_defined st.border then st.border
    else default_value
  | Right ->
    if is_defined st.border_right then st.border_right
    else if is_defined st.border_horizontal then st.border_horizontal
    else if is_defined st.border then st.border
    else default_value
  | Top ->
    if is_defined st.border_top then st.border_top
    else if is_defined st.border_vertical then st.border_vertical
    else if is_defined st.border then st.border
    else default_value
  | Bottom ->
    if is_defined st.border_bottom then st.border_bottom
    else if is_defined st.border_vertical then st.border_vertical
    else if is_defined st.border then st.border
    else default_value

let computed_edge_padding (st : istyle) (edge : edge) (default_value : float) : float =
  match edge with
  | Start ->
    if is_defined st.padding_start then st.padding_start
    else if is_defined st.padding_horizontal then st.padding_horizontal
    else if is_defined st.padding then st.padding
    else undefined
  | End ->
    if is_defined st.padding_end then st.padding_end
    else if is_defined st.padding_horizontal then st.padding_horizontal
    else if is_defined st.padding then st.padding
    else undefined
  | Left ->
    if is_defined st.padding_left then st.padding_left
    else if is_defined st.padding_horizontal then st.padding_horizontal
    else if is_defined st.padding then st.padding
    else default_value
  | Right ->
    if is_defined st.padding_right then st.padding_right
    else if is_defined st.padding_horizontal then st.padding_horizontal
    else if is_defined st.padding then st.padding
    else default_value
  | Top ->
    if is_defined st.padding_top then st.padding_top
    else if is_defined st.padding_vertical then st.padding_vertical
    else if is_defined st.padding then st.padding
    else default_value
  | Bottom ->
    if is_defined st.padding_bottom then st.padding_bottom
    else if is_defined st.padding_vertical then st.padding_vertical
    else if is_defined st.padding then st.padding
    else default_value

(* Whether the winning margin spec for an edge is auto, following the
   same cascade as [computed_edge_margin]. A field counts as present
   when its scalar is defined or its auto flag is set, because an auto
   spec resolves to an undefined scalar. *)
let margin_is_auto (st : istyle) (edge : edge) : bool =
  let present v a = is_defined v || a in
  match edge with
  | Start ->
    if present st.margin_start st.margin_auto_start then st.margin_auto_start
    else if present st.margin_horizontal st.margin_auto_horizontal
    then st.margin_auto_horizontal
    else st.margin_auto_all
  | End ->
    if present st.margin_end st.margin_auto_end then st.margin_auto_end
    else if present st.margin_horizontal st.margin_auto_horizontal
    then st.margin_auto_horizontal
    else st.margin_auto_all
  | Left ->
    if present st.margin_left st.margin_auto_left then st.margin_auto_left
    else if present st.margin_horizontal st.margin_auto_horizontal
    then st.margin_auto_horizontal
    else st.margin_auto_all
  | Right ->
    if present st.margin_right st.margin_auto_right then st.margin_auto_right
    else if present st.margin_horizontal st.margin_auto_horizontal
    then st.margin_auto_horizontal
    else st.margin_auto_all
  | Top ->
    if present st.margin_top st.margin_auto_top then st.margin_auto_top
    else if present st.margin_vertical st.margin_auto_vertical
    then st.margin_auto_vertical
    else st.margin_auto_all
  | Bottom ->
    if present st.margin_bottom st.margin_auto_bottom then st.margin_auto_bottom
    else if present st.margin_vertical st.margin_auto_vertical
    then st.margin_auto_vertical
    else st.margin_auto_all

(* Resolved auto margin for a physical edge of a child, set by the
   parent while laying out the flex line. *)
let res_margin_for_edge (n : node) (edge : edge) : float =
  match edge with
  | Left -> n.res_margin_left
  | Top -> n.res_margin_top
  | Right -> n.res_margin_right
  | Bottom -> n.res_margin_bottom
  | _ -> invalid_arg "No resolved margin for non-concrete edge"

let set_res_margin_for_edge (n : node) (edge : edge) (v : float) : unit =
  match edge with
  | Left -> n.res_margin_left <- v
  | Top -> n.res_margin_top <- v
  | Right -> n.res_margin_right <- v
  | Bottom -> n.res_margin_bottom <- v
  | _ -> invalid_arg "No resolved margin for non-concrete edge"

let reset_auto_margins (n : node) : unit =
  n.res_margin_left <- zero;
  n.res_margin_top <- zero;
  n.res_margin_right <- zero;
  n.res_margin_bottom <- zero

let same_dim (a : float) (b : float) : bool = a = b || (a <> a && b <> b)

let uses_owner_len = function Percent _ -> true | _ -> false
let uses_owner_edges (e : edges) : bool =
  uses_owner_len e.left || uses_owner_len e.right
  || uses_owner_len e.top || uses_owner_len e.bottom
  || uses_owner_len e.start || uses_owner_len e.end_
  || uses_owner_len e.horizontal || uses_owner_len e.vertical
  || uses_owner_len e.all

let spec_owner_axes (s : style) =
  let position = s.position in
  let width =
    uses_owner_len s.width || uses_owner_len s.min_width
    || uses_owner_len s.max_width || uses_owner_edges s.margin
    || uses_owner_edges s.padding || uses_owner_edges s.border
    || uses_owner_len position.all || uses_owner_len position.horizontal
    || uses_owner_len position.left || uses_owner_len position.right
    || uses_owner_len position.start || uses_owner_len position.end_ in
  let height =
    uses_owner_len s.height || uses_owner_len s.min_height
    || uses_owner_len s.max_height || uses_owner_len position.vertical
    || uses_owner_len position.top || uses_owner_len position.bottom in
  (if width then 1 else 0) lor (if height then 2 else 0)
  lor (if uses_owner_len s.flex_basis then 4 else 0)

let spec_uses_owner (s : style) : bool =
  spec_owner_axes s <> 0 || uses_owner_len s.row_gap || uses_owner_len s.column_gap

(* Resolve a node's specs against the owner's inner dims. Returns
   [true] when the resolved scalars were (re)written, [false] when the
   previous resolution still applies — a percent-free spec never
   needs re-resolution, a percent spec only when its owner axis moved. *)
let resolve_specs (n : node) ~owner_w ~owner_h ~owner_main : bool =
  if n.res_valid
     && (n.res_owner_axes land 1 = 0 || same_dim n.res_owner_w owner_w)
     && (n.res_owner_axes land 2 = 0 || same_dim n.res_owner_h owner_h)
     && (n.res_owner_axes land 4 = 0 || same_dim n.res_owner_main owner_main)
  then false
  else begin
  let s = n.spec in
  let st = n.style in
  let dim = resolve_len in
  st.flex_basis <- dim owner_main s.flex_basis;
  st.width <- dim owner_w s.width;
  st.height <- dim owner_h s.height;
  st.min_width <- dim owner_w s.min_width;
  st.min_height <- dim owner_h s.min_height;
  st.max_width <- dim owner_w s.max_width;
  st.max_height <- dim owner_h s.max_height;
  st.margin <- dim owner_w s.margin.all;
  st.margin_vertical <- dim owner_w s.margin.vertical;
  st.margin_horizontal <- dim owner_w s.margin.horizontal;
  st.margin_left <- dim owner_w s.margin.left;
  st.margin_top <- dim owner_w s.margin.top;
  st.margin_right <- dim owner_w s.margin.right;
  st.margin_bottom <- dim owner_w s.margin.bottom;
  st.margin_start <- dim owner_w s.margin.start;
  st.margin_end <- dim owner_w s.margin.end_;
  st.margin_auto_all <- (s.margin.all = Auto);
  st.margin_auto_vertical <- (s.margin.vertical = Auto);
  st.margin_auto_horizontal <- (s.margin.horizontal = Auto);
  st.margin_auto_left <- (s.margin.left = Auto);
  st.margin_auto_top <- (s.margin.top = Auto);
  st.margin_auto_right <- (s.margin.right = Auto);
  st.margin_auto_bottom <- (s.margin.bottom = Auto);
  st.margin_auto_start <- (s.margin.start = Auto);
  st.margin_auto_end <- (s.margin.end_ = Auto);
  st.padding <- dim owner_w s.padding.all;
  st.padding_vertical <- dim owner_w s.padding.vertical;
  st.padding_horizontal <- dim owner_w s.padding.horizontal;
  st.padding_left <- dim owner_w s.padding.left;
  st.padding_top <- dim owner_w s.padding.top;
  st.padding_right <- dim owner_w s.padding.right;
  st.padding_bottom <- dim owner_w s.padding.bottom;
  st.padding_start <- dim owner_w s.padding.start;
  st.padding_end <- dim owner_w s.padding.end_;
  st.border <- dim owner_w s.border.all;
  st.border_vertical <- dim owner_w s.border.vertical;
  st.border_horizontal <- dim owner_w s.border.horizontal;
  st.border_left <- dim owner_w s.border.left;
  st.border_top <- dim owner_w s.border.top;
  st.border_right <- dim owner_w s.border.right;
  st.border_bottom <- dim owner_w s.border.bottom;
  st.border_start <- dim owner_w s.border.start;
  st.border_end <- dim owner_w s.border.end_;
  st.position <- dim owner_w s.position.all;
  st.position_vertical <- dim owner_h s.position.vertical;
  st.position_horizontal <- dim owner_w s.position.horizontal;
  st.left <- dim owner_w s.position.left;
  st.top <- dim owner_h s.position.top;
  st.right <- dim owner_w s.position.right;
  st.bottom <- dim owner_h s.position.bottom;
  st.start <- dim owner_w s.position.start;
  st.endd <- dim owner_w s.position.end_;
  (* Resolution products: auto flags, per-axis non-auto margin sums,
     and the owner-dependence fingerprint. Auto margins reset here so
     a restyle away from auto cannot leak a stale share. *)
  n.any_auto_margin <-
    st.margin_auto_all || st.margin_auto_vertical
    || st.margin_auto_horizontal || st.margin_auto_left
    || st.margin_auto_top || st.margin_auto_right
    || st.margin_auto_bottom || st.margin_auto_start
    || st.margin_auto_end;
  n.res_margin_left <- zero;
  n.res_margin_top <- zero;
  n.res_margin_right <- zero;
  n.res_margin_bottom <- zero;
  n.marg_row <-
    (if is_defined st.margin_start && not st.margin_auto_start
     then st.margin_start
     else if st.margin_auto_left then zero else computed_edge_margin st Left zero)
    +.
    (if is_defined st.margin_end && not st.margin_auto_end
     then st.margin_end
     else if st.margin_auto_right then zero else computed_edge_margin st Right zero);
  n.marg_col <-
    (if st.margin_auto_top then zero else computed_edge_margin st Top zero)
    +.
    (if st.margin_auto_bottom then zero else computed_edge_margin st Bottom zero);
  n.res_owner_axes <- spec_owner_axes s;
  n.res_owner_w <- owner_w;
  n.res_owner_h <- owner_h;
  n.res_owner_main <- owner_main;
  n.res_valid <- true;
  n.res_gen <- n.res_gen + 1;
  (* Old offers and the measurement ring describe the previous resolved
     edges, including when the offered dimensions themselves did not move. *)
  invalidate_measurements n.layout;
  (* The stored position seeds derive from the resolved scalars just
     overwritten — re-seeding is mandatory before the clean lane may
     use them again. *)
  n.pos_seeded <- false;
  true
  end

let rec owner_independent (n : node) =
  match n.owner_independent with
  | Some independent -> independent
  | None ->
    let independent = not (spec_uses_owner n.spec)
      && Array.for_all owner_independent n.children in
    n.owner_independent <- Some independent;
    independent

let rec invalidate_owner_independent (n : node) =
  match n.owner_independent with
  | None -> ()
  | Some _ ->
    n.owner_independent <- None;
    if n.parent != null_node then invalidate_owner_independent n.parent

let is_row_direction = function
  | Row | Row_reverse -> true
  | _ -> false

let is_column_direction = function
  | Column | Column_reverse -> true
  | _ -> false

(* The leading margin for [axis]: logical start wins for row directions,
   auto margins report the parent's resolved share. *)
let get_leading_margin (n : node) (axis : flex_direction) : float =
  if is_row_direction axis && is_defined n.style.margin_start
     && not n.style.margin_auto_start
  then n.style.margin_start
  else
    let edge = leading_edge_for_axis axis in
    if margin_is_auto n.style edge then res_margin_for_edge n edge
    else computed_edge_margin n.style edge zero

let get_trailing_margin (n : node) (axis : flex_direction) : float =
  if is_row_direction axis && is_defined n.style.margin_end
     && not n.style.margin_auto_end
  then n.style.margin_end
  else
    let edge = trailing_edge_for_axis axis in
    if margin_is_auto n.style edge then res_margin_for_edge n edge
    else computed_edge_margin n.style edge zero

let get_leading_padding (n : node) (axis : flex_direction) : float =
  if is_row_direction axis && is_defined n.style.padding_start
     && n.style.padding_start >= zero
  then n.style.padding_start
  else
    fmaxf
      (computed_edge_padding n.style (leading_edge_for_axis axis) zero)
      zero

let get_trailing_padding (n : node) (axis : flex_direction) : float =
  if is_row_direction axis && is_defined n.style.padding_end
     && n.style.padding_end >= zero
  then n.style.padding_end
  else
    fmaxf
      (computed_edge_padding n.style (trailing_edge_for_axis axis) zero)
      zero

let get_leading_border (n : node) (axis : flex_direction) : float =
  if is_row_direction axis && is_defined n.style.border_start
     && n.style.border_start >= zero
  then n.style.border_start
  else
    fmaxf
      (computed_edge_border n.style (leading_edge_for_axis axis) zero)
      zero

let get_trailing_border (n : node) (axis : flex_direction) : float =
  if is_row_direction axis && is_defined n.style.border_end
     && n.style.border_end >= zero
  then n.style.border_end
  else
    fmaxf
      (computed_edge_border n.style (trailing_edge_for_axis axis) zero)
      zero

let get_leading_padding_and_border (n : node) (axis : flex_direction) : float =
  get_leading_padding n axis +. get_leading_border n axis

let get_trailing_padding_and_border (n : node) (axis : flex_direction) : float =
  get_trailing_padding n axis +. get_trailing_border n axis

let get_margin_axis (n : node) (axis : flex_direction) : float =
  get_leading_margin n axis +. get_trailing_margin n axis

(* Per-axis margin for a child in the fast lane: spec_clean implies
   no auto margins, so the resolution-time sums are exact. *)
let margin_axis_of (n : node) (axis : flex_direction) : float =
  if n.spec_clean then
    (if is_row_direction axis then n.marg_row else n.marg_col)
  else get_margin_axis n axis

let get_padding_and_border_axis (n : node) (axis : flex_direction) : float =
  get_leading_padding_and_border n axis +. get_trailing_padding_and_border n axis

let get_align_item (node : node) (child : node) : align =
  if child.style.align_self = Align_auto then node.style.align_items
  else child.style.align_self

let layout_measured_dimension_for_axis (n : node) (axis : flex_direction) : float =
  match axis with
  | Column | Column_reverse -> n.layout.measured_height
  | Row | Row_reverse -> n.layout.measured_width

let layout_pos_position_for_axis (n : node) (axis : flex_direction) : float =
  match axis with
  | Column -> n.layout.top
  | Column_reverse -> n.layout.bottom
  | Row -> n.layout.left
  | Row_reverse -> n.layout.right

let style_dimension_for_axis (n : node) (axis : flex_direction) : float =
  match axis with
  | Column | Column_reverse -> n.style.height
  | Row | Row_reverse -> n.style.width

let style_min_dimension_for_axis (n : node) (axis : flex_direction) : float =
  match axis with
  | Column | Column_reverse -> n.style.min_height
  | Row | Row_reverse -> n.style.min_width


let dim_with_margin_of (n : node) (axis : flex_direction) : float =
  layout_measured_dimension_for_axis n axis +. margin_axis_of n axis

let is_style_dim_defined (n : node) (axis : flex_direction) : bool =
  let value = style_dimension_for_axis n axis in
  is_defined value && value >= zero

let is_layout_dim_defined (n : node) (axis : flex_direction) : bool =
  let value = layout_measured_dimension_for_axis n axis in
  is_defined value && value >= zero

let is_leading_pos_defined (n : node) (axis : flex_direction) : bool =
  (is_row_direction axis
   && is_defined (computed_edge_position n.style Start undefined))
  || is_defined (computed_edge_position n.style (leading_edge_for_axis axis) undefined)

let is_trailing_pos_defined (n : node) (axis : flex_direction) : bool =
  (is_row_direction axis
   && is_defined (computed_edge_position n.style End undefined))
  || is_defined (computed_edge_position n.style (trailing_edge_for_axis axis) undefined)

let get_leading_position (n : node) (axis : flex_direction) : float =
  if is_row_direction axis then begin
    let leading = computed_edge_position n.style Start undefined in
    if is_defined leading then leading
    else
      let leading =
        computed_edge_position n.style (leading_edge_for_axis axis) undefined
      in
      if is_undefined leading then zero else leading
  end else
    let leading =
      computed_edge_position n.style (leading_edge_for_axis axis) undefined
    in
    if is_undefined leading then zero else leading

let get_trailing_position (n : node) (axis : flex_direction) : float =
  if is_row_direction axis then begin
    let trailing = computed_edge_position n.style End undefined in
    if is_defined trailing then trailing
    else
      let trailing =
        computed_edge_position n.style (trailing_edge_for_axis axis) undefined
      in
      if is_undefined trailing then zero else trailing
  end else
    let trailing =
      computed_edge_position n.style (trailing_edge_for_axis axis) undefined
    in
    if is_undefined trailing then zero else trailing

let bound_axis_within_min_and_max (n : node) (axis : flex_direction) (value : float) : float =
  let (minv, maxv) =
    if is_column_direction axis then (n.style.min_height, n.style.max_height)
    else if is_row_direction axis then (n.style.min_width, n.style.max_width)
    else (undefined, undefined)
  in
  let bound =
    if is_defined maxv && maxv >= zero && value > maxv then maxv else value
  in
  if is_defined minv && minv >= zero && is_defined bound && bound < minv
  then minv
  else bound

(* Also keeps the value at or above the padding-and-border size. *)
let bound_axis (n : node) (axis : flex_direction) (value : float) : float =
  fmaxf
    (bound_axis_within_min_and_max n axis value)
    (get_padding_and_border_axis n axis)

let set_layout_leading_position_for_axis (n : node) (axis : flex_direction) (v : float) : unit =
  match axis with
  | Column -> n.layout.top <- v
  | Column_reverse -> n.layout.bottom <- v
  | Row -> n.layout.left <- v
  | Row_reverse -> n.layout.right <- v

let set_layout_trailing_position_for_axis (n : node) (axis : flex_direction) (v : float) : unit =
  match axis with
  | Column -> n.layout.bottom <- v
  | Column_reverse -> n.layout.top <- v
  | Row -> n.layout.right <- v
  | Row_reverse -> n.layout.left <- v

let set_layout_measured_dimension_for_axis (n : node) (axis : flex_direction) (v : float) : unit =
  match axis with
  | Column | Column_reverse -> n.layout.measured_height <- v
  | Row | Row_reverse -> n.layout.measured_width <- v

let set_layout_position_for_axis (n : node) (axis : flex_direction) (leading : float) (trailing : float) : unit =
  match axis with
  | Column ->
    n.layout.top <- leading;
    n.layout.bottom <- trailing
  | Column_reverse ->
    n.layout.bottom <- leading;
    n.layout.top <- trailing
  | Row ->
    n.layout.left <- leading;
    n.layout.right <- trailing
  | Row_reverse ->
    n.layout.right <- leading;
    n.layout.left <- trailing

let resolve_direction (n : node) (parent_direction : direction) : direction =
  match n.style.direction with
  | Inherit -> if parent_direction <> Inherit then parent_direction else Ltr
  | d -> d

let resolve_axis (flex_direction : flex_direction) (direction : direction) : flex_direction =
  if direction = Rtl then
    match flex_direction with
    | Row -> Row_reverse
    | Row_reverse -> Row
    | _ -> flex_direction
  else flex_direction

let resolve_axises (flex_direction : flex_direction) (direction : direction)
    : flex_direction * flex_direction =
  match (direction, flex_direction) with
  | (Rtl, Row) -> (Row_reverse, Column)
  | (Rtl, Row_reverse) -> (Row, Column)
  | (Rtl, Column) -> (Column, Row_reverse)
  | (Rtl, Column_reverse) -> (Column_reverse, Row_reverse)
  | (_, Column) -> (Column, Row)
  | (_, Column_reverse) -> (Column_reverse, Row)
  | (_, Row) -> (Row, Column)
  | (_, Row_reverse) -> (Row_reverse, Column)

let is_flex (n : node) : bool =
  n.style.position_type = Relative
  && (get_flex_grow n <> zero || get_flex_shrink n <> zero)

(* Sets the trailing position of a child so it mirrors the leading one. *)
let set_trailing_position (node : node) (child : node) (axis : flex_direction) : unit =
  let size = layout_measured_dimension_for_axis child axis in
  let child_pos = layout_pos_position_for_axis child axis in
  let value =
    layout_measured_dimension_for_axis node axis -. size -. child_pos
  in
  set_layout_trailing_position_for_axis child axis value

(* Both edges defined: leading wins; otherwise +leading or -trailing. *)
let get_relative_position (n : node) (axis : flex_direction) : float =
  if is_leading_pos_defined n axis then get_leading_position n axis
  else -. get_trailing_position n axis

let set_seed_for_axis (n : node) (axis : flex_direction) (leading : float) (trailing : float) : unit =
  match axis with
  | Column -> n.pos_seed_t <- leading; n.pos_seed_b <- trailing
  | Column_reverse -> n.pos_seed_b <- leading; n.pos_seed_t <- trailing
  | Row -> n.pos_seed_l <- leading; n.pos_seed_r <- trailing
  | Row_reverse -> n.pos_seed_r <- leading; n.pos_seed_l <- trailing

let set_position (n : node) (direction : direction) : unit =
  let (main_axis, cross_axis) = resolve_axises n.style.flex_direction direction in
  let rel_main = get_relative_position n main_axis in
  let rel_cross = get_relative_position n cross_axis in
  let lead_main = get_leading_margin n main_axis +. rel_main in
  let trail_main = get_trailing_margin n main_axis +. rel_main in
  let lead_cross = get_leading_margin n cross_axis +. rel_cross in
  let trail_cross = get_trailing_margin n cross_axis +. rel_cross in
  set_seed_for_axis n main_axis lead_main trail_main;
  set_seed_for_axis n cross_axis lead_cross trail_cross;
  set_layout_position_for_axis n main_axis lead_main trail_main;
  set_layout_position_for_axis n cross_axis lead_cross trail_cross;
  n.pos_seeded <- true

(* The value [set_position] seeded (or would seed) into the slot the
   parent treats as [axis]'s leading edge — lets a clean child keep
   its old position field while the parent re-derives placement. *)
let pos_seed (n : node) (axis : flex_direction) : float =
  match axis with
  | Column -> n.pos_seed_t
  | Column_reverse -> n.pos_seed_b
  | Row -> n.pos_seed_l
  | Row_reverse -> n.pos_seed_r

let rec mark_dirty_internal (n : node) : unit =
  if not n.is_dirty then begin
    n.is_dirty <- true;
    n.layout.computed_flex_basis <- undefined;
    if n.parent != null_node then mark_dirty_internal n.parent
  end

let mark_dirty (n : node) : unit = mark_dirty_internal n

let constrain_size_to_max_size_for_mode (max_size : float) (mode : measure_mode) (size : float) : float =
  match mode with
  | Measure_invalid ->
    invalid_arg "No clue how this could happen"
  | Measure_exactly | Measure_at_most ->
    if is_undefined max_size || size < max_size then size else max_size
  | Measure_undefined ->
    if is_defined max_size then max_size else size

let constrain_mode_to_max_size_for_mode (max_size : float) (mode : measure_mode) : measure_mode =
  match mode with
  | Measure_invalid ->
    invalid_arg "No clue how this could happen"
  | Measure_exactly | Measure_at_most -> mode
  | Measure_undefined ->
    if is_defined max_size then Measure_at_most else mode

let measure_node_set_measured_dimensions
    (node : node)
    (available_width : float)
    (available_height : float)
    (width_measure_mode : measure_mode)
    (height_measure_mode : measure_mode) : unit =
  match node.measure with
  | None -> invalid_arg "Passed node with no measurement function"
  | Some measure ->
    let pad_border_row = get_padding_and_border_axis node Row in
    let pad_border_col = get_padding_and_border_axis node Column in
    let margin_row = get_margin_axis node Row in
    let margin_col = get_margin_axis node Column in
    let inner_width = available_width -. margin_row -. pad_border_row in
    let inner_height = available_height -. margin_col -. pad_border_col in
    if width_measure_mode = Measure_exactly && height_measure_mode = Measure_exactly then begin
      (* Both dimensions are already definite; skip the measure call. *)
      node.layout.measured_width <-
        bound_axis node Row (available_width -. margin_row);
      node.layout.measured_height <-
        bound_axis node Column (available_height -. margin_col)
    end
    else if (is_defined inner_width && inner_width <= zero)
         || (is_defined inner_height && inner_height <= zero) then begin
      (* No room to measure into; the result is the bounded zero. *)
      node.layout.measured_width <- bound_axis node Row zero;
      node.layout.measured_height <- bound_axis node Column zero
    end
    else begin
      let measured =
        measure node
          ~width:inner_width ~width_mode:width_measure_mode
          ~height:inner_height ~height_mode:height_measure_mode
      in
      node.layout.measured_width <-
        bound_axis node Row
          (if width_measure_mode = Measure_undefined || width_measure_mode = Measure_at_most
           then measured.width +. pad_border_row
           else available_width -. margin_row);
      node.layout.measured_height <-
        bound_axis node Column
          (if height_measure_mode = Measure_undefined || height_measure_mode = Measure_at_most
           then measured.height +. pad_border_col
           else available_height -. margin_col)
    end

(* Nodes with no children take the offered size, or fall back to their
   padding-and-border size when unconstrained. *)
let empty_container_set_measured_dimensions
    (node : node)
    (available_width : float)
    (available_height : float)
    (width_measure_mode : measure_mode)
    (height_measure_mode : measure_mode) : unit =
  let pad_border_row = get_padding_and_border_axis node Row in
  let pad_border_col = get_padding_and_border_axis node Column in
  let margin_row = get_margin_axis node Row in
  let margin_col = get_margin_axis node Column in
  node.layout.measured_width <-
    bound_axis node Row
      (if width_measure_mode = Measure_undefined || width_measure_mode = Measure_at_most
       then pad_border_row
       else available_width -. margin_row);
  node.layout.measured_height <-
    bound_axis node Column
      (if height_measure_mode = Measure_undefined || height_measure_mode = Measure_at_most
       then pad_border_col
       else available_height -. margin_col)

(* When a node is already definite on both axes (or gets no room at all),
   a measurement-only pass can skip the flex steps entirely. *)
let fixed_size_set_measured_dimensions
    (node : node)
    (available_width : float)
    (available_height : float)
    (width_measure_mode : measure_mode)
    (height_measure_mode : measure_mode) : bool =
  if (width_measure_mode = Measure_at_most
      && is_defined available_width && available_width <= zero)
     || (height_measure_mode = Measure_at_most
         && is_defined available_height && available_height <= zero)
     || (width_measure_mode = Measure_exactly
         && height_measure_mode = Measure_exactly)
  then begin
    let margin_col = get_margin_axis node Column in
    let margin_row = get_margin_axis node Row in
    node.layout.measured_width <-
      bound_axis node Row
        (if is_undefined available_width
            || (width_measure_mode = Measure_at_most && available_width < zero)
         then zero
         else available_width -. margin_row);
    node.layout.measured_height <-
      bound_axis node Column
        (if is_undefined available_height
            || (height_measure_mode = Measure_at_most && available_height < zero)
         then zero
         else available_height -. margin_col);
    true
  end
  else false

let g_current_generation_count = ref 0

let can_use_cached_measurement
    (available_width : float)
    (available_height : float)
    (margin_row : float)
    (margin_col : float)
    (width_measure_mode : measure_mode)
    (height_measure_mode : measure_mode)
    (cached_layout : cached_measurement) : bool =
  let fits mode available old_mode old_available computed margin =
    (mode = old_mode && same_dim available old_available)
    || (mode = Measure_exactly && available -. margin = computed)
    || (mode = Measure_at_most && computed <= available -. margin
        && (old_mode = Measure_undefined
            || (old_mode = Measure_at_most && old_available > available)))
  in
  fits width_measure_mode available_width cached_layout.width_measure_mode
    cached_layout.available_width cached_layout.computed_width margin_row
  && fits height_measure_mode available_height cached_layout.height_measure_mode
    cached_layout.available_height cached_layout.computed_height margin_col

let cached_measurement_at (layout : ilayout) (i : int) : cached_measurement =
  if i < 0 || i >= css_max_cached_result_count then
    invalid_arg ("No cached measurement at " ^ string_of_int i);
  let c = layout.cached_measurements.(i) in
  if c == dummy_cached_measurement then begin
    let c' = create_cached_measurement () in
    layout.cached_measurements.(i) <- c';
    c'
  end
  else c

(* Wrapper around [layout_node_impl]: skips the node when the same
   inputs were already measured, keeping a small ring of measurement
   results plus one layout result per node. Returns true when layout
   actually ran. *)
let profile_enabled = Sys.getenv_opt "LUI_FLEX_PROFILE" = Some "1"
let profile_calls = ref 0
let profile_hits = ref 0

let rec layout_node_internal
    (node : node)
    (available_width : float)
    (available_height : float)
    (parent_direction : direction)
    (width_measure_mode : measure_mode)
    (height_measure_mode : measure_mode)
    (perform_layout : bool) : bool =
  if profile_enabled then incr profile_calls;
  let layout = node.layout in
  let need_to_visit_node =
    (node.is_dirty && layout.generation_count <> !g_current_generation_count)
    || layout.last_parent_direction <> Some parent_direction
  in
  (* A new resolution has already discarded its old offers. Dirty nodes
     also invalidate the ring; unchanged nodes retain their bounded history. *)
  if need_to_visit_node then invalidate_measurements layout
  else if layout.generation_count <> !g_current_generation_count
          && Measurement_cache.length layout.offer_cache > 32 then
    clear_measurement_offers layout;
  let key_dim d = if Float.is_nan d then Float.nan else d in
  let offer = (key_dim available_width, key_dim available_height,
               width_measure_mode, height_measure_mode, node.res_gen) in
  let memo = if perform_layout then None
    else match Measurement_cache.find_opt layout.offer_cache offer with
      | Some _ as result -> result
      | None when owner_independent node ->
        (match layout.natural_cache with
         | Some result when can_use_cached_measurement
             available_width available_height
             (get_margin_axis node Row) (get_margin_axis node Column)
             width_measure_mode height_measure_mode result -> Some result
         | _ -> match layout.natural_height with
           | Some result when same_dim result.available_width available_width
               && result.width_measure_mode=width_measure_mode
               && (height_measure_mode=Measure_undefined
                   || (height_measure_mode=Measure_at_most
                       && result.computed_height <= available_height -. get_margin_axis node Column)) -> Some result
           | _ -> None)
      | None -> None in
  let cached_results = ref memo in
  if !cached_results = None then begin
  (* Determine whether the results are already cached. A layout result
     modifies positions and dimensions for the whole subtree; the
     algorithm assumes each node is laid out at most once per tree pass,
     while multiple measurements may be needed to resolve flex
     dimensions. Measure nodes get the richest caching because they are
     the most expensive to recompute. *)
  if node.measure <> None then begin
    let margin_row = get_margin_axis node Row in
    let margin_col = get_margin_axis node Column in
    (* First try the single layout cache entry. *)
    if can_use_cached_measurement
        available_width available_height margin_row margin_col
        width_measure_mode height_measure_mode layout.cached_layout
    then cached_results := Some layout.cached_layout
    else begin
      (* Then the ring of measurement results. *)
      let found = ref false in
      for i = 0 to layout.next_cached_measurements_index - 1 do
        if not !found then begin
          let c = cached_measurement_at layout i in
          if can_use_cached_measurement
              available_width available_height margin_row margin_col
              width_measure_mode height_measure_mode c
          then begin
            cached_results := Some c;
            found := true
          end
        end
      done
    end
  end
  else if perform_layout then begin
    if same_dim layout.cached_layout.available_width available_width
       && same_dim layout.cached_layout.available_height available_height
       && layout.cached_layout.width_measure_mode = width_measure_mode
       && layout.cached_layout.height_measure_mode = height_measure_mode
    then cached_results := Some layout.cached_layout
  end
  else begin
    let found = ref false in
    for i = 0 to layout.next_cached_measurements_index - 1 do
      if not !found then begin
        let c = cached_measurement_at layout i in
        if same_dim c.available_width available_width
           && same_dim c.available_height available_height
           && c.width_measure_mode = width_measure_mode
           && c.height_measure_mode = height_measure_mode
        then begin
          cached_results := Some c;
          found := true
        end
      end
    done
  end;
  end;
  if (not need_to_visit_node) && !cached_results <> None then begin
    if profile_enabled then incr profile_hits;
    let cached =
      match !cached_results with
      | None -> invalid_arg "Not possible"
      | Some c -> c
    in
    layout.measured_width <- cached.computed_width;
    layout.measured_height <- cached.computed_height
  end
  else begin
    layout_node_impl
      node available_width available_height parent_direction
      width_measure_mode height_measure_mode perform_layout;
    layout.last_parent_direction <- Some parent_direction;
    if !cached_results = None then begin
      (if layout.next_cached_measurements_index = css_max_cached_result_count then
         layout.next_cached_measurements_index <- 0);
      let new_entry =
        if perform_layout then layout.cached_layout
        else begin
          let c =
            cached_measurement_at layout layout.next_cached_measurements_index
          in
          layout.next_cached_measurements_index <-
            layout.next_cached_measurements_index + 1;
          c
        end
      in
      new_entry.available_width <- available_width;
      new_entry.available_height <- available_height;
      new_entry.width_measure_mode <- width_measure_mode;
      new_entry.height_measure_mode <- height_measure_mode;
      new_entry.computed_width <- layout.measured_width;
      new_entry.computed_height <- layout.measured_height
    end
  end;
  if not perform_layout && memo = None then begin
    let result = { available_width; available_height; width_measure_mode; height_measure_mode;
      computed_width=layout.measured_width; computed_height=layout.measured_height } in
    Measurement_cache.replace layout.offer_cache offer result;
    (* Intrinsic measurements can satisfy a tighter fitting offer.
       Descendant percentages would change their content dimensions,
       so only owner-independent subtrees use this representative. *)
    if owner_independent node then begin
      let representative = Some result in
      if width_measure_mode<>Measure_exactly && height_measure_mode<>Measure_exactly
      then layout.natural_cache <- representative;
      if height_measure_mode=Measure_undefined
         || (height_measure_mode=Measure_at_most
             && result.computed_height < available_height -. get_margin_axis node Column)
      then layout.natural_height <- representative
    end
  end;
  if perform_layout then begin
    node.layout.width <- node.layout.measured_width;
    node.layout.height <- node.layout.measured_height;
    node.has_new_layout <- true;
    node.is_dirty <- false
  end;
  layout.generation_count <- !g_current_generation_count;
  (* Record the offer that produced the node's current measured
     dims — later calls with a provably identical offer are skippable. *)
  node.fin_w <- available_width;
  node.fin_h <- available_height;
  node.fin_wm <- width_measure_mode;
  node.fin_hm <- height_measure_mode;
  node.fin_pl <- perform_layout;
  node.fin_gen <- node.res_gen;
  node.fin_set <- true;
  need_to_visit_node || !cached_results = None

and compute_child_flex_basis
    (node : node)
    (child : node)
    (width : float)
    (width_mode : measure_mode)
    (height : float)
    (height_mode : measure_mode)
    (direction : direction) : unit =
  let main_axis = resolve_axis node.style.flex_direction direction in
  let is_main_axis_row = is_row_direction main_axis in
  let child_width = ref zero in
  let child_height = ref zero in
  let child_width_mode = ref Measure_undefined in
  let child_height_mode = ref Measure_undefined in
  let is_row_style_dim_defined = is_style_dim_defined child Row in
  let is_column_style_dim_defined = is_style_dim_defined child Column in
  let this_flex_basis = get_flex_basis child in
  if is_defined this_flex_basis
     && is_defined (if is_main_axis_row then width else height)
  then begin
    child.basis_static <- true;
    if is_undefined child.layout.computed_flex_basis
    then
      child.layout.computed_flex_basis <-
        fmaxf this_flex_basis (get_padding_and_border_axis child main_axis)
  end
  else if is_main_axis_row && is_row_style_dim_defined then begin
    (* The width is definite, so use it as the flex basis. *)
    child.basis_static <- true;
    child.layout.computed_flex_basis <-
      fmaxf child.style.width (get_padding_and_border_axis child Row)
  end
  else if (not is_main_axis_row) && is_column_style_dim_defined then begin
    (* The height is definite, so use it as the flex basis. *)
    child.basis_static <- true;
    child.layout.computed_flex_basis <-
      fmaxf child.style.height (get_padding_and_border_axis child Column)
  end
  else begin
    child.basis_static <- false;
    child_width := undefined;
    child_height := undefined;
    child_width_mode := Measure_undefined;
    child_height_mode := Measure_undefined;
    if is_row_style_dim_defined then begin
      child_width := child.style.width +. get_margin_axis child Row;
      child_width_mode := Measure_exactly
    end;
    if is_column_style_dim_defined then begin
      child_height := child.style.height +. get_margin_axis child Column;
      child_height_mode := Measure_exactly
    end;
    (* Overflow behaves like browsers: a non-scroll main axis lets the
       child shrink to the offered cross/main size at most. *)
    (if ((not is_main_axis_row) && node.style.overflow = Scroll
         || node.style.overflow <> Scroll)
     then
       if is_undefined !child_width && is_defined width then begin
         child_width := width;
         child_width_mode := Measure_at_most
       end);
    (if (is_main_axis_row && node.style.overflow = Scroll
         || node.style.overflow <> Scroll)
     then
       if is_undefined !child_height && is_defined height then begin
         child_height := height;
         child_height_mode := Measure_at_most
       end);
    (* An undefined cross size on a stretched child is measured exactly
       against the available inner cross dim. *)
    if (not is_main_axis_row) && is_defined width
       && (not is_row_style_dim_defined)
       && width_mode = Measure_exactly
       && get_align_item node child = Align_stretch
    then begin
      child_width := width;
      child_width_mode := Measure_exactly
    end;
    if is_main_axis_row && is_defined height
       && (not is_column_style_dim_defined)
       && height_mode = Measure_exactly
       && get_align_item node child = Align_stretch
    then begin
      child_height := height;
      child_height_mode := Measure_exactly
    end;
    child_width :=
      constrain_size_to_max_size_for_mode child.style.max_width
        !child_width_mode !child_width;
    child_width_mode :=
      constrain_mode_to_max_size_for_mode child.style.max_width !child_width_mode;
    child_height :=
      constrain_size_to_max_size_for_mode child.style.max_height
        !child_height_mode !child_height;
    child_height_mode :=
      constrain_mode_to_max_size_for_mode child.style.max_height !child_height_mode;
    (* Measure the child to get its flex basis. *)
    let _ =
      layout_node_internal
        child !child_width !child_height direction
        !child_width_mode !child_height_mode false
    in
    child.layout.computed_flex_basis <-
      fmaxf
        (if is_main_axis_row then child.layout.measured_width
         else child.layout.measured_height)
        (get_padding_and_border_axis child main_axis)
  end;

(* Lay out a child positioned absolute relative to [node].
   [width] is the parent's available inner width. *)
and absolute_layout_child
    (node : node)
    (child : node)
    (width : float)
    (width_mode : measure_mode)
    (direction : direction) : unit =
  let (main_axis, cross_axis) =
    resolve_axises node.style.flex_direction direction
  in
  let child_width = ref undefined in
  let child_height = ref undefined in
  let child_width_mode = ref Measure_undefined in
  let child_height_mode = ref Measure_undefined in
  let is_main_axis_row = is_row_direction main_axis in
  if is_style_dim_defined child Row then
    child_width := child.style.width +. get_margin_axis child Row
  else if is_leading_pos_defined child Row && is_trailing_pos_defined child Row then begin
    child_width :=
      node.layout.measured_width
      -. (get_leading_border node Row +. get_trailing_border node Row)
      -. (get_leading_position child Row +. get_trailing_position child Row);
    child_width := bound_axis child Row !child_width
  end;
  if is_style_dim_defined child Column then
    child_height := child.style.height +. get_margin_axis child Column
  else if is_leading_pos_defined child Column
          && is_trailing_pos_defined child Column
  then begin
    (* Both top and bottom defined: size follows from the offsets. *)
    child_height :=
      node.layout.measured_height
      -. (get_leading_border node Column +. get_trailing_border node Column)
      -. (get_leading_position child Column +. get_trailing_position child Column);
    child_height := bound_axis child Column !child_height
  end;
  if is_undefined !child_width || is_undefined !child_height then begin
    child_width_mode :=
      (if is_undefined !child_width then Measure_undefined else Measure_exactly);
    child_height_mode :=
      (if is_undefined !child_height then Measure_undefined else Measure_exactly);
    (* When the main size is indefinite and the child's inline axis is
       parallel to it, size with an undefined main size and at-most on
       the cross axis. *)
    (* A non-positive offer cannot bound anything — content-size the
       child instead, or fixed_size_set_measured_dimensions skips the
       child's subtree and reports 0x0. *)
    if (not is_main_axis_row) && is_undefined !child_width
       && width_mode <> Measure_undefined && width > zero
    then begin
      child_width := width;
      child_width_mode := Measure_at_most
    end;
    let _ =
      layout_node_internal
        child !child_width !child_height direction
        !child_width_mode !child_height_mode false
    in
    child_width := child.layout.measured_width +. get_margin_axis child Row;
    child_height := child.layout.measured_height +. get_margin_axis child Column
  end;
  let _ =
    layout_node_internal
      child !child_width !child_height direction
      Measure_exactly Measure_exactly true
  in
  (if is_trailing_pos_defined child main_axis
      && not (is_leading_pos_defined child main_axis)
   then
     set_layout_leading_position_for_axis child main_axis
       (layout_measured_dimension_for_axis node main_axis
        -. layout_measured_dimension_for_axis child main_axis
        -. get_trailing_border node main_axis
        -. get_trailing_position child main_axis));
  (if is_trailing_pos_defined child cross_axis
      && not (is_leading_pos_defined child cross_axis)
   then
     set_layout_leading_position_for_axis child cross_axis
       (layout_measured_dimension_for_axis node cross_axis
        -. layout_measured_dimension_for_axis child cross_axis
        -. get_trailing_border node cross_axis
        -. get_trailing_position child cross_axis)
   else if not (is_leading_pos_defined child cross_axis) then begin
     (* Static cross-axis alignment needs the absolute child's final
        content size, which is not available during the flex-line pass. *)
     let leading = get_leading_padding_and_border node cross_axis in
     let trailing = get_trailing_padding_and_border node cross_axis in
     let remaining =
       layout_measured_dimension_for_axis node cross_axis
       -. leading -. trailing
       -. layout_measured_dimension_for_axis child cross_axis
       -. get_margin_axis child cross_axis
     in
     let offset = match get_align_item node child with
       | Align_center -> remaining /. 2.
       | Align_flex_end -> remaining
       | Align_auto | Align_flex_start | Align_stretch -> 0.
     in
     set_layout_leading_position_for_axis child cross_axis
       (leading +. get_leading_margin child cross_axis +. offset)
   end)

and layout_node_impl
    (node : node)
    (available_width : float)
    (available_height : float)
    (parent_direction : direction)
    (width_measure_mode : measure_mode)
    (height_measure_mode : measure_mode)
    (perform_layout : bool) : unit =
  if is_undefined available_width then
    assert (width_measure_mode = Measure_undefined);
  if is_undefined available_height then
    assert (height_measure_mode = Measure_undefined);
  let direction = resolve_direction node parent_direction in
  if node.layout.direction <> direction then
    node.layout.direction <- direction;
  if node.measure <> None then
    measure_node_set_measured_dimensions
      node available_width available_height
      width_measure_mode height_measure_mode
  else if node.children_count = 0 then
    empty_container_set_measured_dimensions
      node available_width available_height
      width_measure_mode height_measure_mode
  else begin
    let skipped =
      (not perform_layout)
      && fixed_size_set_measured_dimensions
           node available_width available_height
           width_measure_mode height_measure_mode
    in
    if not skipped then begin
      (* STEP 1: CALCULATE VALUES FOR REMAINDER OF ALGORITHM *)
      let (main_axis, cross_axis) =
        resolve_axises node.style.flex_direction direction
      in
      let is_main_axis_row = is_row_direction main_axis in
      let justify_content = node.style.justify_content in
      let is_node_flex_wrap = node.style.flex_wrap = Wrap in
      let first_absolute_child = ref null_node in
      let current_absolute_child_ref = ref null_node in

      (* Padding and border. *)
      let leading_padding_and_border_main =
        get_leading_padding_and_border node main_axis
      in
      let trailing_padding_and_border_main =
        get_trailing_padding_and_border node main_axis
      in
      let leading_padding_and_border_cross =
        get_leading_padding_and_border node cross_axis
      in

      let padding_and_border_axis_main =
        get_padding_and_border_axis node main_axis
      in
      let padding_and_border_axis_cross =
        get_padding_and_border_axis node cross_axis
      in

      (* Measure mode along each axis. *)
      let measure_mode_main_dim =
        if is_main_axis_row then width_measure_mode else height_measure_mode
      in
      let measure_mode_cross_dim =
        if is_main_axis_row then height_measure_mode else width_measure_mode
      in

      (* Padding/border/margin on the physical row and column axes. *)
      let padding_and_border_axis_row =
        if is_main_axis_row then padding_and_border_axis_main
        else padding_and_border_axis_cross
      in
      let padding_and_border_axis_column =
        if is_main_axis_row then padding_and_border_axis_cross
        else padding_and_border_axis_main
      in
      let margin_axis_row = get_margin_axis node Row in
      let margin_axis_column = get_margin_axis node Column in

      (* STEP 2: DETERMINE AVAILABLE SIZE IN MAIN AND CROSS DIRECTIONS *)
      let available_inner_width =
        available_width -. margin_axis_row -. padding_and_border_axis_row
      in
      let available_inner_height =
        available_height -. margin_axis_column -. padding_and_border_axis_column
      in
      let available_inner_main_dim =
        if is_main_axis_row then available_inner_width else available_inner_height
      in
      let available_inner_cross_dim =
        if is_main_axis_row then available_inner_height else available_inner_width
      in

      (* Resolved gaps: the gap along the main axis separates items in a
         line, the gap along the cross axis separates wrapped lines.
         Percent gaps resolve against the container's content box. *)
      let gap_main =
        let spec =
          if is_main_axis_row then node.spec.column_gap else node.spec.row_gap
        in
        match spec with
        | Percent p ->
          if is_undefined available_inner_main_dim then zero
          else available_inner_main_dim *. (p /. 100.)
        | Pt v -> v
        | Unset | Auto -> zero
      in
      let gap_cross =
        let spec =
          if is_main_axis_row then node.spec.row_gap else node.spec.column_gap
        in
        match spec with
        | Percent p ->
          if is_undefined available_inner_cross_dim then zero
          else available_inner_cross_dim *. (p /. 100.)
        | Pt v -> v
        | Unset | Auto -> zero
      in
      let child = ref null_node in
      let child_count = node.children_count in

      (* A single child that can both grow and shrink gets a flex basis
         of zero: it will be flexed to exactly fill the space, so the
         basis measurement can be skipped entirely, including a
         measurement pass whose main-axis offer is already exact. *)
      let single_flex_child = ref null_node in
      if ((is_main_axis_row && width_measure_mode = Measure_exactly)
             || ((not is_main_axis_row)
                 && height_measure_mode = Measure_exactly))
      then begin
        let should_continue = ref true in
        let i = ref 0 in
        while !should_continue && !i < child_count do
          let child = node.children.(!i) in
          (if !single_flex_child != null_node then begin
             if is_flex child then begin
               (* There is already a flexible child, abort. *)
               single_flex_child := null_node;
               should_continue := false
             end
           end
           else if get_flex_grow child > zero && get_flex_shrink child > zero then
             single_flex_child := child);
          i := !i + 1
        done
      end;

      (* STEP 3: DETERMINE FLEX BASIS FOR EACH ITEM

         This loop computes [.computed_flex_basis] for each child and
         builds a chain of absolute children through [.next_child]. For
         every non-absolute child we store a [.computed_flex_basis];
         a chain of relative children is built per line afterwards. *)
      for i = 0 to child_count - 1 do
        let child = node.children.(i) in
        assert (child != null_node);
        (* Resolve the child's percent/auto specs against this node's
           inner dimensions before anything reads them. A fingerprint
           hit means the resolved scalars — and the cached margin
           sums — are still current. *)
        let fresh =
          resolve_specs child
            ~owner_w:available_inner_width
            ~owner_h:available_inner_height
            ~owner_main:available_inner_main_dim
        in
        (* Context equality: the inputs every per-child derivation
           reads. [spec_clean] additionally certifies the cheap lane —
           identical spec, relative flow, no auto margins, seeds and a
           basis already computed under this axis/direction. *)
        child.ctx_same <-
          child.ctx_valid
          && same_dim child.ctx_w available_inner_width
          && same_dim child.ctx_h available_inner_height
          && same_dim child.ctx_main available_inner_main_dim
          && child.ctx_wm = width_measure_mode
          && child.ctx_hm = height_measure_mode
          && child.ctx_axis = main_axis
          && child.ctx_dir = direction
          && child.ctx_poverflow = node.style.overflow
          && child.ctx_palign = node.style.align_items;
        child.spec_clean <-
          (not fresh) && (not child.is_dirty)
          && child.style.position_type = Relative
          && (not child.any_auto_margin)
          && (not is_node_flex_wrap)
          && child.ctx_valid
          && child.ctx_axis = main_axis
          && child.ctx_dir = direction
          && child.pos_seeded
          && is_defined child.layout.computed_flex_basis;
        let sflex = child == !single_flex_child in
        if child.spec_clean && (child.basis_static || child.ctx_same)
           && child.was_sflex = sflex
        then ()
        else begin
          (* The child is being fully re-evaluated under this
             context — record the context its basis/offers will
             reflect, clear the resolved auto-margin scratch, and
             (in a perform pass) seed positions from the raw style. *)
          child.ctx_valid <- true;
          child.ctx_w <- available_inner_width;
          child.ctx_h <- available_inner_height;
          child.ctx_main <- available_inner_main_dim;
          child.ctx_wm <- width_measure_mode;
          child.ctx_hm <- height_measure_mode;
          child.ctx_axis <- main_axis;
          child.ctx_dir <- direction;
          child.ctx_poverflow <- node.style.overflow;
          child.ctx_palign <- node.style.align_items;
          child.was_sflex <- sflex;
          reset_auto_margins child;
          (if perform_layout then begin
             let child_direction = resolve_direction child direction in
             set_position child child_direction
           end);
          if child.style.position_type = Absolute then begin
            (if !first_absolute_child == null_node then
               first_absolute_child := child);
            let previous_absolute_child = !current_absolute_child_ref in
            (* If there was a prev absolute, set its next_child to child. *)
            (if previous_absolute_child != null_node then
               previous_absolute_child.next_child <- child);
            current_absolute_child_ref := child
          end
          else if sflex then begin
            child.basis_static <- true;
            child.layout.computed_flex_basis <- zero
          end
          else
            compute_child_flex_basis
              node child
              available_inner_width width_measure_mode
              available_inner_height height_measure_mode
              direction
        end
      done;
      (if !current_absolute_child_ref != null_node then
         (* Seal the absolute-child chain. *)
         (!current_absolute_child_ref).next_child <- null_node);

      (* STEP 4: COLLECT FLEX ITEMS INTO FLEX LINES *)
      let start_of_line_index = ref 0 in
      let end_of_line_index = ref 0 in
      let line_count = ref 0 in
      let total_line_cross_dim = ref zero in
      let max_line_main_dim = ref zero in
      while !end_of_line_index < child_count do
        (* Relative items on the current line; absolute-positioned items
           are skipped but still advance the indices. *)
        let items_on_line = ref 0 in
        (* Accumulated dimensions and margins of the children on this
           line: used to compute the container's main size when no size
           was given, and the space left for flexible children. *)
        let size_consumed_on_current_line = ref zero in
        let total_flex_grow_factors = ref zero in
        let total_flex_shrink_scaled_factors = ref zero in
        let cur_index = ref !start_of_line_index in

        (* Chain of the children on this line that can shrink/grow. *)
        let first_relative_child = ref null_node in
        let current_relative_child = ref null_node in
        let any_auto_anywhere = ref false in
        let should_continue = ref true in
        (* Add items to the current line until it's full or the items
           run out. *)
        while !cur_index < child_count && !should_continue do
          child := node.children.(!cur_index);
          (!child).line_index <- !line_count;
          if (!child).style.position_type <> Absolute then begin
            let outer_flex_basis =
              (!child).layout.computed_flex_basis
              +. margin_axis_of !child main_axis
            in
            (* A new item on a non-empty line also consumes one gap. *)
            let item_main_dim =
              outer_flex_basis
              +. (if !items_on_line > 0 then gap_main else zero)
            in
            (* In multi-line mode an item that overflows the available
               main size ends the current line (there must be at least
               one item already on it). *)
            let is_end_of_line =
              is_node_flex_wrap
              && !size_consumed_on_current_line +. item_main_dim
                 > available_inner_main_dim
              && !items_on_line > 0
            in
            if is_end_of_line then
              (* No index increments on this path: the item starts the
                 next line. *)
              should_continue := false
            else begin
              size_consumed_on_current_line :=
                !size_consumed_on_current_line +. item_main_dim;
              items_on_line := !items_on_line + 1;
              (if (!child).any_auto_margin then any_auto_anywhere := true);
              if is_flex !child then begin
                total_flex_grow_factors :=
                  !total_flex_grow_factors +. get_flex_grow !child;
                (* The shrink factor is scaled by the child's base
                   dimension, unlike the grow factor. *)
                total_flex_shrink_scaled_factors :=
                  !total_flex_shrink_scaled_factors
                  +. -. get_flex_shrink !child
                     *. (!child).layout.computed_flex_basis
              end;
              (if !first_relative_child == null_node then
                 first_relative_child := !child);
              (if !current_relative_child != null_node then
                 (!current_relative_child).next_child <- !child);
              current_relative_child := !child;
              (!child).next_child <- null_node;
              cur_index := !cur_index + 1;
              end_of_line_index := !end_of_line_index + 1
            end
          end
          else begin
            (* Absolute children consume no flex space but still advance
               the line indices. *)
            cur_index := !cur_index + 1;
            end_of_line_index := !end_of_line_index + 1
          end
        done;

        (* If the cross axis doesn't need to be measured, the flex step
           can be skipped entirely. *)
        let can_skip_flex =
          (not perform_layout) && measure_mode_cross_dim = Measure_exactly
        in

        (* STEP 5: RESOLVING FLEXIBLE LENGTHS ON MAIN AXIS
           Compute the space left to distribute. An indefinite main size
           means the node is content-sized and there is no space left. *)
        let remaining_free_space = ref zero in
        (if is_defined available_inner_main_dim then
           remaining_free_space :=
             available_inner_main_dim -. !size_consumed_on_current_line
         else if is_defined !size_consumed_on_current_line
                 && !size_consumed_on_current_line < zero
         then
           (* Indefinite main dim, negative consumption: the node will
              clamp to zero content size. *)
           remaining_free_space := -. !size_consumed_on_current_line);
        (* A scroll container's children overflow along its main axis —
           they grow to fill spare space but never shrink to fit, so a
           negative remainder resolves like a content-sized line. *)
        if node.style.overflow = Scroll && !remaining_free_space < zero then
          remaining_free_space := zero;
        let original_remaining_free_space = !remaining_free_space in
        let delta_free_space = ref zero in

        if not can_skip_flex then begin
          (* Two passes over the flex items: the first finds the items
             whose min/max constraints trigger, freezes them at those
             sizes and excludes those sizes from the remaining space;
             the second sets each flexible item's size, distributing
             the remaining space among items whose constraints did not
             trigger. This fixed two-pass scheme deviates from the
             spec's repeat-until-stable process but bounds the work. *)
          let delta_flex_shrink_scaled_factors = ref zero in
          let delta_flex_grow_factors = ref zero in
          current_relative_child := !first_relative_child;
          if !remaining_free_space <> zero then
          while !current_relative_child != null_node do
            let child_flex_basis =
              (!current_relative_child).layout.computed_flex_basis
            in
            if !remaining_free_space < zero then begin
              let flex_shrink_scaled_factor =
                -. get_flex_shrink !current_relative_child
                *. child_flex_basis
              in
              (* Is this child able to shrink? *)
              if flex_shrink_scaled_factor <> zero then begin
                let base_main_size =
                  child_flex_basis
                  (* Scale first, then divide, keeping the math faithful
                     to fixed-point encodings. *)
                  +. flex_shrink_scaled_factor
                     *. !remaining_free_space
                     /. !total_flex_shrink_scaled_factors
                in
                let bound_main_size =
                  bound_axis !current_relative_child main_axis base_main_size
                in
                if base_main_size <> bound_main_size then begin
                  (* Excluding this item's size and factor makes its
                     constraint trigger identically in the second pass. *)
                  delta_free_space :=
                    !delta_free_space -. (bound_main_size -. child_flex_basis);
                  delta_flex_shrink_scaled_factors :=
                    !delta_flex_shrink_scaled_factors -. flex_shrink_scaled_factor
                end
              end
            end
            else if (perform_layout || measure_mode_main_dim = Measure_exactly)
                    && !remaining_free_space > zero then begin
              let flex_grow_factor = get_flex_grow !current_relative_child in
              (* Is this child able to grow? *)
              if flex_grow_factor <> zero then begin
                let base_main_size =
                  child_flex_basis
                  +. flex_grow_factor
                     *. !remaining_free_space
                     /. !total_flex_grow_factors
                in
                let bound_main_size =
                  bound_axis !current_relative_child main_axis base_main_size
                in
                if base_main_size <> bound_main_size then begin
                  delta_free_space :=
                    !delta_free_space -. (bound_main_size -. child_flex_basis);
                  delta_flex_grow_factors :=
                    !delta_flex_grow_factors -. flex_grow_factor
                end
              end
            end;
            current_relative_child := (!current_relative_child).next_child
          done;
          total_flex_shrink_scaled_factors :=
            !total_flex_shrink_scaled_factors
            +. !delta_flex_shrink_scaled_factors;
          total_flex_grow_factors :=
            !total_flex_grow_factors +. !delta_flex_grow_factors;
          remaining_free_space :=
            !remaining_free_space +. !delta_free_space;

          (* Second pass: resolve the sizes of the flexible items. *)
          delta_free_space := zero;
          current_relative_child := !first_relative_child;
          while !current_relative_child != null_node do
            let child_flex_basis =
              (!current_relative_child).layout.computed_flex_basis
            in
            (* A clean child under an identical context and an inert
               flex pass is being offered exactly what this site
               offered it last perform pass ([prev_a]); flex-inert
               means its updated main size is just the basis. When its
               measured dims still hold that offer's result — or the
               equally final stretch-pass result — the whole offer
               derivation and the recursive call are skippable. *)
            let clean_inert =
              perform_layout && (!current_relative_child).spec_clean
              && (!current_relative_child).ctx_same
              && ((not (is_flex !current_relative_child))
                  || !remaining_free_space = zero)
            in
            if clean_inert && (!current_relative_child).prev_a_set
               && ((!current_relative_child).fin_set
                   && !current_relative_child.fin_pl
                      = !current_relative_child.prev_a_pl
                   && !current_relative_child.fin_wm
                      = !current_relative_child.prev_a_wm
                   && !current_relative_child.fin_hm
                      = !current_relative_child.prev_a_hm
                   && !current_relative_child.fin_w
                      = !current_relative_child.prev_a_w
                   && !current_relative_child.fin_h
                      = !current_relative_child.prev_a_h
                   || ((!current_relative_child).prev_b_set
                       && !current_relative_child.fin_pl
                       && !current_relative_child.fin_w
                          = !current_relative_child.prev_b_w
                       && !current_relative_child.fin_h
                          = !current_relative_child.prev_b_h))
            then
              current_relative_child := (!current_relative_child).next_child
            else begin
            let updated_main_size = ref child_flex_basis in
            if !remaining_free_space < zero then begin
              let flex_shrink_scaled_factor =
                -. get_flex_shrink !current_relative_child
                *. child_flex_basis
              in
              if flex_shrink_scaled_factor <> zero then begin
                let child_size =
                  if !total_flex_shrink_scaled_factors = zero
                  then child_flex_basis +. flex_shrink_scaled_factor
                  else
                    child_flex_basis
                    +. flex_shrink_scaled_factor
                       *. !remaining_free_space
                       /. !total_flex_shrink_scaled_factors
                in
                updated_main_size :=
                  bound_axis !current_relative_child main_axis child_size
              end
            end
            else if (perform_layout || measure_mode_main_dim = Measure_exactly)
                    && !remaining_free_space > zero then begin
              let flex_grow_factor = get_flex_grow !current_relative_child in
              if flex_grow_factor <> zero then
                updated_main_size :=
                  bound_axis !current_relative_child main_axis
                    (child_flex_basis
                     +. flex_grow_factor
                        *. !remaining_free_space
                        /. !total_flex_grow_factors)
            end;
            delta_free_space :=
              !delta_free_space -. (!updated_main_size -. child_flex_basis);
            let child_width = ref zero in
            let child_height = ref zero in
            let child_width_mode = ref Measure_undefined in
            let child_height_mode = ref Measure_undefined in
            if is_main_axis_row then begin
              child_width :=
                !updated_main_size
                +. get_margin_axis !current_relative_child Row;
              child_width_mode := Measure_exactly;
              if is_defined available_inner_cross_dim
                 && not is_node_flex_wrap
                 && not (is_style_dim_defined !current_relative_child Column)
                 && height_measure_mode = Measure_exactly
                 && get_align_item node !current_relative_child = Align_stretch
              then begin
                child_height := available_inner_cross_dim;
                child_height_mode := Measure_exactly
              end
              else if not (is_style_dim_defined !current_relative_child Column)
              then begin
                child_height := available_inner_cross_dim;
                child_height_mode :=
                  (if is_undefined !child_height then Measure_undefined
                   else Measure_at_most)
              end
              else begin
                child_height :=
                  (!current_relative_child).style.height
                  +. get_margin_axis !current_relative_child Column;
                child_height_mode := Measure_exactly
              end
            end
            else begin
              child_height :=
                !updated_main_size
                +. get_margin_axis !current_relative_child Column;
              child_height_mode := Measure_exactly;
              if is_defined available_inner_cross_dim
                 && not is_node_flex_wrap
                 && not (is_style_dim_defined !current_relative_child Row)
                 && width_measure_mode = Measure_exactly
                 && get_align_item node !current_relative_child = Align_stretch
              then begin
                child_width := available_inner_cross_dim;
                child_width_mode := Measure_exactly
              end
              else if not (is_style_dim_defined !current_relative_child Row)
              then begin
                child_width := available_inner_cross_dim;
                child_width_mode :=
                  (if is_undefined !child_width then Measure_undefined
                   else Measure_at_most)
              end
              else begin
                child_width :=
                  (!current_relative_child).style.width
                  +. get_margin_axis !current_relative_child Row;
                child_width_mode := Measure_exactly
              end
            end;
            child_width :=
              constrain_size_to_max_size_for_mode
                (!current_relative_child).style.max_width
                !child_width_mode !child_width;
            child_width_mode :=
              constrain_mode_to_max_size_for_mode
                (!current_relative_child).style.max_width !child_width_mode;
            child_height :=
              constrain_size_to_max_size_for_mode
                (!current_relative_child).style.max_height
                !child_height_mode !child_height;
            child_height_mode :=
              constrain_mode_to_max_size_for_mode
                (!current_relative_child).style.max_height !child_height_mode;
            let requires_stretch_layout =
              (not (is_style_dim_defined !current_relative_child cross_axis))
              && get_align_item node !current_relative_child = Align_stretch
            in
            (if perform_layout then begin
               (!current_relative_child).prev_a_set <- true;
               (!current_relative_child).prev_a_w <- !child_width;
               (!current_relative_child).prev_a_h <- !child_height;
               (!current_relative_child).prev_a_wm <- !child_width_mode;
               (!current_relative_child).prev_a_hm <- !child_height_mode;
               (!current_relative_child).prev_a_pl <-
                 (perform_layout && not requires_stretch_layout)
             end);
            (* Recursively lay out this child with its updated main size. *)
            (* Even without a clean-lane certificate the call is
               skippable when the child's measured dims already equal
               the result of this exact offer: [fin] tracks the offer
               that produced them. A dirty child must be laid out —
               its dirty flag and the new-layout bookkeeping ride
               along on the call. *)
            let pl = perform_layout && not requires_stretch_layout in
            (if not
                ((not (!current_relative_child).is_dirty)
                     && !current_relative_child.layout.last_parent_direction
                        = Some direction
                     && !current_relative_child.fin_set
                     && !current_relative_child.fin_gen
                        = !current_relative_child.res_gen
                     && !current_relative_child.fin_pl = pl
                     && same_dim !current_relative_child.fin_w !child_width
                     && same_dim !current_relative_child.fin_h !child_height
                     && !current_relative_child.fin_wm = !child_width_mode
                     && !current_relative_child.fin_hm = !child_height_mode)
            then
              let _ =
                layout_node_internal
                  !current_relative_child
                  !child_width !child_height direction
                  !child_width_mode !child_height_mode pl
              in
              ());
            current_relative_child := (!current_relative_child).next_child
            end
          done
        end;
        remaining_free_space :=
          original_remaining_free_space +. !delta_free_space;

        (* STEP 6: MAIN-AXIS JUSTIFICATION & CROSS-AXIS SIZE DETERMINATION
           All children have their main-axis dimensions now; their cross
           dimensions are set except for stretched items, resolved
           below. *)

        (* Under "at most" rules, the remaining space is capped by the
           container's min size on the main axis. *)
        if measure_mode_main_dim = Measure_at_most
           && !remaining_free_space > zero
        then begin
          let min_dim = style_min_dimension_for_axis node main_axis in
          if is_defined min_dim && min_dim >= zero then
            remaining_free_space :=
              fmaxf zero
                (min_dim
                 -. (available_inner_main_dim -. !remaining_free_space))
          else
            remaining_free_space := zero
        end;

        (* Auto margins on the main axis absorb the remaining free space
           before any justification applies: each auto margin gets an
           equal share of it. *)
        let leading_main_dim, between_main_dim =
          let auto_count = ref 0 in
          (if !any_auto_anywhere then
             for i = !start_of_line_index to !end_of_line_index - 1 do
               let c = node.children.(i) in
               if c.style.position_type = Relative && c.any_auto_margin then begin
                 (if margin_is_auto c.style (leading_edge_for_axis main_axis) then
                    incr auto_count);
                 (if margin_is_auto c.style (trailing_edge_for_axis main_axis) then
                    incr auto_count)
               end
             done);
          if !auto_count > 0 && !remaining_free_space > zero then begin
            let share =
              !remaining_free_space /. float_of_int !auto_count
            in
            (if !any_auto_anywhere then
               for i = !start_of_line_index to !end_of_line_index - 1 do
                 let c = node.children.(i) in
                 if c.style.position_type = Relative && c.any_auto_margin then begin
                   let lead = leading_edge_for_axis main_axis in
                   let trail = trailing_edge_for_axis main_axis in
                   (if margin_is_auto c.style lead then
                      set_res_margin_for_edge c lead share);
                   (if margin_is_auto c.style trail then
                      set_res_margin_for_edge c trail share)
                 end
               done);
            remaining_free_space := zero
          end;
          match justify_content with
          | Justify_center ->
            (divideScalarByInt !remaining_free_space 2, zero)
          | Justify_flex_end -> (!remaining_free_space, zero)
          | Justify_space_between ->
            (zero,
             if !items_on_line > 1 then
               divideScalarByInt (fmaxf !remaining_free_space zero)
                 (!items_on_line - 1)
             else zero)
          | Justify_space_around ->
            let between =
              divideScalarByInt !remaining_free_space !items_on_line
            in
            (divideScalarByInt between 2, between)
          | Justify_space_evenly ->
            let between =
              divideScalarByInt (fmaxf !remaining_free_space zero)
                (!items_on_line + 1)
            in
            (between, between)
          | Justify_flex_start -> (zero, zero)
        in
        let main_dim =
          ref (leading_padding_and_border_main +. leading_main_dim)
        in
        let cross_dim = ref zero in
        let relative_index = ref 0 in
        for i = !start_of_line_index to !end_of_line_index - 1 do
          child := node.children.(i);
          if (!child).style.position_type = Absolute
             && is_leading_pos_defined !child main_axis
          then begin
            if perform_layout then
              (* An absolute child with a leading position gets exactly
                 the user's offset (plus border and margin). *)
              set_layout_leading_position_for_axis
                !child main_axis
                (get_leading_position !child main_axis
                 +. get_leading_border node main_axis
                 +. get_leading_margin !child main_axis)
          end
          else if (!child).style.position_type = Relative then begin
            (* Gaps only appear between consecutive items. *)
            (if !relative_index > 0 then
               main_dim := !main_dim +. gap_main);
            relative_index := !relative_index + 1;
            (if perform_layout then
               (* Auto margins were seeded as zero before resolution, so
                  the resolved leading share is added explicitly here.
                  [pos_seed] is the value [set_position] seeded (or
                  would seed) into this slot. *)
               set_layout_leading_position_for_axis
                 !child main_axis
                 (pos_seed !child main_axis
                  +. res_margin_for_edge !child
                       (leading_edge_for_axis main_axis)
                  +. !main_dim));
            if can_skip_flex then begin
              (* Without a flex pass the measured dims were never set;
                 accumulate the basis instead. *)
              main_dim :=
                !main_dim
                +. between_main_dim
                +. margin_axis_of !child main_axis
                +. (!child).layout.computed_flex_basis;
              (* A wrapping container's line cross is the line's largest
                 item cross; only single-line containers inherit the
                 definite container cross. *)
              cross_dim :=
                if is_node_flex_wrap then
                  fmaxf !cross_dim
                    (dim_with_margin_of !child cross_axis)
                else available_inner_cross_dim
            end
            else begin
              (* The main dimension is the sum of the items' dimensions
                 plus the spacing. *)
              main_dim :=
                !main_dim +. between_main_dim
                +. dim_with_margin_of !child main_axis;
              (* The cross dimension is the max of the items' cross
                 dimensions. *)
              cross_dim :=
                fmaxf !cross_dim
                  (dim_with_margin_of !child cross_axis)
            end
          end
          else if perform_layout then
            set_layout_leading_position_for_axis
              !child main_axis
              (pos_seed !child main_axis
               +. get_leading_border !child main_axis
               +. leading_main_dim)
        done;
        main_dim := !main_dim +. trailing_padding_and_border_main;
        let container_cross_axis = ref available_inner_cross_dim in
        if measure_mode_cross_dim = Measure_undefined
           || measure_mode_cross_dim = Measure_at_most
        then begin
          (* The container's cross size comes from the largest cross
             dimension among its children. *)
          container_cross_axis :=
            bound_axis node cross_axis
              (!cross_dim +. padding_and_border_axis_cross)
            -. padding_and_border_axis_cross;
          if measure_mode_cross_dim = Measure_at_most then
            container_cross_axis :=
              fminf !container_cross_axis available_inner_cross_dim
        end;
        (* Without wrap the container's cross dim defines the line's. *)
        (if (not is_node_flex_wrap) && measure_mode_cross_dim = Measure_exactly
         then cross_dim := available_inner_cross_dim);
        (* Clamp to the container's min/max cross size. *)
        cross_dim :=
          bound_axis node cross_axis
            (!cross_dim +. padding_and_border_axis_cross)
          -. padding_and_border_axis_cross;
        (* Remember the line cross the stretch re-layouts below are
           made against (nowrap ⇔ single line ⇔ this is the node's
           only line cross). *)
        (if perform_layout && not is_node_flex_wrap then begin
           node.pl_valid <- true;
           node.pl_cross <- !cross_dim
         end);
        (* STEP 7: CROSS-AXIS ALIGNMENT. Skipped on measurement-only
           passes. *)
        (if perform_layout then
          for i = !start_of_line_index to !end_of_line_index - 1 do
            child := node.children.(i);
            if (!child).style.position_type = Absolute then begin
              (* An absolute child with a leading position overrides the
                 computed position; otherwise it hugs the leading
                 border plus margin. *)
              if is_leading_pos_defined !child cross_axis then
                set_layout_leading_position_for_axis
                  !child cross_axis
                  (get_leading_position !child cross_axis
                   +. get_leading_border node cross_axis
                   +. get_leading_margin !child cross_axis)
              else
                set_layout_leading_position_for_axis
                  !child cross_axis
                  (get_leading_border node cross_axis
                   +. get_leading_margin !child cross_axis)
            end
            else begin
              let leading_cross_dim = ref leading_padding_and_border_cross in
              (* Relative children use align-items/align-self unless an
                 auto margin on the cross axis absorbs the free space
                 first. *)
              let align_item = get_align_item node !child in
              let cross_lead_auto =
                (!child).any_auto_margin
                && margin_is_auto (!child).style
                     (leading_edge_for_axis cross_axis)
              in
              let cross_trail_auto =
                (!child).any_auto_margin
                && margin_is_auto (!child).style
                     (trailing_edge_for_axis cross_axis)
              in
              let auto_cross_count =
                (if cross_lead_auto then 1 else 0)
                + (if cross_trail_auto then 1 else 0)
              in
              if auto_cross_count > 0 then begin
                let remaining_cross =
                  !container_cross_axis
                  -. dim_with_margin_of !child cross_axis
                in
                let share =
                  fmaxf remaining_cross zero
                  /. float_of_int auto_cross_count
                in
                (if cross_lead_auto then
                   set_res_margin_for_edge !child
                     (leading_edge_for_axis cross_axis) share);
                (if cross_trail_auto then
                   set_res_margin_for_edge !child
                     (trailing_edge_for_axis cross_axis) share);
                (* The resolved margins enter through the regular
                 * margin getters below. *)
                leading_cross_dim :=
                  !leading_cross_dim +. res_margin_for_edge !child
                    (leading_edge_for_axis cross_axis)
              end
              (* A stretched child is laid out one more time with the
                 line's cross size forced as its own. *)
              else if align_item = Align_stretch then begin
                let is_cross_size_definite =
                  (is_main_axis_row
                   && is_style_dim_defined !child Column)
                  || ((not is_main_axis_row)
                      && is_style_dim_defined !child Row)
                in
                let child_width_mode = Measure_exactly in
                let child_height_mode = Measure_exactly in
                let (child_height, child_width) =
                  if is_main_axis_row then
                    (!cross_dim,
                     (!child).layout.measured_width
                     +. margin_axis_of !child Row)
                  else
                    ((!child).layout.measured_height
                     +. margin_axis_of !child Column,
                     !cross_dim)
                in
                let child_width =
                  constrain_size_to_max_size_for_mode
                    (!child).style.max_width child_width_mode child_width
                in
                let child_height =
                  constrain_size_to_max_size_for_mode
                    (!child).style.max_height child_height_mode child_height
                in
                (* Only re-lay-out when the cross size wasn't definite. *)
                if not is_cross_size_definite then begin
                  let child_width_mode =
                    if is_undefined child_width then Measure_undefined
                    else Measure_exactly
                  in
                  let child_height_mode =
                    if is_undefined child_height then Measure_undefined
                    else Measure_exactly
                  in
                  (* Same story as the main call site: a clean child
                     under an identical context is being offered what
                     this site offered last perform pass ([prev_b]);
                     when the final line cross also matches, the
                     measured dims are already in place. *)
                  let skip_b =
                    (!child).spec_clean && (!child).ctx_same
                    && node.pl_valid && same_dim !cross_dim node.pl_cross
                    && (!child).prev_b_set && (!child).fin_set
                    && (!child).fin_pl
                    && (!child).fin_wm = child_width_mode
                    && (!child).fin_hm = child_height_mode
                    && (!child).fin_w = child_width
                    && (!child).fin_h = child_height
                  in
                  (!child).prev_b_set <- true;
                  (!child).prev_b_w <- child_width;
                  (!child).prev_b_h <- child_height;
                  if not skip_b then
                    let _ =
                      layout_node_internal
                        !child child_width child_height direction
                        child_width_mode child_height_mode true
                    in
                    ()
                end
              end
              else if align_item <> Align_flex_start then begin
                let remaining_cross_dim =
                  !container_cross_axis
                  -. dim_with_margin_of !child cross_axis
                in
                if align_item = Align_center then
                  leading_cross_dim :=
                    !leading_cross_dim
                    +. divideScalarByInt remaining_cross_dim 2
                else
                  leading_cross_dim :=
                    !leading_cross_dim +. remaining_cross_dim
              end;
              set_layout_leading_position_for_axis
                !child cross_axis
                (pos_seed !child cross_axis
                 +. (!total_line_cross_dim +. !leading_cross_dim))
            end
          done);
        total_line_cross_dim := !total_line_cross_dim +. !cross_dim;
        (* Wrapped lines are separated by the cross-axis gap. *)
        (if !end_of_line_index < child_count then
           total_line_cross_dim := !total_line_cross_dim +. gap_cross);
        max_line_main_dim := fmaxf !max_line_main_dim !main_dim;
        line_count := !line_count + 1;
        start_of_line_index := !end_of_line_index
      done;

      (* STEP 8: MULTI-LINE CONTENT ALIGNMENT *)
      if !line_count > 1 && perform_layout
         && is_defined available_inner_cross_dim
      then begin
        let remaining_align_content_dim =
          available_inner_cross_dim -. !total_line_cross_dim
        in
        let cross_dim_lead = ref zero in
        let current_lead = ref leading_padding_and_border_cross in
        let align_content = node.style.align_content in
        (match align_content with
         | Align_flex_end ->
           current_lead := !current_lead +. remaining_align_content_dim
         | Align_center ->
           current_lead :=
             !current_lead
             +. divideScalarByInt remaining_align_content_dim 2
         | Align_stretch ->
           if available_inner_cross_dim > !total_line_cross_dim then
             cross_dim_lead :=
               divideScalarByInt remaining_align_content_dim !line_count
         | Align_auto | Align_flex_start -> ());
        let end_index = ref 0 in
        for i = 0 to !line_count - 1 do
          let start_index = !end_index in
          let j = ref start_index in
          let line_height = ref zero in
          let keep_scanning = ref true in
          while !j < child_count && !keep_scanning do
            child := node.children.(!j);
            if (!child).style.position_type = Relative then begin
              if (!child).line_index <> i then keep_scanning := false
              else begin
                (if is_layout_dim_defined !child cross_axis then
                   line_height :=
                     fmaxf !line_height
                       (layout_measured_dimension_for_axis !child cross_axis
                        +. get_margin_axis !child cross_axis));
                j := !j + 1
              end
            end
            else j := !j + 1
          done;
          end_index := !j;
          line_height := !line_height +. !cross_dim_lead;
          for j = start_index to !end_index - 1 do
            child := node.children.(j);
            if (!child).style.position_type = Relative then
              (match get_align_item node !child with
               | Align_flex_start ->
                 set_layout_leading_position_for_axis
                   !child cross_axis
                   (!current_lead
                    +. get_leading_margin !child cross_axis)
               | Align_flex_end ->
                 set_layout_leading_position_for_axis
                   !child cross_axis
                   (!current_lead
                    +. !line_height
                    -. get_trailing_margin !child cross_axis
                    -. layout_measured_dimension_for_axis !child cross_axis)
               | Align_center ->
                 let child_height =
                   layout_measured_dimension_for_axis !child cross_axis
                 in
                 set_layout_leading_position_for_axis
                   !child cross_axis
                   (!current_lead
                    +. divideScalarByInt (!line_height -. child_height) 2)
               | Align_stretch ->
                 set_layout_leading_position_for_axis
                   !child cross_axis
                   (!current_lead
                    +. get_leading_margin !child cross_axis)
               | Align_auto ->
                 invalid_arg "get_align_item should never return auto")
          done;
          current_lead := !current_lead +. !line_height +. gap_cross
        done
      end;

      (* STEP 9: COMPUTING FINAL DIMENSIONS *)
      node.layout.measured_width <-
        bound_axis node Row (available_width -. margin_axis_row);
      node.layout.measured_height <-
        bound_axis node Column (available_height -. margin_axis_column);
      (* An unspecified width or height takes the size of the children. *)
      (if measure_mode_main_dim = Measure_undefined then
         set_layout_measured_dimension_for_axis node main_axis
           (bound_axis node main_axis !max_line_main_dim)
       else if measure_mode_main_dim = Measure_at_most then
         set_layout_measured_dimension_for_axis node main_axis
           (fmaxf
              (fminf
                 (available_inner_main_dim +. padding_and_border_axis_main)
                 (bound_axis_within_min_and_max node main_axis !max_line_main_dim))
              padding_and_border_axis_main));
      (if measure_mode_cross_dim = Measure_undefined then
         set_layout_measured_dimension_for_axis node cross_axis
           (bound_axis node cross_axis
              (!total_line_cross_dim +. padding_and_border_axis_cross))
       else if measure_mode_cross_dim = Measure_at_most then
         set_layout_measured_dimension_for_axis node cross_axis
           (fmaxf
              (fminf
                 (available_inner_cross_dim +. padding_and_border_axis_cross)
                 (bound_axis_within_min_and_max node cross_axis
                    (!total_line_cross_dim +. padding_and_border_axis_cross)))
              padding_and_border_axis_cross));
      if perform_layout then begin
        (* STEP 10: SIZING AND POSITIONING ABSOLUTE CHILDREN *)
        let current_absolute_child = ref !first_absolute_child in
        while !current_absolute_child != null_node do
          absolute_layout_child
            node !current_absolute_child
            available_inner_width width_measure_mode direction;
          current_absolute_child := (!current_absolute_child).next_child
        done;
        (* STEP 11: SETTING TRAILING POSITIONS FOR CHILDREN *)
        let needs_main_trailing_pos =
          main_axis = Row_reverse || main_axis = Column_reverse
        in
        let needs_cross_trailing_pos =
          cross_axis = Row_reverse || cross_axis = Column_reverse
        in
        if needs_main_trailing_pos || needs_cross_trailing_pos then
          for i = 0 to child_count - 1 do
            let child = node.children.(i) in
            (if needs_main_trailing_pos then
               set_trailing_position node child main_axis);
            (if needs_cross_trailing_pos then
               set_trailing_position node child cross_axis)
          done
      end
    end
  end

let layout_node (node : node) (available_width : float) (available_height : float)
    (parent_direction : direction) : unit =
  (* Bump the generation count: all dirty nodes are visited at least
     once; later visits can be skipped when inputs are unchanged. *)
  incr g_current_generation_count;
  (* When the caller doesn't give a width or height, fall back to the
     style's own dimensions. *)
  let (width, width_mode) =
    if is_defined available_width then (available_width, Measure_exactly)
    else if is_style_dim_defined node Row then
      (node.style.width +. get_margin_axis node Row, Measure_exactly)
    else if node.style.max_width >= zero then
      (node.style.max_width, Measure_at_most)
    else (available_width, Measure_undefined)
  in
  let (height, height_mode) =
    if is_defined available_height then (available_height, Measure_exactly)
    else if is_style_dim_defined node Column then
      (node.style.height +. get_margin_axis node Column, Measure_exactly)
    else if node.style.max_height >= zero then
      (node.style.max_height, Measure_at_most)
    else (available_height, Measure_undefined)
  in
  if layout_node_internal
       node width height parent_direction
       width_mode height_mode true
  then set_position node node.layout.direction

(* ------------------------------------------------------------------ *)
(* Public API                                                          *)
(* ------------------------------------------------------------------ *)

let create ?(style = default_style) ?measure (children : node list) : node =
  if measure <> None && children <> [] then
    invalid_arg "Lui_flex.create: a measure callback is only allowed on leaf nodes";
  let arr = Array.of_list children in
  let n =
    { null_node with
      spec = style;
      style = style_of_spec style;
      layout = fresh_layout ();
      measure;
      children = arr;
      children_count = Array.length arr;
      parent = null_node;
      next_child = null_node;
      has_new_layout = false;
      is_dirty = false;
      res_margin_left = zero;
      res_margin_top = zero;
      res_margin_right = zero;
      res_margin_bottom = zero }
  in
  Array.iter (fun c -> c.parent <- n) arr;
  n

let children (n : node) : node list = Array.to_list n.children
let child_count (n : node) : int = n.children_count

let parent (n : node) : node option =
  if n.parent == null_node then None else Some n.parent

let set_style (n : node) (s : style) : unit =
  invalidate_owner_independent n;
  n.spec <- s;
  n.style <- style_of_spec s;
  n.res_valid <- false;
  (* Propagate the dirty flag up so the ancestors re-measure. *)
  mark_dirty_internal n

(* The persistent layout mirror needs mid-life child edits: swapping the
   array keeps node identity (and its cached layout) while the store
   splices produced children in and out. Detached children lose their
   parent link so a stale pointer cannot dirty a tree they left. *)
let set_children (n : node) (kids : node list) : unit =
  invalidate_owner_independent n;
  let arr = Array.of_list kids in
  Array.iter (fun c -> if c.parent == n then c.parent <- null_node) n.children;
  Array.iter (fun c -> c.parent <- n) arr;
  n.children <- arr;
  n.children_count <- Array.length arr;
  mark_dirty_internal n

(* Text/leaf re-measure: the mirror rebuilds the closure when a measure
   input prop changes instead of recreating the node. *)
let set_measure (n : node) (m : measure option) : unit =
  if m <> None && n.children_count > 0 then
    invalid_arg "Lui_flex.set_measure: a measure callback is only allowed on leaf nodes";
  n.measure <- m;
  mark_dirty_internal n

let has_new_layout (n : node) : bool = n.has_new_layout
let clear_new_layout (n : node) : unit = n.has_new_layout <- false

let compute_layout (node : node) ~(width : float) ~(height : float)
    ?(direction : direction = Ltr) () : unit =
  (* Resolve the root's specs against the offered size. The main-axis
     basis for a percent flex basis follows the root's own direction. *)
  let owner_main =
    if is_row_direction (resolve_axis node.spec.flex_direction direction)
    then width
    else height
  in
  ignore (resolve_specs node ~owner_w:width ~owner_h:height ~owner_main);
  let before_calls = !profile_calls and before_hits = !profile_hits in
  let started = Sys.time () in
  layout_node node width height direction;
  if profile_enabled then Printf.eprintf "flex: %.2fms calls=%d hits=%d\n%!"
    ((Sys.time () -. started) *. 1000.)
    (!profile_calls - before_calls) (!profile_hits - before_hits)

let layout (n : node) : rect =
  { x = n.layout.left; y = n.layout.top;
    w = n.layout.width; h = n.layout.height }

(* Rect relative to the layout root: sum the offsets up the chain. *)
let absolute_layout (n : node) : rect =
  let rec walk acc_x acc_y (cur : node) =
    if cur == null_node then (acc_x, acc_y)
    else walk (acc_x +. cur.layout.left) (acc_y +. cur.layout.top) cur.parent
  in
  let (x, y) = walk 0. 0. n in
  { x; y; w = n.layout.width; h = n.layout.height }

let rec iter (f : node -> unit) (n : node) : unit =
  f n;
  Array.iter (iter f) n.children

