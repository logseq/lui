(ns lui.switch
  (:require [lui.elements :refer [defcomponent defcompound defelement]]))

(defcompound switch
  {:root :box
   :class "lui-switch"
   :controls [:switch/control]
   :forwards [:checked :disabled :invalid :on-change]
   :relations
   [[:labelled-by :switch/label]
    [:described-by :switch/description]
    [:error-message-by :switch/error-message]]})

(defelement control [context parent attrs & children]
  (let [node (gensym "node")
        resolved-attrs
        (lui.elements/component-attrs
         {:class "lui-switch-control"} attrs)]
    `(let [~node
           (lui.ui/switch-control!
            ~context ~(:checked attrs) ~(:on-change attrs))]
       ~@(lui.elements/control-properties context node resolved-attrs)
       ~@(if parent
           [`(lui.ui/append! ~context ~parent ~node)]
           [])
       ~@(map
          (fn [child]
            `(lui.elements/element ~context ~node ~child))
          children)
       ~node)))

(defcomponent thumb :box {:class "lui-switch-thumb"})
(defcomponent label :label {:class "lui-switch-label"})
(defcomponent description :paragraph {:class "lui-switch-description"})
(defcomponent error-message :paragraph {:class "lui-switch-error-message"})
