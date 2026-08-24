(ns lui.backend.web
  (:require [ocaml.package/melange-webapi]
            [clojure.string :as string]
            [ocaml.Webapi.Dom.HtmlCollection :as html-collection]
            [lui.protocol :as proto
             :refer [Row Column Grid Stack Panel Card Box
                     Text Heading Paragraph Label Button ToggleButton
                     TextField Input SearchField Textarea Checkbox SwitchControl
                     Scroll ListContainer Spacer Spinner Icon
                     Progress Divider
                     Toggle RadioGroup Radio Slider
                     CreateNode DropNode SetProp InsertChild RemoveChild
                     MoveChild TextValue Enabled Gap MainAlignment
                     CrossAlignment GrowValue GridColumns PaddingValue
                     PaddingHorizontal PaddingVertical
                     BackgroundValue ForegroundValue BorderColorValue
                     BorderWidth CornerRadius
                     WidthValue HeightValue MinWidth MaxWidth MinHeight MaxHeight
                     PlaceholderValue AccessibilityLabel StyleClass HeadingLevel
                     Checked
                     ProgressValue OrientationValue SizeValue IconName
                     VariantValue InlineIconName IconPlacementValue Selected Autofocus SubmitOnEnter HoldEnabled
                     ChangeEnabled ToggleEnabled PressEnabled
                     StringValue BoolValue IntValue FloatValue]]
            [lui.backend.retained :as retained]))

(defn create
  ([host] (create host {}))
  ([host app-icons]
   (record web-renderer
     (web-store (retained/create-store))
     (web-document (Webapi.Dom.Element.ownerDocument host))
     (web-event-handler (atom (fn [_event] true)))
     (web-app-icons app-icons))))

(defn set-event-handler! [renderer handler]
  (reset! (:web-event-handler renderer) handler)
  true)

(defn- base-class-name [kind]
  (match kind
    Row "lui-row"
    Column "lui-column"
    Grid "lui-grid"
    Stack "lui-stack"
    Panel "lui-panel"
    Card "lui-card"
    Box "lui-box"
    Text "lui-text"
    Heading "lui-heading"
    Paragraph "lui-paragraph"
    Label "lui-label"
    Button "lui-button"
    ToggleButton "lui-button lui-toggle-button"
    Toggle "lui-toggle"
    RadioGroup "lui-radio-group"
    Radio "lui-radio"
    Slider "lui-slider"
    TextField "lui-text-field"
    Input "lui-input"
    SearchField "lui-search-field"
    Textarea "lui-textarea"
    Checkbox "lui-checkbox"
    SwitchControl "lui-switch"
    Progress "lui-progress"
    Divider "lui-separator"
    Scroll "lui-scroll"
    ListContainer "lui-list"
    Spacer "lui-spacer"
    Spinner "lui-spinner"
    Icon "lui-icon"))

(defn- direct-toggle? [kind]
  (or (= kind Checkbox) (= kind SwitchControl) (= kind Radio)))

(defn- button-like? [kind]
  (or (= kind Button) (= kind ToggleButton) (= kind Toggle)))

(defn- create-direct-toggle-node [renderer kind]
  (let [document (:web-document renderer)
        root (Webapi.Dom.Document.createElement "label" document)
        control (Webapi.Dom.Document.createElement "input" document)
        label (Webapi.Dom.Document.createElement "span" document)]
    (Webapi.Dom.Element.setClassName root (base-class-name kind))
    (Webapi.Dom.Element.setClassName
     control
     (if (= kind Radio)
       "lui-radio-control"
       (if (= kind Checkbox)
       "lui-checkbox-control"
       "lui-switch-control")))
    (Webapi.Dom.Element.setClassName label "lui-control-label")
    (Webapi.Dom.Element.setAttribute
     "type" (if (= kind Radio) "radio" "checkbox") control)
    (when (= kind SwitchControl)
      (Webapi.Dom.Element.setAttribute "role" "switch" control))
    (Webapi.Dom.Element.appendChild
     (Webapi.Dom.Element.asNode control) root)
    (Webapi.Dom.Element.appendChild
     (Webapi.Dom.Element.asNode label) root)
    root))

(defn- create-button-node [renderer kind]
  (let [document (:web-document renderer)
        root (Webapi.Dom.Document.createElement "button" document)
        icon (Webapi.Dom.Document.createElement "span" document)
        label (Webapi.Dom.Document.createElement "span" document)]
    (Webapi.Dom.Element.setClassName root (base-class-name kind))
    (Webapi.Dom.Element.setClassName icon "lui-button-icon lui-icon")
    (Webapi.Dom.Element.setClassName label "lui-button-label")
    (Webapi.Dom.Element.setAttribute "aria-hidden" "true" icon)
    (Webapi.Dom.Element.setAttribute "data-variant" "default" root)
    (Webapi.Dom.Element.setAttribute "data-size" "default" root)
    (Webapi.Dom.Element.setAttribute "data-icon-placement" "leading" root)
    (Webapi.Dom.Element.setAttribute "type" "button" root)
    (when (or (= kind ToggleButton) (= kind Toggle))
      (Webapi.Dom.Element.setAttribute "aria-pressed" "false" root))
    (Webapi.Dom.Element.appendChild (Webapi.Dom.Element.asNode icon) root)
    (Webapi.Dom.Element.appendChild (Webapi.Dom.Element.asNode label) root)
    root))

(defn- platform-node [renderer kind]
  (if (button-like? kind)
    (create-button-node renderer kind)
    (if (direct-toggle? kind)
    (create-direct-toggle-node renderer kind)
    (let [tag
        (match kind
          Heading "div"
          Paragraph "p"
          Label "label"
          Text "span"
          Button "button"
          TextField "input"
          Input "input"
          SearchField "input"
          Textarea "textarea"
          Progress "div"
          Slider "input"
          Divider "hr"
          _ "div")
        node
        (Webapi.Dom.Document.createElement tag (:web-document renderer))]
    (Webapi.Dom.Element.setClassName node (base-class-name kind))
    (when (= kind Heading)
      (Webapi.Dom.Element.setAttribute "role" "heading" node))
    (when (= kind SearchField)
      (Webapi.Dom.Element.setAttribute "type" "search" node))
    (when (= kind Textarea)
      (Webapi.Dom.Element.setAttribute
       "style" "field-sizing: content; resize: vertical; overflow-y: auto" node))
    (when (= kind Progress)
      (do
        (Webapi.Dom.Element.setAttribute "role" "progressbar" node)
        (Webapi.Dom.Element.setAttribute "aria-valuemin" "0" node)
        (Webapi.Dom.Element.setAttribute "aria-valuemax" "1" node)))
    (when (= kind RadioGroup)
      (Webapi.Dom.Element.setAttribute "role" "radiogroup" node))
    (when (= kind Slider)
      (do
        (Webapi.Dom.Element.setAttribute "type" "range" node)
        (Webapi.Dom.Element.setAttribute "min" "0" node)
        (Webapi.Dom.Element.setAttribute "max" "1" node)
        (Webapi.Dom.Element.setAttribute "step" "any" node)))
    (when (= kind Spinner)
      (Webapi.Dom.Element.setAttribute "role" "progressbar" node))
    (when (= kind Divider)
      (Webapi.Dom.Element.setAttribute "role" "separator" node))
      node))))

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

(defn- child-element [dom-node index]
  (if-some [child
            (html-collection/item index (Webapi.Dom.Element.children dom-node))]
    child
    (raise (Invalid_argument "DOM node child is missing"))))

(defn- text-control-node [dom-node]
  (let [candidate
        (if-some [_control
                  (Webapi.Dom.HtmlInputElement.ofNode
                   (Webapi.Dom.Element.asNode dom-node))]
          dom-node
          (child-element dom-node 0))]
    (if-some [control
              (Webapi.Dom.HtmlInputElement.ofNode
               (Webapi.Dom.Element.asNode candidate))]
    control
      (raise (Invalid_argument "DOM node is not a text control")))))

(defn- toggle-label-node [dom-node]
  (child-element dom-node 1))

(defn- button-icon-node [dom-node]
  (child-element dom-node 0))

(defn- button-label-node [dom-node]
  (child-element dom-node 1))

(defn- node-dom-id [node]
  (str "lui-node-" node))

(defn- submit-on-enter? [renderer node]
  (= (retained/property (:web-store renderer) node SubmitOnEnter)
     (Some (BoolValue true))))

(defn- attach-text-events! [renderer node kind dom-node]
  (Webapi.Dom.Element.addEventListener
   "input"
   (fn [_event]
     (Stdlib.ignore
      ((deref (:web-event-handler renderer))
       (proto/TextChanged
        node (Webapi.Dom.HtmlInputElement.value
              (text-control-node dom-node)))))
     (Stdlib.ignore true))
   dom-node)
  (Webapi.Dom.Element.addKeyDownEventListener
   (fn [event]
     (let [enter (= "Enter" (Webapi.Dom.KeyboardEvent.key event))
           shift (Webapi.Dom.KeyboardEvent.shiftKey event)
           primary
           (or (Webapi.Dom.KeyboardEvent.metaKey event)
               (Webapi.Dom.KeyboardEvent.ctrlKey event))
           submit
           (and
            enter
            (if (= kind Textarea)
              (if (submit-on-enter? renderer node)
                (not shift)
                primary)
              true))]
       (when submit
         (Webapi.Dom.KeyboardEvent.preventDefault event)
         (Stdlib.ignore
          ((deref (:web-event-handler renderer)) (proto/Submit node))))
       (Stdlib.ignore true)))
   dom-node))

(defn- attach-toggle-event! [renderer node _kind dom-node]
  (Webapi.Dom.Element.addEventListener
   "change"
   (fn [_event]
     (let [checked
           (Webapi.Dom.HtmlInputElement.checked
            (text-control-node dom-node))]
       (Stdlib.ignore
        ((deref (:web-event-handler renderer))
         (proto/ToggleChanged node checked)))
       (Stdlib.ignore true)))
   (child-element dom-node 0)))

(defn- attach-radio-event! [renderer node dom-node]
  (Webapi.Dom.Element.addEventListener
   "change"
   (fn [_event]
     (when (Webapi.Dom.HtmlInputElement.checked (text-control-node dom-node))
       (Stdlib.ignore
        ((deref (:web-event-handler renderer))
         (if (= (retained/property (:web-store renderer) node ChangeEnabled)
                (Some (BoolValue true)))
           (proto/Change node)
           (if (= (retained/property (:web-store renderer) node ToggleEnabled)
                  (Some (BoolValue true)))
             (proto/ToggleChanged node true)
             (proto/Press node))))))
     (Stdlib.ignore true))
   (child-element dom-node 0)))

(defn- attach-slider-event! [renderer node dom-node]
  (Webapi.Dom.Element.addEventListener
   "input"
   (fn [_event]
     (Stdlib.ignore
      ((deref (:web-event-handler renderer))
       (proto/ValueChanged
        node (Webapi.Dom.HtmlInputElement.valueAsNumber
              (text-control-node dom-node)))))
     (Stdlib.ignore true))
   dom-node))

(defn- attach-button-events! [renderer node kind dom-node]
  (let [timer (atom None)
        suppress-click (atom false)
        hold-enabled?
        (fn []
          (and
           (Webapi.Dom.Element.hasAttribute "data-hold-enabled" dom-node)
           (not (Webapi.Dom.Element.hasAttribute "disabled" dom-node))))
        cancel!
        (fn []
          (match (deref timer)
            (Some timer-id) (Js.Global.clearTimeout timer-id)
            None (Stdlib.ignore true))
          (reset! timer None)
          true)
        dispatch-hold!
        (fn [suppress]
          (when (hold-enabled?)
            (reset! suppress-click suppress)
            (Stdlib.ignore
             ((deref (:web-event-handler renderer)) (proto/Hold node))))
          true)
        dispatch-primary!
        (fn []
          (if (or (= kind ToggleButton) (= kind Toggle))
            (let [selected
                  (match (Webapi.Dom.Element.getAttribute
                          "aria-pressed" dom-node)
                    (Some "true") true
                    _ false)
                  next-selected (not selected)]
              (if next-selected
                (Webapi.Dom.Element.setAttribute "data-selected" "" dom-node)
                (Webapi.Dom.Element.removeAttribute "data-selected" dom-node))
              (Webapi.Dom.Element.setAttribute
               "aria-pressed" (if next-selected "true" "false") dom-node)
              (Stdlib.ignore
               ((deref (:web-event-handler renderer))
                (proto/ToggleChanged node next-selected))))
            (Stdlib.ignore
             ((deref (:web-event-handler renderer)) (proto/Press node))))
          true)
        start!
        (fn []
          (cancel!)
          (when (hold-enabled?)
            (reset!
             timer
             (Some
              (Js.Global.setTimeout
               350
               :f
               (fn []
                 (reset! timer None)
                 (dispatch-hold! true)
                 (Stdlib.ignore true))))))
          true)]
    (Webapi.Dom.Element.addMouseDownEventListener
     (fn [event]
       (when (= 0 (Webapi.Dom.MouseEvent.button event)) (start!))
       (Stdlib.ignore true))
     dom-node)
    (Webapi.Dom.Element.addMouseUpEventListener
     (fn [_event] (cancel!) (Stdlib.ignore true)) dom-node)
    (Webapi.Dom.Element.addEventListener
     "mouseleave"
     (fn [_event] (cancel!) (Stdlib.ignore true)) dom-node)
    (Webapi.Dom.Element.addTouchStartEventListener
     (fn [_event] (start!) (Stdlib.ignore true)) dom-node)
    (Webapi.Dom.Element.addTouchEndEventListener
     (fn [_event] (cancel!) (Stdlib.ignore true)) dom-node)
    (Webapi.Dom.Element.addEventListener
     "touchcancel"
     (fn [_event]
       (cancel!)
       (reset! suppress-click false)
       (Stdlib.ignore true))
     dom-node)
    (Webapi.Dom.Element.addEventListener
     "contextmenu"
     (fn [event]
       (when (hold-enabled?)
         (cancel!)
         (Webapi.Dom.Event.preventDefault event)
         (Stdlib.ignore (dispatch-hold! false)))
       (Stdlib.ignore true))
     dom-node)
    (Webapi.Dom.Element.addEventListener
     "click"
     (fn [event]
       (if (deref suppress-click)
         (do
           (reset! suppress-click false)
           (Webapi.Dom.Event.preventDefault event))
         (Stdlib.ignore (dispatch-primary!)))
       (Stdlib.ignore true))
     dom-node)))

(defn- attach-events! [renderer node kind dom-node]
  (match kind
    Button (attach-button-events! renderer node kind dom-node)
    ToggleButton (attach-button-events! renderer node kind dom-node)
    TextField (attach-text-events! renderer node kind dom-node)
    Input (attach-text-events! renderer node kind dom-node)
    SearchField (attach-text-events! renderer node kind dom-node)
    Textarea (attach-text-events! renderer node kind dom-node)
    Checkbox (attach-toggle-event! renderer node kind dom-node)
    SwitchControl (attach-toggle-event! renderer node kind dom-node)
    Toggle (attach-button-events! renderer node kind dom-node)
    Radio (attach-radio-event! renderer node dom-node)
    Slider (attach-slider-event! renderer node dom-node)
    _ (Stdlib.ignore true)))

(defn- set-style! [dom-node property value]
  (let [element-style
        (Webapi.Dom.HtmlElement.style
         (Webapi.Dom.Element.unsafeAsHtmlElement dom-node))]
    (Webapi.Dom.CssStyleDeclaration.setProperty
     property value "" element-style)))

(defn- css-url [url]
  (str
   "url(\""
   (string/escape url {\\ "\\\\" \" "\\\""})
   "\")"))

(defn- update-icon-name! [renderer dom-node name]
  (let [element-style
        (Webapi.Dom.HtmlElement.style
         (Webapi.Dom.Element.unsafeAsHtmlElement dom-node))]
    (if (string/starts-with? name "app:")
      (let [bare-name (subs name 4)
            image
            (if-some [url (clojure.core/get (:web-app-icons renderer) bare-name)]
              (css-url url)
              "url(\"./icons/missing.svg\")")]
        (Webapi.Dom.CssStyleDeclaration.setProperty
         "--lui-icon-image" image "" element-style))
      (Stdlib.ignore
       (Webapi.Dom.CssStyleDeclaration.removeProperty
        "--lui-icon-image" element-style)))))

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

(defn- progress-float [renderer node]
  (match (retained/property (:web-store renderer) node ProgressValue)
    (Some (FloatValue value)) value
    _ 0.0))

(defn- update-progress! [renderer node dom-node]
  (let [value (progress-float renderer node)
        clamped (max 0.0 (min value 1.0))
        position (* clamped 100.0)]
    (Webapi.Dom.Element.setAttribute "aria-valuenow" (str clamped) dom-node)
    (set-style! dom-node "--lui-progress-position" (str position "%"))))

(defn- apply-property! [renderer node kind dom-node property value]
  (match (tuple property value)
    (tuple TextValue (StringValue text))
    (if (or (= kind TextField) (= kind Input) (= kind SearchField)
            (= kind Textarea))
      (let [control (text-control-node dom-node)]
        (when (not (= text (Webapi.Dom.HtmlInputElement.value control)))
          (Webapi.Dom.HtmlInputElement.setValue control text)))
      (let [text-node
            (if (direct-toggle? kind)
              (toggle-label-node dom-node)
              dom-node)]
        (let [text-node
              (if (button-like? kind)
                (button-label-node dom-node)
                text-node)]
        (when (not (= text (Webapi.Dom.Element.textContent text-node)))
          (Webapi.Dom.Element.setTextContent text-node text)))))

    (tuple Enabled (BoolValue enabled))
    (let [control-node
          (if (direct-toggle? kind)
            (child-element dom-node 0)
            dom-node)]
      (if enabled
        (Webapi.Dom.Element.removeAttribute "disabled" control-node)
        (Webapi.Dom.Element.setAttribute
         "disabled" "disabled" control-node))
      (when (direct-toggle? kind)
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

    (tuple AccessibilityLabel (StringValue label))
    (Webapi.Dom.Element.setAttribute
     "aria-label" label
     (if (direct-toggle? kind)
       (child-element dom-node 0)
       dom-node))

    (tuple StyleClass (StringValue class-name))
    (Webapi.Dom.Element.setClassName
     dom-node (str (base-class-name kind) " " class-name))

    (tuple HeadingLevel (IntValue level))
    (Webapi.Dom.Element.setAttribute "aria-level" (str level) dom-node)

    (tuple Checked (BoolValue checked))
    (if (= kind Toggle)
      (do
        (set-state-attribute! dom-node "data-checked" checked)
        (Webapi.Dom.Element.setAttribute
         "aria-pressed" (if checked "true" "false") dom-node))
      (do
        (Webapi.Dom.HtmlInputElement.setChecked
         (text-control-node dom-node) checked)
        (set-state-attribute! dom-node "data-checked" checked)
        (Webapi.Dom.Element.setAttribute
         "aria-checked" (if checked "true" "false")
         (child-element dom-node 0))))

    (tuple ProgressValue (FloatValue value))
    (if (= kind Progress)
      (update-progress! renderer node dom-node)
      (Webapi.Dom.HtmlInputElement.setValue
       (text-control-node dom-node) (str value)))

    (tuple OrientationValue (StringValue orientation))
    (do
      (Webapi.Dom.Element.setAttribute
       "data-orientation" orientation dom-node)
      (Webapi.Dom.Element.setAttribute
       "aria-orientation" orientation dom-node))

    (tuple SizeValue (StringValue size))
    (Webapi.Dom.Element.setAttribute "data-size" size dom-node)

    (tuple IconName (StringValue name))
    (do
      (Webapi.Dom.Element.setAttribute "data-name" name dom-node)
      (update-icon-name! renderer dom-node name))

    (tuple VariantValue (StringValue variant))
    (Webapi.Dom.Element.setAttribute "data-variant" variant dom-node)

    (tuple InlineIconName (StringValue name))
    (let [icon (button-icon-node dom-node)]
      (Webapi.Dom.Element.setAttribute "data-name" name icon)
      (update-icon-name! renderer icon name))

    (tuple IconPlacementValue (StringValue placement))
    (Webapi.Dom.Element.setAttribute "data-icon-placement" placement dom-node)

    (tuple Selected (BoolValue selected))
    (do
      (set-state-attribute! dom-node "data-selected" selected)
      (Webapi.Dom.Element.setAttribute
       "aria-pressed" (if selected "true" "false") dom-node))

    (tuple Autofocus (BoolValue autofocus))
    (if autofocus
      (do
        (Webapi.Dom.Element.setAttribute "autofocus" "autofocus" dom-node)
        (Stdlib.ignore
         (Js.Global.setTimeout
          0
          :f
          (fn []
            (Webapi.Dom.HtmlElement.focus
             (Webapi.Dom.Element.unsafeAsHtmlElement dom-node))
            (Stdlib.ignore true)))))
      (Webapi.Dom.Element.removeAttribute "autofocus" dom-node))

    (tuple SubmitOnEnter (BoolValue submit-on-enter))
    (set-state-attribute! dom-node "data-submit-on-enter" submit-on-enter)

    (tuple HoldEnabled (BoolValue enabled))
    (set-state-attribute! dom-node "data-hold-enabled" enabled)

    (tuple ChangeEnabled (BoolValue enabled))
    (set-state-attribute! dom-node "data-change-enabled" enabled)

    (tuple ToggleEnabled (BoolValue enabled))
    (set-state-attribute! dom-node "data-toggle-enabled" enabled)

    (tuple PressEnabled (BoolValue enabled))
    (set-state-attribute! dom-node "data-press-enabled" enabled)

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

(defn- radio-group-ancestor [renderer node]
  (if-some [current (retained/node (:web-store renderer) node)]
    (match (:retained-parent current)
      (Some parent)
      (if-some [parent-node (retained/node (:web-store renderer) parent)]
        (if (= (:semantic-kind parent-node) RadioGroup)
          (Some parent)
          (radio-group-ancestor renderer parent))
        None)
      None None)
    None))

(defn- update-radio-group! [renderer node]
  (match (radio-group-ancestor renderer node)
    (Some group)
    (Webapi.Dom.Element.setAttribute
     "name" (str "lui-radio-group-" group)
     (child-element (dom-node renderer node) 0))
    None (Stdlib.ignore true)))

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

    (DropNode _node)
    (Stdlib.ignore true)

    (SetProp node property value)
    (if-some [current (retained/node (:web-store renderer) node)]
      (apply-property!
       renderer node (:semantic-kind current) (:platform-node current)
       property value)
      (raise (Invalid_argument "unknown DOM node")))

    (InsertChild parent child index)
    (do
      (insert-dom-child!
       (dom-node renderer parent) (dom-node renderer child) index)
      (if-some [current (retained/node (:web-store renderer) child)]
        (when (= (:semantic-kind current) Radio)
          (update-radio-group! renderer child))
        (Stdlib.ignore true)))

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
