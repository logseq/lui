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
                       (if (= tag :if)
                         'lui.elements/conditional
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
                         (= tag :tabs)
                         (= tag :button-group)
                         (= tag :toggle-group)
                         (= tag :breadcrumb)
                         (= tag :pagination)
                         (= tag :spacer)
                         (= tag :spinner)
                         (= tag :icon)
                         (= tag :text)
                         (= tag :heading)
                         (= tag :paragraph)
                         (= tag :label)
                         (= tag :button)
                         (= tag :toggle-button)
                         (= tag :toggle)
                         (= tag :radio-group)
                         (= tag :radio)
                         (= tag :slider)
                         (= tag :progress)
                         (= tag :checkbox)
                         (= tag :switch)
                         (= tag :text-field)
                         (= tag :input)
                         (= tag :search-field)
                         (= tag :textarea)
                         (= tag :select)
                         (= tag :combobox)
                         (= tag :dropdown-menu)
                         (= tag :dialog)
                         (= tag :menu-item)
                         (= tag :list-item)
                         (= tag :avatar)
                          (= tag :keyed))
                          (symbol (str "lui.elements/" (name tag)))
                          (symbol (str "lui." (name tag) "/" (name tag))))))))

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

(macro-helper-defn leaf-expansion [expression context parent attrs]
                   (let [node (gensym "node")]
                     `(let [~node ~expression]
                        ~@(element-properties context node attrs)
                        ~@(if parent
                            [`(lui.ui/append! ~context ~parent ~node)]
                            [])
                        ~node)))

(macro-helper-defn string-attribute-expansion
                   [context node value property]
                   (if value
                     (if (string? value)
                       [`(lui.ui/string-property! ~context ~node ~property ~value)]
                       [`(lui.ui/string-property-signal! ~context ~node ~property ~value)])
                     []))

(macro-helper-defn bool-attribute-expansion
                   [context node value property]
                   (if (or (= value true) (= value false))
                     [`(lui.ui/bool-property! ~context ~node ~property ~value)]
                     (if value
                       [`(lui.ui/bool-property-signal! ~context ~node ~property ~value)]
                       [])))

(macro-helper-defn disabled-attribute-expansion [context node attrs]
                   (let [value (:disabled attrs)]
                     (if value
                       (if (or (= value true) (= value false))
                         [`(lui.ui/disabled! ~context ~node ~value)]
                         [`(lui.ui/disabled-signal! ~context ~node ~value)])
                       [])))

(macro-helper-defn float-attribute-expansion
                   [context node value property]
                   (if value
                     (if (float? value)
                       [`(lui.ui/float-property! ~context ~node ~property ~value)]
                       [`(lui.ui/float-property-signal!
                          ~context ~node ~property ~value)])
                     []))

(macro-helper-defn button-event-expansion [context node attrs]
                   (let [on-press (:on-press attrs)
                         on-hold (:on-hold attrs)]
                     (if (or on-press on-hold)
                       [`(lui.ui/on-event!
                          ~context ~node
                          (fn [~'event]
                            (match ~'event
                              (lui.protocol/Press ~'_node)
                              ~(if on-press `(~on-press ~'event) true)
                              (lui.protocol/Hold ~'_node)
                              ~(if on-hold `(~on-hold ~'event) true)
                              ~'_ true)))]
                       [])))

(macro-helper-defn toggle-button-event-expansion [context node attrs]
                   (let [on-toggle (:on-toggle attrs)
                         on-hold (:on-hold attrs)]
                     (if (or on-toggle on-hold)
                       [`(lui.ui/on-event!
                          ~context ~node
                          (fn [~'event]
                            (match ~'event
                              (lui.protocol/ToggleChanged ~'_node ~'_checked)
                              ~(if on-toggle `(~on-toggle ~'event) true)
                              (lui.protocol/Hold ~'_node)
                              ~(if on-hold `(~on-hold ~'event) true)
                              ~'_ true)))]
                       [])))

(macro-helper-defn text-entry-event-expansion [context node attrs]
                   (let [on-input (:on-input attrs)
                         on-submit (:on-submit attrs)]
                     (if (or on-input on-submit)
                       [`(lui.ui/on-event!
                          ~context ~node
                          (fn [~'event]
                            (match ~'event
                              (lui.protocol/TextChanged ~'_node ~'_text)
                              ~(if on-input `(~on-input ~'event) true)
                              (lui.protocol/Submit ~'_node)
                              ~(if on-submit `(~on-submit ~'event) true)
                              ~'_ true)))]
                       [])))

(macro-helper-defn picker-event-expansion [context node attrs]
                   (let [on-press (:on-press attrs)
                         on-input (:on-input attrs)
                         on-submit (:on-submit attrs)
                         on-dismiss (:on-dismiss attrs)]
                     (if (or on-press on-input on-submit on-dismiss)
                       [`(lui.ui/on-event!
                          ~context ~node
                          (fn [~'event]
                            (match ~'event
                              (lui.protocol/Press ~'_node)
                              ~(if on-press `(~on-press ~'event) true)
                              (lui.protocol/TextChanged ~'_node ~'_text)
                              ~(if on-input `(~on-input ~'event) true)
                              (lui.protocol/Submit ~'_node)
                              ~(if on-submit `(~on-submit ~'event) true)
                              (lui.protocol/Dismiss ~'_node)
                              ~(if on-dismiss `(~on-dismiss ~'event) true)
                              ~'_ true)))]
                       [])))

(macro-helper-defn dismiss-event-expansion [context node attrs]
                   (let [on-dismiss (:on-dismiss attrs)]
                     (if on-dismiss
                       [`(lui.ui/on-event!
                          ~context ~node
                          (fn [~'event]
                            (match ~'event
                              (lui.protocol/Dismiss ~'_node)
                              (~on-dismiss ~'event)
                              ~'_ true)))]
                       [])))

(macro-helper-defn list-item-event-expansion [context node attrs]
                   (let [on-press (:on-press attrs)
                         on-double-press (:on-double-press attrs)
                         on-submit (:on-submit attrs)]
                     (if (or on-press on-double-press on-submit)
                       [`(lui.ui/on-event!
                          ~context ~node
                          (fn [~'event]
                            (match ~'event
                              (lui.protocol/Press ~'_node)
                              ~(if on-press `(~on-press ~'event) true)
                              (lui.protocol/DoublePress ~'_node)
                              ~(if on-double-press
                                 `(~on-double-press ~'event)
                                 true)
                              (lui.protocol/Submit ~'_node)
                              ~(if on-submit `(~on-submit ~'event) true)
                              ~'_ true)))]
                       [])))

(macro-helper-defn text-entry-expansion
                   [constructor context parent attrs children]
                   (if (empty? children)
                     (let [node (gensym "node")
                           resolved-attrs
                           (if (:label attrs)
                             (assoc attrs :accessibility-label (:label attrs))
                             attrs)]
                       `(let [~node (~constructor ~context)]
                          ~@(string-attribute-expansion
                             context node (:text attrs) 'lui.protocol/TextValue)
                          ~@(string-attribute-expansion
                             context node (:placeholder attrs)
                             'lui.protocol/PlaceholderValue)
                          ~@(string-attribute-expansion
                             context node (:accessibility-label resolved-attrs)
                             'lui.protocol/AccessibilityLabel)
                          ~@(bool-attribute-expansion
                             context node (:autofocus attrs)
                             'lui.protocol/Autofocus)
                          ~@(bool-attribute-expansion
                             context node (:submit-on-enter attrs)
                             'lui.protocol/SubmitOnEnter)
                          ~@(disabled-attribute-expansion context node attrs)
                          ~@(text-entry-event-expansion context node attrs)
                          ~@(element-properties context node attrs)
                          ~@(if parent
                              [`(lui.ui/append! ~context ~parent ~node)]
                              [])
                          ~node))
                     (throw
                      (IllegalArgumentException.
                       "text-entry elements are leaves and cannot contain children"))))

(macro-helper-defn direct-toggle-expansion
                   [constructor context parent attrs children]
                   (let [node (gensym "node")
                         text-source (:text attrs)
                         literal-text (first children)
                         resolved-attrs
                         (if (:label attrs)
                           (assoc attrs :accessibility-label (:label attrs))
                           attrs)]
                     `(let [~node (~constructor ~context)]
                        ~@(if text-source
                            [`(lui.ui/text-property-signal! ~context ~node ~text-source)]
                            (if literal-text
                              [`(lui.ui/text-property! ~context ~node ~literal-text)]
                              []))
                        ~@(bool-attribute-expansion
                           context node (:checked attrs) 'lui.protocol/Checked)
                        ~@(if (:on-toggle attrs)
                            [`(lui.ui/on-event! ~context ~node ~(:on-toggle attrs))]
                            [])
                        ~@(interactive-properties context node resolved-attrs)
                        ~@(if parent
                            [`(lui.ui/append! ~context ~parent ~node)]
                            [])
                        ~node)))

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

(defelement tabs [context parent attrs & children]
  (container-expansion 'lui.ui/tabs! context parent attrs children))

(macro-helper-defn labelled-container-expansion
                   [constructor context parent attrs children]
                   (let [node (gensym "node")]
                     `(let [~node (~constructor ~context)]
                        ~@(element-properties context node attrs)
                        ~@(property-expansions
                           context node
                           [[(:accessibility-label attrs)
                             'lui.ui/accessibility-label!]])
                        ~@(if parent
                            [`(lui.ui/append! ~context ~parent ~node)]
                            [])
                        ~@(map
                           (fn [child]
                             `(lui.elements/element ~context ~node ~child))
                           children)
                        ~node)))

(defelement button-group [context parent attrs & children]
  (labelled-container-expansion
   'lui.ui/button-group! context parent attrs children))

(defelement toggle-group [context parent attrs & children]
  (labelled-container-expansion
   'lui.ui/toggle-group! context parent attrs children))

(defelement breadcrumb [context parent attrs & children]
  (labelled-container-expansion
   'lui.ui/breadcrumb! context parent attrs children))

(defelement pagination [context parent attrs & children]
  (labelled-container-expansion
   'lui.ui/pagination! context parent attrs children))

(defelement spacer [context parent _attrs & _children]
  (let [node (gensym "node")]
    `(let [~node (lui.ui/spacer! ~context)]
       ~@(if parent
           [`(lui.ui/append! ~context ~parent ~node)]
           [])
       ~node)))

(defelement spinner [context parent attrs & children]
  (if (empty? children)
    (let [node (gensym "node")]
      `(let [~node (lui.ui/spinner! ~context)]
         ~@(element-properties context node attrs)
         ~@(property-expansions
            context node [[(:size attrs) 'lui.ui/size!]])
         ~@(if parent
             [`(lui.ui/append! ~context ~parent ~node)]
             [])
         ~node))
    (throw
     (IllegalArgumentException.
      "spinner is a leaf and cannot contain children"))))

(defelement icon [context parent attrs & children]
  (if (empty? children)
    (let [node (gensym "node")]
      `(let [~node (lui.ui/icon! ~context ~(:name attrs))]
         ~@(element-properties context node attrs)
         ~@(property-expansions
            context node [[(:size attrs) 'lui.ui/size!]])
         ~@(if parent
             [`(lui.ui/append! ~context ~parent ~node)]
             [])
         ~node))
    (throw
     (IllegalArgumentException.
      "icon is a leaf and cannot contain children"))))

(defelement text [context parent attrs & children]
  (let [value (:value attrs)
        on-press (:on-press attrs)
        expression
        (if value
          `(lui.ui/text-signal! ~context ~value)
          `(lui.ui/text! ~context ~(first children)))
        node (gensym "node")]
    `(let [~node ~expression]
       ~@(element-properties context node attrs)
       ~@(if on-press
           [`(lui.ui/bool-property!
              ~context ~node lui.protocol/PressEnabled true)
            `(lui.ui/on-event! ~context ~node ~on-press)]
           [])
       ~@(if parent
           [`(lui.ui/append! ~context ~parent ~node)]
           [])
       ~node)))

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
        text-source (:text attrs)
        literal-text (first children)]
    `(let [~node (lui.ui/button! ~context)]
       ~@(if text-source
           [`(lui.ui/text-property-signal! ~context ~node ~text-source)]
           (if literal-text
             [`(lui.ui/text-property! ~context ~node ~literal-text)]
             []))
       ~@(string-attribute-expansion
          context node (:variant attrs) 'lui.protocol/VariantValue)
       ~@(string-attribute-expansion
          context node (:size attrs) 'lui.protocol/SizeValue)
       ~@(string-attribute-expansion
          context node (:icon attrs) 'lui.protocol/InlineIconName)
       ~@(string-attribute-expansion
          context node (:icon-placement attrs) 'lui.protocol/IconPlacementValue)
       ~@(string-attribute-expansion
          context node (:label attrs) 'lui.protocol/AccessibilityLabel)
       ~@(bool-attribute-expansion
          context node (:selected attrs) 'lui.protocol/Selected)
       ~@(bool-attribute-expansion
          context node (:autofocus attrs) 'lui.protocol/Autofocus)
       ~@(disabled-attribute-expansion context node attrs)
       ~@(if (:on-hold attrs)
           [`(lui.ui/bool-property!
              ~context ~node lui.protocol/HoldEnabled true)]
           [])
       ~@(button-event-expansion context node attrs)
       ~@(element-properties context node attrs)
       ~@(if parent
           [`(lui.ui/append! ~context ~parent ~node)]
           [])
       ~node)))

(defelement toggle-button [context parent attrs & children]
  (let [node (gensym "node")
        text-source (:text attrs)
        literal-text (first children)]
    `(let [~node (lui.ui/toggle-button! ~context)]
       ~@(if text-source
           [`(lui.ui/text-property-signal! ~context ~node ~text-source)]
           (if literal-text
             [`(lui.ui/text-property! ~context ~node ~literal-text)]
             []))
       ~@(string-attribute-expansion
          context node (:variant attrs) 'lui.protocol/VariantValue)
       ~@(string-attribute-expansion
          context node (:size attrs) 'lui.protocol/SizeValue)
       ~@(string-attribute-expansion
          context node (:icon attrs) 'lui.protocol/InlineIconName)
       ~@(string-attribute-expansion
          context node (:icon-placement attrs) 'lui.protocol/IconPlacementValue)
       ~@(string-attribute-expansion
          context node (:label attrs) 'lui.protocol/AccessibilityLabel)
       ~@(bool-attribute-expansion
          context node (:selected attrs) 'lui.protocol/Selected)
       ~@(bool-attribute-expansion
          context node (:autofocus attrs) 'lui.protocol/Autofocus)
       ~@(disabled-attribute-expansion context node attrs)
       ~@(if (:on-hold attrs)
           [`(lui.ui/bool-property!
              ~context ~node lui.protocol/HoldEnabled true)]
           [])
       ~@(toggle-button-event-expansion context node attrs)
       ~@(element-properties context node attrs)
       ~@(if parent
           [`(lui.ui/append! ~context ~parent ~node)]
           [])
       ~node)))

(defelement checkbox [context parent attrs & _children]
  (direct-toggle-expansion
   'lui.ui/checkbox! context parent attrs _children))

(defelement switch [context parent attrs & children]
  (direct-toggle-expansion
   'lui.ui/switch-control! context parent attrs children))

(defelement toggle [context parent attrs & children]
  (direct-toggle-expansion
   'lui.ui/toggle! context parent attrs children))

(defelement radio-group [context parent attrs & children]
  (let [node (gensym "node")]
    `(let [~node (lui.ui/radio-group! ~context)]
       ~@(string-attribute-expansion
          context node (:label attrs) 'lui.protocol/AccessibilityLabel)
       ~@(element-properties context node attrs)
       ~@(if parent
           [`(lui.ui/append! ~context ~parent ~node)]
           [])
       ~@(map
          (fn [child]
            `(lui.elements/element ~context ~node ~child))
          children)
       ~node)))

(defelement radio [context parent attrs & children]
  (let [node (gensym "node")
        text-source (:text attrs)
        literal-text (first children)
        selection-source
        (if (:checked attrs) (:checked attrs) (:selected attrs))
        on-change (:on-change attrs)
        on-toggle (:on-toggle attrs)
        on-press (:on-press attrs)]
    `(let [~node (lui.ui/radio! ~context)]
       ~@(if text-source
           [`(lui.ui/text-property-signal! ~context ~node ~text-source)]
           (if literal-text
             [`(lui.ui/text-property! ~context ~node ~literal-text)]
             []))
       ~@(bool-attribute-expansion
          context node selection-source 'lui.protocol/Checked)
       ~@(string-attribute-expansion
          context node (:label attrs) 'lui.protocol/AccessibilityLabel)
       ~@(disabled-attribute-expansion context node attrs)
       ~@(if on-change
           [`(lui.ui/bool-property! ~context ~node lui.protocol/ChangeEnabled true)
            `(lui.ui/on-event! ~context ~node ~on-change)]
           (if on-toggle
             [`(lui.ui/bool-property! ~context ~node lui.protocol/ToggleEnabled true)
              `(lui.ui/on-event! ~context ~node ~on-toggle)]
             (if on-press
               [`(lui.ui/bool-property! ~context ~node lui.protocol/PressEnabled true)
                `(lui.ui/on-event! ~context ~node ~on-press)]
               [])))
       ~@(element-properties context node attrs)
       ~@(if parent
           [`(lui.ui/append! ~context ~parent ~node)]
           [])
       ~node)))

(defelement slider [context parent attrs & _children]
  (let [node (gensym "node")
        value (:value attrs)
        constructor
        (if (float? value) 'lui.ui/slider-literal! 'lui.ui/slider!)]
    `(let [~node (~constructor ~context ~value)]
       ~@(string-attribute-expansion
          context node (:label attrs) 'lui.protocol/AccessibilityLabel)
       ~@(disabled-attribute-expansion context node attrs)
       ~@(if (:on-change attrs)
           [`(lui.ui/on-event! ~context ~node ~(:on-change attrs))]
           [])
       ~@(element-properties context node attrs)
       ~@(if parent
           [`(lui.ui/append! ~context ~parent ~node)]
           [])
       ~node)))

(defelement progress [context parent attrs & children]
  (if (empty? children)
    (let [node (gensym "node")
          value (:value attrs)
          constructor
          (if (float? value) 'lui.ui/progress-literal! 'lui.ui/progress!)]
      `(let [~node (~constructor ~context ~value)]
         ~@(element-properties context node attrs)
         ~@(if parent
             [`(lui.ui/append! ~context ~parent ~node)]
             [])
         ~node))
    (throw
     (IllegalArgumentException.
      "progress is a leaf and cannot contain children"))))

(defelement text-field [context parent attrs & children]
  (text-entry-expansion
   'lui.ui/text-field! context parent attrs children))

(defelement input [context parent attrs & children]
  (text-entry-expansion
   'lui.ui/input! context parent attrs children))

(defelement search-field [context parent attrs & children]
  (text-entry-expansion
   'lui.ui/search-field! context parent attrs children))

(defelement textarea [context parent attrs & children]
  (text-entry-expansion
   'lui.ui/textarea! context parent attrs children))

(defelement select [context parent attrs & children]
  (let [node (gensym "node")
        text-source (:text attrs)
        literal-text (first children)]
    `(let [~node (lui.ui/select! ~context)]
       ~@(if text-source
           [`(lui.ui/text-property-signal! ~context ~node ~text-source)]
           (if literal-text
             [`(lui.ui/text-property! ~context ~node ~literal-text)]
             []))
       ~@(string-attribute-expansion
          context node (:placeholder attrs) 'lui.protocol/PlaceholderValue)
       ~@(disabled-attribute-expansion context node attrs)
       ~@(if (:on-press attrs)
           [`(lui.ui/bool-property!
              ~context ~node lui.protocol/PressEnabled true)]
           [])
       ~@(picker-event-expansion context node attrs)
       ~@(element-properties context node attrs)
       ~@(if parent
           [`(lui.ui/append! ~context ~parent ~node)]
           [])
       ~node)))

(defelement combobox [context parent attrs & children]
  (if (empty? children)
    (let [node (gensym "node")]
      `(let [~node (lui.ui/combobox! ~context)]
         ~@(string-attribute-expansion
            context node (:text attrs) 'lui.protocol/TextValue)
         ~@(string-attribute-expansion
            context node (:placeholder attrs) 'lui.protocol/PlaceholderValue)
         ~@(disabled-attribute-expansion context node attrs)
         ~@(if (:on-press attrs)
             [`(lui.ui/bool-property!
                ~context ~node lui.protocol/PressEnabled true)]
             [])
         ~@(if (:on-submit attrs)
             [`(lui.ui/bool-property!
                ~context ~node lui.protocol/SubmitEnabled true)]
             [])
         ~@(picker-event-expansion context node attrs)
         ~@(element-properties context node attrs)
         ~@(if parent
             [`(lui.ui/append! ~context ~parent ~node)]
             [])
         ~node))
    (throw
     (IllegalArgumentException.
      "combobox is a leaf and cannot contain children"))))

(defelement dropdown-menu [context parent attrs & children]
  (let [node (gensym "node")]
    `(let [~node (lui.ui/dropdown-menu! ~context)]
       ~@(string-attribute-expansion
          context node (:anchor attrs) 'lui.protocol/AnchorValue)
       ~@(string-attribute-expansion
          context node (:anchor-alignment attrs)
          'lui.protocol/AnchorAlignmentValue)
       ~@(float-attribute-expansion
          context node (:anchor-offset attrs) 'lui.protocol/AnchorOffset)
       ~@(picker-event-expansion context node attrs)
       ~@(element-properties context node attrs)
       ~@(if parent
           [`(lui.ui/append! ~context ~parent ~node)]
           [])
       ~@(map
          (fn [child]
            `(lui.elements/element ~context ~node ~child))
          children)
       ~node)))

(defelement dialog [context parent attrs & children]
  (let [node (gensym "node")]
    `(let [~node (lui.ui/dialog! ~context)]
       ~@(string-attribute-expansion
          context node (:text attrs) 'lui.protocol/TextValue)
       ~@(property-expansions
          context node
          [[(:width attrs) 'lui.ui/width!]
           [(:height attrs) 'lui.ui/height!]
           [(:padding attrs) 'lui.ui/padding!]])
       ~@(dismiss-event-expansion context node attrs)
       ~@(if parent
           [`(lui.ui/append! ~context ~parent ~node)]
           [])
       ~@(map
          (fn [child]
            `(lui.elements/element ~context ~node ~child))
          children)
       ~node)))

(defelement menu-item [context parent attrs & children]
  (let [node (gensym "node")
        text-source (:text attrs)
        literal-text (first children)]
    `(let [~node (lui.ui/menu-item! ~context)]
       ~@(if text-source
           [`(lui.ui/text-property-signal! ~context ~node ~text-source)]
           (if literal-text
             [`(lui.ui/text-property! ~context ~node ~literal-text)]
             []))
       ~@(string-attribute-expansion
          context node (:icon attrs) 'lui.protocol/InlineIconName)
       ~@(bool-attribute-expansion
          context node (:selected attrs) 'lui.protocol/Selected)
       ~@(disabled-attribute-expansion context node attrs)
       ~@(if (:on-press attrs)
           [`(lui.ui/bool-property!
              ~context ~node lui.protocol/PressEnabled true)]
           [])
       ~@(picker-event-expansion context node attrs)
       ~@(element-properties context node attrs)
       ~@(if parent
           [`(lui.ui/append! ~context ~parent ~node)]
           [])
       ~node)))

(defelement list-item [context parent attrs & children]
  (let [node (gensym "node")
        text-source (:text attrs)
        literal-text
        (if (and (= (count children) 1) (string? (first children)))
          (first children)
          nil)
        child-elements (if literal-text [] children)]
    (if text-source
      (if (= (count children) 0)
        nil
        (throw
         (IllegalArgumentException.
          "list-item accepts :text or children, not both")))
      nil)
    (if (string? (first children))
      (if (= (count children) 1)
        nil
        (throw
         (IllegalArgumentException.
          "list-item cannot mix text and element children")))
      nil)
    `(let [~node (lui.ui/list-item! ~context)]
       ~@(if text-source
           [`(lui.ui/text-property-signal! ~context ~node ~text-source)]
           (if literal-text
             [`(lui.ui/text-property! ~context ~node ~literal-text)]
             []))
       ~@(string-attribute-expansion
          context node (:icon attrs) 'lui.protocol/InlineIconName)
       ~@(bool-attribute-expansion
          context node (:selected attrs) 'lui.protocol/Selected)
       ~@(disabled-attribute-expansion context node attrs)
       ~@(if (:on-press attrs)
           [`(lui.ui/bool-property!
              ~context ~node lui.protocol/PressEnabled true)]
           [])
       ~@(if (:on-double-press attrs)
           [`(lui.ui/bool-property!
              ~context ~node lui.protocol/DoublePressEnabled true)]
           [])
       ~@(if (:on-submit attrs)
           [`(lui.ui/bool-property!
              ~context ~node lui.protocol/SubmitEnabled true)]
           [])
       ~@(list-item-event-expansion context node attrs)
       ~@(element-properties context node attrs)
       ~@(if parent
           [`(lui.ui/append! ~context ~parent ~node)]
           [])
       ~@(map
          (fn [child]
            `(lui.elements/element ~context ~node ~child))
          child-elements)
       ~node)))

(defelement avatar [context parent attrs & children]
  (let [node (gensym "node")
        text-source (:text attrs)
        image-source (:image attrs)
        literal-text
        (if (and (= (count children) 1) (string? (first children)))
          (first children)
          nil)]
    (if text-source
      (if (empty? children)
        nil
        (throw
         (IllegalArgumentException.
          "avatar accepts :text or one initials child, not both")))
      (if literal-text
        nil
        (throw
         (IllegalArgumentException.
          "avatar requires exactly one initials string"))))
    `(let [~node (lui.ui/avatar! ~context)]
       ~@(if text-source
           [`(lui.ui/text-property-signal! ~context ~node ~text-source)]
           [`(lui.ui/text-property! ~context ~node ~literal-text)])
       ~@(if image-source
           [`(lui.ui/int-property-signal!
              ~context ~node lui.protocol/ImageIdValue ~image-source)]
           [])
       ~@(float-attribute-expansion
          context node (:source-x attrs) 'lui.protocol/SourceX)
       ~@(float-attribute-expansion
          context node (:source-y attrs) 'lui.protocol/SourceY)
       ~@(float-attribute-expansion
          context node (:source-width attrs) 'lui.protocol/SourceWidth)
       ~@(float-attribute-expansion
          context node (:source-height attrs) 'lui.protocol/SourceHeight)
       ~@(string-attribute-expansion
          context node (:label attrs) 'lui.protocol/AccessibilityLabel)
       ~@(if parent
           [`(lui.ui/append! ~context ~parent ~node)]
           [])
       ~node)))

(defelement conditional [context parent attrs & children]
  (when (nil? parent)
    (throw
     (IllegalArgumentException.
      "if must be declared inside a retained parent")))
  (when-not (:test attrs)
    (throw
     (IllegalArgumentException.
      "if requires a :test signal")))
  (when-not (= 1 (count children))
    (throw
     (IllegalArgumentException.
      "if requires exactly one child")))
  (let [branch-context (gensym "branch_context")]
    `(lui.dynamic/conditional!
      ~context ~parent ~(:test attrs)
      (fn [~branch-context]
        (lui.elements/element
         ~branch-context nil ~(first children))))))

(defelement keyed [context parent attrs & children]
  (let [item-context (gensym "item_context")
        item-symbol (:as attrs)]
    `(lui.dynamic/keyed!
      ~context ~parent ~(:source attrs) ~(:key attrs) ~(:compare attrs)
      (fn [~item-context ~item-symbol]
        (lui.elements/element
         ~item-context nil ~(first children))))))
