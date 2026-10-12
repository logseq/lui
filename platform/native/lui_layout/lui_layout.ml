(* Store → flex glue for the native backend.

   The mirror is rebuilt wholesale on every {!sync}; the store is small
   and rebuild-per-sync keeps invalidation trivial. All wire lengths are
   logical px and are multiplied by [scale] as they become flex style
   values, so the computed rects land in device px — the coordinate
   space [Lui_paint] and [Lui_scene] use. *)

open Lui_protocol
open Lui_flex

type text_measure = int -> string -> float -> float -> (float * float) option

(* Shared defaults so the memo's physical-equality check on function
   inputs sees a stable identity: an inline [fun] default would
   allocate a fresh closure per call and never match. *)
let no_measure _id _text _offered_w _offered_h = None
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
  rows : (int, vrow) Hashtbl.t;   (* index → mounted row subtree *)
  nodes : (int, Lui_flex.node) Hashtbl.t; (* store id → flex node, rows *)
  mutable mounted_ids : int list; (* ids whose rects are registered *)
  mutable key_index : (string, int) Hashtbl.t option; (* lazy key → index *)
  mutable id_index : (int, int) Hashtbl.t option; (* lazy store id → index *)
}

(* The sync inputs a scroll-driven remount needs to rebuild row
   subtrees on a memo-hit path: the live store plus the style/measure
   context the rows were built under. *)
type saved_ctx = {
  sc_scale : float;
  sc_vw : float;
  sc_vh : float;
  sc_tm : text_measure;
  sc_hidden : int -> bool;
  sc_anchor : (float * float) option;
  sc_store : Lui_store.t;
}

type t = {
  mutable root : Lui_flex.node option;
  nodes : (int, Lui_flex.node) Hashtbl.t; (* store id → flex node *)
  applied : (int, Lui_flex.style) Hashtbl.t; (* store id → applied style *)
  rects : (int, Lui_scene.rect) Hashtbl.t;
  vlists : (int, vlist) Hashtbl.t; (* store id → virtual-list state *)
  mutable vctx : saved_ctx option; (* inputs of the last full sync *)
  mutable extent : float * float; (* frame extent the last layout used *)
  (* Memo of the inputs the current mirror+rects reflect. [synced_rev]
     is the store revision covered; -1 forces a rebuild. Function
     inputs compare by identity — a caller whose measure/hidden
     closure keeps its identity but changes its answers (e.g. a text
     engine that finishes loading fonts) must {!invalidate}. *)
  mutable synced_rev : int;
  mutable synced_scale : float;
  mutable synced_w : float;
  mutable synced_h : float;
  mutable synced_anchor : (float * float) option;
  mutable synced_measure : text_measure;
  mutable synced_hidden : int -> bool;
}

let create () =
  { root = None;
    nodes = Hashtbl.create 64;
    applied = Hashtbl.create 64;
    rects = Hashtbl.create 64;
    vlists = Hashtbl.create 4;
    vctx = None;
    extent = (0., 0.);
    synced_rev = -1;
    synced_scale = 0.;
    synced_w = 0.;
    synced_h = 0.;
    synced_anchor = None;
    synced_measure = no_measure;
    synced_hidden = show_all }

let invalidate (t : t) = t.synced_rev <- -1

(* ---------- wire value access ---------- *)

let pstr store id name = Lui_store.string_prop store id name

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

(* padding / padding-horizontal / padding-vertical → flex padding edges.
   The uniform prop also accepts a string shorthand. *)
let padding_edges ~scale store id : Lui_flex.edges =
  let base = Lui_flex.edges_auto in
  let base =
    match Lui_store.prop store id "padding" with
    | Some (StringValue s) -> (
      match shorthand_lengths ~scale s with
      | Some (t, r, b, l) -> { base with top = t; right = r; bottom = b; left = l }
      | None -> base)
    | Some _ -> { base with all = length_prop ~scale store id "padding" }
    | None -> base
  in
  { base with
    horizontal = length_prop ~scale store id "padding-horizontal";
    vertical = length_prop ~scale store id "padding-vertical" }

(* margin family → flex margin edges, same resolution order as
   padding: shorthand on the uniform prop, then per-axis and per-side
   props win. *)
let margin_edges ~scale store id : Lui_flex.edges =
  let base = Lui_flex.edges_auto in
  let base =
    match Lui_store.prop store id "margin" with
    | Some (StringValue s) -> (
      match shorthand_lengths ~scale s with
      | Some (t, r, b, l) -> { base with top = t; right = r; bottom = b; left = l }
      | None -> base)
    | Some _ -> { base with all = length_prop ~scale store id "margin" }
    | None -> base
  in
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
    | "row" | "grid" | "button" | "toggle-button" | "menu-item"
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
  | _ -> if scroll_kind kind then Scroll else Visible

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
      | "popover" | "alert" -> Pt (8. *. scale)
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
         | None -> d.justify_content);
      align_items =
        (match pstr store id "cross" with
         | Some s -> align_of_string s
         | None -> (
           (* Grouped controls and labeled chrome center their children
              on the cross axis — .lui-button / .lui-menu-item are
              items-center flex rows on the web. *)
           match kind with
           | "button" | "toggle-button" | "menu-item"
           | "button-group" | "toggle-group" | "input-group-actions"
           | "breadcrumb" | "pagination" | "toolbar" -> Align_center
           | _ -> d.align_items));
      position_type;
      flex_wrap =
        (match pstr store id "flex-wrap" with
         | Some "wrap" -> Wrap
         | Some "nowrap" -> No_wrap
         | _ -> if kind = "grid" || kind = "text" then Wrap else No_wrap);
      overflow = overflow_of ~store ~id kind;
      flex_grow = grow;
      width =
        (match viewport_len ~viewport store id ~name:"width-viewport" ~horizontal:true with
         | Unset -> (
           match lp "width" with Unset -> size_w | l -> l)
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
let adjust ~pkind ~pid ~index store id (style : Lui_flex.style) : Lui_flex.style =
  let style =
    if pkind = "frame" && not (popup_kind (Lui_store.kind store id)) then
      (* Non-popup store roots fill the frame. *)
      { style with flex_grow = 1. }
    else style
  in
  let style =
    if zstack_kind pkind && index > 0 then
      { style with
        position_type = Lui_flex.Absolute;
        position = overlay_edges store id }
    else style
  in
  let style =
    if pkind = "grid" then
      let basis =
        match pnum store pid "columns" with
        | Some n when n > 0. -> Lui_flex.Percent (100. /. n)
        | _ -> Pt 0.
      in
      (* Cells stay at exactly 1/n of the row — no grow, else a lone
         cell on the last line would stretch to full width. *)
      { style with flex_basis = basis }
    else style
  in
  let style =
    if pkind = "split" then
      (* The split kind's ~value is the first pane's fraction of the
         track. The second pane grows into the remainder; the gap is
         the divider. *)
      match Lui_store.child_ids store pid with
      | first :: second :: _ ->
        if id = first then (
          match pnum store pid "value" with
          | Some v ->
            (* Panes clip like the web resizer: a collapsed track
               hides its content instead of letting it leak into the
               sibling pane, and min-width:0 lets the track actually
               reach the fraction instead of its content's floor. *)
            { style with
              flex_basis = Lui_flex.Percent (v *. 100.); flex_grow = 0.;
              min_width = Pt 0.; overflow = Hidden }
          | None -> style)
        else if id = second then
          { style with flex_grow = 1.; min_width = Pt 0.; overflow = Hidden }
        else style
      | _ -> style
    else style
  in
  let style =
    if scroll_kind pkind then
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
  hidden : int -> bool; (* host-owned transient visibility (menus) *)
  ctx_anchor : (float * float) option; (* pointer point for context menus *)
  store : Lui_store.t;
  nodes : (int, Lui_flex.node) Hashtbl.t; (* store id → flex node *)
  applied : (int, Lui_flex.style) Hashtbl.t; (* store id → applied style *)
  grids : (Lui_flex.node * Lui_flex.style * float) list ref;
  popups : (Lui_flex.node * int) list ref; (* flex node, store id *)
  vlists : (int, vlist) Hashtbl.t; (* virtual-list states (t.vlists) *)
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
        rows = Hashtbl.create 16;
        nodes = Hashtbl.create 64;
        mounted_ids = [];
        key_index = None;
        id_index = None;
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
      match Lui_store.child_id_at store v.vid 0 with
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

(* [build] expands a store node into flex nodes — a singleton list for
   normal kinds, [] for display:none, and the lifted children for
   display:contents. [index] is the flattened sibling position. *)
let rec build ctx store ~pkind ~pid ~index id : Lui_flex.node list =
  if display_none store id || ctx.hidden id then []
  else if display_contents store id then
    build_seq ctx store ~pkind ~pid ~first:index (Lui_store.child_ids store id)
  else
    let style =
      style_of ~scale:ctx.scale ~viewport:(ctx.vw, ctx.vh) store id
      |> adjust ~pkind ~pid ~index store id
    in
    let kind = Lui_store.kind store id in
    if kind = "virtual-list" && vlist_vertical store id then begin
      (* Real virtualization: the list is a leaf in this mirror — only
         the mounted row window gets flex trees (side forest). *)
      let v = vlist_state ctx id in
      vlist_configure ctx store v style;
      let style = vlist_leaf_style ctx v style in
      let node = Lui_flex.create ~style [] in
      Hashtbl.replace ctx.nodes id node;
      Hashtbl.replace ctx.applied id style;
      [ node ]
    end
    else
    let cids = ordered_child_ids store id kind in
    let kids = build_seq ctx store ~pkind:kind ~pid:id ~first:0 cids in
    let text = text_of store id in
    let style =
      (* A node whose built children are all popup surfaces (e.g. a
         menu trigger) still sizes to its own label — the popups are
         out of flow and contribute nothing. *)
      match (kids, text) with
      | _ :: _, Some t
        when List.for_all
               (fun cid -> popup_kind (Lui_store.kind store cid))
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
    in
    let m =
      match (kids, text) with
      | [], Some t -> (
        match Lui_store.prop store id "icon" with
        | Some (StringValue s) when s <> "" ->
          (* labeled_content_ops paints a 16px icon slot + 6px gap —
             reserve them so the label doesn't overflow the chrome *)
          let icon_extra = 22. *. ctx.scale in
          Some
            (fun node ~width ~width_mode ~height ~height_mode ->
              let d =
                measure_of ctx.tm ~id ~text:t node ~width ~width_mode
                  ~height ~height_mode
              in
              { d with Lui_flex.width = d.Lui_flex.width +. icon_extra })
        | _ -> Some (measure_of ctx.tm ~id ~text:t))
      | _ -> None
    in
    let node = Lui_flex.create ~style ?measure:m kids in
    Hashtbl.replace ctx.nodes id node;
    Hashtbl.replace ctx.applied id style;
    (if kind = "grid" then
       match pnum store id "columns" with
       | Some n when n > 0. ->
         ctx.grids := (node, style, n) :: !(ctx.grids)
       | _ -> ());
    (if popup_kind kind
        && not (kind = "drawer" && has_prop store id "selected")
     then ctx.popups := (node, id) :: !(ctx.popups));
    [ node ]

and build_seq ctx store ~pkind ~pid ~first ids : Lui_flex.node list =
  let counter = ref first in
  List.concat_map
    (fun cid ->
      let ns = build ctx store ~pkind ~pid ~index:!counter cid in
      counter := !counter + List.length ns;
      ns)
    ids

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

(* Reverse lookup: store id that produced [fnode] (physical equality —
   the mirror is rebuilt per sync and discarded right after). *)
let store_id_of_flex ctx fnode =
  let found = ref None in
  Hashtbl.iter
    (fun sid n -> if !found = None && n == fnode then found := Some sid)
    ctx.nodes;
  !found

(* Pin every flex child of a [columns = n] grid to its real share of
   the row so [n] cells plus [(n-1)] gaps fit one line. *)
let refine_grids ctx =
  List.iter
    (fun (gnode, (gstyle : Lui_flex.style), ncols) ->
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
        (fun c ->
          match store_id_of_flex ctx c with
          | Some sid -> (
            match Hashtbl.find_opt ctx.applied sid with
            | Some s ->
              Lui_flex.set_style c { s with flex_basis = Pt basis }
            | None -> ())
          | None -> ())
        (Lui_flex.children gnode))
    !(ctx.grids)

(* Popup anchoring: [x]/[y] supply an anchor point (a zero-size anchor
   box inside the containing block); bare [anchor] uses the parent rect
   as the anchor box, like the web backend's element anchoring. [anchor]
   names the preferred side (below default), [anchor-alignment] the
   cross-axis alignment (start default), [anchor-offset] the gap
   (4px default). *)
let anchor_rect_of ctx store id ~cb pr =
  let s = ctx.scale in
  let f name = Option.map (fun v -> v *. s) (pnum store id name) in
  match (f "x", f "y") with
  | Some x, Some y -> { Lui_flex.x = cb.x +. x; y = cb.y +. y; w = 0.; h = 0. }
  | _ -> pr

let anchored_xy ctx store sid ar (prp : Lui_flex.rect) =
  let s = ctx.scale in
  let offset = Option.value ~default:4. (pnum store sid "anchor-offset") *. s in
  let side =
    match pstr store sid "anchor" with
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
    match side with
    | "above" -> ar.y -. offset -. prp.h
    | "left" -> ar.x -. offset -. prp.w
    | "right" -> ar.x +. ar.w +. offset
    | _ -> ar.y +. ar.h +. offset
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
  let x, y = if vertical then (cross, main) else (main, cross) in
  (* Clamp inside the viewport so the popup stays on-screen — the
     containing block may be smaller than the panel (a menu
     trigger). *)
  ( Float.max 0. (Float.min x (Float.max 0. (ctx.vw -. prp.w))),
    Float.max 0. (Float.min y (Float.max 0. (ctx.vh -. prp.h))) )

(* Center each default-placed popup in its containing block by giving
   its spec concrete [left]/[top] offsets. Position edges resolve
   against the parent's padding box (offset + border + margin lands at
   the child's layout position), so the center of the border box is
   [parent.w/2 - border - margin]. *)
let refine_popups ctx =
  (* Bottom y of the last placed toast per containing block, so a
     viewport's toasts stack downward like the web viewport. *)
  let toast_next = Hashtbl.create 2 in
  List.iter
    (fun (pnode, sid) ->
      match Lui_flex.parent pnode with
      | None -> ()
      | Some parent -> (
        let pr, pstyle_opt =
          match store_id_of_flex ctx parent with
          | Some psid ->
            ( Lui_flex.absolute_layout parent,
              Hashtbl.find_opt ctx.applied psid )
          | None ->
            (* The frame root is no store node's containing block —
               default to the offered frame, not the grown extent. *)
            ( { Lui_flex.x = 0.; y = 0.; w = ctx.vw; h = ctx.vh },
              None )
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
              | Some n -> Some (Lui_flex.absolute_layout n)
              | None -> None)
            | _ -> (
              match Lui_store.parent ctx.store id with
              | Some anc -> positioned anc
              | None -> None)
          in
          match store_id_of_flex ctx parent with
          | Some psid -> (match positioned psid with
            | Some r -> r
            | None -> pr)
          | None -> pr
        in
        match Hashtbl.find_opt ctx.applied sid with
        | None -> ()
        | Some (pstyle : Lui_flex.style) ->
          let pstyle =
            (* A popup measures against the viewport, not its
               (possibly tiny) parent — bound its max extents and
               re-measure the subtree before placing it. *)
            { pstyle with
              max_width =
                (match pstyle.max_width with Unset -> Pt ctx.vw | m -> m);
              max_height =
                (match pstyle.max_height with Unset -> Pt ctx.vh | m -> m) }
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
          (* Web overlay caps: .lui-toast-viewport is 22.5rem wide,
             .lui-dialog is min(42rem, 100vw-2rem) (48rem ≥1024px). *)
          (match kind with
           | "toast" ->
             let w = Float.min (360. *. ctx.scale) ctx.vw in
             Lui_flex.set_style pnode
               { pstyle with max_width = Pt w };
             Lui_flex.compute_layout pnode ~width:Lui_flex.undefined
               ~height:Lui_flex.undefined ()
           | "dialog" | "modal" ->
             (* Web default cap applies only when the view did not set an
                explicit max-width/max-width-viewport — typed clamps like
                plugins-dashboard's 1246px take precedence. *)
             (match pstyle.max_width with
              | Unset ->
                let rem =
                  if ctx.vw >= 1024. *. ctx.scale then 768. else 672.
                in
                let w =
                  Float.min (rem *. ctx.scale)
                    (ctx.vw -. (32. *. ctx.scale))
                in
                Lui_flex.set_style pnode
                  { pstyle with max_width = Pt w };
                Lui_flex.compute_layout pnode ~width:Lui_flex.undefined
                  ~height:Lui_flex.undefined ()
              | _ -> ())
           | _ -> ());
          let prp = Lui_flex.absolute_layout pnode in
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
                (anchored_xy ctx ctx.store sid
                   (anchor_rect_of ctx ctx.store sid ~cb pr) prp)
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
          Lui_flex.set_style pnode
            { pstyle with
              width = Pt prp.w;
              height;
              position =
                { pstyle.position with left = Pt left; top = Pt top } }))
    (* Mount order: the list is prepended during build; oldest first so
       a toast stack grows downward like the web viewport. *)
    (List.rev !(ctx.popups))

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

let scene_rect (r : Lui_flex.rect) : Lui_scene.rect =
  { x = r.x; y = r.y; w = r.w; h = r.h }

let collect (t : t) =
  Hashtbl.reset t.rects;
  Hashtbl.iter
    (fun id n -> Hashtbl.replace t.rects id (scene_rect (Lui_flex.absolute_layout n)))
    t.nodes

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

(* Mount the row subtrees for [first, last): drop the ones that left
   the window, build the ones that entered. A row is a standalone flex
   tree measured against the list's content width; its laid-out main
   extent refines the model ([vlist_measure]). *)
let build_vrows t ctx store (v : vlist) ~first ~last =
  let stale = ref [] in
  Hashtbl.iter
    (fun i (_ : vrow) -> if i < first || i >= last then stale := i :: !stale)
    v.rows;
  List.iter
    (fun i ->
       match Hashtbl.find_opt v.rows i with
       | Some row ->
         List.iter (fun id -> Hashtbl.remove v.nodes id) row.rids;
         List.iter (fun id -> Hashtbl.remove t.rects id) row.rids;
         Hashtbl.remove v.rows i
       | None -> ())
    !stale;
  for i = first to last - 1 do
    if not (Hashtbl.mem v.rows i) then begin
      let cid = Lui_store.child_id_at store v.vid i in
      if cid >= 0 then begin
        (* Row-local context: registrations land in the list's own
           node table so [collect] stays a mirror-only pass. *)
        let rctx =
          { ctx with
            nodes = v.nodes;
            applied = Hashtbl.create 8;
            grids = ref [];
            popups = ref [] }
        in
        let kids =
          build rctx store ~pkind:"virtual-list" ~pid:v.vid ~index:i cid
        in
        let root =
          match kids with
          | [ n ] -> n
          | _ -> Lui_flex.create kids
        in
        Lui_flex.compute_layout root ~width:v.cross_size
          ~height:Lui_flex.undefined ();
        refine_grids rctx;
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
       let f, l = vlist_range v in
       if f <> v.first || l <> v.last || Hashtbl.length v.rows < l - f
       then begin
         v.first <- f;
         v.last <- l;
         build_vrows t ctx store v ~first:f ~last:l;
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
  List.iter (fun id -> Hashtbl.remove t.rects id) v.mounted_ids;
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
              Hashtbl.replace t.rects id
                {
                  Lui_scene.x = v.origin_cross +. (r.x -. rr.x);
                  y = ry +. (r.y -. rr.y);
                  w = r.w;
                  h = r.h;
                };
              ids := id :: !ids
            | None -> ())
         row.rids)
    v.rows;
  v.mounted_ids <- !ids

let vlists_collect (t : t) =
  Hashtbl.iter (fun _ v -> collect_vlist t v) t.vlists

(* Full-sync pass: prune dead lists, learn geometry, mount the fed
   windows, and repatch leaf extents when measurements moved them. *)
let vlists_prepare (t : t) ctx ~vport ~width ~height =
  let store = ctx.store in
  Hashtbl.filter_map_inplace
    (fun id v ->
       if Lui_store.kind store id = "virtual-list" && vlist_vertical store id
       then Some v
       else None)
    t.vlists;
  if Hashtbl.length t.vlists > 0 then begin
    (* Row subtrees were built under the previous sync's context —
       props, scale and viewport may all have changed, so the mounted
       forest rebuilds from scratch against the fresh ctx. *)
    Hashtbl.iter
      (fun _ (v : vlist) ->
         Hashtbl.reset v.rows;
         Hashtbl.reset v.nodes)
      t.vlists;
    Hashtbl.iter (fun _ v -> vlist_geometry ctx v) t.vlists;
    ignore (vlists_mount t ctx store ~vport);
    if vlists_patch t ctx then begin
      (match t.root with
       | Some root ->
         let ew, eh = layout_frame root ~width ~height in
         t.extent <- (ew, eh);
         Hashtbl.iter (fun _ v -> vlist_geometry ctx v) t.vlists;
         ignore (vlists_mount t ctx store ~vport)
       | None -> ())
    end
  end

(* A build ctx reconstructed from the saved sync inputs — used by the
   memo-hit path to remount row windows without a mirror rebuild. *)
let ctx_of_saved (t : t) (sc : saved_ctx) : ctx =
  { scale = sc.sc_scale;
    vw = sc.sc_vw;
    vh = sc.sc_vh;
    tm = sc.sc_tm;
    hidden = sc.sc_hidden;
    ctx_anchor = sc.sc_anchor;
    store = sc.sc_store;
    nodes = t.nodes;
    applied = t.applied;
    grids = ref [];
    popups = ref [];
    vlists = t.vlists }

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
             collect t
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

let sync ?(scale = 1.) ?(measure = no_measure) ?(hidden = show_all)
    ?ctx_anchor ?(vport = no_vport) ~width ~height (t : t) store =
  let rev = Lui_store.revision store in
  (* The store bumps its revision on every mutation, so a matching key
     means the rebuild below would produce an identical mirror —
     skipped wholesale (scroll-only and idle repaints pay nothing). *)
  if
    t.synced_rev <> rev || t.synced_scale <> scale
    || t.synced_w <> width || t.synced_h <> height
    || t.synced_anchor <> ctx_anchor
    || (not (t.synced_measure == measure))
    || (not (t.synced_hidden == hidden))
  then begin
    Hashtbl.reset t.nodes;
    Hashtbl.reset t.applied;
    let ctx =
      { scale; vw = width; vh = height; tm = measure; hidden;
        ctx_anchor; store; nodes = t.nodes;
        applied = t.applied; grids = ref []; popups = ref [];
        vlists = t.vlists }
    in
    let kids =
      build_seq ctx store ~pkind:"frame" ~pid:(-1) ~first:0
        (Lui_store.root_ids store)
    in
    let root =
      Lui_flex.create ~style:(frame_style_for width (Pt height)) kids
    in
    t.root <- Some root;
    let ew, eh = layout_frame root ~width ~height in
    refine_grids ctx;
    refine_popups ctx;
    (if !(ctx.grids) <> [] || !(ctx.popups) <> [] then
       Lui_flex.compute_layout root ~width:ew ~height:eh ());
    t.extent <- (ew, eh);
    vlists_prepare t ctx ~vport ~width ~height;
    collect t;
    vlists_collect t;
    t.synced_rev <- rev;
    t.synced_scale <- scale;
    t.synced_w <- width;
    t.synced_h <- height;
    t.synced_anchor <- ctx_anchor;
    t.synced_measure <- measure;
    t.synced_hidden <- hidden;
    t.vctx <-
      Some
        { sc_scale = scale; sc_vw = width; sc_vh = height;
          sc_tm = measure; sc_hidden = hidden; sc_anchor = ctx_anchor;
          sc_store = store }
  end
  else
    (* Memo-hit: only the fed viewports may have moved — remount the
       virtual-list windows that slid instead of rebuilding anything. *)
    vlists_update t ~vport

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
          let cid = Lui_store.child_id_at store id i in
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
let virtual_index_of_id (t : t) store id cid =
  match Hashtbl.find_opt t.vlists id with
  | None -> None
  | Some v ->
    let m =
      match v.id_index with
      | Some m -> m
      | None ->
        let m = Hashtbl.create 64 in
        for i = 0 to v.count - 1 do
          let k = Lui_store.child_id_at store id i in
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
