(ns lui.hot-reload-view-test
  (:require [clojure.test :refer [deftest is]]
            [signal.core :as sig]
            [lui.app :as app]
            [lui.hot-reload :as hot]
            [lui.macros :refer [defui state]]
            [lui.protocol :as proto]
            [lui.runtime :as runtime]
            [lui.ui :as ui]
            [lui.backend.apple :as apple]))

(defmacro assert-equal [expected actual message]
  `(is (= ~expected ~actual) ~message))

(defn counter-label [prefix ^:int value]
  (str prefix value))

(defn counter-view [prefix step context model-source send]
  (let [root (ui/column! context)
        label
        (ui/text-signal!
         context
         (sig/own-signal!
          (:ui-scope context)
          (sig/map (fn [value] (counter-label prefix value)) model-source)))
        button (ui/button! context)]
    (ui/text-property! context button "Increment")
    (ui/on-event! context button (fn [_event] (send step)))
    (ui/append! context root label)
    (ui/append! context root button)
    root))

(defn initial-counter-view [context model-source send]
  (counter-view "Before " 1 context model-source send))

(defn replacement-counter-view [context model-source send]
  (counter-view "After " 10 context model-source send))

(defn invalid-counter-view [context _model-source _send]
  (runtime/create-node! (:ui-application context) proto/Root))

(defui local-count-state []
  (state 0))

(defn stateful-view [context prefix]
  (let [local-count (local-count-state context)
        root (ui/column! context)
        label
        (ui/text-signal!
         context
         (sig/own-signal!
          (:ui-scope context)
          (sig/map
           (fn [^:int value] (str prefix value))
           (sig/value local-count))))
        button (ui/button! context)]
    (ui/text-property! context button "Local increment")
    (ui/on-event!
     context button
     (fn [_event]
       (sig/update! local-count (fn [^:int value] (inc value)))))
    (ui/append! context root label)
    (ui/append! context root button)
    root))

(defn initial-stateful-view [context _model-source _send]
  (stateful-view
   (ui/child-context context "local-counter") "Before local "))

(defn replacement-stateful-view [context _model-source _send]
  (stateful-view
   (ui/child-context context "local-counter") "After local "))

(defn decorated-view [context _model-source _send]
  (let [root (ui/column! context)
        label (ui/text! context "Decorated")]
    (ui/padding! context root 24)
    (ui/append! context root label)
    root))

(defn plain-view [context _model-source _send]
  (let [root (ui/column! context)
        label (ui/text! context "Plain")]
    (ui/append! context root label)
    root))

(defn text-field-view [context _model-source _send]
  (let [root (ui/column! context)
        stable-label (ui/text! context "Stable")
        editor (ui/text-field! context)]
    (ui/accessibility-label! context editor "Draft")
    (ui/append! context root stable-label)
    (ui/append! context root editor)
    root))

(defn textarea-view [context _model-source _send]
  (let [root (ui/column! context)
        stable-label (ui/text! context "Stable after")
        editor (ui/textarea! context)]
    (ui/accessibility-label! context editor "Draft")
    (ui/append! context root stable-label)
    (ui/append! context root editor)
    root))

(defn keyed-row-view [context order]
  (let [root (ui/row! context)
        first-item (ui/text! context "First")
        second-item (ui/text! context "Second")]
    (ui/key! context first-item "first")
    (ui/key! context second-item "second")
    (if (= order :forward)
      (do
        (ui/append! context root first-item)
        (ui/append! context root second-item))
      (do
        (ui/append! context root second-item)
        (ui/append! context root first-item)))
    root))

(defn initial-keyed-view [context _model-source _send]
  (keyed-row-view context :forward))

(defn reordered-keyed-view [context _model-source _send]
  (keyed-row-view context :reverse))

(defn add-action [model action]
  (+ model action))

(deftest stable-root-publishes-one-atomic-child-replacement-batch
  (let [scheduler (sig/scheduler)
        renderer (apple/create)
        application (runtime/create scheduler (apple/backend renderer))
        scope (sig/scope "hot-reload-root")
        context (ui/context application scope)
        root (runtime/create-node! application proto/Root)
        initial (ui/text! context "Before")]
    (runtime/insert-child! application root initial 0)
    (runtime/flush! application)
    (assert-equal (Some apple/AppleRoot) (apple/node renderer root)
                  "the root has the dedicated backend identity")
    (let [replacement (ui/text! context "After")]
      (runtime/remove-child! application root initial)
      (runtime/insert-child! application root replacement 0)
      (runtime/drop-node! application initial)
      (runtime/flush! application)
      (assert-equal [replacement] (apple/children renderer root)
                    "the stable root points at the replacement subtree")
      (assert-equal 2 (count (apple/batches renderer))
                    "initial mount and replacement each use one batch")
      (assert-equal 2 (apple/node-count renderer)
                    "the previous subtree is released after replacement"))))

(deftest stable-root-rejects-an-invalid-child-count-transactionally
  (let [scheduler (sig/scheduler)
        renderer (apple/create)
        application (runtime/create scheduler (apple/backend renderer))
        scope (sig/scope "invalid-hot-reload-root")
        context (ui/context application scope)
        root (runtime/create-node! application proto/Root)
        first-child (ui/text! context "First")]
    (runtime/insert-child! application root first-child 0)
    (runtime/flush! application)
    (let [second-child (ui/text! context "Second")]
      (runtime/insert-child! application root second-child 1)
      (is (thrown? Invalid_argument (runtime/flush! application))
          "a runtime root cannot publish two visible children")
      (assert-equal [first-child] (apple/children renderer root)
                    "backend rejection preserves the last known-good child")
      (assert-equal 1 (runtime/generation application)
                    "backend rejection does not advance the visible generation"))))

(deftest stable-root-cannot-be-nested-or-styled
  (let [scheduler (sig/scheduler)
        renderer (apple/create)
        application (runtime/create scheduler (apple/backend renderer))
        scope (sig/scope "nested-hot-reload-root")
        context (ui/context application scope)
        container (ui/column! context)
        root (runtime/create-node! application proto/Root)]
    (is (thrown? Invalid_argument
                 (runtime/set-prop!
                  application root proto/StyleClass
                  (proto/StringValue "not-authorable")))
        "the internal root has no authorable properties")
    (is (thrown? Invalid_argument
                 (runtime/insert-child! application container root 0))
        "the internal root cannot be nested in an application view")))

(deftest reloadable-reducer-app-replaces-its-view-and-keeps-model-state
  (let [renderer (apple/create)
        application
        (app/create-reloadable
         (apple/backend renderer) "source-a" "contract-a"
         2 add-action initial-counter-view)]
    (app/start! application)
    (app/flush! application)
    (let [stable-root (app/root-node application)
          initial-view (nth (apple/children renderer stable-root) 0)
          initial-label (nth (apple/children renderer initial-view) 0)
          initial-button (nth (apple/children renderer initial-view) 1)]
      (assert-equal (Some apple/AppleRoot) (apple/node renderer stable-root)
                    "a reloadable app exposes one stable internal root")
      (app/dispatch-event! application (proto/Press initial-button))
      (app/flush! application)
      (assert-equal 3 (app/model application)
                    "the original handler updates the live typed model")
      (let [request (app/request-reload! application)
            status
            (app/reload-view!
             application request "source-b" "contract-a"
             replacement-counter-view 18)]
        (assert-equal (hot/ReloadApplied request) status
                      "a compatible typed view is hot-applied")
        (let [replacement-view (nth (apple/children renderer stable-root) 0)
              replacement-label
              (nth (apple/children renderer replacement-view) 0)
              replacement-button
              (nth (apple/children renderer replacement-view) 1)]
          (assert-equal initial-view replacement-view
                        "matching root containers retain native identity")
          (assert-equal initial-label replacement-label
                        "matching child nodes retain native identity")
          (assert-equal initial-button replacement-button
                        "matching controls retain focus-bearing identity")
          (match (apple/property renderer replacement-label proto/TextValue)
            (Some (proto/StringValue text))
            (assert-equal "After 3" text
                          "the replacement renders the preserved model")
            _ (is false "the replacement label has text"))
          (app/dispatch-event! application (proto/Press replacement-button))
          (app/flush! application)
          (assert-equal 13 (app/model application)
                        "new event dispatches use the replacement closure"))))))

(deftest rejected-view-candidate-restores-the-complete-runtime-checkpoint
  (let [renderer (apple/create)
        application
        (app/create-reloadable
         (apple/backend renderer) "source-a" "contract-a"
         4 add-action initial-counter-view)]
    (app/start! application)
    (app/flush! application)
    (let [stable-root (app/root-node application)
          committed-child (nth (apple/children renderer stable-root) 0)
          committed-count (runtime/mounted-count (app/runtime application))
          request (app/request-reload! application)
          status
          (app/reload-view!
           application request "source-invalid" "contract-a"
           invalid-counter-view 7)]
      (assert-equal
       (hot/ReloadRejected request "runtime root cannot be nested") status
       "an invalid candidate reports a recoverable reload rejection")
      (assert-equal [committed-child] (apple/children renderer stable-root)
                    "the backend keeps the last known-good view")
      (assert-equal [committed-child]
                    (runtime/children (app/runtime application) stable-root)
                    "the LG runtime rolls back to the same committed tree")
      (assert-equal committed-count
                    (runtime/mounted-count (app/runtime application))
                    "candidate nodes are removed from runtime ownership")
      (is (app/flush! application)
          "a rejected candidate leaves no poisoned pending operations")
      (assert-equal 4 (app/model application)
                    "candidate rejection preserves the typed model"))))

(deftest application-preflight-never-builds-a-stale-or-incompatible-view
  (let [renderer (apple/create)
        application
        (app/create-reloadable
         (apple/backend renderer) "source-a" "contract-a"
         1 add-action initial-counter-view)]
    (app/start! application)
    (app/flush! application)
    (let [stable-root (app/root-node application)
          committed-child (nth (apple/children renderer stable-root) 0)
          committed-count (runtime/mounted-count (app/runtime application))
          batch-count (count (apple/batches renderer))
          stale-request (app/request-reload! application)
          current-request (app/request-reload! application)]
      (assert-equal
       (hot/ReloadStale stale-request)
       (app/reload-view!
        application stale-request "source-stale" "contract-a"
        invalid-counter-view 3)
       "stale candidates are discarded before view construction")
      (assert-equal
       (hot/ReloadRestartRequired current-request "root contract changed")
       (app/reload-view!
        application current-request "source-b" "contract-b"
        invalid-counter-view 4)
       "contract changes route to restart without building a view")
      (assert-equal [committed-child] (apple/children renderer stable-root)
                    "preflight outcomes do not touch the visible tree")
      (assert-equal committed-count
                    (runtime/mounted-count (app/runtime application))
                    "preflight outcomes allocate no candidate nodes")
      (assert-equal batch-count (count (apple/batches renderer))
                    "preflight outcomes emit no patch batch"))))

(deftest repeated-view-reloads-release-old-nodes-handlers-and-subscriptions
  (let [renderer (apple/create)
        application
        (app/create-reloadable
         (apple/backend renderer) "source-0" "contract-a"
         0 add-action initial-counter-view)]
    (app/start! application)
    (app/flush! application)
    (loop [index 1]
      (when (<= index 40)
        (let [request (app/request-reload! application)
              view
              (if (= (mod index 2) 0)
                initial-counter-view
                replacement-counter-view)]
          (assert-equal
           (hot/ReloadApplied request)
           (app/reload-view!
            application request (str "source-" index) "contract-a" view 1)
           "every compatible generation commits")
          (assert-equal 4 (runtime/mounted-count (app/runtime application))
                        "only Root, Column, Text, and Button remain mounted")
          (assert-equal 1 (runtime/handler-count (app/runtime application))
                        "only the current generation handler remains")
          (recur (inc index)))))))

(deftest reload-reuses-compatible-positions-and-replaces-only-kind-changes
  (let [renderer (apple/create)
        application
        (app/create-reloadable
         (apple/backend renderer) "source-a" "contract-a"
         0 add-action text-field-view)]
    (app/start! application)
    (app/flush! application)
    (let [stable-root (app/root-node application)
          layout (nth (apple/children renderer stable-root) 0)
          label (nth (apple/children renderer layout) 0)
          text-field (nth (apple/children renderer layout) 1)
          request (app/request-reload! application)]
      (assert-equal
       (hot/ReloadApplied request)
       (app/reload-view!
        application request "source-b" "contract-a" textarea-view 2)
       "the mixed compatible candidate is applied")
      (let [next-layout (nth (apple/children renderer stable-root) 0)
            next-label (nth (apple/children renderer next-layout) 0)
            textarea (nth (apple/children renderer next-layout) 1)]
        (assert-equal layout next-layout
                      "the compatible parent retains identity")
        (assert-equal label next-label
                      "the compatible sibling retains identity")
        (is (not (= text-field textarea))
            "an incompatible control kind receives a new identity")
        (assert-equal (Some apple/AppleTextArea) (apple/node renderer textarea)
                      "the replacement control has the candidate kind")))))

(deftest reload-removes-properties-that-disappear-from-the-candidate
  (let [renderer (apple/create)
        application
        (app/create-reloadable
         (apple/backend renderer) "source-a" "contract-a"
         0 add-action decorated-view)]
    (app/start! application)
    (app/flush! application)
    (let [stable-root (app/root-node application)
          layout (nth (apple/children renderer stable-root) 0)
          request (app/request-reload! application)]
      (assert-equal (Some (proto/IntValue 24))
                    (apple/property renderer layout proto/PaddingValue)
                    "the committed view starts with padding")
      (assert-equal
       (hot/ReloadApplied request)
       (app/reload-view!
        application request "source-b" "contract-a" plain-view 2)
       "the property-removal candidate is applied")
      (assert-equal layout (nth (apple/children renderer stable-root) 0)
                    "property removal does not replace the layout node")
      (assert-equal None (apple/property renderer layout proto/PaddingValue)
                    "properties absent from the candidate are removed"))))

(deftest reload-preserves-view-local-state-at-a-compatible-component-slot
  (let [renderer (apple/create)
        application
        (app/create-reloadable
         (apple/backend renderer) "source-a" "contract-a"
         0 add-action initial-stateful-view)]
    (app/start! application)
    (app/flush! application)
    (let [stable-root (app/root-node application)
          layout (nth (apple/children renderer stable-root) 0)
          label (nth (apple/children renderer layout) 0)
          button (nth (apple/children renderer layout) 1)]
      (app/dispatch-event! application (proto/Press button))
      (app/flush! application)
      (match (apple/property renderer label proto/TextValue)
        (Some (proto/StringValue text))
        (assert-equal "Before local 1" text "local state updates before reload")
        _ (is false "the local-state label has text"))
      (let [request (app/request-reload! application)]
        (assert-equal
         (hot/ReloadApplied request)
         (app/reload-view!
          application request "source-b" "contract-a"
          replacement-stateful-view 2)
         "the stateful candidate is applied")
        (let [next-layout (nth (apple/children renderer stable-root) 0)
              next-label (nth (apple/children renderer next-layout) 0)]
          (assert-equal layout next-layout
                        "the stateful component root retains identity")
          (assert-equal label next-label
                        "the stateful label retains identity")
          (match (apple/property renderer next-label proto/TextValue)
            (Some (proto/StringValue text))
            (assert-equal "After local 1" text
                          "the compatible state slot retains its value")
            _ (is false "the reloaded local-state label has text")))))))

(deftest reload-matches-keyed-children-across-reordering
  (let [renderer (apple/create)
        application
        (app/create-reloadable
         (apple/backend renderer) "source-a" "contract-a"
         0 add-action initial-keyed-view)]
    (app/start! application)
    (app/flush! application)
    (let [stable-root (app/root-node application)
          row (nth (apple/children renderer stable-root) 0)
          first-item (nth (apple/children renderer row) 0)
          second-item (nth (apple/children renderer row) 1)
          request (app/request-reload! application)]
      (assert-equal
       (hot/ReloadApplied request)
       (app/reload-view!
        application request "source-b" "contract-a"
        reordered-keyed-view 0)
       "a keyed reordering hot-applies")
      (assert-equal [second-item first-item] (apple/children renderer row)
                    "native identities follow explicit keys across moves"))))

(deftest reload-prunes-state-scopes-for-removed-component-paths
  (let [renderer (apple/create)
        application
        (app/create-reloadable
         (apple/backend renderer) "source-a" "contract-a"
         0 add-action initial-stateful-view)]
    (app/start! application)
    (app/flush! application)
    (let [stable-root (app/root-node application)
          layout (nth (apple/children renderer stable-root) 0)
          button (nth (apple/children renderer layout) 1)]
      (app/dispatch-event! application (proto/Press button))
      (app/flush! application)
      (let [remove-request (app/request-reload! application)]
        (assert-equal
         (hot/ReloadApplied remove-request)
         (app/reload-view!
          application remove-request "source-b" "contract-a" plain-view 0)
         "removing the stateful component hot-applies"))
      (let [restore-request (app/request-reload! application)]
        (assert-equal
         (hot/ReloadApplied restore-request)
         (app/reload-view!
          application restore-request "source-c" "contract-a"
          initial-stateful-view 0)
         "adding the component path again hot-applies"))
      (let [next-layout (nth (apple/children renderer stable-root) 0)
            next-label (nth (apple/children renderer next-layout) 0)]
        (match (apple/property renderer next-label proto/TextValue)
          (Some (proto/StringValue text))
          (assert-equal "Before local 0" text
                        "a removed component path receives fresh local state")
          _ (is false "the recreated local-state label has text"))))))
