(ns components.app-test
  (:require [clojure.test :refer [deftest is]]
            [lui.app :as driver]
            [lui.backend.flutter :as flutter]
            [lui.protocol :as proto]
            [components.app :as components]
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
                 (gallery-density "comfortable")
                 (gallery-volume 0.35)
                 (gallery-environment "Production")
                 (gallery-picker-query "")
                 (gallery-open-picker "none")
                 (gallery-document "Quarterly report.md")
                 (gallery-document-action "Selected Quarterly report.md")
                 (gallery-avatar-image 1)
                 (gallery-tab "overview")
                 (gallery-dialog-open false)
                 (gallery-drawer-open false)
                 (gallery-sheet-open false)
                 (gallery-accordion-open false))
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
    (assert-equal "overview" (:gallery-tab initial)
                  "Tabs starts with one model-owned selection")
    (assert-equal false (:gallery-dialog-open initial)
                  "Dialog starts closed without a retained placeholder")
    (assert-equal false (:gallery-drawer-open initial)
                  "Drawer starts closed without a retained placeholder")
    (assert-equal false (:gallery-sheet-open initial)
                  "Sheet starts closed without a retained placeholder")
    (assert-equal false (:gallery-accordion-open initial)
                  "Accordion starts collapsed under model control")
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
                  (:gallery-drawer-open
                   (model/update initial model/OpenDrawer))
                  "the shared reducer owns Drawer presentation")
    (assert-equal false
                  (:gallery-drawer-open
                   (model/update
                    (model/update initial model/OpenDrawer)
                    model/CloseDrawer))
                  "native dismissal closes Drawer through the reducer")
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
      (driver/send! application model/OpenDrawer)
      (driver/flush! application)
      (is (creates-kind? (flutter/batches renderer) proto/Drawer)
          "the shared Gallery mounts the semantic Drawer node")
      (is (> (flutter/node-count renderer) mounted-count)
          "opening mounts only the Drawer retained subtree")
      (driver/send! application model/CloseDrawer)
      (driver/flush! application)
      (assert-equal mounted-count (flutter/node-count renderer)
                    "closing removes the Drawer subtree without placeholders"))
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
