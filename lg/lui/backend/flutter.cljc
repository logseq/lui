(ns lui.backend.flutter
  (:require [lui.protocol :as proto
             :refer [Row Column Grid Stack Panel Card Alert Bubble Box
                     Text Heading Paragraph Label Button ToggleButton
                     TextField Input SearchField Textarea
                     Scroll ListContainer Tabs ButtonGroup ToggleGroup Breadcrumb Pagination
                     Spacer Spinner Icon
                     Checkbox SwitchControl
                     Progress Divider Toggle RadioGroup Radio Slider
                     Select Combobox DropdownMenu ContextMenu MenuItem ListItem Avatar Image MediaSurface Dialog Drawer Sheet Tooltip
                     Accordion Table TableRow TableCell Tree Resizable Split StatusBar]]
            [lui.backend.retained :as retained]
            [lui.wire :as wire]))

(defn create
  ([] (create (fn [_batch] true)))
  ([send-batch]
   (record flutter-renderer
           (flutter-store (retained/create-store))
           (flutter-send-batch send-batch))))

(defn create-wire [send-json]
  (create (fn [batch] (send-json (wire/encode-batch batch)))))

(defn- platform-node [kind]
  (match kind
    Row FlutterFlexRow
    Column FlutterFlexColumn
    Grid FlutterGrid
    Stack FlutterStack
    Panel FlutterPanel
    Card FlutterCard
    Alert FlutterAlert
    Bubble FlutterBubble
    Box FlutterBox
    Text FlutterParagraph
    Heading FlutterHeading
    Paragraph FlutterParagraph
    Label FlutterFormLabel
    Button FlutterButton
    ToggleButton FlutterToggleButton
    TextField FlutterWidgetIsland
    Input FlutterWidgetIsland
    SearchField FlutterWidgetIsland
    Textarea FlutterWidgetIsland
    Checkbox FlutterCheckbox
    SwitchControl FlutterSwitch
    Progress FlutterProgress
    Toggle FlutterToggle
    RadioGroup FlutterRadioGroup
    Radio FlutterRadio
    Slider FlutterSlider
    Divider FlutterDivider
    Scroll FlutterViewport
    ListContainer FlutterList
    Tabs FlutterTabs
    ButtonGroup FlutterButtonGroup
    ToggleGroup FlutterToggleGroup
    Breadcrumb FlutterBreadcrumb
    Pagination FlutterPagination
    Spacer FlutterSpacer
    Spinner FlutterSpinner
    Icon FlutterIcon
    Select FlutterSelect
    Combobox FlutterCombobox
    DropdownMenu FlutterDropdownMenu
    ContextMenu FlutterContextMenu
    MenuItem FlutterMenuItem
    ListItem FlutterListItem
    Avatar FlutterAvatar
    Image FlutterImage
    MediaSurface FlutterMediaSurface
    Dialog FlutterDialog
    Drawer FlutterDrawer
    Sheet FlutterSheet
    Tooltip FlutterTooltip
    Accordion FlutterAccordion
    Table FlutterTable
    TableRow FlutterTableRow
    TableCell FlutterTableCell
    Tree FlutterTree
    Resizable FlutterResizable
    Split FlutterSplit
    StatusBar FlutterStatusBar))

(defn backend-for [renderer operating-system]
  (record proto/backend
          (backend-profile (proto/profile operating-system proto/FlutterHost))
          (apply-batch
           (fn [batch]
             (retained/apply-batch-with!
              (:flutter-store renderer) platform-node
              (:flutter-send-batch renderer) batch)))))

(defn backend [renderer]
  (backend-for renderer proto/GenericOS))

(defn- some-node [value]
  (Some value))

(defn node [renderer node]
  (match (retained/node (:flutter-store renderer) node)
    (Some current) (some-node (:platform-node current))
    None None))

(defn property [renderer node property]
  (retained/property (:flutter-store renderer) node property))

(defn children [renderer node]
  (retained/children (:flutter-store renderer) node))

(defn node-count [renderer]
  (retained/node-count (:flutter-store renderer)))

(defn batches [renderer]
  (retained/batches (:flutter-store renderer)))
