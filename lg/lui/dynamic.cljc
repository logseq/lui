(ns lui.dynamic
  (:require [signal.core :as sig :refer [Insert Remove Move]]
            [lui.runtime :as runtime]
            [lui.ui :as ui]))

(defn- make-switch [dispose-callback node-ref]
  (record ui-switch
    (dispose-dynamic-switch dispose-callback)
    (switch-node-ref node-ref)))

(defn switch! [context parent source equal mount]
  (let [node-ref (atom None)
        switch-value
        (sig/switch
         (:ui-scope context)
         source
         equal
         (fn [key]
           (let [branch-context (ui/child-context context "switch-branch")
                 branch-scope (:ui-scope branch-context)
                 node (mount branch-context key)]
             (reset! node-ref (Some node))
             (runtime/insert-child!
              (:ui-application context) parent node 0)
             (sig/on-unmount!
              branch-scope
              (fn []
                (runtime/remove-child!
                 (:ui-application context) parent node)
                (runtime/drop-subtree! (:ui-application context) node)
                (reset! node-ref None)
                true))
             branch-scope)))]
    (make-switch
     (fn [] (sig/dispose-switch! switch-value))
     node-ref)))

(defn switch-node [switch-value]
  (match (deref (:switch-node-ref switch-value))
    (Some node) node
    None (raise (Invalid_argument "switch has no active node"))))

(defn dispose-switch! [switch-value]
  ((:dispose-dynamic-switch switch-value)))

(defn- find-key-node [nodes key compare]
  (loop [index 0]
    (if (= index (count nodes))
      None
      (let [entry (nth nodes index)]
        (if (= 0 (compare (:ui-key entry) key))
          (Some (:ui-node entry))
          (recur (inc index)))))))

(defn- remove-key-node! [nodes-ref key compare]
  (swap!
   nodes-ref
   (fn [nodes]
     (filterv
      (fn [entry]
        (not (= 0 (compare (:ui-key entry) key))))
      nodes)))
  true)

(defn- make-keyed [dispose-callback nodes-ref compare]
  (record ui-keyed
    (dispose-dynamic-keyed dispose-callback)
    (key-nodes nodes-ref)
    (key-compare compare)))

(defn- mount-keyed-item!
  [context parent key-fn compare mount nodes-ref item-source]
  (let [current (sig/sample item-source)
        key (key-fn current)
        item-context (ui/child-context context "keyed-item")
        item-scope (:ui-scope item-context)
        node (mount item-context item-source)
        entry
        (record ui-key-node
          (ui-key key)
          (ui-node node))]
    (swap! nodes-ref conj entry)
    (sig/on-unmount!
     item-scope
     (fn []
       (runtime/remove-child!
        (:ui-application context) parent node)
       (runtime/drop-subtree! (:ui-application context) node)
       (remove-key-node! nodes-ref key compare)
       true))
    item-scope))

(defn keyed! [context parent source key-fn compare mount]
  (let [nodes-ref (atom [])
        keyed-value
        (sig/keyed
         (:ui-scope context)
         source
         key-fn
         compare
         (fn [item-source]
           (mount-keyed-item!
            context parent key-fn compare mount nodes-ref item-source))
         (fn [patch]
           (match patch
             (Insert key index)
             (if-some [node (find-key-node
                             (deref nodes-ref) key compare)]
               (runtime/insert-child!
                (:ui-application context) parent node index)
               (raise (Invalid_argument "missing inserted keyed node")))
             (Remove _key _index) true
             (Move key _from-index to-index)
             (if-some [node (find-key-node
                             (deref nodes-ref) key compare)]
               (runtime/move-child!
                (:ui-application context) parent node to-index)
               (raise (Invalid_argument "missing moved keyed node"))))))]
    (make-keyed
     (fn [] (sig/dispose-keyed! keyed-value))
     nodes-ref compare)))

(defn keyed-node [keyed-value key]
  (if-some [node (find-key-node
                  (deref (:key-nodes keyed-value)) key
                  (:key-compare keyed-value))]
    node
    (raise (Invalid_argument "keyed node not found"))))

(defn dispose-keyed! [keyed-value]
  ((:dispose-dynamic-keyed keyed-value)))
