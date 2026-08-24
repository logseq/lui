(ns lui.backend.web
  (:require [ocaml.package/melange-webapi]
            [ocaml.Webapi.Dom.HtmlCollection :as html-collection]
            [lui.protocol :as proto
             :refer [Row Column Box Text Heading Paragraph Button
                     TextInput TextArea Scroll Spacer
                     CreateNode DropNode SetProp InsertChild RemoveChild
                     MoveChild TextValue Enabled Gap PaddingValue
                     BackgroundValue PlaceholderValue ReadOnly MinLines MaxLines
                     AccessibilityLabel StyleClass HeadingLevel
                     StringValue BoolValue IntValue]]
            [lui.backend.retained :as retained]))

(defn create [host]
  (record web-renderer
    (web-store (retained/create-store))
    (web-document (Webapi.Dom.Element.ownerDocument host))
    (web-event-handler (atom (fn [_event] true)))))

(defn set-event-handler! [renderer handler]
  (reset! (:web-event-handler renderer) handler)
  true)

(defn- base-class-name [kind]
  (match kind
    Row "lui-row"
    Column "lui-column"
    Box "lui-box"
    Text "lui-text"
    Heading "lui-heading"
    Paragraph "lui-paragraph"
    Button "lui-button"
    TextInput "lui-text-input"
    TextArea "lui-text-area"
    Scroll "lui-scroll"
    Spacer "lui-spacer"))

(defn- platform-node [renderer kind]
  (let [tag
        (match kind
          Heading "div"
          Paragraph "p"
          Text "span"
          Button "button"
          TextInput "input"
          TextArea "textarea"
          _ "div")
        node
        (Webapi.Dom.Document.createElement tag (:web-document renderer))]
    (Webapi.Dom.Element.setClassName node (base-class-name kind))
    (when (= kind Heading)
      (Webapi.Dom.Element.setAttribute "role" "heading" node))
    (when (= kind TextArea)
      (Webapi.Dom.Element.setAttribute
       "style" "field-sizing: content; resize: vertical; overflow-y: auto" node))
    node))

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

(defn- text-control-node [dom-node]
  (if-some [control
            (Webapi.Dom.HtmlInputElement.ofNode
             (Webapi.Dom.Element.asNode dom-node))]
    control
    (raise (Invalid_argument "DOM node is not a text control"))))

(defn- attach-text-event! [renderer node dom-node]
  (Webapi.Dom.Element.addEventListener
   "input"
   (fn [_event]
     (Stdlib.ignore
      ((deref (:web-event-handler renderer))
       (proto/TextChanged
        node (Webapi.Dom.HtmlInputElement.value
              (text-control-node dom-node)))))
     (Stdlib.ignore true))
   dom-node))

(defn- attach-events! [renderer node kind dom-node]
  (match kind
    Button
    (Webapi.Dom.Element.addEventListener
     "click"
     (fn [_event]
       ((deref (:web-event-handler renderer)) (proto/Press node))
       (Stdlib.ignore true))
     dom-node)
    TextInput (attach-text-event! renderer node dom-node)
    TextArea (attach-text-event! renderer node dom-node)
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
    (if (or (= kind TextInput) (= kind TextArea))
      (let [control (text-control-node dom-node)]
        (when (not (= text (Webapi.Dom.HtmlInputElement.value control)))
          (Webapi.Dom.HtmlInputElement.setValue control text)))
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
     (text-control-node dom-node) placeholder)

    (tuple ReadOnly (BoolValue read-only))
    (Webapi.Dom.HtmlInputElement.setReadOnly
     (text-control-node dom-node) read-only)

    (tuple AccessibilityLabel (StringValue label))
    (Webapi.Dom.Element.setAttribute "aria-label" label dom-node)

    (tuple StyleClass (StringValue class-name))
    (Webapi.Dom.Element.setClassName
     dom-node (str (base-class-name kind) " " class-name))

    (tuple HeadingLevel (IntValue level))
    (Webapi.Dom.Element.setAttribute "aria-level" (str level) dom-node)

    (tuple MinLines (IntValue lines))
    (do
      (Webapi.Dom.Element.setAttribute "rows" (str lines) dom-node)
      (set-style!
       dom-node "min-block-size"
       (str "calc(" lines
            "lh + var(--lui-text-area-block-chrome, 1rem + 2px))")))

    (tuple MaxLines (IntValue lines))
    (set-style!
     dom-node "max-block-size"
     (str "calc(" lines
          "lh + var(--lui-text-area-block-chrome, 1rem + 2px))"))

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

(defn- focused-descendant [renderer dom-node]
  (let [document
        (Webapi.Dom.Document.unsafeAsHtmlDocument (:web-document renderer))]
    (if-some [focused (Webapi.Dom.HtmlDocument.activeElement document)]
      (if (Webapi.Dom.Element.contains
           (Webapi.Dom.Element.asNode focused) dom-node)
        (Some focused)
        None)
      None)))

(defn- focus-element! [element]
  (Webapi.Dom.HtmlElement.focus
   (Webapi.Dom.Element.unsafeAsHtmlElement element)))

(defn- document-body-focused? [renderer]
  (let [document
        (Webapi.Dom.Document.unsafeAsHtmlDocument (:web-document renderer))]
    (if-some [focused (Webapi.Dom.HtmlDocument.activeElement document)]
      (if-some [body (Webapi.Dom.HtmlDocument.body document)]
        (Webapi.Dom.Element.isSameNode
         (Webapi.Dom.Element.asNode body) focused)
        false)
      false)))

(defn- restore-focus! [renderer focused]
  (match focused
    (Some element)
    (do
      (focus-element! element)
      (Stdlib.ignore
       (Js.Global.setTimeout
        0
        :f
        (fn []
          (when (document-body-focused? renderer)
            (focus-element! element))
          (Stdlib.ignore true)))))
    None (Stdlib.ignore true)))

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
          child-node (dom-node-before renderer previous-nodes child)
          focused (focused-descendant renderer child-node)]
      (Stdlib.ignore
       (Webapi.Dom.Element.removeChild
        (Webapi.Dom.Element.asNode child-node) parent-node))
      (insert-dom-child! parent-node child-node index)
      (restore-focus! renderer focused))))

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
