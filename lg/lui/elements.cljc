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
     [])
   (if (:class attrs)
     [`(lui.ui/style-class! ~context ~node ~(:class attrs))]
     [])))

(macro-helper-defn button-style-class [attrs]
  (let [variant (if (:variant attrs) (:variant attrs) "default")
        size (if (:size attrs) (:size attrs) "size-default")
        size-class (if (= size "default") "size-default" size)
        resolved
        (str "lui-button--" variant " lui-button--" size-class)]
    (if (:class attrs)
      (str resolved " " (:class attrs))
      resolved)))

(macro-helper-defn find-part-node [children child-nodes part]
  (if (empty? children)
    false
    (if (= (first (first children)) part)
      (first child-nodes)
      (find-part-node (next children) (next child-nodes) part))))

(macro-helper-defn part-bindings [context children child-nodes]
  (if (empty? children)
    []
    (concat
     [(first child-nodes)
      `(lui.elements/element ~context nil ~(first children))]
     (part-bindings context (next children) (next child-nodes)))))

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

(defelement box [context parent attrs & children]
  (container-expansion 'lui.ui/box! context parent attrs children))

(defelement card [context parent attrs & children]
  (let [node (gensym "node")
        class-name
        (if (:class attrs)
          (str "lui-card " (:class attrs))
          "lui-card")]
    `(let [~node (lui.ui/box! ~context)]
       (lui.ui/style-class! ~context ~node ~class-name)
       ~@(if parent
           [`(lui.ui/append! ~context ~parent ~node)]
           [])
       ~@(map
          (fn [child]
            `(lui.elements/element ~context ~node ~child))
          children)
       ~node)))

(defelement text-field [context parent attrs & children]
  (let [node (gensym "node")
        child-nodes (map (fn [_child] (gensym "part")) children)
        label-node
        (find-part-node children child-nodes :text-field/label)
        input-node
        (find-part-node children child-nodes :text-field/input)
        text-area-node
        (find-part-node children child-nodes :text-field/text-area)
        description-node
        (find-part-node children child-nodes :text-field/description)
        error-node
        (find-part-node children child-nodes :text-field/error-message)
        control-node (if input-node input-node text-area-node)
        class-name
        (if (:class attrs)
          (str "lui-text-field " (:class attrs))
          "lui-text-field")]
    `(let [~node (lui.ui/box! ~context)
           ~@(part-bindings context children child-nodes)]
       (lui.ui/style-class! ~context ~node ~class-name)
       ~@(if parent
           [`(lui.ui/append! ~context ~parent ~node)]
           [])
       ~@(map
          (fn [part-node]
            `(lui.ui/append! ~context ~node ~part-node))
          child-nodes)
       ~@(if (and control-node label-node)
           [`(lui.ui/labelled-by!
              ~context ~control-node ~label-node)]
           [])
       ~@(if (and control-node description-node)
           [`(lui.ui/described-by!
              ~context ~control-node ~description-node)]
           [])
       ~@(if (and control-node error-node)
           [`(lui.ui/error-message-by!
              ~context ~control-node ~error-node)]
           [])
       ~node)))

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

(defelement heading [context parent attrs & children]
  (let [node (gensym "node")
        level (if (:level attrs) (:level attrs) 1)
        value (:value attrs)
        expression
        (if value
          `(lui.ui/heading-signal! ~context ~level ~value)
          `(lui.ui/heading! ~context ~level ~(first children)))]
    `(let [~node ~expression]
       ~@(if (:class attrs)
           [`(lui.ui/style-class! ~context ~node ~(:class attrs))]
           [])
       ~@(if parent
           [`(lui.ui/append! ~context ~parent ~node)]
           [])
       ~node)))

(defelement paragraph [context parent attrs & children]
  (let [node (gensym "node")
        value (:value attrs)
        expression
        (if value
          `(lui.ui/paragraph-signal! ~context ~value)
          `(lui.ui/paragraph! ~context ~(first children)))]
    `(let [~node ~expression]
       ~@(if (:class attrs)
           [`(lui.ui/style-class! ~context ~node ~(:class attrs))]
           [])
       ~@(if parent
           [`(lui.ui/append! ~context ~parent ~node)]
           [])
       ~node)))

(defelement label [context parent attrs & children]
  (let [node (gensym "node")
        value (:value attrs)
        expression
        (if value
          `(lui.ui/label-signal! ~context ~value)
          `(lui.ui/label! ~context ~(first children)))]
    `(let [~node ~expression]
       ~@(if (:class attrs)
           [`(lui.ui/style-class! ~context ~node ~(:class attrs))]
           [])
       ~@(if parent
           [`(lui.ui/append! ~context ~parent ~node)]
           [])
       ~node)))

(defelement button [context parent attrs & children]
  (let [node (gensym "node")]
    `(let [~node
           (lui.ui/button!
            ~context ~(first children) ~(:on-press attrs))]
       ~@(if (:disabled attrs)
           [`(lui.ui/disabled-signal! ~context ~node ~(:disabled attrs))]
           [])
       (lui.ui/style-class! ~context ~node ~(button-style-class attrs))
       ~@(if parent
           [`(lui.ui/append! ~context ~parent ~node)]
           [])
       ~node)))

(defelement text-input [context parent attrs & _children]
  (let [node (gensym "node")]
    `(let [~node
           (lui.ui/text-input!
            ~context ~(:value attrs) ~(:on-change attrs))]
       ~@(if (:placeholder attrs)
           [`(lui.ui/placeholder! ~context ~node ~(:placeholder attrs))]
           [])
       ~@(if (:read-only attrs)
           [`(lui.ui/read-only! ~context ~node ~(:read-only attrs))]
           [])
       ~@(if (:accessibility-label attrs)
           [`(lui.ui/accessibility-label!
              ~context ~node ~(:accessibility-label attrs))]
           [])
       ~@(if (:type attrs)
           [`(lui.ui/input-type! ~context ~node ~(:type attrs))]
           [])
       ~@(if (:invalid attrs)
           [`(lui.ui/invalid-signal! ~context ~node ~(:invalid attrs))]
           [])
       ~@(if (:disabled attrs)
           [`(lui.ui/disabled-signal! ~context ~node ~(:disabled attrs))]
           [])
       ~@(if (:class attrs)
           [`(lui.ui/style-class! ~context ~node ~(:class attrs))]
           [])
       ~@(if parent
           [`(lui.ui/append! ~context ~parent ~node)]
           [])
       ~node)))

(defelement text-area [context parent attrs & _children]
  (let [node (gensym "node")]
    `(let [~node
           (lui.ui/text-area!
            ~context ~(:value attrs) ~(:on-change attrs))]
       ~@(if (:placeholder attrs)
           [`(lui.ui/placeholder! ~context ~node ~(:placeholder attrs))]
           [])
       ~@(if (:read-only attrs)
           [`(lui.ui/read-only! ~context ~node ~(:read-only attrs))]
           [])
       ~@(if (:accessibility-label attrs)
           [`(lui.ui/accessibility-label!
              ~context ~node ~(:accessibility-label attrs))]
           [])
       ~@(if (:min-lines attrs)
           [`(lui.ui/min-lines! ~context ~node ~(:min-lines attrs))]
           [])
       ~@(if (:max-lines attrs)
           [`(lui.ui/max-lines! ~context ~node ~(:max-lines attrs))]
           [])
       ~@(if (:invalid attrs)
           [`(lui.ui/invalid-signal! ~context ~node ~(:invalid attrs))]
           [])
       ~@(if (:disabled attrs)
           [`(lui.ui/disabled-signal! ~context ~node ~(:disabled attrs))]
           [])
       ~@(if (:class attrs)
           [`(lui.ui/style-class! ~context ~node ~(:class attrs))]
           [])
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
