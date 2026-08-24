(ns lui.authoring-test
  (:require [clojure.test :refer [deftest is]]
            [signal.core :as sig]
            [lui.protocol :as proto :refer [StringValue TextChanged]]
            [lui.runtime :as runtime]
            [lui.ui :as ui]
            [lui.elements :refer [defcomponent defelement]]
            [lui.badge]
            [lui.separator]
            [lui.skeleton]
            [lui.macros :refer [defui state effect platform host]]
            [lui.backend.apple :as apple
             :refer [AppleBox AppleCard AppleCheckbox AppleColumn AppleFormLabel AppleGrid
                     AppleHeading AppleDivider AppleParagraph AppleProgress AppleRow AppleSpinner AppleSwitch
                     AppleList ApplePanel AppleScrollView AppleStack AppleTextInput]]
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

(defui declarative-conditional [visible]
  [:column
   [:text "before"]
   [:if {:test visible}
    [:text "visible"]]
   [:text "after"]])

(defelement badge [context parent _attrs & children]
  `(lui.elements/text ~context ~parent {} ~@children))

(defcomponent simple-panel :box {:class "simple-panel"})

(defui custom-element-view []
  [:lui.authoring-test/badge "Extensible"])

(defui simple-component-view []
  [:lui.authoring-test/simple-panel {:class "profile-panel"}
   [:text "Declarative"]])

(defui loading-placeholder []
  [:skeleton
   {:width 120
    :height 16
    :min-width 80
    :max-width 160
    :class "profile-loading"}])

(defui activity-indicators []
  [:row {:gap 12 :cross "center"}
   [:spinner]
   [:spinner {:size "sm"}]
   [:spinner {:size "lg" :foreground "primary"}]
   [:spinner {:size "icon"}]])

(defui vercel-layout-primitives []
  [:column {:gap 12 :main "center" :cross "stretch"}
   [:row {:gap 8 :main "space_between" :cross "end"}
    [:text {:grow 1.0} "Leading"]
    [:text "Trailing"]]
   [:grid {:columns 2 :gap 6}
    [:text "One"]
    [:text "Two"]
    [:text "Three"]]])

(defui collection-containers [copy-source]
  [:row {:gap 16}
   [:list {:gap 6 :main "center" :cross "stretch"}
    [:text "First item"]
    [:text "Second item"]]
   [:scroll {:width 160 :height 80}
    [:text "Base scroll layer"]
    [:text {:value copy-source}]]])

(defui current-platform-profile []
  (tuple (platform) (host)))

(defui text-entry-set [draft notes disabled on-input on-submit]
  [:column
   [:text-field
    {:text draft
     :placeholder "Project name"
     :disabled disabled
     :autofocus true
     :label "Project name"
     :on-input on-input
     :on-submit on-submit}]
   [:input
    {:text "Literal input"
     :placeholder "Email address"
     :on-input on-input}]
   [:search-field
    {:text draft
     :placeholder "Search todos"
     :on-input on-input
     :on-submit on-submit}]
   [:textarea
    {:text notes
     :placeholder "Notes"
     :disabled disabled
     :submit-on-enter true
     :on-input on-input
     :on-submit on-submit}]])

(defui controlled-delete-button [disabled-source callback]
  [:button
   {:variant "destructive"
    :size "sm"
    :class "danger-zone-action"
    :disabled disabled-source
    :on-press callback}
   "Delete"])

(defui default-button [callback]
  [:button {:on-press callback} "Continue"])

(defui retained-vercel-button
  [text-source disabled-source selected-source autofocus-source on-press on-hold]
  [:button
   {:text text-source
    :variant "primary"
    :size "lg"
    :icon "download"
    :icon-placement "trailing"
    :disabled disabled-source
    :selected selected-source
    :autofocus autofocus-source
    :label "Download report"
    :on-press on-press
    :on-hold on-hold}])

(defui icon-action-button [callback]
  [:button
   {:variant "ghost"
    :size "icon"
    :icon "plus"
    :selected true
    :autofocus true
    :label "New note"
    :on-press callback}])

(defui formatting-toggle [selected-source on-toggle on-hold]
  [:toggle-button
   {:variant "outline"
    :size "sm"
    :icon "edit"
    :selected selected-source
    :label "Bold formatting"
    :on-toggle on-toggle
    :on-hold on-hold}
   "Bold"])

(defui semantic-content []
  [:box {:class "semantic-content"}
   [:heading {:level 3} "Account"]
   [:paragraph "Manage your profile settings."]])

(defui reactive-semantic-content [source]
  [:box
   [:heading {:level 2 :value source}]
   [:paragraph {:value source}]])

(defui overlay-surfaces [copy-source]
  [:stack {:width 320 :height 180}
   [:panel {:padding 12}
    [:text "Panel layer"]]
   [:card
    [:text {:value copy-source}]]])

(defui status-badges []
  [:column
   [:badge "Default"]
   [:badge
    {:variant "success" :round true :class "sync-status"}
    "Synchronized"]])

(defui task-progress [completed]
  [:progress {:value completed :width 240 :class "task-progress"}])

(defui literal-progress []
  [:progress {:value 0.5}])

(defui content-separators []
  [:column
   [:separator]
   [:separator {:orientation "vertical" :class "content-divider"}]])

(defui settings-toggles
  [checked disabled checkbox-text switch-text checkbox-toggle switch-toggle]
  [:column
   [:checkbox
    {:checked checked
     :disabled disabled
     :text checkbox-text
     :label "Select all"
     :on-toggle checkbox-toggle}]
   [:switch
    {:checked checked
     :disabled disabled
     :text switch-text
     :on-toggle switch-toggle}]])

(defui value-control-batch
  [checked slider-value disabled toggle-change radio-change slider-change]
  [:column
   [:toggle
    {:checked checked
     :disabled disabled
     :label "Bold formatting"
     :on-toggle toggle-change}
    "Bold"]
   [:radio-group {:label "Density"}
    [:radio
     {:checked checked
      :disabled disabled
      :on-change radio-change}
     "Comfortable"]
    [:radio
     {:selected true
      :disabled disabled
      :on-toggle radio-change}
     "Compact"]]
   [:slider
    {:value slider-value
     :disabled disabled
     :label "Volume"
     :on-change slider-change}]
   [:slider {:value 0.5 :label "Balance"}]])

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

(deftest defui-if-is-a-placeholder-free-retained-conditional
  (let [scheduler (sig/scheduler)
        renderer (apple/create)
        application (runtime/create scheduler (apple/backend renderer))
        scope (sig/scope "declarative-conditional")
        context (ui/context application scope)
        visible (sig/state scheduler false)
        root (declarative-conditional context (sig/value visible))]
    (sig/mount! scope)
    (runtime/flush! application)
    (assert-equal 2 (count (apple/children renderer root))
                  "false declarative if has no wrapper or placeholder")
    (sig/set! visible true)
    (runtime/flush! application)
    (assert-equal 3 (count (apple/children renderer root))
                  "true declarative if inserts one retained child")
    (sig/set! visible false)
    (runtime/flush! application)
    (assert-equal 2 (count (apple/children renderer root))
                  "declarative if removes its child again")))

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

(deftest defcomponent-composes-a-primitive-without-node-plumbing
  (let [renderer (apple/create)
        application
        (runtime/create (sig/scheduler) (apple/backend renderer))
        scope (sig/scope "simple-component")
        root (simple-component-view (ui/context application scope))]
    (sig/mount! scope)
    (runtime/flush! application)
    (match (apple/property renderer root proto/StyleClass)
      (Some (StringValue value))
      (assert-equal
       "simple-panel profile-panel" value
       "component defaults and caller classes are merged")
      _ (is false "component root exposes its style class"))
    (assert-equal 1 (count (apple/children renderer root))
                  "component children are mounted automatically")))

(deftest skeleton-is-a-declarative-sized-surface
  (let [renderer (apple/create)
        application
        (runtime/create (sig/scheduler) (apple/backend renderer))
        root
        (loading-placeholder
         (ui/context application (sig/scope "loading-placeholder")))]
    (runtime/flush! application)
    (match (apple/node renderer root)
      (Some AppleBox) (is true "Skeleton reuses the Box primitive")
      _ (is false "Skeleton must not introduce a platform node kind"))
    (match (apple/property renderer root proto/StyleClass)
      (Some (StringValue value))
      (assert-equal "lui-skeleton profile-loading" value
                    "Skeleton exposes its semantic class")
      _ (is false "Skeleton retains its class"))
    (doseq [constraint
            [(tuple proto/WidthValue 120)
             (tuple proto/HeightValue 16)
             (tuple proto/MinWidth 80)
             (tuple proto/MaxWidth 160)]]
      (match constraint
        (tuple property expected)
        (match (apple/property renderer root property)
          (Some (proto/IntValue value))
          (assert-equal expected value
                        "component sizing flows through shared Surface props")
          _ (is false "Skeleton retains its size constraints"))))))

(deftest spinner-is-a-direct-sized-progress-leaf
  (let [renderer (apple/create)
        application
        (runtime/create (sig/scheduler) (apple/backend renderer))
        root
        (activity-indicators
         (ui/context application (sig/scope "activity-indicators")))]
    (runtime/flush! application)
    (let [spinners (apple/children renderer root)]
      (assert-equal 4 (count spinners) "all Spinner sizes are retained")
      (doseq [spinner spinners]
        (match (apple/node renderer spinner)
          (Some AppleSpinner) (is true "Spinner maps to a native progress leaf")
          _ (is false "Spinner must keep its semantic node kind")))
      (assert-equal None
                    (apple/property renderer (nth spinners 0) proto/SizeValue)
                    "an omitted size keeps the Vercel Native default")
      (doseq [expected [(tuple 1 "sm") (tuple 2 "lg") (tuple 3 "icon")]]
        (match expected
          (tuple index size)
          (assert-equal
           (Some (proto/StringValue size))
           (apple/property renderer (nth spinners index) proto/SizeValue)
           "Spinner retains its closed size rung")))
      (assert-equal
       (Some (proto/StringValue "primary"))
       (apple/property renderer (nth spinners 2) proto/ForegroundValue)
       "Spinner tint uses the shared foreground token"))))

(deftest vercel-layout-primitives-lower-without-an-extra-flex-api
  (let [renderer (apple/create)
        application
        (runtime/create (sig/scheduler) (apple/backend renderer))
        root
        (vercel-layout-primitives
         (ui/context application (sig/scope "vercel-layout")))]
    (runtime/flush! application)
    (let [children (apple/children renderer root)
          row (nth children 0)
          grid (nth children 1)
          leading (nth (apple/children renderer row) 0)]
      (match (apple/node renderer root)
        (Some AppleColumn) (is true "Column remains the vertical primitive")
        _ (is false "the root is a retained Column"))
      (match (apple/node renderer row)
        (Some AppleRow) (is true "Row remains the horizontal primitive")
        _ (is false "the first child is a retained Row"))
      (match (apple/node renderer grid)
        (Some AppleGrid) (is true "Grid is one semantic retained primitive")
        _ (is false "the second child is a retained Grid"))
      (doseq [constraint
              [(tuple root proto/MainAlignment
                      (proto/StringValue "center"))
               (tuple root proto/CrossAlignment
                      (proto/StringValue "stretch"))
               (tuple row proto/MainAlignment
                      (proto/StringValue "space_between"))
               (tuple row proto/CrossAlignment
                      (proto/StringValue "end"))
               (tuple leading proto/GrowValue (proto/FloatValue 1.0))
               (tuple grid proto/GridColumns (proto/IntValue 2))]]
        (match constraint
          (tuple node property expected)
          (assert-equal
           (Some expected)
           (apple/property renderer node property)
           "layout attrs retain the exact Vercel Native vocabulary"))))))

(deftest list-flows-while-scroll-retains-multiple-overlay-children
  (let [scheduler (sig/scheduler)
        renderer (apple/create)
        application (runtime/create scheduler (apple/backend renderer))
        copy (sig/state scheduler "Overlay copy")
        root
        (collection-containers
         (ui/context application (sig/scope "collections")) (sig/value copy))]
    (runtime/flush! application)
    (let [containers (apple/children renderer root)
          list-node (nth containers 0)
          scroll-node (nth containers 1)
          overlay-copy (nth (apple/children renderer scroll-node) 1)
          node-count (apple/node-count renderer)]
      (match (apple/node renderer list-node)
        (Some AppleList) (is true "List is a direct vertical flow node")
        _ (is false "List must map to List"))
      (match (apple/node renderer scroll-node)
        (Some AppleScrollView) (is true "Scroll keeps its native identity")
        _ (is false "Scroll must map to ScrollView"))
      (assert-equal 2 (count (apple/children renderer list-node))
                    "List retains every flow item")
      (assert-equal 2 (count (apple/children renderer scroll-node))
                    "Scroll admits multiple overlay children")
      (assert-equal (Some (proto/IntValue 6))
                    (apple/property renderer list-node proto/Gap)
                    "List retains its flow gap")
      (sig/set! copy "Updated overlay")
      (runtime/flush! application)
      (assert-equal node-count (apple/node-count renderer)
                    "scroll content patches without replacing containers")
      (assert-equal (Some (StringValue "Updated overlay"))
                    (apple/property renderer overlay-copy proto/TextValue)
                    "the dependent scroll child patches locally"))))

(deftest semantic-builders-produce-retained-ui
  (let [scheduler (sig/scheduler)
        renderer (apple/create)
        application (runtime/create scheduler (apple/backend renderer))
        scope (sig/scope "toolbar")
        context (ui/context application scope)
        presses (atom 0)
        root (ui/row! context)
        title (ui/text! context "Signal")
        save (ui/button! context)]
    (ui/text-property! context save "Save")
    (ui/on-event! context save (fn [_event]
                                 (swap! presses inc)
                                 true))
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

(deftest overlay-surfaces-are-direct-retained-nodes
  (let [renderer (apple/create)
        scheduler (sig/scheduler)
        application
        (runtime/create scheduler (apple/backend renderer))
        copy (sig/state scheduler "Retained card")
        scope (sig/scope "overlay-surfaces")
        root (overlay-surfaces (ui/context application scope) (sig/value copy))]
    (sig/mount! scope)
    (runtime/flush! application)
    (let [layers (apple/children renderer root)
          panel (nth layers 0)
          card (nth layers 1)
          card-copy (nth (apple/children renderer card) 0)
          node-count (apple/node-count renderer)]
      (match (apple/node renderer root)
        (Some AppleStack) (is true "Stack is a direct overlay node")
        _ (is false "Stack must map to Stack"))
      (match (apple/node renderer panel)
        (Some ApplePanel) (is true "Panel is a direct surface node")
        _ (is false "Panel must map to Panel"))
      (match (apple/node renderer card)
        (Some AppleCard) (is true "Card is a direct surface node")
        _ (is false "Card must map to Card"))
      (assert-equal 2 (count layers) "Stack retains both overlay layers")
      (sig/set! copy "Updated card")
      (runtime/flush! application)
      (assert-equal node-count (apple/node-count renderer)
                    "reactive card content preserves every retained node")
      (match (apple/property renderer card-copy proto/TextValue)
        (Some (StringValue value))
        (assert-equal "Updated card" value "Card content patches locally")
        _ (is false "Card text remains retained")))))

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

(deftest progress-is-one-fractional-retained-native-control
  (let [scheduler (sig/scheduler)
        renderer (apple/create)
        application (runtime/create scheduler (apple/backend renderer))
        scope (sig/scope "task-progress")
        completed (sig/state scheduler 0.3)
        root
        (task-progress
         (ui/context application scope)
         (sig/value completed))]
    (sig/mount! scope)
    (runtime/flush! application)
    (let [node-count (apple/node-count renderer)]
      (match (apple/node renderer root)
        (Some AppleProgress) (is true "Progress maps directly to native progress")
        _ (is false "Progress must be one retained progress node"))
      (assert-equal [] (apple/children renderer root)
                    "Progress does not expose compound public parts")
      (match (apple/property renderer root proto/StyleClass)
        (Some (StringValue value))
        (assert-equal "task-progress" value "Progress keeps its style class")
        _ (is false "Progress root class"))
      (match (apple/property renderer root proto/ProgressValue)
        (Some (proto/FloatValue value))
        (assert-equal 0.3 value "Progress retains its fractional Signal value")
        _ (is false "Progress value"))
      (sig/set! completed 0.8)
      (runtime/flush! application)
      (assert-equal node-count (apple/node-count renderer)
                    "value patches preserve retained identity")
      (match (apple/property renderer root proto/ProgressValue)
        (Some (proto/FloatValue value))
        (assert-equal 0.8 value "the Signal patches Progress in place")
        _ (is false "patched Progress value")))
    (let [literal-root (literal-progress (ui/context application scope))]
      (runtime/flush! application)
      (match (apple/property renderer literal-root proto/ProgressValue)
        (Some (proto/FloatValue value))
        (assert-equal 0.5 value "Progress accepts a float literal")
        _ (is false "literal Progress value")))))

(deftest separator-maps-orientation-to-retained-native-leaves
  (let [renderer (apple/create)
        application
        (runtime/create (sig/scheduler) (apple/backend renderer))
        root
        (content-separators
         (ui/context application (sig/scope "content-separators")))]
    (runtime/flush! application)
    (let [children (apple/children renderer root)
          horizontal (nth children 0)
          vertical (nth children 1)]
      (assert-equal 2 (count children) "Separator creates one leaf per form")
      (match (apple/node renderer horizontal)
        (Some AppleDivider) (is true "horizontal Separator uses Divider")
        _ (is false "horizontal Separator native mapping"))
      (match (apple/node renderer vertical)
        (Some AppleDivider) (is true "vertical Separator uses Divider")
        _ (is false "vertical Separator native mapping"))
      (match (apple/property renderer horizontal proto/OrientationValue)
        (Some (StringValue value))
        (assert-equal "horizontal" value "Separator defaults to horizontal")
        _ (is false "horizontal Separator orientation"))
      (match (apple/property renderer vertical proto/OrientationValue)
        (Some (StringValue value))
        (assert-equal "vertical" value "Separator accepts vertical")
        _ (is false "vertical Separator orientation"))
      (match (apple/property renderer vertical proto/StyleClass)
        (Some (StringValue value))
        (assert-equal
         "lui-separator content-divider" value
         "Separator retains its semantic class and override")
        _ (is false "Separator semantic class")))))

(deftest direct-text-entry-elements-patch-signals-and-route-events
  (let [scheduler (sig/scheduler)
        renderer (apple/create)
        application (runtime/create scheduler (apple/backend renderer))
        scope (sig/scope "text-entry")
        draft (sig/state scheduler "Draft")
        notes (sig/state scheduler "One line")
        disabled (sig/state scheduler false)
        received (atom [])
        on-input
        (fn [event]
          (do
            (swap! received conj event)
            (match event
              (TextChanged _node text) (sig/set! draft text)
              _ true)))
        on-submit (fn [event] (do (swap! received conj event) true))
        root
        (text-entry-set
         (ui/context application scope)
         (sig/value draft)
         (sig/value notes)
         (sig/value disabled)
         on-input on-submit)]
    (sig/mount! scope)
    (runtime/flush! application)
    (let [entries (apple/children renderer root)
          text-field (nth entries 0)
          input (nth entries 1)
          search-field (nth entries 2)
          textarea (nth entries 3)
          node-count (apple/node-count renderer)]
      (assert-equal 4 (count entries) "all direct text-entry kinds mount")
      (doseq [node [text-field input search-field]]
        (match (apple/node renderer node)
          (Some AppleTextInput) (is true "single-line entry is native")
          _ (is false "single-line entry maps to Apple text input")))
      (match (apple/node renderer textarea)
        (Some AppleTextArea) (is true "textarea is native multiline entry")
        _ (is false "textarea maps to Apple multiline input"))
      (match (apple/property renderer input proto/TextValue)
        (Some (StringValue value))
        (assert-equal "Literal input" value "input accepts literal text")
        _ (is false "literal input text"))
      (match (apple/property renderer text-field proto/Autofocus)
        (Some (proto/BoolValue value))
        (assert-equal true value "autofocus reaches the retained node")
        _ (is false "autofocus property"))
      (match (apple/property renderer textarea proto/SubmitOnEnter)
        (Some (proto/BoolValue value))
        (assert-equal true value "textarea keeps its Enter policy")
        _ (is false "submit-on-enter property"))
      (runtime/dispatch!
       application (proto/TextChanged search-field "Updated"))
      (runtime/dispatch! application (proto/Submit text-field))
      (runtime/flush! application)
      (assert-equal "Updated" (sig/get draft) "on-input updates shared state")
      (assert-equal
       [(proto/TextChanged search-field "Updated") (proto/Submit text-field)]
       @received
       "input and submit callbacks stay distinct")
      (match (apple/property renderer text-field proto/TextValue)
        (Some (StringValue value))
        (assert-equal "Updated" value "Signal patches retained text")
        _ (is false "patched text-field value"))
      (assert-equal node-count (apple/node-count renderer)
                    "text edits do not replace retained nodes")
      (sig/set! disabled true)
      (runtime/flush! application)
      (match (apple/property renderer textarea proto/Enabled)
        (Some (proto/BoolValue value))
        (assert-equal false value "disabled Signal patches textarea")
        _ (is false "textarea enabled state")))))

(deftest direct-toggle-controls-patch-text-and-state-without-replacement
  (let [scheduler (sig/scheduler)
        renderer (apple/create)
        application (runtime/create scheduler (apple/backend renderer))
        scope (sig/scope "settings-toggles")
        checked (sig/state scheduler false)
        disabled (sig/state scheduler false)
        checkbox-text (sig/state scheduler "Select everything")
        switch-text (sig/state scheduler "Notifications")
        events (atom [])
        root
        (settings-toggles
         (ui/context application scope)
         (sig/value checked)
         (sig/value disabled)
         (sig/value checkbox-text)
         (sig/value switch-text)
         (fn [event] (swap! events conj event) true)
         (fn [event] (swap! events conj event) true))]
    (sig/mount! scope)
    (runtime/flush! application)
    (let [children (apple/children renderer root)
          checkbox (nth children 0)
          switch-control (nth children 1)
          node-count (apple/node-count renderer)]
      (match (apple/node renderer checkbox)
        (Some AppleCheckbox) (is true "Checkbox maps to a native control")
        _ (is false "Checkbox native mapping"))
      (match (apple/node renderer switch-control)
        (Some AppleSwitch) (is true "SwitchControl maps to a native switch")
        _ (is false "SwitchControl native mapping"))
      (assert-equal 3 node-count
                    "direct controls add no retained implementation parts")
      (match (apple/property renderer checkbox proto/TextValue)
        (Some (StringValue value))
        (assert-equal "Select everything" value "Checkbox retains text")
        _ (is false "Checkbox text"))
      (match (apple/property renderer switch-control proto/TextValue)
        (Some (StringValue value))
        (assert-equal "Notifications" value "Switch retains text")
        _ (is false "Switch text"))
      (match (apple/property renderer checkbox proto/AccessibilityLabel)
        (Some (StringValue value))
        (assert-equal "Select all" value "label is accessibility-only")
        _ (is false "Checkbox accessibility label"))
      (sig/set! checked true)
      (sig/set! checkbox-text "All items")
      (sig/set! switch-text "Email notifications")
      (runtime/flush! application)
      (assert-equal node-count (apple/node-count renderer)
                    "toggle Signals preserve the retained tree")
      (assert-equal checkbox (nth (apple/children renderer root) 0)
                    "Checkbox identity is stable")
      (assert-equal switch-control
                    (nth (apple/children renderer root) 1)
                    "Switch identity is stable")
      (match (apple/property renderer switch-control proto/Checked)
        (Some (proto/BoolValue value))
        (assert-equal true value "checked Signal patches SwitchControl")
        _ (is false "Switch checked state"))
      (match (apple/property renderer checkbox proto/TextValue)
        (Some (StringValue value))
        (assert-equal "All items" value "text Signal patches Checkbox")
        _ (is false "Checkbox patched text"))
      (when (and (= (apple/node renderer checkbox) (Some AppleCheckbox))
                 (= (apple/node renderer switch-control) (Some AppleSwitch)))
        (runtime/dispatch!
         application (proto/ToggleChanged checkbox false))
        (runtime/dispatch!
         application (proto/ToggleChanged switch-control false))
        (runtime/flush! application)
        (assert-equal
         [(proto/ToggleChanged checkbox false)
          (proto/ToggleChanged switch-control false)]
         (deref events)
         "on-toggle callbacks receive only their native transitions")))))

(deftest button-disabled-state-is-signal-controlled
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

(deftest button-retains-the-vercel-native-contract
  (let [scheduler (sig/scheduler)
        renderer (apple/create)
        application (runtime/create scheduler (apple/backend renderer))
        scope (sig/scope "vercel-button-contract")
        context (ui/context application scope)
        disabled (sig/state scheduler false)
        selected (sig/state scheduler false)
        autofocus (sig/state scheduler false)
        label (sig/state scheduler "Download")
        presses (atom 0)
        holds (atom 0)
        button
        (retained-vercel-button
         context
         (sig/value label)
         (sig/value disabled)
         (sig/value selected)
         (sig/value autofocus)
         (fn [_event] (swap! presses inc) true)
         (fn [_event] (swap! holds inc) true))]
    (sig/mount! scope)
    (runtime/flush! application)
    (doseq [property-and-value
            [(tuple proto/TextValue "Download")
             (tuple proto/VariantValue "primary")
             (tuple proto/SizeValue "lg")
             (tuple proto/InlineIconName "download")
             (tuple proto/IconPlacementValue "trailing")
             (tuple proto/AccessibilityLabel "Download report")]]
      (match property-and-value
        (tuple property expected)
        (match (apple/property renderer button property)
          (Some (StringValue value))
          (assert-equal expected value "Button string property reaches backend")
          _ (is false "Button string property is present"))))
    (runtime/dispatch! application (proto/Press button))
    (runtime/dispatch! application (proto/Hold button))
    (runtime/flush! application)
    (assert-equal 1 @presses "on-press receives only Press")
    (assert-equal 1 @holds "on-hold receives only Hold")
    (let [node-count (apple/node-count renderer)]
      (sig/set! label "Export")
      (sig/set! selected true)
      (sig/set! autofocus true)
      (runtime/flush! application)
      (assert-equal node-count (apple/node-count renderer)
                    "Signal patches preserve the retained Button node"))
    (match (apple/property renderer button proto/TextValue)
      (Some (StringValue value)) (assert-equal "Export" value "text patches")
      _ (is false "Button text is present"))
    (match (apple/property renderer button proto/Selected)
      (Some (proto/BoolValue value)) (assert-equal true value "selected patches")
      _ (is false "Button selected state is present"))
    (match (apple/property renderer button proto/Autofocus)
      (Some (proto/BoolValue value)) (assert-equal true value "autofocus patches")
      _ (is false "Button autofocus state is present"))))

(deftest button-supports-literal-icon-action-state
  (let [scheduler (sig/scheduler)
        renderer (apple/create)
        application (runtime/create scheduler (apple/backend renderer))
        scope (sig/scope "icon-action-button")
        context (ui/context application scope)
        button (icon-action-button context (fn [_event] true))]
    (sig/mount! scope)
    (runtime/flush! application)
    (match (apple/property renderer button proto/Selected)
      (Some (proto/BoolValue value)) (assert-equal true value "literal selected")
      _ (is false "literal selected is present"))
    (match (apple/property renderer button proto/Autofocus)
      (Some (proto/BoolValue value)) (assert-equal true value "literal autofocus")
      _ (is false "literal autofocus is present"))))

(deftest toggle-button-selected-state-is-incremental-and-dispatches-toggle-only
  (let [scheduler (sig/scheduler)
        renderer (apple/create)
        application (runtime/create scheduler (apple/backend renderer))
        scope (sig/scope "formatting-toggle")
        context (ui/context application scope)
        selected (sig/state scheduler false)
        toggles (atom [])
        holds (atom 0)
        button
        (formatting-toggle
         context
         (sig/value selected)
         (fn [event] (swap! toggles conj event) true)
         (fn [_event] (swap! holds inc) true))]
    (sig/mount! scope)
    (runtime/flush! application)
    (is (= (Some apple/AppleToggleButton) (apple/node renderer button))
        "ToggleButton maps to a distinct native control kind")
    (runtime/dispatch! application (proto/ToggleChanged button true))
    (runtime/dispatch! application (proto/Hold button))
    (runtime/flush! application)
    (assert-equal 1 (count @toggles) "on-toggle receives one toggle event")
    (assert-equal 1 @holds "on-hold receives one hold event")
    (let [node-count (apple/node-count renderer)]
      (sig/set! selected true)
      (runtime/flush! application)
      (assert-equal
       node-count (apple/node-count renderer)
       "selected Signal patches the retained ToggleButton in place"))
    (match (apple/property renderer button proto/Selected)
      (Some (proto/BoolValue value))
      (assert-equal true value "selected Signal reaches the backend")
      _ (is false "selected property is present"))))

(deftest daily-value-controls-share-one-retained-event-contract
  (let [scheduler (sig/scheduler)
        renderer (apple/create)
        application (runtime/create scheduler (apple/backend renderer))
        scope (sig/scope "value-control-batch")
        checked (sig/state scheduler false)
        value (sig/state scheduler 0.25)
        disabled (sig/state scheduler false)
        events (atom [])
        root
        (value-control-batch
         (ui/context application scope)
         (sig/value checked)
         (sig/value value)
         (sig/value disabled)
         (fn [event] (swap! events conj event) true)
         (fn [event] (swap! events conj event) true)
         (fn [event] (swap! events conj event) true))]
    (sig/mount! scope)
    (runtime/flush! application)
    (let [toggle (nth (apple/children renderer root) 0)
          group (nth (apple/children renderer root) 1)
          radio (nth (apple/children renderer group) 0)
          selected-radio (nth (apple/children renderer group) 1)
          slider (nth (apple/children renderer root) 2)
          literal-slider (nth (apple/children renderer root) 3)
          node-count (apple/node-count renderer)]
      (is (not (= None (apple/node renderer toggle)))
          "Toggle creates one retained native node")
      (is (not (= None (apple/node renderer group)))
          "RadioGroup creates one retained native group")
      (is (not (= None (apple/node renderer radio)))
          "Radio creates one retained native choice")
      (match (apple/property renderer selected-radio proto/Checked)
        (Some (proto/BoolValue current))
        (assert-equal true current "literal Radio selected aliases checked state")
        _ (is false "Radio selected state is present"))
      (is (not (= None (apple/node renderer slider)))
          "Slider creates one retained native value control")
      (match (apple/property renderer slider proto/ProgressValue)
        (Some (proto/FloatValue current))
        (assert-equal 0.25 current "Slider retains a fractional value")
        _ (is false "Slider fractional value is present"))
      (match (apple/property renderer literal-slider proto/ProgressValue)
        (Some (proto/FloatValue current))
        (assert-equal 0.5 current "Slider accepts a literal fraction")
        _ (is false "literal Slider fractional value is present"))
      (runtime/dispatch! application (proto/ToggleChanged toggle true))
      (runtime/dispatch! application (proto/Change radio))
      (runtime/dispatch! application (proto/ValueChanged slider 0.75))
      (runtime/flush! application)
      (assert-equal
       [(proto/ToggleChanged toggle true)
        (proto/Change radio)
        (proto/ValueChanged slider 0.75)]
       @events
       "each control receives only its typed native event")
      (sig/set! checked true)
      (sig/set! value 0.75)
      (runtime/flush! application)
      (assert-equal node-count (apple/node-count renderer)
                    "Signal changes patch all controls without replacement")
      (assert-equal toggle (nth (apple/children renderer root) 0)
                    "Toggle identity survives a checked patch")
      (assert-equal radio (nth (apple/children renderer group) 0)
                    "Radio identity survives group reconciliation")
      (match (apple/property renderer selected-radio proto/Checked)
        (Some (proto/BoolValue current))
        (assert-equal true current "literal Radio selected state remains stable")
        _ (is false "updated Radio selected state is present"))
      (assert-equal slider (nth (apple/children renderer root) 2)
                    "Slider identity survives a value patch"))))
