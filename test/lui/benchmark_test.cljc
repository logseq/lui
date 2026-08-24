(ns lui.benchmark-test
  (:require [clojure.test :refer [deftest is]]
            [signal.core :as sig]
            [lui.protocol :as proto]
            [lui.runtime :as runtime]
            [lui.ui :as ui]
            [lui.dynamic :as dynamic]
            [lui.backend.apple :as apple]))

(type-record benchmark-item
  (benchmark-key :int)
  (benchmark-label :string))

(defn benchmark-item [key label]
  (record benchmark-item
    (benchmark-key key)
    (benchmark-label label)))

(defmacro assert-equal [expected actual message]
  `(is (= ~expected ~actual) ~message))

(deftest benchmark-1k-text-local-update
  (let [scheduler (sig/scheduler)
        renderer (apple/create)
        application (runtime/create scheduler (apple/backend renderer))
        scope (sig/scope "1k-text")
        context (ui/context application scope)
        root (ui/column! context)
        target-state (sig/state scheduler "before")
        target-value
        (sig/own-signal!
         scope
         (sig/map (fn [value] (proto/StringValue value))
                  (sig/value target-state)))]
    (loop [index 0]
      (when (< index 1000)
        (let [node
              (if (= index 500)
                (ui/text-value! context target-value)
                (ui/text! context (str index)))]
          (ui/append! context root node)
          (recur (inc index)))))
    (runtime/flush! application)
    (let [started (system-time)]
      (sig/set! target-state "after")
      (runtime/flush! application)
      (println "benchmark 1k local text ms"
               (- (system-time) started)))
    (let [batch (nth (apple/batches renderer)
                     (dec (count (apple/batches renderer))))]
      (assert-equal 1 (count (:ops batch))
                    "1k tree updates one retained property"))))

(deftest benchmark-10k-typing-updates
  (let [scheduler (sig/scheduler)
        renderer (apple/create)
        application (runtime/create scheduler (apple/backend renderer))
        scope (sig/scope "10k-typing")
        context (ui/context application scope)
        target-state (sig/state scheduler 0)
        target-value
        (sig/own-signal!
         scope
         (sig/map
          (fn [value] (proto/StringValue (str value)))
          (sig/value target-state)))]
    (loop [index 0]
      (when (< index 10000)
        (if (= index 5000)
          (ui/text-value! context target-value)
          (ui/text! context (str index)))
        (recur (inc index))))
    (runtime/flush! application)
    (let [started (system-time)]
      (loop [update 1]
        (when (<= update 60)
          (sig/set! target-state update)
          (runtime/flush! application)
          (recur (inc update))))
      (println "benchmark 10k nodes 60 updates ms"
               (- (system-time) started)))
    (assert-equal 61 (count (apple/batches renderer))
                  "typing workload emits one initial and 60 local batches")
    (let [batch (nth (apple/batches renderer) 60)]
      (assert-equal 1 (count (:ops batch))
                    "10k-node typing update remains one patch"))))

(deftest benchmark-keyed-1k-reorder-and-middle-edit
  (let [scheduler (sig/scheduler)
        renderer (apple/create)
        application (runtime/create scheduler (apple/backend renderer))
        scope (sig/scope "1k-keyed")
        context (ui/context application scope)
        initial
        (loop [index 0
               result []]
          (if (= index 1000)
            result
            (recur (inc index)
                   (conj result (benchmark-item index (str index))))))
        items (sig/state scheduler initial)
        root (ui/column! context)
        keyed
        (dynamic/keyed!
         context root (sig/value items) :benchmark-key compare
         (fn [item-context item-source]
           (ui/text! item-context
                     (:benchmark-label (sig/sample item-source)))))]
    (runtime/flush! application)
    (let [last-node (dynamic/keyed-node keyed 999)
          reordered (into [(nth initial 999)] (subvec initial 0 999))
          started (system-time)]
      (sig/set! items reordered)
      (runtime/flush! application)
      (println "benchmark keyed 1k reorder ms"
               (- (system-time) started))
      (assert-equal last-node (nth (apple/children renderer root) 0)
                    "1k reorder preserves moved node identity")
      (let [batch (nth (apple/batches renderer)
                       (dec (count (apple/batches renderer))))]
        (assert-equal 1 (count (:ops batch))
                      "1k rotation emits one MoveChild"))
      (let [edited
            (into
             (conj (subvec reordered 0 500)
                   (benchmark-item 1001 "new"))
             (subvec reordered 501 1000))
            started-edit (system-time)]
        (sig/set! items edited)
        (runtime/flush! application)
        (println "benchmark keyed middle edit ms"
                 (- (system-time) started-edit))
        (let [batch (nth (apple/batches renderer)
                         (dec (count (apple/batches renderer))))]
          (assert-equal 5 (count (:ops batch))
                        "middle replacement emits only local structural ops"))))))

(deftest benchmark-scroll-background-update
  (let [scheduler (sig/scheduler)
        renderer (apple/create)
        application (runtime/create scheduler (apple/backend renderer))
        scope (sig/scope "scroll")
        context (ui/context application scope)
        color (sig/state scheduler "white")
        color-value
        (sig/own-signal!
         scope
         (sig/map (fn [value] (proto/StringValue value))
                  (sig/value color)))
        scroll (ui/scroll! context)
        content (ui/column! context)]
    (ui/append! context scroll content)
    (runtime/bind-prop!
     scope application scroll proto/BackgroundValue color-value)
    (runtime/flush! application)
    (let [children-before (apple/children renderer scroll)
          started (system-time)]
      (sig/set! color "black")
      (runtime/flush! application)
      (println "benchmark scroll background ms"
               (- (system-time) started))
      (assert-equal children-before (apple/children renderer scroll)
                    "background update preserves scroll children")
      (let [batch (nth (apple/batches renderer)
                       (dec (count (apple/batches renderer))))]
        (assert-equal 1 (count (:ops batch))
                      "scroll background update emits one SetProp")))))
