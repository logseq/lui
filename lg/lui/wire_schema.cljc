;; Generated from schema/components.json. Do not edit by hand.
(ns lui.wire-schema
  (:require [lui.protocol :refer [Row Column Grid Stack Panel Card
                     Box Text Heading Paragraph Label Button
                     ToggleButton Toggle RadioGroup Radio Slider TextField
                     Input SearchField Textarea Checkbox SwitchControl Progress
                     Divider Scroll ListContainer Spacer Spinner Icon
                     Select Combobox DropdownMenu MenuItem TextValue Enabled
                     Gap MainAlignment CrossAlignment GrowValue GridColumns PaddingValue
                     PaddingHorizontal PaddingVertical BackgroundValue ForegroundValue BorderColorValue BorderWidth
                     CornerRadius WidthValue HeightValue MinWidth MaxWidth MinHeight
                     MaxHeight PlaceholderValue AccessibilityLabel StyleClass HeadingLevel Checked
                     ProgressValue OrientationValue SizeValue IconName VariantValue InlineIconName
                     IconPlacementValue Selected Autofocus SubmitOnEnter HoldEnabled ChangeEnabled
                     ToggleEnabled PressEnabled SubmitEnabled AnchorValue AnchorAlignmentValue AnchorOffset]]))

(defn node-kind-name [kind]
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
    Spacer "spacer"
    Spinner "spinner"
    Icon "icon"
    Select "select"
    Combobox "combobox"
    DropdownMenu "dropdown-menu"
    MenuItem "menu-item"))

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
    AnchorValue "anchor"
    AnchorAlignmentValue "anchor-alignment"
    AnchorOffset "anchor-offset"))
