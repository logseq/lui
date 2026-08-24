(ns lui.backend.retained
  (:require [lui.protocol :as proto
             :refer [CreateNode DropNode SetProp InsertChild RemoveChild
                     MoveChild Radio RadioGroup StringValue]]))

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

(defn- update-node [nodes node current properties children]
  (assoc
   nodes
   node
   (record retained-node
     (platform-node (:platform-node current))
     (semantic-kind (:semantic-kind current))
     (retained-parent (:retained-parent current))
     (retained-properties properties)
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
     (retained-children (:retained-children current)))))

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

(defn- apply-op [nodes platform-for operation]
  (match operation
    (CreateNode node kind)
    (if (contains? nodes node)
      (raise (Invalid_argument "node already exists"))
      (assoc
       nodes
       node
       (record retained-node
         (platform-node (platform-for kind))
         (semantic-kind kind)
         (retained-parent None)
         (retained-properties (hash-map))
               (retained-children []))))

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
      (if (and
           (proto/property-supported? (:semantic-kind current) property)
           (proto/property-value-supported? property value))
        (update-node
         nodes node current
         (assoc (:retained-properties current) property value)
         (:retained-children current))
        (raise (Invalid_argument "unsupported property value")))
      (raise (Invalid_argument "unknown node")))

    (InsertChild parent child index)
    (if-some [parent-node (clojure.core/get nodes parent)]
      (if-some [child-node (clojure.core/get nodes child)]
        (cond
          (not (proto/can-contain-children? (:semantic-kind parent-node)))
          (raise (Invalid_argument "parent cannot contain children"))
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
         (move-at (:retained-children parent-node) current-index index))
        (raise (Invalid_argument "child is not attached to parent")))
      (raise (Invalid_argument "unknown parent")))))

(defn- string-property [properties property]
  (match (clojure.core/get properties property)
    (Some (StringValue value)) value
    _ ""))

(defn- node-properties-error [current]
  (let [kind (:semantic-kind current)
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

(defn- validate-list-item! [current]
  (when (= (:semantic-kind current) proto/ListItem)
    (let [text
          (string-property (:retained-properties current) proto/TextValue)
          has-text (not (= text ""))
          has-children (not (empty? (:retained-children current)))]
      (when (and has-text has-children)
        (raise
         (Invalid_argument "list-item accepts text or children, not both")))
      (when (and (not has-text) (not has-children))
        (raise
         (Invalid_argument "list-item requires text or children"))))))

(defn- validate-avatar! [current]
  (when (= (:semantic-kind current) proto/Avatar)
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
          "avatar source crop requires all four coordinates")))
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
              "avatar source crop coordinates must be non-negative")))
          (when (or (<= width 0.0) (<= height 0.0))
            (raise
             (Invalid_argument
              "avatar source crop dimensions must be positive"))))))))

(defn- has-ancestor-kind? [nodes parent kind]
  (match parent
    (Some parent-id)
    (if-some [parent-node (clojure.core/get nodes parent-id)]
      (or
       (= (:semantic-kind parent-node) kind)
       (has-ancestor-kind? nodes (:retained-parent parent-node) kind))
      false)
    None false))

(defn- validate-nodes! [nodes]
  (reduce-kv
   (fn [_valid _node current]
     (when (and
            (= (:semantic-kind current) Radio)
            (not (has-ancestor-kind?
                  nodes (:retained-parent current) RadioGroup)))
       (raise
        (Invalid_argument "radio must be contained by a radio-group")))
     (validate-list-item! current)
     (validate-avatar! current)
     (when (not
            (proto/node-properties-supported?
             (:semantic-kind current) (:retained-properties current)))
       (raise
        (Invalid_argument
         (node-properties-error current))))
     true)
   true
   nodes))

(defn- apply-operations [nodes platform-for batch]
  (loop [index 0
         current-nodes nodes]
    (if (= index (count (:ops batch)))
      (do
        (validate-nodes! current-nodes)
        current-nodes)
      (recur
       (inc index)
       (apply-op current-nodes platform-for (nth (:ops batch) index))))))

(defn apply-batch-with! [store platform-for send-batch batch]
  (let [expected-generation (inc (deref (:retained-generation store)))]
    (when (not (= expected-generation (:generation batch)))
      (raise
       (Invalid_argument
        (str "expected patch generation " expected-generation
             ", received " (:generation batch)))))
    (let [next-nodes
        (apply-operations
         (deref (:retained-nodes store)) platform-for batch)]
      (if (send-batch batch)
        (do
          (reset! (:retained-nodes store) next-nodes)
          (swap! (:retained-batches store) conj batch)
          (reset! (:retained-generation store) (:generation batch))
          true)
        (raise (Invalid_argument "platform rejected patch batch"))))))

(defn apply-batch! [store platform-for batch]
  (apply-batch-with! store platform-for (fn [_batch] true) batch))

(defn node [store node-id]
  (clojure.core/get (deref (:retained-nodes store)) node-id))

(defn nodes [store]
  (deref (:retained-nodes store)))

(defn property [store node-id property]
  (if-some [current (node store node-id)]
    (clojure.core/get (:retained-properties current) property)
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
