(ns components.web-main
  (:require [ocaml.package/melange-webapi]
            [lui.app :as driver]
            [lui.backend.web :as web]
            [components.app :as components]))

(defn- append! [parent child]
  (Webapi.Dom.Element.appendChild (Webapi.Dom.Element.asNode child) parent))

(defn- select-section! [renderer content buttons sections selected-index]
  (let [section (nth sections selected-index)]
    (Webapi.Dom.Element.setTextContent content "")
    (web/mount! renderer (:root-section-node section) content)
    (loop [index 0]
      (when (< index (count buttons))
        (let [button (nth buttons index)
              selected (= index selected-index)]
          (Webapi.Dom.Element.setAttribute
           "aria-current" (if selected "page" "false") button)
          (Webapi.Dom.Element.setAttribute
           "data-selected" (if selected "true" "false") button)
          (recur (inc index)))))
    true))

(defn- mount-gallery-shell! [renderer root host]
  (let [document (:web-document renderer)
        shell (Webapi.Dom.Document.createElement "div" document)
        sidebar (Webapi.Dom.Document.createElement "nav" document)
        content (Webapi.Dom.Document.createElement "div" document)
        sections (web/root-sections renderer root)
        buttons
        (loop [index 0
               result []]
          (if (= index (count sections))
            result
            (let [section (nth sections index)
                  button (Webapi.Dom.Document.createElement "button" document)]
              (Webapi.Dom.Element.setAttribute "type" "button" button)
              (Webapi.Dom.Element.setClassName button "lui-gallery-nav-item")
              (Webapi.Dom.Element.setTextContent
               button (:root-section-title section))
              (append! sidebar button)
              (recur (inc index) (conj result button)))))]
    (Webapi.Dom.Element.setClassName shell "lui-gallery-shell")
    (Webapi.Dom.Element.setClassName sidebar "lui-gallery-sidebar")
    (Webapi.Dom.Element.setAttribute "aria-label" "Components" sidebar)
    (Webapi.Dom.Element.setClassName content "lui-gallery-content")
    (append! shell sidebar)
    (append! shell content)
    (append! host shell)
    (loop [index 0]
      (when (< index (count buttons))
        (let [button (nth buttons index)]
          (Webapi.Dom.Element.addEventListener
           "click"
           (fn [_event]
             (select-section! renderer content buttons sections index)
             (Stdlib.ignore true))
           button)
          (recur (inc index)))))
    (when (> (count sections) 0)
      (select-section! renderer content buttons sections 0))
    true))

(defn main [host]
  (let [renderer (web/create host)
        application (components/create (web/backend renderer))]
    (web/register-image!
     renderer
     1
     "/examples/components/flutter/macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_128.png"
     128.0
     128.0)
    (web/present-media-surface-frame!
     renderer
     1
     "/examples/components/flutter/macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_128.png"
     128.0
     128.0)
    (web/set-event-handler!
     renderer
     (fn [event]
       (driver/dispatch-event! application event)
       (driver/flush! application)))
    (driver/start! application)
    (driver/flush! application)
    (mount-gallery-shell! renderer (driver/root-node application) host)
    true))
