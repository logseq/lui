(ns components.view
  (:require [lui.macros :refer [defui reactive]]
            [lui.protocol :refer [TextChanged ToggleChanged ValueChanged]]
            [components.gallery :as gallery]
            [components.model :as model]))

(defn card-copy [gallery-model]
  (if (:gallery-disabled gallery-model)
    "Signal patched this paragraph; the Card node stayed mounted."
    "Signals update retained content without rebuilding the Card."))

(defui gallery-view [model-source send]
  [gallery/component-gallery
   (reactive :gallery-disabled model-source)
   (fn [_event] (send model/ToggleDisabled))
   (reactive card-copy model-source)
   (reactive :gallery-field-value model-source)
   (fn [event]
     (match event
       (TextChanged _node text) (send (model/SetFieldValue text))
       _ true))
   (reactive :gallery-checked model-source)
   (fn [event]
     (match event
       (ToggleChanged _node checked) (send (model/SetChecked checked))
       _ true))
   (reactive :gallery-progress model-source)
   (reactive model/progress-label model-source)
   (fn [_event] (send model/AdvanceProgress))
   (reactive model/density-comfortable? model-source)
   (reactive model/density-compact? model-source)
   (reactive :gallery-volume model-source)
   (reactive model/volume-label model-source)
   (fn [_event] (send (model/SetDensity "comfortable")))
   (fn [_event] (send (model/SetDensity "compact")))
   (fn [event]
     (match event
       (ValueChanged _node value) (send (model/SetVolume value))
       _ true))
   (reactive :gallery-environment model-source)
   (reactive :gallery-picker-query model-source)
   (reactive model/select-open? model-source)
   (reactive model/combobox-open? model-source)
   (reactive model/production-selected? model-source)
   (reactive model/staging-selected? model-source)
   (fn [_event] (send (model/OpenPicker "select")))
   (fn [_event] (send (model/OpenPicker "combobox")))
   (fn [event]
     (match event
       (TextChanged _node query) (send (model/SetPickerQuery query))
       _ true))
   (fn [_event] (send model/CommitPickerQuery))
   (fn [_event] (send model/ClosePicker))
   (fn [_event] (send (model/SelectEnvironment "Production")))
   (fn [_event] (send (model/SelectEnvironment "Staging")))
   (reactive model/report-selected? model-source)
   (reactive model/checklist-selected? model-source)
   (reactive :gallery-document-action model-source)
   (fn [_event] (send (model/SelectDocument "Quarterly report.md")))
   (fn [_event] (send (model/SelectDocument "Launch checklist.md")))
   (fn [_event] (send (model/OpenDocument "Quarterly report.md")))
   (fn [_event] (send (model/OpenDocument "Launch checklist.md")))
   (reactive :gallery-avatar-image model-source)
   (fn [_event] (send model/ToggleAvatarImage))
   (reactive model/overview-tab-selected? model-source)
   (reactive model/activity-tab-selected? model-source)
   (reactive model/tab-content model-source)
   (fn [_event] (send (model/SelectTab "overview")))
   (fn [_event] (send (model/SelectTab "activity")))
   (reactive :gallery-dialog-open model-source)
   (fn [_event] (send model/OpenDialog))
   (fn [_event] (send model/CloseDialog))
   (reactive :gallery-drawer-open model-source)
   (fn [_event] (send model/OpenDrawer))
   (fn [_event] (send model/CloseDrawer))
   (reactive :gallery-sheet-open model-source)
   (fn [_event] (send model/OpenSheet))
   (fn [_event] (send model/CloseSheet))
   (reactive :gallery-accordion-open model-source)
   (fn [event]
     (match event
       (ToggleChanged _node open) (send (model/SetAccordionOpen open))
       _ true))
   (reactive :gallery-split-fraction model-source)
   (fn [event]
     (match event
       (ValueChanged _node fraction) (send (model/SetSplitFraction fraction))
       _ true))])
