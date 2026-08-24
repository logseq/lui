(ns lui.runtime-test
  (:require [clojure.test :refer [deftest is testing]]
            [signal.core :as sig]
            [lui.protocol :as proto
             :refer [StringValue SetProp MoveChild Press]]
            [lui.wire :as wire]
            [lui.runtime :as runtime]
            [lui.backend.apple :as apple
             :refer [AppleRow AppleLabel AppleTextInput]]
            [lui.backend.flutter :as flutter
             :refer [FlutterFlexRow FlutterParagraph FlutterWidgetIsland]]))

(defmacro assert-equal [expected actual message]
  `(is (= ~expected ~actual) ~message))

(deftest patch-batch-encodes-for-native-hosts
  (let [batch
        (record proto/patch-batch
          (generation 7)
          (ops [(proto/create-node-op 1 proto/Row)
                (proto/create-node-op 2 proto/Text)
                (proto/set-prop-op
                 2 proto/TextValue
                 (proto/StringValue "Hello \"LG\"\nUI"))
                (proto/insert-child-op 1 2 0)]))]
    (assert-equal
     "{\"generation\":7,\"ops\":[{\"op\":\"create-node\",\"id\":1,\"kind\":\"row\"},{\"op\":\"create-node\",\"id\":2,\"kind\":\"text\"},{\"op\":\"set-prop\",\"id\":2,\"property\":\"text\",\"value\":\"Hello \\\"LG\\\"\\nUI\"},{\"op\":\"insert-child\",\"parent\":1,\"child\":2,\"index\":0}]}"
     (wire/encode-batch batch)
     "LG emits the native host wire format without dynamic values")))

(deftest wire-backend-sends-one-json-batch
  (let [sent (atom "")
        renderer (apple/create-wire (fn [json] (reset! sent json) true))
        application (runtime/create (sig/scheduler) (apple/backend renderer))]
    (runtime/create-node! application proto/Spacer)
    (runtime/flush! application)
    (assert-equal
     "{\"generation\":1,\"ops\":[{\"op\":\"create-node\",\"id\":1,\"kind\":\"spacer\"}]}"
     @sent
     "Apple host receives one encoded PatchBatch")))

(deftest reactive-property-produces-local-patch
  (let [scheduler (sig/scheduler)
        renderer (apple/create)
        application (runtime/create scheduler (apple/backend renderer))
        component-scope (sig/scope "counter")
        count-state (sig/state scheduler 0)
        root (runtime/create-node! application proto/Row)
        label (runtime/create-node! application proto/Text)
        label-value
        (sig/map
         (fn [count] (proto/StringValue (str count)))
         (sig/value count-state))]
    (sig/mount! component-scope)
    (runtime/insert-child! application root label 0)
    (runtime/bind-prop!
     component-scope application label proto/TextValue label-value)
    (runtime/flush! application)
    (assert-equal 1 (count (apple/batches renderer)) "initial batch count")
    (assert-equal 4
                  (count (:ops (nth (apple/batches renderer) 0)))
                  "initial batch contains create, insert, and property patches")
    (match (apple/property renderer label proto/TextValue)
      (Some (StringValue text))
      (assert-equal "0" text "initial retained text")
      _ (is false "initial text property exists"))
    (sig/set! count-state 1)
    (runtime/flush! application)
    (assert-equal 2 (count (apple/batches renderer)) "update batch count")
    (let [update-batch (nth (apple/batches renderer) 1)]
      (assert-equal 2 (:generation update-batch) "second patch generation")
      (assert-equal 1 (count (:ops update-batch))
                    "reactive update emits one patch")
      (match (nth (:ops update-batch) 0)
        (SetProp node property (StringValue text))
        (do
          (assert-equal label node "updated node id")
          (assert-equal proto/TextValue property "updated property")
          (assert-equal "1" text "updated text"))
        _ (is false "reactive update is SetProp")))
    (runtime/flush! application)
    (assert-equal 2 (count (apple/batches renderer))
                  "no-op flush emits no batch")
    (assert-equal 2 (runtime/generation application)
                  "runtime generation advances only for emitted batches")))

(deftest structural-edits-preserve-retained-nodes
  (let [scheduler (sig/scheduler)
        renderer (apple/create)
        application (runtime/create scheduler (apple/backend renderer))
        root (runtime/create-node! application proto/Column)
        first-child (runtime/create-node! application proto/Text)
        second-child (runtime/create-node! application proto/Text)
        third-child (runtime/create-node! application proto/Button)]
    (runtime/insert-child! application root first-child 0)
    (runtime/insert-child! application root second-child 1)
    (runtime/insert-child! application root third-child 2)
    (runtime/flush! application)
    (runtime/move-child! application root third-child 0)
    (runtime/remove-child! application root second-child)
    (runtime/drop-node! application second-child)
    (runtime/flush! application)
    (assert-equal [third-child first-child]
                  (apple/children renderer root)
                  "backend applies move and remove locally")
    (assert-equal 3 (apple/node-count renderer)
                  "drop removes only the requested retained node")
    (assert-equal 3 (runtime/mounted-count application)
                  "runtime mount table stores remaining identities")
    (let [batch (nth (apple/batches renderer) 1)]
      (assert-equal 3 (count (:ops batch)) "structural patch count")
      (match (nth (:ops batch) 0)
        (MoveChild parent child index)
        (do
          (assert-equal root parent "move parent")
          (assert-equal third-child child "move child")
          (assert-equal 0 index "move index"))
        _ (is false "first structural patch is MoveChild")))))

(deftest backend-event-runs-through-effect-queue
  (let [scheduler (sig/scheduler)
        renderer (apple/create)
        application (runtime/create scheduler (apple/backend renderer))
        component-scope (sig/scope "button")
        count-state (sig/state scheduler 0)
        button (runtime/create-node! application proto/Button)
        label (runtime/create-node! application proto/Text)
        label-value
        (sig/map
         (fn [count] (proto/StringValue (str count)))
         (sig/value count-state))]
    (sig/mount! component-scope)
    (runtime/bind-prop!
     component-scope application label proto/TextValue label-value)
    (runtime/on-event!
     component-scope application button
     (fn [event]
       (match event
         (Press _node)
         (sig/update! count-state inc)
         _ true)))
    (runtime/flush! application)
    (runtime/dispatch! application (proto/Press button))
    (assert-equal 0 (sig/get count-state)
                  "event effect is deferred until stabilization")
    (runtime/flush! application)
    (assert-equal 1 (sig/get count-state) "event updates semantic state")
    (let [batch (nth (apple/batches renderer) 1)]
      (assert-equal 1 (count (:ops batch))
                    "event-driven state emits one property patch"))
    (sig/dispose-scope! component-scope)
    (runtime/dispatch! application (proto/Press button))
    (runtime/flush! application)
    (assert-equal 1 (sig/get count-state)
                  "disposed component handler is detached")))

(deftest semantic-nodes-map-to-platform-retained-types
  (let [scheduler (sig/scheduler)
        apple-renderer (apple/create)
        flutter-renderer (flutter/create)
        apple-runtime (runtime/create scheduler (apple/backend apple-renderer))
        flutter-runtime
        (runtime/create (sig/scheduler) (flutter/backend flutter-renderer))
        apple-row (runtime/create-node! apple-runtime proto/Row)
        apple-text (runtime/create-node! apple-runtime proto/Text)
        apple-input (runtime/create-node! apple-runtime proto/TextInput)
        flutter-row (runtime/create-node! flutter-runtime proto/Row)
        flutter-text (runtime/create-node! flutter-runtime proto/Text)
        flutter-input (runtime/create-node! flutter-runtime proto/TextInput)]
    (runtime/flush! apple-runtime)
    (runtime/flush! flutter-runtime)
    (match (apple/node apple-renderer apple-row)
      (Some AppleRow) (is true "row maps to Apple retained stack")
      _ (is false "Apple row mapping"))
    (match (apple/node apple-renderer apple-text)
      (Some AppleLabel) (is true "text maps to Apple native label")
      _ (is false "Apple text mapping"))
    (match (apple/node apple-renderer apple-input)
      (Some AppleTextInput) (is true "input maps to Apple native control")
      _ (is false "Apple text input mapping"))
    (match (flutter/node flutter-renderer flutter-row)
      (Some FlutterFlexRow) (is true "row maps to Flutter RenderBox")
      _ (is false "Flutter row mapping"))
    (match (flutter/node flutter-renderer flutter-text)
      (Some FlutterParagraph) (is true "text maps to Flutter render text")
      _ (is false "Flutter text mapping"))
    (match (flutter/node flutter-renderer flutter-input)
      (Some FlutterWidgetIsland)
      (is true "text input maps to Flutter Widget island")
      _ (is false "Flutter text input mapping"))))

(deftest backend-rejects-invalid-structural-patches
  (let [scheduler (sig/scheduler)
        renderer (apple/create)
        application (runtime/create scheduler (apple/backend renderer))
        root (runtime/create-node! application proto/Row)]
    (runtime/flush! application)
    (runtime/insert-child! application root 999 0)
    (is (thrown-with-msg?
         Invalid_argument
         #"unknown child"
         (runtime/flush! application))
        "backend validates patch identities")))

(deftest backend-protects-retained-tree-invariants
  (let [scheduler (sig/scheduler)
        renderer (apple/create)
        application (runtime/create scheduler (apple/backend renderer))
        root (runtime/create-node! application proto/Row)
        child (runtime/create-node! application proto/Text)]
    (runtime/insert-child! application root child 0)
    (runtime/flush! application)
    (runtime/drop-node! application child)
    (is (thrown-with-msg?
         Invalid_argument
         #"attached"
         (runtime/flush! application))
        "backend rejects dropping an attached node"))
  (let [scheduler (sig/scheduler)
        renderer (apple/create)
        application (runtime/create scheduler (apple/backend renderer))
        root (runtime/create-node! application proto/Row)
        child (runtime/create-node! application proto/Column)]
    (runtime/insert-child! application root child 0)
    (runtime/insert-child! application child root 0)
    (is (thrown-with-msg?
         Invalid_argument
         #"cycle"
         (runtime/flush! application))
        "backend rejects structural cycles"))
  (let [scheduler (sig/scheduler)
        renderer (apple/create)
        application (runtime/create scheduler (apple/backend renderer))
        row (runtime/create-node! application proto/Row)]
    (runtime/set-prop!
     application row proto/TextValue (proto/StringValue "invalid"))
    (is (thrown-with-msg?
         Invalid_argument
         #"property"
         (runtime/flush! application))
        "backend rejects properties unsupported by a semantic node")))

(deftest platform-bridge-receives-one-call-per-batch
  (let [scheduler (sig/scheduler)
        calls (atom 0)
        operation-count (atom 0)
        renderer
        (apple/create
         (fn [batch]
           (swap! calls inc)
           (swap! operation-count + (count (:ops batch)))
           true))
        application (runtime/create scheduler (apple/backend renderer))
        root (runtime/create-node! application proto/Row)
        child (runtime/create-node! application proto/Text)]
    (runtime/insert-child! application root child 0)
    (runtime/set-prop!
     application child proto/TextValue (proto/StringValue "batched"))
    (runtime/flush! application)
    (assert-equal 1 @calls "platform bridge is called once per PatchBatch")
    (assert-equal 4 @operation-count "one bridge call carries every operation")))

(deftest rejected-platform-batch-is-not-committed
  (let [scheduler (sig/scheduler)
        renderer (flutter/create (fn [_batch] false))
        application (runtime/create scheduler (flutter/backend renderer))]
    (runtime/create-node! application proto/Text)
    (is (thrown-with-msg?
         Invalid_argument
         #"rejected"
         (runtime/flush! application))
        "platform can reject a patch batch")
    (assert-equal 0 (flutter/node-count renderer)
                  "rejected batch does not mutate retained nodes")
    (assert-equal 0 (count (flutter/batches renderer))
                  "rejected batch is not recorded as committed")))
