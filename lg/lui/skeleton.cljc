(ns lui.skeleton
  (:require [lui.elements :refer [defcomponent]]))

(defcomponent skeleton :box
  {:class "lui-skeleton"
   :background "secondary"
   :corner-radius 6})
