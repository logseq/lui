(ns lui.backend.apple
  (:require [lui.protocol :as proto
             :refer [Root Row Column Grid Stack Panel Card Alert Bubble Box
                     Text Heading Paragraph Label Button ToggleButton
                     TextField SecureField Input SearchField Textarea
                     Scroll ListContainer VirtualList Tabs BottomTabs BottomTab ButtonGroup ToggleGroup Breadcrumb Pagination
                     Spacer Spinner Icon
                     Checkbox SwitchControl
                     Progress Divider Toggle RadioGroup Radio Slider
                     Select Combobox DropdownMenu ContextMenu MenuItem ListItem Avatar Image MediaSurface Stepper Step Timeline TimelineItem InputGroup InputGroupActions Dialog Drawer Sheet Tooltip Toast Toolbar
                     Accordion Table TableRow TableCell Tree Resizable Split StatusBar]]
            [lui.backend.retained :as retained]
            [lui.extension :as ext]
            [lui.wire :as wire]))

(defn create-with-extensions
  ([registry] (create-with-extensions (fn [_batch] true) registry))
  ([send-batch registry]
   (record apple-renderer
           (apple-store (retained/create-store))
           (apple-send-batch send-batch)
           (apple-extension-registry registry))))

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
    Root AppleRoot
    Row AppleRow
    Column AppleColumn
    Grid AppleGrid
    Stack AppleStack
    Panel ApplePanel
    Card AppleCard
    Alert AppleAlert
    Bubble AppleBubble
    Box AppleBox
    Text AppleLabel
    Heading AppleHeading
    Paragraph AppleParagraph
    Label AppleFormLabel
    Button AppleButton
    ToggleButton AppleToggleButton
    TextField AppleTextInput
    SecureField AppleTextInput
    Input AppleTextInput
    SearchField AppleTextInput
    Textarea AppleTextArea
    Checkbox AppleCheckbox
    SwitchControl AppleSwitch
    Progress AppleProgress
    Toggle AppleToggle
    RadioGroup AppleRadioGroup
    Radio AppleRadio
    Slider AppleSlider
    Divider AppleDivider
    Scroll AppleScrollView
    ListContainer AppleList
    VirtualList AppleVirtualList
    Tabs AppleTabs
    BottomTabs AppleBottomTabs
    BottomTab AppleBottomTab
    ButtonGroup AppleButtonGroup
    ToggleGroup AppleToggleGroup
    Breadcrumb AppleBreadcrumb
    Pagination ApplePagination
    Spacer AppleSpacer
    Spinner AppleSpinner
    Icon AppleIcon
    Select AppleSelect
    Combobox AppleCombobox
    DropdownMenu AppleDropdownMenu
    ContextMenu AppleContextMenu
    MenuItem AppleMenuItem
    ListItem AppleListItem
    Avatar AppleAvatar
    Image AppleImage
    MediaSurface AppleMediaSurface
    Stepper AppleStepper
    Step AppleStep
    Timeline AppleTimeline
    TimelineItem AppleTimelineItem
    InputGroup AppleInputGroup
    InputGroupActions AppleInputGroupActions
    Dialog AppleDialog
    Drawer AppleDrawer
    Sheet AppleSheet
    Tooltip AppleTooltip
    Toast AppleToast
    Toolbar AppleToolbar
    Accordion AppleAccordion
    Table AppleTable
    TableRow AppleTableRow
    TableCell AppleTableCell
    Tree AppleTree
    Resizable AppleResizable
    Split AppleSplit
    StatusBar AppleStatusBar))

(defn- extension-platform-node [_node identifier]
  (AppleExtension identifier))

(defn backend-for [renderer operating-system host]
  (record proto/backend
          (backend-profile (proto/profile operating-system host))
          (apply-batch
           (fn [batch]
             (retained/apply-batch-with-extensions!
              (:apple-store renderer) platform-node extension-platform-node
              (:apple-extension-registry renderer)
              (:apple-send-batch renderer) batch)))))

(defn backend [renderer]
  (backend-for renderer proto/MacOS proto/SwiftUIHost))

(defn- some-node [value]
  (Some value))

(defn node [renderer node]
  (match (retained/node (:apple-store renderer) node)
    (Some current) (some-node (:platform-node current))
    None None))

(defn property [renderer node property]
  (retained/property (:apple-store renderer) node property))

(defn children [renderer node]
  (retained/children (:apple-store renderer) node))

(defn node-count [renderer]
  (retained/node-count (:apple-store renderer)))

(defn batches [renderer]
  (retained/batches (:apple-store renderer)))
