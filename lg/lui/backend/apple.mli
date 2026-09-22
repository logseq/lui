(* ns lui.backend.apple *)

type apple_node =
  | AppleRoot
  | AppleRow
  | AppleColumn
  | AppleGrid
  | AppleStack
  | ApplePanel
  | AppleCard
  | AppleAlert
  | AppleBubble
  | AppleBox
  | AppleLabel
  | AppleHeading
  | AppleParagraph
  | AppleFormLabel
  | AppleButton
  | AppleToggleButton
  | AppleTextInput
  | AppleTextArea
  | AppleCheckbox
  | AppleSwitch
  | AppleProgress
  | AppleToggle
  | AppleRadioGroup
  | AppleRadio
  | AppleSlider
  | AppleDivider
  | AppleScrollView
  | AppleList
  | AppleVirtualList
  | AppleTabs
  | AppleBottomTabs
  | AppleBottomTab
  | AppleButtonGroup
  | AppleToggleGroup
  | AppleBreadcrumb
  | ApplePagination
  | AppleSpacer
  | AppleSpinner
  | AppleIcon
  | AppleSelect
  | AppleCombobox
  | AppleDropdownMenu
  | AppleContextMenu
  | AppleMenuItem
  | AppleListItem
  | AppleAvatar
  | AppleImage
  | AppleMediaSurface
  | AppleStepper
  | AppleStep
  | AppleTimeline
  | AppleTimelineItem
  | AppleInputGroup
  | AppleInputGroupActions
  | AppleDialog
  | AppleDrawer
  | AppleSheet
  | AppleTooltip
  | AppleToast
  | AppleToolbar
  | AppleAccordion
  | AppleTable
  | AppleTableRow
  | AppleTableCell
  | AppleTree
  | AppleResizable
  | AppleSplit
  | AppleStatusBar
  | AppleExtension of string

type apple_renderer = { apple_store : apple_node retained_store ; apple_send_batch : patch_batch -> bool ; apple_extension_registry : extension_registry }

val create : (unit -> apple_renderer) * (((patch_batch -> bool) -> apple_renderer) * unit)

val create_with_extensions : (extension_registry -> apple_renderer) * (((patch_batch -> bool) -> extension_registry -> apple_renderer) * unit)

val create_wire : (string -> bool) -> apple_renderer

val create_wire_with_extensions : (string -> bool) -> extension_registry -> apple_renderer

val platform_node : node_kind -> apple_node

val extension_platform_node : int -> string -> apple_node

val backend_for : apple_renderer -> operating_system -> host_kind -> backend

val backend : apple_renderer -> backend

val some_node : apple_node -> apple_node option

val node : apple_renderer -> int -> apple_node option

val property : apple_renderer -> int -> property -> wire_value option

val children : apple_renderer -> int -> int Rrbvec.t

val node_count : apple_renderer -> int

val batches : apple_renderer -> patch_batch Rrbvec.t

