(ns lui.runtime
  (:require [signal.core :as sig]
            [lui.protocol :as proto]))

(defn- empty-ops [] [])
(defn- empty-handlers [] [])

(defn create [scheduler backend]
  (record application
    (runtime-scheduler scheduler)
    (runtime-backend backend)
    (next-node-id (atom 0))
    (mounted-nodes (atom (hash-map)))
    (runtime-children (atom (hash-map)))
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

(defn create-node! [application kind]
  (let [node (swap! (:next-node-id application) inc)]
    (swap! (:mounted-nodes application) assoc node kind)
    (swap! (:runtime-children application) assoc node [])
    (enqueue! application (proto/create-node-op node kind))
    node))

(defn drop-node! [application node]
  (swap! (:mounted-nodes application) dissoc node)
  (swap! (:runtime-children application) dissoc node)
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
  (enqueue! application (proto/set-prop-op node property value)))

(defn insert-child! [application parent child index]
  (if-some [children (clojure.core/get
                      (deref (:runtime-children application)) parent)]
    (do
      (when (and (contains? (deref (:mounted-nodes application)) child)
                 (<= 0 index)
                 (<= index (count children)))
        (swap! (:runtime-children application)
               assoc parent (insert-at children index child)))
      true)
    true)
  (enqueue! application (proto/insert-child-op parent child index)))

(defn remove-child! [application parent child]
  (if-some [children (clojure.core/get
                      (deref (:runtime-children application)) parent)]
    (if-some [index (find-child-index children child)]
      (do
        (swap! (:runtime-children application)
               assoc parent (remove-at children index))
        true)
      true)
    true)
  (enqueue! application (proto/remove-child-op parent child)))

(defn move-child! [application parent child index]
  (if-some [children (clojure.core/get
                      (deref (:runtime-children application)) parent)]
    (if-some [current-index (find-child-index children child)]
      (do
        (when (and (<= 0 index) (< index (count children)))
          (swap! (:runtime-children application)
                 assoc parent (move-at children current-index index)))
        true)
      true)
    true)
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
