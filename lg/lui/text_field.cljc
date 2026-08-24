(ns lui.text-field
  (:require [lui.elements :refer [defcomponent defcompound]]))

(defcompound text-field
  {:root :box
   :class "lui-text-field"
   :controls [:text-field/input :text-field/text-area]
   :forwards []
   :relations
   [[:labelled-by :text-field/label]
    [:described-by :text-field/description]
    [:error-message-by :text-field/error-message]]})

(defcomponent label :label {:class "lui-text-field-label"})
(defcomponent input :text-input {:class "lui-text-field-input"})
(defcomponent text-area :text-area {:class "lui-text-field-text-area"})
(defcomponent description :paragraph {:class "lui-text-field-description"})
(defcomponent error-message :paragraph
  {:class "lui-text-field-error-message"})
