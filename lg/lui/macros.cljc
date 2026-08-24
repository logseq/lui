(ns lui.macros
  (:require [lui.elements]))

(macro-helper-defn state-call? [form]
  (and (seq? form)
       (= 2 (count form))
       (= "state" (name (first form)))))

(macro-helper-defn rewrite-states [form component-name]
  (cond
    (state-call? form)
    (let [slot-name (gensym)
          slot-label (str component-name ":" slot-name)]
      [`(signal.core/state-at
         (:ui-scheduler ~'ui-context)
         (:ui-scope ~'ui-context)
         ~slot-name
       ~(second form))
       [[slot-name slot-label]]
       ])

    (or (seq? form) (vector? form))
    (loop [remaining form
           rewritten []
           slots []]
      (if (empty? remaining)
        [(if (vector? form)
           (vec rewritten)
           (apply list rewritten))
         slots]
        (let [result
              (rewrite-states (first remaining) component-name)]
          (recur
           (next remaining)
           (conj rewritten (first result))
           (into slots (second result))))))

    :else [form []]))

(macro-helper-defn lower-ui-body [form]
  (if (vector? form)
    `(lui.elements/element ~'ui-context nil ~form)
    form))

(defmacro defui [component-name params & body]
  (let [result (rewrite-states `(do ~@body) component-name)
        rewritten (first result)
        transformed
        (if (and (seq? rewritten) (= 'do (first rewritten)))
          (loop [remaining (next rewritten)
                 leading []]
            (if (empty? (next remaining))
              `(do ~@leading ~(lower-ui-body (first remaining)))
              (recur (next remaining) (conj leading (first remaining)))))
          (lower-ui-body rewritten))
        slots (second result)]
    `(do
       ~@(map
          (fn [[slot-name slot-label]]
            `(def ~slot-name (signal.core/state-slot ~slot-label)))
          slots)
       (defn ~component-name [~'ui-context ~@params]
         ~transformed))))

(defmacro state [_initial]
  (throw (IllegalArgumentException.
          "state must appear inside defui")))

(defmacro effect [& body]
  `(signal.core/enqueue-effect!
    (:ui-scheduler ~'ui-context)
    (fn []
      ~@body
      true)))

(defmacro on-mount [& body]
  `(signal.core/on-mount!
    (:ui-scope ~'ui-context)
    (fn []
      ~@body
      true)))

(defmacro on-unmount [& body]
  `(signal.core/on-unmount!
    (:ui-scope ~'ui-context)
    (fn []
      ~@body
      true)))

(defmacro platform []
  `(lui.ui/platform ~'ui-context))

(defmacro host []
  `(lui.ui/host ~'ui-context))

(defmacro platform? [operating-system]
  `(= (lui.ui/platform ~'ui-context) ~operating-system))

(defmacro host? [host-kind]
  `(= (lui.ui/host ~'ui-context) ~host-kind))

(defmacro reactive [transform & sources]
  `(signal.core/own-signal!
    (:ui-scope ~'ui-context)
    (signal.core/map ~transform ~@sources)))

(defmacro event [[value source] & body]
  `(fn [~'_event]
     (let [~value (signal.core/sample ~source)]
       ~@body)))

(defmacro keyed-for [source key-fn compare mount on-patch]
  `(signal.core/keyed
    (:ui-scope ~'ui-context)
    ~source ~key-fn ~compare ~mount ~on-patch))
