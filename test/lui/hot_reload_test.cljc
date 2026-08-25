(ns lui.hot-reload-test
  (:require [clojure.test :refer [deftest is]]
            [lui.hot-reload :as hot]))

(defmacro assert-equal [expected actual message]
  `(is (= ~expected ~actual) ~message))

(defn render-count [prefix count]
  (str prefix count))

(deftest successful-publication-updates-existing-callers
  (let [model (atom 7)
        initial-root (fn [^:int count] (render-count "Count: " count))
        next-root (fn [^:int count] (render-count "Total: " count))
        session (hot/create "source-a" "contract-a" initial-root)
        caller (fn [] ((hot/current-root session) (deref model)))
        request (hot/request! session)
        status
        (hot/publish!
         session request "source-b" "contract-a" next-root
         (fn [_candidate] None) 24)]
    (assert-equal (hot/ReloadApplied request) status
                  "a valid candidate is applied")
    (assert-equal "Total: 7" (caller)
                  "an existing caller observes the replaced typed root")
    (assert-equal 7 (deref model) "publication preserves external model state")
    (assert-equal request (hot/generation session)
                  "publication commits the requested generation")
    (assert-equal "source-b" (hot/source-hash session)
                  "publication commits the candidate source hash")))

(deftest validation-failure-keeps-the-last-known-good-generation
  (let [initial-root (fn [^:int count] (render-count "Count: " count))
        invalid-root (fn [^:int count] (render-count "Broken: " count))
        session (hot/create "source-a" "contract-a" initial-root)
        request (hot/request! session)
        status
        (hot/publish!
         session request "source-b" "contract-a" invalid-root
         (fn [_candidate] (Some "candidate tree is invalid")) 8)]
    (assert-equal
     (hot/ReloadRejected request "candidate tree is invalid") status
     "candidate validation reports a structured rejection")
    (assert-equal "Count: 3" ((hot/current-root session) 3)
                  "a rejected candidate cannot replace the current root")
    (assert-equal 0 (hot/generation session)
                  "a rejected candidate cannot advance the generation")
    (assert-equal "source-a" (hot/source-hash session)
                  "a rejected candidate cannot replace the source hash")))

(deftest unchanged-content-does-not-publish-a-generation
  (let [initial-root (fn [^:int count] (render-count "Count: " count))
        session (hot/create "source-a" "contract-a" initial-root)
        request (hot/request! session)
        status
        (hot/publish!
         session request "source-a" "contract-a" initial-root
         (fn [_candidate] None) 2)]
    (assert-equal (hot/ReloadUnchanged request) status
                  "identical content is reported as unchanged")
    (assert-equal 0 (hot/generation session)
                  "unchanged content does not advance the generation")
    (assert-equal 1 (count (hot/events session))
                  "unchanged publication still produces one tooling event")))

(deftest stale-results-cannot-overwrite-a-newer-request
  (let [initial-root (fn [^:int count] (render-count "Count: " count))
        stale-root (fn [^:int count] (render-count "Stale: " count))
        newest-root (fn [^:int count] (render-count "Newest: " count))
        session (hot/create "source-a" "contract-a" initial-root)
        stale-request (hot/request! session)
        newest-request (hot/request! session)
        stale-status
        (hot/publish!
         session stale-request "source-stale" "contract-a" stale-root
         (fn [_candidate] None) 40)]
    (assert-equal (hot/ReloadStale stale-request) stale-status
                  "an older result is classified as stale")
    (assert-equal "Count: 4" ((hot/current-root session) 4)
                  "a stale result leaves the committed root untouched")
    (let [newest-status
          (hot/publish!
           session newest-request "source-newest" "contract-a" newest-root
           (fn [_candidate] None) 10)]
      (assert-equal (hot/ReloadApplied newest-request) newest-status
                    "the newest requested result can still commit")
      (assert-equal "Newest: 4" ((hot/current-root session) 4)
                    "the newest root becomes visible"))))

(deftest unrequested-generation-is-rejected
  (let [initial-root (fn [^:int count] (render-count "Count: " count))
        candidate-root (fn [^:int count] (render-count "Future: " count))
        session (hot/create "source-a" "contract-a" initial-root)
        status
        (hot/publish!
         session 1 "source-future" "contract-a" candidate-root
         (fn [_candidate] None) 1)]
    (assert-equal
     (hot/ReloadRejected 1 "candidate generation was not requested") status
     "a fabricated future generation is rejected")
    (assert-equal 0 (hot/generation session)
                  "an unrequested generation cannot commit")))

(deftest incompatible-contract-requires-restart-without-publication
  (let [initial-root (fn [^:int count] (render-count "Count: " count))
        incompatible-root (fn [^:int count] (render-count "Changed: " count))
        session (hot/create "source-a" "contract-a" initial-root)
        request (hot/request! session)
        status
        (hot/publish!
         session request "source-b" "contract-b" incompatible-root
         (fn [_candidate] None) 5)]
    (assert-equal
     (hot/ReloadRestartRequired request "root contract changed") status
     "an incompatible static contract selects the restart path")
    (assert-equal "Count: 9" ((hot/current-root session) 9)
                  "restart classification keeps the last known-good root")
    (assert-equal 0 (hot/generation session)
                  "restart classification does not publish in place")
    (match (hot/latest-event session)
      (Some event)
      (do
        (assert-equal request (:reload-event-generation event)
                      "the tooling event identifies the request")
        (assert-equal "source-b" (:reload-event-source-hash event)
                      "the tooling event identifies the candidate source")
        (assert-equal 5 (:reload-event-elapsed-ms event)
                      "the tooling event records candidate latency")
        (assert-equal status (:reload-event-status event)
                      "the tooling event records the fallback decision"))
      None (is false "restart classification emits a tooling event"))))

(deftest committed-generation-cannot-publish-twice
  (let [initial-root (fn [^:int count] (render-count "Count: " count))
        first-root (fn [^:int count] (render-count "First: " count))
        duplicate-root (fn [^:int count] (render-count "Duplicate: " count))
        session (hot/create "source-a" "contract-a" initial-root)
        request (hot/request! session)
        first-status
        (hot/publish!
         session request "source-b" "contract-a" first-root
         (fn [_candidate] None) 3)
        duplicate-status
        (hot/publish!
         session request "source-c" "contract-a" duplicate-root
         (fn [_candidate] None) 4)]
    (assert-equal (hot/ReloadApplied request) first-status
                  "the requested generation commits once")
    (assert-equal (hot/ReloadStale request) duplicate-status
                  "a duplicate result is stale after its generation commits")
    (assert-equal "First: 2" ((hot/current-root session) 2)
                  "a duplicate result cannot replace committed code")
    (assert-equal "source-b" (hot/source-hash session)
                  "a duplicate result cannot replace committed metadata")))

(deftest validator-exception-is-a-recoverable-rejection
  (let [initial-root (fn [^:int count] (render-count "Count: " count))
        candidate-root (fn [^:int count] (render-count "Candidate: " count))
        session (hot/create "source-a" "contract-a" initial-root)
        request (hot/request! session)
        status
        (hot/publish!
         session request "source-b" "contract-a" candidate-root
         (fn [_candidate]
           (raise (Invalid_argument "candidate validation crashed")))
         6)]
    (assert-equal
     (hot/ReloadRejected request "candidate validation crashed") status
     "validator exceptions become reload diagnostics")
    (assert-equal "Count: 6" ((hot/current-root session) 6)
                  "validator exceptions preserve the last known-good root")
    (assert-equal 0 (hot/generation session)
                  "validator exceptions cannot advance the generation")))
