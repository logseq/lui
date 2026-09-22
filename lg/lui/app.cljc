(ns lui.app
  (:require [signal.core :as sig]
            [lui.hot-reload :as hot]
            [lui.protocol :as proto]
            [lui.runtime :as runtime]
            [lui.subscriptions :as subscriptions]
            [lui.ui :as ui]))

(defn reduce! [model-state reducer action]
  (sig/update!
   model-state
   (fn [current] (reducer current action))))

(defn- restore-state-scopes! [state-scopes saved]
  (doseq [[path scope] (deref state-scopes)]
    (when-not (contains? saved path)
      (sig/dispose-scope! scope)))
  (reset! state-scopes saved)
  true)

(defn- prune-state-scopes! [state-scopes active]
  (let [retained
        (reduce-kv
         (fn [result path scope]
           (if (contains? active path)
             (assoc result path scope)
             (do
               (sig/dispose-scope! scope)
               result)))
         (hash-map)
         (deref state-scopes))]
    (reset! state-scopes retained)
    true))

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
         (app-read-model (fn [_] (signal.core/get ~model-state)))
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
        active-state-paths (gensym "active_state_paths")
        context (gensym "context")
        model-state (gensym "model_state")
        lifecycle (gensym "lifecycle")
        reducer-root (gensym "reducer_root")
        send-action (gensym "send_action")
        root (gensym "root")
        view-node (gensym "view_node")
        session (gensym "session")
        app (gensym "app")
        cancel-reducer-watch (gensym "cancel_reducer_watch")
        cancel-redefinition-watch (gensym "cancel_redefinition_watch")]
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
           ~active-state-paths (atom (hash-map))
           ~context
           (lui.ui/context-with-state-registry
            ~application ~view-scope ~state-scope ~state-scopes
            ~active-state-paths)
           ~model-state (signal.core/state ~scheduler ~initial-model)
           ~lifecycle (atom lui.app/Running)
           ~reducer-root (atom ~reducer)
           ~send-action
           (fn [~'action]
             (if (= (deref ~lifecycle) lui.app/Running)
               (lui.app/reduce! ~model-state (deref ~reducer-root) ~'action)
               false))
           ~root (lui.runtime/create-node! ~application lui.protocol/Root)
           ~view-node
           (~view ~context (signal.core/value ~model-state) ~send-action)
           ~session (lui.hot-reload/create ~source-hash ~contract-hash ~view)
           ~app
           (record lui.app/reducer-app
             (app-scheduler ~scheduler)
             (app-runtime ~application)
             (app-scope ~scope)
             (app-read-model (fn [_] (signal.core/get ~model-state)))
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
                 (reload-session ~session)))))
           ~cancel-reducer-watch
           (watch-redef!
            ~reducer
            (fn []
              (do
                (reset! ~reducer-root ~reducer)
                true)))
           ~cancel-redefinition-watch
           (watch-redef!
            ~view
            (fn []
              (let [~'request (lui.app/request-reload! ~app)
                    ~'status
                    (lui.app/reload-view!
                     ~app ~'request (str "definition-" ~'request)
                     ~contract-hash ~view 0)]
                (match ~'status
                  (lui.hot-reload/ReloadApplied ~'_generation) true
                  (lui.hot-reload/ReloadUnchanged ~'_generation) true
                  _ false))))]
       (lui.runtime/insert-child! ~application ~root ~view-node 0)
       (signal.core/on-dispose! ~scope ~cancel-reducer-watch)
       (signal.core/on-dispose! ~scope ~cancel-redefinition-watch)
       ~app)))

(macro-helper-defn reloadable-subscriptions-expansion
  [app-form subscription-definition]
  (let [app (gensym "app")
        coordinator (gensym "subscription_coordinator")
        generation (gensym "subscription_generation")
        initial-status (gensym "initial_subscription_status")
        cancel-watch (gensym "cancel_subscription_watch")]
    `(let [~app ~app-form
           ~coordinator
           (lui.subscriptions/create (:app-send-action ~app))
           ~generation (atom 1)
           ~initial-status
           (lui.subscriptions/reconcile!
            ~coordinator 1 (~subscription-definition (lui.app/model ~app)))
           ~cancel-watch
           (watch-redef!
            ~subscription-definition
            (fn []
              (let [~'next-generation (swap! ~generation inc)
                    ~'status
                    (lui.subscriptions/reconcile!
                     ~coordinator ~'next-generation
                     (~subscription-definition (lui.app/model ~app)))]
                (match ~'status
                  (lui.subscriptions/SubscriptionsApplied ~'_generation) true
                  (lui.subscriptions/SubscriptionsUnchanged ~'_generation) true
                  _ false))))]
       (match ~initial-status
         (lui.subscriptions/SubscriptionsApplied ~'_generation) true
         (lui.subscriptions/SubscriptionsUnchanged ~'_generation) true
         (lui.subscriptions/SubscriptionsRejected ~'_generation ~'message)
         (raise (Invalid_argument ~'message))
         (lui.subscriptions/SubscriptionsStale ~'_generation)
         (raise (Invalid_argument "initial subscription generation is stale")))
       (signal.core/on-dispose!
        (:app-scope ~app)
        (fn [] (lui.subscriptions/dispose! ~coordinator)))
       (signal.core/on-dispose! (:app-scope ~app) ~cancel-watch)
       ~app)))

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

(defmacro create-reloadable-with-subscriptions
  [backend source-hash contract-hash initial-model reducer view subscriptions]
  (reloadable-subscriptions-expansion
   `(lui.app/create-reloadable
     ~backend ~source-hash ~contract-hash ~initial-model ~reducer ~view)
   subscriptions))

(defmacro create-reloadable-with-extensions-and-subscriptions
  [backend registry source-hash contract-hash initial-model reducer view
   subscriptions]
  (reloadable-subscriptions-expansion
   `(lui.app/create-reloadable-with-extensions
     ~backend ~registry ~source-hash ~contract-hash ~initial-model ~reducer ~view)
   subscriptions))

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
  `((.-app-read-model ~app) nil))

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
              saved-state-scopes (deref (:reload-state-scopes state))
              candidate-active-state-paths (atom (hash-map))
              candidate-scope
              (sig/scope (str "app-view-" request) (:app-scope app))
              candidate-node (atom None)
              failure
              (try
                (let [context
                      (ui/context-with-state-registry
                       application candidate-scope
                       (:reload-state-scope state)
                       (:reload-state-scopes state)
                       candidate-active-state-paths)
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
                    (restore-state-scopes!
                     (:reload-state-scopes state) saved-state-scopes)
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
              (runtime/retire-checkpoint-dynamic-segments! saved old-view)
              (sig/dispose-scope! old-scope)
              (prune-state-scopes!
               (:reload-state-scopes state)
               (deref candidate-active-state-paths))
              (sig/mount! candidate-scope)
              (reset! (:reload-view-scope state) candidate-scope)
              (reset! (:reload-view-node state) node)
              (hot/publish!
               session request source-hash contract-hash view
               (fn [_candidate] None) elapsed-ms))))))))
