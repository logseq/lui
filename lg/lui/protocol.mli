(* Generated from schema/components.json. Do not edit by hand. *)
(* ns lui.protocol *)

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

type platform_profile = { profile_os : operating_system ; profile_host : host_kind }

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
  | ExtensionEvent of int * string * string * (string, wire_value) Lg_runtime.Runtime_map.t

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

type patch_batch = { generation : int ; ops : patch_op Rrbvec.t }

type backend = { backend_profile : platform_profile ; apply_batch : patch_batch -> bool }

val profile : operating_system -> host_kind -> platform_profile
val generic_profile : unit -> platform_profile
val event_node : event -> int
val tree_row_kind_ : node_kind -> bool
val event_supported_ : node_kind -> event -> bool
val event_supported_for_properties_ : node_kind -> (property, wire_value) Lg_runtime.Runtime_map.t -> event -> bool
val orientation_supported_ : string -> bool
val control_size_supported_ : string -> bool
val button_variant_supported_ : string -> bool
val icon_placement_supported_ : string -> bool
val icon_name_supported_ : string -> bool
val main_alignment_supported_ : string -> bool
val cross_alignment_supported_ : string -> bool
val property_supported_ : node_kind -> property -> bool
val property_value_supported_ : property -> wire_value -> bool
val property_value_supported_for_kind_ : node_kind -> property -> wire_value -> bool
val int_property : (property, wire_value) Lg_runtime.Runtime_map.t -> property -> int -> int
val surface_size_supported_ : (property, wire_value) Lg_runtime.Runtime_map.t -> bool
val node_properties_supported_ : node_kind -> (property, wire_value) Lg_runtime.Runtime_map.t -> bool
val can_contain_children_ : node_kind -> bool
val child_kind_supported_ : node_kind -> node_kind -> bool
val create_node_op : int -> node_kind -> patch_op
val create_extension_op : int -> string -> string -> patch_op
val drop_node_op : int -> patch_op
val set_prop_op : int -> property -> wire_value -> patch_op
val remove_prop_op : int -> property -> patch_op
val set_extension_prop_op : int -> string -> wire_value -> patch_op
val remove_extension_prop_op : int -> string -> patch_op
val insert_child_op : int -> int -> int -> patch_op
val remove_child_op : int -> int -> patch_op
val move_child_op : int -> int -> int -> patch_op
