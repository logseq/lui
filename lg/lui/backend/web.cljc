(ns lui.backend.web
  (:require [ocaml.package/melange-webapi]
            [ocaml.Webapi.Dom.HtmlCollection :as html-collection]
            [lui.protocol :as proto
             :refer [Row Column Box Text Heading Paragraph Label Button
                     TextInput TextArea Checkbox SwitchControl Scroll Spacer
                     CreateNode DropNode SetProp InsertChild RemoveChild
                     MoveChild TextValue Enabled Gap PaddingValue
                     BackgroundValue PlaceholderValue ReadOnly MinLines MaxLines
                     AccessibilityLabel StyleClass HeadingLevel LabelledBy
                     DescribedBy ErrorMessageBy InputType Invalid
                     Checked Indeterminate
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
    Label "lui-label"
    Button "lui-button"
    TextInput "lui-text-input"
    TextArea "lui-text-area"
    Checkbox "lui-checkbox"
    SwitchControl "lui-switch-control"
    Scroll "lui-scroll"
    Spacer "lui-spacer"))

(defn- platform-node [renderer kind]
  (let [tag
        (match kind
          Heading "div"
          Paragraph "p"
          Label "label"
          Text "span"
          Button "button"
          TextInput "input"
          TextArea "textarea"
          Checkbox "input"
          SwitchControl "button"
          _ "div")
        node
        (Webapi.Dom.Document.createElement tag (:web-document renderer))]
    (Webapi.Dom.Element.setClassName node (base-class-name kind))
    (when (= kind Heading)
      (Webapi.Dom.Element.setAttribute "role" "heading" node))
    (when (= kind TextArea)
      (Webapi.Dom.Element.setAttribute
       "style" "field-sizing: content; resize: vertical; overflow-y: auto" node))
    (when (= kind Checkbox)
      (Webapi.Dom.Element.setAttribute "type" "checkbox" node))
    (when (= kind SwitchControl)
      (Webapi.Dom.Element.setAttribute "type" "button" node)
      (Webapi.Dom.Element.setAttribute "role" "switch" node))
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

(defn- node-dom-id [node]
  (str "lui-node-" node))

(defn- relationship-dom-node [renderer node]
  (dom-node renderer node))

(defn- update-describedby! [dom-node]
  (let [description
        (Webapi.Dom.Element.getAttribute "data-lui-described-by" dom-node)
        error
        (Webapi.Dom.Element.getAttribute "data-lui-error-message-by" dom-node)
        invalid
        (Webapi.Dom.Element.hasAttribute "data-invalid" dom-node)]
    (match (tuple description error)
      (tuple (Some description-id) (Some error-id))
      (Webapi.Dom.Element.setAttribute "aria-describedby"
       (if invalid
         (str description-id " " error-id)
         description-id)
       dom-node)
      (tuple (Some description-id) None)
      (Webapi.Dom.Element.setAttribute
       "aria-describedby" description-id dom-node)
      (tuple None (Some error-id))
      (if invalid
        (Webapi.Dom.Element.setAttribute
         "aria-describedby" error-id dom-node)
        (Webapi.Dom.Element.removeAttribute "aria-describedby" dom-node))
      (tuple None None)
      (Webapi.Dom.Element.removeAttribute "aria-describedby" dom-node))))

(defn- attribute-target? [element attribute target]
  (if-some [value (Webapi.Dom.Element.getAttribute attribute element)]
    (= value (node-dom-id target))
    false))

(defn- clear-dom-relationships! [previous-nodes target]
  (reduce-kv
   (fn [_result _node current]
     (let [element (:platform-node current)]
       (when (attribute-target? element "aria-labelledby" target)
         (Webapi.Dom.Element.removeAttribute "aria-labelledby" element))
       (when (attribute-target? element "data-lui-described-by" target)
         (Webapi.Dom.Element.removeAttribute "data-lui-described-by" element)
         (update-describedby! element))
       (when (attribute-target? element "data-lui-error-message-by" target)
         (Webapi.Dom.Element.removeAttribute
          "data-lui-error-message-by" element)
         (update-describedby! element))
       true))
   true
   previous-nodes))

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

(defn- attach-toggle-event! [renderer node kind dom-node]
  (Webapi.Dom.Element.addEventListener
   (if (= kind Checkbox) "change" "click")
   (fn [_event]
     (let [checked
           (if (= kind Checkbox)
             (Webapi.Dom.HtmlInputElement.checked
              (text-control-node dom-node))
             (not (Webapi.Dom.Element.hasAttribute
                   "data-checked" dom-node)))]
       (Stdlib.ignore
        ((deref (:web-event-handler renderer))
         (proto/ToggleChanged node checked)))
       (Stdlib.ignore true)))
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
    Checkbox (attach-toggle-event! renderer node kind dom-node)
    SwitchControl (attach-toggle-event! renderer node kind dom-node)
    _ (Stdlib.ignore true)))

(defn- set-style! [dom-node property value]
  (let [element-style
        (Webapi.Dom.HtmlElement.style
         (Webapi.Dom.Element.unsafeAsHtmlElement dom-node))]
    (Webapi.Dom.CssStyleDeclaration.setProperty
     property value "" element-style)))

(defn- set-state-attribute! [dom-node attribute enabled]
  (if enabled
    (Webapi.Dom.Element.setAttribute attribute "" dom-node)
    (Webapi.Dom.Element.removeAttribute attribute dom-node)))

(defn- apply-property! [renderer kind dom-node property value]
  (match (tuple property value)
    (tuple TextValue (StringValue text))
    (if (or (= kind TextInput) (= kind TextArea))
      (let [control (text-control-node dom-node)]
        (when (not (= text (Webapi.Dom.HtmlInputElement.value control)))
          (Webapi.Dom.HtmlInputElement.setValue control text)))
      (when (not (= text (Webapi.Dom.Element.textContent dom-node)))
        (Webapi.Dom.Element.setTextContent dom-node text)))

    (tuple Enabled (BoolValue enabled))
    (do
      (if enabled
        (Webapi.Dom.Element.removeAttribute "disabled" dom-node)
        (Webapi.Dom.Element.setAttribute "disabled" "disabled" dom-node))
      (when (or (= kind Checkbox) (= kind SwitchControl))
        (set-state-attribute! dom-node "data-disabled" (not enabled))))

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

    (tuple LabelledBy (IntValue label))
    (do
      (Webapi.Dom.Element.setAttribute
       "aria-labelledby" (node-dom-id label) dom-node)
      (if-some [control-id
                (Webapi.Dom.Element.getAttribute "id" dom-node)]
        (Webapi.Dom.Element.setAttribute
         "for" control-id (relationship-dom-node renderer label))
        (Stdlib.ignore true)))

    (tuple DescribedBy (IntValue description))
    (do
      (Webapi.Dom.Element.setAttribute
       "data-lui-described-by" (node-dom-id description) dom-node)
      (update-describedby! dom-node))

    (tuple ErrorMessageBy (IntValue error))
    (do
      (Webapi.Dom.Element.setAttribute
       "data-lui-error-message-by" (node-dom-id error) dom-node)
      (update-describedby! dom-node))

    (tuple InputType (StringValue input-type))
    (Webapi.Dom.Element.setAttribute "type" input-type dom-node)

    (tuple Invalid (BoolValue invalid))
    (do
      (if invalid
        (do
          (Webapi.Dom.Element.setAttribute "aria-invalid" "true" dom-node)
          (Webapi.Dom.Element.setAttribute "data-invalid" "" dom-node))
        (do
          (Webapi.Dom.Element.removeAttribute "aria-invalid" dom-node)
          (Webapi.Dom.Element.removeAttribute "data-invalid" dom-node)))
      (update-describedby! dom-node))

    (tuple Checked (BoolValue checked))
    (do
      (when (= kind Checkbox)
        (Webapi.Dom.HtmlInputElement.setChecked
         (text-control-node dom-node) checked))
      (set-state-attribute! dom-node "data-checked" checked)
      (Webapi.Dom.Element.setAttribute
       "aria-checked"
       (if (and
            (= kind Checkbox)
            (Webapi.Dom.HtmlInputElement.indeterminate
             (text-control-node dom-node)))
         "mixed"
         (if checked "true" "false"))
       dom-node))

    (tuple Indeterminate (BoolValue indeterminate))
    (let [control (text-control-node dom-node)]
      (Webapi.Dom.HtmlInputElement.setIndeterminate control indeterminate)
      (set-state-attribute!
       dom-node "data-indeterminate" indeterminate)
      (Webapi.Dom.Element.setAttribute
       "aria-checked"
       (if indeterminate
         "mixed"
         (if (Webapi.Dom.HtmlInputElement.checked control) "true" "false"))
       dom-node))

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
    (let [created (dom-node renderer node)]
      (Webapi.Dom.Element.setAttribute "id" (node-dom-id node) created)
      (attach-events! renderer node kind created))

    (DropNode node)
    (Stdlib.ignore (clear-dom-relationships! previous-nodes node))

    (SetProp node property value)
    (if-some [current (retained/node (:web-store renderer) node)]
      (apply-property!
       renderer (:semantic-kind current) (:platform-node current)
       property value)
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
