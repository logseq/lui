(ns components.web-main
  (:require [ocaml.package/melange-webapi]
            [signal.core :as sig]
            [lui.protocol :refer [TextChanged ToggleChanged]]
            [lui.backend.web :as web]
            [lui.runtime :as runtime]
            [lui.ui :as ui]
            [components.gallery :as gallery]))

(defn main [host]
  (let [scheduler (sig/scheduler)
        renderer (web/create host)
        application (runtime/create scheduler (web/backend renderer))
        scope (sig/scope "components-gallery")
        context (ui/context application scope)
        disabled (sig/state scheduler false)
        field-value (sig/state scheduler "")
        field-invalid (sig/state scheduler false)
        toggle-checked (sig/state scheduler false)
        toggle-indeterminate (sig/state scheduler true)
        toggle-invalid (sig/state scheduler false)
        card-copy
        (sig/map
         (fn [is-disabled]
           (if is-disabled
             "Signal patched this paragraph; the Card node stayed mounted."
             "Signals update retained content without rebuilding the Card."))
         (sig/value disabled))
        root
        (gallery/component-gallery
         context
         (sig/value disabled)
         (fn [_event]
           (sig/set!
            disabled (if (= (sig/get disabled) true) false true)))
         card-copy
         (sig/value field-value)
         (sig/value field-invalid)
         (fn [event]
           (match event
             (TextChanged _node text) (sig/set! field-value text)
             _ true))
         (fn [_event]
           (sig/set!
            field-invalid
            (if (= (sig/get field-invalid) true) false true)))
         (sig/value toggle-checked)
         (sig/value toggle-indeterminate)
         (sig/value toggle-invalid)
         (fn [event]
           (match event
             (ToggleChanged _node checked)
             (do
               (sig/set! toggle-indeterminate false)
               (sig/set! toggle-checked checked))
             _ true))
         (fn [_event]
           (sig/set!
            toggle-indeterminate
            (if (= (sig/get toggle-indeterminate) true) false true)))
         (fn [_event]
           (sig/set!
            toggle-invalid
            (if (= (sig/get toggle-invalid) true) false true))))]
    (web/set-event-handler!
     renderer
     (fn [event]
       (runtime/dispatch! application event)
       (runtime/flush! application)))
    (sig/mount! scope)
    (runtime/flush! application)
    (web/mount! renderer root host)
    true))
