(* DOM application of retained patch batches — port of web.cljc apply-dom-op. *)

open Lui_protocol
open Lui_web_types
module W = Webapi.Dom
module Store = Lui_web_store
module Nodes = Lui_web_nodes
module Util = Lui_web_util
module Ext = Lui_web_extensions

external element_is_connected : W.Element.t -> bool = "isConnected"
  [@@mel.get]

let prev_node previous_nodes node_id = previous_nodes node_id

let prev_kind_is previous_nodes node_id expected =
  match prev_node previous_nodes node_id with
  | Some current -> Store.standard_kind_is current expected
  | None -> false

let prev_modal previous_nodes node_id =
  match prev_node previous_nodes node_id with
  | Some current -> (
      match Store.standard_kind current with
      | Some kind -> modal_surface kind
      | None -> false)
  | None -> false

let prev_anchored_tooltip previous_nodes node_id =
  match prev_node previous_nodes node_id with
  | Some current -> Store.anchored_tooltip current
  | None -> false

let retained_content_container current dom_node =
  match Store.standard_kind current with
  | Some kind -> Util.content_container kind dom_node
  | None -> dom_node

let dom_child_container renderer node dom_node =
  match Store.node renderer.web_store node with
  | Some current -> retained_content_container current dom_node
  | None -> dom_node

let dom_child_container_before renderer previous_nodes node dom_node =
  match Store.node renderer.web_store node with
  | Some current -> retained_content_container current dom_node
  | None -> (
      match prev_node previous_nodes node with
      | Some previous -> retained_content_container previous dom_node
      | None -> dom_node)

let portal_parent renderer previous_nodes parent child =
  if prev_kind_is previous_nodes child Toast then renderer.web_toast_viewport
  else if
    prev_kind_is previous_nodes child DropdownMenu
    || prev_kind_is previous_nodes child Popover
    || prev_modal previous_nodes child
    || prev_anchored_tooltip previous_nodes child
  then renderer.web_portal_root
  else if prev_kind_is previous_nodes child ContextMenu then
    renderer.web_portal_root
  else
    dom_child_container_before renderer previous_nodes parent
      (Nodes.dom_node_before renderer previous_nodes parent)

let cleanup_node renderer node =
  Lui_web_events.release_pointer_events renderer node;
  match Hashtbl.find_opt renderer.web_cleanups node with
  | Some cleanup ->
      cleanup ();
      Hashtbl.remove renderer.web_cleanups node
  | None -> ()

(* a retained child only advances the DOM insertion index when its
   platform node is a DOM child of the container right now — portal
   children (menus, modals, toasts), never-mounted segments and nodes
   dropped inside the same batch all sit outside it and must be skipped *)
let child_counted_in_container child container =
  match child.platform_node |> W.Element.parentElement with
  | Some actual -> actual == container
  | None -> false

(* Growable int buffer. Append is amortized O(1); the visible-child prefix
   is filled once per child so repeated inserts into one parent stay linear. *)
type int_buf = {mutable data : int array; mutable len : int}

let int_buf_create capacity =
  {data = Array.make (max 4 capacity) 0; len = 0}

let int_buf_ensure buf extra =
  if buf.len + extra > Array.length buf.data then begin
    let next_len = max (buf.len + extra) (Array.length buf.data * 2) in
    let next = Array.make next_len 0 in
    Array.blit buf.data 0 next 0 buf.len;
    buf.data <- next
  end

let int_buf_push buf value =
  int_buf_ensure buf 1;
  buf.data.(buf.len) <- value;
  buf.len <- buf.len + 1

let int_buf_insert buf index value =
  let index = if index < 0 then 0 else if index > buf.len then buf.len else index in
  int_buf_ensure buf 1;
  Array.blit buf.data index buf.data (index + 1) (buf.len - index);
  buf.data.(index) <- value;
  buf.len <- buf.len + 1

let int_buf_remove_at buf index =
  Array.blit buf.data (index + 1) buf.data index (buf.len - index - 1);
  buf.len <- buf.len - 1

let int_buf_index buf value =
  let rec loop index =
    if index >= buf.len then None
    else if buf.data.(index) = value then Some index
    else loop (index + 1)
  in
  loop 0

type child_shadow = {
  items : int_buf;
  prefix : int_buf;
  mutable prefix_filled : int;
  mutable prefix_container : W.Element.t option;
}

let shadow_of_list children =
  let items = int_buf_create (List.length children) in
  List.iter (int_buf_push items) children;
  let prefix = int_buf_create 1 in
  int_buf_push prefix 0;
  {items; prefix; prefix_filled = 1; prefix_container = None}

let shadow_invalidate shadow index =
  if shadow.prefix_filled > index + 1 then shadow.prefix_filled <- index + 1

let shadow_insert shadow index child =
  int_buf_insert shadow.items index child;
  shadow_invalidate shadow index

let shadow_ids shadow =
  Array.sub shadow.items.data 0 shadow.items.len |> Array.to_list

let shadow_remove shadow child =
  match int_buf_index shadow.items child with
  | None -> ()
  | Some index ->
      int_buf_remove_at shadow.items index;
      shadow_invalidate shadow index

let visible_child_index renderer ~container ~children index =
  let reset =
    match children.prefix_container with
    | Some previous when previous == container -> false
    | _ -> true
  in
  if reset then begin
    children.prefix.len <- 0;
    int_buf_push children.prefix 0;
    children.prefix_filled <- 1;
    children.prefix_container <- Some container
  end;
  let index =
    if index < 0 then 0
    else if index > children.items.len then children.items.len
    else index
  in
  while children.prefix_filled <= index do
    let slot = children.prefix_filled - 1 in
    let child = children.items.data.(slot) in
    let previous = children.prefix.data.(slot) in
    let counted =
      match Store.node renderer.web_store child with
      | Some child_node -> child_counted_in_container child_node container
      | None -> false
    in
    int_buf_push children.prefix (previous + if counted then 1 else 0);
    children.prefix_filled <- children.prefix_filled + 1
  done;
  children.prefix.data.(index)

let focused_descendant renderer dom_node =
  let document =
    W.Document.unsafeAsHtmlDocument renderer.web_document
  in
  match W.HtmlDocument.activeElement document with
  | Some focused ->
      if W.Element.contains (W.Element.asNode focused) dom_node then
        Some focused
      else None
  | None -> None

let refresh_structured_children renderer parent =
  match Store.node renderer.web_store parent with
  | Some current -> (
      match Store.standard_kind current with
      | Some Stepper -> Lui_web_widgets.update_stepper renderer parent
      | Some Timeline -> Lui_web_widgets.update_timeline renderer parent
      | _ -> ())
  | None -> ()

let refresh_dropdown_parent renderer parent =
  match Store.node renderer.web_store parent with
  | Some parent_node ->
      if Store.standard_kind_is parent_node DropdownMenu then begin
        Lui_web_menu.refresh_dropdown_item_roles renderer parent;
        ignore (Lui_web_menu.refresh_combobox_list_state renderer parent)
      end
  | None -> ()

let refresh_parent_for_prop renderer node property =
  match Store.node renderer.web_store node with
  | Some current -> (
      match current.retained_parent with
      | Some parent -> (
          if property = MinWidth then
            Lui_web_split.update_split renderer parent;
          match Store.node renderer.web_store parent with
          | Some parent_node ->
              if
                Store.standard_kind_is parent_node Tabs
                && (property = Selected || property = Enabled)
              then
                Lui_web_focus.refresh_tabs_roving renderer.web_store
                  renderer.web_document parent;
              if
                Store.standard_kind_is parent_node BottomTabs
                && (property = Selected || property = Enabled)
              then Lui_web_widgets.refresh_bottom_tabs renderer parent;
              if Store.standard_kind_is parent_node DropdownMenu then
                ignore
                  (Lui_web_menu.refresh_combobox_list_state renderer parent)
          | None -> ())
      | None -> ())
  | None -> ()

let apply_create renderer node kind =
  let created = Nodes.dom_node renderer node in
  (* the store already holds this batch's `as` prop at DOM-apply time, so a
     phrasing kind created with an override tag gets swapped before the id
     and event wiring below are attached. *)
  let created =
    match
      Store.node renderer.web_store node
      |> Option.map (fun current ->
             Property_map.find_opt As current.retained_properties)
    with
    | Some (Some (StringValue tag)) -> (
        match Nodes.retag renderer node tag with
        | Some next -> next
        | None -> created)
    | _ -> created
  in
  W.Element.setAttribute "id" (Util.node_dom_id node) created;
  if kind = Accordion then Util.initialize_accordion_semantics node created;
  if kind = ViewThatFits then Lui_web_fit.attach renderer node created;
  Lui_web_events.attach_events renderer node kind created

(* The nearest ancestor that forms a popup container, returned as
   (container_node_id, container_role). Menu items are often nested inside
   box wrappers (e.g. a cm entry box), so the direct parent kind alone is
   not enough — walk up to the container node. *)
let rec popup_container renderer node_id =
  match Store.node renderer.web_store node_id with
  | Some current -> (
      match Store.standard_kind current with
      | Some ContextMenu -> Some (node_id, `Menu)
      | Some DropdownMenu ->
          if Nodes.dropdown_listbox renderer node_id then
            Some (node_id, `Listbox)
          else Some (node_id, `Menu)
      | Some Popover -> (
          (* a popover is a menu container only when ~role:`menu was
             passed (RoleValue "menu"); otherwise it is a plain panel *)
          match Store.property renderer.web_store node_id RoleValue with
          | Some (StringValue "menu") -> Some (node_id, `Menu)
          | _ -> None)
      | _ -> (
          match current.retained_parent with
          | Some parent -> popup_container renderer parent
          | None -> None))
  | None -> None

let insert_menu_item_role renderer _child current parent =
  if Store.menu_item_row current then
    match popup_container renderer parent with
    | Some (container_id, `Menu) ->
        W.Element.setAttribute "role" "menuitem" current.platform_node;
        W.Element.setAttribute "tabindex" "-1" current.platform_node;
        W.Element.removeAttribute "aria-selected" current.platform_node;
        Lui_web_menu.highlight_initial_menu_item renderer container_id
    | _ -> ()

(* a child removed or reparented by a later op in the same batch has no
   mount to perform — its wiring belongs to the parent it ends under *)
let mount_inserted_child renderer parent child current =
  if current.retained_parent = Some parent then
    match Store.standard_kind current with
  | Some Radio -> Lui_web_focus.update_radio_group renderer child
  | Some DropdownMenu ->
      (match current.retained_parent with
       | Some parent ->
           Lui_web_menu.update_picker_expanded renderer parent true
       | None -> ());
      Lui_web_menu.mount_dropdown renderer child
  | Some Popover -> Lui_web_menu.mount_popover renderer child
  | Some (Dialog | Sheet) ->
      Lui_web_overlay.open_modal renderer child current.platform_node
  | Some Tooltip ->
      if Store.anchored_tooltip current then
        Lui_web_overlay.mount_tooltip renderer child current.platform_node
  | Some Toast ->
      Lui_web_overlay.mount_toast renderer child current.platform_node
  | _ -> ()

let insert_child_dom renderer previous_nodes children_of parent child
    index =
  let parent_dom = Nodes.dom_node_before renderer previous_nodes parent in
  let child_dom = Nodes.dom_node_before renderer previous_nodes child in
  match Store.node renderer.web_store child with
  | None ->
      (* dropped again inside this batch — insert anyway so the later
         remove op finds the element where the op stream put it *)
      Util.insert_dom_child parent_dom child_dom index
  | Some current -> (
      match Store.standard_kind current with
      | Some BottomTab -> (
          match Store.node renderer.web_store parent with
          | Some parent_node
            when Store.standard_kind_is parent_node BottomTabs ->
              Util.insert_dom_child
                (Util.bottom_tabs_pages_node parent_dom) child_dom index;
              ignore
                (Lui_web_widgets.create_bottom_tab_trigger renderer parent
                   child index);
              Lui_web_widgets.refresh_bottom_tabs renderer parent
          | _ ->
              let container =
                dom_child_container renderer parent parent_dom
              in
              Util.insert_dom_child container child_dom
                (visible_child_index renderer ~container
                   ~children:(children_of parent) index))
      | Some Toast ->
          W.Element.appendChild (W.Element.asNode child_dom)
            renderer.web_toast_viewport
      | Some DropdownMenu | Some Popover ->
          W.Element.appendChild (W.Element.asNode child_dom)
            renderer.web_portal_root
      | Some Tooltip when Store.anchored_tooltip current ->
          W.Element.appendChild (W.Element.asNode child_dom)
            renderer.web_portal_root
      | Some kind when modal_surface kind ->
          W.Element.appendChild
            (W.Element.asNode (Util.modal_layer_node child_dom))
            renderer.web_portal_root
      | Some ContextMenu ->
          W.Element.appendChild (W.Element.asNode child_dom)
            renderer.web_portal_root
      | Some (SwipeActions | SwipeAction) -> ()
      | _ ->
          let container =
            dom_child_container renderer parent parent_dom
          in
          Util.insert_dom_child container child_dom
            (visible_child_index renderer ~container
               ~children:(children_of parent) index))

let apply_insert_child renderer previous_nodes children_of parent child
    index =
  insert_child_dom renderer previous_nodes children_of parent child index;
  Lui_web_split.update_split renderer parent;
  Lui_web_focus.refresh_button_context renderer child;
  refresh_structured_children renderer parent;
  (match Store.node renderer.web_store child with
   | Some current ->
       insert_menu_item_role renderer child current parent;
       mount_inserted_child renderer parent child current;
       Lui_web_layers.reconcile_owner renderer.web_layers
         renderer.web_document child current.retained_parent
   | None -> ());
  refresh_dropdown_parent renderer parent

let remove_bottom_tab renderer parent child =
  let tabs_dom = Nodes.dom_node renderer parent in
  let pages = Util.bottom_tabs_pages_node tabs_dom in
  let bar = Util.bottom_tabs_bar_node tabs_dom in
  let child_dom = Nodes.dom_node renderer child in
  if W.Element.contains (W.Element.asNode child_dom) pages then
    ignore (W.Element.removeChild (W.Element.asNode child_dom) pages);
  match
    W.Element.querySelector ("#" ^ Util.bottom_tab_trigger_id child) bar
  with
  | Some trigger ->
      ignore (W.Element.removeChild (W.Element.asNode trigger) bar)
  | None -> ()

let clear_submenu_trigger _renderer previous_nodes parent =
  match prev_node previous_nodes parent with
  | Some parent_node ->
      if Store.menu_item_row parent_node then begin
        W.Element.removeAttribute "data-submenu-trigger"
          parent_node.platform_node;
        W.Element.removeAttribute "aria-haspopup" parent_node.platform_node;
        W.Element.removeAttribute "aria-expanded" parent_node.platform_node
      end
  | None -> ()

let apply_remove_child renderer previous_nodes parent child =
  let surface = Nodes.dom_node_before renderer previous_nodes child in
  let modal = prev_modal previous_nodes child in
  let bottom_tab = prev_kind_is previous_nodes child BottomTab in
  let bottom_tabs = prev_kind_is previous_nodes parent BottomTabs in
  let child_node =
    if modal then Util.modal_layer_node surface else surface
  in
  let parent_node = portal_parent renderer previous_nodes parent child in
  (if bottom_tab && bottom_tabs then remove_bottom_tab renderer parent child
   else if modal then
     match prev_node previous_nodes child with
     | Some previous ->
           ignore
             (Lui_web_overlay.remove_modal_layer_after_exit
              renderer child parent_node child_node surface
              (Store.standard_kind previous))
     | None -> ()
   else if prev_kind_is previous_nodes child DropdownMenu then
     Lui_web_menu.remove_dropdown_after_exit renderer child parent_node
       child_node
   else if prev_kind_is previous_nodes child Popover then
     Lui_web_menu.remove_popover_after_exit renderer child parent_node
       child_node
   else (
     (* parent_node is re-resolved from the previous snapshot and can be
        stale for portal-rendered children; remove from the actual DOM
        parent instead *)
     match W.Element.parentElement child_node with
     | Some actual_parent ->
         (* a child inside an already-detached subtree leaves the
            document with its ancestor — skipping that detach keeps
            outside element references (captured nodes) intact *)
         if element_is_connected actual_parent then
           ignore
             (W.Element.removeChild
                (W.Element.asNode child_node) actual_parent)
     | None -> ()));
  Lui_web_focus.refresh_button_context renderer child;
  refresh_structured_children renderer parent;
  (match prev_node previous_nodes parent with
   | Some parent_node ->
       if Store.standard_kind_is parent_node BottomTabs then
         Lui_web_widgets.refresh_bottom_tabs renderer parent
   | None -> ());
  (match prev_node previous_nodes child with
   | Some previous ->
       if Store.standard_kind_is previous DropdownMenu then begin
         Lui_web_menu.update_picker_expanded renderer parent false;
         clear_submenu_trigger renderer previous_nodes parent
       end
   | None -> ());
  refresh_dropdown_parent renderer parent

let move_bottom_tab renderer parent child index =
  let tabs_dom = Nodes.dom_node renderer parent in
  let pages = Util.bottom_tabs_pages_node tabs_dom in
  let bar = Util.bottom_tabs_bar_node tabs_dom in
  let child_node = Nodes.dom_node renderer child in
  if W.Element.contains (W.Element.asNode child_node) pages then
    ignore (W.Element.removeChild (W.Element.asNode child_node) pages);
  Util.insert_dom_child pages child_node index;
  match Lui_web_widgets.bottom_tab_trigger renderer child with
  | Some trigger ->
      if W.Element.contains (W.Element.asNode trigger) bar then
        ignore (W.Element.removeChild (W.Element.asNode trigger) bar);
      Util.insert_dom_child bar trigger index
  | None -> ()

let apply_move_child renderer previous_nodes children_of parent child
    index =
  let dropdown = prev_kind_is previous_nodes child DropdownMenu in
  let modal = prev_modal previous_nodes child in
  let tooltip = prev_anchored_tooltip previous_nodes child in
  let toast = prev_kind_is previous_nodes child Toast in
  let metadata = prev_kind_is previous_nodes child ContextMenu in
  let swipe_meta =
    prev_kind_is previous_nodes child SwipeActions
    || prev_kind_is previous_nodes child SwipeAction
  in
  let bottom_tab =
    match Store.node renderer.web_store child with
    | Some current -> Store.standard_kind_is current BottomTab
    | None -> false
  in
  let bottom_tabs =
    match Store.node renderer.web_store parent with
    | Some current -> Store.standard_kind_is current BottomTabs
    | None -> false
  in
  let parent_node = portal_parent renderer previous_nodes parent child in
  let surface_node = Nodes.dom_node_before renderer previous_nodes child in
  let child_node =
    if modal then Util.modal_layer_node surface_node else surface_node
  in
  let focused = focused_descendant renderer surface_node in
  if bottom_tab && bottom_tabs then move_bottom_tab renderer parent child index
  else begin
    (* the resolved parent can be stale for portal children; detach via the
       actual DOM parent *)
    (match W.Element.parentElement child_node with
     | Some actual_parent ->
         ignore
           (W.Element.removeChild
              (W.Element.asNode child_node) actual_parent)
     | None -> ());
    if swipe_meta then ()
    else if dropdown || modal || tooltip || toast || metadata then
      W.Element.appendChild (W.Element.asNode child_node) parent_node
    else
      Util.insert_dom_child parent_node child_node
        (visible_child_index renderer ~container:parent_node
           ~children:(children_of parent) index)
  end;
  Lui_web_split.update_split renderer parent;
  refresh_structured_children renderer parent;
  if bottom_tab && bottom_tabs then
    Lui_web_widgets.refresh_bottom_tabs renderer parent;
  refresh_dropdown_parent renderer parent;
  if dropdown then Lui_web_position.position_dropdown renderer child;
  if tooltip && W.Element.hasAttribute "data-open" surface_node then
    Lui_web_position.position_tooltip renderer child;
  (match Store.node renderer.web_store child with
   | Some current ->
       Lui_web_layers.reconcile_owner renderer.web_layers
         renderer.web_document child current.retained_parent
   | None -> ());
  Lui_web_focus.restore_focus renderer focused

let apply_set_prop renderer node property value =
  match Store.node renderer.web_store node with
  | Some current -> (
      match Store.standard_kind current with
      | Some kind ->
          (match property with
           | As -> (
               (* a mid-life tag change replaces the element, which drops
                  listeners — clean up first, then re-attach onto the new
                  element. *)
               match value with
               | StringValue tag -> (
                   match Nodes.retag renderer node tag with
                   | Some next ->
                       cleanup_node renderer node;
                       Lui_web_events.attach_events renderer node kind next
                   | None -> ())
               | _ -> ())
           | _ ->
               Lui_web_props.apply_property renderer node kind
                 current.platform_node property value);
          if property = PointerEnabled then
            Lui_web_events.sync_pointer_events renderer node kind
              current.platform_node;
          refresh_parent_for_prop renderer node property
      | None -> invalid_arg "standard property targets extension node")
  | None -> ()

let apply_remove_prop renderer node property =
  (match Store.node renderer.web_store node with
   | Some current -> (
       match Store.standard_kind current with
       | Some kind ->
           (match property with
            | As -> (
                match Nodes.retag renderer node (Nodes.simple_node_tag kind) with
                | Some next ->
                    cleanup_node renderer node;
                    Lui_web_events.attach_events renderer node kind next
                | None -> ())
            | _ ->
                Lui_web_props.remove_property renderer node kind
                  current.platform_node property);
           if property = PointerEnabled then
             Lui_web_events.sync_pointer_events renderer node kind
               current.platform_node;
           refresh_parent_for_prop renderer node property
       | None -> invalid_arg "standard property targets extension node")
   | None -> ())

(* A node created and dropped inside the same batch never reaches the DOM:
   the store already reflects the batch's final state, so ops that mention it
   have no element to act on and are skipped. *)
let known_node renderer previous_nodes node =
  match Store.node renderer.web_store node with
  | Some _ -> true
  | None -> prev_node previous_nodes node <> None

(* detach-subtree replaces the per-node remove/drop op pair for a whole
   removed subtree: one pass unmounts every member — layer registrations,
   extension resources, registered cleanups — and removes the elements
   mounted outside the detaching parent chain (portal members, modal
   layer shells, bottom-tab triggers). Members inside the subtree leave
   the document with their ancestor's detach; only elements whose actual
   parent is still connected get removed here. A departing popup root keeps
   its visual subtree until its existing exit transition completes. *)
let apply_detach_subtree renderer previous_nodes children_of node =
  let exit_boundary =
    match prev_node previous_nodes node with
    | Some previous
      when Lui_web_layers.is_present renderer.web_layers node
           && (prev_modal previous_nodes node
               || Store.standard_kind_is previous DropdownMenu
               || Store.standard_kind_is previous Popover) ->
        (match previous.retained_parent with
         | Some parent ->
             let boundary =
               if prev_modal previous_nodes node then
                 Util.modal_layer_node previous.platform_node
               else previous.platform_node
             in
             apply_remove_child renderer previous_nodes parent node;
             Some boundary
         | None -> None)
    | _ -> None
  in
  let retained_for_exit element =
    match exit_boundary with
    | Some boundary ->
        W.Element.contains (W.Element.asNode element) boundary
    | None -> false
  in
  let detach_element node_id =
    match prev_node previous_nodes node_id with
    | Some previous ->
        let surface = previous.platform_node in
        let target =
          if prev_modal previous_nodes node_id then
            Util.modal_layer_node surface
          else surface
        in
        (match W.Element.parentElement target with
         | Some actual_parent ->
             if element_is_connected actual_parent
                && not (retained_for_exit target) then
               ignore
                 (W.Element.removeChild
                    (W.Element.asNode target) actual_parent)
         | None -> ())
    | None ->
        (* a member created inside this batch has no pre-batch record but
           a portal-mounted element can still sit outside the subtree *)
        (match
           W.Document.getElementById (Util.node_dom_id node_id)
             renderer.web_document
         with
         | Some element ->
             (match W.Element.parentElement element with
              | Some actual_parent ->
                  if element_is_connected actual_parent
                     && not (retained_for_exit element) then
                    ignore
                      (W.Element.removeChild
                         (W.Element.asNode element) actual_parent)
              | None -> ())
         | None -> ())
  in
  let detach_bottom_tab_trigger node_id =
    if prev_kind_is previous_nodes node_id BottomTab then
      match prev_node previous_nodes node_id with
      | Some previous ->
          (match previous.retained_parent with
           | Some parent when prev_kind_is previous_nodes parent BottomTabs ->
               (match prev_node previous_nodes parent with
                | Some tabs_node ->
                    let bar =
                      Util.bottom_tabs_bar_node tabs_node.platform_node
                    in
                    (match
                       W.Element.querySelector
                         ("#" ^ Util.bottom_tab_trigger_id node_id) bar
                     with
                     | Some trigger when not (retained_for_exit trigger) ->
                         ignore
                           (W.Element.removeChild
                              (W.Element.asNode trigger) bar)
                     | Some _ | None -> ())
                | None -> ())
           | _ -> ())
      | None -> ()
  in
  let rec visit node_id =
    (* Outside an exiting popup, the root leaves first so member parents
       read disconnected and skip their own detach. The exit callback owns
       the root layer registration until it removes the retained visuals. *)
    (if (node_id <> node || exit_boundary = None)
        && Lui_web_layers.layer_at renderer.web_layers node_id <> None then
       Lui_web_layers.remove renderer.web_layers renderer.web_document
         node_id);
    detach_element node_id;
    detach_bottom_tab_trigger node_id;
    Ext.cleanup_extension_node renderer previous_nodes node_id;
    cleanup_node renderer node_id;
    List.iter visit (shadow_ids (children_of node_id))
  in
  visit node;
  (* parent-side follow-ups mirror apply_remove_child *)
  match (exit_boundary, prev_node previous_nodes node) with
  | None, Some previous ->
      (match previous.retained_parent with
       | Some parent ->
           Lui_web_focus.refresh_button_context renderer parent;
           refresh_structured_children renderer parent;
           (match prev_node previous_nodes parent with
            | Some parent_node ->
                if Store.standard_kind_is parent_node BottomTabs then
                  Lui_web_widgets.refresh_bottom_tabs renderer parent
            | None -> ());
           (if Store.standard_kind_is previous DropdownMenu then begin
              Lui_web_menu.update_picker_expanded renderer parent false;
              clear_submenu_trigger renderer previous_nodes parent
            end);
           refresh_dropdown_parent renderer parent
       | None -> ())
  | _ -> ()

let apply_dom_op renderer previous_nodes children_of operation =
  match operation with
  | CreateNode (node, kind) ->
      if Store.node renderer.web_store node <> None then
        apply_create renderer node kind
  | CreateExtension (node, _identifier, _fingerprint) -> (
      match Store.node renderer.web_store node with
      | Some current ->
          W.Element.setAttribute "id" (Util.node_dom_id node)
            current.platform_node
      | None -> ())
  | DropNode node ->
      if known_node renderer previous_nodes node then begin
        Ext.cleanup_extension_node renderer previous_nodes node;
        cleanup_node renderer node
      end
  | DetachSubtree node ->
      if known_node renderer previous_nodes node then
        apply_detach_subtree renderer previous_nodes children_of node
  | SetProp (node, property, value) ->
      apply_set_prop renderer node property value
  | RemoveProp (node, property) -> apply_remove_prop renderer node property
  | SetExtensionProp (node, property, value) ->
      Ext.apply_extension_property renderer node property value
  | RemoveExtensionProp (node, property) ->
      Ext.remove_extension_property renderer node property
  | InsertChild (parent, child, index) ->
      if
        known_node renderer previous_nodes parent
        && known_node renderer previous_nodes child
      then
        apply_insert_child renderer previous_nodes children_of parent
          child index
  | RemoveChild (parent, child) ->
      if
        known_node renderer previous_nodes parent
        && known_node renderer previous_nodes child
      then apply_remove_child renderer previous_nodes parent child
  | MoveChild (parent, child, index) ->
      if
        known_node renderer previous_nodes parent
        && known_node renderer previous_nodes child
      then
        apply_move_child renderer previous_nodes children_of parent
          child index
(* DOM ops run after the whole store batch has landed, so
   `retained_children` already reflects every op in the batch; sibling ops
   earlier in the batch need the children list as of their own position,
   so structural ops replay onto a shadow seeded from the pre-batch
   snapshot *)
let apply_dom_batch renderer previous_nodes batch =
  let shadow = Hashtbl.create 16 in
  let children_of parent =
    match Hashtbl.find_opt shadow parent with
    | Some children -> children
    | None ->
        let children =
          match prev_node previous_nodes parent with
          | Some node -> shadow_of_list node.retained_children
          | None -> shadow_of_list []
        in
        Hashtbl.replace shadow parent children;
        children
  in
  let mirror operation =
    match operation with
    | InsertChild (parent, child, index) ->
        shadow_insert (children_of parent) index child
    | RemoveChild (parent, child) -> shadow_remove (children_of parent) child
    | DetachSubtree node -> (
        match prev_node previous_nodes node with
        | Some previous -> (
            match previous.retained_parent with
            | Some parent -> shadow_remove (children_of parent) node
            | None -> ())
        | None -> ())
    | MoveChild (parent, child, index) ->
        let children = children_of parent in
        shadow_remove children child;
        shadow_insert children index child
    | _ -> ()
  in
  List.iter
    (fun operation ->
       mirror operation;
       try apply_dom_op renderer previous_nodes children_of operation
       with Invalid_argument msg ->
         invalid_arg
           (Printf.sprintf "op %s: %s" (Lui_wire.encode_op operation) msg))
    batch.ops;
  (* Refresh roving tabindex only on groups this batch could have changed,
     walking from each touched id to the nearest tree, toolbar, or
     horizontal group instead of scanning the whole store. *)
  let touched = Hashtbl.create 16 in
  let note id = Hashtbl.replace touched id () in
  List.iter
    (fun operation ->
       match operation with
       | CreateNode (id, _)
       | CreateExtension (id, _, _)
       | DropNode id
       | DetachSubtree id
       | SetProp (id, _, _)
       | RemoveProp (id, _)
       | SetExtensionProp (id, _, _)
       | RemoveExtensionProp (id, _) ->
         note id
       | InsertChild (parent, child, _)
       | RemoveChild (parent, child)
       | MoveChild (parent, child, _) ->
         note parent;
         note child)
    batch.ops;
  let refreshed = Hashtbl.create 8 in
  let refresh id kind =
    if not (Hashtbl.mem refreshed id) then begin
      Hashtbl.replace refreshed id ();
      if kind = Tree then Lui_web_focus.update_tree_roving renderer id
      else if kind = Toolbar then
        ignore (Lui_web_focus.refresh_toolbar_roving renderer id)
      else if Lui_web_focus.horizontal_focus_kind kind then
        ignore (Lui_web_focus.refresh_horizontal_group_roving renderer id kind)
    end
  in
  let visited = Hashtbl.create 16 in
  let rec climb id =
    if Hashtbl.mem visited id then ()
    else begin
      Hashtbl.replace visited id ();
      match Store.node renderer.web_store id with
      | Some current ->
          (match Store.standard_kind current with
           | Some kind -> refresh id kind
           | None -> ());
          (match current.retained_parent with
           | Some parent -> climb parent
           | None -> ())
      | None -> (
          match prev_node previous_nodes id with
          | Some previous -> (
              match previous.retained_parent with
              | Some parent -> climb parent
              | None -> ())
          | None -> ())
    end
  in
  Hashtbl.iter (fun id () -> climb id) touched
