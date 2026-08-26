(ns lui.resources)

(defn create [invalidate-dependents retire]
  (record resource-session
          (resource-values (atom (hash-map)))
          (resource-dependencies (atom (hash-map)))
          (resource-completed-generation (atom 0))
          (invalidate-resource-dependents invalidate-dependents)
          (retire-resource retire)))

(defn- contains-node? [nodes node]
  (loop [index 0]
    (if (= index (count nodes))
      false
      (if (= (nth nodes index) node)
        true
        (recur (inc index))))))

(defn register-dependency! [session resource-id node]
  (let [dependencies (:resource-dependencies session)
        current
        (if-some [nodes (clojure.core/get (deref dependencies) resource-id)]
          nodes
          [])]
    (when-not (contains-node? current node)
      (swap! dependencies assoc resource-id (conj current node)))
    true))

(defn current [session resource-id]
  (if-some [resource
            (clojure.core/get (deref (:resource-values session)) resource-id)]
    (Some (:committed-resource-value resource))
    None))

(defn- reject! [session generation message]
  (reset! (:resource-completed-generation session) generation)
  (ResourceRejected generation message))

(defn reload! [session generation resource-id source-hash payload prepare]
  (let [completed (deref (:resource-completed-generation session))
        values (:resource-values session)
        previous (clojure.core/get (deref values) resource-id)]
    (cond
      (<= generation completed) (ResourceStale generation)
      (match previous
        (Some resource) (= source-hash (:committed-resource-hash resource))
        None false)
      (do
        (reset! (:resource-completed-generation session) generation)
        (ResourceUnchanged generation))
      :else
      (let [prepared
            (try
              (ResourcePrepared (prepare payload))
              (catch (Invalid_argument message)
                     (ResourcePrepareRejected message)))]
        (match prepared
          (ResourcePrepareRejected message)
          (reject! session generation message)
          (ResourcePrepared candidate)
          (let [committed
                (record committed-resource
                        (committed-resource-hash source-hash)
                        (committed-resource-value candidate)
                        (committed-resource-generation generation))
                dependents
                (if-some [nodes
                          (clojure.core/get
                           (deref (:resource-dependencies session)) resource-id)]
                  nodes
                  [])]
            (reset! values (assoc (deref values) resource-id committed))
            (let [invalidation
                  (try
                    (do
                      ((:invalidate-resource-dependents session) dependents)
                      ResourceInvalidated)
                    (catch (Invalid_argument message)
                           (ResourceInvalidationRejected message)))]
              (match invalidation
                (ResourceInvalidationRejected message)
                (do
                  (match previous
                    (Some old)
                    (reset! values (assoc (deref values) resource-id old))
                    None (reset! values (dissoc (deref values) resource-id)))
                  ((:retire-resource session) candidate)
                  (reject! session generation message))
                ResourceInvalidated
                (do
                  (match previous
                    (Some old)
                    ((:retire-resource session)
                     (:committed-resource-value old))
                    None true)
                  (reset! (:resource-completed-generation session) generation)
                  (ResourceApplied generation))))))))))
