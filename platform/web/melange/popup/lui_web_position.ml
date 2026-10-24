(* Popup geometry, select-item alignment, and the
   submenu pointer corridor.
   Source: /tmp/lui-web-ref/web.cljc lines 3137-3345 and 5439-5597. *)

open Lui_protocol
open Lui_web_types

module W = Webapi.Dom
module Store = Lui_web_store
module Util = Lui_web_util
module Nodes = Lui_web_nodes

let css_px value = Js.Float.toString value ^ "px"

let set_style element name value =
  Util.set_style
    (W.HtmlElement.style (W.Element.unsafeAsHtmlElement element))
    name value

let collision_padding renderer node =
  match Store.property renderer.web_store node CollisionPadding with
  | Some (FloatValue value) -> value
  | _ -> 8.0

let clamp_popup_axis ~padding value size viewport_start viewport_size =
  let edge = viewport_start +. padding in
  let maximum = max edge (viewport_start +. viewport_size -. size -. padding) in
  max edge (min value maximum)

(* Base UI collision, with LUI's 8px default gutter left intact.
   Dropdown, select, and combobox roots flip only on the preferred axis
   (fallbackAxisSide none), then flip start/end alignment before a last
   resort shift. Popovers, tooltips, and nested menus may leave that axis
   when neither side fits, trying the perpendicular end side first. *)
let placement_spaces ~padding anchor_bounds viewport_left viewport_top
    viewport_width viewport_height offset =
  let above = W.DomRect.top anchor_bounds -. viewport_top -. offset -. padding in
  let below =
    viewport_top +. viewport_height -. W.DomRect.bottom anchor_bounds -. offset -. padding
  in
  let left = W.DomRect.left anchor_bounds -. viewport_left -. offset -. padding in
  let right =
    viewport_left +. viewport_width -. W.DomRect.right anchor_bounds -. offset -. padding
  in
  (above, below, left, right)

let side_space side (above, below, left, right) =
  match side with
  | "above" -> above
  | "left" -> left
  | "right" -> right
  | _ -> below

let side_main_size side popup_width popup_height =
  if side = "left" || side = "right" then popup_width else popup_height

let side_fits side popup_width popup_height spaces =
  side_main_size side popup_width popup_height <= side_space side spaces

let main_axis_side preferred popup_width popup_height spaces =
  let choose preferred_side opposite size =
    let preferred_space = side_space preferred_side spaces in
    let opposite_space = side_space opposite spaces in
    if size <= preferred_space || preferred_space >= opposite_space then
      preferred_side
    else opposite
  in
  match preferred with
  | "above" -> choose "above" "below" popup_height
  | "left" -> choose "left" "right" popup_width
  | "right" -> choose "right" "left" popup_width
  | _ -> choose "below" "above" popup_height

let perpendicular_sides preferred rtl =
  match preferred with
  | "left" | "right" -> [ "below"; "above" ]
  | _ -> if rtl then [ "left"; "right" ] else [ "right"; "left" ]

let resolved_popup_side ~padding ~fallback ~rtl preferred anchor_bounds
    popup_width popup_height viewport_left viewport_top viewport_width
    viewport_height offset =
  let spaces =
    placement_spaces ~padding anchor_bounds viewport_left viewport_top
      viewport_width viewport_height offset
  in
  let main = main_axis_side preferred popup_width popup_height spaces in
  if (not fallback) || side_fits main popup_width popup_height spaces then main
  else
    let rec first_fit = function
      | [] -> main
      | side :: rest ->
          if side_fits side popup_width popup_height spaces then side
          else first_fit rest
    in
    first_fit (perpendicular_sides preferred rtl)

let cross_aligned alignment origin anchor_size popup_size =
  match alignment with
  | "center" -> origin +. (anchor_size /. 2.0) -. (popup_size /. 2.0)
  | "end" -> origin +. anchor_size -. popup_size
  | _ -> origin

let cross_overflow ~padding value popup_size viewport_start viewport_size =
  let edge = viewport_start +. padding in
  let limit = viewport_start +. viewport_size -. padding in
  max 0.0 (edge -. value) +. max 0.0 (value +. popup_size -. limit)

let resolved_alignment ~padding alignment vertical anchor_bounds popup_width
    popup_height viewport_left viewport_top viewport_width viewport_height =
  if alignment = "center" then alignment
  else
    let origin, anchor_size, popup_size, view_start, view_size =
      if vertical then
        (W.DomRect.left anchor_bounds, W.DomRect.width anchor_bounds, popup_width,
         viewport_left, viewport_width)
      else
        (W.DomRect.top anchor_bounds, W.DomRect.height anchor_bounds, popup_height,
         viewport_top, viewport_height)
    in
    let overflow alignment =
      cross_overflow ~padding
        (cross_aligned alignment origin anchor_size popup_size)
        popup_size view_start view_size
    in
    let opposite = if alignment = "end" then "start" else "end" in
    if overflow opposite < overflow alignment then opposite else alignment

let document_rtl document =
  match W.HtmlDocument.defaultView (W.Document.unsafeAsHtmlDocument document) with
  | None -> false
  | Some window ->
      W.CssStyleDeclaration.direction
        (W.Window.getComputedStyle (W.Document.documentElement document) window)
      = "rtl"

let position_anchored ?(padding = 8.0) ?(alignment_offset = 0.0) ?(fallback = false)
    document positioner popup anchor_bounds preferred alignment offset =
  let scroll_top = W.Element.scrollTop popup
  and scroll_left = W.Element.scrollLeft popup in
  (* The undecorated positioner keeps fractional layout dimensions while
     its painted child scales. A tooltip is its own positioner, so use its
     untransformed offset dimensions instead of the animated bounds. *)
  let measure () =
    if W.Element.isSameNode (W.Element.asNode popup) positioner then
      let element = W.Element.unsafeAsHtmlElement popup in
      (float_of_int (W.HtmlElement.offsetWidth element),
       float_of_int (W.HtmlElement.offsetHeight element))
    else
      let bounds = W.Element.getBoundingClientRect positioner in
      (W.DomRect.width bounds, W.DomRect.height bounds)
  in
  let viewport_left, viewport_top, viewport_width, viewport_height =
    Lui_web_popup_tracking.viewport_bounds document
  in
  let available_width = max 0.0 (viewport_width -. (2.0 *. padding)) in
  let available_height = max 0.0 (viewport_height -. (2.0 *. padding)) in
  (* clamp to the viewport before the first measure so an oversized popup
     reports its constrained size *)
  set_style popup "--lui-popup-available-width" (css_px available_width);
  set_style popup "--lui-popup-available-height" (css_px available_height);
  let popup_width, popup_height = measure () in
  let side =
    resolved_popup_side ~padding ~fallback ~rtl:(document_rtl document) preferred
      anchor_bounds popup_width popup_height viewport_left viewport_top
      viewport_width viewport_height offset
  in
  let vertical = side = "above" || side = "below" in
  let side_room = max 0.0
      (match side with
       | "above" -> W.DomRect.top anchor_bounds -. viewport_top -. offset -. padding
       | "below" -> viewport_top +. viewport_height -. W.DomRect.bottom anchor_bounds -. offset -. padding
       | "left" -> W.DomRect.left anchor_bounds -. viewport_left -. offset -. padding
       | _ -> viewport_left +. viewport_width -. W.DomRect.right anchor_bounds -. offset -. padding)
  in
  let side_available =
    min side_room
      (if vertical then available_height else available_width)
  in
  set_style popup
    (if vertical then "--lui-popup-available-height"
     else "--lui-popup-available-width")
    (css_px side_available);
  (* the side-axis clamp only forces a second layout pass when it actually
     binds: a value at or above the measured size cannot change it, so the
     re-measure is skipped *)
  let popup_width, popup_height =
    if
      (vertical && side_available < popup_height)
      || ((not vertical) && side_available < popup_width)
    then measure ()
    else (popup_width, popup_height)
  in
  (* Flip start/end only when the opposite edge stays closer to the anchor.
     The alignment offset is applied afterwards, so an explicit offset still
     shifts and then clamps instead of becoming a reason to flip. *)
  let alignment =
    resolved_alignment ~padding alignment vertical anchor_bounds popup_width
      popup_height viewport_left viewport_top viewport_width viewport_height
  in
  let aligned_left =
    cross_aligned alignment (W.DomRect.left anchor_bounds)
      (W.DomRect.width anchor_bounds) popup_width
  in
  let aligned_top =
    cross_aligned alignment (W.DomRect.top anchor_bounds)
      (W.DomRect.height anchor_bounds) popup_height
  in
  let alignment_offset = if alignment = "end" then -.alignment_offset else alignment_offset in
  let aligned_left = aligned_left +. alignment_offset in
  let aligned_top = aligned_top +. alignment_offset in
  let left =
    clamp_popup_axis ~padding
      (if vertical then aligned_left
       else if side = "left" then
         W.DomRect.left anchor_bounds -. popup_width -. offset
       else W.DomRect.right anchor_bounds +. offset)
      popup_width viewport_left viewport_width
  in
  let top =
    clamp_popup_axis ~padding
      (if vertical then
         if side = "above" then
           W.DomRect.top anchor_bounds -. popup_height -. offset
         else W.DomRect.bottom anchor_bounds +. offset
       else aligned_top)
      popup_height viewport_top viewport_height
  in
  W.Element.setAttribute "data-side" side positioner;
  if not (W.Element.isSameNode (W.Element.asNode popup) positioner) then
    W.Element.setAttribute "data-side" side popup;
  set_style positioner "left" (css_px left);
  set_style positioner "top" (css_px top);
  (* The temporary viewport cap can expand the scroller and truncate its
     offset. Restore against the final side cap; normal DOM clamping still
     applies when the finished viewport genuinely grows. *)
  W.Element.setScrollTop popup scroll_top;
  W.Element.setScrollLeft popup scroll_left

let position_anchored_bang = position_anchored

let position_at_point ?(padding = 8.0) document popup x y =
  let left, top, width, height = Lui_web_popup_tracking.viewport_bounds document in
  set_style popup "--lui-popup-available-width" (css_px (max 0.0 (width -. (2.0 *. padding))));
  set_style popup "--lui-popup-available-height" (css_px (max 0.0 (height -. (2.0 *. padding))));
  let element = W.Element.unsafeAsHtmlElement popup in
  let popup_width = float_of_int (W.HtmlElement.offsetWidth element) in
  let popup_height = float_of_int (W.HtmlElement.offsetHeight element) in
  set_style popup "left" (css_px (clamp_popup_axis ~padding x popup_width left width));
  set_style popup "top" (css_px (clamp_popup_axis ~padding y popup_height top height))

(* an anchored popup detached from its parent has no anchor to position
   against — a detached-but-open menu or tooltip is skipped rather than
   treated as an error *)
external make_rect : float -> float -> float -> float -> W.DomRect.t = "DOMRect" [@@mel.new]

let frozen_anchor renderer node =
  match Store.property renderer.web_store node AnchorRect with
  | Some (StringValue value) -> Option.map (fun (x, y, width, height) ->
      make_rect x y width height) (anchor_rect_of_string value)
  | _ -> None

let anchored renderer node =
  if frozen_anchor renderer node <> None then Store.node renderer.web_store node <> None
  else
  match Nodes.explicit_anchor renderer node with
  | Some target -> Option.fold ~none:false ~some:Nodes.anchor_available target
  | None ->
  match Store.node renderer.web_store node with
  | Some current ->
      (match current.retained_parent with
       | Some parent -> Store.node renderer.web_store parent <> None
       | None -> false)
  | None -> false

let track renderer node popup ~update ~on_invalid =
  if anchored renderer node then
    Lui_web_popup_tracking.start ~frozen:(frozen_anchor renderer node <> None) ~document:renderer.web_document
      ~positioner:(Nodes.dom_node renderer node) ~popup
      ~anchor:(match frozen_anchor renderer node with
        | Some _ -> Nodes.dom_node renderer node
        | None -> Nodes.dropdown_anchor_node renderer node)
      ~valid:(fun () -> anchored renderer node) ~update
      ~on_invalid:(fun () ->
        if Store.node renderer.web_store node <> None then on_invalid ()) ()

let position_tooltip renderer node =
  if anchored renderer node then begin
    let tooltip = Nodes.dom_node renderer node in
    let anchor = Nodes.dropdown_anchor_node renderer node in
    let anchor_bounds = W.Element.getBoundingClientRect anchor in
    let offset = Nodes.dropdown_offset renderer node in
    let side = Nodes.dropdown_side tooltip in
    let alignment =
      match W.Element.getAttribute "data-anchor-alignment" tooltip with
      | Some value -> value
      | None -> "start"
    in
    position_anchored ~padding:(collision_padding renderer node) ~fallback:true
      renderer.web_document tooltip tooltip anchor_bounds side alignment offset
  end

let position_tooltip_bang = position_tooltip

let begin_popup_open popup =
  W.Element.removeAttribute "data-closed" popup;
  W.Element.removeAttribute "data-ending-style" popup;
  W.Element.setAttribute "data-open" "" popup;
  W.Element.setAttribute "data-starting-style" "" popup;
  Webapi.requestAnimationFrame (fun _time ->
      W.Element.removeAttribute "data-starting-style" popup)

let begin_popup_open_bang = begin_popup_open

let begin_popup_close popup =
  W.Element.removeAttribute "data-open" popup;
  W.Element.setAttribute "data-closed" "" popup;
  W.Element.setAttribute "data-ending-style" "" popup

let begin_popup_close_bang = begin_popup_close

(* Select/combobox lookup helpers. The menu module owns the picker behavior,
   but position sits below it in the layering, so the queries it needs are
   replicated here against the retained store. *)
let picker_under_parent renderer parent =
  match Store.node renderer.web_store parent with
  | Some parent_node ->
      Lui_sequence.find_opt
        (fun child ->
           match Store.node renderer.web_store child with
           | Some child_node ->
               Store.standard_kind_is child_node Select
               || Store.standard_kind_is child_node Combobox
           | None -> false)
        parent_node.retained_children
  | None -> None

let picker_for_dropdown renderer dropdown =
  match Store.node renderer.web_store dropdown with
  | Some current ->
      (match current.retained_parent with
       | Some parent -> picker_under_parent renderer parent
       | None -> None)
  | None -> None

let picker_control_element renderer picker =
  let picker_element = Nodes.dom_node renderer picker in
  match Store.node renderer.web_store picker with
  | Some current ->
      if Store.standard_kind_is current Combobox then
        Util.child_element picker_element 0
      else picker_element
  | None -> invalid_arg "unknown picker node"

let picker_menu_items renderer dropdown =
  match Store.node renderer.web_store dropdown with
  | Some current ->
      Lui_sequence.fold_left
        (fun items child ->
           match Store.node renderer.web_store child with
           | Some child_node
             when Store.menu_item_row child_node
                  && Store.enabled_node renderer child ->
               child :: items
           | _ -> items)
        [] current.retained_children
      |> List.rev
  | None -> []

let picker_selected_index renderer dropdown =
  let rec search items index =
    match items with
    | [] -> 0
    | item :: rest ->
        if Store.selected_property renderer item then index
        else search rest (index + 1)
  in
  search (picker_menu_items renderer dropdown) 0

let align_selected_menu_item renderer dropdown positioner popup anchor
    anchor_bounds items =
  let viewport_left, viewport_top, viewport_width, viewport_height =
    Lui_web_popup_tracking.viewport_bounds renderer.web_document
  in
  let padding = collision_padding renderer dropdown in
  let edge_threshold = 20.0 in
  if
    W.DomRect.top anchor_bounds < viewport_top +. edge_threshold
    || W.DomRect.bottom anchor_bounds > viewport_top +. viewport_height -. edge_threshold
  then false
  else begin
    set_style popup "transition" "none";
    set_style popup "transform" "none";
    let selected =
      Nodes.dom_node renderer
        (List.nth items (picker_selected_index renderer dropdown))
    in
    let value = Util.child_element anchor 0 in
    let label = Util.child_element selected 1 in
    let positioner_bounds = W.Element.getBoundingClientRect positioner in
    let popup_bounds = W.Element.getBoundingClientRect popup in
    let value_bounds = W.Element.getBoundingClientRect value in
    let label_bounds = W.Element.getBoundingClientRect label in
    let value_center =
      W.DomRect.top value_bounds +. (W.DomRect.height value_bounds /. 2.0)
    in
    let label_center =
      W.DomRect.top label_bounds +. (W.DomRect.height label_bounds /. 2.0)
    in
    let left =
      W.DomRect.left positioner_bounds
      +. (W.DomRect.left value_bounds -. W.DomRect.left label_bounds)
    in
    let top =
      W.DomRect.top positioner_bounds +. (value_center -. label_center)
    in
    let fits =
      left >= viewport_left +. padding
      && left +. W.DomRect.width popup_bounds <= viewport_left +. viewport_width -. padding
      && top >= viewport_top +. padding
      && top +. W.DomRect.height popup_bounds <= viewport_top +. viewport_height -. padding
    in
    set_style popup "transform" "";
    set_style popup "transition" "";
    if fits then begin
      W.Element.setAttribute "data-side" "none" positioner;
      W.Element.setAttribute "data-side" "none" popup;
      set_style positioner "left" (css_px left);
      set_style positioner "top" (css_px top);
      true
    end
    else false
  end

let align_select_item_with_trigger renderer dropdown positioner popup anchor
    anchor_bounds =
  match picker_for_dropdown renderer dropdown with
  | None -> false
  | Some picker ->
      (match Store.node renderer.web_store picker with
       | None -> false
       | Some picker_node ->
           let control = picker_control_element renderer picker in
           let open_method =
             match W.Element.getAttribute "data-lui-open-method" control with
             | Some value -> value
             | None -> "keyboard"
           in
           let items = picker_menu_items renderer dropdown in
           if
             Store.standard_kind_is picker_node Select
             && open_method <> "touch"
             && items <> []
           then
             align_selected_menu_item renderer dropdown positioner popup
               anchor anchor_bounds items
           else false)

let align_select_item_with_trigger_bang = align_select_item_with_trigger

let position_dropdown renderer node =
  if anchored renderer node then begin
    let positioner = Nodes.dom_node renderer node in
    match Store.property renderer.web_store node PopupX with
    | Some (FloatValue x) ->
        (match Store.property renderer.web_store node PopupY with
         | Some (FloatValue y) ->
             (* programmatic point anchor (popover ~at parity): the menu
                mounts at a computed point, not a DOM element *)
             Util.set_state_attribute positioner "hidden" false;
             position_at_point ~padding:(collision_padding renderer node) renderer.web_document positioner x y
         | _ -> ())
    | _ ->
    let popup = Util.child_element positioner 0 in
    let anchor = Nodes.dropdown_anchor_node renderer node in
    let anchor_bounds = W.Element.getBoundingClientRect anchor in
    let visible =
      W.DomRect.width anchor_bounds > 0.0
      || W.DomRect.height anchor_bounds > 0.0
    in
    Util.set_state_attribute positioner "hidden" (not visible);
    if visible then begin
      let offset = Nodes.dropdown_offset renderer node in
      let side = Nodes.dropdown_side positioner in
      let alignment =
        match W.Element.getAttribute "data-anchor-alignment" positioner with
        | Some value -> value
        | None -> "start"
      in
      let fallback =
        match W.Element.getAttribute "data-submenu" positioner with
        | Some _ -> true
        | None -> false
      in
      position_anchored ~padding:(collision_padding renderer node) ~fallback
        renderer.web_document positioner popup anchor_bounds side alignment offset;
      ignore
        (align_select_item_with_trigger renderer node positioner popup
           anchor anchor_bounds)
    end
  end

let position_dropdown_bang = position_dropdown

(* a popover positions in one of three modes: PopupX/PopupY set → point
   positioning (pointer-anchored menus), AnchorValue set → anchored to the
   element under its retained parent, neither → cover mode (the
   positioner spans the viewport and needs no coordinates) *)
let position_popover renderer node =
  let positioner = Nodes.dom_node renderer node in
  match Store.property renderer.web_store node PopupX with
  | Some (FloatValue x) ->
      (match Store.property renderer.web_store node PopupY with
       | Some (FloatValue y) ->
           Util.set_state_attribute positioner "hidden" false;
           position_at_point ~padding:(collision_padding renderer node) renderer.web_document positioner x y
       | _ -> ())
  | _ ->
      (match Store.property renderer.web_store node AnchorValue with
       | Some (StringValue _) ->
           if not (anchored renderer node) then
             Util.set_state_attribute positioner "hidden" true
           else begin
             let popup = Util.child_element positioner 0 in
             let anchor_bounds = match frozen_anchor renderer node with
               | Some bounds -> bounds
               | None -> W.Element.getBoundingClientRect (Nodes.dropdown_anchor_node renderer node) in
             let visible =
               W.DomRect.width anchor_bounds > 0.0
               || W.DomRect.height anchor_bounds > 0.0
             in
             Util.set_state_attribute positioner "hidden" (not visible);
             if visible then begin
               let offset = Nodes.dropdown_offset renderer node in
               let side = Nodes.dropdown_side positioner in
               let alignment =
                 match
                   W.Element.getAttribute "data-anchor-alignment" positioner
                 with
                 | Some value -> value
                 | None -> "start"
               in
               let alignment_offset =
                 match Store.property renderer.web_store node AnchorAlignmentOffset with
                 | Some (FloatValue value) -> value
                 | _ -> 0.0
               in
               position_anchored ~padding:(collision_padding renderer node) ~alignment_offset
                 ~fallback:true renderer.web_document positioner popup
                 anchor_bounds side alignment offset
             end
           end
       | _ -> ())

let position_popover_bang = position_popover

let point_in_triangle point_x point_y ax ay bx by cx cy =
  let cross_a =
    ((point_x -. bx) *. (ay -. by)) -. ((ax -. bx) *. (point_y -. by))
  in
  let cross_b =
    ((point_x -. cx) *. (by -. cy)) -. ((bx -. cx) *. (point_y -. cy))
  in
  let cross_c =
    ((point_x -. ax) *. (cy -. ay)) -. ((cx -. ax) *. (point_y -. ay))
  in
  let has_negative = cross_a < 0.0 || cross_b < 0.0 || cross_c < 0.0 in
  let has_positive = cross_a > 0.0 || cross_b > 0.0 || cross_c > 0.0 in
  not (has_negative && has_positive)

let point_in_triangle_ = point_in_triangle

let submenu_corridor positioner popup leave_x leave_y point_x point_y =
  let bounds = W.Element.getBoundingClientRect popup in
  let buffer = 4.0 in
  let side =
    match W.Element.getAttribute "data-side" positioner with
    | Some value -> value
    | None -> Nodes.dropdown_side positioner
  in
  match side with
  | "left" ->
      point_in_triangle point_x point_y (leave_x +. buffer) leave_y
        (W.DomRect.right bounds)
        (W.DomRect.top bounds -. buffer)
        (W.DomRect.right bounds)
        (W.DomRect.bottom bounds +. buffer)
  | "above" ->
      point_in_triangle point_x point_y leave_x (leave_y +. buffer)
        (W.DomRect.left bounds -. buffer)
        (W.DomRect.bottom bounds)
        (W.DomRect.right bounds +. buffer)
        (W.DomRect.bottom bounds)
  | "below" ->
      point_in_triangle point_x point_y leave_x (leave_y -. buffer)
        (W.DomRect.left bounds -. buffer)
        (W.DomRect.top bounds)
        (W.DomRect.right bounds +. buffer)
        (W.DomRect.top bounds)
  | _ ->
      point_in_triangle point_x point_y (leave_x -. buffer) leave_y
        (W.DomRect.left bounds)
        (W.DomRect.top bounds -. buffer)
        (W.DomRect.left bounds)
        (W.DomRect.bottom bounds +. buffer)

let submenu_corridor_ = submenu_corridor
