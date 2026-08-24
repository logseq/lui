(ns components.view
  (:require [lui.macros :refer [defui reactive]]
            [lui.protocol :refer [TextChanged ToggleChanged]]
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
   (reactive :gallery-invalid model-source)
   (fn [event]
     (match event
       (TextChanged _node text) (send (model/SetFieldValue text))
       _ true))
   (fn [_event] (send model/ToggleInvalid))
   (reactive :gallery-checked model-source)
   (fn [event]
     (match event
       (ToggleChanged _node checked) (send (model/SetChecked checked))
       _ true))
   (reactive :gallery-progress model-source)
   (reactive model/progress-label model-source)
   (fn [_event] (send model/AdvanceProgress))])
