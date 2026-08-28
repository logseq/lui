(ns components.web-main
  (:require [ocaml.package/melange-webapi]
            [ocaml.Js.Dict :as js-dict]
            [ocaml.Obj :as obj]
            [ocaml.Webapi.Dom.NodeList :as node-list]
            [lui.app :as driver]
            [lui.backend.web :as web]
            [lui.protocol :as proto :refer [StringValue FloatValue]]
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

(defn- set-hidden! [element hidden]
  (if hidden
    (Webapi.Dom.Element.setAttribute "hidden" "" element)
    (Webapi.Dom.Element.removeAttribute "hidden" element)))

(defn- attribute-float [element name fallback]
  (match (Webapi.Dom.Element.getAttribute name element)
    (Some value) (Stdlib.float_of_string value)
    None fallback))

(defn- set-float-attribute! [element name value]
  (Webapi.Dom.Element.setAttribute name (str value) element))

(defn- refresh-map-markers! [map]
  (let [center-latitude (attribute-float map "data-center-latitude" 0.0)
        center-longitude (attribute-float map "data-center-longitude" 0.0)
        latitude-delta (attribute-float map "data-latitude-delta" 1.0)
        longitude-delta (attribute-float map "data-longitude-delta" 1.0)
        markers
        (Webapi.Dom.Element.querySelectorAll ".lui-simulator-map-marker" map)]
    (loop [index 0]
      (when (< index (node-list/length markers))
        (if-some [node (node-list/item index markers)]
          (if-some [marker (Webapi.Dom.Element.ofNode node)]
            (let [latitude (attribute-float marker "data-latitude" 0.0)
                  longitude (attribute-float marker "data-longitude" 0.0)
                  x
                  (+ 50.0
                     (* (/ (- longitude center-longitude)
                           longitude-delta)
                        100.0))
                  y
                  (- 50.0
                     (* (/ (- latitude center-latitude)
                           latitude-delta)
                        100.0))
                  style
                  (Webapi.Dom.HtmlElement.style
                   (Webapi.Dom.Element.unsafeAsHtmlElement marker))]
              (Webapi.Dom.CssStyleDeclaration.setProperty
               "left" (str x "%") "" style)
              (Webapi.Dom.CssStyleDeclaration.setProperty
               "top" (str y "%") "" style))
            (Stdlib.ignore true))
          (Stdlib.ignore true))
        (recur (inc index))))
    true))

(defn- emit-map-region! [map emit]
  (emit
   "region-change"
   {"latitude"
    (FloatValue (attribute-float map "data-center-latitude" 0.0))
    "longitude"
    (FloatValue (attribute-float map "data-center-longitude" 0.0))
    "latitude-delta"
    (FloatValue (attribute-float map "data-latitude-delta" 1.0))
    "longitude-delta"
    (FloatValue (attribute-float map "data-longitude-delta" 1.0))}))

(defn- map-control [document label text on-press]
  (let [button (Webapi.Dom.Document.createElement "button" document)]
    (Webapi.Dom.Element.setAttribute "type" "button" button)
    (Webapi.Dom.Element.setAttribute "aria-label" label button)
    (Webapi.Dom.Element.setTextContent button text)
    (Webapi.Dom.Element.addEventListener
     "click"
     (fn [_event]
       (on-press)
       (Stdlib.ignore true))
     button)
    button))

(defn- simulator-map-adapter []
  (record web/web-extension-adapter
    (web-extension-create
     (fn [_node document emit]
       (let [map (Webapi.Dom.Document.createElement "section" document)
             texture (Webapi.Dom.Document.createElement "div" document)
             controls (Webapi.Dom.Document.createElement "div" document)
             drag (atom [0.0 0.0 0.0 0.0])
             dragging (atom false)
             update-zoom!
             (fn [factor]
               (set-float-attribute!
                map "data-latitude-delta"
                (* (attribute-float map "data-latitude-delta" 1.0) factor))
               (set-float-attribute!
                map "data-longitude-delta"
                (* (attribute-float map "data-longitude-delta" 1.0) factor))
               (refresh-map-markers! map)
               (emit-map-region! map emit))
             recenter!
             (fn []
               (doseq [tuple
                        [(tuple "data-center-latitude" "data-home-latitude")
                         (tuple "data-center-longitude" "data-home-longitude")
                         (tuple "data-latitude-delta" "data-home-latitude-delta")
                         (tuple "data-longitude-delta" "data-home-longitude-delta")]]
                 (match (Webapi.Dom.Element.getAttribute (Stdlib.snd tuple) map)
                   (Some value)
                   (Webapi.Dom.Element.setAttribute
                    (Stdlib.fst tuple) value map)
                   None (Stdlib.ignore true)))
               (refresh-map-markers! map)
               (emit-map-region! map emit))]
         (Webapi.Dom.Element.setClassName map "lui-simulator-map")
         (Webapi.Dom.Element.setAttribute "role" "region" map)
         (Webapi.Dom.Element.setAttribute "aria-grabbed" "false" map)
         (Webapi.Dom.Element.setClassName texture "lui-simulator-map-texture")
         (Webapi.Dom.Element.setAttribute "aria-hidden" "true" texture)
         (Webapi.Dom.Element.setClassName controls "lui-simulator-map-controls")
         (append! texture controls)
         (append! controls (map-control document "Zoom in" "+" (fn [] (update-zoom! 0.5))))
         (append! controls (map-control document "Zoom out" "−" (fn [] (update-zoom! 2.0))))
         (append! controls (map-control document "Recenter map" "◎" recenter!))
         (append! map texture)
         (Webapi.Dom.Element.addEventListener
          "pointerdown"
          (fn [event]
            (let [target
                  (Webapi.Dom.EventTarget.unsafeAsElement
                   (Webapi.Dom.Event.target event))]
              (when (not (= (Webapi.Dom.Element.tagName target) "BUTTON"))
                (reset!
                 drag
                 [(Stdlib.float_of_int
                   (Webapi.Dom.MouseEvent.clientX
                    (web/pointer-mouse-event event)))
                  (Stdlib.float_of_int
                   (Webapi.Dom.MouseEvent.clientY
                    (web/pointer-mouse-event event)))
                  (attribute-float map "data-center-latitude" 0.0)
                  (attribute-float map "data-center-longitude" 0.0)])
                (reset! dragging true)
                (Webapi.Dom.Element.setAttribute "aria-grabbed" "true" map)))
            (Stdlib.ignore true))
          map)
         (Webapi.Dom.Element.addEventListener
          "pointermove"
          (fn [event]
            (when (deref dragging)
              (let [values (deref drag)
                    start-x (nth values 0)
                    start-y (nth values 1)
                    start-latitude (nth values 2)
                    start-longitude (nth values 3)
                    bounds (Webapi.Dom.Element.getBoundingClientRect map)
                    width (max 1.0 (Webapi.Dom.DomRect.width bounds))
                    height (max 1.0 (Webapi.Dom.DomRect.height bounds))
                    x
                    (Stdlib.float_of_int
                     (Webapi.Dom.MouseEvent.clientX
                      (web/pointer-mouse-event event)))
                    y
                    (Stdlib.float_of_int
                     (Webapi.Dom.MouseEvent.clientY
                      (web/pointer-mouse-event event)))
                    longitude-delta
                    (attribute-float map "data-longitude-delta" 1.0)
                    latitude-delta
                    (attribute-float map "data-latitude-delta" 1.0)]
                (set-float-attribute!
                 map "data-center-longitude"
                 (- start-longitude
                    (* (/ (- x start-x) width)
                       longitude-delta)))
                (set-float-attribute!
                 map "data-center-latitude"
                 (+ start-latitude
                    (* (/ (- y start-y) height)
                       latitude-delta)))
                (refresh-map-markers! map)))
            (Stdlib.ignore true))
          map)
         (doseq [event-name ["pointerup" "pointercancel"]]
           (Webapi.Dom.Element.addEventListener
            event-name
            (fn [_event]
              (when (deref dragging)
                (do
                  (reset! dragging false)
                  (Webapi.Dom.Element.setAttribute "aria-grabbed" "false" map)
                  (emit-map-region! map emit)))
              (Stdlib.ignore true))
            map))
         map)))
    (web-extension-set-property
     (fn [map property value]
       (match (tuple property value)
         (tuple "label" (StringValue label))
         (Webapi.Dom.Element.setAttribute "aria-label" label map)
         (tuple "latitude" (FloatValue latitude))
         (do
           (set-float-attribute! map "data-center-latitude" latitude)
           (set-float-attribute! map "data-home-latitude" latitude))
         (tuple "longitude" (FloatValue longitude))
         (do
           (set-float-attribute! map "data-center-longitude" longitude)
           (set-float-attribute! map "data-home-longitude" longitude))
         (tuple "latitude-delta" (FloatValue delta))
         (do
           (set-float-attribute! map "data-latitude-delta" delta)
           (set-float-attribute! map "data-home-latitude-delta" delta))
         (tuple "longitude-delta" (FloatValue delta))
         (do
           (set-float-attribute! map "data-longitude-delta" delta)
           (set-float-attribute! map "data-home-longitude-delta" delta))
         _ (raise (Invalid_argument "invalid simulator-map property")))
       (Webapi.requestAnimationFrame
        (fn [_time] (Stdlib.ignore (refresh-map-markers! map))))
       (Stdlib.ignore true)))
    (web-extension-remove-property
     (fn [map property]
       (match property
         "label" (Webapi.Dom.Element.removeAttribute "aria-label" map)
         "latitude" (Webapi.Dom.Element.removeAttribute "data-center-latitude" map)
         "longitude" (Webapi.Dom.Element.removeAttribute "data-center-longitude" map)
         "latitude-delta" (Webapi.Dom.Element.removeAttribute "data-latitude-delta" map)
         "longitude-delta" (Webapi.Dom.Element.removeAttribute "data-longitude-delta" map)
         _ (Stdlib.ignore true))))
    (web-extension-cleanup (fn [_map] (Stdlib.ignore true)))))

(defn- simulator-map-marker-adapter []
  (record web/web-extension-adapter
    (web-extension-create
     (fn [_node document _emit]
       (let [marker (Webapi.Dom.Document.createElement "button" document)]
         (Webapi.Dom.Element.setAttribute "type" "button" marker)
         (Webapi.Dom.Element.setClassName marker "lui-simulator-map-marker")
         marker)))
    (web-extension-set-property
     (fn [marker property value]
       (match (tuple property value)
         (tuple "title" (StringValue title))
         (do
           (Webapi.Dom.Element.setTextContent marker title)
           (Webapi.Dom.Element.setAttribute "aria-label" title marker))
         (tuple "latitude" (FloatValue latitude))
         (set-float-attribute! marker "data-latitude" latitude)
         (tuple "longitude" (FloatValue longitude))
         (set-float-attribute! marker "data-longitude" longitude)
         _ (raise (Invalid_argument "invalid simulator-map-marker property")))
       (Webapi.requestAnimationFrame
        (fn [_time]
          (if-some [parent (Webapi.Dom.Element.parentElement marker)]
            (Stdlib.ignore (refresh-map-markers! parent))
            (Stdlib.ignore true))))
       (Stdlib.ignore true)))
    (web-extension-remove-property
     (fn [marker property]
       (match property
         "title"
         (do
           (Webapi.Dom.Element.setTextContent marker "")
           (Webapi.Dom.Element.removeAttribute "aria-label" marker))
         "latitude" (Webapi.Dom.Element.removeAttribute "data-latitude" marker)
         "longitude" (Webapi.Dom.Element.removeAttribute "data-longitude" marker)
         _ (Stdlib.ignore true))))
    (web-extension-cleanup (fn [_marker] (Stdlib.ignore true)))))

(defn- simulator-camera-adapter [request-camera stop-camera]
  (record web/web-extension-adapter
    (web-extension-create
     (fn [_node document emit]
       (let [camera (Webapi.Dom.Document.createElement "section" document)
             frame (Webapi.Dom.Document.createElement "div" document)
             video (Webapi.Dom.Document.createElement "video" document)
             mock (Webapi.Dom.Document.createElement "div" document)
             status (Webapi.Dom.Document.createElement "span" document)
             alert (Webapi.Dom.Document.createElement "p" document)
             action (Webapi.Dom.Document.createElement "button" document)
             show-mock!
             (fn []
               (stop-camera video)
               (Webapi.Dom.Element.setAttribute "data-camera-state" "mock" camera)
               (set-hidden! video true)
               (set-hidden! mock false)
               (set-hidden! alert true)
               (Webapi.Dom.Element.setTextContent
                status "Using deterministic simulator camera")
               (Webapi.Dom.Element.setTextContent action "Use browser camera")
               (emit "state-change" {"state" (StringValue "mock")}))
             show-live!
             (fn []
               (Webapi.Dom.Element.setAttribute "data-camera-state" "live" camera)
               (set-hidden! video false)
               (set-hidden! mock true)
               (set-hidden! alert true)
               (Webapi.Dom.Element.setTextContent status "Using browser camera")
               (Webapi.Dom.Element.setTextContent action "Use simulator camera")
               (emit "state-change" {"state" (StringValue "live")}))
             show-denied!
             (fn []
               (Webapi.Dom.Element.setAttribute "data-camera-state" "denied" camera)
               (set-hidden! video true)
               (set-hidden! mock false)
               (set-hidden! alert false)
               (Webapi.Dom.Element.setTextContent
                alert
                "Camera permission denied. The simulator camera remains available.")
               (Webapi.Dom.Element.setTextContent
                status "Using deterministic simulator camera")
               (Webapi.Dom.Element.setTextContent action "Use browser camera")
               (emit "state-change" {"state" (StringValue "denied")}))]
         (Webapi.Dom.Element.setClassName camera "lui-simulator-camera")
         (Webapi.Dom.Element.setAttribute "role" "group" camera)
         (Webapi.Dom.Element.setAttribute "data-camera-state" "mock" camera)
         (Webapi.Dom.Element.setClassName frame "lui-simulator-camera-frame")
         (Webapi.Dom.Element.setAttribute "autoplay" "" video)
         (Webapi.Dom.Element.setAttribute "muted" "" video)
         (Webapi.Dom.Element.setAttribute "playsinline" "" video)
         (js-dict/set (obj/magic video) "muted" true)
         (Webapi.Dom.Element.setAttribute "aria-label" "Live camera preview" video)
         (set-hidden! video true)
         (Webapi.Dom.Element.setClassName mock "lui-simulator-camera-mock")
         (Webapi.Dom.Element.setAttribute "aria-hidden" "true" mock)
         (Webapi.Dom.Element.setTextContent mock "SIMULATOR CAMERA")
         (Webapi.Dom.Element.setAttribute "role" "status" status)
         (Webapi.Dom.Element.setTextContent
          status "Using deterministic simulator camera")
         (Webapi.Dom.Element.setAttribute "role" "alert" alert)
         (set-hidden! alert true)
         (Webapi.Dom.Element.setAttribute "type" "button" action)
         (Webapi.Dom.Element.setTextContent action "Use browser camera")
         (Webapi.Dom.Element.addEventListener
          "click"
          (fn [_event]
            (match (Webapi.Dom.Element.getAttribute "data-camera-state" camera)
              (Some "live") (show-mock!)
              _
              (do
                (Webapi.Dom.Element.setAttribute
                 "data-camera-state" "requesting" camera)
                (Webapi.Dom.Element.setTextContent
                 status "Requesting browser camera")
                (request-camera
                 document video
                 (match (Webapi.Dom.Element.getAttribute "data-facing" camera)
                   (Some facing) facing
                   None "environment")
                 show-live! show-denied!)))
            (Stdlib.ignore true))
          action)
         (append! frame video)
         (append! frame mock)
         (append! camera frame)
         (append! camera status)
         (append! camera alert)
         (append! camera action)
         camera)))
    (web-extension-set-property
     (fn [camera property value]
       (match (tuple property value)
         (tuple "label" (StringValue label))
         (Webapi.Dom.Element.setAttribute "aria-label" label camera)
         (tuple "facing" (StringValue facing))
         (Webapi.Dom.Element.setAttribute "data-facing" facing camera)
         _ (raise (Invalid_argument "invalid simulator-camera property")))
       (Stdlib.ignore true)))
    (web-extension-remove-property
     (fn [camera property]
       (match property
         "label" (Webapi.Dom.Element.removeAttribute "aria-label" camera)
         "facing" (Webapi.Dom.Element.removeAttribute "data-facing" camera)
         _ (Stdlib.ignore true))))
    (web-extension-cleanup
     (fn [camera]
       (if-some [video (Webapi.Dom.Element.querySelector "video" camera)]
         (stop-camera video)
         (Stdlib.ignore true))))))

(defn- select-value [event]
  (let [target
        (Webapi.Dom.EventTarget.unsafeAsElement
         (Webapi.Dom.Event.target event))]
    (match (js-dict/get (obj/magic target) "value")
      (Some value) value
      None "")))

(defn- simulator-option [document value label]
  (let [option (Webapi.Dom.Document.createElement "option" document)]
    (Webapi.Dom.Element.setAttribute "value" value option)
    (Webapi.Dom.Element.setTextContent option label)
    option))

(defn- mount-simulator-toolbar! [renderer refresh-layout!]
  (let [document (:web-document renderer)
        html-document (Webapi.Dom.Document.unsafeAsHtmlDocument document)
        toolbar (Webapi.Dom.Document.createElement "div" document)
        label (Webapi.Dom.Document.createElement "label" document)
        label-text (Webapi.Dom.Document.createElement "span" document)
        select (Webapi.Dom.Document.createElement "select" document)
        device-label (Webapi.Dom.Document.createElement "label" document)
        device-label-text (Webapi.Dom.Document.createElement "span" document)
        device-select (Webapi.Dom.Document.createElement "select" document)
        rotate (Webapi.Dom.Document.createElement "button" document)]
    (Webapi.Dom.Element.setClassName toolbar "lui-simulator-toolbar")
    (Webapi.Dom.Element.setClassName label "lui-simulator-platform-field")
    (Webapi.Dom.Element.setTextContent label-text "Platform")
    (Webapi.Dom.Element.setAttribute "aria-label" "Simulator platform" select)
    (append! select (simulator-option document "ios" "iOS"))
    (append! select (simulator-option document "android" "Android"))
    (Webapi.Dom.Element.setClassName
     device-label "lui-simulator-platform-field")
    (Webapi.Dom.Element.setTextContent device-label-text "Device")
    (Webapi.Dom.Element.setAttribute
     "aria-label" "Simulator form factor" device-select)
    (append! device-select (simulator-option document "phone" "Phone"))
    (append! device-select (simulator-option document "tablet" "Tablet"))
    (Webapi.Dom.Element.setAttribute "type" "button" rotate)
    (Webapi.Dom.Element.setAttribute "aria-label" "Rotate simulator" rotate)
    (Webapi.Dom.Element.setTextContent rotate "Rotate")
    (Webapi.Dom.Element.addEventListener
     "change"
     (fn [event]
       (match (select-value event)
         "ios" (web/set-simulator-platform! renderer proto/IOS)
         "android" (web/set-simulator-platform! renderer proto/AndroidOS)
         _ true)
       (refresh-layout!)
       (Stdlib.ignore true))
     select)
    (Webapi.Dom.Element.addEventListener
     "change"
     (fn [event]
       (match (select-value event)
         "phone"
         (web/set-simulator-form-factor! renderer web/SimulatorPhone)
         "tablet"
         (web/set-simulator-form-factor! renderer web/SimulatorTablet)
         _ true)
       (refresh-layout!)
       (Stdlib.ignore true))
     device-select)
    (Webapi.Dom.Element.addEventListener
     "click"
     (fn [_event]
       (web/rotate-simulator! renderer)
       (refresh-layout!)
       (Stdlib.ignore true))
     rotate)
    (append! label label-text)
    (append! label select)
    (append! device-label device-label-text)
    (append! device-label device-select)
    (append! toolbar label)
    (append! toolbar device-label)
    (append! toolbar rotate)
    (if-some [body (Webapi.Dom.HtmlDocument.body html-document)]
      (append! body toolbar)
      (raise (Invalid_argument "document body is unavailable")))
    true))

(defn- set-accessibility-hidden! [element hidden]
  (Webapi.Dom.Element.setAttribute
   "aria-hidden" (if hidden "true" "false") element)
  (if hidden
    (Webapi.Dom.Element.setAttribute "inert" "" element)
    (Webapi.Dom.Element.removeAttribute "inert" element)))

(defn- focus! [element]
  (Webapi.Dom.HtmlElement.focus
   (Webapi.Dom.Element.unsafeAsHtmlElement element)))

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
        navigation-bar (Webapi.Dom.Document.createElement "header" document)
        back (Webapi.Dom.Document.createElement "button" document)
        navigation-title (Webapi.Dom.Document.createElement "span" document)
        sidebar (Webapi.Dom.Document.createElement "nav" document)
        content (Webapi.Dom.Document.createElement "div" document)
        sections (web/root-sections renderer root)
        selected-index (atom 0)
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
              (recur (inc index) (conj result button)))))
        refresh-layout!
        (fn []
          (let [tablet
                (= (Webapi.Dom.Element.getAttribute
                    "data-lui-form-factor" host)
                   (Some "tablet"))
                detail
                (= (Webapi.Dom.Element.getAttribute
                    "data-lui-navigation" shell)
                   (Some "detail"))
                show-detail (or tablet detail)]
            (set-accessibility-hidden! sidebar (and (not tablet) detail))
            (set-accessibility-hidden! content (not show-detail))
            (set-hidden! back (or tablet (not detail)))
            (Webapi.Dom.Element.setTextContent
             navigation-title
             (if detail
               (:root-section-title (nth sections (deref selected-index)))
               "Components"))
            true))]
    (Webapi.Dom.Element.setClassName shell "lui-gallery-shell")
    (Webapi.Dom.Element.setAttribute "data-lui-navigation" "list" shell)
    (Webapi.Dom.Element.setClassName
     navigation-bar "lui-gallery-navigation-bar")
    (Webapi.Dom.Element.setClassName back "lui-gallery-navigation-back")
    (Webapi.Dom.Element.setAttribute "type" "button" back)
    (Webapi.Dom.Element.setAttribute "aria-label" "Back to Components" back)
    (Webapi.Dom.Element.setTextContent back "Components")
    (Webapi.Dom.Element.setClassName
     navigation-title "lui-gallery-navigation-title")
    (Webapi.Dom.Element.setTextContent navigation-title "Components")
    (Webapi.Dom.Element.setClassName sidebar "lui-gallery-sidebar")
    (Webapi.Dom.Element.setAttribute "aria-label" "Components" sidebar)
    (Webapi.Dom.Element.setClassName content "lui-gallery-content")
    (append! navigation-bar back)
    (append! navigation-bar navigation-title)
    (append! shell navigation-bar)
    (append! shell sidebar)
    (append! shell content)
    (append! host shell)
    (Webapi.Dom.Element.addEventListener
     "click"
     (fn [_event]
       (Webapi.Dom.Element.setAttribute "data-lui-navigation" "list" shell)
       (refresh-layout!)
       (focus! (nth buttons (deref selected-index)))
       (Stdlib.ignore true))
     back)
    (loop [index 0]
      (when (< index (count buttons))
        (let [button (nth buttons index)]
          (Webapi.Dom.Element.addEventListener
           "click"
           (fn [_event]
             (select-section! renderer content buttons sections index)
             (reset! selected-index index)
             (Webapi.Dom.Element.setAttribute
              "data-lui-navigation" "detail" shell)
             (refresh-layout!)
             (when (= (Webapi.Dom.Element.getAttribute
                       "data-lui-form-factor" host)
                      (Some "phone"))
               (focus! back))
             (Stdlib.ignore true))
           button)
          (recur (inc index)))))
    (when (> (count sections) 0)
      (select-section! renderer content buttons sections 0))
    (refresh-layout!)
    refresh-layout!))

(defn main [host request-camera stop-camera]
  (let [registry (extensions/registry)
        renderer
        (web/create-simulator-with-extensions
         host proto/IOS {} registry
         {"simulator-map" (simulator-map-adapter)
          "simulator-map-marker" (simulator-map-marker-adapter)
          "simulator-camera" (simulator-camera-adapter request-camera stop-camera)
          "native-card" (native-card-adapter)
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
    (let [refresh-gallery-layout!
          (mount-gallery-shell! renderer (driver/root-node application) host)]
      (mount-simulator-toolbar! renderer refresh-gallery-layout!))
    true))
