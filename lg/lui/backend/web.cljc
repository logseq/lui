(ns lui.backend.web
  (:require [ocaml.package/melange-webapi]
            [clojure.string :as string]
            [ocaml.Webapi.Dom.HtmlCollection :as html-collection]
            [lui.protocol :as proto
             :refer [Row Column Grid Stack Panel Card Box
                     Text Heading Paragraph Label Button ToggleButton
                     TextField Input SearchField Textarea Checkbox SwitchControl
                     Select Combobox DropdownMenu MenuItem ListItem Avatar
                     Scroll ListContainer Tabs ButtonGroup ToggleGroup Breadcrumb Pagination
                     Spacer Spinner Icon
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
                     SubmitEnabled DoublePressEnabled
                     ImageIdValue SourceX SourceY SourceWidth SourceHeight
                     AnchorValue AnchorAlignmentValue AnchorOffset
                     StringValue BoolValue IntValue FloatValue]]
            [lui.backend.retained :as retained]))

(defn create
  ([host] (create host {}))
  ([host app-icons]
   (record web-renderer
           (web-store (retained/create-store))
           (web-document (Webapi.Dom.Element.ownerDocument host))
           (web-event-handler (atom (fn [_event] true)))
           (web-app-icons app-icons)
           (web-images (atom {}))
           (web-cleanups (atom {})))))

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
    Tabs "lui-tabs"
    ButtonGroup "lui-button-group"
    ToggleGroup "lui-toggle-group"
    Breadcrumb "lui-breadcrumb"
    Pagination "lui-pagination"
    Spacer "lui-spacer"
    Spinner "lui-spinner"
    Icon "lui-icon"
    Select "lui-select"
    Combobox "lui-combobox"
    DropdownMenu "lui-dropdown-menu"
    MenuItem "lui-menu-item"
    ListItem "lui-list-item"
    Avatar "lui-avatar"))

(defn- direct-toggle? [kind]
  (or (= kind Checkbox) (= kind SwitchControl) (= kind Radio)))

(defn- button-like? [kind]
  (or (= kind Button) (= kind ToggleButton) (= kind Toggle)))

(defn- element [document tag class-name attributes children]
  (let [node (Webapi.Dom.Document.createElement tag document)
        node
        (reduce-kv
         (fn [current name value]
           (Webapi.Dom.Element.setAttribute name value current)
           current)
         node
         attributes)]
    (Webapi.Dom.Element.setClassName node class-name)
    (doseq [child children]
      (Webapi.Dom.Element.appendChild
       (Webapi.Dom.Element.asNode child) node))
    node))

(defn- create-direct-toggle-node [renderer kind]
  (let [document (:web-document renderer)
        control-class
        (match kind
          Radio "lui-radio-control"
          Checkbox "lui-checkbox-control"
          _ "lui-switch-control")
        control-attributes
        (if (= kind SwitchControl)
          {"type" "checkbox" "role" "switch"}
          {"type" (if (= kind Radio) "radio" "checkbox")})]
    (element
     document "label" (base-class-name kind) {}
     [(element document "input" control-class control-attributes [])
      (element document "span" "lui-control-label" {} [])])))

(defn- create-button-node [renderer kind]
  (let [document (:web-document renderer)
        attributes
        {"data-variant" "default"
         "data-size" "default"
         "data-icon-placement" "leading"
         "type" "button"}
        attributes
        (if (or (= kind ToggleButton) (= kind Toggle))
          (assoc attributes "aria-pressed" "false")
          attributes)]
    (element
     document "button" (base-class-name kind) attributes
     [(element
       document "span" "lui-button-icon lui-icon"
       {"aria-hidden" "true"} [])
      (element document "span" "lui-button-label" {} [])])))

(defn- create-combobox-node [renderer]
  (let [document (:web-document renderer)]
    (element
     document "div" "lui-combobox" {}
     [(element
       document "input" "lui-combobox-control"
       {"role" "combobox"
        "aria-haspopup" "listbox"
        "aria-expanded" "false"}
       [])
      (element
       document "button" "lui-combobox-trigger"
       {"type" "button" "aria-label" "Open menu"}
       [])])))

(defn- create-menu-item-node [renderer]
  (let [document (:web-document renderer)
        hidden {"aria-hidden" "true"}]
    (element
     document "button" "lui-menu-item"
     {"type" "button"
      "role" "option"
      "aria-selected" "false"}
     [(element document "span" "lui-menu-item-icon lui-icon" hidden [])
      (element document "span" "lui-menu-item-label" {} [])
      (element
       document "span" "lui-menu-item-check lui-icon"
       {"aria-hidden" "true" "data-name" "check"}
       [])])))

(defn- create-avatar-node [renderer]
  (let [document (:web-document renderer)]
    (element
     document "span" "lui-avatar" {}
     [(element
       document "img" "lui-avatar-image"
       {"alt" "" "aria-hidden" "true" "draggable" "false" "hidden" ""}
       [])
      (element document "span" "lui-avatar-initials" {} [])])))

(defn- create-simple-node [renderer kind]
  (let [tag
        (match kind
          Heading "div"
          Paragraph "p"
          Label "label"
          Text "span"
          TextField "input"
          Input "input"
          SearchField "input"
          Textarea "textarea"
          Select "button"
          ListItem "button"
          Slider "input"
          Divider "hr"
          _ "div")
        attributes
        (match kind
          Heading {"role" "heading"}
          SearchField {"type" "search"}
          Textarea
          {"style"
           "field-sizing: content; resize: vertical; overflow-y: auto"}
          Progress
          {"role" "progressbar"
           "aria-valuemin" "0"
           "aria-valuemax" "1"}
          RadioGroup {"role" "radiogroup"}
          Tabs {"role" "tablist" "aria-orientation" "horizontal"}
          ButtonGroup {"role" "group"}
          ToggleGroup {"role" "group"}
          Breadcrumb {"role" "group"}
          Pagination {"role" "group"}
          Slider
          {"type" "range" "min" "0" "max" "1" "step" "any"}
          Spinner {"role" "progressbar"}
          Divider {"role" "separator"}
          Select
          {"type" "button"
           "role" "combobox"
           "aria-haspopup" "listbox"
           "aria-expanded" "false"}
          ListItem
          {"type" "button"
           "aria-pressed" "false"}
          DropdownMenu
          {"role" "listbox"
           "data-anchor" "below"
           "data-anchor-alignment" "start"}
          _ {})]
    (element
     (:web-document renderer) tag (base-class-name kind) attributes [])))

(defn- platform-node [renderer kind]
  (match kind
    Button (create-button-node renderer kind)
    ToggleButton (create-button-node renderer kind)
    Toggle (create-button-node renderer kind)
    Checkbox (create-direct-toggle-node renderer kind)
    SwitchControl (create-direct-toggle-node renderer kind)
    Radio (create-direct-toggle-node renderer kind)
    Combobox (create-combobox-node renderer)
    MenuItem (create-menu-item-node renderer)
    Avatar (create-avatar-node renderer)
    _ (create-simple-node renderer kind)))

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

(defn- submit-enabled? [renderer node]
  (= (retained/property (:web-store renderer) node SubmitEnabled)
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
       (when (and submit (not (= kind Combobox)))
         (Webapi.Dom.KeyboardEvent.preventDefault event)
         (Stdlib.ignore
          ((deref (:web-event-handler renderer)) (proto/Submit node))))
       (when (and enter (= kind Combobox))
         (Webapi.Dom.KeyboardEvent.preventDefault event)
         (Stdlib.ignore
          ((deref (:web-event-handler renderer))
           (if (submit-enabled? renderer node)
             (proto/Submit node)
             (proto/Press node)))))
       (when (and
              (= kind Combobox)
              (or
               (= "ArrowDown" (Webapi.Dom.KeyboardEvent.key event))
               (= "ArrowUp" (Webapi.Dom.KeyboardEvent.key event))))
         (Webapi.Dom.KeyboardEvent.preventDefault event)
         (Stdlib.ignore
          ((deref (:web-event-handler renderer)) (proto/Press node))))
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

(defn- attach-picker-press-event! [renderer node dom-node]
  (Webapi.Dom.Element.addEventListener
   "click"
   (fn [_event]
     (Stdlib.ignore
      ((deref (:web-event-handler renderer)) (proto/Press node)))
     (Stdlib.ignore true))
   dom-node))

(defn- event-capability? [renderer node property]
  (= (retained/property (:web-store renderer) node property)
     (Some (BoolValue true))))

(defn- attach-pressable-text-events! [renderer node dom-node]
  (Webapi.Dom.Element.addEventListener
   "click"
   (fn [_event]
     (when (event-capability? renderer node PressEnabled)
       (Stdlib.ignore
        ((deref (:web-event-handler renderer)) (proto/Press node))))
     (Stdlib.ignore true))
   dom-node)
  (Webapi.Dom.Element.addKeyDownEventListener
   (fn [event]
     (let [key (Webapi.Dom.KeyboardEvent.key event)]
       (when (and
              (event-capability? renderer node PressEnabled)
              (or (= key "Enter") (= key " ")))
         (Webapi.Dom.KeyboardEvent.preventDefault event)
         (Stdlib.ignore
          ((deref (:web-event-handler renderer)) (proto/Press node))))
       (Stdlib.ignore true)))
   dom-node))

(defn- attach-list-item-events! [renderer node dom-node]
  (Webapi.Dom.Element.addEventListener
   "click"
   (fn [_event]
     (when (event-capability? renderer node PressEnabled)
       (Stdlib.ignore
        ((deref (:web-event-handler renderer)) (proto/Press node))))
     (Stdlib.ignore true))
   dom-node)
  (Webapi.Dom.Element.addEventListener
   "dblclick"
   (fn [_event]
     (when (event-capability? renderer node DoublePressEnabled)
       (Stdlib.ignore
        ((deref (:web-event-handler renderer)) (proto/DoublePress node))))
     (Stdlib.ignore true))
   dom-node)
  (Webapi.Dom.Element.addKeyDownEventListener
   (fn [event]
     (when (and
            (= "Enter" (Webapi.Dom.KeyboardEvent.key event))
            (event-capability? renderer node SubmitEnabled))
       (Webapi.Dom.KeyboardEvent.preventDefault event)
       (Stdlib.ignore
        ((deref (:web-event-handler renderer)) (proto/Submit node))))
     (Stdlib.ignore true))
   dom-node))

(defn- dropdown-group-contains-event? [renderer node event]
  (if-some [current (retained/node (:web-store renderer) node)]
    (match (:retained-parent current)
      (Some parent)
      (Webapi.Dom.Element.contains
       (Webapi.Dom.Element.asNode
        (Webapi.Dom.EventTarget.unsafeAsElement
         (Webapi.Dom.Event.target event)))
       (dom-node renderer parent))
      None false)
    false))

(defn- cleanup-node! [renderer node]
  (if-some [cleanup (clojure.core/get (deref (:web-cleanups renderer)) node)]
    (do
      (cleanup)
      (Stdlib.ignore (swap! (:web-cleanups renderer) dissoc node)))
    (Stdlib.ignore true)))

(defn- attach-dropdown-events! [renderer node _dom-node]
  (let [document (:web-document renderer)
        pointer-handler
        (fn [event]
          (when (not (dropdown-group-contains-event? renderer node event))
            (Stdlib.ignore
             ((deref (:web-event-handler renderer)) (proto/Dismiss node))))
          (Stdlib.ignore true))
        key-handler
        (fn [event]
          (when (= "Escape" (Webapi.Dom.KeyboardEvent.key event))
            (Webapi.Dom.KeyboardEvent.preventDefault event)
            (Stdlib.ignore
             ((deref (:web-event-handler renderer)) (proto/Dismiss node))))
          (Stdlib.ignore true))]
    (Webapi.Dom.Document.addEventListener
     "pointerdown" pointer-handler document)
    (Webapi.Dom.Document.addKeyDownEventListener key-handler document)
    (swap!
     (:web-cleanups renderer)
     assoc
     node
     (fn []
       (Webapi.Dom.Document.removeEventListener
        "pointerdown" pointer-handler document)
       (Webapi.Dom.Document.removeKeyDownEventListener key-handler document)
       (Stdlib.ignore true)))
    (Stdlib.ignore true)))

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

(defn- horizontal-group-child? [group-kind child-kind]
  (match group-kind
    Tabs (= child-kind Button)
    ButtonGroup (or (= child-kind Button) (= child-kind ToggleButton))
    ToggleGroup (= child-kind ToggleButton)
    Breadcrumb (= child-kind Button)
    Pagination (= child-kind Button)
    _ false))

(defn- enabled-node? [renderer node]
  (not (= (retained/property (:web-store renderer) node Enabled)
          (Some (BoolValue false)))))

(defn- horizontal-focus-children [renderer node kind]
  (into
   []
   (filter
    (fn [child]
      (if-some [current (retained/node (:web-store renderer) child)]
        (and
         (horizontal-group-child? kind (:semantic-kind current))
         (enabled-node? renderer child))
        false))
    (retained/children (:web-store renderer) node))))

(defn- focused-child-index [renderer children focused index]
  (if (>= index (count children))
    None
    (if (Webapi.Dom.Element.isSameNode
         (Webapi.Dom.Element.asNode (dom-node renderer (nth children index)))
         focused)
      (Some index)
      (focused-child-index renderer children focused (+ index 1)))))

(defn- horizontal-focus-index [key current length]
  (if (= length 0)
    None
    (match key
      "Home" (Some 0)
      "End" (Some (- length 1))
      "ArrowRight"
      (match current
        (Some index) (Some (mod (+ index 1) length))
        None (Some 0))
      "ArrowLeft"
      (match current
        (Some index) (Some (mod (+ index length -1) length))
        None (Some 0))
      _ None)))

(defn- attach-horizontal-focus! [renderer node kind group-node]
  (Webapi.Dom.Element.addKeyDownEventListener
   (fn [event]
     (let [key (Webapi.Dom.KeyboardEvent.key event)
           children (horizontal-focus-children renderer node kind)
           document
           (Webapi.Dom.Document.unsafeAsHtmlDocument (:web-document renderer))
           current
           (if-some [focused (Webapi.Dom.HtmlDocument.activeElement document)]
             (focused-child-index renderer children focused 0)
             None)]
       (match (horizontal-focus-index key current (count children))
         (Some index)
         (do
           (Webapi.Dom.KeyboardEvent.preventDefault event)
           (Webapi.Dom.HtmlElement.focus
            (Webapi.Dom.Element.unsafeAsHtmlElement
             (dom-node renderer (nth children index)))))
         None (Stdlib.ignore true))
       (Stdlib.ignore true)))
   group-node))

(defn- attach-events! [renderer node kind dom-node]
  (match kind
    Text (attach-pressable-text-events! renderer node dom-node)
    Button (attach-button-events! renderer node kind dom-node)
    ToggleButton (attach-button-events! renderer node kind dom-node)
    TextField (attach-text-events! renderer node kind dom-node)
    Input (attach-text-events! renderer node kind dom-node)
    SearchField (attach-text-events! renderer node kind dom-node)
    Textarea (attach-text-events! renderer node kind dom-node)
    Select (attach-picker-press-event! renderer node dom-node)
    Combobox
    (do
      (attach-text-events! renderer node kind dom-node)
      (attach-picker-press-event! renderer node (child-element dom-node 1)))
    DropdownMenu (attach-dropdown-events! renderer node dom-node)
    MenuItem (attach-picker-press-event! renderer node dom-node)
    ListItem (attach-list-item-events! renderer node dom-node)
    Checkbox (attach-toggle-event! renderer node kind dom-node)
    SwitchControl (attach-toggle-event! renderer node kind dom-node)
    Toggle (attach-button-events! renderer node kind dom-node)
    Radio (attach-radio-event! renderer node dom-node)
    Slider (attach-slider-event! renderer node dom-node)
    Tabs (attach-horizontal-focus! renderer node kind dom-node)
    ButtonGroup (attach-horizontal-focus! renderer node kind dom-node)
    ToggleGroup (attach-horizontal-focus! renderer node kind dom-node)
    Breadcrumb (attach-horizontal-focus! renderer node kind dom-node)
    Pagination (attach-horizontal-focus! renderer node kind dom-node)
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
      (Webapi.Dom.CssStyleDeclaration.setProperty
       "--lui-icon-image" (css-url (str "./icons/" name ".svg"))
       "" element-style))))

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

(defn- avatar-float [renderer node property fallback]
  (match (retained/property (:web-store renderer) node property)
    (Some (FloatValue value)) value
    _ fallback))

(defn- registered-avatar-image [renderer node]
  (match (retained/property (:web-store renderer) node ImageIdValue)
    (Some (IntValue image-id))
    (if (= image-id 0)
      None
      (clojure.core/get (deref (:web-images renderer)) image-id))
    _ None))

(defn- update-avatar! [renderer node dom-node]
  (let [image-node (child-element dom-node 0)
        initials-node (child-element dom-node 1)]
    (match (registered-avatar-image renderer node)
      (Some resource)
      (let [source-x (avatar-float renderer node SourceX 0.0)
            source-y (avatar-float renderer node SourceY 0.0)
            source-width (avatar-float renderer node SourceWidth 0.0)
            source-height (avatar-float renderer node SourceHeight 0.0)
            cropped (> source-width 0.0)]
        (Webapi.Dom.Element.setAttribute
         "src" (:web-image-url resource) image-node)
        (set-state-attribute! image-node "hidden" false)
        (set-state-attribute! initials-node "hidden" true)
        (if cropped
          (let [size 40.0
                scale
                (max (/ size source-width) (/ size source-height))
                crop-width (* source-width scale)
                crop-height (* source-height scale)]
            (set-style!
             image-node "width"
             (str (* (:web-image-width resource) scale) "px"))
            (set-style!
             image-node "height"
             (str (* (:web-image-height resource) scale) "px"))
            (set-style!
             image-node "left"
             (str (+ (* (- source-x) scale)
                     (/ (- size crop-width) 2.0))
                  "px"))
            (set-style!
             image-node "top"
             (str (+ (* (- source-y) scale)
                     (/ (- size crop-height) 2.0))
                  "px"))
            (set-style! image-node "object-fit" "fill"))
          (do
            (set-style! image-node "width" "100%")
            (set-style! image-node "height" "100%")
            (set-style! image-node "left" "0")
            (set-style! image-node "top" "0")
            (set-style! image-node "object-fit" "cover"))))
      None
      (do
        (Webapi.Dom.Element.removeAttribute "src" image-node)
        (set-state-attribute! image-node "hidden" true)
        (set-state-attribute! initials-node "hidden" false)))))

(defn- refresh-avatar-image-id! [renderer image-id]
  (reduce-kv
   (fn [_updated node current]
     (when
      (and
       (= (:semantic-kind current) Avatar)
       (= (clojure.core/get (:retained-properties current) ImageIdValue)
          (Some (IntValue image-id))))
       (update-avatar! renderer node (:platform-node current)))
     true)
   true
   (retained/nodes (:web-store renderer))))

(defn register-image! [renderer image-id url width height]
  (when (<= image-id 0)
    (raise (Invalid_argument "registered image id must be positive")))
  (when
   (or
    (not (Float.is_finite width))
    (not (Float.is_finite height))
    (<= width 0.0)
    (<= height 0.0))
    (raise (Invalid_argument "registered image dimensions must be positive")))
  (swap!
   (:web-images renderer)
   assoc image-id
   (record web-image-resource
     (web-image-url url)
     (web-image-width width)
     (web-image-height height)))
  (refresh-avatar-image-id! renderer image-id)
  true)

(defn unregister-image! [renderer image-id]
  (when (<= image-id 0)
    (raise (Invalid_argument "registered image id must be positive")))
  (when (contains? (deref (:web-images renderer)) image-id)
    (swap! (:web-images renderer) dissoc image-id)
    (refresh-avatar-image-id! renderer image-id))
  true)

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

(defn- select-display-text [renderer node]
  (match (retained/property (:web-store renderer) node TextValue)
    (Some (StringValue text))
    (if (not (= text ""))
      text
      (match (retained/property (:web-store renderer) node PlaceholderValue)
        (Some (StringValue placeholder)) placeholder
        _ ""))
    _
    (match (retained/property (:web-store renderer) node PlaceholderValue)
      (Some (StringValue placeholder)) placeholder
      _ "")))

(defn- direct-tab-trigger? [renderer node]
  (if-some [current (retained/node (:web-store renderer) node)]
    (and
     (= (:semantic-kind current) Button)
     (match (:retained-parent current)
       (Some parent)
       (if-some [parent-node (retained/node (:web-store renderer) parent)]
         (= (:semantic-kind parent-node) Tabs)
         false)
       None false))
    false))

(defn- selected-property [renderer node]
  (match (retained/property (:web-store renderer) node Selected)
    (Some (BoolValue selected)) selected
    _ false))

(defn- refresh-button-context! [renderer node]
  (if-some [current (retained/node (:web-store renderer) node)]
    (when (= (:semantic-kind current) Button)
      (let [element (:platform-node current)
            selected (selected-property renderer node)]
        (if (direct-tab-trigger? renderer node)
          (do
            (Webapi.Dom.Element.setAttribute "role" "tab" element)
            (Webapi.Dom.Element.setAttribute
             "aria-selected" (if selected "true" "false") element)
            (Webapi.Dom.Element.removeAttribute "aria-pressed" element))
          (do
            (Webapi.Dom.Element.removeAttribute "role" element)
            (Webapi.Dom.Element.removeAttribute "aria-selected" element)
            (match (retained/property (:web-store renderer) node Selected)
              (Some (BoolValue _))
              (Webapi.Dom.Element.setAttribute
               "aria-pressed" (if selected "true" "false") element)
              _ (Webapi.Dom.Element.removeAttribute "aria-pressed" element))))))
    (Stdlib.ignore true)))

(defn- apply-property! [renderer node kind dom-node property value]
  (match (tuple property value)
    (tuple TextValue (StringValue text))
    (if (= kind Avatar)
      (do
        (Webapi.Dom.Element.setTextContent
         (child-element dom-node 1) text)
        (update-avatar! renderer node dom-node))
      (if (= kind Select)
      (Webapi.Dom.Element.setTextContent
       dom-node (select-display-text renderer node))
      (if (or (= kind TextField) (= kind Input) (= kind SearchField)
              (= kind Textarea) (= kind Combobox))
        (let [control (text-control-node dom-node)]
          (when (not (= text (Webapi.Dom.HtmlInputElement.value control)))
            (Webapi.Dom.HtmlInputElement.setValue control text)))
        (let [text-node
              (if (direct-toggle? kind)
                (toggle-label-node dom-node)
                dom-node)]
          (let [text-node
                (if (or (button-like? kind) (= kind MenuItem))
                  (button-label-node dom-node)
                  text-node)]
            (when (not (= text (Webapi.Dom.Element.textContent text-node)))
              (Webapi.Dom.Element.setTextContent text-node text)))))))

    (tuple Enabled (BoolValue enabled))
    (let [control-node
          (if (direct-toggle? kind)
            (child-element dom-node 0)
            (if (= kind Combobox)
              (child-element dom-node 0)
              dom-node))]
      (if enabled
        (Webapi.Dom.Element.removeAttribute "disabled" control-node)
        (Webapi.Dom.Element.setAttribute
         "disabled" "disabled" control-node))
      (when (= kind Combobox)
        (let [trigger (child-element dom-node 1)]
          (if enabled
            (Webapi.Dom.Element.removeAttribute "disabled" trigger)
            (Webapi.Dom.Element.setAttribute "disabled" "disabled" trigger))
          (set-state-attribute! dom-node "data-disabled" (not enabled))))
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
    (if (= kind Select)
      (Webapi.Dom.Element.setTextContent
       dom-node (select-display-text renderer node))
      (Webapi.Dom.HtmlInputElement.setPlaceholder
       (text-control-node dom-node) placeholder))

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
    (let [icon
          (if (= kind ListItem)
            dom-node
            (button-icon-node dom-node))]
      (Webapi.Dom.Element.setAttribute "data-name" name icon)
      (update-icon-name! renderer icon name))

    (tuple IconPlacementValue (StringValue placement))
    (Webapi.Dom.Element.setAttribute "data-icon-placement" placement dom-node)

    (tuple Selected (BoolValue selected))
    (do
      (set-state-attribute! dom-node "data-selected" selected)
      (Webapi.Dom.Element.setAttribute
       (if (or (= kind MenuItem) (direct-tab-trigger? renderer node))
         "aria-selected"
         "aria-pressed")
       (if selected "true" "false") dom-node))

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
    (do
      (set-state-attribute! dom-node "data-press-enabled" enabled)
      (when (= kind Text)
        (set-state-attribute! dom-node "data-pressable" enabled)
        (if enabled
          (do
            (Webapi.Dom.Element.setAttribute "role" "button" dom-node)
            (Webapi.Dom.Element.setAttribute "tabindex" "0" dom-node))
          (do
            (Webapi.Dom.Element.removeAttribute "role" dom-node)
            (Webapi.Dom.Element.removeAttribute "tabindex" dom-node)))))

    (tuple SubmitEnabled (BoolValue enabled))
    (set-state-attribute! dom-node "data-submit-enabled" enabled)

    (tuple DoublePressEnabled (BoolValue enabled))
    (set-state-attribute! dom-node "data-double-press-enabled" enabled)

    (tuple ImageIdValue (IntValue _image-id))
    (update-avatar! renderer node dom-node)

    (tuple SourceX (FloatValue _value))
    (update-avatar! renderer node dom-node)

    (tuple SourceY (FloatValue _value))
    (update-avatar! renderer node dom-node)

    (tuple SourceWidth (FloatValue _value))
    (update-avatar! renderer node dom-node)

    (tuple SourceHeight (FloatValue _value))
    (update-avatar! renderer node dom-node)

    (tuple AnchorValue (StringValue anchor))
    (Webapi.Dom.Element.setAttribute "data-anchor" anchor dom-node)

    (tuple AnchorAlignmentValue (StringValue alignment))
    (Webapi.Dom.Element.setAttribute
     "data-anchor-alignment" alignment dom-node)

    (tuple AnchorOffset (FloatValue offset))
    (set-style! dom-node "--lui-anchor-offset" (str offset "px"))

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

(defn- update-picker-expanded! [renderer parent expanded]
  (doseq [child (retained/children (:web-store renderer) parent)]
    (if-some [current (retained/node (:web-store renderer) child)]
      (match (:semantic-kind current)
        Select
        (Webapi.Dom.Element.setAttribute
         "aria-expanded" (if expanded "true" "false")
         (:platform-node current))
        Combobox
        (Webapi.Dom.Element.setAttribute
         "aria-expanded" (if expanded "true" "false")
         (child-element (:platform-node current) 0))
        _ (Stdlib.ignore true))
      (Stdlib.ignore true))))

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
    (cleanup-node! renderer node)

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
      (refresh-button-context! renderer child)
      (if-some [current (retained/node (:web-store renderer) child)]
        (match (:semantic-kind current)
          Radio (update-radio-group! renderer child)
          DropdownMenu (update-picker-expanded! renderer parent true)
          _ (Stdlib.ignore true))
        (Stdlib.ignore true)))

    (RemoveChild parent child)
    (do
      (Stdlib.ignore
       (Webapi.Dom.Element.removeChild
        (Webapi.Dom.Element.asNode
         (dom-node-before renderer previous-nodes child))
        (dom-node-before renderer previous-nodes parent)))
      (refresh-button-context! renderer child)
      (if-some [previous (clojure.core/get previous-nodes child)]
        (when (= (:semantic-kind previous) DropdownMenu)
          (update-picker-expanded! renderer parent false))
        (Stdlib.ignore true)))

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
