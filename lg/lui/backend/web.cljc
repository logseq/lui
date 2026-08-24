(ns lui.backend.web
  (:require [ocaml.package/melange-webapi]
            [ocaml.Webapi.Dom.HtmlCollection :as html-collection]
            [lui.protocol :as proto
             :refer [Row Column Grid Box Text Heading Paragraph Label Button
                     TextInput TextArea Checkbox SwitchControl Scroll Spacer
                     ProgressControl Divider
                     CreateNode DropNode SetProp InsertChild RemoveChild
                     MoveChild TextValue Enabled Gap MainAlignment
                     CrossAlignment GrowValue GridColumns PaddingValue
                     PaddingHorizontal PaddingVertical
                     BackgroundValue ForegroundValue BorderColorValue
                     BorderWidth CornerRadius
                     WidthValue HeightValue MinWidth MaxWidth MinHeight MaxHeight
                     PlaceholderValue ReadOnly MinLines MaxLines
                     AccessibilityLabel StyleClass HeadingLevel LabelledBy
                     DescribedBy ErrorMessageBy InputType Invalid
                     Checked Indeterminate
                     ProgressValue MinValue MaxValue OrientationValue
                     StringValue BoolValue IntValue FloatValue]]
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
    Grid "lui-grid"
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
    ProgressControl "lui-progress-control"
    Divider "lui-separator"
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
          ProgressControl "div"
          Divider "hr"
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
    (when (= kind ProgressControl)
      (Webapi.Dom.Element.setAttribute "role" "progressbar" node))
    (when (= kind Divider)
      (Webapi.Dom.Element.setAttribute "role" "separator" node))
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

(defn- web-color-value [color]
  (if (= color "transparent")
    "transparent"
    (if (or
         (= color "background")
         (= color "foreground")
         (= color "primary")
         (= color "primary-foreground")
         (= color "secondary")
         (= color "secondary-foreground")
         (= color "success")
         (= color "success-foreground")
         (= color "warning")
         (= color "warning-foreground")
         (= color "error")
         (= color "error-foreground")
         (= color "border"))
      (str "var(--color-" color ")")
      color)))

(defn- set-state-attribute! [dom-node attribute enabled]
  (if enabled
    (Webapi.Dom.Element.setAttribute attribute "" dom-node)
    (Webapi.Dom.Element.removeAttribute attribute dom-node)))

(defn- main-alignment-value [alignment]
  (match alignment
    "start" "flex-start"
    "center" "center"
    "end" "flex-end"
    "space_between" "space-between"
    _ (raise (Invalid_argument "invalid main alignment"))))

(defn- cross-alignment-value [alignment]
  (match alignment
    "stretch" "stretch"
    "start" "flex-start"
    "center" "center"
    "end" "flex-end"
    _ (raise (Invalid_argument "invalid cross alignment"))))

(defn- progress-int [renderer node property fallback]
  (match (retained/property (:web-store renderer) node property)
    (Some (IntValue value)) value
    _ fallback))

(defn- update-progress! [renderer node dom-node]
  (let [minimum (progress-int renderer node MinValue 0)
        maximum (progress-int renderer node MaxValue 100)
        value (progress-int renderer node ProgressValue minimum)
        clamped (max minimum (min value maximum))
        position (/ (* (- clamped minimum) 100) (- maximum minimum))]
    (Webapi.Dom.Element.setAttribute "aria-valuemin" (str minimum) dom-node)
    (Webapi.Dom.Element.setAttribute "aria-valuemax" (str maximum) dom-node)
    (Webapi.Dom.Element.setAttribute "aria-valuenow" (str clamped) dom-node)
    (set-style! dom-node "--lui-progress-position" (str position "%"))))

(defn- apply-property! [renderer node kind dom-node property value]
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

    (tuple MainAlignment (StringValue alignment))
    (set-style!
     dom-node "justify-content" (main-alignment-value alignment))

    (tuple CrossAlignment (StringValue alignment))
    (set-style! dom-node "align-items" (cross-alignment-value alignment))

    (tuple GrowValue (FloatValue grow))
    (set-style! dom-node "flex-grow" (str grow))

    (tuple GridColumns (IntValue columns))
    (if (= columns 0)
      (do
        (set-style! dom-node "grid-auto-flow" "column")
        (set-style! dom-node "grid-auto-columns" "minmax(0, 1fr)")
        (set-style! dom-node "grid-template-columns" "none"))
      (do
        (set-style! dom-node "grid-auto-flow" "row")
        (set-style! dom-node "grid-auto-columns" "auto")
        (set-style!
         dom-node "grid-template-columns"
         (str "repeat(" columns ", minmax(0, 1fr))"))))

    (tuple PaddingValue (IntValue padding))
    (set-style! dom-node "padding" (str padding "px"))

    (tuple PaddingHorizontal (IntValue padding))
    (set-style! dom-node "padding-inline" (str padding "px"))

    (tuple PaddingVertical (IntValue padding))
    (set-style! dom-node "padding-block" (str padding "px"))

    (tuple BackgroundValue (StringValue background))
    (set-style! dom-node "background" (web-color-value background))

    (tuple ForegroundValue (StringValue foreground))
    (set-style! dom-node "color" (web-color-value foreground))

    (tuple BorderColorValue (StringValue border))
    (set-style! dom-node "border-color" (web-color-value border))

    (tuple BorderWidth (IntValue width))
    (do
      (set-style! dom-node "border-style" "solid")
      (set-style! dom-node "border-width" (str width "px")))

    (tuple CornerRadius (IntValue radius))
    (set-style! dom-node "border-radius" (str radius "px"))

    (tuple WidthValue (IntValue width))
    (set-style! dom-node "width" (str width "px"))

    (tuple HeightValue (IntValue height))
    (set-style! dom-node "height" (str height "px"))

    (tuple MinWidth (IntValue width))
    (set-style! dom-node "min-width" (str width "px"))

    (tuple MaxWidth (IntValue width))
    (set-style! dom-node "max-width" (str width "px"))

    (tuple MinHeight (IntValue height))
    (set-style! dom-node "min-height" (str height "px"))

    (tuple MaxHeight (IntValue height))
    (set-style! dom-node "max-height" (str height "px"))

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

    (tuple ProgressValue (IntValue _value))
    (update-progress! renderer node dom-node)

    (tuple MinValue (IntValue _value))
    (update-progress! renderer node dom-node)

    (tuple MaxValue (IntValue _value))
    (update-progress! renderer node dom-node)

    (tuple OrientationValue (StringValue orientation))
    (do
      (Webapi.Dom.Element.setAttribute
       "data-orientation" orientation dom-node)
      (Webapi.Dom.Element.setAttribute
       "aria-orientation" orientation dom-node))

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
       renderer node (:semantic-kind current) (:platform-node current)
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
