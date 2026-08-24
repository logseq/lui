(ns lui.protocol)

(defn profile [operating-system host]
  (record platform-profile
    (profile-os operating-system)
    (profile-host host)))

(defn generic-profile []
  (profile GenericOS GenericHost))

(defn event-node [event]
  (match event
    (Press node) node
    (TextChanged node _text) node
    (ToggleChanged node _checked) node))

(defn event-supported? [kind event]
  (match event
    (Press _node) (= kind Button)
    (TextChanged _node _text) (or (= kind TextInput) (= kind TextArea))
    (ToggleChanged _node _checked)
    (or (= kind Checkbox) (= kind SwitchControl))))

(defn input-type-supported? [value]
  (or
   (= value "button")
   (= value "checkbox")
   (= value "color")
   (= value "date")
   (= value "datetime-local")
   (= value "email")
   (= value "file")
   (= value "hidden")
   (= value "image")
   (= value "month")
   (= value "number")
   (= value "password")
   (= value "radio")
   (= value "range")
   (= value "reset")
   (= value "search")
   (= value "submit")
   (= value "tel")
   (= value "text")
   (= value "time")
   (= value "url")
   (= value "week")))

(defn orientation-supported? [value]
  (or (= value "horizontal") (= value "vertical")))

(defn property-supported? [kind property]
  (match property
    PaddingValue true
    PaddingHorizontal (or (= kind Row) (= kind Column) (= kind Box))
    PaddingVertical (or (= kind Row) (= kind Column) (= kind Box))
    BackgroundValue true
    ForegroundValue
    (match kind
      Text true
      Heading true
      Paragraph true
      Label true
      Button true
      TextInput true
      TextArea true
      Checkbox true
      _ false)
    BorderColorValue true
    BorderWidth true
    CornerRadius true
    WidthValue true
    HeightValue true
    MinWidth true
    MaxWidth true
    MinHeight true
    MaxHeight true
    StyleClass true
    AccessibilityLabel
    (or (= kind TextInput) (= kind TextArea)
        (= kind Checkbox) (= kind SwitchControl) (= kind ProgressControl))
    PlaceholderValue (or (= kind TextInput) (= kind TextArea))
    ReadOnly (or (= kind TextInput) (= kind TextArea))
    MinLines (= kind TextArea)
    MaxLines (= kind TextArea)
    HeadingLevel (= kind Heading)
    LabelledBy
    (or (= kind TextInput) (= kind TextArea)
        (= kind SwitchControl) (= kind ProgressControl))
    DescribedBy
    (or (= kind TextInput) (= kind TextArea) (= kind SwitchControl))
    ErrorMessageBy
    (or (= kind TextInput) (= kind TextArea) (= kind SwitchControl))
    InputType (= kind TextInput)
    Invalid
    (or (= kind TextInput) (= kind TextArea)
        (= kind Checkbox) (= kind SwitchControl))
    Checked (or (= kind Checkbox) (= kind SwitchControl))
    Indeterminate (= kind Checkbox)
    ProgressValue (= kind ProgressControl)
    MinValue (= kind ProgressControl)
    MaxValue (= kind ProgressControl)
    OrientationValue (= kind Divider)
    TextValue
    (match kind
      Text true
      Heading true
      Paragraph true
      Label true
      Button true
      TextInput true
      TextArea true
      _ false)
    Enabled
    (match kind
      Button true
      TextInput true
      TextArea true
      Checkbox true
      SwitchControl true
      _ false)
    Gap
    (match kind
      Row true
      Column true
      _ false)))

(defn property-value-supported? [property value]
  (match (tuple property value)
    (tuple TextValue (StringValue _value)) true
    (tuple Enabled (BoolValue _value)) true
    (tuple Gap (IntValue _value)) true
    (tuple PaddingValue (IntValue _value)) true
    (tuple PaddingHorizontal (IntValue value)) (>= value 0)
    (tuple PaddingVertical (IntValue value)) (>= value 0)
    (tuple BackgroundValue (StringValue _value)) true
    (tuple ForegroundValue (StringValue _value)) true
    (tuple BorderColorValue (StringValue _value)) true
    (tuple BorderWidth (IntValue value)) (>= value 0)
    (tuple CornerRadius (IntValue value)) (>= value 0)
    (tuple WidthValue (IntValue value)) (>= value 0)
    (tuple HeightValue (IntValue value)) (>= value 0)
    (tuple MinWidth (IntValue value)) (>= value 0)
    (tuple MaxWidth (IntValue value)) (>= value 0)
    (tuple MinHeight (IntValue value)) (>= value 0)
    (tuple MaxHeight (IntValue value)) (>= value 0)
    (tuple PlaceholderValue (StringValue _value)) true
    (tuple ReadOnly (BoolValue _value)) true
    (tuple AccessibilityLabel (StringValue _value)) true
    (tuple MinLines (IntValue value)) (> value 0)
    (tuple MaxLines (IntValue value)) (> value 0)
    (tuple StyleClass (StringValue _value)) true
    (tuple HeadingLevel (IntValue value))
    (and (>= value 1) (<= value 6))
    (tuple LabelledBy (IntValue value)) (> value 0)
    (tuple DescribedBy (IntValue value)) (> value 0)
    (tuple ErrorMessageBy (IntValue value)) (> value 0)
    (tuple InputType (StringValue value)) (input-type-supported? value)
    (tuple Invalid (BoolValue _value)) true
    (tuple Checked (BoolValue _value)) true
    (tuple Indeterminate (BoolValue _value)) true
    (tuple ProgressValue (IntValue _value)) true
    (tuple MinValue (IntValue _value)) true
    (tuple MaxValue (IntValue _value)) true
    (tuple OrientationValue (StringValue value))
    (orientation-supported? value)
    _ false))

(defn int-property [properties property fallback]
  (if-some [value (clojure.core/get properties property)]
    (match value
      (IntValue number) number
      _ fallback)
    fallback))

(defn- size-axis-supported? [properties fixed-property min-property max-property]
  (let [minimum (int-property properties min-property 0)
        fixed (int-property properties fixed-property minimum)]
    (and
     (>= fixed minimum)
     (if-some [value (clojure.core/get properties max-property)]
       (match value
         (IntValue maximum)
         (and (<= minimum maximum) (<= fixed maximum))
         _ false)
       true))))

(defn surface-size-supported? [properties]
  (and
   (size-axis-supported? properties WidthValue MinWidth MaxWidth)
   (size-axis-supported? properties HeightValue MinHeight MaxHeight)))

(defn node-properties-supported? [kind properties]
  (and
   (surface-size-supported? properties)
   (if (= kind ProgressControl)
     (< (int-property properties MinValue 0)
        (int-property properties MaxValue 100))
     true)))

(defn can-contain-children? [kind]
  (match kind
    Row true
    Column true
    Box true
    Scroll true
    SwitchControl true
    _ false))

(defn single-child-container? [kind]
  (or (= kind Scroll) (= kind SwitchControl)))

(defn create-node-op [node kind]
  (CreateNode node kind))

(defn drop-node-op [node]
  (DropNode node))

(defn set-prop-op [node property value]
  (SetProp node property value))

(defn insert-child-op [parent child index]
  (InsertChild parent child index))

(defn remove-child-op [parent child]
  (RemoveChild parent child))

(defn move-child-op [parent child index]
  (MoveChild parent child index))
