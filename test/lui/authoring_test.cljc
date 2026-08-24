(ns lui.authoring-test
  (:require [clojure.test :refer [deftest is]]
            [signal.core :as sig]
            [lui.protocol :as proto :refer [StringValue TextChanged]]
            [lui.runtime :as runtime]
            [lui.ui :as ui]
            [lui.elements :refer [defelement]]
            [lui.card :as card]
            [lui.progress :as progress]
            [lui.text-field :as text-field]
            [lui.switch :as switch]
            [lui.macros :refer [defui state effect platform host]]
            [lui.backend.apple :as apple
             :refer [AppleBox AppleCheckbox AppleColumn AppleFormLabel AppleHeading
                     AppleParagraph AppleProgress AppleSwitch AppleTextInput]]
            [lui.backend.flutter :as flutter]))

(defmacro assert-equal [expected actual message]
  `(is (= ~expected ~actual) ~message))

(defui scoped-count []
  (state 0))

(defui increment-later [counter]
  (effect (sig/update! counter inc)))

(defui declarative-toolbar [title-source on-save]
  [:row {:gap 8 :padding 12}
   [:text {:value title-source}]
   [:spacer]
   [:button {:on-press on-save} "Save"]])

(defelement badge [context parent _attrs & children]
  `(lui.elements/text ~context ~parent {} ~@children))

(defui custom-element-view []
  [:lui.authoring-test/badge "Extensible"])

(defui current-platform-profile []
  (tuple (platform) (host)))

(defui accessible-search [source callback]
  [:text-input
   {:value source
    :placeholder "Search"
    :read-only true
    :accessibility-label "Search todos"
    :on-change callback}])

(defui bounded-notes [source callback]
  [:text-area
   {:value source
    :placeholder "Notes"
    :min-lines 2
    :max-lines 5
    :accessibility-label "Todo notes"
    :on-change callback}])

(defui controlled-delete-button [disabled-source callback]
  [:button
   {:variant "destructive"
    :size "sm"
    :class "danger-zone-action"
    :disabled disabled-source
    :on-press callback}
   "Delete"])

(defui default-solid-button [callback]
  [:button {:on-press callback} "Continue"])

(defui semantic-content []
  [:box {:class "semantic-content"}
   [:heading {:level 3} "Account"]
   [:paragraph "Manage your profile settings."]])

(defui reactive-semantic-content [source]
  [:box
   [:heading {:level 2 :value source}]
   [:paragraph {:value source}]])

(defui profile-card [callback]
  [:card {:class "profile-card"}
   [:card/header
    [:card/title "Account"]
    [:card/description "Manage your profile settings."]]
   [:card/content
    [:paragraph "Changes stay local until you save them."]]
   [:card/footer
    [:button {:on-press callback} "Save changes"]]])

(defui status-badges []
  [:column
   [:badge "Default"]
   [:badge
    {:variant "success" :round true :class "sync-status"}
    "Synchronized"]])

(defui task-progress [completed completed-label]
  [:progress
   {:value completed :min-value 0 :max-value 10 :class "task-progress"}
   [:progress/label "Processing..."]
   [:progress/value-label {:value completed-label}]])

(defui email-field [value invalid disabled callback]
  [:text-field {:class "account-email"}
   [:text-field/label "Email"]
   [:text-field/input
    {:value value
     :type "email"
     :invalid invalid
     :disabled disabled
     :placeholder "you@example.com"
     :on-change callback}]
   [:text-field/description "Used for account notifications."]
   [:text-field/error-message "Enter a valid email address."]])

(defui settings-toggles
  [checked indeterminate disabled invalid checkbox-change switch-change]
  [:column
   [:checkbox
    {:checked checked
     :indeterminate indeterminate
     :disabled disabled
     :accessibility-label "Select all"
     :on-change checkbox-change}]
   [:switch
    {:checked checked
     :disabled disabled
     :invalid invalid
     :on-change switch-change}
    [:switch/control
     [:switch/thumb]]
    [:switch/label "Notifications"]
    [:switch/description "Receive a daily summary."]
    [:switch/error-message "Choose a notification preference."]]])

(deftest platform-profile-flows-through-ui-context
  (let [apple-renderer (apple/create)
        apple-application
        (runtime/create (sig/scheduler) (apple/backend apple-renderer))
        apple-context
        (ui/context apple-application (sig/scope "apple-profile"))
        flutter-renderer (flutter/create)
        flutter-application
        (runtime/create
         (sig/scheduler)
         (flutter/backend-for flutter-renderer proto/AndroidOS))
        flutter-context
        (ui/context flutter-application (sig/scope "flutter-profile"))]
    (assert-equal
     (tuple proto/MacOS proto/SwiftUIHost)
     (current-platform-profile apple-context)
     "SwiftUI publishes its OS and host profile")
    (assert-equal
     (tuple proto/AndroidOS proto/FlutterHost)
     (current-platform-profile flutter-context)
     "Flutter can publish an Android-specific profile")))

(deftest defui-state-is-stable-and-scoped
  (let [scheduler (sig/scheduler)
        renderer (apple/create)
        application (runtime/create scheduler (apple/backend renderer))
        first-scope (sig/scope "first")
        second-scope (sig/scope "second")
        first-context (ui/context application first-scope)
        second-context (ui/context application second-scope)
        first-state (scoped-count first-context)
        same-state (scoped-count first-context)
        other-state (scoped-count second-context)]
    (is (identical? first-state same-state)
        "defui state keeps its identity inside a scope")
    (is (not (identical? first-state other-state))
        "defui state is isolated between scopes")
    (sig/set! first-state 7)
    (runtime/flush! application)
    (assert-equal 7 (sig/get first-state) "first scoped state updates")
    (assert-equal 0 (sig/get other-state) "second scoped state stays isolated")
    (sig/dispose-scope! first-scope)))

(deftest defui-effect-enters-the-scheduler
  (let [scheduler (sig/scheduler)
        renderer (apple/create)
        application (runtime/create scheduler (apple/backend renderer))
        context (ui/context application (sig/scope "effect"))
        counter (sig/state scheduler 0)]
    (increment-later context counter)
    (assert-equal 0 (sig/get counter) "effect is deferred")
    (runtime/flush! application)
    (assert-equal 1 (sig/get counter) "effect runs during flush")))

(deftest defui-lowers-declarative-views-to-retained-bindings
  (let [scheduler (sig/scheduler)
        renderer (apple/create)
        application (runtime/create scheduler (apple/backend renderer))
        scope (sig/scope "declarative-toolbar")
        context (ui/context application scope)
        title (sig/state scheduler "Todos")
        presses (atom 0)
        root
        (declarative-toolbar
         context (sig/value title)
         (fn [_event]
           (swap! presses inc)
           true))]
    (sig/mount! scope)
    (runtime/flush! application)
    (let [children (apple/children renderer root)
          label (nth children 0)
          button (nth children 2)]
      (assert-equal 3 (count children) "declarative children are mounted")
      (match (apple/property renderer label proto/TextValue)
        (Some (StringValue text))
        (assert-equal "Todos" text "reactive text is bound")
        _ (is false "declarative text exists"))
      (sig/set! title "Done")
      (runtime/flush! application)
      (match (apple/property renderer label proto/TextValue)
        (Some (StringValue text))
        (assert-equal "Done" text "only the reactive property updates")
        _ (is false "updated declarative text exists"))
      (runtime/dispatch! application (proto/Press button))
      (runtime/flush! application)
      (assert-equal 1 @presses "declarative event enters the effect queue"))))

(deftest defelement-adds-a-tag-without-changing-defui
  (let [scheduler (sig/scheduler)
        renderer (apple/create)
        application (runtime/create scheduler (apple/backend renderer))
        scope (sig/scope "custom-element")
        context (ui/context application scope)
        node (custom-element-view context)]
    (sig/mount! scope)
    (runtime/flush! application)
    (match (apple/property renderer node proto/TextValue)
      (Some (StringValue text))
      (assert-equal "Extensible" text "qualified custom tag is expanded")
      _ (is false "custom element creates a retained node"))))

(deftest semantic-builders-produce-retained-ui
  (let [scheduler (sig/scheduler)
        renderer (apple/create)
        application (runtime/create scheduler (apple/backend renderer))
        scope (sig/scope "toolbar")
        context (ui/context application scope)
        presses (atom 0)
        root (ui/row! context)
        title (ui/text! context "Signal")
        save (ui/button! context "Save" (fn [_event]
                                           (swap! presses inc)
                                           true))]
    (sig/mount! scope)
    (ui/append! context root title)
    (ui/append! context root save)
    (runtime/flush! application)
    (assert-equal [title save] (apple/children renderer root)
                  "semantic row retains its children")
    (match (apple/property renderer title proto/TextValue)
      (Some (StringValue text))
      (assert-equal "Signal" text "semantic text property")
      _ (is false "semantic text exists"))
    (runtime/dispatch! application (proto/Press save))
    (runtime/flush! application)
    (assert-equal 1 @presses "semantic button dispatches through effects")))

(deftest semantic-content-primitives-retain-structure-and-heading-level
  (let [renderer (apple/create)
        application
        (runtime/create (sig/scheduler) (apple/backend renderer))
        scope (sig/scope "semantic-content")
        root (semantic-content (ui/context application scope))]
    (sig/mount! scope)
    (runtime/flush! application)
    (let [children (apple/children renderer root)
          heading (nth children 0)
          paragraph (nth children 1)]
      (match (apple/node renderer root)
        (Some AppleBox) (is true "box has a retained platform identity")
        _ (is false "box maps to the Apple backend"))
      (match (apple/property renderer root proto/StyleClass)
        (Some (StringValue value))
        (assert-equal "semantic-content" value "Box retains its class")
        _ (is false "Box class reaches the backend"))
      (match (apple/node renderer heading)
        (Some AppleHeading) (is true "heading retains semantic identity")
        _ (is false "heading maps to the Apple backend"))
      (match (apple/node renderer paragraph)
        (Some AppleParagraph) (is true "paragraph retains semantic identity")
        _ (is false "paragraph maps to the Apple backend"))
      (match (apple/property renderer heading proto/HeadingLevel)
        (Some (proto/IntValue level))
        (assert-equal 3 level "heading level reaches the backend")
        _ (is false "heading level is retained")))))

(deftest semantic-content-signals-patch-text-without-replacing-nodes
  (let [scheduler (sig/scheduler)
        renderer (apple/create)
        application (runtime/create scheduler (apple/backend renderer))
        scope (sig/scope "reactive-semantic-content")
        copy (sig/state scheduler "Initial copy")
        root
        (reactive-semantic-content
         (ui/context application scope) (sig/value copy))]
    (sig/mount! scope)
    (runtime/flush! application)
    (let [children (apple/children renderer root)
          heading (nth children 0)
          paragraph (nth children 1)
          node-count (apple/node-count renderer)]
      (sig/set! copy "Updated copy")
      (runtime/flush! application)
      (assert-equal node-count (apple/node-count renderer)
                    "Signal copy updates preserve semantic nodes")
      (match (apple/property renderer heading proto/TextValue)
        (Some (StringValue value))
        (assert-equal "Updated copy" value "Heading patches TextValue")
        _ (is false "Heading retains reactive text"))
      (match (apple/property renderer paragraph proto/TextValue)
        (Some (StringValue value))
        (assert-equal "Updated copy" value "Paragraph patches TextValue")
        _ (is false "Paragraph retains reactive text")))))

(deftest card-composes-public-parts-from-semantic-retained-primitives
  (let [renderer (apple/create)
        application
        (runtime/create (sig/scheduler) (apple/backend renderer))
        scope (sig/scope "profile-card")
        root (profile-card (ui/context application scope) (fn [_event] true))]
    (sig/mount! scope)
    (runtime/flush! application)
    (let [parts (apple/children renderer root)
          header (nth parts 0)
          content (nth parts 1)
          footer (nth parts 2)
          title (nth (apple/children renderer header) 0)
          description (nth (apple/children renderer header) 1)]
      (assert-equal 3 (count parts) "Card retains header, content, and footer")
      (match (apple/property renderer root proto/StyleClass)
        (Some (StringValue value))
        (assert-equal "lui-card profile-card" value
                      "application class follows the Card default")
        _ (is false "Card exposes its resolved class"))
      (match (apple/property renderer header proto/StyleClass)
        (Some (StringValue value))
        (assert-equal "lui-card-header" value "CardHeader class")
        _ (is false "CardHeader exposes its class"))
      (match (apple/property renderer content proto/StyleClass)
        (Some (StringValue value))
        (assert-equal "lui-card-content" value "CardContent class")
        _ (is false "CardContent exposes its class"))
      (match (apple/property renderer footer proto/StyleClass)
        (Some (StringValue value))
        (assert-equal "lui-card-footer" value "CardFooter class")
        _ (is false "CardFooter exposes its class"))
      (match (apple/node renderer title)
        (Some AppleHeading) (is true "CardTitle is a semantic heading")
        _ (is false "CardTitle maps to Heading"))
      (match (apple/property renderer title proto/HeadingLevel)
        (Some (proto/IntValue level))
        (assert-equal 3 level "CardTitle matches Solid UI's h3")
        _ (is false "CardTitle retains heading level"))
      (match (apple/node renderer description)
        (Some AppleParagraph) (is true "CardDescription is a paragraph")
        _ (is false "CardDescription maps to Paragraph")))))

(deftest badge-composes-row-and-text-with-reusable-surface-properties
  (let [renderer (apple/create)
        application
        (runtime/create (sig/scheduler) (apple/backend renderer))
        scope (sig/scope "status-badges")
        root (status-badges (ui/context application scope))]
    (sig/mount! scope)
    (runtime/flush! application)
    (let [badges (apple/children renderer root)
          badge (nth badges 1)
          label (nth (apple/children renderer badge) 0)]
      (assert-equal 2 (count badges) "Badge adds no wrapper beyond its Row")
      (match (apple/node renderer badge)
        (Some AppleRow) (is true "Badge reuses the Row primitive")
        _ (is false "Badge must not introduce a platform node kind"))
      (match (apple/node renderer label)
        (Some AppleLabel) (is true "Badge text reuses the Text primitive")
        _ (is false "Badge content remains semantic text"))
      (match (apple/property renderer badge proto/StyleClass)
        (Some (StringValue value))
        (assert-equal
         "lui-badge lui-badge--success lui-badge--round sync-status"
         value
         "Badge exposes Solid UI variant selectors")
        _ (is false "Badge retains its semantic classes"))
      (match (apple/property renderer badge proto/PaddingHorizontal)
        (Some (proto/IntValue value))
        (assert-equal 10 value "Badge uses reusable horizontal padding")
        _ (is false "Badge retains horizontal padding"))
      (match (apple/property renderer badge proto/PaddingVertical)
        (Some (proto/IntValue value))
        (assert-equal 2 value "Badge uses reusable vertical padding")
        _ (is false "Badge retains vertical padding"))
      (match (apple/property renderer badge proto/BackgroundValue)
        (Some (StringValue value))
        (assert-equal "success" value "Badge background is semantic")
        _ (is false "Badge retains its background"))
      (match (apple/property renderer badge proto/BorderColorValue)
        (Some (StringValue value))
        (assert-equal
         "success-foreground" value "Badge border is semantic")
        _ (is false "Badge retains its border color"))
      (match (apple/property renderer badge proto/BorderWidth)
        (Some (proto/IntValue value))
        (assert-equal 1 value "Badge border uses a Surface property")
        _ (is false "Badge retains its border width"))
      (match (apple/property renderer badge proto/CornerRadius)
        (Some (proto/IntValue value))
        (assert-equal 999 value "round Badge uses a reusable radius")
        _ (is false "Badge retains its corner radius"))
      (match (apple/property renderer label proto/ForegroundValue)
        (Some (StringValue value))
        (assert-equal
         "success-foreground" value "Badge content uses foreground")
        _ (is false "Badge retains its content color")))))

(deftest progress-composes-public-parts-around-one-native-control
  (let [scheduler (sig/scheduler)
        renderer (apple/create)
        application (runtime/create scheduler (apple/backend renderer))
        scope (sig/scope "task-progress")
        completed (sig/state scheduler 3)
        completed-label (sig/state scheduler "3 of 10 tasks completed")
        root
        (task-progress
         (ui/context application scope)
         (sig/value completed)
         (sig/value completed-label))]
    (sig/mount! scope)
    (runtime/flush! application)
    (let [parts (apple/children renderer root)
          label (nth parts 0)
          value-label (nth parts 1)
          control (nth parts 2)
          node-count (apple/node-count renderer)]
      (assert-equal 3 (count parts)
                    "Progress retains two public parts and one control")
      (match (apple/node renderer root)
        (Some AppleColumn) (is true "Progress root composes Column")
        _ (is false "Progress root maps to Column"))
      (match (apple/node renderer label)
        (Some AppleFormLabel) (is true "ProgressLabel is semantic")
        _ (is false "ProgressLabel maps to Label"))
      (match (apple/node renderer value-label)
        (Some AppleFormLabel) (is true "ProgressValueLabel is semantic")
        _ (is false "ProgressValueLabel maps to Label"))
      (match (apple/node renderer control)
        (Some AppleProgress) (is true "Progress uses one native control")
        _ (is false "Progress maps to the progress primitive"))
      (match (apple/property renderer root proto/StyleClass)
        (Some (StringValue value))
        (assert-equal "lui-progress task-progress" value
                      "Progress exposes one semantic root class")
        _ (is false "Progress root class"))
      (match (apple/property renderer control proto/MinValue)
        (Some (proto/IntValue value))
        (assert-equal 0 value "Progress retains min-value")
        _ (is false "Progress min-value"))
      (match (apple/property renderer control proto/MaxValue)
        (Some (proto/IntValue value))
        (assert-equal 10 value "Progress retains max-value")
        _ (is false "Progress max-value"))
      (match (apple/property renderer control proto/ProgressValue)
        (Some (proto/IntValue value))
        (assert-equal 3 value "Progress retains its Signal value")
        _ (is false "Progress value"))
      (match (apple/property renderer control proto/LabelledBy)
        (Some (proto/IntValue value))
        (assert-equal label value "ProgressControl references ProgressLabel")
        _ (is false "Progress label relationship"))
      (sig/set! completed 8)
      (runtime/flush! application)
      (assert-equal node-count (apple/node-count renderer)
                    "value patches preserve the retained component tree")
      (assert-equal control (nth (apple/children renderer root) 2)
                    "value patches preserve ProgressControl identity")
      (match (apple/property renderer control proto/ProgressValue)
        (Some (proto/IntValue value))
        (assert-equal 8 value "the value Signal patches ProgressControl")
        _ (is false "patched Progress value")))))

(deftest text-field-composes-semantic-parts-and-patches-invalid-in-place
  (let [scheduler (sig/scheduler)
        renderer (apple/create)
        application (runtime/create scheduler (apple/backend renderer))
        scope (sig/scope "email-field")
        value (sig/state scheduler "")
        invalid (sig/state scheduler false)
        disabled (sig/state scheduler false)
        root
        (email-field
         (ui/context application scope)
         (sig/value value)
         (sig/value invalid)
         (sig/value disabled)
         (fn [_event] true))]
    (sig/mount! scope)
    (runtime/flush! application)
    (let [parts (apple/children renderer root)
          label (nth parts 0)
          input (nth parts 1)
          description (nth parts 2)
          error (nth parts 3)
          node-count (apple/node-count renderer)]
      (assert-equal 4 (count parts) "TextField retains all public parts")
      (match (apple/property renderer root proto/StyleClass)
        (Some (StringValue value))
        (assert-equal "lui-text-field account-email" value
                      "TextField exposes one semantic root class")
        _ (is false "TextField exposes its resolved class"))
      (match (apple/node renderer label)
        (Some AppleFormLabel) (is true "TextFieldLabel is semantic")
        _ (is false "TextFieldLabel maps to Label"))
      (match (apple/node renderer input)
        (Some AppleTextInput) (is true "TextFieldInput is semantic")
        _ (is false "TextFieldInput maps to TextInput"))
      (match (apple/property renderer label proto/StyleClass)
        (Some (StringValue value))
        (assert-equal "lui-text-field-label" value "label class")
        _ (is false "label class"))
      (match (apple/property renderer input proto/StyleClass)
        (Some (StringValue value))
        (assert-equal "lui-text-field-input" value "input class")
        _ (is false "input class"))
      (match (apple/property renderer description proto/StyleClass)
        (Some (StringValue value))
        (assert-equal
         "lui-text-field-description" value "description class")
        _ (is false "description class"))
      (match (apple/property renderer error proto/StyleClass)
        (Some (StringValue value))
        (assert-equal
         "lui-text-field-error-message" value "error class")
        _ (is false "error class"))
      (match (apple/property renderer input proto/LabelledBy)
        (Some (proto/IntValue value))
        (assert-equal label value "input references its label")
        _ (is false "input references its label"))
      (match (apple/property renderer input proto/DescribedBy)
        (Some (proto/IntValue value))
        (assert-equal description value "input references description")
        _ (is false "input references description"))
      (match (apple/property renderer input proto/ErrorMessageBy)
        (Some (proto/IntValue value))
        (assert-equal error value "input references error")
        _ (is false "input references error"))
      (match (apple/property renderer input proto/InputType)
        (Some (StringValue value))
        (assert-equal "email" value "TextFieldInput retains its type")
        _ (is false "TextFieldInput retains its type"))
      (sig/set! invalid true)
      (runtime/flush! application)
      (assert-equal node-count (apple/node-count renderer)
                    "invalid Signal does not replace retained nodes")
      (assert-equal input (nth (apple/children renderer root) 1)
                    "invalid Signal preserves control identity")
      (match (apple/property renderer input proto/Invalid)
        (Some (proto/BoolValue value))
        (assert-equal true value "invalid Signal patches one property")
        _ (is false "invalid Signal reaches the input"))
      (sig/set! disabled true)
      (runtime/flush! application)
      (assert-equal node-count (apple/node-count renderer)
                    "disabled Signal does not replace retained nodes")
      (match (apple/property renderer input proto/Enabled)
        (Some (proto/BoolValue value))
        (assert-equal false value "disabled Signal patches Enabled")
        _ (is false "disabled Signal reaches the input")))))

(deftest toggle-components-patch-native-controls-without-replacing-them
  (let [scheduler (sig/scheduler)
        renderer (apple/create)
        application (runtime/create scheduler (apple/backend renderer))
        scope (sig/scope "settings-toggles")
        checked (sig/state scheduler false)
        indeterminate (sig/state scheduler true)
        disabled (sig/state scheduler false)
        invalid (sig/state scheduler false)
        root
        (settings-toggles
         (ui/context application scope)
         (sig/value checked)
         (sig/value indeterminate)
         (sig/value disabled)
         (sig/value invalid)
         (fn [_event] true)
         (fn [_event] true))]
    (sig/mount! scope)
    (runtime/flush! application)
    (let [children (apple/children renderer root)
          checkbox (nth children 0)
          switch-root (nth children 1)
          switch-parts (apple/children renderer switch-root)
          control (nth switch-parts 0)
          label (nth switch-parts 1)
          description (nth switch-parts 2)
          error (nth switch-parts 3)
          thumb (nth (apple/children renderer control) 0)
          node-count (apple/node-count renderer)]
      (match (apple/node renderer checkbox)
        (Some AppleCheckbox) (is true "Checkbox maps to a native control")
        _ (is false "Checkbox native mapping"))
      (match (apple/node renderer control)
        (Some AppleSwitch) (is true "SwitchControl maps to a native switch")
        _ (is false "SwitchControl native mapping"))
      (match (apple/node renderer thumb)
        (Some AppleBox) (is true "SwitchThumb remains a retained visual part")
        _ (is false "SwitchThumb retained mapping"))
      (match (apple/property renderer control proto/LabelledBy)
        (Some (proto/IntValue value))
        (assert-equal label value "SwitchControl references SwitchLabel")
        _ (is false "Switch label relationship"))
      (match (apple/property renderer control proto/DescribedBy)
        (Some (proto/IntValue value))
        (assert-equal description value "SwitchControl references description")
        _ (is false "Switch description relationship"))
      (match (apple/property renderer control proto/ErrorMessageBy)
        (Some (proto/IntValue value))
        (assert-equal error value "SwitchControl references error")
        _ (is false "Switch error relationship"))
      (match (apple/property renderer checkbox proto/Indeterminate)
        (Some (proto/BoolValue value))
        (assert-equal true value "Checkbox retains indeterminate Signal")
        _ (is false "Checkbox indeterminate state"))
      (sig/set! checked true)
      (sig/set! indeterminate false)
      (sig/set! invalid true)
      (runtime/flush! application)
      (assert-equal node-count (apple/node-count renderer)
                    "toggle Signals preserve the retained tree")
      (assert-equal checkbox (nth (apple/children renderer root) 0)
                    "Checkbox identity is stable")
      (assert-equal control
                    (nth (apple/children renderer switch-root) 0)
                    "Switch identity is stable")
      (match (apple/property renderer control proto/Checked)
        (Some (proto/BoolValue value))
        (assert-equal true value "checked Signal patches SwitchControl")
        _ (is false "Switch checked state"))
      (match (apple/property renderer control proto/Invalid)
        (Some (proto/BoolValue value))
        (assert-equal true value "invalid Signal patches SwitchControl")
        _ (is false "Switch invalid state")))))

(deftest reactive-text-input-updates-through-semantic-events
  (let [scheduler (sig/scheduler)
        renderer (apple/create)
        application (runtime/create scheduler (apple/backend renderer))
        scope (sig/scope "input")
        context (ui/context application scope)
        draft (sig/state scheduler "")
        value
        (sig/map (fn [text] (proto/StringValue text)) (sig/value draft))
        input
        (ui/text-input-value!
         context value
         (fn [event]
           (match event
             (TextChanged _node text) (sig/set! draft text)
             _ true)))]
    (sig/mount! scope)
    (runtime/flush! application)
    (runtime/dispatch! application (proto/TextChanged input "new todo"))
    (runtime/flush! application)
    (assert-equal "new todo" (sig/get draft) "input event updates LG state")
    (match (apple/property renderer input proto/TextValue)
      (Some (StringValue text))
      (assert-equal "new todo" text "state updates retained input text")
      _ (is false "reactive input text exists"))))

(deftest declarative-text-input-preserves-native-semantics
  (let [scheduler (sig/scheduler)
        renderer (apple/create)
        application (runtime/create scheduler (apple/backend renderer))
        scope (sig/scope "accessible-input")
        context (ui/context application scope)
        draft (sig/state scheduler "")
        input
        (accessible-search context (sig/value draft) (fn [_event] true))]
    (sig/mount! scope)
    (runtime/flush! application)
    (match (apple/property renderer input proto/PlaceholderValue)
      (Some (StringValue value))
      (assert-equal "Search" value "placeholder reaches the backend")
      _ (is false "placeholder is present"))
    (match (apple/property renderer input proto/ReadOnly)
      (Some (proto/BoolValue value))
      (assert-equal true value "readonly reaches the backend")
      _ (is false "readonly is present"))
    (match (apple/property renderer input proto/AccessibilityLabel)
      (Some (StringValue value))
      (assert-equal "Search todos" value "accessible name reaches the backend")
      _ (is false "accessible name is present"))))

(deftest declarative-text-area-maps-provider-sizing-semantics
  (let [scheduler (sig/scheduler)
        renderer (apple/create)
        application (runtime/create scheduler (apple/backend renderer))
        scope (sig/scope "bounded-notes")
        context (ui/context application scope)
        notes (sig/state scheduler "One line")
        node
        (bounded-notes
         context
         (sig/value notes)
         (fn [event]
           (match event
             (TextChanged _node text) (sig/set! notes text)
             _ true)))]
    (sig/mount! scope)
    (runtime/flush! application)
    (match (apple/property renderer node proto/MinLines)
      (Some (proto/IntValue lines))
      (assert-equal 2 lines "minimum lines reach the provider")
      _ (is false "minimum lines are present"))
    (match (apple/property renderer node proto/MaxLines)
      (Some (proto/IntValue lines))
      (assert-equal 5 lines "maximum lines reach the provider")
      _ (is false "maximum lines are present"))
    (runtime/dispatch! application (proto/TextChanged node "One\nTwo"))
    (runtime/flush! application)
    (assert-equal "One\nTwo" (sig/get notes) "text area updates LG state")))

(deftest solid-button-disabled-state-is-signal-controlled
  (let [scheduler (sig/scheduler)
        renderer (apple/create)
        application (runtime/create scheduler (apple/backend renderer))
        scope (sig/scope "controlled-delete-button")
        context (ui/context application scope)
        disabled (sig/state scheduler false)
        button
        (controlled-delete-button
         context (sig/value disabled) (fn [_event] true))]
    (sig/mount! scope)
    (runtime/flush! application)
    (match (apple/property renderer button proto/Enabled)
      (Some (proto/BoolValue enabled))
      (assert-equal true enabled "false disabled state enables the button")
      _ (is false "button exposes its enabled state"))
    (let [node-count (apple/node-count renderer)]
      (sig/set! disabled true)
      (runtime/flush! application)
      (assert-equal
       node-count (apple/node-count renderer)
       "Signal state patches the retained button without replacing it"))
    (match (apple/property renderer button proto/Enabled)
      (Some (proto/BoolValue enabled))
      (assert-equal false enabled "true disabled state disables the button")
      _ (is false "updated button exposes its enabled state"))))

(deftest solid-button-resolves-reference-variants-and-class-order
  (let [scheduler (sig/scheduler)
        renderer (apple/create)
        application (runtime/create scheduler (apple/backend renderer))
        scope (sig/scope "solid-button-variants")
        context (ui/context application scope)
        disabled (sig/state scheduler false)
        destructive
        (controlled-delete-button
         context (sig/value disabled) (fn [_event] true))
        default-button (default-solid-button context (fn [_event] true))]
    (sig/mount! scope)
    (runtime/flush! application)
    (match (apple/property renderer destructive proto/StyleClass)
      (Some (StringValue value))
      (assert-equal
       "lui-button--destructive lui-button--sm danger-zone-action"
       value
       "application class follows the resolved Solid UI variant classes")
      _ (is false "destructive button exposes retained style classes"))
    (match (apple/property renderer default-button proto/StyleClass)
      (Some (StringValue value))
      (assert-equal
       "lui-button--default lui-button--size-default"
       value
       "omitted props resolve to Solid UI's default variant and size")
      _ (is false "default button exposes retained style classes"))))
