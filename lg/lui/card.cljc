(ns lui.card
  (:require [lui.elements :refer [defcomponent]]))

(defcomponent card :box {:class "lui-card"})
(defcomponent header :box {:class "lui-card-header"})
(defcomponent content :box {:class "lui-card-content"})
(defcomponent footer :box {:class "lui-card-footer"})
(defcomponent title :heading {:level 3 :class "lui-card-title"})
(defcomponent description :paragraph {:class "lui-card-description"})
