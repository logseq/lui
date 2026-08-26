(ns lui.phase4-hot-reload-test
  (:require [clojure.test :refer [deftest is]]
            [signal.core :as sig]
            [lui.devtools :as dev]
            [lui.hot-reload :as hot]
            [lui.protocol :as proto]
            [lui.restart :as restart]
            [lui.runtime :as runtime]
            [lui.ui :as ui]
            [lui.backend.apple :as apple]))

(defmacro assert-equal [expected actual message]
  `(is (= ~expected ~actual) ~message))

(deftest editor-diagnostics-and-overlay-share-one-deduplicated-session
  (let [session (dev/create)
        source-range
        (record dev/source-range
          (range-file "src/app.cljc")
          (range-start-line 12)
          (range-start-column 4)
          (range-end-line 12)
          (range-end-column 18))
        diagnostic
        (record dev/hot-diagnostic
          (diagnostic-code "LG2000")
          (diagnostic-phase dev/TypeDiagnostic)
          (diagnostic-message "expected int, got string")
          (diagnostic-range (Some source-range))
          (diagnostic-related-ranges []))]
    (dev/record-change-detected! session 3 ["src/app.cljc"])
    (dev/record-compilation-started! session 3)
    (dev/record-diagnostic! session 3 diagnostic)
    (dev/record-diagnostic! session 3 diagnostic)
    (assert-equal 1 (count (dev/editor-diagnostics session))
                  "identical editor diagnostics are deduplicated")
    (let [overlay (dev/overlay session)]
      (assert-equal true (:overlay-visible overlay)
                    "a diagnostic opens the in-application overlay")
      (assert-equal false (:overlay-collapsed overlay)
                    "the overlay starts expanded")
      (assert-equal 3 (:overlay-generation overlay)
                    "the overlay identifies the failed generation"))
    (dev/collapse-overlay! session)
    (assert-equal true (:overlay-collapsed (dev/overlay session))
                  "the non-modal overlay can be collapsed")
    (let [reload-session (hot/create "source-a" "contract-a" "root-a")
          request (hot/request! reload-session)
          _status
          (hot/publish!
           reload-session request "source-b" "contract-a" "root-b"
           (fn [_candidate] None) 42)
          event
          (match (hot/latest-event reload-session)
            (Some current) current
            None (raise (Invalid_argument "missing reload event")))
          inspection
          (record dev/retained-state-inspection
            (inspection-widget-count 14)
            (inspection-handler-count 3)
            (inspection-subscription-count 1)
            (inspection-resource-count 2)
            (inspection-state-scope-count 4))]
      (dev/ingest-reload! session event ["view" "update"] [7 9] inspection)
      (assert-equal 0 (count (dev/editor-diagnostics session))
                    "the next successful generation clears diagnostics")
      (assert-equal false (:overlay-visible (dev/overlay session))
                    "the overlay disappears after a successful generation")
      (match (dev/latest-event session)
        (Some (dev/DeveloperReloadCommitted generation elapsed roots nodes state))
        (do
          (assert-equal request generation "tooling receives the generation")
          (assert-equal 42 elapsed "tooling receives reload latency")
          (assert-equal ["view" "update"] roots
                        "tooling receives affected typed roots")
          (assert-equal [7 9] nodes
                        "tooling receives component invalidation traces")
          (assert-equal 4 (:inspection-state-scope-count state)
                        "tooling receives retained-state inspection"))
        _ (is false "the committed developer event is available")))))

(deftest latency-summary-exposes-p50-and-p95-for-the-dashboard
  (let [session (dev/create)]
    (doseq [elapsed [20 1 13 2 19 3 18 4 17 5 16 6 15 7 14 8 12 9 11 10]]
      (dev/record-latency! session elapsed))
    (let [summary (dev/latency-summary session)]
      (assert-equal 20 (:latency-sample-count summary)
                    "the dashboard reports its sample size")
      (assert-equal 10 (:latency-p50-ms summary)
                    "p50 uses the nearest-rank sample")
      (assert-equal 19 (:latency-p95-ms summary)
                    "p95 uses the nearest-rank sample")
      (assert-equal 20 (:latency-max-ms summary)
                    "the dashboard exposes the slowest sample"))))

(deftest disconnect-and-protocol-mismatch-remain-visible
  (let [session (dev/create)]
    (dev/record-target-disconnected! session "socket closed")
    (assert-equal true (:overlay-visible (dev/overlay session))
                  "a disconnected target is visible in the app")
    (dev/record-protocol-mismatch! session "4" "3")
    (match (dev/latest-event session)
      (Some (dev/DeveloperProtocolMismatch expected actual))
      (do
        (assert-equal "4" expected "the expected protocol is reported")
        (assert-equal "3" actual "the target protocol is reported"))
      _ (is false "the protocol mismatch is a closed developer event"))))

(deftest diagnostic-overlay-renders-as-a-non-modal-toast
  (let [session (dev/create)
        diagnostic
        (record dev/hot-diagnostic
          (diagnostic-code "LG1002")
          (diagnostic-phase dev/ParseDiagnostic)
          (diagnostic-message "unexpected delimiter")
          (diagnostic-range None)
          (diagnostic-related-ranges []))
        scheduler (sig/scheduler)
        renderer (apple/create)
        application (runtime/create scheduler (apple/backend renderer))
        scope (sig/scope "hot-reload-overlay")
        context (ui/context application scope)
        root (runtime/create-node! application proto/Root)]
    (dev/record-diagnostic! session 7 diagnostic)
    (let [toast (dev/render-overlay! context (dev/overlay session))]
      (runtime/insert-child! application root toast 0)
      (runtime/flush! application)
      (assert-equal (Some apple/AppleToast) (apple/node renderer toast)
                    "the in-app diagnostic surface is a native non-modal Toast")
      (assert-equal 2 (count (apple/children renderer toast))
                    "expanded overlay renders a title and diagnostic detail"))))

(deftest migration-and-restart-events-use-the-same-developer-protocol
  (let [session (dev/create)
        context
        (record restart/restart-context
          (restart-route (Some "/tasks"))
          (restart-selected-tabs (hash-map))
          (restart-focused-reload-key None)
          (restart-selection None)
          (restart-scroll-offsets (hash-map))
          (restart-windows []))
        coordinator
        (restart/create
         (fn [] context)
         (fn [_reason] restart/RestartStepCompleted)
         (fn [_context] restart/RestartStepCompleted)
         (fn [_context] restart/RestartStepCompleted))
        _status (restart/automatic! coordinator restart/ModelTypeChanged)
        restart-event
        (let [events (restart/events coordinator)]
          (nth events (dec (count events))))]
    (dev/record-migration-required! session "counter-v1 -> counter-v2")
    (dev/ingest-restart! session restart-event)
    (match (dev/latest-event session)
      (Some (dev/DeveloperRestartCompleted generation true))
      (assert-equal 1 generation
                    "the shared protocol reports automatic restart completion")
      _ (is false "restart completion reaches developer tooling"))
    (dev/record-migration-failed! session "counter field is invalid")
    (assert-equal true (:overlay-visible (dev/overlay session))
                  "migration failure remains visible in the same overlay")))
