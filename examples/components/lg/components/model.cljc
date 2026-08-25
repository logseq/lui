(ns components.model)

(defn initial []
  (record gallery-model
    (gallery-disabled false)
    (gallery-field-value "")
    (gallery-checked false)
    (gallery-progress 0.3)
    (gallery-active-step 1)
    (gallery-density "comfortable")
    (gallery-volume 0.35)
    (gallery-environment "Production")
    (gallery-picker-query "")
    (gallery-open-picker "none")
    (gallery-document "Quarterly report.md")
    (gallery-document-action "Selected Quarterly report.md")
    (gallery-avatar-image 0)
    (gallery-media-surface 1)
    (gallery-tab "overview")
    (gallery-dialog-open false)
    (gallery-sheet-open false)
    (gallery-accordion-open false)
    (gallery-split-fraction 0.35)))

(defn update [model action]
  (match action
    ToggleDisabled
    (assoc model :gallery-disabled (not (:gallery-disabled model)))

    (SetFieldValue value)
    (assoc model :gallery-field-value value)

    (SetChecked checked)
    (assoc model :gallery-checked checked)

    (SetDensity density)
    (assoc model :gallery-density density)

    (SetVolume volume)
    (assoc model :gallery-volume volume)

    (OpenPicker picker)
    (assoc model :gallery-open-picker picker)

    (SetPickerQuery query)
    (assoc model :gallery-picker-query query :gallery-open-picker "combobox")

    (SelectEnvironment environment)
    (assoc model
           :gallery-environment environment
           :gallery-picker-query environment
           :gallery-open-picker "none")

    ClosePicker
    (assoc model :gallery-open-picker "none")

    CommitPickerQuery
    (if (= (:gallery-picker-query model) "")
      (assoc model :gallery-open-picker "none")
      (assoc model
             :gallery-environment (:gallery-picker-query model)
             :gallery-open-picker "none"))

    (SelectDocument document)
    (assoc model
           :gallery-document document
           :gallery-document-action (str "Selected " document))

    (OpenDocument document)
    (assoc model :gallery-document-action (str "Opened " document))

    (PerformContextAction action)
    (assoc model :gallery-document-action (str "Context action: " action))

    ToggleAvatarImage
    (assoc model
           :gallery-avatar-image
           (if (= (:gallery-avatar-image model) 0) 1 0))

    (SelectTab tab)
    (assoc model :gallery-tab tab)

    OpenDialog
    (assoc model :gallery-dialog-open true)

    CloseDialog
    (assoc model :gallery-dialog-open false)

    OpenSheet
    (assoc model :gallery-sheet-open true)

    CloseSheet
    (assoc model :gallery-sheet-open false)

    (SetAccordionOpen open)
    (assoc model :gallery-accordion-open open)

    (SetSplitFraction fraction)
    (assoc model :gallery-split-fraction fraction)

    AdvanceProgress
    (assoc
     model
     :gallery-progress
     (if (>= (:gallery-progress model) 1.0)
       0.0
       (+ (:gallery-progress model) 0.1)))

    AdvanceStep
    (assoc model
           :gallery-active-step
           (if (>= (:gallery-active-step model) 3)
             0
             (inc (:gallery-active-step model))))))

(defn progress-label [model]
  (str "Progress fraction: " (:gallery-progress model)))

(defn density-comfortable? [model]
  (= (:gallery-density model) "comfortable"))

(defn density-compact? [model]
  (= (:gallery-density model) "compact"))

(defn volume-label [model]
  (str "Volume: " (:gallery-volume model)))

(defn select-open? [model]
  (= (:gallery-open-picker model) "select"))

(defn combobox-open? [model]
  (= (:gallery-open-picker model) "combobox"))

(defn production-selected? [model]
  (= (:gallery-environment model) "Production"))

(defn staging-selected? [model]
  (= (:gallery-environment model) "Staging"))

(defn report-selected? [model]
  (= (:gallery-document model) "Quarterly report.md"))

(defn checklist-selected? [model]
  (= (:gallery-document model) "Launch checklist.md"))

(defn overview-tab-selected? [model]
  (= (:gallery-tab model) "overview"))

(defn activity-tab-selected? [model]
  (= (:gallery-tab model) "activity"))

(defn tab-content [model]
  (if (activity-tab-selected? model)
    "Recent retained updates"
    "Signal updates remain local"))
