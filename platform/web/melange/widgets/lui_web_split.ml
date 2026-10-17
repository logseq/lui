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

let split_uses_pixels renderer node =
  Store.property renderer.web_store node FirstPaneWidth <> None

let split_base_fraction value =
  Float.max 0. (Float.min value 1.0)

let split_int_property renderer node property fallback =
  match Store.property renderer.web_store node property with
  | Some (IntValue value) -> value
  | _ -> fallback

let split_child_width renderer node index property =
  match Store.node renderer.web_store node with
  | Some current ->
      if index < Lui_sequence.length current.retained_children then
        match Store.property renderer.web_store
          (Lui_sequence.get current.retained_children index) property with
        | Some (IntValue value) -> Some (float_of_int value)
        | _ -> None
      else None
  | None -> None

(* Gap, minima, and the layout read are captured once per update — the old
   code rebuilt the children list and re-queried the gap three times per
   render, and every clientWidth read after a style write forced layout. *)
type split_geometry = {
  geo_gap : int;
  geo_first_min : float;
  geo_second_min : float;
  geo_first_max : float option;
  geo_second_max : float option;
  geo_available : int;
}

let split_geometry renderer node root =
  let gap = split_int_property renderer node Gap 9 in
  { geo_gap = gap;
    geo_first_min = Option.value (split_child_width renderer node 0 MinWidth) ~default:0.;
    geo_second_min = Option.value (split_child_width renderer node 1 MinWidth) ~default:0.;
    geo_first_max = split_child_width renderer node 0 MaxWidth;
    geo_second_max = split_child_width renderer node 1 MaxWidth;
    geo_available = W.Element.clientWidth root - gap }

let effective_fraction geometry value =
  Lui_split_geometry.constrain_fraction ~available:(float_of_int geometry.geo_available)
    ~first_min:geometry.geo_first_min ~second_min:geometry.geo_second_min
    ?first_max:geometry.geo_first_max ?second_max:geometry.geo_second_max
    (Float.max 0. (Float.min 1. value))

let normalize_value renderer node value =
  if split_uses_pixels renderer node then Float.max 0. value else split_base_fraction value

let effective_split_fraction renderer node value =
  let root = Lui_web_nodes.dom_node renderer node in
  effective_fraction (split_geometry renderer node root) value

let split_timing_function renderer node =
  match Store.property renderer.web_store node ResizeEasing with
  | Some (StringValue "linear") -> "linear"
  | Some (StringValue "emphasized") -> "cubic-bezier(0.2, 0, 0, 1)"
  | Some (StringValue "spring") -> "cubic-bezier(0.16, 1.2, 0.3, 1)"
  | _ -> "ease-in-out"

let render_split renderer node root value animated =
  let geometry = split_geometry renderer node root in
  let fraction = split_base_fraction value in
  let gap_float = Float.of_int geometry.geo_gap in
  let panes = Util.child_element root 0 in
  let divider = Util.child_element root 1 in
  let duration =
    if animated then split_int_property renderer node ResizeDuration 0 else 0
  in
  (* A zero duration only affects new transitions. Direct input and resize
     observations must also cancel a transition already changing geometry. *)
  set_style panes "transition-property"
    (if animated then "grid-template-columns" else "none");
  set_style divider "transition-property" (if animated then "left" else "none");
  set_style panes "transition-duration" (string_of_int duration ^ "ms");
  set_style divider "transition-duration" (string_of_int duration ^ "ms");
  set_style panes "transition-timing-function"
    (split_timing_function renderer node);
  set_style divider "transition-timing-function"
    (split_timing_function renderer node);
  (* Controlled tracks can pass through zero during closure. Pane bounds
     constrain input, while the split owns clipping in both backends. *)
  for index = 0 to 1 do
    Option.iter (fun pane ->
      set_style pane "min-width" "0px";
      set_style pane "overflow" "hidden")
      (W.HtmlCollection.item index (W.Element.children panes))
  done;
  let first_track, columns =
    if split_uses_pixels renderer node then
      let width = "min(" ^ float_string (Float.max 0. value) ^ "px, max(0px, calc(100% - "
        ^ string_of_int geometry.geo_gap ^ "px)))" in
      width, width ^ " minmax(0, 1fr)"
    else
      "calc(" ^ float_string (fraction *. 100.0) ^ "% - "
        ^ float_string (fraction *. gap_float) ^ "px)",
      "minmax(0, " ^ float_string fraction ^ "fr) minmax(0, "
        ^ float_string (1.0 -. fraction) ^ "fr)"
  in
  set_style panes "grid-template-columns" columns;
  set_style panes "column-gap" (string_of_int geometry.geo_gap ^ "px");
  set_style divider "left" first_track;
  set_style divider "width" (string_of_int geometry.geo_gap ^ "px");
  W.Element.setAttribute "aria-valuenow" (float_string value) divider

let render_split_bang = render_split

let split_progress_source renderer node =
  let property = if split_uses_pixels renderer node then FirstPaneWidth else ProgressValue in
  match Store.property renderer.web_store node property with
  | Some (FloatValue value) -> value
  | _ -> 0.5

let replace_split_state renderer node source current =
  Hashtbl.replace renderer.web_splits node
    { web_split_pixels = split_uses_pixels renderer node;
      web_split_source = source; web_split_current = current }

let reconcile_split renderer node root source =
  match Hashtbl.find_opt renderer.web_splits node with
  | Some state ->
      let source_changed = source <> state.web_split_source
        || state.web_split_pixels <> split_uses_pixels renderer node in
      let current = state.web_split_current in
      let next_current =
        if source_changed then
          if Float.abs (normalize_value renderer node source -. current) < 0.000001 then
            current
          else normalize_value renderer node source
        else current
      in
      replace_split_state renderer node source next_current;
      (* A second update in the same batch must preserve the controlled
         transition. Direct input and viewport resize cancel it explicitly. *)
      render_split renderer node root next_current true
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
            if duration > 0 then normalize_value renderer node value
            else normalize_value renderer node source
        | None -> normalize_value renderer node source
      in
      replace_split_state renderer node source start;
      render_split renderer node root start false;
      if duration > 0 && start <> normalize_value renderer node source then
        Webapi.requestAnimationFrame (fun _time ->
            replace_split_state renderer node source
              (normalize_value renderer node source);
            render_split renderer node root (normalize_value renderer node source) true)

let reconcile_split_bang = reconcile_split

let update_split renderer node =
  match Store.node renderer.web_store node with
  | Some current ->
      if Store.standard_kind_is current Split then
        reconcile_split renderer node (Lazy.force current.platform_node)
          (split_progress_source renderer node)
  | None -> ()

let update_split_bang = update_split

let rec update_splits_under renderer node =
  update_split renderer node;
  match Store.node renderer.web_store node with
  | Some current ->
      Lui_sequence.iter
        (fun child -> update_splits_under renderer child)
        current.retained_children
  | None -> ()

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
    let geometry = split_geometry renderer node root in
    let available = float_of_int geometry.geo_available in
    let pixels = split_uses_pixels renderer node in
    let fraction = if pixels then current /. Float.max 1. available else current in
    let next = effective_fraction geometry (fraction +. delta) in
    let next = if pixels then next *. available else next in
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
      let current = if split_uses_pixels renderer node then current *. available else current in
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
        | Some state when not (split_uses_pixels renderer node) ->
            render_split renderer node root state.web_split_current false
        | Some _ | None -> ())
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
