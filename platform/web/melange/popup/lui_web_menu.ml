(* Menus for the web backend: picker/combobox plumbing, dropdown wiring,
   and context-menu behaviour. *)

open Lui_protocol
open Lui_web_types

module W = Webapi.Dom
module Store = Lui_web_store

(* Popup transition helpers. These belong to the popup-transition vocabulary
   owned by Lui_web_position, but that module is still a stub, so the port
   keeps local copies here; switch to the shared versions when they exist. *)
external media_query_list_matches : W.Window.mediaQueryList -> bool = "matches"
  [@@mel.get]

let emit renderer event = ignore (!(renderer.web_event_handler) event)

let transition_event_from target event =
  W.Element.isSameNode
    (W.Element.asNode
       (Lui_web_util.event_target_to_element (W.Event.target event)))
    target

let prefers_reduced_motion document =
  let html_document = W.Document.unsafeAsHtmlDocument document in
  match W.HtmlDocument.defaultView html_document with
  | Some window ->
      media_query_list_matches
        (W.Window.matchMedia "(prefers-reduced-motion: reduce)" window)
  | None -> false

let after_transition document target fallback_duration finish_on_cancel
    complete =
  if prefers_reduced_motion document then complete ()
  else begin
    let finished = ref false in
    let timer = ref None in
    let finish_ref = ref (fun () -> ()) in
    let transition_handler event =
      if transition_event_from target event then !finish_ref ()
    in
    let finish () =
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
    in
    finish_ref := finish;
    W.Element.addEventListener "transitionend" transition_handler target;
    if finish_on_cancel then
      W.Element.addEventListener "transitioncancel" transition_handler target;
    timer := Some (Js.Global.setTimeout ~f:finish fallback_duration)
  end

let begin_popup_open popup =
  W.Element.removeAttribute "data-closed" popup;
  W.Element.removeAttribute "data-ending-style" popup;
  W.Element.setAttribute "data-open" "" popup;
  W.Element.setAttribute "data-starting-style" "" popup;
  Webapi.requestAnimationFrame (fun _time ->
      W.Element.removeAttribute "data-starting-style" popup)

let begin_popup_close popup =
  W.Element.removeAttribute "data-open" popup;
  W.Element.setAttribute "data-closed" "" popup;
  W.Element.setAttribute "data-ending-style" "" popup

let finish_popup_close_after_transition document popup duration =
  after_transition document popup duration true (fun () ->
      if W.Element.getAttribute "data-ending-style" popup = Some "" then
        W.Element.removeAttribute "data-ending-style" popup)

let cancel_typeahead typeahead_timer =
  (match !typeahead_timer with
   | Some timer_id -> Js.Global.clearTimeout timer_id
   | None -> ());
  typeahead_timer := None

let reset_typeahead_later typeahead_buffer typeahead_timer =
  cancel_typeahead typeahead_timer;
  typeahead_timer :=
    Some
      (Js.Global.setTimeout
         ~f:(fun () ->
           typeahead_timer := None;
           typeahead_buffer := "")
         500)

let starts_with ~prefix value =
  let prefix_length = String.length prefix in
  String.length value >= prefix_length
  && String.sub value 0 prefix_length = prefix

let dropdown_node nodes node =
  match Hashtbl.find_opt nodes node with
  | Some current -> Store.standard_kind_is current DropdownMenu
  | None -> false

let dropdown_node_ = dropdown_node

let child_with_kind renderer children kind =
  List.find_opt
    (fun child ->
      match Store.node renderer.web_store child with
      | Some child_node -> Store.standard_kind_is child_node kind
      | None -> false)
    children

(* --- picker / combobox plumbing --- *)

let picker_dropdown renderer picker =
  match Store.node renderer.web_store picker with
  | Some current ->
      (match current.retained_parent with
       | Some parent ->
           child_with_kind renderer
             (Store.children renderer.web_store parent)
             DropdownMenu
       | None -> None)
  | None -> None

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
  let picker_element = Lui_web_nodes.dom_node renderer picker in
  match Store.node renderer.web_store picker with
  | Some current ->
      if Store.standard_kind_is current Combobox then
        Lui_web_util.child_element picker_element 0
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
  let items = picker_menu_items renderer dropdown in
  let rec loop index =
    if index = List.length items then 0
    else if
      Store.property renderer.web_store (List.nth items index) Selected
      = Some (BoolValue true)
    then index
    else loop (index + 1)
  in
  loop 0

let combobox_active_index renderer picker items =
  match
    W.Element.getAttribute "data-lui-active-index"
      (picker_control_element renderer picker)
  with
  | Some value ->
      (match int_of_string_opt value with
       | Some index ->
           if index >= 0 && index < List.length items then Some index
           else None
       | None -> None)
  | None -> None

let set_combobox_active renderer picker dropdown index =
  let items = picker_menu_items renderer dropdown in
  let control = picker_control_element renderer picker in
  List.iter
    (fun item ->
      W.Element.removeAttribute "data-highlighted"
        (Lui_web_nodes.dom_node renderer item))
    items;
  if items <> [] && index >= 0 && index < List.length items then begin
    let item = List.nth items index in
    let element = Lui_web_nodes.dom_node renderer item in
    W.Element.setAttribute "data-lui-active-index" (string_of_int index)
      control;
    W.Element.setAttribute "data-highlighted" "" element;
    W.Element.setAttribute "aria-activedescendant"
      (Lui_web_util.node_dom_id item) control
  end

let set_combobox_active_bang = set_combobox_active

let clear_combobox_active renderer picker =
  let control = picker_control_element renderer picker in
  W.Element.removeAttribute "data-lui-active-index" control;
  W.Element.removeAttribute "aria-activedescendant" control

let ensure_combobox_status renderer dropdown =
  let popup =
    Lui_web_util.child_element (Lui_web_nodes.dom_node renderer dropdown) 0
  in
  match W.Element.querySelector ".lui-combobox-status" popup with
  | Some status -> status
  | None ->
      let status =
        Lui_web_util.element renderer.web_document "div"
          "lui-combobox-status"
          [ ("role", "status"); ("aria-live", "polite");
            ("aria-atomic", "true") ]
          []
      in
      W.Element.appendChild (W.Element.asNode status) popup;
      status

let refresh_dropdown_item_roles renderer dropdown =
  let listbox = Lui_web_nodes.dropdown_listbox renderer dropdown in
  List.iter
    (fun item ->
      match Store.node renderer.web_store item with
      | Some current ->
          if Store.menu_item_row current then
            if listbox then begin
              W.Element.setAttribute "role" "option" current.platform_node;
              W.Element.setAttribute "aria-selected"
                (if
                   Store.property renderer.web_store item Selected
                   = Some (BoolValue true)
                 then "true"
                 else "false")
                current.platform_node
            end
            else begin
              W.Element.setAttribute "role" "menuitem" current.platform_node;
              W.Element.removeAttribute "aria-selected" current.platform_node
            end
      | None -> ())
    (Store.children renderer.web_store dropdown)

let combobox_status_text item_count =
  if item_count = 1 then "1 result available."
  else string_of_int item_count ^ " results available."

let refresh_combobox_list_state renderer dropdown =
  (match picker_for_dropdown renderer dropdown with
   | Some picker ->
       (match Store.node renderer.web_store picker with
        | Some current ->
            if Store.standard_kind_is current Combobox then begin
              let items = picker_menu_items renderer dropdown in
              let item_count = List.length items in
              let empty = items = [] in
              let root = current.platform_node in
              let control = Lui_web_util.child_element root 0 in
              let trigger = Lui_web_util.child_element root 1 in
              let positioner = Lui_web_nodes.dom_node renderer dropdown in
              let popup = Lui_web_util.child_element positioner 0 in
              let status = ensure_combobox_status renderer dropdown in
              Lui_web_util.set_state_attribute control "data-list-empty" empty;
              Lui_web_util.set_state_attribute trigger "data-list-empty" empty;
              Lui_web_util.set_state_attribute positioner "data-empty" empty;
              Lui_web_util.set_state_attribute popup "data-empty" empty;
              W.Element.setTextContent status
                (if empty then "No results." else combobox_status_text item_count);
              if empty then clear_combobox_active renderer picker
              else begin
                let index =
                  match combobox_active_index renderer picker items with
                  | Some current_index -> current_index
                  | None -> 0
                in
                let expected_id =
                  Lui_web_util.node_dom_id (List.nth items index)
                in
                if
                  W.Element.getAttribute "aria-activedescendant" control
                  <> Some expected_id
                then set_combobox_active renderer picker dropdown index
              end;
              if W.Element.hasAttribute "data-open" popup then
                Lui_web_position.position_dropdown renderer dropdown
            end
        | None -> ())
   | None -> ())

let activate_menu_item renderer item =
  W.HtmlElement.click
    (W.Element.unsafeAsHtmlElement (Lui_web_nodes.dom_node renderer item))

let activate_menu_item_bang = activate_menu_item

(* --- dropdown open/close --- *)

let set_dropdown_open renderer node open_ =
  let positioner = Lui_web_nodes.dom_node renderer node in
  let popup = Lui_web_util.child_element positioner 0 in
  if open_ then begin
    begin_popup_open popup;
    ignore (Lui_web_position.position_dropdown renderer node);
    Webapi.requestAnimationFrame (fun _time ->
        match Store.node renderer.web_store node with
        | Some _current -> Lui_web_position.position_dropdown renderer node
        | None -> ())
  end
  else begin
    begin_popup_close popup;
    finish_popup_close_after_transition renderer.web_document popup 130
  end

let set_dropdown_open_bang = set_dropdown_open

(* --- context menu core --- *)

let direct_context_menu renderer node =
  match Store.node renderer.web_store node with
  | Some current ->
      List.find_opt
        (fun child ->
          match Store.node renderer.web_store child with
          | Some child_node ->
              Store.standard_kind_is child_node ContextMenu
              && List.exists
                   (fun item ->
                     match Store.node renderer.web_store item with
                     | Some item_node ->
                         Store.standard_kind_is item_node MenuItem
                     | None -> false)
                   child_node.retained_children
          | None -> false)
        current.retained_children
  | None -> None

let direct_dropdown_menu renderer node =
  match Store.node renderer.web_store node with
  | Some current ->
      child_with_kind renderer current.retained_children DropdownMenu
  | None -> None

let hide_context_menu renderer =
  match !(renderer.web_open_context_menu) with
  | Some menu ->
      W.Element.removeAttribute "data-open"
        (Lui_web_nodes.dom_node renderer menu);
      renderer.web_open_context_menu := None
  | None -> ()

let context_menu_focus_items renderer menu =
  match Store.node renderer.web_store menu with
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

let focus_context_menu_item renderer menu index =
  let items = context_menu_focus_items renderer menu in
  if items <> [] then
    W.HtmlElement.focus
      (W.Element.unsafeAsHtmlElement
         (Lui_web_nodes.dom_node renderer (List.nth items index)))

let focus_context_menu_item_bang = focus_context_menu_item

let focus_context_menu_host renderer menu =
  match Store.node renderer.web_store menu with
  | Some current ->
      (match current.retained_parent with
       | Some host ->
           Lui_web_util.focus_element (Lui_web_nodes.dom_node renderer host)
       | None -> ())
  | None -> ()

let set_context_position dom_node property value =
  W.CssStyleDeclaration.setProperty property value ""
    (W.HtmlElement.style (W.Element.unsafeAsHtmlElement dom_node))

let show_context_menu renderer menu x y =
  hide_context_menu renderer;
  let menu_node = Lui_web_nodes.dom_node renderer menu in
  W.Element.setAttribute "data-open" "" menu_node;
  let width = W.Element.clientWidth menu_node in
  let height = W.Element.clientHeight menu_node in
  let document_root = W.Document.documentElement renderer.web_document in
  let viewport_width = W.Element.clientWidth document_root in
  let viewport_height = W.Element.clientHeight document_root in
  let left = max 8 (min x (viewport_width - width - 8)) in
  let top = max 8 (min y (viewport_height - height - 8)) in
  set_context_position menu_node "left" (string_of_int left ^ "px");
  set_context_position menu_node "top" (string_of_int top ^ "px");
  renderer.web_open_context_menu := Some menu;
  let items = context_menu_focus_items renderer menu in
  if items = [] then
    W.HtmlElement.focus (W.Element.unsafeAsHtmlElement menu_node)
  else focus_context_menu_item renderer menu 0

(* --- picker event wiring --- *)

let attach_picker_press_event renderer node dom_node =
  W.Element.addEventListener "click"
    (fun _event ->
      if Store.event_capability renderer node PressEnabled then
        emit renderer (Press node))
    dom_node

let attach_picker_press_event_bang = attach_picker_press_event

let attach_picker_trigger_events renderer node dom_node =
  let current_pointer_type = ref "mouse" in
  let suppress_click = ref false in
  let press () =
    if
      Store.enabled_node renderer node
      && Store.event_capability renderer node PressEnabled
    then emit renderer (Press node)
  in
  W.Element.addEventListener "pointerdown"
    (fun event ->
      let method_ = Lui_web_util.pointer_type event in
      current_pointer_type := method_;
      W.Element.setAttribute "data-lui-open-method" method_ dom_node)
    dom_node;
  W.Element.addEventListener "mousedown"
    (fun event ->
      if W.MouseEvent.button (Lui_web_util.pointer_mouse_event event) = 0
      then begin
        W.Element.setAttribute "data-lui-open-method" !current_pointer_type
          dom_node;
        if !current_pointer_type = "touch" then W.Event.preventDefault event;
        suppress_click := true;
        ignore
          (Js.Global.setTimeout ~f:(fun () -> suppress_click := false) 0);
        press ()
      end)
    dom_node;
  W.Element.addEventListener "click"
    (fun _event ->
      if !suppress_click then suppress_click := false
      else begin
        W.Element.setAttribute "data-lui-open-method" "keyboard" dom_node;
        press ()
      end)
    dom_node

let attach_picker_trigger_events_bang = attach_picker_trigger_events

(* --- dropdown event wiring --- *)

let dropdown_group_contains_event renderer node event =
  match Store.node renderer.web_store node with
  | Some current ->
      let target =
        Lui_web_util.event_target_to_element (W.Event.target event)
      in
      W.Element.contains (W.Element.asNode target) current.platform_node
      ||
      (match current.retained_parent with
       | Some parent ->
           W.Element.contains (W.Element.asNode target)
             (Lui_web_nodes.dom_node renderer parent)
       | None -> false)
  | None -> false

let dropdown_submenu_trigger renderer node =
  match Store.node renderer.web_store node with
  | Some current ->
      (match current.retained_parent with
       | Some candidate ->
           (match Store.node renderer.web_store candidate with
            | Some candidate_node ->
                if Store.menu_item_row candidate_node then
                  Some candidate
                else None
            | None -> None)
       | None -> None)
  | None -> None

let close_submenu_to_trigger renderer node trigger =
  let trigger_node = Lui_web_nodes.dom_node renderer trigger in
  W.HtmlElement.focus (W.Element.unsafeAsHtmlElement trigger_node);
  set_dropdown_open renderer node false;
  W.Element.setAttribute "aria-expanded" "false" trigger_node

let dropdown_navigate renderer node items current_index key event =
  let navigation_key =
    if key = "ArrowDown" then "ArrowRight"
    else if key = "ArrowUp" then "ArrowLeft"
    else key
  in
  match
    Lui_web_focus.horizontal_focus_index navigation_key current_index
      (List.length items)
  with
  | Some index ->
      W.KeyboardEvent.preventDefault event;
      focus_context_menu_item renderer node index
  | None -> ()

let dropdown_typeahead renderer node typeahead_buffer typeahead_timer items
    current_index key event =
  let query = String.lowercase_ascii (!typeahead_buffer ^ key) in
  let start = match current_index with Some index -> index | None -> -1 in
  typeahead_buffer := query;
  reset_typeahead_later typeahead_buffer typeahead_timer;
  let rec loop offset =
    if offset <= List.length items then begin
      let index = (start + offset) mod List.length items in
      let label =
        String.lowercase_ascii
          (String.trim
             (W.Element.textContent
                (Lui_web_nodes.dom_node renderer (List.nth items index))))
      in
      if starts_with ~prefix:query label then begin
        W.KeyboardEvent.preventDefault event;
        focus_context_menu_item renderer node index
      end
      else loop (offset + 1)
    end
  in
  loop 1

let dropdown_key_handler renderer node typeahead_buffer typeahead_timer
    event =
  let key = W.KeyboardEvent.key event in
  let items = context_menu_focus_items renderer node in
  let event_target =
    Lui_web_util.event_target_to_element (W.KeyboardEvent.target event)
  in
  let current_index =
    Lui_web_focus.focused_child_index renderer items event_target 0
  in
  let submenu_trigger = dropdown_submenu_trigger renderer node in
  if current_index <> None then begin
    if key = "ArrowDown" || key = "ArrowUp" || key = "Home" || key = "End"
    then dropdown_navigate renderer node items current_index key event
    else if key = "ArrowRight" then begin
      match current_index with
      | Some index ->
          (match direct_dropdown_menu renderer (List.nth items index) with
           | Some submenu ->
               W.KeyboardEvent.preventDefault event;
               set_dropdown_open renderer submenu true;
               focus_context_menu_item renderer submenu 0
           | None -> ())
      | None -> ()
    end
    else if key = "ArrowLeft" && submenu_trigger <> None then begin
      match submenu_trigger with
      | Some trigger ->
          W.KeyboardEvent.preventDefault event;
          close_submenu_to_trigger renderer node trigger
      | None -> ()
    end
    else if key = "Escape" then begin
      W.KeyboardEvent.preventDefault event;
      match submenu_trigger with
      | Some trigger -> close_submenu_to_trigger renderer node trigger
      | None -> emit renderer (Dismiss node)
    end
    else if
      String.length key = 1
      && not (W.KeyboardEvent.metaKey event)
      && not (W.KeyboardEvent.ctrlKey event)
    then
      dropdown_typeahead renderer node typeahead_buffer typeahead_timer
        items current_index key event
  end

let attach_dropdown_events renderer node _dropdown_node =
  let document = renderer.web_document in
  let window =
    W.HtmlDocument.defaultView (W.Document.unsafeAsHtmlDocument document)
  in
  let typeahead_buffer = ref "" in
  let typeahead_timer = ref None in
  let refresh_position _event =
    Webapi.requestAnimationFrame (fun _time ->
        match Store.node renderer.web_store node with
        | Some _current -> Lui_web_position.position_dropdown renderer node
        | None -> ())
  in
  let pointer_handler event =
    if not (dropdown_group_contains_event renderer node event) then
      emit renderer (Dismiss node);
    refresh_position event
  in
  let key_handler event =
    dropdown_key_handler renderer node typeahead_buffer typeahead_timer event
  in
  W.Document.addEventListener "pointerdown" pointer_handler document;
  W.Document.addEventListener "click" refresh_position document;
  (match window with
   | Some current_window ->
       W.Window.addEventListener "resize" refresh_position current_window
   | None -> ());
  W.Document.addKeyDownEventListener key_handler document;
  Hashtbl.replace renderer.web_cleanups node (fun () ->
      cancel_typeahead typeahead_timer;
      W.Document.removeEventListener "pointerdown" pointer_handler document;
      W.Document.removeEventListener "click" refresh_position document;
      (match window with
       | Some current_window ->
           W.Window.removeEventListener "resize" refresh_position
             current_window
       | None -> ());
      W.Document.removeKeyDownEventListener key_handler document)

let attach_dropdown_events_bang = attach_dropdown_events

(* --- context menu host wiring --- *)

type context_host_state = {
  timer : Js.Global.timeoutId option ref;
  suppress_click : bool ref;
  touch_pointer : int option ref;
  touch_origin_x : int option ref;
  touch_origin_y : int option ref;
}

let cancel_context_touch state =
  (match !(state.timer) with
   | Some timer_id -> Js.Global.clearTimeout timer_id
   | None -> ());
  state.timer := None;
  state.touch_pointer := None;
  state.touch_origin_x := None;
  state.touch_origin_y := None

let context_host_mouse_down renderer node event =
  if W.MouseEvent.button event = 2 then
    match direct_context_menu renderer node with
    | Some menu ->
        W.MouseEvent.preventDefault event;
        W.MouseEvent.stopImmediatePropagation event;
        show_context_menu renderer menu
          (W.MouseEvent.clientX event)
          (W.MouseEvent.clientY event)
    | None -> ()

let context_host_pointer_down renderer node state event =
  if
    Lui_web_util.pointer_type event = "touch"
    && W.MouseEvent.button (Lui_web_util.pointer_mouse_event event) = 0
  then
    match direct_context_menu renderer node with
    | Some menu ->
        let x =
          W.MouseEvent.clientX (Lui_web_util.pointer_mouse_event event)
        in
        let y =
          W.MouseEvent.clientY (Lui_web_util.pointer_mouse_event event)
        in
        cancel_context_touch state;
        state.touch_pointer := Some (Lui_web_util.pointer_id event);
        state.touch_origin_x := Some x;
        state.touch_origin_y := Some y;
        state.timer :=
          Some
            (Js.Global.setTimeout
               ~f:(fun () ->
                 state.timer := None;
                 state.touch_origin_x := None;
                 state.touch_origin_y := None;
                 state.suppress_click := true;
                 show_context_menu renderer menu x y)
               500)
    | None -> ()

let context_host_pointer_move state event =
  match !(state.touch_pointer) with
  | Some active_pointer_id ->
      if active_pointer_id = Lui_web_util.pointer_id event then
        (match (!(state.touch_origin_x), !(state.touch_origin_y)) with
         | Some origin_x, Some origin_y ->
             let mouse_event = Lui_web_util.pointer_mouse_event event in
             let delta_x = abs (W.MouseEvent.clientX mouse_event - origin_x) in
             let delta_y = abs (W.MouseEvent.clientY mouse_event - origin_y) in
             if delta_x > 10 || delta_y > 10 then cancel_context_touch state
         | _ -> ())
  | None -> ()

let context_host_pointer_end state event =
  match !(state.touch_pointer) with
  | Some active_pointer_id ->
      if active_pointer_id = Lui_web_util.pointer_id event then
        cancel_context_touch state
  | None -> ()

let context_host_click state event =
  if !(state.suppress_click) then begin
    state.suppress_click := false;
    W.Event.preventDefault event;
    W.Event.stopImmediatePropagation event
  end

let context_host_contextmenu renderer node event =
  match direct_context_menu renderer node with
  | Some _menu ->
      W.Event.preventDefault event;
      W.Event.stopImmediatePropagation event
  | None -> ()

let context_host_keydown renderer node host_node event =
  let key = W.KeyboardEvent.key event in
  if
    key = "ContextMenu"
    || (key = "F10" && W.KeyboardEvent.shiftKey event)
  then
    match direct_context_menu renderer node with
    | Some menu ->
        let bounds = W.Element.getBoundingClientRect host_node in
        W.KeyboardEvent.preventDefault event;
        show_context_menu renderer menu
          (int_of_float (W.DomRect.left bounds))
          (int_of_float (W.DomRect.bottom bounds))
    | None -> ()

let attach_context_host_events renderer node host_node =
  let state =
    { timer = ref None; suppress_click = ref false;
      touch_pointer = ref None; touch_origin_x = ref None;
      touch_origin_y = ref None }
  in
  W.Element.addMouseDownEventListener
    (fun event -> context_host_mouse_down renderer node event)
    host_node;
  W.Element.addEventListener "pointerdown"
    (fun event -> context_host_pointer_down renderer node state event)
    host_node;
  W.Element.addEventListener "pointermove"
    (fun event -> context_host_pointer_move state event)
    host_node;
  W.Element.addEventListener "pointerup"
    (fun event -> context_host_pointer_end state event)
    host_node;
  W.Element.addEventListener "pointercancel"
    (fun event -> context_host_pointer_end state event)
    host_node;
  W.Element.addEventListener "click"
    (fun event -> context_host_click state event)
    host_node;
  W.Element.addEventListener "contextmenu"
    (fun event -> context_host_contextmenu renderer node event)
    host_node;
  W.Element.addKeyDownEventListener
    (fun event -> context_host_keydown renderer node host_node event)
    host_node

let attach_context_host_events_bang = attach_context_host_events

(* --- context menu document-level wiring --- *)

let context_menu_key_handler renderer document node event =
  if !(renderer.web_open_context_menu) = Some node then begin
    let key = W.KeyboardEvent.key event in
    if key = "Escape" then begin
      W.KeyboardEvent.preventDefault event;
      hide_context_menu renderer;
      focus_context_menu_host renderer node
    end
    else if
      key = "ArrowDown" || key = "ArrowUp" || key = "Home" || key = "End"
    then begin
      let items = context_menu_focus_items renderer node in
      let html_document = W.Document.unsafeAsHtmlDocument document in
      let current =
        match W.HtmlDocument.activeElement html_document with
        | Some focused ->
            Lui_web_focus.focused_child_index renderer items focused 0
        | None -> None
      in
      let navigation_key =
        if key = "ArrowDown" then "ArrowRight"
        else if key = "ArrowUp" then "ArrowLeft"
        else key
      in
      match
        Lui_web_focus.horizontal_focus_index navigation_key current
          (List.length items)
      with
      | Some index ->
          W.KeyboardEvent.preventDefault event;
          focus_context_menu_item renderer node index
      | None -> ()
    end
  end

let attach_context_menu_events renderer node dom_node =
  let document = renderer.web_document in
  let pointer_handler event =
    let target =
      Lui_web_util.event_target_to_element (W.Event.target event)
    in
    if not (W.Element.contains (W.Element.asNode target) dom_node) then
      hide_context_menu renderer
  in
  let key_handler event =
    context_menu_key_handler renderer document node event
  in
  let focus_handler event =
    let target =
      Lui_web_util.event_target_to_element (W.Event.target event)
    in
    if
      !(renderer.web_open_context_menu) = Some node
      && not (W.Element.contains (W.Element.asNode target) dom_node)
    then hide_context_menu renderer
  in
  let click_handler _event = hide_context_menu renderer in
  W.Document.addEventListener "pointerdown" pointer_handler document;
  W.Document.addKeyDownEventListener key_handler document;
  W.Document.addEventListener "focusin" focus_handler document;
  W.Element.addEventListener "click" click_handler dom_node;
  Hashtbl.replace renderer.web_cleanups node (fun () ->
      W.Document.removeEventListener "pointerdown" pointer_handler document;
      W.Document.removeKeyDownEventListener key_handler document;
      W.Document.removeEventListener "focusin" focus_handler document;
      W.Element.removeEventListener "click" click_handler dom_node;
      if !(renderer.web_open_context_menu) = Some node then
        renderer.web_open_context_menu := None)

let attach_context_menu_events_bang = attach_context_menu_events

(* --- mount --- *)

(* A dropdown hanging off a menu row (MenuItem/MenuTrigger) that lives inside
   another menu opens to the side by default, like the original gallery's
   explicit {:anchor "right"} submenu declaration. *)
let nested_submenu renderer current =
  match current.retained_parent with
  | Some trigger ->
      (match Store.node renderer.web_store trigger with
       | Some trigger_node ->
           (match trigger_node.retained_parent with
            | Some container ->
                (match Store.node renderer.web_store container with
                 | Some container_node ->
                     Store.standard_kind_is container_node DropdownMenu
                 | None -> false)
            | None -> false)
       | None -> false)
  | None -> false

let attach_submenu_hover renderer node current trigger =
  let positioner = current.platform_node in
  let popup = Lui_web_util.child_element current.platform_node 0 in
  (match Store.property renderer.web_store node AnchorValue with
   | Some _ -> ()
   | None ->
       if nested_submenu renderer current then
         W.Element.setAttribute "data-anchor" "right" positioner);
  let close_timer = ref None in
  let grace_active = ref false in
  let grace_x = ref 0.0 in
  let grace_y = ref 0.0 in
  let cancel_close () =
    (match !close_timer with
     | Some timer -> Js.Global.clearTimeout timer
     | None -> ());
    close_timer := None
  in
  let close_later () =
    cancel_close ();
    close_timer :=
      Some
        (Js.Global.setTimeout
           ~f:(fun () ->
             close_timer := None;
             grace_active := false;
             W.Element.setAttribute "aria-expanded" "false" trigger;
             set_dropdown_open renderer node false)
           120)
  in
  let open_submenu _event =
    cancel_close ();
    grace_active := false;
    W.Element.setAttribute "aria-expanded" "true" trigger;
    set_dropdown_open renderer node true
  in
  let trigger_leave event =
    let mouse_event = Lui_web_util.pointer_mouse_event event in
    grace_active := true;
    grace_x := float_of_int (W.MouseEvent.clientX mouse_event);
    grace_y := float_of_int (W.MouseEvent.clientY mouse_event);
    close_later ()
  in
  let popup_leave _event =
    grace_active := false;
    close_later ()
  in
  let pointer_move event =
    if !grace_active then begin
      let mouse_event = Lui_web_util.pointer_mouse_event event in
      let point_x = float_of_int (W.MouseEvent.clientX mouse_event) in
      let point_y = float_of_int (W.MouseEvent.clientY mouse_event) in
      if
        not
          (Lui_web_position.submenu_corridor positioner popup !grace_x
             !grace_y point_x point_y)
      then grace_active := false;
      close_later ()
    end
  in
  let previous_cleanup = Hashtbl.find_opt renderer.web_cleanups node in
  W.Element.setAttribute "data-submenu-trigger" "" trigger;
  W.Element.setAttribute "aria-haspopup" "menu" trigger;
  W.Element.setAttribute "aria-expanded" "false" trigger;
  W.Element.setAttribute "data-submenu" "" positioner;
  W.Element.setAttribute "role" "menu" popup;
  W.Element.addEventListener "mouseenter" open_submenu trigger;
  W.Element.addEventListener "focusin" open_submenu trigger;
  W.Element.addEventListener "mouseleave" trigger_leave trigger;
  W.Element.addEventListener "mouseenter" open_submenu popup;
  W.Element.addEventListener "mouseleave" popup_leave popup;
  W.Document.addEventListener "mousemove" pointer_move
    renderer.web_document;
  Hashtbl.replace renderer.web_cleanups node (fun () ->
      (match previous_cleanup with
       | Some cleanup -> cleanup ()
       | None -> ());
      cancel_close ();
      W.Element.removeEventListener "mouseenter" open_submenu trigger;
      W.Element.removeEventListener "focusin" open_submenu trigger;
      W.Element.removeEventListener "mouseleave" trigger_leave trigger;
      W.Element.removeEventListener "mouseenter" open_submenu popup;
      W.Element.removeEventListener "mouseleave" popup_leave popup;
      W.Document.removeEventListener "mousemove" pointer_move
        renderer.web_document);
  Lui_web_position.position_dropdown renderer node

(* The batch that mounts a picker dropdown can still be mid-flight, with
   the popup's items inserted by later ops in the same batch, so work that
   touches the items has to wait for the synchronous apply to unwind. A
   microtask runs as soon as the current task's JS completes, ahead of any
   subsequently queued task. *)
let after_batch_apply f =
  ignore
    (Js.Promise.resolve ()
     |> Js.Promise.then_ (fun () ->
            f ();
            Js.Promise.resolve ()))

let mount_picker_dropdown renderer node =
  set_dropdown_open renderer node true;
  match picker_for_dropdown renderer node with
  | Some picker ->
      let control = picker_control_element renderer picker in
      let popup_id = Lui_web_util.node_dom_id node ^ "-popup" in
      let previous_cleanup = Hashtbl.find_opt renderer.web_cleanups node in
      W.Element.setAttribute "aria-controls" popup_id control;
      (match Store.node renderer.web_store picker with
       | Some picker_node ->
           if Store.standard_kind_is picker_node Combobox then
             after_batch_apply (fun () ->
                 match Store.node renderer.web_store node with
                 | Some _menu -> set_combobox_active renderer picker node 0
                 | None -> ())
           else
             after_batch_apply (fun () ->
                 match Store.node renderer.web_store node with
                 | Some _menu ->
                     focus_context_menu_item renderer node
                       (picker_selected_index renderer node)
                 | None -> ())
       | None -> ());
      Hashtbl.replace renderer.web_cleanups node (fun () ->
          (match previous_cleanup with
           | Some cleanup -> cleanup ()
           | None -> ());
          W.Element.removeAttribute "aria-controls" control;
          W.Element.removeAttribute "data-lui-active-index" control;
          W.Element.removeAttribute "aria-activedescendant" control;
          Lui_web_util.focus_element control)
  | None -> ()

let mount_dropdown renderer node =
  match Store.node renderer.web_store node with
  | Some current ->
      let popup = Lui_web_util.child_element current.platform_node 0 in
      W.Element.setAttribute "role"
        (if Lui_web_nodes.dropdown_listbox renderer node then "listbox"
         else "menu")
        popup;
      W.Element.setAttribute "id"
        (Lui_web_util.node_dom_id node ^ "-popup") popup;
      refresh_dropdown_item_roles renderer node;
      refresh_combobox_list_state renderer node;
      (match current.retained_parent with
       | Some parent ->
           (match Store.node renderer.web_store parent with
            | Some parent_node ->
                if Store.menu_item_row parent_node then
                  ignore
                    (attach_submenu_hover renderer node current
                       parent_node.platform_node)
                else mount_picker_dropdown renderer node
            | None -> invalid_arg "dropdown parent is unavailable")
       | None -> invalid_arg "dropdown requires an anchor parent")
  | None -> invalid_arg "unknown dropdown node"

let mount_dropdown_bang = mount_dropdown

let update_picker_expanded renderer parent expanded =
  match Store.node renderer.web_store parent with
  | Some parent_node ->
      List.iter
        (fun child ->
          match Store.node renderer.web_store child with
          | Some current ->
              (match Store.standard_kind current with
               | Some Select ->
                   W.Element.setAttribute "aria-expanded"
                     (if expanded then "true" else "false")
                     current.platform_node
               | Some Combobox ->
                   W.Element.setAttribute "aria-expanded"
                     (if expanded then "true" else "false")
                     (Lui_web_util.child_element current.platform_node 0)
               | _ -> ())
          | None -> ())
        parent_node.retained_children
  | None -> ()

let update_picker_expanded_bang = update_picker_expanded

let remove_dropdown_after_exit document parent positioner =
  let popup = Lui_web_util.child_element positioner 0 in
  begin_popup_close popup;
  W.Element.setAttribute "inert" "" popup;
  after_transition document popup 130 true (fun () ->
      if W.Element.contains (W.Element.asNode positioner) parent then
        ignore
          (W.Element.removeChild (W.Element.asNode positioner) parent))
