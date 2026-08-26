(ns lui.phase3-hot-reload-test
  (:require [clojure.test :refer [deftest is]]
            [lui.hot-reload :as hot]
            [lui.migration :as migration]
            [lui.restart :as restart]))

(defmacro assert-equal [expected actual message]
  `(is (= ~expected ~actual) ~message))

(defn migrate-counter [payload]
  (record migrated-counter
    (counter-value payload)
    (counter-label "Migrated")))

(defn validate-counter [model]
  (if (= (:counter-value model) 7)
    None
    (Some "counter changed")))

(defn apply-counter [plan snapshot]
  (migration/apply plan snapshot))

(deftest typed-model-migration-validates-before-soft-restart
  (let [snapshot-result
        (migration/capture 1 "counter-v1" 7 (fn [^:int model] model))]
    (match snapshot-result
      (migration/SnapshotCaptureRejected message)
      (is false message)
      (migration/SnapshotCaptured snapshot)
      (let [plan
            (record migration/migration-plan
              (migration-source-version 1)
              (migration-source-fingerprint "counter-v1")
              (migration-target-fingerprint "counter-v2")
              (migrate-snapshot migrate-counter)
              (validate-model validate-counter))
            migrated (apply-counter plan snapshot)]
        (match migrated
          (migration/MigrationApplied model)
          (do
            (assert-equal 7 (:counter-value model)
                          "migration preserves the old model value")
            (assert-equal "Migrated" (:counter-label model)
                          "migration constructs the new concrete model"))
          _ (is false "the compatible typed migration applies"))
        (match
         (apply-counter
          (record migration/migration-plan
            (migration-source-version 1)
            (migration-source-fingerprint "other-v1")
            (migration-target-fingerprint "counter-v2")
            (migrate-snapshot migrate-counter)
            (validate-model validate-counter))
          snapshot)
          (migration/MigrationRestartRequired message)
          (assert-equal
           "snapshot fingerprint changed" message
           "an incompatible snapshot routes to restart rather than a cast")
          _ (is false "an incompatible snapshot requires restart"))))))

(deftest soft-restart-publishes-only-an-activated-candidate
  (let [discarded (atom [])
        retired (atom 0)
        failed
        (migration/soft-restart!
         (migration/MigrationApplied 8)
         (fn [model] (str "candidate-" model))
         (fn [_candidate] false)
         (fn [candidate]
           (swap! discarded conj candidate)
           true)
         (fn []
           (swap! retired inc)
           true))]
    (match failed
      (migration/SoftRestartRejected message)
      (assert-equal "candidate activation failed" message
                    "activation failure rejects the soft restart")
      _ (is false "activation failure rejects the soft restart"))
    (assert-equal ["candidate-8"] (deref discarded)
                  "a rejected candidate is disposed")
    (assert-equal 0 (deref retired)
                  "the old app remains live after candidate rejection")
    (let [applied
          (migration/soft-restart!
           (migration/MigrationApplied 9)
           (fn [model] (str "candidate-" model))
           (fn [_candidate] true)
           (fn [_candidate] true)
           (fn []
             (swap! retired inc)
             true))]
      (match applied
        (migration/SoftRestartApplied candidate)
        (assert-equal "candidate-9" candidate
                      "an activated candidate becomes the new app")
        _ (is false "an activated candidate becomes the new app"))
      (assert-equal 1 (deref retired)
                    "the old app retires only after activation"))))

(deftest migration-boundary-discards-incompatible-queued-messages
  (let [drained
        (migration/drain-compatible
         [(record migration/generation-message
            (message-generation 2)
            (message-fingerprint "counter-v2")
            (message-value 7))
          (record migration/generation-message
            (message-generation 1)
            (message-fingerprint "counter-v1")
            (message-value 8))
          (record migration/generation-message
            (message-generation 2)
            (message-fingerprint "other-v2")
            (message-value 9))]
         2 "counter-v2")]
    (assert-equal [7] (:compatible-messages drained)
                  "only exact-generation exact-fingerprint messages survive")
    (assert-equal 2 (:discarded-message-count drained)
                  "incompatible queued messages are counted and discarded")))

(deftest automatic-restart-restores-context-and-rejects-stale-work
  (let [steps (atom [])
        context
        (record restart/restart-context
          (restart-route (Some "/settings/profile"))
          (restart-selected-tabs (hash-map "settings" "profile"))
          (restart-focused-reload-key (Some "display-name"))
          (restart-selection
           (Some
            (record restart/text-selection
              (selection-start 2)
              (selection-end 5))))
          (restart-scroll-offsets (hash-map "main" 144.0))
          (restart-windows
           [(record restart/window-context
              (window-key "main")
              (window-x 20.0)
              (window-y 30.0)
              (window-width 900.0)
              (window-height 700.0)
              (window-active true))]))
        coordinator
        (restart/create
         (fn []
           (swap! steps conj "capture")
           context)
         (fn [_reason]
           (swap! steps conj "rebuild")
           restart/RestartStepCompleted)
         (fn [_context]
           (swap! steps conj "launch")
           restart/RestartStepCompleted)
         (fn [saved]
           (swap! steps conj "restore")
           (if (= (:restart-route saved) (Some "/settings/profile"))
             restart/RestartStepCompleted
             (restart/RestartStepRejected "route was lost"))))
        first (restart/request! coordinator)
        second (restart/request! coordinator)]
    (assert-equal
     (restart/RestartStale first)
     (restart/run! coordinator first restart/PackageGraphChanged)
     "a newer request prevents stale rebuild work")
    (assert-equal
     (restart/RestartCompleted second true)
     (restart/run! coordinator second restart/CompilerCrashed)
     "the newest incompatible edit rebuilds, launches, and restores context")
    (assert-equal ["capture" "rebuild" "launch" "restore"] (deref steps)
                  "automatic restart runs the complete fallback pipeline")
    (assert-equal 2 (count (restart/events coordinator))
                  "tooling receives stale and completed fallback decisions")))

(deftest automatic-fallback-reports-rebuild-failure-without-launching
  (let [launches (atom 0)
        context
        (record restart/restart-context
          (restart-route None)
          (restart-selected-tabs (hash-map))
          (restart-focused-reload-key None)
          (restart-selection None)
          (restart-scroll-offsets (hash-map))
          (restart-windows []))
        coordinator
        (restart/create
         (fn [] context)
         (fn [_reason]
           (restart/RestartStepRejected "compiler unavailable"))
         (fn [_context]
           (swap! launches inc)
           restart/RestartStepCompleted)
         (fn [_context] restart/RestartStepCompleted))]
    (match (restart/automatic! coordinator restart/TargetDisconnected)
      (restart/RestartRejected generation stage message)
      (do
        (assert-equal 1 generation "automatic fallback requests a generation")
        (assert-equal "rebuild" stage "the failed fallback stage is explicit")
        (assert-equal "compiler unavailable" message
                      "the underlying rebuild error remains visible"))
      _ (is false "rebuild failure is reported"))
    (assert-equal 0 (deref launches)
                  "a failed rebuild never replaces the old target")))

(deftest incompatible-hot-reload-contract-automatically-enters-fallback
  (let [context
        (record restart/restart-context
          (restart-route None)
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
        session (hot/create "source-a" "contract-a" "root-a")
        request (hot/request! session)
        status
        (hot/publish!
         session request "source-b" "contract-b" "root-b"
         (fn [_candidate] None) 4)]
    (match
     (restart/handle-reload! coordinator status restart/ModelTypeChanged)
      (Some (restart/RestartCompleted generation true))
      (assert-equal 1 generation
                    "contract mismatch automatically runs fallback")
      _ (is false "contract mismatch automatically runs fallback"))
    (assert-equal "root-a" (hot/current-root session)
                  "in-place publication keeps its last-known-good root")))
