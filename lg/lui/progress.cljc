(ns lui.progress
  (:require [lui.elements :refer [defcomponent defelement]]))

(defelement progress [context parent attrs & children]
  (let [node (gensym "node")
        control (gensym "control")
        child-nodes (map (fn [_child] (gensym "part")) children)
        label-node
        (lui.elements/find-part-node children child-nodes :progress/label)
        minimum (if (:min-value attrs) (:min-value attrs) 0)
        maximum (if (:max-value attrs) (:max-value attrs) 100)
        resolved-attrs
        (lui.elements/component-attrs {:class "lui-progress"} attrs)]
    `(let [~node (lui.ui/column! ~context)
           ~@(lui.elements/part-bindings context children child-nodes)
           ~control
           (lui.ui/progress-control!
            ~context ~(:value attrs) ~minimum ~maximum)]
       ~@(lui.elements/element-properties context node resolved-attrs)
       ~@(if parent
           [`(lui.ui/append! ~context ~parent ~node)]
           [])
       ~@(map
          (fn [part-node]
            `(lui.ui/append! ~context ~node ~part-node))
          child-nodes)
       (lui.ui/append! ~context ~node ~control)
       ~@(if label-node
           [`(lui.ui/labelled-by! ~context ~control ~label-node)]
           [])
       ~node)))

(defcomponent label :label {:class "lui-progress-label"})
(defcomponent value-label :label {:class "lui-progress-value-label"})
