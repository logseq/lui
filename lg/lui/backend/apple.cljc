(ns lui.backend.apple
  (:require [lui.protocol :as proto
             :refer [Row Column Grid Stack Panel Card Box
                     Text Heading Paragraph Label Button ToggleButton
                     TextField Input SearchField Textarea
                     Scroll ListContainer Tabs ButtonGroup ToggleGroup Breadcrumb Pagination
                     Spacer Spinner Icon
                     Checkbox SwitchControl
                     Progress Divider Toggle RadioGroup Radio Slider
                     Select Combobox DropdownMenu MenuItem ListItem Avatar]]
            [lui.backend.retained :as retained]
            [lui.wire :as wire]))

(defn create
  ([] (create (fn [_batch] true)))
  ([send-batch]
   (record apple-renderer
           (apple-store (retained/create-store))
           (apple-send-batch send-batch))))

(defn create-wire [send-json]
  (create (fn [batch] (send-json (wire/encode-batch batch)))))

(defn- platform-node [kind]
  (match kind
    Row AppleRow
    Column AppleColumn
    Grid AppleGrid
    Stack AppleStack
    Panel ApplePanel
    Card AppleCard
    Box AppleBox
    Text AppleLabel
    Heading AppleHeading
    Paragraph AppleParagraph
    Label AppleFormLabel
    Button AppleButton
    ToggleButton AppleToggleButton
    TextField AppleTextInput
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
    Tabs AppleTabs
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
    MenuItem AppleMenuItem
    ListItem AppleListItem
    Avatar AppleAvatar))

(defn backend-for [renderer operating-system host]
  (record proto/backend
          (backend-profile (proto/profile operating-system host))
          (apply-batch
           (fn [batch]
             (retained/apply-batch-with!
              (:apple-store renderer) platform-node
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
