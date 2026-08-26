(defn app-subscriptions [^:int _model]
  [(record subscriptions/subscription-spec
           (subscription-key "clock")
           (subscription-fingerprint "v1")
           (start-subscription
            (fn [dispatch]
              (swap! subscription-starts inc)
              (dispatch 0)
              (let [disposed (atom false)]
                (record signal.core/subscription
                        (disposed disposed)
                        (cancel
                         (fn []
                           (if (deref disposed)
                             true
                             (do
                               (reset! disposed true)
                               (swap! subscription-stops inc)
                               true)))))))))])
