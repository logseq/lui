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
        root (gensym "root")]
    `(let [~scheduler (signal.core/scheduler)
           ~application (lui.runtime/create ~scheduler ~backend)
           ~scope (signal.core/scope "app")
           ~context (lui.ui/context ~application ~scope)
           ~model-state (signal.core/state ~scheduler ~initial-model)
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
            (lui.app/reduce! ~model-state ~reducer ~'action)))
         (app-root-node ~root)))))

(defn start! [app]
  (sig/mount! (:app-scope app)))

(defn flush! [app]
  (runtime/flush! (:app-runtime app)))

(defmacro model [app]
  `((:app-read-model ~app)))

(defn root-node [app]
  (:app-root-node app))

(defn runtime [app]
  (:app-runtime app))

(defmacro send! [app action]
  `((:app-send-action ~app) ~action))

(defn dispatch-event! [app event]
  (runtime/dispatch! (:app-runtime app) event))
