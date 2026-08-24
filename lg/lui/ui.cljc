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

(defn row! [context]
  (runtime/create-node! (:ui-application context) proto/Row))

(defn column! [context]
  (runtime/create-node! (:ui-application context) proto/Column))

(defn grid! [context]
  (runtime/create-node! (:ui-application context) proto/Grid))

(defn box! [context]
  (runtime/create-node! (:ui-application context) proto/Box))

(defn scroll! [context]
  (runtime/create-node! (:ui-application context) proto/Scroll))

(defn spacer! [context]
  (runtime/create-node! (:ui-application context) proto/Spacer))

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

(defn text-input-value! [context source callback]
  (let [node (runtime/create-node! (:ui-application context) proto/TextInput)]
    (runtime/bind-prop!
     (:ui-scope context) (:ui-application context)
     node proto/TextValue source)
    (runtime/on-event!
     (:ui-scope context) (:ui-application context) node callback)
    node))

(defn text-input! [context source callback]
  (text-input-value!
   context
   (sig/own-signal!
    (:ui-scope context)
    (sig/map (fn [text] (proto/StringValue text)) source))
   callback))

(defn text-area-value! [context source callback]
  (let [node (runtime/create-node! (:ui-application context) proto/TextArea)]
    (runtime/bind-prop!
     (:ui-scope context) (:ui-application context)
     node proto/TextValue source)
    (runtime/on-event!
     (:ui-scope context) (:ui-application context) node callback)
    node))

(defn text-area! [context source callback]
  (text-area-value!
   context
   (sig/own-signal!
    (:ui-scope context)
    (sig/map (fn [text] (proto/StringValue text)) source))
   callback))

(defn button! [context label callback]
  (let [node (runtime/create-node! (:ui-application context) proto/Button)]
    (runtime/set-prop!
     (:ui-application context) node proto/TextValue
     (proto/StringValue label))
    (runtime/on-event!
     (:ui-scope context) (:ui-application context) node callback)
    node))

(defn disabled-signal! [context node source]
  (do
    (runtime/bind-prop!
     (:ui-scope context) (:ui-application context) node proto/Enabled
     (sig/own-signal!
      (:ui-scope context)
      (sig/map (fn [disabled] (proto/BoolValue (not disabled))) source)))
    true))

(defn invalid-signal! [context node source]
  (do
    (runtime/bind-prop!
     (:ui-scope context) (:ui-application context) node proto/Invalid
     (sig/own-signal!
      (:ui-scope context)
      (sig/map (fn [invalid] (proto/BoolValue invalid)) source)))
    true))

(defn checked-signal! [context node source]
  (do
    (runtime/bind-prop!
     (:ui-scope context) (:ui-application context) node proto/Checked
     (sig/own-signal!
      (:ui-scope context)
      (sig/map (fn [checked] (proto/BoolValue checked)) source)))
    true))

(defn indeterminate-signal! [context node source]
  (do
    (runtime/bind-prop!
     (:ui-scope context) (:ui-application context) node proto/Indeterminate
     (sig/own-signal!
      (:ui-scope context)
      (sig/map
       (fn [indeterminate] (proto/BoolValue indeterminate)) source)))
    true))

(defn checkbox! [context source callback]
  (let [node (runtime/create-node! (:ui-application context) proto/Checkbox)]
    (checked-signal! context node source)
    (runtime/on-event!
     (:ui-scope context) (:ui-application context) node callback)
    node))

(defn switch-control! [context source callback]
  (let [node
        (runtime/create-node! (:ui-application context) proto/SwitchControl)]
    (checked-signal! context node source)
    (runtime/on-event!
     (:ui-scope context) (:ui-application context) node callback)
    node))

(defn progress-control! [context source minimum maximum]
  (let [node
        (runtime/create-node! (:ui-application context) proto/ProgressControl)]
    (runtime/set-prop!
     (:ui-application context) node proto/MinValue (proto/IntValue minimum))
    (runtime/set-prop!
     (:ui-application context) node proto/MaxValue (proto/IntValue maximum))
    (runtime/bind-prop!
     (:ui-scope context) (:ui-application context) node proto/ProgressValue
     (sig/own-signal!
      (:ui-scope context)
      (sig/map (fn [value] (proto/IntValue value)) source)))
    node))

(defn separator! [context orientation]
  (let [node (runtime/create-node! (:ui-application context) proto/Divider)]
    (runtime/set-prop!
     (:ui-application context) node proto/OrientationValue
     (proto/StringValue orientation))
    node))

(defn labelled-by! [context node label]
  (runtime/set-prop!
   (:ui-application context) node proto/LabelledBy (proto/IntValue label)))

(defn described-by! [context node description]
  (runtime/set-prop!
   (:ui-application context) node proto/DescribedBy
   (proto/IntValue description)))

(defn error-message-by! [context node error]
  (runtime/set-prop!
   (:ui-application context) node proto/ErrorMessageBy
   (proto/IntValue error)))

(defn input-type! [context node input-type]
  (runtime/set-prop!
   (:ui-application context) node proto/InputType
   (proto/StringValue input-type)))

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

(defn read-only! [context node read-only]
  (runtime/set-prop!
   (:ui-application context) node proto/ReadOnly
   (proto/BoolValue read-only)))

(defn accessibility-label! [context node label]
  (runtime/set-prop!
   (:ui-application context) node proto/AccessibilityLabel
   (proto/StringValue label)))

(defn min-lines! [context node lines]
  (runtime/set-prop!
   (:ui-application context) node proto/MinLines
   (proto/IntValue lines)))

(defn max-lines! [context node lines]
  (runtime/set-prop!
   (:ui-application context) node proto/MaxLines
   (proto/IntValue lines)))
