(* Core protocol types and validation for lui. Mirrors schema/components.json. *)

module String_map = Map.Make (String)
module Int_map = Map.Make (Int)

type node_kind =
  | Root
  | Row
  | Column
  | Grid
  | Stack
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

type operating_system =
  | GenericOS
  | WebOS
  | MacOS
  | IOS
  | AndroidOS
  | LinuxOS
  | WindowsOS

type host_kind =
  | GenericHost
  | WebHost
  | SwiftUIHost
  | FlutterHost

type platform_profile = {
  profile_os : operating_system;
  profile_host : host_kind;
}

type property =
  | TextValue
  | Enabled
  | Gap
  | MainAlignment
  | CrossAlignment
  | GrowValue
  | GridColumns
  | PaddingValue
  | PaddingHorizontal
  | PaddingVertical
  | BackgroundValue
  | ForegroundValue
  | BorderColorValue
  | BorderWidth
  | CornerRadius
  | WidthValue
  | HeightValue
  | MinWidth
  | MaxWidth
  | MinHeight
  | MaxHeight
  | ContainerRelativeFrameValue
  | ContainerRelativeFrameInset
  | PlaceholderValue
  | AccessibilityLabel
  | AccessibilityIdentifier
  | StyleClass
  | HeadingLevel
  | Checked
  | ProgressValue
  | OrientationValue
  | SizeValue
  | IconName
  | VariantValue
  | InlineIconName
  | IconPlacementValue
  | Selected
  | Autofocus
  | SubmitOnEnter
  | LongPressEnabled
  | ChangeEnabled
  | ToggleEnabled
  | PressEnabled
  | SubmitEnabled
  | DoublePressEnabled
  | AppearEnabled
  | ImageIdValue
  | SurfaceIdValue
  | ActiveIndex
  | TitleValue
  | DescriptionValue
  | MetaValue
  | IndicatorValue
  | Connector
  | SourceX
  | SourceY
  | SourceWidth
  | SourceHeight
  | AnchorValue
  | AnchorAlignmentValue
  | AnchorOffset
  | TooltipDelay
  | DurationValue
  | TextAlignment
  | RoleValue
  | TreeLevel
  | Expanded
  | ResizeDuration
  | ResizeEasing
  | ResizeOrigin

module Property_map =
  Map.Make
    (struct
      type t = property

      let compare = Stdlib.compare
    end)

type wire_value =
  | StringValue of string
  | BoolValue of bool
  | IntValue of int
  | FloatValue of float

type event =
  | Press of int
  | LongPress of int
  | TextChanged of int * string
  | Submit of int
  | ToggleChanged of int * bool
  | Change of int
  | ValueChanged of int * float
  | Dismiss of int
  | DoublePress of int
  | Appear of int
  | ExtensionEvent of int * string * string * wire_value String_map.t

type patch_op =
  | CreateNode of int * node_kind
  | CreateExtension of int * string * string
  | DropNode of int
  | SetProp of int * property * wire_value
  | RemoveProp of int * property
  | SetExtensionProp of int * string * wire_value
  | RemoveExtensionProp of int * string
  | InsertChild of int * int * int
  | RemoveChild of int * int
  | MoveChild of int * int * int

type patch_batch = {
  generation : int;
  ops : patch_op list;
}

type backend = {
  backend_profile : platform_profile;
  apply_batch : patch_batch -> bool;
}

let profile operating_system host = { profile_os = operating_system; profile_host = host }

let generic_profile () = profile GenericOS GenericHost

let event_node event =
  match event with
  | Press node
  | LongPress node
  | TextChanged (node, _)
  | Submit node
  | ToggleChanged (node, _)
  | Change node
  | ValueChanged (node, _)
  | Dismiss node
  | DoublePress node
  | Appear node
  | ExtensionEvent (node, _, _, _) -> node

let modal_surface kind = kind = Dialog || kind = Drawer || kind = Sheet

let tree_row_kind kind =
  kind = Row
  || kind = Column
  || kind = Panel
  || kind = Card
  || kind = Box
  || kind = ListItem

let context_menu_host_kind kind =
  kind = Button
  || kind = ToggleButton
  || kind = Toggle
  || kind = Radio
  || kind = Slider
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
  || kind = ListItem
  || kind = Accordion
  || kind = Text
  || kind = TableCell

let context_menu_leaf_host_kind kind =
  kind = Button
  || kind = ToggleButton
  || kind = Toggle
  || kind = Radio
  || kind = Slider
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

let event_supported kind event =
  match event with
  | Press _ ->
    (match kind with
    | Button
    | Radio
    | Select
    | Combobox
    | MenuItem
    | ListItem
    | Text
    | TableCell
    | TimelineItem
    | BottomTab -> true
    | _ -> false)
  | LongPress _ ->
    (match kind with
    | Button
    | ToggleButton
    | ListItem -> true
    | _ -> false)
  | TextChanged _ ->
    (match kind with
    | TextField
    | SecureField
    | Input
    | SearchField
    | Textarea
    | Combobox -> true
    | _ -> false)
  | Submit _ ->
    (match kind with
    | TextField
    | SecureField
    | Input
    | SearchField
    | Textarea
    | Combobox
    | ListItem -> true
    | _ -> false)
  | ToggleChanged _ ->
    (match kind with
    | ToggleButton
    | Checkbox
    | SwitchControl
    | Toggle
    | Radio
    | Accordion
    | Drawer -> true
    | _ -> false)
  | Change _ -> kind = Radio
  | ValueChanged _ ->
    (match kind with
    | Slider
    | Split -> true
    | _ -> false)
  | Dismiss _ ->
    (match kind with
    | Select
    | Combobox
    | DropdownMenu
    | Toast
    | Dialog
    | Drawer
    | Sheet -> true
    | _ -> false)
  | DoublePress _ -> kind = ListItem
  | Appear _ -> kind <> Root
  | ExtensionEvent _ -> false

let true_property properties property =
  match Property_map.find_opt property properties with
  | Some (BoolValue true) -> true
  | _ -> false

let treeitem_properties properties =
  match Property_map.find_opt RoleValue properties with
  | Some (StringValue "treeitem") -> true
  | _ -> false

let event_supported_for_properties kind properties event =
  if
    match event with
    | Appear _ -> true_property properties AppearEnabled
    | _ -> false
  then true
  else if treeitem_properties properties then
    match event with
    | Press _ -> true_property properties PressEnabled
    | Change _ -> true_property properties ChangeEnabled
    | ToggleChanged _ -> true_property properties ToggleEnabled
    | _ -> event_supported kind event
  else event_supported kind event

let container_relative_frame_supported value =
  value = "horizontal"
  || value = "vertical"
  || value = "both"
  || value = "min-horizontal"
  || value = "min-vertical"
  || value = "min-both"

let orientation_supported value = value = "horizontal" || value = "vertical"

let control_size_supported value =
  value = "default" || value = "sm" || value = "lg" || value = "icon"

let button_variant_supported value =
  value = "default"
  || value = "primary"
  || value = "secondary"
  || value = "outline"
  || value = "ghost"
  || value = "destructive"

let icon_placement_supported value =
  value = "leading" || value = "trailing" || value = "top"

let built_in_icon_name_supported value =
  match value with
  | "alert"
  | "archive"
  | "arrow-down"
  | "arrow-right"
  | "arrow-up"
  | "check"
  | "check-circle"
  | "chevron-down"
  | "chevron-left"
  | "chevron-right"
  | "chevron-up"
  | "circle-dot"
  | "clock"
  | "copy"
  | "download"
  | "edit"
  | "ellipsis"
  | "external-link"
  | "eye"
  | "file-text"
  | "folder"
  | "folder-open"
  | "git-branch"
  | "git-merge"
  | "git-pull-request"
  | "info"
  | "menu"
  | "mic"
  | "moon"
  | "music"
  | "panel-left"
  | "panel-right"
  | "pause"
  | "play"
  | "plus"
  | "refresh-cw"
  | "repeat"
  | "save"
  | "search"
  | "send"
  | "settings"
  | "shuffle"
  | "skip-back"
  | "skip-forward"
  | "sun"
  | "terminal"
  | "trash"
  | "volume"
  | "wrench"
  | "x"
  | "x-circle" -> true
  | _ -> false

(* matches [a-z0-9]+(-[a-z0-9]+)* *)
let is_slug_char c = (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9')

let slug_segment value =
  let n = String.length value in
  n > 0
  && is_slug_char value.[0]
  && is_slug_char value.[n - 1]
  &&
  let rec loop index =
    if index = n then true
    else if is_slug_char value.[index] then loop (index + 1)
    else
      (* a '-' must be followed by a slug char; the final char is known to
         be one, so index + 1 < n here *)
      value.[index] = '-' && is_slug_char value.[index + 1]
      && loop (index + 1)
  in
  loop 0

let custom_icon_name_supported value =
  let prefix = "app:" in
  let plen = String.length prefix in
  String.length value > plen
  && String.sub value 0 plen = prefix
  && slug_segment (String.sub value plen (String.length value - plen))

let icon_name_supported value =
  built_in_icon_name_supported value || custom_icon_name_supported value

let main_alignment_supported value =
  value = "start" || value = "center" || value = "end" || value = "space_between"

let cross_alignment_supported value =
  value = "stretch" || value = "start" || value = "center" || value = "end"

let horizontal_container kind =
  kind = Tabs || kind = ButtonGroup || kind = ToggleGroup || kind = Breadcrumb
  || kind = Pagination

let common_property_supported kind property =
  match property with
  | MainAlignment | CrossAlignment ->
    kind = Row
    || kind = Column
    || kind = ListContainer
    || kind = VirtualList
    || horizontal_container kind
  | GrowValue ->
    kind <> Avatar && (not (modal_surface kind)) && kind <> Tooltip
  | GridColumns -> kind = Grid
  | PaddingValue -> kind <> Avatar && kind <> Tooltip
  | PaddingHorizontal ->
    kind = Row || kind = Column || kind = Grid || kind = Box || kind = Button
  | PaddingVertical -> kind = Row || kind = Column || kind = Grid || kind = Box
  | BackgroundValue | BorderColorValue | BorderWidth | CornerRadius ->
    kind <> Avatar && (not (modal_surface kind)) && kind <> Tooltip
  | ForegroundValue ->
    (match kind with
    | Text | Heading | Paragraph | Label | Button | ToggleButton | TextField
    | SecureField | Input | SearchField | Textarea | Checkbox | Toggle | Radio
    | Slider | Spinner | Icon | Select | Combobox | DropdownMenu | MenuItem
    | ListItem | TableCell | Resizable | Split | Alert | Bubble | StatusBar -> true
    | _ -> false)
  | WidthValue | HeightValue -> kind <> Avatar && kind <> Tooltip
  | MinWidth | MaxWidth | MinHeight | MaxHeight ->
    kind <> Avatar && (not (modal_surface kind)) && kind <> Tooltip
  | ContainerRelativeFrameValue | ContainerRelativeFrameInset ->
    kind <> Root && not (modal_surface kind)
  | StyleClass -> kind <> Avatar && kind <> Tooltip
  | AccessibilityLabel ->
    kind = Button
    || kind = ToggleButton
    || kind = Select
    || kind = TextField
    || kind = SecureField
    || kind = Input
    || kind = SearchField
    || kind = Textarea
    || kind = Checkbox
    || kind = SwitchControl
    || kind = Toggle
    || kind = RadioGroup
    || kind = Radio
    || kind = Slider
    || horizontal_container kind
    || kind = Avatar
    || kind = Image
    || kind = MediaSurface
    || kind = Tree
    || kind = Resizable
    || kind = Split
    || kind = Drawer
    || kind = Alert
    || kind = Bubble
    || kind = ListItem
    || tree_row_kind kind
  | AccessibilityIdentifier -> true
  | PlaceholderValue ->
    kind = TextField
    || kind = SecureField
    || kind = Input
    || kind = SearchField
    || kind = Textarea
    || kind = Select
    || kind = Combobox
  | HeadingLevel -> kind = Heading
  | Checked ->
    kind = Checkbox || kind = SwitchControl || kind = Toggle || kind = Radio
  | ProgressValue -> kind = Progress || kind = Slider || kind = Split
  | OrientationValue -> kind = Divider || kind = Tabs
  | SizeValue ->
    kind = Button || kind = ToggleButton || kind = Spinner || kind = Icon
    || kind = TableCell || kind = MenuItem
  | IconName -> kind = Icon
  | VariantValue ->
    kind = Button || kind = ToggleButton || kind = MenuItem || kind = Alert
    || kind = Bubble
  | InlineIconName ->
    kind = Button
    || kind = ToggleButton
    || kind = MenuItem
    || kind = ListItem
    || kind = BottomTab
  | IconPlacementValue -> kind = Button || kind = ToggleButton || kind = ListItem
  | Selected ->
    kind = Button
    || kind = ToggleButton
    || kind = MenuItem
    || kind = ListItem
    || kind = TableRow
    || kind = Drawer
    || kind = BottomTab
    || kind = VirtualList
    || tree_row_kind kind
  | Autofocus ->
    kind = Button
    || kind = ToggleButton
    || kind = TextField
    || kind = SecureField
    || kind = Input
    || kind = SearchField
    || kind = Textarea
  | SubmitOnEnter -> kind = Textarea
  | LongPressEnabled -> kind = Button || kind = ToggleButton || kind = ListItem
  | ChangeEnabled -> kind = Radio || tree_row_kind kind
  | ToggleEnabled -> kind = Radio || kind = Drawer || tree_row_kind kind
  | PressEnabled ->
    kind = Text
    || kind = Radio
    || kind = Select
    || kind = Combobox
    || kind = MenuItem
    || kind = ListItem
    || kind = TableCell
    || kind = BottomTab
    || tree_row_kind kind
  | SubmitEnabled -> kind = Combobox || kind = ListItem
  | DoublePressEnabled -> kind = ListItem
  | AppearEnabled -> kind <> Root
  | ImageIdValue | SourceX | SourceY | SourceWidth | SourceHeight ->
    kind = Avatar || kind = Image
  | SurfaceIdValue -> kind = MediaSurface
  | AnchorValue | AnchorAlignmentValue | AnchorOffset ->
    kind = DropdownMenu || kind = Tooltip
  | TooltipDelay -> kind = Tooltip
  | DurationValue -> false
  | TextAlignment ->
    kind = Text
    || kind = Button
    || kind = ToggleButton
    || kind = TableCell
    || kind = Bubble
    || kind = StatusBar
  | RoleValue -> tree_row_kind kind || kind = ListItem
  | TreeLevel | Expanded -> tree_row_kind kind
  | ResizeDuration | ResizeEasing | ResizeOrigin -> kind = Split
  | TextValue ->
    (match kind with
    | Text
    | Heading
    | Paragraph
    | Label
    | Button
    | ToggleButton
    | TextField
    | SecureField
    | Input
    | SearchField
    | Textarea
    | Checkbox
    | SwitchControl
    | Toggle
    | Radio
    | Select
    | Combobox
    | MenuItem
    | ListItem
    | Avatar
    | Dialog
    | Drawer
    | Sheet
    | Tooltip
    | TableCell
    | Alert
    | Bubble
    | StatusBar -> true
    | _ -> false)
  | Enabled ->
    (match kind with
    | Button
    | ToggleButton
    | TextField
    | SecureField
    | Input
    | SearchField
    | Textarea
    | Checkbox
    | SwitchControl
    | Toggle
    | Radio
    | Slider
    | Select
    | Combobox
    | MenuItem
    | ListItem
    | Drawer
    | BottomTab -> true
    | _ -> false)
  | ActiveIndex | DescriptionValue | MetaValue | IndicatorValue | Connector ->
    false
  | TitleValue -> kind = BottomTab
  | Gap ->
    kind = Row
    || kind = Column
    || kind = Grid
    || kind = ListContainer
    || kind = VirtualList
    || kind = DropdownMenu
    || kind = TableRow
    || kind = Tree
    || kind = Split
    || horizontal_container kind

let property_supported kind property =
  if property = AccessibilityIdentifier then true
  else
    match kind with
    | Root | ContextMenu -> false
    | Toast ->
      property = DurationValue || property = AccessibilityLabel
      || property = StyleClass
    | Toolbar ->
      property = OrientationValue || property = AccessibilityLabel
      || property = Gap || property = StyleClass
    | BottomTabs ->
      property = AccessibilityLabel || property = StyleClass
      || property = GrowValue || property = WidthValue || property = HeightValue
      || property = MinWidth || property = MaxWidth || property = MinHeight
      || property = MaxHeight
    | BottomTab ->
      property = TitleValue || property = InlineIconName
      || property = Selected || property = Enabled || property = PressEnabled
    | Accordion ->
      property = TextValue || property = Selected
      || property = ToggleEnabled || property = HeightValue
    | Stepper -> property = ActiveIndex || property = AccessibilityLabel
    | Step -> property = TextValue
    | Timeline ->
      property = Gap || property = GrowValue || property = AccessibilityLabel
    | TimelineItem ->
      property = TitleValue || property = DescriptionValue
      || property = MetaValue || property = IndicatorValue
      || property = InlineIconName || property = VariantValue
      || property = Connector || property = Selected || property = PressEnabled
    | InputGroup ->
      property = AccessibilityLabel || property = WidthValue
      || property = HeightValue || property = MinWidth || property = GrowValue
    | InputGroupActions -> property = Gap
    | _ -> common_property_supported kind property

let is_finite value =
  value = value && value <> infinity && value <> neg_infinity

let property_value_supported property value =
  match (property, value) with
  | TextValue, StringValue _ -> true
  | Enabled, BoolValue _ -> true
  | Gap, IntValue value -> value >= 0
  | MainAlignment, StringValue value -> main_alignment_supported value
  | CrossAlignment, StringValue value -> cross_alignment_supported value
  | GrowValue, FloatValue value -> value >= 0.0
  | GridColumns, IntValue value -> value >= 0
  | PaddingValue, IntValue _ -> true
  | PaddingHorizontal, IntValue value -> value >= 0
  | PaddingVertical, IntValue value -> value >= 0
  | BackgroundValue, StringValue _ -> true
  | ForegroundValue, StringValue _ -> true
  | BorderColorValue, StringValue _ -> true
  | BorderWidth, IntValue value -> value >= 0
  | CornerRadius, IntValue value -> value >= 0
  | WidthValue, IntValue value -> value >= 0
  | HeightValue, IntValue value -> value >= 0
  | MinWidth, IntValue value -> value >= 0
  | MaxWidth, IntValue value -> value >= 0
  | MinHeight, IntValue value -> value >= 0
  | MaxHeight, IntValue value -> value >= 0
  | ContainerRelativeFrameValue, StringValue value ->
    container_relative_frame_supported value
  | ContainerRelativeFrameInset, IntValue value -> value >= 0
  | PlaceholderValue, StringValue _ -> true
  | AccessibilityLabel, StringValue _ -> true
  | AccessibilityIdentifier, StringValue _ -> true
  | StyleClass, StringValue _ -> true
  | HeadingLevel, IntValue value -> value >= 1 && value <= 6
  | Checked, BoolValue _ -> true
  | ProgressValue, FloatValue _ -> true
  | OrientationValue, StringValue value -> orientation_supported value
  | SizeValue, StringValue value -> control_size_supported value
  | IconName, StringValue value -> icon_name_supported value
  | VariantValue, StringValue value -> button_variant_supported value
  | InlineIconName, StringValue value -> icon_name_supported value
  | IconPlacementValue, StringValue value -> icon_placement_supported value
  | Selected, BoolValue _ -> true
  | Autofocus, BoolValue _ -> true
  | SubmitOnEnter, BoolValue _ -> true
  | LongPressEnabled, BoolValue _ -> true
  | ChangeEnabled, BoolValue _ -> true
  | ToggleEnabled, BoolValue _ -> true
  | PressEnabled, BoolValue _ -> true
  | SubmitEnabled, BoolValue _ -> true
  | DoublePressEnabled, BoolValue _ -> true
  | AppearEnabled, BoolValue _ -> true
  | ImageIdValue, IntValue value -> value >= 0
  | SurfaceIdValue, IntValue value -> value >= 0
  | ActiveIndex, IntValue value -> value >= 0
  | TitleValue, StringValue _ -> true
  | DescriptionValue, StringValue _ -> true
  | MetaValue, StringValue _ -> true
  | IndicatorValue, StringValue _ -> true
  | Connector, BoolValue _ -> true
  | SourceX, FloatValue value
  | SourceY, FloatValue value
  | SourceWidth, FloatValue value
  | SourceHeight, FloatValue value -> is_finite value
  | AnchorValue, StringValue value ->
    value = "above" || value = "below" || value = "left" || value = "right"
  | AnchorAlignmentValue, StringValue value ->
    value = "start" || value = "end" || value = "stretch"
  | AnchorOffset, FloatValue _ -> true
  | TooltipDelay, IntValue value | DurationValue, IntValue value ->
    value >= 0 && value <= 2147483647
  | TextAlignment, StringValue value ->
    value = "start" || value = "center" || value = "end"
  | RoleValue, StringValue value ->
    value = "treeitem" || value = "navigation"
    || value = "navigation-heading"
  | TreeLevel, IntValue value -> value > 0
  | Expanded, BoolValue _ -> true
  | ResizeDuration, IntValue value -> value >= 0
  | ResizeEasing, StringValue value ->
    value = "linear" || value = "standard" || value = "emphasized"
    || value = "spring"
  | ResizeOrigin, FloatValue value -> is_finite value
  | _ -> false

let property_value_supported_for_kind kind property value =
  if property = SizeValue then
    match value with
    | StringValue size ->
      if kind = TableCell then
        control_size_supported size || size = "heading" || size = "display"
      else control_size_supported size
    | _ -> false
  else property_value_supported property value

let int_property properties property fallback =
  match Property_map.find_opt property properties with
  | Some (IntValue number) -> number
  | _ -> fallback

let float_property properties property fallback =
  match Property_map.find_opt property properties with
  | Some (FloatValue number) -> number
  | _ -> fallback

let size_axis_supported properties fixed_property min_property max_property =
  let minimum = int_property properties min_property 0 in
  let fixed = int_property properties fixed_property minimum in
  fixed >= minimum
  &&
  match Property_map.find_opt max_property properties with
  | Some (IntValue maximum) -> minimum <= maximum && fixed <= maximum
  | Some _ -> false
  | None -> true

let surface_size_supported properties =
  size_axis_supported properties WidthValue MinWidth MaxWidth
  && size_axis_supported properties HeightValue MinHeight MaxHeight

let string_property_or properties property fallback =
  match Property_map.find_opt property properties with
  | Some (StringValue value) -> value
  | _ -> fallback

let string_property_nonempty properties property =
  match Property_map.find_opt property properties with
  | Some (StringValue value) -> value <> ""
  | _ -> false

let float_property_of properties property fallback =
  match Property_map.find_opt property properties with
  | Some (FloatValue number) -> number
  | _ -> fallback

let node_properties_supported kind properties =
  surface_size_supported properties
  && (if kind = Icon then
        match Property_map.find_opt IconName properties with
        | Some name -> property_value_supported IconName name
        | None -> false
      else true)
  && (if kind = Button || kind = ToggleButton || kind = Toggle || kind = Radio
      then
        let text = string_property_or properties TextValue "" in
        let label = string_property_or properties AccessibilityLabel "" in
        let icon = string_property_or properties InlineIconName "" in
        (text <> "" || label <> "")
        && (if text = "" && icon <> "" then label <> "" else true)
      else true)
  && (if kind = RadioGroup || kind = Slider then
        string_property_nonempty properties AccessibilityLabel
      else true)
  && (if kind = Select || kind = Combobox then
        let text = string_property_or properties TextValue "" in
        let placeholder = string_property_or properties PlaceholderValue "" in
        text <> "" || placeholder <> ""
      else true)
  && (if kind = MenuItem || kind = Accordion then
        string_property_nonempty properties TextValue
      else true)
  && (if modal_surface kind then string_property_nonempty properties TextValue
      else true)
  && (if kind = Tooltip then
        string_property_nonempty properties TextValue
        && (if Property_map.mem TooltipDelay properties then
              Property_map.mem AnchorValue properties
            else true)
      else true)
  && (if kind = DropdownMenu || kind = Tooltip then
        if Property_map.mem AnchorAlignmentValue properties
           || Property_map.mem AnchorOffset properties
        then Property_map.mem AnchorValue properties
        else true
      else true)
  && (if kind = Avatar || kind = Image then
        let has_image = Property_map.mem ImageIdValue properties in
        let has_source_x = Property_map.mem SourceX properties in
        let has_source_y = Property_map.mem SourceY properties in
        let has_source_width = Property_map.mem SourceWidth properties in
        let has_source_height = Property_map.mem SourceHeight properties in
        let source_count =
          (if has_source_x then 1 else 0)
          + (if has_source_y then 1 else 0)
          + (if has_source_width then 1 else 0)
          + (if has_source_height then 1 else 0)
        in
        let source_x = float_property_of properties SourceX 0.0 in
        let source_y = float_property_of properties SourceY 0.0 in
        let source_width = float_property_of properties SourceWidth 0.0 in
        let source_height = float_property_of properties SourceHeight 0.0 in
        (if kind = Avatar then string_property_nonempty properties TextValue
         else has_image)
        && (source_count = 0 || source_count = 4)
        && (source_count = 0 || has_image)
        && (source_count = 0
           || (source_x >= 0.0 && source_y >= 0.0 && source_width > 0.0
              && source_height > 0.0))
      else true)
  && (if kind = MediaSurface then Property_map.mem SurfaceIdValue properties
      else true)
  && (if kind = Stepper then Property_map.mem ActiveIndex properties else true)
  && (if kind = Step || kind = TimelineItem || kind = BottomTabs then
        let property =
          if kind = Step then TextValue
          else if kind = TimelineItem then TitleValue
          else AccessibilityLabel
        in
        string_property_nonempty properties property
      else true)
  && (if kind = BottomTab then
        string_property_nonempty properties TitleValue
        && true_property properties PressEnabled
      else true)
  && (if kind = Slider || kind = Progress then
        match Property_map.find_opt ProgressValue properties with
        | Some (FloatValue _) -> true
        | _ -> false
      else true)
  && (if kind = Tree || kind = Toolbar then
        string_property_nonempty properties AccessibilityLabel
      else true)
  && (if kind = Split then
        let duration = int_property properties ResizeDuration 0 in
        (if Property_map.mem ResizeEasing properties then duration > 0 else true)
        &&
        if Property_map.mem ResizeOrigin properties then duration > 0 else true
      else true)
  &&
  if tree_row_kind kind then
    let treeitem = treeitem_properties properties in
    let has_tree_metadata =
      Property_map.mem TreeLevel properties
      || Property_map.mem Expanded properties
      || Property_map.mem ChangeEnabled properties
      || Property_map.mem ToggleEnabled properties
    in
    ((not has_tree_metadata) || treeitem)
    && (if Property_map.mem Expanded properties then
          true_property properties ToggleEnabled
        else true)
  else true

let can_contain_children kind =
  if horizontal_container kind || context_menu_leaf_host_kind kind then true
  else
    match kind with
    | Root
    | Row
    | Column
    | Grid
    | Stack
    | Panel
    | Card
    | Box
    | Scroll
    | ListContainer
    | VirtualList
    | RadioGroup
    | DropdownMenu
    | ContextMenu
    | ListItem
    | Dialog
    | Drawer
    | Sheet
    | Accordion
    | Table
    | TableRow
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
    | BottomTabs
    | BottomTab -> true
    | _ -> false

let child_kind_supported parent_kind child_kind =
  if child_kind = Root then false
  else if parent_kind = Root then true
  else if parent_kind = MenuItem then
    child_kind = ContextMenu || child_kind = DropdownMenu
  else if context_menu_leaf_host_kind parent_kind then child_kind = ContextMenu
  else
    match parent_kind with
    | Table -> child_kind = TableRow
    | TableRow -> child_kind = TableCell
    | BottomTabs -> child_kind = BottomTab
    | BottomTab -> child_kind <> BottomTab
    | Tree -> tree_row_kind child_kind
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
      | Divider -> true
      | _ -> false)
    | DropdownMenu | ContextMenu -> child_kind = MenuItem || child_kind = Divider
    | _ -> true

let create_node_op node kind = CreateNode (node, kind)

let create_extension_op node identifier fingerprint =
  CreateExtension (node, identifier, fingerprint)

let drop_node_op node = DropNode node

let set_prop_op node property value = SetProp (node, property, value)

let remove_prop_op node property = RemoveProp (node, property)

let set_extension_prop_op node property value =
  SetExtensionProp (node, property, value)

let remove_extension_prop_op node property = RemoveExtensionProp (node, property)

let insert_child_op parent child index = InsertChild (parent, child, index)

let remove_child_op parent child = RemoveChild (parent, child)

let move_child_op parent child index = MoveChild (parent, child, index)
