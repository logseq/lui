;; Generated from schema/components.json. Do not edit by hand.
(ns lui.wire-schema
  (:require [lui.protocol :refer [Row Column Grid Stack Panel Card
                     Alert Bubble Box Text Heading Paragraph
                     Label Button ToggleButton Toggle RadioGroup Radio
                     Slider TextField Input SearchField Textarea Checkbox
                     SwitchControl Progress Divider Scroll ListContainer Tabs
                     ButtonGroup ToggleGroup Spacer Spinner Icon Select
                     Combobox DropdownMenu ContextMenu MenuItem ListItem Avatar
                     Image MediaSurface Stepper Step Timeline TimelineItem
                     InputGroup InputGroupActions Breadcrumb Pagination Accordion Table
                     TableRow TableCell Tree Resizable Split Dialog
                     Drawer Sheet Tooltip StatusBar TextValue Enabled
                     Gap MainAlignment CrossAlignment GrowValue GridColumns PaddingValue
                     PaddingHorizontal PaddingVertical BackgroundValue ForegroundValue BorderColorValue BorderWidth
                     CornerRadius WidthValue HeightValue MinWidth MaxWidth MinHeight
                     MaxHeight PlaceholderValue AccessibilityLabel StyleClass HeadingLevel Checked
                     ProgressValue OrientationValue SizeValue IconName VariantValue InlineIconName
                     IconPlacementValue Selected Autofocus SubmitOnEnter HoldEnabled ChangeEnabled
                     ToggleEnabled PressEnabled SubmitEnabled DoublePressEnabled ImageIdValue SurfaceIdValue
                     ActiveIndex TitleValue DescriptionValue MetaValue IndicatorValue Connector
                     SourceX SourceY SourceWidth SourceHeight AnchorValue AnchorAlignmentValue
                     AnchorOffset TooltipDelay TextAlignment RoleValue TreeLevel Expanded
                     ResizeDuration ResizeEasing ResizeOrigin]]))

(defn node-kind-name [kind]
  (match kind
    Row "row"
    Column "column"
    Grid "grid"
    Stack "stack"
    Panel "panel"
    Card "card"
    Alert "alert"
    Bubble "bubble"
    Box "box"
    Text "text"
    Heading "heading"
    Paragraph "paragraph"
    Label "label"
    Button "button"
    ToggleButton "toggle-button"
    Toggle "toggle"
    RadioGroup "radio-group"
    Radio "radio"
    Slider "slider"
    TextField "text-field"
    Input "input"
    SearchField "search-field"
    Textarea "textarea"
    Checkbox "checkbox"
    SwitchControl "switch"
    Progress "progress"
    Divider "divider"
    Scroll "scroll"
    ListContainer "list"
    Tabs "tabs"
    ButtonGroup "button-group"
    ToggleGroup "toggle-group"
    Spacer "spacer"
    Spinner "spinner"
    Icon "icon"
    Select "select"
    Combobox "combobox"
    DropdownMenu "dropdown-menu"
    ContextMenu "context-menu"
    MenuItem "menu-item"
    ListItem "list-item"
    Avatar "avatar"
    Image "image"
    MediaSurface "media-surface"
    Stepper "stepper"
    Step "step"
    Timeline "timeline"
    TimelineItem "timeline-item"
    InputGroup "input-group"
    InputGroupActions "input-group-actions"
    Breadcrumb "breadcrumb"
    Pagination "pagination"
    Accordion "accordion"
    Table "table"
    TableRow "table-row"
    TableCell "table-cell"
    Tree "tree"
    Resizable "resizable"
    Split "split"
    Dialog "dialog"
    Drawer "drawer"
    Sheet "sheet"
    Tooltip "tooltip"
    StatusBar "status-bar"))

(defn property-name [property]
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
    AccessibilityLabel "accessibility-label"
    StyleClass "style-class"
    HeadingLevel "heading-level"
    Checked "checked"
    ProgressValue "value"
    OrientationValue "orientation"
    SizeValue "size"
    IconName "name"
    VariantValue "variant"
    InlineIconName "icon"
    IconPlacementValue "icon-placement"
    Selected "selected"
    Autofocus "autofocus"
    SubmitOnEnter "submit-on-enter"
    HoldEnabled "hold-enabled"
    ChangeEnabled "change-enabled"
    ToggleEnabled "toggle-enabled"
    PressEnabled "press-enabled"
    SubmitEnabled "submit-enabled"
    DoublePressEnabled "double-press-enabled"
    ImageIdValue "image"
    SurfaceIdValue "surface"
    ActiveIndex "active"
    TitleValue "title"
    DescriptionValue "description"
    MetaValue "meta"
    IndicatorValue "indicator"
    Connector "connector"
    SourceX "source-x"
    SourceY "source-y"
    SourceWidth "source-width"
    SourceHeight "source-height"
    AnchorValue "anchor"
    AnchorAlignmentValue "anchor-alignment"
    AnchorOffset "anchor-offset"
    TooltipDelay "tooltip-delay"
    TextAlignment "text-alignment"
    RoleValue "role"
    TreeLevel "tree-level"
    Expanded "expanded"
    ResizeDuration "resize-duration"
    ResizeEasing "resize-easing"
    ResizeOrigin "resize-origin"))
