(ns lui.wire
  (:require [clojure.string :as string]
            [lui.protocol
             :refer [Row Column Box Text Heading Paragraph Label Button
                     TextInput TextArea Scroll Spacer
                     TextValue Enabled Gap PaddingValue BackgroundValue
                     PlaceholderValue ReadOnly AccessibilityLabel MinLines MaxLines
                     StyleClass HeadingLevel LabelledBy DescribedBy
                     ErrorMessageBy InputType Invalid
                     StringValue BoolValue IntValue
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
    Box "box"
    Text "text"
    Heading "heading"
    Paragraph "paragraph"
    Label "label"
    Button "button"
    TextInput "text-input"
    TextArea "text-area"
    Scroll "scroll"
    Spacer "spacer"))

(defn- property-name [property]
  (match property
    TextValue "text"
    Enabled "enabled"
    Gap "gap"
    PaddingValue "padding"
    BackgroundValue "background"
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
    Invalid "invalid"))

(defn- encode-value [value]
  (match value
    (StringValue text) (quoted text)
    (BoolValue enabled) (if enabled "true" "false")
    (IntValue number) (str number)))

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
