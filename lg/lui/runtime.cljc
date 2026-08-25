(ns lui.runtime
  (:require [signal.core :as sig]
            [lui.protocol :as proto :refer [ExtensionEvent]]
            [lui.extension :as ext]))

(defn- empty-ops [] [])
(defn- empty-handlers [] [])
(defn- empty-dynamic-segments [] (hash-map))
(defn- empty-extension-nodes [] (hash-map))
(defn- empty-extension-properties [] (hash-map))

(defn create-with-extensions [scheduler backend registry]
  (ext/freeze! registry)
  (record application
    (runtime-scheduler scheduler)
    (runtime-backend backend)
    (runtime-extension-registry registry)
    (next-node-id (atom 0))
    (mounted-nodes (atom (hash-map)))
    (runtime-extension-nodes (atom (empty-extension-nodes)))
    (runtime-properties (atom (hash-map)))
    (runtime-extension-properties (atom (empty-extension-properties)))
    (runtime-children (atom (hash-map)))
    (runtime-parents (atom (hash-map)))
    (pending-ops (atom (empty-ops)))
    (runtime-generation (atom 0))
    (runtime-diagnostics
     (atom
      (record flush-diagnostics
        (flush-status NotFlushed)
        (flush-generation 0)
        (flush-operation-count 0)
        (flush-pending-operation-count 0)
        (flush-mounted-node-count 0)
        (flush-handler-count 0)
        (flush-dynamic-segment-count 0)
        (flush-signal-generation 0)
        (flush-signal-round-count 0)
        (flush-signal-effect-count 0)
        (flush-signal-dirty-task-count 0))))
    (next-handler-id (atom 0))
    (event-handlers (atom (hash-map)))
    (next-dynamic-segment-id (atom 0))
    (dynamic-segments (atom (empty-dynamic-segments)))))

(defn create [scheduler backend]
  (create-with-extensions scheduler backend (ext/registry)))

(defn- enqueue! [application operation]
  (swap! (:pending-ops application) conj operation)
  true)

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
  (insert-at (remove-at values from-index) to-index
             (nth values from-index)))

(defn- descendant? [application root target]
  (if (= root target)
    true
    (if-some [children (clojure.core/get
                        (deref (:runtime-children application)) root)]
      (loop [index 0]
        (if (= index (count children))
          false
          (if (descendant? application (nth children index) target)
            true
            (recur (inc index)))))
      false)))

(defn- require-standard-node-kind [application node]
  (if-some [kind (clojure.core/get (deref (:mounted-nodes application)) node)]
    kind
    (raise (Invalid_argument "unknown node"))))

(defn- extension-identifier [application node]
  (clojure.core/get (deref (:runtime-extension-nodes application)) node))

(defn- require-extension-schema [application node]
  (if-some [identifier (extension-identifier application node)]
    (match (ext/schema (:runtime-extension-registry application) identifier)
      (Some schema) schema
      None (raise (Invalid_argument "unknown extension schema")))
    (raise (Invalid_argument "unknown extension node"))))

(defn- require-node! [application node]
  (when-not
   (or
    (contains? (deref (:mounted-nodes application)) node)
    (contains? (deref (:runtime-extension-nodes application)) node))
   (raise (Invalid_argument "unknown node")))
  true)

(defn create-node! [application kind]
  (let [node (swap! (:next-node-id application) inc)]
    (swap! (:mounted-nodes application) assoc node kind)
    (swap! (:runtime-properties application) assoc node (hash-map))
    (swap! (:runtime-children application) assoc node [])
    (enqueue! application (proto/create-node-op node kind))
    node))

(defn create-extension-node! [application identifier]
  (let [schema
        (match (ext/schema (:runtime-extension-registry application) identifier)
          (Some current) current
          None (raise (Invalid_argument "unknown extension identifier")))]
    (when-not
     (ext/profile-supported? schema (:backend-profile (:runtime-backend application)))
     (raise (Invalid_argument "extension is unsupported by backend profile")))
    (let [node (swap! (:next-node-id application) inc)]
      (swap! (:runtime-extension-nodes application) assoc node identifier)
      (swap! (:runtime-extension-properties application) assoc node (hash-map))
      (swap! (:runtime-children application) assoc node [])
      (enqueue!
       application
       (proto/create-extension-op node identifier (ext/fingerprint schema)))
      node)))

(defn create-tweak-node! [application identifier]
  (let [registry (:runtime-extension-registry application)]
    (when-not (ext/tweak? registry identifier)
      (raise (Invalid_argument "unknown platform tweak")))
    (let [schema
          (match (ext/schema registry identifier)
            (Some current) current
            None (raise (Invalid_argument "unknown platform tweak")))]
      (when-not
       (ext/profile-supported?
        schema (:backend-profile (:runtime-backend application)))
       (raise (Invalid_argument "tweak is unsupported by backend profile")))
      (let [node (swap! (:next-node-id application) inc)]
        (swap! (:runtime-extension-nodes application) assoc node identifier)
        (swap! (:runtime-extension-properties application) assoc node (hash-map))
        (swap! (:runtime-children application) assoc node [])
        (enqueue!
         application
         (proto/create-extension-op
          node identifier (ext/tweak-fingerprint schema)))
        node))))

(defn drop-node! [application node]
  (require-node! application node)
  (when (contains? (deref (:runtime-parents application)) node)
    (raise (Invalid_argument "cannot drop an attached node")))
  (when (not (empty? (children application node)))
    (raise (Invalid_argument "cannot drop a node with children")))
  (swap! (:mounted-nodes application) dissoc node)
  (swap! (:runtime-extension-nodes application) dissoc node)
  (swap! (:runtime-properties application) dissoc node)
  (swap! (:runtime-extension-properties application) dissoc node)
  (swap! (:runtime-children application) dissoc node)
  (swap! (:runtime-parents application) dissoc node)
  (enqueue! application (proto/drop-node-op node)))

(defn drop-subtree! [application node]
  (if-some [children (clojure.core/get
                      (deref (:runtime-children application)) node)]
    (do
      (doseq [child children]
        (remove-child! application node child)
        (drop-subtree! application child))
      (drop-node! application node))
    (drop-node! application node)))

(defn set-prop! [application node property value]
  (let [kind (require-standard-node-kind application node)]
    (when (not (proto/property-supported? kind property))
      (raise (Invalid_argument "property is unsupported by node kind")))
    (when (not (proto/property-value-supported-for-kind? kind property value))
      (raise (Invalid_argument "invalid property value"))))
  (swap! (:runtime-properties application) update node assoc property value)
  (enqueue! application (proto/set-prop-op node property value)))

(defn set-extension-prop! [application node property value]
  (let [schema (require-extension-schema application node)]
    (when-not (ext/property-value-supported? schema property value)
      (raise (Invalid_argument "invalid extension property value"))))
  (let [properties (:runtime-extension-properties application)
        current
        (if-some [values (clojure.core/get (deref properties) node)]
          values
          (hash-map))]
    (swap! properties assoc node (assoc current property value)))
  (enqueue! application (proto/set-extension-prop-op node property value)))

(defn remove-extension-prop! [application node property]
  (let [schema (require-extension-schema application node)]
    (when-not (ext/property-supported? schema property)
      (raise (Invalid_argument "unknown extension property"))))
  (let [properties (:runtime-extension-properties application)
        current
        (if-some [values (clojure.core/get (deref properties) node)]
          values
          (hash-map))]
    (swap! properties assoc node (dissoc current property)))
  (enqueue! application (proto/remove-extension-prop-op node property)))

(defn- standard-extension-container? [kind]
  (ext/standard-container-supported? kind))

(defn- identifier-allowed? [identifiers identifier]
  (ext/identifier-allowed? identifiers identifier))

(defn- child-supported? [application parent child]
  (let [standard-nodes (deref (:mounted-nodes application))
        extension-nodes (deref (:runtime-extension-nodes application))
        registry (:runtime-extension-registry application)]
    (if-some [child-identifier (clojure.core/get extension-nodes child)]
      (if (ext/tweak? registry child-identifier)
        (let [tweak-children (children application child)]
          (and (= 1 (count tweak-children))
               (child-supported? application parent (nth tweak-children 0))))
        (if-some [parent-kind (clojure.core/get standard-nodes parent)]
          (standard-extension-container? parent-kind)
          (if-some [parent-identifier (clojure.core/get extension-nodes parent)]
            (match (ext/schema registry parent-identifier)
              (Some schema)
              (if (ext/tweak? registry parent-identifier)
                (empty? (children application parent))
                (identifier-allowed?
                 (:extension-child-identifiers schema) child-identifier))
              None false)
            false)))
      (if-some [child-kind (clojure.core/get standard-nodes child)]
        (if-some [parent-kind (clojure.core/get standard-nodes parent)]
          (and
           (proto/can-contain-children? parent-kind)
           (proto/child-kind-supported? parent-kind child-kind))
          (if-some [parent-identifier (clojure.core/get extension-nodes parent)]
            (match (ext/schema registry parent-identifier)
              (Some schema)
              (if (ext/tweak? registry parent-identifier)
                (empty? (children application parent))
                (:extension-standard-children schema))
              None false)
            false))
        false))))

(defn insert-child! [application parent child index]
  (require-node! application parent)
  (require-node! application child)
  (let [children (children application parent)
        standard-nodes (deref (:mounted-nodes application))]
    (if-some [parent-kind (clojure.core/get standard-nodes parent)]
      (if-some [child-kind (clojure.core/get standard-nodes child)]
        (do
          (when-not (proto/can-contain-children? parent-kind)
            (raise (Invalid_argument "parent cannot contain children")))
          (when-not (proto/child-kind-supported? parent-kind child-kind)
            (raise
             (Invalid_argument
              (cond
                (= parent-kind proto/Table) "table can contain only table-row"
                (= parent-kind proto/TableRow)
                "table-row can contain only table-cell"
                (= parent-kind proto/Tree) "tree accepts only row containers"
                :else "unsupported child kind")))))
        (when-not (child-supported? application parent child)
          (raise (Invalid_argument "unsupported child kind"))))
      (when-not (child-supported? application parent child)
        (raise (Invalid_argument "unsupported child kind"))))
    (when (contains? (deref (:runtime-parents application)) child)
      (raise (Invalid_argument "child is already attached")))
    (when (or (< index 0) (> index (count children)))
      (raise (Invalid_argument "child index is out of bounds")))
    (when (descendant? application child parent)
      (raise (Invalid_argument "child insertion would create a cycle")))
    (swap! (:runtime-children application)
           assoc parent (insert-at children index child))
    (swap! (:runtime-parents application) assoc child parent))
  (enqueue! application (proto/insert-child-op parent child index)))

(defn remove-child! [application parent child]
  (require-node! application parent)
  (require-node! application child)
  (let [children (children application parent)]
    (if-some [index (find-child-index children child)]
      (do
        (swap! (:runtime-children application)
               assoc parent (remove-at children index))
        (swap! (:runtime-parents application) dissoc child))
      (raise (Invalid_argument "child is not attached to parent"))))
  (enqueue! application (proto/remove-child-op parent child)))

(defn move-child! [application parent child index]
  (require-node! application parent)
  (require-node! application child)
  (let [children (children application parent)]
    (if-some [current-index (find-child-index children child)]
      (do
        (when (or (< index 0) (>= index (count children)))
          (raise (Invalid_argument "child index is out of bounds")))
        (swap! (:runtime-children application)
               assoc parent (move-at children current-index index)))
      (raise (Invalid_argument "child is not attached to parent"))))
  (enqueue! application (proto/move-child-op parent child index)))

(defn bind-prop! [scope application node property source]
  (sig/own!
   scope
   (sig/observe
    source
    (fn [value]
      (set-prop! application node property value)))))

(defn bind-extension-prop! [scope application node property source]
  (sig/own!
   scope
   (sig/observe
    source
    (fn [value]
      (set-extension-prop! application node property value)))))

(defn- remove-handler! [application node handler-id]
  (if-some [handlers (clojure.core/get (deref (:event-handlers application)) node)]
    (let [remaining
          (filterv
           (fn [handler]
             (not (= handler-id (:handler-id handler))))
           handlers)]
      (if (empty? remaining)
        (swap! (:event-handlers application) dissoc node)
        (swap! (:event-handlers application) assoc node remaining))
      true)
    true))

(defn on-event! [scope application node callback]
  (require-node! application node)
  (let [handler-id (swap! (:next-handler-id application) inc)
        handler
        (record event-handler
          (handler-id handler-id)
          (handler-callback callback))
        handlers
        (if-some [current (clojure.core/get
                           (deref (:event-handlers application)) node)]
          current
          (empty-handlers))]
    (swap! (:event-handlers application)
           assoc node (conj handlers handler))
    (sig/on-dispose!
     scope
     (fn [] (remove-handler! application node handler-id)))
    true))

(defn dispatch! [application event]
  (let [node (proto/event-node event)]
    (match event
      (ExtensionEvent _event-node identifier name values)
      (let [schema (require-extension-schema application node)]
        (when-not (= identifier (:extension-identifier schema))
          (raise (Invalid_argument "extension event identifier mismatch")))
        (when-not (ext/event-payload-supported? schema name values)
          (raise (Invalid_argument "invalid extension event payload"))))
      _
      (let [kind (require-standard-node-kind application node)
            properties
            (if-some [current (clojure.core/get
                               (deref (:runtime-properties application)) node)]
              current
              (hash-map))]
        (when-not (proto/event-supported-for-properties? kind properties event)
          (raise (Invalid_argument "event is unsupported by node kind")))))
    (if-some [handlers (clojure.core/get
                        (deref (:event-handlers application)) node)]
      (do
        (doseq [handler handlers]
          (sig/enqueue-effect!
           (:runtime-scheduler application)
           (fn [] ((:handler-callback handler) event))))
        true)
      true)))

(defn- validate-extension-nodes! [application]
  (let [properties (deref (:runtime-extension-properties application))]
    (reduce-kv
     (fn [_valid node _identifier]
       (let [schema (require-extension-schema application node)
             values
             (if-some [current (clojure.core/get properties node)]
               current
               (hash-map))]
         (when-not (ext/properties-supported? schema values)
           (raise (Invalid_argument "extension properties are incomplete")))
         (when (and
                (ext/tweak?
                 (:runtime-extension-registry application)
                 (:extension-identifier schema))
                (not (= 1 (count (children application node)))))
           (raise (Invalid_argument "platform tweak requires exactly one child")))
         true))
     true
     (deref (:runtime-extension-nodes application)))))

(defn- handler-count [application]
  (reduce-kv
   (fn [total _node handlers]
     (+ total (count handlers)))
   0
   (deref (:event-handlers application))))

(defn- dynamic-segment-count [application]
  (reduce-kv
   (fn [total _parent segments]
     (+ total (count segments)))
   0
   (deref (:dynamic-segments application))))

(defn- record-diagnostics!
  [application status operation-count pending-operation-count]
  (let [signal-diagnostics
        (sig/last-stabilization (:runtime-scheduler application))]
    (reset!
     (:runtime-diagnostics application)
     (record flush-diagnostics
       (flush-status status)
       (flush-generation (deref (:runtime-generation application)))
       (flush-operation-count operation-count)
       (flush-pending-operation-count pending-operation-count)
       (flush-mounted-node-count (mounted-count application))
       (flush-handler-count (handler-count application))
       (flush-dynamic-segment-count (dynamic-segment-count application))
       (flush-signal-generation
        (:stabilization-generation signal-diagnostics))
       (flush-signal-round-count
        (:stabilization-rounds signal-diagnostics))
       (flush-signal-effect-count
        (:stabilization-effects signal-diagnostics))
       (flush-signal-dirty-task-count
        (:stabilization-dirty-tasks signal-diagnostics))))
    true))

(defn- apply-pending-batch!
  [application batch operation-count next-generation]
  (try
    (do
      (when-not ((:apply-batch (:runtime-backend application)) batch)
        (raise (Invalid_argument "backend rejected patch batch")))
      (reset! (:pending-ops application) (empty-ops))
      (reset! (:runtime-generation application) next-generation)
      (record-diagnostics! application Applied operation-count 0))
    (catch (Invalid_argument message)
      (do
        (record-diagnostics!
         application Rejected operation-count
         (count (deref (:pending-ops application))))
        (raise (Invalid_argument message))
        false))))

(defn flush! [application]
  (sig/stabilize! (:runtime-scheduler application))
  (validate-extension-nodes! application)
  (let [operations (deref (:pending-ops application))]
    (if (empty? operations)
      (record-diagnostics! application NoBatch 0 0)
      (let [next-generation (inc (deref (:runtime-generation application)))
            batch
            (record proto/patch-batch
              (generation next-generation)
              (ops operations))]
        (apply-pending-batch!
         application batch (count operations) next-generation)))))

(defn diagnostics [application]
  (deref (:runtime-diagnostics application)))

(defn generation [application]
  (deref (:runtime-generation application)))

(defn mounted-count [application]
  (+
   (count (deref (:mounted-nodes application)))
   (count (deref (:runtime-extension-nodes application)))))

(defn child-count [application node]
  (if-some [children (clojure.core/get
                      (deref (:runtime-children application)) node)]
    (count children)
    (raise (Invalid_argument "unknown parent"))))

(defn children [application node]
  (if-some [children (clojure.core/get
                      (deref (:runtime-children application)) node)]
    children
    (raise (Invalid_argument "unknown parent"))))

(defn- find-dynamic-segment-index [segments segment-id]
  (loop [index 0]
    (if (= index (count segments))
      None
      (if (= segment-id (:dynamic-segment-id (nth segments index)))
        (Some index)
        (recur (inc index))))))

(defn register-dynamic-segment! [application parent]
  (require-node! application parent)
  (let [segment
        (record dynamic-segment
          (dynamic-segment-id
           (swap! (:next-dynamic-segment-id application) inc))
          (dynamic-segment-parent parent)
          (dynamic-segment-base (atom (child-count application parent)))
          (dynamic-segment-size (atom 0))
          (dynamic-segment-active (atom true)))
        current
        (if-some [segments
                  (clojure.core/get
                   (deref (:dynamic-segments application)) parent)]
          segments
          [])]
    (swap! (:dynamic-segments application)
           assoc parent (conj current segment))
    segment))

(defn dynamic-segment-index [segment local-index]
  (when-not (deref (:dynamic-segment-active segment))
    (raise (Invalid_argument "dynamic segment is inactive")))
  (let [size (deref (:dynamic-segment-size segment))]
    (when (or (< local-index 0) (>= local-index size))
      (raise (Invalid_argument "dynamic segment index is out of bounds"))))
  (+ (deref (:dynamic-segment-base segment)) local-index))

(defn dynamic-segment-insert-index [segment local-index]
  (when-not (deref (:dynamic-segment-active segment))
    (raise (Invalid_argument "dynamic segment is inactive")))
  (let [size (deref (:dynamic-segment-size segment))]
    (when (or (< local-index 0) (> local-index size))
      (raise (Invalid_argument "dynamic segment insert index is out of bounds"))))
  (+ (deref (:dynamic-segment-base segment)) local-index))

(defn resize-dynamic-segment! [application segment delta]
  (when-not (deref (:dynamic-segment-active segment))
    (raise (Invalid_argument "dynamic segment is inactive")))
  (let [parent (:dynamic-segment-parent segment)
        segments
        (if-some [registered
                  (clojure.core/get
                   (deref (:dynamic-segments application)) parent)]
          registered
          (raise (Invalid_argument "dynamic segment is not registered")))
        segment-index
        (match (find-dynamic-segment-index
                segments (:dynamic-segment-id segment))
          (Some index) index
          None (raise (Invalid_argument "dynamic segment is not registered")))
        next-size (+ (deref (:dynamic-segment-size segment)) delta)]
    (when (< next-size 0)
      (raise (Invalid_argument "dynamic segment size cannot be negative")))
    (reset! (:dynamic-segment-size segment) next-size)
    (loop [index (inc segment-index)]
      (when (< index (count segments))
        (swap! (:dynamic-segment-base (nth segments index)) + delta)
        (recur (inc index))))
    true))

(defn unregister-dynamic-segment! [application segment]
  (if-not (deref (:dynamic-segment-active segment))
    true
    (do
      (when-not (= 0 (deref (:dynamic-segment-size segment)))
        (raise (Invalid_argument "cannot unregister a non-empty dynamic segment")))
      (let [parent (:dynamic-segment-parent segment)]
        (if-some [segments
                  (clojure.core/get
                   (deref (:dynamic-segments application)) parent)]
          (let [remaining
                (filterv
                 (fn [current]
                   (not (= (:dynamic-segment-id current)
                           (:dynamic-segment-id segment))))
                 segments)]
            (if (empty? remaining)
              (swap! (:dynamic-segments application) dissoc parent)
              (swap! (:dynamic-segments application) assoc parent remaining))
            true)
          true))
      (reset! (:dynamic-segment-active segment) false)
      true)))
