(ns lui.backend.web
  (:require [ocaml.package/melange-webapi]
            [ocaml.Webapi.Dom.HtmlCollection :as html-collection]
            [lui.protocol :as proto
             :refer [Row Column Text Button TextInput Scroll Spacer
                     CreateNode DropNode SetProp InsertChild RemoveChild
                     MoveChild TextValue Enabled Gap PaddingValue
                     BackgroundValue PlaceholderValue ReadOnly
                     AccessibilityLabel StringValue BoolValue IntValue]]
            [lui.backend.retained :as retained]))

(defn create [host]
  (record web-renderer
    (web-store (retained/create-store))
    (web-document (Webapi.Dom.Element.ownerDocument host))
    (web-event-handler (atom (fn [_event] true)))))

(defn set-event-handler! [renderer handler]
  (reset! (:web-event-handler renderer) handler)
  true)

(defn- platform-node [renderer kind]
  (let [tag
        (match kind
          Text "span"
          Button "button"
          TextInput "input"
          _ "div")
        node
        (Webapi.Dom.Document.createElement tag (:web-document renderer))
        class-name
        (match kind
          Row "lui-row"
          Column "lui-column"
          Text "lui-text"
          Button "lui-button"
          TextInput "lui-text-input"
          Scroll "lui-scroll"
          Spacer "lui-spacer")]
    (Webapi.Dom.Element.setClassName node class-name)
    node))

(defn- input-node [dom-node]
  (if-some [input
            (Webapi.Dom.HtmlInputElement.ofNode
             (Webapi.Dom.Element.asNode dom-node))]
    input
    (raise (Invalid_argument "DOM node is not an input"))))

(defn- dom-node [renderer node]
  (if-some [current (retained/node (:web-store renderer) node)]
    (:platform-node current)
    (raise (Invalid_argument "unknown DOM node"))))

(defn- dom-node-before [renderer previous-nodes node]
  (if-some [current (retained/node (:web-store renderer) node)]
    (:platform-node current)
    (if-some [previous (clojure.core/get previous-nodes node)]
      (:platform-node previous)
      (raise (Invalid_argument "unknown DOM node")))))

(defn- attach-events! [renderer node kind dom-node]
  (match kind
    Button
    (Webapi.Dom.Element.addEventListener
     "click"
     (fn [_event]
       ((deref (:web-event-handler renderer)) (proto/Press node))
       (Stdlib.ignore true))
     dom-node)
    TextInput
    (Webapi.Dom.Element.addEventListener
     "input"
     (fn [_event]
       ((deref (:web-event-handler renderer))
        (proto/TextChanged
         node (Webapi.Dom.HtmlInputElement.value (input-node dom-node))))
       (Stdlib.ignore true))
     dom-node)
    _ (Stdlib.ignore true)))

(defn- set-style! [dom-node property value]
  (let [element-style
        (Webapi.Dom.HtmlElement.style
         (Webapi.Dom.Element.unsafeAsHtmlElement dom-node))]
    (Webapi.Dom.CssStyleDeclaration.setProperty
     property value "" element-style)))

(defn- apply-property! [kind dom-node property value]
  (match (tuple property value)
    (tuple TextValue (StringValue text))
    (if (= kind TextInput)
      (let [input (input-node dom-node)]
        (when (not (= text (Webapi.Dom.HtmlInputElement.value input)))
          (Webapi.Dom.HtmlInputElement.setValue input text)))
      (when (not (= text (Webapi.Dom.Element.textContent dom-node)))
        (Webapi.Dom.Element.setTextContent dom-node text)))

    (tuple Enabled (BoolValue enabled))
    (if enabled
      (Webapi.Dom.Element.removeAttribute "disabled" dom-node)
      (Webapi.Dom.Element.setAttribute "disabled" "disabled" dom-node))

    (tuple Gap (IntValue gap))
    (set-style! dom-node "gap" (str gap "px"))

    (tuple PaddingValue (IntValue padding))
    (set-style! dom-node "padding" (str padding "px"))

    (tuple BackgroundValue (StringValue background))
    (set-style! dom-node "background" background)

    (tuple PlaceholderValue (StringValue placeholder))
    (Webapi.Dom.HtmlInputElement.setPlaceholder
     (input-node dom-node) placeholder)

    (tuple ReadOnly (BoolValue read-only))
    (Webapi.Dom.HtmlInputElement.setReadOnly (input-node dom-node) read-only)

    (tuple AccessibilityLabel (StringValue label))
    (Webapi.Dom.Element.setAttribute "aria-label" label dom-node)

    _ (raise (Invalid_argument "invalid DOM property value"))))

(defn- insert-dom-child! [parent child index]
  (let [children (Webapi.Dom.Element.children parent)
        length (html-collection/length children)]
    (if (= index length)
      (Webapi.Dom.Element.appendChild
       (Webapi.Dom.Element.asNode child) parent)
      (if-some [reference (html-collection/item index children)]
        (Stdlib.ignore
         (Webapi.Dom.Element.insertBefore
          (Webapi.Dom.Element.asNode child)
          (Webapi.Dom.Element.asNode reference)
          parent))
        (raise (Invalid_argument "DOM child index is out of bounds"))))))

(defn- apply-dom-op! [renderer previous-nodes operation]
  (match operation
    (CreateNode node kind)
    (attach-events! renderer node kind (dom-node renderer node))

    (DropNode _node) (Stdlib.ignore true)

    (SetProp node property value)
    (if-some [current (retained/node (:web-store renderer) node)]
      (apply-property!
       (:semantic-kind current) (:platform-node current) property value)
      (raise (Invalid_argument "unknown DOM node")))

    (InsertChild parent child index)
    (insert-dom-child!
     (dom-node renderer parent) (dom-node renderer child) index)

    (RemoveChild parent child)
    (Stdlib.ignore
     (Webapi.Dom.Element.removeChild
      (Webapi.Dom.Element.asNode
       (dom-node-before renderer previous-nodes child))
      (dom-node-before renderer previous-nodes parent)))

    (MoveChild parent child index)
    (let [parent-node (dom-node-before renderer previous-nodes parent)
          child-node (dom-node-before renderer previous-nodes child)]
      (Stdlib.ignore
       (Webapi.Dom.Element.removeChild
        (Webapi.Dom.Element.asNode child-node) parent-node))
      (insert-dom-child! parent-node child-node index))))

(defn- apply-dom-batch! [renderer previous-nodes batch]
  (doseq [operation (:ops batch)]
    (apply-dom-op! renderer previous-nodes operation))
  (Stdlib.ignore true))

(defn backend [renderer]
  (record proto/backend
    (backend-profile (proto/profile proto/WebOS proto/WebHost))
    (apply-batch
     (fn [batch]
       (let [previous-nodes
             (retained/nodes (:web-store renderer))]
         (retained/apply-batch!
          (:web-store renderer)
          (fn [kind] (platform-node renderer kind))
          batch)
         (apply-dom-batch! renderer previous-nodes batch)
         true)))))

(defn mount! [renderer root host]
  (Webapi.Dom.Element.appendChild
   (Webapi.Dom.Element.asNode (dom-node renderer root)) host))

(defn- some-node [value]
  (Some value))

(defn node [renderer node]
  (if-some [current (retained/node (:web-store renderer) node)]
    (some-node (:platform-node current))
    None))

(defn property [renderer node property]
  (retained/property (:web-store renderer) node property))

(defn children [renderer node]
  (retained/children (:web-store renderer) node))

(defn node-count [renderer]
  (retained/node-count (:web-store renderer)))

(defn batches [renderer]
  (retained/batches (:web-store renderer)))
