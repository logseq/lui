(ns components.web-main
  (:require [ocaml.package/melange-webapi]
            [lui.app :as driver]
            [lui.backend.web :as web]
            [components.app :as components]))

(defn main [host]
  (let [renderer (web/create host)
        application (components/create (web/backend renderer))]
    (web/set-event-handler!
     renderer
     (fn [event]
       (driver/dispatch-event! application event)
       (driver/flush! application)))
    (driver/start! application)
    (driver/flush! application)
    (web/mount! renderer (driver/root-node application) host)
    true))
