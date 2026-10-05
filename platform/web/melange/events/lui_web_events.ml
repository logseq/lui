(* DOM event wiring for the web backend: per-control listeners plus the
   attach_events! dispatcher. Source: web.cljc — see PORTING.md. *)

open Lui_protocol
open Lui_web_types

module W = Webapi.Dom
module Store = Lui_web_store
module Util = Lui_web_util

(* web.cljc enabled-node? — a node is interactive unless Enabled is
   explicitly BoolValue false; an absent property means enabled. *)
let enabled_node renderer node =
  match Store.property renderer.web_store node Enabled with
  | Some (BoolValue false) -> false
  | _ -> true

let emit renderer event = ignore (!(renderer.web_event_handler) event)

let record_modal_return_focus renderer element =
  renderer.web_modal_return_focus := Some element

let combobox_keydown renderer node event =
  let key = W.KeyboardEvent.key event in
  let dropdown = Lui_web_menu.picker_dropdown renderer node in
  if key = "ArrowDown" || key = "ArrowUp" then begin
    W.KeyboardEvent.preventDefault event;
    match dropdown with
    | Some menu ->
        let items = Lui_web_menu.picker_menu_items renderer menu in
        let current = Lui_web_menu.combobox_active_index renderer node items in
        let navigation_key =
          if key = "ArrowDown" then "ArrowRight" else "ArrowLeft"
        in
        (match
           Lui_web_focus.horizontal_focus_index
             navigation_key current (List.length items)
         with
         | Some index ->
             ignore (Lui_web_menu.set_combobox_active renderer node menu index)
         | None -> ())
    | None -> emit renderer (Press node)
  end
  else if key = "Enter" then begin
    W.KeyboardEvent.preventDefault event;
    match dropdown with
    | Some menu ->
        let items = Lui_web_menu.picker_menu_items renderer menu in
        (match Lui_web_menu.combobox_active_index renderer node items with
         | Some index ->
             ignore
               (Lui_web_menu.activate_menu_item renderer (List.nth items index))
         | None ->
             if items <> [] then
               ignore
                 (Lui_web_menu.set_combobox_active renderer node menu 0))
    | None ->
        emit renderer
          (if Store.submit_enabled renderer node then Submit node
           else Press node)
  end

let text_keydown renderer node kind composing event =
  if enabled_node renderer node then begin
    let composing_now = !composing || W.KeyboardEvent.isComposing event in
    let enter = W.KeyboardEvent.key event = "Enter" in
    let shift = W.KeyboardEvent.shiftKey event in
    let primary =
      W.KeyboardEvent.metaKey event || W.KeyboardEvent.ctrlKey event
    in
    let submit =
      (not composing_now)
      &&
      (if enter then
         (if kind = Textarea then
            (if Store.submit_on_enter renderer node then not shift
             else primary)
          else true)
       else false)
    in
    if submit && kind <> Combobox then begin
      W.KeyboardEvent.preventDefault event;
      emit renderer (Submit node)
    end;
    if kind = Combobox && not composing_now && not primary
       && not (W.KeyboardEvent.altKey event) then
      combobox_keydown renderer node event
  end

let attach_text_events renderer node kind dom_node =
  let composing = ref false in
  let committed_composition = ref None in
  let current_value () =
    W.HtmlInputElement.value (Util.text_control_node dom_node)
  in
  let emit_value value =
    if enabled_node renderer node then begin
      if
        kind = Combobox
        && Store.true_property renderer node PressEnabled
        && Lui_web_menu.picker_dropdown renderer node = None
      then emit renderer (Press node);
      emit renderer (TextChanged (node, value))
    end
  in
  W.Element.addEventListener "beforeinput"
    (fun event ->
       if not (enabled_node renderer node) then W.Event.preventDefault event)
    dom_node;
  W.Element.addEventListener "compositionstart"
    (fun _event ->
       composing := true;
       W.Element.setAttribute "data-lui-composing" "" dom_node;
       committed_composition := None)
    dom_node;
  W.Element.addEventListener "compositionend"
    (fun _event ->
       let value = current_value () in
       composing := false;
       W.Element.removeAttribute "data-lui-composing" dom_node;
       committed_composition := Some value;
       emit_value value)
    dom_node;
  W.Element.addEventListener "input"
    (fun _event ->
       if not !composing then begin
         let value = current_value () in
         match !committed_composition with
         | Some committed ->
             committed_composition := None;
             if value <> committed then emit_value value
         | None -> emit_value value
       end)
    dom_node;
  W.Element.addKeyDownEventListener
    (fun event -> text_keydown renderer node kind composing event)
    dom_node

let attach_toggle_event renderer node _kind dom_node =
  let control = Util.child_element dom_node 0 in
  W.Element.addEventListener "click"
    (fun event ->
       if not (enabled_node renderer node) then W.Event.preventDefault event)
    control;
  W.Element.addEventListener "change"
    (fun _event ->
       if enabled_node renderer node then
         let checked =
           W.HtmlInputElement.checked (Util.text_control_node dom_node)
         in
         emit renderer (ToggleChanged (node, checked)))
    control

(* Emits PressDetail for a real click only when the runtime would admit it
   (pointer-enabled property plus kind support). Button/picker/radio click
   paths call this directly so suppressed clicks stay suppressed; other
   kinds get it from the plain click listener in attach_pointer_events. *)
let emit_press_detail renderer node event =
  let candidate = PressDetail (node, Util.pointer_detail_of event) in
  if
    enabled_node renderer node
    && Store.event_admitted renderer node candidate
  then emit renderer candidate

let attach_radio_event renderer node dom_node =
  let control = Util.child_element dom_node 0 in
  W.Element.addEventListener "click"
    (fun event ->
       if not (enabled_node renderer node) then W.Event.preventDefault event
       else emit_press_detail renderer node event)
    control;
  W.Element.addEventListener "change"
    (fun _event ->
       if
         enabled_node renderer node
         && W.HtmlInputElement.checked (Util.text_control_node dom_node)
       then
         emit renderer
           (if Store.true_property renderer node ChangeEnabled then Change node
            else if Store.true_property renderer node ToggleEnabled then
              ToggleChanged (node, true)
            else Press node))
    control

let attach_slider_event renderer node dom_node =
  W.Element.addEventListener "input"
    (fun _event ->
       emit renderer
         (ValueChanged
            (node,
             W.HtmlInputElement.valueAsNumber
               (Util.text_control_node dom_node))))
    dom_node

let attach_number_stepper_event renderer node dom_node =
  let input = Util.child_element dom_node 0 in
  W.Element.addEventListener "input"
    (fun _event ->
       let raw =
         W.HtmlInputElement.valueAsNumber (Util.text_control_node dom_node)
       in
       (* Clearing the field reports NaN; only finite values in range emit. *)
       if Float.is_finite raw then begin
         let minimum = Store.float_property renderer node MinValue 0.0 in
         let maximum =
           Store.float_property renderer node MaxValue Float.max_float
         in
         emit renderer
           (ValueChanged
              (node,
               Float.min (Float.max raw minimum) (Float.max minimum maximum)))
       end)
    input

let attach_accordion_event renderer node dom_node =
  W.Element.addEventListener "click"
    (fun event ->
       W.Event.preventDefault event;
       if Store.true_property renderer node ToggleEnabled then begin
         let selected = Store.true_property renderer node Selected in
         emit renderer (ToggleChanged (node, not selected))
       end)
    (Util.accordion_trigger_node dom_node)

let attach_pressable_text_events renderer node dom_node =
  W.Element.addEventListener "click"
    (fun _event ->
       if Store.event_capability renderer node PressEnabled then
         emit renderer (Press node))
    dom_node;
  W.Element.addKeyDownEventListener
    (fun event ->
       let key = W.KeyboardEvent.key event in
       if
         Store.event_capability renderer node PressEnabled
         && (key = "Enter" || key = " ")
       then begin
         W.KeyboardEvent.preventDefault event;
         emit renderer (Press node)
       end)
    dom_node

let attach_list_item_events renderer node dom_node =
  W.Element.addEventListener "dblclick"
    (fun _event ->
       if Store.event_capability renderer node DoublePressEnabled then
         emit renderer (DoublePress node))
    dom_node;
  W.Element.addKeyDownEventListener
    (fun event ->
       if
         W.KeyboardEvent.key event = "Enter"
         && Store.event_capability renderer node SubmitEnabled
       then begin
         W.KeyboardEvent.preventDefault event;
         emit renderer (Submit node)
       end)
    dom_node

type button_state = {
  button_timer : Js.Global.timeoutId option ref;
  button_suppress_click : bool ref;
  button_active_pointer : int option ref;
  button_origin_x : int ref;
  button_origin_y : int ref;
}

let button_long_press_enabled renderer node dom_node =
  enabled_node renderer node
  && W.Element.hasAttribute "data-long-press-enabled" dom_node
  && not (W.Element.hasAttribute "disabled" dom_node)

let button_connected renderer dom_node =
  W.Element.contains
    (W.Element.asNode dom_node)
    (W.Document.documentElement renderer.web_document)

let button_cancel_timer state =
  (match !(state.button_timer) with
   | Some timer_id -> Js.Global.clearTimeout timer_id
   | None -> ());
  state.button_timer := None

let button_cancel_long_press state =
  button_cancel_timer state;
  state.button_active_pointer := None

let button_dispatch_long_press renderer node dom_node state suppress =
  if button_long_press_enabled renderer node dom_node then begin
    state.button_suppress_click := suppress;
    emit renderer (LongPress node)
  end

let button_dispatch_primary renderer node kind dom_node =
  record_modal_return_focus renderer dom_node;
  if kind = ToggleButton || kind = Toggle then begin
    let selected =
      match W.Element.getAttribute "aria-pressed" dom_node with
      | Some "true" -> true
      | _ -> false
    in
    let next_selected = not selected in
    if next_selected then W.Element.setAttribute "data-selected" "" dom_node
    else W.Element.removeAttribute "data-selected" dom_node;
    W.Element.setAttribute "aria-pressed"
      (if next_selected then "true" else "false")
      dom_node;
    emit renderer (ToggleChanged (node, next_selected))
  end
  else if kind = ListItem then begin
    if Store.event_capability renderer node PressEnabled then
      emit renderer (Press node);
    if
      Store.treeitem renderer node
      && Store.event_capability renderer node ToggleEnabled
    then
      match Store.property renderer.web_store node Expanded with
      | Some (BoolValue expanded) ->
          emit renderer (ToggleChanged (node, not expanded))
      | _ -> ()
  end
  else emit renderer (Press node)

let button_schedule_long_press renderer node dom_node state =
  state.button_timer :=
    Some
      (Js.Global.setTimeout
         ~f:(fun () ->
           state.button_timer := None;
           if button_connected renderer dom_node then
             button_dispatch_long_press renderer node dom_node state true)
         350)

let button_pointer_down renderer node dom_node state event =
  button_cancel_long_press state;
  state.button_suppress_click := false;
  if
    button_long_press_enabled renderer node dom_node
    && W.MouseEvent.button (Util.pointer_mouse_event event) = 0
  then begin
    state.button_active_pointer := Some (Util.pointer_id event);
    state.button_origin_x :=
      W.MouseEvent.clientX (Util.pointer_mouse_event event);
    state.button_origin_y :=
      W.MouseEvent.clientY (Util.pointer_mouse_event event);
    if W.Event.isTrusted event then
      W.Element.setPointerCapture
        (W.PointerEvent.pointerId (Util.as_pointer_event event))
        dom_node;
    button_schedule_long_press renderer node dom_node state
  end

let button_pointer_move state event =
  match !(state.button_active_pointer) with
  | Some pointer when pointer = Util.pointer_id event ->
      let delta_x =
        abs (W.MouseEvent.clientX (Util.pointer_mouse_event event)
             - !(state.button_origin_x))
      in
      let delta_y =
        abs (W.MouseEvent.clientY (Util.pointer_mouse_event event)
             - !(state.button_origin_y))
      in
      if delta_x > 10 || delta_y > 10 then begin
        button_cancel_long_press state;
        state.button_suppress_click := false
      end
  | _ -> ()

let button_pointer_end state event =
  match !(state.button_active_pointer) with
  | Some pointer when pointer = Util.pointer_id event ->
      button_cancel_long_press state
  | _ -> ()

let button_pointer_cancel state event =
  match !(state.button_active_pointer) with
  | Some pointer when pointer = Util.pointer_id event ->
      button_cancel_long_press state;
      state.button_suppress_click := false
  | _ -> ()

let button_context_menu renderer node dom_node state event =
  if button_long_press_enabled renderer node dom_node then begin
    button_cancel_long_press state;
    W.Event.preventDefault event;
    button_dispatch_long_press renderer node dom_node state false
  end

let button_click renderer node kind dom_node state event =
  if not (enabled_node renderer node) then W.Event.preventDefault event
  else if !(state.button_suppress_click) then begin
    state.button_suppress_click := false;
    W.Event.preventDefault event
  end
  else begin
    emit_press_detail renderer node event;
    button_dispatch_primary renderer node kind dom_node
  end

let attach_button_events renderer node kind dom_node =
  let state =
    { button_timer = ref None;
      button_suppress_click = ref false;
      button_active_pointer = ref None;
      button_origin_x = ref 0;
      button_origin_y = ref 0 }
  in
  let pointer_down = button_pointer_down renderer node dom_node state in
  let pointer_move = button_pointer_move state in
  let pointer_end = button_pointer_end state in
  let pointer_cancel = button_pointer_cancel state in
  let context_menu = button_context_menu renderer node dom_node state in
  let click = button_click renderer node kind dom_node state in
  let previous_cleanup = Hashtbl.find_opt renderer.web_cleanups node in
  W.Element.addEventListener "pointerdown" pointer_down dom_node;
  W.Element.addEventListener "pointermove" pointer_move dom_node;
  W.Element.addEventListener "pointerup" pointer_end dom_node;
  W.Element.addEventListener "pointercancel" pointer_cancel dom_node;
  W.Element.addEventListener "lostpointercapture" pointer_cancel dom_node;
  W.Element.addEventListener "contextmenu" context_menu dom_node;
  W.Element.addEventListener "click" click dom_node;
  Hashtbl.replace renderer.web_cleanups node (fun () ->
      (match previous_cleanup with
       | Some cleanup -> cleanup ()
       | None -> ());
      button_cancel_long_press state;
      W.Element.removeEventListener "pointerdown" pointer_down dom_node;
      W.Element.removeEventListener "pointermove" pointer_move dom_node;
      W.Element.removeEventListener "pointerup" pointer_end dom_node;
      W.Element.removeEventListener "pointercancel" pointer_cancel dom_node;
      W.Element.removeEventListener "lostpointercapture" pointer_cancel
        dom_node;
      W.Element.removeEventListener "contextmenu" context_menu dom_node;
      W.Element.removeEventListener "click" click dom_node)

(* Kinds whose click path owns PressDetail emission (button family,
   pickers, radio): a suppressed click there must not still emit it, so the
   shared listener below skips them. *)
let press_detail_via_click kind =
  match kind with
  | Button | ToggleButton | Toggle | ListItem | Select | Combobox | Radio ->
      true
  | _ -> false

(* PointerDetail-family listeners, attached when the node opted in via the
   pointer-enabled property. Emission re-checks admission at event time so
   kind/property mismatches stay silent instead of crashing dispatch. *)
let attach_pointer_events renderer node kind dom_node =
  if Store.true_property renderer node PointerEnabled then begin
    let emit_detail make_event event =
      let candidate = make_event event in
      if
        enabled_node renderer node
        && Store.event_admitted renderer node candidate
      then emit renderer candidate
    in
    let pointer_down =
      emit_detail (fun event -> PointerDown (node, Util.pointer_detail_of event))
    in
    let pointer_up =
      emit_detail (fun event -> PointerUp (node, Util.pointer_detail_of event))
    in
    let pointer_enter = emit_detail (fun _event -> PointerEnter node) in
    let pointer_leave = emit_detail (fun _event -> PointerLeave node) in
    let context_menu =
      emit_detail
        (fun event -> ContextMenuPress (node, Util.pointer_detail_of event))
    in
    let click =
      emit_detail
        (fun event -> PressDetail (node, Util.pointer_detail_of event))
    in
    let attach_click = not (press_detail_via_click kind) in
    W.Element.addEventListener "pointerdown" pointer_down dom_node;
    W.Element.addEventListener "pointerup" pointer_up dom_node;
    W.Element.addEventListener "pointerenter" pointer_enter dom_node;
    W.Element.addEventListener "pointerleave" pointer_leave dom_node;
    W.Element.addEventListener "contextmenu" context_menu dom_node;
    if attach_click then
      W.Element.addEventListener "click" click dom_node;
    let previous_cleanup = Hashtbl.find_opt renderer.web_cleanups node in
    Hashtbl.replace renderer.web_cleanups node (fun () ->
        (match previous_cleanup with
         | Some cleanup -> cleanup ()
         | None -> ());
        W.Element.removeEventListener "pointerdown" pointer_down dom_node;
        W.Element.removeEventListener "pointerup" pointer_up dom_node;
        W.Element.removeEventListener "pointerenter" pointer_enter dom_node;
        W.Element.removeEventListener "pointerleave" pointer_leave dom_node;
        W.Element.removeEventListener "contextmenu" context_menu dom_node;
        if attach_click then
          W.Element.removeEventListener "click" click dom_node)
  end

let attach_events renderer node kind dom_node =
  if kind <> ContextMenu then
    ignore (Lui_web_menu.attach_context_host_events renderer node dom_node);
  attach_pointer_events renderer node kind dom_node;
  if tree_row_kind kind then
    ignore
      (Lui_web_focus.attach_tree_item_events renderer node kind dom_node);
  if kind = Tree then
    ignore (Lui_web_focus.attach_tree_events renderer node dom_node);
  if kind = Toolbar then
    ignore (Lui_web_focus.attach_toolbar_events renderer node dom_node);
  match kind with
  | Text | TableCell | TimelineItem | FileImage ->
      attach_pressable_text_events renderer node dom_node
  | Button | ToggleButton | Toggle ->
      attach_button_events renderer node kind dom_node
  | TextField | SecureField | Input | SearchField | Textarea ->
      attach_text_events renderer node kind dom_node
  | Select ->
      ignore (Lui_web_menu.attach_picker_trigger_events renderer node dom_node)
  | Combobox ->
      attach_text_events renderer node kind dom_node;
      ignore
        (Lui_web_menu.attach_picker_trigger_events renderer node
           (Util.child_element dom_node 1))
  | DropdownMenu ->
      ignore
        (Lui_web_menu.attach_dropdown_events renderer node
           (Util.child_element dom_node 0))
  | ContextMenu ->
      ignore (Lui_web_menu.attach_context_menu_events renderer node dom_node)
  | Dialog | Sheet ->
      ignore (Lui_web_overlay.attach_modal_events renderer node dom_node)
  | MenuItem | MenuTrigger ->
      ignore (Lui_web_menu.attach_picker_press_event renderer node dom_node);
      W.Element.addEventListener "focusin"
        (fun _event ->
           W.Element.setAttribute "data-highlighted" "" dom_node)
        dom_node;
      W.Element.addEventListener "focusout"
        (fun _event -> W.Element.removeAttribute "data-highlighted" dom_node)
        dom_node
  | ListItem ->
      attach_button_events renderer node kind dom_node;
      attach_list_item_events renderer node dom_node
  | Checkbox | SwitchControl ->
      attach_toggle_event renderer node kind dom_node
  | Radio -> attach_radio_event renderer node dom_node
  | Slider -> attach_slider_event renderer node dom_node
  | NumberStepper -> attach_number_stepper_event renderer node dom_node
  | Split -> ignore (Lui_web_split.attach_split_events renderer node dom_node)
  | Tabs | ButtonGroup | ToggleGroup | Breadcrumb | Pagination ->
      ignore (Lui_web_focus.attach_horizontal_focus renderer node kind dom_node)
  | Accordion -> attach_accordion_event renderer node dom_node
  | _ -> ()

let attach_events_bang = attach_events
let attach_pointer_events_bang = attach_pointer_events
let emit_press_detail_bang = emit_press_detail
let attach_text_events_bang = attach_text_events
let attach_toggle_event_bang = attach_toggle_event
let attach_radio_event_bang = attach_radio_event
let attach_slider_event_bang = attach_slider_event
let attach_number_stepper_event_bang = attach_number_stepper_event
let attach_list_item_events_bang = attach_list_item_events
let attach_pressable_text_events_bang = attach_pressable_text_events
let attach_accordion_event_bang = attach_accordion_event
let attach_button_events_bang = attach_button_events
