(* Split panes: fraction math, divider layout, and drag/keyboard
   interaction. Ported from web.cljc (split-base-fraction …
   attach-split-events!). *)

open Lui_protocol
open Lui_web_types

module W = Webapi.Dom
module Store = Lui_web_store
module Util = Lui_web_util

let float_string value = Js.Float.toString value

let set_style element property value =
  Util.set_style
    (W.HtmlElement.style (W.Element.unsafeAsHtmlElement element))
    property value

let split_base_fraction value =
  if Float.is_finite value && value > 0.0 then Float.min value 1.0 else 0.5

let split_int_property renderer node property fallback =
  match Store.property renderer.web_store node property with
  | Some (IntValue value) -> value
  | _ -> fallback

let split_child_minimum renderer node index =
  let children = Store.children renderer.web_store node in
  if index < List.length children then
    split_int_property renderer (List.nth children index) MinWidth 0
  else 0

let effective_split_fraction renderer node value =
  let root = Lui_web_nodes.dom_node renderer node in
  let gap = split_int_property renderer node Gap 9 in
  let available = W.Element.clientWidth root - gap in
  let first_minimum = split_child_minimum renderer node 0 in
  let second_minimum = split_child_minimum renderer node 1 in
  if available <= 0 then 0.5
  else
    let available_float = Float.of_int available in
    let low = Float.of_int first_minimum /. available_float in
    let high = 1.0 -. (Float.of_int second_minimum /. available_float) in
    if low > high then
      low /. Float.max (low +. (1.0 -. high)) 0.0001
    else Float.min (Float.max (split_base_fraction value) low) high

let split_timing_function renderer node =
  match Store.property renderer.web_store node ResizeEasing with
  | Some (StringValue "linear") -> "linear"
  | Some (StringValue "emphasized") -> "cubic-bezier(0.2, 0, 0, 1)"
  | Some (StringValue "spring") -> "cubic-bezier(0.16, 1.2, 0.3, 1)"
  | _ -> "ease-in-out"

let render_split renderer node root value animated =
  let fraction = effective_split_fraction renderer node value in
  let gap = split_int_property renderer node Gap 9 in
  let gap_float = Float.of_int gap in
  let first_minimum = split_child_minimum renderer node 0 in
  let second_minimum = split_child_minimum renderer node 1 in
  let panes = Util.child_element root 0 in
  let divider = Util.child_element root 1 in
  let duration =
    if animated then split_int_property renderer node ResizeDuration 0 else 0
  in
  set_style panes "grid-template-columns"
    ("minmax(" ^ string_of_int first_minimum ^ "px, "
     ^ float_string fraction ^ "fr) minmax("
     ^ string_of_int second_minimum ^ "px, "
     ^ float_string (1.0 -. fraction) ^ "fr)");
  set_style panes "column-gap" (string_of_int gap ^ "px");
  set_style divider "left"
    ("calc(" ^ float_string (fraction *. 100.0) ^ "% - "
     ^ float_string (fraction *. gap_float) ^ "px)");
  set_style divider "width" (string_of_int gap ^ "px");
  set_style panes "transition-property" "grid-template-columns";
  set_style divider "transition-property" "left";
  set_style panes "transition-duration" (string_of_int duration ^ "ms");
  set_style divider "transition-duration" (string_of_int duration ^ "ms");
  set_style panes "transition-timing-function"
    (split_timing_function renderer node);
  set_style divider "transition-timing-function"
    (split_timing_function renderer node);
  W.Element.setAttribute "aria-valuenow" (float_string fraction) divider

let render_split_bang = render_split

let split_progress_source renderer node =
  match Store.property renderer.web_store node ProgressValue with
  | Some (FloatValue value) -> value
  | _ -> 0.0

let replace_split_state renderer node source current =
  Hashtbl.replace renderer.web_splits node
    { web_split_source = source; web_split_current = current }

let reconcile_split renderer node root source =
  match Hashtbl.find_opt renderer.web_splits node with
  | Some state ->
      let source_changed = source <> state.web_split_source in
      let current = state.web_split_current in
      let next_current =
        if source_changed then
          if Float.abs (split_base_fraction source -. current) < 0.000001 then
            current
          else split_base_fraction source
        else current
      in
      replace_split_state renderer node source next_current;
      render_split renderer node root next_current source_changed
  | None ->
      let duration = split_int_property renderer node ResizeDuration 0 in
      let origin =
        match Store.property renderer.web_store node ResizeOrigin with
        | Some (FloatValue value) -> Some value
        | _ -> None
      in
      let start =
        match origin with
        | Some value ->
            if duration > 0 then split_base_fraction value
            else split_base_fraction source
        | None -> split_base_fraction source
      in
      replace_split_state renderer node source start;
      render_split renderer node root start false;
      if duration > 0 && start <> split_base_fraction source then
        Webapi.requestAnimationFrame (fun _time ->
            replace_split_state renderer node source
              (split_base_fraction source);
            render_split renderer node root (split_base_fraction source) true)

let reconcile_split_bang = reconcile_split

let update_split renderer node =
  match Store.node renderer.web_store node with
  | Some current ->
      if Store.standard_kind_is current Split then
        reconcile_split renderer node current.platform_node
          (split_progress_source renderer node)
  | None -> ()

let update_split_bang = update_split

let rec update_splits_under renderer node =
  update_split renderer node;
  List.iter
    (fun child -> update_splits_under renderer child)
    (Store.children renderer.web_store node)

let update_splits_under_bang = update_splits_under

let attach_split_events renderer node root =
  let divider = Util.child_element root 1 in
  let document = renderer.web_document in
  let dragging = ref false in
  let adjust delta =
    let current =
      match Hashtbl.find_opt renderer.web_splits node with
      | Some state -> state.web_split_current
      | None -> 0.5
    in
    let next = effective_split_fraction renderer node (current +. delta) in
    let source = split_progress_source renderer node in
    replace_split_state renderer node source next;
    render_split renderer node root next false;
    ignore (!(renderer.web_event_handler) (ValueChanged (node, next)))
  in
  let move event =
    if !dragging then begin
      let bounds = W.Element.getBoundingClientRect root in
      let gap = split_int_property renderer node Gap 9 in
      let available = W.DomRect.width bounds -. Float.of_int gap in
      let pointer =
        Float.of_int (W.MouseEvent.clientX event) -. W.DomRect.left bounds
      in
      let raw =
        (pointer -. (Float.of_int gap /. 2.0)) /. Float.max available 1.0
      in
      let current = effective_split_fraction renderer node raw in
      let source = split_progress_source renderer node in
      replace_split_state renderer node source current;
      render_split renderer node root current false;
      ignore (!(renderer.web_event_handler) (ValueChanged (node, current)))
    end
  in
  let stop _event = dragging := false in
  let resize_observer =
    Webapi.ResizeObserver.make (fun _entries ->
        match Hashtbl.find_opt renderer.web_splits node with
        | Some state ->
            render_split renderer node root state.web_split_current false
        | None -> ())
  in
  W.Element.addMouseDownEventListener
    (fun event ->
       if W.MouseEvent.button event = 0 then begin
         W.MouseEvent.preventDefault event;
         dragging := true
       end)
    divider;
  W.Document.addMouseMoveEventListener move document;
  W.Document.addMouseUpEventListener stop document;
  Webapi.ResizeObserver.observe resize_observer root;
  W.Element.addKeyDownEventListener
    (fun event ->
       (match W.KeyboardEvent.key event with
        | "ArrowLeft" ->
            W.KeyboardEvent.preventDefault event;
            adjust (-0.05)
        | "ArrowRight" ->
            W.KeyboardEvent.preventDefault event;
            adjust 0.05
        | "Home" ->
            W.KeyboardEvent.preventDefault event;
            adjust (-1.0)
        | "End" ->
            W.KeyboardEvent.preventDefault event;
            adjust 1.0
        | _ -> ()))
    divider;
  Hashtbl.replace renderer.web_cleanups node (fun () ->
      W.Document.removeMouseMoveEventListener move document;
      W.Document.removeMouseUpEventListener stop document;
      Webapi.ResizeObserver.disconnect resize_observer;
      Hashtbl.remove renderer.web_splits node)

let attach_split_events_bang = attach_split_events
