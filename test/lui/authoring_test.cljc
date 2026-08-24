(ns lui.authoring-test
  (:require [clojure.test :refer [deftest is]]
            [signal.core :as sig]
            [lui.protocol :as proto :refer [StringValue TextChanged]]
            [lui.runtime :as runtime]
            [lui.ui :as ui]
            [lui.elements :refer [defelement]]
            [lui.macros :refer [defui state effect platform host]]
            [lui.backend.apple :as apple]
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
     (tuple proto/MacOS proto/AppKitHost)
     (current-platform-profile apple-context)
     "AppKit publishes its OS and host profile")
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
