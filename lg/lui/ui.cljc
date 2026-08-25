(ns lui.ui
  (:require [signal.core :as sig]
            [lui.protocol :as proto]
            [lui.runtime :as runtime]))

(defn context [application scope]
  (record ui-context
    (ui-application application)
    (ui-scheduler (:runtime-scheduler application))
    (ui-scope scope)
    (ui-profile (:backend-profile (:runtime-backend application)))))

(defn child-context [parent name]
  (context
   (:ui-application parent)
   (sig/scope name (:ui-scope parent))))

(defn profile [context]
  (:ui-profile context))

(defn platform [context]
  (:profile-os (:ui-profile context)))

(defn host [context]
  (:profile-host (:ui-profile context)))

(defn extension! [context identifier]
  (runtime/create-extension-node! (:ui-application context) identifier))

(defn platform-tweak! [context identifier]
  (runtime/create-tweak-node! (:ui-application context) identifier))

(defn extension-property! [context node property value]
  (runtime/set-extension-prop!
   (:ui-application context) node property value))

(defn extension-property-signal! [context node property source]
  (do
    (runtime/bind-extension-prop!
     (:ui-scope context) (:ui-application context) node property source)
    true))

(defn row! [context]
  (runtime/create-node! (:ui-application context) proto/Row))

(defn column! [context]
  (runtime/create-node! (:ui-application context) proto/Column))

(defn grid! [context]
  (runtime/create-node! (:ui-application context) proto/Grid))

(defn stack! [context]
  (runtime/create-node! (:ui-application context) proto/Stack))

(defn panel! [context]
  (runtime/create-node! (:ui-application context) proto/Panel))

(defn card! [context]
  (runtime/create-node! (:ui-application context) proto/Card))

(defn alert! [context]
  (runtime/create-node! (:ui-application context) proto/Alert))

(defn bubble! [context]
  (runtime/create-node! (:ui-application context) proto/Bubble))

(defn box! [context]
  (runtime/create-node! (:ui-application context) proto/Box))

(defn scroll! [context]
  (runtime/create-node! (:ui-application context) proto/Scroll))

(defn list! [context]
  (runtime/create-node! (:ui-application context) proto/ListContainer))

(defn tabs! [context]
  (runtime/create-node! (:ui-application context) proto/Tabs))

(defn button-group! [context]
  (runtime/create-node! (:ui-application context) proto/ButtonGroup))

(defn toggle-group! [context]
  (runtime/create-node! (:ui-application context) proto/ToggleGroup))

(defn breadcrumb! [context]
  (runtime/create-node! (:ui-application context) proto/Breadcrumb))

(defn pagination! [context]
  (runtime/create-node! (:ui-application context) proto/Pagination))

(defn table! [context]
  (runtime/create-node! (:ui-application context) proto/Table))

(defn table-row! [context]
  (runtime/create-node! (:ui-application context) proto/TableRow))

(defn table-cell! [context]
  (runtime/create-node! (:ui-application context) proto/TableCell))

(defn tree! [context]
  (runtime/create-node! (:ui-application context) proto/Tree))

(defn resizable! [context]
  (runtime/create-node! (:ui-application context) proto/Resizable))

(defn split! [context source]
  (let [node (runtime/create-node! (:ui-application context) proto/Split)]
    (runtime/bind-prop!
     (:ui-scope context) (:ui-application context) node proto/ProgressValue
     (sig/own-signal!
      (:ui-scope context)
      (sig/map (fn [value] (proto/FloatValue value)) source)))
    node))

(defn split-literal! [context value]
  (let [node (runtime/create-node! (:ui-application context) proto/Split)]
    (runtime/set-prop!
     (:ui-application context) node proto/ProgressValue
     (proto/FloatValue value))
    node))

(defn status-bar! [context]
  (runtime/create-node! (:ui-application context) proto/StatusBar))

(defn spacer! [context]
  (runtime/create-node! (:ui-application context) proto/Spacer))

(defn spinner! [context]
  (runtime/create-node! (:ui-application context) proto/Spinner))

(defn icon! [context name]
  (let [node (runtime/create-node! (:ui-application context) proto/Icon)]
    (runtime/set-prop!
     (:ui-application context) node proto/IconName (proto/StringValue name))
    node))

(defn text! [context text]
  (let [node (runtime/create-node! (:ui-application context) proto/Text)]
    (runtime/set-prop!
     (:ui-application context) node proto/TextValue
     (proto/StringValue text))
    node))

(defn heading! [context level text]
  (let [node (runtime/create-node! (:ui-application context) proto/Heading)]
    (runtime/set-prop!
     (:ui-application context) node proto/HeadingLevel
     (proto/IntValue level))
    (runtime/set-prop!
     (:ui-application context) node proto/TextValue
     (proto/StringValue text))
    node))

(defn heading-value! [context level source]
  (let [node (runtime/create-node! (:ui-application context) proto/Heading)]
    (runtime/set-prop!
     (:ui-application context) node proto/HeadingLevel
     (proto/IntValue level))
    (runtime/bind-prop!
     (:ui-scope context) (:ui-application context)
     node proto/TextValue source)
    node))

(defn heading-signal! [context level source]
  (heading-value!
   context level
   (sig/own-signal!
    (:ui-scope context)
    (sig/map (fn [text] (proto/StringValue text)) source))))

(defn paragraph! [context text]
  (let [node (runtime/create-node! (:ui-application context) proto/Paragraph)]
    (runtime/set-prop!
     (:ui-application context) node proto/TextValue
     (proto/StringValue text))
    node))

(defn paragraph-value! [context source]
  (let [node (runtime/create-node! (:ui-application context) proto/Paragraph)]
    (runtime/bind-prop!
     (:ui-scope context) (:ui-application context)
     node proto/TextValue source)
    node))

(defn paragraph-signal! [context source]
  (paragraph-value!
   context
   (sig/own-signal!
    (:ui-scope context)
    (sig/map (fn [text] (proto/StringValue text)) source))))

(defn label! [context text]
  (let [node (runtime/create-node! (:ui-application context) proto/Label)]
    (runtime/set-prop!
     (:ui-application context) node proto/TextValue
     (proto/StringValue text))
    node))

(defn label-value! [context source]
  (let [node (runtime/create-node! (:ui-application context) proto/Label)]
    (runtime/bind-prop!
     (:ui-scope context) (:ui-application context)
     node proto/TextValue source)
    node))

(defn label-signal! [context source]
  (label-value!
   context
   (sig/own-signal!
    (:ui-scope context)
    (sig/map (fn [text] (proto/StringValue text)) source))))

(defn text-value! [context source]
  (let [node (runtime/create-node! (:ui-application context) proto/Text)]
    (runtime/bind-prop!
     (:ui-scope context) (:ui-application context)
     node proto/TextValue source)
    node))

(defn text-signal! [context source]
  (text-value!
   context
   (sig/own-signal!
    (:ui-scope context)
    (sig/map (fn [text] (proto/StringValue text)) source))))

(defn text-field! [context]
  (runtime/create-node! (:ui-application context) proto/TextField))

(defn input! [context]
  (runtime/create-node! (:ui-application context) proto/Input))

(defn search-field! [context]
  (runtime/create-node! (:ui-application context) proto/SearchField))

(defn textarea! [context]
  (runtime/create-node! (:ui-application context) proto/Textarea))

(defn select! [context]
  (runtime/create-node! (:ui-application context) proto/Select))

(defn combobox! [context]
  (runtime/create-node! (:ui-application context) proto/Combobox))

(defn dropdown-menu! [context]
  (runtime/create-node! (:ui-application context) proto/DropdownMenu))

(defn context-menu! [context]
  (runtime/create-node! (:ui-application context) proto/ContextMenu))

(defn dialog! [context]
  (runtime/create-node! (:ui-application context) proto/Dialog))

(defn drawer! [context]
  (runtime/create-node! (:ui-application context) proto/Drawer))

(defn sheet! [context]
  (runtime/create-node! (:ui-application context) proto/Sheet))

(defn tooltip! [context]
  (runtime/create-node! (:ui-application context) proto/Tooltip))

(defn accordion! [context]
  (runtime/create-node! (:ui-application context) proto/Accordion))

(defn menu-item! [context]
  (runtime/create-node! (:ui-application context) proto/MenuItem))

(defn list-item! [context]
  (runtime/create-node! (:ui-application context) proto/ListItem))

(defn avatar! [context]
  (runtime/create-node! (:ui-application context) proto/Avatar))

(defn image! [context]
  (runtime/create-node! (:ui-application context) proto/Image))

(defn media-surface! [context]
  (runtime/create-node! (:ui-application context) proto/MediaSurface))

(defn stepper! [context]
  (runtime/create-node! (:ui-application context) proto/Stepper))

(defn step! [context]
  (runtime/create-node! (:ui-application context) proto/Step))

(defn timeline! [context]
  (runtime/create-node! (:ui-application context) proto/Timeline))

(defn timeline-item! [context]
  (runtime/create-node! (:ui-application context) proto/TimelineItem))

(defn input-group! [context]
  (runtime/create-node! (:ui-application context) proto/InputGroup))

(defn input-group-actions! [context]
  (runtime/create-node! (:ui-application context) proto/InputGroupActions))

(defn button! [context]
  (runtime/create-node! (:ui-application context) proto/Button))

(defn toggle-button! [context]
  (runtime/create-node! (:ui-application context) proto/ToggleButton))

(defn toggle! [context]
  (runtime/create-node! (:ui-application context) proto/Toggle))

(defn radio-group! [context]
  (runtime/create-node! (:ui-application context) proto/RadioGroup))

(defn radio! [context]
  (runtime/create-node! (:ui-application context) proto/Radio))

(defn slider! [context source]
  (let [node (runtime/create-node! (:ui-application context) proto/Slider)]
    (runtime/bind-prop!
     (:ui-scope context) (:ui-application context) node proto/ProgressValue
     (sig/own-signal!
      (:ui-scope context)
      (sig/map
       (fn [value] (proto/FloatValue value))
       source)))
    node))

(defn slider-literal! [context value]
  (let [node (runtime/create-node! (:ui-application context) proto/Slider)]
    (runtime/set-prop!
     (:ui-application context) node proto/ProgressValue
     (proto/FloatValue value))
    node))

(defn string-property! [context node property value]
  (runtime/set-prop!
   (:ui-application context) node property (proto/StringValue value)))

(defn string-property-signal! [context node property source]
  (do
    (runtime/bind-prop!
     (:ui-scope context) (:ui-application context) node property
     (sig/own-signal!
      (:ui-scope context)
      (sig/map (fn [value] (proto/StringValue value)) source)))
    true))

(defn bool-property! [context node property value]
  (runtime/set-prop!
   (:ui-application context) node property (proto/BoolValue value)))

(defn bool-property-signal! [context node property source]
  (do
    (runtime/bind-prop!
     (:ui-scope context) (:ui-application context) node property
     (sig/own-signal!
      (:ui-scope context)
      (sig/map (fn [value] (proto/BoolValue value)) source)))
    true))

(defn float-property! [context node property value]
  (runtime/set-prop!
   (:ui-application context) node property (proto/FloatValue value)))

(defn float-property-signal! [context node property source]
  (do
    (runtime/bind-prop!
     (:ui-scope context) (:ui-application context) node property
     (sig/own-signal!
      (:ui-scope context)
      (sig/map (fn [value] (proto/FloatValue value)) source)))
    true))

(defn int-property-signal! [context node property source]
  (do
    (runtime/bind-prop!
     (:ui-scope context) (:ui-application context) node property
     (sig/own-signal!
      (:ui-scope context)
      (sig/map (fn [value] (proto/IntValue value)) source)))
    true))

(defn int-property! [context node property value]
  (runtime/set-prop!
   (:ui-application context) node property (proto/IntValue value)))

(defn disabled! [context node disabled]
  (bool-property! context node proto/Enabled (not disabled)))

(defn disabled-signal! [context node source]
  (do
    (runtime/bind-prop!
     (:ui-scope context) (:ui-application context) node proto/Enabled
     (sig/own-signal!
      (:ui-scope context)
      (sig/map (fn [disabled] (proto/BoolValue (not disabled))) source)))
    true))

(defn checked-signal! [context node source]
  (do
    (runtime/bind-prop!
     (:ui-scope context) (:ui-application context) node proto/Checked
     (sig/own-signal!
      (:ui-scope context)
      (sig/map (fn [checked] (proto/BoolValue checked)) source)))
    true))

(defn text-property! [context node text]
  (do
    (runtime/set-prop!
     (:ui-application context) node proto/TextValue (proto/StringValue text))
    true))

(defn text-property-signal! [context node source]
  (do
    (runtime/bind-prop!
     (:ui-scope context) (:ui-application context) node proto/TextValue
     (sig/own-signal!
      (:ui-scope context)
      (sig/map (fn [text] (proto/StringValue text)) source)))
    true))

(defn on-event! [context node callback]
  (runtime/on-event!
   (:ui-scope context) (:ui-application context) node callback))

(defn checkbox! [context]
  (runtime/create-node! (:ui-application context) proto/Checkbox))

(defn switch-control! [context]
  (runtime/create-node! (:ui-application context) proto/SwitchControl))

(defn progress! [context source]
  (let [node
        (runtime/create-node! (:ui-application context) proto/Progress)]
    (runtime/bind-prop!
     (:ui-scope context) (:ui-application context) node proto/ProgressValue
     (sig/own-signal!
      (:ui-scope context)
      (sig/map (fn [value] (proto/FloatValue value)) source)))
    node))

(defn progress-literal! [context value]
  (let [node
        (runtime/create-node! (:ui-application context) proto/Progress)]
    (runtime/set-prop!
     (:ui-application context) node proto/ProgressValue
     (proto/FloatValue value))
    node))

(defn separator! [context orientation]
  (let [node (runtime/create-node! (:ui-application context) proto/Divider)]
    (runtime/set-prop!
     (:ui-application context) node proto/OrientationValue
     (proto/StringValue orientation))
    node))

(defn size! [context node size]
  (runtime/set-prop!
   (:ui-application context) node proto/SizeValue
   (proto/StringValue size)))

(defn style-class! [context node class-name]
  (runtime/set-prop!
   (:ui-application context) node proto/StyleClass
   (proto/StringValue class-name)))

(defn append! [context parent child]
  (runtime/insert-child!
   (:ui-application context) parent child
   (runtime/child-count (:ui-application context) parent)))

(defn gap! [context node gap]
  (runtime/set-prop!
   (:ui-application context) node proto/Gap (proto/IntValue gap)))

(defn main! [context node alignment]
  (runtime/set-prop!
   (:ui-application context) node proto/MainAlignment
   (proto/StringValue alignment)))

(defn cross! [context node alignment]
  (runtime/set-prop!
   (:ui-application context) node proto/CrossAlignment
   (proto/StringValue alignment)))

(defn grow! [context node grow]
  (runtime/set-prop!
   (:ui-application context) node proto/GrowValue (proto/FloatValue grow)))

(defn columns! [context node columns]
  (runtime/set-prop!
   (:ui-application context) node proto/GridColumns
   (proto/IntValue columns)))

(defn padding! [context node padding]
  (runtime/set-prop!
   (:ui-application context) node proto/PaddingValue
   (proto/IntValue padding)))

(defn padding-horizontal! [context node padding]
  (runtime/set-prop!
   (:ui-application context) node proto/PaddingHorizontal
   (proto/IntValue padding)))

(defn padding-vertical! [context node padding]
  (runtime/set-prop!
   (:ui-application context) node proto/PaddingVertical
   (proto/IntValue padding)))

(defn background! [context node color]
  (runtime/set-prop!
   (:ui-application context) node proto/BackgroundValue
   (proto/StringValue color)))

(defn foreground! [context node color]
  (runtime/set-prop!
   (:ui-application context) node proto/ForegroundValue
   (proto/StringValue color)))

(defn border-color! [context node color]
  (runtime/set-prop!
   (:ui-application context) node proto/BorderColorValue
   (proto/StringValue color)))

(defn border-width! [context node width]
  (runtime/set-prop!
   (:ui-application context) node proto/BorderWidth
   (proto/IntValue width)))

(defn corner-radius! [context node radius]
  (runtime/set-prop!
   (:ui-application context) node proto/CornerRadius
   (proto/IntValue radius)))

(defn width! [context node width]
  (runtime/set-prop!
   (:ui-application context) node proto/WidthValue (proto/IntValue width)))

(defn height! [context node height]
  (runtime/set-prop!
   (:ui-application context) node proto/HeightValue (proto/IntValue height)))

(defn min-width! [context node width]
  (runtime/set-prop!
   (:ui-application context) node proto/MinWidth (proto/IntValue width)))

(defn max-width! [context node width]
  (runtime/set-prop!
   (:ui-application context) node proto/MaxWidth (proto/IntValue width)))

(defn min-height! [context node height]
  (runtime/set-prop!
   (:ui-application context) node proto/MinHeight (proto/IntValue height)))

(defn max-height! [context node height]
  (runtime/set-prop!
   (:ui-application context) node proto/MaxHeight (proto/IntValue height)))

(defn placeholder! [context node placeholder]
  (runtime/set-prop!
   (:ui-application context) node proto/PlaceholderValue
   (proto/StringValue placeholder)))

(defn accessibility-label! [context node label]
  (runtime/set-prop!
   (:ui-application context) node proto/AccessibilityLabel
   (proto/StringValue label)))
