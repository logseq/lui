(ns lui.separator
  (:require [lui.elements :refer [defelement]]))

(defelement separator [context parent attrs & _children]
  (let [node (gensym "node")
        orientation
        (if (:orientation attrs) (:orientation attrs) "horizontal")
        resolved-attrs
        (lui.elements/component-attrs
         {:class "lui-separator"} attrs)]
    `(let [~node (lui.ui/separator! ~context ~orientation)]
       ~@(lui.elements/element-properties context node resolved-attrs)
       ~@(if parent
           [`(lui.ui/append! ~context ~parent ~node)]
           [])
       ~node)))
