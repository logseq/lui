(ns lui.runtime-test
  (:require [clojure.test :refer [deftest is testing]]
            [signal.core :as sig]
            [lui.protocol :as proto
             :refer [StringValue SetProp MoveChild Press]]
            [lui.wire :as wire]
            [lui.runtime :as runtime]
            [lui.backend.apple :as apple
             :refer [AppleRow AppleLabel AppleTextInput AppleResizable AppleSplit
                     AppleContextMenu]]
            [lui.backend.flutter :as flutter
             :refer [FlutterFlexRow FlutterParagraph FlutterWidgetIsland
                     FlutterResizable FlutterSplit FlutterContextMenu]]))

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

(deftest text-entry-patch-uses-direct-reference-wire-names
  (let [batch
        (record proto/patch-batch
                (generation 1)
                (ops [(proto/create-node-op 1 proto/TextField)
                      (proto/create-node-op 2 proto/Input)
                      (proto/create-node-op 3 proto/SearchField)
                      (proto/create-node-op 4 proto/Textarea)
                      (proto/set-prop-op
                       1 proto/TextValue (proto/StringValue "Draft"))
                      (proto/set-prop-op
                       2 proto/PlaceholderValue (proto/StringValue "Email"))
                      (proto/set-prop-op
                       3 proto/Autofocus (proto/BoolValue true))
                      (proto/set-prop-op
                       4 proto/SubmitOnEnter (proto/BoolValue true))]))]
    (assert-equal
     (str
      "{\"generation\":1,\"ops\":["
      "{\"op\":\"create-node\",\"id\":1,\"kind\":\"text-field\"},"
      "{\"op\":\"create-node\",\"id\":2,\"kind\":\"input\"},"
      "{\"op\":\"create-node\",\"id\":3,\"kind\":\"search-field\"},"
      "{\"op\":\"create-node\",\"id\":4,\"kind\":\"textarea\"},"
      "{\"op\":\"set-prop\",\"id\":1,"
      "\"property\":\"text\",\"value\":\"Draft\"},"
      "{\"op\":\"set-prop\",\"id\":2,"
      "\"property\":\"placeholder\",\"value\":\"Email\"},"
      "{\"op\":\"set-prop\",\"id\":3,"
      "\"property\":\"autofocus\",\"value\":true},"
      "{\"op\":\"set-prop\",\"id\":4,"
      "\"property\":\"submit-on-enter\",\"value\":true}]}")
     (wire/encode-batch batch)
     "form controls use the native host's closed wire vocabulary")))

(deftest picker-primitives-use-closed-reference-wire-names
  (let [batch
        (record proto/patch-batch
                (generation 1)
                (ops [(proto/create-node-op 1 proto/Select)
                      (proto/create-node-op 2 proto/Combobox)
                      (proto/create-node-op 3 proto/DropdownMenu)
                      (proto/create-node-op 4 proto/MenuItem)
                      (proto/set-prop-op
                       1 proto/TextValue (proto/StringValue "Production"))
                      (proto/set-prop-op
                       2 proto/SubmitEnabled (proto/BoolValue true))
                      (proto/set-prop-op
                       3 proto/AnchorValue (proto/StringValue "below"))
                      (proto/set-prop-op
                       3 proto/AnchorAlignmentValue
                       (proto/StringValue "stretch"))
                      (proto/set-prop-op
                       3 proto/AnchorOffset (proto/FloatValue 6.0))
                      (proto/set-prop-op
                       4 proto/Selected (proto/BoolValue true))]))]
    (assert-equal
     (str
      "{\"generation\":1,\"ops\":["
      "{\"op\":\"create-node\",\"id\":1,\"kind\":\"select\"},"
      "{\"op\":\"create-node\",\"id\":2,\"kind\":\"combobox\"},"
      "{\"op\":\"create-node\",\"id\":3,\"kind\":\"dropdown-menu\"},"
      "{\"op\":\"create-node\",\"id\":4,\"kind\":\"menu-item\"},"
      "{\"op\":\"set-prop\",\"id\":1,\"property\":\"text\","
      "\"value\":\"Production\"},"
      "{\"op\":\"set-prop\",\"id\":2,"
      "\"property\":\"submit-enabled\",\"value\":true},"
      "{\"op\":\"set-prop\",\"id\":3,"
      "\"property\":\"anchor\",\"value\":\"below\"},"
      "{\"op\":\"set-prop\",\"id\":3,"
      "\"property\":\"anchor-alignment\",\"value\":\"stretch\"},"
      "{\"op\":\"set-prop\",\"id\":3,"
      "\"property\":\"anchor-offset\",\"value\":6.0},"
      "{\"op\":\"set-prop\",\"id\":4,"
      "\"property\":\"selected\",\"value\":true}]}" )
     (wire/encode-batch batch)
     "picker primitives keep the pinned wire vocabulary")))

(deftest picker-primitives-have-distinct-retained-contracts
  (doseq [property
          [proto/TextValue proto/PlaceholderValue proto/Enabled
           proto/PressEnabled]]
    (is (proto/property-supported? proto/Select property)
        "select admits only trigger state"))
  (doseq [property
          [proto/TextValue proto/PlaceholderValue proto/Enabled
           proto/PressEnabled proto/SubmitEnabled]]
    (is (proto/property-supported? proto/Combobox property)
        "combobox admits editable trigger state"))
  (doseq [property
          [proto/AnchorValue proto/AnchorAlignmentValue proto/AnchorOffset
           proto/MinWidth]]
    (is (proto/property-supported? proto/DropdownMenu property)
        "dropdown menu admits anchored surface state"))
  (doseq [property
          [proto/TextValue proto/InlineIconName proto/Enabled proto/Selected
           proto/PressEnabled]]
    (is (proto/property-supported? proto/MenuItem property)
        "menu item admits row state"))
  (is (proto/can-contain-children? proto/DropdownMenu)
      "dropdown menu retains menu item children")
  (doseq [kind [proto/Select proto/Combobox proto/MenuItem]]
    (is (proto/can-contain-children? kind)
        "picker leaves may retain ContextMenu metadata")
    (is (not (proto/child-kind-supported? kind proto/Text))
        "picker visible content remains property-owned"))
  (is (proto/event-supported? proto/Select (proto/Press 1))
      "select activation opens through on-press")
  (is (proto/event-supported? proto/Combobox (proto/TextChanged 2 "q"))
      "combobox edits through on-input")
  (is (proto/event-supported? proto/Combobox (proto/Submit 2))
      "combobox Enter may submit")
  (is (proto/event-supported? proto/DropdownMenu (proto/Dismiss 3))
      "dropdown surface reports native dismissal")
  (is (proto/event-supported? proto/MenuItem (proto/Press 4))
      "menu item commits through on-press")
  (is (proto/property-value-supported?
       proto/AnchorValue (proto/StringValue "below"))
      "below is a legal anchor")
  (is (not (proto/property-value-supported?
            proto/AnchorValue (proto/StringValue "sideways")))
      "anchor direction is closed")
  (is (proto/property-value-supported?
       proto/AnchorAlignmentValue (proto/StringValue "stretch"))
      "stretch is a legal anchored alignment")
  (is (not (proto/property-value-supported?
            proto/AnchorAlignmentValue (proto/StringValue "center")))
      "the pinned anchored alignment vocabulary excludes center"))

(deftest tooltip-has-the-pinned-static-and-anchored-contract
  (let [batch
        (record proto/patch-batch
                (generation 1)
                (ops [(proto/create-node-op 1 proto/Tooltip)
                      (proto/set-prop-op
                       1 proto/TextValue
                       (proto/StringValue "Bold the selection"))
                      (proto/set-prop-op
                       1 proto/AnchorValue (proto/StringValue "above"))
                      (proto/set-prop-op
                       1 proto/AnchorAlignmentValue (proto/StringValue "end"))
                      (proto/set-prop-op
                       1 proto/AnchorOffset (proto/FloatValue 8.0))
                      (proto/set-prop-op
                       1 proto/TooltipDelay (proto/IntValue 250))]))]
    (assert-equal
     (str
      "{\"generation\":1,\"ops\":["
      "{\"op\":\"create-node\",\"id\":1,\"kind\":\"tooltip\"},"
      "{\"op\":\"set-prop\",\"id\":1,\"property\":\"text\","
      "\"value\":\"Bold the selection\"},"
      "{\"op\":\"set-prop\",\"id\":1,\"property\":\"anchor\","
      "\"value\":\"above\"},"
      "{\"op\":\"set-prop\",\"id\":1,"
      "\"property\":\"anchor-alignment\",\"value\":\"end\"},"
      "{\"op\":\"set-prop\",\"id\":1,"
      "\"property\":\"anchor-offset\",\"value\":8.0},"
      "{\"op\":\"set-prop\",\"id\":1,"
      "\"property\":\"tooltip-delay\",\"value\":250}]}" )
     (wire/encode-batch batch)
     "Tooltip uses only the pinned five-property wire vocabulary")
    (doseq [property
            [proto/TextValue proto/AnchorValue proto/AnchorAlignmentValue
             proto/AnchorOffset proto/TooltipDelay]]
      (is (proto/property-supported? proto/Tooltip property)
          "Tooltip admits its exact public state"))
    (doseq [property
            [proto/Gap proto/PaddingValue proto/WidthValue proto/ForegroundValue
             proto/StyleClass]]
      (is (not (proto/property-supported? proto/Tooltip property))
          "Tooltip rejects common surface properties"))
    (is (not (proto/can-contain-children? proto/Tooltip))
        "Tooltip is a text leaf")
    (is (not (proto/event-supported? proto/Tooltip (proto/Press 1)))
        "Tooltip visibility never emits an application event")
    (is (proto/property-value-supported?
         proto/TooltipDelay (proto/IntValue 0))
        "zero opts into immediate hover reveal")
    (is (proto/property-value-supported?
         proto/TooltipDelay (proto/IntValue 2147483647))
        "the signed 32-bit boundary is legal")
    (is (not (proto/property-value-supported?
              proto/TooltipDelay (proto/IntValue -1)))
        "negative delay is invalid")
    (is (not (proto/property-value-supported?
              proto/TooltipDelay (proto/IntValue 2147483648)))
        "delay cannot overflow the host contract")
    (let [renderer (apple/create)
          invalid
          (record proto/patch-batch
                  (generation 1)
                  (ops [(proto/create-node-op 1 proto/Tooltip)
                        (proto/set-prop-op
                         1 proto/TextValue (proto/StringValue "Static"))
                        (proto/set-prop-op
                         1 proto/TooltipDelay (proto/IntValue 250))]))]
      (is (thrown-with-msg?
           Invalid_argument
           #"node properties conflict"
           ((:apply-batch (apple/backend renderer)) invalid))
          "tooltip-delay without anchor is rejected")
      (assert-equal 0 (apple/node-count renderer)
                    "dependent-property failure is atomic"))))

(deftest accordion-has-the-pinned-controlled-disclosure-contract
  (let [batch
        (record proto/patch-batch
                (generation 1)
                (ops [(proto/create-node-op 1 proto/Accordion)
                      (proto/set-prop-op
                       1 proto/TextValue (proto/StringValue "Details"))
                      (proto/set-prop-op
                       1 proto/Selected (proto/BoolValue true))
                      (proto/set-prop-op
                       1 proto/ToggleEnabled (proto/BoolValue true))
                      (proto/set-prop-op
                       1 proto/HeightValue (proto/IntValue 180))]))]
    (assert-equal
     (str
      "{\"generation\":1,\"ops\":["
      "{\"op\":\"create-node\",\"id\":1,\"kind\":\"accordion\"},"
      "{\"op\":\"set-prop\",\"id\":1,\"property\":\"text\","
      "\"value\":\"Details\"},"
      "{\"op\":\"set-prop\",\"id\":1,\"property\":\"selected\","
      "\"value\":true},"
      "{\"op\":\"set-prop\",\"id\":1,"
      "\"property\":\"toggle-enabled\",\"value\":true},"
      "{\"op\":\"set-prop\",\"id\":1,\"property\":\"height\","
      "\"value\":180}]}" )
     (wire/encode-batch batch)
     "Accordion uses only the pinned four-property wire vocabulary")
    (doseq [property
            [proto/TextValue proto/Selected proto/ToggleEnabled
             proto/HeightValue]]
      (is (proto/property-supported? proto/Accordion property)
          "Accordion admits its exact public state"))
    (doseq [property
            [proto/Gap proto/PaddingValue proto/WidthValue proto/Enabled
             proto/StyleClass]]
      (is (not (proto/property-supported? proto/Accordion property))
          "Accordion rejects API beyond the reference contract"))
    (is (proto/can-contain-children? proto/Accordion)
        "Accordion retains disclosure content")
    (is (proto/event-supported?
         proto/Accordion (proto/ToggleChanged 1 false))
        "Accordion requests model-owned state through on-toggle")))

(deftest dialog-has-the-pinned-modal-surface-contract
  (let [batch
        (record proto/patch-batch
                (generation 1)
                (ops [(proto/create-node-op 1 proto/Dialog)
                      (proto/set-prop-op
                       1 proto/TextValue (proto/StringValue "Rename note"))
                      (proto/set-prop-op 1 proto/WidthValue (proto/IntValue 380))
                      (proto/set-prop-op 1 proto/HeightValue (proto/IntValue 240))
                      (proto/set-prop-op 1 proto/PaddingValue (proto/IntValue 24))]))]
    (assert-equal
     (str
      "{\"generation\":1,\"ops\":["
      "{\"op\":\"create-node\",\"id\":1,\"kind\":\"dialog\"},"
      "{\"op\":\"set-prop\",\"id\":1,\"property\":\"text\","
      "\"value\":\"Rename note\"},"
      "{\"op\":\"set-prop\",\"id\":1,\"property\":\"width\",\"value\":380},"
      "{\"op\":\"set-prop\",\"id\":1,\"property\":\"height\",\"value\":240},"
      "{\"op\":\"set-prop\",\"id\":1,\"property\":\"padding\",\"value\":24}]}" )
     (wire/encode-batch batch)
     "dialog uses the pinned closed wire vocabulary")
    (doseq [property
            [proto/TextValue proto/WidthValue proto/HeightValue proto/PaddingValue]]
      (is (proto/property-supported? proto/Dialog property)
          "dialog admits only its authored surface state"))
    (doseq [property [proto/Gap proto/MainAlignment proto/CrossAlignment
                      proto/Selected proto/Enabled]]
      (is (not (proto/property-supported? proto/Dialog property))
          "dialog rejects flow and control state"))
    (is (proto/can-contain-children? proto/Dialog)
        "dialog stacks retained content children")
    (is (proto/event-supported? proto/Dialog (proto/Dismiss 1))
        "dialog reports native dismissal")
    (let [renderer (apple/create)
          invalid
          (record proto/patch-batch
                  (generation 1)
                  (ops [(proto/create-node-op 1 proto/Dialog)]))]
      (is (thrown-with-msg?
           Invalid_argument
           #"node properties conflict"
           ((:apply-batch (apple/backend renderer)) invalid))
          "dialog requires a non-empty accessible title")
      (assert-equal 0 (apple/node-count renderer)
                    "an invalid dialog batch is atomic"))))

(deftest drawer-and-sheet-have-the-pinned-edge-surface-contract
  (let [batch
        (record proto/patch-batch
                (generation 1)
                (ops [(proto/create-node-op 1 proto/Drawer)
                      (proto/set-prop-op
                       1 proto/TextValue (proto/StringValue "Filters"))
                      (proto/set-prop-op 1 proto/HeightValue (proto/IntValue 260))
                      (proto/set-prop-op 1 proto/PaddingValue (proto/IntValue 24))
                      (proto/create-node-op 2 proto/Sheet)
                      (proto/set-prop-op
                       2 proto/TextValue (proto/StringValue "Share"))
                      (proto/set-prop-op 2 proto/WidthValue (proto/IntValue 320))
                      (proto/set-prop-op 2 proto/PaddingValue (proto/IntValue 24))]))]
    (assert-equal
     (str
      "{\"generation\":1,\"ops\":["
      "{\"op\":\"create-node\",\"id\":1,\"kind\":\"drawer\"},"
      "{\"op\":\"set-prop\",\"id\":1,\"property\":\"text\","
      "\"value\":\"Filters\"},"
      "{\"op\":\"set-prop\",\"id\":1,\"property\":\"height\",\"value\":260},"
      "{\"op\":\"set-prop\",\"id\":1,\"property\":\"padding\",\"value\":24},"
      "{\"op\":\"create-node\",\"id\":2,\"kind\":\"sheet\"},"
      "{\"op\":\"set-prop\",\"id\":2,\"property\":\"text\","
      "\"value\":\"Share\"},"
      "{\"op\":\"set-prop\",\"id\":2,\"property\":\"width\",\"value\":320},"
      "{\"op\":\"set-prop\",\"id\":2,\"property\":\"padding\",\"value\":24}]}")
     (wire/encode-batch batch)
     "edge surfaces use the pinned closed wire vocabulary")
    (doseq [kind [proto/Drawer proto/Sheet]]
      (doseq [property
              [proto/TextValue proto/WidthValue proto/HeightValue proto/PaddingValue]]
        (is (proto/property-supported? kind property)
            "edge surfaces admit the exact Vercel Native attributes"))
      (doseq [property [proto/Gap proto/MainAlignment proto/CrossAlignment
                        proto/Selected proto/Enabled]]
        (is (not (proto/property-supported? kind property))
            "edge surfaces reject flow and control state"))
      (is (proto/can-contain-children? kind)
          "edge surfaces retain stacking content")
      (is (proto/event-supported? kind (proto/Dismiss 1))
          "edge surfaces report native dismissal"))
    (let [renderer (apple/create)
          invalid
          (record proto/patch-batch
                  (generation 1)
                  (ops [(proto/create-node-op 1 proto/Drawer)
                        (proto/set-prop-op 1 proto/Gap (proto/IntValue 8))
                        (proto/create-node-op 2 proto/Sheet)]))]
      (is (thrown-with-msg?
           Invalid_argument
           #"unsupported property value|property is not supported|node properties conflict"
           ((:apply-batch (apple/backend renderer)) invalid))
          "missing titles and gap are rejected atomically")
      (assert-equal 0 (apple/node-count renderer)
                    "an invalid edge-surface batch leaves no retained nodes"))))

(deftest tabs-is-a-controlled-horizontal-trigger-container
  (let [batch
        (record proto/patch-batch
                (generation 1)
                (ops [(proto/create-node-op 1 proto/Tabs)
                      (proto/create-node-op 2 proto/Button)
                      (proto/set-prop-op 1 proto/Gap (proto/IntValue 4))
                      (proto/set-prop-op
                       2 proto/TextValue (proto/StringValue "Overview"))
                      (proto/set-prop-op
                       2 proto/Selected (proto/BoolValue true))
                      (proto/insert-child-op 1 2 0)]))]
    (assert-equal
     (str
      "{\"generation\":1,\"ops\":["
      "{\"op\":\"create-node\",\"id\":1,\"kind\":\"tabs\"},"
      "{\"op\":\"create-node\",\"id\":2,\"kind\":\"button\"},"
      "{\"op\":\"set-prop\",\"id\":1,\"property\":\"gap\",\"value\":4},"
      "{\"op\":\"set-prop\",\"id\":2,\"property\":\"text\","
      "\"value\":\"Overview\"},"
      "{\"op\":\"set-prop\",\"id\":2,\"property\":\"selected\","
      "\"value\":true},"
      "{\"op\":\"insert-child\",\"parent\":1,\"child\":2,\"index\":0}]}" )
     (wire/encode-batch batch)
     "Tabs adds one closed container kind without a second trigger API"))
  (is (proto/can-contain-children? proto/Tabs)
      "Tabs retains its direct trigger children")
  (doseq [property
          [proto/Gap proto/MainAlignment proto/CrossAlignment
           proto/PaddingValue proto/GrowValue proto/WidthValue
           proto/MinWidth proto/MaxWidth]]
    (is (proto/property-supported? proto/Tabs property)
        "Tabs admits the reference container surface"))
  (doseq [property [proto/TextValue proto/Selected proto/Enabled]]
    (is (not (proto/property-supported? proto/Tabs property))
        "Tabs does not own trigger content or selection"))
  (is (not (proto/event-supported? proto/Tabs (proto/Press 1)))
      "Tabs introduces no container event"))

(deftest button-and-toggle-groups-own-layout-not-selection
  (let [batch
        (record proto/patch-batch
                (generation 1)
                (ops [(proto/create-node-op 1 proto/ButtonGroup)
                      (proto/create-node-op 2 proto/ToggleGroup)
                      (proto/create-node-op 3 proto/Button)
                      (proto/create-node-op 4 proto/ToggleButton)
                      (proto/set-prop-op 1 proto/Gap (proto/IntValue 4))
                      (proto/set-prop-op
                       2 proto/MainAlignment (proto/StringValue "end"))
                      (proto/insert-child-op 1 3 0)
                      (proto/insert-child-op 2 4 0)]))]
    (assert-equal
     (str
      "{\"generation\":1,\"ops\":["
      "{\"op\":\"create-node\",\"id\":1,\"kind\":\"button-group\"},"
      "{\"op\":\"create-node\",\"id\":2,\"kind\":\"toggle-group\"},"
      "{\"op\":\"create-node\",\"id\":3,\"kind\":\"button\"},"
      "{\"op\":\"create-node\",\"id\":4,\"kind\":\"toggle-button\"},"
      "{\"op\":\"set-prop\",\"id\":1,\"property\":\"gap\",\"value\":4},"
      "{\"op\":\"set-prop\",\"id\":2,\"property\":\"main\","
      "\"value\":\"end\"},"
      "{\"op\":\"insert-child\",\"parent\":1,\"child\":3,\"index\":0},"
      "{\"op\":\"insert-child\",\"parent\":2,\"child\":4,\"index\":0}]}" )
     (wire/encode-batch batch)
     "both groups have closed wire kinds without a second control API"))
  (doseq [kind [proto/ButtonGroup proto/ToggleGroup]]
    (is (proto/can-contain-children? kind)
        "action groups retain direct controls")
    (doseq [property
            [proto/Gap proto/MainAlignment proto/CrossAlignment
             proto/PaddingValue proto/GrowValue proto/WidthValue
             proto/MinWidth proto/MaxWidth]]
      (is (proto/property-supported? kind property)
          "groups admit the reference horizontal-container surface"))
    (doseq [property [proto/TextValue proto/Selected proto/Enabled]]
      (is (not (proto/property-supported? kind property))
          "groups do not own control content, selection, or enabled state"))
    (is (not (proto/event-supported? kind (proto/Press 1)))
        "groups introduce no press event")
    (is (not (proto/event-supported? kind (proto/ToggleChanged 1 true)))
        "groups introduce no toggle event")))

(deftest breadcrumb-and-pagination-are-stateless-composition-containers
  (let [batch
        (record proto/patch-batch
                (generation 1)
                (ops [(proto/create-node-op 1 proto/Breadcrumb)
                      (proto/create-node-op 2 proto/Text)
                      (proto/create-node-op 3 proto/Pagination)
                      (proto/create-node-op 4 proto/Button)
                      (proto/set-prop-op 1 proto/Gap (proto/IntValue 4))
                      (proto/set-prop-op
                       2 proto/TextValue (proto/StringValue "Home"))
                      (proto/set-prop-op
                       2 proto/PressEnabled (proto/BoolValue true))
                      (proto/set-prop-op 3 proto/Gap (proto/IntValue 2))
                      (proto/set-prop-op
                       4 proto/TextValue (proto/StringValue "1"))
                      (proto/set-prop-op
                       4 proto/Selected (proto/BoolValue true))
                      (proto/insert-child-op 1 2 0)
                      (proto/insert-child-op 3 4 0)]))]
    (assert-equal
     (str
      "{\"generation\":1,\"ops\":["
      "{\"op\":\"create-node\",\"id\":1,\"kind\":\"breadcrumb\"},"
      "{\"op\":\"create-node\",\"id\":2,\"kind\":\"text\"},"
      "{\"op\":\"create-node\",\"id\":3,\"kind\":\"pagination\"},"
      "{\"op\":\"create-node\",\"id\":4,\"kind\":\"button\"},"
      "{\"op\":\"set-prop\",\"id\":1,\"property\":\"gap\",\"value\":4},"
      "{\"op\":\"set-prop\",\"id\":2,\"property\":\"text\","
      "\"value\":\"Home\"},"
      "{\"op\":\"set-prop\",\"id\":2,\"property\":\"press-enabled\","
      "\"value\":true},"
      "{\"op\":\"set-prop\",\"id\":3,\"property\":\"gap\",\"value\":2},"
      "{\"op\":\"set-prop\",\"id\":4,\"property\":\"text\",\"value\":\"1\"},"
      "{\"op\":\"set-prop\",\"id\":4,\"property\":\"selected\","
      "\"value\":true},"
      "{\"op\":\"insert-child\",\"parent\":1,\"child\":2,\"index\":0},"
      "{\"op\":\"insert-child\",\"parent\":3,\"child\":4,\"index\":0}]}" )
     (wire/encode-batch batch)
     "navigation containers and pressable Text use the closed wire vocabulary"))
  (doseq [kind [proto/Breadcrumb proto/Pagination]]
    (is (proto/can-contain-children? kind)
        "navigation containers retain their composed children")
    (doseq [property
            [proto/Gap proto/MainAlignment proto/CrossAlignment
             proto/PaddingValue proto/GrowValue proto/WidthValue
             proto/MinWidth proto/MaxWidth proto/AccessibilityLabel]]
      (is (proto/property-supported? kind property)
          "navigation containers admit the horizontal-container surface"))
    (doseq [property [proto/TextValue proto/Selected proto/Enabled]]
      (is (not (proto/property-supported? kind property))
          "navigation containers own no child state"))
    (is (not (proto/event-supported? kind (proto/Press 1)))
        "navigation containers introduce no event"))
  (is (proto/property-supported? proto/Text proto/PressEnabled)
      "Text can opt into the reference's general press capability")
  (is (proto/event-supported? proto/Text (proto/Press 2))
      "pressable Text dispatches the ordinary Press event"))

(deftest list-item-has-the-complete-reference-contract
  (let [batch
        (record proto/patch-batch
                (generation 1)
                (ops [(proto/create-node-op 1 proto/ListItem)
                      (proto/set-prop-op
                       1 proto/TextValue
                       (proto/StringValue "Quarterly report.md"))
                      (proto/set-prop-op
                       1 proto/InlineIconName
                       (proto/StringValue "file-text"))
                      (proto/set-prop-op
                       1 proto/Selected
                       (proto/BoolValue true))
                      (proto/set-prop-op
                       1 proto/DoublePressEnabled
                       (proto/BoolValue true))
                      (proto/set-prop-op
                       1 proto/SubmitEnabled
                       (proto/BoolValue true))]))]
    (assert-equal
     (str
      "{\"generation\":1,\"ops\":["
      "{\"op\":\"create-node\",\"id\":1,\"kind\":\"list-item\"},"
      "{\"op\":\"set-prop\",\"id\":1,\"property\":\"text\","
      "\"value\":\"Quarterly report.md\"},"
      "{\"op\":\"set-prop\",\"id\":1,\"property\":\"icon\","
      "\"value\":\"file-text\"},"
      "{\"op\":\"set-prop\",\"id\":1,\"property\":\"selected\","
      "\"value\":true},"
      "{\"op\":\"set-prop\",\"id\":1,"
      "\"property\":\"double-press-enabled\",\"value\":true},"
      "{\"op\":\"set-prop\",\"id\":1,"
      "\"property\":\"submit-enabled\",\"value\":true}]}" )
     (wire/encode-batch batch)
     "list-item uses the pinned wire vocabulary"))
  (doseq [property
          [proto/TextValue proto/InlineIconName proto/Selected proto/Enabled
           proto/PressEnabled proto/DoublePressEnabled proto/SubmitEnabled]]
    (is (proto/property-supported? proto/ListItem property)
        "list-item admits its complete row contract"))
  (is (proto/can-contain-children? proto/ListItem)
      "list-item may retain custom row children instead of text")
  (is (proto/event-supported? proto/ListItem (proto/Press 1))
      "Space and click select through on-press")
  (is (proto/event-supported? proto/ListItem (proto/DoublePress 1))
      "double click dispatches the additive primary action")
  (is (proto/event-supported? proto/ListItem (proto/Submit 1))
      "Enter dispatches the primary action when configured"))

(deftest list-item-rejects-mixed-or-empty-content
  (let [renderer (apple/create)
        backend (apple/backend renderer)
        mixed
        (record proto/patch-batch
                (generation 1)
                (ops [(proto/create-node-op 1 proto/ListItem)
                      (proto/create-node-op 2 proto/Text)
                      (proto/set-prop-op
                       1 proto/TextValue (proto/StringValue "Mixed"))
                      (proto/set-prop-op
                       2 proto/TextValue (proto/StringValue "Child"))
                      (proto/insert-child-op 1 2 0)]))]
    (is (thrown-with-msg?
         Invalid_argument
         #"list-item accepts text or children, not both"
         ((:apply-batch backend) mixed))
        "the wire boundary rejects ambiguous row content"))
  (let [renderer (apple/create)
        backend (apple/backend renderer)
        empty-row
        (record proto/patch-batch
                (generation 1)
                (ops [(proto/create-node-op 1 proto/ListItem)]))]
    (is (thrown-with-msg?
         Invalid_argument
         #"list-item requires text or children"
         ((:apply-batch backend) empty-row))
        "an unnamed empty interactive row is rejected")))

(deftest avatar-uses-a-registered-image-id-with-initials-fallback
  (let [batch
        (record proto/patch-batch
                (generation 1)
                (ops [(proto/create-node-op 1 proto/Avatar)
                      (proto/set-prop-op
                       1 proto/TextValue (proto/StringValue "ZN"))
                      (proto/set-prop-op
                       1 proto/ImageIdValue (proto/IntValue 7))
                      (proto/set-prop-op
                       1 proto/SourceX (proto/FloatValue 4.0))
                      (proto/set-prop-op
                       1 proto/SourceY (proto/FloatValue 8.0))
                      (proto/set-prop-op
                       1 proto/SourceWidth (proto/FloatValue 32.0))
                      (proto/set-prop-op
                       1 proto/SourceHeight (proto/FloatValue 24.0))
                      (proto/set-prop-op
                       1 proto/AccessibilityLabel
                       (proto/StringValue "Profile picture"))]))]
    (assert-equal
     (str
      "{\"generation\":1,\"ops\":["
      "{\"op\":\"create-node\",\"id\":1,\"kind\":\"avatar\"},"
      "{\"op\":\"set-prop\",\"id\":1,\"property\":\"text\","
      "\"value\":\"ZN\"},"
      "{\"op\":\"set-prop\",\"id\":1,\"property\":\"image\","
      "\"value\":7},"
      "{\"op\":\"set-prop\",\"id\":1,\"property\":\"source-x\","
      "\"value\":4.0},"
      "{\"op\":\"set-prop\",\"id\":1,\"property\":\"source-y\","
      "\"value\":8.0},"
      "{\"op\":\"set-prop\",\"id\":1,\"property\":\"source-width\","
      "\"value\":32.0},"
      "{\"op\":\"set-prop\",\"id\":1,\"property\":\"source-height\","
      "\"value\":24.0},"
      "{\"op\":\"set-prop\",\"id\":1,"
      "\"property\":\"accessibility-label\","
      "\"value\":\"Profile picture\"}]}" )
     (wire/encode-batch batch)
     "avatar keeps the pinned registered-image vocabulary"))
  (doseq [property
          [proto/TextValue proto/ImageIdValue proto/SourceX proto/SourceY
           proto/SourceWidth proto/SourceHeight proto/AccessibilityLabel]]
    (is (proto/property-supported? proto/Avatar property)
        "avatar admits only its image and fallback contract"))
  (is (not (proto/can-contain-children? proto/Avatar))
      "avatar is one retained display leaf")
  (is (not (proto/property-supported? proto/Avatar proto/WidthValue))
      "avatar does not inherit extra surface API")
  (is (not (proto/property-value-supported?
            proto/ImageIdValue (proto/IntValue -1)))
      "negative image ids are rejected before a backend sees them"))

(deftest avatar-source-crop-is-an-atomic-valid-rectangle
  (let [partial-renderer (apple/create)
        partial-backend (apple/backend partial-renderer)
        partial
        (record proto/patch-batch
                (generation 1)
                (ops [(proto/create-node-op 1 proto/Avatar)
                      (proto/set-prop-op
                       1 proto/TextValue (proto/StringValue "ZN"))
                      (proto/set-prop-op
                       1 proto/ImageIdValue (proto/IntValue 7))
                      (proto/set-prop-op
                       1 proto/SourceX (proto/FloatValue 4.0))]))]
    (is (thrown-with-msg?
         Invalid_argument
         #"avatar source crop requires all four coordinates"
         ((:apply-batch partial-backend) partial))
        "partial atlas declarations fail atomically"))
  (let [invalid-renderer (apple/create)
        invalid-backend (apple/backend invalid-renderer)
        invalid
        (record proto/patch-batch
                (generation 1)
                (ops [(proto/create-node-op 1 proto/Avatar)
                      (proto/set-prop-op
                       1 proto/TextValue (proto/StringValue "ZN"))
                      (proto/set-prop-op
                       1 proto/ImageIdValue (proto/IntValue 7))
                      (proto/set-prop-op
                       1 proto/SourceX (proto/FloatValue 0.0))
                      (proto/set-prop-op
                       1 proto/SourceY (proto/FloatValue 0.0))
                      (proto/set-prop-op
                       1 proto/SourceWidth (proto/FloatValue 0.0))
                      (proto/set-prop-op
                       1 proto/SourceHeight (proto/FloatValue 24.0))]))]
    (is (thrown-with-msg?
         Invalid_argument
         #"avatar source crop dimensions must be positive"
         ((:apply-batch invalid-backend) invalid))
        "zero-area atlas declarations fail atomically")))

(deftest image-and-media-surface-use-stable-resource-identities
  (let [batch
        (record proto/patch-batch
                (generation 1)
                (ops [(proto/create-node-op 1 proto/Row)
                      (proto/create-node-op 2 proto/Image)
                      (proto/create-node-op 3 proto/MediaSurface)
                      (proto/set-prop-op
                       2 proto/ImageIdValue (proto/IntValue 7))
                      (proto/set-prop-op
                       2 proto/SourceX (proto/FloatValue 8.0))
                      (proto/set-prop-op
                       2 proto/SourceY (proto/FloatValue 4.0))
                      (proto/set-prop-op
                       2 proto/SourceWidth (proto/FloatValue 40.0))
                      (proto/set-prop-op
                       2 proto/SourceHeight (proto/FloatValue 24.0))
                      (proto/set-prop-op
                       2 proto/WidthValue (proto/IntValue 160))
                      (proto/set-prop-op
                       2 proto/HeightValue (proto/IntValue 96))
                      (proto/set-prop-op
                       3 proto/SurfaceIdValue (proto/IntValue 11))
                      (proto/set-prop-op
                       3 proto/GrowValue (proto/FloatValue 1.0))
                      (proto/set-prop-op
                       3 proto/HeightValue (proto/IntValue 96))
                      (proto/insert-child-op 1 2 0)
                      (proto/insert-child-op 1 3 1)]))]
    (assert-equal
     (str
      "{\"generation\":1,\"ops\":["
      "{\"op\":\"create-node\",\"id\":1,\"kind\":\"row\"},"
      "{\"op\":\"create-node\",\"id\":2,\"kind\":\"image\"},"
      "{\"op\":\"create-node\",\"id\":3,\"kind\":\"media-surface\"},"
      "{\"op\":\"set-prop\",\"id\":2,\"property\":\"image\",\"value\":7},"
      "{\"op\":\"set-prop\",\"id\":2,\"property\":\"source-x\",\"value\":8.0},"
      "{\"op\":\"set-prop\",\"id\":2,\"property\":\"source-y\",\"value\":4.0},"
      "{\"op\":\"set-prop\",\"id\":2,\"property\":\"source-width\",\"value\":40.0},"
      "{\"op\":\"set-prop\",\"id\":2,\"property\":\"source-height\",\"value\":24.0},"
      "{\"op\":\"set-prop\",\"id\":2,\"property\":\"width\",\"value\":160},"
      "{\"op\":\"set-prop\",\"id\":2,\"property\":\"height\",\"value\":96},"
      "{\"op\":\"set-prop\",\"id\":3,\"property\":\"surface\",\"value\":11},"
      "{\"op\":\"set-prop\",\"id\":3,\"property\":\"grow\",\"value\":1.0},"
      "{\"op\":\"set-prop\",\"id\":3,\"property\":\"height\",\"value\":96},"
      "{\"op\":\"insert-child\",\"parent\":1,\"child\":2,\"index\":0},"
      "{\"op\":\"insert-child\",\"parent\":1,\"child\":3,\"index\":1}]}" )
     (wire/encode-batch batch)
     "media leaves keep the pinned resource vocabulary"))
  (doseq [kind [proto/Image proto/MediaSurface]]
    (is (not (proto/can-contain-children? kind))
        "media elements are display-only leaves")
    (doseq [property
            [proto/GrowValue proto/WidthValue proto/HeightValue
             proto/CornerRadius proto/AccessibilityLabel]]
      (is (proto/property-supported? kind property)
          "media leaves admit common surface layout and styling")))
  (doseq [property
          [proto/ImageIdValue proto/SourceX proto/SourceY
           proto/SourceWidth proto/SourceHeight]]
    (is (proto/property-supported? proto/Image property)
        "Image admits registered pixels and an atlas crop"))
  (is (proto/property-supported? proto/MediaSurface proto/SurfaceIdValue)
      "MediaSurface admits only its producer rendezvous id")
  (is (not (proto/property-supported? proto/MediaSurface proto/ImageIdValue))
      "resource namespaces remain distinct")
  (is (not (proto/property-supported? proto/Image proto/SurfaceIdValue))
      "Image cannot bind a live surface"))

(deftest media-leaf-required-resources-and-image-crops-validate-atomically
  (doseq [kind [proto/Image proto/MediaSurface]]
    (let [renderer (apple/create)
          backend (apple/backend renderer)
          batch
          (record proto/patch-batch
                  (generation 1)
                  (ops [(proto/create-node-op 1 kind)]))]
      (is (thrown-with-msg?
           Invalid_argument
           #"requires (image|surface)"
           ((:apply-batch backend) batch))
          "a resource-less media leaf is dead markup")
      (assert-equal 0 (apple/node-count renderer)
                    "a rejected media batch remains atomic")))
  (let [renderer (apple/create)
        backend (apple/backend renderer)
        partial
        (record proto/patch-batch
                (generation 1)
                (ops [(proto/create-node-op 1 proto/Image)
                      (proto/set-prop-op
                       1 proto/ImageIdValue (proto/IntValue 7))
                      (proto/set-prop-op
                       1 proto/SourceX (proto/FloatValue 0.0))]))]
    (is (thrown-with-msg?
         Invalid_argument
         #"image source crop requires all four coordinates"
         ((:apply-batch backend) partial))
        "partial Image atlas declarations fail atomically")
    (assert-equal 0 (apple/node-count renderer)
                  "the rejected crop commits no retained nodes"))
  (is (not (proto/property-value-supported?
            proto/SurfaceIdValue (proto/IntValue -1)))
      "negative surface ids are rejected at the wire boundary"))

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
    (is (not (proto/property-supported? kind proto/PlaceholderValue))
        "text-entry properties stay off toggle controls")
    (is (proto/can-contain-children? kind)
        "direct controls may retain ContextMenu metadata")
    (is (not (proto/child-kind-supported? kind proto/Text))
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

(deftest progress-control-uses-a-closed-fractional-contract
  (let [batch
        (record proto/patch-batch
                (generation 1)
                (ops [(proto/create-node-op 1 proto/Progress)
                      (proto/set-prop-op
                       1 proto/ProgressValue (proto/FloatValue 0.3))]))]
    (assert-equal
     (str
      "{\"generation\":1,\"ops\":["
      "{\"op\":\"create-node\",\"id\":1,\"kind\":\"progress\"},"
      "{\"op\":\"set-prop\",\"id\":1,"
      "\"property\":\"value\",\"value\":0.3}]}")
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

(deftest progress-control-rejects-an-integer-value
  (let [renderer (apple/create)
        application
        (runtime/create (sig/scheduler) (apple/backend renderer))
        progress (runtime/create-node! application proto/Progress)]
    (is (thrown-with-msg?
         Invalid_argument
         #"invalid property value"
         (runtime/set-prop!
          application progress proto/ProgressValue (proto/IntValue 1)))
        "Progress accepts only fractional float values")))

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

(deftest tree-has-the-pinned-role-driven-contract
  (let [properties
        (hash-map
         proto/RoleValue (proto/StringValue "treeitem")
         proto/TreeLevel (proto/IntValue 2)
         proto/Expanded (proto/BoolValue true)
         proto/Selected (proto/BoolValue false)
         proto/PressEnabled (proto/BoolValue true)
         proto/ChangeEnabled (proto/BoolValue true)
         proto/ToggleEnabled (proto/BoolValue true))
        batch
        (record proto/patch-batch
                (generation 1)
                (ops [(proto/create-node-op 1 proto/Tree)
                      (proto/create-node-op 2 proto/ListItem)
                      (proto/set-prop-op
                       1 proto/Gap (proto/IntValue 2))
                      (proto/set-prop-op
                       1 proto/AccessibilityLabel
                       (proto/StringValue "Project files"))
                      (proto/set-prop-op
                       2 proto/RoleValue (proto/StringValue "treeitem"))
                      (proto/set-prop-op
                       2 proto/TreeLevel (proto/IntValue 2))
                      (proto/set-prop-op
                       2 proto/Expanded (proto/BoolValue true))
                      (proto/set-prop-op
                       2 proto/Selected (proto/BoolValue false))
                      (proto/insert-child-op 1 2 0)]))]
    (is (proto/property-supported? proto/Tree proto/Gap)
        "Tree is a vertical gap container")
    (is (proto/property-supported? proto/Tree proto/AccessibilityLabel)
        "Tree accepts its accessible label")
    (is (not (proto/child-kind-supported? proto/Tree proto/Text))
        "Tree contains row containers rather than anonymous leaf content")
    (doseq [kind [proto/ListItem proto/Row proto/Panel]]
      (doseq [property
              [proto/RoleValue proto/TreeLevel proto/Expanded proto/Selected
               proto/PressEnabled proto/ChangeEnabled proto/ToggleEnabled]]
        (is (proto/property-supported? kind property)
            "ordinary retained rows admit the Tree row vocabulary"))
      (is (proto/event-supported-for-properties?
           kind properties (proto/Press 2))
          "a Tree row can activate")
      (is (proto/event-supported-for-properties?
           kind properties (proto/Change 2))
          "a Tree row can select while focus moves")
      (is (proto/event-supported-for-properties?
           kind properties (proto/ToggleChanged 2 false))
          "an expandable Tree row can request disclosure"))
    (is (proto/property-value-supported?
         proto/RoleValue (proto/StringValue "treeitem"))
        "treeitem is the closed role value")
    (doseq [role ["tree" "listitem" "row" ""]]
      (is (not (proto/property-value-supported?
                proto/RoleValue (proto/StringValue role)))
          "unimplemented or invalid roles are rejected"))
    (is (proto/property-value-supported?
         proto/TreeLevel (proto/IntValue 1))
        "Tree levels are one-based")
    (is (not (proto/property-value-supported?
              proto/TreeLevel (proto/IntValue 0)))
        "zero cannot masquerade as a declared Tree level")
    (assert-equal
     (str
      "{\"generation\":1,\"ops\":["
      "{\"op\":\"create-node\",\"id\":1,\"kind\":\"tree\"},"
      "{\"op\":\"create-node\",\"id\":2,\"kind\":\"list-item\"},"
      "{\"op\":\"set-prop\",\"id\":1,\"property\":\"gap\",\"value\":2},"
      "{\"op\":\"set-prop\",\"id\":1,"
      "\"property\":\"accessibility-label\",\"value\":\"Project files\"},"
      "{\"op\":\"set-prop\",\"id\":2,\"property\":\"role\","
      "\"value\":\"treeitem\"},"
      "{\"op\":\"set-prop\",\"id\":2,\"property\":\"tree-level\","
      "\"value\":2},"
      "{\"op\":\"set-prop\",\"id\":2,\"property\":\"expanded\","
      "\"value\":true},"
      "{\"op\":\"set-prop\",\"id\":2,\"property\":\"selected\","
      "\"value\":false},"
      "{\"op\":\"insert-child\",\"parent\":1,\"child\":2,\"index\":0}]}" )
     (wire/encode-batch batch)
     "Tree uses the pinned public wire vocabulary")))

(deftest tree-role-metadata-is-validated-atomically
  (doseq [operations
          [[(proto/create-node-op 1 proto/Column)
            (proto/create-node-op 2 proto/ListItem)
            (proto/set-prop-op
             2 proto/RoleValue (proto/StringValue "treeitem"))
            (proto/insert-child-op 1 2 0)]
           [(proto/create-node-op 1 proto/Tree)
            (proto/create-node-op 2 proto/ListItem)
            (proto/set-prop-op 2 proto/Expanded (proto/BoolValue true))
            (proto/insert-child-op 1 2 0)]
           [(proto/create-node-op 1 proto/Tree)
            (proto/create-node-op 2 proto/ListItem)
            (proto/set-prop-op
             2 proto/RoleValue (proto/StringValue "treeitem"))
            (proto/set-prop-op 2 proto/TreeLevel (proto/IntValue 0))
            (proto/insert-child-op 1 2 0)]
           [(proto/create-node-op 1 proto/Tree)
            (proto/create-node-op 2 proto/Text)
            (proto/set-prop-op
             1 proto/AccessibilityLabel (proto/StringValue "Project files"))
            (proto/set-prop-op
             2 proto/TextValue (proto/StringValue "orphaned leaf"))
            (proto/insert-child-op 1 2 0)]]]
    (let [renderer (apple/create)
          backend (:apply-batch (apple/backend renderer))]
      (is (thrown? Invalid_argument
                   (backend
                    (record proto/patch-batch
                            (generation 1)
                            (ops operations))))
          "malformed Tree metadata rejects the entire batch")
      (assert-equal 0 (apple/node-count renderer)
                    "a rejected Tree batch commits no nodes"))))

(deftest resizable-keeps-native-width-behind-a-closed-stacking-contract
  (doseq [property
          [proto/WidthValue proto/HeightValue proto/MinWidth proto/MaxWidth
           proto/MinHeight proto/MaxHeight proto/GrowValue proto/PaddingValue
           proto/BackgroundValue proto/ForegroundValue proto/BorderColorValue
           proto/BorderWidth proto/CornerRadius proto/AccessibilityLabel
           proto/StyleClass]]
    (is (proto/property-supported? proto/Resizable property)
        "Resizable admits its reference surface vocabulary"))
  (doseq [property
          [proto/Gap proto/MainAlignment proto/CrossAlignment proto/Selected]]
    (is (not (proto/property-supported? proto/Resizable property))
        "Resizable is a stacking surface without flow or model resize state"))
  (is (proto/can-contain-children? proto/Resizable)
      "Resizable retains stacked child content")
  (is (not (proto/event-supported? proto/Resizable (proto/ValueChanged 1 0.5)))
      "native resizing does not add an application event")
  (let [renderer (apple/create)
        backend (apple/backend renderer)
        valid
        (record proto/patch-batch
                (generation 1)
                (ops [(proto/create-node-op 1 proto/Resizable)
                      (proto/create-node-op 2 proto/Panel)
                      (proto/set-prop-op
                       1 proto/WidthValue (proto/IntValue 240))
                      (proto/set-prop-op
                       1 proto/MinWidth (proto/IntValue 180))
                      (proto/set-prop-op
                       1 proto/AccessibilityLabel
                       (proto/StringValue "Resizable sidebar"))
                      (proto/insert-child-op 1 2 0)]))]
    (is ((:apply-batch backend) valid) "valid Resizable batch applies")
    (match (apple/node renderer 1)
      (Some AppleResizable) (is true "Resizable maps to Apple native surface")
      _ (is false "Apple Resizable mapping exists"))
    (assert-equal
     (Some (proto/IntValue 240))
     (apple/property renderer 1 proto/WidthValue)
     "initial width is retained for native reconciliation"))
  (let [renderer (flutter/create)
        backend (flutter/backend renderer)
        valid
        (record proto/patch-batch
                (generation 1)
                (ops [(proto/create-node-op 1 proto/Resizable)
                      (proto/create-node-op 2 proto/Panel)
                      (proto/set-prop-op
                       1 proto/WidthValue (proto/IntValue 240))
                      (proto/insert-child-op 1 2 0)]))]
    (is ((:apply-batch backend) valid) "valid Flutter Resizable batch applies")
    (match (flutter/node renderer 1)
      (Some FlutterResizable)
      (is true "Resizable maps to Flutter native surface")
      _ (is false "Flutter Resizable mapping exists")))
  (let [renderer (flutter/create)
        backend (flutter/backend renderer)
        invalid
        (record proto/patch-batch
                (generation 1)
                (ops [(proto/create-node-op 1 proto/Resizable)
                      (proto/set-prop-op 1 proto/Gap (proto/IntValue 8))]))]
    (is (thrown? Invalid_argument ((:apply-batch backend) invalid))
        "flow gap is rejected instead of ignored")
    (assert-equal 0 (flutter/node-count renderer)
                  "invalid Resizable batches remain atomic")))

(deftest split-owns-one-controlled-two-pane-fraction
  (doseq [property
          [proto/ProgressValue proto/ResizeDuration proto/ResizeEasing
           proto/ResizeOrigin proto/Gap proto/GrowValue proto/PaddingValue
           proto/BackgroundValue proto/ForegroundValue proto/BorderColorValue
           proto/BorderWidth proto/CornerRadius proto/WidthValue
           proto/HeightValue proto/MinWidth proto/MaxWidth proto/MinHeight
           proto/MaxHeight proto/AccessibilityLabel proto/StyleClass]]
    (is (proto/property-supported? proto/Split property)
        "Split admits only its model, divider, animation, and surface vocabulary"))
  (doseq [property [proto/MainAlignment proto/CrossAlignment proto/Selected]]
    (is (not (proto/property-supported? proto/Split property))
        "Split owns neither flow alignment nor selection"))
  (is (proto/can-contain-children? proto/Split)
      "Split contains its two pane roots")
  (is (proto/event-supported? proto/Split (proto/ValueChanged 1 0.4))
      "Split reports effective fractions through ValueChanged")
  (is (proto/property-value-supported?
       proto/ResizeEasing (proto/StringValue "spring"))
      "the final reference easing rung is accepted")
  (is (not (proto/property-value-supported?
            proto/ResizeEasing (proto/StringValue "bounce")))
      "unknown easing names are rejected")
  (is (not
       (proto/node-properties-supported?
        proto/Split
        {proto/ResizeEasing (proto/StringValue "standard")}))
      "resize easing without a nonzero duration is invalid")
  (is (not
       (proto/node-properties-supported?
        proto/Split
        {proto/ResizeDuration (proto/IntValue 0)
         proto/ResizeOrigin (proto/FloatValue 0.1)}))
      "resize origin beside a zero duration is invalid")
  (is
   (proto/node-properties-supported?
    proto/Split
    {proto/ProgressValue (proto/FloatValue 0.35)
     proto/ResizeDuration (proto/IntValue 180)
     proto/ResizeEasing (proto/StringValue "emphasized")
     proto/ResizeOrigin (proto/FloatValue 0.1)})
   "a complete animated Split declaration is valid")
  (let [operations
        [(proto/create-node-op 1 proto/Split)
         (proto/create-node-op 2 proto/Panel)
         (proto/create-node-op 3 proto/Panel)
         (proto/set-prop-op
          1 proto/ProgressValue (proto/FloatValue 0.35))
         (proto/set-prop-op 1 proto/Gap (proto/IntValue 8))
         (proto/set-prop-op 1 proto/ResizeDuration (proto/IntValue 180))
         (proto/set-prop-op
          1 proto/ResizeEasing (proto/StringValue "standard"))
         (proto/set-prop-op
          1 proto/ResizeOrigin (proto/FloatValue 0.1))
         (proto/insert-child-op 1 2 0)
         (proto/insert-child-op 1 3 1)]]
    (let [renderer (apple/create)
          backend (:apply-batch (apple/backend renderer))]
      (is (backend
           (record proto/patch-batch (generation 1) (ops operations)))
          "valid Apple Split batch applies")
      (match (apple/node renderer 1)
        (Some AppleSplit) (is true "Split maps to Apple native layout")
        _ (is false "Apple Split mapping exists"))
      (assert-equal [2 3] (apple/children renderer 1)
                    "Apple retains the two pane identities"))
    (let [renderer (flutter/create)
          backend (:apply-batch (flutter/backend renderer))]
      (is (backend
           (record proto/patch-batch (generation 1) (ops operations)))
          "valid Flutter Split batch applies")
      (match (flutter/node renderer 1)
        (Some FlutterSplit) (is true "Split maps to Flutter native layout")
        _ (is false "Flutter Split mapping exists"))))
  (doseq [operations
          [[(proto/create-node-op 1 proto/Split)
            (proto/create-node-op 2 proto/Panel)
            (proto/insert-child-op 1 2 0)]
           [(proto/create-node-op 1 proto/Split)
            (proto/create-node-op 2 proto/Panel)
            (proto/create-node-op 3 proto/Panel)
            (proto/create-node-op 4 proto/Panel)
            (proto/insert-child-op 1 2 0)
            (proto/insert-child-op 1 3 1)
            (proto/insert-child-op 1 4 2)]]]
    (let [renderer (apple/create)
          backend (:apply-batch (apple/backend renderer))]
      (is (thrown? Invalid_argument
                   (backend
                    (record proto/patch-batch
                            (generation 1)
                            (ops operations))))
          "Split rejects every child count except exactly two")
      (assert-equal 0 (apple/node-count renderer)
                    "malformed Split batches remain atomic"))))

(deftest context-menu-is-retained-host-metadata
  (is (proto/can-contain-children? proto/ContextMenu)
      "ContextMenu retains its flat item identities")
  (doseq [property [proto/TextValue proto/Enabled proto/Gap proto/StyleClass]]
    (is (not (proto/property-supported? proto/ContextMenu property))
        "ContextMenu has no public attributes"))
  (is (proto/child-kind-supported? proto/ContextMenu proto/MenuItem)
      "ContextMenu accepts MenuItem")
  (is (proto/child-kind-supported? proto/ContextMenu proto/Divider)
      "ContextMenu accepts separators")
  (is (not (proto/child-kind-supported? proto/ContextMenu proto/Text))
      "ContextMenu rejects arbitrary content")
  (let [operations
        [(proto/create-node-op 1 proto/ListItem)
         (proto/create-node-op 2 proto/ContextMenu)
         (proto/create-node-op 3 proto/MenuItem)
         (proto/create-node-op 4 proto/Divider)
         (proto/create-node-op 5 proto/MenuItem)
         (proto/set-prop-op 1 proto/TextValue (proto/StringValue "Document"))
         (proto/set-prop-op 3 proto/TextValue (proto/StringValue "Rename"))
         (proto/set-prop-op 3 proto/PressEnabled (proto/BoolValue true))
         (proto/set-prop-op 5 proto/TextValue (proto/StringValue "Archive"))
         (proto/set-prop-op 5 proto/PressEnabled (proto/BoolValue true))
         (proto/set-prop-op 5 proto/Enabled (proto/BoolValue false))
         (proto/insert-child-op 1 2 0)
         (proto/insert-child-op 2 3 0)
         (proto/insert-child-op 2 4 1)
         (proto/insert-child-op 2 5 2)]]
    (let [renderer (apple/create)
          apply-batch (:apply-batch (apple/backend renderer))]
      (is (apply-batch
           (record proto/patch-batch (generation 1) (ops operations))))
      (match (apple/node renderer 2)
        (Some AppleContextMenu) (is true "Apple maps ContextMenu metadata")
        _ (is false "Apple ContextMenu mapping exists"))
      (assert-equal [2] (apple/children renderer 1)
                    "the host retains one metadata child")
      (assert-equal [3 4 5] (apple/children renderer 2)
                    "menu item and separator slots retain order"))
    (let [renderer (flutter/create)
          apply-batch (:apply-batch (flutter/backend renderer))]
      (is (apply-batch
           (record proto/patch-batch (generation 1) (ops operations))))
      (match (flutter/node renderer 2)
        (Some FlutterContextMenu) (is true "Flutter maps ContextMenu metadata")
        _ (is false "Flutter ContextMenu mapping exists"))))
  (doseq [operations
          [[(proto/create-node-op 1 proto/ContextMenu)
            (proto/create-node-op 2 proto/Text)
            (proto/set-prop-op 2 proto/TextValue (proto/StringValue "No"))
            (proto/insert-child-op 1 2 0)]
           [(proto/create-node-op 1 proto/ListItem)
            (proto/create-node-op 2 proto/ContextMenu)
            (proto/create-node-op 3 proto/ContextMenu)
            (proto/set-prop-op 1 proto/TextValue (proto/StringValue "Host"))
            (proto/insert-child-op 1 2 0)
            (proto/insert-child-op 1 3 1)]
           [(proto/create-node-op 1 proto/ListItem)
            (proto/create-node-op 2 proto/ContextMenu)
            (proto/create-node-op 3 proto/MenuItem)
            (proto/set-prop-op 1 proto/TextValue (proto/StringValue "Host"))
            (proto/set-prop-op 3 proto/TextValue (proto/StringValue "Missing handler"))
            (proto/insert-child-op 1 2 0)
            (proto/insert-child-op 2 3 0)]
           [(proto/create-node-op 1 proto/Button)
            (proto/create-node-op 2 proto/ContextMenu)
            (proto/create-node-op 3 proto/MenuItem)
            (proto/create-node-op 4 proto/ContextMenu)
            (proto/create-node-op 5 proto/MenuItem)
            (proto/set-prop-op 1 proto/TextValue (proto/StringValue "Host"))
            (proto/set-prop-op 3 proto/TextValue (proto/StringValue "Parent"))
            (proto/set-prop-op 3 proto/PressEnabled (proto/BoolValue true))
            (proto/set-prop-op 5 proto/TextValue (proto/StringValue "Nested"))
            (proto/set-prop-op 5 proto/PressEnabled (proto/BoolValue true))
            (proto/insert-child-op 1 2 0)
            (proto/insert-child-op 2 3 0)
            (proto/insert-child-op 3 4 0)
            (proto/insert-child-op 4 5 0)]]]
    (let [renderer (apple/create)
          apply-batch (:apply-batch (apple/backend renderer))]
      (is (thrown? Invalid_argument
                   (apply-batch
                    (record proto/patch-batch
                            (generation 1)
                            (ops operations)))))
      (assert-equal 0 (apple/node-count renderer)
                    "invalid ContextMenu batches remain atomic"))))

(deftest context-menu-leaf-hosts-accept-only-metadata-children
  (doseq [kind
          [proto/Button proto/ToggleButton proto/Toggle proto/Radio
           proto/Slider proto/TextField proto/Input proto/SearchField
           proto/Textarea proto/Checkbox proto/SwitchControl proto/Select
           proto/Combobox proto/MenuItem proto/Text proto/TableCell]]
    (is (proto/can-contain-children? kind)
        "interactive leaves can retain direct ContextMenu metadata")
    (is (proto/child-kind-supported? kind proto/ContextMenu)
        "interactive leaves accept ContextMenu metadata")
    (is (not (proto/child-kind-supported? kind proto/Text))
        "interactive leaves reject visible child nodes"))
  (let [valid
        [(proto/create-node-op 1 proto/Button)
         (proto/create-node-op 2 proto/ContextMenu)
         (proto/create-node-op 3 proto/MenuItem)
         (proto/set-prop-op 1 proto/TextValue (proto/StringValue "More"))
         (proto/set-prop-op 3 proto/TextValue (proto/StringValue "Duplicate"))
         (proto/set-prop-op 3 proto/PressEnabled (proto/BoolValue true))
         (proto/insert-child-op 1 2 0)
         (proto/insert-child-op 2 3 0)]]
    (let [renderer (apple/create)
          apply-batch (:apply-batch (apple/backend renderer))]
      (is (apply-batch
           (record proto/patch-batch (generation 1) (ops valid))))
      (assert-equal [2] (apple/children renderer 1)
                    "Apple retains leaf-host metadata"))
    (let [renderer (flutter/create)
          apply-batch (:apply-batch (flutter/backend renderer))]
      (is (apply-batch
           (record proto/patch-batch (generation 1) (ops valid))))
      (assert-equal [2] (flutter/children renderer 1)
                    "Flutter retains leaf-host metadata")))
  (let [renderer (apple/create)
        apply-batch (:apply-batch (apple/backend renderer))]
    (is (thrown? Invalid_argument
                 (apply-batch
                  (record
                   proto/patch-batch
                   (generation 1)
                   (ops [(proto/create-node-op 1 proto/Button)
                         (proto/create-node-op 2 proto/Text)
                         (proto/set-prop-op
                          1 proto/TextValue (proto/StringValue "More"))
                         (proto/set-prop-op
                          2 proto/TextValue (proto/StringValue "Visible"))
                         (proto/insert-child-op 1 2 0)])))))
    (assert-equal 0 (apple/node-count renderer)
                  "invalid visible children remain atomic")))

(deftest message-surfaces-use-the-pinned-retained-contract
  (let [batch
        (record
         proto/patch-batch
         (generation 1)
         (ops [(proto/create-node-op 1 proto/Column)
               (proto/create-node-op 2 proto/Alert)
               (proto/create-node-op 3 proto/Text)
               (proto/create-node-op 4 proto/Bubble)
               (proto/create-node-op 5 proto/Text)
               (proto/create-node-op 6 proto/StatusBar)
               (proto/set-prop-op
                2 proto/TextValue (proto/StringValue "Sync paused"))
               (proto/set-prop-op
                4 proto/VariantValue (proto/StringValue "primary"))
               (proto/set-prop-op
                4 proto/TextValue (proto/StringValue "2 reactions"))
               (proto/set-prop-op
                4 proto/TextAlignment (proto/StringValue "start"))
               (proto/set-prop-op
                6 proto/TextValue (proto/StringValue "3 items"))
               (proto/insert-child-op 1 2 0)
               (proto/insert-child-op 2 3 0)
               (proto/insert-child-op 1 4 1)
               (proto/insert-child-op 4 5 0)
               (proto/insert-child-op 1 6 2)]))]
    (assert-equal
     (str
      "{\"generation\":1,\"ops\":["
      "{\"op\":\"create-node\",\"id\":1,\"kind\":\"column\"},"
      "{\"op\":\"create-node\",\"id\":2,\"kind\":\"alert\"},"
      "{\"op\":\"create-node\",\"id\":3,\"kind\":\"text\"},"
      "{\"op\":\"create-node\",\"id\":4,\"kind\":\"bubble\"},"
      "{\"op\":\"create-node\",\"id\":5,\"kind\":\"text\"},"
      "{\"op\":\"create-node\",\"id\":6,\"kind\":\"status-bar\"},"
      "{\"op\":\"set-prop\",\"id\":2,\"property\":\"text\","
      "\"value\":\"Sync paused\"},"
      "{\"op\":\"set-prop\",\"id\":4,\"property\":\"variant\","
      "\"value\":\"primary\"},"
      "{\"op\":\"set-prop\",\"id\":4,\"property\":\"text\","
      "\"value\":\"2 reactions\"},"
      "{\"op\":\"set-prop\",\"id\":4,"
      "\"property\":\"text-alignment\",\"value\":\"start\"},"
      "{\"op\":\"set-prop\",\"id\":6,\"property\":\"text\","
      "\"value\":\"3 items\"},"
      "{\"op\":\"insert-child\",\"parent\":1,\"child\":2,\"index\":0},"
      "{\"op\":\"insert-child\",\"parent\":2,\"child\":3,\"index\":0},"
      "{\"op\":\"insert-child\",\"parent\":1,\"child\":4,\"index\":1},"
      "{\"op\":\"insert-child\",\"parent\":4,\"child\":5,\"index\":0},"
      "{\"op\":\"insert-child\",\"parent\":1,\"child\":6,\"index\":2}]}")
     (wire/encode-batch batch)
     "message surfaces keep closed native wire names")
    (doseq [kind [proto/Alert proto/Bubble]]
      (is (proto/can-contain-children? kind)
          "message surfaces retain stacked content")
      (is (not (proto/property-supported? kind proto/Gap))
          "stacking message surfaces reject gap"))
    (is (not (proto/can-contain-children? proto/StatusBar))
        "StatusBar remains a text leaf")
    (is (proto/property-supported? proto/Alert proto/TextValue)
        "Alert admits its chrome title")
    (is (proto/property-supported? proto/Bubble proto/TextValue)
        "Bubble carries lowered Reactions text internally")
    (is (proto/property-supported? proto/Bubble proto/TextAlignment)
        "Bubble carries the Reactions dock internally")
    (is (proto/property-supported? proto/StatusBar proto/TextValue)
        "StatusBar admits plain text")
    (let [renderer (apple/create)
          apply-batch (:apply-batch (apple/backend renderer))]
      (is (apply-batch batch))
      (assert-equal [2 4 6] (apple/children renderer 1)
                    "native adapters retain all three surfaces")
      (assert-equal [3] (apple/children renderer 2)
                    "Alert content stays retained")
      (assert-equal [5] (apple/children renderer 4)
                    "Bubble message stays retained")))
  (doseq [kind [proto/Alert proto/Bubble]]
    (let [renderer (apple/create)
          apply-batch (:apply-batch (apple/backend renderer))]
      (is (thrown? Invalid_argument
                   (apply-batch
                    (record
                     proto/patch-batch
                     (generation 1)
                     (ops [(proto/create-node-op 1 kind)
                           (proto/set-prop-op
                            1 proto/Gap (proto/IntValue 8))])))))
      (assert-equal 0 (apple/node-count renderer)
                    "invalid surface batches remain atomic"))))

(deftest table-family-has-the-pinned-closed-contract
  (let [batch
        (record proto/patch-batch
                (generation 1)
                (ops [(proto/create-node-op 1 proto/Table)
                      (proto/create-node-op 2 proto/TableRow)
                      (proto/create-node-op 3 proto/TableCell)
                      (proto/set-prop-op
                       2 proto/Selected (proto/BoolValue true))
                      (proto/set-prop-op
                       3 proto/TextValue (proto/StringValue "INV-002"))
                      (proto/set-prop-op
                       3 proto/TextAlignment (proto/StringValue "end"))
                      (proto/set-prop-op
                       3 proto/PressEnabled (proto/BoolValue true))
                      (proto/insert-child-op 1 2 0)
                      (proto/insert-child-op 2 3 0)]))]
    (assert-equal
     (str
      "{\"generation\":1,\"ops\":["
      "{\"op\":\"create-node\",\"id\":1,\"kind\":\"table\"},"
      "{\"op\":\"create-node\",\"id\":2,\"kind\":\"table-row\"},"
      "{\"op\":\"create-node\",\"id\":3,\"kind\":\"table-cell\"},"
      "{\"op\":\"set-prop\",\"id\":2,\"property\":\"selected\","
      "\"value\":true},"
      "{\"op\":\"set-prop\",\"id\":3,\"property\":\"text\","
      "\"value\":\"INV-002\"},"
      "{\"op\":\"set-prop\",\"id\":3,"
      "\"property\":\"text-alignment\",\"value\":\"end\"},"
      "{\"op\":\"set-prop\",\"id\":3,"
      "\"property\":\"press-enabled\",\"value\":true},"
      "{\"op\":\"insert-child\",\"parent\":1,\"child\":2,\"index\":0},"
      "{\"op\":\"insert-child\",\"parent\":2,\"child\":3,\"index\":0}]}" )
     (wire/encode-batch batch)
     "Table uses the pinned element and attribute vocabulary"))
  (doseq [property
          [proto/GrowValue proto/WidthValue proto/MinWidth proto/MaxWidth]]
    (is (proto/property-supported? proto/Table property)
        "Table admits its collection layout contract"))
  (doseq [property [proto/Gap proto/Selected]]
    (is (proto/property-supported? proto/TableRow property)
        "TableRow admits row spacing and model-owned selection"))
  (doseq [property
          [proto/TextValue proto/GrowValue proto/SizeValue
           proto/ForegroundValue proto/TextAlignment proto/PressEnabled]]
    (is (proto/property-supported? proto/TableCell property)
        "TableCell admits its complete text-cell contract"))
  (is (proto/can-contain-children? proto/Table)
      "Table retains rows")
  (is (proto/can-contain-children? proto/TableRow)
      "TableRow retains cells")
  (is (proto/can-contain-children? proto/TableCell)
      "TableCell may retain ContextMenu metadata")
  (is (not (proto/child-kind-supported? proto/TableCell proto/Text))
      "TableCell visible text remains property-owned")
  (is (proto/event-supported? proto/TableCell (proto/Press 3))
      "TableCell dispatches on-press")
  (doseq [alignment ["start" "center" "end"]]
    (is (proto/property-value-supported?
         proto/TextAlignment (proto/StringValue alignment))
        "every reference text alignment is accepted"))
  (doseq [alignment ["left" "right" "stretch" ""]]
    (is (not (proto/property-value-supported?
              proto/TextAlignment (proto/StringValue alignment)))
        "CSS aliases and invalid text alignments are rejected"))
  (is (proto/property-value-supported-for-kind?
       proto/TableCell proto/SizeValue (proto/StringValue "heading"))
      "a TableCell accepts typography size rungs")
  (is (not (proto/property-value-supported-for-kind?
            proto/Spinner proto/SizeValue (proto/StringValue "heading")))
      "control-sized widgets reject typography-only sizes"))

(deftest table-family-enforces-structural-nesting-atomically
  (let [application
        (runtime/create (sig/scheduler) (apple/backend (apple/create)))
        table (runtime/create-node! application proto/Table)
        row (runtime/create-node! application proto/TableRow)
        cell (runtime/create-node! application proto/TableCell)
        text (runtime/create-node! application proto/Text)]
    (runtime/insert-child! application table row 0)
    (runtime/insert-child! application row cell 0)
    (is (thrown-with-msg?
         Invalid_argument
         #"table can contain only table-row"
         (runtime/insert-child! application table text 1))
        "authoring rejects a non-row directly under Table")
    (is (thrown-with-msg?
         Invalid_argument
         #"table-row can contain only table-cell"
         (runtime/insert-child! application row text 1))
        "authoring rejects a non-cell directly under TableRow"))
  (let [renderer (apple/create)
        invalid
        (record proto/patch-batch
                (generation 1)
                (ops [(proto/create-node-op 1 proto/Table)
                      (proto/create-node-op 2 proto/Text)
                      (proto/set-prop-op
                       2 proto/TextValue (proto/StringValue "Invalid"))
                      (proto/insert-child-op 1 2 0)]))]
    (is (thrown-with-msg?
         Invalid_argument
         #"table can contain only table-row"
         ((:apply-batch (apple/backend renderer)) invalid))
        "the backend rejects malformed wire nesting")
    (assert-equal 0 (apple/node-count renderer)
                  "a rejected Table batch retains no partial nodes")))

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
    (is (proto/can-contain-children? proto/Button)
        "Button may retain ContextMenu metadata")
    (is (not (proto/child-kind-supported? proto/Button proto/Text))
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
    (is (proto/can-contain-children? proto/ToggleButton)
        "ToggleButton may retain ContextMenu metadata")
    (is (not (proto/child-kind-supported? proto/ToggleButton proto/Text))
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
        heading (runtime/create-node! application proto/Heading)
        calls (atom 0)]
    (sig/mount! component-scope)
    (runtime/on-event!
     component-scope application heading
     (fn [_event] (swap! calls inc) true))
    (is (thrown-with-msg?
         Invalid_argument
         #"unsupported"
         (runtime/dispatch! application (proto/Press heading)))
        "a native host cannot emit press events for non-pressable headings")
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
        apple-input (runtime/create-node! apple-runtime proto/TextField)
        flutter-row (runtime/create-node! flutter-runtime proto/Row)
        flutter-text (runtime/create-node! flutter-runtime proto/Text)
        flutter-input (runtime/create-node! flutter-runtime proto/TextField)]
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
                  "invalid batches are rejected atomically"))
  (let [renderer (apple/create)
        backend (apple/backend renderer)
        invalid-batch
        (record proto/patch-batch
                (generation 1)
                (ops [(proto/create-node-op 1 proto/Radio)
                      (proto/set-prop-op
                       1 proto/TextValue (proto/StringValue "Orphan"))]))]
    (is (thrown-with-msg?
         Invalid_argument
         #"radio-group"
         ((:apply-batch backend) invalid-batch))
        "Radio must have a RadioGroup ancestor")
    (assert-equal 0 (apple/node-count renderer)
                  "orphan Radio rejection is atomic")))

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
         #"unsupported child kind"
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
         #"unsupported child kind"
         ((:apply-batch backend) invalid-batch))
        "backend keeps native switch implementation parts off-tree")))

(deftest runtime-rejects-invalid-structure-before-enqueue
  (let [application
        (runtime/create (sig/scheduler) (apple/backend (apple/create)))
        label (runtime/create-node! application proto/Text)
        child (runtime/create-node! application proto/Text)]
    (is (thrown-with-msg?
         Invalid_argument
         #"unsupported child kind"
         (runtime/insert-child! application label child 0))
        "leaf nodes reject children before a batch reaches the backend"))
  (let [application
        (runtime/create (sig/scheduler) (apple/backend (apple/create)))
        switch-control (runtime/create-node! application proto/SwitchControl)
        first-child (runtime/create-node! application proto/Text)
        _second-child (runtime/create-node! application proto/Text)]
    (is (thrown-with-msg?
         Invalid_argument
         #"unsupported child kind"
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

(deftest progress-structures-have-closed-properties-and-child-shapes
  (doseq [property [proto/ActiveIndex proto/AccessibilityLabel]]
    (is (proto/property-supported? proto/Stepper property)
        "Stepper exposes only controlled progress and its label"))
  (is (proto/property-supported? proto/Step proto/TextValue)
      "Step owns only its label")
  (doseq [property [proto/Gap proto/GrowValue proto/AccessibilityLabel]]
    (is (proto/property-supported? proto/Timeline property)
        "Timeline exposes the reference list layout API"))
  (doseq [property
          [proto/TitleValue proto/DescriptionValue proto/MetaValue
           proto/IndicatorValue proto/InlineIconName proto/VariantValue
           proto/Connector proto/Selected proto/PressEnabled]]
    (is (proto/property-supported? proto/TimelineItem property)
        "TimelineItem exposes the pinned reference fields"))
  (is (proto/child-kind-supported? proto/Stepper proto/Step)
      "Stepper accepts Step children")
  (is (not (proto/child-kind-supported? proto/Stepper proto/Text))
      "Stepper rejects ordinary visible children")
  (is (proto/child-kind-supported? proto/Timeline proto/TimelineItem)
      "Timeline accepts TimelineItem children")
  (is (not (proto/child-kind-supported? proto/Timeline proto/ListItem))
      "Timeline rejects generic list rows")
  (is (not (proto/can-contain-children? proto/Step))
      "Step is a semantic text leaf")
  (is (not (proto/can-contain-children? proto/TimelineItem))
      "TimelineItem internal composition stays backend-owned")
  (is (proto/event-supported? proto/TimelineItem (proto/Press 9))
      "TimelineItem supports a single root Press event")
  (is (not (proto/event-supported? proto/TimelineItem (proto/Submit 9)))
      "TimelineItem has no extra interaction API")
  (is (proto/property-value-supported?
       proto/ActiveIndex (proto/IntValue 0))
      "the first Step is a valid active index")
  (is (not (proto/property-value-supported?
            proto/ActiveIndex (proto/IntValue -1)))
      "active index cannot be negative"))

(deftest retained-progress-structures-reject-incomplete-or-invalid-batches
  (let [renderer (apple/create)
        backend (apple/backend renderer)
        missing-active
        (record proto/patch-batch
                (generation 1)
                (ops [(proto/create-node-op 1 proto/Stepper)]))]
    (is (thrown-with-msg?
         Invalid_argument #"stepper requires active"
         ((:apply-batch backend) missing-active))
        "Stepper cannot silently invent model state")
    (assert-equal 0 (apple/node-count renderer)
                  "missing active is rejected atomically"))
  (let [renderer (apple/create)
        backend (apple/backend renderer)
        missing-title
        (record proto/patch-batch
                (generation 1)
                (ops [(proto/create-node-op 1 proto/TimelineItem)]))]
    (is (thrown-with-msg?
         Invalid_argument #"timeline-item requires title"
         ((:apply-batch backend) missing-title))
        "TimelineItem requires visible content")
    (assert-equal 0 (apple/node-count renderer)
                  "missing title is rejected atomically"))
  (let [renderer (apple/create)
        backend (apple/backend renderer)
        wrong-child
        (record proto/patch-batch
                (generation 1)
                (ops [(proto/create-node-op 1 proto/Stepper)
                      (proto/set-prop-op
                       1 proto/ActiveIndex (proto/IntValue 0))
                      (proto/create-node-op 2 proto/Text)
                      (proto/set-prop-op
                       2 proto/TextValue (proto/StringValue "Wrong"))
                      (proto/insert-child-op 1 2 0)]))]
    (is (thrown-with-msg?
         Invalid_argument #"unsupported child kind"
         ((:apply-batch backend) wrong-child))
        "Stepper accepts only semantic Steps")
    (assert-equal 0 (apple/node-count renderer)
                  "invalid Stepper structure is rejected atomically")))

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
