(ns lui.subscriptions
  (:refer-clojure :exclude [count])
  (:require [signal.core :as sig]))

(defn create [dispatch]
  (record subscription-coordinator
          (subscription-dispatch dispatch)
          (active-subscriptions (atom (hash-map)))
          (subscription-completed-generation (atom 0))))

(defn- reject! [coordinator generation message]
  (reset! (:subscription-completed-generation coordinator) generation)
  (SubscriptionsRejected generation message))

(defn- validate-unique-keys! [specs]
  (loop [index 0
         keys (hash-map)]
    (if (= index (clojure.core/count specs))
      None
      (let [key (:subscription-key (nth specs index))]
        (if (contains? keys key)
          (Some (str "duplicate subscription key " key))
          (recur (inc index) (assoc keys key true)))))))

(defn- same-active? [active spec]
  (= (:active-subscription-fingerprint active)
     (:subscription-fingerprint spec)))

(defn- unchanged? [active specs]
  (and
   (= (clojure.core/count active) (clojure.core/count specs))
   (every?
    (fn [spec]
      (if-some [current (clojure.core/get active (:subscription-key spec))]
        (same-active? current spec)
        false))
    specs)))

(defn- dispose-started! [started]
  (doseq [subscription (deref started)]
    (sig/dispose-subscription! subscription))
  true)

(defn- build-desired [active specs dispatch]
  (let [started (atom [])]
    (try
      (SubscriptionsPrepared
       (reduce
        (fn [result spec]
          (let [key (:subscription-key spec)]
            (if-some [current (clojure.core/get active key)]
              (if (same-active? current spec)
                (assoc result key current)
                (let [subscription ((:start-subscription spec) dispatch)]
                  (swap! started conj subscription)
                  (assoc
                   result key
                   (record active-subscription
                           (active-subscription-fingerprint
                            (:subscription-fingerprint spec))
                           (active-subscription-value subscription)))))
              (let [subscription ((:start-subscription spec) dispatch)]
                (swap! started conj subscription)
                (assoc
                 result key
                 (record active-subscription
                         (active-subscription-fingerprint
                          (:subscription-fingerprint spec))
                         (active-subscription-value subscription)))))))
        (hash-map)
        specs))
      (catch (Invalid_argument message)
             (do
               (dispose-started! started)
               (SubscriptionsPrepareRejected message))))))

(defn reconcile! [coordinator generation specs]
  (let [completed (deref (:subscription-completed-generation coordinator))]
    (if (<= generation completed)
      (SubscriptionsStale generation)
      (match (validate-unique-keys! specs)
        (Some message) (reject! coordinator generation message)
        None
        (let [active (deref (:active-subscriptions coordinator))]
          (if (unchanged? active specs)
            (do
              (reset! (:subscription-completed-generation coordinator) generation)
              (SubscriptionsUnchanged generation))
            (match
             (build-desired
              active specs (:subscription-dispatch coordinator))
              (SubscriptionsPrepareRejected message)
              (reject! coordinator generation message)
              (SubscriptionsPrepared desired)
              (do
                (doseq [[key current] active]
                  (if-some [replacement (clojure.core/get desired key)]
                    (when-not
                     (= (:active-subscription-fingerprint current)
                        (:active-subscription-fingerprint replacement))
                      (sig/dispose-subscription!
                       (:active-subscription-value current)))
                    (sig/dispose-subscription!
                     (:active-subscription-value current))))
                (reset! (:active-subscriptions coordinator) desired)
                (reset!
                 (:subscription-completed-generation coordinator) generation)
                (SubscriptionsApplied generation)))))))))

(defn dispose! [coordinator]
  (doseq [[_key active] (deref (:active-subscriptions coordinator))]
    (sig/dispose-subscription! (:active-subscription-value active)))
  (reset! (:active-subscriptions coordinator) (hash-map))
  true)

(defn count [coordinator]
  (clojure.core/count (deref (:active-subscriptions coordinator))))
