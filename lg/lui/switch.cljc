(ns lui.switch
  (:require [lui.elements :refer [defelement]]))

(macro-helper-defn resolved-class [default-class attrs]
  (if (:class attrs)
    (str default-class " " (:class attrs))
    default-class))

(defelement control [context parent attrs & children]
  (let [node (gensym "node")]
    `(let [~node
           (lui.ui/switch-control!
            ~context ~(:checked attrs) ~(:on-change attrs))]
       (lui.ui/style-class!
        ~context ~node ~(resolved-class "lui-switch-control" attrs))
       ~@(if (:disabled attrs)
           [`(lui.ui/disabled-signal! ~context ~node ~(:disabled attrs))]
           [])
       ~@(if (:invalid attrs)
           [`(lui.ui/invalid-signal! ~context ~node ~(:invalid attrs))]
           [])
       ~@(if (:accessibility-label attrs)
           [`(lui.ui/accessibility-label!
              ~context ~node ~(:accessibility-label attrs))]
           [])
       ~@(if parent
           [`(lui.ui/append! ~context ~parent ~node)]
           [])
       ~@(map
          (fn [child]
            `(lui.elements/element ~context ~node ~child))
          children)
       ~node)))

(defelement thumb [context parent attrs & children]
  (let [node (gensym "node")]
    `(let [~node (lui.ui/box! ~context)]
       (lui.ui/style-class!
        ~context ~node ~(resolved-class "lui-switch-thumb" attrs))
       ~@(if parent
           [`(lui.ui/append! ~context ~parent ~node)]
           [])
       ~@(map
          (fn [child]
            `(lui.elements/element ~context ~node ~child))
          children)
       ~node)))

(defelement label [context parent attrs & children]
  (let [node (gensym "node")
        value (:value attrs)
        expression
        (if value
          `(lui.ui/label-signal! ~context ~value)
          `(lui.ui/label! ~context ~(first children)))]
    `(let [~node ~expression]
       (lui.ui/style-class!
        ~context ~node ~(resolved-class "lui-switch-label" attrs))
       ~@(if parent
           [`(lui.ui/append! ~context ~parent ~node)]
           [])
       ~node)))

(macro-helper-defn paragraph-part-expansion
  [default-class context parent attrs children]
  (let [node (gensym "node")
        value (:value attrs)
        expression
        (if value
          `(lui.ui/paragraph-signal! ~context ~value)
          `(lui.ui/paragraph! ~context ~(first children)))]
    `(let [~node ~expression]
       (lui.ui/style-class!
        ~context ~node ~(resolved-class default-class attrs))
       ~@(if parent
           [`(lui.ui/append! ~context ~parent ~node)]
           [])
       ~node)))

(defelement description [context parent attrs & children]
  (paragraph-part-expansion
   "lui-switch-description" context parent attrs children))

(defelement error-message [context parent attrs & children]
  (paragraph-part-expansion
   "lui-switch-error-message" context parent attrs children))
