(* ns lui.backend.flutter *)

type flutter_node =
  | FlutterRoot
  | FlutterFlexRow
  | FlutterFlexColumn
  | FlutterGrid
  | FlutterStack
  | FlutterPanel
  | FlutterCard
  | FlutterAlert
  | FlutterBubble
  | FlutterBox
  | FlutterParagraph
  | FlutterHeading
  | FlutterFormLabel
  | FlutterButton
  | FlutterToggleButton
  | FlutterWidgetIsland
  | FlutterCheckbox
  | FlutterSwitch
  | FlutterProgress
  | FlutterToggle
  | FlutterRadioGroup
  | FlutterRadio
  | FlutterSlider
  | FlutterDivider
  | FlutterViewport
  | FlutterList
  | FlutterVirtualList
  | FlutterTabs
  | FlutterBottomTabs
  | FlutterBottomTab
  | FlutterButtonGroup
  | FlutterToggleGroup
  | FlutterBreadcrumb
  | FlutterPagination
  | FlutterSpacer
  | FlutterSpinner
  | FlutterIcon
  | FlutterSelect
  | FlutterCombobox
  | FlutterDropdownMenu
  | FlutterContextMenu
  | FlutterMenuItem
  | FlutterListItem
  | FlutterAvatar
  | FlutterImage
  | FlutterMediaSurface
  | FlutterStepper
  | FlutterStep
  | FlutterTimeline
  | FlutterTimelineItem
  | FlutterInputGroup
  | FlutterInputGroupActions
  | FlutterDialog
  | FlutterDrawer
  | FlutterSheet
  | FlutterTooltip
  | FlutterToast
  | FlutterToolbar
  | FlutterAccordion
  | FlutterTable
  | FlutterTableRow
  | FlutterTableCell
  | FlutterTree
  | FlutterResizable
  | FlutterSplit
  | FlutterStatusBar
  | FlutterExtension of string

type flutter_renderer = { flutter_store : flutter_node retained_store ; flutter_send_batch : patch_batch -> bool ; flutter_extension_registry : extension_registry }

val create : (unit -> flutter_renderer) * (((patch_batch -> bool) -> flutter_renderer) * unit)

val create_with_extensions : (extension_registry -> flutter_renderer) * (((patch_batch -> bool) -> extension_registry -> flutter_renderer) * unit)

val create_wire : (string -> bool) -> flutter_renderer

val create_wire_with_extensions : (string -> bool) -> extension_registry -> flutter_renderer

val backend_for_profile : flutter_renderer -> platform_profile -> backend

val platform_node : node_kind -> flutter_node

val extension_platform_node : int -> string -> flutter_node

val backend_for : flutter_renderer -> operating_system -> backend

val backend : flutter_renderer -> backend

val some_node : flutter_node -> flutter_node option

val node : flutter_renderer -> int -> flutter_node option

val property : flutter_renderer -> int -> property -> wire_value option

val children : flutter_renderer -> int -> int Rrbvec.t

val node_count : flutter_renderer -> int

val batches : flutter_renderer -> patch_batch Rrbvec.t

