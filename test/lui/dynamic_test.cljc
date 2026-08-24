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

(deftest switch-preserves-static-sibling-order
  (let [scheduler (sig/scheduler)
        renderer (apple/create)
        application (runtime/create scheduler (apple/backend renderer))
        scope (sig/scope "interleaved-switch")
        context (ui/context application scope)
        selected (sig/state scheduler false)
        root (ui/row! context)
        before (ui/text! context "before")
        _ (ui/append! context root before)
        switch
        (dynamic/switch!
         context root (sig/value selected)
         (fn [^:bool left ^:bool right] (= left right))
         (fn [branch-context ^:bool key]
           (ui/text! branch-context (if key "on" "off"))))
        after (ui/text! context "after")
        _ (ui/append! context root after)]
    (sig/mount! scope)
    (runtime/flush! application)
    (let [initial-node (dynamic/switch-node switch)]
      (assert-equal [before initial-node after]
                    (apple/children renderer root)
                    "switch occupies its declaration position")
      (sig/set! selected true)
      (runtime/flush! application)
      (let [replacement (dynamic/switch-node switch)]
        (assert-equal [before replacement after]
                      (apple/children renderer root)
                      "branch replacement leaves static siblings in place")
        (assert-equal [before replacement after]
                      (runtime/children application root)
                      "runtime and backend retain the same order")))
    (dynamic/dispose-switch! switch)
    (runtime/flush! application)
    (assert-equal [before after] (apple/children renderer root)
                  "switch disposal closes only its dynamic segment")))

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

(deftest keyed-preserves-static-sibling-order
  (let [scheduler (sig/scheduler)
        renderer (apple/create)
        application (runtime/create scheduler (apple/backend renderer))
        scope (sig/scope "interleaved-keyed")
        context (ui/context application scope)
        items (sig/state scheduler [(item "a" 1) (item "b" 2)])
        root (ui/column! context)
        before (ui/text! context "before")
        _ (ui/append! context root before)
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
              item-source)))))
        after (ui/text! context "after")
        _ (ui/append! context root after)]
    (sig/mount! scope)
    (runtime/flush! application)
    (let [a (dynamic/keyed-node keyed "a")
          b (dynamic/keyed-node keyed "b")]
      (assert-equal [before a b after] (apple/children renderer root)
                    "keyed items occupy their declaration segment")
      (sig/set! items [(item "b" 20) (item "c" 30) (item "a" 10)])
      (runtime/flush! application)
      (let [c (dynamic/keyed-node keyed "c")]
        (assert-equal [before b c a after]
                      (apple/children renderer root)
                      "keyed patches stay inside their segment")))
    (dynamic/dispose-keyed! keyed)
    (runtime/flush! application)
    (assert-equal [before after] (apple/children renderer root)
                  "keyed disposal preserves surrounding siblings")))

(deftest conditional-mounts-and-drops-one-retained-subtree
  (let [scheduler (sig/scheduler)
        renderer (apple/create)
        application (runtime/create scheduler (apple/backend renderer))
        scope (sig/scope "conditional")
        context (ui/context application scope)
        visible (sig/state scheduler false)
        root (ui/column! context)
        before (ui/text! context "before")
        _ (ui/append! context root before)
        conditional
        (dynamic/conditional!
         context root (sig/value visible)
         (fn [branch-context]
           (ui/text! branch-context "visible")))
        after (ui/text! context "after")
        _ (ui/append! context root after)]
    (sig/mount! scope)
    (runtime/flush! application)
    (assert-equal [before after] (apple/children renderer root)
                  "false condition has no retained placeholder")
    (assert-equal 3 (runtime/mounted-count application)
                  "false condition allocates no hidden node")
    (sig/set! visible true)
    (runtime/flush! application)
    (let [conditional-node (dynamic/conditional-node conditional)]
      (assert-equal [before conditional-node after]
                    (apple/children renderer root)
                    "true condition mounts at its declaration position")
      (assert-equal 4 (runtime/mounted-count application)
                    "true condition owns exactly one subtree root")
      (sig/set! visible false)
      (runtime/flush! application)
      (assert-equal [before after] (apple/children renderer root)
                    "false transition removes only the conditional subtree")
      (assert-equal 3 (runtime/mounted-count application)
                    "removed conditional subtree is dropped")
      (match (apple/node renderer conditional-node)
        None (is true "removed conditional node leaves the backend")
        _ (is false "removed conditional node must not remain")))
    (sig/set! visible true)
    (runtime/flush! application)
    (dynamic/dispose-conditional! conditional)
    (runtime/flush! application)
    (assert-equal [before after] (apple/children renderer root)
                  "conditional disposal removes an active subtree")
    (assert-equal 3 (runtime/mounted-count application)
                  "conditional disposal releases its retained nodes")))

(deftest earlier-dynamic-growth-adjusts-later-segment-offsets
  (let [scheduler (sig/scheduler)
        renderer (apple/create)
        application (runtime/create scheduler (apple/backend renderer))
        scope (sig/scope "multiple-dynamic-segments")
        context (ui/context application scope)
        visible (sig/state scheduler false)
        selected (sig/state scheduler false)
        root (ui/row! context)
        before (ui/text! context "before")
        _ (ui/append! context root before)
        conditional
        (dynamic/conditional!
         context root (sig/value visible)
         (fn [branch-context]
           (ui/text! branch-context "optional")))
        middle (ui/text! context "middle")
        _ (ui/append! context root middle)
        switch
        (dynamic/switch!
         context root (sig/value selected)
         (fn [^:bool left ^:bool right] (= left right))
         (fn [branch-context ^:bool key]
           (ui/text! branch-context (if key "on" "off"))))
        after (ui/text! context "after")
        _ (ui/append! context root after)]
    (sig/mount! scope)
    (runtime/flush! application)
    (let [initial-switch-node (dynamic/switch-node switch)]
      (assert-equal [before middle initial-switch-node after]
                    (apple/children renderer root)
                    "empty earlier segment does not offset later content")
      (sig/set! visible true)
      (runtime/flush! application)
      (let [conditional-node (dynamic/conditional-node conditional)]
        (assert-equal [before conditional-node middle initial-switch-node after]
                      (apple/children renderer root)
                      "earlier segment growth shifts later segment bases")
        (sig/set! selected true)
        (runtime/flush! application)
        (let [replacement (dynamic/switch-node switch)]
          (assert-equal [before conditional-node middle replacement after]
                        (apple/children renderer root)
                        "later segment updates use their adjusted base"))))
    (dynamic/dispose-switch! switch)
    (dynamic/dispose-conditional! conditional)))

(deftest parent-scope-disposal-releases-dynamic-segments
  (let [scheduler (sig/scheduler)
        renderer (apple/create)
        application (runtime/create scheduler (apple/backend renderer))
        scope (sig/scope "dynamic-owner")
        context (ui/context application scope)
        visible (sig/state scheduler true)
        root (ui/column! context)
        conditional
        (dynamic/conditional!
         context root (sig/value visible)
         (fn [branch-context]
           (ui/text! branch-context "owned")))]
    (sig/mount! scope)
    (runtime/flush! application)
    (assert-equal 2 (runtime/mounted-count application)
                  "mounted owner retains its conditional child")
    (sig/dispose-scope! scope)
    (runtime/flush! application)
    (assert-equal [] (apple/children renderer root)
                  "owner disposal unmounts the dynamic subtree")
    (assert-equal 1 (runtime/mounted-count application)
                  "owner disposal drops the dynamic subtree")
    (is (dynamic/dispose-conditional! conditional)
        "explicit disposal remains idempotent after owner disposal")))
