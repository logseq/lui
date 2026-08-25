(ns lui.runtime
  (:require [signal.core :as sig]
            [lui.protocol :as proto]))

(defn- empty-ops [] [])
(defn- empty-handlers [] [])
(defn- empty-dynamic-segments [] (hash-map))

(defn create [scheduler backend]
  (record application
    (runtime-scheduler scheduler)
    (runtime-backend backend)
    (next-node-id (atom 0))
    (mounted-nodes (atom (hash-map)))
    (runtime-properties (atom (hash-map)))
    (runtime-children (atom (hash-map)))
    (runtime-parents (atom (hash-map)))
    (pending-ops (atom (empty-ops)))
    (runtime-generation (atom 0))
    (next-handler-id (atom 0))
    (event-handlers (atom (hash-map)))
    (next-dynamic-segment-id (atom 0))
    (dynamic-segments (atom (empty-dynamic-segments)))))

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

(defn- require-node-kind [application node]
  (if-some [kind (clojure.core/get (deref (:mounted-nodes application)) node)]
    kind
    (raise (Invalid_argument "unknown node"))))

(defn create-node! [application kind]
  (let [node (swap! (:next-node-id application) inc)]
    (swap! (:mounted-nodes application) assoc node kind)
    (swap! (:runtime-properties application) assoc node (hash-map))
    (swap! (:runtime-children application) assoc node [])
    (enqueue! application (proto/create-node-op node kind))
    node))

(defn drop-node! [application node]
  (require-node-kind application node)
  (when (contains? (deref (:runtime-parents application)) node)
    (raise (Invalid_argument "cannot drop an attached node")))
  (when (not (empty? (children application node)))
    (raise (Invalid_argument "cannot drop a node with children")))
  (swap! (:mounted-nodes application) dissoc node)
  (swap! (:runtime-properties application) dissoc node)
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
  (let [kind (require-node-kind application node)]
    (when (not (proto/property-supported? kind property))
      (raise (Invalid_argument "property is unsupported by node kind")))
    (when (not (proto/property-value-supported-for-kind? kind property value))
      (raise (Invalid_argument "invalid property value"))))
  (swap! (:runtime-properties application) update node assoc property value)
  (enqueue! application (proto/set-prop-op node property value)))

(defn insert-child! [application parent child index]
  (let [parent-kind (require-node-kind application parent)
        child-kind (require-node-kind application child)
        children (children application parent)]
    (when (not (proto/can-contain-children? parent-kind))
      (raise (Invalid_argument "parent cannot contain children")))
    (when (not (proto/child-kind-supported? parent-kind child-kind))
      (raise
       (Invalid_argument
        (if (= parent-kind proto/Table)
          "table can contain only table-row"
          "table-row can contain only table-cell"))))
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
  (require-node-kind application parent)
  (require-node-kind application child)
  (let [children (children application parent)]
    (if-some [index (find-child-index children child)]
      (do
        (swap! (:runtime-children application)
               assoc parent (remove-at children index))
        (swap! (:runtime-parents application) dissoc child))
      (raise (Invalid_argument "child is not attached to parent"))))
  (enqueue! application (proto/remove-child-op parent child)))

(defn move-child! [application parent child index]
  (require-node-kind application parent)
  (require-node-kind application child)
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
  (require-node-kind application node)
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
  (let [node (proto/event-node event)
        kind (require-node-kind application node)
        properties
        (if-some [current (clojure.core/get
                           (deref (:runtime-properties application)) node)]
          current
          (hash-map))]
    (when (not (proto/event-supported-for-properties?
                kind properties event))
      (raise (Invalid_argument "event is unsupported by node kind")))
    (if-some [handlers (clojure.core/get
                        (deref (:event-handlers application)) node)]
      (do
        (doseq [handler handlers]
          (sig/enqueue-effect!
           (:runtime-scheduler application)
           (fn [] ((:handler-callback handler) event))))
        true)
      true)))

(defn flush! [application]
  (sig/stabilize! (:runtime-scheduler application))
  (let [operations (deref (:pending-ops application))]
    (if (empty? operations)
      true
      (let [next-generation (inc (deref (:runtime-generation application)))
            batch
            (record proto/patch-batch
              (generation next-generation)
              (ops operations))]
        ((:apply-batch (:runtime-backend application)) batch)
        (reset! (:pending-ops application) (empty-ops))
        (reset! (:runtime-generation application) next-generation)
        true))))

(defn generation [application]
  (deref (:runtime-generation application)))

(defn mounted-count [application]
  (count (deref (:mounted-nodes application))))

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
  (require-node-kind application parent)
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
