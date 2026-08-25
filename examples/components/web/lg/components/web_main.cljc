(ns components.web-main
  (:require [ocaml.package/melange-webapi]
            [lui.app :as driver]
            [lui.backend.web :as web]
            [lui.protocol :refer [StringValue]]
            [components.app :as components]
            [components.extensions :as extensions]))

(defn- native-card-adapter []
  (record web/web-extension-adapter
    (web-extension-create
     (fn [_node document _emit]
       (let [button (Webapi.Dom.Document.createElement "button" document)
             pressed (atom false)]
         (Webapi.Dom.Element.setAttribute "type" "button" button)
         (Webapi.Dom.Element.setClassName button "lui-native-card")
         (Webapi.Dom.Element.addEventListener
          "click"
          (fn [_event]
            (swap! pressed not)
            (Webapi.Dom.Element.setAttribute
             "data-active" (if (deref pressed) "true" "false") button)
            (Stdlib.ignore true))
          button)
         button)))
    (web-extension-set-property
     (fn [node property value]
       (if (= property "title")
         (match value
           (StringValue text)
           (do
             (Webapi.Dom.Element.setTextContent node text)
             (Stdlib.ignore true))
           _ (raise (Invalid_argument "native-card title must be a string")))
         (Stdlib.ignore true))))
    (web-extension-remove-property
     (fn [node property]
       (if (= property "title")
         (do
           (Webapi.Dom.Element.setTextContent node "")
           (Stdlib.ignore true))
         (Stdlib.ignore true))))
    (web-extension-cleanup (fn [_node] (Stdlib.ignore true)))))

(defn- gallery-accent-adapter []
  (record web/web-extension-adapter
    (web-extension-create
     (fn [_node document _emit]
       (let [element (Webapi.Dom.Document.createElement "div" document)]
         (Webapi.Dom.Element.setClassName element "lui-gallery-accent")
         element)))
    (web-extension-set-property
     (fn [_node _property _value] (Stdlib.ignore true)))
    (web-extension-remove-property
     (fn [_node _property] (Stdlib.ignore true)))
    (web-extension-cleanup (fn [_node] (Stdlib.ignore true)))))

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
  (let [registry (extensions/registry)
        renderer
        (web/create-with-extensions
         host {} registry
         {"native-card" (native-card-adapter)
          "gallery-accent" (gallery-accent-adapter)})
        application
        (components/create-with-extensions (web/backend renderer) registry)]
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
