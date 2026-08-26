(ns lui.phase2-hot-reload-test
  (:require [clojure.test :refer [deftest is]]
            [signal.core :as sig]
            [lui.resources :as resources]
            [lui.subscriptions :as subscriptions]))

(defmacro assert-equal [expected actual message]
  `(is (= ~expected ~actual) ~message))

(deftest subscription-reload-preserves-compatible-and-restarts-changed-keys
  (let [starts (atom 0)
        stops (atom 0)
        messages (atom [])
        test-subscription
        (fn [key fingerprint message]
          (record subscriptions/subscription-spec
            (subscription-key key)
            (subscription-fingerprint fingerprint)
            (start-subscription
             (fn [dispatch]
               (swap! starts inc)
               (dispatch message)
               (let [disposed (atom false)]
                 (record signal.core/subscription
                   (disposed disposed)
                   (cancel
                    (fn []
                      (if (deref disposed)
                        true
                        (do
                          (reset! disposed true)
                          (swap! stops inc)
                          true))))))))))
        coordinator
        (subscriptions/create
         (fn [message]
           (swap! messages conj message)
           true))]
    (assert-equal
     (subscriptions/SubscriptionsApplied 1)
     (subscriptions/reconcile!
      coordinator 1 [(test-subscription "clock" "v1" 1)])
     "the first typed subscription generation starts")
    (assert-equal [1] (deref messages) "the subscription dispatch type is retained")
    (assert-equal
     (subscriptions/SubscriptionsUnchanged 2)
     (subscriptions/reconcile!
      coordinator 2 [(test-subscription "clock" "v1" 1)])
     "an unchanged key and fingerprint keeps its live resource")
    (assert-equal 1 (deref starts) "the compatible subscription is not restarted")
    (assert-equal 0 (deref stops) "the compatible subscription is not cancelled")
    (assert-equal
     (subscriptions/SubscriptionsApplied 3)
     (subscriptions/reconcile!
      coordinator 3 [(test-subscription "clock" "v2" 2)])
     "a changed fingerprint replaces the subscription")
    (assert-equal 2 (deref starts) "the replacement starts before publication")
    (assert-equal 1 (deref stops) "the previous subscription is cancelled")
    (assert-equal [1 2] (deref messages) "the new typed dispatch is active")
    (let [failing
          (record subscriptions/subscription-spec
            (subscription-key "broken")
            (subscription-fingerprint "v1")
            (start-subscription
             (fn [_dispatch]
               (raise (Invalid_argument "start failed")))))]
      (assert-equal
       (subscriptions/SubscriptionsRejected 4 "start failed")
       (subscriptions/reconcile!
        coordinator 4
        [(test-subscription "candidate" "v1" 3) failing])
       "a failed subscription candidate rejects the whole generation")
      (assert-equal 1 (subscriptions/count coordinator)
                    "rejection keeps the previous active set")
      (assert-equal 3 (deref starts)
                    "the candidate that started before failure is tracked")
      (assert-equal 2 (deref stops)
                    "a partially started generation is fully cancelled")
      (assert-equal [1 2 3] (deref messages)
                    "candidate dispatch remains statically typed")
      (assert-equal
       (subscriptions/SubscriptionsStale 3)
       (subscriptions/reconcile!
        coordinator 3 [(test-subscription "clock" "stale" 4)])
       "an older subscription generation cannot replace the last-known-good set"))
    (subscriptions/dispose! coordinator)
    (assert-equal 3 (deref stops)
                  "disposing the coordinator cancels the last live resource")
    (assert-equal 0 (subscriptions/count coordinator)
                  "no subscription remains after disposal")))

(deftest resource-reload-invalidates-dependents-and-keeps-last-known-good
  (let [invalidated (atom [])
        retired (atom [])
        session
        (resources/create
         (fn [nodes]
           (swap! invalidated into nodes)
           true)
         (fn [resource]
           (swap! retired conj resource)
           true))]
    (resources/register-dependency! session "hero" 10)
    (resources/register-dependency! session "hero" 11)
    (assert-equal
     (resources/ResourceApplied 1)
     (resources/reload!
      session 1 "hero" "hash-a" "image-a" (fn [payload] payload))
     "the first decoded resource commits")
    (assert-equal [10 11] (deref invalidated)
                  "only registered dependents are invalidated")
    (assert-equal
     (resources/ResourceUnchanged 2)
     (resources/reload!
      session 2 "hero" "hash-a" "ignored" (fn [payload] payload))
     "an unchanged resource hash is a no-op")
    (assert-equal
     (resources/ResourceRejected 3 "decode failed")
     (resources/reload!
      session 3 "hero" "hash-b" "bad"
      (fn [_payload] (raise (Invalid_argument "decode failed"))))
     "decode failure rejects the candidate")
    (assert-equal (Some "image-a") (resources/current session "hero")
                  "decode failure keeps the last-known-good resource")
    (assert-equal [] (deref retired)
                  "the committed resource remains live after rejection")
    (assert-equal
     (resources/ResourceApplied 4)
     (resources/reload!
      session 4 "hero" "hash-c" "image-c" (fn [payload] payload))
     "a later valid resource commits")
    (assert-equal ["image-a"] (deref retired)
                  "the old generation retires after dependent invalidation")
    (assert-equal
     (resources/ResourceStale 3)
     (resources/reload!
      session 3 "hero" "hash-stale" "image-stale" (fn [payload] payload))
     "an older resource generation cannot overwrite the committed resource")
    (assert-equal (Some "image-c") (resources/current session "hero")
                  "stale resource work leaves the committed value unchanged")))

(deftest repeated-subscription-reloads-cancel-every-replaced-generation
  (let [starts (atom 0)
        stops (atom 0)
        coordinator (subscriptions/create (fn [_message] true))]
    (loop [generation 1]
      (when (<= generation 100)
        (let [spec
              (record subscriptions/subscription-spec
                (subscription-key "clock")
                (subscription-fingerprint (str generation))
                (start-subscription
                 (fn [_dispatch]
                   (swap! starts inc)
                   (let [disposed (atom false)]
                     (record signal.core/subscription
                       (disposed disposed)
                       (cancel
                        (fn []
                          (if (deref disposed)
                            true
                            (do
                              (reset! disposed true)
                              (swap! stops inc)
                              true)))))))))]
          (assert-equal
           (subscriptions/SubscriptionsApplied generation)
           (subscriptions/reconcile! coordinator generation [spec])
           "every newer subscription generation commits"))
        (recur (inc generation))))
    (assert-equal 100 (deref starts)
                  "every subscription generation starts exactly once")
    (assert-equal 99 (deref stops)
                  "every replaced subscription is cancelled exactly once")
    (assert-equal 1 (subscriptions/count coordinator)
                  "only the newest subscription remains active")
    (subscriptions/dispose! coordinator)
    (assert-equal 100 (deref stops)
                  "disposing the coordinator releases the final subscription")))

(deftest resource-invalidation-failure-rolls-back-and-retires-candidate
  (let [reject-invalidation (atom false)
        retired (atom [])
        session
        (resources/create
         (fn [_nodes]
           (if (deref reject-invalidation)
             (raise (Invalid_argument "invalidate failed"))
             true))
         (fn [resource]
           (swap! retired conj resource)
           true))]
    (assert-equal
     (resources/ResourceApplied 1)
     (resources/reload!
      session 1 "hero" "hash-a" "image-a" (fn [payload] payload))
     "the last-known-good resource is seeded")
    (reset! reject-invalidation true)
    (assert-equal
     (resources/ResourceRejected 2 "invalidate failed")
     (resources/reload!
      session 2 "hero" "hash-b" "image-b" (fn [payload] payload))
     "dependent invalidation failure rejects publication")
    (assert-equal (Some "image-a") (resources/current session "hero")
                  "failed publication restores the last-known-good resource")
    (assert-equal ["image-b"] (deref retired)
                  "failed publication retires only the candidate")))

(deftest repeated-resource-reloads-retire-every-replaced-generation
  (let [retired (atom [])
        session
        (resources/create
         (fn [_nodes] true)
         (fn [resource]
           (swap! retired conj resource)
           true))]
    (loop [generation 1]
      (when (<= generation 100)
        (let [value (str "image-" generation)]
          (assert-equal
           (resources/ResourceApplied generation)
           (resources/reload!
            session generation "hero" value value (fn [payload] payload))
           "every newer resource generation commits"))
        (recur (inc generation))))
    (assert-equal (Some "image-100") (resources/current session "hero")
                  "only the newest resource remains current")
    (assert-equal 99 (count (deref retired))
                  "every replaced resource is retired exactly once")))
