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
    (dynamic-segments (atom (empty-dynamic-segments)))
    (runtime-reload-keys (atom (hash-map)))
    (runtime-node-aliases (atom (hash-map)))))

(defn create [scheduler backend]
  (create-with-extensions scheduler backend (ext/registry)))

(defn checkpoint [application]
  (record runtime-checkpoint
    (checkpoint-generation (deref (:runtime-generation application)))
    (checkpoint-next-node-id (deref (:next-node-id application)))
    (checkpoint-mounted-nodes (deref (:mounted-nodes application)))
    (checkpoint-extension-nodes
     (deref (:runtime-extension-nodes application)))
    (checkpoint-properties (deref (:runtime-properties application)))
    (checkpoint-extension-properties
     (deref (:runtime-extension-properties application)))
    (checkpoint-children (deref (:runtime-children application)))
    (checkpoint-parents (deref (:runtime-parents application)))
    (checkpoint-pending-ops (deref (:pending-ops application)))
    (checkpoint-next-handler-id (deref (:next-handler-id application)))
    (checkpoint-event-handlers (deref (:event-handlers application)))
    (checkpoint-next-dynamic-segment-id
     (deref (:next-dynamic-segment-id application)))
    (checkpoint-dynamic-segments (deref (:dynamic-segments application)))
    (checkpoint-reload-keys (deref (:runtime-reload-keys application)))
    (checkpoint-node-aliases (deref (:runtime-node-aliases application)))))

(defn render-tree-snapshot [application]
  (record render-tree-snapshot
    (render-mounted-nodes (deref (:mounted-nodes application)))
    (render-extension-nodes (deref (:runtime-extension-nodes application)))
    (render-properties (deref (:runtime-properties application)))
    (render-extension-properties
     (deref (:runtime-extension-properties application)))
    (render-children (deref (:runtime-children application)))
    (render-reload-keys (deref (:runtime-reload-keys application)))))

(defn restore! [application saved]
  (when-not (= (deref (:runtime-generation application))
               (:checkpoint-generation saved))
    (raise (Invalid_argument "cannot restore a stale runtime checkpoint")))
  (reset! (:next-node-id application) (:checkpoint-next-node-id saved))
  (reset! (:mounted-nodes application) (:checkpoint-mounted-nodes saved))
  (reset! (:runtime-extension-nodes application)
          (:checkpoint-extension-nodes saved))
  (reset! (:runtime-properties application) (:checkpoint-properties saved))
  (reset! (:runtime-extension-properties application)
          (:checkpoint-extension-properties saved))
  (reset! (:runtime-children application) (:checkpoint-children saved))
  (reset! (:runtime-parents application) (:checkpoint-parents saved))
  (reset! (:pending-ops application) (:checkpoint-pending-ops saved))
  (reset! (:next-handler-id application) (:checkpoint-next-handler-id saved))
  (reset! (:event-handlers application) (:checkpoint-event-handlers saved))
  (reset! (:next-dynamic-segment-id application)
          (:checkpoint-next-dynamic-segment-id saved))
  (reset! (:dynamic-segments application) (:checkpoint-dynamic-segments saved))
  (reset! (:runtime-reload-keys application) (:checkpoint-reload-keys saved))
  (reset! (:runtime-node-aliases application) (:checkpoint-node-aliases saved))
  true)

(defn- canonical-node [application node]
  (if-some [canonical
            (clojure.core/get (deref (:runtime-node-aliases application)) node)]
    canonical
    node))

(defn- map-node [mapping node]
  (if-some [mapped (clojure.core/get mapping node)]
    mapped
    node))

(defn- node-compatible? [application saved old-node candidate-node]
  (if-some [old-kind
            (clojure.core/get
             (:checkpoint-mounted-nodes saved) old-node)]
    (if-some [candidate-kind
              (clojure.core/get
               (deref (:mounted-nodes application)) candidate-node)]
      (= old-kind candidate-kind)
      false)
    (if-some [old-identifier
              (clojure.core/get
               (:checkpoint-extension-nodes saved) old-node)]
      (if-some [candidate-identifier
                (clojure.core/get
                 (deref (:runtime-extension-nodes application)) candidate-node)]
        (= old-identifier candidate-identifier)
        false)
      false)))

(defn- find-child-by-reload-key [children reload-keys key]
  (loop [index 0
         found None]
    (if (= index (count children))
      found
      (let [child (nth children index)]
        (if (= (clojure.core/get reload-keys child) (Some key))
          (if-some [_existing found]
            (raise (Invalid_argument "duplicate reload key among siblings"))
            (recur (inc index) (Some child)))
          (recur (inc index) found))))))

(defn- collect-node-mapping
  [application saved old-node candidate-node mapping]
  (if-not (node-compatible? application saved old-node candidate-node)
    mapping
    (let [mapping (assoc mapping candidate-node old-node)
          old-children
          (if-some [children
                    (clojure.core/get
                     (:checkpoint-children saved) old-node)]
            children
            [])
          candidate-children
          (if-some [children
                    (clojure.core/get
                     (deref (:runtime-children application)) candidate-node)]
            children
            [])
          old-reload-keys (:checkpoint-reload-keys saved)
          candidate-reload-keys (deref (:runtime-reload-keys application))]
      (loop [index 0
             current mapping]
        (if (= index (count candidate-children))
          current
          (let [candidate-child (nth candidate-children index)
                old-child
                (if-some [key
                          (clojure.core/get
                           candidate-reload-keys candidate-child)]
                  (let [_candidate-match
                        (find-child-by-reload-key
                         candidate-children candidate-reload-keys key)]
                    (find-child-by-reload-key
                     old-children old-reload-keys key))
                  (if (< index (count old-children))
                    (let [position-child (nth old-children index)]
                      (if (contains? old-reload-keys position-child)
                        None
                        (Some position-child)))
                    None))]
            (recur
             (inc index)
             (match old-child
               (Some matched)
               (collect-node-mapping
                application saved matched candidate-child current)
               None current))))))))

(defn- collect-subtree-nodes [children-map root]
  (let [children
        (if-some [current (clojure.core/get children-map root)]
          current
          [])]
    (reduce
     (fn [nodes child]
       (into nodes (collect-subtree-nodes children-map child)))
     [root]
     children)))

(defn retire-checkpoint-dynamic-segments! [saved root]
  (doseq [node
          (collect-subtree-nodes (:checkpoint-children saved) root)]
    (if-some [segments
              (clojure.core/get
               (:checkpoint-dynamic-segments saved) node)]
      (doseq [segment segments]
        (reset! (:dynamic-segment-active segment) false))
      true))
  true)

(defn- remove-node-keys [values nodes]
  (reduce (fn [current node] (dissoc current node)) values nodes))

(defn- remap-node-values [source candidate-nodes mapping base]
  (reduce
   (fn [result candidate]
     (if-some [value (clojure.core/get source candidate)]
       (assoc result (map-node mapping candidate) value)
       result))
   base
   candidate-nodes))

(defn- remap-children [source candidate-nodes mapping base]
  (reduce
   (fn [result candidate]
     (let [children
           (if-some [current (clojure.core/get source candidate)]
             current
             [])]
       (assoc
        result (map-node mapping candidate)
        (mapv (fn [child] (map-node mapping child)) children))))
   base
   candidate-nodes))

(defn- rebuild-parents [children-map]
  (reduce-kv
   (fn [parents parent children]
     (reduce (fn [current child] (assoc current child parent)) parents children))
   (hash-map)
   children-map))

(defn- vector-contains? [values target]
  (match (find-child-index values target)
    (Some _index) true
    None false))

(defn- emit-child-diff! [application parent old-children desired-children]
  (let [after-removals
        (reduce
         (fn [current child]
           (if (vector-contains? desired-children child)
             current
             (do
               (enqueue! application (proto/remove-child-op parent child))
               (match (find-child-index current child)
                 (Some index) (remove-at current index)
                 None current))))
         old-children
         old-children)]
    (loop [index 0
           current after-removals]
      (if (= index (count desired-children))
        true
        (let [child (nth desired-children index)]
          (if (and (< index (count current)) (= child (nth current index)))
            (recur (inc index) current)
            (if-some [from-index (find-child-index current child)]
              (do
                (enqueue!
                 application (proto/move-child-op parent child index))
                (recur (inc index) (move-at current from-index index)))
              (do
                (enqueue!
                 application (proto/insert-child-op parent child index))
                (recur (inc index) (insert-at current index child))))))))))

(defn- emit-property-diff! [application node old-values desired-values]
  (reduce-kv
   (fn [_ property _value]
     (when-not (contains? desired-values property)
       (enqueue! application (proto/remove-prop-op node property)))
     true)
   true
   old-values)
  (reduce-kv
   (fn [_ property value]
     (when-not (= (clojure.core/get old-values property) (Some value))
       (enqueue! application (proto/set-prop-op node property value)))
     true)
   true
   desired-values))

(defn- emit-extension-property-diff!
  [application node old-values desired-values]
  (reduce-kv
   (fn [_ property _value]
     (when-not (contains? desired-values property)
       (enqueue!
        application (proto/remove-extension-prop-op node property)))
     true)
   true
   old-values)
  (reduce-kv
   (fn [_ property value]
     (when-not (= (clojure.core/get old-values property) (Some value))
       (enqueue!
        application (proto/set-extension-prop-op node property value)))
     true)
   true
   desired-values))

(defn- emit-dropped-subtree! [application saved removed-nodes node]
  (let [children
        (if-some [current
                  (clojure.core/get (:checkpoint-children saved) node)]
          current
          [])]
    (doseq [child children]
      (when (vector-contains? removed-nodes child)
        (enqueue! application (proto/remove-child-op node child))
        (emit-dropped-subtree! application saved removed-nodes child)))
    (enqueue! application (proto/drop-node-op node))))

(defn reconcile-subtree!
  [application saved parent old-root candidate-root]
  (let [parent (canonical-node application parent)
        old-root (canonical-node application old-root)
        current-children (deref (:runtime-children application))
        old-nodes (collect-subtree-nodes (:checkpoint-children saved) old-root)
        candidate-nodes (collect-subtree-nodes current-children candidate-root)
        mapping
        (collect-node-mapping
         application saved old-root candidate-root (hash-map))
        desired-root (map-node mapping candidate-root)
        desired-node-set
        (reduce
         (fn [nodes candidate]
           (assoc nodes (map-node mapping candidate) true))
         (hash-map)
         candidate-nodes)
        removed-nodes
        (filterv
         (fn [node] (not (contains? desired-node-set node)))
         old-nodes)
        base-standard
        (remove-node-keys (:checkpoint-mounted-nodes saved) old-nodes)
        base-extensions
        (remove-node-keys (:checkpoint-extension-nodes saved) old-nodes)
        base-properties
        (remove-node-keys (:checkpoint-properties saved) old-nodes)
        base-extension-properties
        (remove-node-keys (:checkpoint-extension-properties saved) old-nodes)
        base-reload-keys
        (remove-node-keys (:checkpoint-reload-keys saved) old-nodes)
        base-children
        (remove-node-keys (:checkpoint-children saved) old-nodes)
        desired-standard
        (remap-node-values
         (deref (:mounted-nodes application)) candidate-nodes mapping
         base-standard)
        desired-extensions
        (remap-node-values
         (deref (:runtime-extension-nodes application)) candidate-nodes mapping
         base-extensions)
        desired-properties
        (remap-node-values
         (deref (:runtime-properties application)) candidate-nodes mapping
         base-properties)
        desired-extension-properties
        (remap-node-values
         (deref (:runtime-extension-properties application))
         candidate-nodes mapping base-extension-properties)
        desired-reload-keys
        (remap-node-values
         (deref (:runtime-reload-keys application))
         candidate-nodes mapping base-reload-keys)
        desired-children
        (assoc
         (remap-children current-children candidate-nodes mapping base-children)
         parent [desired-root])
        desired-handlers
        (remap-node-values
         (deref (:event-handlers application)) candidate-nodes mapping
         (remove-node-keys (:checkpoint-event-handlers saved) old-nodes))
        desired-segments
        (remap-node-values
         (deref (:dynamic-segments application)) candidate-nodes mapping
         (remove-node-keys (:checkpoint-dynamic-segments saved) old-nodes))]
    (when (= (clojure.core/get
              (deref (:mounted-nodes application)) candidate-root)
             (Some proto/Root))
      (raise (Invalid_argument "runtime root cannot be nested")))
    (reset! (:pending-ops application) (:checkpoint-pending-ops saved))
    (doseq [candidate candidate-nodes]
      (when (= candidate (map-node mapping candidate))
        (if-some [kind (clojure.core/get desired-standard candidate)]
          (enqueue! application (proto/create-node-op candidate kind))
          (if-some [identifier
                    (clojure.core/get desired-extensions candidate)]
            (let [schema
                  (match (ext/schema
                          (:runtime-extension-registry application) identifier)
                    (Some current) current
                    None (raise (Invalid_argument "unknown extension schema")))
                  fingerprint
                  (if (ext/tweak?
                       (:runtime-extension-registry application) identifier)
                    (ext/tweak-fingerprint schema)
                    (ext/fingerprint schema))]
              (enqueue!
               application
               (proto/create-extension-op candidate identifier fingerprint)))
            true))))
    (doseq [candidate candidate-nodes]
      (let [node (map-node mapping candidate)]
        (if-some [values (clojure.core/get desired-properties node)]
          (emit-property-diff!
           application node
           (if-some [old-values
                     (clojure.core/get (:checkpoint-properties saved) node)]
             old-values
             (hash-map))
           values)
          (if-some [values
                    (clojure.core/get desired-extension-properties node)]
            (emit-extension-property-diff!
             application node
             (if-some [old-values
                       (clojure.core/get
                        (:checkpoint-extension-properties saved) node)]
               old-values
               (hash-map))
             values)
            true))))
    (doseq [node (conj (mapv (fn [candidate] (map-node mapping candidate))
                              candidate-nodes)
                        parent)]
      (emit-child-diff!
       application node
       (if-some [children
                 (clojure.core/get (:checkpoint-children saved) node)]
         children
         [])
       (if-some [children (clojure.core/get desired-children node)]
         children
         [])))
    (doseq [node removed-nodes]
      (if-some [old-parent
                (clojure.core/get (:checkpoint-parents saved) node)]
        (when-not (vector-contains? removed-nodes old-parent)
          (emit-dropped-subtree! application saved removed-nodes node))
        (emit-dropped-subtree! application saved removed-nodes node)))
    (reset! (:mounted-nodes application) desired-standard)
    (reset! (:runtime-extension-nodes application) desired-extensions)
    (reset! (:runtime-properties application) desired-properties)
    (reset! (:runtime-extension-properties application)
            desired-extension-properties)
    (reset! (:runtime-children application) desired-children)
    (reset! (:runtime-parents application) (rebuild-parents desired-children))
    (reset! (:event-handlers application) desired-handlers)
    (reset! (:dynamic-segments application) desired-segments)
    (reset! (:runtime-reload-keys application) desired-reload-keys)
    (reset!
     (:runtime-node-aliases application)
     (reduce-kv
      (fn [aliases candidate node]
        (if (= candidate node) aliases (assoc aliases candidate node)))
      (hash-map)
      mapping))
    desired-root))

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
  (if-some [kind (clojure.core/get
                  (deref (:mounted-nodes application))
                  (canonical-node application node))]
    kind
    (raise (Invalid_argument "unknown node"))))

(defn- extension-identifier [application node]
  (clojure.core/get
   (deref (:runtime-extension-nodes application))
   (canonical-node application node)))

(defn- require-extension-schema [application node]
  (if-some [identifier (extension-identifier application node)]
    (match (ext/schema (:runtime-extension-registry application) identifier)
      (Some schema) schema
      None (raise (Invalid_argument "unknown extension schema")))
    (raise (Invalid_argument "unknown extension node"))))

(defn- require-node! [application node]
  (let [node (canonical-node application node)]
    (when-not
     (or
      (contains? (deref (:mounted-nodes application)) node)
      (contains? (deref (:runtime-extension-nodes application)) node))
     (raise (Invalid_argument "unknown node")))
    true))

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

(defn set-reload-key! [application node key]
  (let [node (canonical-node application node)]
    (require-node! application node)
    (swap! (:runtime-reload-keys application) assoc node key)
    true))

(defn drop-node! [application node]
  (let [node (canonical-node application node)]
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
  (swap! (:runtime-reload-keys application) dissoc node)
  (enqueue! application (proto/drop-node-op node))))

(defn drop-subtree! [application node]
  (let [node (canonical-node application node)]
  (if-some [children (clojure.core/get
                      (deref (:runtime-children application)) node)]
    (do
      (doseq [child children]
        (remove-child! application node child)
        (drop-subtree! application child))
      (drop-node! application node))
    (drop-node! application node))))

(defn set-prop! [application node property value]
  (let [node (canonical-node application node)
        kind (require-standard-node-kind application node)]
    (when (not (proto/property-supported? kind property))
      (raise (Invalid_argument "property is unsupported by node kind")))
    (when (not (proto/property-value-supported-for-kind? kind property value))
      (raise (Invalid_argument "invalid property value")))
    (swap! (:runtime-properties application) update node assoc property value)
    (enqueue! application (proto/set-prop-op node property value))))

(defn remove-prop! [application node property]
  (let [node (canonical-node application node)
        kind (require-standard-node-kind application node)]
    (when-not (proto/property-supported? kind property)
      (raise (Invalid_argument "property is unsupported by node kind")))
    (let [properties (:runtime-properties application)
          current
          (if-some [values (clojure.core/get (deref properties) node)]
            values
            (hash-map))]
      (swap! properties assoc node (dissoc current property)))
    (enqueue! application (proto/remove-prop-op node property))))

(defn set-extension-prop! [application node property value]
  (let [node (canonical-node application node)
        schema (require-extension-schema application node)]
    (when-not (ext/property-value-supported? schema property value)
      (raise (Invalid_argument "invalid extension property value")))
    (let [properties (:runtime-extension-properties application)
          current
          (if-some [values (clojure.core/get (deref properties) node)]
            values
            (hash-map))]
      (swap! properties assoc node (assoc current property value)))
    (enqueue! application (proto/set-extension-prop-op node property value))))

(defn remove-extension-prop! [application node property]
  (let [node (canonical-node application node)
        schema (require-extension-schema application node)]
    (when-not (ext/property-supported? schema property)
      (raise (Invalid_argument "unknown extension property")))
    (let [properties (:runtime-extension-properties application)
          current
          (if-some [values (clojure.core/get (deref properties) node)]
            values
            (hash-map))]
      (swap! properties assoc node (dissoc current property)))
    (enqueue! application (proto/remove-extension-prop-op node property))))

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
        (if (= child-kind proto/Root)
          false
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
              false)))
        false))))

(defn insert-child! [application parent child index]
  (let [parent (canonical-node application parent)
        child (canonical-node application child)]
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
                (= child-kind proto/Root) "runtime root cannot be nested"
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
  (enqueue! application (proto/insert-child-op parent child index))))

(defn remove-child! [application parent child]
  (let [parent (canonical-node application parent)
        child (canonical-node application child)]
  (require-node! application parent)
  (require-node! application child)
  (let [children (children application parent)]
    (if-some [index (find-child-index children child)]
      (do
        (swap! (:runtime-children application)
               assoc parent (remove-at children index))
        (swap! (:runtime-parents application) dissoc child))
      (raise (Invalid_argument "child is not attached to parent"))))
  (enqueue! application (proto/remove-child-op parent child))))

(defn move-child! [application parent child index]
  (let [parent (canonical-node application parent)
        child (canonical-node application child)]
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
  (enqueue! application (proto/move-child-op parent child index))))

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
  (let [node (canonical-node application node)]
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
    true)))

(defn on-event! [scope application node callback]
  (let [node (canonical-node application node)]
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
    true)))

(defn dispatch! [application event]
  (let [node (canonical-node application (proto/event-node event))]
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
                      (deref (:runtime-children application))
                      (canonical-node application node))]
    (count children)
    (raise (Invalid_argument "unknown parent"))))

(defn children [application node]
  (if-some [children (clojure.core/get
                      (deref (:runtime-children application))
                      (canonical-node application node))]
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
  (let [parent (canonical-node application parent)]
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
    segment)))

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
  (let [parent
        (canonical-node application (:dynamic-segment-parent segment))
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
      (let [parent
            (canonical-node application (:dynamic-segment-parent segment))]
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
