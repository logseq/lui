(* Generated from schema/components.json. Do not edit by hand. *)


open Lui_protocol

let node_kind_name kind =
  match kind with
  | Root -> "root"
  | Row -> "row"
  | Column -> "column"
  | Grid -> "grid"
  | Stack -> "stack"
  | EdgeInset -> "edge-inset"
  | Overlay -> "overlay"
  | ViewThatFits -> "view-that-fits"
  | Panel -> "panel"
  | Card -> "card"
  | Alert -> "alert"
  | Bubble -> "bubble"
  | Box -> "box"
  | Text -> "text"
  | Heading -> "heading"
  | Paragraph -> "paragraph"
  | Label -> "label"
  | Button -> "button"
  | ToggleButton -> "toggle-button"
  | Toggle -> "toggle"
  | RadioGroup -> "radio-group"
  | Radio -> "radio"
  | Slider -> "slider"
  | NumberStepper -> "number-stepper"
  | TextField -> "text-field"
  | SecureField -> "secure-field"
  | Input -> "input"
  | SearchField -> "search-field"
  | Textarea -> "textarea"
  | Checkbox -> "checkbox"
  | SwitchControl -> "switch"
  | Progress -> "progress"
  | Divider -> "divider"
  | Scroll -> "scroll"
  | ListContainer -> "list"
  | VirtualList -> "virtual-list"
  | Tabs -> "tabs"
  | BottomTabs -> "bottom-tabs"
  | BottomTab -> "bottom-tab"
  | ButtonGroup -> "button-group"
  | ToggleGroup -> "toggle-group"
  | Spacer -> "spacer"
  | Spinner -> "spinner"
  | Icon -> "icon"
  | Select -> "select"
  | Combobox -> "combobox"
  | DropdownMenu -> "dropdown-menu"
  | ContextMenu -> "context-menu"
  | MenuItem -> "menu-item"
  | MenuTrigger -> "menu-trigger"
  | ListItem -> "list-item"
  | Avatar -> "avatar"
  | Image -> "image"
  | MediaSurface -> "media-surface"
  | Stepper -> "stepper"
  | Step -> "step"
  | Timeline -> "timeline"
  | TimelineItem -> "timeline-item"
  | InputGroup -> "input-group"
  | InputGroupActions -> "input-group-actions"
  | Breadcrumb -> "breadcrumb"
  | Pagination -> "pagination"
  | Accordion -> "accordion"
  | Table -> "table"
  | TableRow -> "table-row"
  | TableCell -> "table-cell"
  | Tree -> "tree"
  | Resizable -> "resizable"
  | Split -> "split"
  | Dialog -> "dialog"
  | Drawer -> "drawer"
  | Sheet -> "sheet"
  | Tooltip -> "tooltip"
  | Toast -> "toast"
  | Toolbar -> "toolbar"
  | StatusBar -> "status-bar"
  | ListSection -> "list-section"
  | ListSectionHeader -> "list-section-header"
  | ListSectionFooter -> "list-section-footer"
  | SwipeActions -> "swipe-actions"
  | SwipeAction -> "swipe-action"
  | FilePicker -> "file-picker"
  | Kbd -> "kbd"
  | Link -> "link"
  | FileImage -> "file-image"
  | FilePreview -> "file-preview"
  | Br -> "br"

let standard_node_name name =
  match name with
  | "root" -> true
  | "row" -> true
  | "column" -> true
  | "grid" -> true
  | "stack" -> true
  | "edge-inset" -> true
  | "overlay" -> true
  | "view-that-fits" -> true
  | "panel" -> true
  | "card" -> true
  | "alert" -> true
  | "bubble" -> true
  | "box" -> true
  | "text" -> true
  | "heading" -> true
  | "paragraph" -> true
  | "label" -> true
  | "button" -> true
  | "toggle-button" -> true
  | "toggle" -> true
  | "radio-group" -> true
  | "radio" -> true
  | "slider" -> true
  | "number-stepper" -> true
  | "text-field" -> true
  | "secure-field" -> true
  | "input" -> true
  | "search-field" -> true
  | "textarea" -> true
  | "checkbox" -> true
  | "switch" -> true
  | "progress" -> true
  | "divider" -> true
  | "scroll" -> true
  | "list" -> true
  | "virtual-list" -> true
  | "tabs" -> true
  | "bottom-tabs" -> true
  | "bottom-tab" -> true
  | "button-group" -> true
  | "toggle-group" -> true
  | "spacer" -> true
  | "spinner" -> true
  | "icon" -> true
  | "select" -> true
  | "combobox" -> true
  | "dropdown-menu" -> true
  | "context-menu" -> true
  | "menu-item" -> true
  | "menu-trigger" -> true
  | "list-item" -> true
  | "avatar" -> true
  | "image" -> true
  | "media-surface" -> true
  | "stepper" -> true
  | "step" -> true
  | "timeline" -> true
  | "timeline-item" -> true
  | "input-group" -> true
  | "input-group-actions" -> true
  | "breadcrumb" -> true
  | "pagination" -> true
  | "accordion" -> true
  | "table" -> true
  | "table-row" -> true
  | "table-cell" -> true
  | "tree" -> true
  | "resizable" -> true
  | "split" -> true
  | "dialog" -> true
  | "drawer" -> true
  | "sheet" -> true
  | "tooltip" -> true
  | "toast" -> true
  | "toolbar" -> true
  | "status-bar" -> true
  | "list-section" -> true
  | "list-section-header" -> true
  | "list-section-footer" -> true
  | "swipe-actions" -> true
  | "swipe-action" -> true
  | "file-picker" -> true
  | "kbd" -> true
  | "link" -> true
  | "file-image" -> true
  | "file-preview" -> true
  | "br" -> true
  | _ -> false

let property_name property =
  match property with
  | TextValue -> "text"
  | Enabled -> "enabled"
  | Gap -> "gap"
  | MainAlignment -> "main"
  | CrossAlignment -> "cross"
  | GrowValue -> "grow"
  | GridColumns -> "columns"
  | PaddingValue -> "padding"
  | PaddingHorizontal -> "padding-horizontal"
  | PaddingVertical -> "padding-vertical"
  | BackgroundValue -> "background"
  | ForegroundValue -> "foreground"
  | BorderColorValue -> "border-color"
  | BorderWidth -> "border-width"
  | CornerRadius -> "corner-radius"
  | WidthValue -> "width"
  | HeightValue -> "height"
  | MinWidth -> "min-width"
  | MaxWidth -> "max-width"
  | MinHeight -> "min-height"
  | MaxHeight -> "max-height"
  | ContainerRelativeFrameValue -> "container-relative-frame"
  | ContainerRelativeFrameInset -> "container-relative-frame-inset"
  | PlaceholderValue -> "placeholder"
  | AccessibilityLabel -> "accessibility-label"
  | AccessibilityIdentifier -> "accessibility-identifier"
  | StyleClass -> "style-class"
  | HeadingLevel -> "heading-level"
  | Checked -> "checked"
  | ProgressValue -> "value"
  | OrientationValue -> "orientation"
  | PlacementValue -> "placement"
  | SizeValue -> "size"
  | IconName -> "name"
  | VariantValue -> "variant"
  | InlineIconName -> "icon"
  | IconPlacementValue -> "icon-placement"
  | Selected -> "selected"
  | Autofocus -> "autofocus"
  | SubmitOnEnter -> "submit-on-enter"
  | LongPressEnabled -> "long-press-enabled"
  | ChangeEnabled -> "change-enabled"
  | ToggleEnabled -> "toggle-enabled"
  | PressEnabled -> "press-enabled"
  | SubmitEnabled -> "submit-enabled"
  | DoublePressEnabled -> "double-press-enabled"
  | AppearEnabled -> "appear-enabled"
  | ImageIdValue -> "image"
  | SurfaceIdValue -> "surface"
  | ActiveIndex -> "active"
  | TitleValue -> "title"
  | DescriptionValue -> "description"
  | MetaValue -> "meta"
  | IndicatorValue -> "indicator"
  | Connector -> "connector"
  | SourceX -> "source-x"
  | SourceY -> "source-y"
  | SourceWidth -> "source-width"
  | SourceHeight -> "source-height"
  | AnchorValue -> "anchor"
  | AnchorAlignmentValue -> "anchor-alignment"
  | AnchorOffset -> "anchor-offset"
  | TooltipDelay -> "tooltip-delay"
  | DurationValue -> "duration"
  | TextAlignment -> "text-alignment"
  | RoleValue -> "role"
  | TreeLevel -> "tree-level"
  | Expanded -> "expanded"
  | ResizeDuration -> "resize-duration"
  | ResizeEasing -> "resize-easing"
  | ResizeOrigin -> "resize-origin"
  | ThemeValue -> "theme"
  | ThemeMode -> "theme-mode"
  | KeyValue -> "key"
  | SeparatorValue -> "separator"
  | StyleValue -> "style"
  | ScrollTarget -> "scroll-target"
  | ScrollAnchor -> "scroll-anchor"
  | ScrollToken -> "scroll-token"
  | ScrollAnimated -> "scroll-animated"
  | TrackVisibleRange -> "track-visible-range"
  | EdgeValue -> "edge"
  | PickerRequest -> "request"
  | PickerTypes -> "types"
  | PickerMultiple -> "multiple"
  | PickerSource -> "source"
  | PickerCompletion -> "completion"
  | MinValue -> "min"
  | MaxValue -> "max"
  | StepValue -> "step"
  | Detents -> "detents"
  | Sizing -> "sizing"
  | PathValue -> "path"
  | UrlValue -> "url"
  | MaxPixelSize -> "max-pixel-size"
  | ImageFitValue -> "image-fit"
  | Visible -> "visible"
  | AlignmentValue -> "alignment"
  | PointerEnabled -> "pointer-enabled"
  | DataAttrs -> "data-attrs"
  | As -> "as"
  | AltValue -> "alt"
  | LoadingValue -> "loading"
  | ReferrerPolicy -> "referrer-policy"
  | TargetValue -> "target"
  | Opacity -> "opacity"
  | DisplayValue -> "display"
  | TooltipText -> "tooltip"
  | TooltipKeys -> "tooltip-keys"
  | InputType -> "input-type"

let kind_property_matrix kind =
  match kind with
  | Accordion -> Some [ TextValue; Selected; ToggleEnabled; HeightValue; PointerEnabled ]
  | Stepper -> Some [ ActiveIndex; AccessibilityLabel; PointerEnabled ]
  | Step -> Some [ TextValue; PointerEnabled ]
  | Timeline -> Some [ Gap; GrowValue; AccessibilityLabel; PointerEnabled ]
  | TimelineItem -> Some [ TitleValue; DescriptionValue; MetaValue; IndicatorValue; InlineIconName; VariantValue; Connector; Selected; PressEnabled; PointerEnabled ]
  | InputGroup -> Some [ AccessibilityLabel; WidthValue; HeightValue; MinWidth; GrowValue; PointerEnabled ]
  | InputGroupActions -> Some [ Gap; PointerEnabled ]
  | Toast -> Some [ DurationValue; AccessibilityLabel; StyleClass; DataAttrs; PointerEnabled ]
  | Toolbar -> Some [ OrientationValue; AccessibilityLabel; Gap; StyleClass; DataAttrs; PlacementValue; PointerEnabled ]
  | BottomTabs -> Some [ AccessibilityLabel; StyleClass; DataAttrs; GrowValue; WidthValue; HeightValue; MinWidth; MaxWidth; MinHeight; MaxHeight; PointerEnabled ]
  | BottomTab -> Some [ TitleValue; InlineIconName; Selected; Enabled; PressEnabled; PointerEnabled ]
  | MenuTrigger -> Some [ TextValue; InlineIconName; AccessibilityLabel; Enabled; ForegroundValue; StyleClass; DataAttrs; PointerEnabled ]
  | ListSection -> Some [ KeyValue; SeparatorValue; PointerEnabled ]
  | SwipeActions -> Some [  ]
  | SwipeAction -> Some [ TextValue; InlineIconName; VariantValue; EdgeValue; Enabled; BackgroundValue; PressEnabled; PointerEnabled ]
  | FilePicker -> Some [ PickerRequest; PickerTypes; PickerMultiple; PickerSource; PickerCompletion; Enabled; AppearEnabled; PointerEnabled ]
  | FilePreview -> Some [ PathValue; PointerEnabled ]
  | Kbd -> Some [ TextValue; StyleClass; DataAttrs; PointerEnabled ]
  | _ -> None

let kind_extra_properties kind =
  match kind with
  | Dialog -> [ DescriptionValue ]
  | _ -> []

let all_node_kinds = [ Root; Row; Column; Grid; Stack; EdgeInset; Overlay; ViewThatFits; Panel; Card; Alert; Bubble; Box; Text; Heading; Paragraph; Label; Button; ToggleButton; Toggle; RadioGroup; Radio; Slider; NumberStepper; TextField; SecureField; Input; SearchField; Textarea; Checkbox; SwitchControl; Progress; Divider; Scroll; ListContainer; VirtualList; Tabs; BottomTabs; BottomTab; ButtonGroup; ToggleGroup; Spacer; Spinner; Icon; Select; Combobox; DropdownMenu; ContextMenu; MenuItem; MenuTrigger; ListItem; Avatar; Image; MediaSurface; Stepper; Step; Timeline; TimelineItem; InputGroup; InputGroupActions; Breadcrumb; Pagination; Accordion; Table; TableRow; TableCell; Tree; Resizable; Split; Dialog; Drawer; Sheet; Tooltip; Toast; Toolbar; StatusBar; ListSection; ListSectionHeader; ListSectionFooter; SwipeActions; SwipeAction; FilePicker; Kbd; Link; FileImage; FilePreview; Br ]

let all_properties = [ TextValue; Enabled; Gap; MainAlignment; CrossAlignment; GrowValue; GridColumns; PaddingValue; PaddingHorizontal; PaddingVertical; BackgroundValue; ForegroundValue; BorderColorValue; BorderWidth; CornerRadius; WidthValue; HeightValue; MinWidth; MaxWidth; MinHeight; MaxHeight; ContainerRelativeFrameValue; ContainerRelativeFrameInset; PlaceholderValue; AccessibilityLabel; AccessibilityIdentifier; StyleClass; HeadingLevel; Checked; ProgressValue; OrientationValue; PlacementValue; SizeValue; IconName; VariantValue; InlineIconName; IconPlacementValue; Selected; Autofocus; SubmitOnEnter; LongPressEnabled; ChangeEnabled; ToggleEnabled; PressEnabled; SubmitEnabled; DoublePressEnabled; AppearEnabled; ImageIdValue; SurfaceIdValue; ActiveIndex; TitleValue; DescriptionValue; MetaValue; IndicatorValue; Connector; SourceX; SourceY; SourceWidth; SourceHeight; AnchorValue; AnchorAlignmentValue; AnchorOffset; TooltipDelay; DurationValue; TextAlignment; RoleValue; TreeLevel; Expanded; ResizeDuration; ResizeEasing; ResizeOrigin; ThemeValue; ThemeMode; KeyValue; SeparatorValue; StyleValue; ScrollTarget; ScrollAnchor; ScrollToken; ScrollAnimated; TrackVisibleRange; EdgeValue; PickerRequest; PickerTypes; PickerMultiple; PickerSource; PickerCompletion; MinValue; MaxValue; StepValue; Detents; Sizing; PathValue; UrlValue; MaxPixelSize; ImageFitValue; Visible; AlignmentValue; PointerEnabled; DataAttrs; As; AltValue; LoadingValue; ReferrerPolicy; TargetValue; Opacity; DisplayValue; TooltipText; TooltipKeys; InputType ]
