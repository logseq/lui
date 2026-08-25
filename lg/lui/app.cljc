(ns lui.app
  (:require [signal.core :as sig]
            [lui.hot-reload :as hot]
            [lui.protocol :as proto]
            [lui.runtime :as runtime]
            [lui.ui :as ui]))

(defn reduce! [model-state reducer action]
  (sig/update!
   model-state
   (fn [current] (reducer current action))))

(macro-helper-defn reducer-app-expansion
  [backend registry initial-model reducer view]
  (let [scheduler (gensym "scheduler")
        application (gensym "application")
        scope (gensym "scope")
        context (gensym "context")
        model-state (gensym "model_state")
        lifecycle (gensym "lifecycle")
        root (gensym "root")]
    `(let [~scheduler (signal.core/scheduler)
           ~application
           ~(if registry
              `(lui.runtime/create-with-extensions
                ~scheduler ~backend ~registry)
              `(lui.runtime/create ~scheduler ~backend))
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
         (app-lifecycle-state ~lifecycle)
         (app-reload-state None)))))

(macro-helper-defn reloadable-app-expansion
  [backend registry source-hash contract-hash initial-model reducer view]
  (let [scheduler (gensym "scheduler")
        application (gensym "application")
        scope (gensym "scope")
        view-scope (gensym "view_scope")
        state-scope (gensym "state_scope")
        state-scopes (gensym "state_scopes")
        context (gensym "context")
        model-state (gensym "model_state")
        lifecycle (gensym "lifecycle")
        send-action (gensym "send_action")
        root (gensym "root")
        view-node (gensym "view_node")
        session (gensym "session")]
    `(let [~scheduler (signal.core/scheduler)
           ~application
           ~(if registry
              `(lui.runtime/create-with-extensions
                ~scheduler ~backend ~registry)
              `(lui.runtime/create ~scheduler ~backend))
           ~scope (signal.core/scope "app")
           ~view-scope (signal.core/scope "app-view-0" ~scope)
           ~state-scope (signal.core/scope "app-view-state" ~scope)
           ~state-scopes (atom (hash-map))
           ~context
           (lui.ui/context-with-state-registry
            ~application ~view-scope ~state-scope ~state-scopes)
           ~model-state (signal.core/state ~scheduler ~initial-model)
           ~lifecycle (atom lui.app/Running)
           ~send-action
           (fn [~'action]
             (if (= (deref ~lifecycle) lui.app/Running)
               (lui.app/reduce! ~model-state ~reducer ~'action)
               false))
           ~root (lui.runtime/create-node! ~application lui.protocol/Root)
           ~view-node
           (~view ~context (signal.core/value ~model-state) ~send-action)
           ~session (lui.hot-reload/create ~source-hash ~contract-hash ~view)]
       (lui.runtime/insert-child! ~application ~root ~view-node 0)
       (record lui.app/reducer-app
         (app-scheduler ~scheduler)
         (app-runtime ~application)
         (app-scope ~scope)
         (app-read-model (fn [] (signal.core/get ~model-state)))
         (app-send-action ~send-action)
         (app-root-node ~root)
         (app-lifecycle-state ~lifecycle)
         (app-reload-state
          (Some
           (record lui.app/reloadable-view-state
             (reload-model-source (signal.core/value ~model-state))
             (reload-view-scope (atom ~view-scope))
             (reload-state-scope ~state-scope)
             (reload-state-scopes ~state-scopes)
             (reload-view-node (atom ~view-node))
             (reload-session ~session))))))))

(defmacro create [backend initial-model reducer view]
  (reducer-app-expansion backend nil initial-model reducer view))

(defmacro create-with-extensions
  [backend registry initial-model reducer view]
  (reducer-app-expansion backend registry initial-model reducer view))

(defmacro create-reloadable
  [backend source-hash contract-hash initial-model reducer view]
  (reloadable-app-expansion
   backend nil source-hash contract-hash initial-model reducer view))

(defmacro create-reloadable-with-extensions
  [backend registry source-hash contract-hash initial-model reducer view]
  (reloadable-app-expansion
   backend registry source-hash contract-hash initial-model reducer view))

(defn start! [app]
  (if (= (deref (:app-lifecycle-state app)) Running)
    (do
      (sig/mount! (:app-scope app))
      (match (:app-reload-state app)
        (Some state)
        (do
          (sig/mount! (:reload-state-scope state))
          (sig/mount! (deref (:reload-view-scope state))))
        None true))
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

(defn- require-reload-state [app]
  (match (:app-reload-state app)
    (Some state) state
    None (raise (Invalid_argument "application is not reloadable"))))

(defn request-reload! [app]
  (hot/request! (:reload-session (require-reload-state app))))

(defn- reject-view! [state request source-hash contract-hash view message elapsed-ms]
  (hot/publish!
   (:reload-session state) request source-hash contract-hash view
   (fn [_candidate] (Some message)) elapsed-ms))

(defn reload-view!
  [app request source-hash contract-hash view elapsed-ms]
  (let [state (require-reload-state app)
        session (:reload-session state)]
    (if-not (= (deref (:app-lifecycle-state app)) Running)
      (reject-view!
       state request source-hash contract-hash view
       "application is not running" elapsed-ms)
      (match (hot/preflight session request source-hash contract-hash)
        (Some _status)
        (hot/publish!
         session request source-hash contract-hash view
         (fn [_candidate] None) elapsed-ms)
        None
        (let [application (:app-runtime app)
              saved (runtime/checkpoint application)
              old-scope (deref (:reload-view-scope state))
              old-view (deref (:reload-view-node state))
              candidate-scope
              (sig/scope (str "app-view-" request) (:app-scope app))
              candidate-node (atom None)
              failure
              (try
                (let [context
                      (ui/context-with-state-registry
                       application candidate-scope
                       (:reload-state-scope state)
                       (:reload-state-scopes state))
                      node
                      (view context (:reload-model-source state)
                            (:app-send-action app))]
                  (reset!
                   candidate-node
                   (Some
                    (runtime/reconcile-subtree!
                     application saved (:app-root-node app) old-view node)))
                  (runtime/flush! application)
                  None)
                (catch (Invalid_argument message)
                  (do
                    (runtime/restore! application saved)
                    (sig/dispose-scope! candidate-scope)
                    (Some message))))]
          (match failure
            (Some message)
            (reject-view!
             state request source-hash contract-hash view message elapsed-ms)
            None
            (let [node
                  (match (deref candidate-node)
                    (Some current) current
                    None
                    (raise
                     (Invalid_argument "candidate view did not return a node")))]
              (sig/dispose-scope! old-scope)
              (sig/mount! candidate-scope)
              (reset! (:reload-view-scope state) candidate-scope)
              (reset! (:reload-view-node state) node)
              (hot/publish!
               session request source-hash contract-hash view
               (fn [_candidate] None) elapsed-ms))))))))
