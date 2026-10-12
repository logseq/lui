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

type t = {
  mutable root : Lui_flex.node option;
  (* The mirror is persistent: maps below live across syncs and the
     journal replays store ops onto them. *)
  nodes : (int, Lui_flex.node) Hashtbl.t; (* store id → flex node *)
  applied : (int, Lui_flex.style) Hashtbl.t; (* store id → applied style *)
  rects : (int, Lui_scene.rect) Hashtbl.t;
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
  mutable synced_rev : int;
  mutable synced_lrev : int;
  mutable synced_scale : float;
  mutable synced_w : float;
  mutable synced_h : float;
  mutable synced_anchor : (float * float) option;
  mutable synced_measure : text_measure;
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
    rect_dirty = Hashtbl.create 16;
    rect_changed = Hashtbl.create 64;
    pkids = Hashtbl.create 64;
    sparent = Hashtbl.create 64;
    owner = Hashtbl.create 64;
    grids = ref [];
    popups = ref [];
    extent = (0., 0.);
    synced_rev = -1;
    synced_lrev = -1;
    synced_scale = 0.;
    synced_w = 0.;
    synced_h = 0.;
    synced_anchor = None;
    synced_measure = no_measure;
    synced_hidden = show_all;
    stat_syncs = 0;
    stat_steps = 0 }

let invalidate (t : t) = t.synced_rev <- -1
let stat_syncs (t : t) = t.stat_syncs
let stat_steps (t : t) = t.stat_steps

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
  eng : t; (* back-reference: root and rects *)
  nodes : (int, Lui_flex.node) Hashtbl.t; (* store id → flex node *)
  applied : (int, Lui_flex.style) Hashtbl.t; (* store id → applied style *)
  pkids : (int, pkid list) Hashtbl.t;
  sparent : (int, int) Hashtbl.t;
  owner : (int, int) Hashtbl.t;
  grids : (int * Lui_flex.node * Lui_flex.style * float) list ref;
  popups : (Lui_flex.node * int) list ref; (* flex node, store id *)
}

let kind_of ctx id = if id = frame_id then "frame" else Lui_store.kind ctx.store id

(* What a store node produces into its flex parent's children. *)
type nstatus = N_hidden | N_contents | N_normal

let status_of ctx id =
  if display_none ctx.store id || ctx.hidden id then N_hidden
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

let measure_for ctx id ~kids : Lui_flex.measure option =
  match (kids, text_of ctx.store id) with
  | [], Some t -> (
    match Lui_store.prop ctx.store id "icon" with
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

let register ctx id kind node style =
  (if kind = "grid" then
     match pnum ctx.store id "columns" with
     | Some n when n > 0. ->
       ctx.grids := (id, node, style, n) :: !(ctx.grids)
     | _ -> ());
  if popup_kind kind
     && not (kind = "drawer" && has_prop ctx.store id "selected")
  then ctx.popups := (node, id) :: !(ctx.popups)

let unregister ctx id =
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
      |> adjust ~pkind ~pid ~index ctx.store id
    in
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

(* Pin every flex child of a [columns = n] grid to its real share of
   the row so [n] cells plus [(n-1)] gaps fit one line. The produced
   children come from pkids — the mirror is persistent, so a reverse
   flex→store lookup is no longer needed. *)
let refine_grids ctx =
  List.iter
    (fun (gsid, gnode, (gstyle : Lui_flex.style), ncols) ->
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
                Lui_flex.set_style f { s with flex_basis = Pt basis }
              | _ -> ())
            e.gens)
        (pkids_of ctx gsid))
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
          match psid_opt with
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

(* Re-read [id]'s absolute rect into [t.rects], marking it changed when
     it differs from what consumers last saw. *)
let update_rect (t : t) id r =
  let r' = scene_rect r in
  (match Hashtbl.find_opt t.rects id with
   | Some old when old = r' -> ()
   | _ -> Hashtbl.replace t.rect_changed id ());
  Hashtbl.replace t.rects id r'

let collect (t : t) =
  Hashtbl.iter
    (fun id n -> update_rect t id (Lui_flex.absolute_layout n))
    t.nodes

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
let restyle_gen ctx o g =
  match Hashtbl.find_opt ctx.nodes g with
  | Some f ->
    let index = produced_index ctx o g in
    let style =
      style_of ~scale:ctx.scale ~viewport:(ctx.vw, ctx.vh) ctx.store g
      |> adjust ~pkind:(kind_of ctx o) ~pid:o ~index ctx.store g
    in
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
    register ctx g kind f style
  | None -> ()

(* Parent kinds whose child adjustment depends on sibling position:
   membership or order churn under them rewrites sibling styles, not
   just the moved node's. *)
let index_sensitive = function
  | "overlay" | "stack" | "panel" | "card" | "resizable"
  | "view-that-fits" | "split" | "edge-inset" -> true
  | _ -> false

let restyle_children_of ctx o =
  List.iter
    (fun e -> List.iter (fun g -> restyle_gen ctx o g) e.gens)
    (pkids_of ctx o)

(* Insert/MoveChild: detach the shadow entry from the old raw parent,
   ensure the child's produced set exists, then let [sync_entries]
   place it at the store's current position. *)
let attach_child ctx ~parent:p ~child:c =
  (match Hashtbl.find_opt ctx.sparent c with
   | Some op when op <> p ->
     sync_entries ctx op;
     commit ctx op;
     mark_affected ctx (children_owner ctx op)
   | _ -> ());
  let o = children_owner ctx p in
  let gens = ensure_produced ctx ~owner_id:o c in
  Hashtbl.replace ctx.sparent c p;
  sync_entries ctx p ~overrides:[ (c, gens) ];
  (* Commit before restyling: gens indices inside the owner's produced
     list only read correctly once the parent chain has propagated. *)
  commit ctx p;
  List.iter
    (fun g ->
      Hashtbl.replace ctx.owner g o;
      restyle_gen ctx o g)
    gens;
  (if index_sensitive (kind_of ctx o) then restyle_children_of ctx o);
  mark_affected ctx o

let detach_child ctx ~parent:p ~child:c =
  Hashtbl.remove ctx.sparent c;
  sync_entries ctx p;
  commit ctx p;
  let o = children_owner ctx p in
  (if index_sensitive (kind_of ctx o) then restyle_children_of ctx o);
  mark_affected ctx o

(* The store link is already gone (drop/recreate): find the old raw
   parent in the shadow, drop the entry, keep the subtree for reuse. *)
let detach_from_parent ctx id =
  match Hashtbl.find_opt ctx.sparent id with
  | Some par ->
    Hashtbl.remove ctx.sparent id;
    sync_entries ctx par;
    commit ctx par;
    mark_affected ctx (children_owner ctx par)
  | None -> ()

(* Remove id's flex node and every built descendant's mirror state. *)
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
  List.iter
    (fun e ->
      List.iter
        (fun g ->
          Hashtbl.replace ctx.owner g o;
          restyle_gen ctx o g)
        e.gens)
    (pkids_of ctx id);
  mark_affected ctx o

let apply_journal_op ctx (op : patch_op) =
  match op with
  | SetProp (id, p, _) | RemoveProp (id, p) -> (
    let m =
      Lui_store.mask_of_prop (Lui_wire_schema.property_name p)
    in
    if m land (Lui_store.d_structure lor Lui_store.d_layout lor Lui_store.d_layout_kids) = 0 then ()
    else if Lui_store.mask_has m Lui_store.d_structure then reexpand ctx id
    else begin
      if Lui_store.mask_has m Lui_store.d_layout then restyle_self ctx id;
      if Lui_store.mask_has m Lui_store.d_layout_kids then
        restyle_children ctx id
    end)
  | SetExtensionProp (id, _, _) | RemoveExtensionProp (id, _) ->
    (* Unknown prop semantics: restyle the node and its children. *)
    restyle_self ctx id;
    restyle_children ctx id
  | CreateNode (id, _) | CreateExtension (id, _, _)
  | DropNode id | DetachSubtree id ->
    detach_from_parent ctx id;
    purge ctx id
  | InsertChild (p, c, _) | MoveChild (p, c, _) -> attach_child ctx ~parent:p ~child:c
  | RemoveChild (p, c) -> detach_child ctx ~parent:p ~child:c

(* Rect refresh scoped to dirty owner subtrees: every produced
   descendant of a dirty owner gets its rect re-read (a resized node
   moves its siblings, so the refresh root is the owner — the flex
   parent — not the changed node). [frame_id] dirties everything. *)
let rec refresh_sub ctx sid =
  (match Hashtbl.find_opt ctx.nodes sid with
   | Some f -> update_rect ctx.eng sid (Lui_flex.absolute_layout f)
   | None -> ());
  List.iter
    (fun e -> List.iter (fun g -> refresh_sub ctx g) e.gens)
    (pkids_of ctx sid)

let refresh_rects ctx =
  if Hashtbl.mem ctx.eng.rect_dirty frame_id then collect ctx.eng
  else
    Hashtbl.iter (fun sid () -> refresh_sub ctx sid) ctx.eng.rect_dirty;
  Hashtbl.reset ctx.eng.rect_dirty

let ctx_of t store ~scale ~measure ~hidden ctx_anchor ~width ~height : ctx =
  { scale; vw = width; vh = height; tm = measure; hidden; ctx_anchor;
    store; eng = t; nodes = t.nodes; applied = t.applied;
    pkids = t.pkids; sparent = t.sparent; owner = t.owner;
    grids = t.grids; popups = t.popups }

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

let finish ctx (t : t) ~width ~height =
  match t.root with
  | None -> ()
  | Some root ->
    let ew, eh = layout_frame root ~width ~height in
    refine_grids ctx;
    refine_popups ctx;
    (if !(ctx.grids) <> [] || !(ctx.popups) <> [] then
       Lui_flex.compute_layout root ~width:ew ~height:eh ());
    t.extent <- (ew, eh);
    refresh_rects ctx

let sync ?(scale = 1.) ?(measure = no_measure) ?(hidden = show_all)
    ?ctx_anchor ~width ~height (t : t) store =
  let inputs_changed =
    t.synced_scale <> scale
    || t.synced_w <> width || t.synced_h <> height
    || t.synced_anchor <> ctx_anchor
    || (not (t.synced_measure == measure))
    || (not (t.synced_hidden == hidden))
  in
  (* Fast path: inputs stable and the store's layout revision
     unmoved — paint-only churn, scroll-only and idle frames all skip
     the mirror entirely. The store-revision cursor still advances so
     the journal never re-feeds paint ops. *)
  if
    (not inputs_changed) && t.synced_rev >= 0
    && t.synced_lrev = Lui_store.layout_rev store
  then t.synced_rev <- Lui_store.revision store
  else begin
    t.stat_syncs <- t.stat_syncs + 1;
    let ctx = ctx_of t store ~scale ~measure ~hidden ctx_anchor ~width ~height in
    let full =
      if inputs_changed || t.synced_rev < 0 || t.root = None then true
      else
        match Lui_store.changes_since store t.synced_rev with
        | None -> true
        | Some ops ->
          t.stat_steps <- t.stat_steps + 1;
          List.iter (apply_journal_op ctx) ops;
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
          false
    in
    if full then rebuild ctx t ~width ~height;
    finish ctx t ~width ~height;
    t.synced_rev <- Lui_store.revision store;
    t.synced_lrev <- Lui_store.layout_rev store;
    t.synced_scale <- scale;
    t.synced_w <- width;
    t.synced_h <- height;
    t.synced_anchor <- ctx_anchor;
    t.synced_measure <- measure;
    t.synced_hidden <- hidden
  end

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
