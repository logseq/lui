(ns lui.bottom-tabs
  (:require [lui.elements :refer [defelement]]))

(defelement bottom-tabs [context parent attrs & children]
  (if (or (= (count children) 2) (= (count children) 3)
          (= (count children) 4) (= (count children) 5))
    (let [node (gensym "node")]
      `(let [~node (lui.ui/bottom-tabs! ~context)]
         ~@(lui.elements/string-attribute-expansion
            context node (:label attrs) 'lui.protocol/AccessibilityLabel)
         ~@(lui.elements/element-properties context node attrs)
         ~@(if parent
             [`(lui.ui/append! ~context ~parent ~node)]
             [])
         ~@(map
            (fn [child]
              `(lui.elements/element ~context ~node ~child))
            children)
         ~node))
    (throw
     (IllegalArgumentException.
      "bottom-tabs requires between two and five bottom-tab children"))))

(defelement bottom-tab [context parent attrs & children]
  (if (and (:title attrs) (:on-press attrs))
    (if (empty? children)
      (throw
       (IllegalArgumentException.
        "bottom-tab requires title, on-press, and retained page content"))
      (let [node (gensym "node")]
        `(let [~node (lui.ui/bottom-tab! ~context)]
           ~@(lui.elements/string-attribute-expansion
              context node (:title attrs) 'lui.protocol/TitleValue)
           ~@(lui.elements/string-attribute-expansion
              context node (:icon attrs) 'lui.protocol/InlineIconName)
           ~@(lui.elements/bool-attribute-expansion
              context node (:selected attrs) 'lui.protocol/Selected)
           ~@(lui.elements/disabled-attribute-expansion context node attrs)
           (lui.ui/bool-property!
            ~context ~node lui.protocol/PressEnabled true)
           ~@(lui.elements/button-event-expansion context node attrs)
           ~@(lui.elements/element-properties context node attrs)
           ~@(if parent
               [`(lui.ui/append! ~context ~parent ~node)]
               [])
           ~@(map
              (fn [child]
                `(lui.elements/element ~context ~node ~child))
              children)
           ~node)))
    (throw
     (IllegalArgumentException.
      "bottom-tab requires title, on-press, and retained page content"))))
