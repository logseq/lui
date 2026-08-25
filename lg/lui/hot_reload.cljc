(ns lui.hot-reload)

(defn create [source-hash contract-hash root]
  (record hot-reload-session
    (hot-reload-committed-root
     (atom
      (record committed-root
        (committed-root-value root)
        (committed-root-source-hash source-hash)
        (committed-root-generation 0))))
    (hot-reload-contract-hash contract-hash)
    (hot-reload-requested-generation (atom 0))
    (hot-reload-completed-generation (atom 0))
    (hot-reload-events (atom []))))

(defn request! [session]
  (swap! (:hot-reload-requested-generation session) inc))

(defn preflight [session request candidate-source-hash contract-hash]
  (let [requested (deref (:hot-reload-requested-generation session))
        completed (deref (:hot-reload-completed-generation session))]
    (cond
      (or (<= request 0) (> request requested))
      (Some (ReloadRejected request "candidate generation was not requested"))
      (or (< request requested) (<= request completed))
      (Some (ReloadStale request))
      (not (= contract-hash (:hot-reload-contract-hash session)))
      (Some (ReloadRestartRequired request "root contract changed"))
      (= candidate-source-hash (source-hash session))
      (Some (ReloadUnchanged request))
      :else None)))

(defn- record-event! [session request source-hash status elapsed-ms]
  (swap!
   (:hot-reload-events session)
   conj
   (record reload-event
     (reload-event-generation request)
     (reload-event-source-hash source-hash)
     (reload-event-status status)
     (reload-event-elapsed-ms elapsed-ms)))
  status)

(defn- record-completed-event!
  [session request source-hash status elapsed-ms]
  (reset! (:hot-reload-completed-generation session) request)
  (record-event! session request source-hash status elapsed-ms))

(defn- reject! [session request source-hash message elapsed-ms]
  (record-completed-event!
   session request source-hash (ReloadRejected request message) elapsed-ms))

(defn- validate-and-publish!
  [session request source-hash root validate elapsed-ms]
  (try
    (match (validate root)
      (Some message)
      (reject! session request source-hash message elapsed-ms)
      None
      (do
        (reset!
         (:hot-reload-committed-root session)
         (record committed-root
           (committed-root-value root)
           (committed-root-source-hash source-hash)
           (committed-root-generation request)))
        (record-completed-event!
         session request source-hash (ReloadApplied request) elapsed-ms)))
    (catch (Invalid_argument message)
      (reject! session request source-hash message elapsed-ms))))

(defn publish!
  [session request candidate-source-hash contract-hash root validate elapsed-ms]
  (match (preflight session request candidate-source-hash contract-hash)
    (Some status)
    (match status
      (ReloadRejected _generation message)
      (record-event!
       session request candidate-source-hash
       (ReloadRejected request message)
       elapsed-ms)
      (ReloadStale _generation)
      (record-event!
       session request candidate-source-hash (ReloadStale request) elapsed-ms)
      (ReloadRestartRequired _generation message)
      (record-completed-event!
       session request candidate-source-hash
       (ReloadRestartRequired request message) elapsed-ms)
      (ReloadUnchanged _generation)
      (record-completed-event!
       session request candidate-source-hash (ReloadUnchanged request) elapsed-ms)
      (ReloadApplied _generation)
      (raise (Invalid_argument "applied status cannot be preflighted")))
    None
    (validate-and-publish!
     session request candidate-source-hash root validate elapsed-ms)))

(defn- committed-root [session]
  (deref (:hot-reload-committed-root session)))

(defn current-root [session]
  (:committed-root-value (committed-root session)))

(defn generation [session]
  (:committed-root-generation (committed-root session)))

(defn source-hash [session]
  (:committed-root-source-hash (committed-root session)))

(defn events [session]
  (deref (:hot-reload-events session)))

(defn latest-event [session]
  (let [current (events session)]
    (if (empty? current)
      None
      (Some (nth current (dec (count current)))))))
