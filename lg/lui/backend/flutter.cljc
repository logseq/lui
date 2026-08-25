(ns lui.backend.flutter
  (:require [lui.protocol :as proto
             :refer [Root Row Column Grid Stack Panel Card Alert Bubble Box
                     Text Heading Paragraph Label Button ToggleButton
                     TextField Input SearchField Textarea
                     Scroll ListContainer Tabs ButtonGroup ToggleGroup Breadcrumb Pagination
                     Spacer Spinner Icon
                     Checkbox SwitchControl
                     Progress Divider Toggle RadioGroup Radio Slider
                     Select Combobox DropdownMenu ContextMenu MenuItem ListItem Avatar Image MediaSurface Stepper Step Timeline TimelineItem InputGroup InputGroupActions Dialog Sheet Tooltip Toast Toolbar
                     Accordion Table TableRow TableCell Tree Resizable Split StatusBar]]
            [lui.backend.retained :as retained]
            [lui.extension :as ext]
            [lui.wire :as wire]))

(defn create-with-extensions
  ([registry] (create-with-extensions (fn [_batch] true) registry))
  ([send-batch registry]
   (record flutter-renderer
           (flutter-store (retained/create-store))
           (flutter-send-batch send-batch)
           (flutter-extension-registry registry))))

(defn create
  ([] (create (fn [_batch] true)))
  ([send-batch] (create-with-extensions send-batch (ext/registry))))

(defn create-wire [send-json]
  (create (fn [batch] (send-json (wire/encode-batch batch)))))

(defn create-wire-with-extensions [send-json registry]
  (create-with-extensions
   (fn [batch] (send-json (wire/encode-batch batch))) registry))

(defn- platform-node [kind]
  (match kind
    Root FlutterRoot
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
    Stepper FlutterStepper
    Step FlutterStep
    Timeline FlutterTimeline
    TimelineItem FlutterTimelineItem
    InputGroup FlutterInputGroup
    InputGroupActions FlutterInputGroupActions
    Dialog FlutterDialog
    Sheet FlutterSheet
    Tooltip FlutterTooltip
    Toast FlutterToast
    Toolbar FlutterToolbar
    Accordion FlutterAccordion
    Table FlutterTable
    TableRow FlutterTableRow
    TableCell FlutterTableCell
    Tree FlutterTree
    Resizable FlutterResizable
    Split FlutterSplit
    StatusBar FlutterStatusBar))

(defn- extension-platform-node [_node identifier]
  (FlutterExtension identifier))

(defn backend-for-profile [renderer profile]
  (record proto/backend
          (backend-profile profile)
          (apply-batch
           (fn [batch]
             (retained/apply-batch-with-extensions!
              (:flutter-store renderer) platform-node extension-platform-node
              (:flutter-extension-registry renderer)
              (:flutter-send-batch renderer) batch)))))

(defn backend-for [renderer operating-system]
  (backend-for-profile
   renderer (proto/profile operating-system proto/FlutterHost)))

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
