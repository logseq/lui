(ns lui.card
  (:require [lui.elements :refer [defelement]]))

(macro-helper-defn resolved-class [default-class attrs]
  (if (:class attrs)
    (str default-class " " (:class attrs))
    default-class))

(macro-helper-defn box-part-expansion
  [default-class context parent attrs children]
  (let [node (gensym "node")]
    `(let [~node (lui.ui/box! ~context)]
       (lui.ui/style-class!
        ~context ~node ~(resolved-class default-class attrs))
       ~@(if parent
           [`(lui.ui/append! ~context ~parent ~node)]
           [])
       ~@(map
          (fn [child]
            `(lui.elements/element ~context ~node ~child))
          children)
       ~node)))

(defelement header [context parent attrs & children]
  (box-part-expansion
   "lui-card-header" context parent attrs children))

(defelement content [context parent attrs & children]
  (box-part-expansion
   "lui-card-content" context parent attrs children))

(defelement footer [context parent attrs & children]
  (box-part-expansion
   "lui-card-footer" context parent attrs children))

(defelement title [context parent attrs & children]
  (let [node (gensym "node")]
    `(let [~node (lui.ui/heading! ~context 3 ~(first children))]
       (lui.ui/style-class!
        ~context ~node ~(resolved-class "lui-card-title" attrs))
       ~@(if parent
           [`(lui.ui/append! ~context ~parent ~node)]
           [])
       ~node)))

(defelement description [context parent attrs & children]
  (let [node (gensym "node")]
    `(let [~node (lui.ui/paragraph! ~context ~(first children))]
       (lui.ui/style-class!
        ~context ~node ~(resolved-class "lui-card-description" attrs))
       ~@(if parent
           [`(lui.ui/append! ~context ~parent ~node)]
           [])
       ~node)))
