(ns todos.web-main
  (:require [ocaml.package/melange-webapi]
            [ocaml.Webapi.Dom :refer [document]]
            [lui.app :as app]
            [lui.backend.web :as web]
            [todos.app :as todos]))

(defn main []
  (let [renderer (web/create)
        application (todos/create (web/backend renderer))]
    (web/set-event-handler!
     renderer
     (fn [event]
       (app/dispatch-event! application event)
       (app/flush! application)))
    (app/start! application)
    (app/flush! application)
    (if-some [host (Webapi.Dom.Document.querySelector "#app" document)]
      (do
        (web/mount! renderer (app/root-node application) host)
        true)
      (raise (Invalid_argument "missing #app host element")))))

(defn show-error! [message]
  (if-some [host (Webapi.Dom.Document.querySelector "#app" document)]
    (do
      (Webapi.Dom.Element.setTextContent host message)
      (Webapi.Dom.Element.setAttribute "data-error" "true" host)
      true)
    false))

(Webapi.Dom.Document.addEventListener
 "DOMContentLoaded"
 (fn [_event]
   (do
     (try
       (main)
       (catch error
         (if-some [message (ex-message error)]
           (show-error! message)
           (show-error! "Unknown Web startup error"))))
     (Stdlib.ignore true)))
 document)
