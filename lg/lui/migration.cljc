(ns lui.migration
  (:refer-clojure :exclude [apply]))

(defn capture [version fingerprint model encode]
  (if (or (< version 0) (= fingerprint ""))
    (SnapshotCaptureRejected "snapshot contract is invalid")
    (try
      (SnapshotCaptured
       (record model-snapshot
         (snapshot-version version)
         (snapshot-fingerprint fingerprint)
         (snapshot-payload (encode model))))
      (catch (Invalid_argument message)
        (SnapshotCaptureRejected message)))))

(defn apply [plan snapshot]
  (cond
    (not (= (:snapshot-version snapshot)
            (:migration-source-version plan)))
    (MigrationRestartRequired "snapshot version changed")
    (not (= (:snapshot-fingerprint snapshot)
            (:migration-source-fingerprint plan)))
    (MigrationRestartRequired "snapshot fingerprint changed")
    (= (:migration-target-fingerprint plan) "")
    (MigrationRestartRequired "target fingerprint is missing")
    :else
    (try
      (let [model ((:migrate-snapshot plan) (:snapshot-payload snapshot))]
        (match ((:validate-model plan) model)
          (Some message) (MigrationRejected message)
          None (MigrationApplied model)))
      (catch (Invalid_argument message)
        (MigrationRejected message)))))

(defn soft-restart! [migration start activate discard retire-old]
  (match migration
    (MigrationRejected message) (SoftRestartRejected message)
    (MigrationRestartRequired message) (SoftRestartRequired message)
    (MigrationApplied model)
    (let [candidate
          (try
            (Some (start model))
            (catch (Invalid_argument _message) None))]
      (match candidate
        None (SoftRestartRejected "candidate start failed")
        (Some target)
        (let [activated
              (try
                (activate target)
                (catch (Invalid_argument _message) false))]
          (if-not activated
            (do
              (discard target)
              (SoftRestartRejected "candidate activation failed"))
            (if (retire-old nil)
              (SoftRestartApplied target)
              (SoftRestartRequired "old application retirement failed"))))))))

(defn drain-compatible [messages generation fingerprint]
  (reduce
   (fn [result message]
     (if (and (= (:message-generation message) generation)
              (= (:message-fingerprint message) fingerprint))
       (record message-drain
         (compatible-messages
          (conj (:compatible-messages result) (:message-value message)))
         (discarded-message-count (:discarded-message-count result)))
       (record message-drain
         (compatible-messages (:compatible-messages result))
         (discarded-message-count
          (inc (:discarded-message-count result))))))
   (record message-drain
     (compatible-messages [])
     (discarded-message-count 0))
   messages))
