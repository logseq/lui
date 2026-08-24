(ns lui.wire
  (:require [clojure.string :as string]
            [lui.protocol
             :refer [Row Column Grid Stack Panel Card Box
                     Text Heading Paragraph Label Button
                     TextInput TextArea Scroll ListContainer Spacer Spinner Icon
                     Checkbox SwitchControl
                     ProgressControl Divider
                     TextValue Enabled Gap MainAlignment CrossAlignment
                     GrowValue GridColumns PaddingValue
                     PaddingHorizontal PaddingVertical
                     BackgroundValue ForegroundValue BorderColorValue
                     BorderWidth CornerRadius
                     WidthValue HeightValue MinWidth MaxWidth MinHeight MaxHeight
                     PlaceholderValue ReadOnly AccessibilityLabel MinLines MaxLines
                     StyleClass HeadingLevel LabelledBy DescribedBy
                     ErrorMessageBy InputType Invalid
                     Checked
                     ProgressValue MinValue MaxValue OrientationValue SizeValue IconName
                     StringValue BoolValue IntValue FloatValue
                     CreateNode DropNode SetProp InsertChild RemoveChild
                     MoveChild]]))

(defn- escape-json [value]
  (string/escape
   value
   {\\ "\\\\"
    \" "\\\""
    \newline "\\n"
    \return "\\r"
    \tab "\\t"}))

(defn- quoted [value]
  (str "\"" (escape-json value) "\""))

(defn- node-kind-name [kind]
  (match kind
    Row "row"
    Column "column"
    Grid "grid"
    Stack "stack"
    Panel "panel"
    Card "card"
    Box "box"
    Text "text"
    Heading "heading"
    Paragraph "paragraph"
    Label "label"
    Button "button"
    TextInput "text-input"
    TextArea "text-area"
    Checkbox "checkbox"
    SwitchControl "switch"
    ProgressControl "progress"
    Divider "divider"
    Scroll "scroll"
    ListContainer "list"
    Spacer "spacer"
    Spinner "spinner"
    Icon "icon"))

(defn- property-name [property]
  (match property
    TextValue "text"
    Enabled "enabled"
    Gap "gap"
    MainAlignment "main"
    CrossAlignment "cross"
    GrowValue "grow"
    GridColumns "columns"
    PaddingValue "padding"
    PaddingHorizontal "padding-horizontal"
    PaddingVertical "padding-vertical"
    BackgroundValue "background"
    ForegroundValue "foreground"
    BorderColorValue "border-color"
    BorderWidth "border-width"
    CornerRadius "corner-radius"
    WidthValue "width"
    HeightValue "height"
    MinWidth "min-width"
    MaxWidth "max-width"
    MinHeight "min-height"
    MaxHeight "max-height"
    PlaceholderValue "placeholder"
    ReadOnly "read-only"
    AccessibilityLabel "accessibility-label"
    MinLines "min-lines"
    MaxLines "max-lines"
    StyleClass "style-class"
    HeadingLevel "heading-level"
    LabelledBy "labelled-by"
    DescribedBy "described-by"
    ErrorMessageBy "error-message-by"
    InputType "input-type"
    Invalid "invalid"
    Checked "checked"
    ProgressValue "value"
    MinValue "min-value"
    MaxValue "max-value"
    OrientationValue "orientation"
    SizeValue "size"
    IconName "name"))

(defn- encode-value [value]
  (match value
    (StringValue text) (quoted text)
    (BoolValue enabled) (if enabled "true" "false")
    (IntValue number) (str number)
    (FloatValue number)
    (let [encoded (str number)]
      (cond
        (string/ends-with? encoded ".") (str encoded "0")
        (and (not (string/includes? encoded "."))
             (not (string/includes? encoded "e"))
             (not (string/includes? encoded "E"))) (str encoded ".0")
        :else encoded))))

(defn- encode-op [operation]
  (match operation
    (CreateNode node kind)
    (str "{\"op\":\"create-node\",\"id\":" node
         ",\"kind\":" (quoted (node-kind-name kind)) "}")
    (DropNode node)
    (str "{\"op\":\"drop-node\",\"id\":" node "}")
    (SetProp node property value)
    (str "{\"op\":\"set-prop\",\"id\":" node
         ",\"property\":" (quoted (property-name property))
         ",\"value\":" (encode-value value) "}")
    (InsertChild parent child index)
    (str "{\"op\":\"insert-child\",\"parent\":" parent
         ",\"child\":" child ",\"index\":" index "}")
    (RemoveChild parent child)
    (str "{\"op\":\"remove-child\",\"parent\":" parent
         ",\"child\":" child "}")
    (MoveChild parent child index)
    (str "{\"op\":\"move-child\",\"parent\":" parent
         ",\"child\":" child ",\"index\":" index "}")))

(defn- encode-ops [operations]
  (loop [index 0
         encoded []]
    (if (= index (count operations))
      (string/join "," encoded)
      (recur (inc index) (conj encoded (encode-op (nth operations index)))))))

(defn encode-batch [batch]
  (str "{\"generation\":" (:generation batch)
       ",\"ops\":[" (encode-ops (:ops batch)) "]}"))
