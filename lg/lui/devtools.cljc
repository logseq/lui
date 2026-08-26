(ns lui.devtools
  (:require [lui.hot-reload :as hot]
            [lui.restart :as restart]
            [lui.ui :as ui]))

(defn create []
  (record developer-session
    (developer-events (atom []))
    (developer-diagnostics (atom (hash-map)))
    (developer-latencies (atom []))
    (developer-overlay-visible (atom false))
    (developer-overlay-collapsed (atom false))
    (developer-overlay-generation (atom 0))
    (developer-overlay-title (atom ""))
    (developer-overlay-detail (atom ""))))

(defn- diagnostic-key [diagnostic]
  (str
   (:diagnostic-code diagnostic) "\u0000"
   (:diagnostic-message diagnostic) "\u0000"
   (match (:diagnostic-range diagnostic)
     (Some location)
     (str (:range-file location) ":"
          (:range-start-line location) ":"
          (:range-start-column location) ":"
          (:range-end-line location) ":"
          (:range-end-column location))
     None "")))

(defn- record-event! [session event]
  (swap! (:developer-events session) conj event)
  true)

(defn- show-overlay! [session generation title detail]
  (reset! (:developer-overlay-visible session) true)
  (reset! (:developer-overlay-generation session) generation)
  (reset! (:developer-overlay-title session) title)
  (reset! (:developer-overlay-detail session) detail)
  true)

(defn- hide-overlay! [session]
  (reset! (:developer-overlay-visible session) false)
  (reset! (:developer-overlay-collapsed session) false)
  true)

(defn record-change-detected! [session generation paths]
  (record-event! session (DeveloperChangeDetected generation paths)))

(defn record-compilation-started! [session generation]
  (record-event! session (DeveloperCompilationStarted generation)))

(defn record-diagnostic! [session generation diagnostic]
  (swap!
   (:developer-diagnostics session)
   assoc (diagnostic-key diagnostic) diagnostic)
  (show-overlay!
   session generation (:diagnostic-code diagnostic)
   (:diagnostic-message diagnostic))
  (record-event! session (DeveloperDiagnostic generation diagnostic)))

(defn editor-diagnostics [session]
  (reduce-kv
   (fn [result _key diagnostic] (conj result diagnostic))
   []
   (deref (:developer-diagnostics session))))

(defn overlay [session]
  (record overlay-model
    (overlay-visible (deref (:developer-overlay-visible session)))
    (overlay-collapsed (deref (:developer-overlay-collapsed session)))
    (overlay-generation (deref (:developer-overlay-generation session)))
    (overlay-title (deref (:developer-overlay-title session)))
    (overlay-detail (deref (:developer-overlay-detail session)))))

(defn render-overlay! [context model]
  (let [toast (ui/toast! context)
        title (ui/text! context (:overlay-title model))]
    (ui/append! context toast title)
    (when-not (:overlay-collapsed model)
      (let [detail (ui/text! context (:overlay-detail model))]
        (ui/append! context toast detail)))
    toast))

(defn collapse-overlay! [session]
  (reset! (:developer-overlay-collapsed session) true)
  true)

(defn expand-overlay! [session]
  (reset! (:developer-overlay-collapsed session) false)
  true)

(defn record-latency! [session elapsed-ms]
  (when (< elapsed-ms 0)
    (raise (Invalid_argument "reload latency cannot be negative")))
  (swap! (:developer-latencies session) conj elapsed-ms)
  true)

(defn- percentile [sorted-latencies percent]
  (if (empty? sorted-latencies)
    0
    (let [sample-count (count sorted-latencies)
          rank (quot (+ (* sample-count percent) 99) 100)
          index (dec (max 1 rank))]
      (nth sorted-latencies index))))

(defn latency-summary [session]
  (let [sorted-latencies
        (vec (sort (deref (:developer-latencies session))))
        sample-count (count sorted-latencies)]
    (record reload-latency-summary
      (latency-sample-count sample-count)
      (latency-p50-ms (percentile sorted-latencies 50))
      (latency-p95-ms (percentile sorted-latencies 95))
      (latency-max-ms
       (if (= sample-count 0)
         0
         (nth sorted-latencies (dec sample-count)))))))

(defn ingest-reload! [session event affected-roots invalidated-nodes inspection]
  (let [generation (:reload-event-generation event)
        elapsed-ms (:reload-event-elapsed-ms event)]
    (match (:reload-event-status event)
      (hot/ReloadApplied _generation)
      (do
        (reset! (:developer-diagnostics session) (hash-map))
        (record-latency! session elapsed-ms)
        (hide-overlay! session)
        (record-event!
         session
         (DeveloperReloadCommitted
          generation elapsed-ms affected-roots invalidated-nodes inspection)))
      (hot/ReloadUnchanged _generation)
      (do
        (reset! (:developer-diagnostics session) (hash-map))
        (record-latency! session elapsed-ms)
        (hide-overlay! session)
        (record-event!
         session (DeveloperReloadUnchanged generation elapsed-ms)))
      (hot/ReloadRejected _generation message)
      (do
        (show-overlay! session generation "Reload rejected" message)
        (record-event!
         session (DeveloperReloadRejected generation message)))
      (hot/ReloadStale _generation)
      (record-event! session (DeveloperReloadStale generation))
      (hot/ReloadRestartRequired _generation message)
      (do
        (show-overlay! session generation "Restart required" message)
        (record-event!
         session (DeveloperRestartRequired generation message))))))

(defn record-target-disconnected! [session message]
  (show-overlay! session 0 "Target disconnected" message)
  (record-event! session (DeveloperTargetDisconnected message)))

(defn record-migration-required! [session message]
  (show-overlay! session 0 "Migration required" message)
  (record-event! session (DeveloperMigrationRequired message)))

(defn record-migration-failed! [session message]
  (show-overlay! session 0 "Migration failed" message)
  (record-event! session (DeveloperMigrationFailed message)))

(defn ingest-restart! [session event]
  (let [generation (:restart-event-generation event)
        reason (:restart-event-reason event)]
    (match (:restart-event-status event)
      (restart/RestartStale _generation)
      (record-event! session (DeveloperRestartStale generation))
      (restart/RestartCompleted _generation restored)
      (do
        (record-event! session (DeveloperRestartStarted generation reason))
        (hide-overlay! session)
        (record-event!
         session (DeveloperRestartCompleted generation restored)))
      (restart/RestartRejected _generation stage message)
      (do
        (record-event! session (DeveloperRestartStarted generation reason))
        (show-overlay!
         session generation (str "Restart failed during " stage) message)
        (record-event!
         session (DeveloperRestartRejected generation stage message))))))

(defn record-protocol-mismatch! [session expected actual]
  (show-overlay!
   session 0 "Protocol mismatch"
   (str "expected " expected ", got " actual))
  (record-event! session (DeveloperProtocolMismatch expected actual)))

(defn events [session]
  (deref (:developer-events session)))

(defn latest-event [session]
  (let [current (events session)]
    (if (empty? current)
      None
      (Some (nth current (dec (count current)))))))
