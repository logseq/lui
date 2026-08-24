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

(deftest semantic-content-patch-uses-closed-wire-names
  (let [batch
        (record proto/patch-batch
          (generation 1)
          (ops [(proto/create-node-op 1 proto/Box)
                (proto/create-node-op 2 proto/Heading)
                (proto/create-node-op 3 proto/Paragraph)
                (proto/set-prop-op
                 2 proto/HeadingLevel (proto/IntValue 3))]))]
    (assert-equal
     (str
      "{\"generation\":1,\"ops\":["
      "{\"op\":\"create-node\",\"id\":1,\"kind\":\"box\"},"
      "{\"op\":\"create-node\",\"id\":2,\"kind\":\"heading\"},"
      "{\"op\":\"create-node\",\"id\":3,\"kind\":\"paragraph\"},"
      "{\"op\":\"set-prop\",\"id\":2,"
      "\"property\":\"heading-level\",\"value\":3}]}")
     (wire/encode-batch batch)
     "semantic content uses the native host's closed wire vocabulary")))

(deftest form-control-patch-uses-closed-wire-names
  (let [batch
        (record proto/patch-batch
          (generation 1)
          (ops [(proto/create-node-op 1 proto/Label)
                (proto/create-node-op 2 proto/TextInput)
                (proto/set-prop-op
                 2 proto/LabelledBy (proto/IntValue 1))
                (proto/set-prop-op
                 2 proto/DescribedBy (proto/IntValue 3))
                (proto/set-prop-op
                 2 proto/ErrorMessageBy (proto/IntValue 4))
                (proto/set-prop-op
                 2 proto/InputType (proto/StringValue "email"))
                (proto/set-prop-op
                 2 proto/Invalid (proto/BoolValue true))]))]
    (assert-equal
     (str
      "{\"generation\":1,\"ops\":["
      "{\"op\":\"create-node\",\"id\":1,\"kind\":\"label\"},"
      "{\"op\":\"create-node\",\"id\":2,\"kind\":\"text-input\"},"
      "{\"op\":\"set-prop\",\"id\":2,"
      "\"property\":\"labelled-by\",\"value\":1},"
      "{\"op\":\"set-prop\",\"id\":2,"
      "\"property\":\"described-by\",\"value\":3},"
      "{\"op\":\"set-prop\",\"id\":2,"
      "\"property\":\"error-message-by\",\"value\":4},"
      "{\"op\":\"set-prop\",\"id\":2,"
      "\"property\":\"input-type\",\"value\":\"email\"},"
      "{\"op\":\"set-prop\",\"id\":2,"
      "\"property\":\"invalid\",\"value\":true}]}")
     (wire/encode-batch batch)
     "form controls use the native host's closed wire vocabulary")))

(deftest toggle-controls-use-closed-wire-names
  (let [batch
        (record proto/patch-batch
          (generation 1)
          (ops [(proto/create-node-op 1 proto/Checkbox)
                (proto/create-node-op 2 proto/SwitchControl)
                (proto/set-prop-op
                 1 proto/Checked (proto/BoolValue true))
                (proto/set-prop-op
                 1 proto/Indeterminate (proto/BoolValue true))
                (proto/set-prop-op
                 2 proto/Checked (proto/BoolValue false))]))]
    (assert-equal
     (str
      "{\"generation\":1,\"ops\":["
      "{\"op\":\"create-node\",\"id\":1,\"kind\":\"checkbox\"},"
      "{\"op\":\"create-node\",\"id\":2,\"kind\":\"switch\"},"
      "{\"op\":\"set-prop\",\"id\":1,"
      "\"property\":\"checked\",\"value\":true},"
      "{\"op\":\"set-prop\",\"id\":1,"
      "\"property\":\"indeterminate\",\"value\":true},"
      "{\"op\":\"set-prop\",\"id\":2,"
      "\"property\":\"checked\",\"value\":false}]}")
     (wire/encode-batch batch)
     "toggle controls use a closed native wire vocabulary")))

(deftest surface-properties-use-closed-wire-names
  (let [batch
        (record proto/patch-batch
          (generation 1)
          (ops [(proto/create-node-op 1 proto/Row)
                (proto/set-prop-op
                 1 proto/PaddingHorizontal (proto/IntValue 10))
                (proto/set-prop-op
                 1 proto/PaddingVertical (proto/IntValue 2))
                (proto/set-prop-op
                 1 proto/ForegroundValue (proto/StringValue "foreground"))
                (proto/set-prop-op
                 1 proto/BorderColorValue (proto/StringValue "border"))
                (proto/set-prop-op
                 1 proto/BorderWidth (proto/IntValue 1))
                (proto/set-prop-op
                 1 proto/CornerRadius (proto/IntValue 6))]))]
    (assert-equal
     (str
      "{\"generation\":1,\"ops\":["
      "{\"op\":\"create-node\",\"id\":1,\"kind\":\"row\"},"
      "{\"op\":\"set-prop\",\"id\":1,"
      "\"property\":\"padding-horizontal\",\"value\":10},"
      "{\"op\":\"set-prop\",\"id\":1,"
      "\"property\":\"padding-vertical\",\"value\":2},"
      "{\"op\":\"set-prop\",\"id\":1,"
      "\"property\":\"foreground\",\"value\":\"foreground\"},"
      "{\"op\":\"set-prop\",\"id\":1,"
      "\"property\":\"border-color\",\"value\":\"border\"},"
      "{\"op\":\"set-prop\",\"id\":1,"
      "\"property\":\"border-width\",\"value\":1},"
      "{\"op\":\"set-prop\",\"id\":1,"
      "\"property\":\"corner-radius\",\"value\":6}]}")
     (wire/encode-batch batch)
     "Surface styling remains a closed typed wire contract")))

(deftest surface-numeric-properties-reject-negative-values
  (let [application
        (runtime/create (sig/scheduler) (apple/backend (apple/create)))
        box (runtime/create-node! application proto/Box)]
    (is (thrown-with-msg?
         Invalid_argument
         #"invalid property value"
         (runtime/set-prop!
          application box proto/BorderWidth (proto/IntValue -1)))
        "border width cannot be negative")
    (is (thrown-with-msg?
         Invalid_argument
         #"invalid property value"
         (runtime/set-prop!
          application box proto/CornerRadius (proto/IntValue -1)))
        "corner radius cannot be negative")
    (is (thrown-with-msg?
         Invalid_argument
         #"invalid property value"
         (runtime/set-prop!
          application box proto/PaddingHorizontal (proto/IntValue -1)))
        "surface padding cannot be negative")))

(deftest form-controls-retain-typed-accessibility-relationships
  (let [renderer (apple/create)
        application
        (runtime/create (sig/scheduler) (apple/backend renderer))
        label (runtime/create-node! application proto/Label)
        input (runtime/create-node! application proto/TextInput)
        description (runtime/create-node! application proto/Paragraph)
        error (runtime/create-node! application proto/Paragraph)]
    (runtime/set-prop!
     application label proto/TextValue (proto/StringValue "Email"))
    (runtime/set-prop!
     application input proto/LabelledBy (proto/IntValue label))
    (runtime/set-prop!
     application input proto/DescribedBy (proto/IntValue description))
    (runtime/set-prop!
     application input proto/ErrorMessageBy (proto/IntValue error))
    (runtime/set-prop!
     application input proto/InputType (proto/StringValue "email"))
    (runtime/set-prop!
     application input proto/Invalid (proto/BoolValue true))
    (runtime/flush! application)
    (match (apple/property renderer input proto/LabelledBy)
      (Some (proto/IntValue node))
      (assert-equal label node "input retains its Label node relationship")
      _ (is false "input has a labelled-by relationship"))
    (match (apple/property renderer input proto/DescribedBy)
      (Some (proto/IntValue node))
      (assert-equal description node "input retains its description")
      _ (is false "input has a described-by relationship"))
    (match (apple/property renderer input proto/ErrorMessageBy)
      (Some (proto/IntValue node))
      (assert-equal error node "input retains its error message")
      _ (is false "input has an error relationship"))
    (match (apple/property renderer input proto/InputType)
      (Some (StringValue value))
      (assert-equal "email" value "input type is typed retained state")
      _ (is false "input type reaches the backend"))
    (match (apple/property renderer input proto/Invalid)
      (Some (proto/BoolValue value))
      (assert-equal true value "invalid state is retained")
      _ (is false "invalid state reaches the backend"))))

(deftest dropping-form-content-clears-retained-relationships
  (let [renderer (apple/create)
        application
        (runtime/create (sig/scheduler) (apple/backend renderer))
        label (runtime/create-node! application proto/Label)
        input (runtime/create-node! application proto/TextInput)]
    (runtime/set-prop!
     application input proto/LabelledBy (proto/IntValue label))
    (runtime/flush! application)
    (runtime/drop-node! application label)
    (runtime/flush! application)
    (match (apple/property renderer input proto/LabelledBy)
      None (is true "dropping a label clears incoming relationships")
      _ (is false "retained relationships cannot point at dropped nodes"))))

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

(deftest retained-backend-rejects-out-of-order-generations
  (let [renderer (apple/create)
        backend (apple/backend renderer)
        skipped
        (record proto/patch-batch
          (generation 2)
          (ops [(proto/create-node-op 1 proto/Text)]))]
    (is (thrown-with-msg?
         Invalid_argument
         #"expected patch generation 1"
         ((:apply-batch backend) skipped))
        "retained backends reject skipped generations")
    (assert-equal 0 (apple/node-count renderer)
                  "rejected generations do not mutate retained nodes")))

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

(deftest runtime-validates-native-events-before-scheduling
  (let [application
        (runtime/create (sig/scheduler) (apple/backend (apple/create)))
        component-scope (sig/scope "events")
        text (runtime/create-node! application proto/Text)
        calls (atom 0)]
    (sig/mount! component-scope)
    (runtime/on-event!
     component-scope application text
     (fn [_event] (swap! calls inc) true))
    (is (thrown-with-msg?
         Invalid_argument
         #"unsupported"
         (runtime/dispatch! application (proto/Press text)))
        "a native host cannot emit button events for text nodes")
    (runtime/flush! application)
    (assert-equal 0 @calls "invalid native events never enter the effect queue")
    (is (thrown-with-msg?
         Invalid_argument
         #"unknown node"
         (runtime/dispatch! application (proto/Press 999)))
        "events cannot target unknown retained identities")))

(deftest toggle-events-carry-the-native-next-value
  (let [application
        (runtime/create (sig/scheduler) (apple/backend (apple/create)))
        component-scope (sig/scope "toggle-events")
        checkbox (runtime/create-node! application proto/Checkbox)
        changes (atom [])]
    (sig/mount! component-scope)
    (runtime/on-event!
     component-scope application checkbox
     (fn [event]
       (match event
         (proto/ToggleChanged _node checked)
         (do
           (swap! changes conj checked)
           true)
         _ true)))
    (runtime/dispatch!
     application (proto/ToggleChanged checkbox true))
    (runtime/flush! application)
    (assert-equal [true] @changes
                  "toggle events carry the native checked value")))

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
  (let [renderer (apple/create)
        backend (apple/backend renderer)
        invalid-batch
        (record proto/patch-batch
          (generation 1)
          (ops [(proto/create-node-op 1 proto/Row)
                (proto/insert-child-op 1 999 0)]))]
    (is (thrown-with-msg?
         Invalid_argument
         #"unknown child"
         ((:apply-batch backend) invalid-batch))
        "backend validates patch identities")
    (assert-equal 0 (apple/node-count renderer)
                  "invalid batches are rejected atomically")))

(deftest runtime-rejects-property-values-with-the-wrong-wire-type
  (let [renderer (apple/create)
        application
        (runtime/create (sig/scheduler) (apple/backend renderer))
        text (runtime/create-node! application proto/Text)
        heading (runtime/create-node! application proto/Heading)
        button (runtime/create-node! application proto/Button)
        row (runtime/create-node! application proto/Row)
        checkbox (runtime/create-node! application proto/Checkbox)
        switch-control (runtime/create-node! application proto/SwitchControl)]
    (is (thrown-with-msg?
         Invalid_argument
         #"invalid property value"
         (runtime/set-prop!
          application heading proto/HeadingLevel (proto/IntValue 7)))
        "heading levels are limited to the semantic HTML range")
    (is (thrown-with-msg?
         Invalid_argument
         #"invalid property value"
         (runtime/set-prop!
          application text proto/TextValue (proto/BoolValue true)))
        "text properties require string wire values")
    (is (thrown-with-msg?
         Invalid_argument
         #"invalid property value"
         (runtime/set-prop!
          application button proto/Enabled (proto/StringValue "yes")))
        "enabled properties require boolean wire values")
    (is (thrown-with-msg?
         Invalid_argument
         #"invalid property value"
         (runtime/set-prop!
          application row proto/Gap (proto/StringValue "8")))
        "numeric layout properties require integer wire values")
    (is (thrown-with-msg?
         Invalid_argument
         #"invalid property value"
         (runtime/set-prop!
          application checkbox proto/Checked (proto/StringValue "yes")))
        "checked state requires a boolean wire value")
    (is (thrown-with-msg?
         Invalid_argument
         #"unsupported"
         (runtime/set-prop!
          application switch-control proto/Indeterminate
          (proto/BoolValue true)))
        "only Checkbox supports indeterminate state")
    (runtime/flush! application)
    (assert-equal
     6
     (count (:ops (nth (apple/batches renderer) 0)))
     "rejected values never enter the patch queue")))

(deftest backend-protects-retained-tree-invariants
  (let [backend (apple/backend (apple/create))
        invalid-batch
        (record proto/patch-batch
          (generation 1)
          (ops [(proto/create-node-op 1 proto/Row)
                (proto/create-node-op 2 proto/Text)
                (proto/insert-child-op 1 2 0)
                (proto/drop-node-op 2)]))]
    (is (thrown-with-msg?
         Invalid_argument
         #"attached"
         ((:apply-batch backend) invalid-batch))
        "backend rejects dropping an attached node"))
  (let [backend (apple/backend (apple/create))
        invalid-batch
        (record proto/patch-batch
          (generation 1)
          (ops [(proto/create-node-op 1 proto/Row)
                (proto/create-node-op 2 proto/Column)
                (proto/insert-child-op 1 2 0)
                (proto/insert-child-op 2 1 0)]))]
    (is (thrown-with-msg?
         Invalid_argument
         #"cycle"
         ((:apply-batch backend) invalid-batch))
        "backend rejects structural cycles"))
  (let [backend (apple/backend (apple/create))
        invalid-batch
        (record proto/patch-batch
          (generation 1)
          (ops [(proto/create-node-op 1 proto/Row)
                (proto/set-prop-op
                 1 proto/TextValue (proto/StringValue "invalid"))]))]
    (is (thrown-with-msg?
         Invalid_argument
         #"property"
         ((:apply-batch backend) invalid-batch))
        "backend rejects properties unsupported by a semantic node"))
  (let [backend (apple/backend (apple/create))
        invalid-batch
        (record proto/patch-batch
          (generation 1)
          (ops [(proto/create-node-op 1 proto/Text)
                (proto/create-node-op 2 proto/Text)
                (proto/insert-child-op 1 2 0)]))]
    (is (thrown-with-msg?
         Invalid_argument
         #"cannot contain"
         ((:apply-batch backend) invalid-batch))
        "backend rejects children on leaf nodes"))
  (let [backend (apple/backend (apple/create))
        invalid-batch
        (record proto/patch-batch
          (generation 1)
          (ops [(proto/create-node-op 1 proto/Scroll)
                (proto/create-node-op 2 proto/Text)
                (proto/create-node-op 3 proto/Text)
                (proto/insert-child-op 1 2 0)
                (proto/insert-child-op 1 3 1)]))]
    (is (thrown-with-msg?
         Invalid_argument
         #"one child"
         ((:apply-batch backend) invalid-batch))
        "backend enforces single-child containers")))

(deftest runtime-rejects-invalid-structure-before-enqueue
  (let [application
        (runtime/create (sig/scheduler) (apple/backend (apple/create)))
        label (runtime/create-node! application proto/Text)
        child (runtime/create-node! application proto/Text)]
    (is (thrown-with-msg?
         Invalid_argument
         #"cannot contain"
         (runtime/insert-child! application label child 0))
        "leaf nodes reject children before a batch reaches the backend"))
  (let [application
        (runtime/create (sig/scheduler) (apple/backend (apple/create)))
        scroll (runtime/create-node! application proto/Scroll)
        first-child (runtime/create-node! application proto/Text)
        second-child (runtime/create-node! application proto/Text)]
    (runtime/insert-child! application scroll first-child 0)
    (is (thrown-with-msg?
         Invalid_argument
         #"one child"
         (runtime/insert-child! application scroll second-child 1))
        "scroll nodes enforce their single-child contract"))
  (let [application
        (runtime/create (sig/scheduler) (apple/backend (apple/create)))
        root (runtime/create-node! application proto/Column)
        child (runtime/create-node! application proto/Row)]
    (runtime/insert-child! application root child 0)
    (is (thrown-with-msg?
         Invalid_argument
         #"already attached"
         (runtime/insert-child! application root child 1))
        "a retained node can only have one parent")
    (is (thrown-with-msg?
         Invalid_argument
         #"cycle"
         (runtime/insert-child! application child root 0))
        "runtime prevents retained-tree cycles")))

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
