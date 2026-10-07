(* Popup geometry, open/close transitions, select-item alignment, and the
   submenu pointer corridor.
   Source: /tmp/lui-web-ref/web.cljc lines 3137-3345 and 5439-5597. *)

open Lui_protocol
open Lui_web_types

module W = Webapi.Dom
module Store = Lui_web_store
module Util = Lui_web_util
module Nodes = Lui_web_nodes

(* melange-webapi exposes Window.matchMedia but no accessor for the result's
   [matches] flag; this is a property getter, not a coercion. *)
external media_query_list_matches : W.Window.mediaQueryList -> bool
  = "matches" [@@mel.get]

let css_px value = Js.Float.toString value ^ "px"

let set_style element name value =
  Util.set_style
    (W.HtmlElement.style (W.Element.unsafeAsHtmlElement element))
    name value

(* collision margin: 5px matches the cljs popup inset measured on
   real menus (Radix popup-show! output sits ~5px off the viewport edge) *)
let clamp_popup_axis value size viewport_start viewport_size =
  let edge = viewport_start +. 5.0 in
  let maximum = max edge (viewport_start +. viewport_size -. size -. 5.0) in
  max edge (min value maximum)

let resolved_popup_side preferred anchor_bounds popup_width popup_height
    viewport_left viewport_top viewport_width viewport_height offset =
  let above_space = W.DomRect.top anchor_bounds -. viewport_top -. offset -. 8.0 in
  let below_space =
    viewport_top +. viewport_height -. W.DomRect.bottom anchor_bounds -. offset -. 8.0
  in
  let left_space = W.DomRect.left anchor_bounds -. viewport_left -. offset -. 8.0 in
  let right_space =
    viewport_left +. viewport_width -. W.DomRect.right anchor_bounds -. offset -. 8.0
  in
  match preferred with
  | "above" ->
      if popup_height <= above_space || above_space >= below_space then
        "above"
      else "below"
  | "left" ->
      if popup_width <= left_space || left_space >= right_space then "left"
      else "right"
  | "right" ->
      if popup_width <= right_space || right_space >= left_space then "right"
      else "left"
  | _ ->
      if popup_height <= below_space || below_space >= above_space then
        "below"
      else "above"

let position_anchored document positioner popup anchor_bounds preferred
    alignment offset =
  let viewport_left, viewport_top, viewport_width, viewport_height =
    Lui_web_popup_tracking.viewport_bounds document
  in
  let available_width = max 0.0 (viewport_width -. 16.0) in
  let available_height = max 0.0 (viewport_height -. 16.0) in
  set_style popup "--lui-popup-available-width" (css_px available_width);
  set_style popup "--lui-popup-available-height" (css_px available_height);
  let popup_bounds = W.Element.getBoundingClientRect popup in
  let popup_element = W.Element.unsafeAsHtmlElement popup in
  let popup_width =
    1.0
    +. max
         (float_of_int (W.HtmlElement.offsetWidth popup_element))
         (W.DomRect.width popup_bounds)
  in
  let popup_height =
    1.0
    +. max
         (float_of_int (W.HtmlElement.offsetHeight popup_element))
         (W.DomRect.height popup_bounds)
  in
  let side =
    resolved_popup_side preferred anchor_bounds popup_width popup_height
      viewport_left viewport_top viewport_width viewport_height offset
  in
  let vertical = side = "above" || side = "below" in
  let side_space = max 0.0
      (match side with
       | "above" -> W.DomRect.top anchor_bounds -. viewport_top -. offset -. 8.0
       | "below" -> viewport_top +. viewport_height -. W.DomRect.bottom anchor_bounds -. offset -. 8.0
       | "left" -> W.DomRect.left anchor_bounds -. viewport_left -. offset -. 8.0
       | _ -> viewport_left +. viewport_width -. W.DomRect.right anchor_bounds -. offset -. 8.0)
  in
  set_style popup
    (if vertical then "--lui-popup-available-height" else "--lui-popup-available-width")
    (css_px (min side_space (if vertical then available_height else available_width)));
  let popup_width = float_of_int (W.HtmlElement.offsetWidth popup_element) in
  let popup_height = float_of_int (W.HtmlElement.offsetHeight popup_element) in
  let aligned_left =
    match alignment with
    | "center" ->
        W.DomRect.left anchor_bounds +. (W.DomRect.width anchor_bounds /. 2.0)
        -. (popup_width /. 2.0)
    | "end" -> W.DomRect.right anchor_bounds -. popup_width
    | _ -> W.DomRect.left anchor_bounds
  in
  let aligned_top =
    match alignment with
    | "center" ->
        W.DomRect.top anchor_bounds +. (W.DomRect.height anchor_bounds /. 2.0)
        -. (popup_height /. 2.0)
    | "end" -> W.DomRect.bottom anchor_bounds -. popup_height
    | _ -> W.DomRect.top anchor_bounds
  in
  let left =
    clamp_popup_axis
      (if vertical then aligned_left
       else if side = "left" then
         W.DomRect.left anchor_bounds -. popup_width -. offset
       else W.DomRect.right anchor_bounds +. offset)
      popup_width viewport_left viewport_width
  in
  let top =
    clamp_popup_axis
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
  set_style positioner "top" (css_px top)

let position_anchored_bang = position_anchored

let position_at_point document popup x y =
  let left, top, width, height = Lui_web_popup_tracking.viewport_bounds document in
  set_style popup "--lui-popup-available-width" (css_px (max 0.0 (width -. 16.0)));
  set_style popup "--lui-popup-available-height" (css_px (max 0.0 (height -. 16.0)));
  let element = W.Element.unsafeAsHtmlElement popup in
  let popup_width = float_of_int (W.HtmlElement.offsetWidth element) in
  let popup_height = float_of_int (W.HtmlElement.offsetHeight element) in
  set_style popup "left" (css_px (clamp_popup_axis x popup_width left width));
  set_style popup "top" (css_px (clamp_popup_axis y popup_height top height))

(* an anchored popup detached from its parent has no anchor to position
   against — a detached-but-open menu or tooltip is skipped rather than
   treated as an error *)
let anchored renderer node =
  match Store.node renderer.web_store node with
  | Some current ->
      (match current.retained_parent with
       | Some parent -> Store.node renderer.web_store parent <> None
       | None -> false)
  | None -> false

let track renderer node popup ~update ~on_invalid =
  if anchored renderer node then
    Lui_web_popup_tracking.start ~document:renderer.web_document
      ~positioner:(Nodes.dom_node renderer node) ~popup
      ~anchor:(Nodes.dropdown_anchor_node renderer node)
      ~valid:(fun () -> anchored renderer node) ~update
      ~on_invalid:(fun () ->
        if Store.node renderer.web_store node <> None then on_invalid ())

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
    position_anchored renderer.web_document tooltip tooltip anchor_bounds
      side alignment offset
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

let prefers_reduced_motion document =
  let html_document = W.Document.unsafeAsHtmlDocument document in
  match W.HtmlDocument.defaultView html_document with
  | Some window ->
      media_query_list_matches
        (W.Window.matchMedia "(prefers-reduced-motion: reduce)" window)
  | None -> false

let prefers_reduced_motion_ = prefers_reduced_motion

let transition_event_from target event =
  W.Element.isSameNode
    (W.Element.asNode
       (W.EventTarget.unsafeAsElement (W.Event.target event)))
    target

let transition_event_from_ = transition_event_from

let after_transition document target fallback_duration finish_on_cancel
    complete =
  if prefers_reduced_motion document then complete ()
  else begin
    let finished = ref false in
    let timer = ref None in
    let rec finish () =
      if not !finished then begin
        finished := true;
        (match !timer with
         | Some timer_id -> Js.Global.clearTimeout timer_id
         | None -> ());
        W.Element.removeEventListener "transitionend" transition_handler
          target;
        if finish_on_cancel then
          W.Element.removeEventListener "transitioncancel" transition_handler
            target;
        complete ()
      end
    and transition_handler (event : Dom.event) =
      if transition_event_from target event then finish ()
    in
    W.Element.addEventListener "transitionend" transition_handler target;
    if finish_on_cancel then
      W.Element.addEventListener "transitioncancel" transition_handler target;
    timer :=
      Some (Js.Global.setTimeout ~f:(fun () -> finish ()) fallback_duration)
  end

let after_transition_bang = after_transition

let finish_popup_close_after_transition document popup duration =
  after_transition document popup duration true (fun () ->
      if W.Element.getAttribute "data-ending-style" popup = Some "" then
        W.Element.removeAttribute "data-ending-style" popup)

let finish_popup_close_after_transition_bang =
  finish_popup_close_after_transition

(* Select/combobox lookup helpers. The menu module owns the picker behavior,
   but position sits below it in the layering, so the queries it needs are
   replicated here against the retained store. *)
let picker_under_parent renderer parent =
  List.find_opt
    (fun child ->
       match Store.node renderer.web_store child with
       | Some child_node ->
           Store.standard_kind_is child_node Select
           || Store.standard_kind_is child_node Combobox
       | None -> false)
    (Store.children renderer.web_store parent)

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
      List.filter
        (fun child ->
           match Store.node renderer.web_store child with
           | Some child_node ->
               Store.menu_item_row child_node
               && Store.enabled_node renderer child
           | None -> false)
        current.retained_children
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
      left >= viewport_left +. 8.0
      && left +. W.DomRect.width popup_bounds <= viewport_left +. viewport_width -. 8.0
      && top >= viewport_top +. 8.0
      && top +. W.DomRect.height popup_bounds <= viewport_top +. viewport_height -. 8.0
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
      position_anchored renderer.web_document positioner popup anchor_bounds
        side alignment offset;
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
           position_at_point renderer.web_document positioner x y
       | _ -> ())
  | _ ->
      (match Store.property renderer.web_store node AnchorValue with
       | Some (StringValue _) ->
           if anchored renderer node then begin
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
                 match
                   W.Element.getAttribute "data-anchor-alignment" positioner
                 with
                 | Some value -> value
                 | None -> "start"
               in
               position_anchored renderer.web_document positioner popup
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
