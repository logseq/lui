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

(defn control-size-supported? [value]
  (or
   (= value "default")
   (= value "sm")
   (= value "lg")
   (= value "icon")))

(defn- built-in-icon-name-supported? [value]
  (match value
    "alert" true "archive" true "arrow-down" true "arrow-right" true
    "arrow-up" true "check" true "check-circle" true "chevron-down" true
    "chevron-left" true "chevron-right" true "chevron-up" true
    "circle-dot" true "clock" true "copy" true "download" true "edit" true
    "ellipsis" true "external-link" true "eye" true "file-text" true
    "folder" true "folder-open" true "git-branch" true "git-merge" true
    "git-pull-request" true "info" true "menu" true "mic" true "moon" true
    "music" true "panel-left" true "panel-right" true "pause" true
    "play" true "plus" true "refresh-cw" true "repeat" true "save" true
    "search" true "send" true "settings" true "shuffle" true
    "skip-back" true "skip-forward" true "sun" true "terminal" true
    "trash" true "volume" true "wrench" true "x" true "x-circle" true
    _ false))

(defn icon-name-supported? [value]
  (or
   (built-in-icon-name-supported? value)
   (boolean (re-matches #"app:[a-z0-9]+(?:-[a-z0-9]+)*" value))))

(defn main-alignment-supported? [value]
  (or
   (= value "start")
   (= value "center")
   (= value "end")
   (= value "space_between")))

(defn cross-alignment-supported? [value]
  (or
   (= value "stretch")
   (= value "start")
   (= value "center")
   (= value "end")))

(defn property-supported? [kind property]
  (match property
    MainAlignment (or (= kind Row) (= kind Column) (= kind ListContainer))
    CrossAlignment (or (= kind Row) (= kind Column) (= kind ListContainer))
    GrowValue true
    GridColumns (= kind Grid)
    PaddingValue true
    PaddingHorizontal
    (or (= kind Row) (= kind Column) (= kind Grid) (= kind Box))
    PaddingVertical
    (or (= kind Row) (= kind Column) (= kind Grid) (= kind Box))
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
      Spinner true
      Icon true
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
        (= kind ProgressControl))
    DescribedBy
    (or (= kind TextInput) (= kind TextArea))
    ErrorMessageBy
    (or (= kind TextInput) (= kind TextArea))
    InputType (= kind TextInput)
    Invalid
    (or (= kind TextInput) (= kind TextArea))
    Checked (or (= kind Checkbox) (= kind SwitchControl))
    ProgressValue (= kind ProgressControl)
    MinValue (= kind ProgressControl)
    MaxValue (= kind ProgressControl)
    OrientationValue (= kind Divider)
    SizeValue (or (= kind Spinner) (= kind Icon))
    IconName (= kind Icon)
    TextValue
    (match kind
      Text true
      Heading true
      Paragraph true
      Label true
      Button true
      TextInput true
      TextArea true
      Checkbox true
      SwitchControl true
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
      Grid true
      ListContainer true
      _ false)))

(defn property-value-supported? [property value]
  (match (tuple property value)
    (tuple TextValue (StringValue _value)) true
    (tuple Enabled (BoolValue _value)) true
    (tuple Gap (IntValue value)) (>= value 0)
    (tuple MainAlignment (StringValue value))
    (main-alignment-supported? value)
    (tuple CrossAlignment (StringValue value))
    (cross-alignment-supported? value)
    (tuple GrowValue (FloatValue value)) (>= value 0.0)
    (tuple GridColumns (IntValue value)) (>= value 0)
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
    (tuple ProgressValue (IntValue _value)) true
    (tuple MinValue (IntValue _value)) true
    (tuple MaxValue (IntValue _value)) true
    (tuple OrientationValue (StringValue value))
    (orientation-supported? value)
    (tuple SizeValue (StringValue value))
    (control-size-supported? value)
    (tuple IconName (StringValue value))
    (icon-name-supported? value)
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
   (if (= kind Icon)
     (if-some [name (clojure.core/get properties IconName)]
       (property-value-supported? IconName name)
       false)
     true)
   (if (= kind ProgressControl)
     (< (int-property properties MinValue 0)
        (int-property properties MaxValue 100))
     true)))

(defn can-contain-children? [kind]
  (match kind
    Row true
    Column true
    Grid true
    Stack true
    Panel true
    Card true
    Box true
    Scroll true
    ListContainer true
    _ false))

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
