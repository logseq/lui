;; Generated from schema/components.json. Do not edit by hand.
(ns lui.wire-schema
  (:require [lui.protocol :refer [Row Column Grid Stack Panel Card
                     Box Text Heading Paragraph Label Button
                     ToggleButton TextInput TextArea Checkbox SwitchControl ProgressControl
                     Divider Scroll ListContainer Spacer Spinner Icon
                     TextValue Enabled Gap MainAlignment CrossAlignment GrowValue
                     GridColumns PaddingValue PaddingHorizontal PaddingVertical BackgroundValue ForegroundValue
                     BorderColorValue BorderWidth CornerRadius WidthValue HeightValue MinWidth
                     MaxWidth MinHeight MaxHeight PlaceholderValue ReadOnly AccessibilityLabel
                     MinLines MaxLines StyleClass HeadingLevel LabelledBy DescribedBy
                     ErrorMessageBy InputType Invalid Checked ProgressValue MinValue
                     MaxValue OrientationValue SizeValue IconName VariantValue InlineIconName
                     IconPlacementValue Selected Autofocus HoldEnabled]]))

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
    IconName "name"
    VariantValue "variant"
    InlineIconName "icon"
    IconPlacementValue "icon-placement"
    Selected "selected"
    Autofocus "autofocus"
    HoldEnabled "hold-enabled"))
