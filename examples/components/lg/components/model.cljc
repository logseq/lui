(ns components.model)

(defn initial []
  (record gallery-model
    (gallery-disabled false)
    (gallery-field-value "")
    (gallery-invalid false)
    (gallery-checked false)
    (gallery-progress 30)))

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

    AdvanceProgress
    (assoc
     model
     :gallery-progress
     (if (>= (:gallery-progress model) 100)
       0
       (+ (:gallery-progress model) 10)))))

(defn progress-label [model]
  (str (:gallery-progress model) "%"))
