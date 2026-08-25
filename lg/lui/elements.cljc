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

(macro-helper-defn context-menu-form? [form]
                   (and (vector? form) (= (first form) :context-menu)))

(macro-helper-defn dropdown-menu-form? [form]
                   (and (vector? form) (= (first form) :dropdown-menu)))

(macro-helper-defn menu-item-submenu? [form]
                   (loop [children (element-children form)]
                     (if (empty? children)
                       false
                       (if (dropdown-menu-form? (first children))
                         true
                         (recur (next children))))))

(macro-helper-defn reactions-form? [form]
                   (and (vector? form) (= (first form) :reactions)))

(macro-helper-defn reactions-children [children]
                   (loop [remaining children
                          result []]
                     (if (empty? remaining)
                       result
                       (recur
                        (next remaining)
                        (if (reactions-form? (first remaining))
                          (conj result (first remaining))
                          result)))))

(macro-helper-defn message-children [children]
                   (loop [remaining children
                          result []]
                     (if (empty? remaining)
                       result
                       (recur
                        (next remaining)
                        (if (reactions-form? (first remaining))
                          result
                          (conj result (first remaining)))))))

(macro-helper-defn context-menu-children [children]
                   (loop [remaining children
                          result []]
                     (if (empty? remaining)
                       result
                       (recur
                        (next remaining)
                        (if (context-menu-form? (first remaining))
                          (conj result (first remaining))
                          result)))))

(macro-helper-defn visible-children [children]
                   (loop [remaining children
                          result []]
                     (if (empty? remaining)
                       result
                       (recur
                        (next remaining)
                        (if (context-menu-form? (first remaining))
                          result
                          (conj result (first remaining)))))))

(macro-helper-defn context-menu-has-item? [children]
                   (loop [remaining children]
                     (if (empty? remaining)
                       false
                       (let [tag (first (first remaining))]
                         (if (or (= tag :menu-item) (= tag :if))
                           true
                           (recur (next remaining)))))))

(macro-helper-defn context-menu-item-missing-press? [children]
                   (loop [remaining children]
                     (if (empty? remaining)
                       false
                       (let [child (first remaining)]
                         (if (and
                              (= (first child) :menu-item)
                              (if (:on-press (element-attrs child)) false true)
                              (not (menu-item-submenu? child)))
                           true
                           (recur (next remaining)))))))

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
                         (= tag :alert)
                         (= tag :bubble)
                         (= tag :box)
                         (= tag :scroll)
                         (= tag :list)
                         (= tag :tabs)
                         (= tag :button-group)
                         (= tag :toggle-group)
                         (= tag :breadcrumb)
                         (= tag :pagination)
                         (= tag :table)
                         (= tag :table-row)
                         (= tag :table-cell)
                         (= tag :tree)
                         (= tag :resizable)
                         (= tag :split)
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
                         (= tag :context-menu)
                         (= tag :dialog)
                         (= tag :sheet)
                         (= tag :tooltip)
                         (= tag :toast)
                         (= tag :toolbar)
                         (= tag :accordion)
                         (= tag :menu-item)
                         (= tag :list-item)
                         (= tag :avatar)
                         (= tag :image)
                         (= tag :media-surface)
                         (= tag :stepper)
                         (= tag :step)
                         (= tag :timeline)
                         (= tag :timeline-item)
                         (= tag :input-group)
                         (= tag :input-group-actions)
                         (= tag :reactions)
                         (= tag :status-bar)
                          (= tag :keyed))
                          (symbol (str "lui.elements/" (name tag)))
                          (symbol (str "lui." (name tag) "/" (name tag))))))))

(defmacro defelement [element-name params & body]
  `(defmacro ~element-name ~params ~@body))

(macro-helper-defn extension-value-constructor [kind]
                   (cond
                     (= kind :string) 'lui.protocol/StringValue
                     (= kind :bool) 'lui.protocol/BoolValue
                     (= kind :int) 'lui.protocol/IntValue
                     (= kind :float) 'lui.protocol/FloatValue
                     :else
                     (throw
                      (IllegalArgumentException.
                       (str "unknown extension property kind " kind)))))

(macro-helper-defn extension-literal? [kind value]
                   (cond
                     (= kind :string) (string? value)
                     (= kind :bool) (or (= value true) (= value false))
                     (= kind :int) (int? value)
                     (= kind :float) (float? value)
                     :else false))

(macro-helper-defn macro-map-value [values key]
                   (loop [remaining values]
                     (if (empty? remaining)
                       nil
                       (let [entry (first remaining)]
                         (if (= (first entry) key)
                           (second entry)
                           (recur (next remaining)))))))

(macro-helper-defn platform-tweak-entries [attrs]
                   (loop [remaining
                          [[:ios 'lui.protocol/IOS]
                           [:macos 'lui.protocol/MacOS]
                           [:android 'lui.protocol/AndroidOS]
                           [:web 'lui.protocol/WebOS]]
                          result []]
                     (if (empty? remaining)
                       result
                       (let [entry (first remaining)
                             specs (macro-map-value attrs (first entry))]
                         (recur
                          (next remaining)
                          (if specs
                            (conj result [(second entry) specs])
                            result))))))

(macro-helper-defn tweak-spec-name [spec]
                   (if (keyword? spec) (name spec) (name (first spec))))

(macro-helper-defn tweak-spec-properties [spec]
                   (if (keyword? spec)
                     []
                     (if (empty? (next spec))
                       []
                       (if (map? (second spec)) (second spec) []))))

(macro-helper-defn inferred-wire-value [value]
                   (cond
                     (string? value) `(lui.protocol/StringValue ~value)
                     (or (= value true) (= value false))
                     `(lui.protocol/BoolValue ~value)
                     (int? value) `(lui.protocol/IntValue ~value)
                     (float? value) `(lui.protocol/FloatValue ~value)
                     :else nil))

(macro-helper-defn tweak-property-expansions [context node properties]
                   (loop [remaining properties
                          result []]
                     (if (empty? remaining)
                       result
                       (let [entry (first remaining)
                             property-name (name (first entry))
                             value (second entry)
                             literal (inferred-wire-value value)]
                         (recur
                          (next remaining)
                          (conj
                           result
                           (if literal
                             `(lui.ui/extension-property!
                               ~context ~node ~property-name ~literal)
                             `(lui.ui/extension-property-signal!
                               ~context ~node ~property-name ~value))))))))

(macro-helper-defn tweak-chain-expansion [context base specs]
                   (if (empty? specs)
                     base
                     (let [spec (first specs)
                           node (gensym "platform_tweak")]
                       `(let [~node
                              (lui.ui/platform-tweak!
                               ~context ~(tweak-spec-name spec))]
                          ~@(tweak-property-expansions
                             context node (tweak-spec-properties spec))
                          (lui.ui/append! ~context ~node ~base)
                          ~(tweak-chain-expansion context node (next specs))))))

(macro-helper-defn tweak-condition-branches [context base entries]
                   (loop [remaining entries
                          result []]
                     (if (empty? remaining)
                       result
                       (let [entry (first remaining)]
                         (recur
                          (next remaining)
                          (concat
                           result
                           [`(= (lui.ui/platform ~context) ~(first entry))
                            (tweak-chain-expansion
                             context base (second entry))]))))))

(macro-helper-defn selected-tweak-expansion [context base entries]
                   (if (empty? entries)
                     base
                     `(cond
                        ~@(tweak-condition-branches context base entries)
                        :else ~base)))

(macro-helper-defn extension-property-expansions
                   [context node properties attrs]
                   (loop [remaining properties
                          result []]
                     (if (empty? remaining)
                       result
                       (let [entry (first remaining)
                             property (first entry)
                             kind (second entry)]
                         (recur
                          (next remaining)
                          (let [value (macro-map-value attrs property)]
                            (if (or value (= value false))
                              (let [
                                  constructor
                                  (extension-value-constructor kind)
                                  property-name (name property)]
                                (conj
                                 result
                                 (if (extension-literal? kind value)
                                   `(lui.ui/extension-property!
                                     ~context ~node ~property-name
                                     (~constructor ~value))
                                   `(lui.ui/extension-property-signal!
                                     ~context ~node ~property-name
                                     (signal.core/own-signal!
                                      (:ui-scope ~context)
                                      (signal.core/map
                                       (fn [~'value] (~constructor ~'value))
                                       ~value))))))
                              result)))))))

(macro-helper-defn extension-event-branches [events attrs event-name event]
                   (loop [remaining events
                          result []]
                     (if (empty? remaining)
                       result
                       (let [entry (first remaining)
                             name-key (first entry)
                             attribute (second entry)
                             handler (macro-map-value attrs attribute)]
                         (recur
                          (next remaining)
                          (if handler
                            (concat
                             result
                             [`(= ~event-name ~(name name-key))
                              `(~handler ~event)])
                            result))))))

(macro-helper-defn extension-event-expansion
                   [context node events attrs]
                   (let [event-name (gensym "extension_event_name")
                         event (gensym "extension_event")
                         branches
                         (extension-event-branches events attrs event-name event)]
                     (if (empty? branches)
                       []
                       [`(lui.ui/on-event!
                          ~context ~node
                          (fn [~event]
                            (match ~event
                              (lui.protocol/ExtensionEvent
                               ~'_node ~'_identifier ~event-name ~'_values)
                              (cond ~@branches :else true)
                              ~'_ true)))])))

(macro-helper-defn extension-expansion
                   [definition context parent attrs children]
                   (let [identifier (:identifier definition)
                         properties (:properties definition)
                         events (:events definition)
                         node (gensym "extension_node")]
                     (when-not (string? identifier)
                       (throw
                        (IllegalArgumentException.
                         "defextension requires a string :identifier")))
                     `(let [~node (lui.ui/extension! ~context ~identifier)]
                        ~@(extension-property-expansions
                           context node properties attrs)
                        ~@(extension-event-expansion context node events attrs)
                        ~@(if parent
                            [`(lui.ui/append! ~context ~parent ~node)]
                            [])
                        ~@(map
                           (fn [child]
                             `(lui.elements/element ~context ~node ~child))
                           children)
                        ~node)))

(defmacro defextension [element-name definition]
  `(defmacro ~element-name [~'context ~'parent ~'attrs & ~'children]
     (lui.elements/extension-expansion
      ~definition ~'context ~'parent ~'attrs ~'children)))

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
        children (element-children form)
        metadata-children (context-menu-children children)
        visible-children (visible-children children)]
    (if (keyword? tag)
      (let [entries (platform-tweak-entries attrs)]
        (if (empty? entries)
          (if (empty? metadata-children)
            `(~(element-expander-symbol tag)
              ~context ~parent ~attrs ~@children)
            (let [node (gensym "metadata_host")]
              `(let [~node
                     (~(element-expander-symbol tag)
                      ~context ~parent ~attrs ~@visible-children)]
                 ~@(map
                    (fn [child]
                      `(lui.elements/element ~context ~node ~child))
                    metadata-children)
                 ~node)))
          (let [base-node (gensym "tweak_base")
                result-node (gensym "tweak_result")
                base
                (if (empty? metadata-children)
                  `(~(element-expander-symbol tag)
                    ~context nil ~attrs ~@children)
                  `(let [~base-node
                         (~(element-expander-symbol tag)
                          ~context nil ~attrs ~@visible-children)]
                     ~@(map
                        (fn [child]
                          `(lui.elements/element ~context ~base-node ~child))
                        metadata-children)
                     ~base-node))]
            `(let [~base-node ~base
                   ~result-node
                   ~(selected-tweak-expansion context base-node entries)]
               ~@(if parent
                   [`(lui.ui/append! ~context ~parent ~result-node)]
                   [])
               ~result-node))))
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

(macro-helper-defn int-attribute-expansion
                   [context node value property]
                   (if value
                     (if (int? value)
                       [`(lui.ui/int-property! ~context ~node ~property ~value)]
                       [`(lui.ui/int-property-signal!
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

(macro-helper-defn accordion-event-expansion [context node attrs]
                   (let [on-toggle (:on-toggle attrs)]
                     (if on-toggle
                       [`(lui.ui/bool-property!
                          ~context ~node lui.protocol/ToggleEnabled true)
                        `(lui.ui/on-event!
                          ~context ~node
                          (fn [~'event]
                            (match ~'event
                              (lui.protocol/ToggleChanged ~'_node ~'_selected)
                              (~on-toggle ~'event)
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

(macro-helper-defn tree-item-event-expansion [context node attrs]
                   (let [on-press (:on-press attrs)
                         on-change (:on-change attrs)
                         on-toggle (:on-toggle attrs)]
                     (if (or on-press on-change on-toggle)
                       [`(lui.ui/on-event!
                          ~context ~node
                          (fn [~'event]
                            (match ~'event
                              (lui.protocol/Press ~'_node)
                              ~(if on-press `(~on-press ~'event) true)
                              (lui.protocol/Change ~'_node)
                              ~(if on-change `(~on-change ~'event) true)
                              (lui.protocol/ToggleChanged ~'_node ~'_expanded)
                              ~(if on-toggle `(~on-toggle ~'event) true)
                              ~'_ true)))]
                       [])))

(macro-helper-defn tree-item-property-expansions [context node attrs]
                   (concat
                    (string-attribute-expansion
                     context node (:role attrs) 'lui.protocol/RoleValue)
                    (int-attribute-expansion
                     context node (:tree-level attrs) 'lui.protocol/TreeLevel)
                    (bool-attribute-expansion
                     context node (:expanded attrs) 'lui.protocol/Expanded)
                    (bool-attribute-expansion
                     context node (:selected attrs) 'lui.protocol/Selected)
                    (string-attribute-expansion
                     context node (:label attrs)
                     'lui.protocol/AccessibilityLabel)
                    (if (:on-press attrs)
                      [`(lui.ui/bool-property!
                         ~context ~node lui.protocol/PressEnabled true)]
                      [])
                    (if (:on-change attrs)
                      [`(lui.ui/bool-property!
                         ~context ~node lui.protocol/ChangeEnabled true)]
                      [])
                    (if (:on-toggle attrs)
                      [`(lui.ui/bool-property!
                         ~context ~node lui.protocol/ToggleEnabled true)]
                      [])))

(macro-helper-defn list-item-event-expansion [context node attrs]
                   (let [on-press (:on-press attrs)
                         on-double-press (:on-double-press attrs)
                         on-submit (:on-submit attrs)
                         on-change (:on-change attrs)
                         on-toggle (:on-toggle attrs)]
                     (if (or on-press on-double-press on-submit
                             on-change on-toggle)
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
                              (lui.protocol/Change ~'_node)
                              ~(if on-change `(~on-change ~'event) true)
                              (lui.protocol/ToggleChanged ~'_node ~'_expanded)
                              ~(if on-toggle `(~on-toggle ~'event) true)
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
                        ~@(tree-item-property-expansions context node attrs)
                        ~@(tree-item-event-expansion context node attrs)
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

(defelement alert [context parent attrs & children]
  (let [node (gensym "node")]
    `(let [~node (lui.ui/alert! ~context)]
       ~@(string-attribute-expansion
          context node (:text attrs) 'lui.protocol/TextValue)
       ~@(string-attribute-expansion
          context node (:variant attrs) 'lui.protocol/VariantValue)
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

(macro-helper-defn reactions-expansions [context node form]
                   (let [attrs (element-attrs form)
                         children (element-children form)
                         value (:value attrs)
                         literal-text
                         (if (and (= (count children) 1)
                                  (string? (first children)))
                           (first children)
                           nil)]
                     (when (and value (if (empty? children) false true))
                       (throw
                        (IllegalArgumentException.
                         "reactions accepts :value or one text child, not both")))
                     (when (and (if value false true)
                                (if literal-text false true))
                       (throw
                        (IllegalArgumentException.
                         "reactions requires exactly one non-empty text value")))
                     (when (and literal-text (= literal-text ""))
                       (throw
                        (IllegalArgumentException.
                         "reactions requires exactly one non-empty text value")))
                     (concat
                      (if value
                        [`(lui.ui/text-property-signal!
                           ~context ~node ~value)]
                        [`(lui.ui/text-property!
                           ~context ~node ~literal-text)])
                      (string-attribute-expansion
                       context node
                       (if (:text-alignment attrs)
                         (:text-alignment attrs)
                         "end")
                       'lui.protocol/TextAlignment))))

(defelement bubble [context parent attrs & children]
  (when (:text attrs)
    (throw
     (IllegalArgumentException.
      "bubble text is reserved for reactions; use a text child")))
  (let [reaction-forms (reactions-children children)
        visible (message-children children)
        node (gensym "node")]
    (when (if (empty? reaction-forms)
            false
            (if (= (count reaction-forms) 1) false true))
      (throw
       (IllegalArgumentException.
        "bubble accepts at most one reactions child")))
    `(let [~node (lui.ui/bubble! ~context)]
       ~@(string-attribute-expansion
          context node (:variant attrs) 'lui.protocol/VariantValue)
       ~@(string-attribute-expansion
          context node (:label attrs) 'lui.protocol/AccessibilityLabel)
       ~@(if (empty? reaction-forms)
           []
           (reactions-expansions context node (first reaction-forms)))
       ~@(element-properties context node attrs)
       ~@(if parent
           [`(lui.ui/append! ~context ~parent ~node)]
           [])
       ~@(map
          (fn [child]
            `(lui.elements/element ~context ~node ~child))
          visible)
       ~node)))

(defelement reactions [_context _parent _attrs & _children]
  (throw
   (IllegalArgumentException.
    "reactions is only allowed as a direct child of bubble")))

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

(defelement table [context parent attrs & children]
  (container-expansion 'lui.ui/table! context parent attrs children))

(defelement table-row [context parent attrs & children]
  (let [node (gensym "node")]
    `(let [~node (lui.ui/table-row! ~context)]
       ~@(bool-attribute-expansion
          context node (:selected attrs) 'lui.protocol/Selected)
       ~@(element-properties context node attrs)
       ~@(if parent
           [`(lui.ui/append! ~context ~parent ~node)]
           [])
       ~@(map
          (fn [child]
            `(lui.elements/element ~context ~node ~child))
          children)
       ~node)))

(defelement table-cell [context parent attrs & children]
  (let [node (gensym "node")
        text-source (:text attrs)
        literal-text
        (if (and (= (count children) 1) (string? (first children)))
          (first children)
          nil)]
    (if text-source
      (if (= (count children) 0)
        nil
        (throw
         (IllegalArgumentException.
          "table-cell accepts :text or one text child, not both")))
      nil)
    (if (= (count children) 0)
      nil
      (if literal-text
        nil
        (throw
         (IllegalArgumentException.
          "table-cell is a text leaf"))))
    `(let [~node (lui.ui/table-cell! ~context)]
       ~@(if text-source
           [`(lui.ui/text-property-signal! ~context ~node ~text-source)]
           (if literal-text
             [`(lui.ui/text-property! ~context ~node ~literal-text)]
             []))
       ~@(string-attribute-expansion
          context node (:size attrs) 'lui.protocol/SizeValue)
       ~@(string-attribute-expansion
          context node (:text-alignment attrs) 'lui.protocol/TextAlignment)
       ~@(if (:on-press attrs)
           [`(lui.ui/bool-property!
              ~context ~node lui.protocol/PressEnabled true)
            `(lui.ui/on-event! ~context ~node ~(:on-press attrs))]
           [])
       ~@(element-properties context node attrs)
       ~@(if parent
           [`(lui.ui/append! ~context ~parent ~node)]
           [])
       ~node)))

(defelement tree [context parent attrs & children]
  (let [node (gensym "node")]
    `(let [~node (lui.ui/tree! ~context)]
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

(defelement resizable [context parent attrs & children]
  (let [node (gensym "node")]
    `(let [~node (lui.ui/resizable! ~context)]
       ~@(string-attribute-expansion
          context node (:label attrs) 'lui.protocol/AccessibilityLabel)
       ~@(int-attribute-expansion
          context node (:width attrs) 'lui.protocol/WidthValue)
       ~@(element-properties context node (assoc attrs :width nil))
       ~@(if parent
           [`(lui.ui/append! ~context ~parent ~node)]
           [])
       ~@(map
          (fn [child]
            `(lui.elements/element ~context ~node ~child))
          children)
       ~node)))

(defelement split [context parent attrs & children]
  (if (= (count children) 2)
    (let [node (gensym "node")
          value (:value attrs)
          resolved-value (if value value 0.0)
          constructor
          (if (float? resolved-value)
            'lui.ui/split-literal!
            'lui.ui/split!)]
      `(let [~node (~constructor ~context ~resolved-value)]
         ~@(int-attribute-expansion
            context node (:resize-duration attrs)
            'lui.protocol/ResizeDuration)
         ~@(string-attribute-expansion
            context node (:resize-easing attrs)
            'lui.protocol/ResizeEasing)
         ~@(float-attribute-expansion
            context node (:resize-origin attrs)
            'lui.protocol/ResizeOrigin)
         ~@(string-attribute-expansion
            context node (:label attrs)
            'lui.protocol/AccessibilityLabel)
         ~@(if (:on-resize attrs)
             [`(lui.ui/on-event! ~context ~node ~(:on-resize attrs))]
             [])
         ~@(element-properties context node attrs)
         ~@(if parent
             [`(lui.ui/append! ~context ~parent ~node)]
             [])
         ~@(map
            (fn [child]
              `(lui.elements/element ~context ~node ~child))
            children)
         ~node))
    (throw
     (IllegalArgumentException. "split requires exactly two children"))))

(defelement status-bar [context parent attrs & children]
  (let [value (:value attrs)
        literal-text
        (if (and (= (count children) 1) (string? (first children)))
          (first children)
          nil)
        node (gensym "node")]
    (when (and value (if (empty? children) false true))
      (throw
       (IllegalArgumentException.
        "status-bar accepts :value or one text child, not both")))
    (when (and (if value false true) (if literal-text false true))
      (throw
       (IllegalArgumentException.
        "status-bar requires exactly one text value")))
    `(let [~node (lui.ui/status-bar! ~context)]
       ~@(if value
           [`(lui.ui/text-property-signal! ~context ~node ~value)]
           [`(lui.ui/text-property! ~context ~node ~literal-text)])
       ~@(string-attribute-expansion
          context node (:text-alignment attrs) 'lui.protocol/TextAlignment)
       ~@(element-properties context node attrs)
       ~@(if parent
           [`(lui.ui/append! ~context ~parent ~node)]
           [])
       ~node)))

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

(defelement input-group [context parent attrs & children]
  (labelled-container-expansion
   'lui.ui/input-group!
   context
   parent
   (assoc attrs :accessibility-label (:label attrs))
   children))

(defelement input-group-actions [context parent attrs & children]
  (container-expansion
   'lui.ui/input-group-actions! context parent attrs children))

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

(defelement context-menu [context parent attrs & children]
  (if (empty? attrs)
    nil
    (throw (IllegalArgumentException. "context-menu accepts no attributes")))
  (if (context-menu-item-missing-press? children)
    (throw
     (IllegalArgumentException.
      "context-menu menu-item requires :on-press"))
    nil)
  (if (context-menu-has-item? children)
    nil
    (throw
     (IllegalArgumentException.
      "context-menu requires at least one menu-item")))
  (let [node (gensym "node")]
    `(let [~node (lui.ui/context-menu! ~context)]
       ~@(if parent
           [`(lui.ui/append! ~context ~parent ~node)]
           [])
       ~@(map
          (fn [child]
            `(lui.elements/element ~context ~node ~child))
          children)
       ~node)))

(macro-helper-defn modal-surface-expansion
                   [constructor context parent attrs children]
  (let [node (gensym "node")]
    `(let [~node (~constructor ~context)]
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

(defelement dialog [context parent attrs & children]
  (modal-surface-expansion
   'lui.ui/dialog! context parent attrs children))

(defelement sheet [context parent attrs & children]
  (modal-surface-expansion
   'lui.ui/sheet! context parent attrs children))

(defelement tooltip [context parent attrs & children]
  (let [node (gensym "node")
        text-source (:text attrs)
        literal-text
        (if (and (= (count children) 1) (string? (first children)))
          (first children)
          nil)]
    (if text-source
      (if (empty? children)
        nil
        (throw
         (IllegalArgumentException.
          "tooltip accepts :text or one text child, not both")))
      (if literal-text
        nil
        (throw
         (IllegalArgumentException.
          "tooltip requires exactly one text child"))))
    `(let [~node (lui.ui/tooltip! ~context)]
       ~@(if text-source
           [`(lui.ui/text-property-signal! ~context ~node ~text-source)]
           [`(lui.ui/text-property! ~context ~node ~literal-text)])
       ~@(string-attribute-expansion
          context node (:anchor attrs) 'lui.protocol/AnchorValue)
       ~@(string-attribute-expansion
          context node (:anchor-alignment attrs)
          'lui.protocol/AnchorAlignmentValue)
       ~@(float-attribute-expansion
          context node (:anchor-offset attrs) 'lui.protocol/AnchorOffset)
       ~@(int-attribute-expansion
          context node (:tooltip-delay attrs) 'lui.protocol/TooltipDelay)
       ~@(if parent
           [`(lui.ui/append! ~context ~parent ~node)]
           [])
       ~node)))

(defelement toast [context parent attrs & children]
  (let [node (gensym "node")]
    `(let [~node (lui.ui/toast! ~context)]
       ~@(int-attribute-expansion
          context node (:duration attrs) 'lui.protocol/DurationValue)
       ~@(string-attribute-expansion
          context node (:label attrs) 'lui.protocol/AccessibilityLabel)
       ~@(string-attribute-expansion
          context node (:class attrs) 'lui.protocol/StyleClass)
       ~@(dismiss-event-expansion context node attrs)
       ~@(if parent
           [`(lui.ui/append! ~context ~parent ~node)]
           [])
       ~@(map
          (fn [child]
            `(lui.elements/element ~context ~node ~child))
          children)
       ~node)))

(defelement toolbar [context parent attrs & children]
  (let [node (gensym "node")]
    `(let [~node (lui.ui/toolbar! ~context)]
       ~@(string-attribute-expansion
          context node (:orientation attrs) 'lui.protocol/OrientationValue)
       ~@(string-attribute-expansion
          context node (:label attrs) 'lui.protocol/AccessibilityLabel)
       ~@(int-attribute-expansion
          context node (:gap attrs) 'lui.protocol/Gap)
       ~@(string-attribute-expansion
          context node (:class attrs) 'lui.protocol/StyleClass)
       ~@(if parent
           [`(lui.ui/append! ~context ~parent ~node)]
           [])
       ~@(map
          (fn [child]
            `(lui.elements/element ~context ~node ~child))
          children)
       ~node)))

(defelement accordion [context parent attrs & children]
  (let [node (gensym "node")
        text-source (:text attrs)]
    (if text-source
      nil
      (throw (IllegalArgumentException. "accordion requires :text")))
    `(let [~node (lui.ui/accordion! ~context)]
       ~@(string-attribute-expansion
          context node text-source 'lui.protocol/TextValue)
       ~@(bool-attribute-expansion
          context node (:selected attrs) 'lui.protocol/Selected)
       ~@(int-attribute-expansion
          context node (:height attrs) 'lui.protocol/HeightValue)
       ~@(accordion-event-expansion context node attrs)
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
        literal-text (if (string? (first children)) (first children) nil)
        child-elements (if literal-text (vec (next children)) children)]
    (when (and text-source literal-text)
      (throw
       (IllegalArgumentException.
        "menu-item accepts :text or one text child, not both")))
    (loop [remaining child-elements]
      (if (empty? remaining)
        nil
        (if (or (dropdown-menu-form? (first remaining))
                (context-menu-form? (first remaining)))
          (recur (next remaining))
          (throw
           (IllegalArgumentException.
            "menu-item children must be dropdown-menu or context-menu")))))
    `(let [~node (lui.ui/menu-item! ~context)]
       ~@(if text-source
           [`(lui.ui/text-property-signal! ~context ~node ~text-source)]
           (if literal-text
             [`(lui.ui/text-property! ~context ~node ~literal-text)]
             []))
       ~@(string-attribute-expansion
          context node (:icon attrs) 'lui.protocol/InlineIconName)
       ~@(tree-item-property-expansions context node attrs)
       ~@(disabled-attribute-expansion context node attrs)
       ~@(picker-event-expansion context node attrs)
       ~@(if (:on-press attrs)
           [`(lui.ui/bool-property!
              ~context ~node lui.protocol/PressEnabled true)]
           [])
       ~@(element-properties context node attrs)
       ~@(if parent
           [`(lui.ui/append! ~context ~parent ~node)]
           [])
       ~@(map
          (fn [child]
            `(lui.elements/element ~context ~node ~child))
          child-elements)
       ~node)))

(defelement list-item [context parent attrs & children]
  (let [node (gensym "node")
        text-source (:text attrs)
        metadata-children
        (context-menu-children children)
        visible-children
        (visible-children children)
        literal-text
        (if (and (= (count visible-children) 1)
                 (string? (first visible-children)))
          (first visible-children)
          nil)
        child-elements
        (if literal-text metadata-children children)]
    (if text-source
      (if (= (count visible-children) 0)
        nil
        (throw
         (IllegalArgumentException.
          "list-item accepts :text or children, not both")))
      nil)
    (if (string? (first visible-children))
      (if (= (count visible-children) 1)
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
       ~@(tree-item-property-expansions context node attrs)
       ~@(disabled-attribute-expansion context node attrs)
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

(defelement image [context parent attrs & children]
  (when (if (empty? children) false true)
    (throw (IllegalArgumentException. "image does not accept children")))
  (when-not (:image attrs)
    (throw (IllegalArgumentException. "image requires an :image signal")))
  (let [node (gensym "node")]
    `(let [~node (lui.ui/image! ~context)]
       (lui.ui/int-property-signal!
        ~context ~node lui.protocol/ImageIdValue ~(:image attrs))
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
       ~@(element-properties context node attrs)
       ~@(if parent
           [`(lui.ui/append! ~context ~parent ~node)]
           [])
       ~node)))

(defelement media-surface [context parent attrs & children]
  (when (if (empty? children) false true)
    (throw
     (IllegalArgumentException. "media-surface does not accept children")))
  (when-not (:surface attrs)
    (throw
     (IllegalArgumentException.
      "media-surface requires a :surface signal")))
  (let [node (gensym "node")]
    `(let [~node (lui.ui/media-surface! ~context)]
       (lui.ui/int-property-signal!
        ~context ~node lui.protocol/SurfaceIdValue ~(:surface attrs))
       ~@(string-attribute-expansion
          context node (:label attrs) 'lui.protocol/AccessibilityLabel)
       ~@(element-properties context node attrs)
       ~@(if parent
           [`(lui.ui/append! ~context ~parent ~node)]
           [])
       ~node)))

(defelement stepper [context parent attrs & children]
  (when-not (:active attrs)
    (throw (IllegalArgumentException. "stepper requires an :active signal")))
  (let [node (gensym "node")]
    `(let [~node (lui.ui/stepper! ~context)]
       (lui.ui/int-property-signal!
        ~context ~node lui.protocol/ActiveIndex ~(:active attrs))
       ~@(string-attribute-expansion
          context node (:label attrs) 'lui.protocol/AccessibilityLabel)
       ~@(if parent
           [`(lui.ui/append! ~context ~parent ~node)]
           [])
       ~@(map
          (fn [child]
            `(lui.elements/element ~context ~node ~child))
          children)
       ~node)))

(defelement step [context parent attrs & children]
  (let [text-source (:text attrs)
        literal-text
        (if (and (= (count children) 1) (string? (first children)))
          (first children)
          nil)
        node (gensym "node")]
    (when (and text-source (if (empty? children) false true))
      (throw
       (IllegalArgumentException.
        "step accepts :text or one label child, not both")))
    (when (and (if text-source false true)
               (if literal-text false true))
      (throw
       (IllegalArgumentException.
        "step requires exactly one non-empty label")))
    (when (and literal-text (= literal-text ""))
      (throw
       (IllegalArgumentException.
        "step requires exactly one non-empty label")))
    `(let [~node (lui.ui/step! ~context)]
       ~@(if text-source
           [`(lui.ui/text-property-signal! ~context ~node ~text-source)]
           [`(lui.ui/text-property! ~context ~node ~literal-text)])
       ~@(if parent
           [`(lui.ui/append! ~context ~parent ~node)]
           [])
       ~node)))

(defelement timeline [context parent attrs & children]
  (let [node (gensym "node")]
    `(let [~node (lui.ui/timeline! ~context)]
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

(defelement timeline-item [context parent attrs & children]
  (when (if (empty? children) false true)
    (throw
     (IllegalArgumentException. "timeline-item does not accept children")))
  (when-not (:title attrs)
    (throw (IllegalArgumentException. "timeline-item requires :title")))
  (let [node (gensym "node")]
    `(let [~node (lui.ui/timeline-item! ~context)]
       ~@(string-attribute-expansion
          context node (:title attrs) 'lui.protocol/TitleValue)
       ~@(string-attribute-expansion
          context node (:description attrs) 'lui.protocol/DescriptionValue)
       ~@(string-attribute-expansion
          context node (:meta attrs) 'lui.protocol/MetaValue)
       ~@(string-attribute-expansion
          context node (:indicator attrs) 'lui.protocol/IndicatorValue)
       ~@(string-attribute-expansion
          context node (:icon attrs) 'lui.protocol/InlineIconName)
       ~@(string-attribute-expansion
          context node (:variant attrs) 'lui.protocol/VariantValue)
       ~@(bool-attribute-expansion
          context node (:connector attrs) 'lui.protocol/Connector)
       ~@(bool-attribute-expansion
          context node (:selected attrs) 'lui.protocol/Selected)
       ~@(if (:on-press attrs)
           [`(lui.ui/bool-property!
              ~context ~node lui.protocol/PressEnabled true)
            `(lui.ui/on-event! ~context ~node ~(:on-press attrs))]
           [])
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
  (when (= (first (first children)) :context-menu)
    (throw
     (IllegalArgumentException.
      "context-menu shape is static; put conditional items inside it")))
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
