(* Keyboard focus, roving tabindex, and typeahead for the LUI web DOM
   backend. Port of web.cljc ranges 1339-1652, 1802-1827, 2430-2805,
   4712-4815, 5823-5842 — see PORTING.md. *)

open Lui_protocol
open Lui_web_types

module W = Webapi.Dom
module Store = Lui_web_store
module Util = Lui_web_util

let standard_kind_strict current =
  match Store.standard_kind current with
  | Some kind -> kind
  | None -> invalid_arg "expected standard DOM node"

let tree_ancestor = Store.tree_ancestor

let tree_items_under renderer parent =
  let children node =
    match Hashtbl.find_opt renderer.web_virtual_lists node with
    | Some state -> state.virtual_live_rows ()
    | None -> Store.children renderer.web_store node
  in
  let rec collect items child =
    match Store.node renderer.web_store child with
    | Some current when Lazy.is_val current.platform_node ->
        let items = if Store.treeitem renderer child then child :: items else items in
        List.fold_left collect items (children child)
    | _ -> items
  in
  List.rev (List.fold_left collect [] (children parent))

let tree_focus_items_under renderer parent =
  List.filter
    (fun node -> Store.enabled_node renderer node)
    (tree_items_under renderer parent)

let rec derived_tree_item_level renderer tree current level =
  match Store.node renderer.web_store current with
  | Some state ->
      (match state.retained_parent with
       | Some parent ->
           if parent = tree then level
           else
             derived_tree_item_level renderer tree parent
               (if Store.treeitem renderer parent then level + 1 else level)
       | None -> level)
  | None -> level

let tree_item_level renderer tree node =
  match Store.property renderer.web_store node TreeLevel with
  | Some (IntValue level) -> level
  | _ -> derived_tree_item_level renderer tree node 1

let node_index nodes node =
  let rec loop index = function
    | [] -> -1
    | item :: rest -> if item = node then index else loop (index + 1) rest
  in
  loop 0 nodes

let logical_tree_parent renderer tree items node =
  let index = node_index items node in
  let level = tree_item_level renderer tree node in
  let rec loop candidate =
    if candidate < 0 then None
    else
      let candidate_node = List.nth items candidate in
      if tree_item_level renderer tree candidate_node = level - 1 then
        Some candidate_node
      else loop (candidate - 1)
  in
  loop (index - 1)

let logical_tree_child renderer tree items node =
  let index = node_index items node in
  let next_index = index + 1 in
  if next_index < List.length items then
    let candidate = List.nth items next_index in
    if
      tree_item_level renderer tree candidate
      = tree_item_level renderer tree node + 1
    then Some candidate
    else None
  else None

let set_tree_tabstop renderer items target =
  List.iter
    (fun item ->
       W.Element.setAttribute "tabindex"
         (if item = target then "0" else "-1")
         (Lui_web_nodes.dom_node renderer item))
    items

let set_tree_tabstop_bang = set_tree_tabstop

let dispatch_tree_selection renderer node =
  ignore
    (!(renderer.web_event_handler)
       (if Store.event_capability renderer node ChangeEnabled then Change node
        else Press node))

let dispatch_tree_selection_bang = dispatch_tree_selection

let focus_tree_item renderer _tree items node =
  set_tree_tabstop renderer items node;
  W.HtmlElement.focus
    (W.Element.unsafeAsHtmlElement (Lui_web_nodes.dom_node renderer node));
  dispatch_tree_selection renderer node

let focus_tree_item_bang = focus_tree_item

let refresh_tree_item_accessibility renderer tree node =
  let element = Lui_web_nodes.dom_node renderer node in
  W.Element.setAttribute "aria-level"
    (string_of_int (tree_item_level renderer tree node))
    element;
  W.Element.setAttribute "aria-disabled"
    (if Store.enabled_node renderer node then "false" else "true")
    element;
  (match Store.property renderer.web_store node Selected with
   | Some (BoolValue selected) ->
       W.Element.setAttribute "aria-selected"
         (if selected then "true" else "false") element
   | _ -> W.Element.removeAttribute "aria-selected" element);
  match Store.property renderer.web_store node Expanded with
  | Some (BoolValue expanded) ->
      W.Element.setAttribute "aria-expanded"
        (if expanded then "true" else "false") element
  | _ -> W.Element.removeAttribute "aria-expanded" element

let refresh_tree_item_accessibility_bang = refresh_tree_item_accessibility

let rec focused_child_index renderer children focused index =
  if index >= List.length children then None
  else if
    W.Element.isSameNode
      (W.Element.asNode
         (Lui_web_nodes.dom_node renderer (List.nth children index)))
      focused
  then Some index
  else focused_child_index renderer children focused (index + 1)

let update_tree_roving renderer tree =
  let all_items = tree_items_under renderer tree in
  let items = tree_focus_items_under renderer tree in
  List.iter
    (fun item ->
       refresh_tree_item_accessibility renderer tree item;
       W.Element.setAttribute "tabindex" "-1"
         (Lui_web_nodes.dom_node renderer item))
    all_items;
  if items <> [] then begin
    let selected =
      let rec loop index =
        if index = List.length items then List.hd items
        else
          let item = List.nth items index in
          if
            Store.property renderer.web_store item Selected
            = Some (BoolValue true)
          then item
          else loop (index + 1)
      in
      loop 0
    in
    let document =
      W.Document.unsafeAsHtmlDocument renderer.web_document
    in
    let active_index =
      match W.HtmlDocument.activeElement document with
      | Some focused -> focused_child_index renderer items focused 0
      | None -> None
    in
    let target =
      match active_index with
      | Some index -> List.nth items index
      | None -> selected
    in
    set_tree_tabstop renderer items target
  end

let update_tree_roving_bang = update_tree_roving

let update_all_tree_roving renderer =
  Hashtbl.iter
    (fun node current ->
       if Store.standard_kind_is current Tree then
         update_tree_roving renderer node)
    (Store.nodes renderer.web_store);
  true

let update_all_tree_roving_bang = update_all_tree_roving

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

let tree_item_keydown_target items index key =
  if key = "ArrowUp" then
    if index > 0 then Some (List.nth items (index - 1)) else None
  else if key = "ArrowDown" then
    if index + 1 < List.length items then
      Some (List.nth items (index + 1))
    else None
  else if key = "Home" then Some (List.nth items 0)
  else if key = "End" then
    Some (List.nth items (List.length items - 1))
  else None

let attach_tree_item_events renderer node kind element =
  (if kind <> ListItem then
     W.Element.addEventListener "click"
       (fun (_event : Dom.event) ->
          if
            Store.treeitem renderer node
            && Store.event_capability renderer node PressEnabled
          then ignore (!(renderer.web_event_handler) (Press node)))
       element);
  W.Element.addKeyDownEventListener
    (fun (event : Dom.keyboardEvent) ->
       if Store.treeitem renderer node then
         match Store.tree_ancestor renderer node with
         | Some tree ->
             let items = tree_focus_items_under renderer tree in
             let index = node_index items node in
             let key = W.KeyboardEvent.key event in
             (match tree_item_keydown_target items index key with
              | Some target_node ->
                  W.KeyboardEvent.preventDefault event;
                  focus_tree_item renderer tree items target_node
              | None ->
                  if key = "ArrowLeft" then begin
                    W.KeyboardEvent.preventDefault event;
                    if
                      Store.property renderer.web_store node Expanded
                      = Some (BoolValue true)
                      && Store.event_capability renderer node ToggleEnabled
                    then
                      ignore
                        (!(renderer.web_event_handler)
                           (ToggleChanged (node, false)))
                    else
                      match
                        logical_tree_parent renderer tree items node
                      with
                      | Some parent ->
                          focus_tree_item renderer tree items parent
                      | None -> ()
                  end
                  else if key = "ArrowRight" then begin
                    W.KeyboardEvent.preventDefault event;
                    if
                      Store.property renderer.web_store node Expanded
                      = Some (BoolValue false)
                      && Store.event_capability renderer node ToggleEnabled
                    then
                      ignore
                        (!(renderer.web_event_handler)
                           (ToggleChanged (node, true)))
                    else
                      match
                        logical_tree_child renderer tree items node
                      with
                      | Some child ->
                          focus_tree_item renderer tree items child
                      | None -> ()
                  end
                  else if
                    kind <> ListItem && (key = "Enter" || key = " ")
                  then begin
                    W.KeyboardEvent.preventDefault event;
                    if Store.event_capability renderer node PressEnabled
                    then ignore (!(renderer.web_event_handler) (Press node))
                  end)
         | None -> ())
    element

let attach_tree_item_events_bang = attach_tree_item_events

let typeahead_key_handler renderer tree typeahead_buffer typeahead_timer
    event =
  let key = W.KeyboardEvent.key event in
  if
    String.length key = 1
    && String.trim key <> ""
    && not (W.KeyboardEvent.isComposing event)
    && not (W.KeyboardEvent.metaKey event)
    && not (W.KeyboardEvent.ctrlKey event)
    && not (W.KeyboardEvent.altKey event)
  then begin
    let items = tree_focus_items_under renderer tree in
    let document =
      W.Document.unsafeAsHtmlDocument renderer.web_document
    in
    let current_index =
      match W.HtmlDocument.activeElement document with
      | Some focused -> focused_child_index renderer items focused 0
      | None -> None
    in
    let query =
      String.lowercase_ascii (!typeahead_buffer ^ key)
    in
    let start =
      match current_index with Some index -> index | None -> -1
    in
    typeahead_buffer := query;
    reset_typeahead_later typeahead_buffer typeahead_timer;
    let rec loop offset =
      if offset <= List.length items then begin
        let index = (start + offset) mod List.length items in
        let item = List.nth items index in
        let label =
          String.lowercase_ascii
            (String.trim
               (W.Element.textContent
                  (Lui_web_nodes.dom_node renderer item)))
        in
        if String.starts_with ~prefix:query label then begin
          W.KeyboardEvent.preventDefault event;
          focus_tree_item renderer tree items item
        end
        else loop (offset + 1)
      end
    in
    loop 1
  end

let attach_tree_events renderer tree tree_node =
  let typeahead_buffer = ref "" in
  let typeahead_timer = ref None in
  let key_handler event =
    typeahead_key_handler renderer tree typeahead_buffer typeahead_timer
      event
  in
  W.Element.addKeyDownEventListener key_handler tree_node;
  Hashtbl.replace renderer.web_cleanups tree (fun () ->
      cancel_typeahead typeahead_timer;
      W.Element.removeKeyDownEventListener key_handler tree_node)

let attach_tree_events_bang = attach_tree_events

let document_body_focused renderer =
  let document =
    W.Document.unsafeAsHtmlDocument renderer.web_document
  in
  match W.HtmlDocument.activeElement document with
  | Some focused ->
      (match W.HtmlDocument.body document with
       | Some body ->
           W.Element.isSameNode (W.Element.asNode body) focused
       | None -> false)
  | None -> false

let css_hidden element =
  let document =
    W.Node.ownerDocument (W.Element.asNode element)
  in
  let html_document = W.Document.unsafeAsHtmlDocument document in
  match W.HtmlDocument.defaultView html_document with
  | Some window ->
      let style = W.Window.getComputedStyle element window in
      W.CssStyleDeclaration.display style = "none"
      || W.CssStyleDeclaration.visibility style = "hidden"
      || W.CssStyleDeclaration.visibility style = "collapse"
  | None -> false

let attribute_int element name =
  match W.Element.getAttribute name element with
  | Some value ->
      (try Some (int_of_string (String.trim value)) with _ -> None)
  | None -> None

let explicitly_focusable element =
  let tag = String.lowercase_ascii (W.Element.tagName element) in
  let contenteditable =
    match W.Element.getAttribute "contenteditable" element with
    | Some value -> String.lowercase_ascii value <> "false"
    | None -> false
  in
  match attribute_int element "tabindex" with
  | Some _ -> true
  | None ->
      (tag = "button" || tag = "input" || tag = "select"
       || tag = "textarea")
      || (tag = "a" && W.Element.hasAttribute "href" element)
      || contenteditable

let focus_target_available element =
  let tag = String.lowercase_ascii (W.Element.tagName element) in
  let input_hidden =
    tag = "input"
    &&
    match W.Element.getAttribute "type" element with
    | Some value -> String.lowercase_ascii value = "hidden"
    | None -> false
  in
  let rec visible current =
    let unavailable =
      W.Element.hasAttribute "hidden" current
      || W.Element.hasAttribute "inert" current
      || W.Element.hasAttribute "disabled" current
      || W.Element.getAttribute "aria-hidden" current = Some "true"
      || W.Element.getAttribute "aria-disabled" current = Some "true"
      || W.Element.matches ":disabled" current
      || css_hidden current
    in
    if unavailable then false
    else
      match W.Element.parentElement current with
      | Some parent -> visible parent
      | None -> W.Element.tagName current = "HTML"
  in
  not input_hidden && explicitly_focusable element && visible element

let sequential_focus_target_available element =
  if not (focus_target_available element) then false
  else
    match attribute_int element "tabindex" with
    | Some index -> index >= 0
    | None -> true

let restore_focus renderer focused =
  match focused with
  | Some element when focus_target_available element ->
      Util.focus_element element;
      ignore
        (Js.Global.setTimeout
           ~f:(fun () ->
             if document_body_focused renderer
                && focus_target_available element
             then
               Util.focus_element element)
           0)
  | None -> ()
  | Some _ -> ()

let restore_focus_if_unmoved renderer ~closing focused =
  match focused with
  | Some element when focus_target_available element ->
      let document =
        W.Document.unsafeAsHtmlDocument renderer.web_document
      in
      let active = W.HtmlDocument.activeElement document in
      let moved_inside =
        match active with
        | Some current ->
            W.Element.contains (W.Element.asNode current) closing
        | None -> false
      in
      if document_body_focused renderer || moved_inside then
        restore_focus renderer (Some element)
  | _ -> ()

let restore_focus_bang = restore_focus

let horizontal_group_child group_kind child_kind =
  match group_kind with
  | Tabs -> child_kind = Button
  | ButtonGroup | ToggleGroup ->
      child_kind = Button || child_kind = ToggleButton
  | Breadcrumb | Pagination -> child_kind = Button
  | _ -> false

let horizontal_group_child_ = horizontal_group_child

let horizontal_all_focus_children renderer node kind =
  List.filter
    (fun child ->
       match Store.node renderer.web_store child with
       | Some current ->
           (match Store.standard_kind current with
            | Some child_kind -> horizontal_group_child kind child_kind
            | None -> false)
       | None -> false)
    (Store.children renderer.web_store node)

let horizontal_focus_children renderer node kind =
  List.filter
    (fun child -> Store.enabled_node renderer child)
    (horizontal_all_focus_children renderer node kind)

let rec horizontal_tab_stop_index renderer children index =
  if index >= List.length children then None
  else if
    W.Element.getAttribute "tabindex"
      (Lui_web_nodes.dom_node renderer (List.nth children index))
    = Some "0"
  then Some index
  else horizontal_tab_stop_index renderer children (index + 1)

let horizontal_focus_index key current length =
  if length = 0 then None
  else
    match key with
    | "Home" -> Some 0
    | "End" -> Some (length - 1)
    | "ArrowRight" ->
        (match current with
         | Some index -> Some ((index + 1) mod length)
         | None -> Some 0)
    | "ArrowLeft" ->
        (match current with
         | Some index -> Some ((index + length - 1) mod length)
         | None -> Some 0)
    | _ -> None

let element_direction renderer element =
  let document =
    W.Document.unsafeAsHtmlDocument renderer.web_document
  in
  match W.HtmlDocument.defaultView document with
  | Some window ->
      W.CssStyleDeclaration.direction
        (W.Window.getComputedStyle element window)
  | None -> "ltr"

let refresh_horizontal_group_roving renderer node kind =
  let all_children = horizontal_all_focus_children renderer node kind in
  let children = horizontal_focus_children renderer node kind in
  let document =
    W.Document.unsafeAsHtmlDocument renderer.web_document
  in
  let focused_index =
    match W.HtmlDocument.activeElement document with
    | Some focused -> focused_child_index renderer children focused 0
    | None -> None
  in
  let target =
    match focused_index with
    | Some index -> index
    | None ->
        (match horizontal_tab_stop_index renderer children 0 with
         | Some index -> index
         | None -> 0)
  in
  List.iter
    (fun child ->
       W.Element.setAttribute "tabindex" "-1"
         (Lui_web_nodes.dom_node renderer child))
    all_children;
  (match children with
   | [] -> ()
   | _ ->
       W.Element.setAttribute "tabindex" "0"
         (Lui_web_nodes.dom_node renderer (List.nth children target)));
  true

let refresh_horizontal_group_roving_bang = refresh_horizontal_group_roving

let horizontal_focus_kind kind =
  kind = Tabs || kind = ButtonGroup || kind = ToggleGroup
  || kind = Breadcrumb || kind = Pagination

let update_all_horizontal_group_roving renderer =
  Hashtbl.iter
    (fun node current ->
       match Store.standard_kind current with
       | Some kind ->
           if horizontal_focus_kind kind then
             ignore (refresh_horizontal_group_roving renderer node kind)
       | None -> ())
    (Store.nodes renderer.web_store);
  true

let update_all_horizontal_group_roving_bang =
  update_all_horizontal_group_roving

let horizontal_navigation_key key orientation direction =
  let forward_key =
    if orientation = "vertical" then "ArrowDown"
    else if direction = "rtl" then "ArrowLeft"
    else "ArrowRight"
  in
  let backward_key =
    if orientation = "vertical" then "ArrowUp"
    else if direction = "rtl" then "ArrowRight"
    else "ArrowLeft"
  in
  ( forward_key
  , backward_key
  , if key = forward_key then "ArrowRight"
    else if key = backward_key then "ArrowLeft"
    else if key = "Home" then "Home"
    else if key = "End" then "End"
    else "" )

let attach_horizontal_focus renderer node kind group_node =
  W.Element.addFocusInEventListener
    (fun (_event : Dom.focusEvent) ->
       ignore (refresh_horizontal_group_roving renderer node kind))
    group_node;
  W.Element.addKeyDownEventListener
    (fun (event : Dom.keyboardEvent) ->
       if
         not
           (Store.node_has_ancestor_kind renderer.web_store node Toolbar)
       then begin
         let key = W.KeyboardEvent.key event in
         let orientation =
           if kind = Tabs then
             match
               Store.property renderer.web_store node OrientationValue
             with
             | Some (StringValue value) -> value
             | _ -> "horizontal"
           else "horizontal"
         in
         let direction = element_direction renderer group_node in
         let _forward_key, _backward_key, navigation_key =
           horizontal_navigation_key key orientation direction
         in
         let children = horizontal_focus_children renderer node kind in
         let document =
           W.Document.unsafeAsHtmlDocument renderer.web_document
         in
         let current =
           match W.HtmlDocument.activeElement document with
           | Some focused ->
               focused_child_index renderer children focused 0
           | None -> None
         in
         match
           horizontal_focus_index navigation_key current
             (List.length children)
         with
         | Some index ->
             W.KeyboardEvent.preventDefault event;
             W.HtmlElement.focus
               (W.Element.unsafeAsHtmlElement
                  (Lui_web_nodes.dom_node renderer
                     (List.nth children index)))
         | None -> ()
       end)
    group_node

let attach_horizontal_focus_bang = attach_horizontal_focus

let toolbar_item_kind kind =
  kind = Button || kind = ToggleButton || kind = Toggle
  || kind = Checkbox || kind = SwitchControl || kind = Radio
  || kind = Select || kind = Combobox || kind = TextField
  || kind = SecureField || kind = Input || kind = SearchField

let toolbar_item_kind_ = toolbar_item_kind

let toolbar_all_items_under renderer parent =
  let rec collect items child =
    match Store.node renderer.web_store child with
    | Some current ->
        if toolbar_item_kind (standard_kind_strict current) then
          child :: items
        else
          List.fold_left collect items
            (Store.children renderer.web_store child)
    | None -> items
  in
  List.rev
    (List.fold_left collect []
       (Store.children renderer.web_store parent))

let toolbar_items_under renderer parent =
  toolbar_all_items_under renderer parent

let toolbar_focus_node store node =
  match Store.node store node with
  | Some current ->
      let kind = standard_kind_strict current in
      if Store.direct_toggle kind || kind = Combobox then
        Util.child_element (Lazy.force current.platform_node) 0
      else (Lazy.force current.platform_node)
  | None -> invalid_arg "unknown toolbar item"

let apply_toolbar_disabled_semantics renderer item =
  (match Store.node renderer.web_store item with
   | Some current ->
       let kind = standard_kind_strict current in
       let platform_node = Lui_web_nodes.dom_node renderer item in
       let focus_node =
         if Store.direct_toggle kind || kind = Combobox then
           Util.child_element platform_node 0
         else platform_node
       in
       if Store.enabled_node renderer item then begin
         W.Element.removeAttribute "aria-disabled" focus_node;
         W.Element.removeAttribute "data-disabled" focus_node
       end
       else begin
         W.Element.removeAttribute "disabled" focus_node;
         W.Element.setAttribute "aria-disabled" "true" focus_node;
         W.Element.setAttribute "data-disabled" "" focus_node
       end
   | None -> ());
  true

let apply_toolbar_disabled_semantics_bang =
  apply_toolbar_disabled_semantics

let toolbar_text_input_kind kind =
  kind = TextField || kind = SecureField || kind = Input
  || kind = SearchField || kind = Combobox

let rec focused_toolbar_item_index store items focused index =
  if index >= List.length items then None
  else if
    W.Element.isSameNode
      (W.Element.asNode (toolbar_focus_node store (List.nth items index)))
      focused
  then Some index
  else focused_toolbar_item_index store items focused (index + 1)

let toolbar_input_owns_key store item event forward_key backward_key =
  match Store.node store item with
  | Some current ->
      if toolbar_text_input_kind (standard_kind_strict current) then
        let control = Util.text_control_node (Lazy.force current.platform_node) in
        let start = W.HtmlInputElement.selectionStart control in
        let finish = W.HtmlInputElement.selectionEnd control in
        let length =
          String.length (W.HtmlInputElement.value control)
        in
        let key = W.KeyboardEvent.key event in
        W.KeyboardEvent.isComposing event
        || W.KeyboardEvent.shiftKey event
        || W.KeyboardEvent.ctrlKey event
        || W.KeyboardEvent.altKey event
        || W.KeyboardEvent.metaKey event
        || start <> finish
        || (key = forward_key && finish < length)
        || (key = backward_key && start > 0)
        || (length > 0 && (key = "Home" || key = "End"))
      else false
  | None -> false

let select_toolbar_input store item =
  match Store.node store item with
  | Some current ->
      if toolbar_text_input_kind (standard_kind_strict current) then
        let control = Util.text_control_node (Lazy.force current.platform_node) in
        W.HtmlInputElement.setSelectionRange 0
          (String.length (W.HtmlInputElement.value control)) control
  | None -> ()

let refresh_toolbar_roving renderer toolbar =
  let all_items = toolbar_all_items_under renderer toolbar in
  let items = toolbar_items_under renderer toolbar in
  let document =
    W.Document.unsafeAsHtmlDocument renderer.web_document
  in
  let active =
    match W.HtmlDocument.activeElement document with
    | Some focused ->
        focused_toolbar_item_index renderer.web_store items focused 0
    | None -> None
  in
  let target = match active with Some index -> index | None -> 0 in
  List.iter
    (fun item ->
       ignore (apply_toolbar_disabled_semantics renderer item);
       W.Element.setAttribute "tabindex" "-1"
         (toolbar_focus_node renderer.web_store item))
    all_items;
  List.iteri
    (fun index item ->
       W.Element.setAttribute "tabindex"
         (if index = target then "0" else "-1")
         (toolbar_focus_node renderer.web_store item))
    items;
  true

let refresh_toolbar_roving_bang = refresh_toolbar_roving

let update_all_toolbar_roving renderer =
  Hashtbl.iter
    (fun node current ->
       if Store.standard_kind_is current Toolbar then
         ignore (refresh_toolbar_roving renderer node))
    (Store.nodes renderer.web_store);
  true

let update_all_toolbar_roving_bang = update_all_toolbar_roving

let attach_toolbar_events renderer node toolbar_node =
  W.Element.addFocusInEventListener
    (fun (_event : Dom.focusEvent) ->
       let items = toolbar_items_under renderer node in
       let document =
         W.Document.unsafeAsHtmlDocument renderer.web_document
       in
       match W.HtmlDocument.activeElement document with
       | Some focused ->
           (match
              focused_toolbar_item_index renderer.web_store items
                focused 0
            with
            | Some index ->
                ignore (refresh_toolbar_roving renderer node);
                select_toolbar_input renderer.web_store
                  (List.nth items index)
            | None -> ())
       | None -> ())
    toolbar_node;
  W.Element.addKeyDownEventListener
    (fun (event : Dom.keyboardEvent) ->
       let key = W.KeyboardEvent.key event in
       let orientation =
         match Store.property renderer.web_store node OrientationValue with
         | Some (StringValue value) -> value
         | _ -> "horizontal"
       in
       let direction = element_direction renderer toolbar_node in
       let forward_key, backward_key, navigation_key =
         horizontal_navigation_key key orientation direction
       in
       let items = toolbar_items_under renderer node in
       let document =
         W.Document.unsafeAsHtmlDocument renderer.web_document
       in
       let current =
         match W.HtmlDocument.activeElement document with
         | Some focused ->
             focused_toolbar_item_index renderer.web_store items
               focused 0
         | None -> None
       in
       if
         navigation_key <> ""
         && not
              (match current with
               | Some index ->
                   toolbar_input_owns_key renderer.web_store
                     (List.nth items index) event forward_key backward_key
               | None -> false)
       then
         match
           horizontal_focus_index navigation_key current
             (List.length items)
         with
         | Some index ->
             W.KeyboardEvent.preventDefault event;
             W.HtmlElement.focus
               (W.Element.unsafeAsHtmlElement
                  (toolbar_focus_node renderer.web_store
                     (List.nth items index)))
         | None -> ())
    toolbar_node

let attach_toolbar_events_bang = attach_toolbar_events

let direct_tab_trigger renderer node =
  match Store.node renderer.web_store node with
  | Some current ->
      Store.standard_kind_is current Button
      &&
      (match current.retained_parent with
       | Some parent ->
           (match Store.node renderer.web_store parent with
            | Some parent_node ->
                Store.standard_kind_is parent_node Tabs
            | None -> false)
       | None -> false)
  | None -> false

let direct_tab_trigger_ = direct_tab_trigger

let refresh_tabs_roving store document tabs =
  let all_children =
    List.filter
      (fun child ->
         match Store.node store child with
         | Some current -> Store.standard_kind_is current Button
         | None -> false)
      (Store.children store tabs)
  in
  let children =
    List.filter
      (fun child ->
         Store.property store child Enabled <> Some (BoolValue false))
      all_children
  in
  let html_document = W.Document.unsafeAsHtmlDocument document in
  let active =
    match W.HtmlDocument.activeElement html_document with
    | Some focused ->
        let rec loop index =
          if index >= List.length children then None
          else
            match Store.node store (List.nth children index) with
            | Some current ->
                if
                  W.Element.isSameNode
                    (W.Element.asNode (Lazy.force current.platform_node)) focused
                then Some index
                else loop (index + 1)
            | None -> loop (index + 1)
        in
        loop 0
    | None -> None
  in
  let selected =
    let rec loop index =
      if index >= List.length children then 0
      else if
        Store.property store (List.nth children index) Selected
        = Some (BoolValue true)
      then index
      else loop (index + 1)
    in
    loop 0
  in
  let target =
    match active with Some index -> index | None -> selected
  in
  List.iter
    (fun child ->
       match Store.node store child with
       | Some current ->
           W.Element.setAttribute "tabindex" "-1" (Lazy.force current.platform_node)
       | None -> ())
    all_children;
  List.iteri
    (fun index child ->
       match Store.node store child with
       | Some current ->
           W.Element.setAttribute "tabindex"
             (if index = target then "0" else "-1")
             (Lazy.force current.platform_node)
       | None -> ())
    children

let refresh_tabs_roving_bang = refresh_tabs_roving

let refresh_button_context renderer node =
  match Store.node renderer.web_store node with
  | Some current ->
      if Store.standard_kind_is current Button then begin
        let element = (Lazy.force current.platform_node) in
        let selected = Store.selected_property renderer node in
        if direct_tab_trigger renderer node then begin
          W.Element.setAttribute "role" "tab" element;
          W.Element.setAttribute "aria-selected"
            (if selected then "true" else "false") element;
          W.Element.removeAttribute "aria-pressed" element;
          match current.retained_parent with
          | Some parent ->
              refresh_tabs_roving renderer.web_store
                renderer.web_document parent
          | None -> ()
        end
        else begin
          W.Element.removeAttribute "role" element;
          W.Element.removeAttribute "aria-selected" element;
          match Store.property renderer.web_store node Selected with
          | Some (BoolValue _) ->
              W.Element.setAttribute "aria-pressed"
                (if selected then "true" else "false") element
          | _ -> W.Element.removeAttribute "aria-pressed" element
        end
      end
  | None -> ()

let refresh_button_context_bang = refresh_button_context

let rec radio_group_ancestor renderer node =
  match Store.node renderer.web_store node with
  | Some current ->
      (match current.retained_parent with
       | Some parent ->
           (match Store.node renderer.web_store parent with
            | Some parent_node ->
                if Store.standard_kind_is parent_node RadioGroup then
                  Some parent
                else radio_group_ancestor renderer parent
            | None -> None)
       | None -> None)
  | None -> None

let update_radio_group renderer node =
  match radio_group_ancestor renderer node with
  | Some group ->
      W.Element.setAttribute "name"
        ("lui-radio-group-" ^ string_of_int group)
        (Util.child_element (Lui_web_nodes.dom_node renderer node) 0)
  | None -> ()

let update_radio_group_bang = update_radio_group
