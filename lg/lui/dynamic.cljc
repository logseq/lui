(ns lui.dynamic
  (:require [signal.core :as sig :refer [Insert Remove Move]]
            [lui.runtime :as runtime]
            [lui.ui :as ui]))

(defn- make-switch [dispose-callback node-ref]
  (record ui-switch
    (dispose-dynamic-switch dispose-callback)
    (switch-node-ref node-ref)))

(defn- segment-disposer [application segment dispose-reactive]
  (fn []
    (dispose-reactive)
    (runtime/unregister-dynamic-segment! application segment)))

(defn switch! [context parent source equal mount]
  (let [application (:ui-application context)
        segment (runtime/register-dynamic-segment! application parent)
        node-ref (atom None)
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
              application parent node
              (runtime/dynamic-segment-insert-index segment 0))
             (runtime/resize-dynamic-segment! application segment 1)
             (sig/on-unmount!
              branch-scope
              (fn []
                (when (deref (:dynamic-segment-active segment))
                  (runtime/remove-child! application parent node)
                  (runtime/resize-dynamic-segment! application segment -1)
                  (runtime/drop-subtree! application node))
                (reset! node-ref None)
                true))
             branch-scope)))]
    (let [dispose-callback
          (segment-disposer
           application segment
           (fn [] (sig/dispose-switch! switch-value)))]
      (sig/on-dispose! (:ui-scope context) dispose-callback)
      (make-switch dispose-callback node-ref))))

(defn switch-node [switch-value]
  (match (deref (:switch-node-ref switch-value))
    (Some node) node
    None (raise (Invalid_argument "switch has no active node"))))

(defn dispose-switch! [switch-value]
  ((:dispose-dynamic-switch switch-value)))

(defn- make-conditional [dispose-callback node-ref]
  (record ui-conditional
    (dispose-dynamic-conditional dispose-callback)
    (conditional-node-ref node-ref)))

(defn conditional! [context parent source mount]
  (let [application (:ui-application context)
        segment (runtime/register-dynamic-segment! application parent)
        node-ref (atom None)
        switch-value
        (sig/switch
         (:ui-scope context)
         source
         (fn [^:bool left ^:bool right] (= left right))
         (fn [^:bool visible]
           (let [branch-context (ui/child-context context "conditional-branch")
                 branch-scope (:ui-scope branch-context)]
             (when visible
               (let [node (mount branch-context)]
                 (reset! node-ref (Some node))
                 (runtime/insert-child!
                  application parent node
                  (runtime/dynamic-segment-insert-index segment 0))
                 (runtime/resize-dynamic-segment! application segment 1)
                 (sig/on-unmount!
                  branch-scope
                  (fn []
                    (when (deref (:dynamic-segment-active segment))
                      (runtime/remove-child! application parent node)
                      (runtime/resize-dynamic-segment! application segment -1)
                      (runtime/drop-subtree! application node))
                    (reset! node-ref None)
                    true))))
             branch-scope)))]
    (let [dispose-callback
          (segment-disposer
           application segment
           (fn [] (sig/dispose-switch! switch-value)))]
      (sig/on-dispose! (:ui-scope context) dispose-callback)
      (make-conditional dispose-callback node-ref))))

(defn conditional-node [conditional-value]
  (match (deref (:conditional-node-ref conditional-value))
    (Some node) node
    None (raise (Invalid_argument "conditional has no active node"))))

(defn dispose-conditional! [conditional-value]
  ((:dispose-dynamic-conditional conditional-value)))

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
  [context parent segment key-fn compare mount nodes-ref item-source]
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
       (when (deref (:dynamic-segment-active segment))
         (runtime/remove-child!
          (:ui-application context) parent node)
         (runtime/resize-dynamic-segment!
          (:ui-application context) segment -1)
         (runtime/drop-subtree! (:ui-application context) node))
       (remove-key-node! nodes-ref key compare)
       true))
    item-scope))

(defn keyed! [context parent source key-fn compare mount]
  (let [application (:ui-application context)
        segment (runtime/register-dynamic-segment! application parent)
        nodes-ref (atom [])
        keyed-value
        (sig/keyed
         (:ui-scope context)
         source
         key-fn
         compare
         (fn [item-source]
           (mount-keyed-item!
            context parent segment key-fn compare mount nodes-ref item-source))
         (fn [patch]
           (match patch
             (Insert key index)
             (if-some [node (find-key-node
                             (deref nodes-ref) key compare)]
               (do
                 (runtime/insert-child!
                  application parent node
                  (runtime/dynamic-segment-insert-index segment index))
                 (runtime/resize-dynamic-segment! application segment 1))
               (raise (Invalid_argument "missing inserted keyed node")))
             (Remove _key _index) true
             (Move key _from-index to-index)
             (if-some [node (find-key-node
                             (deref nodes-ref) key compare)]
               (runtime/move-child!
                application parent node
                (runtime/dynamic-segment-index segment to-index))
               (raise (Invalid_argument "missing moved keyed node"))))))]
    (let [dispose-callback
          (segment-disposer
           application segment
           (fn [] (sig/dispose-keyed! keyed-value)))]
      (sig/on-dispose! (:ui-scope context) dispose-callback)
      (make-keyed dispose-callback nodes-ref compare))))

(defn keyed-node [keyed-value key]
  (if-some [node (find-key-node
                  (deref (:key-nodes keyed-value)) key
                  (:key-compare keyed-value))]
    node
    (raise (Invalid_argument "keyed node not found"))))

(defn dispose-keyed! [keyed-value]
  ((:dispose-dynamic-keyed keyed-value)))
