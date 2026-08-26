(ns lui.backend.web
  (:require [ocaml.package/melange-webapi]
            [ocaml.Js.Dict :as js-dict]
            [ocaml.Obj :as obj]
            [clojure.string :as string]
            [ocaml.Webapi.Dom.HtmlCollection :as html-collection]
            [ocaml.Webapi.Dom.NodeList :as node-list]
            [lui.extension :as ext]
            [lui.protocol :as proto
             :refer [Row Column Grid Stack Panel Card Alert Bubble Box
                     Text Heading Paragraph Label Button ToggleButton
                     TextField Input SearchField Textarea Checkbox SwitchControl
                     Select Combobox DropdownMenu ContextMenu MenuItem ListItem Avatar Image MediaSurface Stepper Step Timeline TimelineItem InputGroup InputGroupActions Dialog Sheet Tooltip Toast Toolbar Accordion
                     Table TableRow TableCell Tree Resizable Split StatusBar
                     Scroll ListContainer Tabs ButtonGroup ToggleGroup Breadcrumb Pagination
                     Spacer Spinner Icon
                     Progress Divider
                     Toggle RadioGroup Radio Slider
                     CreateNode CreateExtension DropNode SetProp RemoveProp
                     SetExtensionProp RemoveExtensionProp
                     InsertChild RemoveChild MoveChild
                     TextValue Enabled Gap MainAlignment
                     CrossAlignment GrowValue GridColumns PaddingValue
                     PaddingHorizontal PaddingVertical
                     BackgroundValue ForegroundValue BorderColorValue
                     BorderWidth CornerRadius
                     WidthValue HeightValue MinWidth MaxWidth MinHeight MaxHeight
                     PlaceholderValue AccessibilityLabel StyleClass HeadingLevel
                     Checked
                     ProgressValue ResizeDuration ResizeEasing ResizeOrigin
                     OrientationValue SizeValue IconName
                     VariantValue InlineIconName IconPlacementValue Selected Autofocus SubmitOnEnter HoldEnabled
                     ChangeEnabled ToggleEnabled PressEnabled
                     SubmitEnabled DoublePressEnabled
                     ImageIdValue SurfaceIdValue ActiveIndex TitleValue DescriptionValue MetaValue IndicatorValue Connector SourceX SourceY SourceWidth SourceHeight
                     AnchorValue AnchorAlignmentValue AnchorOffset TooltipDelay DurationValue
                     TextAlignment RoleValue TreeLevel Expanded
                     StringValue BoolValue IntValue FloatValue]]
            [lui.backend.retained :as retained]))

(defn- pointer-mouse-event [event]
  (obj/magic event))

(defn- pointer-type [event]
  (match (js-dict/get (obj/magic event) "pointerType")
    (Some value) value
    None ""))

(defn- pointer-id [event]
  (match (js-dict/get (obj/magic event) "pointerId")
    (Some value) value
    None 0))

(defn- standard-kind [current]
  (match (retained/standard-kind current)
    (Some kind) kind
    None (raise (Invalid_argument "expected standard DOM node"))))

(defn- standard-kind? [current expected]
  (match (retained/standard-kind current)
    (Some kind) (= kind expected)
    None false))

(defn create-with-extensions
  [host app-icons registry adapters]
  (let [document (Webapi.Dom.Element.ownerDocument host)
        portal-root (Webapi.Dom.Document.createElement "div" document)
        toast-viewport (Webapi.Dom.Document.createElement "div" document)
        html-document (Webapi.Dom.Document.unsafeAsHtmlDocument document)]
    (Webapi.Dom.Element.setClassName portal-root "lui-popup-portal")
    (Webapi.Dom.Element.setClassName toast-viewport "lui-toast-viewport")
    (Webapi.Dom.Element.setAttribute "role" "region" toast-viewport)
    (Webapi.Dom.Element.setAttribute
     "aria-label" "Notifications" toast-viewport)
    (Webapi.Dom.Element.setAttribute "tabindex" "-1" toast-viewport)
    (Webapi.Dom.Element.appendChild
     (Webapi.Dom.Element.asNode toast-viewport) portal-root)
    (Webapi.Dom.Element.setAttribute "data-lui-root" "" host)
    (if-some [body (Webapi.Dom.HtmlDocument.body html-document)]
      (Webapi.Dom.Element.appendChild
       (Webapi.Dom.Element.asNode portal-root) body)
      (raise (Invalid_argument "document body is unavailable")))
    (record web-renderer
            (web-store (retained/create-store))
            (web-document document)
            (web-host host)
            (web-portal-root portal-root)
            (web-toast-viewport toast-viewport)
            (web-event-handler (atom (fn [_event] true)))
            (web-app-icons app-icons)
            (web-images (atom {}))
            (web-media-surfaces (atom {}))
            (web-cleanups (atom {}))
            (web-modal-stack (atom []))
            (web-open-tooltip (atom None))
            (web-tooltip-warm (atom false))
            (web-open-context-menu (atom None))
            (web-splits (atom {}))
            (web-extension-registry registry)
            (web-extension-adapters adapters))))

(defn create
  ([host] (create host {}))
  ([host app-icons]
   (create-with-extensions host app-icons (ext/registry) {})))

(defn- extension-adapter [renderer identifier]
  (if-some [adapter
            (clojure.core/get (:web-extension-adapters renderer) identifier)]
    adapter
    (raise (Invalid_argument "web extension adapter is not registered"))))

(defn- extension-platform-node [renderer node identifier]
  (let [adapter (extension-adapter renderer identifier)
        emit
        (fn [name values]
          (Stdlib.ignore
           ((deref (:web-event-handler renderer))
            (proto/ExtensionEvent node identifier name values))))]
    ((:web-extension-create adapter) node (:web-document renderer) emit)))

(defn- apply-extension-property! [renderer node property value]
  (if-some [current (retained/node (:web-store renderer) node)]
    (match (retained/extension-identity current)
      (Some (tuple identifier _fingerprint))
      ((:web-extension-set-property (extension-adapter renderer identifier))
       (:platform-node current) property value)
      None
      (raise (Invalid_argument "extension property targets standard DOM node")))
    (raise (Invalid_argument "unknown DOM node"))))

(defn- remove-extension-property! [renderer node property]
  (if-some [current (retained/node (:web-store renderer) node)]
    (match (retained/extension-identity current)
      (Some (tuple identifier _fingerprint))
      ((:web-extension-remove-property (extension-adapter renderer identifier))
       (:platform-node current) property)
      None
      (raise (Invalid_argument "extension property targets standard DOM node")))
    (raise (Invalid_argument "unknown DOM node"))))

(defn- cleanup-extension-node! [renderer previous-nodes node]
  (if-some [current (clojure.core/get previous-nodes node)]
    (match (retained/extension-identity current)
      (Some (tuple identifier _fingerprint))
      ((:web-extension-cleanup (extension-adapter renderer identifier))
       (:platform-node current))
      None (Stdlib.ignore true))
    (Stdlib.ignore true)))

(defn- modal-surface? [kind]
  (or (= kind Dialog) (= kind Sheet)))

(defn set-event-handler! [renderer handler]
  (reset! (:web-event-handler renderer) handler)
  true)

(defn- base-class-name [kind]
  (match kind
    Root "lui-root"
    Row "lui-row"
    Column "lui-column"
    Grid "lui-grid"
    Stack "lui-stack"
    Panel "lui-panel"
    Card "lui-card"
    Alert "lui-alert"
    Bubble "lui-bubble"
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
    ContextMenu "lui-context-menu"
    MenuItem "lui-menu-item"
    ListItem "lui-list-item"
    Avatar "lui-avatar"
    Image "lui-image"
    MediaSurface "lui-media-surface"
    Stepper "lui-stepper"
    Step "lui-step"
    Timeline "lui-timeline"
    TimelineItem "lui-timeline-item"
    InputGroup "lui-input-group"
    InputGroupActions "lui-input-group-actions"
    Dialog "lui-dialog"
    Sheet "lui-sheet"
    Tooltip "lui-tooltip"
    Toast "lui-toast"
    Toolbar "lui-toolbar"
    Accordion "lui-accordion"
    Table "lui-table"
    TableRow "lui-table-row"
    TableCell "lui-table-cell"
    Tree "lui-tree"
    Resizable "lui-resizable"
    Split "lui-split"
    StatusBar "lui-status-bar"))

(defn- create-split-node [renderer]
  (element
   (:web-document renderer) "div" "lui-split" {}
   [(element (:web-document renderer) "div" "lui-split-panes" {} [])
    (element
     (:web-document renderer) "div" "lui-split-divider"
     {"role" "separator"
      "aria-orientation" "vertical"
      "aria-valuemin" "0"
      "aria-valuemax" "1"
      "aria-valuenow" "0.5"
      "tabindex" "0"}
     [])]))

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

(defn- create-select-node [renderer]
  (element
   (:web-document renderer) "button" "lui-select"
   {"type" "button"
    "role" "combobox"
    "aria-haspopup" "listbox"
    "aria-expanded" "false"}
   [(element
     (:web-document renderer) "span" "lui-select-value" {} [])]))

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

(defn- create-dropdown-node [renderer]
  (let [document (:web-document renderer)]
    (element
     document "div" "lui-popup-positioner"
     {"data-anchor" "below" "data-anchor-alignment" "start"}
     [(element
       document "div" "lui-dropdown-menu"
       {"role" "listbox" "tabindex" "-1"}
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

(defn- create-media-node [renderer kind]
  (let [class-name (base-class-name kind)
        pixels-class
        (if (= kind Image)
          "lui-image-pixels"
          "lui-media-surface-frame")]
    (element
     (:web-document renderer) "span" class-name {}
     [(element
       (:web-document renderer) "img" pixels-class
       {"alt" "" "aria-hidden" "true" "draggable" "false" "hidden" ""}
       [])])))

(defn- create-step-node [renderer]
  (let [document (:web-document renderer)]
    (element
     document "div" "lui-step" {"role" "listitem"}
     [(element document "span" "lui-step-indicator"
               {"aria-hidden" "true"} [])
      (element document "span" "lui-step-label" {} [])
      (element document "span" "lui-step-connector"
               {"aria-hidden" "true"} [])])))

(defn- create-timeline-item-node [renderer]
  (let [document (:web-document renderer)]
    (element
     document "div" "lui-timeline-item"
     {"role" "listitem" "data-variant" "outline"}
     [(element
       document "div" "lui-timeline-item-lead" {"aria-hidden" "true"}
       [(element document "span"
                 "lui-timeline-item-indicator" {} [])
        (element document "span" "lui-timeline-item-connector" {} [])])
      (element
       document "div" "lui-timeline-item-content" {}
       [(element document "div" "lui-timeline-item-title" {} [])
        (element document "div" "lui-timeline-item-description"
                 {"hidden" ""} [])
        (element document "div" "lui-timeline-item-meta"
                 {"hidden" ""} [])])
      (element document "span" "lui-timeline-item-chevron lui-icon"
               {"aria-hidden" "true"
                "data-name" "chevron-right"
                "hidden" ""}
               [])])))

(defn- create-accordion-node [renderer]
  (let [document (:web-document renderer)]
    (element
     document "div" "lui-accordion" {"data-closed" ""}
     [(element
       document "button" "lui-accordion-summary"
       {"type" "button" "aria-expanded" "false"}
       [(element document "span" "lui-accordion-label" {} [])
        (element
         document "span" "lui-accordion-chevron lui-icon"
         {"aria-hidden" "true" "data-name" "chevron-down"} [])])
      (element
       document "div" "lui-accordion-content"
       {"role" "region" "data-closed" "" "hidden" ""} [])])))

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
          Table "table"
          TableRow "tr"
          TableCell "td"
          Stepper "div"
          Timeline "div"
          InputGroup "div"
          InputGroupActions "div"
          Tree "div"
          Tooltip "span"
          Toast "div"
          Toolbar "div"
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
          Table {"role" "grid"}
          TableRow {"role" "row" "aria-selected" "false"}
          TableCell {"role" "gridcell"}
          Tree {"role" "tree"}
          Stepper {"role" "list"}
          Timeline {"role" "list"}
          InputGroup {"role" "group"}
          DropdownMenu
          {"role" "listbox"
           "data-anchor" "below"
           "data-anchor-alignment" "start"}
          ContextMenu {"role" "menu" "tabindex" "-1"}
          Tooltip {"role" "tooltip"}
          Toast
          {"role" "status" "aria-atomic" "true" "tabindex" "0"
           "data-state" "open"}
          Toolbar
          {"role" "toolbar" "aria-orientation" "horizontal"}
          StatusBar {"role" "status"}
          _ {})]
    (element
     (:web-document renderer) tag (base-class-name kind) attributes [])))

(defn- create-modal-node [renderer kind]
  (let [document (:web-document renderer)
        class-name (base-class-name kind)
        layer
        (element
         document "div" "lui-modal-layer"
         {"data-lui-modal-state" "closed" "hidden" ""} [])
        backdrop
        (element document "div" "lui-modal-backdrop" {"aria-hidden" "true"} [])
        surface
        (element
         document "section" class-name
         {"role" "dialog" "aria-modal" "true" "tabindex" "-1"}
         [(element document "div" (str class-name "-title") {} [])
          (element document "div" (str class-name "-body") {} [])])]
    (Webapi.Dom.Element.appendChild (Webapi.Dom.Element.asNode backdrop) layer)
    (Webapi.Dom.Element.appendChild (Webapi.Dom.Element.asNode surface) layer)
    surface))

(defn- create-alert-node [renderer]
  (let [document (:web-document renderer)]
    (element
     document "section" "lui-alert"
     {"role" "alert" "data-variant" "default"}
     [(element document "div" "lui-alert-title" {} [])
      (element document "div" "lui-alert-content" {} [])])))

(defn- create-bubble-node [renderer]
  (let [document (:web-document renderer)]
    (element
     document "div" "lui-bubble"
     {"data-variant" "default" "data-reactions-alignment" "end"}
     [(element document "div" "lui-bubble-content" {} [])
      (element document "span" "lui-bubble-reactions" {} [])])))

(defn- platform-node [renderer kind]
  (match kind
    Button (create-button-node renderer kind)
    ToggleButton (create-button-node renderer kind)
    Toggle (create-button-node renderer kind)
    Checkbox (create-direct-toggle-node renderer kind)
    SwitchControl (create-direct-toggle-node renderer kind)
    Radio (create-direct-toggle-node renderer kind)
    Select (create-select-node renderer)
    Combobox (create-combobox-node renderer)
    DropdownMenu (create-dropdown-node renderer)
    MenuItem (create-menu-item-node renderer)
    Avatar (create-avatar-node renderer)
    Image (create-media-node renderer kind)
    MediaSurface (create-media-node renderer kind)
    Step (create-step-node renderer)
    TimelineItem (create-timeline-item-node renderer)
    Accordion (create-accordion-node renderer)
    Alert (create-alert-node renderer)
    Bubble (create-bubble-node renderer)
    Dialog (create-modal-node renderer kind)
    Sheet (create-modal-node renderer kind)
    Split (create-split-node renderer)
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
  (let [tag-name (Webapi.Dom.Element.tagName dom-node)
        candidate
        (if (or (= tag-name "INPUT") (= tag-name "TEXTAREA"))
          dom-node
          (child-element dom-node 0))
        candidate-tag-name (Webapi.Dom.Element.tagName candidate)]
    (when-not
     (or (= candidate-tag-name "INPUT") (= candidate-tag-name "TEXTAREA"))
     (raise (Invalid_argument "DOM node is not a text control")))
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

(defn- accordion-trigger-node [dom-node]
  (child-element dom-node 0))

(defn- accordion-panel-node [dom-node]
  (child-element dom-node 1))

(defn- accordion-label-node [dom-node]
  (child-element (accordion-trigger-node dom-node) 0))

(defn- initialize-accordion-semantics! [node dom-node]
  (let [trigger (accordion-trigger-node dom-node)
        panel (accordion-panel-node dom-node)
        trigger-id (str (node-dom-id node) "-trigger")
        panel-id (str (node-dom-id node) "-panel")]
    (Webapi.Dom.Element.setAttribute "id" trigger-id trigger)
    (Webapi.Dom.Element.setAttribute "id" panel-id panel)
    (Webapi.Dom.Element.setAttribute "aria-controls" panel-id trigger)
    (Webapi.Dom.Element.setAttribute "aria-labelledby" trigger-id panel)
    (Stdlib.ignore true)))

(defn- submit-on-enter? [renderer node]
  (= (retained/property (:web-store renderer) node SubmitOnEnter)
     (Some (BoolValue true))))

(defn- submit-enabled? [renderer node]
  (= (retained/property (:web-store renderer) node SubmitEnabled)
     (Some (BoolValue true))))

(defn- picker-dropdown [renderer picker]
  (if-some [current (retained/node (:web-store renderer) picker)]
    (match (:retained-parent current)
      (Some parent)
      (loop [children (retained/children (:web-store renderer) parent)
             index 0]
        (if (= index (count children))
          None
          (let [child (nth children index)]
            (if-some [child-node (retained/node (:web-store renderer) child)]
              (if (standard-kind? child-node DropdownMenu)
                (Some child)
                (recur children (inc index)))
              (recur children (inc index))))))
      None None)
    None))

(defn- picker-under-parent [renderer parent]
  (loop [children (retained/children (:web-store renderer) parent)
         index 0]
    (if (= index (count children))
      None
      (let [child (nth children index)]
        (if-some [child-node (retained/node (:web-store renderer) child)]
          (if (or (standard-kind? child-node Select)
                  (standard-kind? child-node Combobox))
            (Some child)
            (recur children (inc index)))
          (recur children (inc index)))))))

(defn- picker-for-dropdown [renderer dropdown]
  (if-some [current (retained/node (:web-store renderer) dropdown)]
    (match (:retained-parent current)
      (Some parent) (picker-under-parent renderer parent)
      None None)
    None))

(defn- picker-control-element [renderer picker]
  (let [picker-element (dom-node renderer picker)]
    (if-some [current (retained/node (:web-store renderer) picker)]
      (if (standard-kind? current Combobox)
        (child-element picker-element 0)
        picker-element)
      (raise (Invalid_argument "unknown picker node")))))

(defn- picker-menu-items [renderer dropdown]
  (if-some [current (retained/node (:web-store renderer) dropdown)]
    (filterv
     (fn [child]
       (if-some [child-node (retained/node (:web-store renderer) child)]
         (and (standard-kind? child-node MenuItem)
              (enabled-node? renderer child))
         false))
     (:retained-children current))
    []))

(defn- picker-selected-index [renderer dropdown]
  (let [items (picker-menu-items renderer dropdown)]
    (loop [index 0]
      (if (= index (count items))
        0
        (if (= (retained/property
                (:web-store renderer) (nth items index) Selected)
               (Some (BoolValue true)))
          index
          (recur (inc index)))))))

(defn- combobox-active-index [renderer picker items]
  (if-some [value
            (Webapi.Dom.Element.getAttribute
             "data-lui-active-index"
             (picker-control-element renderer picker))]
    (if-some [index (parse-long value)]
      (if (and (>= index 0) (< index (count items)))
        (Some index)
        None)
      None)
    None))

(defn- set-combobox-active! [renderer picker dropdown index]
  (let [items (picker-menu-items renderer dropdown)
        control (picker-control-element renderer picker)]
    (doseq [item items]
      (Webapi.Dom.Element.removeAttribute "data-highlighted"
                                          (dom-node renderer item)))
    (when (and (not (empty? items)) (>= index 0) (< index (count items)))
      (let [item (nth items index)
            element (dom-node renderer item)]
        (Webapi.Dom.Element.setAttribute
         "data-lui-active-index" (str index) control)
        (Webapi.Dom.Element.setAttribute "data-highlighted" "" element)
        (Webapi.Dom.Element.setAttribute
         "aria-activedescendant" (node-dom-id item) control)))))

(defn- clear-combobox-active! [renderer picker]
  (let [control (picker-control-element renderer picker)]
    (Webapi.Dom.Element.removeAttribute "data-lui-active-index" control)
    (Webapi.Dom.Element.removeAttribute "aria-activedescendant" control)))

(defn- ensure-combobox-status! [renderer dropdown]
  (let [popup (child-element (dom-node renderer dropdown) 0)]
    (if-some [status
              (Webapi.Dom.Element.querySelector
               ".lui-combobox-status" popup)]
      status
      (let [status
            (element
             (:web-document renderer) "div" "lui-combobox-status"
             {"role" "status"
              "aria-live" "polite"
              "aria-atomic" "true"}
             [])]
        (Webapi.Dom.Element.appendChild
         (Webapi.Dom.Element.asNode status) popup)
        status))))

(defn- refresh-dropdown-item-roles! [renderer dropdown]
  (let [listbox (dropdown-listbox? renderer dropdown)]
    (doseq [item (retained/children (:web-store renderer) dropdown)]
      (if-some [current (retained/node (:web-store renderer) item)]
        (when (standard-kind? current MenuItem)
          (if listbox
            (do
              (Webapi.Dom.Element.setAttribute
               "role" "option" (:platform-node current))
              (Webapi.Dom.Element.setAttribute
               "aria-selected"
               (if (= (retained/property
                       (:web-store renderer) item Selected)
                      (Some (BoolValue true)))
                 "true"
                 "false")
               (:platform-node current)))
            (do
              (Webapi.Dom.Element.setAttribute
               "role" "menuitem" (:platform-node current))
              (Webapi.Dom.Element.removeAttribute
               "aria-selected" (:platform-node current)))))
        (Stdlib.ignore true)))
    true))

(defn- refresh-combobox-list-state! [renderer dropdown]
  (match (picker-for-dropdown renderer dropdown)
    (Some picker)
    (if-some [current (retained/node (:web-store renderer) picker)]
      (when (standard-kind? current Combobox)
        (let [items (picker-menu-items renderer dropdown)
              item-count (count items)
              empty (empty? items)
              root (:platform-node current)
              control (child-element root 0)
              trigger (child-element root 1)
              positioner (dom-node renderer dropdown)
              popup (child-element positioner 0)
              status (ensure-combobox-status! renderer dropdown)]
          (set-state-attribute! control "data-list-empty" empty)
          (set-state-attribute! trigger "data-list-empty" empty)
          (set-state-attribute! positioner "data-empty" empty)
          (set-state-attribute! popup "data-empty" empty)
          (Webapi.Dom.Element.setTextContent
           status
           (if empty
             "No results."
             (str item-count
                  (if (= item-count 1)
                    " result available."
                    " results available."))))
          (if empty
            (clear-combobox-active! renderer picker)
            (let [active (combobox-active-index renderer picker items)
                  index
                  (match active
                    (Some current-index) current-index
                    None 0)
                  expected-id (node-dom-id (nth items index))]
              (when-not
               (= (Webapi.Dom.Element.getAttribute
                   "aria-activedescendant" control)
                  (Some expected-id))
               (set-combobox-active! renderer picker dropdown index))))
          (when (Webapi.Dom.Element.hasAttribute "data-open" popup)
            (position-dropdown! renderer dropdown))))
      (Stdlib.ignore true))
    None (Stdlib.ignore true))
  true)

(defn- activate-menu-item! [renderer item]
  (Webapi.Dom.HtmlElement.click
   (Webapi.Dom.Element.unsafeAsHtmlElement (dom-node renderer item))))

(defn- attach-text-events! [renderer node kind dom-node]
  (let [composing (atom false)
        committed-composition (atom None)
        value!
        (fn []
          (Webapi.Dom.HtmlInputElement.value (text-control-node dom-node)))
        emit!
        (fn [value]
          (when
           (and
            (= kind Combobox)
            (= (retained/property
                (:web-store renderer) node PressEnabled)
               (Some (BoolValue true)))
            (= (picker-dropdown renderer node) None))
            (Stdlib.ignore
             ((deref (:web-event-handler renderer)) (proto/Press node))))
          (Stdlib.ignore
           ((deref (:web-event-handler renderer))
            (proto/TextChanged node value)))
          true)]
    (Webapi.Dom.Element.addEventListener
     "compositionstart"
     (fn [_event]
       (reset! composing true)
       (reset! committed-composition None)
       (Stdlib.ignore true))
     dom-node)
    (Webapi.Dom.Element.addEventListener
     "compositionend"
     (fn [_event]
       (let [value (value!)]
         (reset! composing false)
         (reset! committed-composition (Some value))
         (Stdlib.ignore (emit! value)))
       (Stdlib.ignore true))
     dom-node)
    (Webapi.Dom.Element.addEventListener
     "input"
     (fn [_event]
       (when-not (deref composing)
         (let [value (value!)]
           (match (deref committed-composition)
             (Some committed)
             (do
               (reset! committed-composition None)
               (when-not (= value committed)
                 (Stdlib.ignore (emit! value))))
             None (Stdlib.ignore (emit! value)))))
       (Stdlib.ignore true))
     dom-node)
    (Webapi.Dom.Element.addKeyDownEventListener
     (fn [event]
       (let [composing?
             (or (deref composing)
                 (Webapi.Dom.KeyboardEvent.isComposing event))
             enter (= "Enter" (Webapi.Dom.KeyboardEvent.key event))
             shift (Webapi.Dom.KeyboardEvent.shiftKey event)
             primary
             (or (Webapi.Dom.KeyboardEvent.metaKey event)
                 (Webapi.Dom.KeyboardEvent.ctrlKey event))
             submit
             (and
              (not composing?)
              (if enter
                (if (= kind Textarea)
                  (if (submit-on-enter? renderer node)
                    (not shift)
                    primary)
                  true)
                false))]
         (when (and submit (not (= kind Combobox)))
           (Webapi.Dom.KeyboardEvent.preventDefault event)
           (Stdlib.ignore
            ((deref (:web-event-handler renderer)) (proto/Submit node))))
         (when (and (= kind Combobox) (not composing?))
           (let [key (Webapi.Dom.KeyboardEvent.key event)
                 dropdown (picker-dropdown renderer node)]
             (cond
               (or (= key "ArrowDown") (= key "ArrowUp"))
               (do
                 (Webapi.Dom.KeyboardEvent.preventDefault event)
                 (match dropdown
                   (Some menu)
                   (let [items (picker-menu-items renderer menu)
                         current (combobox-active-index renderer node items)
                         navigation-key
                         (if (= key "ArrowDown") "ArrowRight" "ArrowLeft")]
                     (match (horizontal-focus-index
                             navigation-key current (count items))
                       (Some index)
                       (set-combobox-active! renderer node menu index)
                       None (Stdlib.ignore true)))
                   None
                   (Stdlib.ignore
                    ((deref (:web-event-handler renderer)) (proto/Press node)))))

               (= key "Enter")
               (do
                 (Webapi.Dom.KeyboardEvent.preventDefault event)
                 (match dropdown
                   (Some menu)
                   (let [items (picker-menu-items renderer menu)
                         current
                         (combobox-active-index renderer node items)]
                     (match current
                       (Some index)
                       (activate-menu-item! renderer (nth items index))
                       None
                       (when (not (empty? items))
                         (set-combobox-active! renderer node menu 0))))
                   None
                   (Stdlib.ignore
                    ((deref (:web-event-handler renderer))
                     (if (submit-enabled? renderer node)
                       (proto/Submit node)
                       (proto/Press node))))))

               (= key "Escape")
               (match dropdown
                 (Some menu)
                 (do
                   (Webapi.Dom.KeyboardEvent.preventDefault event)
                   (Stdlib.ignore
                    ((deref (:web-event-handler renderer))
                     (proto/Dismiss menu))))
                 None (Stdlib.ignore true))

               :else (Stdlib.ignore true))))
         (Stdlib.ignore true)))
     dom-node)))

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
     (when (event-capability? renderer node PressEnabled)
       (Stdlib.ignore
        ((deref (:web-event-handler renderer)) (proto/Press node))))
     (Stdlib.ignore true))
   dom-node))

(defn- attach-picker-trigger-events! [renderer node dom-node]
  (let [current-pointer-type (atom "mouse")
        suppress-click (atom false)
        press!
        (fn []
          (when (event-capability? renderer node PressEnabled)
            (Stdlib.ignore
             ((deref (:web-event-handler renderer)) (proto/Press node))))
          true)]
    (Webapi.Dom.Element.addEventListener
     "pointerdown"
     (fn [event]
       (let [method (pointer-type event)]
         (reset! current-pointer-type method)
         (Webapi.Dom.Element.setAttribute
          "data-lui-open-method" method dom-node))
       (Stdlib.ignore true))
     dom-node)
    (Webapi.Dom.Element.addEventListener
     "mousedown"
     (fn [event]
       (when (= (Webapi.Dom.MouseEvent.button
                 (pointer-mouse-event event)) 0)
         (Webapi.Dom.Element.setAttribute
          "data-lui-open-method" (deref current-pointer-type) dom-node)
         (when (= (deref current-pointer-type) "touch")
           (Webapi.Dom.Event.preventDefault event))
         (reset! suppress-click true)
         (Stdlib.ignore
          (Js.Global.setTimeout
           0
           :f
           (fn []
             (reset! suppress-click false)
             (Stdlib.ignore true))))
         (Stdlib.ignore (press!)))
       (Stdlib.ignore true))
     dom-node)
    (Webapi.Dom.Element.addEventListener
     "click"
     (fn [_event]
       (if (deref suppress-click)
         (Stdlib.ignore (reset! suppress-click false))
         (do
           (Webapi.Dom.Element.setAttribute
            "data-lui-open-method" "keyboard" dom-node)
           (Stdlib.ignore (press!))))
       (Stdlib.ignore true))
     dom-node)))

(defn- attach-accordion-event! [renderer node dom-node]
  (Webapi.Dom.Element.addEventListener
   "click"
   (fn [event]
     (Webapi.Dom.Event.preventDefault event)
     (when (= (retained/property (:web-store renderer) node ToggleEnabled)
              (Some (BoolValue true)))
       (let [selected
             (= (retained/property (:web-store renderer) node Selected)
                (Some (BoolValue true)))]
         (Stdlib.ignore
          ((deref (:web-event-handler renderer))
           (proto/ToggleChanged node (not selected))))))
     (Stdlib.ignore true))
   (accordion-trigger-node dom-node)))

(defn- event-capability? [renderer node property]
  (= (retained/property (:web-store renderer) node property)
     (Some (BoolValue true))))

(defn- treeitem? [renderer node]
  (= (retained/property (:web-store renderer) node RoleValue)
     (Some (StringValue "treeitem"))))

(defn- tree-ancestor [renderer node]
  (if-some [current (retained/node (:web-store renderer) node)]
    (match (:retained-parent current)
      (Some parent)
      (if-some [parent-node (retained/node (:web-store renderer) parent)]
        (if (standard-kind? parent-node Tree)
          (Some parent)
          (tree-ancestor renderer parent))
        None)
      None None)
    None))

(defn- tree-items-under [renderer parent]
  (reduce
   (fn [items child]
     (let [with-child (if (treeitem? renderer child)
                        (conj items child)
                        items)]
       (into with-child (tree-items-under renderer child))))
   []
   (retained/children (:web-store renderer) parent)))

(defn- tree-focus-items-under [renderer parent]
  (filterv
   (fn [node] (enabled-node? renderer node))
   (tree-items-under renderer parent)))

(defn- derived-tree-item-level [renderer tree current level]
  (if-some [state (retained/node (:web-store renderer) current)]
    (match (:retained-parent state)
      (Some parent)
      (if (= parent tree)
        level
        (derived-tree-item-level
         renderer tree parent
         (if (treeitem? renderer parent) (inc level) level)))
      None level)
    level))

(defn- tree-item-level [renderer tree node]
  (match (retained/property (:web-store renderer) node TreeLevel)
    (Some (IntValue level)) level
    _ (derived-tree-item-level renderer tree node 1)))

(defn- node-index [nodes node]
  (loop [index 0]
    (if (= index (count nodes))
      -1
      (if (= (nth nodes index) node)
        index
        (recur (inc index))))))

(defn- logical-tree-parent [renderer tree items node]
  (let [index (node-index items node)
        level (tree-item-level renderer tree node)]
    (loop [candidate (dec index)]
      (if (< candidate 0)
        None
        (let [candidate-node (nth items candidate)
              candidate-level (tree-item-level renderer tree candidate-node)]
          (if (= candidate-level (dec level))
            (Some candidate-node)
            (recur (dec candidate))))))))

(defn- logical-tree-child [renderer tree items node]
  (let [index (node-index items node)
        next-index (inc index)]
    (if (< next-index (count items))
      (let [candidate (nth items next-index)]
        (if (= (tree-item-level renderer tree candidate)
               (inc (tree-item-level renderer tree node)))
          (Some candidate)
          None))
      None)))

(defn- set-tree-tabstop! [renderer items target]
  (doseq [item items]
    (Webapi.Dom.Element.setAttribute
     "tabindex" (if (= item target) "0" "-1")
     (dom-node renderer item))))

(defn- dispatch-tree-selection! [renderer node]
  (Stdlib.ignore
   ((deref (:web-event-handler renderer))
    (if (event-capability? renderer node ChangeEnabled)
      (proto/Change node)
      (proto/Press node)))))

(defn- focus-tree-item! [renderer tree items node]
  (set-tree-tabstop! renderer items node)
  (Webapi.Dom.HtmlElement.focus
   (Webapi.Dom.Element.unsafeAsHtmlElement (dom-node renderer node)))
  (dispatch-tree-selection! renderer node))

(defn- refresh-tree-item-accessibility! [renderer tree node]
  (let [element (dom-node renderer node)]
    (Webapi.Dom.Element.setAttribute
     "aria-level" (str (tree-item-level renderer tree node)) element)
    (Webapi.Dom.Element.setAttribute
     "aria-disabled" (if (enabled-node? renderer node) "false" "true") element)
    (match (retained/property (:web-store renderer) node Selected)
      (Some (BoolValue selected))
      (Webapi.Dom.Element.setAttribute
       "aria-selected" (if selected "true" "false") element)
      _ (Webapi.Dom.Element.removeAttribute "aria-selected" element))
    (match (retained/property (:web-store renderer) node Expanded)
      (Some (BoolValue expanded))
      (Webapi.Dom.Element.setAttribute
       "aria-expanded" (if expanded "true" "false") element)
      _ (Webapi.Dom.Element.removeAttribute "aria-expanded" element))))

(defn- update-tree-roving! [renderer tree]
  (let [all-items (tree-items-under renderer tree)
        items (tree-focus-items-under renderer tree)]
    (doseq [item all-items]
      (refresh-tree-item-accessibility! renderer tree item)
      (Webapi.Dom.Element.setAttribute "tabindex" "-1" (dom-node renderer item)))
    (when (not (empty? items))
      (let [selected
            (loop [index 0]
              (if (= index (count items))
                (nth items 0)
                (let [item (nth items index)]
                  (if (= (retained/property
                          (:web-store renderer) item Selected)
                         (Some (BoolValue true)))
                    item
                    (recur (inc index))))))
            document
            (Webapi.Dom.Document.unsafeAsHtmlDocument (:web-document renderer))
            active-index
            (if-some [focused (Webapi.Dom.HtmlDocument.activeElement document)]
              (focused-child-index renderer items focused 0)
              None)
            target
            (match active-index
              (Some index) (nth items index)
              None selected)]
        (set-tree-tabstop! renderer items target)))))

(defn- update-all-tree-roving! [renderer]
  (reduce-kv
   (fn [_updated node current]
     (when (standard-kind? current Tree)
       (update-tree-roving! renderer node))
     true)
   true
   (retained/nodes (:web-store renderer))))

(defn- cancel-typeahead! [typeahead-timer]
  (match (deref typeahead-timer)
    (Some timer-id) (Js.Global.clearTimeout timer-id)
    None (Stdlib.ignore true))
  (reset! typeahead-timer None)
  true)

(defn- reset-typeahead-later! [typeahead-buffer typeahead-timer]
  (cancel-typeahead! typeahead-timer)
  (reset!
   typeahead-timer
   (Some
    (Js.Global.setTimeout
     500
     :f
     (fn []
       (reset! typeahead-timer None)
       (reset! typeahead-buffer "")
       (Stdlib.ignore true)))))
  true)

(defn- attach-tree-item-events! [renderer node kind dom-node]
  (when (not (= kind ListItem))
    (Webapi.Dom.Element.addEventListener
     "click"
     (fn [_event]
       (when (and (treeitem? renderer node)
                  (event-capability? renderer node PressEnabled))
         (Stdlib.ignore
          ((deref (:web-event-handler renderer)) (proto/Press node))))
       (Stdlib.ignore true))
     dom-node))
  (Webapi.Dom.Element.addKeyDownEventListener
   (fn [event]
     (when (treeitem? renderer node)
       (match (tree-ancestor renderer node)
         (Some tree)
         (let [items (tree-focus-items-under renderer tree)
               index (node-index items node)
               key (Webapi.Dom.KeyboardEvent.key event)
               target
               (cond
                 (= key "ArrowUp")
                 (if (> index 0) (Some (nth items (dec index))) None)
                 (= key "ArrowDown")
                 (if (< (inc index) (count items))
                   (Some (nth items (inc index))) None)
                 (= key "Home") (Some (nth items 0))
                 (= key "End") (Some (nth items (dec (count items))))
                 :else None)]
           (if-some [target-node target]
             (do
               (Webapi.Dom.KeyboardEvent.preventDefault event)
               (focus-tree-item! renderer tree items target-node))
             (cond
               (= key "ArrowLeft")
               (do
                 (Webapi.Dom.KeyboardEvent.preventDefault event)
                 (if (and
                      (= (retained/property
                          (:web-store renderer) node Expanded)
                         (Some (BoolValue true)))
                      (event-capability? renderer node ToggleEnabled))
                   (Stdlib.ignore
                    ((deref (:web-event-handler renderer))
                     (proto/ToggleChanged node false)))
                   (match (logical-tree-parent renderer tree items node)
                     (Some parent)
                     (focus-tree-item! renderer tree items parent)
                     None (Stdlib.ignore true))))
               (= key "ArrowRight")
               (do
                 (Webapi.Dom.KeyboardEvent.preventDefault event)
                 (if (and
                      (= (retained/property
                          (:web-store renderer) node Expanded)
                         (Some (BoolValue false)))
                      (event-capability? renderer node ToggleEnabled))
                   (Stdlib.ignore
                    ((deref (:web-event-handler renderer))
                     (proto/ToggleChanged node true)))
                   (match (logical-tree-child renderer tree items node)
                     (Some child)
                     (focus-tree-item! renderer tree items child)
                     None (Stdlib.ignore true))))
               (and
                (not (= kind ListItem))
                (or (= key "Enter") (= key " ")))
               (do
                 (Webapi.Dom.KeyboardEvent.preventDefault event)
                 (when (event-capability? renderer node PressEnabled)
                   (Stdlib.ignore
                    ((deref (:web-event-handler renderer))
                     (proto/Press node)))))
               :else (Stdlib.ignore true))))
         None (Stdlib.ignore true)))
     (Stdlib.ignore true))
   dom-node))

(defn- attach-tree-events! [renderer tree tree-node]
  (let [typeahead-buffer (atom "")
        typeahead-timer (atom None)
        key-handler
        (fn [event]
          (let [key (Webapi.Dom.KeyboardEvent.key event)]
            (when
             (and (= (String.length key) 1)
                  (not (= (string/trim key) ""))
                  (not (Webapi.Dom.KeyboardEvent.isComposing event))
                  (not (Webapi.Dom.KeyboardEvent.metaKey event))
                  (not (Webapi.Dom.KeyboardEvent.ctrlKey event))
                  (not (Webapi.Dom.KeyboardEvent.altKey event)))
              (let [items (tree-focus-items-under renderer tree)
                    document
                    (Webapi.Dom.Document.unsafeAsHtmlDocument
                     (:web-document renderer))
                    current-index
                    (if-some [focused
                              (Webapi.Dom.HtmlDocument.activeElement document)]
                      (focused-child-index renderer items focused 0)
                      None)
                    query
                    (String.lowercase_ascii
                     (str (deref typeahead-buffer) key))
                    start
                    (match current-index
                      (Some index) index
                      None -1)]
                (reset! typeahead-buffer query)
                (reset-typeahead-later!
                 typeahead-buffer typeahead-timer)
                (loop [offset 1]
                  (when (<= offset (count items))
                    (let [index (mod (+ start offset) (count items))
                          item (nth items index)
                          label
                          (String.lowercase_ascii
                           (string/trim
                            (Webapi.Dom.Element.textContent
                             (dom-node renderer item))))]
                      (if (string/starts-with? label query)
                        (do
                          (Webapi.Dom.KeyboardEvent.preventDefault event)
                          (focus-tree-item! renderer tree items item))
                        (recur (inc offset)))))))))
          (Stdlib.ignore true))]
    (Webapi.Dom.Element.addKeyDownEventListener key-handler tree-node)
    (swap!
     (:web-cleanups renderer)
     assoc
     tree
     (fn []
       (cancel-typeahead! typeahead-timer)
       (Webapi.Dom.Element.removeKeyDownEventListener key-handler tree-node)
       (Stdlib.ignore true)))
    (Stdlib.ignore true)))

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
     (when (and
            (treeitem? renderer node)
            (event-capability? renderer node ToggleEnabled))
       (match (retained/property (:web-store renderer) node Expanded)
         (Some (BoolValue expanded))
         (Stdlib.ignore
          ((deref (:web-event-handler renderer))
           (proto/ToggleChanged node (not expanded))))
         _ (Stdlib.ignore true)))
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
    (let [target
          (Webapi.Dom.EventTarget.unsafeAsElement
           (Webapi.Dom.Event.target event))]
      (or
       (Webapi.Dom.Element.contains
        (Webapi.Dom.Element.asNode target)
        (:platform-node current))
       (match (:retained-parent current)
         (Some parent)
         (Webapi.Dom.Element.contains
          (Webapi.Dom.Element.asNode target)
          (dom-node renderer parent))
         None false)))
    false))

(defn- cleanup-node! [renderer node]
  (if-some [cleanup (clojure.core/get (deref (:web-cleanups renderer)) node)]
    (do
      (cleanup)
      (Stdlib.ignore (swap! (:web-cleanups renderer) dissoc node)))
    (Stdlib.ignore true)))

(defn- topmost-modal? [renderer node]
  (let [stack (deref (:web-modal-stack renderer))]
    (and (not (empty? stack)) (= node (nth stack (dec (count stack)))))))

(defn- remove-modal-from-stack! [renderer node]
  (swap!
   (:web-modal-stack renderer)
   (fn [stack]
     (into [] (filter (fn [current] (not (= current node))) stack)))))

(defn- refresh-modal-host-inert! [renderer]
  (set-state-attribute!
   (:web-host renderer) "inert" (not (empty? (deref (:web-modal-stack renderer)))))
  true)

(defn- modal-focus-items [renderer parent]
  (let [nodes
        (Webapi.Dom.Element.querySelectorAll
         (str
          "button:not([disabled]):not([hidden]),"
          "input:not([disabled]):not([hidden]),"
          "textarea:not([disabled]):not([hidden]),"
          "select:not([disabled]):not([hidden]),"
          "[tabindex]:not([tabindex=\"-1\"]):not([disabled]):not([hidden])")
         (dom-node renderer parent))]
    (loop [index 0
           result []]
      (if (= index (node-list/length nodes))
        result
        (if-some [candidate (node-list/item index nodes)]
          (if-some [candidate-element (Webapi.Dom.Element.ofNode candidate)]
            (recur (inc index) (conj result candidate-element))
            (recur (inc index) result))
          (recur (inc index) result))))))

(defn- focused-element-index [elements focused]
  (loop [index 0]
    (if (= index (count elements))
      -1
      (if (Webapi.Dom.Element.isSameNode
           (Webapi.Dom.Element.asNode (nth elements index)) focused)
        index
        (recur (inc index))))))

(defn- swipe-ignored-target? [target boundary]
  (if (Webapi.Dom.Element.isSameNode
       (Webapi.Dom.Element.asNode target) boundary)
    false
    (let [role (Webapi.Dom.Element.getAttribute "role" target)
          class-name (Webapi.Dom.Element.getAttribute "class" target)
          ignored
          (or (Webapi.Dom.Element.hasAttribute
               "data-lui-swipe-ignore" target)
              (Webapi.Dom.Element.hasAttribute "type" target)
              (Webapi.Dom.Element.hasAttribute "href" target)
              (= role (Some "button"))
              (match class-name
                (Some value)
                (or (string/includes? value "lui-textarea")
                    (string/includes? value "lui-input"))
                None false))]
      (if ignored
        true
        (if-some [parent (Webapi.Dom.Element.parentElement target)]
          (swipe-ignored-target? parent boundary)
          false)))))

(defn- attach-modal-events! [renderer node dom-node]
  (let [document (:web-document renderer)
        html-document (Webapi.Dom.Document.unsafeAsHtmlDocument document)
        previous-focus (Webapi.Dom.HtmlDocument.activeElement html-document)
        layer (modal-layer-node dom-node)
        backdrop (child-element layer 0)
        sheet?
        (if-some [current (retained/node (:web-store renderer) node)]
          (standard-kind? current Sheet)
          false)
        swipe-pointer (atom None)
        swipe-start-x (atom 0.0)
        swipe-start-y (atom 0.0)
        swipe-current-y (atom 0.0)
        reset-swipe!
        (fn []
          (reset! swipe-pointer None)
          (Webapi.Dom.Element.removeAttribute "data-swiping" dom-node)
          (Webapi.Dom.Element.removeAttribute "data-swipe-direction" dom-node)
          (set-style! dom-node "--drawer-swipe-movement-y" "0px")
          true)
        dismiss!
        (fn []
          (when (and
                 (topmost-modal? renderer node)
                 (= (Webapi.Dom.Element.getAttribute
                     "data-lui-modal-state" layer)
                    (Some "open")))
            (Stdlib.ignore
             ((deref (:web-event-handler renderer)) (proto/Dismiss node))))
          true)
        pointer-down!
        (fn [event]
          (let [target
                (Webapi.Dom.EventTarget.unsafeAsElement
                 (Webapi.Dom.Event.target event))
                root (Webapi.Dom.Document.documentElement document)
                compact (<= (Webapi.Dom.Element.clientWidth root) 640)
                ignored (swipe-ignored-target? target dom-node)]
            (when (and sheet? compact
                       (= (pointer-type event) "touch")
                       (= (Webapi.Dom.MouseEvent.button
                           (pointer-mouse-event event)) 0)
                       (not ignored))
              (let [x (Stdlib.float_of_int
                       (Webapi.Dom.MouseEvent.clientX
                        (pointer-mouse-event event)))
                    y (Stdlib.float_of_int
                       (Webapi.Dom.MouseEvent.clientY
                        (pointer-mouse-event event)))]
                (reset! swipe-pointer (Some (pointer-id event)))
                (reset! swipe-start-x x)
                (reset! swipe-start-y y)
                (reset! swipe-current-y y)
                (Stdlib.ignore true))))
          (Stdlib.ignore true))
        pointer-move!
        (fn [event]
          (match (deref swipe-pointer)
            (Some active-pointer-id)
            (when (= active-pointer-id (pointer-id event))
              (let [delta-x
                    (Float.abs
                     (- (Stdlib.float_of_int
                         (Webapi.Dom.MouseEvent.clientX
                          (pointer-mouse-event event)))
                        (deref swipe-start-x)))
                    delta-y
                    (max 0.0
                         (- (Stdlib.float_of_int
                             (Webapi.Dom.MouseEvent.clientY
                              (pointer-mouse-event event)))
                            (deref swipe-start-y)))]
                (when (and (> delta-y 4.0) (> delta-y delta-x))
                  (Webapi.Dom.Event.preventDefault event)
                  (reset!
                   swipe-current-y
                   (Stdlib.float_of_int
                    (Webapi.Dom.MouseEvent.clientY
                     (pointer-mouse-event event))))
                  (Webapi.Dom.Element.setAttribute "data-swiping" "" dom-node)
                  (Webapi.Dom.Element.setAttribute
                   "data-swipe-direction" "down" dom-node)
                  (set-style!
                   dom-node "--drawer-swipe-movement-y"
                   (str delta-y "px")))))
            None (Stdlib.ignore true))
          (Stdlib.ignore true))
        pointer-end!
        (fn [event]
          (match (deref swipe-pointer)
            (Some active-pointer-id)
            (when (= active-pointer-id (pointer-id event))
              (let [delta
                    (max 0.0
                         (- (deref swipe-current-y) (deref swipe-start-y)))
                    threshold
                    (max 96.0
                         (* 0.25
                            (Stdlib.float_of_int
                             (Webapi.Dom.Element.clientHeight dom-node))))]
                (reset-swipe!)
                (when (> delta threshold)
                  (Stdlib.ignore (dismiss!)))))
            None (Stdlib.ignore true))
          (Stdlib.ignore true))
        pointer-cancel!
        (fn [event]
          (match (deref swipe-pointer)
            (Some active-pointer-id)
            (when (= active-pointer-id (pointer-id event))
              (Stdlib.ignore (reset-swipe!)))
            None (Stdlib.ignore true))
          (Stdlib.ignore true))
        click-handler
        (fn [_event]
          (dismiss!)
          (Stdlib.ignore true))
        key-handler
        (fn [event]
          (when (topmost-modal? renderer node)
            (let [key (Webapi.Dom.KeyboardEvent.key event)]
              (if (= "Escape" key)
                (do
                  (Webapi.Dom.KeyboardEvent.preventDefault event)
                  (dismiss!))
                (do
                  (when (= "Tab" key)
                    (let [items (modal-focus-items renderer node)
                          focused
                          (Webapi.Dom.EventTarget.unsafeAsElement
                           (Webapi.Dom.KeyboardEvent.target event))
                          index (focused-element-index items focused)
                          backwards (Webapi.Dom.KeyboardEvent.shiftKey event)]
                      (when (and
                             (not (empty? items))
                             (or (= index -1)
                                 (and backwards (= index 0))
                                 (and (not backwards)
                                      (= index (dec (count items))))))
                        (Webapi.Dom.KeyboardEvent.preventDefault event)
                        (focus-element!
                         (if backwards
                           (nth items (dec (count items)))
                           (nth items 0))))))
                  true))))
          (Stdlib.ignore true))]
    (Webapi.Dom.Element.addEventListener "click" click-handler backdrop)
    (when sheet?
      (Webapi.Dom.Element.addEventListener "pointerdown" pointer-down! dom-node)
      (Webapi.Dom.Element.addEventListener "pointermove" pointer-move! dom-node)
      (Webapi.Dom.Element.addEventListener "pointerup" pointer-end! dom-node)
      (Webapi.Dom.Element.addEventListener
       "pointercancel" pointer-cancel! dom-node))
    (Webapi.Dom.Document.addKeyDownEventListener key-handler document)
    (swap!
     (:web-cleanups renderer)
     assoc node
     (fn []
       (remove-modal-from-stack! renderer node)
       (Webapi.Dom.Element.setAttribute
        "data-lui-modal-state" "closed" layer)
       (Webapi.Dom.Element.removeAttribute "data-open" layer)
       (Webapi.Dom.Element.setAttribute "data-closed" "" layer)
       (Webapi.Dom.Element.setAttribute "data-ending-style" "" layer)
       (Webapi.Dom.Element.removeAttribute "data-open" dom-node)
       (Webapi.Dom.Element.setAttribute "data-closed" "" dom-node)
       (Webapi.Dom.Element.setAttribute "data-ending-style" "" dom-node)
       (Webapi.Dom.Element.setAttribute "inert" "" layer)
       (refresh-modal-host-inert! renderer)
       (Webapi.Dom.Element.removeEventListener "click" click-handler backdrop)
       (when sheet?
         (reset-swipe!)
         (Webapi.Dom.Element.removeEventListener
          "pointerdown" pointer-down! dom-node)
         (Webapi.Dom.Element.removeEventListener
          "pointermove" pointer-move! dom-node)
         (Webapi.Dom.Element.removeEventListener
          "pointerup" pointer-end! dom-node)
         (Webapi.Dom.Element.removeEventListener
          "pointercancel" pointer-cancel! dom-node))
       (Webapi.Dom.Document.removeKeyDownEventListener key-handler document)
       (match previous-focus
         (Some element)
         (Webapi.Dom.HtmlElement.focus
          (Webapi.Dom.Element.unsafeAsHtmlElement element))
         None (Stdlib.ignore true))
       (Stdlib.ignore true)))
    (Stdlib.ignore true)))

(defn- attach-dropdown-events! [renderer node _dropdown-node]
  (let [document (:web-document renderer)
        window
        (Webapi.Dom.HtmlDocument.defaultView
         (Webapi.Dom.Document.unsafeAsHtmlDocument document))
        typeahead-buffer (atom "")
        typeahead-timer (atom None)
        refresh-position!
        (fn [_event]
          (Webapi.requestAnimationFrame
           (fn [_time]
             (if-some [_current
                       (retained/node (:web-store renderer) node)]
               (position-dropdown! renderer node)
               (Stdlib.ignore true))))
          (Stdlib.ignore true))
        pointer-handler
        (fn [event]
          (when (not (dropdown-group-contains-event? renderer node event))
            (Stdlib.ignore
             ((deref (:web-event-handler renderer)) (proto/Dismiss node))))
          (refresh-position! event)
          (Stdlib.ignore true))
        key-handler
        (fn [event]
          (let [key (Webapi.Dom.KeyboardEvent.key event)
                items (context-menu-focus-items renderer node)
                event-target
                (Webapi.Dom.EventTarget.unsafeAsElement
                 (Webapi.Dom.KeyboardEvent.target event))
                current-index
                (focused-child-index renderer items event-target 0)
                parent
                (if-some [current
                          (retained/node (:web-store renderer) node)]
                  (:retained-parent current)
                  None)
                submenu-trigger
                (match parent
                  (Some candidate)
                  (if-some [candidate-node
                            (retained/node (:web-store renderer) candidate)]
                    (if (standard-kind? candidate-node MenuItem)
                      (Some candidate)
                      None)
                    None)
                  None None)]
            (when (not (= current-index None))
              (cond
              (or (= key "ArrowDown") (= key "ArrowUp")
                  (= key "Home") (= key "End"))
              (let [navigation-key
                    (if (= key "ArrowDown")
                      "ArrowRight"
                      (if (= key "ArrowUp") "ArrowLeft" key))]
                (match
                 (horizontal-focus-index
                  navigation-key current-index (count items))
                  (Some index)
                  (do
                    (Webapi.Dom.KeyboardEvent.preventDefault event)
                    (focus-context-menu-item! renderer node index))
                  None (Stdlib.ignore true)))

              (= key "ArrowRight")
              (match current-index
                (Some index)
                (match (direct-dropdown-menu renderer (nth items index))
                  (Some submenu)
                  (do
                    (Webapi.Dom.KeyboardEvent.preventDefault event)
                    (set-dropdown-open! renderer submenu true)
                    (focus-context-menu-item! renderer submenu 0))
                  None (Stdlib.ignore true))
                None (Stdlib.ignore true))

              (and (= key "ArrowLeft") (not (= submenu-trigger None)))
              (match submenu-trigger
                (Some trigger)
                (do
                  (Webapi.Dom.KeyboardEvent.preventDefault event)
                  (Webapi.Dom.HtmlElement.focus
                   (Webapi.Dom.Element.unsafeAsHtmlElement
                    (dom-node renderer trigger)))
                  (set-dropdown-open! renderer node false)
                  (Webapi.Dom.Element.setAttribute
                   "aria-expanded" "false" (dom-node renderer trigger)))
                None (Stdlib.ignore true))

              (= key "Escape")
              (do
                (Webapi.Dom.KeyboardEvent.preventDefault event)
                (match submenu-trigger
                  (Some trigger)
                  (do
                    (Webapi.Dom.HtmlElement.focus
                     (Webapi.Dom.Element.unsafeAsHtmlElement
                      (dom-node renderer trigger)))
                    (set-dropdown-open! renderer node false)
                    (Webapi.Dom.Element.setAttribute
                     "aria-expanded" "false" (dom-node renderer trigger)))
                  None
                  (Stdlib.ignore
                   ((deref (:web-event-handler renderer))
                    (proto/Dismiss node)))))

              (and (= (String.length key) 1)
                   (not (Webapi.Dom.KeyboardEvent.metaKey event))
                   (not (Webapi.Dom.KeyboardEvent.ctrlKey event)))
              (let [query
                    (String.lowercase_ascii
                     (str (deref typeahead-buffer) key))
                    start
                    (match current-index
                      (Some index) index
                      None -1)]
                (reset! typeahead-buffer query)
                (reset-typeahead-later!
                 typeahead-buffer typeahead-timer)
                (loop [offset 1]
                  (when (<= offset (count items))
                    (let [index (mod (+ start offset) (count items))
                          label
                          (String.lowercase_ascii
                           (string/trim
                            (Webapi.Dom.Element.textContent
                             (dom-node renderer (nth items index)))))]
                      (if (string/starts-with? label query)
                        (do
                          (Webapi.Dom.KeyboardEvent.preventDefault event)
                          (focus-context-menu-item! renderer node index))
                        (recur (inc offset)))))))

                :else (Stdlib.ignore true))))
          (Stdlib.ignore true))]
    (Webapi.Dom.Document.addEventListener
     "pointerdown" pointer-handler document)
    (Webapi.Dom.Document.addEventListener
     "click" refresh-position! document)
    (match window
      (Some current-window)
      (Webapi.Dom.Window.addEventListener
       "resize" refresh-position! current-window)
      None (Stdlib.ignore true))
    (Webapi.Dom.Document.addKeyDownEventListener key-handler document)
    (swap!
     (:web-cleanups renderer)
     assoc
     node
     (fn []
       (cancel-typeahead! typeahead-timer)
       (Webapi.Dom.Document.removeEventListener
        "pointerdown" pointer-handler document)
       (Webapi.Dom.Document.removeEventListener
        "click" refresh-position! document)
       (match window
         (Some current-window)
         (Webapi.Dom.Window.removeEventListener
          "resize" refresh-position! current-window)
         None (Stdlib.ignore true))
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
    ToggleGroup (or (= child-kind Button) (= child-kind ToggleButton))
    Breadcrumb (= child-kind Button)
    Pagination (= child-kind Button)
    _ false))

(defn- enabled-node? [renderer node]
  (not (= (retained/property (:web-store renderer) node Enabled)
          (Some (BoolValue false)))))

(defn- horizontal-all-focus-children [renderer node kind]
  (into
   []
   (filter
    (fn [child]
      (if-some [current (retained/node (:web-store renderer) child)]
        (match (retained/standard-kind current)
          (Some child-kind) (horizontal-group-child? kind child-kind)
          None false)
        false))
    (retained/children (:web-store renderer) node))))

(defn- horizontal-focus-children [renderer node kind]
  (into
   []
   (filter
    (fn [child] (enabled-node? renderer child))
    (horizontal-all-focus-children renderer node kind))))

(defn- focused-child-index [renderer children focused index]
  (if (>= index (count children))
    None
    (if (Webapi.Dom.Element.isSameNode
         (Webapi.Dom.Element.asNode (dom-node renderer (nth children index)))
         focused)
      (Some index)
      (focused-child-index renderer children focused (+ index 1)))))

(defn- horizontal-tab-stop-index [renderer children index]
  (if (>= index (count children))
    None
    (if (= (Webapi.Dom.Element.getAttribute
            "tabindex" (dom-node renderer (nth children index)))
           (Some "0"))
      (Some index)
      (horizontal-tab-stop-index renderer children (+ index 1)))))

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

(defn- element-direction [renderer element]
  (let [document
        (Webapi.Dom.Document.unsafeAsHtmlDocument (:web-document renderer))]
    (if-some [window (Webapi.Dom.HtmlDocument.defaultView document)]
      (Webapi.Dom.CssStyleDeclaration.direction
       (Webapi.Dom.Window.getComputedStyle element window))
      "ltr")))

(defn- refresh-horizontal-group-roving! [renderer node kind]
  (let [all-children (horizontal-all-focus-children renderer node kind)
        children (horizontal-focus-children renderer node kind)
        document
        (Webapi.Dom.Document.unsafeAsHtmlDocument (:web-document renderer))
        focused-index
        (if-some [focused (Webapi.Dom.HtmlDocument.activeElement document)]
          (focused-child-index renderer children focused 0)
          None)
        target
        (match focused-index
          (Some index) index
          None
          (match (horizontal-tab-stop-index renderer children 0)
            (Some index) index
            None 0))]
    (doseq [child all-children]
      (Webapi.Dom.Element.setAttribute
       "tabindex" "-1" (dom-node renderer child)))
    (when (not (empty? children))
      (Webapi.Dom.Element.setAttribute
       "tabindex" "0" (dom-node renderer (nth children target))))
    true))

(defn- horizontal-focus-kind? [kind]
  (or (= kind Tabs) (= kind ButtonGroup) (= kind ToggleGroup)
      (= kind Breadcrumb) (= kind Pagination)))

(defn- update-all-horizontal-group-roving! [renderer]
  (reduce-kv
   (fn [_updated node current]
     (match (retained/standard-kind current)
       (Some kind)
       (do
         (when (horizontal-focus-kind? kind)
           (refresh-horizontal-group-roving! renderer node kind))
         true)
       None true)
     true)
   true
   (retained/nodes (:web-store renderer))))

(defn- attach-horizontal-focus! [renderer node kind group-node]
  (Webapi.Dom.Element.addFocusInEventListener
   (fn [_event]
     (refresh-horizontal-group-roving! renderer node kind)
     (Stdlib.ignore true))
   group-node)
  (Webapi.Dom.Element.addKeyDownEventListener
   (fn [event]
     (let [key (Webapi.Dom.KeyboardEvent.key event)
           orientation
           (if (= kind Tabs)
             (match (retained/property
                     (:web-store renderer) node OrientationValue)
               (Some (StringValue value)) value
               _ "horizontal")
             "horizontal")
           direction (element-direction renderer group-node)
           forward-key
           (if (= orientation "vertical")
             "ArrowDown"
             (if (= direction "rtl") "ArrowLeft" "ArrowRight"))
           backward-key
           (if (= orientation "vertical")
             "ArrowUp"
             (if (= direction "rtl") "ArrowRight" "ArrowLeft"))
           navigation-key
           (cond
             (= key forward-key) "ArrowRight"
             (= key backward-key) "ArrowLeft"
             (= key "Home") "Home"
             (= key "End") "End"
             :else "")
           children (horizontal-focus-children renderer node kind)
           document
           (Webapi.Dom.Document.unsafeAsHtmlDocument (:web-document renderer))
           current
           (if-some [focused (Webapi.Dom.HtmlDocument.activeElement document)]
             (focused-child-index renderer children focused 0)
             None)]
       (match (horizontal-focus-index navigation-key current (count children))
         (Some index)
         (do
           (Webapi.Dom.KeyboardEvent.preventDefault event)
           (Webapi.Dom.HtmlElement.focus
            (Webapi.Dom.Element.unsafeAsHtmlElement
             (dom-node renderer (nth children index)))))
         None (Stdlib.ignore true))
       (Stdlib.ignore true)))
   group-node))

(defn- toolbar-item-kind? [kind]
  (or (= kind Button) (= kind ToggleButton) (= kind Toggle)
      (= kind Checkbox) (= kind SwitchControl) (= kind Radio)
      (= kind Select) (= kind Combobox) (= kind TextField)
      (= kind Input) (= kind SearchField)))

(defn- toolbar-all-items-under [renderer parent]
  (reduce
   (fn [items child]
     (if-some [current (retained/node (:web-store renderer) child)]
       (if (toolbar-item-kind? (standard-kind current))
         (conj items child)
         (into items (toolbar-all-items-under renderer child)))
       items))
   []
   (retained/children (:web-store renderer) parent)))

(defn- toolbar-items-under [renderer parent]
  (into
   []
   (filter
    (fn [item] (enabled-node? renderer item))
    (toolbar-all-items-under renderer parent))))

(defn- toolbar-focus-node [store node]
  (if-some [current (retained/node store node)]
    (let [kind (standard-kind current)
          platform-node (:platform-node current)]
      (if (or (direct-toggle? kind) (= kind Combobox))
        (child-element platform-node 0)
        platform-node))
    (raise (Invalid_argument "unknown toolbar item"))))

(defn- toolbar-text-input-kind? [kind]
  (or (= kind TextField) (= kind Input) (= kind SearchField)
      (= kind Combobox)))

(defn- focused-toolbar-item-index [store items focused index]
  (if (>= index (count items))
    None
    (if (Webapi.Dom.Element.isSameNode
         (Webapi.Dom.Element.asNode
          (toolbar-focus-node store (nth items index)))
         focused)
      (Some index)
      (focused-toolbar-item-index store items focused (+ index 1)))))

(defn- toolbar-input-owns-key? [store item event forward-key backward-key]
  (if-some [current (retained/node store item)]
    (if (toolbar-text-input-kind? (standard-kind current))
      (let [control (text-control-node (:platform-node current))
            start (Webapi.Dom.HtmlInputElement.selectionStart control)
            end (Webapi.Dom.HtmlInputElement.selectionEnd control)
            length (count (Webapi.Dom.HtmlInputElement.value control))
            key (Webapi.Dom.KeyboardEvent.key event)]
        (or
         (Webapi.Dom.KeyboardEvent.isComposing event)
         (Webapi.Dom.KeyboardEvent.shiftKey event)
         (Webapi.Dom.KeyboardEvent.ctrlKey event)
         (Webapi.Dom.KeyboardEvent.altKey event)
         (Webapi.Dom.KeyboardEvent.metaKey event)
         (not (= start end))
         (and (= key forward-key) (< end length))
         (and (= key backward-key) (> start 0))
         (and (> length 0) (or (= key "Home") (= key "End")))))
      false)
    false))

(defn- select-toolbar-input! [store item]
  (if-some [current (retained/node store item)]
    (when (toolbar-text-input-kind? (standard-kind current))
      (let [control (text-control-node (:platform-node current))]
        (Webapi.Dom.HtmlInputElement.setSelectionRange
         0 (count (Webapi.Dom.HtmlInputElement.value control)) control)))
    (Stdlib.ignore true)))

(defn- refresh-toolbar-roving! [renderer toolbar]
  (let [all-items (toolbar-all-items-under renderer toolbar)
        items (toolbar-items-under renderer toolbar)
        document
        (Webapi.Dom.Document.unsafeAsHtmlDocument (:web-document renderer))
        active
        (if-some [focused (Webapi.Dom.HtmlDocument.activeElement document)]
          (focused-toolbar-item-index (:web-store renderer) items focused 0)
          None)
        target
        (match active
          (Some index) index
          None 0)]
    (loop [index 0]
      (when (< index (count all-items))
        (Webapi.Dom.Element.setAttribute
         "tabindex" "-1"
         (toolbar-focus-node (:web-store renderer) (nth all-items index)))
        (recur (inc index))))
    (loop [index 0]
      (when (< index (count items))
        (Webapi.Dom.Element.setAttribute
         "tabindex" (if (= index target) "0" "-1")
         (toolbar-focus-node (:web-store renderer) (nth items index)))
        (recur (inc index))))
    true))

(defn- update-all-toolbar-roving! [renderer]
  (reduce-kv
   (fn [_updated node current]
     (when (standard-kind? current Toolbar)
       (refresh-toolbar-roving! renderer node))
     true)
   true
   (retained/nodes (:web-store renderer))))

(defn- attach-toolbar-events! [renderer node toolbar-node]
  (Webapi.Dom.Element.addFocusInEventListener
   (fn [_event]
     (let [items (toolbar-items-under renderer node)
           document
           (Webapi.Dom.Document.unsafeAsHtmlDocument (:web-document renderer))]
       (if-some [focused (Webapi.Dom.HtmlDocument.activeElement document)]
         (match
          (focused-toolbar-item-index (:web-store renderer) items focused 0)
          (Some index)
          (do
            (refresh-toolbar-roving! renderer node)
            (select-toolbar-input! (:web-store renderer) (nth items index)))
          None (Stdlib.ignore true))
         (Stdlib.ignore true))
       (Stdlib.ignore true)))
   toolbar-node)
  (Webapi.Dom.Element.addKeyDownEventListener
   (fn [event]
     (let [key (Webapi.Dom.KeyboardEvent.key event)
           orientation
           (match (retained/property
                   (:web-store renderer) node OrientationValue)
             (Some (StringValue value)) value
             _ "horizontal")
           direction (element-direction renderer toolbar-node)
           forward-key
           (if (= orientation "vertical")
             "ArrowDown"
             (if (= direction "rtl") "ArrowLeft" "ArrowRight"))
           backward-key
           (if (= orientation "vertical")
             "ArrowUp"
             (if (= direction "rtl") "ArrowRight" "ArrowLeft"))
           navigation-key
           (cond
             (= key forward-key) "ArrowRight"
             (= key backward-key) "ArrowLeft"
             (= key "Home") "Home"
             (= key "End") "End"
             :else "")
           items (toolbar-items-under renderer node)
           document
           (Webapi.Dom.Document.unsafeAsHtmlDocument (:web-document renderer))
           current
           (if-some [focused (Webapi.Dom.HtmlDocument.activeElement document)]
             (focused-toolbar-item-index
              (:web-store renderer) items focused 0)
             None)]
       (when
        (and
         (not (= navigation-key ""))
         (not
          (match current
            (Some index)
            (toolbar-input-owns-key?
             (:web-store renderer) (nth items index) event
             forward-key backward-key)
            None false)))
         (match (horizontal-focus-index navigation-key current (count items))
           (Some index)
           (do
             (Webapi.Dom.KeyboardEvent.preventDefault event)
             (Webapi.Dom.HtmlElement.focus
              (Webapi.Dom.Element.unsafeAsHtmlElement
               (toolbar-focus-node
                (:web-store renderer) (nth items index)))))
           None (Stdlib.ignore true)))
       (Stdlib.ignore true)))
   toolbar-node))

(defn- direct-context-menu [renderer node]
  (if-some [current (retained/node (:web-store renderer) node)]
    (loop [index 0]
      (if (= index (count (:retained-children current)))
        None
        (let [child (nth (:retained-children current) index)]
          (if-some [child-node (retained/node (:web-store renderer) child)]
            (if (and
                 (standard-kind? child-node ContextMenu)
                 (some
                  (fn [item]
                    (if-some [item-node
                              (retained/node (:web-store renderer) item)]
                      (standard-kind? item-node MenuItem)
                      false))
                  (:retained-children child-node)))
              (Some child)
              (recur (inc index)))
            (recur (inc index))))))
    None))

(defn- direct-dropdown-menu [renderer node]
  (if-some [current (retained/node (:web-store renderer) node)]
    (loop [index 0]
      (if (= index (count (:retained-children current)))
        None
        (let [child (nth (:retained-children current) index)]
          (if-some [child-node (retained/node (:web-store renderer) child)]
            (if (standard-kind? child-node DropdownMenu)
              (Some child)
              (recur (inc index)))
            (recur (inc index))))))
    None))

(defn- hide-context-menu! [renderer]
  (match (deref (:web-open-context-menu renderer))
    (Some menu)
    (do
      (Webapi.Dom.Element.removeAttribute "data-open" (dom-node renderer menu))
      (Stdlib.ignore (reset! (:web-open-context-menu renderer) None)))
    None (Stdlib.ignore true)))

(defn- context-menu-focus-items [renderer menu]
  (if-some [current (retained/node (:web-store renderer) menu)]
    (filterv
     (fn [child]
       (if-some [child-node (retained/node (:web-store renderer) child)]
         (and
          (standard-kind? child-node MenuItem)
          (enabled-node? renderer child))
         false))
     (:retained-children current))
    []))

(defn- focus-context-menu-item! [renderer menu index]
  (let [items (context-menu-focus-items renderer menu)]
    (when (not (empty? items))
      (Webapi.Dom.HtmlElement.focus
       (Webapi.Dom.Element.unsafeAsHtmlElement
        (dom-node renderer (nth items index)))))))

(defn- focus-context-menu-host! [renderer menu]
  (if-some [current (retained/node (:web-store renderer) menu)]
    (match (:retained-parent current)
      (Some host)
      (Webapi.Dom.HtmlElement.focus
       (Webapi.Dom.Element.unsafeAsHtmlElement (dom-node renderer host)))
      None (Stdlib.ignore true))
    (Stdlib.ignore true)))

(defn- set-context-position! [dom-node property value]
  (Webapi.Dom.CssStyleDeclaration.setProperty
   property value ""
   (Webapi.Dom.HtmlElement.style
    (Webapi.Dom.Element.unsafeAsHtmlElement dom-node))))

(defn- show-context-menu! [renderer menu x y]
  (hide-context-menu! renderer)
  (let [menu-node (dom-node renderer menu)]
    (Webapi.Dom.Element.setAttribute "data-open" "" menu-node)
    (let [width (Webapi.Dom.Element.clientWidth menu-node)
          height (Webapi.Dom.Element.clientHeight menu-node)
          document-root
          (Webapi.Dom.Document.documentElement (:web-document renderer))
          viewport-width (Webapi.Dom.Element.clientWidth document-root)
          viewport-height (Webapi.Dom.Element.clientHeight document-root)
          left (max 8 (min x (- viewport-width width 8)))
          top (max 8 (min y (- viewport-height height 8)))]
      (set-context-position! menu-node "left" (str left "px"))
      (set-context-position! menu-node "top" (str top "px")))
    (reset! (:web-open-context-menu renderer) (Some menu))
    (let [items (context-menu-focus-items renderer menu)]
      (if (empty? items)
        (Webapi.Dom.HtmlElement.focus
         (Webapi.Dom.Element.unsafeAsHtmlElement menu-node))
        (focus-context-menu-item! renderer menu 0))))
  true)

(defn- attach-context-host-events! [renderer node host-node]
  (let [timer (atom None)
        suppress-click (atom false)
        touch-pointer (atom None)
        touch-origin-x (atom None)
        touch-origin-y (atom None)
        cancel!
        (fn []
          (match (deref timer)
            (Some timer-id) (Js.Global.clearTimeout timer-id)
            None (Stdlib.ignore true))
          (reset! timer None)
          (reset! touch-pointer None)
          (reset! touch-origin-x None)
          (reset! touch-origin-y None)
          true)]
    (Webapi.Dom.Element.addMouseDownEventListener
     (fn [event]
       (when (= 2 (Webapi.Dom.MouseEvent.button event))
         (match (direct-context-menu renderer node)
           (Some menu)
           (do
             (Webapi.Dom.MouseEvent.preventDefault event)
             (Webapi.Dom.MouseEvent.stopImmediatePropagation event)
             (Stdlib.ignore
              (show-context-menu!
               renderer menu
               (Webapi.Dom.MouseEvent.clientX event)
               (Webapi.Dom.MouseEvent.clientY event))))
           None (Stdlib.ignore true)))
       (Stdlib.ignore true))
     host-node)
    (Webapi.Dom.Element.addEventListener
     "pointerdown"
     (fn [event]
       (when (and (= (pointer-type event) "touch")
                  (= (Webapi.Dom.MouseEvent.button
                      (pointer-mouse-event event)) 0))
         (match (direct-context-menu renderer node)
           (Some menu)
           (let [x (Webapi.Dom.MouseEvent.clientX
                    (pointer-mouse-event event))
                 y (Webapi.Dom.MouseEvent.clientY
                    (pointer-mouse-event event))]
             (cancel!)
             (reset! touch-pointer (Some (pointer-id event)))
             (reset! touch-origin-x (Some x))
             (reset! touch-origin-y (Some y))
             (reset!
              timer
              (Some
               (Js.Global.setTimeout
                500
                :f
                (fn []
                  (reset! timer None)
                  (reset! touch-origin-x None)
                  (reset! touch-origin-y None)
                  (reset! suppress-click true)
                  (show-context-menu! renderer menu x y)
                  (Stdlib.ignore true)))))
             (Stdlib.ignore true))
           None (Stdlib.ignore true)))
       (Stdlib.ignore true))
     host-node)
    (Webapi.Dom.Element.addEventListener
     "pointermove"
     (fn [event]
       (match (deref touch-pointer)
         (Some active-pointer-id)
         (when (= active-pointer-id (pointer-id event))
           (match (deref touch-origin-x)
             (Some origin-x)
             (match (deref touch-origin-y)
               (Some origin-y)
               (let [delta-x
                     (abs (- (Webapi.Dom.MouseEvent.clientX
                              (pointer-mouse-event event)) origin-x))
                     delta-y
                     (abs (- (Webapi.Dom.MouseEvent.clientY
                              (pointer-mouse-event event)) origin-y))]
                 (when (or (> delta-x 10) (> delta-y 10))
                   (Stdlib.ignore (cancel!))))
               None (Stdlib.ignore true))
             None (Stdlib.ignore true)))
         None (Stdlib.ignore true))
       (Stdlib.ignore true))
     host-node)
    (Webapi.Dom.Element.addEventListener
     "pointerup"
     (fn [event]
       (match (deref touch-pointer)
         (Some active-pointer-id)
         (when (= active-pointer-id (pointer-id event))
           (Stdlib.ignore (cancel!)))
         None (Stdlib.ignore true))
       (Stdlib.ignore true))
     host-node)
    (Webapi.Dom.Element.addEventListener
     "pointercancel"
     (fn [event]
       (match (deref touch-pointer)
         (Some active-pointer-id)
         (when (= active-pointer-id (pointer-id event))
           (Stdlib.ignore (cancel!)))
         None (Stdlib.ignore true))
       (Stdlib.ignore true))
     host-node)
    (Webapi.Dom.Element.addEventListener
     "click"
     (fn [event]
       (when (deref suppress-click)
         (reset! suppress-click false)
         (Webapi.Dom.Event.preventDefault event)
         (Webapi.Dom.Event.stopImmediatePropagation event))
       (Stdlib.ignore true))
     host-node)
    (Webapi.Dom.Element.addEventListener
     "contextmenu"
     (fn [event]
       (match (direct-context-menu renderer node)
         (Some _menu)
         (do
           (Webapi.Dom.Event.preventDefault event)
           (Webapi.Dom.Event.stopImmediatePropagation event))
         None (Stdlib.ignore true))
       (Stdlib.ignore true))
     host-node)
    (Webapi.Dom.Element.addKeyDownEventListener
     (fn [event]
       (let [key (Webapi.Dom.KeyboardEvent.key event)]
         (when (or (= key "ContextMenu")
                   (and (= key "F10")
                        (Webapi.Dom.KeyboardEvent.shiftKey event)))
           (match (direct-context-menu renderer node)
             (Some menu)
             (let [bounds (Webapi.Dom.Element.getBoundingClientRect host-node)]
               (Webapi.Dom.KeyboardEvent.preventDefault event)
               (Stdlib.ignore
                (show-context-menu!
                 renderer menu
                 (int (Webapi.Dom.DomRect.left bounds))
                 (int (Webapi.Dom.DomRect.bottom bounds)))))
             None (Stdlib.ignore true)))
         (Stdlib.ignore true)))
     host-node)))

(defn- attach-context-menu-events! [renderer node dom-node]
  (let [document (:web-document renderer)
        pointer-handler
        (fn [event]
          (let [target
                (Webapi.Dom.EventTarget.unsafeAsElement
                 (Webapi.Dom.Event.target event))]
            (when (not
                   (Webapi.Dom.Element.contains
                    (Webapi.Dom.Element.asNode target) dom-node))
              (hide-context-menu! renderer)))
          (Stdlib.ignore true))
        key-handler
        (fn [event]
          (when (= (deref (:web-open-context-menu renderer)) (Some node))
            (let [key (Webapi.Dom.KeyboardEvent.key event)]
              (if (= "Escape" key)
                (do
                  (Webapi.Dom.KeyboardEvent.preventDefault event)
                  (hide-context-menu! renderer)
                  (focus-context-menu-host! renderer node))
                (when (or
                       (= key "ArrowDown") (= key "ArrowUp")
                       (= key "Home") (= key "End"))
                  (let [items (context-menu-focus-items renderer node)
                        html-document
                        (Webapi.Dom.Document.unsafeAsHtmlDocument document)
                        current
                        (if-some [focused
                                  (Webapi.Dom.HtmlDocument.activeElement
                                   html-document)]
                          (focused-child-index renderer items focused 0)
                          None)
                        navigation-key
                        (if (= key "ArrowDown")
                          "ArrowRight"
                          (if (= key "ArrowUp") "ArrowLeft" key))]
                    (if-some [index
                              (horizontal-focus-index
                               navigation-key current (count items))]
                      (do
                        (Webapi.Dom.KeyboardEvent.preventDefault event)
                        (focus-context-menu-item! renderer node index))
                      (Stdlib.ignore true)))))))
          (Stdlib.ignore true))
        focus-handler
        (fn [event]
          (let [target
                (Webapi.Dom.EventTarget.unsafeAsElement
                 (Webapi.Dom.Event.target event))]
            (when
             (and
              (= (deref (:web-open-context-menu renderer)) (Some node))
              (not
               (Webapi.Dom.Element.contains
                (Webapi.Dom.Element.asNode target) dom-node))
              (hide-context-menu! renderer))))
          (Stdlib.ignore true))
        click-handler
        (fn [_event]
          (hide-context-menu! renderer)
          (Stdlib.ignore true))]
    (Webapi.Dom.Document.addEventListener
     "pointerdown" pointer-handler document)
    (Webapi.Dom.Document.addKeyDownEventListener key-handler document)
    (Webapi.Dom.Document.addEventListener "focusin" focus-handler document)
    (Webapi.Dom.Element.addEventListener "click" click-handler dom-node)
    (Stdlib.ignore
     (swap!
      (:web-cleanups renderer) assoc node
      (fn []
        (Webapi.Dom.Document.removeEventListener
         "pointerdown" pointer-handler document)
        (Webapi.Dom.Document.removeKeyDownEventListener key-handler document)
        (Webapi.Dom.Document.removeEventListener
         "focusin" focus-handler document)
        (Webapi.Dom.Element.removeEventListener "click" click-handler dom-node)
        (when (= (deref (:web-open-context-menu renderer)) (Some node))
          (reset! (:web-open-context-menu renderer) None))
        (Stdlib.ignore true))))))

(defn- tooltip-delay [renderer node]
  (match (retained/property (:web-store renderer) node TooltipDelay)
    (Some (IntValue delay)) delay
    _ 600))

(defn- clamp-popup-axis [value size viewport-size]
  (let [edge 8.0
        maximum (max edge (- viewport-size size edge))]
    (max edge (min value maximum))))

(defn- resolved-popup-side
  [preferred anchor-bounds popup-width popup-height
   viewport-width viewport-height offset]
  (let [above-space
        (- (Webapi.Dom.DomRect.top anchor-bounds) offset 8.0)
        below-space
        (- viewport-height
           (Webapi.Dom.DomRect.bottom anchor-bounds) offset 8.0)
        left-space
        (- (Webapi.Dom.DomRect.left anchor-bounds) offset 8.0)
        right-space
        (- viewport-width
           (Webapi.Dom.DomRect.right anchor-bounds) offset 8.0)]
    (match preferred
      "above"
      (if (or (<= popup-height above-space)
              (>= above-space below-space))
        "above" "below")
      "left"
      (if (or (<= popup-width left-space)
              (>= left-space right-space))
        "left" "right")
      "right"
      (if (or (<= popup-width right-space)
              (>= right-space left-space))
        "right" "left")
      _
      (if (or (<= popup-height below-space)
              (>= below-space above-space))
        "below" "above"))))

(defn- position-anchored!
  [document positioner popup anchor-bounds preferred alignment offset]
  (let [root (Webapi.Dom.Document.documentElement document)
        viewport-width
        (Stdlib.float_of_int (Webapi.Dom.Element.clientWidth root))
        viewport-height
        (Stdlib.float_of_int (Webapi.Dom.Element.clientHeight root))
        popup-bounds (Webapi.Dom.Element.getBoundingClientRect popup)
        popup-element (Webapi.Dom.Element.unsafeAsHtmlElement popup)
        popup-width
        (+ 1.0
           (max
            (Stdlib.float_of_int
             (Webapi.Dom.HtmlElement.offsetWidth popup-element))
            (Webapi.Dom.DomRect.width popup-bounds)))
        popup-height
        (+ 1.0
           (max
            (Stdlib.float_of_int
             (Webapi.Dom.HtmlElement.offsetHeight popup-element))
            (Webapi.Dom.DomRect.height popup-bounds)))
        side
        (resolved-popup-side
         preferred anchor-bounds popup-width popup-height
         viewport-width viewport-height offset)
        vertical (or (= side "above") (= side "below"))
        aligned-left
        (match alignment
          "center"
          (- (+ (Webapi.Dom.DomRect.left anchor-bounds)
                (/ (Webapi.Dom.DomRect.width anchor-bounds) 2.0))
             (/ popup-width 2.0))
          "end"
          (- (Webapi.Dom.DomRect.right anchor-bounds) popup-width)
          _ (Webapi.Dom.DomRect.left anchor-bounds))
        aligned-top
        (match alignment
          "center"
          (- (+ (Webapi.Dom.DomRect.top anchor-bounds)
                (/ (Webapi.Dom.DomRect.height anchor-bounds) 2.0))
             (/ popup-height 2.0))
          "end"
          (- (Webapi.Dom.DomRect.bottom anchor-bounds) popup-height)
          _ (Webapi.Dom.DomRect.top anchor-bounds))
        left
        (clamp-popup-axis
         (if vertical
           aligned-left
           (if (= side "left")
             (- (Webapi.Dom.DomRect.left anchor-bounds)
                popup-width offset)
             (+ (Webapi.Dom.DomRect.right anchor-bounds) offset)))
         popup-width viewport-width)
        top
        (clamp-popup-axis
         (if vertical
           (if (= side "above")
             (- (Webapi.Dom.DomRect.top anchor-bounds)
                popup-height offset)
             (+ (Webapi.Dom.DomRect.bottom anchor-bounds) offset))
           aligned-top)
         popup-height viewport-height)]
    (Webapi.Dom.Element.setAttribute "data-side" side positioner)
    (when (not (Webapi.Dom.Element.isSameNode
                (Webapi.Dom.Element.asNode popup) positioner))
      (Webapi.Dom.Element.setAttribute "data-side" side popup))
    (set-style! positioner "left" (str left "px"))
    (set-style! positioner "top" (str top "px"))
    (Stdlib.ignore true)))

(defn- position-tooltip! [renderer node]
  (let [tooltip (dom-node renderer node)
        anchor (dropdown-anchor-node renderer node)
        anchor-bounds (Webapi.Dom.Element.getBoundingClientRect anchor)
        offset (dropdown-offset renderer node)
        side (dropdown-side tooltip)
        alignment
        (match (Webapi.Dom.Element.getAttribute
                "data-anchor-alignment" tooltip)
          (Some value) value
          None "start")]
    (position-anchored!
     (:web-document renderer) tooltip tooltip anchor-bounds
     side alignment offset)))

(defn- begin-popup-open! [popup]
  (Webapi.Dom.Element.removeAttribute "data-closed" popup)
  (Webapi.Dom.Element.removeAttribute "data-ending-style" popup)
  (Webapi.Dom.Element.setAttribute "data-open" "" popup)
  (Webapi.Dom.Element.setAttribute "data-starting-style" "" popup)
  (Webapi.requestAnimationFrame
   (fn [_time]
     (Webapi.Dom.Element.removeAttribute "data-starting-style" popup)))
  true)

(defn- begin-popup-close! [popup]
  (Webapi.Dom.Element.removeAttribute "data-open" popup)
  (Webapi.Dom.Element.setAttribute "data-closed" "" popup)
  (Webapi.Dom.Element.setAttribute "data-ending-style" "" popup)
  true)

(defn- prefers-reduced-motion? [document]
  (let [html-document (Webapi.Dom.Document.unsafeAsHtmlDocument document)]
    (if-some [window (Webapi.Dom.HtmlDocument.defaultView html-document)]
      (match (js-dict/get
              (obj/magic
               (Webapi.Dom.Window.matchMedia
                "(prefers-reduced-motion: reduce)" window))
              "matches")
        (Some matches) matches
        None false)
      false)))

(defn- transition-event-from? [target event]
  (Webapi.Dom.Element.isSameNode
   (Webapi.Dom.Element.asNode
    (Webapi.Dom.EventTarget.unsafeAsElement
     (Webapi.Dom.Event.target event)))
   target))

(defn- after-transition!
  [document target fallback-duration finish-on-cancel complete!]
  (if (prefers-reduced-motion? document)
    (do
      (complete!)
      true)
    (let [finished (atom false)
          timer (atom None)
          finish-ref (atom (fn [] true))
          transition-handler
          (fn [event]
            (when (transition-event-from? target event)
              (Stdlib.ignore ((deref finish-ref))))
            (Stdlib.ignore true))
          finish!
          (fn []
            (when (not (deref finished))
              (reset! finished true)
              (match (deref timer)
                (Some timer-id) (Js.Global.clearTimeout timer-id)
                None (Stdlib.ignore true))
              (Webapi.Dom.Element.removeEventListener
               "transitionend" transition-handler target)
              (when finish-on-cancel
                (Webapi.Dom.Element.removeEventListener
                 "transitioncancel" transition-handler target))
              (complete!))
            true)]
      (reset! finish-ref finish!)
      (Webapi.Dom.Element.addEventListener
       "transitionend" transition-handler target)
      (when finish-on-cancel
        (Webapi.Dom.Element.addEventListener
         "transitioncancel" transition-handler target))
      (reset! timer
              (Some
               (Js.Global.setTimeout
                fallback-duration
                :f
                (fn [] (Stdlib.ignore (finish!))))))
      true)))

(defn- finish-popup-close-after-transition! [document popup duration]
  (after-transition!
   document popup duration true
   (fn []
     (when (= (Webapi.Dom.Element.getAttribute
               "data-ending-style" popup)
              (Some ""))
       (Webapi.Dom.Element.removeAttribute "data-ending-style" popup))
     true))
  true)

(defn- set-tooltip-open! [renderer node open]
  (let [tooltip (dom-node renderer node)]
    (if open
      (do
        (match (deref (:web-open-tooltip renderer))
          (Some previous)
          (when (not (= previous node))
            (if-some [_current (retained/node (:web-store renderer) previous)]
              (let [previous-tooltip (dom-node renderer previous)]
                (begin-popup-close! previous-tooltip)
                (Stdlib.ignore
                 (finish-popup-close-after-transition!
                  (:web-document renderer) previous-tooltip 120)))
              (Stdlib.ignore true)))
          None (Stdlib.ignore true))
        (reset! (:web-open-tooltip renderer) (Some node))
        (begin-popup-open! tooltip)
        (position-tooltip! renderer node)
        (Webapi.requestAnimationFrame
         (fn [_time]
           (if-some [_current (retained/node (:web-store renderer) node)]
             (position-tooltip! renderer node)
             (Stdlib.ignore true)))))
      (do
        (begin-popup-close! tooltip)
        (finish-popup-close-after-transition!
         (:web-document renderer) tooltip 120)
        (when (= (deref (:web-open-tooltip renderer)) (Some node))
          (Stdlib.ignore
           (reset! (:web-open-tooltip renderer) None)))))
    (Stdlib.ignore true)))

(defn- add-tooltip-description! [trigger tooltip-id]
  (match (Webapi.Dom.Element.getAttribute "aria-describedby" trigger)
    (Some current)
    (when (not (string/includes? (str " " current " ")
                                 (str " " tooltip-id " ")))
      (Webapi.Dom.Element.setAttribute
       "aria-describedby" (str current " " tooltip-id) trigger))
    None
    (Webapi.Dom.Element.setAttribute
     "aria-describedby" tooltip-id trigger))
  true)

(defn- remove-tooltip-description! [trigger tooltip-id]
  (match (Webapi.Dom.Element.getAttribute "aria-describedby" trigger)
    (Some current)
    (let [next (string/trim (string/replace current tooltip-id ""))]
      (if (= next "")
        (Webapi.Dom.Element.removeAttribute "aria-describedby" trigger)
        (Webapi.Dom.Element.setAttribute "aria-describedby" next trigger)))
    None (Stdlib.ignore true))
  true)

(defn- mount-tooltip! [renderer node tooltip]
  (let [document (:web-document renderer)
        window
        (Webapi.Dom.HtmlDocument.defaultView
         (Webapi.Dom.Document.unsafeAsHtmlDocument document))
        trigger (dropdown-anchor-node renderer node)
        tooltip-id (node-dom-id node)
        pointer-inside (atom false)
        origin (atom "")
        show-timer (atom None)
        hide-timer (atom None)
        warm-timer (atom None)
        cancel-show!
        (fn []
          (match (deref show-timer)
            (Some timer-id) (Js.Global.clearTimeout timer-id)
            None (Stdlib.ignore true))
          (reset! show-timer None)
          true)
        cancel-hide!
        (fn []
          (match (deref hide-timer)
            (Some timer-id) (Js.Global.clearTimeout timer-id)
            None (Stdlib.ignore true))
          (reset! hide-timer None)
          true)
        cancel-warm-timer!
        (fn []
          (match (deref warm-timer)
            (Some timer-id) (Js.Global.clearTimeout timer-id)
            None (Stdlib.ignore true))
          (reset! warm-timer None)
          true)
        cancel!
        (fn []
          (cancel-show!)
          (cancel-hide!)
          true)
        cancel-warm!
        (fn []
          (cancel-warm-timer!)
          (reset! (:web-tooltip-warm renderer) false)
          true)
        warm!
        (fn []
          (cancel-warm!)
          (reset! (:web-tooltip-warm renderer) true)
          (reset!
           warm-timer
           (Some
            (Js.Global.setTimeout
             400
             :f
             (fn []
               (reset! warm-timer None)
               (reset! (:web-tooltip-warm renderer) false)
               (Stdlib.ignore true)))))
          true)
        show!
        (fn [next-origin]
          (cancel!)
          (reset! origin next-origin)
          (set-tooltip-open! renderer node true)
          true)
        hide!
        (fn [warm]
          (cancel!)
          (when (and warm (= (deref origin) "pointer")) (warm!))
          (set-tooltip-open! renderer node false)
          (reset! origin "")
          true)
        pointer-enter!
        (fn [event]
          (when (not (= (pointer-type event) "touch"))
            (reset! pointer-inside true)
            (cancel-hide!)
            (let [delay (if (deref (:web-tooltip-warm renderer))
                          0
                          (tooltip-delay renderer node))]
              (if (= delay 0)
                (do
                  (show! "pointer")
                  (Stdlib.ignore true))
                (do
                  (reset!
                   show-timer
                   (Some
                    (Js.Global.setTimeout
                     delay
                     :f
                     (fn []
                       (reset! show-timer None)
                       (show! "pointer")
                       (Stdlib.ignore true)))))
                  (Stdlib.ignore true)))))
          (Stdlib.ignore true))
        pointer-leave!
        (fn [_event]
          (reset! pointer-inside false)
          (cancel-show!)
          (reset!
           hide-timer
           (Some
            (Js.Global.setTimeout
             50
             :f
             (fn []
               (reset! hide-timer None)
               (hide! true)
               (Stdlib.ignore true)))))
          (Stdlib.ignore true))
        focus-in!
        (fn [_event]
          (show! "focus")
          (Stdlib.ignore true))
        focus-out!
        (fn [_event]
          (cancel-hide!)
          (reset!
           hide-timer
           (Some
            (Js.Global.setTimeout
             0
             :f
             (fn []
               (reset! hide-timer None)
               (when (not (deref pointer-inside)) (hide! false))
               (Stdlib.ignore true)))))
          (Stdlib.ignore true))
        press!
        (fn [_event]
          (cancel-warm!)
          (hide! false)
          (Stdlib.ignore true))
        key!
        (fn [event]
          (when (and
                 (= (Webapi.Dom.KeyboardEvent.key event) "Escape")
                 (= (deref (:web-open-tooltip renderer)) (Some node)))
            (Webapi.Dom.KeyboardEvent.preventDefault event)
            (cancel-warm!)
            (hide! false))
          (Stdlib.ignore true))
        refresh-position!
        (fn [_event]
          (when (= (deref (:web-open-tooltip renderer)) (Some node))
            (position-tooltip! renderer node))
          (Stdlib.ignore true))]
    (add-tooltip-description! trigger tooltip-id)
    (Webapi.Dom.Element.addEventListener "pointerenter" pointer-enter! trigger)
    (Webapi.Dom.Element.addEventListener "pointerleave" pointer-leave! trigger)
    (Webapi.Dom.Element.addEventListener "focusin" focus-in! trigger)
    (Webapi.Dom.Element.addEventListener "focusout" focus-out! trigger)
    (Webapi.Dom.Element.addEventListener "pointerdown" press! trigger)
    (match window
      (Some current-window)
      (Webapi.Dom.Window.addEventListener
       "resize" refresh-position! current-window)
      None (Stdlib.ignore true))
    (Webapi.Dom.Document.addKeyDownEventListener key! document)
    (swap!
     (:web-cleanups renderer) assoc node
     (fn []
       (cancel!)
       (cancel-warm!)
       (Webapi.Dom.Element.removeAttribute "data-open" tooltip)
       (when (= (deref (:web-open-tooltip renderer)) (Some node))
         (Stdlib.ignore
          (reset! (:web-open-tooltip renderer) None)))
       (remove-tooltip-description! trigger tooltip-id)
       (Webapi.Dom.Element.removeEventListener
        "pointerenter" pointer-enter! trigger)
       (Webapi.Dom.Element.removeEventListener
        "pointerleave" pointer-leave! trigger)
       (Webapi.Dom.Element.removeEventListener "focusin" focus-in! trigger)
       (Webapi.Dom.Element.removeEventListener "focusout" focus-out! trigger)
       (Webapi.Dom.Element.removeEventListener "pointerdown" press! trigger)
       (match window
         (Some current-window)
         (Webapi.Dom.Window.removeEventListener
          "resize" refresh-position! current-window)
         None (Stdlib.ignore true))
       (Webapi.Dom.Document.removeKeyDownEventListener key! document)
       (Stdlib.ignore true)))
    (Stdlib.ignore true)))

(defn- toast-duration [renderer node]
  (match (retained/property (:web-store renderer) node DurationValue)
    (Some (IntValue duration)) duration
    _ 5000))

(defn- first-toast-node? [renderer toast]
  (let [children (Webapi.Dom.Element.children (:web-toast-viewport renderer))]
    (if-some [first-toast (html-collection/item 0 children)]
      (Webapi.Dom.Element.isSameNode
       (Webapi.Dom.Element.asNode first-toast) toast)
      false)))

(defn- mount-toast! [renderer node toast]
  (let [document (:web-document renderer)
        timer (atom None)
        pointer-inside (atom false)
        focus-inside (atom false)
        active-pointer (atom None)
        start-x (atom None)
        current-x (atom 0)
        reset-toast-swipe!
        (fn []
          (reset! active-pointer None)
          (reset! start-x None)
          (Webapi.Dom.Element.removeAttribute "data-swiping" toast)
          (Webapi.Dom.Element.removeAttribute "data-swipe-direction" toast)
          (set-style! toast "--toast-swipe-movement-x" "0px")
          true)
        cancel!
        (fn []
          (match (deref timer)
            (Some timer-id) (Js.Global.clearTimeout timer-id)
            None (Stdlib.ignore true))
          (reset! timer None)
          true)
        dismiss!
        (fn []
          (cancel!)
          (Stdlib.ignore
           ((deref (:web-event-handler renderer)) (proto/Dismiss node)))
          true)
        schedule!
        (fn []
          (cancel!)
          (let [duration (toast-duration renderer node)]
            (when (> duration 0)
              (reset!
               timer
               (Some
                (Js.Global.setTimeout
                 duration
                 :f
                 (fn []
                   (reset! timer None)
                   (dismiss!)
                   (Stdlib.ignore true)))))))
          true)
        resume!
        (fn []
          (when (and (not (deref pointer-inside))
                     (not (deref focus-inside)))
            (schedule!))
          true)
        pointer-enter!
        (fn [_event]
          (reset! pointer-inside true)
          (cancel!)
          (Stdlib.ignore true))
        pointer-leave!
        (fn [_event]
          (reset! pointer-inside false)
          (resume!)
          (Stdlib.ignore true))
        focus-in!
        (fn [_event]
          (reset! focus-inside true)
          (cancel!)
          (Stdlib.ignore true))
        focus-out!
        (fn [_event]
          (reset! focus-inside false)
          (resume!)
          (Stdlib.ignore true))
        pointer-down!
        (fn [event]
          (let [target
                (Webapi.Dom.EventTarget.unsafeAsElement
                 (Webapi.Dom.Event.target event))
                interactive (swipe-ignored-target? target toast)]
            (when (and (= (Webapi.Dom.MouseEvent.button
                           (pointer-mouse-event event)) 0)
                       (not interactive))
              (let [x (Webapi.Dom.MouseEvent.clientX
                       (pointer-mouse-event event))]
                (reset! active-pointer (Some (pointer-id event)))
                (reset! start-x (Some x))
                (reset! current-x x)
                (cancel!))))
          (Stdlib.ignore true))
        pointer-move!
        (fn [event]
          (match (deref active-pointer)
            (Some active-pointer-id)
            (when (= active-pointer-id (pointer-id event))
              (match (deref start-x)
              (Some origin)
              (let [x (Webapi.Dom.MouseEvent.clientX
                       (pointer-mouse-event event))
                    delta (- x origin)]
                (reset! current-x x)
                (Webapi.Dom.Event.preventDefault event)
                (Webapi.Dom.Element.setAttribute "data-swiping" "" toast)
                (Webapi.Dom.Element.setAttribute
                 "data-swipe-direction" (if (< delta 0) "left" "right") toast)
                (set-style!
                 toast "--toast-swipe-movement-x" (str delta "px")))
                None (Stdlib.ignore true)))
            None (Stdlib.ignore true))
          (Stdlib.ignore true))
        pointer-up!
        (fn [event]
          (match (deref active-pointer)
            (Some active-pointer-id)
            (when (= active-pointer-id (pointer-id event))
              (match (deref start-x)
              (Some origin)
              (let [delta (- (deref current-x) origin)]
                (reset! active-pointer None)
                (reset! start-x None)
                (Stdlib.ignore
                 (if (or (> delta 80) (< delta -80))
                   (dismiss!)
                   (do
                     (reset-toast-swipe!)
                     (resume!)))))
                None (Stdlib.ignore true)))
            None (Stdlib.ignore true))
          (Stdlib.ignore true))
        pointer-cancel!
        (fn [event]
          (match (deref active-pointer)
            (Some active-pointer-id)
            (when (= active-pointer-id (pointer-id event))
              (reset-toast-swipe!)
              (Stdlib.ignore (resume!)))
            None (Stdlib.ignore true))
          (Stdlib.ignore true))
        key!
        (fn [event]
          (when (and (= (Webapi.Dom.KeyboardEvent.key event) "F6")
                     (first-toast-node? renderer toast))
            (Webapi.Dom.KeyboardEvent.preventDefault event)
            (Webapi.Dom.HtmlElement.focus
             (Webapi.Dom.Element.unsafeAsHtmlElement toast)))
          (Stdlib.ignore true))
        previous-cleanup
        (clojure.core/get (deref (:web-cleanups renderer)) node)]
    (schedule!)
    (Webapi.Dom.Element.addEventListener "pointerenter" pointer-enter! toast)
    (Webapi.Dom.Element.addEventListener "pointerleave" pointer-leave! toast)
    (Webapi.Dom.Element.addEventListener "focusin" focus-in! toast)
    (Webapi.Dom.Element.addEventListener "focusout" focus-out! toast)
    (Webapi.Dom.Element.addEventListener "pointerdown" pointer-down! toast)
    (Webapi.Dom.Element.addEventListener "pointermove" pointer-move! toast)
    (Webapi.Dom.Element.addEventListener "pointerup" pointer-up! toast)
    (Webapi.Dom.Element.addEventListener "pointercancel" pointer-cancel! toast)
    (Webapi.Dom.Document.addKeyDownEventListener key! document)
    (swap!
     (:web-cleanups renderer) assoc node
     (fn []
       (match previous-cleanup
         (Some cleanup) (cleanup)
         None (Stdlib.ignore true))
       (cancel!)
       (Webapi.Dom.Element.removeEventListener
        "pointerenter" pointer-enter! toast)
       (Webapi.Dom.Element.removeEventListener
        "pointerleave" pointer-leave! toast)
       (Webapi.Dom.Element.removeEventListener "focusin" focus-in! toast)
       (Webapi.Dom.Element.removeEventListener "focusout" focus-out! toast)
       (Webapi.Dom.Element.removeEventListener "pointerdown" pointer-down! toast)
       (Webapi.Dom.Element.removeEventListener "pointermove" pointer-move! toast)
       (Webapi.Dom.Element.removeEventListener "pointerup" pointer-up! toast)
       (Webapi.Dom.Element.removeEventListener
        "pointercancel" pointer-cancel! toast)
       (Webapi.Dom.Document.removeKeyDownEventListener key! document)
       (Stdlib.ignore true)))
    (Stdlib.ignore true)))

(defn- attach-events! [renderer node kind dom-node]
  (when (not (= kind ContextMenu))
    (attach-context-host-events! renderer node dom-node))
  (when (proto/tree-row-kind? kind)
    (attach-tree-item-events! renderer node kind dom-node))
  (when (= kind Tree)
    (attach-tree-events! renderer node dom-node))
  (when (= kind Toolbar)
    (attach-toolbar-events! renderer node dom-node))
  (match kind
    Text (attach-pressable-text-events! renderer node dom-node)
    Button (attach-button-events! renderer node kind dom-node)
    ToggleButton (attach-button-events! renderer node kind dom-node)
    TextField (attach-text-events! renderer node kind dom-node)
    Input (attach-text-events! renderer node kind dom-node)
    SearchField (attach-text-events! renderer node kind dom-node)
    Textarea (attach-text-events! renderer node kind dom-node)
    Select (attach-picker-trigger-events! renderer node dom-node)
    Combobox
    (do
      (attach-text-events! renderer node kind dom-node)
      (attach-picker-trigger-events! renderer node (child-element dom-node 1)))
    DropdownMenu
    (attach-dropdown-events! renderer node (child-element dom-node 0))
    ContextMenu (attach-context-menu-events! renderer node dom-node)
    Dialog (attach-modal-events! renderer node dom-node)
    Sheet (attach-modal-events! renderer node dom-node)
    MenuItem
    (do
      (attach-picker-press-event! renderer node dom-node)
      (Webapi.Dom.Element.addEventListener
       "focusin"
       (fn [_event]
         (Webapi.Dom.Element.setAttribute "data-highlighted" "" dom-node)
         (Stdlib.ignore true))
       dom-node)
      (Webapi.Dom.Element.addEventListener
       "focusout"
       (fn [_event]
         (Webapi.Dom.Element.removeAttribute "data-highlighted" dom-node)
         (Stdlib.ignore true))
       dom-node))
    ListItem (attach-list-item-events! renderer node dom-node)
    Checkbox (attach-toggle-event! renderer node kind dom-node)
    SwitchControl (attach-toggle-event! renderer node kind dom-node)
    Toggle (attach-button-events! renderer node kind dom-node)
    Radio (attach-radio-event! renderer node dom-node)
    Slider (attach-slider-event! renderer node dom-node)
    Split (attach-split-events! renderer node dom-node)
    Tabs (attach-horizontal-focus! renderer node kind dom-node)
    ButtonGroup (attach-horizontal-focus! renderer node kind dom-node)
    ToggleGroup (attach-horizontal-focus! renderer node kind dom-node)
    Breadcrumb (attach-horizontal-focus! renderer node kind dom-node)
    Pagination (attach-horizontal-focus! renderer node kind dom-node)
    Accordion (attach-accordion-event! renderer node dom-node)
    TableCell (attach-pressable-text-events! renderer node dom-node)
    TimelineItem (attach-pressable-text-events! renderer node dom-node)
    _ (Stdlib.ignore true)))

(defn- set-style! [dom-node property value]
  (let [element-style
        (Webapi.Dom.HtmlElement.style
         (Webapi.Dom.Element.unsafeAsHtmlElement dom-node))]
    (Webapi.Dom.CssStyleDeclaration.setProperty
     property value "" element-style)))

(defn- set-accordion-open! [renderer dom-node open]
  (let [trigger (accordion-trigger-node dom-node)
        panel (accordion-panel-node dom-node)]
    (Webapi.Dom.Element.setAttribute
     "aria-expanded" (if open "true" "false") trigger)
    (if open
      (do
        (Webapi.Dom.Element.removeAttribute "data-closed" dom-node)
        (Webapi.Dom.Element.setAttribute "data-open" "" dom-node)
        (Webapi.Dom.Element.removeAttribute "hidden" panel)
        (Webapi.Dom.Element.removeAttribute "data-closed" panel)
        (Webapi.Dom.Element.removeAttribute "data-ending-style" panel)
        (Webapi.Dom.Element.setAttribute "data-open" "" panel)
        (set-style!
         panel "--lui-accordion-panel-height"
         (str (Webapi.Dom.Element.scrollHeight panel) "px"))
        (Webapi.Dom.Element.setAttribute "data-starting-style" "" panel)
        (Webapi.requestAnimationFrame
         (fn [_time]
           (when (Webapi.Dom.Element.hasAttribute "data-open" panel)
             (Webapi.Dom.Element.removeAttribute
              "data-starting-style" panel))
           (Stdlib.ignore true)))
        (if (prefers-reduced-motion? (:web-document renderer))
          (set-style! panel "--lui-accordion-panel-height" "auto")
          (Stdlib.ignore
           (Js.Global.setTimeout
            190
            :f
            (fn []
              (when (Webapi.Dom.Element.hasAttribute "data-open" panel)
                (set-style! panel "--lui-accordion-panel-height" "auto"))
              (Stdlib.ignore true))))))
      (do
        (Webapi.Dom.Element.removeAttribute "data-open" dom-node)
        (Webapi.Dom.Element.setAttribute "data-closed" "" dom-node)
        (when (not (Webapi.Dom.Element.hasAttribute "hidden" panel))
          (set-style!
           panel "--lui-accordion-panel-height"
           (str (Webapi.Dom.Element.scrollHeight panel) "px"))
          (Stdlib.ignore
           (Webapi.Dom.HtmlElement.offsetHeight
            (Webapi.Dom.Element.unsafeAsHtmlElement panel)))
          (Webapi.Dom.Element.removeAttribute "data-open" panel)
          (Webapi.Dom.Element.removeAttribute "data-starting-style" panel)
          (Webapi.Dom.Element.setAttribute "data-closed" "" panel)
          (let [complete!
                (fn []
                  (when (Webapi.Dom.Element.hasAttribute
                         "data-ending-style" panel)
                    (Webapi.Dom.Element.removeAttribute
                     "data-ending-style" panel)
                    (Webapi.Dom.Element.setAttribute "hidden" "" panel))
                  true)]
            (if (prefers-reduced-motion? (:web-document renderer))
              (do
                (Webapi.Dom.Element.setAttribute
                 "data-ending-style" "" panel)
                (Stdlib.ignore (complete!)))
              (do
                (Stdlib.ignore
                 (after-transition!
                  (:web-document renderer) panel 190 false complete!))
                (Webapi.Dom.Element.setAttribute
                 "data-ending-style" "" panel)))))))
    (Stdlib.ignore true)))

(defn- split-base-fraction [value]
  (if (and (Float.is_finite value) (> value 0.0))
    (min value 1.0)
    0.5))

(defn- split-int-property [renderer node property fallback]
  (match (retained/property (:web-store renderer) node property)
    (Some (IntValue value)) value
    _ fallback))

(defn- split-child-minimum [renderer node index]
  (let [children (retained/children (:web-store renderer) node)]
    (if (< index (count children))
      (split-int-property renderer (nth children index) MinWidth 0)
      0)))

(defn- effective-split-fraction [renderer node value]
  (let [root (dom-node renderer node)
        gap (split-int-property renderer node Gap 9)
        available
        (- (Webapi.Dom.Element.clientWidth root) gap)
        first-minimum (split-child-minimum renderer node 0)
        second-minimum (split-child-minimum renderer node 1)]
    (if (<= available 0)
      0.5
      (let [available-float (Stdlib.float_of_int available)
            low (/ (Stdlib.float_of_int first-minimum) available-float)
            high
            (- 1.0 (/ (Stdlib.float_of_int second-minimum) available-float))]
        (if (> low high)
          (/ low (max (+ low (- 1.0 high)) 0.0001))
          (min (max (split-base-fraction value) low) high))))))

(defn- split-timing-function [renderer node]
  (match (retained/property (:web-store renderer) node ResizeEasing)
    (Some (StringValue "linear")) "linear"
    (Some (StringValue "emphasized")) "cubic-bezier(0.2, 0, 0, 1)"
    (Some (StringValue "spring")) "cubic-bezier(0.16, 1.2, 0.3, 1)"
    _ "ease-in-out"))

(defn- render-split! [renderer node root value animated]
  (let [fraction (effective-split-fraction renderer node value)
        gap (split-int-property renderer node Gap 9)
        gap-float (Stdlib.float_of_int gap)
        first-minimum (split-child-minimum renderer node 0)
        second-minimum (split-child-minimum renderer node 1)
        panes (child-element root 0)
        divider (child-element root 1)
        duration
        (if animated
          (split-int-property renderer node ResizeDuration 0)
          0)]
    (set-style!
     panes "grid-template-columns"
     (str
      "minmax(" first-minimum "px, " fraction "fr) "
      "minmax(" second-minimum "px, " (- 1.0 fraction) "fr)"))
    (set-style! panes "column-gap" (str gap "px"))
    (set-style!
     divider "left"
     (str "calc(" (* fraction 100.0) "% - " (* fraction gap-float) "px)"))
    (set-style! divider "width" (str gap "px"))
    (set-style! panes "transition-property" "grid-template-columns")
    (set-style! divider "transition-property" "left")
    (set-style! panes "transition-duration" (str duration "ms"))
    (set-style! divider "transition-duration" (str duration "ms"))
    (set-style! panes "transition-timing-function" (split-timing-function renderer node))
    (set-style! divider "transition-timing-function" (split-timing-function renderer node))
    (Webapi.Dom.Element.setAttribute "aria-valuenow" (str fraction) divider)
    (Stdlib.ignore true)))

(defn- reconcile-split! [renderer node root source]
  (if-some [state (clojure.core/get (deref (:web-splits renderer)) node)]
    (let [source-changed (not (= source (:web-split-source state)))
          current (:web-split-current state)
          next-current
          (if source-changed
            (if (< (Float.abs (- (split-base-fraction source) current)) 0.000001)
              current
              (split-base-fraction source))
            current)]
      (swap!
       (:web-splits renderer) assoc node
       (record web-split-state
               (web-split-source source)
               (web-split-current next-current)))
      (render-split! renderer node root next-current source-changed))
    (let [duration (split-int-property renderer node ResizeDuration 0)
          origin
          (match (retained/property (:web-store renderer) node ResizeOrigin)
            (Some (FloatValue value)) (Some value)
            _ None)
          start
          (match origin
            (Some value) (if (> duration 0) (split-base-fraction value)
                             (split-base-fraction source))
            None (split-base-fraction source))]
      (swap!
       (:web-splits renderer) assoc node
       (record web-split-state
               (web-split-source source)
               (web-split-current start)))
      (render-split! renderer node root start false)
      (when (and (> duration 0) (not (= start (split-base-fraction source))))
        (Webapi.requestAnimationFrame
         (fn [_time]
           (swap!
            (:web-splits renderer) assoc node
            (record web-split-state
                    (web-split-source source)
                    (web-split-current (split-base-fraction source))))
           (render-split! renderer node root (split-base-fraction source) true)))))))

(defn- update-split! [renderer node]
  (if-some [current (retained/node (:web-store renderer) node)]
    (when (standard-kind? current Split)
      (let [source
            (match (retained/property (:web-store renderer) node ProgressValue)
              (Some (FloatValue value)) value
              _ 0.0)]
        (reconcile-split! renderer node (:platform-node current) source)))
    (Stdlib.ignore true)))

(defn- update-splits-under! [renderer node]
  (update-split! renderer node)
  (doseq [child (retained/children (:web-store renderer) node)]
    (update-splits-under! renderer child))
  (Stdlib.ignore true))

(defn- attach-split-events! [renderer node root]
  (let [divider (child-element root 1)
        document (:web-document renderer)
        dragging (atom false)
        move!
        (fn [event]
          (when (deref dragging)
            (let [bounds (Webapi.Dom.Element.getBoundingClientRect root)
                  gap (split-int-property renderer node Gap 9)
                  available (- (Webapi.Dom.DomRect.width bounds)
                               (Stdlib.float_of_int gap))
                  pointer (- (Stdlib.float_of_int
                              (Webapi.Dom.MouseEvent.clientX event))
                             (Webapi.Dom.DomRect.left bounds))
                  raw (/ (- pointer (/ (Stdlib.float_of_int gap) 2.0))
                         (max available 1.0))
                  current (effective-split-fraction renderer node raw)
                  source
                  (match (retained/property (:web-store renderer) node ProgressValue)
                    (Some (FloatValue value)) value
                    _ 0.0)]
              (swap!
               (:web-splits renderer) assoc node
               (record web-split-state
                       (web-split-source source)
                       (web-split-current current)))
              (render-split! renderer node root current false)
              (Stdlib.ignore
               ((deref (:web-event-handler renderer))
                (proto/ValueChanged node current)))))
          (Stdlib.ignore true))
        stop!
        (fn [_event]
          (reset! dragging false)
          (Stdlib.ignore true))
        adjust!
        (fn [delta]
          (let [current
                (if-some [state (clojure.core/get
                                 (deref (:web-splits renderer)) node)]
                  (:web-split-current state)
                  0.5)
                next (effective-split-fraction renderer node (+ current delta))
                source
                (match (retained/property (:web-store renderer) node ProgressValue)
                  (Some (FloatValue value)) value
                  _ 0.0)]
            (swap!
             (:web-splits renderer) assoc node
             (record web-split-state
                     (web-split-source source)
                     (web-split-current next)))
            (render-split! renderer node root next false)
            (Stdlib.ignore
             ((deref (:web-event-handler renderer))
              (proto/ValueChanged node next)))))
        resize-observer
        (Webapi.ResizeObserver.make
         (fn [_entries]
           (if-some [state (clojure.core/get
                            (deref (:web-splits renderer)) node)]
             (render-split!
              renderer node root (:web-split-current state) false)
             (Stdlib.ignore true))))]
    (Webapi.Dom.Element.addMouseDownEventListener
     (fn [event]
       (when (= 0 (Webapi.Dom.MouseEvent.button event))
         (Webapi.Dom.MouseEvent.preventDefault event)
         (reset! dragging true))
       (Stdlib.ignore true))
     divider)
    (Webapi.Dom.Document.addMouseMoveEventListener move! document)
    (Webapi.Dom.Document.addMouseUpEventListener stop! document)
    (Webapi.ResizeObserver.observe resize-observer root)
    (Webapi.Dom.Element.addKeyDownEventListener
     (fn [event]
       (match (Webapi.Dom.KeyboardEvent.key event)
         "ArrowLeft"
         (do (Webapi.Dom.KeyboardEvent.preventDefault event) (adjust! -0.05))
         "ArrowRight"
         (do (Webapi.Dom.KeyboardEvent.preventDefault event) (adjust! 0.05))
         "Home"
         (do (Webapi.Dom.KeyboardEvent.preventDefault event) (adjust! -1.0))
         "End"
         (do (Webapi.Dom.KeyboardEvent.preventDefault event) (adjust! 1.0))
         _ (Stdlib.ignore true))
       (Stdlib.ignore true))
     divider)
    (swap!
     (:web-cleanups renderer) assoc node
     (fn []
       (Webapi.Dom.Document.removeMouseMoveEventListener move! document)
       (Webapi.Dom.Document.removeMouseUpEventListener stop! document)
       (Webapi.ResizeObserver.disconnect resize-observer)
       (swap! (:web-splits renderer) dissoc node)
       (Stdlib.ignore true)))
    (Stdlib.ignore true)))

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
         (= color "card")
         (= color "card-foreground")
         (= color "primary")
         (= color "primary-foreground")
         (= color "secondary")
         (= color "secondary-foreground")
         (= color "accent")
         (= color "accent-foreground")
         (= color "muted-foreground")
         (= color "destructive")
         (= color "destructive-foreground")
         (= color "success")
         (= color "success-foreground")
         (= color "warning")
         (= color "warning-foreground")
         (= color "error")
         (= color "error-foreground")
         (= color "input")
         (= color "ring")
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
  (registered-image renderer node))

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

(defn- media-size [renderer node property fallback]
  (match (retained/property (:web-store renderer) node property)
    (Some (IntValue value)) (Stdlib.float_of_int value)
    _ fallback))

(defn- registered-image [renderer node]
  (match (retained/property (:web-store renderer) node ImageIdValue)
    (Some (IntValue image-id))
    (if (= image-id 0)
      None
      (clojure.core/get (deref (:web-images renderer)) image-id))
    _ None))

(defn- update-image! [renderer node dom-node]
  (let [pixels (child-element dom-node 0)]
    (match (registered-image renderer node)
      (Some resource)
      (let [source-x (avatar-float renderer node SourceX 0.0)
            source-y (avatar-float renderer node SourceY 0.0)
            source-width (avatar-float renderer node SourceWidth 0.0)
            source-height (avatar-float renderer node SourceHeight 0.0)
            cropped (> source-width 0.0)]
        (Webapi.Dom.Element.setAttribute
         "src" (:web-image-url resource) pixels)
        (set-state-attribute! pixels "hidden" false)
        (if cropped
          (let [target-width
                (media-size renderer node WidthValue source-width)
                target-height
                (media-size renderer node HeightValue source-height)
                scale-x (/ target-width source-width)
                scale-y (/ target-height source-height)]
            (set-style!
             pixels "width"
             (str (* (:web-image-width resource) scale-x) "px"))
            (set-style!
             pixels "height"
             (str (* (:web-image-height resource) scale-y) "px"))
            (set-style!
             pixels "left"
             (str (* (- source-x) scale-x) "px"))
            (set-style!
             pixels "top"
             (str (* (- source-y) scale-y) "px"))
            (set-style! pixels "object-fit" "fill"))
          (do
            (set-style! pixels "width" "100%")
            (set-style! pixels "height" "100%")
            (set-style! pixels "left" "0")
            (set-style! pixels "top" "0")
            (set-style! pixels "object-fit" "fill"))))
      None
      (do
        (Webapi.Dom.Element.removeAttribute "src" pixels)
        (set-state-attribute! pixels "hidden" true)))))

(defn- update-media-surface! [renderer node dom-node]
  (let [frame (child-element dom-node 0)]
    (match (retained/property (:web-store renderer) node SurfaceIdValue)
      (Some (IntValue surface-id))
      (match (if (= surface-id 0)
               None
               (clojure.core/get
                (deref (:web-media-surfaces renderer)) surface-id))
        (Some resource)
        (do
          (set-style! dom-node "background-color" "transparent")
          (Webapi.Dom.Element.setAttribute
           "src" (:web-image-url resource) frame)
          (set-state-attribute! frame "hidden" false))
        None
        (do
          (set-style!
           dom-node "background-color"
           (if (= surface-id 0)
             "transparent"
             (str
              "rgb("
              (+ 64 (mod (* surface-id 37) 64)) ", "
              (+ 64 (mod (* surface-id 57) 64)) ", "
              (+ 64 (mod (* surface-id 83) 64)) ")")))
          (Webapi.Dom.Element.removeAttribute "src" frame)
          (set-state-attribute! frame "hidden" true)))
      _
      (do
        (set-style! dom-node "background-color" "transparent")
        (Webapi.Dom.Element.removeAttribute "src" frame)
        (set-state-attribute! frame "hidden" true)))))

(defn- refresh-image-id! [renderer image-id]
  (reduce-kv
   (fn [_updated node current]
     (when
      (and
       (or (standard-kind? current Avatar)
           (standard-kind? current Image))
       (= (clojure.core/get (:retained-properties current) ImageIdValue)
          (Some (IntValue image-id)))
       (if (standard-kind? current Avatar)
         (update-avatar! renderer node (:platform-node current))
         (update-image! renderer node (:platform-node current)))))
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
  (refresh-image-id! renderer image-id)
  true)

(defn unregister-image! [renderer image-id]
  (when (<= image-id 0)
    (raise (Invalid_argument "registered image id must be positive")))
  (when (contains? (deref (:web-images renderer)) image-id)
    (swap! (:web-images renderer) dissoc image-id)
    (refresh-image-id! renderer image-id))
  true)

(defn- refresh-media-surface-id! [renderer surface-id]
  (reduce-kv
   (fn [_updated node current]
     (when
      (and
       (standard-kind? current MediaSurface)
       (= (clojure.core/get (:retained-properties current) SurfaceIdValue)
          (Some (IntValue surface-id)))
       (update-media-surface! renderer node (:platform-node current))))
     true)
   true
   (retained/nodes (:web-store renderer))))

(defn present-media-surface-frame! [renderer surface-id url width height]
  (when (<= surface-id 0)
    (raise (Invalid_argument "media surface id must be positive")))
  (when
   (or
    (not (Float.is_finite width))
    (not (Float.is_finite height))
    (<= width 0.0)
    (<= height 0.0))
   (raise (Invalid_argument "media surface dimensions must be positive")))
  (swap!
   (:web-media-surfaces renderer)
   assoc surface-id
   (record web-image-resource
           (web-image-url url)
           (web-image-width width)
           (web-image-height height)))
  (refresh-media-surface-id! renderer surface-id)
  true)

(defn unregister-media-surface! [renderer surface-id]
  (when (<= surface-id 0)
    (raise (Invalid_argument "media surface id must be positive")))
  (when (contains? (deref (:web-media-surfaces renderer)) surface-id)
    (swap! (:web-media-surfaces renderer) dissoc surface-id)
    (refresh-media-surface-id! renderer surface-id))
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

(defn- string-property [renderer node property]
  (match (retained/property (:web-store renderer) node property)
    (Some (StringValue value)) value
    _ ""))

(defn- update-stepper! [renderer node]
  (let [children (retained/children (:web-store renderer) node)
        active (proto/int-property
                (:retained-properties
                 (match (retained/node (:web-store renderer) node)
                   (Some current) current
                   None (raise (Invalid_argument "unknown Stepper"))))
                ActiveIndex 0)
        count (count children)]
    (loop [index 0]
      (when (< index count)
        (let [child (nth children index)
              step (dom-node renderer child)
              indicator (child-element step 0)
              label (string-property renderer child TextValue)
              state
              (if (< index active)
                "completed"
                (if (= index active) "active" "pending"))]
          (Webapi.Dom.Element.setAttribute "data-state" state step)
          (Webapi.Dom.Element.setAttribute
           "aria-label" (str label " (" state ")") step)
          (Webapi.Dom.Element.setAttribute "aria-posinset" (str (inc index)) step)
          (Webapi.Dom.Element.setAttribute "aria-setsize" (str count) step)
          (if (= state "active")
            (Webapi.Dom.Element.setAttribute "aria-current" "step" step)
            (Webapi.Dom.Element.removeAttribute "aria-current" step))
          (if (= state "completed")
            (do
              (Webapi.Dom.Element.setTextContent indicator "")
              (Webapi.Dom.Element.setAttribute "data-name" "check" indicator)
              (update-icon-name! renderer indicator "check"))
            (do
              (Webapi.Dom.Element.removeAttribute "data-name" indicator)
              (set-style! indicator "--lui-icon-image" "none")
              (Webapi.Dom.Element.setTextContent indicator (str (inc index)))))
          (if (= index (dec count))
            (Webapi.Dom.Element.setAttribute "hidden" "" (child-element step 2))
            (Webapi.Dom.Element.removeAttribute "hidden" (child-element step 2)))
          (recur (inc index)))))
    (Stdlib.ignore true)))

(defn- update-stepper-parent! [renderer node]
  (if-some [current (retained/node (:web-store renderer) node)]
    (match (:retained-parent current)
      (Some parent)
      (if-some [parent-node (retained/node (:web-store renderer) parent)]
        (when (standard-kind? parent-node Stepper)
          (update-stepper! renderer parent))
        (Stdlib.ignore true))
      None (Stdlib.ignore true))
    (Stdlib.ignore true)))

(defn- update-timeline! [renderer node]
  (let [children (retained/children (:web-store renderer) node)
        count (count children)]
    (loop [index 0]
      (when (< index count)
        (let [item (dom-node renderer (nth children index))]
          (Webapi.Dom.Element.setAttribute
           "aria-posinset" (str (inc index)) item)
          (Webapi.Dom.Element.setAttribute "aria-setsize" (str count) item)
          (recur (inc index)))))
    (Stdlib.ignore true)))

(defn- set-optional-text! [element value]
  (Webapi.Dom.Element.setTextContent element value)
  (if (= value "")
    (Webapi.Dom.Element.setAttribute "hidden" "" element)
    (Webapi.Dom.Element.removeAttribute "hidden" element)))

(defn- update-timeline-indicator! [renderer node dom-node]
  (let [indicator (child-element (child-element dom-node 0) 0)
        icon (string-property renderer node InlineIconName)
        text (string-property renderer node IndicatorValue)]
    (if (not (= icon ""))
      (do
        (Webapi.Dom.Element.setTextContent indicator "")
        (Webapi.Dom.Element.setAttribute "data-name" icon indicator)
        (update-icon-name! renderer indicator icon))
      (do
        (Webapi.Dom.Element.removeAttribute "data-name" indicator)
        (set-style! indicator "--lui-icon-image" "none")
        (Webapi.Dom.Element.setTextContent indicator text)
        (if (= text "")
          (Webapi.Dom.Element.setAttribute "data-dot" "" indicator)
          (Webapi.Dom.Element.removeAttribute "data-dot" indicator))))))

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
     (standard-kind? current Button)
     (match (:retained-parent current)
       (Some parent)
       (if-some [parent-node (retained/node (:web-store renderer) parent)]
         (standard-kind? parent-node Tabs)
         false)
       None false))
    false))

(defn- selected-property [renderer node]
  (match (retained/property (:web-store renderer) node Selected)
    (Some (BoolValue selected)) selected
    _ false))

(defn- refresh-tabs-roving! [store document tabs]
  (let [all-children
        (into
         []
         (filter
          (fn [child]
            (if-some [current (retained/node store child)]
              (standard-kind? current Button)
              false))
          (retained/children store tabs)))
        children
        (into
         []
         (filter
          (fn [child]
            (not (= (retained/property store child Enabled)
                    (Some (BoolValue false)))))
          all-children))
        html-document (Webapi.Dom.Document.unsafeAsHtmlDocument document)
        active
        (if-some [focused (Webapi.Dom.HtmlDocument.activeElement html-document)]
          (loop [index 0]
            (if (>= index (count children))
              None
              (if-some [current (retained/node store (nth children index))]
                (if (Webapi.Dom.Element.isSameNode
                     (Webapi.Dom.Element.asNode (:platform-node current))
                     focused)
                  (Some index)
                  (recur (inc index)))
                (recur (inc index)))))
          None)
        selected
        (loop [index 0]
          (if (>= index (count children))
            0
            (if (= (retained/property store (nth children index) Selected)
                   (Some (BoolValue true)))
              index
              (recur (inc index)))))
        target
        (match active
          (Some index) index
          None selected)]
    (loop [index 0]
      (when (< index (count all-children))
        (if-some [current (retained/node store (nth all-children index))]
          (Webapi.Dom.Element.setAttribute
           "tabindex" "-1" (:platform-node current))
          (Stdlib.ignore true))
        (recur (inc index))))
    (loop [index 0]
      (when (< index (count children))
        (if-some [current (retained/node store (nth children index))]
          (Webapi.Dom.Element.setAttribute
           "tabindex" (if (= index target) "0" "-1")
           (:platform-node current))
          (Stdlib.ignore true))
        (recur (inc index))))
    (Stdlib.ignore true)))

(defn- refresh-button-context! [renderer node]
  (if-some [current (retained/node (:web-store renderer) node)]
    (when (standard-kind? current Button)
      (let [element (:platform-node current)
            selected (selected-property renderer node)]
        (if (direct-tab-trigger? renderer node)
          (do
            (Webapi.Dom.Element.setAttribute "role" "tab" element)
            (Webapi.Dom.Element.setAttribute
             "aria-selected" (if selected "true" "false") element)
            (Webapi.Dom.Element.removeAttribute "aria-pressed" element)
            (match (:retained-parent current)
              (Some parent)
              (refresh-tabs-roving!
               (:web-store renderer) (:web-document renderer) parent)
              None (Stdlib.ignore true)))
          (do
            (Webapi.Dom.Element.removeAttribute "role" element)
            (Webapi.Dom.Element.removeAttribute "aria-selected" element)
            (match (retained/property (:web-store renderer) node Selected)
              (Some (BoolValue _))
              (Webapi.Dom.Element.setAttribute
               "aria-pressed" (if selected "true" "false") element)
              _ (Webapi.Dom.Element.removeAttribute "aria-pressed" element))))))
    (Stdlib.ignore true)))

(defn- refresh-node-class! [renderer node kind dom-node]
  (let [style-class
        (match (retained/property (:web-store renderer) node StyleClass)
          (Some (StringValue value)) value
          _ "")
        tree-class (if (treeitem? renderer node) "lui-tree-item" "")]
    (Webapi.Dom.Element.setClassName
     (if (= kind DropdownMenu) (child-element dom-node 0) dom-node)
     (string/trim
      (str (base-class-name kind) " " tree-class " " style-class)))))

(defn- set-text-control-value! [dom-node text]
  (let [control (text-control-node dom-node)]
    (when (not (= text (Webapi.Dom.HtmlInputElement.value control)))
      (Webapi.Dom.HtmlInputElement.setValue control text))))

(defn- set-visible-text! [kind dom-node text]
  (let [target
        (if (direct-toggle? kind)
          (toggle-label-node dom-node)
          (if (or (button-like? kind) (= kind MenuItem))
            (button-label-node dom-node)
            dom-node))]
    (when (not (= text (Webapi.Dom.Element.textContent target)))
      (Webapi.Dom.Element.setTextContent target text))))

(defn- apply-text-value! [renderer node kind dom-node text]
  (match kind
    Alert
    (Webapi.Dom.Element.setTextContent (child-element dom-node 0) text)
    Bubble
    (Webapi.Dom.Element.setTextContent (child-element dom-node 1) text)
    Accordion
    (Webapi.Dom.Element.setTextContent
     (accordion-label-node dom-node) text)
    Step
    (do
      (Webapi.Dom.Element.setTextContent (child-element dom-node 1) text)
      (update-stepper-parent! renderer node))
    Dialog
    (Webapi.Dom.Element.setTextContent (child-element dom-node 0) text)
    Sheet
    (Webapi.Dom.Element.setTextContent (child-element dom-node 0) text)
    Avatar
    (do
      (Webapi.Dom.Element.setTextContent (child-element dom-node 1) text)
      (update-avatar! renderer node dom-node))
    Select
    (Webapi.Dom.Element.setTextContent
     (child-element dom-node 0) (select-display-text renderer node))
    TextField (set-text-control-value! dom-node text)
    Input (set-text-control-value! dom-node text)
    SearchField (set-text-control-value! dom-node text)
    Textarea (set-text-control-value! dom-node text)
    Combobox (set-text-control-value! dom-node text)
    _ (set-visible-text! kind dom-node text)))

(defn- apply-property! [renderer node kind dom-node property value]
  (match (tuple property value)
    (tuple TextValue (StringValue text))
    (apply-text-value! renderer node kind dom-node text)

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
        (set-state-attribute! dom-node "data-disabled" (not enabled)))
      (when (treeitem? renderer node)
        (Webapi.Dom.Element.setAttribute
         "aria-disabled" (if enabled "false" "true") dom-node)))

    (tuple Gap (IntValue gap))
    (do
      (if (= kind Split)
        (update-split! renderer node)
        (set-style! dom-node "gap" (str gap "px")))
      (when (= kind TableRow)
        (set-style! dom-node "--lui-table-gap" (str gap "px"))))

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
    (do
      (set-style! dom-node "width" (str width "px"))
      (when (= kind Image) (update-image! renderer node dom-node))
      (when (= kind Bubble)
        (Webapi.Dom.Element.setAttribute "data-width" "explicit" dom-node)))

    (tuple HeightValue (IntValue height))
    (do
      (set-style! dom-node "height" (str height "px"))
      (when (= kind Image) (update-image! renderer node dom-node)))

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
    (if (= kind Split)
      (Webapi.Dom.Element.setAttribute
       "aria-label" (str label " divider") (child-element dom-node 1))
      (Webapi.Dom.Element.setAttribute
       "aria-label" label
       (if (direct-toggle? kind)
         (child-element dom-node 0)
         dom-node)))

    (tuple StyleClass (StringValue _class-name))
    (refresh-node-class! renderer node kind dom-node)

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
    (if (= kind Split)
      (reconcile-split! renderer node dom-node value)
      (if (= kind Progress)
        (update-progress! renderer node dom-node)
        (Webapi.Dom.HtmlInputElement.setValue
         (text-control-node dom-node) (str value))))

    (tuple ResizeDuration (IntValue _duration))
    (update-split! renderer node)

    (tuple ResizeEasing (StringValue _easing))
    (update-split! renderer node)

    (tuple ResizeOrigin (FloatValue _origin))
    (update-split! renderer node)

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
    (if (= kind TimelineItem)
      (update-timeline-indicator! renderer node dom-node)
      (let [icon
            (if (= kind ListItem)
              dom-node
              (button-icon-node dom-node))]
        (Webapi.Dom.Element.setAttribute "data-name" name icon)
        (update-icon-name! renderer icon name)))

    (tuple IconPlacementValue (StringValue placement))
    (Webapi.Dom.Element.setAttribute "data-icon-placement" placement dom-node)

    (tuple Selected (BoolValue selected))
    (if (= kind Accordion)
      (set-accordion-open! renderer dom-node selected)
      (if (or (= kind TableRow) (= kind TimelineItem)
              (treeitem? renderer node))
        (do
          (set-state-attribute! dom-node "data-selected" selected)
          (Webapi.Dom.Element.setAttribute
           "aria-selected" (if selected "true" "false") dom-node))
        (do
          (set-state-attribute! dom-node "data-selected" selected)
          (Webapi.Dom.Element.setAttribute
           (if (or (= kind MenuItem) (direct-tab-trigger? renderer node))
             "aria-selected"
             "aria-pressed")
           (if selected "true" "false") dom-node))))

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
            (Webapi.Dom.Element.removeAttribute "tabindex" dom-node))))
      (when (= kind TableCell)
        (set-state-attribute! dom-node "data-pressable" enabled)
        (if enabled
          (Webapi.Dom.Element.setAttribute "tabindex" "0" dom-node)
          (Webapi.Dom.Element.removeAttribute "tabindex" dom-node)))
      (when (= kind TimelineItem)
        (set-state-attribute! dom-node "data-pressable" enabled)
        (if enabled
          (do
            (Webapi.Dom.Element.setAttribute "tabindex" "0" dom-node)
            (Webapi.Dom.Element.removeAttribute
             "hidden" (child-element dom-node 2)))
          (do
            (Webapi.Dom.Element.removeAttribute "tabindex" dom-node)
            (Webapi.Dom.Element.setAttribute
             "hidden" "" (child-element dom-node 2))))))

    (tuple RoleValue (StringValue role))
    (do
      (Webapi.Dom.Element.setAttribute "role" role dom-node)
      (Webapi.Dom.Element.removeAttribute "aria-pressed" dom-node)
      (refresh-node-class! renderer node kind dom-node))

    (tuple TreeLevel (IntValue level))
    (Webapi.Dom.Element.setAttribute "aria-level" (str level) dom-node)

    (tuple Expanded (BoolValue expanded))
    (do
      (set-state-attribute! dom-node "data-expanded" expanded)
      (Webapi.Dom.Element.setAttribute
       "aria-expanded" (if expanded "true" "false") dom-node))

    (tuple SubmitEnabled (BoolValue enabled))
    (set-state-attribute! dom-node "data-submit-enabled" enabled)

    (tuple DoublePressEnabled (BoolValue enabled))
    (set-state-attribute! dom-node "data-double-press-enabled" enabled)

    (tuple ImageIdValue (IntValue _image-id))
    (if (= kind Avatar)
      (update-avatar! renderer node dom-node)
      (update-image! renderer node dom-node))

    (tuple SurfaceIdValue (IntValue _surface-id))
    (update-media-surface! renderer node dom-node)

    (tuple ActiveIndex (IntValue _active))
    (update-stepper! renderer node)

    (tuple TitleValue (StringValue title))
    (do
      (Webapi.Dom.Element.setTextContent
       (child-element (child-element dom-node 1) 0) title)
      (Webapi.Dom.Element.setAttribute "aria-label" title dom-node))

    (tuple DescriptionValue (StringValue description))
    (set-optional-text!
     (child-element (child-element dom-node 1) 1) description)

    (tuple MetaValue (StringValue meta))
    (set-optional-text!
     (child-element (child-element dom-node 1) 2) meta)

    (tuple IndicatorValue (StringValue _indicator))
    (update-timeline-indicator! renderer node dom-node)

    (tuple Connector (BoolValue connector))
    (set-state-attribute!
     (child-element (child-element dom-node 0) 1) "hidden" (not connector))

    (tuple SourceX (FloatValue _value))
    (if (= kind Avatar)
      (update-avatar! renderer node dom-node)
      (update-image! renderer node dom-node))

    (tuple SourceY (FloatValue _value))
    (if (= kind Avatar)
      (update-avatar! renderer node dom-node)
      (update-image! renderer node dom-node))

    (tuple SourceWidth (FloatValue _value))
    (if (= kind Avatar)
      (update-avatar! renderer node dom-node)
      (update-image! renderer node dom-node))

    (tuple SourceHeight (FloatValue _value))
    (if (= kind Avatar)
      (update-avatar! renderer node dom-node)
      (update-image! renderer node dom-node))

    (tuple AnchorValue (StringValue anchor))
    (do
      (Webapi.Dom.Element.setAttribute "data-anchor" anchor dom-node)
      (when (= kind Tooltip)
        (Webapi.Dom.Element.setAttribute
         "data-anchor-alignment" "start" dom-node)))

    (tuple AnchorAlignmentValue (StringValue alignment))
    (Webapi.Dom.Element.setAttribute
     "data-anchor-alignment" alignment dom-node)

    (tuple AnchorOffset (FloatValue offset))
    (do
      (set-style! dom-node "--lui-anchor-offset" (str offset "px"))
      (when (= kind Tooltip)
        (Webapi.Dom.Element.setAttribute
         "data-anchor-offset" (str offset) dom-node)))

    (tuple TooltipDelay (IntValue delay))
    (Webapi.Dom.Element.setAttribute
     "data-tooltip-delay" (str delay) dom-node)

    (tuple DurationValue (IntValue duration))
    (Webapi.Dom.Element.setAttribute
     "data-duration" (str duration) dom-node)

    (tuple TextAlignment (StringValue alignment))
    (if (= kind Bubble)
      (Webapi.Dom.Element.setAttribute
       "data-reactions-alignment" alignment dom-node)
      (set-style! dom-node "text-align" alignment))

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

(defn- document-body [renderer]
  (let [document
        (Webapi.Dom.Document.unsafeAsHtmlDocument (:web-document renderer))]
    (if-some [body (Webapi.Dom.HtmlDocument.body document)]
      body
      (raise (Invalid_argument "document body is unavailable")))))

(defn- context-menu-node? [nodes node]
  (if-some [current (clojure.core/get nodes node)]
    (standard-kind? current ContextMenu)
    false))

(defn- dropdown-node? [nodes node]
  (if-some [current (clojure.core/get nodes node)]
    (standard-kind? current DropdownMenu)
    false))

(defn- modal-node? [nodes node]
  (if-some [current (clojure.core/get nodes node)]
    (if-some [kind (retained/standard-kind current)]
      (modal-surface? kind)
      false)
    false))

(defn- toast-node? [nodes node]
  (if-some [current (clojure.core/get nodes node)]
    (standard-kind? current Toast)
    false))

(defn- modal-layer-node [surface]
  (if-some [layer (Webapi.Dom.Element.parentElement surface)]
    layer
    (raise (Invalid_argument "modal surface requires a portal layer"))))

(defn- anchored-tooltip? [current]
  (and
   (standard-kind? current Tooltip)
   (contains? (:retained-properties current) AnchorValue)))

(defn- anchored-tooltip-node? [nodes node]
  (if-some [current (clojure.core/get nodes node)]
    (anchored-tooltip? current)
    false))

(defn- visible-child-index [renderer parent index]
  (if-some [current (retained/node (:web-store renderer) parent)]
    (loop [source-index 0
           result 0]
      (if (= source-index index)
        result
        (let [child (nth (:retained-children current) source-index)]
          (recur
           (inc source-index)
           (if-some [child-node
                     (retained/node (:web-store renderer) child)]
             (if (or (standard-kind? child-node ContextMenu)
                     (standard-kind? child-node DropdownMenu)
                     (standard-kind? child-node Toast)
                     (anchored-tooltip? child-node)
                     (if-some [kind (retained/standard-kind child-node)]
                       (modal-surface? kind)
                       false))
               result
               (inc result))
             result)))))
    index))

(defn- content-container [kind dom-node]
  (if (= kind DropdownMenu)
    (child-element dom-node 0)
    (if (= kind Split)
      (child-element dom-node 0)
      (if (= kind Alert)
        (child-element dom-node 1)
        (if (= kind Bubble)
          (child-element dom-node 0)
          (if (or (= kind Accordion) (modal-surface? kind))
            (if (= kind Accordion)
              (accordion-panel-node dom-node)
              (child-element dom-node 1))
            dom-node))))))

(defn- retained-content-container [current dom-node]
  (match (retained/standard-kind current)
    (Some kind) (content-container kind dom-node)
    None dom-node))

(defn- dom-child-container [renderer node dom-node]
  (if-some [current (retained/node (:web-store renderer) node)]
    (retained-content-container current dom-node)
    dom-node))

(defn- dom-child-container-before
  [renderer previous-nodes node dom-node]
  (if-some [current (retained/node (:web-store renderer) node)]
    (retained-content-container current dom-node)
    (if-some [previous (clojure.core/get previous-nodes node)]
      (retained-content-container previous dom-node)
      dom-node)))

(defn- dropdown-anchor-node [renderer node]
  (if-some [current (retained/node (:web-store renderer) node)]
    (match (:retained-parent current)
      (Some parent)
      (if-some [parent-node (retained/node (:web-store renderer) parent)]
        (if (standard-kind? parent-node MenuItem)
          (:platform-node parent-node)
          (let [container
                (retained-content-container
                 parent-node (:platform-node parent-node))
                children (Webapi.Dom.Element.children container)
                length (html-collection/length children)]
            (if (> length 0)
              (if-some [anchor (html-collection/item (dec length) children)]
                anchor
                container)
              container)))
        (raise (Invalid_argument "dropdown parent is unavailable")))
      None (raise (Invalid_argument "dropdown requires an anchor parent")))
    (raise (Invalid_argument "unknown dropdown node"))))

(defn- dropdown-side [dom-node]
  (match (Webapi.Dom.Element.getAttribute "data-anchor" dom-node)
    (Some value) value
    None "below"))

(defn- dropdown-offset [renderer node]
  (match (retained/property (:web-store renderer) node AnchorOffset)
    (Some (FloatValue value)) value
    _ 0.0))

(defn- dropdown-listbox? [renderer node]
  (not (= (picker-for-dropdown renderer node) None)))

(defn- align-select-item-with-trigger!
  [renderer dropdown positioner popup anchor anchor-bounds]
  (match (picker-for-dropdown renderer dropdown)
    (Some picker)
    (if-some [picker-node (retained/node (:web-store renderer) picker)]
      (let [control (picker-control-element renderer picker)
            open-method
            (match (Webapi.Dom.Element.getAttribute
                    "data-lui-open-method" control)
              (Some value) value
              None "keyboard")
            items (picker-menu-items renderer dropdown)]
        (if (and (standard-kind? picker-node Select)
                 (not (= open-method "touch"))
                 (not (empty? items)))
          (let [root
                (Webapi.Dom.Document.documentElement (:web-document renderer))
                viewport-width
                (Stdlib.float_of_int (Webapi.Dom.Element.clientWidth root))
                viewport-height
                (Stdlib.float_of_int (Webapi.Dom.Element.clientHeight root))
                edge-threshold 20.0]
            (if (or (< (Webapi.Dom.DomRect.top anchor-bounds) edge-threshold)
                    (> (Webapi.Dom.DomRect.bottom anchor-bounds)
                       (- viewport-height edge-threshold)))
              false
              (do
                (set-style! popup "transition" "none")
                (set-style! popup "transform" "none")
                (let [selected
                      (dom-node
                       renderer (nth items (picker-selected-index renderer dropdown)))
                      value (child-element anchor 0)
                      label (child-element selected 1)
                      positioner-bounds
                      (Webapi.Dom.Element.getBoundingClientRect positioner)
                      popup-bounds (Webapi.Dom.Element.getBoundingClientRect popup)
                      value-bounds (Webapi.Dom.Element.getBoundingClientRect value)
                      label-bounds (Webapi.Dom.Element.getBoundingClientRect label)
                      value-center
                      (+ (Webapi.Dom.DomRect.top value-bounds)
                         (/ (Webapi.Dom.DomRect.height value-bounds) 2.0))
                      label-center
                      (+ (Webapi.Dom.DomRect.top label-bounds)
                         (/ (Webapi.Dom.DomRect.height label-bounds) 2.0))
                      left
                      (+ (Webapi.Dom.DomRect.left positioner-bounds)
                         (- (Webapi.Dom.DomRect.left value-bounds)
                            (Webapi.Dom.DomRect.left label-bounds)))
                      top
                      (+ (Webapi.Dom.DomRect.top positioner-bounds)
                         (- value-center label-center))
                      fits
                      (and (>= left 8.0)
                           (<= (+ left (Webapi.Dom.DomRect.width popup-bounds))
                               (- viewport-width 8.0))
                           (>= top 8.0)
                           (<= (+ top (Webapi.Dom.DomRect.height popup-bounds))
                               (- viewport-height 8.0)))]
                  (set-style! popup "transform" "")
                  (set-style! popup "transition" "")
                  (if fits
                    (do
                      (Webapi.Dom.Element.setAttribute
                       "data-side" "none" positioner)
                      (Webapi.Dom.Element.setAttribute "data-side" "none" popup)
                      (set-style! positioner "left" (str left "px"))
                      (set-style! positioner "top" (str top "px"))
                      true)
                    false)))))
          false))
      false)
    None false))

(defn- position-dropdown! [renderer node]
  (let [positioner (dom-node renderer node)
        popup (child-element positioner 0)
        anchor (dropdown-anchor-node renderer node)
        anchor-bounds (Webapi.Dom.Element.getBoundingClientRect anchor)
        visible
        (or (> (Webapi.Dom.DomRect.width anchor-bounds) 0.0)
            (> (Webapi.Dom.DomRect.height anchor-bounds) 0.0))]
    (set-state-attribute! positioner "hidden" (not visible))
    (when visible
      (let [offset (dropdown-offset renderer node)
            side (dropdown-side positioner)
            alignment
            (match (Webapi.Dom.Element.getAttribute
                    "data-anchor-alignment" positioner)
              (Some value) value
              None "start")]
        (position-anchored!
         (:web-document renderer) positioner popup anchor-bounds
         side alignment offset)
        (Stdlib.ignore
         (align-select-item-with-trigger!
          renderer node positioner popup anchor anchor-bounds))))
    (Stdlib.ignore true)))

(defn- point-in-triangle?
  [point-x point-y ax ay bx by cx cy]
  (let [cross-a
        (- (* (- point-x bx) (- ay by))
           (* (- ax bx) (- point-y by)))
        cross-b
        (- (* (- point-x cx) (- by cy))
           (* (- bx cx) (- point-y cy)))
        cross-c
        (- (* (- point-x ax) (- cy ay))
           (* (- cx ax) (- point-y ay)))
        has-negative
        (or (< cross-a 0.0) (< cross-b 0.0) (< cross-c 0.0))
        has-positive
        (or (> cross-a 0.0) (> cross-b 0.0) (> cross-c 0.0))]
    (not (and has-negative has-positive))))

(defn- submenu-corridor?
  [positioner popup leave-x leave-y point-x point-y]
  (let [bounds (Webapi.Dom.Element.getBoundingClientRect popup)
        buffer 4.0
        side
        (match (Webapi.Dom.Element.getAttribute "data-side" positioner)
          (Some value) value
          None (dropdown-side positioner))]
    (match side
      "left"
      (point-in-triangle?
       point-x point-y
       (+ leave-x buffer) leave-y
       (Webapi.Dom.DomRect.right bounds)
       (- (Webapi.Dom.DomRect.top bounds) buffer)
       (Webapi.Dom.DomRect.right bounds)
       (+ (Webapi.Dom.DomRect.bottom bounds) buffer))
      "above"
      (point-in-triangle?
       point-x point-y
       leave-x (+ leave-y buffer)
       (- (Webapi.Dom.DomRect.left bounds) buffer)
       (Webapi.Dom.DomRect.bottom bounds)
       (+ (Webapi.Dom.DomRect.right bounds) buffer)
       (Webapi.Dom.DomRect.bottom bounds))
      "below"
      (point-in-triangle?
       point-x point-y
       leave-x (- leave-y buffer)
       (- (Webapi.Dom.DomRect.left bounds) buffer)
       (Webapi.Dom.DomRect.top bounds)
       (+ (Webapi.Dom.DomRect.right bounds) buffer)
       (Webapi.Dom.DomRect.top bounds))
      _
      (point-in-triangle?
       point-x point-y
       (- leave-x buffer) leave-y
       (Webapi.Dom.DomRect.left bounds)
       (- (Webapi.Dom.DomRect.top bounds) buffer)
       (Webapi.Dom.DomRect.left bounds)
       (+ (Webapi.Dom.DomRect.bottom bounds) buffer)))))

(defn- set-dropdown-open! [renderer node open]
  (let [positioner (dom-node renderer node)
        popup (child-element positioner 0)]
    (if open
      (do
        (begin-popup-open! popup)
        (position-dropdown! renderer node)
        (Webapi.requestAnimationFrame
         (fn [_time]
           (if-some [_current (retained/node (:web-store renderer) node)]
             (position-dropdown! renderer node)
             (Stdlib.ignore true)))))
      (do
        (begin-popup-close! popup)
        (Stdlib.ignore
         (finish-popup-close-after-transition!
          (:web-document renderer) popup 130))))
    (Stdlib.ignore true)))

(defn- mount-dropdown! [renderer node]
  (if-some [current (retained/node (:web-store renderer) node)]
    (do
      (let [popup (child-element (:platform-node current) 0)]
        (Webapi.Dom.Element.setAttribute
         "role" (if (dropdown-listbox? renderer node) "listbox" "menu")
         popup)
        (Webapi.Dom.Element.setAttribute
         "id" (str (node-dom-id node) "-popup") popup))
      (refresh-dropdown-item-roles! renderer node)
      (refresh-combobox-list-state! renderer node)
      (match (:retained-parent current)
      (Some parent)
      (if-some [parent-node (retained/node (:web-store renderer) parent)]
        (if (standard-kind? parent-node MenuItem)
          (let [trigger (:platform-node parent-node)
                positioner (:platform-node current)
                popup (child-element (:platform-node current) 0)
                close-timer (atom None)
                grace-active (atom false)
                grace-x (atom 0.0)
                grace-y (atom 0.0)
                cancel-close!
                (fn []
                  (match (deref close-timer)
                    (Some timer) (Js.Global.clearTimeout timer)
                    None (Stdlib.ignore true))
                  (reset! close-timer None)
                  true)
                close-later!
                (fn []
                  (cancel-close!)
                  (reset!
                   close-timer
                   (Some
                    (Js.Global.setTimeout
                     120
                     :f
                     (fn []
                       (reset! close-timer None)
                       (reset! grace-active false)
                       (Webapi.Dom.Element.setAttribute
                        "aria-expanded" "false" trigger)
                       (set-dropdown-open! renderer node false)))))
                  true)
                open!
                (fn [_event]
                  (cancel-close!)
                  (reset! grace-active false)
                  (Webapi.Dom.Element.setAttribute
                   "aria-expanded" "true" trigger)
                  (set-dropdown-open! renderer node true))
                trigger-leave!
                (fn [event]
                  (let [mouse-event (pointer-mouse-event event)]
                    (reset! grace-active true)
                    (reset!
                     grace-x
                     (Stdlib.float_of_int
                      (Webapi.Dom.MouseEvent.clientX mouse-event)))
                    (reset!
                     grace-y
                     (Stdlib.float_of_int
                      (Webapi.Dom.MouseEvent.clientY mouse-event)))
                    (close-later!))
                  (Stdlib.ignore true))
                popup-leave!
                (fn [_event]
                  (reset! grace-active false)
                  (close-later!)
                  (Stdlib.ignore true))
                pointer-move!
                (fn [event]
                  (when (deref grace-active)
                    (let [mouse-event (pointer-mouse-event event)
                          point-x
                          (Stdlib.float_of_int
                           (Webapi.Dom.MouseEvent.clientX mouse-event))
                          point-y
                          (Stdlib.float_of_int
                           (Webapi.Dom.MouseEvent.clientY mouse-event))]
                      (when (not (submenu-corridor?
                                  positioner popup
                                  (deref grace-x) (deref grace-y)
                                  point-x point-y))
                        (reset! grace-active false))
                      (close-later!)))
                  (Stdlib.ignore true))
                previous-cleanup
                (clojure.core/get (deref (:web-cleanups renderer)) node)]
            (Webapi.Dom.Element.setAttribute
             "data-submenu-trigger" "" trigger)
            (Webapi.Dom.Element.setAttribute "aria-haspopup" "menu" trigger)
            (Webapi.Dom.Element.setAttribute "aria-expanded" "false" trigger)
            (Webapi.Dom.Element.setAttribute
             "data-submenu" "" (:platform-node current))
            (Webapi.Dom.Element.setAttribute
             "role" "menu" (child-element (:platform-node current) 0))
            (Webapi.Dom.Element.addEventListener "mouseenter" open! trigger)
            (Webapi.Dom.Element.addEventListener "focusin" open! trigger)
            (Webapi.Dom.Element.addEventListener
             "mouseleave" trigger-leave! trigger)
            (Webapi.Dom.Element.addEventListener "mouseenter" open! popup)
            (Webapi.Dom.Element.addEventListener
             "mouseleave" popup-leave! popup)
            (Webapi.Dom.Document.addEventListener
             "mousemove" pointer-move! (:web-document renderer))
            (swap!
             (:web-cleanups renderer) assoc node
             (fn []
               (match previous-cleanup
                 (Some cleanup) (cleanup)
                 None (Stdlib.ignore true))
               (cancel-close!)
               (Webapi.Dom.Element.removeEventListener
                "mouseenter" open! trigger)
               (Webapi.Dom.Element.removeEventListener
                "focusin" open! trigger)
               (Webapi.Dom.Element.removeEventListener
                "mouseleave" trigger-leave! trigger)
               (Webapi.Dom.Element.removeEventListener
                "mouseenter" open! popup)
               (Webapi.Dom.Element.removeEventListener
                "mouseleave" popup-leave! popup)
               (Webapi.Dom.Document.removeEventListener
                "mousemove" pointer-move! (:web-document renderer))
               (Stdlib.ignore true)))
            (position-dropdown! renderer node))
          (do
            (set-dropdown-open! renderer node true)
            (match (picker-for-dropdown renderer node)
              (Some picker)
              (let [control (picker-control-element renderer picker)
                    popup-id (str (node-dom-id node) "-popup")
                    previous-cleanup
                    (clojure.core/get (deref (:web-cleanups renderer)) node)]
                (Webapi.Dom.Element.setAttribute "aria-controls" popup-id control)
                (if-some [picker-node
                          (retained/node (:web-store renderer) picker)]
                  (if (standard-kind? picker-node Combobox)
                    (Stdlib.ignore
                     (Js.Global.setTimeout
                      0 :f
                      (fn []
                        (if-some [_menu
                                  (retained/node (:web-store renderer) node)]
                          (set-combobox-active! renderer picker node 0)
                          (Stdlib.ignore true))
                        (Stdlib.ignore true))))
                    (Stdlib.ignore
                     (Js.Global.setTimeout
                      0 :f
                      (fn []
                        (if-some [_menu
                                  (retained/node (:web-store renderer) node)]
                          (focus-context-menu-item!
                           renderer node (picker-selected-index renderer node))
                          (Stdlib.ignore true))
                        (Stdlib.ignore true)))))
                  (Stdlib.ignore true))
                (Stdlib.ignore
                 (swap!
                  (:web-cleanups renderer) assoc node
                  (fn []
                    (match previous-cleanup
                      (Some cleanup) (cleanup)
                      None (Stdlib.ignore true))
                    (Webapi.Dom.Element.removeAttribute "aria-controls" control)
                    (Webapi.Dom.Element.removeAttribute
                     "data-lui-active-index" control)
                    (Webapi.Dom.Element.removeAttribute
                     "aria-activedescendant" control)
                    (focus-element! control)
                    (Stdlib.ignore true)))))
              None (Stdlib.ignore true))))
        (raise (Invalid_argument "dropdown parent is unavailable")))
      None (raise (Invalid_argument "dropdown requires an anchor parent"))))
    (raise (Invalid_argument "unknown dropdown node"))))

(defn- open-modal! [renderer node dom-node]
  (let [layer (modal-layer-node dom-node)]
    (when (not (=
                (Webapi.Dom.Element.getAttribute
                 "data-lui-modal-state" layer)
                (Some "open")))
      (Webapi.Dom.Element.removeAttribute "hidden" layer)
      (Webapi.Dom.Element.removeAttribute "inert" layer)
      (Webapi.Dom.Element.removeAttribute "data-closed" layer)
      (Webapi.Dom.Element.removeAttribute "data-ending-style" layer)
      (Webapi.Dom.Element.setAttribute "data-open" "" layer)
      (Webapi.Dom.Element.setAttribute "data-starting-style" "" layer)
      (Webapi.Dom.Element.removeAttribute "data-closed" dom-node)
      (Webapi.Dom.Element.removeAttribute "data-ending-style" dom-node)
      (Webapi.Dom.Element.setAttribute "data-open" "" dom-node)
      (Webapi.Dom.Element.setAttribute "data-starting-style" "" dom-node)
      (Webapi.Dom.Element.setAttribute
       "data-lui-modal-state" "open" layer)
      (swap! (:web-modal-stack renderer) conj node)
      (refresh-modal-host-inert! renderer)
      (Webapi.Dom.HtmlElement.focus
       (Webapi.Dom.Element.unsafeAsHtmlElement dom-node))
      (Webapi.requestAnimationFrame
       (fn [_time]
         (Webapi.Dom.Element.removeAttribute "data-starting-style" layer)
         (Webapi.Dom.Element.removeAttribute "data-starting-style" dom-node))))
    (Stdlib.ignore true)))

(defn- radio-group-ancestor [renderer node]
  (if-some [current (retained/node (:web-store renderer) node)]
    (match (:retained-parent current)
      (Some parent)
      (if-some [parent-node (retained/node (:web-store renderer) parent)]
        (if (standard-kind? parent-node RadioGroup)
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
  (if-some [parent-node (retained/node (:web-store renderer) parent)]
    (doseq [child (:retained-children parent-node)]
      (if-some [current (retained/node (:web-store renderer) child)]
        (match (standard-kind current)
          Select
          (Webapi.Dom.Element.setAttribute
           "aria-expanded" (if expanded "true" "false")
           (:platform-node current))
          Combobox
          (Webapi.Dom.Element.setAttribute
           "aria-expanded" (if expanded "true" "false")
           (child-element (:platform-node current) 0))
          _ (Stdlib.ignore true))
        (Stdlib.ignore true)))
    (Stdlib.ignore true)))

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

(defn- refresh-structured-children! [renderer parent]
  (if-some [current (retained/node (:web-store renderer) parent)]
    (match (retained/standard-kind current)
      (Some Stepper) (update-stepper! renderer parent)
      (Some Timeline) (update-timeline! renderer parent)
      _ (Stdlib.ignore true))
    (Stdlib.ignore true)))

(defn- remove-modal-layer-after-exit!
  [document parent layer surface kind]
  (let [transition-target
        (if (= kind Sheet) surface (child-element layer 0))
        duration (if (= kind Sheet) 470 170)]
    (after-transition!
     document transition-target duration true
     (fn []
       (when (Webapi.Dom.Element.contains
              (Webapi.Dom.Element.asNode layer) parent)
         (Stdlib.ignore
          (Webapi.Dom.Element.removeChild
           (Webapi.Dom.Element.asNode layer) parent)))
       (Webapi.Dom.Element.removeAttribute "data-ending-style" surface)
       true))))

(defn- remove-dropdown-after-exit! [document parent positioner]
  (let [popup (child-element positioner 0)]
    (begin-popup-close! popup)
    (Webapi.Dom.Element.setAttribute "inert" "" popup)
    (after-transition!
     document popup 130 true
     (fn []
       (when (Webapi.Dom.Element.contains
              (Webapi.Dom.Element.asNode positioner) parent)
         (Stdlib.ignore
          (Webapi.Dom.Element.removeChild
           (Webapi.Dom.Element.asNode positioner) parent)))
       true))))

(defn- remove-property! [renderer node property]
  (if-some [current (retained/node (:web-store renderer) node)]
    (let [kind (standard-kind current)
          dom-node (:platform-node current)]
      (match property
        TextValue (apply-text-value! renderer node kind dom-node "")
        Enabled
        (apply-property!
         renderer node kind dom-node Enabled (BoolValue true))
        Gap (set-style! dom-node "gap" "")
        MainAlignment (set-style! dom-node "justify-content" "")
        CrossAlignment (set-style! dom-node "align-items" "")
        GrowValue (set-style! dom-node "flex-grow" "")
        GridColumns
        (do
          (set-style! dom-node "grid-auto-flow" "")
          (set-style! dom-node "grid-auto-columns" "")
          (set-style! dom-node "grid-template-columns" ""))
        PaddingValue (set-style! dom-node "padding" "")
        PaddingHorizontal (set-style! dom-node "padding-inline" "")
        PaddingVertical (set-style! dom-node "padding-block" "")
        BackgroundValue (set-style! dom-node "background" "")
        ForegroundValue (set-style! dom-node "color" "")
        BorderColorValue (set-style! dom-node "border-color" "")
        BorderWidth
        (do
          (set-style! dom-node "border-style" "")
          (set-style! dom-node "border-width" ""))
        CornerRadius (set-style! dom-node "border-radius" "")
        WidthValue (set-style! dom-node "width" "")
        HeightValue (set-style! dom-node "height" "")
        MinWidth (set-style! dom-node "min-width" "")
        MaxWidth (set-style! dom-node "max-width" "")
        MinHeight (set-style! dom-node "min-height" "")
        MaxHeight (set-style! dom-node "max-height" "")
        PlaceholderValue
        (Webapi.Dom.HtmlInputElement.setPlaceholder
         (text-control-node dom-node) "")
        AccessibilityLabel
        (Webapi.Dom.Element.removeAttribute
         "aria-label"
         (if (direct-toggle? kind) (child-element dom-node 0) dom-node))
        OrientationValue
        (when (= kind Tabs)
          (Webapi.Dom.Element.setAttribute
           "data-orientation" "horizontal" dom-node)
          (Webapi.Dom.Element.setAttribute
           "aria-orientation" "horizontal" dom-node))
        StyleClass (refresh-node-class! renderer node kind dom-node)
        _ (Stdlib.ignore true)))
    (raise (Invalid_argument "unknown DOM node"))))

(defn- apply-dom-op! [renderer previous-nodes operation]
  (match operation
    (CreateNode node kind)
    (let [created (dom-node renderer node)]
      (Webapi.Dom.Element.setAttribute "id" (node-dom-id node) created)
      (when (= kind Accordion)
        (initialize-accordion-semantics! node created))
      (attach-events! renderer node kind created))

    (CreateExtension node _identifier _fingerprint)
    (Webapi.Dom.Element.setAttribute
     "id" (node-dom-id node) (dom-node renderer node))

    (DropNode node)
    (do
      (cleanup-extension-node! renderer previous-nodes node)
      (cleanup-node! renderer node))

    (SetProp node property value)
    (if-some [current (retained/node (:web-store renderer) node)]
      (do
        (apply-property!
         renderer node (standard-kind current) (:platform-node current)
         property value)
        (match (:retained-parent current)
          (Some parent)
          (do
            (when (= property MinWidth) (update-split! renderer parent))
            (if-some [parent-node
                      (retained/node (:web-store renderer) parent)]
              (do
                (when
                 (and
                  (standard-kind? parent-node Tabs)
                  (or (= property Selected) (= property Enabled)))
                  (refresh-tabs-roving!
                   (:web-store renderer) (:web-document renderer) parent))
                (when (standard-kind? parent-node DropdownMenu)
                  (Stdlib.ignore
                   (refresh-combobox-list-state! renderer parent))))
              (Stdlib.ignore true)))
          None (Stdlib.ignore true)))
      (raise (Invalid_argument "unknown DOM node")))

    (RemoveProp node property)
    (do
      (remove-property! renderer node property)
      (if-some [current (retained/node (:web-store renderer) node)]
        (match (:retained-parent current)
          (Some parent)
          (if-some [parent-node (retained/node (:web-store renderer) parent)]
            (when
             (and
              (standard-kind? parent-node Tabs)
              (or (= property Selected) (= property Enabled)))
              (refresh-tabs-roving!
               (:web-store renderer) (:web-document renderer) parent))
            (Stdlib.ignore true))
          None (Stdlib.ignore true))
        (Stdlib.ignore true)))

    (SetExtensionProp node property value)
    (apply-extension-property! renderer node property value)

    (RemoveExtensionProp node property)
    (remove-extension-property! renderer node property)

    (InsertChild parent child index)
    (do
      (if-some [current (retained/node (:web-store renderer) child)]
        (if-some [kind (retained/standard-kind current)]
          (cond
            (= kind Toast)
            (Webapi.Dom.Element.appendChild
             (Webapi.Dom.Element.asNode (dom-node renderer child))
             (:web-toast-viewport renderer))
            (= kind DropdownMenu)
            (Webapi.Dom.Element.appendChild
             (Webapi.Dom.Element.asNode (dom-node renderer child))
             (:web-portal-root renderer))
            (anchored-tooltip? current)
            (Webapi.Dom.Element.appendChild
             (Webapi.Dom.Element.asNode (dom-node renderer child))
             (:web-portal-root renderer))
            (modal-surface? kind)
            (Webapi.Dom.Element.appendChild
             (Webapi.Dom.Element.asNode
              (modal-layer-node (dom-node renderer child)))
             (:web-portal-root renderer))
            (= kind ContextMenu)
            (Webapi.Dom.Element.appendChild
             (Webapi.Dom.Element.asNode (dom-node renderer child))
             (document-body renderer))
            :else
            (insert-dom-child!
             (dom-child-container renderer parent (dom-node renderer parent))
             (dom-node renderer child)
             (visible-child-index renderer parent index)))
          (insert-dom-child!
           (dom-child-container renderer parent (dom-node renderer parent))
           (dom-node renderer child)
           (visible-child-index renderer parent index)))
        (raise (Invalid_argument "unknown DOM child")))
      (update-split! renderer parent)
      (refresh-button-context! renderer child)
      (update-split! renderer parent)
      (refresh-structured-children! renderer parent)
      (if-some [current (retained/node (:web-store renderer) child)]
        (do
          (when (standard-kind? current MenuItem)
            (if-some [parent-node
                      (retained/node (:web-store renderer) parent)]
              (when
               (or
                (standard-kind? parent-node ContextMenu)
                (and
                 (standard-kind? parent-node DropdownMenu)
                 (not (dropdown-listbox? renderer parent)))
                (Webapi.Dom.Element.setAttribute
                 "role" "menuitem" (:platform-node current))
                (Webapi.Dom.Element.removeAttribute
                 "aria-selected" (:platform-node current))))
              (Stdlib.ignore true)))
          (match (retained/standard-kind current)
            (Some Radio) (update-radio-group! renderer child)
            (Some DropdownMenu)
            (do
              (update-picker-expanded! renderer parent true)
              (mount-dropdown! renderer child))
            (Some Dialog)
            (open-modal! renderer child (:platform-node current))
            (Some Sheet)
            (open-modal! renderer child (:platform-node current))
            (Some Tooltip)
            (when (anchored-tooltip? current)
              (mount-tooltip! renderer child (:platform-node current)))
            (Some Toast)
            (mount-toast! renderer child (:platform-node current))
            _ (Stdlib.ignore true)))
        (Stdlib.ignore true))
      (if-some [parent-node (retained/node (:web-store renderer) parent)]
        (when (standard-kind? parent-node DropdownMenu)
          (refresh-dropdown-item-roles! renderer parent)
          (Stdlib.ignore
           (refresh-combobox-list-state! renderer parent)))
        (Stdlib.ignore true)))

    (RemoveChild parent child)
    (do
      (let [surface (dom-node-before renderer previous-nodes child)
            modal (modal-node? previous-nodes child)
            child-node (if modal (modal-layer-node surface) surface)
            parent-node
            (if (toast-node? previous-nodes child)
              (:web-toast-viewport renderer)
              (if (or (dropdown-node? previous-nodes child)
                      modal
                      (anchored-tooltip-node? previous-nodes child))
                (:web-portal-root renderer)
                (if (context-menu-node? previous-nodes child)
                  (document-body renderer)
                  (dom-child-container-before
                   renderer previous-nodes parent
                   (dom-node-before renderer previous-nodes parent)))))]
        (if modal
          (if-some [previous (clojure.core/get previous-nodes child)]
            (Stdlib.ignore
             (remove-modal-layer-after-exit!
              (:web-document renderer)
              parent-node child-node surface (standard-kind previous)))
            (Stdlib.ignore true))
          (if (dropdown-node? previous-nodes child)
            (Stdlib.ignore
             (remove-dropdown-after-exit!
              (:web-document renderer) parent-node child-node))
            (Stdlib.ignore
             (Webapi.Dom.Element.removeChild
              (Webapi.Dom.Element.asNode child-node) parent-node)))))
      (refresh-button-context! renderer child)
      (refresh-structured-children! renderer parent)
      (if-some [previous (clojure.core/get previous-nodes child)]
        (when (standard-kind? previous DropdownMenu)
          (update-picker-expanded! renderer parent false)
          (if-some [parent-node (clojure.core/get previous-nodes parent)]
            (when (standard-kind? parent-node MenuItem)
              (Webapi.Dom.Element.removeAttribute
               "data-submenu-trigger" (:platform-node parent-node))
              (Webapi.Dom.Element.removeAttribute
               "aria-haspopup" (:platform-node parent-node))
              (Webapi.Dom.Element.removeAttribute
               "aria-expanded" (:platform-node parent-node)))
            (Stdlib.ignore true)))
        (Stdlib.ignore true))
      (if-some [parent-node (retained/node (:web-store renderer) parent)]
        (when (standard-kind? parent-node DropdownMenu)
          (refresh-dropdown-item-roles! renderer parent)
          (Stdlib.ignore
           (refresh-combobox-list-state! renderer parent)))
        (Stdlib.ignore true)))

    (MoveChild parent child index)
    (let [dropdown (dropdown-node? previous-nodes child)
          modal (modal-node? previous-nodes child)
          tooltip (anchored-tooltip-node? previous-nodes child)
          toast (toast-node? previous-nodes child)
          metadata (context-menu-node? previous-nodes child)
          parent-node
          (if toast
            (:web-toast-viewport renderer)
            (if (or dropdown modal tooltip)
              (:web-portal-root renderer)
              (if metadata
                (document-body renderer)
                (dom-child-container-before
                 renderer previous-nodes parent
                 (dom-node-before renderer previous-nodes parent)))))
          surface-node (dom-node-before renderer previous-nodes child)
          child-node (if modal (modal-layer-node surface-node) surface-node)
          focused (focused-descendant renderer surface-node)]
      (Stdlib.ignore
       (Webapi.Dom.Element.removeChild
        (Webapi.Dom.Element.asNode child-node) parent-node))
      (if (or dropdown modal tooltip toast metadata)
        (Webapi.Dom.Element.appendChild
         (Webapi.Dom.Element.asNode child-node) parent-node)
        (insert-dom-child!
         parent-node child-node (visible-child-index renderer parent index)))
      (update-split! renderer parent)
      (refresh-structured-children! renderer parent)
      (if-some [parent-node (retained/node (:web-store renderer) parent)]
        (when (standard-kind? parent-node DropdownMenu)
          (refresh-dropdown-item-roles! renderer parent)
          (Stdlib.ignore
           (refresh-combobox-list-state! renderer parent)))
        (Stdlib.ignore true))
      (when dropdown (position-dropdown! renderer child))
      (when (and tooltip
                 (Webapi.Dom.Element.hasAttribute "data-open" surface-node))
        (position-tooltip! renderer child))
      (restore-focus! renderer focused))))

(defn- apply-dom-batch! [renderer previous-nodes batch]
  (doseq [operation (:ops batch)]
    (apply-dom-op! renderer previous-nodes operation))
  (update-all-horizontal-group-roving! renderer)
  (update-all-tree-roving! renderer)
  (update-all-toolbar-roving! renderer)
  (Stdlib.ignore true))

(defn backend [renderer]
  (record proto/backend
          (backend-profile (proto/profile proto/WebOS proto/WebHost))
          (apply-batch
           (fn [batch]
             (let [previous-nodes
                   (retained/nodes (:web-store renderer))]
               (retained/apply-batch-with-extensions!
                (:web-store renderer)
                (fn [kind] (platform-node renderer kind))
                (fn [node identifier]
                  (extension-platform-node renderer node identifier))
                (:web-extension-registry renderer)
                (fn [_batch] true)
                batch)
               (apply-dom-batch! renderer previous-nodes batch)
               true)))))

(defn mount! [renderer root host]
  (Webapi.Dom.Element.appendChild
   (Webapi.Dom.Element.asNode (dom-node renderer root)) host)
  (update-splits-under! renderer root))

(defn- first-section-title [renderer node]
  (if-some [current (retained/node (:web-store renderer) node)]
    (let [kind (standard-kind current)
          title (retained/property (:web-store renderer) node TextValue)]
      (if (and
           (or (= kind Heading) (= kind Text))
           (match title
             (Some (StringValue value)) (not (= value ""))
             _ false))
        (match title
          (Some (StringValue value)) (Some value)
          _ None)
        (let [children (:retained-children current)]
          (loop [index 0]
            (if (= index (count children))
              None
              (if-some [found (first-section-title renderer (nth children index))]
                (Some found)
                (recur (inc index))))))))
    None))

(defn root-sections [renderer root]
  (let [children (retained/children (:web-store renderer) root)]
    (loop [index 0
           result []]
      (if (= index (count children))
        result
        (let [page (nth children index)
              title
              (if-some [found (first-section-title renderer page)]
                found
                (str "Component " page))]
          (recur
           (inc index)
           (conj
            result
            (record root-section
                    (root-section-node page)
                    (root-section-title title)))))))))

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
