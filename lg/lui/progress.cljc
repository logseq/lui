(ns lui.progress
  (:require [lui.elements :refer [defelement]]))

(macro-helper-defn resolved-class [default-class attrs]
  (if (:class attrs)
    (str default-class " " (:class attrs))
    default-class))

(macro-helper-defn label-expansion [default-class context parent attrs children]
  (let [node (gensym "node")
        value (:value attrs)
        expression
        (if value
          `(lui.ui/label-signal! ~context ~value)
          `(lui.ui/label! ~context ~(first children)))]
    `(let [~node ~expression]
       (lui.ui/style-class!
        ~context ~node ~(resolved-class default-class attrs))
       ~@(if parent
           [`(lui.ui/append! ~context ~parent ~node)]
           [])
       ~node)))

(defelement label [context parent attrs & children]
  (label-expansion "lui-progress-label" context parent attrs children))

(defelement value-label [context parent attrs & children]
  (label-expansion "lui-progress-value-label" context parent attrs children))
