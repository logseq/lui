(ns todos.web-main
  (:require [ocaml.package/melange-webapi]
            [lui.app :as app]
            [lui.backend.web :as web]
            [todos.app :as todos]))

(defn main [host]
  (let [renderer (web/create host)
        application (todos/create (web/backend renderer))]
    (web/set-event-handler!
     renderer
     (fn [event]
       (app/dispatch-event! application event)
       (app/flush! application)))
    (app/start! application)
    (app/flush! application)
    (web/mount! renderer (app/root-node application) host)
    true))
