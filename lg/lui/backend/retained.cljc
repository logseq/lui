(ns lui.backend.retained
  (:require [lui.protocol :as proto
             :refer [CreateNode DropNode SetProp InsertChild RemoveChild
                     MoveChild CreateExtension SetExtensionProp
                     RemoveExtensionProp Radio RadioGroup StringValue]]
            [lui.extension :as ext]))

(defn- empty-batches [] [])

(defn create-store []
  (record retained-store
          (retained-nodes (atom (hash-map)))
          (retained-batches (atom (empty-batches)))
          (retained-generation (atom 0))))

(defn- find-child-index [children child]
  (loop [index 0]
    (if (= index (count children))
      None
      (if (= child (nth children index))
        (Some index)
        (recur (inc index))))))

(defn- remove-at [values removed-index]
  (loop [index 0
         result []]
    (if (= index (count values))
      result
      (recur
       (inc index)
       (if (= index removed-index)
         result
         (conj result (nth values index)))))))

(defn- insert-at [values inserted-index value]
  (when (or (< inserted-index 0) (> inserted-index (count values)))
    (raise (Invalid_argument "child index is out of bounds")))
  (if (= inserted-index (count values))
    (conj values value)
    (loop [index 0
           result []]
      (if (= index (count values))
        result
        (recur
         (inc index)
         (conj
          (if (= index inserted-index)
            (conj result value)
            result)
          (nth values index)))))))

(defn- move-at [values from-index to-index]
  (let [value (nth values from-index)
        without (remove-at values from-index)]
    (insert-at without to-index value)))

(defn- update-node
  [nodes node current properties extension-properties children]
  (assoc
   nodes
   node
   (record retained-node
           (platform-node (:platform-node current))
     (semantic-kind (:semantic-kind current))
     (retained-parent (:retained-parent current))
     (retained-properties properties)
     (retained-extension-properties extension-properties)
     (retained-children children))))

(defn- update-parent [nodes node current parent]
  (assoc
   nodes
   node
   (record retained-node
           (platform-node (:platform-node current))
     (semantic-kind (:semantic-kind current))
     (retained-parent parent)
     (retained-properties (:retained-properties current))
     (retained-extension-properties
      (:retained-extension-properties current))
     (retained-children (:retained-children current)))))

(defn standard-kind [current]
  (match (:semantic-kind current)
    (StandardSemantic kind) (Some kind)
    (ExtensionSemantic _identifier _fingerprint) None))

(defn- standard-kind? [current expected]
  (match (standard-kind current)
    (Some kind) (= kind expected)
    None false))

(defn extension-identity [current]
  (match (:semantic-kind current)
    (ExtensionSemantic identifier fingerprint)
    (Some (tuple identifier fingerprint))
    (StandardSemantic _kind) None))

(defn- descendant? [nodes root target]
  (if (= root target)
    true
    (if-some [current (clojure.core/get nodes root)]
      (loop [index 0]
        (if (= index (count (:retained-children current)))
          false
          (if (descendant?
               nodes (nth (:retained-children current) index) target)
            true
            (recur (inc index)))))
      false)))

(defn- extension-schema [registry identifier]
  (match (ext/schema registry identifier)
    (Some schema) schema
    None (raise (Invalid_argument "unknown extension identifier"))))

(defn- retained-child-supported? [registry nodes parent child]
  (match (:semantic-kind child)
    (ExtensionSemantic child-identifier _child-fingerprint)
    (if (ext/tweak? registry child-identifier)
      (let [children (:retained-children child)]
        (and
         (= 1 (count children))
         (if-some [inner-child (clojure.core/get nodes (nth children 0))]
           (retained-child-supported? registry nodes parent inner-child)
           false)))
      (match (:semantic-kind parent)
        (StandardSemantic parent-kind)
        (ext/standard-container-supported? parent-kind)
        (ExtensionSemantic parent-identifier _parent-fingerprint)
        (if (ext/tweak? registry parent-identifier)
          (empty? (:retained-children parent))
          (ext/identifier-allowed?
           (:extension-child-identifiers
            (extension-schema registry parent-identifier))
           child-identifier))))
    (StandardSemantic child-kind)
    (match (:semantic-kind parent)
      (StandardSemantic parent-kind)
      (and
       (proto/can-contain-children? parent-kind)
       (proto/child-kind-supported? parent-kind child-kind))
      (ExtensionSemantic parent-identifier _parent-fingerprint)
      (if (ext/tweak? registry parent-identifier)
        (empty? (:retained-children parent))
        (:extension-standard-children
         (extension-schema registry parent-identifier))))))

(defn- unsupported-child-message [parent child]
  (match (tuple (:semantic-kind parent) (:semantic-kind child))
    (tuple (StandardSemantic parent-kind) (StandardSemantic _child-kind))
    (cond
      (not (proto/can-contain-children? parent-kind))
      "parent cannot contain children"
      (= parent-kind proto/Table) "table can contain only table-row"
      (= parent-kind proto/TableRow) "table-row can contain only table-cell"
      (= parent-kind proto/Tree) "tree accepts only row containers"
      :else "unsupported child kind")
    _ "unsupported child kind"))

(defn- apply-op-with-extensions
  [nodes platform-for extension-platform-for registry operation]
  (match operation
    (CreateNode node kind)
    (if (contains? nodes node)
      (raise (Invalid_argument "node already exists"))
      (assoc
       nodes node
       (record retained-node
         (platform-node (platform-for kind))
         (semantic-kind (StandardSemantic kind))
         (retained-parent None)
         (retained-properties (hash-map))
         (retained-extension-properties (hash-map))
         (retained-children []))))

    (CreateExtension node identifier fingerprint)
    (if (contains? nodes node)
      (raise (Invalid_argument "node already exists"))
      (let [schema (extension-schema registry identifier)]
        (let [expected
              (if (ext/tweak? registry identifier)
                (ext/tweak-fingerprint schema)
                (ext/fingerprint schema))]
        (when-not (= fingerprint expected)
          (raise (Invalid_argument "extension fingerprint mismatch")))
        (assoc
         nodes node
         (record retained-node
           (platform-node (extension-platform-for node identifier))
           (semantic-kind (ExtensionSemantic identifier fingerprint))
           (retained-parent None)
           (retained-properties (hash-map))
           (retained-extension-properties (hash-map))
           (retained-children []))))))

    (DropNode node)
    (if-some [current (clojure.core/get nodes node)]
      (cond
        (match (:retained-parent current)
          (Some _parent) true
          None false)
        (raise (Invalid_argument "cannot drop an attached node"))
        (not (empty? (:retained-children current)))
        (raise (Invalid_argument "cannot drop a node with children"))
        :else (dissoc nodes node))
      (raise (Invalid_argument "unknown node")))

    (SetProp node property value)
    (if-some [current (clojure.core/get nodes node)]
      (match (standard-kind current)
        (Some kind)
        (if (and
             (proto/property-supported? kind property)
             (proto/property-value-supported-for-kind? kind property value))
          (update-node
           nodes node current
           (assoc (:retained-properties current) property value)
           (:retained-extension-properties current)
           (:retained-children current))
          (raise (Invalid_argument "unsupported property value")))
        None (raise (Invalid_argument "standard property targets extension")))
      (raise (Invalid_argument "unknown node")))

    (SetExtensionProp node property value)
    (if-some [current (clojure.core/get nodes node)]
      (match (:semantic-kind current)
        (ExtensionSemantic identifier _fingerprint)
        (let [schema (extension-schema registry identifier)]
          (when-not (ext/property-value-supported? schema property value)
            (raise (Invalid_argument "unsupported extension property value")))
          (update-node
           nodes node current (:retained-properties current)
           (assoc (:retained-extension-properties current) property value)
           (:retained-children current)))
        (StandardSemantic _kind)
        (raise (Invalid_argument "extension property targets standard node")))
      (raise (Invalid_argument "unknown node")))

    (RemoveExtensionProp node property)
    (if-some [current (clojure.core/get nodes node)]
      (match (:semantic-kind current)
        (ExtensionSemantic identifier _fingerprint)
        (let [schema (extension-schema registry identifier)]
          (when-not (ext/property-supported? schema property)
            (raise (Invalid_argument "unknown extension property")))
          (update-node
           nodes node current (:retained-properties current)
           (dissoc (:retained-extension-properties current) property)
           (:retained-children current)))
        (StandardSemantic _kind)
        (raise (Invalid_argument "extension property targets standard node")))
      (raise (Invalid_argument "unknown node")))

    (InsertChild parent child index)
    (if-some [parent-node (clojure.core/get nodes parent)]
      (if-some [child-node (clojure.core/get nodes child)]
        (cond
          (not (retained-child-supported? registry nodes parent-node child-node))
          (raise (Invalid_argument
                  (unsupported-child-message parent-node child-node)))
          (descendant? nodes child parent)
          (raise (Invalid_argument "child insertion would create a cycle"))
          (match (:retained-parent child-node)
            (Some _current-parent) true
            None false)
          (raise (Invalid_argument "child is already attached"))
          :else
          (let [with-child
                (update-node
                 nodes parent parent-node (:retained-properties parent-node)
                 (:retained-extension-properties parent-node)
                 (insert-at (:retained-children parent-node) index child))]
            (update-parent with-child child child-node (Some parent))))
        (raise (Invalid_argument "unknown child")))
      (raise (Invalid_argument "unknown parent")))

    (RemoveChild parent child)
    (if-some [parent-node (clojure.core/get nodes parent)]
      (if-some [index (find-child-index
                       (:retained-children parent-node) child)]
        (if-some [child-node (clojure.core/get nodes child)]
          (let [without-child
                (update-node
                 nodes parent parent-node (:retained-properties parent-node)
                 (:retained-extension-properties parent-node)
                 (remove-at (:retained-children parent-node) index))]
            (update-parent without-child child child-node None))
          (raise (Invalid_argument "unknown child")))
        (raise (Invalid_argument "child is not attached to parent")))
      (raise (Invalid_argument "unknown parent")))

    (MoveChild parent child index)
    (if-some [parent-node (clojure.core/get nodes parent)]
      (if-some [current-index (find-child-index
                               (:retained-children parent-node) child)]
        (update-node
         nodes parent parent-node (:retained-properties parent-node)
         (:retained-extension-properties parent-node)
         (move-at (:retained-children parent-node) current-index index))
        (raise (Invalid_argument "child is not attached to parent")))
      (raise (Invalid_argument "unknown parent")))))

(defn- unavailable-extension-platform [_node _identifier]
  (raise (Invalid_argument "extension registry is not configured")))

(defn- apply-op [nodes platform-for operation]
  (apply-op-with-extensions
   nodes platform-for unavailable-extension-platform (ext/registry) operation))

(defn- string-property [properties property]
  (match (clojure.core/get properties property)
    (Some (StringValue value)) value
    _ ""))

(defn- node-properties-error [current]
  (let [kind
        (match (standard-kind current)
          (Some value) value
          None (raise (Invalid_argument "expected standard node")))
        properties (:retained-properties current)]
    (if (not (proto/surface-size-supported? properties))
      "surface size constraints conflict"
      (if (or (= kind proto/Button) (= kind proto/ToggleButton))
        (let [text (string-property properties proto/TextValue)
              label (string-property properties proto/AccessibilityLabel)
              icon (string-property properties proto/InlineIconName)]
          (if (and (= text "") (not (= icon "")) (= label ""))
            "icon-only button requires an accessibility label"
            "button requires text or an accessibility label"))
        (if (= kind proto/Icon)
          "icon requires a valid name"
          "node properties conflict")))))

(defn- context-menu-child? [nodes child]
  (if-some [current (clojure.core/get nodes child)]
    (standard-kind? current proto/ContextMenu)
    false))

(defn- validate-list-item-content! [nodes current]
  (when (standard-kind? current proto/ListItem)
    (let [text
          (string-property (:retained-properties current) proto/TextValue)
          visible-children
          (filterv
           (fn [child] (not (context-menu-child? nodes child)))
           (:retained-children current))]
      (when (and (not (= text "")) (not (empty? visible-children)))
        (raise
         (Invalid_argument "list-item accepts text or children, not both")))
      (when (and (= text "") (empty? visible-children))
        (raise
         (Invalid_argument "list-item requires text or children"))))))

(defn- bool-property-true? [properties property]
  (match (clojure.core/get properties property)
    (Some (proto/BoolValue true)) true
    _ false))

(defn- interactive-context-menu-host? [current]
  (let [properties (:retained-properties current)]
    (or
     (match (standard-kind current)
       (Some kind) (proto/context-menu-host-kind? kind)
       None false)
     (bool-property-true? properties proto/PressEnabled)
     (bool-property-true? properties proto/DoublePressEnabled)
     (bool-property-true? properties proto/ToggleEnabled)
     (bool-property-true? properties proto/HoldEnabled))))

(defn- validate-context-menu! [nodes current]
  (let [context-children
        (filterv
         (fn [child] (context-menu-child? nodes child))
         (:retained-children current))]
    (when (> (count context-children) 1)
      (raise (Invalid_argument "host accepts at most one context-menu")))
    (when (and (not (empty? context-children))
               (not (interactive-context-menu-host? current)))
      (raise (Invalid_argument "context-menu host must be interactive"))))
  (when (standard-kind? current proto/ContextMenu)
    (match (:retained-parent current)
      None (raise (Invalid_argument "context-menu requires a direct host"))
      _ nil)
    (doseq [child-id (:retained-children current)]
      (if-some [child (clojure.core/get nodes child-id)]
        (let [properties (:retained-properties child)]
          (when (and (standard-kind? child proto/MenuItem)
                     (not (bool-property-true? properties proto/PressEnabled)))
            (raise
             (Invalid_argument "context-menu menu-item requires press support")))
          (when (and (standard-kind? child proto/MenuItem)
                     (not (empty? (:retained-children child))))
            (raise
             (Invalid_argument "context-menu does not support nested menus")))
          (when (and (standard-kind? child proto/MenuItem)
                     (some
                      (fn [property]
                        (not (or (= property proto/TextValue)
                                 (= property proto/Enabled)
                                 (= property proto/PressEnabled))))
                      (keys properties)))
            (raise
             (Invalid_argument "context-menu menu-item has unsupported metadata")))
          (when (and
                 (standard-kind? child proto/Divider)
                 (not
                  (or
                   (empty? properties)
                   (= properties
                      {proto/OrientationValue
                       (proto/StringValue "horizontal")
                       proto/StyleClass
                       (proto/StringValue "lui-separator")}))))
            (raise
             (Invalid_argument "context-menu separator accepts no attributes"))))
        (raise (Invalid_argument "unknown context-menu child"))))))

(defn- validate-image-source! [current]
  (let [kind
        (match (standard-kind current)
          (Some value) value
          None (raise (Invalid_argument "expected standard node")))]
    (when (or (= kind proto/Avatar) (= kind proto/Image))
      (let [properties (:retained-properties current)
            has-source-x (contains? properties proto/SourceX)
            has-source-y (contains? properties proto/SourceY)
            has-source-width (contains? properties proto/SourceWidth)
            has-source-height (contains? properties proto/SourceHeight)
            source-count
            (+ (if has-source-x 1 0)
               (if has-source-y 1 0)
               (if has-source-width 1 0)
               (if has-source-height 1 0))]
        (when (and (> source-count 0) (< source-count 4))
          (raise
           (Invalid_argument
            (str (if (= kind proto/Avatar) "avatar" "image")
                 " source crop requires all four coordinates"))))
        (when (= source-count 4)
          (let [x
                (match (clojure.core/get properties proto/SourceX)
                  (Some (proto/FloatValue value)) value
                  _ -1.0)
                y
                (match (clojure.core/get properties proto/SourceY)
                  (Some (proto/FloatValue value)) value
                  _ -1.0)
                width
                (match (clojure.core/get properties proto/SourceWidth)
                  (Some (proto/FloatValue value)) value
                  _ 0.0)
                height
                (match (clojure.core/get properties proto/SourceHeight)
                  (Some (proto/FloatValue value)) value
                  _ 0.0)]
            (when (or (< x 0.0) (< y 0.0))
              (raise
               (Invalid_argument
                (str (if (= kind proto/Avatar) "avatar" "image")
                     " source crop coordinates must be non-negative"))))
            (when (or (<= width 0.0) (<= height 0.0))
              (raise
               (Invalid_argument
                (str (if (= kind proto/Avatar) "avatar" "image")
                     " source crop dimensions must be positive"))))))))))

(defn- validate-media-resource! [current]
  (let [kind
        (match (standard-kind current)
          (Some value) value
          None (raise (Invalid_argument "expected standard node")))
        properties (:retained-properties current)]
    (when (and (= kind proto/Image)
               (not (contains? properties proto/ImageIdValue)))
      (raise (Invalid_argument "image requires image")))
    (when (and (= kind proto/MediaSurface)
               (not (contains? properties proto/SurfaceIdValue)))
      (raise (Invalid_argument "media-surface requires surface")))))

(defn- validate-progress-structure! [current]
  (let [kind
        (match (standard-kind current)
          (Some value) value
          None (raise (Invalid_argument "expected standard node")))
        properties (:retained-properties current)]
    (when (and (= kind proto/Stepper)
               (not (contains? properties proto/ActiveIndex)))
      (raise (Invalid_argument "stepper requires active")))
    (when (and (= kind proto/TimelineItem)
               (not (contains? properties proto/TitleValue)))
      (raise (Invalid_argument "timeline-item requires title")))))

(defn- child-kind [nodes child]
  (if-some [current (clojure.core/get nodes child)]
    (match (standard-kind current)
      (Some kind) kind
      None (raise (Invalid_argument "expected standard child")))
    (raise (Invalid_argument "unknown child"))))

(defn- validate-input-group! [nodes current]
  (let [kind
        (match (standard-kind current)
          (Some value) value
          None (raise (Invalid_argument "expected standard node")))
        children (:retained-children current)]
    (when (= kind proto/InputGroup)
      (when (or (empty? children) (> (count children) 2))
        (raise
         (Invalid_argument
          "input-group requires one textarea and optional actions")))
      (when (not (= (child-kind nodes (nth children 0)) proto/Textarea))
        (raise
         (Invalid_argument "input-group requires textarea first")))
      (when (and (= (count children) 2)
                 (not (= (child-kind nodes (nth children 1))
                         proto/InputGroupActions)))
        (raise
         (Invalid_argument "input-group actions must follow textarea"))))
    (when (= kind proto/InputGroupActions)
      (match (:retained-parent current)
        (Some parent)
        (if-some [parent-node (clojure.core/get nodes parent)]
          (when-not (standard-kind? parent-node proto/InputGroup)
            (raise
             (Invalid_argument
              "input-group-actions requires a direct input-group parent")))
          (raise (Invalid_argument "unknown input-group parent")))
        None
        (raise
         (Invalid_argument
          "input-group-actions requires a direct input-group parent"))))))

(defn- has-ancestor-kind? [nodes parent kind]
  (match parent
    (Some parent-id)
    (if-some [parent-node (clojure.core/get nodes parent-id)]
      (or
       (standard-kind? parent-node kind)
       (has-ancestor-kind? nodes (:retained-parent parent-node) kind))
      false)
    None false))

(defn- validate-tree-item! [nodes current]
  (when
   (= (string-property (:retained-properties current) proto/RoleValue)
      "treeitem")
    (when (not (has-ancestor-kind?
                nodes (:retained-parent current) proto/Tree))
      (raise
       (Invalid_argument "treeitem must be contained by a tree")))))

(defn- validate-split! [current]
  (when (standard-kind? current proto/Split)
    (when (not (= (count (:retained-children current)) 2))
      (raise (Invalid_argument "split requires exactly two children")))))

(defn- validate-nodes! [nodes registry]
  (reduce-kv
   (fn [_valid _node current]
     (match (:semantic-kind current)
       (StandardSemantic kind)
       (do
         (when (and
                (= kind Radio)
                (not (has-ancestor-kind?
                      nodes (:retained-parent current) RadioGroup)))
           (raise
            (Invalid_argument "radio must be contained by a radio-group")))
         (validate-list-item-content! nodes current)
         (validate-context-menu! nodes current)
         (validate-image-source! current)
         (validate-media-resource! current)
         (validate-progress-structure! current)
         (validate-input-group! nodes current)
         (validate-tree-item! nodes current)
         (validate-split! current)
         (when-not
          (proto/node-properties-supported?
           kind (:retained-properties current))
           (raise (Invalid_argument (node-properties-error current)))))
       (ExtensionSemantic identifier _fingerprint)
       (do
         (when-not
          (ext/properties-supported?
           (extension-schema registry identifier)
           (:retained-extension-properties current))
           (raise (Invalid_argument "extension properties are incomplete")))
         (when (and
                (ext/tweak? registry identifier)
                (not (= 1 (count (:retained-children current)))))
           (raise (Invalid_argument "platform tweak requires exactly one child")))))
     true)
   true
   nodes))

(defn- apply-operations-with-extensions
  [nodes platform-for extension-platform-for registry batch]
  (loop [index 0
         current-nodes nodes]
    (if (= index (count (:ops batch)))
      (do
        (validate-nodes! current-nodes registry)
        current-nodes)
      (recur
       (inc index)
       (apply-op-with-extensions
        current-nodes platform-for extension-platform-for registry
        (nth (:ops batch) index))))))

(defn- apply-operations [nodes platform-for batch]
  (apply-operations-with-extensions
   nodes platform-for unavailable-extension-platform (ext/registry) batch))

(defn- commit-batch!
  [store platform-for extension-platform-for registry send-batch batch]
  (let [expected-generation (inc (deref (:retained-generation store)))]
    (when-not (= expected-generation (:generation batch))
      (raise
       (Invalid_argument
        (str "expected patch generation " expected-generation
             ", received " (:generation batch)))))
    (let [next-nodes
          (apply-operations-with-extensions
           (deref (:retained-nodes store)) platform-for
           extension-platform-for registry batch)]
      (if (send-batch batch)
        (do
          (reset! (:retained-nodes store) next-nodes)
          (swap! (:retained-batches store) conj batch)
          (reset! (:retained-generation store) (:generation batch))
          true)
        (raise (Invalid_argument "platform rejected patch batch"))))))

(defn apply-batch-with! [store platform-for send-batch batch]
  (commit-batch!
   store platform-for unavailable-extension-platform (ext/registry)
   send-batch batch))

(defn apply-batch-with-extensions!
  [store platform-for extension-platform-for registry send-batch batch]
  (commit-batch!
   store platform-for extension-platform-for registry send-batch batch))

(defn- unavailable-standard-platform [_kind]
  (raise (Invalid_argument "standard platform factory is not configured")))

(defn apply-extension-batch! [store extension-platform-for registry batch]
  (commit-batch!
   store unavailable-standard-platform extension-platform-for registry
   (fn [_batch] true) batch))

(defn apply-batch! [store platform-for batch]
  (apply-batch-with! store platform-for (fn [_batch] true) batch))

(defn node [store node-id]
  (clojure.core/get (deref (:retained-nodes store)) node-id))

(defn nodes [store]
  (deref (:retained-nodes store)))

(defn platform-node [store node-id]
  (if-some [current (node store node-id)]
    (Some (:platform-node current))
    None))

(defn property [store node-id property]
  (if-some [current (node store node-id)]
    (clojure.core/get (:retained-properties current) property)
    None))

(defn extension-identifier [store node-id]
  (if-some [current (node store node-id)]
    (match (:semantic-kind current)
      (ExtensionSemantic identifier _fingerprint) (Some identifier)
      (StandardSemantic _kind) None)
    None))

(defn extension-property [store node-id property]
  (if-some [current (node store node-id)]
    (clojure.core/get (:retained-extension-properties current) property)
    None))

(defn children [store node-id]
  (if-some [current (node store node-id)]
    (:retained-children current)
    (raise (Invalid_argument "unknown node"))))

(defn node-count [store]
  (count (deref (:retained-nodes store))))

(defn batches [store]
  (deref (:retained-batches store)))

(defn generation [store]
  (deref (:retained-generation store)))
