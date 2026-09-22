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
    (LongPress node) node
    (TextChanged node _text) node
    (Submit node) node
    (ToggleChanged node _checked) node
    (Change node) node
    (ValueChanged node _value) node
    (Dismiss node) node
    (DoublePress node) node
    (Appear node) node
    (ExtensionEvent node _identifier _name _values) node))

(defn- modal-surface? [kind]
  (or (= kind Dialog) (= kind Drawer) (= kind Sheet)))

(defn tree-row-kind? [kind]
  (or (= kind Row) (= kind Column) (= kind Panel) (= kind Card)
      (= kind Box) (= kind ListItem)))

(defn context-menu-host-kind? [kind]
  (or
   (= kind Button) (= kind ToggleButton) (= kind Toggle) (= kind Radio)
   (= kind Slider) (= kind TextField) (= kind SecureField) (= kind Input) (= kind SearchField)
   (= kind Textarea) (= kind Checkbox) (= kind SwitchControl)
   (= kind Select) (= kind Combobox) (= kind MenuItem) (= kind ListItem)
   (= kind Accordion) (= kind Text) (= kind TableCell)))

(defn context-menu-leaf-host-kind? [kind]
  (or
   (= kind Button) (= kind ToggleButton) (= kind Toggle) (= kind Radio)
   (= kind Slider) (= kind TextField) (= kind SecureField) (= kind Input) (= kind SearchField)
   (= kind Textarea) (= kind Checkbox) (= kind SwitchControl)
   (= kind Select) (= kind Combobox) (= kind MenuItem) (= kind Text)
   (= kind TableCell)))

(defn event-supported? [kind event]
  (match event
    (Press _node)
    (match kind
      Button true Radio true Select true Combobox true MenuItem true
      ListItem true Text true TableCell true TimelineItem true
      BottomTab true _ false)
    (LongPress _node)
    (match kind Button true ToggleButton true ListItem true _ false)
    (TextChanged _node _text)
    (match kind
      TextField true SecureField true Input true SearchField true
      Textarea true Combobox true _ false)
    (Submit _node)
    (match kind
      TextField true SecureField true Input true SearchField true
      Textarea true Combobox true ListItem true _ false)
    (ToggleChanged _node _checked)
    (match kind
      ToggleButton true Checkbox true SwitchControl true Toggle true
      Radio true Accordion true Drawer true _ false)
    (Change _node) (= kind Radio)
    (ValueChanged _node _value)
    (match kind Slider true Split true _ false)
    (Dismiss _node)
    (match kind
      Select true Combobox true DropdownMenu true Toast true
      Dialog true Drawer true Sheet true _ false)
    (DoublePress _node) (= kind ListItem)
    (Appear _node) (not (= kind Root))
    (ExtensionEvent _node _identifier _name _values) false))

(defn- true-property? [properties property]
  (match (get properties property)
    (Some (BoolValue true)) true
    _ false))

(defn- treeitem-properties? [properties]
  (match (get properties RoleValue)
    (Some (StringValue "treeitem")) true
    _ false))

(defn event-supported-for-properties? [kind properties event]
  (if (match event
        (Appear _node) (true-property? properties AppearEnabled)
        _ false)
    true
    (if (treeitem-properties? properties)
    (match event
      (Press _node) (true-property? properties PressEnabled)
      (Change _node) (true-property? properties ChangeEnabled)
      (ToggleChanged _node _checked)
      (true-property? properties ToggleEnabled)
      _ (event-supported? kind event))
    (event-supported? kind event))))

(defn container-relative-frame-supported? [value]
  (or
   (= value "horizontal")
   (= value "vertical")
   (= value "both")
   (= value "min-horizontal")
   (= value "min-vertical")
   (= value "min-both")))

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
  (or (= value "leading") (= value "trailing") (= value "top")))

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

(def custom-icon-name-pattern
  (re-pattern "app:[a-z0-9]+(?:-[a-z0-9]+)*"))

(defn icon-name-supported? [value]
  (or
   (built-in-icon-name-supported? value)
   (boolean (re-matches custom-icon-name-pattern value))))

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

(defn- common-property-supported? [kind property]
  (match property
    MainAlignment
    (or (= kind Row) (= kind Column) (= kind ListContainer) (= kind VirtualList)
        (horizontal-container? kind))
    CrossAlignment
    (or (= kind Row) (= kind Column) (= kind ListContainer) (= kind VirtualList)
        (horizontal-container? kind))
    GrowValue
    (and (not (= kind Avatar)) (not (modal-surface? kind))
         (not (= kind Tooltip)))
    GridColumns (= kind Grid)
    PaddingValue (and (not (= kind Avatar)) (not (= kind Tooltip)))
    PaddingHorizontal
    (or (= kind Row) (= kind Column) (= kind Grid) (= kind Box)
        (= kind Button))
    PaddingVertical
    (or (= kind Row) (= kind Column) (= kind Grid) (= kind Box))
    BackgroundValue
    (and (not (= kind Avatar)) (not (modal-surface? kind))
         (not (= kind Tooltip)))
    ForegroundValue
    (match kind
      Text true
      Heading true
      Paragraph true
      Label true
      Button true
      ToggleButton true
      TextField true
      SecureField true
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
      TableCell true
      Resizable true
      Split true
      Alert true
      Bubble true
      StatusBar true
      _ false)
    BorderColorValue
    (and (not (= kind Avatar)) (not (modal-surface? kind))
         (not (= kind Tooltip)))
    BorderWidth
    (and (not (= kind Avatar)) (not (modal-surface? kind))
         (not (= kind Tooltip)))
    CornerRadius
    (and (not (= kind Avatar)) (not (modal-surface? kind))
         (not (= kind Tooltip)))
    WidthValue (and (not (= kind Avatar)) (not (= kind Tooltip)))
    HeightValue (and (not (= kind Avatar)) (not (= kind Tooltip)))
    MinWidth
    (and (not (= kind Avatar)) (not (modal-surface? kind))
         (not (= kind Tooltip)))
    MaxWidth
    (and (not (= kind Avatar)) (not (modal-surface? kind))
         (not (= kind Tooltip)))
    MinHeight
    (and (not (= kind Avatar)) (not (modal-surface? kind))
         (not (= kind Tooltip)))
    MaxHeight
    (and (not (= kind Avatar)) (not (modal-surface? kind))
         (not (= kind Tooltip)))
    ContainerRelativeFrameValue
    (and (not (= kind Root)) (not (modal-surface? kind)))
    ContainerRelativeFrameInset
    (and (not (= kind Root)) (not (modal-surface? kind)))
    StyleClass
    (and (not (= kind Avatar)) (not (= kind Tooltip)))
    AccessibilityLabel
    (or (= kind Button) (= kind ToggleButton)
        (= kind Select)
        (= kind TextField) (= kind SecureField) (= kind Input) (= kind SearchField)
        (= kind Textarea)
        (= kind Checkbox) (= kind SwitchControl)
        (= kind Toggle) (= kind RadioGroup) (= kind Radio) (= kind Slider)
        (horizontal-container? kind)
        (= kind Avatar) (= kind Image) (= kind MediaSurface)
        (= kind Tree) (= kind Resizable) (= kind Split) (= kind Drawer)
        (= kind Alert) (= kind Bubble)
        (= kind ListItem)
        (tree-row-kind? kind))
    AccessibilityIdentifier true
    PlaceholderValue
    (or (= kind TextField) (= kind SecureField) (= kind Input) (= kind SearchField)
        (= kind Textarea) (= kind Select) (= kind Combobox))
    HeadingLevel (= kind Heading)
    Checked (or (= kind Checkbox) (= kind SwitchControl)
                (= kind Toggle) (= kind Radio))
    ProgressValue (or (= kind Progress) (= kind Slider) (= kind Split))
    OrientationValue (or (= kind Divider) (= kind Tabs))
    SizeValue
    (or (= kind Button) (= kind ToggleButton) (= kind Spinner) (= kind Icon)
        (= kind TableCell))
    IconName (= kind Icon)
    VariantValue
    (or (= kind Button) (= kind ToggleButton) (= kind MenuItem)
        (= kind Alert) (= kind Bubble))
    InlineIconName
    (or (= kind Button) (= kind ToggleButton) (= kind MenuItem)
        (= kind ListItem) (= kind BottomTab))
    IconPlacementValue
    (or (= kind Button) (= kind ToggleButton) (= kind ListItem))
    Selected
    (or (= kind Button) (= kind ToggleButton) (= kind MenuItem)
        (= kind ListItem) (= kind TableRow) (= kind Drawer)
        (= kind BottomTab) (= kind VirtualList)
        (tree-row-kind? kind))
    Autofocus
    (or (= kind Button) (= kind ToggleButton)
        (= kind TextField) (= kind SecureField) (= kind Input) (= kind SearchField)
        (= kind Textarea))
    SubmitOnEnter (= kind Textarea)
    LongPressEnabled (or (= kind Button) (= kind ToggleButton) (= kind ListItem))
    ChangeEnabled (or (= kind Radio) (tree-row-kind? kind))
    ToggleEnabled (or (= kind Radio) (= kind Drawer) (tree-row-kind? kind))
    PressEnabled
    (or (= kind Text) (= kind Radio) (= kind Select) (= kind Combobox)
        (= kind MenuItem) (= kind ListItem) (= kind TableCell)
        (= kind BottomTab) (tree-row-kind? kind))
    SubmitEnabled (or (= kind Combobox) (= kind ListItem))
    DoublePressEnabled (= kind ListItem)
    AppearEnabled (not (= kind Root))
    ImageIdValue (or (= kind Avatar) (= kind Image))
    SurfaceIdValue (= kind MediaSurface)
    SourceX (or (= kind Avatar) (= kind Image))
    SourceY (or (= kind Avatar) (= kind Image))
    SourceWidth (or (= kind Avatar) (= kind Image))
    SourceHeight (or (= kind Avatar) (= kind Image))
    AnchorValue (or (= kind DropdownMenu) (= kind Tooltip))
    AnchorAlignmentValue (or (= kind DropdownMenu) (= kind Tooltip))
    AnchorOffset (or (= kind DropdownMenu) (= kind Tooltip))
    TooltipDelay (= kind Tooltip)
    DurationValue false
    TextAlignment
    (or (= kind Text) (= kind Button) (= kind ToggleButton)
        (= kind TableCell) (= kind Bubble) (= kind StatusBar))
    RoleValue (or (tree-row-kind? kind) (= kind ListItem))
    TreeLevel (tree-row-kind? kind)
    Expanded (tree-row-kind? kind)
    ResizeDuration (= kind Split)
    ResizeEasing (= kind Split)
    ResizeOrigin (= kind Split)
    TextValue
    (match kind
      Text true
      Heading true
      Paragraph true
      Label true
      Button true
      ToggleButton true
      TextField true
      SecureField true
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
      Tooltip true
      TableCell true
      Alert true
      Bubble true
      StatusBar true
      _ false)
    Enabled
    (match kind
      Button true
      ToggleButton true
      TextField true
      SecureField true
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
      Drawer true
      BottomTab true
      _ false)
    ActiveIndex false
    TitleValue (= kind BottomTab)
    DescriptionValue false
    MetaValue false
    IndicatorValue false
    Connector false
    Gap
    (or (= kind Row) (= kind Column) (= kind Grid)
        (= kind ListContainer) (= kind VirtualList) (= kind DropdownMenu) (= kind TableRow)
        (= kind Tree) (= kind Split)
        (horizontal-container? kind))))

(defn property-supported? [kind property]
  (if (= property AccessibilityIdentifier)
    true
    (match kind
      Root false
      ContextMenu false
      Toast
      (or (= property DurationValue) (= property AccessibilityLabel)
          (= property StyleClass))
      Toolbar
      (or (= property OrientationValue) (= property AccessibilityLabel)
          (= property Gap) (= property StyleClass))
      BottomTabs
      (or (= property AccessibilityLabel) (= property StyleClass)
          (= property GrowValue) (= property WidthValue)
          (= property HeightValue) (= property MinWidth)
          (= property MaxWidth) (= property MinHeight)
          (= property MaxHeight))
      BottomTab
      (or (= property TitleValue) (= property InlineIconName)
          (= property Selected) (= property Enabled)
          (= property PressEnabled))
      Accordion
      (or (= property TextValue) (= property Selected)
          (= property ToggleEnabled) (= property HeightValue))
      Stepper
      (or (= property ActiveIndex) (= property AccessibilityLabel))
      Step (= property TextValue)
      Timeline
      (or (= property Gap) (= property GrowValue)
          (= property AccessibilityLabel))
      TimelineItem
      (or (= property TitleValue) (= property DescriptionValue)
          (= property MetaValue) (= property IndicatorValue)
          (= property InlineIconName) (= property VariantValue)
          (= property Connector) (= property Selected)
          (= property PressEnabled))
      InputGroup
      (or (= property AccessibilityLabel) (= property WidthValue)
          (= property HeightValue) (= property MinWidth)
          (= property GrowValue))
      InputGroupActions (= property Gap)
      _ (common-property-supported? kind property))))

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
    (tuple ContainerRelativeFrameValue (StringValue value))
    (container-relative-frame-supported? value)
    (tuple ContainerRelativeFrameInset (IntValue value)) (>= value 0)
    (tuple PlaceholderValue (StringValue _value)) true
    (tuple AccessibilityLabel (StringValue _value)) true
    (tuple AccessibilityIdentifier (StringValue _value)) true
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
    (tuple LongPressEnabled (BoolValue _value)) true
    (tuple ChangeEnabled (BoolValue _value)) true
    (tuple ToggleEnabled (BoolValue _value)) true
    (tuple PressEnabled (BoolValue _value)) true
    (tuple SubmitEnabled (BoolValue _value)) true
    (tuple DoublePressEnabled (BoolValue _value)) true
    (tuple AppearEnabled (BoolValue _value)) true
    (tuple ImageIdValue (IntValue value)) (>= value 0)
    (tuple SurfaceIdValue (IntValue value)) (>= value 0)
    (tuple ActiveIndex (IntValue value)) (>= value 0)
    (tuple TitleValue (StringValue _value)) true
    (tuple DescriptionValue (StringValue _value)) true
    (tuple MetaValue (StringValue _value)) true
    (tuple IndicatorValue (StringValue _value)) true
    (tuple Connector (BoolValue _value)) true
    (tuple SourceX (FloatValue value)) (Float.is_finite value)
    (tuple SourceY (FloatValue value)) (Float.is_finite value)
    (tuple SourceWidth (FloatValue value)) (Float.is_finite value)
    (tuple SourceHeight (FloatValue value)) (Float.is_finite value)
    (tuple AnchorValue (StringValue value))
    (or (= value "above") (= value "below")
        (= value "left") (= value "right"))
    (tuple AnchorAlignmentValue (StringValue value))
    (or (= value "start") (= value "end") (= value "stretch"))
    (tuple AnchorOffset (FloatValue _value)) true
    (tuple TooltipDelay (IntValue value))
    (and (>= value 0) (<= value 2147483647))
    (tuple DurationValue (IntValue value))
    (and (>= value 0) (<= value 2147483647))
    (tuple TextAlignment (StringValue value))
    (or (= value "start") (= value "center") (= value "end"))
    (tuple RoleValue (StringValue value))
    (or (= value "treeitem") (= value "navigation")
        (= value "navigation-heading"))
    (tuple TreeLevel (IntValue value)) (> value 0)
    (tuple Expanded (BoolValue _value)) true
    (tuple ResizeDuration (IntValue value)) (>= value 0)
    (tuple ResizeEasing (StringValue value))
    (or (= value "linear") (= value "standard")
        (= value "emphasized") (= value "spring"))
    (tuple ResizeOrigin (FloatValue value)) (Float.is_finite value)
    _ false))

(defn property-value-supported-for-kind? [kind property value]
  (if (= property SizeValue)
    (match value
      (StringValue size)
      (if (= kind TableCell)
        (or (control-size-supported? size)
            (= size "heading") (= size "display"))
        (control-size-supported? size))
      _ false)
    (property-value-supported? property value)))

(defn int-property [properties property fallback]
  (if-some [value (get properties property)]
    (match value
      (IntValue number) number
      _ fallback)
    fallback))

(defn- float-property [properties property fallback]
  (if-some [value (get properties property)]
    (match value
      (FloatValue number) number
      _ fallback)
    fallback))

(defn- size-axis-supported? [properties fixed-property min-property max-property]
  (let [minimum (int-property properties min-property 0)
        fixed (int-property properties fixed-property minimum)]
    (and
     (>= fixed minimum)
     (if-some [value (get properties max-property)]
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
     (if-some [name (get properties IconName)]
       (property-value-supported? IconName name)
       false)
     true)
   (if (or (= kind Button) (= kind ToggleButton) (= kind Toggle) (= kind Radio))
     (let [text
           (match (get properties TextValue)
             (Some (StringValue value)) value
             _ "")
           label
           (match (get properties AccessibilityLabel)
             (Some (StringValue value)) value
             _ "")
           icon
           (match (get properties InlineIconName)
             (Some (StringValue value)) value
             _ "")]
       (and
        (or (not (= text "")) (not (= label "")))
        (if (and (= text "") (not (= icon "")))
          (not (= label ""))
          true)))
     true)
   (if (or (= kind RadioGroup) (= kind Slider))
     (match (get properties AccessibilityLabel)
       (Some (StringValue value)) (not (= value ""))
     _ false)
     true)
   (if (or (= kind Select) (= kind Combobox))
     (let [text
           (match (get properties TextValue)
             (Some (StringValue value)) value
             _ "")
           placeholder
           (match (get properties PlaceholderValue)
             (Some (StringValue value)) value
             _ "")]
       (or (not (= text "")) (not (= placeholder ""))))
     true)
   (if (= kind MenuItem)
     (match (get properties TextValue)
       (Some (StringValue value)) (not (= value ""))
       _ false)
     true)
   (if (= kind Accordion)
     (match (get properties TextValue)
       (Some (StringValue value)) (not (= value ""))
       _ false)
     true)
   (if (modal-surface? kind)
     (match (get properties TextValue)
       (Some (StringValue value)) (not (= value ""))
       _ false)
     true)
   (if (= kind Tooltip)
     (and
      (match (get properties TextValue)
        (Some (StringValue value)) (not (= value ""))
        _ false)
      (if (contains? properties TooltipDelay)
        (contains? properties AnchorValue)
        true))
     true)
   (if (or (= kind DropdownMenu) (= kind Tooltip))
     (if (or (contains? properties AnchorAlignmentValue)
             (contains? properties AnchorOffset))
       (contains? properties AnchorValue)
       true)
     true)
   (if (or (= kind Avatar) (= kind Image))
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
        (if (= kind Avatar)
          (match (get properties TextValue)
            (Some (StringValue value)) (not (= value ""))
            _ false)
          has-image)
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
   (if (= kind MediaSurface)
     (contains? properties SurfaceIdValue)
     true)
   (if (= kind Stepper)
     (contains? properties ActiveIndex)
     true)
   (if (= kind Step)
     (match (get properties TextValue)
       (Some (StringValue value)) (not (= value ""))
       _ false)
     true)
   (if (= kind TimelineItem)
     (match (get properties TitleValue)
       (Some (StringValue value)) (not (= value ""))
       _ false)
     true)
   (if (= kind BottomTabs)
     (match (get properties AccessibilityLabel)
       (Some (StringValue value)) (not (= value ""))
       _ false)
     true)
   (if (= kind BottomTab)
     (and
      (match (get properties TitleValue)
        (Some (StringValue value)) (not (= value ""))
        _ false)
      (true-property? properties PressEnabled))
     true)
   (if (or (= kind Slider) (= kind Progress))
     (match (get properties ProgressValue)
       (Some (FloatValue _value)) true
       _ false)
     true)
   (if (= kind Tree)
     (match (get properties AccessibilityLabel)
       (Some (StringValue value)) (not (= value ""))
     _ false)
     true)
   (if (= kind Toolbar)
     (match (get properties AccessibilityLabel)
       (Some (StringValue value)) (not (= value ""))
       _ false)
     true)
   (if (= kind Split)
     (let [duration (int-property properties ResizeDuration 0)]
       (and
        (if (contains? properties ResizeEasing) (> duration 0) true)
        (if (contains? properties ResizeOrigin) (> duration 0) true)))
     true)
   (if (tree-row-kind? kind)
     (let [treeitem (treeitem-properties? properties)
           has-tree-metadata
           (or (contains? properties TreeLevel)
               (contains? properties Expanded)
               (contains? properties ChangeEnabled)
               (contains? properties ToggleEnabled))]
       (and
        (or (not has-tree-metadata) treeitem)
        (if (contains? properties Expanded)
          (true-property? properties ToggleEnabled)
          true)))
     true)))

(defn can-contain-children? [kind]
  (if (or
       (horizontal-container? kind)
       (context-menu-leaf-host-kind? kind))
    true
    (match kind
      Root true
      Row true
      Column true
      Grid true
      Stack true
      Panel true
      Card true
      Box true
      Scroll true
      ListContainer true
      VirtualList true
      RadioGroup true
      DropdownMenu true
      ContextMenu true
      ListItem true
      Dialog true
      Drawer true
      Sheet true
      Accordion true
      Table true
      TableRow true
      Tree true
      Resizable true
      Split true
      Stepper true
      Timeline true
      InputGroup true
      InputGroupActions true
      Toast true
      Toolbar true
      Alert true
      Bubble true
      BottomTabs true
      BottomTab true
      _ false)))

(defn child-kind-supported? [parent-kind child-kind]
  (cond
    (= child-kind Root) false
    (= parent-kind Root) true
    (= parent-kind MenuItem)
    (or (= child-kind ContextMenu) (= child-kind DropdownMenu))
    (context-menu-leaf-host-kind? parent-kind)
    (= child-kind ContextMenu)
    :else
    (match parent-kind
      Table (= child-kind TableRow)
      TableRow (= child-kind TableCell)
      BottomTabs (= child-kind BottomTab)
      BottomTab (not (= child-kind BottomTab))
      Tree (tree-row-kind? child-kind)
      Stepper (= child-kind Step)
      Timeline (= child-kind TimelineItem)
      InputGroup
      (or (= child-kind Textarea) (= child-kind InputGroupActions))
      Toolbar
      (or (= child-kind Button) (= child-kind ToggleButton)
          (= child-kind ButtonGroup) (= child-kind ToggleGroup)
          (= child-kind Checkbox) (= child-kind SwitchControl)
          (= child-kind Toggle) (= child-kind RadioGroup)
          (= child-kind Select) (= child-kind Combobox)
          (= child-kind TextField) (= child-kind SecureField) (= child-kind Input)
          (= child-kind SearchField) (= child-kind Divider))
      DropdownMenu (or (= child-kind MenuItem) (= child-kind Divider))
      ContextMenu (or (= child-kind MenuItem) (= child-kind Divider))
      _ true)))

(defn create-node-op [node kind]
  (CreateNode node kind))

(defn create-extension-op [node identifier fingerprint]
  (CreateExtension node identifier fingerprint))

(defn drop-node-op [node]
  (DropNode node))

(defn set-prop-op [node property value]
  (SetProp node property value))

(defn remove-prop-op [node property]
  (RemoveProp node property))

(defn set-extension-prop-op [node property value]
  (SetExtensionProp node property value))

(defn remove-extension-prop-op [node property]
  (RemoveExtensionProp node property))

(defn insert-child-op [parent child index]
  (InsertChild parent child index))

(defn remove-child-op [parent child]
  (RemoveChild parent child))

(defn move-child-op [parent child index]
  (MoveChild parent child index))
