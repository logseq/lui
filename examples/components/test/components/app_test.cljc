(ns components.app-test
  (:require [clojure.test :refer [deftest is]]
            [lui.app :as driver]
            [lui.backend.flutter :as flutter]
            [lui.protocol :as proto]
            [components.app :as components]
            [components.extensions :as extensions]
            [components.model :as model]))

(defmacro assert-equal [expected actual message]
  `(is (= ~expected ~actual) ~message))

(defn creates-kind? [batches expected]
  (boolean
   (some
    (fn [batch]
      (some
       (fn [operation]
         (match operation
           (proto/CreateNode _node kind) (= kind expected)
           _ false))
       (:ops batch)))
    batches)))

(defn gallery-page-titles [batches]
  (let [operations (mapcat :ops batches)
        heading-nodes
        (keep
         (fn [operation]
           (match operation
             (proto/CreateNode node kind) (when (= kind proto/Heading) node)
             _ nil))
         operations)]
    (vec
     (keep
      (fn [operation]
        (match operation
          (proto/SetProp node property value)
          (when
           (and
            (= property proto/TextValue)
            (some (fn [heading-node] (= heading-node node)) heading-nodes))
           (match value
             (proto/StringValue title) title
             _ nil))
          _ nil))
      operations))))

(defn created-node-kinds [batches]
  (reduce
   (fn [result operation]
     (match operation
       (proto/CreateNode node kind) (assoc result node kind)
       _ result))
   {}
   (mapcat :ops batches)))

(defn heading-count-under [renderer kinds node]
  (+
   (if (= (get kinds node) proto/Heading) 1 0)
   (reduce
    +
    0
    (map
     (fn [child] (heading-count-under renderer kinds child))
     (flutter/children renderer node)))))

(def gallery-page-contract
  ["Row" "Column" "Grid" "Text" "Spacer"
   "Button" "ToggleButton" "ButtonGroup" "ToggleGroup"
   "Breadcrumb" "Pagination" "Tabs"
   "Badge" "Separator" "Skeleton" "Spinner" "Icon" "Progress"
   "Stepper" "Step" "Timeline" "TimelineItem"
   "Stack" "Panel" "Card" "Alert" "Bubble" "Reactions" "StatusBar"
   "Resizable" "Split" "Dialog" "Sheet" "List" "Scroll"
   "ListItem" "ContextMenu" "MenuItem" "Table" "TableRow" "TableCell"
   "Tree" "Avatar" "Image" "MediaSurface"
   "TextField" "Input" "SearchField" "Textarea"
   "InputGroup" "InputGroupActions" "Tooltip" "Toast" "Toolbar" "Accordion"
   "Select" "Combobox" "DropdownMenu" "Checkbox" "Switch"
   "Toggle" "RadioGroup" "Radio" "Slider"])

(deftest gallery-model-owns-the-shared-showcase-state
  (let [initial (model/initial)
        advanced (model/update initial model/AdvanceProgress)
        wrapped
        (model/update
         (record model/gallery-model
                 (gallery-disabled false)
                 (gallery-field-value "")
                 (gallery-checked false)
                 (gallery-progress 1.0)
                 (gallery-active-step 1)
                 (gallery-density "comfortable")
                 (gallery-volume 0.35)
                 (gallery-environment "Production")
                 (gallery-picker-query "")
                 (gallery-open-picker "none")
                 (gallery-document "Quarterly report.md")
                 (gallery-document-action "Selected Quarterly report.md")
                 (gallery-avatar-image 1)
                 (gallery-media-surface 1)
                 (gallery-tab "overview")
                 (gallery-dialog-open false)
                 (gallery-sheet-open false)
                 (gallery-toast-open false)
                 (gallery-toast-message "Saved")
                 (gallery-accordion-open false)
                 (gallery-split-fraction 0.35))
         model/AdvanceProgress)]
    (assert-equal false (:gallery-disabled initial) "controls start enabled")
    (assert-equal 0.3 (:gallery-progress initial) "progress has a visible start")
    (assert-equal "comfortable" (:gallery-density initial)
                  "radio group starts with a visible selection")
    (assert-equal 0.35 (:gallery-volume initial)
                  "slider starts with a fractional shared value")
    (assert-equal "Production" (:gallery-environment initial)
                  "picker starts with a visible selection")
    (assert-equal "none" (:gallery-open-picker initial)
                  "picker menu starts closed")
    (assert-equal "Quarterly report.md" (:gallery-document initial)
                  "list starts with one model-owned selection")
    (assert-equal 0 (:gallery-avatar-image initial)
                  "avatar starts on its initials fallback")
    (assert-equal 1 (:gallery-media-surface initial)
                  "the media producer targets one stable SurfaceId")
    (assert-equal "overview" (:gallery-tab initial)
                  "Tabs starts with one model-owned selection")
    (assert-equal false (:gallery-dialog-open initial)
                  "Dialog starts closed without a retained placeholder")
    (assert-equal false (:gallery-sheet-open initial)
                  "Sheet starts closed without a retained placeholder")
    (assert-equal false (:gallery-toast-open initial)
                  "Toast viewport starts empty")
    (assert-equal false (:gallery-accordion-open initial)
                  "Accordion starts collapsed under model control")
    (assert-equal 0.35 (:gallery-split-fraction initial)
                  "Split starts with a controlled first-pane fraction")
    (assert-equal
     "Context action: Rename"
     (:gallery-document-action
      (model/update initial (model/PerformContextAction "Rename")))
     "ContextMenu selection is owned by the shared reducer")
    (assert-equal true
                  (:gallery-accordion-open
                   (model/update initial (model/SetAccordionOpen true)))
                  "Accordion expansion is owned by the shared reducer")
    (assert-equal true
                  (:gallery-dialog-open
                   (model/update initial model/OpenDialog))
                  "the shared reducer owns Dialog presentation")
    (assert-equal false
                  (:gallery-dialog-open
                   (model/update
                    (model/update initial model/OpenDialog)
                    model/CloseDialog))
                  "native dismissal closes Dialog through the reducer")
    (assert-equal true
                  (:gallery-sheet-open
                   (model/update initial model/OpenSheet))
                  "the shared reducer owns Sheet presentation")
    (assert-equal false
                  (:gallery-sheet-open
                   (model/update
                    (model/update initial model/OpenSheet)
                    model/CloseSheet))
                  "native dismissal closes Sheet through the reducer")
    (let [activity (model/update initial (model/SelectTab "activity"))]
      (assert-equal true (model/activity-tab-selected? activity)
                    "the shared reducer controls the selected trigger")
      (assert-equal false (model/overview-tab-selected? activity)
                    "selecting one trigger clears its controlled sibling")
      (assert-equal "Recent retained updates" (model/tab-content activity)
                    "selected content is derived from the same shared state"))
    (assert-equal 1
                  (:gallery-avatar-image
                   (model/update initial model/ToggleAvatarImage))
                  "the shared reducer adopts the host-registered ImageId")
    (assert-equal 0.4 (:gallery-progress advanced) "progress advances by a tenth")
    (assert-equal
     2
     (:gallery-active-step (model/update initial model/AdvanceStep))
     "Stepper progress is owned by the shared reducer")
    (assert-equal 0.0 (:gallery-progress wrapped) "progress wraps after completion")
    (assert-equal
     "draft@example.com"
     (:gallery-field-value
      (model/update initial (model/SetFieldValue "draft@example.com")))
     "text input state is shared across every host")
    (assert-equal
     "compact"
     (:gallery-density (model/update initial (model/SetDensity "compact")))
     "radio selection is owned by the shared reducer")
    (assert-equal
     0.8
     (:gallery-volume (model/update initial (model/SetVolume 0.8)))
     "slider value is owned by the shared reducer")
    (assert-equal
     0.42
     (:gallery-split-fraction
      (model/update initial (model/SetSplitFraction 0.42)))
     "Split resize echoes remain in the shared reducer")
    (assert-equal
     "select"
     (:gallery-open-picker
      (model/update initial (model/OpenPicker "select")))
     "picker visibility is owned by the shared reducer")
    (let [selected
          (model/update initial (model/SelectEnvironment "Staging"))]
      (assert-equal "Staging" (:gallery-environment selected)
                    "menu item selection updates the shared model")
      (assert-equal "none" (:gallery-open-picker selected)
                    "selection closes the retained menu segment"))
    (let [committed
          (model/update
           (model/update initial (model/SetPickerQuery "Preview"))
           model/CommitPickerQuery)]
      (assert-equal "Preview" (:gallery-environment committed)
                    "combobox submit commits its controlled query")
      (assert-equal "none" (:gallery-open-picker committed)
                    "combobox submit closes its menu"))
    (let [selected
          (model/update initial (model/SelectDocument "Launch checklist.md"))
          opened
          (model/update selected (model/OpenDocument "Launch checklist.md"))]
      (assert-equal "Launch checklist.md" (:gallery-document selected)
                    "list-item press owns selection in the shared reducer")
      (assert-equal "Opened Launch checklist.md" (:gallery-document-action opened)
                    "double press and Enter share the primary action"))))

(deftest native-gallery-app-batches-actions-and-disposes-the-retained-tree
  (let [renderer (flutter/create)
        application (components/create (flutter/backend renderer))]
    (driver/start! application)
    (driver/flush! application)
    (is (> (flutter/node-count renderer) 30)
        "the native gallery mounts the complete shared component source")
    (is (creates-kind? (flutter/batches renderer) proto/ButtonGroup)
        "the shared Gallery demonstrates ButtonGroup")
    (is (creates-kind? (flutter/batches renderer) proto/ToggleGroup)
        "the shared Gallery demonstrates ToggleGroup")
    (is (creates-kind? (flutter/batches renderer) proto/Breadcrumb)
        "the shared Gallery demonstrates Breadcrumb composition")
    (is (creates-kind? (flutter/batches renderer) proto/Pagination)
        "the shared Gallery demonstrates Pagination composition")
    (is (creates-kind? (flutter/batches renderer) proto/Tooltip)
        "the shared Gallery demonstrates static and anchored Tooltip")
    (is (creates-kind? (flutter/batches renderer) proto/Accordion)
        "the shared Gallery demonstrates controlled Accordion")
    (is (creates-kind? (flutter/batches renderer) proto/Table)
        "the shared Gallery demonstrates semantic Table")
    (is (creates-kind? (flutter/batches renderer) proto/TableRow)
        "the shared Gallery demonstrates retained TableRow")
    (is (creates-kind? (flutter/batches renderer) proto/TableCell)
        "the shared Gallery demonstrates pressable TableCell")
    (is (creates-kind? (flutter/batches renderer) proto/Tree)
        "the shared Gallery demonstrates retained Tree navigation")
    (is (creates-kind? (flutter/batches renderer) proto/Resizable)
        "the shared Gallery demonstrates backend-owned Resizable geometry")
    (is (creates-kind? (flutter/batches renderer) proto/Split)
        "the shared Gallery demonstrates controlled two-pane Split geometry")
    (is (creates-kind? (flutter/batches renderer) proto/ContextMenu)
        "the shared Gallery demonstrates retained ContextMenu metadata")
    (is (creates-kind? (flutter/batches renderer) proto/Alert)
        "the shared Gallery demonstrates Alert")
    (is (creates-kind? (flutter/batches renderer) proto/Bubble)
        "the shared Gallery demonstrates Bubble and Reactions chrome")
    (is (creates-kind? (flutter/batches renderer) proto/StatusBar)
        "the shared Gallery demonstrates StatusBar")
    (is (creates-kind? (flutter/batches renderer) proto/Image)
        "the shared Gallery demonstrates registered Image pixels")
    (is (creates-kind? (flutter/batches renderer) proto/MediaSurface)
        "the shared Gallery demonstrates a producer-owned media frame")
    (is (creates-kind? (flutter/batches renderer) proto/Stepper)
        "the shared Gallery demonstrates controlled stage progress")
    (is (creates-kind? (flutter/batches renderer) proto/Step)
        "the shared Gallery demonstrates semantic Step labels")
    (is (creates-kind? (flutter/batches renderer) proto/Timeline)
        "the shared Gallery demonstrates a retained activity list")
    (is (creates-kind? (flutter/batches renderer) proto/TimelineItem)
        "the shared Gallery demonstrates pressable TimelineItem rows")
    (is (creates-kind? (flutter/batches renderer) proto/InputGroup)
        "the shared Gallery demonstrates one composer field")
    (is (creates-kind? (flutter/batches renderer) proto/InputGroupActions)
        "the shared Gallery demonstrates retained composer accessories")
    (assert-equal 1 (count (flutter/batches renderer)) "mount is one batch")
    (let [mounted-count (flutter/node-count renderer)]
      (driver/send! application model/ToggleDisabled)
      (driver/flush! application)
      (assert-equal
       (inc mounted-count) (flutter/node-count renderer)
       "a shared Signal action mounts only the conditional status node"))
    (assert-equal
     true
     (:gallery-disabled (components/model application))
     "the shared reducer owns disabled state")
    (driver/send! application (model/SetChecked true))
    (driver/flush! application)
    (assert-equal
     true
     (:gallery-checked (components/model application))
     "toggle state is shared across hosts")
    (let [mounted-count (flutter/node-count renderer)
          batch-count (count (flutter/batches renderer))]
      (driver/send! application (model/SelectTab "activity"))
      (driver/flush! application)
      (assert-equal
       mounted-count (flutter/node-count renderer)
       "tab selection patches retained triggers and content without remounting")
      (assert-equal
       (inc batch-count) (count (flutter/batches renderer))
       "one shared tab action produces one atomic backend batch")
      (assert-equal
       "activity" (:gallery-tab (components/model application))
       "the shared reducer owns tab selection across hosts"))
    (let [mounted-count (flutter/node-count renderer)]
      (driver/send! application model/OpenDialog)
      (driver/flush! application)
      (is (creates-kind? (flutter/batches renderer) proto/Dialog)
          "the shared Gallery mounts the semantic Dialog node")
      (is (> (flutter/node-count renderer) mounted-count)
          "opening mounts only the Dialog retained subtree")
      (driver/send! application model/CloseDialog)
      (driver/flush! application)
      (assert-equal mounted-count (flutter/node-count renderer)
                    "closing removes the Dialog subtree without placeholders"))
    (let [mounted-count (flutter/node-count renderer)]
      (driver/send! application model/OpenSheet)
      (driver/flush! application)
      (is (creates-kind? (flutter/batches renderer) proto/Sheet)
          "the shared Gallery mounts the semantic Sheet node")
      (is (> (flutter/node-count renderer) mounted-count)
          "opening mounts only the Sheet retained subtree")
      (driver/send! application model/CloseSheet)
      (driver/flush! application)
      (assert-equal mounted-count (flutter/node-count renderer)
                    "closing removes the Sheet subtree without placeholders"))
    (driver/dispose! application)
    (assert-equal 0 (flutter/node-count renderer) "dispose drops every retained node")
    (is (driver/disposed? application) "the native gallery lifecycle terminates")))

(deftest gallery-has-one-page-for-every-public-component
  (let [renderer (flutter/create)
        application (components/create (flutter/backend renderer))]
    (driver/start! application)
    (driver/flush! application)
    (assert-equal
     gallery-page-contract
     (gallery-page-titles (flutter/batches renderer))
     "the retained Gallery exposes every public component on exactly one page")
    (let [batches (flutter/batches renderer)
          kinds (created-node-kinds batches)
          pages (flutter/children renderer (driver/root-node application))]
      (assert-equal
       (count gallery-page-contract)
       (count pages)
       "every component page is a direct child of the shared Gallery root")
      (is
       (every?
        (fn [page] (= 1 (heading-count-under renderer kinds page)))
        pages)
       "each direct Gallery page contains exactly one component heading"))
    (driver/dispose! application)))

(deftest extended-gallery-adds-one-platform-native-page
  (let [registry (extensions/registry)
        renderer (flutter/create-with-extensions registry)
        application
        (components/create-with-extensions
         (flutter/backend-for renderer proto/AndroidOS) registry)]
    (driver/start! application)
    (driver/flush! application)
    (assert-equal
     (conj gallery-page-contract "NativeExtension")
     (gallery-page-titles (flutter/batches renderer))
     "the platform host adds one extension page without merging standard pages")
    (assert-equal
     (inc (count gallery-page-contract))
     (count (flutter/children renderer (driver/root-node application)))
     "the native extension is a direct selectable Gallery page")
    (driver/dispose! application)))
