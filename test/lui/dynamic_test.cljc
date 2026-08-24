(ns lui.dynamic-test
  (:require [clojure.test :refer [deftest is]]
            [signal.core :as sig]
            [lui.protocol :as proto :refer [StringValue]]
            [lui.runtime :as runtime]
            [lui.ui :as ui]
            [lui.dynamic :as dynamic]
            [lui.backend.apple :as apple]))

(type-record dynamic-item
  (item-key :string)
  (item-value :int))

(defn item [key value]
  (record dynamic-item
    (item-key key)
    (item-value value)))

(defmacro assert-equal [expected actual message]
  `(is (= ~expected ~actual) ~message))

(deftest switch-replaces-only-its-local-subtree
  (let [scheduler (sig/scheduler)
        renderer (apple/create)
        application (runtime/create scheduler (apple/backend renderer))
        scope (sig/scope "screen")
        context (ui/context application scope)
        selected (sig/state scheduler false)
        root (ui/column! context)
        switch
        (dynamic/switch!
         context root (sig/value selected)
         (fn [^:bool left ^:bool right] (= left right))
         (fn [branch-context ^:bool key]
           (let [container (ui/row! branch-context)
                 label (ui/text! branch-context
                                 (if key "content" "loading"))]
             (ui/append! branch-context container label)
             container)))]
    (sig/mount! scope)
    (runtime/flush! application)
    (let [old-root (dynamic/switch-node switch)]
      (assert-equal [old-root] (apple/children renderer root)
                    "initial switch subtree is retained")
      (sig/set! selected true)
      (runtime/flush! application)
      (let [new-root (dynamic/switch-node switch)]
        (is (not (= old-root new-root)) "switch replaces branch identity")
        (assert-equal [new-root] (apple/children renderer root)
                      "switch changes only its local child")
        (match (apple/node renderer old-root)
          None (is true "old switch subtree is dropped")
          _ (is false "old switch subtree must not remain"))))
    (dynamic/dispose-switch! switch)
    (runtime/flush! application)
    (assert-equal [] (apple/children renderer root)
                  "switch disposal removes its retained subtree")))

(deftest keyed-reorder-preserves-node-identity-and-updates-values
  (let [scheduler (sig/scheduler)
        renderer (apple/create)
        application (runtime/create scheduler (apple/backend renderer))
        scope (sig/scope "list")
        context (ui/context application scope)
        items (sig/state scheduler
                         [(item "a" 1) (item "b" 2) (item "c" 3)])
        root (ui/column! context)
        keyed
        (dynamic/keyed!
         context root (sig/value items) :item-key compare
         (fn [item-context item-source]
           (ui/text-value!
            item-context
            (sig/own-signal!
             (:ui-scope item-context)
             (sig/map
              (fn [current]
                (proto/StringValue (str (:item-value current))))
              item-source)))))]
    (sig/mount! scope)
    (runtime/flush! application)
    (let [a (dynamic/keyed-node keyed "a")
          b (dynamic/keyed-node keyed "b")
          c (dynamic/keyed-node keyed "c")]
      (assert-equal [a b c] (apple/children renderer root)
                    "initial keyed order")
      (sig/set! items [(item "c" 30) (item "a" 10) (item "b" 20)])
      (runtime/flush! application)
      (assert-equal [c a b] (apple/children renderer root)
                    "keyed reorder moves retained nodes")
      (is (identical? a (dynamic/keyed-node keyed "a"))
          "keyed node identity survives reorder")
      (match (apple/property renderer c proto/TextValue)
        (Some (StringValue text))
        (assert-equal "30" text "keyed item signal updates retained property")
        _ (is false "updated keyed text exists"))
      (sig/set! items [(item "c" 30) (item "d" 40) (item "a" 10)])
      (runtime/flush! application)
      (let [d (dynamic/keyed-node keyed "d")]
        (assert-equal [c d a] (apple/children renderer root)
                      "keyed insert/remove stays local")
        (match (apple/node renderer b)
          None (is true "removed keyed node is dropped")
          _ (is false "removed keyed node must not remain"))))
    (dynamic/dispose-keyed! keyed)
    (runtime/flush! application)
    (assert-equal [] (apple/children renderer root)
                  "keyed disposal removes retained items")))
