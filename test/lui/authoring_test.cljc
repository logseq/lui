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
             :refer [AppleBox AppleCard AppleAlert AppleBubble AppleStatusBar
                     AppleCheckbox AppleColumn AppleFormLabel AppleGrid
                     AppleHeading AppleDivider AppleParagraph AppleProgress AppleRow AppleSpinner AppleSwitch
                     AppleList ApplePanel AppleScrollView AppleStack AppleTextInput AppleTextArea
                     AppleSelect AppleCombobox AppleDropdownMenu AppleContextMenu AppleMenuItem AppleListItem
                     AppleTable AppleTableRow AppleTableCell AppleTree AppleResizable AppleSplit
                     AppleAvatar AppleDialog AppleSheet AppleTooltip AppleToast AppleToolbar
                     AppleImage AppleMediaSurface
                     AppleStepper AppleStep AppleTimeline AppleTimelineItem
                     AppleInputGroup AppleInputGroupActions
                     AppleAccordion]]
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

(defui picker-primitives
  [selected query open on-open on-input on-submit on-dismiss on-pick]
  [:column
   [:stack {:width 240}
    [:select
     {:text selected
      :placeholder "Choose environment"
      :on-press on-open}]
    [:if {:test open}
     [:dropdown-menu
      {:anchor "below"
       :anchor-alignment "stretch"
       :anchor-offset 6.0
       :min-width 200
       :on-dismiss on-dismiss}
      [:menu-item
       {:icon "check" :selected true :on-press on-pick}
       "Production"]
      [:separator]
      [:menu-item {:disabled true} "Development"]]]]
   [:combobox
    {:text query
     :placeholder "Search frameworks"
     :on-input on-input
     :on-submit on-submit
     :on-press on-open}]])

(defui controlled-dialog [open on-dismiss]
  [:column
   [:text "Outside"]
   [:if {:test open}
    [:dialog
     {:text "Rename note"
      :width 380
      :height 240
      :padding 24
      :on-dismiss on-dismiss}
     [:column
      [:input {:placeholder "Name"}]
     [:button "Save"]]]]])

(defui nested-dropdown-menu [on-pick]
  [:dropdown-menu
   [:menu-item
    "Share"
    [:dropdown-menu {:anchor "right" :anchor-offset 4.0}
     [:menu-item {:on-press on-pick} "Copy link"]]]])

(defui controlled-sheet [sheet-open on-dismiss]
  [:column
   [:text "Outside"]
   [:if {:test sheet-open}
    [:sheet
     {:text "Share" :height 320 :padding 24 :on-dismiss on-dismiss}
     [:column [:input {:placeholder "Share link"}]]]]])

(defui retained-tooltips [text-source delay-source]
  [:column
   [:stack
    [:button {:variant "outline" :on-press (fn [_event] true)} "Bold"]
    [:tooltip
     {:text text-source
      :anchor "above"
      :anchor-alignment "end"
      :anchor-offset 8.0
      :tooltip-delay delay-source}]]
   [:tooltip "Copied!"]])

(defui retained-notification-controls
  [message-source orientation-source on-dismiss]
  [:column
   [:toolbar
    {:orientation orientation-source :label "Formatting" :gap 4
     :accessibility-identifier "toolbar.formatting"}
    [:button "Bold"]
    [:separator]
    [:button "Italic"]]
   [:toast
    {:duration 1200 :label "Draft notification" :on-dismiss on-dismiss}
    [:text {:value message-source}]
    [:button "Close"]]])

(defui retained-accordion [title-source selected-source on-toggle]
  [:accordion
   {:text title-source
    :selected selected-source
    :height 180
    :on-toggle on-toggle}
   [:column [:text "Retained disclosure content"]]])

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

(defui retained-list-items
  [selected disabled on-select on-open on-long-press]
  [:list {:gap 2}
   [:list-item
    {:icon "file-text"
     :selected selected
     :disabled disabled
     :on-press on-select
     :on-long-press on-long-press
     :on-double-press on-open
     :on-submit on-open}
    "Quarterly report.md"]
   [:list-item {:on-press on-select}
    [:row {:gap 8}
     [:icon {:name "folder"}]
     [:text "Custom child row"]]]])

(defui retained-table [selected-source amount-source on-open]
  [:table {:width 420}
   [:table-row {:gap 4}
    [:table-cell
     {:grow 1.0 :size "sm" :foreground "text-muted"}
     "Invoice"]
    [:table-cell
     {:grow 1.0 :size "sm" :foreground "text-muted"
      :text-alignment "end"}
     "Amount"]]
   [:table-row {:gap 4 :selected selected-source}
    [:table-cell {:grow 1.0 :on-press on-open} "INV-002"]
    [:table-cell
     {:text amount-source :grow 1.0 :text-alignment "end"}]]])

(defui retained-tree
  [expanded-source folder-selected-source file-selected-source
   on-folder-toggle on-folder-change on-folder-press on-file-change]
  [:tree {:gap 2 :label "Project files"}
   [:list-item
    {:role "treeitem" :tree-level 1 :icon "folder-open"
     :expanded expanded-source :selected folder-selected-source
     :on-toggle on-folder-toggle :on-change on-folder-change
     :on-press on-folder-press}
    "src"]
   [:row {:padding-horizontal 20}
    [:panel
     {:role "treeitem" :tree-level 2 :selected file-selected-source
      :label "main.cljc" :on-change on-file-change}
     [:text "main.cljc"]]]])

(defui retained-resizable [width-source]
  [:resizable
   {:width width-source :min-width 180 :padding 12
    :label "Resizable sidebar"}
   [:panel [:text "Sidebar content"]]])

(defui retained-split [fraction-source on-resize]
  [:split
   {:value fraction-source :gap 8 :grow 1.0
    :resize-duration 180 :resize-easing "standard" :resize-origin 0.1
    :label "Workspace panes" :on-resize on-resize}
   [:panel {:min-width 180 :padding 12} [:text "Sidebar"]]
   [:panel {:min-width 320 :padding 12} [:text "Content"]]])

(defui retained-context-menu [archive-disabled on-rename on-archive]
  [:list-item
   "Document"
   [:context-menu
    [:menu-item {:on-press on-rename} "Rename"]
    [:separator]
    [:menu-item {:disabled archive-disabled :on-press on-archive} "Archive"]]])

(defui retained-leaf-context-menus [on-action]
  [:button {:on-press on-action}
   "More"
   [:context-menu
    [:menu-item {:on-press on-action} "Duplicate"]]])

(defui retained-message-surfaces
  [title-source message-source reactions-source status-source]
  [:column {:gap 16}
   [:alert {:text title-source :variant "secondary" :padding 12}
    [:text "Reconnect to continue"]]
   [:bubble {:variant "primary" :padding 12}
    [:text {:value message-source}]
    [:reactions {:value reactions-source :text-alignment "start"}]]
   [:status-bar {:value status-source :text-alignment "end"}]])

(defui retained-avatars [image-id]
  [:row {:gap 12}
   [:avatar
    {:image image-id
     :source-x 0.0
     :source-y 0.0
     :source-width 32.0
     :source-height 32.0
     :label "Profile picture"}
    "ZN"]
   [:avatar "CT"]])

(defui retained-media [image-id surface-id]
  [:row {:gap 12}
   [:image
    {:image image-id
     :source-x 8.0
     :source-y 4.0
     :source-width 40.0
     :source-height 24.0
     :width 160
     :height 96
     :corner-radius 12
     :label "Cover art"}]
   [:media-surface
    {:surface surface-id
     :grow 1.0
     :height 96
     :corner-radius 12
     :label "Camera preview"}]])

(defui retained-progress-structures
  [active step-label item-title connector selected on-open]
  [:column
   [:stepper {:active active :label "Release progress"}
    [:step "Draft"]
    [:step {:text step-label}]
    [:step "Ship"]]
   [:timeline {:gap 6 :grow 1.0 :label "Release activity"}
    [:timeline-item
     {:title item-title
      :description "Checks completed"
      :meta "CI · 2m"
      :indicator "2"
      :variant "primary"
      :connector connector
      :selected selected
      :on-press on-open}]
    [:timeline-item
     {:title "Published" :icon "check" :connector false}]]])

(defui retained-tabs
  [overview-selected activity-selected on-overview on-activity on-toggle]
  [:tabs {:gap 4 :main "start" :cross "center"
          :orientation "vertical" :label "Workspace sections"}
   [:button
    {:selected overview-selected :on-press on-overview}
    "Overview"]
   [:button
    {:selected activity-selected :on-press on-activity}
    "Activity"]
   [:toggle-button {:selected false :on-toggle on-toggle} "Pinned"]])

(defui retained-action-groups
  [primary-selected secondary-selected disabled on-event]
  [:column
   [:button-group {:gap 4 :main "start" :cross "center"}
    [:button {:on-press on-event} "Save"]
    [:toggle-button
     {:selected primary-selected :on-toggle on-event}
     "Pin"]]
   [:toggle-group {:gap 8 :main "end" :cross "center"}
    [:toggle-button
     {:selected secondary-selected :on-toggle on-event}
     "Comfortable"]
    [:toggle-button {:on-toggle on-event} "Backend-owned"]
    [:button
     {:selected primary-selected :disabled disabled :on-press on-event}
     "Compact"]]])

(defui retained-navigation-containers [page-selected on-event]
  [:column
   [:breadcrumb {:accessibility-label "Component path"}
    [:text {:foreground "text-muted" :on-press on-event} "Home"]
    [:icon {:name "chevron-right" :foreground "text-muted"}]
    [:text "Components"]]
   [:pagination {:accessibility-label "Gallery pages"}
    [:button
     {:variant "ghost" :icon "chevron-left" :on-press on-event}
     "Previous"]
    [:button
     {:variant "outline" :selected page-selected :on-press on-event}
     "1"]
    [:icon {:name "ellipsis"}]
    [:button
     {:variant "ghost" :icon "chevron-right"
      :icon-placement "trailing" :on-press on-event}
     "Next"]]])

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

(defui retained-input-group
  [draft on-input on-submit on-attach on-send]
  [:input-group
   {:label "Message composer"
    :width 320
    :height 120
    :min-width 240
    :grow 1.0}
   [:textarea
    {:text draft
     :placeholder "Message the team"
     :submit-on-enter true
     :on-input on-input
     :on-submit on-submit}]
   [:input-group-actions {:gap 8}
    [:button {:variant "ghost" :icon "plus" :on-press on-attach} "Attach"]
    [:spacer {:grow 1.0}]
    [:button {:icon "send" :on-press on-send} "Send"]]])

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
  [text-source disabled-source selected-source autofocus-source on-press on-long-press]
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
    :accessibility-identifier "button.download"
    :on-press on-press
    :on-long-press on-long-press}])

(defui icon-action-button [callback]
  [:button
   {:variant "ghost"
    :size "icon"
    :icon "plus"
    :selected true
    :autofocus true
    :label "New note"
    :on-press callback}])

(defui formatting-toggle [selected-source on-toggle on-long-press]
  [:toggle-button
   {:variant "outline"
    :size "sm"
    :icon "edit"
    :selected selected-source
    :label "Bold formatting"
    :on-toggle on-toggle
    :on-long-press on-long-press}
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

(deftest picker-elements-compose-through-model-owned-conditional-state
  (let [scheduler (sig/scheduler)
        renderer (apple/create)
        application (runtime/create scheduler (apple/backend renderer))
        scope (sig/scope "picker-primitives")
        context (ui/context application scope)
        selected (sig/state scheduler "Production")
        query (sig/state scheduler "")
        open (sig/state scheduler false)
        received (atom [])
        callback
        (fn [event]
          (swap! received conj event)
          true)
        root
        (picker-primitives
         context (sig/value selected) (sig/value query) (sig/value open)
         callback callback callback callback callback)]
    (sig/mount! scope)
    (runtime/flush! application)
    (let [root-children (apple/children renderer root)
          picker-stack (nth root-children 0)
          combobox (nth root-children 1)
          select (nth (apple/children renderer picker-stack) 0)]
      (match (apple/node renderer select)
        (Some AppleSelect) (is true "select is one retained native trigger")
        _ (is false "select maps to its semantic native node"))
      (match (apple/node renderer combobox)
        (Some AppleCombobox) (is true "combobox is one retained native trigger")
        _ (is false "combobox maps to its semantic native node"))
      (assert-equal 1 (count (apple/children renderer picker-stack))
                    "closed picker retains no menu placeholder")
      (runtime/dispatch! application (proto/Press select))
      (runtime/dispatch! application (proto/TextChanged combobox "sol"))
      (runtime/dispatch! application (proto/Submit combobox))
      (runtime/flush! application)
      (assert-equal
       [(proto/Press select) (proto/TextChanged combobox "sol")
        (proto/Submit combobox)]
       @received
       "trigger events preserve the pinned callback split")
      (sig/set! open true)
      (runtime/flush! application)
      (let [menu (nth (apple/children renderer picker-stack) 1)
            menu-children (apple/children renderer menu)
            selected-item (nth menu-children 0)
            disabled-item (nth menu-children 2)]
        (match (apple/node renderer menu)
          (Some AppleDropdownMenu)
          (is true "conditional branch mounts one semantic dropdown")
          _ (is false "dropdown maps to its semantic native node"))
        (match (apple/node renderer selected-item)
          (Some AppleMenuItem) (is true "menu row is a semantic native node")
          _ (is false "menu row mapping exists"))
        (match (apple/property renderer menu proto/AnchorValue)
          (Some (StringValue value))
          (assert-equal "below" value "dropdown retains its anchor")
          _ (is false "dropdown anchor exists"))
        (match (apple/property renderer menu proto/AnchorOffset)
          (Some (proto/FloatValue value))
          (assert-equal 6.0 value "dropdown retains fractional anchor offset")
          _ (is false "dropdown anchor offset exists"))
        (match (apple/property renderer selected-item proto/Selected)
          (Some (proto/BoolValue value))
          (assert-equal true value "committed option keeps its check state")
          _ (is false "menu item selection exists"))
        (match (apple/property renderer disabled-item proto/Enabled)
          (Some (proto/BoolValue value))
          (assert-equal false value "disabled menu item is retained")
          _ (is false "menu item disabled state exists"))
        (runtime/dispatch! application (proto/Press selected-item))
        (runtime/dispatch! application (proto/Dismiss menu))
        (runtime/flush! application)
        (assert-equal (proto/Dismiss menu) (nth @received 4)
                      "native menu dismissal returns through on-dismiss")))))

(deftest menu-items-compose-arbitrarily-nested-dropdowns
  (let [scheduler (sig/scheduler)
        renderer (apple/create)
        application (runtime/create scheduler (apple/backend renderer))
        scope (sig/scope "nested-dropdown-menu")
        context (ui/context application scope)
        root (nested-dropdown-menu context (fn [_event] true))]
    (sig/mount! scope)
    (runtime/flush! application)
    (let [trigger (nth (apple/children renderer root) 0)
          submenu (nth (apple/children renderer trigger) 0)
          nested-item (nth (apple/children renderer submenu) 0)]
      (match (apple/node renderer submenu)
        (Some AppleDropdownMenu) (is true "submenu is a retained menu")
        _ (is false "submenu maps to its semantic native node"))
      (match (apple/node renderer nested-item)
        (Some AppleMenuItem) (is true "nested item preserves its identity")
        _ (is false "nested item maps to a menu row")))))

(deftest dialog-is-a-model-owned-root-modal-with-retained-content
  (let [scheduler (sig/scheduler)
        renderer (apple/create)
        application (runtime/create scheduler (apple/backend renderer))
        scope (sig/scope "controlled-dialog")
        context (ui/context application scope)
        open (sig/state scheduler false)
        received (atom [])
        on-dismiss (fn [event] (swap! received conj event) true)
        root (controlled-dialog context (sig/value open) on-dismiss)]
    (sig/mount! scope)
    (runtime/flush! application)
    (assert-equal 1 (count (apple/children renderer root))
                  "closed dialog leaves no retained placeholder")
    (sig/set! open true)
    (runtime/flush! application)
    (let [dialog (nth (apple/children renderer root) 1)
          content (nth (apple/children renderer dialog) 0)]
      (match (apple/node renderer dialog)
        (Some AppleDialog) (is true "dialog is one semantic retained node")
        _ (is false "dialog maps to the native modal node"))
      (assert-equal 2 (count (apple/children renderer content))
                    "dialog content remains a retained subtree")
      (assert-equal (Some (StringValue "Rename note"))
                    (apple/property renderer dialog proto/TextValue)
                    "dialog title is retained as surface chrome")
      (assert-equal (Some (proto/IntValue 380))
                    (apple/property renderer dialog proto/WidthValue)
                    "dialog width is retained")
      (runtime/dispatch! application (proto/Dismiss dialog))
      (runtime/flush! application)
      (assert-equal [(proto/Dismiss dialog)] @received
                    "native dismissal reaches on-dismiss exactly once")
      (sig/set! open false)
      (runtime/flush! application)
      (assert-equal 1 (count (apple/children renderer root))
                    "model state removes the dialog subtree"))))

(deftest sheet-is-a-model-owned-native-modal-with-retained-content
  (let [scheduler (sig/scheduler)
        renderer (apple/create)
        application (runtime/create scheduler (apple/backend renderer))
        scope (sig/scope "controlled-sheet")
        context (ui/context application scope)
        sheet-open (sig/state scheduler false)
        received (atom [])
        on-dismiss (fn [event] (swap! received conj event) true)
        root
        (controlled-sheet context (sig/value sheet-open) on-dismiss)]
    (sig/mount! scope)
    (runtime/flush! application)
    (assert-equal 1 (count (apple/children renderer root))
                  "a closed sheet leaves no retained placeholder")
    (sig/set! sheet-open true)
    (runtime/flush! application)
    (let [sheet (nth (apple/children renderer root) 1)]
      (match (apple/node renderer sheet)
        (Some AppleSheet) (is true "sheet is one semantic retained node")
        _ (is false "sheet maps to the platform-native modal surface"))
      (assert-equal (Some (proto/IntValue 320))
                    (apple/property renderer sheet proto/HeightValue)
                    "sheet height is retained")
      (runtime/dispatch! application (proto/Dismiss sheet))
      (runtime/flush! application)
      (assert-equal [(proto/Dismiss sheet)]
                    @received
                    "native dismissal reaches the authored handler once"))
    (sig/set! sheet-open false)
    (runtime/flush! application)
    (assert-equal 1 (count (apple/children renderer root))
                  "model state removes the sheet subtree")))

(deftest tooltip-properties-patch-one-retained-leaf
  (let [scheduler (sig/scheduler)
        renderer (apple/create)
        application (runtime/create scheduler (apple/backend renderer))
        scope (sig/scope "retained-tooltips")
        text (sig/state scheduler "Bold the selection")
        delay (sig/state scheduler 250)
        root
        (retained-tooltips
         (ui/context application scope) (sig/value text) (sig/value delay))]
    (sig/mount! scope)
    (runtime/flush! application)
    (let [stack (nth (apple/children renderer root) 0)
          anchored (nth (apple/children renderer stack) 1)
          static (nth (apple/children renderer root) 1)
          node-count (apple/node-count renderer)]
      (match (apple/node renderer anchored)
        (Some AppleTooltip) (is true "anchored Tooltip is one semantic node")
        _ (is false "anchored Tooltip native mapping exists"))
      (match (apple/node renderer static)
        (Some AppleTooltip) (is true "static Tooltip uses the same node kind")
        _ (is false "static Tooltip native mapping exists"))
      (assert-equal
       (Some (StringValue "Bold the selection"))
       (apple/property renderer anchored proto/TextValue)
       "Tooltip text Signal reaches the retained node")
      (assert-equal
       (Some (proto/IntValue 250))
       (apple/property renderer anchored proto/TooltipDelay)
       "Tooltip delay Signal reaches the retained node")
      (sig/set! text "Toggle bold formatting")
      (sig/set! delay 0)
      (runtime/flush! application)
      (assert-equal node-count (apple/node-count renderer)
                    "Tooltip property patches allocate no nodes")
      (assert-equal anchored (nth (apple/children renderer stack) 1)
                    "anchored Tooltip identity survives Signal patches")
      (assert-equal
       (Some (StringValue "Toggle bold formatting"))
       (apple/property renderer anchored proto/TextValue)
       "text patches locally")
      (assert-equal
       (Some (proto/IntValue 0))
       (apple/property renderer anchored proto/TooltipDelay)
       "delay patches locally"))))

(deftest accordion-properties-patch-one-retained-native-container
  (let [scheduler (sig/scheduler)
        renderer (apple/create)
        application (runtime/create scheduler (apple/backend renderer))
        scope (sig/scope "retained-accordion")
        title (sig/state scheduler "Details")
        selected (sig/state scheduler false)
        received (atom [])
        callback (fn [event] (swap! received conj event) true)
        root
        (retained-accordion
         (ui/context application scope)
         (sig/value title) (sig/value selected) callback)]
    (sig/mount! scope)
    (runtime/flush! application)
    (let [accordion root
          content (nth (apple/children renderer accordion) 0)
          node-count (apple/node-count renderer)]
      (match (apple/node renderer accordion)
        (Some AppleAccordion) (is true "Accordion maps to one native node")
        _ (is false "Accordion native mapping exists"))
      (assert-equal
       (Some (StringValue "Details"))
       (apple/property renderer accordion proto/TextValue)
       "header text reaches the retained node")
      (runtime/dispatch! application (proto/ToggleChanged accordion true))
      (runtime/flush! application)
      (assert-equal [(proto/ToggleChanged accordion true)] @received
                    "native expansion intent reaches on-toggle once")
      (sig/set! title "Advanced details")
      (sig/set! selected true)
      (runtime/flush! application)
      (assert-equal node-count (apple/node-count renderer)
                    "Accordion patches allocate no nodes")
      (assert-equal accordion root "Accordion identity survives Signal patches")
      (assert-equal content (nth (apple/children renderer accordion) 0)
                    "collapsed content retains its identity")
      (assert-equal
       (Some (proto/BoolValue true))
       (apple/property renderer accordion proto/Selected)
       "selected patches locally"))))

(deftest list-item-supports-text-or-custom-children-and-additive-actions
  (let [scheduler (sig/scheduler)
        renderer (apple/create)
        application (runtime/create scheduler (apple/backend renderer))
        scope (sig/scope "retained-list-items")
        context (ui/context application scope)
        selected (sig/state scheduler false)
        disabled (sig/state scheduler false)
        received (atom [])
        callback (fn [event] (swap! received conj event) true)
        root
        (retained-list-items
         context (sig/value selected) (sig/value disabled)
         callback callback callback)]
    (sig/mount! scope)
    (runtime/flush! application)
    (let [text-item (nth (apple/children renderer root) 0)
          custom-item (nth (apple/children renderer root) 1)]
      (match (apple/node renderer text-item)
        (Some AppleListItem) (is true "text row is one semantic ListItem")
        _ (is false "text row has the native ListItem kind"))
      (match (apple/property renderer text-item proto/InlineIconName)
        (Some (StringValue value))
        (assert-equal "file-text" value "inline icon stays on the row")
        _ (is false "list row icon exists"))
      (assert-equal 1 (count (apple/children renderer custom-item))
                    "custom row content is retained below the ListItem")
      (runtime/dispatch! application (proto/Press text-item))
      (runtime/dispatch! application (proto/LongPress text-item))
      (runtime/dispatch! application (proto/DoublePress text-item))
      (runtime/dispatch! application (proto/Submit text-item))
      (runtime/flush! application)
      (assert-equal
       [(proto/Press text-item) (proto/LongPress text-item)
        (proto/DoublePress text-item)
        (proto/Submit text-item)]
       @received
       "press, long press, additive double press, and Enter submit stay distinct")
      (let [node-count (apple/node-count renderer)]
        (sig/set! selected true)
        (runtime/flush! application)
        (assert-equal node-count (apple/node-count renderer)
                      "selection patches the retained ListItem in place")))))

(deftest table-signals-patch-retained-rows-and-cells-in-place
  (let [scheduler (sig/scheduler)
        renderer (apple/create)
        application (runtime/create scheduler (apple/backend renderer))
        scope (sig/scope "retained-table")
        selected (sig/state scheduler false)
        amount (sig/state scheduler "$150.00")
        received (atom [])
        callback (fn [event] (swap! received conj event) true)
        root
        (retained-table
         (ui/context application scope)
         (sig/value selected) (sig/value amount) callback)]
    (sig/mount! scope)
    (runtime/flush! application)
    (let [header-row (nth (apple/children renderer root) 0)
          data-row (nth (apple/children renderer root) 1)
          invoice-cell (nth (apple/children renderer data-row) 0)
          amount-cell (nth (apple/children renderer data-row) 1)
          node-count (apple/node-count renderer)]
      (match (apple/node renderer root)
        (Some AppleTable) (is true "Table maps to one semantic native node")
        _ (is false "Table native mapping exists"))
      (match (apple/node renderer header-row)
        (Some AppleTableRow) (is true "header is a retained TableRow")
        _ (is false "TableRow native mapping exists"))
      (match (apple/node renderer amount-cell)
        (Some AppleTableCell) (is true "amount is a retained TableCell")
        _ (is false "TableCell native mapping exists"))
      (runtime/dispatch! application (proto/Press invoice-cell))
      (runtime/flush! application)
      (assert-equal [(proto/Press invoice-cell)] @received
                    "cell activation reaches on-press once")
      (sig/set! selected true)
      (sig/set! amount "$175.00")
      (runtime/flush! application)
      (assert-equal node-count (apple/node-count renderer)
                    "Table Signal patches allocate no retained nodes")
      (assert-equal data-row (nth (apple/children renderer root) 1)
                    "selected row identity is stable")
      (assert-equal amount-cell (nth (apple/children renderer data-row) 1)
                    "patched cell identity is stable")
      (assert-equal
       (Some (proto/BoolValue true))
       (apple/property renderer data-row proto/Selected)
       "selected patches only the retained row")
      (assert-equal
       (Some (proto/StringValue "$175.00"))
       (apple/property renderer amount-cell proto/TextValue)
       "amount patches only the retained cell"))))

(deftest tree-signals-and-events-retain-ordinary-row-nodes
  (let [scheduler (sig/scheduler)
        renderer (apple/create)
        application (runtime/create scheduler (apple/backend renderer))
        scope (sig/scope "retained-tree")
        expanded (sig/state scheduler false)
        folder-selected (sig/state scheduler true)
        file-selected (sig/state scheduler false)
        received (atom [])
        callback (fn [event] (swap! received conj event) true)
        root
        (retained-tree
         (ui/context application scope)
         (sig/value expanded) (sig/value folder-selected)
         (sig/value file-selected) callback callback callback callback)]
    (sig/mount! scope)
    (runtime/flush! application)
    (let [folder (nth (apple/children renderer root) 0)
          indent (nth (apple/children renderer root) 1)
          file (nth (apple/children renderer indent) 0)
          node-count (apple/node-count renderer)]
      (match (apple/node renderer root)
        (Some AppleTree) (is true "Tree maps to one semantic native node")
        _ (is false "Tree native mapping exists"))
      (assert-equal
       (Some (proto/StringValue "treeitem"))
       (apple/property renderer folder proto/RoleValue)
       "ListItem keeps its treeitem role")
      (assert-equal
       (Some (proto/IntValue 2))
       (apple/property renderer file proto/TreeLevel)
       "a composite Panel row keeps its flat logical level")
      (runtime/dispatch! application (proto/Press folder))
      (runtime/dispatch! application (proto/Change folder))
      (runtime/dispatch! application (proto/ToggleChanged folder true))
      (runtime/dispatch! application (proto/Change file))
      (runtime/flush! application)
      (assert-equal
       [(proto/Press folder) (proto/Change folder)
        (proto/ToggleChanged folder true) (proto/Change file)]
       @received
       "Tree row event capabilities coexist without overwriting callbacks")
      (sig/set! expanded true)
      (sig/set! folder-selected false)
      (sig/set! file-selected true)
      (runtime/flush! application)
      (assert-equal node-count (apple/node-count renderer)
                    "Tree Signal patches allocate no retained nodes")
      (assert-equal folder (nth (apple/children renderer root) 0)
                    "folder row identity is stable")
      (assert-equal file (nth (apple/children renderer indent) 0)
                    "composite file row identity is stable")
      (assert-equal
       (Some (proto/BoolValue true))
       (apple/property renderer folder proto/Expanded)
       "expanded patches only the retained folder row")
      (assert-equal
       (Some (proto/BoolValue true))
       (apple/property renderer file proto/Selected)
       "selection patches only the retained file row"))))

(deftest resizable-source-width-reconciles-without-replacing-native-state
  (let [scheduler (sig/scheduler)
        renderer (apple/create)
        application (runtime/create scheduler (apple/backend renderer))
        scope (sig/scope "retained-resizable")
        width (sig/state scheduler 240)
        root
        (retained-resizable
         (ui/context application scope) (sig/value width))]
    (sig/mount! scope)
    (runtime/flush! application)
    (let [content (nth (apple/children renderer root) 0)
          node-count (apple/node-count renderer)]
      (match (apple/node renderer root)
        (Some AppleResizable)
        (is true "Resizable maps to one retained native surface")
        _ (is false "Resizable native mapping exists"))
      (assert-equal
       (Some (proto/IntValue 240))
       (apple/property renderer root proto/WidthValue)
       "source width seeds native geometry")
      (sig/set! width 280)
      (runtime/flush! application)
      (assert-equal node-count (apple/node-count renderer)
                    "width reconciliation allocates no retained nodes")
      (assert-equal content (nth (apple/children renderer root) 0)
                    "stacked child identity survives a width reset")
      (assert-equal
       (Some (proto/IntValue 280))
       (apple/property renderer root proto/WidthValue)
       "changed source width patches only the retained surface"))))

(deftest split-fraction-and-resize-events-remain-model-owned
  (let [scheduler (sig/scheduler)
        renderer (apple/create)
        application (runtime/create scheduler (apple/backend renderer))
        scope (sig/scope "retained-split")
        fraction (sig/state scheduler 0.35)
        received (atom [])
        callback (fn [event] (swap! received conj event) true)
        root
        (retained-split
         (ui/context application scope) (sig/value fraction) callback)]
    (sig/mount! scope)
    (runtime/flush! application)
    (let [first-pane (nth (apple/children renderer root) 0)
          second-pane (nth (apple/children renderer root) 1)
          node-count (apple/node-count renderer)]
      (match (apple/node renderer root)
        (Some AppleSplit) (is true "Split maps to one retained native layout")
        _ (is false "Split native mapping exists"))
      (assert-equal
       (Some (proto/FloatValue 0.35))
       (apple/property renderer root proto/ProgressValue)
       "bound value seeds the controlled first-pane fraction")
      (assert-equal
       (Some (proto/IntValue 180))
       (apple/property renderer root proto/ResizeDuration)
       "animation duration lowers through the direct element API")
      (runtime/dispatch! application (proto/ValueChanged root 0.42))
      (runtime/flush! application)
      (assert-equal [(proto/ValueChanged root 0.42)] @received
                    "on-resize receives the typed effective fraction")
      (sig/set! fraction 0.42)
      (runtime/flush! application)
      (assert-equal node-count (apple/node-count renderer)
                    "fraction echoes allocate no retained nodes")
      (assert-equal [first-pane second-pane]
                    (apple/children renderer root)
                    "both pane identities survive a fraction patch")
      (assert-equal
       (Some (proto/FloatValue 0.42))
       (apple/property renderer root proto/ProgressValue)
       "the model echo patches only the retained Split"))))

(deftest context-menu-metadata-and-signals-remain-retained
  (let [scheduler (sig/scheduler)
        renderer (apple/create)
        application (runtime/create scheduler (apple/backend renderer))
        scope (sig/scope "retained-context-menu")
        archive-disabled (sig/state scheduler false)
        received (atom [])
        callback (fn [event] (swap! received conj event) true)
        root
        (retained-context-menu
         (ui/context application scope)
         (sig/value archive-disabled)
         callback
         callback)]
    (sig/mount! scope)
    (runtime/flush! application)
    (let [menu (nth (apple/children renderer root) 0)
          rename (nth (apple/children renderer menu) 0)
          archive (nth (apple/children renderer menu) 2)
          node-count (apple/node-count renderer)]
      (match (apple/node renderer menu)
        (Some AppleContextMenu)
        (is true "ContextMenu is retained as non-layout metadata")
        _ (is false "ContextMenu native mapping exists"))
      (assert-equal
       (Some (proto/BoolValue true))
       (apple/property renderer rename proto/PressEnabled)
       "on-press declares the item interaction capability")
      (runtime/dispatch! application (proto/Press rename))
      (runtime/flush! application)
      (assert-equal [(proto/Press rename)] @received
                    "menu selection reuses the typed Press event")
      (sig/set! archive-disabled true)
      (runtime/flush! application)
      (assert-equal node-count (apple/node-count renderer)
                    "disabled Signal patches allocate no retained nodes")
      (assert-equal [rename (nth (apple/children renderer menu) 1) archive]
                    (apple/children renderer menu)
                    "all menu slots preserve identity")
      (assert-equal
       (Some (proto/BoolValue false))
       (apple/property renderer archive proto/Enabled)
       "the Signal patches only the retained menu item"))))

(deftest context-menu-attaches-to-retained-leaf-hosts
  (let [scheduler (sig/scheduler)
        renderer (apple/create)
        application (runtime/create scheduler (apple/backend renderer))
        scope (sig/scope "leaf-context-menus")
        callback (fn [_event] true)
        root
        (retained-leaf-context-menus
         (ui/context application scope) callback)]
    (sig/mount! scope)
    (runtime/flush! application)
    (let [button-menu (nth (apple/children renderer root) 0)]
      (assert-equal
       (Some (proto/StringValue "More"))
       (apple/property renderer root proto/TextValue)
       "Button text remains its visible content")
      (match (apple/node renderer button-menu)
        (Some AppleContextMenu)
        (is true "leaf hosts retain ContextMenu as metadata")
        _ (is false "leaf host ContextMenu mapping exists"))
      (assert-equal 3 (apple/node-count renderer)
                    "metadata adds no visible wrapper nodes"))))

(deftest message-surface-signals-patch-retained-native-nodes
  (let [scheduler (sig/scheduler)
        renderer (apple/create)
        application (runtime/create scheduler (apple/backend renderer))
        scope (sig/scope "message-surfaces")
        title (sig/state scheduler "Sync paused")
        message (sig/state scheduler "Shipped")
        reactions (sig/state scheduler "2 reactions")
        status (sig/state scheduler "3 items")
        root
        (retained-message-surfaces
         (ui/context application scope)
         (sig/value title)
         (sig/value message)
         (sig/value reactions)
         (sig/value status))]
    (sig/mount! scope)
    (runtime/flush! application)
    (let [alert (nth (apple/children renderer root) 0)
          bubble (nth (apple/children renderer root) 1)
          status-bar (nth (apple/children renderer root) 2)
          message-node (nth (apple/children renderer bubble) 0)
          node-count (apple/node-count renderer)]
      (match (apple/node renderer alert)
        (Some AppleAlert) (is true "Alert maps directly")
        _ (is false "Alert native mapping exists"))
      (match (apple/node renderer bubble)
        (Some AppleBubble) (is true "Bubble maps directly")
        _ (is false "Bubble native mapping exists"))
      (match (apple/node renderer status-bar)
        (Some AppleStatusBar) (is true "StatusBar maps directly")
        _ (is false "StatusBar native mapping exists"))
      (assert-equal [message-node] (apple/children renderer bubble)
                    "Reactions adds no layout node")
      (assert-equal
       (Some (proto/StringValue "2 reactions"))
       (apple/property renderer bubble proto/TextValue)
       "Reactions lowers onto Bubble chrome text")
      (sig/set! reactions "4 reactions")
      (sig/set! status "5 items")
      (runtime/flush! application)
      (assert-equal node-count (apple/node-count renderer)
                    "message text patches allocate no nodes")
      (assert-equal
       (Some (proto/StringValue "4 reactions"))
       (apple/property renderer bubble proto/TextValue)
       "Reactions Signal patches only Bubble chrome")
      (assert-equal
       (Some (proto/StringValue "5 items"))
       (apple/property renderer status-bar proto/TextValue)
       "StatusBar Signal patches the same leaf"))))

(deftest avatar-binds-a-model-owned-image-id-without-replacing-its-node
  (let [scheduler (sig/scheduler)
        renderer (apple/create)
        application (runtime/create scheduler (apple/backend renderer))
        scope (sig/scope "retained-avatars")
        context (ui/context application scope)
        image-id (sig/state scheduler 0)
        root (retained-avatars context (sig/value image-id))]
    (sig/mount! scope)
    (runtime/flush! application)
    (let [image-avatar (nth (apple/children renderer root) 0)
          fallback-avatar (nth (apple/children renderer root) 1)
          node-count (apple/node-count renderer)]
      (match (apple/node renderer image-avatar)
        (Some AppleAvatar) (is true "image avatar is one semantic leaf")
        _ (is false "image avatar has the native Avatar kind"))
      (match (apple/property renderer image-avatar proto/ImageIdValue)
        (Some (proto/IntValue value))
        (assert-equal 0 value "zero keeps the initials fallback")
        _ (is false "avatar image id exists"))
      (match (apple/property renderer fallback-avatar proto/TextValue)
        (Some (StringValue value))
        (assert-equal "CT" value "an unbound avatar retains its initials")
        _ (is false "fallback initials exist"))
      (sig/set! image-id 7)
      (runtime/flush! application)
      (assert-equal node-count (apple/node-count renderer)
                    "an image Signal patches the retained Avatar in place")
      (match (apple/property renderer image-avatar proto/ImageIdValue)
        (Some (proto/IntValue value))
        (assert-equal 7 value "the registered image id is model owned")
        _ (is false "patched avatar image id exists")))))

(deftest image-and-media-surface-signals-patch-retained-leaves
  (let [scheduler (sig/scheduler)
        renderer (apple/create)
        application (runtime/create scheduler (apple/backend renderer))
        scope (sig/scope "retained-media")
        image-id (sig/state scheduler 0)
        surface-id (sig/state scheduler 0)
        root
        (retained-media
         (ui/context application scope)
         (sig/value image-id)
         (sig/value surface-id))]
    (sig/mount! scope)
    (runtime/flush! application)
    (let [image-node (nth (apple/children renderer root) 0)
          surface-node (nth (apple/children renderer root) 1)
          node-count (apple/node-count renderer)]
      (match (apple/node renderer image-node)
        (Some AppleImage) (is true "Image is one retained native leaf")
        _ (is false "Image keeps its semantic native kind"))
      (match (apple/node renderer surface-node)
        (Some AppleMediaSurface)
        (is true "MediaSurface is one retained native leaf")
        _ (is false "MediaSurface keeps its semantic native kind"))
      (sig/set! image-id 7)
      (sig/set! surface-id 11)
      (runtime/flush! application)
      (assert-equal node-count (apple/node-count renderer)
                    "resource Signals allocate no retained nodes")
      (assert-equal
       (Some (proto/IntValue 7))
       (apple/property renderer image-node proto/ImageIdValue)
       "ImageId patches the same Image node")
      (assert-equal
       (Some (proto/IntValue 11))
       (apple/property renderer surface-node proto/SurfaceIdValue)
       "SurfaceId patches the same MediaSurface node"))))

(deftest stepper-and-timeline-patch-their-retained-semantic-nodes
  (let [scheduler (sig/scheduler)
        renderer (apple/create)
        application (runtime/create scheduler (apple/backend renderer))
        scope (sig/scope "retained-progress-structures")
        active (sig/state scheduler 1)
        step-label (sig/state scheduler "Review")
        item-title (sig/state scheduler "Validated")
        connector (sig/state scheduler true)
        selected (sig/state scheduler false)
        received (atom [])
        callback (fn [event] (swap! received conj event) true)
        root
        (retained-progress-structures
         (ui/context application scope)
         (sig/value active)
         (sig/value step-label)
         (sig/value item-title)
         (sig/value connector)
         (sig/value selected)
         callback)]
    (sig/mount! scope)
    (runtime/flush! application)
    (let [stepper (nth (apple/children renderer root) 0)
          timeline (nth (apple/children renderer root) 1)
          steps (apple/children renderer stepper)
          items (apple/children renderer timeline)
          review (nth steps 1)
          validated (nth items 0)
          node-count (apple/node-count renderer)]
      (assert-equal (Some AppleStepper) (apple/node renderer stepper)
                    "Stepper is one semantic retained node")
      (assert-equal (Some AppleStep) (apple/node renderer review)
                    "Step labels remain semantic retained leaves")
      (assert-equal (Some AppleTimeline) (apple/node renderer timeline)
                    "Timeline is one semantic retained list")
      (assert-equal (Some AppleTimelineItem) (apple/node renderer validated)
                    "TimelineItem owns one retained native composition")
      (assert-equal (Some (proto/IntValue 1))
                    (apple/property renderer stepper proto/ActiveIndex)
                    "the model owns the active Step index")
      (assert-equal (Some (proto/StringValue "Review"))
                    (apple/property renderer review proto/TextValue)
                    "a Step label may be Signal-backed")
      (assert-equal (Some (proto/StringValue "Validated"))
                    (apple/property renderer validated proto/TitleValue)
                    "TimelineItem title is retained state")
      (runtime/dispatch! application (proto/Press validated))
      (runtime/flush! application)
      (assert-equal [(proto/Press validated)] @received
                    "TimelineItem binds one root Press event")
      (sig/set! active 2)
      (sig/set! step-label "Approve")
      (sig/set! item-title "Deployed")
      (sig/set! connector false)
      (sig/set! selected true)
      (runtime/flush! application)
      (assert-equal node-count (apple/node-count renderer)
                    "progress Signals patch without rebuilding nodes")
      (assert-equal (Some (proto/IntValue 2))
                    (apple/property renderer stepper proto/ActiveIndex)
                    "active index patches the retained Stepper")
      (assert-equal (Some (proto/StringValue "Approve"))
                    (apple/property renderer review proto/TextValue)
                    "Step copy patches only its retained leaf")
      (assert-equal (Some (proto/StringValue "Deployed"))
                    (apple/property renderer validated proto/TitleValue)
                    "Timeline title patches the same native item")
      (assert-equal (Some (proto/BoolValue false))
                    (apple/property renderer validated proto/Connector)
                    "connector state stays controlled")
      (assert-equal (Some (proto/BoolValue true))
                    (apple/property renderer validated proto/Selected)
                    "selection patches the item in place"))))

(deftest tabs-composes-controlled-buttons-without-owning-selection
  (let [scheduler (sig/scheduler)
        renderer (apple/create)
        application (runtime/create scheduler (apple/backend renderer))
        scope (sig/scope "retained-tabs")
        context (ui/context application scope)
        overview-selected (sig/state scheduler true)
        activity-selected (sig/state scheduler false)
        received (atom [])
        callback (fn [event] (swap! received conj event) true)
        root
        (retained-tabs
         context
         (sig/value overview-selected)
         (sig/value activity-selected)
         callback callback callback)]
    (sig/mount! scope)
    (runtime/flush! application)
    (let [children (apple/children renderer root)
          overview (nth children 0)
          activity (nth children 1)
          toggle (nth children 2)
          node-count (apple/node-count renderer)]
      (assert-equal 3 (count children) "Tabs retains all direct triggers")
      (match (apple/property renderer root proto/Gap)
        (Some (proto/IntValue value))
        (assert-equal 4 value "Tabs keeps its explicit trigger gap")
        _ (is false "Tabs gap exists"))
      (match (apple/property renderer root proto/OrientationValue)
        (Some (proto/StringValue value))
        (assert-equal "vertical" value "Tabs keeps its explicit orientation")
        _ (is false "Tabs orientation exists"))
      (match (apple/property renderer root proto/AccessibilityLabel)
        (Some (proto/StringValue value))
        (assert-equal "Workspace sections" value "Tabs keeps its accessible name")
        _ (is false "Tabs accessible name exists"))
      (match (apple/property renderer overview proto/Selected)
        (Some (proto/BoolValue value))
        (assert-equal true value "the first Button owns selected state")
        _ (is false "overview selection exists"))
      (runtime/dispatch! application (proto/Press activity))
      (runtime/dispatch! application (proto/ToggleChanged toggle true))
      (runtime/flush! application)
      (assert-equal
       [(proto/Press activity) (proto/ToggleChanged toggle true)]
       @received
       "Button and ToggleButton children keep their distinct events")
      (sig/set! overview-selected false)
      (sig/set! activity-selected true)
      (runtime/flush! application)
      (assert-equal node-count (apple/node-count renderer)
                    "selection Signals patch triggers without replacing Tabs")
      (match (apple/property renderer activity proto/Selected)
        (Some (proto/BoolValue value))
        (assert-equal true value "the model selects the second trigger")
        _ (is false "activity selection exists")))))

(deftest action-groups-compose-controlled-and-backend-owned-controls
  (let [scheduler (sig/scheduler)
        renderer (apple/create)
        application (runtime/create scheduler (apple/backend renderer))
        scope (sig/scope "retained-action-groups")
        context (ui/context application scope)
        primary-selected (sig/state scheduler false)
        secondary-selected (sig/state scheduler true)
        disabled (sig/state scheduler false)
        received (atom [])
        callback (fn [event] (swap! received conj event) true)
        root
        (retained-action-groups
         context
         (sig/value primary-selected)
         (sig/value secondary-selected)
         (sig/value disabled)
         callback)]
    (sig/mount! scope)
    (runtime/flush! application)
    (let [groups (apple/children renderer root)
          button-group (nth groups 0)
          toggle-group (nth groups 1)
          button-children (apple/children renderer button-group)
          toggle-children (apple/children renderer toggle-group)
          save (nth button-children 0)
          pin (nth button-children 1)
          comfortable (nth toggle-children 0)
          backend-owned (nth toggle-children 1)
          compact (nth toggle-children 2)
          node-count (apple/node-count renderer)]
      (assert-equal (Some apple/AppleButtonGroup)
                    (apple/node renderer button-group)
                    "ButtonGroup has one retained native group node")
      (assert-equal (Some apple/AppleToggleGroup)
                    (apple/node renderer toggle-group)
                    "ToggleGroup has one retained native group node")
      (assert-equal 2 (count button-children)
                    "ButtonGroup keeps its direct actions")
      (assert-equal 3 (count toggle-children)
                    "ToggleGroup accepts ToggleButtons and plain Buttons")
      (match (apple/property renderer toggle-group proto/Gap)
        (Some (proto/IntValue value))
        (assert-equal 8 value "ToggleGroup keeps explicit layout")
        _ (is false "ToggleGroup gap exists"))
      (assert-equal None
                    (apple/property renderer backend-owned proto/Selected)
                    "an omitted selection remains backend owned")
      (runtime/dispatch! application (proto/Press save))
      (runtime/dispatch! application (proto/ToggleChanged pin true))
      (runtime/dispatch! application (proto/Press compact))
      (runtime/flush! application)
      (assert-equal
       [(proto/Press save)
        (proto/ToggleChanged pin true)
        (proto/Press compact)]
       @received
       "group children keep their native Button and ToggleButton events")
      (sig/set! primary-selected true)
      (sig/set! secondary-selected false)
      (sig/set! disabled true)
      (runtime/flush! application)
      (assert-equal node-count (apple/node-count renderer)
                    "Signals patch group children without replacing the tree")
      (match (apple/property renderer comfortable proto/Selected)
        (Some (proto/BoolValue value))
        (assert-equal false value "only the controlled child is patched")
        _ (is false "controlled selection exists"))
      (match (apple/property renderer compact proto/Enabled)
        (Some (proto/BoolValue value))
        (assert-equal false value "disabled Signal stays child owned")
        _ (is false "controlled enabled state exists")))))

(deftest navigation-containers-compose-pressable-text-and-controlled-buttons
  (let [scheduler (sig/scheduler)
        renderer (apple/create)
        application (runtime/create scheduler (apple/backend renderer))
        scope (sig/scope "retained-navigation-containers")
        context (ui/context application scope)
        page-selected (sig/state scheduler false)
        received (atom [])
        callback (fn [event] (swap! received conj event) true)
        root
        (retained-navigation-containers
         context (sig/value page-selected) callback)]
    (sig/mount! scope)
    (runtime/flush! application)
    (let [containers (apple/children renderer root)
          breadcrumb (nth containers 0)
          pagination (nth containers 1)
          crumbs (apple/children renderer breadcrumb)
          pages (apple/children renderer pagination)
          home (nth crumbs 0)
          current-page (nth pages 1)
          node-count (apple/node-count renderer)]
      (assert-equal (Some apple/AppleBreadcrumb)
                    (apple/node renderer breadcrumb)
                    "Breadcrumb is one retained native composition node")
      (assert-equal (Some apple/ApplePagination)
                    (apple/node renderer pagination)
                    "Pagination is one retained native composition node")
      (assert-equal 3 (count crumbs)
                    "Breadcrumb retains Text and Icon composition")
      (assert-equal 4 (count pages)
                    "Pagination retains ordinary Buttons and Icon")
      (assert-equal (Some (proto/BoolValue true))
                    (apple/property renderer home proto/PressEnabled)
                    "on-press makes Text pressable without another item type")
      (assert-equal None
                    (apple/property renderer breadcrumb proto/Gap)
                    "the house gap remains a backend default")
      (assert-equal None
                    (apple/property renderer pagination proto/Gap)
                    "the smaller Pagination gap remains a backend default")
      (runtime/dispatch! application (proto/Press home))
      (runtime/dispatch! application (proto/Press current-page))
      (runtime/flush! application)
      (assert-equal [(proto/Press home) (proto/Press current-page)]
                    @received
                    "composed children keep their ordinary Press events")
      (sig/set! page-selected true)
      (runtime/flush! application)
      (assert-equal node-count (apple/node-count renderer)
                    "page selection patches one retained Button")
      (assert-equal (Some (proto/BoolValue true))
                    (apple/property renderer current-page proto/Selected)
                    "the model owns the current page selection"))))

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

(deftest toast-and-toolbar-retain-identity-through-signal-patches
  (let [scheduler (sig/scheduler)
        renderer (apple/create)
        application (runtime/create scheduler (apple/backend renderer))
        scope (sig/scope "notification-controls")
        message (sig/state scheduler "Saved")
        orientation (sig/state scheduler "horizontal")
        dismissals (atom 0)
        root
        (retained-notification-controls
         (ui/context application scope)
         (sig/value message)
         (sig/value orientation)
         (fn [_event] (swap! dismissals inc) true))]
    (runtime/flush! application)
    (let [children (apple/children renderer root)
          toolbar (nth children 0)
          toast (nth children 1)
          toast-text (nth (apple/children renderer toast) 0)
          node-count (apple/node-count renderer)]
      (match (apple/node renderer toolbar)
        (Some AppleToolbar) (is true "Toolbar has one retained native identity")
        _ (is false "Toolbar maps directly to the native backend"))
      (match (apple/node renderer toast)
        (Some AppleToast) (is true "Toast has one retained native identity")
        _ (is false "Toast maps directly to the native backend"))
      (assert-equal (Some (StringValue "horizontal"))
                    (apple/property renderer toolbar proto/OrientationValue)
                    "Toolbar retains orientation")
      (assert-equal
       (Some (StringValue "toolbar.formatting"))
       (apple/property renderer toolbar proto/AccessibilityIdentifier)
       "Toolbar retains its automation identifier")
      (assert-equal (Some (proto/IntValue 1200))
                    (apple/property renderer toast proto/DurationValue)
                    "Toast retains its dismissal duration")
      (sig/set! message "Updated")
      (sig/set! orientation "vertical")
      (runtime/flush! application)
      (assert-equal node-count (apple/node-count renderer)
                    "Toast and Toolbar Signal patches allocate no nodes")
      (assert-equal (Some (StringValue "Updated"))
                    (apple/property renderer toast-text proto/TextValue)
                    "Toast copy patches its retained Text child")
      (assert-equal (Some (StringValue "vertical"))
                    (apple/property renderer toolbar proto/OrientationValue)
                    "Toolbar orientation patches in place")
      (runtime/dispatch! application (proto/Dismiss toast))
      (runtime/flush! application)
      (assert-equal 1 @dismissals "Toast dismissal dispatches through effects"))))

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

(deftest input-group-retains-one-textarea-and-accessory-row
  (let [scheduler (sig/scheduler)
        renderer (apple/create)
        application (runtime/create scheduler (apple/backend renderer))
        scope (sig/scope "input-group")
        draft (sig/state scheduler "Hello")
        received (atom [])
        record-event (fn [event] (do (swap! received conj event) true))
        on-input
        (fn [event]
          (do
            (swap! received conj event)
            (match event
              (TextChanged _node text) (sig/set! draft text)
              _ true)))
        group
        (retained-input-group
         (ui/context application scope)
         (sig/value draft)
         on-input record-event record-event record-event)]
    (sig/mount! scope)
    (runtime/flush! application)
    (let [children (apple/children renderer group)
          textarea (nth children 0)
          actions (nth children 1)
          action-children (apple/children renderer actions)
          attach (nth action-children 0)
          send (nth action-children 2)
          node-count (apple/node-count renderer)]
      (assert-equal (Some AppleInputGroup) (apple/node renderer group)
                    "InputGroup is one retained semantic field")
      (assert-equal (Some AppleTextArea) (apple/node renderer textarea)
                    "the first child remains a native textarea")
      (assert-equal (Some AppleInputGroupActions)
                    (apple/node renderer actions)
                    "accessories remain one retained semantic row")
      (assert-equal 3 (count action-children)
                    "ordinary action children remain explicit")
      (assert-equal (Some (proto/IntValue 320))
                    (apple/property renderer group proto/WidthValue)
                    "group width uses the ordinary closed layout property")
      (assert-equal (Some (proto/IntValue 8))
                    (apple/property renderer actions proto/Gap)
                    "the action row owns only its gap")
      (runtime/dispatch! application (proto/TextChanged textarea "Updated"))
      (runtime/dispatch! application (proto/Submit textarea))
      (runtime/dispatch! application (proto/Press attach))
      (runtime/dispatch! application (proto/Press send))
      (runtime/flush! application)
      (assert-equal "Updated" (sig/get draft)
                    "the nested textarea updates the shared Signal")
      (assert-equal
       [(proto/TextChanged textarea "Updated")
        (proto/Submit textarea)
        (proto/Press attach)
        (proto/Press send)]
       @received
       "entry and accessory events keep their existing typed paths")
      (assert-equal node-count (apple/node-count renderer)
                    "text patches preserve the group and all descendants")
      (assert-equal (Some (proto/StringValue "Updated"))
                    (apple/property renderer textarea proto/TextValue)
                    "only the retained textarea text is patched"))))

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
        long-presses (atom 0)
        button
        (retained-vercel-button
         context
         (sig/value label)
         (sig/value disabled)
         (sig/value selected)
         (sig/value autofocus)
         (fn [_event] (swap! presses inc) true)
         (fn [_event] (swap! long-presses inc) true))]
    (sig/mount! scope)
    (runtime/flush! application)
    (doseq [property-and-value
            [(tuple proto/TextValue "Download")
             (tuple proto/VariantValue "primary")
             (tuple proto/SizeValue "lg")
             (tuple proto/InlineIconName "download")
             (tuple proto/IconPlacementValue "trailing")
             (tuple proto/AccessibilityLabel "Download report")
             (tuple proto/AccessibilityIdentifier "button.download")]]
      (match property-and-value
        (tuple property expected)
        (match (apple/property renderer button property)
          (Some (StringValue value))
          (assert-equal expected value "Button string property reaches backend")
          _ (is false "Button string property is present"))))
    (runtime/dispatch! application (proto/Press button))
    (runtime/dispatch! application (proto/LongPress button))
    (runtime/flush! application)
    (assert-equal 1 @presses "on-press receives only Press")
    (assert-equal 1 @long-presses "on-long-press receives only LongPress")
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
        long-presses (atom 0)
        button
        (formatting-toggle
         context
         (sig/value selected)
         (fn [event] (swap! toggles conj event) true)
         (fn [_event] (swap! long-presses inc) true))]
    (sig/mount! scope)
    (runtime/flush! application)
    (is (= (Some apple/AppleToggleButton) (apple/node renderer button))
        "ToggleButton maps to a distinct native control kind")
    (runtime/dispatch! application (proto/ToggleChanged button true))
    (runtime/dispatch! application (proto/LongPress button))
    (runtime/flush! application)
    (assert-equal 1 (count @toggles) "on-toggle receives one toggle event")
    (assert-equal
     1 @long-presses "on-long-press receives one long press event")
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
