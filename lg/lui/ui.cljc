(ns lui.ui
  (:require [signal.core :as sig]
            [lui.protocol :as proto]
            [lui.runtime :as runtime]))

(defn context [application scope]
  (record ui-context
    (ui-application application)
    (ui-scheduler (:runtime-scheduler application))
    (ui-scope scope)
    (ui-profile (:backend-profile (:runtime-backend application)))))

(defn child-context [parent name]
  (context
   (:ui-application parent)
   (sig/scope name (:ui-scope parent))))

(defn profile [context]
  (:ui-profile context))

(defn platform [context]
  (:profile-os (:ui-profile context)))

(defn host [context]
  (:profile-host (:ui-profile context)))

(defn row! [context]
  (runtime/create-node! (:ui-application context) proto/Row))

(defn column! [context]
  (runtime/create-node! (:ui-application context) proto/Column))

(defn scroll! [context]
  (runtime/create-node! (:ui-application context) proto/Scroll))

(defn spacer! [context]
  (runtime/create-node! (:ui-application context) proto/Spacer))

(defn text! [context text]
  (let [node (runtime/create-node! (:ui-application context) proto/Text)]
    (runtime/set-prop!
     (:ui-application context) node proto/TextValue
     (proto/StringValue text))
    node))

(defn text-value! [context source]
  (let [node (runtime/create-node! (:ui-application context) proto/Text)]
    (runtime/bind-prop!
     (:ui-scope context) (:ui-application context)
     node proto/TextValue source)
    node))

(defn text-signal! [context source]
  (text-value!
   context
   (sig/own-signal!
    (:ui-scope context)
    (sig/map (fn [text] (proto/StringValue text)) source))))

(defn text-input-value! [context source callback]
  (let [node (runtime/create-node! (:ui-application context) proto/TextInput)]
    (runtime/bind-prop!
     (:ui-scope context) (:ui-application context)
     node proto/TextValue source)
    (runtime/on-event!
     (:ui-scope context) (:ui-application context) node callback)
    node))

(defn text-input! [context source callback]
  (text-input-value!
   context
   (sig/own-signal!
    (:ui-scope context)
    (sig/map (fn [text] (proto/StringValue text)) source))
   callback))

(defn button! [context label callback]
  (let [node (runtime/create-node! (:ui-application context) proto/Button)]
    (runtime/set-prop!
     (:ui-application context) node proto/TextValue
     (proto/StringValue label))
    (runtime/on-event!
     (:ui-scope context) (:ui-application context) node callback)
    node))

(defn append! [context parent child]
  (runtime/insert-child!
   (:ui-application context) parent child
   (runtime/child-count (:ui-application context) parent)))

(defn gap! [context node gap]
  (runtime/set-prop!
   (:ui-application context) node proto/Gap (proto/IntValue gap)))

(defn padding! [context node padding]
  (runtime/set-prop!
   (:ui-application context) node proto/PaddingValue
   (proto/IntValue padding)))

(defn background! [context node color]
  (runtime/set-prop!
   (:ui-application context) node proto/BackgroundValue
   (proto/StringValue color)))
