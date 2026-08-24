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
      (if
       (or
        (= tag :row)
        (= tag :column)
        (= tag :grid)
        (= tag :stack)
        (= tag :panel)
        (= tag :card)
        (= tag :box)
        (= tag :scroll)
        (= tag :list)
        (= tag :spacer)
        (= tag :text)
        (= tag :heading)
        (= tag :paragraph)
        (= tag :label)
        (= tag :button)
        (= tag :checkbox)
        (= tag :text-input)
        (= tag :text-area)
        (= tag :keyed))
       (symbol (str "lui.elements/" (name tag)))
       (symbol (str "lui." (name tag) "/" (name tag)))))))

(defmacro defelement [element-name params & body]
  `(defmacro ~element-name ~params ~@body))

(macro-helper-defn component-attrs [defaults attrs]
  (let [default-class (:class defaults)
        caller-class (:class attrs)
        resolved (into defaults attrs)]
    (if (and default-class caller-class)
      (assoc resolved :class (str default-class " " caller-class))
      resolved)))

(macro-helper-defn component-expansion
  [root-tag defaults context parent attrs children]
  `(lui.elements/element
    ~context ~parent
    ~(vec
      (concat
       [root-tag (component-attrs defaults attrs)]
       children))))

(defmacro defcomponent [component-name root-tag defaults]
  `(defmacro ~component-name
     [~'context ~'parent ~'attrs & ~'children]
     (lui.elements/component-expansion
      ~root-tag ~defaults ~'context ~'parent ~'attrs ~'children)))

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

(macro-helper-defn tag-in? [tag tags]
  (if (empty? tags)
    false
    (if (= tag (first tags))
      true
      (tag-in? tag (next tags)))))

(macro-helper-defn forwarded-attr-value [attrs key]
  (cond
    (= key :checked) (:checked attrs)
    (= key :disabled) (:disabled attrs)
    (= key :invalid) (:invalid attrs)
    (= key :on-change) (:on-change attrs)
    (= key :accessibility-label) (:accessibility-label attrs)
    :else
    (throw
     (IllegalArgumentException.
      (str "unsupported forwarded compound attribute: " key)))))

(macro-helper-defn forwarded-attrs [root-attrs keys child-attrs]
  (if (empty? keys)
    child-attrs
    (forwarded-attrs
     root-attrs
     (next keys)
     (assoc
      child-attrs (first keys)
      (forwarded-attr-value root-attrs (first keys))))))

(macro-helper-defn compound-child-form
  [child root-attrs controls forwards]
  (if (tag-in? (first child) controls)
    (vec
     (concat
      [(first child)
       (forwarded-attrs root-attrs forwards (element-attrs child))]
      (element-children child)))
    child))

(macro-helper-defn compound-child-forms
  [children root-attrs controls forwards]
  (map
   (fn [child]
     (compound-child-form child root-attrs controls forwards))
   children))

(macro-helper-defn first-part-node [children child-nodes parts]
  (if (empty? parts)
    false
    (let [node (find-part-node children child-nodes (first parts))]
      (if node
        node
        (first-part-node children child-nodes (next parts))))))

(macro-helper-defn compound-relation-expansions
  [context control children child-nodes relations]
  (if (empty? relations)
    []
    (let [relation (first (first relations))
          part (second (first relations))
          part-node (find-part-node children child-nodes part)
          setter
          (cond
            (= relation :labelled-by) 'lui.ui/labelled-by!
            (= relation :described-by) 'lui.ui/described-by!
            (= relation :error-message-by) 'lui.ui/error-message-by!
            :else
            (throw
             (IllegalArgumentException.
              (str "unsupported compound relation: " relation))))]
      (concat
       (if (and control part-node)
         [`(~setter ~context ~control ~part-node)]
         [])
       (compound-relation-expansions
        context control children child-nodes (next relations))))))

(macro-helper-defn compound-constructor [root-tag]
  (cond
    (= root-tag :box) 'lui.ui/box!
    (= root-tag :row) 'lui.ui/row!
    (= root-tag :column) 'lui.ui/column!
    :else
    (throw
     (IllegalArgumentException.
      (str "unsupported compound root: " root-tag)))))

(macro-helper-defn compound-expansion
  [root-tag default-class controls forwards relations
   context parent attrs children]
  (let [node (gensym "node")
        resolved-children
        (compound-child-forms children attrs controls forwards)
        child-nodes (map (fn [_child] (gensym "part")) resolved-children)
        control-node
        (first-part-node resolved-children child-nodes controls)
        root-attrs (component-attrs {:class default-class} attrs)
        constructor (compound-constructor root-tag)]
    `(let [~node (~constructor ~context)
           ~@(part-bindings context resolved-children child-nodes)]
       ~@(element-properties context node root-attrs)
       ~@(if parent
           [`(lui.ui/append! ~context ~parent ~node)]
           [])
       ~@(map
          (fn [part-node]
            `(lui.ui/append! ~context ~node ~part-node))
          child-nodes)
       ~@(compound-relation-expansions
          context control-node resolved-children child-nodes relations)
       ~node)))

(defmacro defcompound [component-name options]
  `(defmacro ~component-name
     [~'context ~'parent ~'attrs & ~'children]
     (lui.elements/compound-expansion
      ~(:root options) ~(:class options) ~(:controls options)
      ~(:forwards options) ~(:relations options)
      ~'context ~'parent ~'attrs ~'children)))

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

(macro-helper-defn property-expansions [context node mappings]
  (if (empty? mappings)
    []
    (let [mapping (first mappings)
          value (first mapping)
          setter (second mapping)]
      (concat
       (if value
         [`(~setter ~context ~node ~value)]
         [])
       (property-expansions context node (next mappings))))))

(macro-helper-defn element-properties [context node attrs]
  (property-expansions
   context node
   [[(:gap attrs) 'lui.ui/gap!]
    [(:main attrs) 'lui.ui/main!]
    [(:cross attrs) 'lui.ui/cross!]
    [(:grow attrs) 'lui.ui/grow!]
    [(:columns attrs) 'lui.ui/columns!]
    [(:padding attrs) 'lui.ui/padding!]
    [(:padding-horizontal attrs) 'lui.ui/padding-horizontal!]
    [(:padding-vertical attrs) 'lui.ui/padding-vertical!]
    [(:background attrs) 'lui.ui/background!]
    [(:foreground attrs) 'lui.ui/foreground!]
    [(:border-color attrs) 'lui.ui/border-color!]
    [(:border-width attrs) 'lui.ui/border-width!]
    [(:corner-radius attrs) 'lui.ui/corner-radius!]
    [(:width attrs) 'lui.ui/width!]
    [(:height attrs) 'lui.ui/height!]
    [(:min-width attrs) 'lui.ui/min-width!]
    [(:max-width attrs) 'lui.ui/max-width!]
    [(:min-height attrs) 'lui.ui/min-height!]
    [(:max-height attrs) 'lui.ui/max-height!]
    [(:class attrs) 'lui.ui/style-class!]]))

(macro-helper-defn interactive-properties [context node attrs]
  (concat
   (element-properties context node attrs)
   (property-expansions
    context node
    [[(:disabled attrs) 'lui.ui/disabled-signal!]
     [(:accessibility-label attrs) 'lui.ui/accessibility-label!]])))

(macro-helper-defn control-properties [context node attrs]
  (concat
   (interactive-properties context node attrs)
   (property-expansions
    context node
    [[(:invalid attrs) 'lui.ui/invalid-signal!]])))

(macro-helper-defn text-control-properties [context node attrs]
  (concat
   (control-properties context node attrs)
   (property-expansions
    context node
    [[(:placeholder attrs) 'lui.ui/placeholder!]
     [(:read-only attrs) 'lui.ui/read-only!]])))

(macro-helper-defn leaf-expansion [expression context parent attrs]
  (let [node (gensym "node")]
    `(let [~node ~expression]
       ~@(element-properties context node attrs)
       ~@(if parent
           [`(lui.ui/append! ~context ~parent ~node)]
           [])
       ~node)))

(macro-helper-defn button-style-class [attrs]
  (let [variant (if (:variant attrs) (:variant attrs) "default")
        size (if (:size attrs) (:size attrs) "size-default")
        size-class (if (= size "default") "size-default" size)
        resolved
        (str "lui-button--" variant " lui-button--" size-class)]
    (if (:class attrs)
      (str resolved " " (:class attrs))
      resolved)))

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

(defelement grid [context parent attrs & children]
  (container-expansion 'lui.ui/grid! context parent attrs children))

(defelement stack [context parent attrs & children]
  (container-expansion 'lui.ui/stack! context parent attrs children))

(defelement panel [context parent attrs & children]
  (container-expansion 'lui.ui/panel! context parent attrs children))

(defelement card [context parent attrs & children]
  (container-expansion 'lui.ui/card! context parent attrs children))

(defelement box [context parent attrs & children]
  (container-expansion 'lui.ui/box! context parent attrs children))

(defelement scroll [context parent attrs & children]
  (container-expansion 'lui.ui/scroll! context parent attrs children))

(defelement list [context parent attrs & children]
  (container-expansion 'lui.ui/list! context parent attrs children))

(defelement spacer [context parent _attrs & _children]
  (let [node (gensym "node")]
    `(let [~node (lui.ui/spacer! ~context)]
       ~@(if parent
           [`(lui.ui/append! ~context ~parent ~node)]
           [])
       ~node)))

(defelement text [context parent attrs & children]
  (let [value (:value attrs)
        expression
        (if value
          `(lui.ui/text-signal! ~context ~value)
          `(lui.ui/text! ~context ~(first children)))]
    (leaf-expansion expression context parent attrs)))

(defelement heading [context parent attrs & children]
  (let [level (if (:level attrs) (:level attrs) 1)
        value (:value attrs)
        expression
        (if value
          `(lui.ui/heading-signal! ~context ~level ~value)
          `(lui.ui/heading! ~context ~level ~(first children)))]
    (leaf-expansion expression context parent attrs)))

(defelement paragraph [context parent attrs & children]
  (let [value (:value attrs)
        expression
        (if value
          `(lui.ui/paragraph-signal! ~context ~value)
          `(lui.ui/paragraph! ~context ~(first children)))]
    (leaf-expansion expression context parent attrs)))

(defelement label [context parent attrs & children]
  (let [value (:value attrs)
        expression
        (if value
          `(lui.ui/label-signal! ~context ~value)
          `(lui.ui/label! ~context ~(first children)))]
    (leaf-expansion expression context parent attrs)))

(defelement button [context parent attrs & children]
  (let [node (gensym "node")
        resolved-attrs (assoc attrs :class (button-style-class attrs))]
    `(let [~node
           (lui.ui/button!
            ~context ~(first children) ~(:on-press attrs))]
       ~@(interactive-properties context node resolved-attrs)
       ~@(if parent
           [`(lui.ui/append! ~context ~parent ~node)]
           [])
       ~node)))

(defelement checkbox [context parent attrs & _children]
  (let [node (gensym "node")]
    `(let [~node
           (lui.ui/checkbox!
            ~context ~(:checked attrs) ~(:on-change attrs))]
       ~@(if (:indeterminate attrs)
           [`(lui.ui/indeterminate-signal!
              ~context ~node ~(:indeterminate attrs))]
           [])
       ~@(control-properties context node attrs)
       ~@(if parent
           [`(lui.ui/append! ~context ~parent ~node)]
           [])
       ~node)))

(defelement text-input [context parent attrs & _children]
  (let [node (gensym "node")]
    `(let [~node
           (lui.ui/text-input!
            ~context ~(:value attrs) ~(:on-change attrs))]
       ~@(text-control-properties context node attrs)
       ~@(if (:type attrs)
           [`(lui.ui/input-type! ~context ~node ~(:type attrs))]
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
       ~@(text-control-properties context node attrs)
       ~@(if (:min-lines attrs)
           [`(lui.ui/min-lines! ~context ~node ~(:min-lines attrs))]
           [])
       ~@(if (:max-lines attrs)
           [`(lui.ui/max-lines! ~context ~node ~(:max-lines attrs))]
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
