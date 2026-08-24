(ns components.model)

(defn initial []
  (record gallery-model
    (gallery-disabled false)
    (gallery-field-value "")
    (gallery-invalid false)
    (gallery-checked false)
    (gallery-progress 0.3)
    (gallery-density "comfortable")
    (gallery-volume 0.35)))

(defn update [model action]
  (match action
    ToggleDisabled
    (assoc model :gallery-disabled (not (:gallery-disabled model)))

    (SetFieldValue value)
    (assoc model :gallery-field-value value)

    ToggleInvalid
    (assoc model :gallery-invalid (not (:gallery-invalid model)))

    (SetChecked checked)
    (assoc model :gallery-checked checked)

    (SetDensity density)
    (assoc model :gallery-density density)

    (SetVolume volume)
    (assoc model :gallery-volume volume)

    AdvanceProgress
    (assoc
     model
     :gallery-progress
     (if (>= (:gallery-progress model) 1.0)
       0.0
       (+ (:gallery-progress model) 0.1)))))

(defn progress-label [model]
  (str "Progress fraction: " (:gallery-progress model)))

(defn density-comfortable? [model]
  (= (:gallery-density model) "comfortable"))

(defn density-compact? [model]
  (= (:gallery-density model) "compact"))

(defn volume-label [model]
  (str "Volume: " (:gallery-volume model)))
