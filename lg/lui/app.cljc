(ns lui.app
  (:require [signal.core :as sig]
            [lui.runtime :as runtime]
            [lui.ui :as ui]))

(defn reduce! [model-state reducer action]
  (sig/update!
   model-state
   (fn [current] (reducer current action))))

(defmacro create [backend initial-model reducer view]
  (let [scheduler (gensym "scheduler")
        application (gensym "application")
        scope (gensym "scope")
        context (gensym "context")
        model-state (gensym "model_state")
        lifecycle (gensym "lifecycle")
        root (gensym "root")]
    `(let [~scheduler (signal.core/scheduler)
           ~application (lui.runtime/create ~scheduler ~backend)
           ~scope (signal.core/scope "app")
           ~context (lui.ui/context ~application ~scope)
           ~model-state (signal.core/state ~scheduler ~initial-model)
           ~lifecycle (atom lui.app/Running)
           ~root
           (~view
            ~context
            (signal.core/value ~model-state)
            (fn [~'action]
              (lui.app/reduce! ~model-state ~reducer ~'action)))]
       (record lui.app/reducer-app
         (app-scheduler ~scheduler)
         (app-runtime ~application)
         (app-scope ~scope)
         (app-read-model (fn [] (signal.core/get ~model-state)))
         (app-send-action
          (fn [~'action]
            (if (= (deref ~lifecycle) lui.app/Running)
              (lui.app/reduce! ~model-state ~reducer ~'action)
              false)))
         (app-root-node ~root)
         (app-lifecycle-state ~lifecycle)))))

(defn start! [app]
  (if (= (deref (:app-lifecycle-state app)) Running)
    (sig/mount! (:app-scope app))
    false))

(defn flush! [app]
  (if (= (deref (:app-lifecycle-state app)) Disposed)
    true
    (runtime/flush! (:app-runtime app))))

(defn dispose! [app]
  (match (deref (:app-lifecycle-state app))
    Disposed true
    Running
    (do
      (reset! (:app-lifecycle-state app) Disposing)
      (sig/dispose-scope! (:app-scope app))
      (runtime/drop-subtree! (:app-runtime app) (:app-root-node app))
      (when (runtime/flush! (:app-runtime app))
        (reset! (:app-lifecycle-state app) Disposed))
      true)
    Disposing
    (do
      (when (runtime/flush! (:app-runtime app))
        (reset! (:app-lifecycle-state app) Disposed))
      true)))

(defn disposed? [app]
  (= (deref (:app-lifecycle-state app)) Disposed))

(defmacro model [app]
  `((:app-read-model ~app)))

(defn root-node [app]
  (:app-root-node app))

(defn runtime [app]
  (:app-runtime app))

(defmacro send! [app action]
  `((:app-send-action ~app) ~action))

(defn dispatch-event! [app event]
  (if (= (deref (:app-lifecycle-state app)) Running)
    (runtime/dispatch! (:app-runtime app) event)
    false))
