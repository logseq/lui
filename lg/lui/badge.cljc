(ns lui.badge
  (:require [lui.elements :refer [defelement]]))

(macro-helper-defn variant [attrs]
  (if (:variant attrs) (:variant attrs) "default"))

(macro-helper-defn colors [value]
  (cond
    (= value "default")
    ["primary" "primary-foreground" "transparent"]
    (= value "secondary")
    ["secondary" "secondary-foreground" "transparent"]
    (= value "outline")
    ["transparent" "foreground" "border"]
    (= value "success")
    ["success" "success-foreground" "success-foreground"]
    (= value "warning")
    ["warning" "warning-foreground" "warning-foreground"]
    (= value "error")
    ["error" "error-foreground" "error-foreground"]
    :else
    (throw
     (IllegalArgumentException.
      (str "unsupported Badge variant: " value)))))

(macro-helper-defn style-class [attrs]
  (let [value (variant attrs)
        base (str "lui-badge lui-badge--" value)
        rounded (if (:round attrs) (str base " lui-badge--round") base)]
    (if (:class attrs)
      (str rounded " " (:class attrs))
      rounded)))

(macro-helper-defn surface-attrs [attrs background border]
  (assoc
   attrs
   :class (style-class attrs)
   :padding-horizontal 10
   :padding-vertical 2
   :background background
   :border-color border
   :border-width 1
   :corner-radius (if (:round attrs) 999 6)))

(macro-helper-defn child-bindings [context children child-nodes]
  (if (empty? children)
    []
    (concat
     [(first child-nodes)
      (if (vector? (first children))
        `(lui.elements/element ~context nil ~(first children))
        `(lui.ui/text! ~context ~(first children)))]
     (child-bindings context (next children) (next child-nodes)))))

(defelement badge [context parent attrs & children]
  (let [node (gensym "node")
        child-nodes (map (fn [_child] (gensym "content")) children)
        value (variant attrs)
        palette (colors value)
        background (first palette)
        text-color (second palette)
        border (last palette)]
    `(let [~node (lui.ui/row! ~context)
           ~@(child-bindings context children child-nodes)]
       ~@(lui.elements/element-properties
          context node (surface-attrs attrs background border))
       ~@(if parent
           [`(lui.ui/append! ~context ~parent ~node)]
           [])
       ~@(map
          (fn [child-node]
            `(do
               (lui.ui/foreground! ~context ~child-node ~text-color)
               (lui.ui/append! ~context ~node ~child-node)))
          child-nodes)
       ~node)))
