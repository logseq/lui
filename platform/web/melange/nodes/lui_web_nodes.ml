(* Element factories and DOM lookups for the LUI web (DOM) backend.
   Ported from web.cljc: base-class table, create_* factories, platform_node,
   dom_node lookups, and the dropdown anchor helpers. *)

open Lui_protocol
open Lui_web_types

module W = Webapi.Dom
module Store = Lui_web_store
module Util = Lui_web_util

let base_class_name kind =
  match kind with
  | Root -> "lui-root"
  | Row -> "lui-row"
  | Column -> "lui-column"
  | Grid -> "lui-grid"
  | Stack -> "lui-stack"
  | Panel -> "lui-panel"
  | Card -> "lui-card"
  | Alert -> "lui-alert"
  | Bubble -> "lui-bubble"
  | Box -> "lui-box"
  | Text -> "lui-text"
  | Heading -> "lui-heading"
  | Paragraph -> "lui-paragraph"
  | Label -> "lui-label"
  | Button -> "lui-button"
  | ToggleButton -> "lui-button lui-toggle-button"
  | Toggle -> "lui-toggle"
  | RadioGroup -> "lui-radio-group"
  | Radio -> "lui-radio"
  | Slider -> "lui-slider"
  | TextField -> "lui-text-field"
  | SecureField -> "lui-text-field"
  | Input -> "lui-input"
  | SearchField -> "lui-search-field"
  | Textarea -> "lui-textarea"
  | Checkbox -> "lui-checkbox"
  | SwitchControl -> "lui-switch"
  | Progress -> "lui-progress"
  | Divider -> "lui-separator"
  | Scroll -> "lui-scroll"
  | ListContainer -> "lui-list"
  | VirtualList -> "lui-virtual-list"
  | Tabs -> "lui-tabs"
  | BottomTabs -> "lui-bottom-tabs"
  | BottomTab -> "lui-bottom-tab"
  | ButtonGroup -> "lui-button-group"
  | ToggleGroup -> "lui-toggle-group"
  | Breadcrumb -> "lui-breadcrumb"
  | Pagination -> "lui-pagination"
  | Spacer -> "lui-spacer"
  | Spinner -> "lui-spinner"
  | Icon -> "lui-icon"
  | Select -> "lui-select"
  | Combobox -> "lui-combobox"
  | DropdownMenu -> "lui-dropdown-menu"
  | ContextMenu -> "lui-context-menu"
  | MenuItem -> "lui-menu-item"
  (* MenuTrigger has no counterpart in the original backend (the kind was added
     later); it renders as a menu-item row, matching the
     .lui-menu-item[data-submenu-trigger] styling in lui.css. *)
  | MenuTrigger -> "lui-menu-item"
  | ListItem -> "lui-list-item"
  | Avatar -> "lui-avatar"
  | Image -> "lui-image"
  | MediaSurface -> "lui-media-surface"
  | Stepper -> "lui-stepper"
  | Step -> "lui-step"
  | Timeline -> "lui-timeline"
  | TimelineItem -> "lui-timeline-item"
  | InputGroup -> "lui-input-group"
  | InputGroupActions -> "lui-input-group-actions"
  | Dialog -> "lui-dialog"
  | Sheet -> "lui-sheet"
  | Tooltip -> "lui-tooltip"
  | Toast -> "lui-toast"
  | Toolbar -> "lui-toolbar"
  | Accordion -> "lui-accordion"
  | Table -> "lui-table"
  | TableRow -> "lui-table-row"
  | TableCell -> "lui-table-cell"
  | Tree -> "lui-tree"
  | Resizable -> "lui-resizable"
  | Split -> "lui-split"
  | Drawer -> "lui-drawer"
  | StatusBar -> "lui-status-bar"

let create_split_node renderer =
  let document = renderer.web_document in
  Util.element document "div" "lui-split" []
    [ Util.element document "div" "lui-split-panes" [] [];
      Util.element document "div" "lui-split-divider"
        [ ("role", "separator");
          ("aria-orientation", "vertical");
          ("aria-valuemin", "0");
          ("aria-valuemax", "1");
          ("aria-valuenow", "0.5");
          ("tabindex", "0") ]
        [] ]

let create_direct_toggle_node renderer kind =
  let document = renderer.web_document in
  let control_class =
    match kind with
    | Radio -> "lui-radio-control"
    | Checkbox -> "lui-checkbox-control"
    | _ -> "lui-switch-control"
  in
  let control_attributes =
    if kind = SwitchControl then
      [ ("type", "checkbox"); ("role", "switch") ]
    else [ ("type", if kind = Radio then "radio" else "checkbox") ]
  in
  Util.element document "label" (base_class_name kind) []
    [ Util.element document "input" control_class control_attributes [];
      Util.element document "span" "lui-control-label" [] [] ]

let create_button_node renderer kind =
  let document = renderer.web_document in
  let attributes =
    [ ("data-variant", "default");
      ("data-size", "default");
      ("data-icon-placement", "leading");
      ("type", "button") ]
  in
  let attributes =
    if kind = ToggleButton || kind = Toggle then
      attributes @ [ ("aria-pressed", "false") ]
    else attributes
  in
  Util.element document "button" (base_class_name kind) attributes
    [ Util.element document "span" "lui-button-icon lui-icon"
        [ ("aria-hidden", "true") ] [];
      Util.element document "span" "lui-button-label" [] [] ]

let create_combobox_node renderer =
  let document = renderer.web_document in
  Util.element document "div" "lui-combobox" []
    [ Util.element document "input" "lui-combobox-control"
        [ ("role", "combobox");
          ("aria-haspopup", "listbox");
          ("aria-expanded", "false") ]
        [];
      Util.element document "button" "lui-combobox-trigger"
        [ ("type", "button"); ("aria-label", "Open menu") ]
        [] ]

let create_select_node renderer =
  let document = renderer.web_document in
  Util.element document "button" "lui-select"
    [ ("type", "button");
      ("role", "combobox");
      ("aria-haspopup", "listbox");
      ("aria-expanded", "false") ]
    [ Util.element document "span" "lui-select-value" [] [] ]

let create_menu_item_node renderer =
  let document = renderer.web_document in
  let hidden = [ ("aria-hidden", "true") ] in
  Util.element document "button" "lui-menu-item"
    [ ("type", "button"); ("role", "option"); ("aria-selected", "false") ]
    [ Util.element document "span" "lui-menu-item-icon lui-icon" hidden [];
      Util.element document "span" "lui-menu-item-label" [] [];
      Util.element document "span" "lui-menu-item-check lui-icon"
        [ ("aria-hidden", "true"); ("data-name", "check") ]
        [] ]

let create_dropdown_node renderer =
  let document = renderer.web_document in
  Util.element document "div" "lui-popup-positioner"
    [ ("data-anchor", "below"); ("data-anchor-alignment", "start") ]
    [ Util.element document "div" "lui-dropdown-menu"
        [ ("role", "listbox"); ("tabindex", "-1") ]
        [] ]

let create_avatar_node renderer =
  let document = renderer.web_document in
  Util.element document "span" "lui-avatar" []
    [ Util.element document "img" "lui-avatar-image"
        [ ("alt", "");
          ("aria-hidden", "true");
          ("draggable", "false");
          ("hidden", "") ]
        [];
      Util.element document "span" "lui-avatar-initials" [] [] ]

let create_media_node renderer kind =
  let class_name = base_class_name kind in
  let pixels_class =
    if kind = Image then "lui-image-pixels" else "lui-media-surface-frame"
  in
  Util.element renderer.web_document "span" class_name []
    [ Util.element renderer.web_document "img" pixels_class
        [ ("alt", "");
          ("aria-hidden", "true");
          ("draggable", "false");
          ("hidden", "") ]
        [] ]

let create_step_node renderer =
  let document = renderer.web_document in
  Util.element document "div" "lui-step" [ ("role", "listitem") ]
    [ Util.element document "span" "lui-step-indicator"
        [ ("aria-hidden", "true") ] [];
      Util.element document "span" "lui-step-label" [] [];
      Util.element document "span" "lui-step-connector"
        [ ("aria-hidden", "true") ] [] ]

let create_timeline_item_node renderer =
  let document = renderer.web_document in
  Util.element document "div" "lui-timeline-item"
    [ ("role", "listitem"); ("data-variant", "outline") ]
    [ Util.element document "div" "lui-timeline-item-lead"
        [ ("aria-hidden", "true") ]
        [ Util.element document "span" "lui-timeline-item-indicator" [] [];
          Util.element document "span" "lui-timeline-item-connector" [] [] ];
      Util.element document "div" "lui-timeline-item-content" []
        [ Util.element document "div" "lui-timeline-item-title" [] [];
          Util.element document "div" "lui-timeline-item-description"
            [ ("hidden", "") ] [];
          Util.element document "div" "lui-timeline-item-meta"
            [ ("hidden", "") ] [] ];
      Util.element document "span" "lui-timeline-item-chevron lui-icon"
        [ ("aria-hidden", "true");
          ("data-name", "chevron-right");
          ("hidden", "") ]
        [] ]

let create_accordion_node renderer =
  let document = renderer.web_document in
  Util.element document "div" "lui-accordion" [ ("data-closed", "") ]
    [ Util.element document "button" "lui-accordion-summary"
        [ ("type", "button"); ("aria-expanded", "false") ]
        [ Util.element document "span" "lui-accordion-label" [] [];
          Util.element document "span" "lui-accordion-chevron lui-icon"
            [ ("aria-hidden", "true"); ("data-name", "chevron-down") ]
            [] ];
      Util.element document "div" "lui-accordion-content"
        [ ("role", "region"); ("data-closed", ""); ("hidden", "") ]
        [] ]

let simple_node_tag kind =
  match kind with
  | Heading -> "div"
  | Paragraph -> "p"
  | Label -> "label"
  | Text -> "span"
  | TextField | SecureField | Input -> "input"
  | SearchField -> "input"
  | Textarea -> "textarea"
  | Select | ListItem -> "button"
  | Table -> "table"
  | TableRow -> "tr"
  | TableCell -> "td"
  | Stepper | Timeline | InputGroup | InputGroupActions | Tree | Toast
  | Toolbar -> "div"
  | Slider -> "input"
  | Divider -> "hr"
  | Tooltip -> "span"
  | _ -> "div"

let simple_node_attributes kind =
  match kind with
  | Heading -> [ ("role", "heading") ]
  | SearchField -> [ ("type", "search") ]
  | SecureField -> [ ("type", "password") ]
  | Textarea ->
      [ ("style", "field-sizing: content; resize: vertical; overflow-y: auto") ]
  | Progress ->
      [ ("role", "progressbar");
        ("aria-valuemin", "0");
        ("aria-valuemax", "1") ]
  | RadioGroup -> [ ("role", "radiogroup") ]
  | Tabs -> [ ("role", "tablist"); ("aria-orientation", "horizontal") ]
  | BottomTab -> [ ("role", "tabpanel") ]
  | ButtonGroup | ToggleGroup | Breadcrumb | Pagination ->
      [ ("role", "group") ]
  | Slider ->
      [ ("type", "range"); ("min", "0"); ("max", "1"); ("step", "any") ]
  | Spinner -> [ ("role", "progressbar") ]
  | Divider -> [ ("role", "separator") ]
  | Select ->
      [ ("type", "button");
        ("role", "combobox");
        ("aria-haspopup", "listbox");
        ("aria-expanded", "false") ]
  | ListItem -> [ ("type", "button"); ("aria-pressed", "false") ]
  | Table -> [ ("role", "grid") ]
  | TableRow -> [ ("role", "row"); ("aria-selected", "false") ]
  | TableCell -> [ ("role", "gridcell") ]
  | Tree -> [ ("role", "tree") ]
  | Stepper | Timeline -> [ ("role", "list") ]
  | InputGroup -> [ ("role", "group") ]
  | DropdownMenu ->
      [ ("role", "listbox");
        ("data-anchor", "below");
        ("data-anchor-alignment", "start") ]
  | ContextMenu -> [ ("role", "menu"); ("tabindex", "-1") ]
  | Tooltip -> [ ("role", "tooltip") ]
  | Toast ->
      [ ("role", "status");
        ("aria-atomic", "true");
        ("tabindex", "0");
        ("data-state", "open") ]
  | Toolbar -> [ ("role", "toolbar"); ("aria-orientation", "horizontal") ]
  | StatusBar -> [ ("role", "status") ]
  | _ -> []

let create_simple_node renderer kind =
  Util.element renderer.web_document (simple_node_tag kind)
    (base_class_name kind) (simple_node_attributes kind) []

let create_bottom_tabs_node renderer =
  let document = renderer.web_document in
  Util.element document "div" "lui-bottom-tabs" []
    [ Util.element document "div" "lui-bottom-tabs-pages" [] [];
      Util.element document "div" "lui-bottom-tabs-bar"
        [ ("role", "tablist"); ("aria-orientation", "horizontal") ]
        [] ]

let create_modal_node renderer kind =
  let document = renderer.web_document in
  let class_name = base_class_name kind in
  let layer =
    Util.element document "div" "lui-modal-layer"
      [ ("data-lui-modal-state", "closed"); ("hidden", "") ] []
  in
  let backdrop =
    Util.element document "div" "lui-modal-backdrop"
      [ ("aria-hidden", "true") ] []
  in
  let surface =
    Util.element document "section" class_name
      [ ("role", "dialog"); ("aria-modal", "true"); ("tabindex", "-1") ]
      [ Util.element document "div" (class_name ^ "-title") []
          [ Util.element document "div" (class_name ^ "-heading") [] [];
            Util.element document "div" "lui-modal-description"
              [ ("hidden", "") ] [] ];
        Util.element document "div" (class_name ^ "-body") [] [];
        (if kind = Sheet then
           Util.element document "div" "lui-sheet-handle"
             [ ("aria-hidden", "true") ] []
         else
           Util.element document "span" "lui-modal-decoration"
             [ ("hidden", "") ] []) ]
  in
  W.Element.appendChild (W.Element.asNode backdrop) layer;
  W.Element.appendChild (W.Element.asNode surface) layer;
  surface

let create_alert_node renderer =
  let document = renderer.web_document in
  Util.element document "section" "lui-alert"
    [ ("role", "alert"); ("data-variant", "default") ]
    [ Util.element document "div" "lui-alert-title" [] [];
      Util.element document "div" "lui-alert-content" [] [] ]

let create_bubble_node renderer =
  let document = renderer.web_document in
  Util.element document "div" "lui-bubble"
    [ ("data-variant", "default"); ("data-reactions-alignment", "end") ]
    [ Util.element document "div" "lui-bubble-content" [] [];
      Util.element document "span" "lui-bubble-reactions" [] [] ]

let platform_node renderer kind =
  match kind with
  | Button | ToggleButton | Toggle -> create_button_node renderer kind
  | Checkbox | SwitchControl | Radio -> create_direct_toggle_node renderer kind
  | Select -> create_select_node renderer
  | Combobox -> create_combobox_node renderer
  | DropdownMenu -> create_dropdown_node renderer
  | MenuItem | MenuTrigger -> create_menu_item_node renderer
  | Avatar -> create_avatar_node renderer
  | Image | MediaSurface -> create_media_node renderer kind
  | Step -> create_step_node renderer
  | TimelineItem -> create_timeline_item_node renderer
  | BottomTabs -> create_bottom_tabs_node renderer
  | Accordion -> create_accordion_node renderer
  | Alert -> create_alert_node renderer
  | Bubble -> create_bubble_node renderer
  | Dialog | Sheet -> create_modal_node renderer kind
  | Split -> create_split_node renderer
  | _ -> create_simple_node renderer kind

let dom_node renderer node =
  match Store.node renderer.web_store node with
  | Some current -> current.platform_node
  | None -> invalid_arg "unknown DOM node"

let dom_node_before renderer previous_nodes node =
  match Store.node renderer.web_store node with
  | Some current -> current.platform_node
  | None ->
      (match Hashtbl.find_opt previous_nodes node with
       | Some previous -> previous.platform_node
       | None -> invalid_arg "unknown DOM node")

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
  | None ->
      (match Hashtbl.find_opt previous_nodes node with
       | Some previous -> retained_content_container previous dom_node
       | None -> dom_node)

let picker_under_parent renderer parent =
  let children = Store.children renderer.web_store parent in
  let count = List.length children in
  let rec loop index =
    if index = count then None
    else
      let child = List.nth children index in
      match Store.node renderer.web_store child with
      | Some child_node ->
          if
            Store.standard_kind_is child_node Select
            || Store.standard_kind_is child_node Combobox
          then Some child
          else loop (index + 1)
      | None -> loop (index + 1)
  in
  loop 0

let picker_for_dropdown renderer dropdown =
  match Store.node renderer.web_store dropdown with
  | Some current ->
      (match current.retained_parent with
       | Some parent -> picker_under_parent renderer parent
       | None -> None)
  | None -> None

let dropdown_anchor_node renderer node =
  match Store.node renderer.web_store node with
  | Some current ->
      (match current.retained_parent with
       | Some parent ->
           (match Store.node renderer.web_store parent with
            | Some parent_node ->
                if Store.menu_item_row parent_node then
                  parent_node.platform_node
                else
                  let container =
                    retained_content_container
                      parent_node parent_node.platform_node
                  in
                  let children = W.Element.children container in
                  let length = W.HtmlCollection.length children in
                  if length > 0 then
                    (match W.HtmlCollection.item (length - 1) children with
                     | Some anchor -> anchor
                     | None -> container)
                  else container
            | None -> invalid_arg "dropdown parent is unavailable")
       | None -> invalid_arg "dropdown requires an anchor parent")
  | None -> invalid_arg "unknown dropdown node"

let dropdown_side dom_node =
  match W.Element.getAttribute "data-anchor" dom_node with
  | Some value -> value
  | None -> "below"

let dropdown_offset renderer node =
  match Store.property renderer.web_store node AnchorOffset with
  | Some (FloatValue value) -> value
  | _ -> 0.0

let dropdown_listbox renderer node =
  picker_for_dropdown renderer node <> None

let dropdown_listbox_ = dropdown_listbox
