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
       _ true))])
