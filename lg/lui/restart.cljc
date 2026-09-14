(ns lui.restart
  (:refer-clojure :exclude [run!])
  (:require [lui.hot-reload :as hot]))

(defn create [capture rebuild launch restore]
  (record restart-coordinator
          (capture-restart-context capture)
          (rebuild-target rebuild)
          (launch-target launch)
          (restore-restart-context restore)
          (restart-requested-generation (atom 0))
          (restart-completed-generation (atom 0))
          (restart-events (atom []))))

(defn request! [coordinator]
  (swap! (:restart-requested-generation coordinator) inc))

(defn- record-event! [coordinator generation reason status completed]
  (when completed
    (reset! (:restart-completed-generation coordinator) generation))
  (swap!
   (:restart-events coordinator)
   conj
   (record restart-event
           (restart-event-generation generation)
           (restart-event-reason reason)
           (restart-event-status status)))
  status)

(defn- reject! [coordinator generation reason stage message]
  (record-event!
   coordinator generation reason
   (RestartRejected generation stage message) true))

(defn- run-step [step argument]
  (try
    (step argument)
    (catch (Invalid_argument message)
           (RestartStepRejected message))))

(defn- capture-context [coordinator]
  (try
    (RestartContextCaptured ((:capture-restart-context coordinator)))
    (catch (Invalid_argument message)
           (RestartContextRejected message))))

(defn run! [coordinator generation reason]
  (let [requested (deref (:restart-requested-generation coordinator))
        completed (deref (:restart-completed-generation coordinator))]
    (cond
      (or (< generation requested) (<= generation completed))
      (record-event!
       coordinator generation reason (RestartStale generation) false)
      (or (<= generation 0) (> generation requested))
      (reject!
       coordinator generation reason "request"
       "restart generation was not requested")
      :else
      (match (capture-context coordinator)
        (RestartContextRejected message)
        (reject! coordinator generation reason "capture" message)
        (RestartContextCaptured context)
          (match (run-step (:rebuild-target coordinator) reason)
            (RestartStepRejected message)
            (reject! coordinator generation reason "rebuild" message)
            RestartStepCompleted
            (match (run-step (:launch-target coordinator) context)
              (RestartStepRejected message)
              (reject! coordinator generation reason "launch" message)
              RestartStepCompleted
              (match (run-step (:restore-restart-context coordinator) context)
                (RestartStepRejected message)
                (reject! coordinator generation reason "restore" message)
                RestartStepCompleted
                (record-event!
                 coordinator generation reason
                 (RestartCompleted generation true) true))))))))

(defn automatic! [coordinator reason]
  (run! coordinator (request! coordinator) reason))

(defn handle-reload! [coordinator status reason]
  (match status
    (hot/ReloadRestartRequired _generation _message)
    (Some (automatic! coordinator reason))
    _ None))

(defn events [coordinator]
  (deref (:restart-events coordinator)))
