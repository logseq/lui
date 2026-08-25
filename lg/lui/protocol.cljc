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
    (Hold node) node
    (TextChanged node _text) node
    (Submit node) node
    (ToggleChanged node _checked) node
    (Change node) node
    (ValueChanged node _value) node
    (Dismiss node) node
    (DoublePress node) node))

(defn- modal-surface? [kind]
  (or (= kind Dialog) (= kind Drawer) (= kind Sheet)))

(defn event-supported? [kind event]
  (match event
    (Press _node)
    (or (= kind Button) (= kind Radio) (= kind Select)
        (= kind Combobox) (= kind MenuItem) (= kind ListItem) (= kind Text))
    (Hold _node) (or (= kind Button) (= kind ToggleButton))
    (TextChanged _node _text)
    (or (= kind TextField) (= kind Input) (= kind SearchField)
        (= kind Textarea) (= kind Combobox))
    (Submit _node)
    (or (= kind TextField) (= kind Input) (= kind SearchField)
        (= kind Textarea) (= kind Combobox) (= kind ListItem))
    (ToggleChanged _node _checked)
    (or (= kind ToggleButton) (= kind Checkbox) (= kind SwitchControl)
        (= kind Toggle) (= kind Radio))
    (Change _node) (= kind Radio)
    (ValueChanged _node _value) (= kind Slider)
    (Dismiss _node)
    (or (= kind Select) (= kind Combobox) (= kind DropdownMenu)
        (modal-surface? kind))
    (DoublePress _node) (= kind ListItem)))

(defn orientation-supported? [value]
  (or (= value "horizontal") (= value "vertical")))

(defn control-size-supported? [value]
  (or
   (= value "default")
   (= value "sm")
   (= value "lg")
   (= value "icon")))

(defn button-variant-supported? [value]
  (or
   (= value "default")
   (= value "primary")
   (= value "secondary")
   (= value "outline")
   (= value "ghost")
   (= value "destructive")))

(defn icon-placement-supported? [value]
  (or (= value "leading") (= value "trailing")))

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

(defn- horizontal-container? [kind]
  (or (= kind Tabs) (= kind ButtonGroup) (= kind ToggleGroup)
      (= kind Breadcrumb) (= kind Pagination)))

(defn- labelled-horizontal-container? [kind]
  (and (horizontal-container? kind) (not (= kind Tabs))))

(defn property-supported? [kind property]
  (match property
    MainAlignment
    (or (= kind Row) (= kind Column) (= kind ListContainer)
        (horizontal-container? kind))
    CrossAlignment
    (or (= kind Row) (= kind Column) (= kind ListContainer)
        (horizontal-container? kind))
    GrowValue (and (not (= kind Avatar)) (not (modal-surface? kind)))
    GridColumns (= kind Grid)
    PaddingValue (not (= kind Avatar))
    PaddingHorizontal
    (or (= kind Row) (= kind Column) (= kind Grid) (= kind Box))
    PaddingVertical
    (or (= kind Row) (= kind Column) (= kind Grid) (= kind Box))
    BackgroundValue (and (not (= kind Avatar)) (not (modal-surface? kind)))
    ForegroundValue
    (match kind
      Text true
      Heading true
      Paragraph true
      Label true
      Button true
      ToggleButton true
      TextField true
      Input true
      SearchField true
      Textarea true
      Checkbox true
      Toggle true
      Radio true
      Slider true
      Spinner true
      Icon true
      Select true
      Combobox true
      DropdownMenu true
      MenuItem true
      ListItem true
      _ false)
    BorderColorValue (and (not (= kind Avatar)) (not (modal-surface? kind)))
    BorderWidth (and (not (= kind Avatar)) (not (modal-surface? kind)))
    CornerRadius (and (not (= kind Avatar)) (not (modal-surface? kind)))
    WidthValue (not (= kind Avatar))
    HeightValue (not (= kind Avatar))
    MinWidth (and (not (= kind Avatar)) (not (modal-surface? kind)))
    MaxWidth (and (not (= kind Avatar)) (not (modal-surface? kind)))
    MinHeight (and (not (= kind Avatar)) (not (modal-surface? kind)))
    MaxHeight (and (not (= kind Avatar)) (not (modal-surface? kind)))
    StyleClass (and (not (= kind Avatar)) (not (modal-surface? kind)))
    AccessibilityLabel
    (or (= kind Button) (= kind ToggleButton)
        (= kind TextField) (= kind Input) (= kind SearchField)
        (= kind Textarea)
        (= kind Checkbox) (= kind SwitchControl)
        (= kind Toggle) (= kind RadioGroup) (= kind Radio) (= kind Slider)
        (labelled-horizontal-container? kind)
        (= kind Avatar))
    PlaceholderValue
    (or (= kind TextField) (= kind Input) (= kind SearchField)
        (= kind Textarea) (= kind Select) (= kind Combobox))
    HeadingLevel (= kind Heading)
    Checked (or (= kind Checkbox) (= kind SwitchControl)
                (= kind Toggle) (= kind Radio))
    ProgressValue (or (= kind Progress) (= kind Slider))
    OrientationValue (= kind Divider)
    SizeValue
    (or (= kind Button) (= kind ToggleButton) (= kind Spinner) (= kind Icon))
    IconName (= kind Icon)
    VariantValue (or (= kind Button) (= kind ToggleButton))
    InlineIconName
    (or (= kind Button) (= kind ToggleButton) (= kind MenuItem)
        (= kind ListItem))
    IconPlacementValue (or (= kind Button) (= kind ToggleButton))
    Selected
    (or (= kind Button) (= kind ToggleButton) (= kind MenuItem)
        (= kind ListItem))
    Autofocus
    (or (= kind Button) (= kind ToggleButton)
        (= kind TextField) (= kind Input) (= kind SearchField)
        (= kind Textarea))
    SubmitOnEnter (= kind Textarea)
    HoldEnabled (or (= kind Button) (= kind ToggleButton))
    ChangeEnabled (= kind Radio)
    ToggleEnabled (= kind Radio)
    PressEnabled
    (or (= kind Text) (= kind Radio) (= kind Select) (= kind Combobox)
        (= kind MenuItem) (= kind ListItem))
    SubmitEnabled (or (= kind Combobox) (= kind ListItem))
    DoublePressEnabled (= kind ListItem)
    ImageIdValue (= kind Avatar)
    SourceX (= kind Avatar)
    SourceY (= kind Avatar)
    SourceWidth (= kind Avatar)
    SourceHeight (= kind Avatar)
    AnchorValue (= kind DropdownMenu)
    AnchorAlignmentValue (= kind DropdownMenu)
    AnchorOffset (= kind DropdownMenu)
    TextValue
    (match kind
      Text true
      Heading true
      Paragraph true
      Label true
      Button true
      ToggleButton true
      TextField true
      Input true
      SearchField true
      Textarea true
      Checkbox true
      SwitchControl true
      Toggle true
      Radio true
      Select true
      Combobox true
      MenuItem true
      ListItem true
      Avatar true
      Dialog true
      Drawer true
      Sheet true
      _ false)
    Enabled
    (match kind
      Button true
      ToggleButton true
      TextField true
      Input true
      SearchField true
      Textarea true
      Checkbox true
      SwitchControl true
      Toggle true
      Radio true
      Slider true
      Select true
      Combobox true
      MenuItem true
      ListItem true
      _ false)
    Gap
    (or (= kind Row) (= kind Column) (= kind Grid)
        (= kind ListContainer) (= kind DropdownMenu)
        (horizontal-container? kind))))

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
    (tuple AccessibilityLabel (StringValue _value)) true
    (tuple StyleClass (StringValue _value)) true
    (tuple HeadingLevel (IntValue value))
    (and (>= value 1) (<= value 6))
    (tuple Checked (BoolValue _value)) true
    (tuple ProgressValue (FloatValue _value)) true
    (tuple OrientationValue (StringValue value))
    (orientation-supported? value)
    (tuple SizeValue (StringValue value))
    (control-size-supported? value)
    (tuple IconName (StringValue value))
    (icon-name-supported? value)
    (tuple VariantValue (StringValue value))
    (button-variant-supported? value)
    (tuple InlineIconName (StringValue value))
    (icon-name-supported? value)
    (tuple IconPlacementValue (StringValue value))
    (icon-placement-supported? value)
    (tuple Selected (BoolValue _value)) true
    (tuple Autofocus (BoolValue _value)) true
    (tuple SubmitOnEnter (BoolValue _value)) true
    (tuple HoldEnabled (BoolValue _value)) true
    (tuple ChangeEnabled (BoolValue _value)) true
    (tuple ToggleEnabled (BoolValue _value)) true
    (tuple PressEnabled (BoolValue _value)) true
    (tuple SubmitEnabled (BoolValue _value)) true
    (tuple DoublePressEnabled (BoolValue _value)) true
    (tuple ImageIdValue (IntValue value)) (>= value 0)
    (tuple SourceX (FloatValue value)) (Float.is_finite value)
    (tuple SourceY (FloatValue value)) (Float.is_finite value)
    (tuple SourceWidth (FloatValue value)) (Float.is_finite value)
    (tuple SourceHeight (FloatValue value)) (Float.is_finite value)
    (tuple AnchorValue (StringValue value))
    (or (= value "above") (= value "below"))
    (tuple AnchorAlignmentValue (StringValue value))
    (or (= value "start") (= value "center") (= value "end")
        (= value "stretch"))
    (tuple AnchorOffset (FloatValue _value)) true
    _ false))

(defn int-property [properties property fallback]
  (if-some [value (clojure.core/get properties property)]
    (match value
      (IntValue number) number
      _ fallback)
    fallback))

(defn- float-property [properties property fallback]
  (if-some [value (clojure.core/get properties property)]
    (match value
      (FloatValue number) number
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
   (if (or (= kind Button) (= kind ToggleButton) (= kind Toggle) (= kind Radio))
     (let [text
           (match (clojure.core/get properties TextValue)
             (Some (StringValue value)) value
             _ "")
           label
           (match (clojure.core/get properties AccessibilityLabel)
             (Some (StringValue value)) value
             _ "")
           icon
           (match (clojure.core/get properties InlineIconName)
             (Some (StringValue value)) value
             _ "")]
       (and
        (or (not (= text "")) (not (= label "")))
        (if (and (= text "") (not (= icon "")))
          (not (= label ""))
          true)))
     true)
   (if (or (= kind RadioGroup) (= kind Slider))
     (match (clojure.core/get properties AccessibilityLabel)
       (Some (StringValue value)) (not (= value ""))
     _ false)
     true)
   (if (or (= kind Select) (= kind Combobox))
     (let [text
           (match (clojure.core/get properties TextValue)
             (Some (StringValue value)) value
             _ "")
           placeholder
           (match (clojure.core/get properties PlaceholderValue)
             (Some (StringValue value)) value
             _ "")]
       (or (not (= text "")) (not (= placeholder ""))))
     true)
   (if (= kind MenuItem)
     (match (clojure.core/get properties TextValue)
       (Some (StringValue value)) (not (= value ""))
       _ false)
     true)
   (if (modal-surface? kind)
     (match (clojure.core/get properties TextValue)
       (Some (StringValue value)) (not (= value ""))
       _ false)
     true)
   (if (= kind Avatar)
     (let [has-image (contains? properties ImageIdValue)
           has-source-x (contains? properties SourceX)
           has-source-y (contains? properties SourceY)
           has-source-width (contains? properties SourceWidth)
           has-source-height (contains? properties SourceHeight)
           source-count
           (+ (if has-source-x 1 0)
              (if has-source-y 1 0)
              (if has-source-width 1 0)
              (if has-source-height 1 0))
           source-x (float-property properties SourceX 0.0)
           source-y (float-property properties SourceY 0.0)
           source-width (float-property properties SourceWidth 0.0)
           source-height (float-property properties SourceHeight 0.0)]
       (and
        (match (clojure.core/get properties TextValue)
          (Some (StringValue value)) (not (= value ""))
          _ false)
        (or (= source-count 0) (= source-count 4))
        (or (= source-count 0) has-image)
        (or
         (= source-count 0)
         (and
          (>= source-x 0.0)
          (>= source-y 0.0)
          (> source-width 0.0)
          (> source-height 0.0)))))
     true)
   (if (or (= kind Slider) (= kind Progress))
     (match (clojure.core/get properties ProgressValue)
       (Some (FloatValue _value)) true
       _ false)
     true)))

(defn can-contain-children? [kind]
  (if (horizontal-container? kind)
    true
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
      RadioGroup true
      DropdownMenu true
      ListItem true
      Dialog true
      Drawer true
      Sheet true
      _ false)))

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
