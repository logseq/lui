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

external click_detail : Dom.event -> int = "detail" [@@mel.get]

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

let clear_picker_intent control intent_timer intent_generation =
  cancel_typeahead intent_timer;
  incr intent_generation;
  W.Element.removeAttribute "data-lui-picker-intent" control;
  W.Element.removeAttribute "data-lui-picker-intent-token" control

let reset_picker_intent_later control intent_timer intent_generation =
  cancel_typeahead intent_timer;
  incr intent_generation;
  let token = string_of_int !intent_generation in
  W.Element.setAttribute "data-lui-picker-intent-token" token control;
  intent_timer :=
    Some
      (Js.Global.setTimeout
         ~f:(fun () ->
           intent_timer := None;
           if
             W.Element.getAttribute "data-lui-picker-intent-token" control
             = Some token
           then begin
             W.Element.removeAttribute "data-lui-picker-intent" control;
             W.Element.removeAttribute "data-lui-picker-intent-token" control
           end)
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
        (Lui_sequence.to_list current.retained_children)
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
    W.Element.getAttribute "aria-activedescendant"
      (picker_control_element renderer picker)
  with
  | Some id ->
      let rec find index = function
        | [] -> None
        | item :: rest ->
            if Lui_web_util.node_dom_id item = id then Some index
            else find (index + 1) rest
      in
      find 0 items
  | None -> None

let scroll_picker_item renderer dropdown element =
  let popup =
    Lui_web_util.child_element (Lui_web_nodes.dom_node renderer dropdown) 0
  in
  let bounds = W.Element.getBoundingClientRect popup in
  let item = W.Element.getBoundingClientRect element in
  let top = W.DomRect.top bounds in
  let bottom = W.DomRect.bottom bounds in
  let delta =
    if W.DomRect.top item < top then W.DomRect.top item -. top
    else if W.DomRect.bottom item > bottom then W.DomRect.bottom item -. bottom
    else 0.
  in
  if delta <> 0. then begin
    (* Bounding rectangles include the opening transform, but scrollTop uses
       layout pixels. Convert the visual distance before scrolling. *)
    let layout_height =
      float_of_int
        (W.HtmlElement.offsetHeight (W.Element.unsafeAsHtmlElement popup))
    in
    let visual_height = W.DomRect.height bounds in
    let scale =
      if layout_height > 0. && visual_height > 0. then
        visual_height /. layout_height
      else 1.
    in
    W.Element.setScrollTop popup (W.Element.scrollTop popup +. delta /. scale)
  end

let set_combobox_active renderer picker dropdown index =
  let items = picker_menu_items renderer dropdown in
  let control = picker_control_element renderer picker in
  List.iter
    (fun item ->
      W.Element.removeAttribute "data-highlighted"
        (Lui_web_nodes.dom_node renderer item))
    (Store.children renderer.web_store dropdown);
  W.Element.removeAttribute "data-lui-active-index" control;
  W.Element.removeAttribute "aria-activedescendant" control;
  if items <> [] && index >= 0 && index < List.length items then begin
    let item = List.nth items index in
    let element = Lui_web_nodes.dom_node renderer item in
    W.Element.setAttribute "data-lui-active-index" (string_of_int index)
      control;
    W.Element.setAttribute "data-highlighted" "" element;
    W.Element.setAttribute "aria-activedescendant"
      (Lui_web_util.node_dom_id item) control;
    scroll_picker_item renderer dropdown element
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
              W.Element.setAttribute "role" "option" (Lazy.force current.platform_node);
              W.Element.setAttribute "aria-selected"
                (if
                   Store.property renderer.web_store item Selected
                   = Some (BoolValue true)
                 then "true"
                 else "false")
                (Lazy.force current.platform_node)
            end
            else begin
              W.Element.setAttribute "role" "menuitem" (Lazy.force current.platform_node);
              W.Element.removeAttribute "aria-selected" (Lazy.force current.platform_node)
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
              let root = (Lazy.force current.platform_node) in
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
              if empty then set_combobox_active renderer picker dropdown (-1)
              else begin
                let index =
                  match combobox_active_index renderer picker items with
                  | Some current_index -> current_index
                  | None -> 0
                in
                set_combobox_active renderer picker dropdown index
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

let rec set_dropdown_open renderer node open_ =
  let positioner = Lui_web_nodes.dom_node renderer node in
  let popup = Lui_web_util.child_element positioner 0 in
  if open_ then begin
    W.Element.removeAttribute "inert" popup;
    Lui_web_layers.reconcile_owner renderer.web_layers renderer.web_document
      node
      (match Store.node renderer.web_store node with
       | Some current -> current.retained_parent
       | None -> None);
    Lui_web_layers.open_layer renderer.web_layers renderer.web_document node;
    begin_popup_open popup;
    ignore (Lui_web_position.position_dropdown renderer node);
    Lui_web_position.track renderer node popup
      ~update:(fun () -> Lui_web_position.position_dropdown renderer node)
      ~on_invalid:(fun () -> set_dropdown_open renderer node false)
  end
  else begin
    Lui_web_popup_tracking.stop positioner;
    let token =
      Lui_web_layers.close_layer renderer.web_layers renderer.web_document node
    in
    begin_popup_close popup;
    W.Element.setAttribute "inert" "" popup;
    after_transition renderer.web_document popup 130 true (fun () ->
        if Lui_web_layers.transition renderer.web_layers node = token
           && not (Lui_web_layers.is_open renderer.web_layers node)
        then begin
          W.Element.removeAttribute "data-ending-style" popup;
          Lui_web_layers.finish_present renderer.web_layers
            renderer.web_document node token
        end)
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
                   (Lui_sequence.to_list child_node.retained_children)
          | None -> false)
        (Lui_sequence.to_list current.retained_children)
  | None -> None

let direct_dropdown_menu renderer node =
  match Store.node renderer.web_store node with
  | Some current ->
      child_with_kind renderer (Lui_sequence.to_list current.retained_children) DropdownMenu
  | None -> None

let hide_context_menu renderer =
  match !(renderer.web_open_context_menu) with
  | Some menu ->
      Lui_web_popup_tracking.stop (Lui_web_nodes.dom_node renderer menu);
      let token =
        Lui_web_layers.close_layer renderer.web_layers renderer.web_document
          menu
      in
      W.Element.removeAttribute "data-open"
        (Lui_web_nodes.dom_node renderer menu);
      Lui_web_layers.finish_present renderer.web_layers renderer.web_document
        menu token;
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
        (Lui_sequence.to_list current.retained_children)
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

let show_context_menu renderer menu x y =
  hide_context_menu renderer;
  let menu_node = Lui_web_nodes.dom_node renderer menu in
  W.Element.setAttribute "data-open" "" menu_node;
  Lui_web_layers.reconcile_owner renderer.web_layers renderer.web_document
    menu
    (match Store.node renderer.web_store menu with
     | Some current -> current.retained_parent
     | None -> None);
  Lui_web_layers.open_layer renderer.web_layers renderer.web_document menu;
  renderer.web_open_context_menu := Some menu;
  let update () =
    Lui_web_position.position_at_point renderer.web_document menu_node
      (float_of_int x) (float_of_int y)
  in
  update ();
  (match Store.node renderer.web_store menu with
   | Some current ->
       (match current.retained_parent with
        | Some parent ->
            (match Store.node renderer.web_store parent with
             | Some host ->
                 Lui_web_popup_tracking.start ~document:renderer.web_document
                   ~positioner:menu_node ~popup:menu_node ~anchor:(Lazy.force host.platform_node)
                   ~valid:(fun () ->
                     !(renderer.web_open_context_menu) = Some menu
                     && Store.node renderer.web_store parent <> None
                     && match Store.node renderer.web_store menu with
                        | Some retained -> retained.retained_parent = Some parent
                        | None -> false)
                   ~update ~on_invalid:(fun () ->
                     if !(renderer.web_open_context_menu) = Some menu then
                       hide_context_menu renderer)
             | None -> hide_context_menu renderer)
        | None -> hide_context_menu renderer)
   | None -> ());
  let items = context_menu_focus_items renderer menu in
  if items = [] then
    W.HtmlElement.focus (W.Element.unsafeAsHtmlElement menu_node)
  else focus_context_menu_item renderer menu 0

(* --- picker event wiring --- *)

(* The outermost DropdownMenu containing [node], climbing through
   submenu trigger rows. *)
let rec topmost_dropdown renderer node =
  match Store.node renderer.web_store node with
  | None -> None
  | Some current ->
      (match current.retained_parent with
       | Some parent ->
           (match topmost_dropdown renderer parent with
            | Some _ as top -> top
            | None ->
                if Store.standard_kind_is current DropdownMenu then Some node
                else None)
       | None ->
           if Store.standard_kind_is current DropdownMenu then Some node
           else None)

let attach_picker_press_event renderer node dom_node =
  W.Element.addEventListener "click"
    (fun _event ->
      if Store.event_capability renderer node PressEnabled then begin
        emit renderer (Press node);
        (* Activating an item in a plain dropdown dismisses the whole
           menu, matching base-ui/context-menu behaviour. Picker items
           close through the model and submenu triggers keep the menu
           open, so only MenuItem rows in picker-less menus dismiss. *)
        if
          (match Store.node renderer.web_store node with
           | Some current -> Store.standard_kind_is current MenuItem
           | None -> false)
        then
          (match topmost_dropdown renderer node with
           | Some menu when picker_for_dropdown renderer menu = None -> begin
               emit renderer (Dismiss menu);
               (* Menu-trigger hosts own their dropdown's open state
                   locally, so a model that registers no dismiss handler
                   leaves the layer open — close it directly. *)
               if Lui_web_layers.is_open renderer.web_layers menu then
                 set_dropdown_open renderer menu false
             end
           | _ -> ())
      end)
    dom_node

let attach_picker_press_event_bang = attach_picker_press_event

(* PressDetail for picker triggers: the shared click listener skips these
   kinds (their click is suppressed after a pointer-down open), so the
   detail rides the same branches that emit Press. *)
let picker_emit_press_detail renderer node event =
  let candidate =
    PressDetail (node, Lui_web_util.pointer_detail_of event)
  in
  if
    Store.enabled_node renderer node
    && Store.event_admitted renderer node candidate
  then emit renderer candidate

let attach_picker_trigger_events renderer node dom_node =
  let current_pointer_type = ref "mouse" in
  let suppress_click = ref false in
  let control = picker_control_element renderer node in
  let intent_timer = ref None in
  let intent_generation = ref 0 in
  let previous_cleanup = Hashtbl.find_opt renderer.web_cleanups node in
  let clear_intent () =
    clear_picker_intent control intent_timer intent_generation
  in
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
      suppress_click := false;
      W.Element.setAttribute "data-lui-open-method" method_ dom_node;
      if W.MouseEvent.button (Lui_web_util.pointer_mouse_event event) = 0
      then begin
        let control = picker_control_element renderer node in
        if method_ = "mouse" then begin
          W.Event.preventDefault event;
          suppress_click := true;
          if Store.enabled_node renderer node
             && not (W.Element.isSameNode (W.Element.asNode control) dom_node)
          then Lui_web_util.focus_element control;
          press ();
          picker_emit_press_detail renderer node event
        end
        else if not (W.Element.isSameNode (W.Element.asNode control) dom_node)
        then W.Event.preventDefault event
      end)
    dom_node;
  W.Element.addEventListener "pointercancel"
    (fun _event ->
      suppress_click := false;
      clear_intent ())
    dom_node;
  W.Element.addKeyDownEventListener
    (fun event ->
      suppress_click := false;
      let key = W.KeyboardEvent.key event in
      if Store.enabled_node renderer node
         && Store.event_capability renderer node PressEnabled
         && not (W.KeyboardEvent.isComposing event)
         && not (W.KeyboardEvent.ctrlKey event)
         && not (W.KeyboardEvent.metaKey event)
         && not (W.KeyboardEvent.altKey event)
         && picker_dropdown renderer node = None
         && (key = "ArrowUp" || key = "ArrowDown"
             || (String.length key = 1 && key <> " "))
      then begin
        W.KeyboardEvent.preventDefault event;
        let pending = W.Element.getAttribute "data-lui-picker-intent" control in
        let intent =
          match pending with
          | Some prefix when String.length key = 1
                             && prefix <> "ArrowUp" && prefix <> "ArrowDown" ->
              prefix ^ key
          | _ -> key
        in
        W.Element.setAttribute "data-lui-picker-intent" intent control;
        reset_picker_intent_later control intent_timer intent_generation;
        W.Element.setAttribute "data-lui-open-method" "keyboard" dom_node;
        if pending = None then press ()
      end)
    dom_node;
  W.Element.addEventListener "click"
    (fun event ->
      let keyboard = click_detail event = 0 in
      if !suppress_click && not keyboard then suppress_click := false
      else begin
        suppress_click := false;
        W.Element.setAttribute "data-lui-open-method"
          (if keyboard then "keyboard" else !current_pointer_type) dom_node;
        let control = picker_control_element renderer node in
        if Store.enabled_node renderer node
           && not (W.Element.isSameNode (W.Element.asNode control) dom_node)
        then Lui_web_util.focus_element control;
        press ();
        picker_emit_press_detail renderer node event
      end)
    dom_node;
  Hashtbl.replace renderer.web_cleanups node (fun () ->
      clear_intent ();
      match previous_cleanup with
      | Some cleanup -> cleanup ()
      | None -> ())

let attach_picker_trigger_events_bang = attach_picker_trigger_events

(* --- dropdown event wiring --- *)

(* Nested dropdowns are siblings in the DOM (each gets its own positioner in
   the portal), so a press inside a child submenu is "outside" the parent menu
   and vice versa. The outside-press check has to consider the whole menu
   group: walk up through menu-row parents to the root dropdown, then accept a
   target inside any positioner in that dropdown's subtree. *)
let rec dropdown_group_root renderer current =
  match current.retained_parent with
  | Some parent -> (
      match Store.node renderer.web_store parent with
      | Some parent_node when Store.menu_item_row parent_node -> (
          match parent_node.retained_parent with
          | Some grandparent -> (
              match Store.node renderer.web_store grandparent with
              | Some grandparent_node
                when Store.standard_kind_is grandparent_node DropdownMenu ->
                  dropdown_group_root renderer grandparent_node
              | _ -> current)
          | None -> current)
      | _ -> current)
  | None -> current

let rec group_positioners renderer acc current =
  let acc =
    if Store.standard_kind_is current DropdownMenu then
      (Lazy.force current.platform_node) :: acc
    else acc
  in
  List.fold_left
    (fun acc child ->
      match Store.node renderer.web_store child with
      | Some child_node -> group_positioners renderer acc child_node
      | None -> acc)
    acc (Lui_sequence.to_list current.retained_children)

let dropdown_group_contains_event renderer node event =
  match Store.node renderer.web_store node with
  | Some current ->
      let target =
        Lui_web_util.event_target_to_element (W.Event.target event)
      in
      let group_nodes =
        group_positioners renderer [] (dropdown_group_root renderer current)
      in
      List.exists
        (fun positioner ->
          W.Element.contains (W.Element.asNode target) positioner)
        group_nodes
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

let dismiss_picker renderer node restore =
  (match picker_for_dropdown renderer node with
   | Some picker ->
       W.Element.setAttribute "data-lui-picker-restore"
         (if restore then "true" else "false")
         (picker_control_element renderer picker)
   | None -> ());
  emit renderer (Dismiss node)

let picker_tab renderer node picker event =
  let control = picker_control_element renderer picker in
  (* Resolve the dropdown's DOM before dismissing: emit applies the close
     batch synchronously, which drops the node from the store. *)
  let dropdown_dom = Lui_web_nodes.dom_node renderer node in
  dismiss_picker renderer node false;
  let modal = Lui_web_layers.topmost_blocking renderer.web_layers in
  let roots =
    match modal with
    | Some layer -> Lui_web_layers.focus_roots renderer.web_layers layer.id
    | None -> [W.Document.documentElement renderer.web_document]
  in
  let candidates =
    List.fold_left (fun result root ->
        let nodes = W.Element.querySelectorAll
            "button,input,textarea,select,a[href],[contenteditable],[tabindex]" root in
        let rec collect index result =
          if index = W.NodeList.length nodes then result
          else
            match W.NodeList.item index nodes with
            | Some candidate ->
                (match W.Element.ofNode candidate with
                 | Some element
                   when Lui_web_focus.sequential_focus_target_available element
                        (* The picker's own menu items are reached with
                           arrow keys, not sequential Tab — and the menu
                           they live in is being dismissed anyway. *)
                        && not
                             (W.Element.contains (W.Element.asNode element)
                                dropdown_dom) ->
                     collect (index + 1) (element :: result)
                 | _ -> collect (index + 1) result)
            | None -> collect (index + 1) result
        in
        collect 0 result) [] roots |> List.rev
  in
  let rec find index = function
    | [] -> None
    | element :: rest ->
        if W.Element.isSameNode (W.Element.asNode control) element then Some index
        else find (index + 1) rest
  in
  match find 0 candidates with
  | Some index ->
      let next = index + (if W.KeyboardEvent.shiftKey event then -1 else 1) in
      let count = List.length candidates in
      (* Sequential focus wraps at both ends: out-of-range delegates to the
         browser's own Tab walk, which would restart from the menu item
         that is being dismissed rather than from the picker control. *)
      let next = (next + count) mod count in
      W.KeyboardEvent.preventDefault event;
      Lui_web_util.focus_element (List.nth candidates next)
  | None -> ()

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
  let rec picker_root menu =
    match dropdown_submenu_trigger renderer menu with
    | Some trigger ->
        (match Store.node renderer.web_store trigger with
         | Some current ->
             (match current.retained_parent with
              | Some parent -> picker_root parent
              | None -> menu)
         | None -> menu)
    | None -> menu
  in
  let root = picker_root node in
  if key = "Tab" && picker_for_dropdown renderer root <> None then begin
    match picker_for_dropdown renderer root with
    | Some picker -> picker_tab renderer root picker event
    | None -> ()
  end
  else if key = "Escape" then begin
    W.KeyboardEvent.preventDefault event;
    match submenu_trigger with
    | Some trigger -> close_submenu_to_trigger renderer node trigger
    | None -> dismiss_picker renderer node true
  end
  else if
    key = "ArrowRight" && current_index = None && submenu_trigger <> None
  then begin
    W.KeyboardEvent.preventDefault event;
    focus_context_menu_item renderer node 0
  end
  else if current_index <> None then begin
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
    else if key = "Enter" then begin
      W.KeyboardEvent.preventDefault event;
      match current_index with
      | Some index -> activate_menu_item renderer (List.nth items index)
      | None -> ()
    end
    else if
      String.length key = 1
      && not (W.KeyboardEvent.metaKey event)
      && not (W.KeyboardEvent.ctrlKey event)
      && not (W.KeyboardEvent.altKey event)
      && not (W.KeyboardEvent.isComposing event)
    then
      dropdown_typeahead renderer node typeahead_buffer typeahead_timer
        items current_index key event
  end

let attach_dropdown_events renderer node _dropdown_node =
  let document = renderer.web_document in
  let typeahead_buffer = ref
      (match picker_for_dropdown renderer node with
       | Some picker ->
           (match W.Element.getAttribute "data-lui-picker-intent"
                    (picker_control_element renderer picker) with
            | Some prefix when prefix <> "ArrowUp" && prefix <> "ArrowDown" ->
                String.lowercase_ascii prefix
            | _ -> "")
       | None -> "") in
  let typeahead_timer = ref None in
  if !typeahead_buffer <> "" then
    reset_typeahead_later typeahead_buffer typeahead_timer;
  let key_handler event =
    dropdown_key_handler renderer node typeahead_buffer typeahead_timer event
  in
  let positioner = Lui_web_nodes.dom_node renderer node in
  let popup = Lui_web_util.child_element positioner 0 in
  let owner =
    match Store.node renderer.web_store node with
    | Some current -> current.retained_parent
    | None -> None
  in
  let trigger =
    match picker_for_dropdown renderer node with
    | Some picker ->
        (* The whole picker host counts as the trigger so a combobox's
           chevron button (a sibling of its input control) does not read
           as an outside press that dismisses the layer it just opened. *)
        Some (Lui_web_nodes.dom_node renderer picker)
    | None ->
        (match owner with
         | Some parent ->
             (match Store.node renderer.web_store parent with
              | Some parent_node when Store.menu_item_row parent_node ->
                  Some (Lazy.force parent_node.platform_node)
              | _ -> None)
         | None -> None)
  in
  ignore
    (Lui_web_layers.register renderer.web_layers
       ~document ~id:node ~owner ~trigger ~content:positioner
       ~style_targets:[positioner; popup]
       ~policy:Lui_web_layers.Nonblocking
       ~dismiss:(fun () -> dismiss_picker renderer node false)
       ~close:(fun () -> set_dropdown_open renderer node false)
       ~key_handler ~present:false ~open_:false);
  Hashtbl.replace renderer.web_cleanups node (fun () ->
      cancel_typeahead typeahead_timer;
      Lui_web_popup_tracking.stop positioner;
      if not (Lui_web_layers.is_present renderer.web_layers node) then
        Lui_web_layers.remove renderer.web_layers renderer.web_document node)

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
  let key_handler event =
    context_menu_key_handler renderer document node event
  in
  let click_handler _event = hide_context_menu renderer in
  let owner =
    match Store.node renderer.web_store node with
    | Some current -> current.retained_parent
    | None -> None
  in
  let trigger =
    match owner with
    | Some parent ->
        (match Store.node renderer.web_store parent with
         | Some parent_node -> Some (Lazy.force parent_node.platform_node)
         | None -> None)
    | None -> None
  in
  ignore
    (Lui_web_layers.register renderer.web_layers
       ~document ~id:node ~owner ~trigger ~content:dom_node
       ~style_targets:[dom_node] ~policy:Lui_web_layers.Nonblocking
       ~dismiss:(fun () -> hide_context_menu renderer)
       ~close:(fun () -> hide_context_menu renderer)
       ~key_handler ~present:false ~open_:false);
  W.Element.addEventListener "click" click_handler dom_node;
  Hashtbl.replace renderer.web_cleanups node (fun () ->
      Lui_web_popup_tracking.stop dom_node;
      W.Element.removeEventListener "click" click_handler dom_node;
      if !(renderer.web_open_context_menu) = Some node then
        renderer.web_open_context_menu := None;
      Lui_web_layers.remove renderer.web_layers renderer.web_document node)

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
  let positioner = (Lazy.force current.platform_node) in
  let popup = Lui_web_util.child_element (Lazy.force current.platform_node) 0 in
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
      let positioner = Lui_web_nodes.dom_node renderer node in
      let previous_cleanup = Hashtbl.find_opt renderer.web_cleanups node in
      W.Element.removeAttribute "data-lui-picker-restore" control;
      W.Element.setAttribute "aria-controls" popup_id control;
      (match Store.node renderer.web_store picker with
       | Some picker_node ->
           if Store.standard_kind_is picker_node Combobox then
             after_batch_apply (fun () ->
                 match Store.node renderer.web_store node with
                 | Some menu when menu.retained_parent <> None
                                  && Lui_web_layers.is_open renderer.web_layers node
                                  && Store.node renderer.web_store picker <> None ->
                     refresh_combobox_list_state renderer node
                 | _ -> ())
           else
             after_batch_apply (fun () ->
                 match Store.node renderer.web_store node with
                 | Some menu when menu.retained_parent <> None
                                  && Lui_web_layers.is_open renderer.web_layers node
                                  && Store.node renderer.web_store picker <> None ->
                     let intent = W.Element.getAttribute "data-lui-picker-intent" control in
                     W.Element.removeAttribute "data-lui-picker-intent" control;
                     W.Element.removeAttribute "data-lui-picker-intent-token" control;
                     let items = picker_menu_items renderer node in
                     let rec find predicate index = function
                       | [] -> None
                       | item :: rest ->
                           if predicate item then Some index
                           else find predicate (index + 1) rest
                     in
                     let selected = find (fun item ->
                         Store.property renderer.web_store item Selected
                         = Some (BoolValue true)) 0 items in
                     let index =
                       match intent with
                       | Some prefix when prefix <> "ArrowUp" && prefix <> "ArrowDown" ->
                           (match find (fun item ->
                                starts_with ~prefix:(String.lowercase_ascii prefix)
                                  (String.lowercase_ascii (String.trim
                                     (W.Element.textContent (Lui_web_nodes.dom_node renderer item)))))
                                    0 items with
                            | Some index -> index
                            | None -> Option.value selected ~default:0)
                       | _ -> Option.value selected
                           ~default:(if intent = Some "ArrowUp" then List.length items - 1 else 0)
                     in
                     if items <> [] then focus_context_menu_item renderer node index
                 | _ -> ())
       | None -> ());
      Hashtbl.replace renderer.web_cleanups node (fun () ->
          let restore =
            W.Element.getAttribute "data-lui-picker-restore" control <> Some "false"
          in
          (match previous_cleanup with
           | Some cleanup -> cleanup ()
           | None -> ());
          W.Element.removeAttribute "aria-controls" control;
          W.Element.removeAttribute "data-lui-active-index" control;
          W.Element.removeAttribute "aria-activedescendant" control;
          W.Element.removeAttribute "data-lui-picker-intent" control;
          W.Element.removeAttribute "data-lui-picker-restore" control;
          if restore && Lui_web_focus.focus_target_available control then begin
            let document = W.Document.unsafeAsHtmlDocument renderer.web_document in
            match W.HtmlDocument.activeElement document with
            | Some active when
                W.Element.contains (W.Element.asNode active) positioner
                || Lui_web_focus.document_body_focused renderer ->
                Lui_web_util.focus_element control
            | _ -> ()
          end)
  | None -> ()

(* base-ui parity: a menu opens with an item highlighted and focused
   (useListNavigation's initial sync). A [data-selected] item wins —
   select-style menus reopen on the current value; otherwise the first
   enabled item is highlighted. Items owned by a
   nested submenu (inside a [data-submenu] positioner) and
   [data-menu-tail] items (e.g. a session block appended after the menu
   body mounts) are excluded — cljs-side they mount after the nav list
   syncs, so they never receive the initial highlight; arrow-key
   navigation still reaches them. Deferred to a timeout so it lands
   after the trigger's own click-focus and after the mount batch
   completes. *)
let highlight_initial_menu_item renderer container_id =
  match Store.node renderer.web_store container_id with
  | None -> ()
  | Some container ->
      ignore
        (Js.Global.setTimeout
           ~f:(fun () ->
             (* Closed containers (e.g. a nested submenu that mounts
                eagerly inside an open menu) must not steal focus when a
                parent menu mounts. A dropdown's platform node is its
                positioner; data-open lives on the popup child while the
                menu is presented (menus that are their own popup, e.g.
                context menus, carry it on the node itself). *)
             let presented =
               W.Element.hasAttribute "data-open" (Lazy.force container.platform_node)
               ||
               (match
                  W.HtmlCollection.item 0
                    (W.Element.children (Lazy.force container.platform_node))
                with
                | Some popup -> W.Element.hasAttribute "data-open" popup
                | None -> false)
             in
             (* Submenus (a dropdown nested under a menu row) open on
                hover/focus of their trigger; focusing their items here
                would steal focus from the parent menu's highlighted row.
                Picker dropdowns place initial focus themselves in
                mount_picker_dropdown. *)
             let submenu_or_picker =
               (match container.retained_parent with
                | Some parent ->
                    (match Store.node renderer.web_store parent with
                     | Some parent_node -> Store.menu_item_row parent_node
                     | None -> false)
                | None -> false)
               || picker_for_dropdown renderer container_id <> None
             in
             (* Keyboard input can reach the menu before this deferred
                initialization. Preserve focus already moved into the menu
                or one of its owned portals. *)
             let focus_already_inside =
               let document =
                 W.Document.unsafeAsHtmlDocument renderer.web_document
               in
               match W.HtmlDocument.activeElement document with
               | Some active ->
                   List.exists
                     (fun root ->
                       W.Element.contains (W.Element.asNode active) root)
                     (Lui_web_layers.focus_roots renderer.web_layers
                        container_id)
               | None -> false
             in
             if presented && not submenu_or_picker
                && not focus_already_inside then begin
             let nodes =
               W.Element.querySelectorAll
                 "[role=menuitem]:not([data-disabled]):not([aria-disabled='true']):not([data-menu-tail])"
                 (Lazy.force container.platform_node)
             in
             let n = W.NodeList.length nodes in
             let rec in_submenu element =
               match W.Element.parentElement element with
               | None -> false
               | Some parent ->
                   if
                     W.Element.isSameNode
                       (W.Element.asNode parent)
                       (Lazy.force container.platform_node)
                   then false
                   else
                     (match W.Element.getAttribute "data-submenu" parent with
                      | Some _ -> true
                      | None -> in_submenu parent)
             in
             let rec collect index acc =
               if index < 0 then acc
               else
                 collect (index - 1)
                   (match W.NodeList.item index nodes with
                    | Some item -> (
                        match W.Element.ofNode item with
                        | Some element ->
                            if in_submenu element then acc else element :: acc
                        | None -> acc)
                    | None -> acc)
             in
             let items = collect (n - 1) [] in
             (match items with
              | [] -> ()
              | _ ->
                  List.iter
                    (fun element ->
                      W.Element.removeAttribute "data-highlighted" element;
                      W.Element.setAttribute "tabindex" "-1" element)
                    items;
                  let target =
                    match
                      List.find_opt
                        (fun element ->
                          W.Element.getAttribute "data-selected" element
                          <> None)
                        items
                    with
                    | Some element -> element
                    (* items is collected in DOM order; with no selected
                       row the highlight lands on the first item. *)
                    | None -> List.hd items
                  in
                  W.Element.setAttribute "data-highlighted" "" target;
                  W.Element.setAttribute "tabindex" "0" target;
                  Lui_web_util.focus_element_without_scroll target)
             end)
           0)

let mount_dropdown renderer node =
  match Store.node renderer.web_store node with
  | Some current ->
      let popup = Lui_web_util.child_element (Lazy.force current.platform_node) 0 in
      let listbox = Lui_web_nodes.dropdown_listbox renderer node in
      W.Element.setAttribute "role"
        (if listbox then "listbox" else "menu")
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
                  (* Submenus mount eagerly inside their parent menu and
                     open later on hover/focus; the generic highlight must
                     not steal focus from the parent menu's items. Keyboard
                     entry (ArrowRight) focuses the first item directly. *)
                  ignore
                    (attach_submenu_hover renderer node current
                       (Lazy.force parent_node.platform_node))
                else begin
                  (* Picker dropdowns place initial focus themselves
                     (mount_picker_dropdown lands on the selected item); the
                     generic highlight would race it and read stale
                     selection state. *)
                  if not listbox && picker_for_dropdown renderer node = None
                  then highlight_initial_menu_item renderer node;
                  mount_picker_dropdown renderer node
                end
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
                     (Lazy.force current.platform_node)
               | Some Combobox ->
                   W.Element.setAttribute "aria-expanded"
                     (if expanded then "true" else "false")
                     (Lui_web_util.child_element (Lazy.force current.platform_node) 0)
               | _ -> ())
          | None -> ())
        (Lui_sequence.to_list parent_node.retained_children)
  | None -> ()

let update_picker_expanded_bang = update_picker_expanded

let remove_dropdown_after_exit renderer node parent positioner =
  if not (Lui_web_layers.is_present renderer.web_layers node) then begin
    match W.Element.parentElement positioner with
    | Some actual_parent ->
        ignore
          (W.Element.removeChild (W.Element.asNode positioner) actual_parent)
    | None -> ()
  end else begin
    let popup = Lui_web_util.child_element positioner 0 in
    let token =
      Lui_web_layers.close_layer renderer.web_layers renderer.web_document node
    in
    begin_popup_close popup;
    W.Element.setAttribute "inert" "" popup;
    after_transition renderer.web_document popup 130 true (fun () ->
        if
          Lui_web_layers.transition renderer.web_layers node = token
          && not (Lui_web_layers.is_open renderer.web_layers node)
        then begin
          if W.Element.contains (W.Element.asNode positioner) parent then
            ignore
              (W.Element.removeChild (W.Element.asNode positioner) parent);
          Lui_web_layers.finish_present renderer.web_layers
            renderer.web_document node token;
          if Store.node renderer.web_store node = None then
            Lui_web_layers.remove renderer.web_layers renderer.web_document node
        end)
  end

(* --- popover --- *)

let popover_positioned renderer node =
  match Store.property renderer.web_store node AnchorValue with
  | Some (StringValue _) -> true
  | _ -> false

let attach_popover_events renderer node _popover_node =
  let document = renderer.web_document in
  let positioner = Lui_web_nodes.dom_node renderer node in
  let popup = Lui_web_util.child_element positioner 0 in
  let owner =
    match Store.node renderer.web_store node with
    | Some current -> current.retained_parent
    | None -> None
  in
  ignore
    (Lui_web_layers.register renderer.web_layers
       ~document ~id:node ~owner ~trigger:None ~content:positioner
       ~style_targets:[positioner; popup]
       ~policy:Lui_web_layers.Nonblocking
       ~dismiss:(fun () -> emit renderer (Dismiss node))
       ~close:(fun () -> ())
       ~key_handler:(fun _event -> ())
       ~present:false ~open_:false);
  Hashtbl.replace renderer.web_cleanups node (fun () ->
      Lui_web_popup_tracking.stop positioner;
      if not (Lui_web_layers.is_present renderer.web_layers node) then
        Lui_web_layers.remove renderer.web_layers renderer.web_document node)

let attach_popover_events_bang = attach_popover_events

let mount_popover renderer node =
  match Store.node renderer.web_store node with
  | Some current ->
      let positioner = (Lazy.force current.platform_node) in
      let popup = Lui_web_util.child_element positioner 0 in
      W.Element.setAttribute "id"
        (Lui_web_util.node_dom_id node ^ "-popup") popup;
      if Store.property renderer.web_store node PopupX = None
         && Store.property renderer.web_store node AnchorValue = None
      then W.Element.setAttribute "data-cover" "" positioner;
      W.Element.removeAttribute "inert" popup;
      Lui_web_layers.reconcile_owner renderer.web_layers
        renderer.web_document node current.retained_parent;
      Lui_web_layers.open_layer renderer.web_layers renderer.web_document
        node;
      begin_popup_open popup;
      Lui_web_position.position_popover renderer node;
      if popover_positioned renderer node then
        Lui_web_position.track renderer node popup
          ~update:(fun () -> Lui_web_position.position_popover renderer node)
          ~on_invalid:(fun () ->
            Lui_web_util.set_state_attribute positioner "hidden" true);
      if
        Store.property renderer.web_store node RoleValue
        = Some (StringValue "menu")
      then highlight_initial_menu_item renderer node
  | None -> invalid_arg "unknown popover node"

let mount_popover_bang = mount_popover

let remove_popover_after_exit renderer node parent positioner =
  if not (Lui_web_layers.is_present renderer.web_layers node) then begin
    match W.Element.parentElement positioner with
    | Some actual_parent ->
        ignore
          (W.Element.removeChild (W.Element.asNode positioner) actual_parent)
    | None -> ()
  end else begin
    let popup = Lui_web_util.child_element positioner 0 in
    let token =
      Lui_web_layers.close_layer renderer.web_layers renderer.web_document
        node
    in
    begin_popup_close popup;
    W.Element.setAttribute "inert" "" popup;
    after_transition renderer.web_document popup 130 true (fun () ->
        if
          Lui_web_layers.transition renderer.web_layers node = token
          && not (Lui_web_layers.is_open renderer.web_layers node)
        then begin
          if W.Element.contains (W.Element.asNode positioner) parent then
            ignore
              (W.Element.removeChild (W.Element.asNode positioner) parent);
          Lui_web_layers.finish_present renderer.web_layers
            renderer.web_document node token;
          if Store.node renderer.web_store node = None then
            Lui_web_layers.remove renderer.web_layers renderer.web_document
              node
        end)
  end

let remove_popover_after_exit_bang = remove_popover_after_exit
