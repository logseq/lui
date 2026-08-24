(ns lui.backend.retained
  (:require [lui.protocol :as proto
             :refer [CreateNode DropNode SetProp InsertChild RemoveChild
                     MoveChild]]))

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
      (if (proto/property-supported? (:semantic-kind current) property)
        (update-node
         nodes node current
         (assoc (:retained-properties current) property value)
         (:retained-children current))
        (raise (Invalid_argument "property is unsupported by node kind")))
      (raise (Invalid_argument "unknown node")))

    (InsertChild parent child index)
    (if-some [parent-node (clojure.core/get nodes parent)]
      (if-some [child-node (clojure.core/get nodes child)]
        (cond
          (not (proto/can-contain-children? (:semantic-kind parent-node)))
          (raise (Invalid_argument "parent cannot contain children"))
          (and (proto/single-child-container? (:semantic-kind parent-node))
               (not (empty? (:retained-children parent-node))))
          (raise (Invalid_argument "parent can contain only one child"))
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

(defn- apply-operations [nodes platform-for batch]
  (loop [index 0
         current-nodes nodes]
    (if (= index (count (:ops batch)))
      current-nodes
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
