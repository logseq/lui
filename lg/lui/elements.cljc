(ns lui.elements)

(macro-helper-defn element-attrs [form]
  (if (empty? (next form))
    {}
    (if (map? (first (next form)))
      (first (next form))
      {})))

(macro-helper-defn element-children [form]
  (if (empty? (next form))
    []
    (if (map? (first (next form)))
      (vec (next (next form)))
      (vec (next form)))))

(macro-helper-defn element-expander-symbol [tag]
  (let [tag-namespace (namespace tag)]
    (if tag-namespace
      (symbol (str tag-namespace "/" (name tag)))
      (symbol (str "lui.elements/" (name tag))))))

(defmacro defelement [element-name params & body]
  `(defmacro ~element-name ~params ~@body))

(defmacro element [context parent form]
  (let [tag (first form)
        attrs (element-attrs form)
        children (element-children form)]
    (if (keyword? tag)
      `(~(element-expander-symbol tag)
        ~context ~parent ~attrs ~@children)
      (let [component-context (gensym "component_context")
            node (gensym "component_node")]
        `(let [~component-context
               (lui.ui/child-context ~context ~(str tag))
               ~node (~tag ~component-context ~@(vec (next form)))]
           ~@(if parent
               [`(lui.ui/append! ~context ~parent ~node)]
               [])
           ~node)))))

(macro-helper-defn element-properties [context node attrs]
  (concat
   (if (:gap attrs)
     [`(lui.ui/gap! ~context ~node ~(:gap attrs))]
     [])
   (if (:padding attrs)
     [`(lui.ui/padding! ~context ~node ~(:padding attrs))]
     [])
   (if (:background attrs)
     [`(lui.ui/background! ~context ~node ~(:background attrs))]
     [])))

(macro-helper-defn container-expansion
  [constructor context parent attrs children]
  (let [node (gensym "node")]
    `(let [~node (~constructor ~context)]
       ~@(element-properties context node attrs)
       ~@(if parent
           [`(lui.ui/append! ~context ~parent ~node)]
           [])
       ~@(map
          (fn [child]
            `(lui.elements/element ~context ~node ~child))
          children)
       ~node)))

(defelement row [context parent attrs & children]
  (container-expansion 'lui.ui/row! context parent attrs children))

(defelement column [context parent attrs & children]
  (container-expansion 'lui.ui/column! context parent attrs children))

(defelement scroll [context parent attrs & children]
  (container-expansion 'lui.ui/scroll! context parent attrs children))

(defelement spacer [context parent _attrs & _children]
  (let [node (gensym "node")]
    `(let [~node (lui.ui/spacer! ~context)]
       ~@(if parent
           [`(lui.ui/append! ~context ~parent ~node)]
           [])
       ~node)))

(defelement text [context parent attrs & children]
  (let [node (gensym "node")
        value (:value attrs)
        expression
        (if value
          `(lui.ui/text-signal! ~context ~value)
          `(lui.ui/text! ~context ~(first children)))]
    `(let [~node ~expression]
       ~@(if parent
           [`(lui.ui/append! ~context ~parent ~node)]
           [])
       ~node)))

(defelement button [context parent attrs & children]
  (let [node (gensym "node")]
    `(let [~node
           (lui.ui/button!
            ~context ~(first children) ~(:on-press attrs))]
       ~@(if parent
           [`(lui.ui/append! ~context ~parent ~node)]
           [])
       ~node)))

(defelement text-input [context parent attrs & _children]
  (let [node (gensym "node")]
    `(let [~node
           (lui.ui/text-input!
            ~context ~(:value attrs) ~(:on-change attrs))]
       ~@(if parent
           [`(lui.ui/append! ~context ~parent ~node)]
           [])
       ~node)))

(defelement keyed [context parent attrs & children]
  (let [item-context (gensym "item_context")
        item-symbol (:as attrs)]
    `(lui.dynamic/keyed!
      ~context ~parent ~(:source attrs) ~(:key attrs) ~(:compare attrs)
      (fn [~item-context ~item-symbol]
        (lui.elements/element
         ~item-context nil ~(first children))))))
