(ns components.web-main
  (:require [ocaml.package/melange-webapi]
            [signal.core :as sig]
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
         card-copy)]
    (web/set-event-handler!
     renderer
     (fn [event]
       (runtime/dispatch! application event)
       (runtime/flush! application)))
    (sig/mount! scope)
    (runtime/flush! application)
    (web/mount! renderer root host)
    true))
