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
                       1 proto/TextValue (proto/StringValue "Select all"))
                      (proto/set-prop-op
                       2 proto/Checked (proto/BoolValue false))
                      (proto/set-prop-op
                       2 proto/TextValue (proto/StringValue "Notifications"))]))]
    (assert-equal
     (str
      "{\"generation\":1,\"ops\":["
      "{\"op\":\"create-node\",\"id\":1,\"kind\":\"checkbox\"},"
      "{\"op\":\"create-node\",\"id\":2,\"kind\":\"switch\"},"
      "{\"op\":\"set-prop\",\"id\":1,"
      "\"property\":\"checked\",\"value\":true},"
      "{\"op\":\"set-prop\",\"id\":1,"
      "\"property\":\"text\",\"value\":\"Select all\"},"
      "{\"op\":\"set-prop\",\"id\":2,"
      "\"property\":\"checked\",\"value\":false},"
      "{\"op\":\"set-prop\",\"id\":2,"
      "\"property\":\"text\",\"value\":\"Notifications\"}]}")
     (wire/encode-batch batch)
     "toggle controls use a closed native wire vocabulary")))

(deftest checkbox-and-switch-use-the-direct-vercel-native-contract
  (doseq [kind [proto/Checkbox proto/SwitchControl]]
    (is (proto/property-supported? kind proto/TextValue)
        "direct controls carry their visible text")
    (is (proto/property-supported? kind proto/Checked)
        "direct controls carry model-owned checked state")
    (is (proto/property-supported? kind proto/Enabled)
        "direct controls carry disabled state through Enabled")
    (is (proto/property-supported? kind proto/AccessibilityLabel)
        "direct controls accept the accessibility-only label")
    (is (not (proto/property-supported? kind proto/Invalid))
        "invalid is not part of the reference control contract")
    (is (not (proto/can-contain-children? kind))
        "backend-owned control parts never enter the retained tree")))

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
                       1 proto/CornerRadius (proto/IntValue 6))
                      (proto/set-prop-op
                       1 proto/WidthValue (proto/IntValue 120))
                      (proto/set-prop-op
                       1 proto/HeightValue (proto/IntValue 24))
                      (proto/set-prop-op
                       1 proto/MinWidth (proto/IntValue 80))
                      (proto/set-prop-op
                       1 proto/MaxWidth (proto/IntValue 160))
                      (proto/set-prop-op
                       1 proto/MinHeight (proto/IntValue 16))
                      (proto/set-prop-op
                       1 proto/MaxHeight (proto/IntValue 32))]))]
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
      "\"property\":\"corner-radius\",\"value\":6},"
      "{\"op\":\"set-prop\",\"id\":1,"
      "\"property\":\"width\",\"value\":120},"
      "{\"op\":\"set-prop\",\"id\":1,"
      "\"property\":\"height\",\"value\":24},"
      "{\"op\":\"set-prop\",\"id\":1,"
      "\"property\":\"min-width\",\"value\":80},"
      "{\"op\":\"set-prop\",\"id\":1,"
      "\"property\":\"max-width\",\"value\":160},"
      "{\"op\":\"set-prop\",\"id\":1,"
      "\"property\":\"min-height\",\"value\":16},"
      "{\"op\":\"set-prop\",\"id\":1,"
      "\"property\":\"max-height\",\"value\":32}]}")
     (wire/encode-batch batch)
     "Surface styling remains a closed typed wire contract")))

(deftest progress-control-uses-a-closed-range-contract
  (let [batch
        (record proto/patch-batch
                (generation 1)
                (ops [(proto/create-node-op 1 proto/ProgressControl)
                      (proto/set-prop-op
                       1 proto/MinValue (proto/IntValue 0))
                      (proto/set-prop-op
                       1 proto/MaxValue (proto/IntValue 10))
                      (proto/set-prop-op
                       1 proto/ProgressValue (proto/IntValue 3))]))]
    (assert-equal
     (str
      "{\"generation\":1,\"ops\":["
      "{\"op\":\"create-node\",\"id\":1,\"kind\":\"progress\"},"
      "{\"op\":\"set-prop\",\"id\":1,"
      "\"property\":\"min-value\",\"value\":0},"
      "{\"op\":\"set-prop\",\"id\":1,"
      "\"property\":\"max-value\",\"value\":10},"
      "{\"op\":\"set-prop\",\"id\":1,"
      "\"property\":\"value\",\"value\":3}]}")
     (wire/encode-batch batch)
     "Progress stays inside the typed native wire vocabulary")))

(deftest separator-uses-a-closed-orientation-contract
  (let [batch
        (record proto/patch-batch
                (generation 1)
                (ops [(proto/create-node-op 1 proto/Divider)
                      (proto/set-prop-op
                       1 proto/OrientationValue
                       (proto/StringValue "vertical"))]))]
    (assert-equal
     (str
      "{\"generation\":1,\"ops\":["
      "{\"op\":\"create-node\",\"id\":1,\"kind\":\"divider\"},"
      "{\"op\":\"set-prop\",\"id\":1,"
      "\"property\":\"orientation\",\"value\":\"vertical\"}]}")
     (wire/encode-batch batch)
     "Separator stays inside the typed native wire vocabulary")))

(deftest separator-rejects-an-invalid-orientation-before-enqueue
  (let [renderer (apple/create)
        application
        (runtime/create (sig/scheduler) (apple/backend renderer))
        separator (runtime/create-node! application proto/Divider)]
    (is (thrown-with-msg?
         Invalid_argument
         #"invalid property value"
         (runtime/set-prop!
          application separator proto/OrientationValue
          (proto/StringValue "diagonal")))
        "Separator accepts only horizontal or vertical orientation")
    (runtime/flush! application)
    (assert-equal
     1
     (count (:ops (nth (apple/batches renderer) 0)))
     "invalid orientation never enters the patch queue")))

(deftest progress-control-rejects-an-empty-range-atomically
  (let [renderer (apple/create)
        backend (apple/backend renderer)
        batch
        (record proto/patch-batch
                (generation 1)
                (ops [(proto/create-node-op 1 proto/ProgressControl)
                      (proto/set-prop-op
                       1 proto/MinValue (proto/IntValue 10))
                      (proto/set-prop-op
                       1 proto/MaxValue (proto/IntValue 10))]))]
    (is (thrown-with-msg?
         Invalid_argument
         #"progress max-value must be greater than min-value"
         ((:apply-batch backend) batch))
        "an invalid range never reaches a platform backend")
    (assert-equal 0 (apple/node-count renderer)
                  "range validation rejects the complete patch batch")))

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
        "surface padding cannot be negative")
    (doseq [property
            [proto/WidthValue proto/HeightValue
             proto/MinWidth proto/MaxWidth
             proto/MinHeight proto/MaxHeight]]
      (is (thrown-with-msg?
           Invalid_argument
           #"invalid property value"
           (runtime/set-prop!
            application box property (proto/IntValue -1)))
          "size constraints cannot be negative"))))

(deftest surface-size-constraints-reject-conflicts-atomically
  (doseq [constraint
          [(tuple proto/MinWidth 121 proto/MaxWidth 120)
           (tuple proto/WidthValue 79 proto/MinWidth 80)
           (tuple proto/WidthValue 161 proto/MaxWidth 160)
           (tuple proto/MinHeight 25 proto/MaxHeight 24)
           (tuple proto/HeightValue 15 proto/MinHeight 16)
           (tuple proto/HeightValue 33 proto/MaxHeight 32)]]
    (match constraint
      (tuple property-a value-a property-b value-b)
      (let [renderer (apple/create)
            backend (apple/backend renderer)
            batch
            (record proto/patch-batch
                    (generation 1)
                    (ops [(proto/create-node-op 1 proto/Box)
                          (proto/set-prop-op
                           1 property-a (proto/IntValue value-a))
                          (proto/set-prop-op
                           1 property-b (proto/IntValue value-b))]))]
        (is (thrown-with-msg?
             Invalid_argument
             #"surface size constraints conflict"
             ((:apply-batch backend) batch))
            "conflicting size constraints reject the complete patch batch")
        (assert-equal 0 (apple/node-count renderer)
                      "a rejected size batch leaves no retained nodes")))))

(deftest surface-size-bounds-may-be-equal
  (let [renderer (apple/create)
        backend (apple/backend renderer)
        batch
        (record proto/patch-batch
                (generation 1)
                (ops [(proto/create-node-op 1 proto/Box)
                      (proto/set-prop-op 1 proto/WidthValue (proto/IntValue 80))
                      (proto/set-prop-op 1 proto/MinWidth (proto/IntValue 80))
                      (proto/set-prop-op 1 proto/MaxWidth (proto/IntValue 80))]))]
    ((:apply-batch backend) batch)
    (assert-equal 1 (apple/node-count renderer)
                  "equal bounds describe a valid fixed size")))

(deftest vercel-layout-properties-use-a-closed-wire-contract
  (let [batch
        (record proto/patch-batch
                (generation 1)
                (ops [(proto/create-node-op 1 proto/Row)
                      (proto/create-node-op 2 proto/Grid)
                      (proto/set-prop-op
                       1 proto/MainAlignment (proto/StringValue "space_between"))
                      (proto/set-prop-op
                       1 proto/CrossAlignment (proto/StringValue "center"))
                      (proto/set-prop-op
                       1 proto/GrowValue (proto/FloatValue 1.0))
                      (proto/set-prop-op
                       2 proto/GridColumns (proto/IntValue 3))]))]
    (assert-equal
     (str
      "{\"generation\":1,\"ops\":["
      "{\"op\":\"create-node\",\"id\":1,\"kind\":\"row\"},"
      "{\"op\":\"create-node\",\"id\":2,\"kind\":\"grid\"},"
      "{\"op\":\"set-prop\",\"id\":1,"
      "\"property\":\"main\",\"value\":\"space_between\"},"
      "{\"op\":\"set-prop\",\"id\":1,"
      "\"property\":\"cross\",\"value\":\"center\"},"
      "{\"op\":\"set-prop\",\"id\":1,"
      "\"property\":\"grow\",\"value\":1.0},"
      "{\"op\":\"set-prop\",\"id\":2,"
      "\"property\":\"columns\",\"value\":3}]}")
     (wire/encode-batch batch)
     "layout names match Vercel Native without CSS vocabulary")))

(deftest vercel-layout-values-are-validated-before-enqueue
  (let [application
        (runtime/create (sig/scheduler) (apple/backend (apple/create)))
        row (runtime/create-node! application proto/Row)
        grid (runtime/create-node! application proto/Grid)]
    (doseq [constraint
            [(tuple row proto/MainAlignment (proto/StringValue "between"))
             (tuple row proto/CrossAlignment (proto/StringValue "baseline"))
             (tuple row proto/GrowValue (proto/FloatValue -1.0))
             (tuple grid proto/GridColumns (proto/IntValue -1))]]
      (match constraint
        (tuple node property value)
        (is (thrown-with-msg?
             Invalid_argument
             #"invalid property value"
             (runtime/set-prop! application node property value))
            "invalid layout values never enter a patch batch")))))

(deftest overlay-surfaces-use-direct-closed-node-kinds
  (let [batch
        (record proto/patch-batch
                (generation 1)
                (ops [(proto/create-node-op 1 proto/Stack)
                      (proto/create-node-op 2 proto/Panel)
                      (proto/create-node-op 3 proto/Card)
                      (proto/insert-child-op 1 2 0)
                      (proto/insert-child-op 1 3 1)]))]
    (assert-equal
     (str
      "{\"generation\":1,\"ops\":["
      "{\"op\":\"create-node\",\"id\":1,\"kind\":\"stack\"},"
      "{\"op\":\"create-node\",\"id\":2,\"kind\":\"panel\"},"
      "{\"op\":\"create-node\",\"id\":3,\"kind\":\"card\"},"
      "{\"op\":\"insert-child\",\"parent\":1,\"child\":2,\"index\":0},"
      "{\"op\":\"insert-child\",\"parent\":1,\"child\":3,\"index\":1}]}")
     (wire/encode-batch batch)
     "overlay surfaces retain Vercel Native node names")))

(deftest overlay-surfaces-reject-flow-gap-atomically
  (doseq [kind [proto/Stack proto/Panel proto/Card]]
    (let [renderer (apple/create)
          batch
          (record proto/patch-batch
                  (generation 1)
                  (ops [(proto/create-node-op 1 kind)
                        (proto/set-prop-op 1 proto/Gap (proto/IntValue 8))]))]
      (is (thrown-with-msg?
           Invalid_argument
           #"unsupported property"
           ((:apply-batch (apple/backend renderer)) batch))
          "stacking containers reject meaningless gap")
      (assert-equal 0 (apple/node-count renderer)
                    "a rejected overlay batch leaves no retained nodes"))))

(deftest list-and-scroll-use-the-reference-containment-contract
  (let [renderer (apple/create)
        backend (apple/backend renderer)
        batch
        (record proto/patch-batch
                (generation 1)
                (ops [(proto/create-node-op 1 proto/ListContainer)
                      (proto/create-node-op 2 proto/Scroll)
                      (proto/create-node-op 3 proto/Text)
                      (proto/create-node-op 4 proto/Text)
                      (proto/create-node-op 5 proto/Text)
                      (proto/set-prop-op 1 proto/Gap (proto/IntValue 8))
                      (proto/set-prop-op
                       1 proto/MainAlignment (proto/StringValue "end"))
                      (proto/set-prop-op
                       1 proto/CrossAlignment (proto/StringValue "stretch"))
                      (proto/insert-child-op 1 3 0)
                      (proto/insert-child-op 2 4 0)
                      (proto/insert-child-op 2 5 1)]))]
    ((:apply-batch backend) batch)
    (assert-equal [3] (apple/children renderer 1)
                  "List retains a vertical flow collection")
    (assert-equal [4 5] (apple/children renderer 2)
                  "Scroll retains multiple overlay children")))

(deftest list-has-a-closed-wire-node-name
  (let [batch
        (record proto/patch-batch
                (generation 1)
                (ops [(proto/create-node-op 1 proto/ListContainer)]))]
    (assert-equal
     "{\"generation\":1,\"ops\":[{\"op\":\"create-node\",\"id\":1,\"kind\":\"list\"}]}"
     (wire/encode-batch batch)
     "List uses the pinned Vercel Native wire name")))

(deftest spinner-uses-a-closed-leaf-contract
  (let [batch
        (record proto/patch-batch
                (generation 1)
                (ops [(proto/create-node-op 1 proto/Spinner)
                      (proto/set-prop-op
                       1 proto/SizeValue (proto/StringValue "lg"))]))]
    (assert-equal
     (str
      "{\"generation\":1,\"ops\":["
      "{\"op\":\"create-node\",\"id\":1,\"kind\":\"spinner\"},"
      "{\"op\":\"set-prop\",\"id\":1,"
      "\"property\":\"size\",\"value\":\"lg\"}]}")
     (wire/encode-batch batch)
     "Spinner and size use the pinned closed wire names")
    (doseq [size ["default" "sm" "lg" "icon"]]
      (is (proto/property-value-supported?
           proto/SizeValue (proto/StringValue size))
          "every Vercel Native control-size rung is accepted"))
    (doseq [size ["heading" "display" "large" ""]]
      (is (not (proto/property-value-supported?
                proto/SizeValue (proto/StringValue size)))
          "typography and open-ended size names are rejected"))
    (is (proto/property-supported? proto/Spinner proto/SizeValue)
        "size belongs to Spinner")
    (is (not (proto/can-contain-children? proto/Spinner))
        "Spinner is a leaf")
    (let [application
          (runtime/create (sig/scheduler) (apple/backend (apple/create)))
          spinner (runtime/create-node! application proto/Spinner)
          child (runtime/create-node! application proto/Text)]
      (is (thrown-with-msg?
           Invalid_argument
           #"cannot contain"
           (runtime/insert-child! application spinner child 0))
          "runtime rejects children on Spinner before enqueue"))))

(deftest icon-uses-a-closed-leaf-contract
  (let [batch
        (record proto/patch-batch
                (generation 1)
                (ops [(proto/create-node-op 1 proto/Icon)
                      (proto/set-prop-op
                       1 proto/IconName (proto/StringValue "search"))]))]
    (assert-equal
     (str
      "{\"generation\":1,\"ops\":["
      "{\"op\":\"create-node\",\"id\":1,\"kind\":\"icon\"},"
      "{\"op\":\"set-prop\",\"id\":1,"
      "\"property\":\"name\",\"value\":\"search\"}]}")
     (wire/encode-batch batch)
     "Icon and name use pinned closed wire names")
    (doseq
     [name
      ["alert" "archive" "arrow-down" "arrow-right" "arrow-up"
       "check" "check-circle" "chevron-down" "chevron-left" "chevron-right"
       "chevron-up" "circle-dot" "clock" "copy" "download" "edit"
       "ellipsis" "external-link" "eye" "file-text" "folder" "folder-open"
       "git-branch" "git-merge" "git-pull-request" "info" "menu" "mic"
       "moon" "music" "panel-left" "panel-right" "pause" "play" "plus"
       "refresh-cw" "repeat" "save" "search" "send" "settings" "shuffle"
       "skip-back" "skip-forward" "sun" "terminal" "trash" "volume"
       "wrench" "x" "x-circle"]]
      (is (proto/property-value-supported?
           proto/IconName (proto/StringValue name))
          "every Vercel Native built-in icon name is accepted"))
    (doseq [name ["app:logo" "app:wave-pulse" "app:status-2"]]
      (is (proto/property-value-supported?
           proto/IconName (proto/StringValue name))
          "well-shaped application icon names are structurally accepted"))
    (doseq [name ["" "unknown" "app:" "app:Wave" "app:wave_pulse"
                  "app:-wave" "app:wave-" "app:wave--pulse" "vendor:wave"]]
      (is (not (proto/property-value-supported?
                proto/IconName (proto/StringValue name)))
          "unknown built-ins and malformed namespaces are rejected"))
    (is (proto/property-supported? proto/Icon proto/IconName)
        "name belongs to Icon")
    (is (proto/property-supported? proto/Icon proto/SizeValue)
        "size belongs to Icon")
    (is (proto/property-supported? proto/Icon proto/ForegroundValue)
        "foreground belongs to Icon")
    (is (not (proto/can-contain-children? proto/Icon)) "Icon is a leaf")))

(deftest button-uses-the-closed-vercel-native-contract
  (let [batch
        (record proto/patch-batch
                (generation 1)
                (ops [(proto/create-node-op 1 proto/Button)
                      (proto/set-prop-op
                       1 proto/TextValue (proto/StringValue "Download"))
                      (proto/set-prop-op
                       1 proto/VariantValue (proto/StringValue "primary"))
                      (proto/set-prop-op
                       1 proto/SizeValue (proto/StringValue "lg"))
                      (proto/set-prop-op
                       1 proto/InlineIconName (proto/StringValue "download"))
                      (proto/set-prop-op
                       1 proto/IconPlacementValue (proto/StringValue "trailing"))
                      (proto/set-prop-op 1 proto/Selected (proto/BoolValue true))
                      (proto/set-prop-op 1 proto/Autofocus (proto/BoolValue true))
                      (proto/set-prop-op 1 proto/HoldEnabled (proto/BoolValue true))]))]
    (assert-equal
     (str
      "{\"generation\":1,\"ops\":["
      "{\"op\":\"create-node\",\"id\":1,\"kind\":\"button\"},"
      "{\"op\":\"set-prop\",\"id\":1,\"property\":\"text\",\"value\":\"Download\"},"
      "{\"op\":\"set-prop\",\"id\":1,\"property\":\"variant\",\"value\":\"primary\"},"
      "{\"op\":\"set-prop\",\"id\":1,\"property\":\"size\",\"value\":\"lg\"},"
      "{\"op\":\"set-prop\",\"id\":1,\"property\":\"icon\",\"value\":\"download\"},"
      "{\"op\":\"set-prop\",\"id\":1,\"property\":\"icon-placement\",\"value\":\"trailing\"},"
      "{\"op\":\"set-prop\",\"id\":1,\"property\":\"selected\",\"value\":true},"
      "{\"op\":\"set-prop\",\"id\":1,\"property\":\"autofocus\",\"value\":true},"
      "{\"op\":\"set-prop\",\"id\":1,\"property\":\"hold-enabled\",\"value\":true}]}")
     (wire/encode-batch batch)
     "Button properties keep exact closed wire names")
    (doseq [variant ["default" "primary" "secondary" "outline" "ghost"
                     "destructive"]]
      (is (proto/property-value-supported?
           proto/VariantValue (proto/StringValue variant))
          "every Vercel Native Button variant is accepted"))
    (doseq [variant ["link" "danger" ""]]
      (is (not (proto/property-value-supported?
                proto/VariantValue (proto/StringValue variant)))
          "non-reference Button variants are rejected"))
    (doseq [placement ["leading" "trailing"]]
      (is (proto/property-value-supported?
           proto/IconPlacementValue (proto/StringValue placement))
          "both reference icon placements are accepted"))
    (doseq [property [proto/VariantValue proto/SizeValue proto/InlineIconName
                      proto/IconPlacementValue proto/Selected proto/Autofocus
                      proto/HoldEnabled proto/AccessibilityLabel]]
      (is (proto/property-supported? proto/Button property)
          "Button admits every typed contract property"))
    (is (proto/event-supported? proto/Button (proto/Hold 1))
        "Button admits Hold events")
    (is (not (proto/can-contain-children? proto/Button))
        "Button text remains content rather than a retained child")))

(deftest retained-button-validation-explains-a-missing-accessible-name
  (let [renderer (apple/create)
        backend (apple/backend renderer)
        batch
        (record proto/patch-batch
                (generation 1)
                (ops [(proto/create-node-op 1 proto/Button)
                      (proto/set-prop-op
                       1 proto/SizeValue (proto/StringValue "icon"))
                      (proto/set-prop-op
                       1 proto/InlineIconName (proto/StringValue "plus"))]))]
    (is (thrown-with-msg?
         Invalid_argument
         #"icon-only button requires an accessibility label"
         ((:apply-batch backend) batch))
        "Button accessibility failures report the actionable contract")))

(deftest toggle-button-uses-the-closed-vercel-native-contract
  (let [batch
        (record proto/patch-batch
                (generation 1)
                (ops [(proto/create-node-op 1 proto/ToggleButton)
                      (proto/set-prop-op
                       1 proto/TextValue (proto/StringValue "Bold"))
                      (proto/set-prop-op
                       1 proto/VariantValue (proto/StringValue "outline"))
                      (proto/set-prop-op
                       1 proto/SizeValue (proto/StringValue "sm"))
                      (proto/set-prop-op
                       1 proto/InlineIconName (proto/StringValue "edit"))
                      (proto/set-prop-op
                       1 proto/IconPlacementValue (proto/StringValue "leading"))
                      (proto/set-prop-op 1 proto/Selected (proto/BoolValue false))
                      (proto/set-prop-op 1 proto/Autofocus (proto/BoolValue true))
                      (proto/set-prop-op 1 proto/HoldEnabled (proto/BoolValue true))]))]
    (is (proto/event-supported?
         proto/ToggleButton (proto/ToggleChanged 1 true))
        "ToggleButton activation emits on-toggle with the next state")
    (is (proto/event-supported? proto/ToggleButton (proto/Hold 1))
        "ToggleButton supports the reference hold gesture")
    (is (not (proto/event-supported? proto/ToggleButton (proto/Press 1)))
        "ToggleButton does not expose Button on-press activation")
    (doseq [property [proto/TextValue proto/VariantValue proto/SizeValue
                      proto/InlineIconName proto/IconPlacementValue
                      proto/Selected proto/Autofocus proto/HoldEnabled
                      proto/Enabled proto/AccessibilityLabel]]
      (is (proto/property-supported? proto/ToggleButton property)
          "ToggleButton admits the exact shared control properties"))
    (is (not (proto/can-contain-children? proto/ToggleButton))
        "ToggleButton content is one text run")
    (is (=
         (str
          "{\"generation\":1,\"ops\":["
          "{\"op\":\"create-node\",\"id\":1,\"kind\":\"toggle-button\"},"
          "{\"op\":\"set-prop\",\"id\":1,\"property\":\"text\",\"value\":\"Bold\"},"
          "{\"op\":\"set-prop\",\"id\":1,\"property\":\"variant\",\"value\":\"outline\"},"
          "{\"op\":\"set-prop\",\"id\":1,\"property\":\"size\",\"value\":\"sm\"},"
          "{\"op\":\"set-prop\",\"id\":1,\"property\":\"icon\",\"value\":\"edit\"},"
          "{\"op\":\"set-prop\",\"id\":1,\"property\":\"icon-placement\",\"value\":\"leading\"},"
          "{\"op\":\"set-prop\",\"id\":1,\"property\":\"selected\",\"value\":false},"
          "{\"op\":\"set-prop\",\"id\":1,\"property\":\"autofocus\",\"value\":true},"
          "{\"op\":\"set-prop\",\"id\":1,\"property\":\"hold-enabled\",\"value\":true}]}")
         (wire/encode-batch batch))
        "ToggleButton has one stable typed wire representation")))

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
    (runtime/set-prop!
     application third-child proto/TextValue (proto/StringValue "Move"))
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
    (runtime/set-prop!
     application button proto/TextValue (proto/StringValue "Increment"))
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
        checkbox (runtime/create-node! application proto/Checkbox)]
    (runtime/set-prop!
     application button proto/TextValue (proto/StringValue "Continue"))
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
                (ops [(proto/create-node-op 1 proto/SwitchControl)
                      (proto/create-node-op 2 proto/Text)
                      (proto/insert-child-op 1 2 0)]))]
    (is (thrown-with-msg?
         Invalid_argument
         #"cannot contain"
         ((:apply-batch backend) invalid-batch))
        "backend keeps native switch implementation parts off-tree")))

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
        switch-control (runtime/create-node! application proto/SwitchControl)
        first-child (runtime/create-node! application proto/Text)
        _second-child (runtime/create-node! application proto/Text)]
    (is (thrown-with-msg?
         Invalid_argument
         #"cannot contain"
         (runtime/insert-child! application switch-control first-child 0))
        "switch controls are direct retained leaves"))
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
