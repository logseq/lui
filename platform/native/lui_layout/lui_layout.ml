(* Store → flex glue for the native backend.

   The mirror is rebuilt wholesale on every {!sync}; the store is small
   and rebuild-per-sync keeps invalidation trivial. All wire lengths are
   logical px and are multiplied by [scale] as they become flex style
   values, so the computed rects land in device px — the coordinate
   space [Lui_paint] and [Lui_scene] use. *)

open Lui_protocol
open Lui_flex

type text_measure = int -> string -> float -> float -> (float * float) option

type t = {
  mutable root : Lui_flex.node option;
  nodes : (int, Lui_flex.node) Hashtbl.t; (* store id → flex node *)
  rects : (int, Lui_scene.rect) Hashtbl.t;
  mutable extent : float * float; (* frame extent the last layout used *)
}

let create () =
  { root = None;
    nodes = Hashtbl.create 64;
    rects = Hashtbl.create 64;
    extent = (0., 0.) }

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
    | "row" | "grid" | "button-group" | "toggle-group"
    | "input-group-actions" | "table-row" | "tabs" | "bottom-tabs"
    | "toolbar" | "swipe-actions" | "stepper" | "breadcrumb"
    | "pagination" | "split" | "drawer" | "link" -> Row
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
      match pstr store id "size" with
      | Some "icon" -> (Pt (40. *. scale), Pt (40. *. scale))
      | Some "sm" | Some "small" -> (Unset, Pt (36. *. scale))
      | Some "lg" | Some "large" -> (Unset, Pt (44. *. scale))
      | Some _ -> (Unset, Pt (40. *. scale))
      | None -> (Unset, Unset))
    | _ -> (Unset, Unset)
  in
  let style =
    { d with
      flex_direction = direction_of ~store ~id kind;
      justify_content =
        (match pstr store id "main" with
         | Some s -> justify_of_string s
         | None -> (
           (* Labeled chrome centers its content vertically — the web
              stylesheet's .lui-menu-item items-center on the cross axis
              of a horizontal flex is the main axis of this column
              kind. *)
           match kind with
           | "menu-item" -> Justify_center
           | _ -> d.justify_content));
      align_items =
        (match pstr store id "cross" with
         | Some s -> align_of_string s
         | None -> (
           (* Grouped controls center their children on the cross axis. *)
           match kind with
           | "button-group" | "toggle-group" | "input-group-actions"
           | "breadcrumb" | "pagination" | "toolbar" -> Align_center
           | _ -> d.align_items));
      position_type;
      flex_wrap = (if kind = "grid" then Wrap else No_wrap);
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
   latter). *)
let text_of store id =
  match Lui_store.prop store id "text" with
  | Some (StringValue s) when s <> "" -> Some s
  | _ -> (
    match Lui_store.prop store id "placeholder" with
    | Some (StringValue s) when s <> "" -> Some s
    | _ -> (
      match Lui_store.prop store id "title" with
      | Some (StringValue s) when s <> "" -> Some s
      | _ -> None))

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
}

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

let compute t ~width ~height =
  match t.root with
  | None -> ()
  | Some root ->
    t.extent <- layout_frame root ~width ~height;
    collect t

let sync ?(scale = 1.) ?(measure = (fun _ _ _ _ -> None))
    ?(hidden = fun _ -> false) ?ctx_anchor ~width ~height (t : t) store =
  Hashtbl.reset t.nodes;
  let ctx =
    { scale; vw = width; vh = height; tm = measure; hidden; ctx_anchor;
      store; nodes = t.nodes;
      applied = Hashtbl.create 64; grids = ref []; popups = ref [] }
  in
  let kids =
    build_seq ctx store ~pkind:"frame" ~pid:(-1) ~first:0
      (Lui_store.root_ids store)
  in
  let root = Lui_flex.create ~style:(frame_style_for width (Pt height)) kids in
  t.root <- Some root;
  let ew, eh = layout_frame root ~width ~height in
  refine_grids ctx;
  refine_popups ctx;
  (if !(ctx.grids) <> [] || !(ctx.popups) <> [] then
     Lui_flex.compute_layout root ~width:ew ~height:eh ());
  t.extent <- (ew, eh);
  collect t

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
