(* Store → flex glue for the native backend.

   The mirror is rebuilt wholesale on every {!sync}; the store is small
   and rebuild-per-sync keeps invalidation trivial. All wire lengths are
   logical px and are multiplied by [scale] as they become flex style
   values, so the computed rects land in device px — the coordinate
   space [Lui_paint] and [Lui_scene] use. *)

open Lui_protocol
open Lui_flex

type text_measure = int -> string -> float -> float -> (float * float) option
type image_measure = int -> (float * float) option

(* Shared defaults so the memo's physical-equality check on function
   inputs sees a stable identity: an inline [fun] default would
   allocate a fresh closure per call and never match. *)
let no_measure _id _text _offered_w _offered_h = None
let no_image_measure _id = None
let show_all _id = false

(* Content-space visible range fed to a virtual list: (start, extent)
   in the list's own border-box coordinates. *)
type viewport = float * float

let no_vport _id = None

(* ---------- virtual lists ----------

   A [virtual-list] node's store children are the logical items; only
   the mounted window [first, last) of item indices gets flex trees —
   the node itself stays a leaf in the main mirror whose intrinsic
   main size is the virtual content extent. Row subtrees live in a
   side forest per virtual list; their absolute rects are composed
   (list content origin + model offset + row-relative layout) into
   [t.rects], so paint, hit-testing and scroll math see ordinary
   rects while unmounted items cost nothing. *)

(* One mounted row's flex subtree and the store ids it registered —
   the subtree is dropped wholesale when the row leaves the window. *)
type vrow = {
  rf : Lui_flex.node;
  rids : int list;
}

type vlist = {
  vid : int;
  mutable count : int;
  mutable kids : int array;   (* logical child ids, per structural sync *)
  mutable estimate : float;  (* unmeasured row main extent, device px *)
  mutable overscan : int;    (* extra rows mounted past each view edge *)
  mutable gap : float;       (* resolved row gap, device px *)
  mutable pad0 : float;      (* main-axis padding, near and far edges *)
  mutable pad1 : float;
  mutable bor0 : float;      (* main-axis border *)
  mutable bor1 : float;
  mutable origin_main : float;  (* border-box main origin, frame px *)
  mutable origin_cross : float; (* content-box cross origin *)
  mutable cross_size : float;   (* content-box cross size: row width *)
  measured : (int, float) Hashtbl.t; (* index → measured main extent *)
  mutable bit : float array;   (* Fenwick tree over stride = ext + gap *)
  mutable total : float;       (* padding-box content span *)
  mutable first : int;         (* mounted window [first, last) *)
  mutable last : int;
  mutable vs : float;          (* last viewport fed (content space) *)
  mutable ve : float;
  mutable windowed : bool;     (* a viewport was supplied → slice *)
  mutable drift : float;       (* pending anchor correction, device px *)
  rows : (int, vrow) Hashtbl.t;   (* index → mounted row subtree *)
  nodes : (int, Lui_flex.node) Hashtbl.t; (* store id → flex node, rows *)
  mutable mounted_ids : int list; (* ids whose rects are registered *)
  mutable key_index : (string, int) Hashtbl.t option; (* lazy key → index *)
  mutable id_index : (int, int) Hashtbl.t option; (* lazy store id → index *)
  mutable built_cross : float; (* cross size the mounted rows laid out at *)
}

(* The sync inputs a scroll-driven remount needs to rebuild row
   subtrees on a memo-hit path: the live store plus the style/measure
   context the rows were built under. *)
type saved_ctx = {
  sc_scale : float;
  sc_vw : float;
  sc_vh : float;
  sc_tm : text_measure;
  sc_image_measure : image_measure;
  sc_hidden : int -> bool;
  sc_anchor : (float * float) option;
  sc_store : Lui_store.t;
}

(* One raw child's produced expansion inside its parent's produced
   list: [gens] is the flat list of store ids that own flex nodes and
   land, in order, inside the flex children of the parent's flex owner
   (a normal child produces itself; a display:contents child produces
   its own produced children; display:none produces nothing). *)
type pkid = { raw : int; mutable gens : int list }

(* The pseudo store id of the synthetic frame root: store roots' parent
   in the [sparent] shadow and the key of their produced list in
   [pkids]. Real store ids are >= 0. *)
let frame_id = -1

type table = {
  mutable rows : int array array;
  mutable natural : float array option;
  mutable minima : float array;
  mutable assigned_width : float;
}

type t = {
  mutable root : Lui_flex.node option;
  (* The mirror is persistent: maps below live across syncs and the
     journal replays store ops onto them. *)
  nodes : (int, Lui_flex.node) Hashtbl.t; (* store id → flex node *)
  applied : (int, Lui_flex.style) Hashtbl.t; (* store id → applied style *)
  rects : (int, Lui_scene.rect) Hashtbl.t;
  vlists : (int, vlist) Hashtbl.t; (* store id → virtual-list state *)
  mutable vctx : saved_ctx option; (* inputs of the last full sync *)
  (* Store ids whose produced subtree needs a rect re-read after the
     incremental pass ([frame_id] = everything). *)
  rect_dirty : (int, unit) Hashtbl.t;
  (* Store ids whose absolute rect changed under the refresh — paint
     consumes the accumulated set via {!take_rect_changes} to re-emit
     only moved subtrees. *)
  mutable rect_changed : (int, unit) Hashtbl.t;
  (* [pkids p] is the produced expansion of raw parent p's children —
     the shadow the incremental path edits when children move. Present
     for every built node (leaves keep []) and for [frame_id]. *)
  pkids : (int, pkid list) Hashtbl.t;
  (* Raw parent of each built store id at mirror time (drops need it —
     the store link is already gone when the op arrives). *)
  sparent : (int, int) Hashtbl.t;
  (* Produced store id → owner: the store id whose flex node is its
     flex parent ([frame_id] for frame children). *)
  owner : (int, int) Hashtbl.t;
  tables : (int, table) Hashtbl.t;
  grids : (int * Lui_flex.node * Lui_flex.style * float) list ref;
  popups : (Lui_flex.node * int) list ref;
  mutable extent : float * float; (* frame extent the last layout used *)
  (* Memo of the inputs the current mirror+rects reflect. [synced_rev]
     is the store revision the journal has been replayed through;
     [synced_lrev] is the layout revision ([Lui_store.layout_rev]) —
     paint-only churn leaves it still so the fast path skips entirely.
     -1 forces a rebuild. Function inputs compare by identity — a
     caller whose measure/hidden closure keeps its identity but
     changes its answers (e.g. a text engine that finishes loading
     fonts) must {!invalidate}. *)
  mutable anchor_shift : int -> float * float;
  mutable synced_anchor_shifts : (int * float * float) list;
  mutable synced_rev : int;
  mutable synced_lrev : int;
  mutable synced_scale : float;
  mutable synced_w : float;
  mutable synced_h : float;
  mutable synced_anchor : (float * float) option;
  mutable synced_measure : text_measure;
  mutable synced_image_measure : image_measure;
  mutable synced_hidden : int -> bool;
  (* Instrumentation: [stat_syncs] counts syncs that rebuilt the mirror
     wholesale, [stat_steps] syncs that applied journal ops. Lets tests
     assert memoization and the incremental path instead of trusting
     timings. *)
  mutable stat_syncs : int;
  mutable stat_steps : int;
}

let create () =
  { root = None;
    nodes = Hashtbl.create 64;
    applied = Hashtbl.create 64;
    rects = Hashtbl.create 64;
    vlists = Hashtbl.create 4;
    vctx = None;
    rect_dirty = Hashtbl.create 16;
    rect_changed = Hashtbl.create 64;
    pkids = Hashtbl.create 64;
    sparent = Hashtbl.create 64;
    owner = Hashtbl.create 64;
    tables = Hashtbl.create 4;
    grids = ref [];
    popups = ref [];
    extent = (0., 0.);
    anchor_shift = (fun _ -> (0.,0.)); synced_anchor_shifts = [];
    synced_rev = -1;
    synced_lrev = -1;
    synced_scale = 0.;
    synced_w = 0.;
    synced_h = 0.;
    synced_anchor = None;
    synced_measure = no_measure;
    synced_image_measure = no_image_measure;
    synced_hidden = show_all;
    stat_syncs = 0;
    stat_steps = 0 }

let invalidate (t : t) = t.synced_rev <- -1
let stat_syncs (t : t) = t.stat_syncs
let stat_steps (t : t) = t.stat_steps

(* ---------- wire value access ---------- *)

let pstr store id name = Lui_store.string_prop store id name

let rec text_nowrap store id =
  match pstr store id "white-space" with
  | Some value -> value = "nowrap"
  | None ->
    match Lui_store.parent store id with
    | Some parent -> text_nowrap store parent
    | None -> false

(* Numeric read that accepts Float/Int and numeric strings — the schema
   types most layout props, but staying permissive costs nothing. *)
let pnum store id name =
  match Lui_store.prop store id name with
  | Some (FloatValue f) -> Some f
  | Some (IntValue i) -> Some (float_of_int i)
  | Some (StringValue s) -> float_of_string_opt (String.trim s)
  | _ -> None

(* ---------- length parsing ---------- *)

(* [length_of_string] parses the lenient forms of a wire length: plain
   or "px"-suffixed numbers, "NN%", "auto". *)
let length_of_string ~scale s : Lui_flex.length =
  let s = String.trim s in
  if s = "" || s = "auto" then Lui_flex.Auto
  else if String.length s >= 1 && s.[String.length s - 1] = '%' then (
    let num = String.sub s 0 (String.length s - 1) |> String.trim in
    match float_of_string_opt num with
    | Some p -> Percent p
    | None -> Unset)
  else
    let num =
      if String.length s > 2
         && String.sub s (String.length s - 2) 2 = "px"
      then String.sub s 0 (String.length s - 2)
      else s
    in
    match float_of_string_opt (String.trim num) with
    | Some v -> Pt (v *. scale)
    | None -> Unset

(* Wire value → flex length; numeric values scale to device px. *)
let length_prop ~scale store id name : Lui_flex.length =
  match Lui_store.prop store id name with
  | Some (IntValue i) -> Pt (float_of_int i *. scale)
  | Some (FloatValue f) -> Pt (f *. scale)
  | Some (StringValue s) -> length_of_string ~scale s
  | _ -> Unset

(* Percent of the parent content box; [p] is the CSS percent number
   (50% → Percent 50.). *)
let percent_len p : Lui_flex.length = Percent p

(* A viewport-fraction prop (0..1 of the frame). Resolved against the
   frame when known, else degrades to a parent-relative percent. *)
let viewport_len ~viewport store id ~name ~horizontal : Lui_flex.length =
  let (vw, vh) = viewport in
  match pnum store id name with
  | Some f when f > 0. ->
    let extent = if horizontal then vw else vh in
    if extent > 0. then Pt (f *. extent)
    else percent_len (f *. 100.)
  | _ -> Unset

(* CSS shorthand: 1..4 lengths → (top, right, bottom, left). *)
let shorthand_lengths ~scale s =
  let toks =
    String.split_on_char ' ' s
    |> List.filter (fun t -> String.trim t <> "")
    |> List.map (length_of_string ~scale)
  in
  match toks with
  | [ v ] -> Some (v, v, v, v)
  | [ v; h ] -> Some (v, h, v, h)
  | [ t; h; b ] -> Some (t, h, b, h)
  | [ t; r; b; l ] -> Some (t, r, b, l)
  | _ -> None

(* Uniform edge props accept either a number or the CSS 1–4-value shorthand. *)
let uniform_edges ~scale store id name : Lui_flex.edges =
  let base = Lui_flex.edges_auto in
  match Lui_store.prop store id name with
  | Some (StringValue s) -> (
    match shorthand_lengths ~scale s with
    | Some (t, r, b, l) -> { base with top = t; right = r; bottom = b; left = l }
    | None -> base)
  | Some _ -> { base with all = length_prop ~scale store id name }
  | None -> base

(* Axis props override the uniform padding shorthand. *)
let padding_edges ~scale store id : Lui_flex.edges =
  let base = uniform_edges ~scale store id "padding" in
  let side name uniform =
    match Lui_store.prop store id name with
    | None -> uniform
    | Some _ -> length_prop ~scale store id name
  in
  { base with
    horizontal = length_prop ~scale store id "padding-horizontal";
    vertical = length_prop ~scale store id "padding-vertical";
    top = side "padding-top" base.top;
    right = side "padding-right" base.right;
    bottom = side "padding-bottom" base.bottom;
    left = side "padding-left" base.left }

(* Axis and side props override the uniform margin shorthand. *)
let margin_edges ~scale store id : Lui_flex.edges =
  let base = uniform_edges ~scale store id "margin" in
  let base =
    { base with
      horizontal = length_prop ~scale store id "margin-horizontal";
      vertical = length_prop ~scale store id "margin-vertical" }
  in
  { base with
    top = length_prop ~scale store id "margin-top";
    right = length_prop ~scale store id "margin-right";
    bottom = length_prop ~scale store id "margin-bottom";
    left = length_prop ~scale store id "margin-left" }

(* Modal surfaces reserve the top zone their title chrome paints
   (26px title, 15px description; sheets get a 12px grabber lane).
   The reserve stacks on top of any view-set top padding. *)
let title_pad ~scale store id kind (e : Lui_flex.edges) : Lui_flex.edges =
  match kind with
  | "dialog" | "sheet" ->
    let nonempty name =
      match Lui_store.prop store id name with
      | Some (StringValue s) -> s <> ""
      | _ -> false
    in
    let extra =
      (if nonempty "text" then 26. else 0.)
      +. (if nonempty "description" then 15. else 0.)
    in
    let extra = extra *. scale in
    if extra <= 0. then e
    else
      let add l =
        match l with
        | Lui_flex.Pt v -> Lui_flex.Pt (v +. extra)
        | _ -> Lui_flex.Pt extra
      in
      let top =
        match e.top with
        | Lui_flex.Unset -> (
          match e.vertical with
          | Lui_flex.Unset -> e.all
          | v -> v)
        | v -> v
      in
      { e with top = add top }
  | _ -> e

(* inset / inset-top|right|bottom|left → position edges, per-side
   fallback to the uniform prop (same resolution as paint). *)
let inset_edges ~scale store id : Lui_flex.edges =
  let side name =
    match Lui_store.prop store id name with
    | Some _ -> length_prop ~scale store id name
    | None -> length_prop ~scale store id "inset"
  in
  { Lui_flex.edges_auto with
    left = side "inset-left";
    right = side "inset-right";
    top = side "inset-top";
    bottom = side "inset-bottom" }

(* ---------- value tables ---------- *)

let justify_of_string = function
  | "start" | "flex-start" -> Lui_flex.Justify_flex_start
  | "center" -> Justify_center
  | "end" | "flex-end" -> Justify_flex_end
  | "space_between" | "space-between" -> Justify_space_between
  | "space-around" | "space_around" -> Justify_space_around
  | "space-evenly" | "space_evenly" -> Justify_space_evenly
  | _ -> Justify_flex_start

let align_of_string = function
  | "stretch" -> Lui_flex.Align_stretch
  | "start" | "flex-start" | "auto" -> Align_flex_start
  | "center" -> Align_center
  | "end" | "flex-end" -> Align_flex_end
  | _ -> Align_stretch

(* Popup surfaces live outside the flow everywhere they appear; paint
   positions them via the anchor/x/y channels it owns. *)
let popup_kind = function
  | "dialog" | "drawer" | "sheet" | "tooltip" | "toast"
  | "dropdown-menu" | "context-menu" | "popover" | "alert" -> true
  | _ -> false

(* Kinds whose children occupy one shared cell: the first child sizes
   the box, later children overlay it (mirrors the web grid 1/1
   treatment). *)
let zstack_kind = function
  | "overlay" | "stack" | "panel" | "card" | "resizable"
  | "view-that-fits" -> true
  | _ -> false

let scroll_kind = function
  | "scroll" | "list" | "virtual-list" -> true
  | _ -> false

let has_prop store id name = Lui_store.prop store id name <> None

(* Popups carrying explicit inset/position edges keep them; everything
   else in the family goes through [refine_popups]: anchor props place
   relative to their anchor box, the rest center in the containing
   block (a bare [position] prop gives no placement — auto edges
   resolve to the parent's origin — so it does not count as
   positioning input). *)
let popup_has_edges store id =
  List.exists (has_prop store id)
    [ "position"; "inset"; "inset-top"; "inset-right"; "inset-bottom";
      "inset-left" ]

(* ---------- style translation ---------- *)

(* Kind → container direction + overflow. Everything else is a column.
   Horizontal kinds follow the component contracts: groups, tab strips,
   table rows, toolbars, steppers and the horizontal composition
   containers lay children out along the main axis. An explicit
   [orientation] prop wins over the kind default. *)
let direction_of ~store ~id kind : Lui_flex.flex_direction =
  match pstr store id "orientation" with
  | Some "horizontal" -> Row
  | Some "vertical" -> Column
  | _ -> (
    match kind with
    | "row" | "grid" | "button" | "toggle-button" | "menu-item" | "list-item"
    | "button-group" | "toggle-group"
    | "input-group-actions" | "table-row" | "tabs" | "bottom-tabs"
    | "toolbar" | "swipe-actions" | "stepper" | "breadcrumb"
    | "pagination" | "split" | "drawer" | "link" | "text" -> Row
    | "edge-inset" -> (
      match pstr store id "edge" with
      | Some ("leading" | "trailing") -> Row
      | _ -> Column)
    | _ -> Column)

let overflow_of ~store ~id kind : Lui_flex.overflow =
  match pstr store id "overflow" with
  | Some ("auto" | "scroll") -> Scroll
  | Some ("hidden" | "clip") -> Hidden
  | Some "visible" -> Visible
  | _ ->
    if scroll_kind kind || Lui_paint.menu_kind store id kind then Scroll
    else Visible

(* container-relative-frame(+ -inset): fills the container along the
   named axes (min-* variants floor it instead); the inset becomes a
   margin on the filled axes. *)
let container_frame ~scale ~store ~id (style : Lui_flex.style) : Lui_flex.style =
  match pstr store id "container-relative-frame" with
  | None -> style
  | Some v ->
    let full = percent_len 100. in
    let has_h = v = "horizontal" || v = "both" in
    let has_v = v = "vertical" || v = "both" in
    let has_min_h = v = "min-horizontal" || v = "min-both" in
    let has_min_v = v = "min-vertical" || v = "min-both" in
    let inset = length_prop ~scale store id "container-relative-frame-inset" in
    let inset = match inset with Unset -> Pt 0. | l -> l in
    { style with
      width = (if has_h then full else style.width);
      height = (if has_v then full else style.height);
      min_width = (if has_min_h then full else style.min_width);
      min_height = (if has_min_v then full else style.min_height);
      margin =
        { style.margin with
          left = (if has_h || has_min_h then inset else style.margin.left);
          right = (if has_h || has_min_h then inset else style.margin.right);
          top = (if has_v || has_min_v then inset else style.margin.top);
          bottom = (if has_v || has_min_v then inset else style.margin.bottom) } }

let style_of ?(scale = 1.) ?(viewport = (0., 0.)) store id : Lui_flex.style =
  let kind = Lui_store.kind store id in
  let d = Lui_flex.default_style in
  let lp name = length_prop ~scale store id name in
  (* position prop owns position_type + edges; popup kinds default to
     out-of-flow with no offsets. *)
  let (position_type, position) =
    match pstr store id "position" with
    | Some ("absolute" | "fixed") ->
      (Lui_flex.Absolute, inset_edges ~scale store id)
    | _ ->
      (* A drawer carrying [selected] is the inline pane control —
         in-flow split, not a presented popup. *)
      if popup_kind kind
         && not (kind = "drawer" && has_prop store id "selected")
      then (Absolute, Lui_flex.edges_auto)
      else (Relative, Lui_flex.edges_auto)
  in
  let grow =
    match pnum store id "grow" with
    | Some g -> g
    | None -> if kind = "spacer" then 1. else d.flex_grow
  in
  (* Contract default gaps when the view leaves [gap] unset. *)
  let gap =
    match lp "gap" with
    | Unset -> (
      match kind with
      | "button-group" | "toggle-group" | "breadcrumb" -> Pt (4. *. scale)
      | "input-group-actions" -> Pt (6. *. scale)
      | "pagination" -> Pt (2. *. scale)
      | "dialog" | "sheet" -> Pt (16. *. scale)
      | "popover" | "alert" | "list-item" -> Pt (8. *. scale)
      | _ -> Unset)
    | l -> l
  in
  (* The [size] component contract supplies intrinsic dimensions when
     the view leaves them unset — the same mapping the web stylesheet
     applies (.lui-button[data-size]: icon→40², sm→36h, lg→44h,
     default→40h). *)
  let size_w, size_h =
    match kind with
    | "button" | "toggle-button" -> (
      (* Icon-only buttons are square chrome on the web — the width
         contract falls back to the resolved height (explicit height
         prop or the size contract's default). *)
      let blank s = match s with None | Some "" -> true | _ -> false in
      let icon_only =
        not (blank (pstr store id "icon"))
        && blank (pstr store id "text")
        && blank (pstr store id "label")
        && Lui_store.children store id = []
      in
      if icon_only then
        let dfl =
          match pstr store id "size" with
          | Some "icon" -> 40.
          | Some "sm" | Some "small" -> 36.
          | Some "lg" | Some "large" -> 44.
          | _ -> 40.
        in
        let h =
          match lp "height" with Unset -> Pt (dfl *. scale) | l -> l
        in
        (h, h)
      else
        match pstr store id "size" with
        | Some "icon" -> (Pt (40. *. scale), Pt (40. *. scale))
        | Some "sm" | Some "small" -> (Unset, Pt (36. *. scale))
        | Some "lg" | Some "large" -> (Unset, Pt (44. *. scale))
        | Some _ -> (Unset, Pt (40. *. scale))
        | None -> (Unset, Unset))
    | "icon" -> (
      (* A bare icon's [size] picks its glyph box like the web's
         ti-size utilities (sm→14², lg→20², default 16²). *)
      match pstr store id "size" with
      | Some "sm" | Some "small" -> (Pt (14. *. scale), Pt (14. *. scale))
      | Some "lg" | Some "large" -> (Pt (20. *. scale), Pt (20. *. scale))
      | Some _ -> (Pt (16. *. scale), Pt (16. *. scale))
      | None -> (Unset, Unset))
    | _ -> (Unset, Unset)
  in
  let style =
    { d with
      flex_direction = direction_of ~store ~id kind;
      justify_content =
        (match pstr store id "main" with
         | Some s -> justify_of_string s
         | None -> if kind = "table-cell" then Justify_center else d.justify_content);
      align_items =
        (match pstr store id "cross" with
         | Some s -> align_of_string s
         | None -> (
           (* Grouped controls and labeled chrome center their children
              on the cross axis — .lui-button / .lui-menu-item are
              items-center flex rows on the web. *)
           match kind with
           | "button" | "toggle-button" | "menu-item" | "list-item"
           | "button-group" | "toggle-group" | "input-group-actions"
           | "breadcrumb" | "pagination" | "toolbar" -> Align_center
           | "table-cell" -> (match pstr store id "text-alignment" with
               | Some "end" -> Align_flex_end
               | Some "center" -> Align_center
               | _ -> Align_flex_start)
           | _ -> d.align_items));
      position_type;
      flex_wrap =
        (if kind = "text" && text_nowrap store id then No_wrap
         else match pstr store id "flex-wrap" with
         | Some "wrap" -> Wrap
         | Some "nowrap" -> No_wrap
         | _ -> if kind = "grid" || kind = "text" then Wrap else No_wrap);
      overflow = overflow_of ~store ~id kind;
      flex_grow = grow;
      width =
        (match viewport_len ~viewport store id ~name:"width-viewport" ~horizontal:true with
         | Unset -> (
           match lp "width" with
           | Unset when kind = "table" && size_w = Unset -> Percent 100.
           | Unset -> size_w
           | l -> l)
         | l -> l);
      height =
        (match viewport_len ~viewport store id ~name:"height-viewport" ~horizontal:false with
         | Unset -> (
           match lp "height" with Unset -> size_h | l -> l)
         | l -> l);
      min_width =
        (match viewport_len ~viewport store id ~name:"min-width-viewport" ~horizontal:true with
         | Unset -> lp "min-width"
         | l -> l);
      max_width =
        (match viewport_len ~viewport store id ~name:"max-width-viewport" ~horizontal:true with
         | Unset -> lp "max-width"
         | l -> l);
      min_height =
        (match viewport_len ~viewport store id ~name:"min-height-viewport" ~horizontal:false with
         | Unset -> (
           match lp "min-height" with
           | Unset -> (
             (* The component contract floor the web stylesheet gives
                .lui-menu-item (min-height: 2rem) — without it a
                childless item collapses to its text measure and an item
                with trailing content to the child's height. *)
             match kind with
             | "menu-item" -> Pt (32. *. scale)
             | _ -> Unset)
           | l -> l)
         | l -> l);
      max_height =
        (match viewport_len ~viewport store id ~name:"max-height-viewport" ~horizontal:false with
         | Unset -> lp "max-height"
         | l -> l);
      padding = title_pad ~scale store id kind (padding_edges ~scale store id);
      border = uniform_edges ~scale store id "border-width";
      margin = margin_edges ~scale store id;
      position;
      row_gap =
        (match lp "row-gap" with Unset -> gap | l -> l);
      column_gap =
        (match lp "column-gap" with Unset -> gap | l -> l) }
  in
  container_frame ~scale ~store ~id style

(* ---------- parent-driven child adjustments ---------- *)

(* Non-first children of a shared-cell parent: absolute, pinned by the
   child's [alignment] prop; unset alignment means stretch on that
   axis (the engine has no centering primitive for absolute children —
   a leading+trailing pair is the stretch approximation). *)
let overlay_edges store id : Lui_flex.edges =
  let e = Lui_flex.edges_auto in
  let z = Pt 0. in
  match pstr store id "alignment" with
  | Some "top-leading" -> { e with left = z; top = z }
  | Some "top" -> { e with left = z; right = z; top = z }
  | Some "top-trailing" -> { e with right = z; top = z }
  | Some "leading" -> { e with left = z; top = z; bottom = z }
  | Some "trailing" -> { e with right = z; top = z; bottom = z }
  | Some "bottom-leading" -> { e with left = z; bottom = z }
  | Some "bottom" -> { e with left = z; right = z; bottom = z }
  | Some "bottom-trailing" -> { e with right = z; bottom = z }
  | _ -> { e with left = z; right = z; top = z; bottom = z }

(* [adjust ~pkind ~pid ~index store id style] rewrites a child's style
   for parent-level contracts: shared-cell overlays, grid cells, the
   edge-inset content child and frame-fill roots. [pkind] is the
   parent's wire kind, or "frame" for the synthetic frame root. *)
let adjust ~scale ~pkind ~pid ~index store id (style : Lui_flex.style) : Lui_flex.style =
  let style =
    if pkind = "frame" && not (popup_kind (Lui_store.kind store id)) then
      (* Non-popup store roots fill the frame. *)
      { style with flex_grow = 1. }
    else style
  in
  let style =
    if zstack_kind pkind && index > 0
       && (match pstr store id "position" with
           | Some ("absolute" | "fixed") -> false
           | _ -> true) then
      (* Shared-cell alignment must not overwrite authored position edges. *)
      { style with
        position_type = Lui_flex.Absolute;
        position = overlay_edges store id }
    else style
  in
  let style =
    if pkind = "grid" then
      let basis =
        match pnum store pid "columns" with
        | Some n when n > 0. ->
          let span = Option.value (pnum store id "grid-column-span") ~default:1. in
          if span>n then invalid_arg "grid column span exceeds column count";
          Lui_flex.Percent (100. *. span /. n)
        | _ -> Pt 0.
      in
      (* Cells keep their declared column share; an incomplete final
         row must not stretch to fill unused columns. *)
      { style with flex_basis = basis }
    else style
  in
  let style =
    if pkind = "split" then
      match Lui_store.child_ids store pid with
      | first :: second :: _ when id = first || id = second ->
          let pane_style basis grow =
            { style with flex_basis = basis; flex_grow = grow;
              min_width = Pt 0.; overflow = Hidden }
          in
          (match pnum store pid "first-pane-width", pnum store pid "value" with
           | Some width, _ ->
               pane_style (Pt (if id = first then width *. scale else 0.))
                 (if id = first then 0. else 1.)
           | None, Some fraction ->
               pane_style (Pt 0.) (if id = first then fraction else 1. -. fraction)
           | None, None -> style)
      | _ -> style
    else style
  in
  let style =
    if pkind = "text" && text_nowrap store pid then
      (* Inline fragments keep their ink width when wrapping is disabled.
         Shrinking their boxes would paint adjacent runs on top of each other. *)
      { style with flex_shrink = 0. }
    else style
  in
  let style =
    if scroll_kind pkind || Lui_paint.menu_kind store pid pkind then
      (* A scroller's content keeps its natural main size so it
         overflows and scrolls — the default flex_shrink=1 would
         compress children into the clipped viewport instead. *)
      { style with flex_shrink = 0. }
    else style
  in
  let style =
    if pkind = "edge-inset" then
      (* The first store child is the scrollable content; CSS gives it
         flex:1 while pinned siblings group at the named edge. *)
      match Lui_store.child_ids store pid with
      | first :: _ when first = id ->
        { style with flex_grow = 1. }
      | _ -> style
    else style
  in
  style

(* Edge-inset ordering: the first store child is the content; pinned
   siblings come before it at top/leading, after it at bottom/trailing —
   flex has no order property, so the mirror reorders the child list. *)
let ordered_child_ids store id kind : int list =
  let ids = Lui_store.child_ids store id in
  if kind <> "edge-inset" then ids
  else
    match ids with
    | [] -> []
    | content :: pinned -> (
      match pstr store id "edge" with
      | Some ("bottom" | "trailing") -> ids
      | _ -> pinned @ [ content ])

(* Resolve a length against an owner dimension; non-absolute specs
   count as zero for the purposes of these patches. *)
let len_px ~owner (l : Lui_flex.length) : float =
  match l with
  | Pt v -> v
  | Percent p -> owner *. p /. 100.
  | _ -> 0.

(* One named edge of an [edges] record, following the engine's cascade:
   named side > axis shorthand (horizontal/vertical) > all. *)
let edge_px ~owner named axis (e : Lui_flex.edges) : float =
  let defined (l : Lui_flex.length) =
    match l with Unset | Auto -> false | _ -> true
  in
  if defined named then len_px ~owner named
  else if defined axis then len_px ~owner axis
  else len_px ~owner e.all

(* ---------- mirror ---------- *)

let display_none store id = pstr store id "display" = Some "none"
let display_contents store id = pstr store id "display" = Some "contents"

(* The string a text leaf measures: [text], else [placeholder], else
   [title] (bottom-tab and timeline items carry their label on the
   latter). Empty editable controls still need their line height. *)
let text_of store id =
  match Lui_store.prop store id "text" with
  | Some (StringValue s) when s <> "" -> Some s
  | _ -> (
    match Lui_store.prop store id "placeholder" with
    | Some (StringValue s) when s <> "" -> Some s
    | _ -> (
      match Lui_store.prop store id "title" with
      | Some (StringValue s) when s <> "" -> Some s
      | _ ->
          if Lui_store.is_editable_text_kind (Lui_store.kind store id)
          then Some ""
          else None))

let measure_of (tm : text_measure) ~id ~text : Lui_flex.measure =
  fun _node ~width ~width_mode:_ ~height ~height_mode:_ ->
    match tm id text width height with
    | Some (w, h) -> { Lui_flex.width = w; height = h }
    | None -> { Lui_flex.width = 0.; height = 0. }

type ctx = {
  scale : float;
  vw : float;
  vh : float;
  tm : text_measure;
  image_measure : image_measure;
  hidden : int -> bool; (* host-owned transient visibility (menus) *)
  ctx_anchor : (float * float) option; (* pointer point for context menus *)
  store : Lui_store.t;
  eng : t; (* back-reference: root and rects *)
  nodes : (int, Lui_flex.node) Hashtbl.t; (* store id → flex node *)
  applied : (int, Lui_flex.style) Hashtbl.t; (* store id → applied style *)
  pkids : (int, pkid list) Hashtbl.t;
  sparent : (int, int) Hashtbl.t;
  owner : (int, int) Hashtbl.t;
  grids : (int * Lui_flex.node * Lui_flex.style * float) list ref;
  popups : (Lui_flex.node * int) list ref; (* flex node, store id *)
  vlists : (int, vlist) Hashtbl.t; (* virtual-list states (t.vlists) *)
  (* Virtual lists a journal op touched this sync — resynced before
     layout (row forests are rebuilt, never edited in place). *)
  vresync : (int, unit) Hashtbl.t;
}

(* ---------- virtual-list extent model ----------

   Per-item main extents feed a Fenwick tree over stride = extent + gap,
   so index→offset and offset→index are both O(log n): prefix(i) is
   the content-space offset of item i inside the padding box. *)

let vlist_ext (v : vlist) i =
  match Hashtbl.find_opt v.measured i with
  | Some h -> h
  | None -> v.estimate

(* Sum of strides[0..i) — item i's offset within the padding box. *)
let bit_sum (bit : float array) i =
  let rec go i acc =
    if i <= 0 then acc else go (i - (i land (-i))) (acc +. bit.(i))
  in
  go i 0.

let bit_add (bit : float array) i d =
  let n = Array.length bit - 1 in
  let rec go i =
    if i <= n then begin
      bit.(i) <- bit.(i) +. d;
      go (i + (i land (-i)))
    end
  in
  go (i + 1)

(* Largest i ∈ [0,n] with prefix(i) ≤ y: the index of the item whose
   span contains y (n when y lies past the content end). *)
let bit_lower (bit : float array) y =
  let n = Array.length bit - 1 in
  let idx = ref 0 and acc = ref 0. in
  let k = ref 1 in
  while !k * 2 <= n do
    k := !k * 2
  done;
  while !k > 0 do
    let nx = !idx + !k in
    if nx <= n && !acc +. bit.(nx) <= y then begin
      idx := nx;
      acc := !acc +. bit.(nx)
    end;
    k := !k lsr 1
  done;
  !idx

let vlist_total (v : vlist) =
  v.pad0
  +. (if v.count = 0 then 0. else bit_sum v.bit v.count -. v.gap)
  +. v.pad1

let vlist_rebuild_bit (v : vlist) =
  let n = v.count in
  let bit = Array.make (n + 1) 0. in
  for i = 0 to n - 1 do
    bit.(i + 1) <- vlist_ext v i +. v.gap
  done;
  for i = 1 to n do
    let j = i + (i land (-i)) in
    if j <= n then bit.(j) <- bit.(j) +. bit.(i)
  done;
  v.bit <- bit;
  v.total <- vlist_total v

let vlist_measure (v : vlist) i h =
  let old = vlist_ext v i in
  if Float.abs (h -. old) > 0.01 then begin
    Hashtbl.replace v.measured i h;
    bit_add v.bit i (h -. old);
    v.total <- v.total +. (h -. old)
  end

let vlist_state ctx id =
  match Hashtbl.find_opt ctx.vlists id with
  | Some v -> v
  | None ->
    let v =
      {
        vid = id;
        count = 0;
        kids = [||];
        estimate = 0.;
        overscan = 4;
        gap = 0.;
        pad0 = 0.;
        pad1 = 0.;
        bor0 = 0.;
        bor1 = 0.;
        origin_main = 0.;
        origin_cross = 0.;
        cross_size = 0.;
        measured = Hashtbl.create 16;
        bit = [| 0. |];
        total = 0.;
        first = 0;
        last = 0;
        vs = 0.;
        ve = 0.;
        windowed = false;
        drift = 0.;
        rows = Hashtbl.create 16;
        nodes = Hashtbl.create 64;
        mounted_ids = [];
        key_index = None;
        id_index = None;
        built_cross = 0.;
      }
    in
    Hashtbl.replace ctx.vlists id v;
    v

(* data-attrs is the wire-clean channel for virtual-list config that
   the schema does not model: [data-item-extent] is the estimated row
   main extent in logical px, [data-overscan] the extra rows mounted
   past each viewport edge, [data-scroll-target]/[data-scroll-token]/
   [data-scroll-anchor] the scroll-request triple and
   [data-track-visible-range] the visible-range opt-in. *)
let vlist_data_attr store id name =
  match Lui_store.prop store id "data-attrs" with
  | Some (StringValue s) -> (
    try List.assoc_opt name (Lui_protocol.data_attrs_decode s)
    with Invalid_argument _ -> None)
  | _ -> None

(* M3 virtualizes the vertical axis only: a horizontal virtual-list
   keeps the ordinary flow path (all children in the mirror). *)
let vlist_vertical store id =
  pstr store id "orientation" <> Some "horizontal"

(* Pull the model inputs off the resolved style and the data-attrs.
   [style] is the vlist's own flex style — padding, border and the
   row gap come straight from it. *)
let vlist_configure ctx store (v : vlist) (style : Lui_flex.style) =
  (* The logical child ids snapshot: [count] stays O(1) on the store,
     but a per-row indexed probe on the intrusive child list is O(i),
     so the window machinery reads this array instead. One O(count)
     materialization per structural sync — the same order the mirror
     build already pays. *)
  v.kids <- Array.of_list (Lui_store.child_ids store v.vid);
  let count = Lui_store.child_count store v.vid in
  let gap = len_px ~owner:ctx.vh style.row_gap in
  let estimate =
    match
      Option.bind
        (vlist_data_attr store v.vid "data-item-extent")
        (fun s -> float_of_string_opt (String.trim s))
    with
    | Some f when f > 0. -> f *. ctx.scale
    | _ -> (
      match if count > 0 then v.kids.(0) else -1 with
      | cid when cid >= 0 -> (
        match pnum store cid "height" with
        | Some h -> h *. ctx.scale
        | None -> 28. *. ctx.scale)
      | _ -> 28. *. ctx.scale)
  in
  let overscan =
    match
      Option.bind
        (vlist_data_attr store v.vid "data-overscan")
        (fun s -> int_of_string_opt (String.trim s))
    with
    | Some n -> max 0 n
    | None -> 4
  in
  (* Configure runs once per structural sync; child props may have
     changed under a stable shape, so the lazy lookup indexes rebuild
     on demand. *)
  v.key_index <- None;
  v.id_index <- None;
  let shape_changed =
    count <> v.count || estimate <> v.estimate || gap <> v.gap
  in
  v.count <- count;
  v.estimate <- estimate;
  v.overscan <- overscan;
  v.gap <- gap;
  v.pad0 <-
    edge_px ~owner:ctx.vh style.padding.top style.padding.vertical
      style.padding;
  v.pad1 <-
    edge_px ~owner:ctx.vh style.padding.bottom style.padding.vertical
      style.padding;
  v.bor0 <-
    edge_px ~owner:ctx.vh style.border.top style.border.vertical
      style.border;
  v.bor1 <-
    edge_px ~owner:ctx.vh style.border.bottom style.border.vertical
      style.border;
  if shape_changed then begin
    Hashtbl.filter_map_inplace
      (fun i h -> if i < count then Some h else None)
      v.measured;
    vlist_rebuild_bit v
  end
  else v.total <- vlist_total v

(* The leaf patch: a self-sizing virtual list claims the virtual
   content extent as its minimum main size, so the frame grows to the
   full logical content exactly like the un-windowed flow did. *)
let vlist_leaf_style ctx (v : vlist) (style : Lui_flex.style) :
    Lui_flex.style =
  match style.height with
  | Unset ->
    let want = v.bor0 +. v.total +. v.bor1 in
    let cur = len_px ~owner:ctx.vh style.min_height in
    { style with min_height = Pt (Float.max cur want) }
  | _ -> style

(* Mounted window [first, last) of item indices: the fed viewport
   expanded by [overscan] strides, clamped to \[0, count]. *)
let vlist_range (v : vlist) =
  if (not v.windowed) || v.count = 0 then (0, v.count)
  else begin
    let over =
      float_of_int v.overscan *. Float.max (v.estimate +. v.gap) 1.
    in
    let item_at y =
      min (v.count - 1)
        (bit_lower v.bit (Float.max 0. (y -. v.bor0 -. v.pad0)))
    in
    let first = max 0 (item_at (v.vs -. over)) in
    let last =
      min v.count
        (bit_lower v.bit
           (Float.max 0. (v.vs +. v.ve +. over -. v.bor0 -. v.pad0))
        + 1)
    in
    (first, max first last)
  end

let kind_of ctx id = if id = frame_id then "frame" else Lui_store.kind ctx.store id

(* What a store node produces into its flex parent's children. *)
type nstatus = N_hidden | N_contents | N_normal

let status_of ctx id =
  if display_none ctx.store id || ctx.hidden id
     || not (Lui_store.anchor_available ctx.store id) then N_hidden
  else if display_contents ctx.store id then N_contents
  else N_normal

let pkids_of ctx p = Option.value ~default:[] (Hashtbl.find_opt ctx.pkids p)

(* Produced gens from mirror state only — never builds. *)
let peek_produced ctx id =
  match status_of ctx id with
  | N_hidden -> []
  | N_normal -> if Hashtbl.mem ctx.nodes id then [ id ] else []
  | N_contents -> List.concat_map (fun e -> e.gens) (pkids_of ctx id)

(* The store id owning the flex node p's produced children land in: p
   itself when it has a flex node, else the nearest ancestor with one
   (contents/hidden nodes lift their produced set up the raw chain). *)
let children_owner ctx p =
  if Hashtbl.mem ctx.nodes p then p
  else
    let rec climb x =
      match Hashtbl.find_opt ctx.sparent x with
      | Some par ->
        if par = frame_id || Hashtbl.mem ctx.nodes par then par
        else climb par
      | None -> frame_id
    in
    climb p

(* A node whose produced children are all popup surfaces (e.g. a menu
   trigger) still sizes to its own label — the popups are out of flow
   and contribute nothing. *)
let popup_min_style ctx id cids kids (style : Lui_flex.style) : Lui_flex.style =
  let text = text_of ctx.store id in
  match (kids, text) with
  | _ :: _, Some t
    when List.for_all
           (fun cid -> popup_kind (Lui_store.kind ctx.store cid))
           cids -> (
    match ctx.tm id t ctx.vw ctx.vh with
    | Some (tw, th) ->
      { style with
        min_width =
          (match (style.width, style.min_width) with
           | Unset, Unset -> Pt tw
           | _, l -> l);
        min_height =
          (match (style.height, style.min_height) with
           | Unset, Unset -> Pt th
           | _, l -> l) }
    | None -> style)
  | _ -> style

let image_measure_of ctx id _node ~width ~width_mode ~height ~height_mode =
  match ctx.image_measure id with
  | None -> {Lui_flex.width=0.;height=0.}
  | Some (natural_width,natural_height) ->
      let source_width=Option.value (pnum ctx.store id "source-width") ~default:natural_width
      and source_height=Option.value (pnum ctx.store id "source-height") ~default:natural_height in
      let natural_width=source_width *. ctx.scale and natural_height=source_height *. ctx.scale in
      let cap mode offered natural = match mode with
        | Lui_flex.Measure_undefined -> natural
        | Measure_exactly | Measure_at_most -> Float.min offered natural
        | Measure_invalid -> invalid_arg "Invalid image measure mode" in
      let width,height=match width_mode,height_mode with
        | Lui_flex.Measure_exactly,Measure_exactly -> width,height
        | Measure_exactly,_ -> width,cap height_mode height (width *. natural_height /. natural_width)
        | _,Measure_exactly -> cap width_mode width (height *. natural_width /. natural_height),height
        | _ ->
            let factor=Float.min
              (cap width_mode width natural_width /. natural_width)
              (cap height_mode height natural_height /. natural_height) in
            natural_width *. factor,natural_height *. factor in
      {Lui_flex.width;height}

let measure_for ctx id ~kids : Lui_flex.measure option =
  let choice =
    match Lui_store.kind ctx.store id with
    | "checkbox" | "radio" -> true
    | _ -> false
  in
  let chrome = if choice then 16. *. ctx.scale else 0. in
  match (kids, text_of ctx.store id) with
  | [], None when Lui_store.kind ctx.store id = "image" -> Some (image_measure_of ctx id)
  | [], None when choice ->
      Some
        (fun _ ~width:_ ~width_mode:_ ~height:_ ~height_mode:_ ->
          { Lui_flex.width = chrome; height = chrome })
  | [], Some t ->
      let icon_extra =
        match Lui_store.string_prop ctx.store id "icon" with
        | Some name when name <> "" ->
            16. +. Option.value ~default:6. (pnum ctx.store id "gap")
        | _ -> 0.
      in
      let indicator_extra =
        match Lui_store.kind ctx.store id with
        | "select" | "combobox" ->
            16. +. Option.value ~default:8. (pnum ctx.store id "gap")
        | _ -> 0.
      in
      (* Picker indicators reserve their width and requested label gap. *)
      let choice_extra = if choice then
        16. +. Option.value ~default:8. (pnum ctx.store id "gap") else 0. in
      let extra =
        (icon_extra +. indicator_extra +. choice_extra) *. ctx.scale
      in
      if extra > 0. then
        Some
          (fun node ~width ~width_mode ~height ~height_mode ->
            let d =
              measure_of ctx.tm ~id ~text:t node ~width ~width_mode ~height
                ~height_mode
            in
            {
              Lui_flex.width = Float.max chrome (d.Lui_flex.width +. extra);
              height = Float.max chrome d.Lui_flex.height;
            })
      else Some (measure_of ctx.tm ~id ~text:t)
  | _ -> None

let register ctx id kind node style =
  (if kind = "table" then
     Hashtbl.replace ctx.eng.tables id
       { rows = [||]; natural = None; minima = [||]; assigned_width = Float.nan });
  (if kind = "grid" then
     match pnum ctx.store id "columns" with
     | Some n when n > 0. ->
       ctx.grids := (id, node, style, n) :: !(ctx.grids)
     | _ -> ());
  if popup_kind kind
     && not (kind = "drawer" && has_prop ctx.store id "selected")
  then ctx.popups := (node, id) :: !(ctx.popups)

let unregister ctx id =
  Hashtbl.remove ctx.eng.tables id;
  ctx.grids := List.filter (fun (g, _, _, _) -> g <> id) !(ctx.grids);
  ctx.popups := List.filter (fun (_, s) -> s <> id) !(ctx.popups)

(* [build] expands a store node into (flex node, generator store id)
   pairs — a singleton for normal kinds, [] for display:none/hidden,
   the lifted produced pairs for display:contents. Every mirror map is
   populated as it goes: nodes/applied/owner per built node, pkids and
   sparent per expanded parent. [index] is the flattened sibling
   position inside the produced children of [pid]. *)
let rec build ctx ~owner_id ~pkind ~pid ~index id : (Lui_flex.node * int) list =
  match status_of ctx id with
  | N_hidden -> []
  | N_contents ->
    let cids =
      ordered_child_ids ctx.store id (Lui_store.kind ctx.store id)
    in
    fst
      (expand_children ctx ~owner:owner_id ~pkind ~pid ~raw_parent:id
         ~first:index cids)
  | N_normal ->
    let kind = Lui_store.kind ctx.store id in
    let style =
      style_of ~scale:ctx.scale ~viewport:(ctx.vw, ctx.vh) ctx.store id
      |> adjust ~scale:ctx.scale ~pkind ~pid ~index ctx.store id
    in
    if kind = "virtual-list" && vlist_vertical ctx.store id then begin
      (* Real virtualization: the list is a leaf in this mirror — only
         the mounted row window gets flex trees (side forest). Its
         produced child list stays empty; [pkids] records the leaf. *)
      let v = vlist_state ctx id in
      vlist_configure ctx ctx.store v style;
      let style = vlist_leaf_style ctx v style in
      let node = Lui_flex.create ~style [] in
      Hashtbl.replace ctx.nodes id node;
      Hashtbl.replace ctx.applied id style;
      Hashtbl.replace ctx.owner id owner_id;
      Hashtbl.replace ctx.pkids id [];
      register ctx id kind node style;
      [ (node, id) ]
    end
    else
    let cids = ordered_child_ids ctx.store id kind in
    let kids, () =
      expand_children ctx ~owner:id ~pkind:kind ~pid:id ~raw_parent:id
        ~first:0 cids
    in
    let kids = List.map fst kids in
    let style = popup_min_style ctx id cids kids style in
    let m = measure_for ctx id ~kids in
    let node = Lui_flex.create ~style ?measure:m kids in
    Hashtbl.replace ctx.nodes id node;
    Hashtbl.replace ctx.applied id style;
    Hashtbl.replace ctx.owner id owner_id;
    register ctx id kind node style;
    [ (node, id) ]

(* Build each raw child of [raw_parent], recording sparent per child
   and pkids[raw_parent]. [owner] is the flex owner the produced pairs
   belong to — for a contents raw_parent the enclosing owner's values
   pass straight through, exactly like [pkind]/[pid] did at rebuild
   time. *)
and expand_children ctx ~owner ~pkind ~pid ~raw_parent ~first cids =
  let counter = ref first in
  let acc = ref [] and entries = ref [] in
  List.iter
    (fun cid ->
      let pairs =
        build ctx ~owner_id:owner ~pkind ~pid ~index:!counter cid
      in
      counter := !counter + List.length pairs;
      Hashtbl.replace ctx.sparent cid raw_parent;
      entries := { raw = cid; gens = List.map snd pairs } :: !entries;
      acc := List.rev_append pairs !acc)
    cids;
  Hashtbl.replace ctx.pkids raw_parent (List.rev !entries);
  (List.rev !acc, ())

(* A table owns its column widths. Row-local flex sizing would move each
   boundary according to the contents of that particular row. Natural widths
   are measured only when a table subtree changes, then retained on resize. *)
let table_children ctx id =
  List.fold_left (fun acc entry -> List.rev_append entry.gens acc)
    [] (pkids_of ctx id) |> List.rev |> Array.of_list

let ordered_tables ctx =
  let depths = Hashtbl.create 8 in
  let rec depth id =
    if id = frame_id then 0
    else match Hashtbl.find_opt depths id with
    | Some d -> d
    | None ->
      let d = 1 + depth (Hashtbl.find ctx.owner id) in
      Hashtbl.add depths id d;
      d in
  Hashtbl.fold (fun id table acc -> (depth id, id, table) :: acc)
    ctx.eng.tables []
  |> List.sort (fun (a, _, _) (b, _, _) -> Int.compare a b)

let set_table_columns ctx table widths =
  Array.iter (fun row ->
    Array.iteri (fun index id ->
      let style = Hashtbl.find ctx.applied id in
      let width = Pt widths.(index) in
      Lui_flex.set_style (Hashtbl.find ctx.nodes id)
        { style with width; flex_basis = width; flex_grow = 0.;
          flex_shrink = 0.; min_width = Pt 0.; max_width = Unset;
          align_self = Align_stretch }) row) table.rows

let prepare_tables ctx tables =
  List.iter (fun (_, id, table) ->
    if table.natural = None then begin
      table.rows <- Array.map (table_children ctx) (table_children ctx id);
      let count = Array.fold_left (fun n row -> max n (Array.length row))
        0 table.rows in
      let natural = Array.make count 0. in
      let minima = Array.make count 0. in
      Array.iter (fun row ->
        Array.iteri (fun index cell ->
          let node = Hashtbl.find ctx.nodes cell in
          let style = Hashtbl.find ctx.applied cell in
          Lui_flex.set_style node style;
          Lui_flex.compute_layout node ~width:Lui_flex.undefined
            ~height:Lui_flex.undefined ();
          natural.(index) <- Float.max natural.(index) (Lui_flex.layout node).w;
          let edge edges a b axis =
            edge_px ~owner:ctx.vw a axis edges +.
            edge_px ~owner:ctx.vw b axis edges in
          let chrome = edge style.padding style.padding.left style.padding.right
              style.padding.horizontal +.
            edge style.border style.border.left style.border.right
              style.border.horizontal in
          minima.(index) <- Float.max minima.(index)
            (Float.max chrome (len_px ~owner:ctx.vw style.min_width))) row)
        table.rows;
      table.natural <- Some natural;
      table.minima <- minima;
      table.assigned_width <- Float.nan;
      set_table_columns ctx table natural
    end) (List.rev tables)

(* Proportional natural widths with shared lower bounds. Freeze constrained
   columns in threshold order so many columns remain O(n log n). *)
let table_widths natural minima available =
  let count = Array.length natural in
  let total = Array.fold_left (+.) 0. natural in
  if total = 0. then Array.make count
    (if count = 0 then 0. else available /. float_of_int count)
  else begin
    let remaining = ref available and weight = ref total in
    let indices = Array.init count Fun.id in
    let threshold i = if natural.(i) = 0. then 0.
      else minima.(i) /. natural.(i) in
    Array.sort (fun a b -> Float.compare (threshold b) (threshold a)) indices;
    let widths = Array.make count 0. in
    Array.iter (fun i ->
      let share = if !weight = 0. then 0.
        else Float.max 0. (!remaining /. !weight) in
      if natural.(i) *. share < minima.(i) then begin
        widths.(i) <- minima.(i);
        remaining := !remaining -. minima.(i);
        weight := !weight -. natural.(i)
      end) indices;
    let share = if !weight = 0. then 0.
      else Float.max 0. (!remaining /. !weight) in
    Array.iteri (fun i _ ->
      widths.(i) <- Float.max minima.(i) (natural.(i) *. share)) widths;
    widths
  end

let refine_tables ctx tables ~relayout =
  let current_depth = ref (-1) and changed = ref false in
  List.iter (fun (depth, id, table) ->
    if depth <> !current_depth then begin
      if !changed then relayout ();
      changed := false;
      current_depth := depth
    end;
    let style = Hashtbl.find ctx.applied id in
    let rect = Lui_flex.layout (Hashtbl.find ctx.nodes id) in
    let edge edges a b axis =
      edge_px ~owner:rect.w a axis edges +.
      edge_px ~owner:rect.w b axis edges in
    let available = Float.max 0. (rect.w -.
      edge style.padding style.padding.left style.padding.right style.padding.horizontal -.
      edge style.border style.border.left style.border.right style.border.horizontal) in
    if table.assigned_width <> available then begin
      set_table_columns ctx table
        (table_widths (Option.get table.natural) table.minima available);
      table.assigned_width <- available;
      changed := true
    end) tables;
  if !changed then relayout ()

(* ---------- two-pass refinement ----------

   Two contracts the engine cannot express in a single pass get patched
   here after the first layout, then the layout is re-run:

   - Grid cells: [flex_basis] can be a percent of the row but cannot
     subtract the gap share, so [columns = n] with a [gap] overflows
     the line and wraps early. The real basis is
     [(inner_width - (n-1) * gap) / n], computed once the grid's own
     width is known.
   - Popup surfaces: an absolute child has no centering primitive, so a
     popup-family node with no positioning props (no [position],
     [inset*], [x]/[y] or [anchor]) would land at its parent's origin.
     The default is centered in the containing block — the flex
     parent's border box, or the offered frame for a store-root popup. *)

(* Pin every flex child of a [columns = n] grid to its real share of
   the row so [n] cells plus [(n-1)] gaps fit one line. The produced
   children come from pkids — the mirror is persistent, so a reverse
   flex→store lookup is no longer needed. *)
let refine_grids ctx ~relayout =
  let refine (gsid, gnode, (gstyle : Lui_flex.style), ncols) =
    let gr = Lui_flex.absolute_layout gnode in
    let pl = edge_px ~owner:gr.w gstyle.padding.left gstyle.padding.horizontal gstyle.padding in
    let pr = edge_px ~owner:gr.w gstyle.padding.right gstyle.padding.horizontal gstyle.padding in
    let bl = edge_px ~owner:gr.w gstyle.border.left gstyle.border.horizontal gstyle.border in
    let br = edge_px ~owner:gr.w gstyle.border.right gstyle.border.horizontal gstyle.border in
    let inner_w = Float.max 0. (gr.w -. pl -. pr -. bl -. br) in
    let gap = len_px ~owner:inner_w gstyle.column_gap in
    (* The tiny epsilon guards the wrap test against float rounding
       pushing the last cell onto the next line. *)
    let basis =
      Float.max 0. ((inner_w -. (ncols -. 1.) *. gap) /. ncols -. 0.001)
    in
    List.iter
      (fun e ->
        List.iter
          (fun sid ->
            match
              (Hashtbl.find_opt ctx.applied sid,
               Hashtbl.find_opt ctx.nodes sid)
            with
            | Some s, Some f ->
              let span = Option.value (pnum ctx.store sid "grid-column-span") ~default:1. in
              if span>ncols then invalid_arg "grid column span exceeds column count";
              Lui_flex.set_style f
                { s with flex_basis = Pt (basis *. span +. gap *. (span -. 1.)) }
            | _ -> ())
          e.gens)
      (pkids_of ctx gsid)
  in
  (* A parent grid can change a descendant grid width during refinement.
     Resolve each ancestor level before measuring its descendants. Peers
     share a pass, and callers combine the final pass with popup layout. *)
  match !(ctx.grids) with
  | [] -> ()
  | [grid] -> refine grid
  | grids ->
    let members = Hashtbl.create (List.length grids) in
    List.iter (fun (id, _, _, _) -> Hashtbl.add members id ()) !(ctx.grids);
    let depths = Hashtbl.create (Hashtbl.length members) in
    let rec depth id =
      match Hashtbl.find_opt depths id with
      | Some value -> value
      | None ->
        let value = match Lui_store.parent ctx.store id with
          | None -> 0
          | Some parent -> depth parent + (if Hashtbl.mem members parent then 1 else 0)
        in
        Hashtbl.add depths id value;
        value
    in
    let ordered = List.stable_sort
      (fun (a, _, _, _) (b, _, _, _) -> Int.compare (depth a) (depth b))
      !(ctx.grids) in
    let rec apply = function
      | [] -> ()
      | ((id, _, _, _) as grid) :: rest ->
        refine grid;
        (match rest with
         | (next, _, _, _) :: _ when depth next <> depth id -> relayout ()
         | _ -> ());
        apply rest
    in
    apply ordered

(* Popup anchoring: [x]/[y] supply an anchor point (a zero-size anchor
   box inside the containing block); bare [anchor] uses the parent rect
   as the anchor box, like the web backend's element anchoring. [anchor]
   names the preferred side (below default), [anchor-alignment] the
   cross-axis alignment (start default), [anchor-offset] the gap
   (4px default). *)
let frozen_anchor store id =
  Option.bind (pstr store id "anchor-rect") Lui_protocol.anchor_rect_of_string

let anchor_rect_of ctx store id ~cb pr =
  let s = ctx.scale in
  let f name = Option.map (fun v -> v *. s) (pnum store id name) in
  match (f "x", f "y") with
  | Some x, Some y -> { Lui_flex.x = cb.x +. x; y = cb.y +. y; w = 0.; h = 0. }
  | _ -> pr

let anchored_xy ?resolved_side ctx store sid ar (prp : Lui_flex.rect) =
  let s = ctx.scale in
  let offset = Option.value ~default:4. (pnum store sid "anchor-offset") *. s in
  let side =
    match (match resolved_side with Some side -> Some side | None -> pstr store sid "anchor") with
    | Some ("above" | "left" | "right" as v) -> v
    | _ -> "below"
  in
  let alignment =
    match pstr store sid "anchor-alignment" with
    | Some ("center" | "middle") -> "middle"
    | Some "end" -> "end"
    | _ -> "start"
  in
  let vertical = side = "above" || side = "below" in
  let main =
    let start, finish, extent, viewport =
      if vertical then ar.y, ar.y +. ar.h, prp.h, ctx.vh
      else ar.x, ar.x +. ar.w, prp.w, ctx.vw in
    let before = start -. offset and after = viewport -. finish -. offset in
    let preferred_before = side = "above" || side = "left" in
    let preferred, opposite =
      if preferred_before then before, after else after, before in
    let place_before =
      if resolved_side = None && extent > preferred && opposite > preferred
      then not preferred_before else preferred_before in
    if place_before then start -. offset -. extent else finish +. offset
  in
  let cross =
    if vertical then
      match alignment with
      | "middle" -> ar.x +. ((ar.w -. prp.w) /. 2.)
      | "end" -> ar.x +. ar.w -. prp.w
      | _ -> ar.x
    else
      match alignment with
      | "middle" -> ar.y +. ((ar.h -. prp.h) /. 2.)
      | "end" -> ar.y +. ar.h -. prp.h
      | _ -> ar.y
  in
  let alignment_offset = Option.value ~default:0. (pnum store sid "anchor-alignment-offset") *. s in
  let cross = cross +. (if alignment = "end" then -.alignment_offset else alignment_offset) in
  let x, y = if vertical then (cross, main) else (main, cross) in
  (* Clamp inside the viewport so the popup stays on-screen — the
     containing block may be smaller than the panel (a menu
     trigger). *)
  let edge = if frozen_anchor store sid <> None then 8. *. s else 0. in
  ( Float.max edge (Float.min x (Float.max edge (ctx.vw -. prp.w -. edge))),
    Float.max edge (Float.min y (Float.max edge (ctx.vh -. prp.h -. edge))) )

(* Center each default-placed popup in its containing block by giving
   its spec concrete [left]/[top] offsets. Position edges resolve
   against the parent's padding box (offset + border + margin lands at
   the child's layout position), so the center of the border box is
   [parent.w/2 - border - margin]. *)
let refine_popups ctx =
  (* Bottom y of the last placed toast per containing block, so a
     viewport's toasts stack downward like the web viewport. *)
  let toast_next = Hashtbl.create 2 in
  (* Ancestor surfaces are positioned before the final flex pass. Resolve
     descendant anchors in that final coordinate space, especially when a
     viewport collision clamps a menu inside a newly centered dialog. *)
  let placed = Hashtbl.create 4 in
  let final_rect sid node =
    match Hashtbl.find_opt placed sid with
    | Some r -> r
    | None ->
      let r = Lui_flex.absolute_layout node in
      let rec displacement id =
        match Hashtbl.find_opt ctx.owner id with
        | None -> 0.,0.
        | Some parent when parent = frame_id -> 0.,0.
        | Some parent ->
          match Hashtbl.find_opt placed parent with
          | None -> displacement parent
          | Some target ->
            let before = Lui_flex.absolute_layout (Hashtbl.find ctx.nodes parent) in
            target.Lui_flex.x -. before.x, target.y -. before.y
      in
      let dx,dy = displacement sid in
      {r with Lui_flex.x=r.x+.dx; y=r.y+.dy}
  in
  let select_alignment sid parent (popup : Lui_flex.rect) =
    if
      Lui_store.kind ctx.store sid <> "dropdown-menu"
      || has_prop ctx.store sid "x" || has_prop ctx.store sid "y"
    then None
    else
      let picker =
        List.find_opt
          (fun id ->
            Lui_store.kind ctx.store id = "select" && Hashtbl.mem ctx.nodes id)
          (Lui_store.child_ids ctx.store parent)
      in
      let items =
        List.filter
          (fun id ->
            Lui_store.kind ctx.store id = "menu-item"
            && Lui_store.prop ctx.store id "enabled" <> Some (BoolValue false)
            && Hashtbl.mem ctx.nodes id)
          (Lui_store.child_ids ctx.store sid)
      in
      let selected =
        match
          List.find_opt
            (fun id -> Lui_store.bool_prop ctx.store id "selected")
            items
        with
        | Some id -> Some id
        | None -> List.nth_opt items 0
      in
      match (picker, selected) with
      | Some picker, Some selected ->
          let anchor = final_rect picker (Hashtbl.find ctx.nodes picker)
          and item = Lui_flex.absolute_layout (Hashtbl.find ctx.nodes selected) in
          let value = Lui_paint.text_placement_of ctx.store picker
          and label = Lui_paint.text_placement_of ctx.store selected in
          let s = ctx.scale in
          let center (r : Lui_flex.rect) p =
            r.y
            +. ((r.h +. ((p.Lui_paint.tp_pad_top -. p.tp_pad_bottom) *. s)) /. 2.)
          in
          let x =
            anchor.x +. (value.tp_pad_left *. s)
            -. (item.x -. popup.x +. (label.tp_pad_left *. s))
          and y = center anchor value -. (center item label -. popup.y) in
          if
            anchor.y >= 20. *. s
            && anchor.y +. anchor.h <= ctx.vh -. (20. *. s)
            && x >= 8. *. s
            && x +. popup.w <= ctx.vw -. (8. *. s)
            && y >= 8. *. s
            && y +. popup.h <= ctx.vh -. (8. *. s)
          then Some (x, y)
          else None
      | _ -> None
  in
  let refine (pnode, sid) =
      match Lui_flex.parent pnode with
      | None -> ()
      | Some parent -> (
        (* The flex parent's store id is the popup's recorded owner —
           [frame_id] means the popup sits directly under the root. *)
        let psid_opt =
          match Hashtbl.find_opt ctx.owner sid with
          | Some o when o <> frame_id -> Some o
          | _ -> None
        in
        let pr, pstyle_opt =
          match psid_opt with
          | Some psid ->
            ( final_rect psid parent,
              Hashtbl.find_opt ctx.applied psid )
          | None ->
            (* The frame root is no store node's containing block —
               default to the offered frame, not the grown extent. *)
            ( { Lui_flex.x = 0.; y = 0.; w = ctx.vw; h = ctx.vh },
              None )
        in
        let snapshot = frozen_anchor ctx.store sid in
        let anchor_id, anchor_rect =
          match snapshot with
          | Some (x, y, width, height) ->
              let px, py = ctx.eng.anchor_shift sid in
              None, {Lui_flex.x=x *. ctx.scale -. px; y=y *. ctx.scale -. py;
                     w=width *. ctx.scale; h=height *. ctx.scale}
          | None -> match pstr ctx.store sid "anchor-target" with
          | None -> psid_opt, pr
          | Some identifier ->
              (match Lui_store.find_identifier ctx.store identifier with
               | Some target ->
                   (match Hashtbl.find_opt ctx.nodes target with
                    | Some target_node ->
                        let region = final_rect target target_node in
                        let tx,ty = ctx.eng.anchor_shift target
                        and px,py = ctx.eng.anchor_shift sid in
                        Some target, { region with x=region.x +. tx -. px; y=region.y +. ty -. py }
                    | None -> None, { Lui_flex.x=0.; y=0.; w=0.; h=0. })
               | None -> None, { Lui_flex.x=0.; y=0.; w=0.; h=0. })
        in
        let bor_l, bor_t, bor_r, _bor_b =
          match pstyle_opt with
          | Some (ps : Lui_flex.style) ->
            ( edge_px ~owner:pr.w ps.border.left ps.border.horizontal ps.border,
              edge_px ~owner:pr.h ps.border.top ps.border.vertical ps.border,
              edge_px ~owner:pr.w ps.border.right ps.border.horizontal ps.border,
              edge_px ~owner:pr.h ps.border.bottom ps.border.vertical ps.border )
          | None -> (0., 0., 0., 0.)
        in
        (* The containing block a popup places against is the nearest
           out-of-flow ancestor (popup kinds, [position] edges, shared-
           cell overlays) — layers and nested popups anchor it, while
           in-flow parents keep sizing to content. The flex parent is
           the fallback and the bare-[anchor] target (its trigger). *)
        let cb =
          (* [position:fixed] anchors to the viewport itself, not to
             positioned ancestors — the native tree is document-
             anchored, so a fixed layer pinned to (0,0,vw,vh) outside
             any scroller behaves like the web fixed layer. *)
          match pstr ctx.store sid "position" with
          | Some "fixed" -> { Lui_flex.x = 0.; y = 0.; w = ctx.vw; h = ctx.vh }
          | _ ->
          let rec positioned id =
            match Hashtbl.find_opt ctx.applied id with
            | Some (a : Lui_flex.style)
              when a.position_type = Lui_flex.Absolute -> (
              match Hashtbl.find_opt ctx.nodes id with
              | Some n -> Some (final_rect id n)
              | None -> None)
            | _ -> (
              match Lui_store.parent ctx.store id with
              | Some anc -> positioned anc
              | None -> None)
          in
          match psid_opt with
          | Some psid -> (match positioned psid with
            | Some r -> r
            | None -> pr)
          | None -> pr
        in
        match Hashtbl.find_opt ctx.applied sid with
        | None -> ()
        | Some (pstyle : Lui_flex.style) ->
          let max_height =
            let menu = Lui_paint.menu_kind ctx.store sid (Lui_store.kind ctx.store sid) in
            let viewport = Float.max 0. (ctx.vh -. (if menu then 16. *. ctx.scale else 0.)) in
            let declared = match pstyle.max_height with
              | Unset -> if menu then 288. *. ctx.scale else viewport
              | limit -> len_px ~owner:ctx.vh limit in
            let available = match pnum ctx.store sid "available-height" with
              | Some height -> height *. ctx.scale
              | None -> viewport in
            (* AvailableHeight is a popover contract, independent of its
               semantic role. Intersect every limit on each resize. *)
            Pt (Float.max 0. (Float.min viewport (Float.min declared available)))
          in
          let pstyle =
            (* A popup measures against the viewport, not its
               (possibly tiny) parent — bound its max extents and
               re-measure the subtree before placing it. *)
            { pstyle with
              max_width =
                (match Lui_store.kind ctx.store sid with
                 | "dialog" | "modal" ->
                   let available = Float.max 0. (ctx.vw -. (32. *. ctx.scale)) in
                   let declared = match pstyle.max_width with
                     | Unset -> available
                     | limit -> len_px ~owner:ctx.vw limit in
                   Pt (Float.min available declared)
                 | _ -> (match pstyle.max_width with Unset -> Pt ctx.vw | limit -> limit));
              max_height }
          in
          Lui_flex.set_style pnode pstyle;
          Lui_flex.compute_layout pnode ~width:Lui_flex.undefined
            ~height:Lui_flex.undefined ();
          let ml =
            edge_px ~owner:pr.w pstyle.margin.left pstyle.margin.horizontal pstyle.margin
          and mt =
            edge_px ~owner:pr.w pstyle.margin.top pstyle.margin.vertical pstyle.margin
          and mr =
            edge_px ~owner:pr.w pstyle.margin.right pstyle.margin.horizontal pstyle.margin
          and _mb =
            edge_px ~owner:pr.h pstyle.margin.bottom pstyle.margin.vertical pstyle.margin
          in
          let anchored =
            List.exists (has_prop ctx.store sid) [ "x"; "y"; "anchor" ]
            || (* trigger-owned menu panels anchor below their trigger *)
               (match Lui_store.parent ctx.store sid with
                | Some p -> Lui_store.kind ctx.store p = "menu-trigger"
                | None -> false)
          in
          if (not anchored) && popup_has_edges ctx.store sid then ()
          else
          let kind = Lui_store.kind ctx.store sid in
          (* Toasts keep the shared 22.5rem viewport cap. *)
          (match kind with
           | "toast" ->
             let w = Float.min (360. *. ctx.scale) ctx.vw in
             Lui_flex.set_style pnode
               { pstyle with max_width = Pt w };
             Lui_flex.compute_layout pnode ~width:Lui_flex.undefined
               ~height:Lui_flex.undefined ()
           | _ -> ());
          let prp = Lui_flex.absolute_layout pnode in
          (* Element-owned popovers shrink on their chosen side before
             placement, as the Web positioner does. Keep that side after
             remeasurement so shrinking cannot flip the decision back. *)
          let prp, resolved_side =
            match kind, pstr ctx.store sid "anchor", anchor_id with
            | "popover", Some ("below" | "above" as preferred), owner
              when (snapshot <> None || Option.fold ~none:false
                     ~some:(fun id -> Lui_store.kind ctx.store id <> "root") owner)
                   && not (has_prop ctx.store sid "x" || has_prop ctx.store sid "y") ->
              let offset = Option.value ~default:4. (pnum ctx.store sid "anchor-offset") *. ctx.scale in
              let above = Float.max 0. (anchor_rect.y -. offset -. 8. *. ctx.scale)
              and below = Float.max 0. (ctx.vh -. anchor_rect.y -. anchor_rect.h -. offset -. 8. *. ctx.scale) in
              let first, other = if preferred = "above" then above, below else below, above in
              let side, available =
                if prp.h <= first || first >= other then preferred, first
                else (if preferred = "above" then "below" else "above"), other in
              if available < prp.h then begin
                Lui_flex.set_style pnode {pstyle with max_height = Pt available};
                Lui_flex.compute_layout pnode ~width:Lui_flex.undefined ~height:Lui_flex.undefined ();
                Lui_flex.absolute_layout pnode, Some side
              end else prp, Some side
            | _ -> prp, None
          in
          (* Placement targets live in the containing block [cb] but the
             position edges resolve against the flex parent's padding
             box — express them as offsets from that origin. *)
          let cbx = cb.x -. pr.x and cby = cb.y -. pr.y in
          let center =
            ( cbx +. ((cb.w -. prp.w) /. 2.) -. bor_l -. ml,
              cby +. ((cb.h -. prp.h) /. 2.) -. bor_t -. mt )
          in
          let abs_of (ax, ay) =
            (ax -. pr.x -. bor_l -. ml, ay -. pr.y -. bor_t -. mt)
          in
          let left, top =
            if anchored then
              abs_of
                (match Option.bind psid_opt (fun parent -> select_alignment sid parent prp) with
                 | Some xy -> xy
                 | None -> anchored_xy ?resolved_side ctx ctx.store sid
                     (anchor_rect_of ctx ctx.store sid ~cb anchor_rect) prp)
            else
              (* Unanchored popups take their platform placement —
                 the web stylesheet's fixed rules: a context menu
                 opens at the pointer, sheets pin the right edge on
                 wide screens, toasts stack under the top-right toast
                 viewport, everything else centers. *)
              match kind with
              | "context-menu" -> (
                match ctx.ctx_anchor with
                | Some (cx, cy) ->
                  abs_of
                    (anchored_xy ctx ctx.store sid
                       { Lui_flex.x = cx; y = cy; w = 0.; h = 0. } prp)
                | None -> center)
              | "sheet" ->
                (cbx +. cb.w -. prp.w -. bor_r -. mr, cby -. bor_t -. mt)
              | "toast" ->
                (* Web .lui-toast-viewport: top:3rem right:1rem
                   (2rem when vw ≥ 500px), stacking downward. *)
                let top_m = 48. *. ctx.scale
                and right_m =
                  (if ctx.vw >= 500. *. ctx.scale then 32. else 16.)
                  *. ctx.scale
                in
                let y =
                  match Hashtbl.find_opt toast_next (cb.x, cb.y) with
                  | Some next -> next
                  | None -> cby +. top_m
                in
                Hashtbl.replace toast_next (cb.x, cb.y)
                  (y +. prp.h +. (8. *. ctx.scale));
                (cbx +. cb.w -. prp.w -. right_m -. bor_r -. mr, y)
              | _ -> center
          in
          (* Pin the viewport-measured box as explicit dimensions —
             the final layout pass re-measures absolute children
             against their parent, which would collapse the popup
             back to the parent's size. The sheet keeps its contract
             height: edge-to-edge on wide screens. *)
          let height =
            match kind with
            | "sheet" -> (
              match pstyle.height with
              | Unset -> Pt cb.h
              | h -> h)
            | _ -> Pt prp.h
          in
          Hashtbl.replace placed sid
            {prp with Lui_flex.x=pr.x+.bor_l+.ml+.left;
              y=pr.y+.bor_t+.mt+.top};
          Lui_flex.set_style pnode
            { pstyle with
              width = Pt prp.w;
              height;
              position =
                { pstyle.position with left = Pt left; top = Pt top } })
  in
  let ordered = List.rev !(ctx.popups) in
  let pending = Hashtbl.create (List.length ordered)
  and visited = Hashtbl.create (List.length ordered) in
  List.iter (fun ((_,id) as popup) -> Hashtbl.add pending id popup) ordered;
  let rec visit ((_,sid) as popup) =
    if not (Hashtbl.mem visited sid) then begin
      let rec ancestor id =
        match Hashtbl.find_opt ctx.owner id with
        | None -> ()
        | Some parent when parent = frame_id -> ()
        | Some parent ->
          (match Hashtbl.find_opt pending parent with
           | Some popup -> visit popup
           | None -> ancestor parent)
      in
      ancestor sid;
      Hashtbl.add visited sid ();
      refine popup
    end
  in
  (* Full rebuilds register children before parents; incremental mounts
     can do the reverse. Respect ancestor dependencies in both cases,
     preserving registration order for unrelated surfaces and toasts. *)
  List.iter visit ordered

(* Union of the frame children's absolute rect edges — the extent the
   laid-out content actually occupies. *)
let extent_of root : float * float =
  List.fold_left
    (fun (mx, my) c ->
      let r = Lui_flex.absolute_layout c in
      (Float.max mx (r.x +. r.w), Float.max my (r.y +. r.h)))
    (0., 0.)
    (Lui_flex.children root)

(* ---------- layout ---------- *)

(* The snap boundary of the pixel-snapping contract: flex math stays
   fractional, the exported rect is edge-snapped once here so paint,
   hit-test, scroll extents and damage bounds all share the same
   device-pixel geometry. *)
let scene_rect (r : Lui_flex.rect) : Lui_scene.rect =
  Lui_scene.rect_snap { x = r.x; y = r.y; w = r.w; h = r.h }

(* Re-read [id]'s absolute rect into [t.rects], marking it changed when
     it differs from what consumers last saw. *)
let update_rect (t : t) id r =
  let r' = scene_rect r in
  (match Hashtbl.find t.rects id with
   | old when old = r' -> ()
   | _ | exception Not_found -> Hashtbl.replace t.rect_changed id ());
  Hashtbl.replace t.rects id r'

let absolute_reader (t : t) =
  let resolved = Hashtbl.create (Hashtbl.length t.nodes) in
  let frame = Lui_flex.layout (Option.get t.root) in
  let rec read id =
    match Hashtbl.find resolved id with
    | rect -> rect
    | exception Not_found ->
      let local = Lui_flex.layout (Hashtbl.find t.nodes id) in
      let owner = Hashtbl.find t.owner id in
      let parent = if owner=frame_id then frame else read owner in
      (* Keep ancestor positions unsnapped: only the exported leaf edges
         round to device pixels, so fractional offsets cannot accumulate. *)
      let rect = {local with Lui_flex.x=parent.x +. local.x; y=parent.y +. local.y} in
      Hashtbl.add resolved id rect;
      rect in
  read

let collect (t : t) =
  let read = absolute_reader t in
  Hashtbl.iter (fun id _ -> update_rect t id (read id)) t.nodes

(* The set of ids whose absolute rect differed at the last rect
   refresh. Hands the table itself to the caller and installs a fresh
   one — ids a later refresh moves again simply re-mark. *)
let take_rect_changes (t : t) =
  let s = t.rect_changed in
  t.rect_changed <- Hashtbl.create (Hashtbl.length s);
  s

(* The frame style for one offered extent. *)
let frame_style_for width (height : Lui_flex.length) =
  { Lui_flex.default_style with
    flex_direction = Column; width = Pt width; height }

(* One layout that honours the frame contract. The offered extent is a
   floor: a first pass measured with an unbounded height reports the
   content's natural extent — a definite offered height (or frame spec)
   would cap every child's measured size, hiding overflow — and the
   final pass runs at [max (offered, content)]. Returns the used
   extent. *)
let layout_frame root ~width ~height : float * float =
  Lui_flex.set_style root (frame_style_for width Unset);
  Lui_flex.compute_layout root ~width ~height:undefined ();
  let ex, ey = extent_of root in
  let ew, eh = (Float.max width ex, Float.max height ey) in
  Lui_flex.set_style root (frame_style_for ew (Pt eh));
  Lui_flex.compute_layout root ~width:ew ~height:eh ();
  (ew, eh)

(* ---------- mirror purge and virtual-list ancestry ----------

   Shared by the virtual-list passes below and the incremental journal:
   row subtrees register into the mirror's shadow tables (pkids,
   sparent, owner) even though their flex nodes live in the list's own
   [v.nodes] table, so dropping a row must scrub both. *)

(* Remove id's flex node and every built descendant's mirror state —
   shadow tables included, so a dropped row leaves no trace the
   incremental path could trip over. *)
let rec purge ctx id =
  (match Hashtbl.find_opt ctx.pkids id with
   | Some es ->
     Hashtbl.remove ctx.pkids id;
     List.iter (fun e -> purge ctx e.raw) es
   | None -> ());
  Hashtbl.remove ctx.nodes id;
  Hashtbl.remove ctx.applied id;
  Hashtbl.remove ctx.sparent id;
  Hashtbl.remove ctx.owner id;
  Hashtbl.remove ctx.eng.rects id;
  (* A dropped rect is a geometry change too: paint consumers holding
     the old box must re-derive (their layout hook now answers zero). *)
  Hashtbl.replace ctx.eng.rect_changed id ();
  unregister ctx id

let vlist_of ctx id = if Hashtbl.mem ctx.vlists id then Some id else None

(* The live virtual list [id] sits inside, if any — strict ancestors
   only. [sparent] covers mounted row subtrees (row roots point at the
   list); the store parent covers everything else: unmounted items and
   nodes the journal just moved. *)
let rec vlist_ancestor ctx id =
  if id = frame_id then None
  else
    let above p =
      match vlist_of ctx p with
      | Some _ as v -> v
      | None -> vlist_ancestor ctx p
    in
    match Hashtbl.find_opt ctx.sparent id with
    | Some p -> above p
    | None -> (
      match Lui_store.parent ctx.store id with
      | Some p -> above p
      | None -> None)

(* Marks the enclosing list for resync; true when [id] sits inside one. *)
let under_vlist ctx id =
  match vlist_ancestor ctx id with
  | Some v -> Hashtbl.replace ctx.vresync v (); true
  | None -> false

(* Same, but [id] itself counts: the parent argument of a child op is
   the list it lands in, not a node inside it. *)
let in_vlist ctx id =
  match vlist_of ctx id with
  | Some v -> Hashtbl.replace ctx.vresync v (); true
  | None -> under_vlist ctx id

(* ---------- virtual-list post-layout passes ----------

   After the mirror computes, each virtual list learns its own content
   geometry (origin, cross size) from the resolved rect, mounts the
   window of row subtrees the fed viewport covers, measures them into
   the extent model, and composes their absolute rects into [t.rects]. *)

let vlist_geometry ctx (v : vlist) =
  match Hashtbl.find_opt ctx.nodes v.vid with
  | None -> ()
  | Some f ->
    let ar = Lui_flex.absolute_layout f in
    let s =
      match Hashtbl.find_opt ctx.applied v.vid with
      | Some s -> s
      | None -> Lui_flex.default_style
    in
    let bl = edge_px ~owner:ar.w s.border.left s.border.horizontal s.border
    and br = edge_px ~owner:ar.w s.border.right s.border.horizontal s.border
    and pl = edge_px ~owner:ar.w s.padding.left s.padding.horizontal s.padding
    and pr = edge_px ~owner:ar.w s.padding.right s.padding.horizontal s.padding in
    v.bor0 <- edge_px ~owner:ar.h s.border.top s.border.vertical s.border;
    v.bor1 <- edge_px ~owner:ar.h s.border.bottom s.border.vertical s.border;
    v.pad0 <- edge_px ~owner:ar.h s.padding.top s.padding.vertical s.padding;
    v.pad1 <- edge_px ~owner:ar.h s.padding.bottom s.padding.vertical s.padding;
    v.origin_main <- ar.y;
    v.origin_cross <- ar.x +. bl +. pl;
    v.cross_size <- Float.max 0. (ar.w -. bl -. br -. pl -. pr)

(* Drop one mounted row: its shadow registrations (rows share the
   mirror's shadow tables, which is how journal ops routed to a row
   find the list), its per-list flex nodes and its composed rects.
   A subtree that moved out of the list mid-batch keeps its new mirror
   slot — its raw chain no longer reaches this list. *)
let drop_vrow ctx (v : vlist) i (row : vrow) =
  List.iter
    (fun id ->
      match vlist_ancestor ctx id with
      | Some a when a = v.vid -> purge ctx id
      | _ -> ())
    row.rids;
  List.iter (fun id -> Hashtbl.remove v.nodes id) row.rids;
  Hashtbl.remove v.rows i

(* Mount the row subtrees for [first, last): drop the ones that left
   the window, build the ones that entered. A row is a standalone flex
   tree measured against the list's content width; its laid-out main
   extent refines the model ([vlist_measure]). *)
let build_vrows _t ctx store (v : vlist) ~first ~last =
  let stale = ref [] in
  Hashtbl.iter
    (fun i (_ : vrow) -> if i < first || i >= last then stale := i :: !stale)
    v.rows;
  List.iter
    (fun i ->
       match Hashtbl.find_opt v.rows i with
       | Some row -> drop_vrow ctx v i row
       | None -> ())
    !stale;
  v.built_cross <- v.cross_size;
  for i = first to last - 1 do
    if not (Hashtbl.mem v.rows i) then begin
      let cid = if i < Array.length v.kids then v.kids.(i) else -1 in
      if cid >= 0 then begin
        (* Row-local context: registrations land in the list's own
           node table so [collect] stays a mirror-only pass. The shadow
           tables are shared with the mirror — row roots point their
           [sparent] at the list so incremental ops on row descendants
           resolve to a virtual-list resync. *)
        let rctx =
          { ctx with
            nodes = v.nodes;
            applied = Hashtbl.create 8;
            grids = ref [];
            popups = ref [] }
        in
        let pairs =
          build rctx ~owner_id:v.vid ~pkind:"virtual-list" ~pid:v.vid
            ~index:i cid
        in
        Hashtbl.replace ctx.sparent cid v.vid;
        let kids = List.map fst pairs in
        let root =
          match kids with
          | [ n ] -> n
          | _ -> Lui_flex.create kids
        in
        Lui_flex.compute_layout root ~width:v.cross_size
          ~height:Lui_flex.undefined ();
        refine_grids rctx ~relayout:(fun () ->
          Lui_flex.compute_layout root ~width:v.cross_size
            ~height:Lui_flex.undefined ());
        refine_popups rctx;
        (if !(rctx.grids) <> [] || !(rctx.popups) <> [] then
           Lui_flex.compute_layout root ~width:v.cross_size
             ~height:Lui_flex.undefined ());
        vlist_measure v i (Lui_flex.absolute_layout root).h;
        Hashtbl.replace v.rows i
          { rf = root; rids = Lui_store.preorder ~root:cid store }
      end
    end
  done

(* Feed the viewport accessor and remount any list whose window moved.
   Returns true when row sets changed. *)
let vlists_mount (t : t) ctx store ~vport =
  let changed = ref false in
  Hashtbl.iter
    (fun _ (v : vlist) ->
       (match vport v.vid with
        | Some (vs, ve) ->
          v.windowed <- true;
          v.vs <- vs;
          v.ve <- ve
        | None -> v.windowed <- false);
       (if v.cross_size <> v.built_cross && Hashtbl.length v.rows > 0
        then begin
          (* The content width moved under the mounted forest on the
             persistent mirror — the rows must lay out again at the new
             width, a slide of the window alone would not catch it. *)
          let idx = Hashtbl.fold (fun i _ acc -> i :: acc) v.rows [] in
          List.iter
            (fun i ->
               match Hashtbl.find_opt v.rows i with
               | Some row -> drop_vrow ctx v i row
               | None -> ())
            idx
        end);
       let f, l = vlist_range v in
       if f <> v.first || l <> v.last || Hashtbl.length v.rows < l - f
       then begin
         (* Anchor the item at the viewport top: measuring freshly
            mounted overscan rows above it shifts every offset below —
            record the prefix delta as drift the scroller applies so
            the anchored row keeps its screen position. *)
         let anchor =
           if v.windowed && v.count > 0 then
             let ai =
               min (v.count - 1)
                 (bit_lower v.bit
                    (Float.max 0. (v.vs -. v.bor0 -. v.pad0)))
             in
             Some (ai, bit_sum v.bit ai)
           else None
         in
         v.first <- f;
         v.last <- l;
         build_vrows t ctx store v ~first:f ~last:l;
         (match anchor with
          | Some (ai, y0) ->
            v.drift <- v.drift +. (bit_sum v.bit ai -. y0)
          | None -> ());
         changed := true
       end)
    t.vlists;
  !changed

(* Measurements shift the virtual extent: repatch the leaf min-height
   of every self-sizing list whose total moved. Returns true when any
   style changed (caller re-runs the frame layout). *)
let vlists_patch (t : t) ctx =
  let moved = ref false in
  Hashtbl.iter
    (fun _ (v : vlist) ->
       let total = vlist_total v in
       if Float.abs (total -. v.total) > 0.001 then v.total <- total;
       match
         (Hashtbl.find_opt ctx.nodes v.vid, Hashtbl.find_opt ctx.applied v.vid)
       with
       | Some f, Some (s : Lui_flex.style) -> (
         match s.height with
         | Unset ->
           let want = v.bor0 +. v.total +. v.bor1 in
           let cur = len_px ~owner:ctx.vh s.min_height in
           if Float.abs (want -. cur) > 0.001 then begin
             let s' = { s with min_height = Lui_flex.Pt want } in
             Lui_flex.set_style f s';
             Hashtbl.replace ctx.applied v.vid s';
             moved := true
           end
         | _ -> ())
       | _ -> ())
    t.vlists;
  !moved

(* Composed rects for mounted row subtrees: model offset on the main
   axis, content origin on the cross axis. Stale ids from the previous
   window are dropped first. *)
let collect_vlist t (v : vlist) =
  (* Remember the previous window's boxes so the paint pass only sees
     rows whose rect actually moved, appeared or vanished. *)
  let prev = Hashtbl.create (List.length v.mounted_ids) in
  List.iter
    (fun id ->
       (match Hashtbl.find_opt t.rects id with
        | Some r -> Hashtbl.replace prev id r
        | None -> ());
       Hashtbl.remove t.rects id)
    v.mounted_ids;
  let ids = ref [] in
  Hashtbl.iter
    (fun i (row : vrow) ->
       let ry = v.origin_main +. v.bor0 +. v.pad0 +. bit_sum v.bit i in
       let rr = Lui_flex.absolute_layout row.rf in
       List.iter
         (fun id ->
            match Hashtbl.find_opt v.nodes id with
            | Some f ->
              let r = Lui_flex.absolute_layout f in
              (* Row rects share the engine's snapped scene_rect —
                 paint, hit-test and retained pieces all read the same
                 device-pixel geometry. *)
              let r' =
                Lui_scene.rect_snap
                  {
                    Lui_scene.x = v.origin_cross +. (r.x -. rr.x);
                    y = ry +. (r.y -. rr.y);
                    w = r.w;
                    h = r.h;
                  }
              in
              (match Hashtbl.find_opt prev id with
               | Some old when old = r' -> ()
               | _ -> Hashtbl.replace t.rect_changed id ());
              Hashtbl.remove prev id;
              Hashtbl.replace t.rects id r';
              ids := id :: !ids
            | None -> ())
         row.rids)
    v.rows;
  (* Rows that slid out of the window lost their rect. *)
  Hashtbl.iter (fun id _ -> Hashtbl.replace t.rect_changed id ()) prev;
  v.mounted_ids <- !ids

let vlists_collect (t : t) =
  Hashtbl.iter (fun _ v -> collect_vlist t v) t.vlists

(* Post-layout pass over every live list: prune dead ones (dropped,
   hidden, re-kinded or flipped to horizontal), learn geometry, mount
   the fed windows, and repatch leaf extents when measurements moved
   them. [reset] drops every mounted row first — the rebuild path uses
   it since row forests were built under the previous sync's context;
   the incremental path keeps rows the journal did not touch. *)
let vlists_pass (t : t) ctx ~vport ~width ~height ~reset =
  let dead = ref [] in
  Hashtbl.iter
    (fun _ (v : vlist) ->
       let alive =
         Lui_store.kind ctx.store v.vid = "virtual-list"
         && vlist_vertical ctx.store v.vid
         && Hashtbl.mem t.nodes v.vid
       in
       if not alive then dead := v :: !dead)
    t.vlists;
  List.iter
    (fun (v : vlist) ->
       (* Rows and their composed rects die with the list. *)
       let idx = Hashtbl.fold (fun i row acc -> (i, row) :: acc) v.rows [] in
       List.iter (fun (i, row) -> drop_vrow ctx v i row) idx;
       Hashtbl.reset v.nodes;
       Hashtbl.remove t.vlists v.vid)
    !dead;
  if Hashtbl.length t.vlists > 0 then begin
    (if reset then
       Hashtbl.iter
         (fun _ (v : vlist) ->
            let idx =
              Hashtbl.fold (fun i row acc -> (i, row) :: acc) v.rows []
            in
            List.iter (fun (i, row) -> drop_vrow ctx v i row) idx)
         t.vlists);
    Hashtbl.iter (fun _ v -> vlist_geometry ctx v) t.vlists;
    ignore (vlists_mount t ctx ctx.store ~vport);
    if vlists_patch t ctx then begin
      (* A resized leaf shifts every rect after it — scoped re-reads
         cannot cover that, so refresh the whole frame. *)
      Hashtbl.replace t.rect_dirty frame_id ();
      match t.root with
      | Some root ->
        let ew, eh = layout_frame root ~width ~height in
        t.extent <- (ew, eh);
        Hashtbl.iter (fun _ v -> vlist_geometry ctx v) t.vlists;
        ignore (vlists_mount t ctx ctx.store ~vport)
      | None -> ()
    end
  end

(* A build ctx reconstructed from the saved sync inputs — used by the
   memo-hit path to remount row windows without a mirror rebuild. The
   shadow tables are shared with the mirror for the same reason as in
   [build_vrows]: mounted rows must stay reachable through the raw
   chain. *)
let ctx_of_saved (t : t) (sc : saved_ctx) : ctx =
  { scale = sc.sc_scale;
    vw = sc.sc_vw;
    vh = sc.sc_vh;
    tm = sc.sc_tm;
    image_measure = sc.sc_image_measure;
    hidden = sc.sc_hidden;
    ctx_anchor = sc.sc_anchor;
    store = sc.sc_store;
    eng = t;
    nodes = t.nodes;
    applied = t.applied;
    pkids = t.pkids;
    sparent = t.sparent;
    owner = t.owner;
    grids = ref [];
    popups = ref [];
    vlists = t.vlists;
    vresync = Hashtbl.create 4 }

(* Memo-hit path: only the fed viewports moved since the last layout —
   remount the windows that slid, repatch extents, recompose rects.
   Everything else (mirror, main rects) stands as it was. *)
let vlists_update (t : t) ~vport =
  if Hashtbl.length t.vlists > 0 then
    match t.vctx with
    | Some sc ->
      let ctx = ctx_of_saved t sc in
      if vlists_mount t ctx sc.sc_store ~vport then begin
        if vlists_patch t ctx then begin
          (match t.root with
           | Some root ->
             let ew, eh =
               layout_frame root ~width:sc.sc_vw ~height:sc.sc_vh
             in
             t.extent <- (ew, eh);
             Hashtbl.iter (fun _ v -> vlist_geometry ctx v) t.vlists;
             collect t;
             (* Freshly measured rows can widen the window the first
                pass computed — a second mount covers what the
                post-measure range now reaches. *)
             ignore (vlists_mount t ctx sc.sc_store ~vport)
           | None -> ())
        end;
        vlists_collect t
      end
    | None -> ()


let compute t ~width ~height =
  match t.root with
  | None -> ()
  | Some root ->
    t.extent <- layout_frame root ~width ~height;
    collect t;
    (* The rects now reflect a frame the memo never synced at — a
       later {!sync} at the memoized size would wrongly reuse them. *)
    invalidate t

(* ---------- incremental mirror ----------

   Between syncs the mirror is persistent: [changes_since] replays the
   store's op journal onto the shadow tables (pkids/sparent/owner), the
   flex engine's own dirty propagation confines relayout to the touched
   paths, and [rect_dirty] scopes the rect refresh to the produced
   subtrees a change can actually shift. *)

(* produced_of is the built-state produced list: unlike peek it expands
   whatever the produced set needs. [owner_id] is the flex owner a lazy
   expansion belongs to — the caller knows it, an unbuilt node's own
   shadow does not yet. *)
let rec produced_of ctx ~owner_id id =
  match status_of ctx id with
  | N_hidden -> []
  | N_normal -> [ id ]
  | N_contents ->
    (if not (Hashtbl.mem ctx.pkids id) then
       let cids =
         ordered_child_ids ctx.store id (Lui_store.kind ctx.store id)
       in
       ignore
         (expand_children ctx ~owner:owner_id ~pkind:(kind_of ctx owner_id)
            ~pid:owner_id ~raw_parent:id ~first:0 cids));
    List.concat_map (fun e -> e.gens) (pkids_of ctx id)

(* ensure_produced builds whatever the produced expansion needs: a
   never-built node mirrors its whole subtree, an unexpanded contents
   node expands its children, anything already built is reused. *)
and ensure_produced ctx ~owner_id id =
  match status_of ctx id with
  | N_hidden -> []
  | N_normal ->
    if Hashtbl.mem ctx.nodes id then [ id ]
    else begin
      ignore
        (build ctx ~owner_id ~pkind:(kind_of ctx owner_id) ~pid:owner_id
           ~index:0 id);
      [ id ]
    end
  | N_contents -> produced_of ctx ~owner_id id

(* Raw children in produced order: store roots for the frame
   pseudo-parent, the ordered child list otherwise. *)
let raw_children ctx p =
  if p = frame_id then Lui_store.root_ids ctx.store
  else ordered_child_ids ctx.store p (kind_of ctx p)

(* Align pkids[p] with the store's current child list for p: recorded
   gens survive (the produced set did not change), [overrides] supply
   fresh gens for spliced children, unseen raws peek — never build. *)
let sync_entries ?(overrides = []) ctx p =
  let ids = raw_children ctx p in
  let old = pkids_of ctx p in
  let tbl =
    Hashtbl.create (2 * (List.length old + List.length overrides + 1))
  in
  List.iter (fun e -> Hashtbl.replace tbl e.raw e.gens) old;
  List.iter (fun (id, g) -> Hashtbl.replace tbl id g) overrides;
  Hashtbl.replace ctx.pkids p
    (List.map
       (fun id ->
         { raw = id;
           gens =
             (match Hashtbl.find_opt tbl id with
              | Some g -> g
              | None -> peek_produced ctx id) })
       ids)

let flex_children_of ctx p : Lui_flex.node list =
  List.concat_map
    (fun e -> List.filter_map (Hashtbl.find_opt ctx.nodes) e.gens)
    (pkids_of ctx p)

(* Update pkids[p]'s entry for [raw] to [ng]; true when the gens
   actually changed (unchanged means ancestors see no difference and the
   climb can stop). *)
let replace_gens ctx p raw ng =
  match Hashtbl.find_opt ctx.pkids p with
  | None -> false
  | Some es ->
    let rec loop = function
      | [] -> false
      | e :: rest ->
        if e.raw = raw then
          if e.gens = ng then false
          else begin
            e.gens <- ng;
            true
          end
        else loop rest
    in
    loop es

(* pkids[p] changed: re-set the flex children of the flex owner of p's
   produced set — p's own flex node when it has one — and, for
   hidden/contents p, push the recomputed produced list into the
   parent's slot and keep climbing until a flex owner. *)
let rec commit ctx p =
  if p = frame_id then (
    match ctx.eng.root with
    | Some root -> Lui_flex.set_children root (flex_children_of ctx frame_id)
    | None -> ())
  else if Hashtbl.mem ctx.nodes p then
    Lui_flex.set_children (Hashtbl.find ctx.nodes p) (flex_children_of ctx p)
  else begin
    match Hashtbl.find_opt ctx.sparent p with
    | Some par ->
      if
        replace_gens ctx par p
          (produced_of ctx ~owner_id:(children_owner ctx p) p)
      then commit ctx par
    | None -> ()
  end

(* A frame-level produced node that resized also shifted every later
   frame sibling — mark their produced subtrees too. [t] is a produced
   id directly under the frame. *)
let mark_frame_siblings_after ctx t =
  let rec scan_entries = function
    | [] -> ()
    | e :: rest ->
      let rec mark_tail = function
        | [] -> scan_entries rest
        | g :: gs ->
          if g = t then begin
            List.iter
              (fun x -> Hashtbl.replace ctx.eng.rect_dirty x ())
              gs;
            List.iter
              (fun e' ->
                List.iter
                  (fun x -> Hashtbl.replace ctx.eng.rect_dirty x ())
                  e'.gens)
              rest
          end
          else mark_tail gs
      in
      mark_tail e.gens
  in
  scan_entries (pkids_of ctx frame_id)

(* Any change can re-flow the owner's siblings, which can grow the
   owner, which can re-flow the grandparent's siblings — the shifted
   region walks the flex-parent chain to a store root. The produced
   subtree of that root covers every mirror node under it, so marking
   the chain's topmost owner is the tight bound (plus, for a resized
   root, every later frame sibling) and a full collect is its cheap
   realization (rect writes only — no style resolution, no flex node
   churn). *)
let mark_affected ctx o =
  let rec top x =
    (match Hashtbl.find_opt ctx.eng.tables x with
     | Some table -> table.natural <- None
     | None -> ());
    match Hashtbl.find_opt ctx.owner x with
    | Some p when p <> frame_id -> top p
    | _ -> x
  in
  let t = top o in
  Hashtbl.replace ctx.eng.rect_dirty t ();
  if t <> frame_id then mark_frame_siblings_after ctx t

(* Flattened position of produced node g inside owner o's produced
   children — the value [index] had when g was built. *)
let produced_index ctx o g =
  let rec scan acc = function
    | [] -> acc
    | e :: rest -> (
      let rec find i = function
        | [] -> None
        | x :: xs -> if x = g then Some (acc + i) else find (i + 1) xs
      in
      match find 0 e.gens with
      | Some p -> p
      | None -> scan (acc + List.length e.gens) rest)
  in
  scan 0 (pkids_of ctx o)

(* Recompute g's style and measure against its current owner and index
   — the incremental equivalent of rebuilding its flex node. *)
let restyle_gen_at ctx o g index =
  match Hashtbl.find_opt ctx.nodes g with
  | Some f ->
    let style =
      style_of ~scale:ctx.scale ~viewport:(ctx.vw, ctx.vh) ctx.store g
      |> adjust ~scale:ctx.scale ~pkind:(kind_of ctx o) ~pid:o ~index ctx.store g
    in
    (match Hashtbl.find_opt ctx.vlists g with
     | Some v ->
       (* A virtual list restyles like its build: configure the model
          off the raw style, then claim the virtual extent — children
          are row subtrees, never produced gens. *)
       vlist_configure ctx ctx.store v style;
       let style = vlist_leaf_style ctx v style in
       Lui_flex.set_style f style;
       Lui_flex.set_measure f None;
       Hashtbl.replace ctx.applied g style;
       Hashtbl.replace ctx.owner g o;
       unregister ctx g;
       register ctx g "virtual-list" f style
     | None ->
       let kids = Lui_flex.children f in
       let cids =
         ordered_child_ids ctx.store g (Lui_store.kind ctx.store g)
       in
       let style = popup_min_style ctx g cids kids style in
       let m = measure_for ctx g ~kids in
       Lui_flex.set_style f style;
       Lui_flex.set_measure f m;
       Hashtbl.replace ctx.applied g style;
       Hashtbl.replace ctx.owner g o;
       let kind = Lui_store.kind ctx.store g in
       unregister ctx g;
       register ctx g kind f style)
  | None -> ()

let restyle_gen ctx o g =
  restyle_gen_at ctx o g (produced_index ctx o g)

(* An expansion occupies consecutive positions in its flex owner's produced
   children, including when transparent raw parents lift those children. *)
let iter_produced_indices ctx o entries f =
  let rec first_index = function
    | [] -> 0
    | {gens=[]; _} :: rest -> first_index rest
    | {gens=g::_; _} :: _ -> produced_index ctx o g
  in
  let index = ref (first_index entries) in
  List.iter (fun e -> List.iter (fun g ->
    f g !index;
    incr index) e.gens) entries

(* Parent kinds whose child adjustment depends on sibling position:
   membership or order churn under them rewrites sibling styles, not
   just the moved node's. *)
let index_sensitive = function
  | "overlay" | "stack" | "panel" | "card" | "resizable"
  | "view-that-fits" | "split" | "edge-inset" -> true
  | _ -> false

let restyle_children_of ctx o =
  iter_produced_indices ctx o (pkids_of ctx o) (restyle_gen_at ctx o)

let restyle_content_owner ctx o =
  match kind_of ctx o with
  | "button" | "toggle-button" ->
    restyle_gen ctx (Hashtbl.find ctx.owner o) o
  | _ -> ()

(* Insert/MoveChild: detach the shadow entry from the old raw parent,
   ensure the child's produced set exists, then let [sync_entries]
   place it at the store's current position. *)
let attach_child ctx ~parent:p ~child:c =
  (match Hashtbl.find_opt ctx.sparent c with
   | Some op when op <> p ->
     sync_entries ctx op;
     commit ctx op;
     restyle_content_owner ctx (children_owner ctx op);
     mark_affected ctx (children_owner ctx op)
   | _ -> ());
  let o = children_owner ctx p in
  let gens = ensure_produced ctx ~owner_id:o c in
  Hashtbl.replace ctx.sparent c p;
  sync_entries ctx p ~overrides:[ (c, gens) ];
  (* Commit before restyling: gens indices inside the owner's produced
     list only read correctly once the parent chain has propagated. *)
  commit ctx p;
  restyle_content_owner ctx o;
  List.iter
    (fun g ->
      Hashtbl.replace ctx.owner g o;
      restyle_gen ctx o g)
    gens;
  (if index_sensitive (kind_of ctx o) then restyle_children_of ctx o);
  mark_affected ctx o

let detach_child ctx ~parent:p ~child:c =
  Hashtbl.remove ctx.sparent c;
  (* Replay this unlink against the mirror, rather than the final store
     state: later subtree drops still need their recorded descendants. *)
  Hashtbl.replace ctx.pkids p (List.filter (fun e -> e.raw <> c) (pkids_of ctx p));
  commit ctx p;
  let o = children_owner ctx p in
  restyle_content_owner ctx o;
  (if index_sensitive (kind_of ctx o) then restyle_children_of ctx o);
  mark_affected ctx o

(* The store link is already gone (drop/recreate): find the old raw
   parent in the shadow, drop the entry, keep the subtree for reuse. *)
let detach_from_parent ctx id =
  match Hashtbl.find_opt ctx.sparent id with
  | Some par ->
    Hashtbl.remove ctx.sparent id;
    Hashtbl.replace ctx.pkids par (List.filter (fun e -> e.raw <> id) (pkids_of ctx par));
    commit ctx par;
    restyle_content_owner ctx (children_owner ctx par);
    mark_affected ctx (children_owner ctx par)
  | None -> ()

(* display/structure churn on id: rebuild its produced expansion in
   place — the subtree is re-mirrored (a rare op). *)
let reexpand ctx id =
  match Hashtbl.find_opt ctx.sparent id with
  | Some par ->
    let o = children_owner ctx par in
    purge ctx id;
    (* Purge dropped the raw-parent link too — restore it so the next
       structure op on id can still find its slot. *)
    Hashtbl.replace ctx.sparent id par;
    let pairs =
      build ctx ~owner_id:o ~pkind:(kind_of ctx o) ~pid:o ~index:0 id
    in
    let gens = List.map snd pairs in
    sync_entries ctx par ~overrides:[ (id, gens) ];
    commit ctx par;
    List.iter
      (fun g ->
        Hashtbl.replace ctx.owner g o;
        restyle_gen ctx o g)
      gens;
    mark_affected ctx o
  | None -> ()

let restyle_self ctx id =
  match Hashtbl.find_opt ctx.owner id with
  | Some o ->
    restyle_gen ctx o id;
    mark_affected ctx o
  | None -> ()

(* A layout-kids prop (columns/value/edge) rewrites the produced
   children's styles and possibly their order — restyle them all
   against the current parent inputs. *)
let restyle_children ctx id =
  let o = children_owner ctx id in
  sync_entries ctx id;
  commit ctx id;
  iter_produced_indices ctx o (pkids_of ctx id) (fun g index ->
    Hashtbl.replace ctx.owner g o;
    restyle_gen_at ctx o g index);
  mark_affected ctx o

(* A journal op landed on a live virtual list or inside one: rows
   index a logical model that may have changed and row subtrees are
   never edited in place, so the mounted forest drops wholesale and the
   leaf is restyled/reconfigured — the post-layout pass remounts the
   window. Subtrees that moved out of the list mid-batch keep their new
   mirror slot. *)
let resync_vlist ctx (v : vlist) =
  let idx = Hashtbl.fold (fun i row acc -> (i, row) :: acc) v.rows [] in
  List.iter (fun (i, row) -> drop_vrow ctx v i row) idx;
  Hashtbl.reset v.nodes;
  v.mounted_ids <- [];
  match
    (Hashtbl.find_opt ctx.nodes v.vid, Hashtbl.find_opt ctx.owner v.vid)
  with
  | Some f, Some o ->
    let index = produced_index ctx o v.vid in
    let style =
      style_of ~scale:ctx.scale ~viewport:(ctx.vw, ctx.vh) ctx.store v.vid
      |> adjust ~scale:ctx.scale ~pkind:(kind_of ctx o) ~pid:o ~index ctx.store v.vid
    in
    vlist_configure ctx ctx.store v style;
    let style = vlist_leaf_style ctx v style in
    Lui_flex.set_style f style;
    Hashtbl.replace ctx.applied v.vid style;
    mark_affected ctx o
  | _ -> ()

let apply_journal_op ctx (op : patch_op) =
  (* A virtual list owns its rows: ops landing inside one mark it for
     resync rather than editing the persistent mirror — the side
     forest rebuilds from the store before layout. *)
  match op with
  | SetProp (id, p, _) | RemoveProp (id, p) -> (
    let m =
      Lui_store.mask_of_prop (Lui_wire_schema.property_name p)
    in
    if m land (Lui_store.d_structure lor Lui_store.d_layout lor Lui_store.d_layout_kids) = 0 then ()
    else if under_vlist ctx id then ()
    else
      match vlist_of ctx id with
      | Some _ ->
        (* The list's own props feed the row model (gap, padding,
           estimate) — resync restyles the leaf and rebuilds rows. *)
        Hashtbl.replace ctx.vresync id ();
        if Lui_store.mask_has m Lui_store.d_structure then reexpand ctx id
      | None ->
        if
          Lui_store.kind ctx.store id = "virtual-list"
          && vlist_vertical ctx.store id
        then
          (* A horizontal virtual-list turning vertical becomes a leaf —
             rebuild its produced expansion in place. *)
          reexpand ctx id
        (* White-space changes inherited flow and fragment shrink below this node. *)
        else if p = WhiteSpace || Lui_store.mask_has m Lui_store.d_structure then reexpand ctx id
        else begin
          if Lui_store.mask_has m Lui_store.d_layout then restyle_self ctx id;
          if Lui_store.mask_has m Lui_store.d_layout_kids then
            restyle_children ctx id
        end)
  | SetExtensionProp (id, _, _) | RemoveExtensionProp (id, _) ->
    if under_vlist ctx id then ()
    else (
      match vlist_of ctx id with
      | Some _ -> Hashtbl.replace ctx.vresync id ()
      | None ->
        (* Unknown prop semantics: restyle the node and its children. *)
        restyle_self ctx id;
        restyle_children ctx id)
  | CreateNode (id, _) | CreateExtension (id, _, _)
  | DropNode id | DetachSubtree id ->
    if under_vlist ctx id then purge ctx id
    else begin
      detach_from_parent ctx id;
      purge ctx id
    end
  | InsertChild (p, c, _) | MoveChild (p, c, _) -> (
    (* The mirror reads the transaction's final tree. A link that was
       removed or superseded later in this transaction must not build a
       phantom subtree whose owner no longer exists. *)
    if Lui_store.parent ctx.store c <> Some p then () else begin
    (match Hashtbl.find_opt ctx.sparent c with
     | Some op when op <> p -> ignore (in_vlist ctx op)
     | _ -> ());
    if in_vlist ctx p || not (Hashtbl.mem ctx.pkids p) then begin
      (* Virtual rows materialize during resync; an unmounted parent
         materializes its final subtree on attachment. Building either
         child here would leave stale grid and popup registrations. *)
      detach_from_parent ctx c;
      purge ctx c
    end
    else attach_child ctx ~parent:p ~child:c
    end)
  | RemoveChild (p, c) ->
    if in_vlist ctx p then () else detach_child ctx ~parent:p ~child:c

(* Rect refresh scoped to dirty owner subtrees: every produced
   descendant of a dirty owner gets its rect re-read (a resized node
   moves its siblings, so the refresh root is the owner — the flex
   parent — not the changed node). [frame_id] dirties everything. *)
let rec refresh_sub ctx read sid =
  if Hashtbl.mem ctx.nodes sid then update_rect ctx.eng sid (read sid);
  List.iter
    (fun e -> List.iter (fun g -> refresh_sub ctx read g) e.gens)
    (pkids_of ctx sid)

let refresh_rects ctx =
  if Hashtbl.mem ctx.eng.rect_dirty frame_id then collect ctx.eng
  else begin
    let read = absolute_reader ctx.eng in
    Hashtbl.iter (fun sid () -> refresh_sub ctx read sid) ctx.eng.rect_dirty
  end;
  Hashtbl.reset ctx.eng.rect_dirty

let ctx_of t store ~scale ~measure ~image_measure ~hidden ctx_anchor ~width ~height : ctx =
  { scale; vw = width; vh = height; tm = measure; image_measure; hidden; ctx_anchor;
    store; eng = t; nodes = t.nodes; applied = t.applied;
    pkids = t.pkids; sparent = t.sparent; owner = t.owner;
    grids = t.grids; popups = t.popups;
    vlists = t.vlists; vresync = Hashtbl.create 4 }

(* Wipe the mirror and re-expand the frame: first sync, invalidate, or
   a journal that no longer reaches our cursor. *)
let rebuild ctx (t : t) ~width ~height =
  Hashtbl.reset t.nodes;
  Hashtbl.reset t.applied;
  (* Rects reset with the mirror: entries for dropped ids would
     otherwise linger and answer stale rects to {!rect}. Every rect
     the rebuild produces reads as changed to {!take_rect_changes}
     consumers. *)
  Hashtbl.reset t.rects;
  Hashtbl.reset t.pkids;
  Hashtbl.reset t.sparent;
  Hashtbl.reset t.owner;
  Hashtbl.reset t.tables;
  t.grids := [];
  t.popups := [];
  ignore
    (expand_children ctx ~owner:frame_id ~pkind:"frame" ~pid:frame_id
       ~raw_parent:frame_id ~first:0 (Lui_store.root_ids ctx.store));
  let root =
    Lui_flex.create ~style:(frame_style_for width (Pt height))
      (flex_children_of ctx frame_id)
  in
  t.root <- Some root;
  Hashtbl.reset t.rect_dirty;
  Hashtbl.replace t.rect_dirty frame_id ()

let finish ctx (t : t) ~width ~height ~vport ~full =
  match t.root with
  | None -> ()
  | Some root ->
    let tables = ordered_tables ctx in
    prepare_tables ctx tables;
    let ew, eh = layout_frame root ~width ~height in
    refine_grids ctx ~relayout:(fun () ->
      Lui_flex.compute_layout root ~width:ew ~height:eh ());
    (if !(ctx.grids) <> [] then
       Lui_flex.compute_layout root ~width:ew ~height:eh ());
    refine_tables ctx tables ~relayout:(fun () ->
      Lui_flex.compute_layout root ~width:ew ~height:eh ());
    (* A table can resize a grid inside a cell. *)
    (if tables <> [] then refine_grids ctx ~relayout:(fun () ->
       Lui_flex.compute_layout root ~width:ew ~height:eh ()));
    refine_popups ctx;
    (if !(ctx.grids) <> [] || !(ctx.popups) <> [] then
       Lui_flex.compute_layout root ~width:ew ~height:eh ());
    t.extent <- (ew, eh);
    (* Virtual lists learn their content geometry only after the frame
       layout exists: geometry comes off the fresh rects, the fed
       windows mount (a rebuilt mirror resets the side forests), and
       measured rows can still grow a leaf — [vlists_pass] re-runs the
       frame layout itself when they do. *)
    vlists_pass t ctx ~vport ~width ~height ~reset:full;
    refresh_rects ctx;
    (* Row rects are composed off the final mirror geometry — always
       recomposed, never part of the scoped refresh. *)
    vlists_collect t

let sync ?(scale = 1.) ?(measure = no_measure) ?(image_measure = no_image_measure) ?(hidden = show_all)
    ?ctx_anchor ?(vport = no_vport) ?(anchor_shift = fun _ -> (0.,0.)) ~width ~height (t : t) store =
  t.anchor_shift <- anchor_shift;
  let shifts = ref [] in
  Lui_store.iter_anchor_targets store (fun popup ->
    match Lui_store.string_prop store popup "anchor-target" with
    | Some identifier ->
        (match Lui_store.find_identifier store identifier with
         | Some target ->
             let tx,ty = anchor_shift target and px,py = anchor_shift popup in
             shifts := (popup,tx-.px,ty-.py) :: !shifts
         | None -> ())
    | None -> ());
  let anchor_changed = !shifts <> t.synced_anchor_shifts in
  let viewport_changed = t.synced_w <> width || t.synced_h <> height in
  let mirror_inputs_changed =
    t.synced_scale <> scale
    || t.synced_anchor <> ctx_anchor
    || (not (t.synced_measure == measure))
    || (not (t.synced_image_measure == image_measure))
    || (not (t.synced_hidden == hidden))
  in
  let inputs_changed = mirror_inputs_changed || viewport_changed || anchor_changed in
  (* Fast path: inputs stable and the store's layout revision
     unmoved — paint-only churn, scroll-only and idle frames all skip
     the mirror entirely. The store-revision cursor still advances so
     the journal never re-feeds paint ops. *)
  if
    (not inputs_changed) && t.synced_rev >= 0
    && t.synced_lrev = Lui_store.layout_rev store
  then begin
    t.synced_rev <- Lui_store.revision store;
    (* Memo-hit: only the fed viewports may have moved — remount the
       virtual-list windows that slid instead of touching the mirror. *)
    vlists_update t ~vport
  end
  else begin
    t.stat_syncs <- t.stat_syncs + 1;
    let ctx = ctx_of t store ~scale ~measure ~image_measure ~hidden ctx_anchor ~width ~height in
    let full =
      if mirror_inputs_changed || t.synced_rev < 0 || t.root = None then true
      else
        match Lui_store.changes_since store t.synced_rev with
        | None -> true
        | Some ops ->
          t.stat_steps <- t.stat_steps + 1;
          (* The store already contains the final batch tree. Building a
             newly inserted ancestor also builds its new descendants.
             Purge old identities first so later create records cannot
             destroy and rebuild those freshly mirrored descendants. *)
          let created = Hashtbl.create 16 in
          List.iter (function
            | (CreateNode (id,_) | CreateExtension (id,_,_)) as op ->
              Hashtbl.replace created id ();
              apply_journal_op ctx op
            | _ -> ()) ops;
          List.iter (function
            | CreateNode _ | CreateExtension _ -> ()
            | SetProp (id,_,_) | RemoveProp (id,_)
            | SetExtensionProp (id,_,_) | RemoveExtensionProp (id,_)
              when Hashtbl.mem created id || not (Lui_store.mem store id) -> ()
            | op -> apply_journal_op ctx op) ops;
          (* Retained anchor references cross raw-parent boundaries. Reconcile
             their availability after the complete target batch is applied. *)
          Lui_store.iter_anchor_targets store (fun id ->
            if Hashtbl.mem ctx.sparent id then
              let produced = status_of ctx id <> N_hidden in
              if produced <> Hashtbl.mem ctx.nodes id then reexpand ctx id);
          (* Detach/drop can leave a built node as a fresh store root —
             resync the frame level so new roots appear and removed
             ones vanish. Membership churn dirties the whole frame. *)
          let before =
            List.map (fun e -> e.raw) (pkids_of ctx frame_id)
          in
          sync_entries ctx frame_id;
          if before <> List.map (fun e -> e.raw) (pkids_of ctx frame_id)
          then Hashtbl.replace t.rect_dirty frame_id ();
          List.iter
            (fun e ->
              Hashtbl.replace ctx.sparent e.raw frame_id;
              let gens =
                if e.gens = [] then
                  ensure_produced ctx ~owner_id:frame_id e.raw
                else e.gens
              in
              e.gens <- gens;
              (* A reused node that newly became a root still carries
                 its old owner — restyle it against the frame. *)
              List.iter
                (fun g ->
                  match Hashtbl.find_opt ctx.owner g with
                  | Some o when o = frame_id -> ()
                  | _ ->
                    Hashtbl.replace ctx.owner g frame_id;
                    restyle_gen ctx frame_id g)
                gens)
            (pkids_of ctx frame_id);
          commit ctx frame_id;
          (* Ops that touched a virtual list resync the whole side
             forest — mounted rows are rebuilt, never patched. *)
          Hashtbl.iter
            (fun _ (v : vlist) ->
               if Hashtbl.mem ctx.vresync v.vid then resync_vlist ctx v)
            t.vlists;
          false
    in
    if full then rebuild ctx t ~width ~height
    else if viewport_changed then begin
      (* Keep the flex mirror and its text measurements across resize.
         Only viewport-relative props need new resolved styles. *)
      let viewport_props = ["width-viewport"; "height-viewport";
        "min-width-viewport"; "max-width-viewport";
        "min-height-viewport"; "max-height-viewport"] in
      Hashtbl.iter (fun id _ ->
        if List.exists (has_prop store id) viewport_props then
          (restyle_gen ctx (Hashtbl.find ctx.owner id) id;
           mark_affected ctx id)) t.nodes;
      let popup_owners = List.filter_map (fun (_,id) -> Hashtbl.find_opt ctx.owner id) !(t.popups)
        |> List.sort_uniq Int.compare in
      List.iter (fun id -> if id <> frame_id then
        restyle_gen ctx (Hashtbl.find ctx.owner id) id) popup_owners;
      Hashtbl.replace t.rect_dirty frame_id ()
    end;
    if anchor_changed then
      List.iter (fun (popup,_,_) -> Hashtbl.replace t.rect_dirty popup ()) !shifts;
    finish ctx t ~width ~height ~vport ~full;
    t.synced_anchor_shifts <- !shifts;
    t.synced_rev <- Lui_store.revision store;
    t.synced_lrev <- Lui_store.layout_rev store;
    t.synced_scale <- scale;
    t.synced_w <- width;
    t.synced_h <- height;
    t.synced_anchor <- ctx_anchor;
    t.synced_measure <- measure;
    t.synced_image_measure <- image_measure;
    t.synced_hidden <- hidden;
    t.vctx <-
      Some
        { sc_scale = scale; sc_vw = width; sc_vh = height;
          sc_tm = measure; sc_image_measure = image_measure; sc_hidden = hidden; sc_anchor = ctx_anchor;
          sc_store = store }
  end

(* ---------- virtual-list queries ---------- *)

let vlists (t : t) =
  Hashtbl.fold (fun id _ acc -> id :: acc) t.vlists []

(* The mounted child-index window paint/hit-test slices to. An
   unwindowed list reports its full range — identical behavior to an
   unsliced walk, at slice cost. *)
let mounted_range (t : t) id =
  match Hashtbl.find_opt t.vlists id with
  | Some v -> Some (v.first, v.last)
  | None -> None

(* The mounted window's child store ids — the slice paint and
   hit-test enumerate. Read off [v.kids] so a mid-list window costs
   O(window), not a linked-list walk to [first]. *)
let mounted_children (t : t) id =
  match Hashtbl.find_opt t.vlists id with
  | Some v ->
    let n = max 0 (min v.last (Array.length v.kids) - v.first) in
    Some (Array.to_list (Array.sub v.kids v.first n))
  | None -> None

let mounted_count (t : t) id =
  match Hashtbl.find_opt t.vlists id with
  | Some v -> Hashtbl.length v.rows
  | None -> 0

(* Total virtual content extent (border-box span, device px). *)
let virtual_extent (t : t) id =
  match Hashtbl.find_opt t.vlists id with
  | Some v -> Some (v.bor0 +. v.total +. v.bor1)
  | None -> None

(* The item's rect in engine-absolute (content-space) coordinates —
   works for unmounted indices too, which is what makes scroll-to-item
   reach a row that does not exist yet. *)
let virtual_item_rect (t : t) id ~index : Lui_scene.rect option =
  match Hashtbl.find_opt t.vlists id with
  | Some v when index >= 0 && index < v.count ->
    Some
      { Lui_scene.x = v.origin_cross;
        y = v.origin_main +. v.bor0 +. v.pad0 +. bit_sum v.bit index;
        w = v.cross_size;
        h = vlist_ext v index }
  | _ -> None

(* The last viewport the vport accessor fed this list — what the
   interaction layer reports as the visible range. *)
let virtual_view (t : t) id =
  match Hashtbl.find_opt t.vlists id with
  | Some v when v.windowed -> Some (v.vs, v.ve)
  | _ -> None

(* Pending scroll correction from measurement drift, device px —
   consume-on-read. The scroller adds it to the list's offset so the
   row at the viewport top keeps its screen position when rows above
   measure off-estimate. *)
let virtual_take_drift (t : t) id =
  match Hashtbl.find_opt t.vlists id with
  | Some v ->
    let d = v.drift in
    v.drift <- 0.;
    d
  | None -> 0.

(* key → item index, lazily built once per list shape. *)
let virtual_index_of_key (t : t) store id key =
  match Hashtbl.find_opt t.vlists id with
  | None -> None
  | Some v ->
    let m =
      match v.key_index with
      | Some m -> m
      | None ->
        let m = Hashtbl.create 64 in
        for i = 0 to v.count - 1 do
          let cid = v.kids.(i) in
          if cid >= 0 then
            match Lui_store.string_prop store cid "key" with
            | Some k -> Hashtbl.replace m k i
            | None -> ()
        done;
        v.key_index <- Some m;
        m
    in
    Hashtbl.find_opt m key

(* store id → item index (same lazy index as above, reversed). *)
let virtual_index_of_id (t : t) _store id cid =
  match Hashtbl.find_opt t.vlists id with
  | None -> None
  | Some v ->
    let m =
      match v.id_index with
      | Some m -> m
      | None ->
        let m = Hashtbl.create 64 in
        for i = 0 to v.count - 1 do
          let k = v.kids.(i) in
          if k >= 0 then Hashtbl.replace m k i
        done;
        v.id_index <- Some m;
        m
    in
    Hashtbl.find_opt m cid

let content_extent (t : t) = t.extent

let layout_hook (t : t) id =
  match Hashtbl.find_opt t.rects id with
  | Some r -> Lui_paint.placement_of_rect r
  | None -> Lui_paint.placement_of_rect (Lui_scene.rect 0. 0. 0. 0.)

let rect (t : t) id = Hashtbl.find_opt t.rects id

let run ?(scale = 1.) ?hidden ?ctx_anchor store ~measure ~width ~height =
  let t = create () in
  sync ~scale ~measure:(fun id _text w h -> measure id w h)
    ~width ~height ?hidden ?ctx_anchor t store;
  layout_hook t
