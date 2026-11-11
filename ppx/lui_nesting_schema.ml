(* Generated from schema/components.json, Lui_elements and Lui_protocol. Do not edit by hand. *)

type node_kind =
  | Root
  | Row
  | Column
  | Grid
  | Stack
  | EdgeInset
  | Overlay
  | ViewThatFits
  | Panel
  | Card
  | Alert
  | Bubble
  | Box
  | Text
  | Heading
  | Paragraph
  | Label
  | Button
  | ToggleButton
  | Toggle
  | RadioGroup
  | Radio
  | Slider
  | NumberStepper
  | TextField
  | SecureField
  | Input
  | SearchField
  | Textarea
  | Checkbox
  | SwitchControl
  | Progress
  | Divider
  | Scroll
  | ListContainer
  | VirtualList
  | Tabs
  | BottomTabs
  | BottomTab
  | ButtonGroup
  | ToggleGroup
  | Spacer
  | Spinner
  | Icon
  | Select
  | Combobox
  | DropdownMenu
  | ContextMenu
  | MenuItem
  | MenuTrigger
  | ListItem
  | Avatar
  | Image
  | MediaSurface
  | Stepper
  | Step
  | Timeline
  | TimelineItem
  | InputGroup
  | InputGroupActions
  | Breadcrumb
  | Pagination
  | Accordion
  | Table
  | TableRow
  | TableCell
  | Tree
  | Resizable
  | Split
  | Dialog
  | Drawer
  | Sheet
  | Tooltip
  | Toast
  | Toolbar
  | StatusBar
  | ListSection
  | ListSectionHeader
  | ListSectionFooter
  | SwipeActions
  | SwipeAction
  | FilePicker
  | Kbd
  | Link
  | FileImage
  | FilePreview
  | Popover
  | VirtualRows

let name = function
  | Root -> "root"
  | Row -> "row"
  | Column -> "column"
  | Grid -> "grid"
  | Stack -> "stack"
  | EdgeInset -> "edge-inset"
  | Overlay -> "overlay"
  | ViewThatFits -> "view-that-fits"
  | Panel -> "panel"
  | Card -> "card"
  | Alert -> "alert"
  | Bubble -> "bubble"
  | Box -> "box"
  | Text -> "text"
  | Heading -> "heading"
  | Paragraph -> "paragraph"
  | Label -> "label"
  | Button -> "button"
  | ToggleButton -> "toggle-button"
  | Toggle -> "toggle"
  | RadioGroup -> "radio-group"
  | Radio -> "radio"
  | Slider -> "slider"
  | NumberStepper -> "number-stepper"
  | TextField -> "text-field"
  | SecureField -> "secure-field"
  | Input -> "input"
  | SearchField -> "search-field"
  | Textarea -> "textarea"
  | Checkbox -> "checkbox"
  | SwitchControl -> "switch"
  | Progress -> "progress"
  | Divider -> "divider"
  | Scroll -> "scroll"
  | ListContainer -> "list"
  | VirtualList -> "virtual-list"
  | Tabs -> "tabs"
  | BottomTabs -> "bottom-tabs"
  | BottomTab -> "bottom-tab"
  | ButtonGroup -> "button-group"
  | ToggleGroup -> "toggle-group"
  | Spacer -> "spacer"
  | Spinner -> "spinner"
  | Icon -> "icon"
  | Select -> "select"
  | Combobox -> "combobox"
  | DropdownMenu -> "dropdown-menu"
  | ContextMenu -> "context-menu"
  | MenuItem -> "menu-item"
  | MenuTrigger -> "menu-trigger"
  | ListItem -> "list-item"
  | Avatar -> "avatar"
  | Image -> "image"
  | MediaSurface -> "media-surface"
  | Stepper -> "stepper"
  | Step -> "step"
  | Timeline -> "timeline"
  | TimelineItem -> "timeline-item"
  | InputGroup -> "input-group"
  | InputGroupActions -> "input-group-actions"
  | Breadcrumb -> "breadcrumb"
  | Pagination -> "pagination"
  | Accordion -> "accordion"
  | Table -> "table"
  | TableRow -> "table-row"
  | TableCell -> "table-cell"
  | Tree -> "tree"
  | Resizable -> "resizable"
  | Split -> "split"
  | Dialog -> "dialog"
  | Drawer -> "drawer"
  | Sheet -> "sheet"
  | Tooltip -> "tooltip"
  | Toast -> "toast"
  | Toolbar -> "toolbar"
  | StatusBar -> "status-bar"
  | ListSection -> "list-section"
  | ListSectionHeader -> "list-section-header"
  | ListSectionFooter -> "list-section-footer"
  | SwipeActions -> "swipe-actions"
  | SwipeAction -> "swipe-action"
  | FilePicker -> "file-picker"
  | Kbd -> "kbd"
  | Link -> "link"
  | FileImage -> "file-image"
  | FilePreview -> "file-preview"
  | Popover -> "popover"
  | VirtualRows -> "virtual-rows"

let horizontal_container kind =
  kind = Tabs || kind = ButtonGroup || kind = ToggleGroup || kind = Breadcrumb
  || kind = Pagination

let tree_row_kind kind =
  kind = Row
  || kind = Column
  || kind = Panel
  || kind = Card
  || kind = Box
  || kind = ListItem

let context_menu_leaf_host_kind kind =
  kind = Button
  || kind = ToggleButton
  || kind = Toggle
  || kind = Radio
  || kind = Slider
  || kind = NumberStepper
  || kind = TextField
  || kind = SecureField
  || kind = Input
  || kind = SearchField
  || kind = Textarea
  || kind = Checkbox
  || kind = SwitchControl
  || kind = Select
  || kind = Combobox
  || kind = MenuItem
  || kind = Text
  || kind = TableCell

let regular_child_container kind =
  if horizontal_container kind then true
  else
    match kind with
    | Root
    | Row
    | Column
    | Grid
    | Stack
    | EdgeInset
    | Overlay
    | ViewThatFits
    | Panel
    | Card
    | Box
    | Scroll
    | ListContainer
    | VirtualList
    | RadioGroup
    | Button
    | DropdownMenu
    | ContextMenu
    | MenuTrigger
    | MenuItem
    | ListItem
    (* Option children feed the host picker's item list; they are not
       rendered as subtrees. *)
    | Select
    | Combobox
    | Dialog
    | Drawer
    | Sheet
    | Accordion
    | Table
    | TableRow
    | TableCell
    | Tree
    | Resizable
    | Split
    | Stepper
    | Timeline
    | InputGroup
    | InputGroupActions
    | Toast
    | Toolbar
    | Alert
    | Bubble
    | Text
    | Heading
    | Paragraph
    | Label
    | BottomTabs
    | BottomTab
    | Link
    | FilePicker
    | ListSection
    | ListSectionHeader
    | ListSectionFooter
    | SwipeActions
    | Popover -> true
    | _ -> false

let can_contain_children kind =
  context_menu_leaf_host_kind kind || regular_child_container kind

let child_kind_supported parent_kind child_kind =
  if child_kind = Root then false
  else if parent_kind = Root then true
  else if parent_kind = MenuTrigger then child_kind = DropdownMenu
  else if context_menu_leaf_host_kind parent_kind
  then
    (* Leaf hosts take a context-menu child only; a leaf host that is also
       a container (button) keeps its regular children alongside. *)
    child_kind = ContextMenu || regular_child_container parent_kind
  else if child_kind = ListSection then parent_kind = ListContainer
  else if child_kind = ListSectionHeader || child_kind = ListSectionFooter
  then parent_kind = ListSection
  else if child_kind = SwipeActions then parent_kind = ListItem
  else if child_kind = SwipeAction then parent_kind = SwipeActions
  else
    match parent_kind with
    | ListSection -> child_kind = ListItem
    | SwipeActions -> child_kind = SwipeAction
    | Table -> child_kind = TableRow
    | TableRow -> child_kind = TableCell
    | BottomTabs -> child_kind = BottomTab
    | BottomTab -> child_kind <> BottomTab
    | Tree -> tree_row_kind child_kind || child_kind = VirtualList
    | Stepper -> child_kind = Step
    | Timeline -> child_kind = TimelineItem
    | InputGroup -> child_kind = Textarea || child_kind = InputGroupActions
    | Toolbar ->
      (match child_kind with
      | Button
      | ToggleButton
      | ButtonGroup
      | ToggleGroup
      | Checkbox
      | SwitchControl
      | Toggle
      | RadioGroup
      | Select
      | Combobox
      | TextField
      | SecureField
      | Input
      | SearchField
      | MenuItem
      | MenuTrigger
      | Spacer
      | Divider
      | Text -> true
      | _ -> false)
    | DropdownMenu ->
      child_kind = MenuItem || child_kind = MenuTrigger
      || child_kind = Divider
    | ContextMenu -> child_kind = MenuItem || child_kind = Divider
    | _ -> true

type children = Children_list | Child_arguments of int

let constructor = function
  | "row" -> Some (Row, Row, Children_list)
  | "column" -> Some (Column, Column, Children_list)
  | "grid" -> Some (Grid, Grid, Children_list)
  | "stack" -> Some (Stack, Stack, Children_list)
  | "edge_inset" -> Some (EdgeInset, EdgeInset, Children_list)
  | "overlay" -> Some (Overlay, Overlay, Children_list)
  | "view_that_fits" -> Some (ViewThatFits, ViewThatFits, Children_list)
  | "panel" -> Some (Panel, Panel, Children_list)
  | "card" -> Some (Card, Card, Children_list)
  | "alert" -> Some (Alert, Alert, Children_list)
  | "bubble" -> Some (Bubble, Bubble, Children_list)
  | "box" -> Some (Box, Box, Children_list)
  | "text" -> Some (Text, Text, Children_list)
  | "heading" -> Some (Heading, Heading, Children_list)
  | "paragraph" -> Some (Paragraph, Paragraph, Children_list)
  | "label" -> Some (Label, Label, Children_list)
  | "button" -> Some (Button, Button, Children_list)
  | "toggle_button" -> Some (ToggleButton, ToggleButton, Children_list)
  | "toggle" -> Some (Toggle, Toggle, Children_list)
  | "radio_group" -> Some (RadioGroup, RadioGroup, Children_list)
  | "radio" -> Some (Radio, Radio, Children_list)
  | "slider" -> Some (Slider, Slider, Children_list)
  | "number_stepper" -> Some (NumberStepper, NumberStepper, Children_list)
  | "text_field" -> Some (TextField, TextField, Children_list)
  | "secure_field" -> Some (SecureField, SecureField, Children_list)
  | "input" -> Some (Input, Input, Children_list)
  | "search_field" -> Some (SearchField, SearchField, Children_list)
  | "textarea" -> Some (Textarea, Textarea, Children_list)
  | "checkbox" -> Some (Checkbox, Checkbox, Children_list)
  | "switch_" -> Some (SwitchControl, SwitchControl, Children_list)
  | "progress" -> Some (Progress, Progress, Children_list)
  | "divider" -> Some (Divider, Divider, Children_list)
  | "scroll" -> Some (Scroll, Scroll, Children_list)
  | "list" -> Some (ListContainer, ListContainer, Children_list)
  | "virtual_list" -> Some (VirtualList, VirtualList, Children_list)
  | "tabs" -> Some (Tabs, Tabs, Children_list)
  | "bottom_tabs" -> Some (BottomTabs, BottomTabs, Children_list)
  | "bottom_tab" -> Some (BottomTab, BottomTab, Children_list)
  | "button_group" -> Some (ButtonGroup, ButtonGroup, Children_list)
  | "toggle_group" -> Some (ToggleGroup, ToggleGroup, Children_list)
  | "spacer" -> Some (Spacer, Spacer, Children_list)
  | "spinner" -> Some (Spinner, Spinner, Children_list)
  | "icon" -> Some (Icon, Icon, Children_list)
  | "select" -> Some (Select, Select, Children_list)
  | "combobox" -> Some (Combobox, Combobox, Children_list)
  | "dropdown_menu" -> Some (DropdownMenu, DropdownMenu, Children_list)
  | "context_menu" -> Some (ContextMenu, ContextMenu, Children_list)
  | "menu_item" -> Some (MenuItem, MenuItem, Children_list)
  | "menu_trigger" -> Some (MenuTrigger, MenuTrigger, Children_list)
  | "list_item" -> Some (ListItem, ListItem, Children_list)
  | "avatar" -> Some (Avatar, Avatar, Children_list)
  | "image" -> Some (Image, Image, Children_list)
  | "media_surface" -> Some (MediaSurface, MediaSurface, Children_list)
  | "stepper" -> Some (Stepper, Stepper, Children_list)
  | "step" -> Some (Step, Step, Children_list)
  | "timeline" -> Some (Timeline, Timeline, Children_list)
  | "timeline_item" -> Some (TimelineItem, TimelineItem, Children_list)
  | "input_group" -> Some (InputGroup, InputGroup, Child_arguments 1)
  | "input_group_actions" -> Some (InputGroupActions, InputGroupActions, Children_list)
  | "breadcrumb" -> Some (Breadcrumb, Breadcrumb, Children_list)
  | "pagination" -> Some (Pagination, Pagination, Children_list)
  | "accordion" -> Some (Accordion, Accordion, Children_list)
  | "table" -> Some (Table, Table, Children_list)
  | "table_row" -> Some (TableRow, TableRow, Children_list)
  | "table_cell" -> Some (TableCell, TableCell, Children_list)
  | "tree" -> Some (Tree, Tree, Children_list)
  | "resizable" -> Some (Resizable, Resizable, Children_list)
  | "split" -> Some (Split, Split, Child_arguments 2)
  | "dialog" -> Some (Dialog, Dialog, Children_list)
  | "drawer" -> Some (Drawer, Drawer, Child_arguments 2)
  | "sheet" -> Some (Sheet, Sheet, Children_list)
  | "tooltip" -> Some (Tooltip, Tooltip, Children_list)
  | "toast" -> Some (Toast, Toast, Children_list)
  | "toolbar" -> Some (Toolbar, Toolbar, Children_list)
  | "status_bar" -> Some (StatusBar, StatusBar, Children_list)
  | "list_section" -> Some (ListSection, ListSection, Children_list)
  | "swipe_actions" -> Some (SwipeActions, SwipeActions, Children_list)
  | "swipe_action" -> Some (SwipeAction, SwipeAction, Children_list)
  | "file_picker" -> Some (FilePicker, FilePicker, Children_list)
  | "kbd" -> Some (Kbd, Kbd, Children_list)
  | "link" -> Some (Link, Link, Children_list)
  | "file_image" -> Some (FileImage, FileImage, Children_list)
  | "file_preview" -> Some (FilePreview, FilePreview, Children_list)
  | "popover" -> Some (Popover, Popover, Children_list)
  | "separator" -> Some (Divider, Divider, Children_list)
  | "menu" | "submenu" -> Some (MenuTrigger, DropdownMenu, Children_list)
  | _ -> None

let exports = function
  | "mount" | "scoped" | "scoped_step" | "scoped_timeline_item" | "scoped_bottom_tab" | "scoped_table_row" | "scoped_table_cell" | "scoped_radio" | "scoped_input_group_actions" | "scoped_swipe_action" | "reactive" | "map" | "sample" | "get" | "get_state" | "attach" | "enable" | "mount_children" | "dynamic" | "dyn" | "if_" | "keyed" | "virtual_rows" | "keyed_step" | "keyed_timeline_item" | "keyed_bottom_tab" | "keyed_table_row" | "keyed_table_cell" | "keyed_radio" | "keyed_swipe_action" | "press" | "on_input" | "on_event" | "is_press" | "is_long_press" | "is_double_press" | "is_change" | "is_input" | "is_navigate" | "is_submit" | "is_toggle" | "is_dismiss" | "is_appear" | "is_resize" | "register_press" | "register_long_press" | "register_double_press" | "register_change" | "register_input" | "register_submit" | "register_navigate" | "register_toggle" | "register_dismiss" | "appear_handler" | "register_resize" | "apply_universal" | "row" | "column" | "grid" | "stack" | "edge_inset" | "overlay" | "align" | "view_that_fits" | "panel" | "card" | "alert" | "bubble" | "box" | "scroll" | "list" | "virtual_list" | "tabs" | "bottom_tabs" | "bottom_tab" | "button_group" | "toggle_group" | "breadcrumb" | "pagination" | "table" | "table_row" | "table_cell" | "tree" | "resizable" | "split" | "drawer" | "status_bar" | "spacer" | "spinner" | "icon" | "text" | "heading" | "paragraph" | "label" | "kbd" | "button" | "toggle_button" | "checkbox" | "switch_" | "toggle" | "radio_group" | "radio" | "slider" | "number_stepper" | "progress" | "divider" | "separator" | "text_field" | "secure_field" | "input" | "search_field" | "textarea" | "input_group" | "input_group_actions" | "select" | "combobox" | "dropdown_menu" | "context_menu" | "menu_trigger" | "menu" | "submenu" | "dialog" | "sheet" | "tooltip" | "toast" | "file_picker" | "popover" | "toolbar" | "accordion" | "menu_item" | "list_item" | "list_section" | "swipe_actions" | "swipe_action" | "avatar" | "image" | "media_surface" | "link" | "file_image" | "file_preview" | "stepper" | "step" | "timeline" | "timeline_item" | "themed" -> true
  | _ -> false
