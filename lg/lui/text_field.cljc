(ns lui.text-field
  (:require [lui.elements :refer [defelement]]))

(macro-helper-defn resolved-class [default-class attrs]
  (if (:class attrs)
    (str default-class " " (:class attrs))
    default-class))

(defelement label [context parent attrs & children]
  (let [node (gensym "node")
        value (:value attrs)
        expression
        (if value
          `(lui.ui/label-signal! ~context ~value)
          `(lui.ui/label! ~context ~(first children)))]
    `(let [~node ~expression]
       (lui.ui/style-class!
        ~context ~node ~(resolved-class "lui-text-field-label" attrs))
       ~@(if parent
           [`(lui.ui/append! ~context ~parent ~node)]
           [])
       ~node)))

(defelement input [context parent attrs & _children]
  `(lui.elements/text-input
    ~context ~parent
    ~(assoc attrs :class (resolved-class "lui-text-field-input" attrs))))

(defelement text-area [context parent attrs & _children]
  `(lui.elements/text-area
    ~context ~parent
    ~(assoc attrs :class (resolved-class "lui-text-field-text-area" attrs))))

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
   "lui-text-field-description" context parent attrs children))

(defelement error-message [context parent attrs & children]
  (paragraph-part-expansion
   "lui-text-field-error-message" context parent attrs children))
