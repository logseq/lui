(ns lui.runtime
  (:require [signal.core :as sig]
            [lui.protocol :as proto
             :refer [LabelledBy DescribedBy ErrorMessageBy IntValue]]))

(defn- empty-ops [] [])
(defn- empty-handlers [] [])

(defn create [scheduler backend]
  (record application
    (runtime-scheduler scheduler)
    (runtime-backend backend)
    (next-node-id (atom 0))
    (mounted-nodes (atom (hash-map)))
    (runtime-children (atom (hash-map)))
    (runtime-parents (atom (hash-map)))
    (pending-ops (atom (empty-ops)))
    (runtime-generation (atom 0))
    (next-handler-id (atom 0))
    (event-handlers (atom (hash-map)))))

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
    (when (not (proto/property-value-supported? property value))
      (raise (Invalid_argument "invalid property value")))
    (match (tuple property value)
      (tuple LabelledBy (IntValue target))
      (when (not (= (require-node-kind application target) proto/Label))
        (raise (Invalid_argument "labelled-by must reference a label")))
      (tuple DescribedBy (IntValue target))
      (let [target-kind (require-node-kind application target)]
        (when (not (or (= target-kind proto/Text)
                       (= target-kind proto/Paragraph)))
          (raise (Invalid_argument
                  "described-by must reference text content"))))
      (tuple ErrorMessageBy (IntValue target))
      (let [target-kind (require-node-kind application target)]
        (when (not (or (= target-kind proto/Text)
                       (= target-kind proto/Paragraph)))
          (raise (Invalid_argument
                  "error-message-by must reference text content"))))
      _ true))
  (enqueue! application (proto/set-prop-op node property value)))

(defn insert-child! [application parent child index]
  (let [parent-kind (require-node-kind application parent)
        _child-kind (require-node-kind application child)
        children (children application parent)]
    (when (not (proto/can-contain-children? parent-kind))
      (raise (Invalid_argument "parent cannot contain children")))
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
        kind (require-node-kind application node)]
    (when (not (proto/event-supported? kind event))
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
