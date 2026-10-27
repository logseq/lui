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
  | Popover -> "popover"

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
  | "popover" -> true
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
  | PaddingTop -> "padding-top"
  | PaddingRight -> "padding-right"
  | PaddingBottom -> "padding-bottom"
  | PaddingLeft -> "padding-left"
  | MarginValue -> "margin"
  | MarginHorizontal -> "margin-horizontal"
  | MarginVertical -> "margin-vertical"
  | MarginTop -> "margin-top"
  | MarginRight -> "margin-right"
  | MarginBottom -> "margin-bottom"
  | MarginLeft -> "margin-left"
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
  | SelectionPlacementValue -> "selection-placement"
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
  | AnchorTarget -> "anchor-target"
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
  | PickerAccept -> "accept"
  | PickerDirectory -> "directory"
  | PopupX -> "x"
  | PopupY -> "y"
  | AvailableHeight -> "available-height"
  | FontSize -> "font-size"
  | FontWeight -> "font-weight"
  | FontStyle -> "font-style"
  | LineHeight -> "line-height"
  | LetterSpacing -> "letter-spacing"
  | Position -> "position"
  | Inset -> "inset"
  | InsetTop -> "inset-top"
  | InsetRight -> "inset-right"
  | InsetBottom -> "inset-bottom"
  | InsetLeft -> "inset-left"
  | ZIndex -> "z-index"
  | WhiteSpace -> "white-space"
  | TextOverflow -> "text-overflow"
  | Overflow -> "overflow"
  | UserSelect -> "user-select"
  | Cursor -> "cursor"
  | Shadow -> "shadow"
  | HoverBackground -> "hover-background"
  | HoverOpacity -> "hover-opacity"
  | HoverShadow -> "hover-shadow"
  | PressedBackground -> "pressed-background"
  | PressedOpacity -> "pressed-opacity"
  | PressedShadow -> "pressed-shadow"
  | FocusShadow -> "focus-shadow"
  | FocusWithinBackground -> "focus-within-background"
  | FocusWithinBorder -> "focus-within-border"
  | SelectedBackground -> "selected-background"
  | SelectedShadow -> "selected-shadow"
  | SelectedHoverShadow -> "selected-hover-shadow"
  | DisabledOpacity -> "disabled-opacity"
  | WidthViewport -> "width-viewport"
  | HeightViewport -> "height-viewport"
  | MinWidthViewport -> "min-width-viewport"
  | MaxWidthViewport -> "max-width-viewport"
  | MinHeightViewport -> "min-height-viewport"
  | MaxHeightViewport -> "max-height-viewport"
  | FontFamily -> "font-family"
  | TextDecoration -> "text-decoration"
  | ListStyle -> "list-style"
  | FlexWrap -> "flex-wrap"
  | HoverForeground -> "hover-foreground"
  | HoverBorder -> "hover-border"
  | Transition -> "transition"
  | Inert -> "inert"
  | NavigateEnabled -> "navigate-enabled"
  | FirstPaneWidth -> "first-pane-width"
  | GridColumnSpan -> "grid-column-span"
  | LabelOpacity -> "label-opacity"
  | SubmitOnBlur -> "submit-on-blur"
  | AnchorAlignmentOffset -> "anchor-alignment-offset"
  | AnchorRect -> "anchor-rect"
  | ResizeHandleWidth -> "resize-handle-width"
  | ResizeHandleOffset -> "resize-handle-offset"
  | IndicatorBorderColor -> "indicator-border-color"
  | CheckedIndicatorBorderColor -> "checked-indicator-border-color"
  | CollisionPadding -> "collision-padding"
  | LineClamp -> "line-clamp"
  | ReadOnly -> "read-only"
  | VirtualOverscan -> "overscan"
  | VirtualItemExtent -> "item-extent"
  | PointerCapture -> "pointer-capture"
  | Indeterminate -> "indeterminate"
  | ToggleDetailEnabled -> "toggle-detail-enabled"

let kind_property_matrix kind =
  match kind with
  | Accordion -> Some [ TextValue; Selected; ToggleEnabled; HeightValue; PointerEnabled; StyleClass ]
  | Stepper -> Some [ ActiveIndex; AccessibilityLabel; PointerEnabled ]
  | Step -> Some [ TextValue; PointerEnabled ]
  | Timeline -> Some [ Gap; GrowValue; AccessibilityLabel; PointerEnabled ]
  | TimelineItem -> Some [ TitleValue; DescriptionValue; MetaValue; IndicatorValue; InlineIconName; VariantValue; Connector; Selected; PressEnabled; PointerEnabled ]
  | InputGroup -> Some [ AccessibilityLabel; WidthValue; HeightValue; MinWidth; GrowValue; PointerEnabled ]
  | InputGroupActions -> Some [ Gap; PointerEnabled ]
  | Toast -> Some [ DurationValue; AccessibilityLabel; StyleClass; DataAttrs; PointerEnabled; PaddingValue; PaddingHorizontal; PaddingVertical; PaddingTop; PaddingRight; PaddingBottom; PaddingLeft; MarginValue; MarginHorizontal; MarginVertical; MarginTop; MarginRight; MarginBottom; MarginLeft ]
  | Toolbar -> Some [ HeightValue; PaddingValue; BackgroundValue; BorderWidth; CornerRadius; OrientationValue; AccessibilityLabel; Gap; StyleClass; DataAttrs; PlacementValue; PointerEnabled ]
  | BottomTabs -> Some [ AccessibilityLabel; StyleClass; DataAttrs; GrowValue; WidthValue; HeightValue; MinWidth; MaxWidth; MinHeight; MaxHeight; PointerEnabled ]
  | BottomTab -> Some [ TitleValue; InlineIconName; Selected; Enabled; PressEnabled; PointerEnabled ]
  | MenuTrigger -> Some [ TextValue; TextAlignment; InlineIconName; AccessibilityLabel; Enabled; ForegroundValue; StyleClass; DataAttrs; PointerEnabled ]
  | ListSection -> Some [ KeyValue; SeparatorValue; PointerEnabled ]
  | SwipeActions -> Some [  ]
  | SwipeAction -> Some [ TextValue; InlineIconName; VariantValue; EdgeValue; Enabled; BackgroundValue; PressEnabled; PointerEnabled ]
  | FilePicker -> Some [ PickerRequest; PickerTypes; PickerMultiple; PickerSource; PickerCompletion; PickerAccept; PickerDirectory; Enabled; AppearEnabled; PointerEnabled ]
  | FilePreview -> Some [ PathValue; PointerEnabled ]
  | Kbd -> Some [ TextValue; StyleClass; DataAttrs; PointerEnabled; BackgroundValue; BorderColorValue; BorderWidth; CornerRadius; ForegroundValue; GrowValue; PaddingValue; PaddingHorizontal; PaddingVertical; PaddingTop; PaddingRight; PaddingBottom; PaddingLeft; WidthValue; HeightValue; MinWidth; MaxWidth; MinHeight; MaxHeight; Opacity; FontSize; FontWeight; FontStyle; LineHeight; LetterSpacing; FontFamily; TextDecoration; WhiteSpace; TextOverflow; UserSelect; Cursor; Shadow; HoverBackground; HoverOpacity; HoverShadow; PressedBackground; PressedOpacity; PressedShadow; FocusShadow; FocusWithinBackground; FocusWithinBorder; SelectedBackground; SelectedShadow; SelectedHoverShadow; DisabledOpacity; Transition ]
  | _ -> None

let kind_extra_properties kind =
  match kind with
  | Image -> [ ImageFitValue ]
  | Checkbox -> [ Gap; LabelOpacity; IndicatorBorderColor; CheckedIndicatorBorderColor ]
  | Radio -> [ Gap; LabelOpacity ]
  | Grid -> [ MainAlignment; CrossAlignment ]
  | Row -> [ OrientationValue ]
  | ListItem -> [ DisplayValue ]
  | Dialog -> [ DescriptionValue; BackgroundValue; ForegroundValue; BorderColorValue; BorderWidth; CornerRadius; Gap ]
  | Box -> [ Inert ]
  | Popover -> [ CollisionPadding ]
  | DropdownMenu -> [ CollisionPadding ]
  | Tooltip -> [ CollisionPadding ]
  | SwitchControl -> [ ForegroundValue ]
  | VirtualList -> [ VirtualOverscan; VirtualItemExtent ]
  | TextField -> [ ReadOnly ]
  | SecureField -> [ ReadOnly ]
  | Input -> [ ReadOnly ]
  | SearchField -> [ ReadOnly ]
  | Textarea -> [ ReadOnly ]
  | Combobox -> [ ReadOnly ]
  | _ -> []

let all_node_kinds = [ Root; Row; Column; Grid; Stack; EdgeInset; Overlay; ViewThatFits; Panel; Card; Alert; Bubble; Box; Text; Heading; Paragraph; Label; Button; ToggleButton; Toggle; RadioGroup; Radio; Slider; NumberStepper; TextField; SecureField; Input; SearchField; Textarea; Checkbox; SwitchControl; Progress; Divider; Scroll; ListContainer; VirtualList; Tabs; BottomTabs; BottomTab; ButtonGroup; ToggleGroup; Spacer; Spinner; Icon; Select; Combobox; DropdownMenu; ContextMenu; MenuItem; MenuTrigger; ListItem; Avatar; Image; MediaSurface; Stepper; Step; Timeline; TimelineItem; InputGroup; InputGroupActions; Breadcrumb; Pagination; Accordion; Table; TableRow; TableCell; Tree; Resizable; Split; Dialog; Drawer; Sheet; Tooltip; Toast; Toolbar; StatusBar; ListSection; ListSectionHeader; ListSectionFooter; SwipeActions; SwipeAction; FilePicker; Kbd; Link; FileImage; FilePreview; Popover ]

let all_properties = [ TextValue; Enabled; Gap; MainAlignment; CrossAlignment; GrowValue; GridColumns; PaddingValue; PaddingHorizontal; PaddingVertical; PaddingTop; PaddingRight; PaddingBottom; PaddingLeft; MarginValue; MarginHorizontal; MarginVertical; MarginTop; MarginRight; MarginBottom; MarginLeft; BackgroundValue; ForegroundValue; BorderColorValue; BorderWidth; CornerRadius; WidthValue; HeightValue; MinWidth; MaxWidth; MinHeight; MaxHeight; ContainerRelativeFrameValue; ContainerRelativeFrameInset; PlaceholderValue; AccessibilityLabel; AccessibilityIdentifier; StyleClass; HeadingLevel; Checked; ProgressValue; OrientationValue; PlacementValue; SizeValue; IconName; VariantValue; InlineIconName; IconPlacementValue; SelectionPlacementValue; Selected; Autofocus; SubmitOnEnter; LongPressEnabled; ChangeEnabled; ToggleEnabled; PressEnabled; SubmitEnabled; DoublePressEnabled; AppearEnabled; ImageIdValue; SurfaceIdValue; ActiveIndex; TitleValue; DescriptionValue; MetaValue; IndicatorValue; Connector; SourceX; SourceY; SourceWidth; SourceHeight; AnchorValue; AnchorTarget; AnchorAlignmentValue; AnchorOffset; TooltipDelay; DurationValue; TextAlignment; RoleValue; TreeLevel; Expanded; ResizeDuration; ResizeEasing; ResizeOrigin; ThemeValue; ThemeMode; KeyValue; SeparatorValue; StyleValue; ScrollTarget; ScrollAnchor; ScrollToken; ScrollAnimated; TrackVisibleRange; EdgeValue; PickerRequest; PickerTypes; PickerMultiple; PickerSource; PickerCompletion; MinValue; MaxValue; StepValue; Detents; Sizing; PathValue; UrlValue; MaxPixelSize; ImageFitValue; Visible; AlignmentValue; PointerEnabled; DataAttrs; As; AltValue; LoadingValue; ReferrerPolicy; TargetValue; Opacity; DisplayValue; TooltipText; TooltipKeys; InputType; PickerAccept; PickerDirectory; PopupX; PopupY; AvailableHeight; FontSize; FontWeight; FontStyle; LineHeight; LetterSpacing; Position; Inset; InsetTop; InsetRight; InsetBottom; InsetLeft; ZIndex; WhiteSpace; TextOverflow; Overflow; UserSelect; Cursor; Shadow; HoverBackground; HoverOpacity; HoverShadow; PressedBackground; PressedOpacity; PressedShadow; FocusShadow; FocusWithinBackground; FocusWithinBorder; SelectedBackground; SelectedShadow; SelectedHoverShadow; DisabledOpacity; WidthViewport; HeightViewport; MinWidthViewport; MaxWidthViewport; MinHeightViewport; MaxHeightViewport; FontFamily; TextDecoration; ListStyle; FlexWrap; HoverForeground; HoverBorder; Transition; Inert; NavigateEnabled; FirstPaneWidth; GridColumnSpan; LabelOpacity; SubmitOnBlur; AnchorAlignmentOffset; AnchorRect; ResizeHandleWidth; ResizeHandleOffset; IndicatorBorderColor; CheckedIndicatorBorderColor; CollisionPadding; LineClamp; ReadOnly; VirtualOverscan; VirtualItemExtent; PointerCapture; Indeterminate; ToggleDetailEnabled ]


type view_value =
  | ViewString | ViewBool | ViewInt | ViewFloat
  | ViewEnum of string list
  | ViewIcon of string list
  | ViewToken | ViewAttributes | ViewFloatTuple of int

type view_children = ViewList of string | ViewArguments of string list

type 'property view_contract = {
  view_result : string;
  view_children : view_children;
  view_properties : ('property * view_value * bool) list;
  view_events : string list;
  view_slots : (string * string * bool) list;
}

let view_element_tag = ViewEnum ["span"; "em"; "strong"; "b"; "i"; "u"; "s"; "del"; "mark"; "small"; "code"; "kbd"; "sub"; "sup"; "pre"; "h1"; "h2"; "h3"; "h4"; "h5"; "h6"; "p"; "div"; "ul"; "ol"; "li"; "label"]
let view_main_alignment = ViewEnum ["start"; "center"; "end"; "space_between"]
let view_cross_alignment = ViewEnum ["stretch"; "start"; "center"; "end"]
let view_orientation = ViewEnum ["horizontal"; "vertical"]
let view_frame_axes = ViewEnum ["horizontal"; "vertical"; "both"; "min-horizontal"; "min-vertical"; "min-both"]
let view_display = ViewEnum ["contents"; "none"; "block"; "inline"; "inline-block"; "inline-flex"]
let view_flex_wrap = ViewEnum ["nowrap"; "wrap"]
let view_alignment = ViewEnum ["top-leading"; "top"; "top-trailing"; "leading"; "center"; "trailing"; "bottom-leading"; "bottom"; "bottom-trailing"]
let view_edge = ViewEnum ["top"; "bottom"; "leading"; "trailing"]
let view_variant = ViewEnum ["default"; "primary"; "secondary"; "outline"; "ghost"; "destructive"]
let view_text_alignment = ViewEnum ["start"; "center"; "end"]
let view_control_size = ViewEnum ["default"; "sm"; "lg"; "icon"]
let view_icon = ViewIcon ["alert"; "archive"; "arrow-down"; "arrow-right"; "arrow-up"; "check"; "check-circle"; "chevron-down"; "chevron-left"; "chevron-right"; "chevron-up"; "circle-dot"; "clock"; "copy"; "download"; "edit"; "ellipsis"; "external-link"; "eye"; "file-text"; "folder"; "folder-open"; "git-branch"; "git-merge"; "git-pull-request"; "info"; "menu"; "mic"; "moon"; "music"; "panel-left"; "panel-right"; "pause"; "play"; "plus"; "refresh-cw"; "repeat"; "save"; "search"; "send"; "settings"; "shuffle"; "skip-back"; "skip-forward"; "sun"; "terminal"; "trash"; "volume"; "wrench"; "x"; "x-circle"]
let view_icon_placement = ViewEnum ["leading"; "trailing"; "top"]
let view_input_kind = ViewEnum ["text"; "color"; "time"]
let view_list_style = ViewEnum ["plain"; "inset"; "inset-grouped"]
let view_scroll_anchor = ViewEnum ["top"; "center"; "bottom"; "nearest"]
let view_list_marker = ViewEnum ["none"; "disc"; "decimal"]
let view_anchor = ViewEnum ["above"; "below"; "left"; "right"]
let view_anchor_alignment = ViewEnum ["start"; "center"; "end"; "stretch"]
let view_role = ViewEnum ["treeitem"; "navigation"; "navigation-heading"]
let view_separator_visibility = ViewEnum ["visible"; "hidden"]
let view_image_loading = ViewEnum ["eager"; "lazy"]
let view_referrer_policy = ViewEnum ["no-referrer"; "origin"; "strict-origin-when-cross-origin"; "unsafe-url"]
let view_cell_size = ViewEnum ["default"; "sm"; "lg"; "icon"; "heading"; "display"]
let view_resize_easing = ViewEnum ["linear"; "standard"; "emphasized"; "spring"]
let view_swipe_edge = ViewEnum ["leading"; "trailing"]
let view_file_picker_source = ViewEnum ["files"; "photos"; "camera"]
let view_link_target = ViewEnum ["_self"; "_blank"]
let view_image_fit = ViewEnum ["fit"; "fill"]
let view_popover_role = ViewEnum ["dialog"; "menu"]

let view_contract = function
  | Root -> None
  | Row -> Some {
      view_result = "t";
      view_children = ViewList "t";
      view_properties = [(As, view_element_tag, false); (KeyValue, ViewString, false); (Gap, ViewInt, false); (MainAlignment, view_main_alignment, false); (CrossAlignment, view_cross_alignment, false); (GrowValue, ViewFloat, false); (GridColumns, ViewInt, false); (OrientationValue, view_orientation, false); (PaddingValue, ViewInt, false); (PaddingHorizontal, ViewInt, false); (PaddingVertical, ViewInt, false); (MarginValue, ViewInt, false); (MarginHorizontal, ViewInt, false); (MarginVertical, ViewInt, false); (MarginTop, ViewInt, false); (MarginRight, ViewInt, false); (MarginBottom, ViewInt, false); (MarginLeft, ViewInt, false); (BackgroundValue, ViewString, false); (ForegroundValue, ViewString, false); (BorderColorValue, ViewString, false); (BorderWidth, ViewInt, false); (CornerRadius, ViewInt, false); (WidthValue, ViewInt, false); (HeightValue, ViewInt, false); (MinWidth, ViewInt, false); (MaxWidth, ViewInt, false); (MinHeight, ViewInt, false); (MaxHeight, ViewInt, false); (ContainerRelativeFrameValue, view_frame_axes, false); (ContainerRelativeFrameInset, ViewInt, false); (AccessibilityIdentifier, ViewString, false); (StyleClass, ViewString, false); (DataAttrs, ViewAttributes, false); (Opacity, ViewFloat, false); (DisplayValue, view_display, false); (FlexWrap, view_flex_wrap, false); (Transition, ViewString, false); (AlignmentValue, view_alignment, false)];
      view_events = ["appear"; "pointer-enter"; "pointer-leave"];
      view_slots = [];
    }
  | Column -> Some {
      view_result = "t";
      view_children = ViewList "t";
      view_properties = [(As, view_element_tag, false); (KeyValue, ViewString, false); (Gap, ViewInt, false); (MainAlignment, view_main_alignment, false); (CrossAlignment, view_cross_alignment, false); (GrowValue, ViewFloat, false); (GridColumns, ViewInt, false); (PaddingValue, ViewInt, false); (PaddingHorizontal, ViewInt, false); (PaddingVertical, ViewInt, false); (MarginValue, ViewInt, false); (MarginHorizontal, ViewInt, false); (MarginVertical, ViewInt, false); (MarginTop, ViewInt, false); (MarginRight, ViewInt, false); (MarginBottom, ViewInt, false); (MarginLeft, ViewInt, false); (BackgroundValue, ViewString, false); (ForegroundValue, ViewString, false); (BorderColorValue, ViewString, false); (BorderWidth, ViewInt, false); (CornerRadius, ViewInt, false); (WidthValue, ViewInt, false); (HeightValue, ViewInt, false); (MinWidth, ViewInt, false); (MaxWidth, ViewInt, false); (MinHeight, ViewInt, false); (MaxHeight, ViewInt, false); (ContainerRelativeFrameValue, view_frame_axes, false); (ContainerRelativeFrameInset, ViewInt, false); (AccessibilityIdentifier, ViewString, false); (StyleClass, ViewString, false); (DataAttrs, ViewAttributes, false); (Opacity, ViewFloat, false); (DisplayValue, view_display, false); (FlexWrap, view_flex_wrap, false); (Transition, ViewString, false); (AlignmentValue, view_alignment, false)];
      view_events = ["appear"; "pointer-enter"; "pointer-leave"; "press-detail"; "pointer-down"; "pointer-up"];
      view_slots = [];
    }
  | Grid -> Some {
      view_result = "t";
      view_children = ViewList "t";
      view_properties = [(KeyValue, ViewString, false); (Gap, ViewInt, false); (MainAlignment, view_main_alignment, false); (CrossAlignment, view_cross_alignment, false); (GrowValue, ViewFloat, false); (GridColumns, ViewInt, false); (PaddingValue, ViewInt, false); (PaddingHorizontal, ViewInt, false); (PaddingVertical, ViewInt, false); (MarginValue, ViewInt, false); (MarginHorizontal, ViewInt, false); (MarginVertical, ViewInt, false); (MarginTop, ViewInt, false); (MarginRight, ViewInt, false); (MarginBottom, ViewInt, false); (MarginLeft, ViewInt, false); (BackgroundValue, ViewString, false); (ForegroundValue, ViewString, false); (BorderColorValue, ViewString, false); (BorderWidth, ViewInt, false); (CornerRadius, ViewInt, false); (WidthValue, ViewInt, false); (HeightValue, ViewInt, false); (MinWidth, ViewInt, false); (MaxWidth, ViewInt, false); (MinHeight, ViewInt, false); (MaxHeight, ViewInt, false); (ContainerRelativeFrameValue, view_frame_axes, false); (ContainerRelativeFrameInset, ViewInt, false); (AccessibilityIdentifier, ViewString, false); (StyleClass, ViewString, false); (DataAttrs, ViewAttributes, false); (Opacity, ViewFloat, false); (Transition, ViewString, false); (AlignmentValue, view_alignment, false)];
      view_events = ["appear"; "pointer-enter"; "pointer-leave"];
      view_slots = [];
    }
  | Stack -> Some {
      view_result = "t";
      view_children = ViewList "t";
      view_properties = [(KeyValue, ViewString, false); (Gap, ViewInt, false); (MainAlignment, view_main_alignment, false); (CrossAlignment, view_cross_alignment, false); (GrowValue, ViewFloat, false); (GridColumns, ViewInt, false); (PaddingValue, ViewInt, false); (PaddingHorizontal, ViewInt, false); (PaddingVertical, ViewInt, false); (MarginValue, ViewInt, false); (MarginHorizontal, ViewInt, false); (MarginVertical, ViewInt, false); (MarginTop, ViewInt, false); (MarginRight, ViewInt, false); (MarginBottom, ViewInt, false); (MarginLeft, ViewInt, false); (BackgroundValue, ViewString, false); (ForegroundValue, ViewString, false); (BorderColorValue, ViewString, false); (BorderWidth, ViewInt, false); (CornerRadius, ViewInt, false); (WidthValue, ViewInt, false); (HeightValue, ViewInt, false); (MinWidth, ViewInt, false); (MaxWidth, ViewInt, false); (MinHeight, ViewInt, false); (MaxHeight, ViewInt, false); (ContainerRelativeFrameValue, view_frame_axes, false); (ContainerRelativeFrameInset, ViewInt, false); (AccessibilityIdentifier, ViewString, false); (StyleClass, ViewString, false); (DataAttrs, ViewAttributes, false); (Opacity, ViewFloat, false); (Transition, ViewString, false); (AlignmentValue, view_alignment, false)];
      view_events = ["appear"; "pointer-enter"; "pointer-leave"];
      view_slots = [];
    }
  | EdgeInset -> Some {
      view_result = "t";
      view_children = ViewList "t";
      view_properties = [(KeyValue, ViewString, false); (Gap, ViewInt, false); (MainAlignment, view_main_alignment, false); (CrossAlignment, view_cross_alignment, false); (GrowValue, ViewFloat, false); (GridColumns, ViewInt, false); (PaddingValue, ViewInt, false); (PaddingHorizontal, ViewInt, false); (PaddingVertical, ViewInt, false); (MarginValue, ViewInt, false); (MarginHorizontal, ViewInt, false); (MarginVertical, ViewInt, false); (MarginTop, ViewInt, false); (MarginRight, ViewInt, false); (MarginBottom, ViewInt, false); (MarginLeft, ViewInt, false); (BackgroundValue, ViewString, false); (ForegroundValue, ViewString, false); (BorderColorValue, ViewString, false); (BorderWidth, ViewInt, false); (CornerRadius, ViewInt, false); (WidthValue, ViewInt, false); (HeightValue, ViewInt, false); (MinWidth, ViewInt, false); (MaxWidth, ViewInt, false); (MinHeight, ViewInt, false); (MaxHeight, ViewInt, false); (ContainerRelativeFrameValue, view_frame_axes, false); (ContainerRelativeFrameInset, ViewInt, false); (AccessibilityIdentifier, ViewString, false); (StyleClass, ViewString, false); (DataAttrs, ViewAttributes, false); (EdgeValue, view_edge, true); (Visible, ViewBool, false); (Opacity, ViewFloat, false); (Transition, ViewString, false); (AlignmentValue, view_alignment, false)];
      view_events = ["appear"; "pointer-enter"; "pointer-leave"];
      view_slots = [];
    }
  | Overlay -> Some {
      view_result = "t";
      view_children = ViewList "t";
      view_properties = [(KeyValue, ViewString, false); (Gap, ViewInt, false); (MainAlignment, view_main_alignment, false); (CrossAlignment, view_cross_alignment, false); (GrowValue, ViewFloat, false); (GridColumns, ViewInt, false); (PaddingValue, ViewInt, false); (PaddingHorizontal, ViewInt, false); (PaddingVertical, ViewInt, false); (MarginValue, ViewInt, false); (MarginHorizontal, ViewInt, false); (MarginVertical, ViewInt, false); (MarginTop, ViewInt, false); (MarginRight, ViewInt, false); (MarginBottom, ViewInt, false); (MarginLeft, ViewInt, false); (BackgroundValue, ViewString, false); (ForegroundValue, ViewString, false); (BorderColorValue, ViewString, false); (BorderWidth, ViewInt, false); (CornerRadius, ViewInt, false); (WidthValue, ViewInt, false); (HeightValue, ViewInt, false); (MinWidth, ViewInt, false); (MaxWidth, ViewInt, false); (MinHeight, ViewInt, false); (MaxHeight, ViewInt, false); (ContainerRelativeFrameValue, view_frame_axes, false); (ContainerRelativeFrameInset, ViewInt, false); (AccessibilityIdentifier, ViewString, false); (StyleClass, ViewString, false); (DataAttrs, ViewAttributes, false); (AlignmentValue, view_alignment, false); (Opacity, ViewFloat, false); (Transition, ViewString, false)];
      view_events = ["appear"; "pointer-enter"; "pointer-leave"];
      view_slots = [];
    }
  | ViewThatFits -> Some {
      view_result = "t";
      view_children = ViewList "t";
      view_properties = [(KeyValue, ViewString, false); (Gap, ViewInt, false); (MainAlignment, view_main_alignment, false); (CrossAlignment, view_cross_alignment, false); (GrowValue, ViewFloat, false); (GridColumns, ViewInt, false); (PaddingValue, ViewInt, false); (PaddingHorizontal, ViewInt, false); (PaddingVertical, ViewInt, false); (MarginValue, ViewInt, false); (MarginHorizontal, ViewInt, false); (MarginVertical, ViewInt, false); (MarginTop, ViewInt, false); (MarginRight, ViewInt, false); (MarginBottom, ViewInt, false); (MarginLeft, ViewInt, false); (BackgroundValue, ViewString, false); (ForegroundValue, ViewString, false); (BorderColorValue, ViewString, false); (BorderWidth, ViewInt, false); (CornerRadius, ViewInt, false); (WidthValue, ViewInt, false); (HeightValue, ViewInt, false); (MinWidth, ViewInt, false); (MaxWidth, ViewInt, false); (MinHeight, ViewInt, false); (MaxHeight, ViewInt, false); (ContainerRelativeFrameValue, view_frame_axes, false); (ContainerRelativeFrameInset, ViewInt, false); (AccessibilityIdentifier, ViewString, false); (StyleClass, ViewString, false); (DataAttrs, ViewAttributes, false); (OrientationValue, view_orientation, false); (Opacity, ViewFloat, false); (Transition, ViewString, false); (AlignmentValue, view_alignment, false)];
      view_events = ["appear"; "pointer-enter"; "pointer-leave"];
      view_slots = [];
    }
  | Panel -> Some {
      view_result = "t";
      view_children = ViewList "t";
      view_properties = [(KeyValue, ViewString, false); (Gap, ViewInt, false); (MainAlignment, view_main_alignment, false); (CrossAlignment, view_cross_alignment, false); (GrowValue, ViewFloat, false); (GridColumns, ViewInt, false); (PaddingValue, ViewInt, false); (PaddingHorizontal, ViewInt, false); (PaddingVertical, ViewInt, false); (MarginValue, ViewInt, false); (MarginHorizontal, ViewInt, false); (MarginVertical, ViewInt, false); (MarginTop, ViewInt, false); (MarginRight, ViewInt, false); (MarginBottom, ViewInt, false); (MarginLeft, ViewInt, false); (BackgroundValue, ViewString, false); (ForegroundValue, ViewString, false); (BorderColorValue, ViewString, false); (BorderWidth, ViewInt, false); (CornerRadius, ViewInt, false); (WidthValue, ViewInt, false); (HeightValue, ViewInt, false); (MinWidth, ViewInt, false); (MaxWidth, ViewInt, false); (MinHeight, ViewInt, false); (MaxHeight, ViewInt, false); (ContainerRelativeFrameValue, view_frame_axes, false); (ContainerRelativeFrameInset, ViewInt, false); (AccessibilityIdentifier, ViewString, false); (StyleClass, ViewString, false); (DataAttrs, ViewAttributes, false); (Opacity, ViewFloat, false); (Transition, ViewString, false); (AlignmentValue, view_alignment, false)];
      view_events = ["appear"; "pointer-enter"; "pointer-leave"];
      view_slots = [];
    }
  | Card -> Some {
      view_result = "t";
      view_children = ViewList "t";
      view_properties = [(KeyValue, ViewString, false); (Gap, ViewInt, false); (MainAlignment, view_main_alignment, false); (CrossAlignment, view_cross_alignment, false); (GrowValue, ViewFloat, false); (GridColumns, ViewInt, false); (PaddingValue, ViewInt, false); (PaddingHorizontal, ViewInt, false); (PaddingVertical, ViewInt, false); (MarginValue, ViewInt, false); (MarginHorizontal, ViewInt, false); (MarginVertical, ViewInt, false); (MarginTop, ViewInt, false); (MarginRight, ViewInt, false); (MarginBottom, ViewInt, false); (MarginLeft, ViewInt, false); (BackgroundValue, ViewString, false); (ForegroundValue, ViewString, false); (BorderColorValue, ViewString, false); (BorderWidth, ViewInt, false); (CornerRadius, ViewInt, false); (WidthValue, ViewInt, false); (HeightValue, ViewInt, false); (MinWidth, ViewInt, false); (MaxWidth, ViewInt, false); (MinHeight, ViewInt, false); (MaxHeight, ViewInt, false); (ContainerRelativeFrameValue, view_frame_axes, false); (ContainerRelativeFrameInset, ViewInt, false); (AccessibilityIdentifier, ViewString, false); (StyleClass, ViewString, false); (DataAttrs, ViewAttributes, false); (Opacity, ViewFloat, false); (Transition, ViewString, false); (AlignmentValue, view_alignment, false)];
      view_events = ["appear"; "pointer-enter"; "pointer-leave"];
      view_slots = [];
    }
  | Alert -> Some {
      view_result = "t";
      view_children = ViewList "t";
      view_properties = [(KeyValue, ViewString, false); (Gap, ViewInt, false); (MainAlignment, view_main_alignment, false); (CrossAlignment, view_cross_alignment, false); (GrowValue, ViewFloat, false); (GridColumns, ViewInt, false); (PaddingValue, ViewInt, false); (PaddingHorizontal, ViewInt, false); (PaddingVertical, ViewInt, false); (MarginValue, ViewInt, false); (MarginHorizontal, ViewInt, false); (MarginVertical, ViewInt, false); (MarginTop, ViewInt, false); (MarginRight, ViewInt, false); (MarginBottom, ViewInt, false); (MarginLeft, ViewInt, false); (BackgroundValue, ViewString, false); (ForegroundValue, ViewString, false); (BorderColorValue, ViewString, false); (BorderWidth, ViewInt, false); (CornerRadius, ViewInt, false); (WidthValue, ViewInt, false); (HeightValue, ViewInt, false); (MinWidth, ViewInt, false); (MaxWidth, ViewInt, false); (MinHeight, ViewInt, false); (MaxHeight, ViewInt, false); (ContainerRelativeFrameValue, view_frame_axes, false); (ContainerRelativeFrameInset, ViewInt, false); (AccessibilityIdentifier, ViewString, false); (StyleClass, ViewString, false); (DataAttrs, ViewAttributes, false); (TextValue, ViewString, false); (VariantValue, view_variant, false); (TextAlignment, view_text_alignment, false); (AccessibilityLabel, ViewString, false); (Opacity, ViewFloat, false); (Transition, ViewString, false); (AlignmentValue, view_alignment, false)];
      view_events = ["appear"; "pointer-enter"; "pointer-leave"];
      view_slots = [];
    }
  | Bubble -> Some {
      view_result = "t";
      view_children = ViewList "t";
      view_properties = [(KeyValue, ViewString, false); (Gap, ViewInt, false); (MainAlignment, view_main_alignment, false); (CrossAlignment, view_cross_alignment, false); (GrowValue, ViewFloat, false); (GridColumns, ViewInt, false); (PaddingValue, ViewInt, false); (PaddingHorizontal, ViewInt, false); (PaddingVertical, ViewInt, false); (MarginValue, ViewInt, false); (MarginHorizontal, ViewInt, false); (MarginVertical, ViewInt, false); (MarginTop, ViewInt, false); (MarginRight, ViewInt, false); (MarginBottom, ViewInt, false); (MarginLeft, ViewInt, false); (BackgroundValue, ViewString, false); (ForegroundValue, ViewString, false); (BorderColorValue, ViewString, false); (BorderWidth, ViewInt, false); (CornerRadius, ViewInt, false); (WidthValue, ViewInt, false); (HeightValue, ViewInt, false); (MinWidth, ViewInt, false); (MaxWidth, ViewInt, false); (MinHeight, ViewInt, false); (MaxHeight, ViewInt, false); (ContainerRelativeFrameValue, view_frame_axes, false); (ContainerRelativeFrameInset, ViewInt, false); (AccessibilityIdentifier, ViewString, false); (StyleClass, ViewString, false); (DataAttrs, ViewAttributes, false); (TextValue, ViewString, false); (VariantValue, view_variant, false); (AccessibilityLabel, ViewString, false); (Opacity, ViewFloat, false); (Transition, ViewString, false); (AlignmentValue, view_alignment, false)];
      view_events = ["appear"; "pointer-enter"; "pointer-leave"];
      view_slots = [];
    }
  | Box -> Some {
      view_result = "t";
      view_children = ViewList "t";
      view_properties = [(KeyValue, ViewString, false); (Gap, ViewInt, false); (MainAlignment, view_main_alignment, false); (CrossAlignment, view_cross_alignment, false); (GrowValue, ViewFloat, false); (GridColumns, ViewInt, false); (PaddingValue, ViewInt, false); (PaddingHorizontal, ViewInt, false); (PaddingVertical, ViewInt, false); (MarginValue, ViewInt, false); (MarginHorizontal, ViewInt, false); (MarginVertical, ViewInt, false); (MarginTop, ViewInt, false); (MarginRight, ViewInt, false); (MarginBottom, ViewInt, false); (MarginLeft, ViewInt, false); (BackgroundValue, ViewString, false); (ForegroundValue, ViewString, false); (BorderColorValue, ViewString, false); (BorderWidth, ViewInt, false); (CornerRadius, ViewInt, false); (WidthValue, ViewInt, false); (HeightValue, ViewInt, false); (MinWidth, ViewInt, false); (MaxWidth, ViewInt, false); (MinHeight, ViewInt, false); (MaxHeight, ViewInt, false); (ContainerRelativeFrameValue, view_frame_axes, false); (ContainerRelativeFrameInset, ViewInt, false); (AccessibilityIdentifier, ViewString, false); (StyleClass, ViewString, false); (DataAttrs, ViewAttributes, false); (Opacity, ViewFloat, false); (DisplayValue, view_display, false); (FlexWrap, view_flex_wrap, false); (Inert, ViewBool, false); (Transition, ViewString, false); (AlignmentValue, view_alignment, false)];
      view_events = ["appear"; "pointer-enter"; "pointer-leave"];
      view_slots = [];
    }
  | Text -> Some {
      view_result = "t";
      view_children = ViewList "t";
      view_properties = [(KeyValue, ViewString, false); (Gap, ViewInt, false); (MainAlignment, view_main_alignment, false); (CrossAlignment, view_cross_alignment, false); (GrowValue, ViewFloat, false); (GridColumns, ViewInt, false); (PaddingValue, ViewInt, false); (PaddingHorizontal, ViewInt, false); (PaddingVertical, ViewInt, false); (MarginValue, ViewInt, false); (MarginHorizontal, ViewInt, false); (MarginVertical, ViewInt, false); (MarginTop, ViewInt, false); (MarginRight, ViewInt, false); (MarginBottom, ViewInt, false); (MarginLeft, ViewInt, false); (BackgroundValue, ViewString, false); (ForegroundValue, ViewString, false); (BorderColorValue, ViewString, false); (BorderWidth, ViewInt, false); (CornerRadius, ViewInt, false); (WidthValue, ViewInt, false); (HeightValue, ViewInt, false); (MinWidth, ViewInt, false); (MaxWidth, ViewInt, false); (MinHeight, ViewInt, false); (MaxHeight, ViewInt, false); (ContainerRelativeFrameValue, view_frame_axes, false); (ContainerRelativeFrameInset, ViewInt, false); (AccessibilityIdentifier, ViewString, false); (StyleClass, ViewString, false); (DataAttrs, ViewAttributes, false); (As, view_element_tag, false); (TextValue, ViewString, false); (TextAlignment, view_text_alignment, false); (FontSize, ViewString, false); (FontWeight, ViewInt, false); (LineHeight, ViewString, false); (LetterSpacing, ViewFloat, false); (FontFamily, ViewString, false); (FontStyle, ViewString, false); (TextDecoration, ViewString, false); (WhiteSpace, ViewString, false); (LineClamp, ViewInt, false); (TextOverflow, ViewString, false); (Overflow, ViewString, false); (Transition, ViewString, false); (AlignmentValue, view_alignment, false)];
      view_events = ["appear"; "pointer-enter"; "pointer-leave"; "press"; "press-modifiers"; "press-detail"; "pointer-down"; "pointer-up"; "context-menu"];
      view_slots = [];
    }
  | Heading -> Some {
      view_result = "t";
      view_children = ViewList "t";
      view_properties = [(KeyValue, ViewString, false); (Gap, ViewInt, false); (MainAlignment, view_main_alignment, false); (CrossAlignment, view_cross_alignment, false); (GrowValue, ViewFloat, false); (GridColumns, ViewInt, false); (PaddingValue, ViewInt, false); (PaddingHorizontal, ViewInt, false); (PaddingVertical, ViewInt, false); (MarginValue, ViewInt, false); (MarginHorizontal, ViewInt, false); (MarginVertical, ViewInt, false); (MarginTop, ViewInt, false); (MarginRight, ViewInt, false); (MarginBottom, ViewInt, false); (MarginLeft, ViewInt, false); (BackgroundValue, ViewString, false); (ForegroundValue, ViewString, false); (BorderColorValue, ViewString, false); (BorderWidth, ViewInt, false); (CornerRadius, ViewInt, false); (WidthValue, ViewInt, false); (HeightValue, ViewInt, false); (MinWidth, ViewInt, false); (MaxWidth, ViewInt, false); (MinHeight, ViewInt, false); (MaxHeight, ViewInt, false); (ContainerRelativeFrameValue, view_frame_axes, false); (ContainerRelativeFrameInset, ViewInt, false); (AccessibilityIdentifier, ViewString, false); (StyleClass, ViewString, false); (DataAttrs, ViewAttributes, false); (As, view_element_tag, false); (HeadingLevel, ViewInt, false); (TextValue, ViewString, false); (TextAlignment, view_text_alignment, false); (FontSize, ViewString, false); (FontWeight, ViewInt, false); (LineHeight, ViewString, false); (LetterSpacing, ViewFloat, false); (FontFamily, ViewString, false); (FontStyle, ViewString, false); (TextDecoration, ViewString, false); (WhiteSpace, ViewString, false); (LineClamp, ViewInt, false); (TextOverflow, ViewString, false); (Overflow, ViewString, false); (Transition, ViewString, false); (AlignmentValue, view_alignment, false)];
      view_events = ["appear"; "pointer-enter"; "pointer-leave"];
      view_slots = [];
    }
  | Paragraph -> Some {
      view_result = "t";
      view_children = ViewList "t";
      view_properties = [(KeyValue, ViewString, false); (Gap, ViewInt, false); (MainAlignment, view_main_alignment, false); (CrossAlignment, view_cross_alignment, false); (GrowValue, ViewFloat, false); (GridColumns, ViewInt, false); (PaddingValue, ViewInt, false); (PaddingHorizontal, ViewInt, false); (PaddingVertical, ViewInt, false); (MarginValue, ViewInt, false); (MarginHorizontal, ViewInt, false); (MarginVertical, ViewInt, false); (MarginTop, ViewInt, false); (MarginRight, ViewInt, false); (MarginBottom, ViewInt, false); (MarginLeft, ViewInt, false); (BackgroundValue, ViewString, false); (ForegroundValue, ViewString, false); (BorderColorValue, ViewString, false); (BorderWidth, ViewInt, false); (CornerRadius, ViewInt, false); (WidthValue, ViewInt, false); (HeightValue, ViewInt, false); (MinWidth, ViewInt, false); (MaxWidth, ViewInt, false); (MinHeight, ViewInt, false); (MaxHeight, ViewInt, false); (ContainerRelativeFrameValue, view_frame_axes, false); (ContainerRelativeFrameInset, ViewInt, false); (AccessibilityIdentifier, ViewString, false); (StyleClass, ViewString, false); (DataAttrs, ViewAttributes, false); (As, view_element_tag, false); (TextValue, ViewString, false); (TextAlignment, view_text_alignment, false); (FontSize, ViewString, false); (FontWeight, ViewInt, false); (LineHeight, ViewString, false); (LetterSpacing, ViewFloat, false); (FontFamily, ViewString, false); (FontStyle, ViewString, false); (TextDecoration, ViewString, false); (WhiteSpace, ViewString, false); (LineClamp, ViewInt, false); (TextOverflow, ViewString, false); (Overflow, ViewString, false); (Transition, ViewString, false); (AlignmentValue, view_alignment, false)];
      view_events = ["appear"; "pointer-enter"; "pointer-leave"];
      view_slots = [];
    }
  | Label -> Some {
      view_result = "t";
      view_children = ViewList "t";
      view_properties = [(KeyValue, ViewString, false); (Gap, ViewInt, false); (MainAlignment, view_main_alignment, false); (CrossAlignment, view_cross_alignment, false); (GrowValue, ViewFloat, false); (GridColumns, ViewInt, false); (PaddingValue, ViewInt, false); (PaddingHorizontal, ViewInt, false); (PaddingVertical, ViewInt, false); (MarginValue, ViewInt, false); (MarginHorizontal, ViewInt, false); (MarginVertical, ViewInt, false); (MarginTop, ViewInt, false); (MarginRight, ViewInt, false); (MarginBottom, ViewInt, false); (MarginLeft, ViewInt, false); (BackgroundValue, ViewString, false); (ForegroundValue, ViewString, false); (BorderColorValue, ViewString, false); (BorderWidth, ViewInt, false); (CornerRadius, ViewInt, false); (WidthValue, ViewInt, false); (HeightValue, ViewInt, false); (MinWidth, ViewInt, false); (MaxWidth, ViewInt, false); (MinHeight, ViewInt, false); (MaxHeight, ViewInt, false); (ContainerRelativeFrameValue, view_frame_axes, false); (ContainerRelativeFrameInset, ViewInt, false); (AccessibilityIdentifier, ViewString, false); (StyleClass, ViewString, false); (DataAttrs, ViewAttributes, false); (As, view_element_tag, false); (TextValue, ViewString, false); (FontSize, ViewString, false); (FontWeight, ViewInt, false); (LineHeight, ViewString, false); (LetterSpacing, ViewFloat, false); (FontFamily, ViewString, false); (FontStyle, ViewString, false); (TextDecoration, ViewString, false); (WhiteSpace, ViewString, false); (LineClamp, ViewInt, false); (TextOverflow, ViewString, false); (Overflow, ViewString, false); (Transition, ViewString, false); (AlignmentValue, view_alignment, false)];
      view_events = ["appear"; "pointer-enter"; "pointer-leave"];
      view_slots = [];
    }
  | Button -> Some {
      view_result = "t";
      view_children = ViewList "t";
      view_properties = [(KeyValue, ViewString, false); (Gap, ViewInt, false); (MainAlignment, view_main_alignment, false); (CrossAlignment, view_cross_alignment, false); (GrowValue, ViewFloat, false); (GridColumns, ViewInt, false); (PaddingValue, ViewInt, false); (PaddingHorizontal, ViewInt, false); (PaddingVertical, ViewInt, false); (MarginValue, ViewInt, false); (MarginHorizontal, ViewInt, false); (MarginVertical, ViewInt, false); (MarginTop, ViewInt, false); (MarginRight, ViewInt, false); (MarginBottom, ViewInt, false); (MarginLeft, ViewInt, false); (BackgroundValue, ViewString, false); (ForegroundValue, ViewString, false); (BorderColorValue, ViewString, false); (BorderWidth, ViewInt, false); (CornerRadius, ViewInt, false); (WidthValue, ViewInt, false); (HeightValue, ViewInt, false); (MinWidth, ViewInt, false); (MaxWidth, ViewInt, false); (MinHeight, ViewInt, false); (MaxHeight, ViewInt, false); (ContainerRelativeFrameValue, view_frame_axes, false); (ContainerRelativeFrameInset, ViewInt, false); (AccessibilityIdentifier, ViewString, false); (StyleClass, ViewString, false); (DataAttrs, ViewAttributes, false); (TextValue, ViewString, false); (VariantValue, view_variant, false); (SizeValue, view_control_size, false); (InlineIconName, view_icon, false); (IconPlacementValue, view_icon_placement, false); (AccessibilityLabel, ViewString, false); (TextAlignment, view_text_alignment, false); (Selected, ViewBool, false); (Autofocus, ViewBool, false); (Enabled, ViewBool, false); (TooltipText, ViewString, false); (TooltipKeys, ViewString, false); (Transition, ViewString, false); (AlignmentValue, view_alignment, false)];
      view_events = ["appear"; "pointer-enter"; "pointer-leave"; "navigate-previous"; "navigate-next"; "navigation-key"; "press"; "press-modifiers"; "long-press"; "press-detail"; "pointer-down"; "pointer-up"; "context-menu"];
      view_slots = [];
    }
  | ToggleButton -> Some {
      view_result = "t";
      view_children = ViewList "t";
      view_properties = [(KeyValue, ViewString, false); (Gap, ViewInt, false); (MainAlignment, view_main_alignment, false); (CrossAlignment, view_cross_alignment, false); (GrowValue, ViewFloat, false); (GridColumns, ViewInt, false); (PaddingValue, ViewInt, false); (PaddingHorizontal, ViewInt, false); (PaddingVertical, ViewInt, false); (MarginValue, ViewInt, false); (MarginHorizontal, ViewInt, false); (MarginVertical, ViewInt, false); (MarginTop, ViewInt, false); (MarginRight, ViewInt, false); (MarginBottom, ViewInt, false); (MarginLeft, ViewInt, false); (BackgroundValue, ViewString, false); (ForegroundValue, ViewString, false); (BorderColorValue, ViewString, false); (BorderWidth, ViewInt, false); (CornerRadius, ViewInt, false); (WidthValue, ViewInt, false); (HeightValue, ViewInt, false); (MinWidth, ViewInt, false); (MaxWidth, ViewInt, false); (MinHeight, ViewInt, false); (MaxHeight, ViewInt, false); (ContainerRelativeFrameValue, view_frame_axes, false); (ContainerRelativeFrameInset, ViewInt, false); (AccessibilityIdentifier, ViewString, false); (StyleClass, ViewString, false); (DataAttrs, ViewAttributes, false); (TextValue, ViewString, false); (VariantValue, view_variant, false); (SizeValue, view_control_size, false); (InlineIconName, view_icon, false); (IconPlacementValue, view_icon_placement, false); (AccessibilityLabel, ViewString, false); (TextAlignment, view_text_alignment, false); (Selected, ViewBool, false); (Checked, ViewBool, false); (Autofocus, ViewBool, false); (Enabled, ViewBool, false); (Transition, ViewString, false); (AlignmentValue, view_alignment, false)];
      view_events = ["appear"; "pointer-enter"; "pointer-leave"; "press"; "press-modifiers"; "toggle"; "long-press"; "context-menu"];
      view_slots = [];
    }
  | Toggle -> Some {
      view_result = "t";
      view_children = ViewList "t";
      view_properties = [(KeyValue, ViewString, false); (Gap, ViewInt, false); (MainAlignment, view_main_alignment, false); (CrossAlignment, view_cross_alignment, false); (GrowValue, ViewFloat, false); (GridColumns, ViewInt, false); (PaddingValue, ViewInt, false); (PaddingHorizontal, ViewInt, false); (PaddingVertical, ViewInt, false); (MarginValue, ViewInt, false); (MarginHorizontal, ViewInt, false); (MarginVertical, ViewInt, false); (MarginTop, ViewInt, false); (MarginRight, ViewInt, false); (MarginBottom, ViewInt, false); (MarginLeft, ViewInt, false); (BackgroundValue, ViewString, false); (ForegroundValue, ViewString, false); (BorderColorValue, ViewString, false); (BorderWidth, ViewInt, false); (CornerRadius, ViewInt, false); (WidthValue, ViewInt, false); (HeightValue, ViewInt, false); (MinWidth, ViewInt, false); (MaxWidth, ViewInt, false); (MinHeight, ViewInt, false); (MaxHeight, ViewInt, false); (ContainerRelativeFrameValue, view_frame_axes, false); (ContainerRelativeFrameInset, ViewInt, false); (AccessibilityIdentifier, ViewString, false); (StyleClass, ViewString, false); (DataAttrs, ViewAttributes, false); (TextValue, ViewString, false); (Checked, ViewBool, false); (AccessibilityLabel, ViewString, false); (Enabled, ViewBool, false); (Transition, ViewString, false); (AlignmentValue, view_alignment, false)];
      view_events = ["appear"; "pointer-enter"; "pointer-leave"; "toggle"; "context-menu"];
      view_slots = [];
    }
  | RadioGroup -> Some {
      view_result = "t";
      view_children = ViewList "radio_el";
      view_properties = [(KeyValue, ViewString, false); (Gap, ViewInt, false); (MainAlignment, view_main_alignment, false); (CrossAlignment, view_cross_alignment, false); (GrowValue, ViewFloat, false); (GridColumns, ViewInt, false); (PaddingValue, ViewInt, false); (PaddingHorizontal, ViewInt, false); (PaddingVertical, ViewInt, false); (MarginValue, ViewInt, false); (MarginHorizontal, ViewInt, false); (MarginVertical, ViewInt, false); (MarginTop, ViewInt, false); (MarginRight, ViewInt, false); (MarginBottom, ViewInt, false); (MarginLeft, ViewInt, false); (BackgroundValue, ViewString, false); (ForegroundValue, ViewString, false); (BorderColorValue, ViewString, false); (BorderWidth, ViewInt, false); (CornerRadius, ViewInt, false); (WidthValue, ViewInt, false); (HeightValue, ViewInt, false); (MinWidth, ViewInt, false); (MaxWidth, ViewInt, false); (MinHeight, ViewInt, false); (MaxHeight, ViewInt, false); (ContainerRelativeFrameValue, view_frame_axes, false); (ContainerRelativeFrameInset, ViewInt, false); (AccessibilityIdentifier, ViewString, false); (StyleClass, ViewString, false); (DataAttrs, ViewAttributes, false); (AccessibilityLabel, ViewString, false); (Transition, ViewString, false); (AlignmentValue, view_alignment, false)];
      view_events = ["appear"; "pointer-enter"; "pointer-leave"];
      view_slots = [];
    }
  | Radio -> Some {
      view_result = "radio_el";
      view_children = ViewList "t";
      view_properties = [(KeyValue, ViewString, false); (Gap, ViewInt, false); (MainAlignment, view_main_alignment, false); (CrossAlignment, view_cross_alignment, false); (GrowValue, ViewFloat, false); (GridColumns, ViewInt, false); (PaddingValue, ViewInt, false); (PaddingHorizontal, ViewInt, false); (PaddingVertical, ViewInt, false); (MarginValue, ViewInt, false); (MarginHorizontal, ViewInt, false); (MarginVertical, ViewInt, false); (MarginTop, ViewInt, false); (MarginRight, ViewInt, false); (MarginBottom, ViewInt, false); (MarginLeft, ViewInt, false); (BackgroundValue, ViewString, false); (ForegroundValue, ViewString, false); (BorderColorValue, ViewString, false); (BorderWidth, ViewInt, false); (CornerRadius, ViewInt, false); (WidthValue, ViewInt, false); (HeightValue, ViewInt, false); (MinWidth, ViewInt, false); (MaxWidth, ViewInt, false); (MinHeight, ViewInt, false); (MaxHeight, ViewInt, false); (ContainerRelativeFrameValue, view_frame_axes, false); (ContainerRelativeFrameInset, ViewInt, false); (AccessibilityIdentifier, ViewString, false); (StyleClass, ViewString, false); (DataAttrs, ViewAttributes, false); (TextValue, ViewString, false); (Checked, ViewBool, false); (Selected, ViewBool, false); (AccessibilityLabel, ViewString, false); (Enabled, ViewBool, false); (Transition, ViewString, false)];
      view_events = ["appear"; "pointer-enter"; "pointer-leave"; "change"; "toggle"; "press"; "press-modifiers"; "press-detail"; "pointer-down"; "pointer-up"; "context-menu"];
      view_slots = [];
    }
  | Slider -> Some {
      view_result = "t";
      view_children = ViewList "t";
      view_properties = [(KeyValue, ViewString, false); (Gap, ViewInt, false); (MainAlignment, view_main_alignment, false); (CrossAlignment, view_cross_alignment, false); (GrowValue, ViewFloat, false); (GridColumns, ViewInt, false); (PaddingValue, ViewInt, false); (PaddingHorizontal, ViewInt, false); (PaddingVertical, ViewInt, false); (MarginValue, ViewInt, false); (MarginHorizontal, ViewInt, false); (MarginVertical, ViewInt, false); (MarginTop, ViewInt, false); (MarginRight, ViewInt, false); (MarginBottom, ViewInt, false); (MarginLeft, ViewInt, false); (BackgroundValue, ViewString, false); (ForegroundValue, ViewString, false); (BorderColorValue, ViewString, false); (BorderWidth, ViewInt, false); (CornerRadius, ViewInt, false); (WidthValue, ViewInt, false); (HeightValue, ViewInt, false); (MinWidth, ViewInt, false); (MaxWidth, ViewInt, false); (MinHeight, ViewInt, false); (MaxHeight, ViewInt, false); (ContainerRelativeFrameValue, view_frame_axes, false); (ContainerRelativeFrameInset, ViewInt, false); (AccessibilityIdentifier, ViewString, false); (StyleClass, ViewString, false); (DataAttrs, ViewAttributes, false); (ProgressValue, ViewFloat, false); (AccessibilityLabel, ViewString, false); (Enabled, ViewBool, false); (Transition, ViewString, false); (AlignmentValue, view_alignment, false)];
      view_events = ["appear"; "pointer-enter"; "pointer-leave"; "change"; "context-menu"];
      view_slots = [];
    }
  | NumberStepper -> Some {
      view_result = "t";
      view_children = ViewList "t";
      view_properties = [(KeyValue, ViewString, false); (Gap, ViewInt, false); (MainAlignment, view_main_alignment, false); (CrossAlignment, view_cross_alignment, false); (GrowValue, ViewFloat, false); (GridColumns, ViewInt, false); (PaddingValue, ViewInt, false); (PaddingHorizontal, ViewInt, false); (PaddingVertical, ViewInt, false); (MarginValue, ViewInt, false); (MarginHorizontal, ViewInt, false); (MarginVertical, ViewInt, false); (MarginTop, ViewInt, false); (MarginRight, ViewInt, false); (MarginBottom, ViewInt, false); (MarginLeft, ViewInt, false); (BackgroundValue, ViewString, false); (ForegroundValue, ViewString, false); (BorderColorValue, ViewString, false); (BorderWidth, ViewInt, false); (CornerRadius, ViewInt, false); (WidthValue, ViewInt, false); (HeightValue, ViewInt, false); (MinWidth, ViewInt, false); (MaxWidth, ViewInt, false); (MinHeight, ViewInt, false); (MaxHeight, ViewInt, false); (ContainerRelativeFrameValue, view_frame_axes, false); (ContainerRelativeFrameInset, ViewInt, false); (AccessibilityIdentifier, ViewString, false); (StyleClass, ViewString, false); (DataAttrs, ViewAttributes, false); (ProgressValue, ViewFloat, false); (MinValue, ViewFloat, false); (MaxValue, ViewFloat, false); (StepValue, ViewFloat, false); (TextValue, ViewString, false); (AccessibilityLabel, ViewString, false); (Enabled, ViewBool, false); (Transition, ViewString, false); (AlignmentValue, view_alignment, false)];
      view_events = ["appear"; "pointer-enter"; "pointer-leave"; "value"; "context-menu"];
      view_slots = [];
    }
  | TextField -> Some {
      view_result = "t";
      view_children = ViewList "t";
      view_properties = [(KeyValue, ViewString, false); (Gap, ViewInt, false); (MainAlignment, view_main_alignment, false); (CrossAlignment, view_cross_alignment, false); (GrowValue, ViewFloat, false); (GridColumns, ViewInt, false); (PaddingValue, ViewInt, false); (PaddingHorizontal, ViewInt, false); (PaddingVertical, ViewInt, false); (MarginValue, ViewInt, false); (MarginHorizontal, ViewInt, false); (MarginVertical, ViewInt, false); (MarginTop, ViewInt, false); (MarginRight, ViewInt, false); (MarginBottom, ViewInt, false); (MarginLeft, ViewInt, false); (BackgroundValue, ViewString, false); (ForegroundValue, ViewString, false); (BorderColorValue, ViewString, false); (BorderWidth, ViewInt, false); (CornerRadius, ViewInt, false); (WidthValue, ViewInt, false); (HeightValue, ViewInt, false); (MinWidth, ViewInt, false); (MaxWidth, ViewInt, false); (MinHeight, ViewInt, false); (MaxHeight, ViewInt, false); (ContainerRelativeFrameValue, view_frame_axes, false); (ContainerRelativeFrameInset, ViewInt, false); (AccessibilityIdentifier, ViewString, false); (StyleClass, ViewString, false); (DataAttrs, ViewAttributes, false); (TextValue, ViewString, false); (PlaceholderValue, ViewString, false); (AccessibilityLabel, ViewString, false); (Autofocus, ViewBool, false); (SubmitOnEnter, ViewBool, false); (SubmitOnBlur, ViewBool, false); (ReadOnly, ViewBool, false); (Enabled, ViewBool, false); (Transition, ViewString, false); (AlignmentValue, view_alignment, false)];
      view_events = ["appear"; "pointer-enter"; "pointer-leave"; "input"; "submit"; "navigate-previous"; "navigate-next"; "navigation-key"; "context-menu"];
      view_slots = [];
    }
  | SecureField -> Some {
      view_result = "t";
      view_children = ViewList "t";
      view_properties = [(KeyValue, ViewString, false); (Gap, ViewInt, false); (MainAlignment, view_main_alignment, false); (CrossAlignment, view_cross_alignment, false); (GrowValue, ViewFloat, false); (GridColumns, ViewInt, false); (PaddingValue, ViewInt, false); (PaddingHorizontal, ViewInt, false); (PaddingVertical, ViewInt, false); (MarginValue, ViewInt, false); (MarginHorizontal, ViewInt, false); (MarginVertical, ViewInt, false); (MarginTop, ViewInt, false); (MarginRight, ViewInt, false); (MarginBottom, ViewInt, false); (MarginLeft, ViewInt, false); (BackgroundValue, ViewString, false); (ForegroundValue, ViewString, false); (BorderColorValue, ViewString, false); (BorderWidth, ViewInt, false); (CornerRadius, ViewInt, false); (WidthValue, ViewInt, false); (HeightValue, ViewInt, false); (MinWidth, ViewInt, false); (MaxWidth, ViewInt, false); (MinHeight, ViewInt, false); (MaxHeight, ViewInt, false); (ContainerRelativeFrameValue, view_frame_axes, false); (ContainerRelativeFrameInset, ViewInt, false); (AccessibilityIdentifier, ViewString, false); (StyleClass, ViewString, false); (DataAttrs, ViewAttributes, false); (TextValue, ViewString, false); (PlaceholderValue, ViewString, false); (AccessibilityLabel, ViewString, false); (Autofocus, ViewBool, false); (SubmitOnEnter, ViewBool, false); (SubmitOnBlur, ViewBool, false); (ReadOnly, ViewBool, false); (Enabled, ViewBool, false); (Transition, ViewString, false); (AlignmentValue, view_alignment, false)];
      view_events = ["appear"; "pointer-enter"; "pointer-leave"; "input"; "submit"; "navigate-previous"; "navigate-next"; "navigation-key"; "context-menu"];
      view_slots = [];
    }
  | Input -> Some {
      view_result = "t";
      view_children = ViewList "t";
      view_properties = [(KeyValue, ViewString, false); (Gap, ViewInt, false); (MainAlignment, view_main_alignment, false); (CrossAlignment, view_cross_alignment, false); (GrowValue, ViewFloat, false); (GridColumns, ViewInt, false); (PaddingValue, ViewInt, false); (PaddingHorizontal, ViewInt, false); (PaddingVertical, ViewInt, false); (MarginValue, ViewInt, false); (MarginHorizontal, ViewInt, false); (MarginVertical, ViewInt, false); (MarginTop, ViewInt, false); (MarginRight, ViewInt, false); (MarginBottom, ViewInt, false); (MarginLeft, ViewInt, false); (BackgroundValue, ViewString, false); (ForegroundValue, ViewString, false); (BorderColorValue, ViewString, false); (BorderWidth, ViewInt, false); (CornerRadius, ViewInt, false); (WidthValue, ViewInt, false); (HeightValue, ViewInt, false); (MinWidth, ViewInt, false); (MaxWidth, ViewInt, false); (MinHeight, ViewInt, false); (MaxHeight, ViewInt, false); (ContainerRelativeFrameValue, view_frame_axes, false); (ContainerRelativeFrameInset, ViewInt, false); (AccessibilityIdentifier, ViewString, false); (StyleClass, ViewString, false); (DataAttrs, ViewAttributes, false); (TextValue, ViewString, false); (PlaceholderValue, ViewString, false); (AccessibilityLabel, ViewString, false); (Autofocus, ViewBool, false); (SubmitOnEnter, ViewBool, false); (SubmitOnBlur, ViewBool, false); (ReadOnly, ViewBool, false); (Enabled, ViewBool, false); (InputType, view_input_kind, false); (Transition, ViewString, false); (AlignmentValue, view_alignment, false)];
      view_events = ["appear"; "pointer-enter"; "pointer-leave"; "input"; "submit"; "navigate-previous"; "navigate-next"; "navigation-key"; "context-menu"];
      view_slots = [];
    }
  | SearchField -> Some {
      view_result = "t";
      view_children = ViewList "t";
      view_properties = [(KeyValue, ViewString, false); (Gap, ViewInt, false); (MainAlignment, view_main_alignment, false); (CrossAlignment, view_cross_alignment, false); (GrowValue, ViewFloat, false); (GridColumns, ViewInt, false); (PaddingValue, ViewInt, false); (PaddingHorizontal, ViewInt, false); (PaddingVertical, ViewInt, false); (MarginValue, ViewInt, false); (MarginHorizontal, ViewInt, false); (MarginVertical, ViewInt, false); (MarginTop, ViewInt, false); (MarginRight, ViewInt, false); (MarginBottom, ViewInt, false); (MarginLeft, ViewInt, false); (BackgroundValue, ViewString, false); (ForegroundValue, ViewString, false); (BorderColorValue, ViewString, false); (BorderWidth, ViewInt, false); (CornerRadius, ViewInt, false); (WidthValue, ViewInt, false); (HeightValue, ViewInt, false); (MinWidth, ViewInt, false); (MaxWidth, ViewInt, false); (MinHeight, ViewInt, false); (MaxHeight, ViewInt, false); (ContainerRelativeFrameValue, view_frame_axes, false); (ContainerRelativeFrameInset, ViewInt, false); (AccessibilityIdentifier, ViewString, false); (StyleClass, ViewString, false); (DataAttrs, ViewAttributes, false); (TextValue, ViewString, false); (PlaceholderValue, ViewString, false); (AccessibilityLabel, ViewString, false); (Autofocus, ViewBool, false); (SubmitOnEnter, ViewBool, false); (SubmitOnBlur, ViewBool, false); (ReadOnly, ViewBool, false); (Enabled, ViewBool, false); (Transition, ViewString, false); (AlignmentValue, view_alignment, false)];
      view_events = ["appear"; "pointer-enter"; "pointer-leave"; "input"; "submit"; "navigate-previous"; "navigate-next"; "navigation-key"; "context-menu"];
      view_slots = [];
    }
  | Textarea -> Some {
      view_result = "t";
      view_children = ViewList "t";
      view_properties = [(KeyValue, ViewString, false); (Gap, ViewInt, false); (MainAlignment, view_main_alignment, false); (CrossAlignment, view_cross_alignment, false); (GrowValue, ViewFloat, false); (GridColumns, ViewInt, false); (PaddingValue, ViewInt, false); (PaddingHorizontal, ViewInt, false); (PaddingVertical, ViewInt, false); (MarginValue, ViewInt, false); (MarginHorizontal, ViewInt, false); (MarginVertical, ViewInt, false); (MarginTop, ViewInt, false); (MarginRight, ViewInt, false); (MarginBottom, ViewInt, false); (MarginLeft, ViewInt, false); (BackgroundValue, ViewString, false); (ForegroundValue, ViewString, false); (BorderColorValue, ViewString, false); (BorderWidth, ViewInt, false); (CornerRadius, ViewInt, false); (WidthValue, ViewInt, false); (HeightValue, ViewInt, false); (MinWidth, ViewInt, false); (MaxWidth, ViewInt, false); (MinHeight, ViewInt, false); (MaxHeight, ViewInt, false); (ContainerRelativeFrameValue, view_frame_axes, false); (ContainerRelativeFrameInset, ViewInt, false); (AccessibilityIdentifier, ViewString, false); (StyleClass, ViewString, false); (DataAttrs, ViewAttributes, false); (TextValue, ViewString, false); (PlaceholderValue, ViewString, false); (AccessibilityLabel, ViewString, false); (Autofocus, ViewBool, false); (SubmitOnEnter, ViewBool, false); (SubmitOnBlur, ViewBool, false); (ReadOnly, ViewBool, false); (Enabled, ViewBool, false); (Transition, ViewString, false); (AlignmentValue, view_alignment, false)];
      view_events = ["appear"; "pointer-enter"; "pointer-leave"; "input"; "submit"; "navigate-previous"; "navigate-next"; "navigation-key"; "context-menu"];
      view_slots = [];
    }
  | Checkbox -> Some {
      view_result = "t";
      view_children = ViewList "t";
      view_properties = [(KeyValue, ViewString, false); (Gap, ViewInt, false); (MainAlignment, view_main_alignment, false); (CrossAlignment, view_cross_alignment, false); (GrowValue, ViewFloat, false); (GridColumns, ViewInt, false); (PaddingValue, ViewInt, false); (PaddingHorizontal, ViewInt, false); (PaddingVertical, ViewInt, false); (MarginValue, ViewInt, false); (MarginHorizontal, ViewInt, false); (MarginVertical, ViewInt, false); (MarginTop, ViewInt, false); (MarginRight, ViewInt, false); (MarginBottom, ViewInt, false); (MarginLeft, ViewInt, false); (BackgroundValue, ViewString, false); (ForegroundValue, ViewString, false); (BorderColorValue, ViewString, false); (BorderWidth, ViewInt, false); (CornerRadius, ViewInt, false); (WidthValue, ViewInt, false); (HeightValue, ViewInt, false); (MinWidth, ViewInt, false); (MaxWidth, ViewInt, false); (MinHeight, ViewInt, false); (MaxHeight, ViewInt, false); (ContainerRelativeFrameValue, view_frame_axes, false); (ContainerRelativeFrameInset, ViewInt, false); (AccessibilityIdentifier, ViewString, false); (StyleClass, ViewString, false); (DataAttrs, ViewAttributes, false); (TextValue, ViewString, false); (Checked, ViewBool, false); (AccessibilityLabel, ViewString, false); (Enabled, ViewBool, false); (Transition, ViewString, false); (AlignmentValue, view_alignment, false)];
      view_events = ["appear"; "pointer-enter"; "pointer-leave"; "toggle"; "context-menu"];
      view_slots = [];
    }
  | SwitchControl -> Some {
      view_result = "t";
      view_children = ViewList "t";
      view_properties = [(KeyValue, ViewString, false); (Gap, ViewInt, false); (MainAlignment, view_main_alignment, false); (CrossAlignment, view_cross_alignment, false); (GrowValue, ViewFloat, false); (GridColumns, ViewInt, false); (PaddingValue, ViewInt, false); (PaddingHorizontal, ViewInt, false); (PaddingVertical, ViewInt, false); (MarginValue, ViewInt, false); (MarginHorizontal, ViewInt, false); (MarginVertical, ViewInt, false); (MarginTop, ViewInt, false); (MarginRight, ViewInt, false); (MarginBottom, ViewInt, false); (MarginLeft, ViewInt, false); (BackgroundValue, ViewString, false); (ForegroundValue, ViewString, false); (BorderColorValue, ViewString, false); (BorderWidth, ViewInt, false); (CornerRadius, ViewInt, false); (WidthValue, ViewInt, false); (HeightValue, ViewInt, false); (MinWidth, ViewInt, false); (MaxWidth, ViewInt, false); (MinHeight, ViewInt, false); (MaxHeight, ViewInt, false); (ContainerRelativeFrameValue, view_frame_axes, false); (ContainerRelativeFrameInset, ViewInt, false); (AccessibilityIdentifier, ViewString, false); (StyleClass, ViewString, false); (DataAttrs, ViewAttributes, false); (TextValue, ViewString, false); (Checked, ViewBool, false); (AccessibilityLabel, ViewString, false); (Enabled, ViewBool, false); (Transition, ViewString, false); (AlignmentValue, view_alignment, false)];
      view_events = ["appear"; "pointer-enter"; "pointer-leave"; "toggle"; "context-menu"];
      view_slots = [];
    }
  | Progress -> Some {
      view_result = "t";
      view_children = ViewList "nothing";
      view_properties = [(KeyValue, ViewString, false); (Gap, ViewInt, false); (MainAlignment, view_main_alignment, false); (CrossAlignment, view_cross_alignment, false); (GrowValue, ViewFloat, false); (GridColumns, ViewInt, false); (PaddingValue, ViewInt, false); (PaddingHorizontal, ViewInt, false); (PaddingVertical, ViewInt, false); (MarginValue, ViewInt, false); (MarginHorizontal, ViewInt, false); (MarginVertical, ViewInt, false); (MarginTop, ViewInt, false); (MarginRight, ViewInt, false); (MarginBottom, ViewInt, false); (MarginLeft, ViewInt, false); (BackgroundValue, ViewString, false); (ForegroundValue, ViewString, false); (BorderColorValue, ViewString, false); (BorderWidth, ViewInt, false); (CornerRadius, ViewInt, false); (WidthValue, ViewInt, false); (HeightValue, ViewInt, false); (MinWidth, ViewInt, false); (MaxWidth, ViewInt, false); (MinHeight, ViewInt, false); (MaxHeight, ViewInt, false); (ContainerRelativeFrameValue, view_frame_axes, false); (ContainerRelativeFrameInset, ViewInt, false); (AccessibilityIdentifier, ViewString, false); (StyleClass, ViewString, false); (DataAttrs, ViewAttributes, false); (ProgressValue, ViewFloat, false); (Transition, ViewString, false); (AlignmentValue, view_alignment, false)];
      view_events = ["appear"; "pointer-enter"; "pointer-leave"];
      view_slots = [];
    }
  | Divider -> Some {
      view_result = "t";
      view_children = ViewList "nothing";
      view_properties = [(KeyValue, ViewString, false); (Gap, ViewInt, false); (MainAlignment, view_main_alignment, false); (CrossAlignment, view_cross_alignment, false); (GrowValue, ViewFloat, false); (GridColumns, ViewInt, false); (PaddingValue, ViewInt, false); (PaddingHorizontal, ViewInt, false); (PaddingVertical, ViewInt, false); (MarginValue, ViewInt, false); (MarginHorizontal, ViewInt, false); (MarginVertical, ViewInt, false); (MarginTop, ViewInt, false); (MarginRight, ViewInt, false); (MarginBottom, ViewInt, false); (MarginLeft, ViewInt, false); (BackgroundValue, ViewString, false); (ForegroundValue, ViewString, false); (BorderColorValue, ViewString, false); (BorderWidth, ViewInt, false); (CornerRadius, ViewInt, false); (WidthValue, ViewInt, false); (HeightValue, ViewInt, false); (MinWidth, ViewInt, false); (MaxWidth, ViewInt, false); (MinHeight, ViewInt, false); (MaxHeight, ViewInt, false); (ContainerRelativeFrameValue, view_frame_axes, false); (ContainerRelativeFrameInset, ViewInt, false); (AccessibilityIdentifier, ViewString, false); (StyleClass, ViewString, false); (DataAttrs, ViewAttributes, false); (OrientationValue, view_orientation, false); (Transition, ViewString, false); (AlignmentValue, view_alignment, false)];
      view_events = ["appear"; "pointer-enter"; "pointer-leave"];
      view_slots = [];
    }
  | Scroll -> Some {
      view_result = "t";
      view_children = ViewList "t";
      view_properties = [(KeyValue, ViewString, false); (Gap, ViewInt, false); (MainAlignment, view_main_alignment, false); (CrossAlignment, view_cross_alignment, false); (GrowValue, ViewFloat, false); (GridColumns, ViewInt, false); (PaddingValue, ViewInt, false); (PaddingHorizontal, ViewInt, false); (PaddingVertical, ViewInt, false); (MarginValue, ViewInt, false); (MarginHorizontal, ViewInt, false); (MarginVertical, ViewInt, false); (MarginTop, ViewInt, false); (MarginRight, ViewInt, false); (MarginBottom, ViewInt, false); (MarginLeft, ViewInt, false); (BackgroundValue, ViewString, false); (ForegroundValue, ViewString, false); (BorderColorValue, ViewString, false); (BorderWidth, ViewInt, false); (CornerRadius, ViewInt, false); (WidthValue, ViewInt, false); (HeightValue, ViewInt, false); (MinWidth, ViewInt, false); (MaxWidth, ViewInt, false); (MinHeight, ViewInt, false); (MaxHeight, ViewInt, false); (ContainerRelativeFrameValue, view_frame_axes, false); (ContainerRelativeFrameInset, ViewInt, false); (AccessibilityIdentifier, ViewString, false); (StyleClass, ViewString, false); (DataAttrs, ViewAttributes, false); (OrientationValue, view_orientation, false); (Opacity, ViewFloat, false); (Transition, ViewString, false); (AlignmentValue, view_alignment, false)];
      view_events = ["appear"; "pointer-enter"; "pointer-leave"];
      view_slots = [];
    }
  | ListContainer -> Some {
      view_result = "t";
      view_children = ViewList "t";
      view_properties = [(KeyValue, ViewString, false); (Gap, ViewInt, false); (MainAlignment, view_main_alignment, false); (CrossAlignment, view_cross_alignment, false); (GrowValue, ViewFloat, false); (GridColumns, ViewInt, false); (PaddingValue, ViewInt, false); (PaddingHorizontal, ViewInt, false); (PaddingVertical, ViewInt, false); (MarginValue, ViewInt, false); (MarginHorizontal, ViewInt, false); (MarginVertical, ViewInt, false); (MarginTop, ViewInt, false); (MarginRight, ViewInt, false); (MarginBottom, ViewInt, false); (MarginLeft, ViewInt, false); (BackgroundValue, ViewString, false); (ForegroundValue, ViewString, false); (BorderColorValue, ViewString, false); (BorderWidth, ViewInt, false); (CornerRadius, ViewInt, false); (WidthValue, ViewInt, false); (HeightValue, ViewInt, false); (MinWidth, ViewInt, false); (MaxWidth, ViewInt, false); (MinHeight, ViewInt, false); (MaxHeight, ViewInt, false); (ContainerRelativeFrameValue, view_frame_axes, false); (ContainerRelativeFrameInset, ViewInt, false); (AccessibilityIdentifier, ViewString, false); (StyleClass, ViewString, false); (DataAttrs, ViewAttributes, false); (StyleValue, view_list_style, false); (ScrollTarget, ViewString, false); (ScrollAnchor, view_scroll_anchor, false); (ScrollToken, ViewInt, false); (ScrollAnimated, ViewBool, false); (TrackVisibleRange, ViewBool, false); (Opacity, ViewFloat, false); (ListStyle, view_list_marker, false); (Transition, ViewString, false); (AlignmentValue, view_alignment, false)];
      view_events = ["appear"; "pointer-enter"; "pointer-leave"; "scroll-completed"; "visible-range"];
      view_slots = [];
    }
  | VirtualList -> Some {
      view_result = "t";
      view_children = ViewList "t";
      view_properties = [(KeyValue, ViewString, false); (Gap, ViewInt, false); (MainAlignment, view_main_alignment, false); (CrossAlignment, view_cross_alignment, false); (GrowValue, ViewFloat, false); (GridColumns, ViewInt, false); (PaddingValue, ViewInt, false); (PaddingHorizontal, ViewInt, false); (PaddingVertical, ViewInt, false); (MarginValue, ViewInt, false); (MarginHorizontal, ViewInt, false); (MarginVertical, ViewInt, false); (MarginTop, ViewInt, false); (MarginRight, ViewInt, false); (MarginBottom, ViewInt, false); (MarginLeft, ViewInt, false); (BackgroundValue, ViewString, false); (ForegroundValue, ViewString, false); (BorderColorValue, ViewString, false); (BorderWidth, ViewInt, false); (CornerRadius, ViewInt, false); (WidthValue, ViewInt, false); (HeightValue, ViewInt, false); (MinWidth, ViewInt, false); (MaxWidth, ViewInt, false); (MinHeight, ViewInt, false); (MaxHeight, ViewInt, false); (ContainerRelativeFrameValue, view_frame_axes, false); (ContainerRelativeFrameInset, ViewInt, false); (AccessibilityIdentifier, ViewString, false); (StyleClass, ViewString, false); (DataAttrs, ViewAttributes, false); (ScrollTarget, ViewString, false); (ScrollAnchor, view_scroll_anchor, false); (ScrollToken, ViewInt, false); (ScrollAnimated, ViewBool, false); (TrackVisibleRange, ViewBool, false); (Opacity, ViewFloat, false); (ListStyle, view_list_marker, false); (Transition, ViewString, false); (AlignmentValue, view_alignment, false)];
      view_events = ["appear"; "pointer-enter"; "pointer-leave"; "scroll-completed"; "visible-range"];
      view_slots = [];
    }
  | Tabs -> Some {
      view_result = "t";
      view_children = ViewList "t";
      view_properties = [(KeyValue, ViewString, false); (Gap, ViewInt, false); (MainAlignment, view_main_alignment, false); (CrossAlignment, view_cross_alignment, false); (GrowValue, ViewFloat, false); (GridColumns, ViewInt, false); (PaddingValue, ViewInt, false); (PaddingHorizontal, ViewInt, false); (PaddingVertical, ViewInt, false); (MarginValue, ViewInt, false); (MarginHorizontal, ViewInt, false); (MarginVertical, ViewInt, false); (MarginTop, ViewInt, false); (MarginRight, ViewInt, false); (MarginBottom, ViewInt, false); (MarginLeft, ViewInt, false); (BackgroundValue, ViewString, false); (ForegroundValue, ViewString, false); (BorderColorValue, ViewString, false); (BorderWidth, ViewInt, false); (CornerRadius, ViewInt, false); (WidthValue, ViewInt, false); (HeightValue, ViewInt, false); (MinWidth, ViewInt, false); (MaxWidth, ViewInt, false); (MinHeight, ViewInt, false); (MaxHeight, ViewInt, false); (ContainerRelativeFrameValue, view_frame_axes, false); (ContainerRelativeFrameInset, ViewInt, false); (AccessibilityIdentifier, ViewString, false); (StyleClass, ViewString, false); (DataAttrs, ViewAttributes, false); (AccessibilityLabel, ViewString, false); (OrientationValue, view_orientation, false); (Transition, ViewString, false); (AlignmentValue, view_alignment, false)];
      view_events = ["appear"; "pointer-enter"; "pointer-leave"];
      view_slots = [];
    }
  | BottomTabs -> Some {
      view_result = "t";
      view_children = ViewList "bottom_tab_el";
      view_properties = [(KeyValue, ViewString, false); (Gap, ViewInt, false); (MainAlignment, view_main_alignment, false); (CrossAlignment, view_cross_alignment, false); (GrowValue, ViewFloat, false); (GridColumns, ViewInt, false); (PaddingValue, ViewInt, false); (PaddingHorizontal, ViewInt, false); (PaddingVertical, ViewInt, false); (MarginValue, ViewInt, false); (MarginHorizontal, ViewInt, false); (MarginVertical, ViewInt, false); (MarginTop, ViewInt, false); (MarginRight, ViewInt, false); (MarginBottom, ViewInt, false); (MarginLeft, ViewInt, false); (BackgroundValue, ViewString, false); (ForegroundValue, ViewString, false); (BorderColorValue, ViewString, false); (BorderWidth, ViewInt, false); (CornerRadius, ViewInt, false); (WidthValue, ViewInt, false); (HeightValue, ViewInt, false); (MinWidth, ViewInt, false); (MaxWidth, ViewInt, false); (MinHeight, ViewInt, false); (MaxHeight, ViewInt, false); (ContainerRelativeFrameValue, view_frame_axes, false); (ContainerRelativeFrameInset, ViewInt, false); (AccessibilityIdentifier, ViewString, false); (StyleClass, ViewString, false); (DataAttrs, ViewAttributes, false); (AccessibilityLabel, ViewString, false); (AlignmentValue, view_alignment, false)];
      view_events = ["appear"; "pointer-enter"; "pointer-leave"];
      view_slots = [];
    }
  | BottomTab -> Some {
      view_result = "bottom_tab_el";
      view_children = ViewList "t";
      view_properties = [(KeyValue, ViewString, false); (Gap, ViewInt, false); (MainAlignment, view_main_alignment, false); (CrossAlignment, view_cross_alignment, false); (GrowValue, ViewFloat, false); (GridColumns, ViewInt, false); (PaddingValue, ViewInt, false); (PaddingHorizontal, ViewInt, false); (PaddingVertical, ViewInt, false); (MarginValue, ViewInt, false); (MarginHorizontal, ViewInt, false); (MarginVertical, ViewInt, false); (MarginTop, ViewInt, false); (MarginRight, ViewInt, false); (MarginBottom, ViewInt, false); (MarginLeft, ViewInt, false); (BackgroundValue, ViewString, false); (ForegroundValue, ViewString, false); (BorderColorValue, ViewString, false); (BorderWidth, ViewInt, false); (CornerRadius, ViewInt, false); (WidthValue, ViewInt, false); (HeightValue, ViewInt, false); (MinWidth, ViewInt, false); (MaxWidth, ViewInt, false); (MinHeight, ViewInt, false); (MaxHeight, ViewInt, false); (ContainerRelativeFrameValue, view_frame_axes, false); (ContainerRelativeFrameInset, ViewInt, false); (AccessibilityIdentifier, ViewString, false); (StyleClass, ViewString, false); (DataAttrs, ViewAttributes, false); (TitleValue, ViewString, false); (InlineIconName, view_icon, false); (Selected, ViewBool, false); (Enabled, ViewBool, false)];
      view_events = ["appear"; "pointer-enter"; "pointer-leave"; "press"; "press-modifiers"; "press-detail"; "pointer-down"; "pointer-up"];
      view_slots = [];
    }
  | ButtonGroup -> Some {
      view_result = "t";
      view_children = ViewList "t";
      view_properties = [(KeyValue, ViewString, false); (Gap, ViewInt, false); (MainAlignment, view_main_alignment, false); (CrossAlignment, view_cross_alignment, false); (GrowValue, ViewFloat, false); (GridColumns, ViewInt, false); (PaddingValue, ViewInt, false); (PaddingHorizontal, ViewInt, false); (PaddingVertical, ViewInt, false); (MarginValue, ViewInt, false); (MarginHorizontal, ViewInt, false); (MarginVertical, ViewInt, false); (MarginTop, ViewInt, false); (MarginRight, ViewInt, false); (MarginBottom, ViewInt, false); (MarginLeft, ViewInt, false); (BackgroundValue, ViewString, false); (ForegroundValue, ViewString, false); (BorderColorValue, ViewString, false); (BorderWidth, ViewInt, false); (CornerRadius, ViewInt, false); (WidthValue, ViewInt, false); (HeightValue, ViewInt, false); (MinWidth, ViewInt, false); (MaxWidth, ViewInt, false); (MinHeight, ViewInt, false); (MaxHeight, ViewInt, false); (ContainerRelativeFrameValue, view_frame_axes, false); (ContainerRelativeFrameInset, ViewInt, false); (AccessibilityIdentifier, ViewString, false); (StyleClass, ViewString, false); (DataAttrs, ViewAttributes, false); (AccessibilityLabel, ViewString, false); (Transition, ViewString, false); (AlignmentValue, view_alignment, false)];
      view_events = ["appear"; "pointer-enter"; "pointer-leave"];
      view_slots = [];
    }
  | ToggleGroup -> Some {
      view_result = "t";
      view_children = ViewList "t";
      view_properties = [(KeyValue, ViewString, false); (Gap, ViewInt, false); (MainAlignment, view_main_alignment, false); (CrossAlignment, view_cross_alignment, false); (GrowValue, ViewFloat, false); (GridColumns, ViewInt, false); (PaddingValue, ViewInt, false); (PaddingHorizontal, ViewInt, false); (PaddingVertical, ViewInt, false); (MarginValue, ViewInt, false); (MarginHorizontal, ViewInt, false); (MarginVertical, ViewInt, false); (MarginTop, ViewInt, false); (MarginRight, ViewInt, false); (MarginBottom, ViewInt, false); (MarginLeft, ViewInt, false); (BackgroundValue, ViewString, false); (ForegroundValue, ViewString, false); (BorderColorValue, ViewString, false); (BorderWidth, ViewInt, false); (CornerRadius, ViewInt, false); (WidthValue, ViewInt, false); (HeightValue, ViewInt, false); (MinWidth, ViewInt, false); (MaxWidth, ViewInt, false); (MinHeight, ViewInt, false); (MaxHeight, ViewInt, false); (ContainerRelativeFrameValue, view_frame_axes, false); (ContainerRelativeFrameInset, ViewInt, false); (AccessibilityIdentifier, ViewString, false); (StyleClass, ViewString, false); (DataAttrs, ViewAttributes, false); (AccessibilityLabel, ViewString, false); (Transition, ViewString, false); (AlignmentValue, view_alignment, false)];
      view_events = ["appear"; "pointer-enter"; "pointer-leave"];
      view_slots = [];
    }
  | Spacer -> Some {
      view_result = "t";
      view_children = ViewList "nothing";
      view_properties = [(KeyValue, ViewString, false); (Gap, ViewInt, false); (MainAlignment, view_main_alignment, false); (CrossAlignment, view_cross_alignment, false); (GrowValue, ViewFloat, false); (GridColumns, ViewInt, false); (PaddingValue, ViewInt, false); (PaddingHorizontal, ViewInt, false); (PaddingVertical, ViewInt, false); (MarginValue, ViewInt, false); (MarginHorizontal, ViewInt, false); (MarginVertical, ViewInt, false); (MarginTop, ViewInt, false); (MarginRight, ViewInt, false); (MarginBottom, ViewInt, false); (MarginLeft, ViewInt, false); (BackgroundValue, ViewString, false); (ForegroundValue, ViewString, false); (BorderColorValue, ViewString, false); (BorderWidth, ViewInt, false); (CornerRadius, ViewInt, false); (WidthValue, ViewInt, false); (HeightValue, ViewInt, false); (MinWidth, ViewInt, false); (MaxWidth, ViewInt, false); (MinHeight, ViewInt, false); (MaxHeight, ViewInt, false); (ContainerRelativeFrameValue, view_frame_axes, false); (ContainerRelativeFrameInset, ViewInt, false); (AccessibilityIdentifier, ViewString, false); (StyleClass, ViewString, false); (DataAttrs, ViewAttributes, false); (Transition, ViewString, false); (AlignmentValue, view_alignment, false)];
      view_events = ["appear"; "pointer-enter"; "pointer-leave"];
      view_slots = [];
    }
  | Spinner -> Some {
      view_result = "t";
      view_children = ViewList "nothing";
      view_properties = [(KeyValue, ViewString, false); (Gap, ViewInt, false); (MainAlignment, view_main_alignment, false); (CrossAlignment, view_cross_alignment, false); (GrowValue, ViewFloat, false); (GridColumns, ViewInt, false); (PaddingValue, ViewInt, false); (PaddingHorizontal, ViewInt, false); (PaddingVertical, ViewInt, false); (MarginValue, ViewInt, false); (MarginHorizontal, ViewInt, false); (MarginVertical, ViewInt, false); (MarginTop, ViewInt, false); (MarginRight, ViewInt, false); (MarginBottom, ViewInt, false); (MarginLeft, ViewInt, false); (BackgroundValue, ViewString, false); (ForegroundValue, ViewString, false); (BorderColorValue, ViewString, false); (BorderWidth, ViewInt, false); (CornerRadius, ViewInt, false); (WidthValue, ViewInt, false); (HeightValue, ViewInt, false); (MinWidth, ViewInt, false); (MaxWidth, ViewInt, false); (MinHeight, ViewInt, false); (MaxHeight, ViewInt, false); (ContainerRelativeFrameValue, view_frame_axes, false); (ContainerRelativeFrameInset, ViewInt, false); (AccessibilityIdentifier, ViewString, false); (StyleClass, ViewString, false); (DataAttrs, ViewAttributes, false); (SizeValue, view_control_size, false); (Transition, ViewString, false); (AlignmentValue, view_alignment, false)];
      view_events = ["appear"; "pointer-enter"; "pointer-leave"];
      view_slots = [];
    }
  | Icon -> Some {
      view_result = "t";
      view_children = ViewList "nothing";
      view_properties = [(KeyValue, ViewString, false); (Gap, ViewInt, false); (MainAlignment, view_main_alignment, false); (CrossAlignment, view_cross_alignment, false); (GrowValue, ViewFloat, false); (GridColumns, ViewInt, false); (PaddingValue, ViewInt, false); (PaddingHorizontal, ViewInt, false); (PaddingVertical, ViewInt, false); (MarginValue, ViewInt, false); (MarginHorizontal, ViewInt, false); (MarginVertical, ViewInt, false); (MarginTop, ViewInt, false); (MarginRight, ViewInt, false); (MarginBottom, ViewInt, false); (MarginLeft, ViewInt, false); (BackgroundValue, ViewString, false); (ForegroundValue, ViewString, false); (BorderColorValue, ViewString, false); (BorderWidth, ViewInt, false); (CornerRadius, ViewInt, false); (WidthValue, ViewInt, false); (HeightValue, ViewInt, false); (MinWidth, ViewInt, false); (MaxWidth, ViewInt, false); (MinHeight, ViewInt, false); (MaxHeight, ViewInt, false); (ContainerRelativeFrameValue, view_frame_axes, false); (ContainerRelativeFrameInset, ViewInt, false); (AccessibilityIdentifier, ViewString, false); (StyleClass, ViewString, false); (DataAttrs, ViewAttributes, false); (IconName, view_icon, false); (SizeValue, view_control_size, false); (TooltipText, ViewString, false); (TooltipKeys, ViewString, false); (Transition, ViewString, false); (AlignmentValue, view_alignment, false)];
      view_events = ["appear"; "pointer-enter"; "pointer-leave"];
      view_slots = [];
    }
  | Select -> Some {
      view_result = "t";
      view_children = ViewList "t";
      view_properties = [(KeyValue, ViewString, false); (Gap, ViewInt, false); (MainAlignment, view_main_alignment, false); (CrossAlignment, view_cross_alignment, false); (GrowValue, ViewFloat, false); (GridColumns, ViewInt, false); (PaddingValue, ViewInt, false); (PaddingHorizontal, ViewInt, false); (PaddingVertical, ViewInt, false); (MarginValue, ViewInt, false); (MarginHorizontal, ViewInt, false); (MarginVertical, ViewInt, false); (MarginTop, ViewInt, false); (MarginRight, ViewInt, false); (MarginBottom, ViewInt, false); (MarginLeft, ViewInt, false); (BackgroundValue, ViewString, false); (ForegroundValue, ViewString, false); (BorderColorValue, ViewString, false); (BorderWidth, ViewInt, false); (CornerRadius, ViewInt, false); (WidthValue, ViewInt, false); (HeightValue, ViewInt, false); (MinWidth, ViewInt, false); (MaxWidth, ViewInt, false); (MinHeight, ViewInt, false); (MaxHeight, ViewInt, false); (ContainerRelativeFrameValue, view_frame_axes, false); (ContainerRelativeFrameInset, ViewInt, false); (AccessibilityIdentifier, ViewString, false); (StyleClass, ViewString, false); (DataAttrs, ViewAttributes, false); (AccessibilityLabel, ViewString, false); (TextValue, ViewString, false); (PlaceholderValue, ViewString, false); (Enabled, ViewBool, false); (Transition, ViewString, false); (AlignmentValue, view_alignment, false)];
      view_events = ["appear"; "pointer-enter"; "pointer-leave"; "press"; "press-modifiers"; "input"; "submit"; "dismiss"; "press-detail"; "pointer-down"; "pointer-up"; "context-menu"];
      view_slots = [];
    }
  | Combobox -> Some {
      view_result = "t";
      view_children = ViewList "t";
      view_properties = [(KeyValue, ViewString, false); (Gap, ViewInt, false); (MainAlignment, view_main_alignment, false); (CrossAlignment, view_cross_alignment, false); (GrowValue, ViewFloat, false); (GridColumns, ViewInt, false); (PaddingValue, ViewInt, false); (PaddingHorizontal, ViewInt, false); (PaddingVertical, ViewInt, false); (MarginValue, ViewInt, false); (MarginHorizontal, ViewInt, false); (MarginVertical, ViewInt, false); (MarginTop, ViewInt, false); (MarginRight, ViewInt, false); (MarginBottom, ViewInt, false); (MarginLeft, ViewInt, false); (BackgroundValue, ViewString, false); (ForegroundValue, ViewString, false); (BorderColorValue, ViewString, false); (BorderWidth, ViewInt, false); (CornerRadius, ViewInt, false); (WidthValue, ViewInt, false); (HeightValue, ViewInt, false); (MinWidth, ViewInt, false); (MaxWidth, ViewInt, false); (MinHeight, ViewInt, false); (MaxHeight, ViewInt, false); (ContainerRelativeFrameValue, view_frame_axes, false); (ContainerRelativeFrameInset, ViewInt, false); (AccessibilityIdentifier, ViewString, false); (StyleClass, ViewString, false); (DataAttrs, ViewAttributes, false); (TextValue, ViewString, false); (PlaceholderValue, ViewString, false); (ReadOnly, ViewBool, false); (Enabled, ViewBool, false); (Transition, ViewString, false); (AlignmentValue, view_alignment, false)];
      view_events = ["appear"; "pointer-enter"; "pointer-leave"; "press"; "press-modifiers"; "input"; "submit"; "dismiss"; "press-detail"; "pointer-down"; "pointer-up"; "context-menu"];
      view_slots = [];
    }
  | DropdownMenu -> Some {
      view_result = "t";
      view_children = ViewList "t";
      view_properties = [(KeyValue, ViewString, false); (Gap, ViewInt, false); (MainAlignment, view_main_alignment, false); (CrossAlignment, view_cross_alignment, false); (GrowValue, ViewFloat, false); (GridColumns, ViewInt, false); (PaddingValue, ViewInt, false); (PaddingHorizontal, ViewInt, false); (PaddingVertical, ViewInt, false); (MarginValue, ViewInt, false); (MarginHorizontal, ViewInt, false); (MarginVertical, ViewInt, false); (MarginTop, ViewInt, false); (MarginRight, ViewInt, false); (MarginBottom, ViewInt, false); (MarginLeft, ViewInt, false); (BackgroundValue, ViewString, false); (ForegroundValue, ViewString, false); (BorderColorValue, ViewString, false); (BorderWidth, ViewInt, false); (CornerRadius, ViewInt, false); (WidthValue, ViewInt, false); (HeightValue, ViewInt, false); (MinWidth, ViewInt, false); (MaxWidth, ViewInt, false); (MinHeight, ViewInt, false); (MaxHeight, ViewInt, false); (ContainerRelativeFrameValue, view_frame_axes, false); (ContainerRelativeFrameInset, ViewInt, false); (AccessibilityIdentifier, ViewString, false); (StyleClass, ViewString, false); (DataAttrs, ViewAttributes, false); (PopupX, ViewFloat, false); (PopupY, ViewFloat, false); (AnchorValue, view_anchor, false); (AnchorAlignmentValue, view_anchor_alignment, false); (AnchorOffset, ViewFloat, false); (Transition, ViewString, false); (AlignmentValue, view_alignment, false)];
      view_events = ["appear"; "pointer-enter"; "pointer-leave"; "press"; "press-modifiers"; "input"; "submit"; "dismiss"];
      view_slots = [];
    }
  | ContextMenu -> Some {
      view_result = "t";
      view_children = ViewList "t";
      view_properties = [(KeyValue, ViewString, false); (Gap, ViewInt, false); (MainAlignment, view_main_alignment, false); (CrossAlignment, view_cross_alignment, false); (GrowValue, ViewFloat, false); (GridColumns, ViewInt, false); (PaddingValue, ViewInt, false); (PaddingHorizontal, ViewInt, false); (PaddingVertical, ViewInt, false); (MarginValue, ViewInt, false); (MarginHorizontal, ViewInt, false); (MarginVertical, ViewInt, false); (MarginTop, ViewInt, false); (MarginRight, ViewInt, false); (MarginBottom, ViewInt, false); (MarginLeft, ViewInt, false); (BackgroundValue, ViewString, false); (ForegroundValue, ViewString, false); (BorderColorValue, ViewString, false); (BorderWidth, ViewInt, false); (CornerRadius, ViewInt, false); (WidthValue, ViewInt, false); (HeightValue, ViewInt, false); (MinWidth, ViewInt, false); (MaxWidth, ViewInt, false); (MinHeight, ViewInt, false); (MaxHeight, ViewInt, false); (ContainerRelativeFrameValue, view_frame_axes, false); (ContainerRelativeFrameInset, ViewInt, false); (AccessibilityIdentifier, ViewString, false); (StyleClass, ViewString, false); (DataAttrs, ViewAttributes, false); (Enabled, ViewBool, false); (AlignmentValue, view_alignment, false)];
      view_events = ["appear"; "pointer-enter"; "pointer-leave"; "dismiss"];
      view_slots = [];
    }
  | MenuItem -> Some {
      view_result = "t";
      view_children = ViewList "t";
      view_properties = [(KeyValue, ViewString, false); (Gap, ViewInt, false); (MainAlignment, view_main_alignment, false); (CrossAlignment, view_cross_alignment, false); (GrowValue, ViewFloat, false); (GridColumns, ViewInt, false); (PaddingValue, ViewInt, false); (PaddingHorizontal, ViewInt, false); (PaddingVertical, ViewInt, false); (MarginValue, ViewInt, false); (MarginHorizontal, ViewInt, false); (MarginVertical, ViewInt, false); (MarginTop, ViewInt, false); (MarginRight, ViewInt, false); (MarginBottom, ViewInt, false); (MarginLeft, ViewInt, false); (BackgroundValue, ViewString, false); (ForegroundValue, ViewString, false); (BorderColorValue, ViewString, false); (BorderWidth, ViewInt, false); (CornerRadius, ViewInt, false); (WidthValue, ViewInt, false); (HeightValue, ViewInt, false); (MinWidth, ViewInt, false); (MaxWidth, ViewInt, false); (MinHeight, ViewInt, false); (MaxHeight, ViewInt, false); (ContainerRelativeFrameValue, view_frame_axes, false); (ContainerRelativeFrameInset, ViewInt, false); (AccessibilityIdentifier, ViewString, false); (StyleClass, ViewString, false); (DataAttrs, ViewAttributes, false); (TextValue, ViewString, false); (InlineIconName, view_icon, false); (SelectionPlacementValue, view_icon_placement, false); (RoleValue, view_role, false); (VariantValue, view_variant, false); (SizeValue, view_control_size, false); (TreeLevel, ViewInt, false); (Expanded, ViewBool, false); (Selected, ViewBool, false); (Checked, ViewBool, false); (Enabled, ViewBool, false); (TooltipText, ViewString, false); (TooltipKeys, ViewString, false); (Transition, ViewString, false); (AlignmentValue, view_alignment, false)];
      view_events = ["appear"; "pointer-enter"; "pointer-leave"; "press"; "press-modifiers"; "input"; "submit"; "dismiss"; "press-detail"; "pointer-down"; "pointer-up"; "context-menu"];
      view_slots = [];
    }
  | MenuTrigger -> Some {
      view_result = "t";
      view_children = ViewList "t";
      view_properties = [(KeyValue, ViewString, false); (AccessibilityIdentifier, ViewString, false); (ForegroundValue, ViewString, false); (StyleClass, ViewString, false); (DataAttrs, ViewAttributes, false); (TextValue, ViewString, false); (InlineIconName, view_icon, false); (AccessibilityLabel, ViewString, false); (Enabled, ViewBool, false); (AlignmentValue, view_alignment, false)];
      view_events = [];
      view_slots = [];
    }
  | ListItem -> Some {
      view_result = "t";
      view_children = ViewList "t";
      view_properties = [(KeyValue, ViewString, false); (Gap, ViewInt, false); (MainAlignment, view_main_alignment, false); (CrossAlignment, view_cross_alignment, false); (GrowValue, ViewFloat, false); (GridColumns, ViewInt, false); (PaddingValue, ViewInt, false); (PaddingHorizontal, ViewInt, false); (PaddingVertical, ViewInt, false); (MarginValue, ViewInt, false); (MarginHorizontal, ViewInt, false); (MarginVertical, ViewInt, false); (MarginTop, ViewInt, false); (MarginRight, ViewInt, false); (MarginBottom, ViewInt, false); (MarginLeft, ViewInt, false); (BackgroundValue, ViewString, false); (ForegroundValue, ViewString, false); (BorderColorValue, ViewString, false); (BorderWidth, ViewInt, false); (CornerRadius, ViewInt, false); (WidthValue, ViewInt, false); (HeightValue, ViewInt, false); (MinWidth, ViewInt, false); (MaxWidth, ViewInt, false); (MinHeight, ViewInt, false); (MaxHeight, ViewInt, false); (ContainerRelativeFrameValue, view_frame_axes, false); (ContainerRelativeFrameInset, ViewInt, false); (AccessibilityIdentifier, ViewString, false); (StyleClass, ViewString, false); (DataAttrs, ViewAttributes, false); (TextValue, ViewString, false); (InlineIconName, view_icon, false); (IconPlacementValue, view_icon_placement, false); (RoleValue, view_role, false); (TreeLevel, ViewInt, false); (Expanded, ViewBool, false); (Selected, ViewBool, false); (Enabled, ViewBool, false); (SeparatorValue, view_separator_visibility, false); (ListStyle, view_list_marker, false); (Transition, ViewString, false); (AlignmentValue, view_alignment, false)];
      view_events = ["appear"; "pointer-enter"; "pointer-leave"; "press"; "press-modifiers"; "long-press"; "double-press"; "submit"; "input"; "toggle"; "press-detail"; "pointer-down"; "pointer-up"; "context-menu"];
      view_slots = [("swipe-actions", "swipe_action_el", true)];
    }
  | Avatar -> Some {
      view_result = "t";
      view_children = ViewList "nothing";
      view_properties = [(KeyValue, ViewString, false); (Gap, ViewInt, false); (MainAlignment, view_main_alignment, false); (CrossAlignment, view_cross_alignment, false); (GrowValue, ViewFloat, false); (GridColumns, ViewInt, false); (PaddingValue, ViewInt, false); (PaddingHorizontal, ViewInt, false); (PaddingVertical, ViewInt, false); (MarginValue, ViewInt, false); (MarginHorizontal, ViewInt, false); (MarginVertical, ViewInt, false); (MarginTop, ViewInt, false); (MarginRight, ViewInt, false); (MarginBottom, ViewInt, false); (MarginLeft, ViewInt, false); (BackgroundValue, ViewString, false); (ForegroundValue, ViewString, false); (BorderColorValue, ViewString, false); (BorderWidth, ViewInt, false); (CornerRadius, ViewInt, false); (WidthValue, ViewInt, false); (HeightValue, ViewInt, false); (MinWidth, ViewInt, false); (MaxWidth, ViewInt, false); (MinHeight, ViewInt, false); (MaxHeight, ViewInt, false); (ContainerRelativeFrameValue, view_frame_axes, false); (ContainerRelativeFrameInset, ViewInt, false); (AccessibilityIdentifier, ViewString, false); (StyleClass, ViewString, false); (DataAttrs, ViewAttributes, false); (TextValue, ViewString, false); (ImageIdValue, ViewInt, false); (SourceX, ViewFloat, false); (SourceY, ViewFloat, false); (SourceWidth, ViewFloat, false); (SourceHeight, ViewFloat, false); (AccessibilityLabel, ViewString, false); (Transition, ViewString, false); (AlignmentValue, view_alignment, false)];
      view_events = ["appear"; "pointer-enter"; "pointer-leave"];
      view_slots = [];
    }
  | Image -> Some {
      view_result = "t";
      view_children = ViewList "nothing";
      view_properties = [(KeyValue, ViewString, false); (Gap, ViewInt, false); (MainAlignment, view_main_alignment, false); (CrossAlignment, view_cross_alignment, false); (GrowValue, ViewFloat, false); (GridColumns, ViewInt, false); (PaddingValue, ViewInt, false); (PaddingHorizontal, ViewInt, false); (PaddingVertical, ViewInt, false); (MarginValue, ViewInt, false); (MarginHorizontal, ViewInt, false); (MarginVertical, ViewInt, false); (MarginTop, ViewInt, false); (MarginRight, ViewInt, false); (MarginBottom, ViewInt, false); (MarginLeft, ViewInt, false); (BackgroundValue, ViewString, false); (ForegroundValue, ViewString, false); (BorderColorValue, ViewString, false); (BorderWidth, ViewInt, false); (CornerRadius, ViewInt, false); (WidthValue, ViewInt, false); (HeightValue, ViewInt, false); (MinWidth, ViewInt, false); (MaxWidth, ViewInt, false); (MinHeight, ViewInt, false); (MaxHeight, ViewInt, false); (ContainerRelativeFrameValue, view_frame_axes, false); (ContainerRelativeFrameInset, ViewInt, false); (AccessibilityIdentifier, ViewString, false); (StyleClass, ViewString, false); (DataAttrs, ViewAttributes, false); (ImageIdValue, ViewInt, false); (UrlValue, ViewString, false); (AltValue, ViewString, false); (LoadingValue, view_image_loading, false); (ReferrerPolicy, view_referrer_policy, false); (SourceX, ViewFloat, false); (SourceY, ViewFloat, false); (SourceWidth, ViewFloat, false); (SourceHeight, ViewFloat, false); (AccessibilityLabel, ViewString, false); (Transition, ViewString, false); (AlignmentValue, view_alignment, false)];
      view_events = ["appear"; "pointer-enter"; "pointer-leave"; "load"];
      view_slots = [];
    }
  | MediaSurface -> Some {
      view_result = "t";
      view_children = ViewList "nothing";
      view_properties = [(KeyValue, ViewString, false); (Gap, ViewInt, false); (MainAlignment, view_main_alignment, false); (CrossAlignment, view_cross_alignment, false); (GrowValue, ViewFloat, false); (GridColumns, ViewInt, false); (PaddingValue, ViewInt, false); (PaddingHorizontal, ViewInt, false); (PaddingVertical, ViewInt, false); (MarginValue, ViewInt, false); (MarginHorizontal, ViewInt, false); (MarginVertical, ViewInt, false); (MarginTop, ViewInt, false); (MarginRight, ViewInt, false); (MarginBottom, ViewInt, false); (MarginLeft, ViewInt, false); (BackgroundValue, ViewString, false); (ForegroundValue, ViewString, false); (BorderColorValue, ViewString, false); (BorderWidth, ViewInt, false); (CornerRadius, ViewInt, false); (WidthValue, ViewInt, false); (HeightValue, ViewInt, false); (MinWidth, ViewInt, false); (MaxWidth, ViewInt, false); (MinHeight, ViewInt, false); (MaxHeight, ViewInt, false); (ContainerRelativeFrameValue, view_frame_axes, false); (ContainerRelativeFrameInset, ViewInt, false); (AccessibilityIdentifier, ViewString, false); (StyleClass, ViewString, false); (DataAttrs, ViewAttributes, false); (SurfaceIdValue, ViewInt, false); (AccessibilityLabel, ViewString, false); (Transition, ViewString, false); (AlignmentValue, view_alignment, false)];
      view_events = ["appear"; "pointer-enter"; "pointer-leave"];
      view_slots = [];
    }
  | Stepper -> Some {
      view_result = "t";
      view_children = ViewList "step_el";
      view_properties = [(KeyValue, ViewString, false); (Gap, ViewInt, false); (MainAlignment, view_main_alignment, false); (CrossAlignment, view_cross_alignment, false); (GrowValue, ViewFloat, false); (GridColumns, ViewInt, false); (PaddingValue, ViewInt, false); (PaddingHorizontal, ViewInt, false); (PaddingVertical, ViewInt, false); (MarginValue, ViewInt, false); (MarginHorizontal, ViewInt, false); (MarginVertical, ViewInt, false); (MarginTop, ViewInt, false); (MarginRight, ViewInt, false); (MarginBottom, ViewInt, false); (MarginLeft, ViewInt, false); (BackgroundValue, ViewString, false); (ForegroundValue, ViewString, false); (BorderColorValue, ViewString, false); (BorderWidth, ViewInt, false); (CornerRadius, ViewInt, false); (WidthValue, ViewInt, false); (HeightValue, ViewInt, false); (MinWidth, ViewInt, false); (MaxWidth, ViewInt, false); (MinHeight, ViewInt, false); (MaxHeight, ViewInt, false); (ContainerRelativeFrameValue, view_frame_axes, false); (ContainerRelativeFrameInset, ViewInt, false); (AccessibilityIdentifier, ViewString, false); (StyleClass, ViewString, false); (DataAttrs, ViewAttributes, false); (ActiveIndex, ViewInt, false); (AccessibilityLabel, ViewString, false); (AlignmentValue, view_alignment, false)];
      view_events = ["appear"; "pointer-enter"; "pointer-leave"];
      view_slots = [];
    }
  | Step -> Some {
      view_result = "step_el";
      view_children = ViewList "nothing";
      view_properties = [(KeyValue, ViewString, false); (Gap, ViewInt, false); (MainAlignment, view_main_alignment, false); (CrossAlignment, view_cross_alignment, false); (GrowValue, ViewFloat, false); (GridColumns, ViewInt, false); (PaddingValue, ViewInt, false); (PaddingHorizontal, ViewInt, false); (PaddingVertical, ViewInt, false); (MarginValue, ViewInt, false); (MarginHorizontal, ViewInt, false); (MarginVertical, ViewInt, false); (MarginTop, ViewInt, false); (MarginRight, ViewInt, false); (MarginBottom, ViewInt, false); (MarginLeft, ViewInt, false); (BackgroundValue, ViewString, false); (ForegroundValue, ViewString, false); (BorderColorValue, ViewString, false); (BorderWidth, ViewInt, false); (CornerRadius, ViewInt, false); (WidthValue, ViewInt, false); (HeightValue, ViewInt, false); (MinWidth, ViewInt, false); (MaxWidth, ViewInt, false); (MinHeight, ViewInt, false); (MaxHeight, ViewInt, false); (ContainerRelativeFrameValue, view_frame_axes, false); (ContainerRelativeFrameInset, ViewInt, false); (AccessibilityIdentifier, ViewString, false); (StyleClass, ViewString, false); (DataAttrs, ViewAttributes, false); (TextValue, ViewString, false)];
      view_events = ["appear"; "pointer-enter"; "pointer-leave"];
      view_slots = [];
    }
  | Timeline -> Some {
      view_result = "t";
      view_children = ViewList "timeline_item_el";
      view_properties = [(KeyValue, ViewString, false); (Gap, ViewInt, false); (MainAlignment, view_main_alignment, false); (CrossAlignment, view_cross_alignment, false); (GrowValue, ViewFloat, false); (GridColumns, ViewInt, false); (PaddingValue, ViewInt, false); (PaddingHorizontal, ViewInt, false); (PaddingVertical, ViewInt, false); (MarginValue, ViewInt, false); (MarginHorizontal, ViewInt, false); (MarginVertical, ViewInt, false); (MarginTop, ViewInt, false); (MarginRight, ViewInt, false); (MarginBottom, ViewInt, false); (MarginLeft, ViewInt, false); (BackgroundValue, ViewString, false); (ForegroundValue, ViewString, false); (BorderColorValue, ViewString, false); (BorderWidth, ViewInt, false); (CornerRadius, ViewInt, false); (WidthValue, ViewInt, false); (HeightValue, ViewInt, false); (MinWidth, ViewInt, false); (MaxWidth, ViewInt, false); (MinHeight, ViewInt, false); (MaxHeight, ViewInt, false); (ContainerRelativeFrameValue, view_frame_axes, false); (ContainerRelativeFrameInset, ViewInt, false); (AccessibilityIdentifier, ViewString, false); (StyleClass, ViewString, false); (DataAttrs, ViewAttributes, false); (AccessibilityLabel, ViewString, false); (AlignmentValue, view_alignment, false)];
      view_events = ["appear"; "pointer-enter"; "pointer-leave"];
      view_slots = [];
    }
  | TimelineItem -> Some {
      view_result = "timeline_item_el";
      view_children = ViewList "nothing";
      view_properties = [(KeyValue, ViewString, false); (Gap, ViewInt, false); (MainAlignment, view_main_alignment, false); (CrossAlignment, view_cross_alignment, false); (GrowValue, ViewFloat, false); (GridColumns, ViewInt, false); (PaddingValue, ViewInt, false); (PaddingHorizontal, ViewInt, false); (PaddingVertical, ViewInt, false); (MarginValue, ViewInt, false); (MarginHorizontal, ViewInt, false); (MarginVertical, ViewInt, false); (MarginTop, ViewInt, false); (MarginRight, ViewInt, false); (MarginBottom, ViewInt, false); (MarginLeft, ViewInt, false); (BackgroundValue, ViewString, false); (ForegroundValue, ViewString, false); (BorderColorValue, ViewString, false); (BorderWidth, ViewInt, false); (CornerRadius, ViewInt, false); (WidthValue, ViewInt, false); (HeightValue, ViewInt, false); (MinWidth, ViewInt, false); (MaxWidth, ViewInt, false); (MinHeight, ViewInt, false); (MaxHeight, ViewInt, false); (ContainerRelativeFrameValue, view_frame_axes, false); (ContainerRelativeFrameInset, ViewInt, false); (AccessibilityIdentifier, ViewString, false); (StyleClass, ViewString, false); (DataAttrs, ViewAttributes, false); (TitleValue, ViewString, false); (DescriptionValue, ViewString, false); (MetaValue, ViewString, false); (IndicatorValue, ViewString, false); (InlineIconName, view_icon, false); (VariantValue, view_variant, false); (Connector, ViewBool, false); (Selected, ViewBool, false)];
      view_events = ["appear"; "pointer-enter"; "pointer-leave"; "press"; "press-modifiers"; "press-detail"; "pointer-down"; "pointer-up"];
      view_slots = [];
    }
  | InputGroup -> Some {
      view_result = "t";
      view_children = ViewArguments ["t"];
      view_properties = [(KeyValue, ViewString, false); (Gap, ViewInt, false); (MainAlignment, view_main_alignment, false); (CrossAlignment, view_cross_alignment, false); (GrowValue, ViewFloat, false); (GridColumns, ViewInt, false); (PaddingValue, ViewInt, false); (PaddingHorizontal, ViewInt, false); (PaddingVertical, ViewInt, false); (MarginValue, ViewInt, false); (MarginHorizontal, ViewInt, false); (MarginVertical, ViewInt, false); (MarginTop, ViewInt, false); (MarginRight, ViewInt, false); (MarginBottom, ViewInt, false); (MarginLeft, ViewInt, false); (BackgroundValue, ViewString, false); (ForegroundValue, ViewString, false); (BorderColorValue, ViewString, false); (BorderWidth, ViewInt, false); (CornerRadius, ViewInt, false); (WidthValue, ViewInt, false); (HeightValue, ViewInt, false); (MinWidth, ViewInt, false); (MaxWidth, ViewInt, false); (MinHeight, ViewInt, false); (MaxHeight, ViewInt, false); (ContainerRelativeFrameValue, view_frame_axes, false); (ContainerRelativeFrameInset, ViewInt, false); (AccessibilityIdentifier, ViewString, false); (StyleClass, ViewString, false); (DataAttrs, ViewAttributes, false); (AccessibilityLabel, ViewString, false); (AlignmentValue, view_alignment, false)];
      view_events = ["appear"; "pointer-enter"; "pointer-leave"];
      view_slots = [("actions", "input_group_actions_el", false)];
    }
  | InputGroupActions -> Some {
      view_result = "input_group_actions_el";
      view_children = ViewList "t";
      view_properties = [(KeyValue, ViewString, false); (Gap, ViewInt, false); (MainAlignment, view_main_alignment, false); (CrossAlignment, view_cross_alignment, false); (GrowValue, ViewFloat, false); (GridColumns, ViewInt, false); (PaddingValue, ViewInt, false); (PaddingHorizontal, ViewInt, false); (PaddingVertical, ViewInt, false); (MarginValue, ViewInt, false); (MarginHorizontal, ViewInt, false); (MarginVertical, ViewInt, false); (MarginTop, ViewInt, false); (MarginRight, ViewInt, false); (MarginBottom, ViewInt, false); (MarginLeft, ViewInt, false); (BackgroundValue, ViewString, false); (ForegroundValue, ViewString, false); (BorderColorValue, ViewString, false); (BorderWidth, ViewInt, false); (CornerRadius, ViewInt, false); (WidthValue, ViewInt, false); (HeightValue, ViewInt, false); (MinWidth, ViewInt, false); (MaxWidth, ViewInt, false); (MinHeight, ViewInt, false); (MaxHeight, ViewInt, false); (ContainerRelativeFrameValue, view_frame_axes, false); (ContainerRelativeFrameInset, ViewInt, false); (AccessibilityIdentifier, ViewString, false); (StyleClass, ViewString, false); (DataAttrs, ViewAttributes, false)];
      view_events = ["appear"; "pointer-enter"; "pointer-leave"];
      view_slots = [];
    }
  | Breadcrumb -> Some {
      view_result = "t";
      view_children = ViewList "t";
      view_properties = [(KeyValue, ViewString, false); (Gap, ViewInt, false); (MainAlignment, view_main_alignment, false); (CrossAlignment, view_cross_alignment, false); (GrowValue, ViewFloat, false); (GridColumns, ViewInt, false); (PaddingValue, ViewInt, false); (PaddingHorizontal, ViewInt, false); (PaddingVertical, ViewInt, false); (MarginValue, ViewInt, false); (MarginHorizontal, ViewInt, false); (MarginVertical, ViewInt, false); (MarginTop, ViewInt, false); (MarginRight, ViewInt, false); (MarginBottom, ViewInt, false); (MarginLeft, ViewInt, false); (BackgroundValue, ViewString, false); (ForegroundValue, ViewString, false); (BorderColorValue, ViewString, false); (BorderWidth, ViewInt, false); (CornerRadius, ViewInt, false); (WidthValue, ViewInt, false); (HeightValue, ViewInt, false); (MinWidth, ViewInt, false); (MaxWidth, ViewInt, false); (MinHeight, ViewInt, false); (MaxHeight, ViewInt, false); (ContainerRelativeFrameValue, view_frame_axes, false); (ContainerRelativeFrameInset, ViewInt, false); (AccessibilityIdentifier, ViewString, false); (StyleClass, ViewString, false); (DataAttrs, ViewAttributes, false); (AccessibilityLabel, ViewString, false); (Transition, ViewString, false); (AlignmentValue, view_alignment, false)];
      view_events = ["appear"; "pointer-enter"; "pointer-leave"];
      view_slots = [];
    }
  | Pagination -> Some {
      view_result = "t";
      view_children = ViewList "t";
      view_properties = [(KeyValue, ViewString, false); (Gap, ViewInt, false); (MainAlignment, view_main_alignment, false); (CrossAlignment, view_cross_alignment, false); (GrowValue, ViewFloat, false); (GridColumns, ViewInt, false); (PaddingValue, ViewInt, false); (PaddingHorizontal, ViewInt, false); (PaddingVertical, ViewInt, false); (MarginValue, ViewInt, false); (MarginHorizontal, ViewInt, false); (MarginVertical, ViewInt, false); (MarginTop, ViewInt, false); (MarginRight, ViewInt, false); (MarginBottom, ViewInt, false); (MarginLeft, ViewInt, false); (BackgroundValue, ViewString, false); (ForegroundValue, ViewString, false); (BorderColorValue, ViewString, false); (BorderWidth, ViewInt, false); (CornerRadius, ViewInt, false); (WidthValue, ViewInt, false); (HeightValue, ViewInt, false); (MinWidth, ViewInt, false); (MaxWidth, ViewInt, false); (MinHeight, ViewInt, false); (MaxHeight, ViewInt, false); (ContainerRelativeFrameValue, view_frame_axes, false); (ContainerRelativeFrameInset, ViewInt, false); (AccessibilityIdentifier, ViewString, false); (StyleClass, ViewString, false); (DataAttrs, ViewAttributes, false); (AccessibilityLabel, ViewString, false); (Transition, ViewString, false); (AlignmentValue, view_alignment, false)];
      view_events = ["appear"; "pointer-enter"; "pointer-leave"];
      view_slots = [];
    }
  | Accordion -> Some {
      view_result = "t";
      view_children = ViewList "t";
      view_properties = [(KeyValue, ViewString, false); (Gap, ViewInt, false); (MainAlignment, view_main_alignment, false); (CrossAlignment, view_cross_alignment, false); (GrowValue, ViewFloat, false); (GridColumns, ViewInt, false); (PaddingValue, ViewInt, false); (PaddingHorizontal, ViewInt, false); (PaddingVertical, ViewInt, false); (MarginValue, ViewInt, false); (MarginHorizontal, ViewInt, false); (MarginVertical, ViewInt, false); (MarginTop, ViewInt, false); (MarginRight, ViewInt, false); (MarginBottom, ViewInt, false); (MarginLeft, ViewInt, false); (BackgroundValue, ViewString, false); (ForegroundValue, ViewString, false); (BorderColorValue, ViewString, false); (BorderWidth, ViewInt, false); (CornerRadius, ViewInt, false); (WidthValue, ViewInt, false); (HeightValue, ViewInt, false); (MinWidth, ViewInt, false); (MaxWidth, ViewInt, false); (MinHeight, ViewInt, false); (MaxHeight, ViewInt, false); (ContainerRelativeFrameValue, view_frame_axes, false); (ContainerRelativeFrameInset, ViewInt, false); (AccessibilityIdentifier, ViewString, false); (StyleClass, ViewString, false); (DataAttrs, ViewAttributes, false); (TextValue, ViewString, false); (Selected, ViewBool, false); (AlignmentValue, view_alignment, false)];
      view_events = ["appear"; "pointer-enter"; "pointer-leave"; "toggle"; "context-menu"];
      view_slots = [];
    }
  | Table -> Some {
      view_result = "t";
      view_children = ViewList "table_row_el";
      view_properties = [(KeyValue, ViewString, false); (Gap, ViewInt, false); (MainAlignment, view_main_alignment, false); (CrossAlignment, view_cross_alignment, false); (GrowValue, ViewFloat, false); (GridColumns, ViewInt, false); (PaddingValue, ViewInt, false); (PaddingHorizontal, ViewInt, false); (PaddingVertical, ViewInt, false); (MarginValue, ViewInt, false); (MarginHorizontal, ViewInt, false); (MarginVertical, ViewInt, false); (MarginTop, ViewInt, false); (MarginRight, ViewInt, false); (MarginBottom, ViewInt, false); (MarginLeft, ViewInt, false); (BackgroundValue, ViewString, false); (ForegroundValue, ViewString, false); (BorderColorValue, ViewString, false); (BorderWidth, ViewInt, false); (CornerRadius, ViewInt, false); (WidthValue, ViewInt, false); (HeightValue, ViewInt, false); (MinWidth, ViewInt, false); (MaxWidth, ViewInt, false); (MinHeight, ViewInt, false); (MaxHeight, ViewInt, false); (ContainerRelativeFrameValue, view_frame_axes, false); (ContainerRelativeFrameInset, ViewInt, false); (AccessibilityIdentifier, ViewString, false); (StyleClass, ViewString, false); (DataAttrs, ViewAttributes, false); (Transition, ViewString, false); (AlignmentValue, view_alignment, false)];
      view_events = ["appear"; "pointer-enter"; "pointer-leave"];
      view_slots = [];
    }
  | TableRow -> Some {
      view_result = "table_row_el";
      view_children = ViewList "table_cell_el";
      view_properties = [(KeyValue, ViewString, false); (Gap, ViewInt, false); (MainAlignment, view_main_alignment, false); (CrossAlignment, view_cross_alignment, false); (GrowValue, ViewFloat, false); (GridColumns, ViewInt, false); (PaddingValue, ViewInt, false); (PaddingHorizontal, ViewInt, false); (PaddingVertical, ViewInt, false); (MarginValue, ViewInt, false); (MarginHorizontal, ViewInt, false); (MarginVertical, ViewInt, false); (MarginTop, ViewInt, false); (MarginRight, ViewInt, false); (MarginBottom, ViewInt, false); (MarginLeft, ViewInt, false); (BackgroundValue, ViewString, false); (ForegroundValue, ViewString, false); (BorderColorValue, ViewString, false); (BorderWidth, ViewInt, false); (CornerRadius, ViewInt, false); (WidthValue, ViewInt, false); (HeightValue, ViewInt, false); (MinWidth, ViewInt, false); (MaxWidth, ViewInt, false); (MinHeight, ViewInt, false); (MaxHeight, ViewInt, false); (ContainerRelativeFrameValue, view_frame_axes, false); (ContainerRelativeFrameInset, ViewInt, false); (AccessibilityIdentifier, ViewString, false); (StyleClass, ViewString, false); (DataAttrs, ViewAttributes, false); (Selected, ViewBool, false); (Transition, ViewString, false)];
      view_events = ["appear"; "pointer-enter"; "pointer-leave"];
      view_slots = [];
    }
  | TableCell -> Some {
      view_result = "table_cell_el";
      view_children = ViewList "t";
      view_properties = [(KeyValue, ViewString, false); (Gap, ViewInt, false); (MainAlignment, view_main_alignment, false); (CrossAlignment, view_cross_alignment, false); (GrowValue, ViewFloat, false); (GridColumns, ViewInt, false); (PaddingValue, ViewInt, false); (PaddingHorizontal, ViewInt, false); (PaddingVertical, ViewInt, false); (MarginValue, ViewInt, false); (MarginHorizontal, ViewInt, false); (MarginVertical, ViewInt, false); (MarginTop, ViewInt, false); (MarginRight, ViewInt, false); (MarginBottom, ViewInt, false); (MarginLeft, ViewInt, false); (BackgroundValue, ViewString, false); (ForegroundValue, ViewString, false); (BorderColorValue, ViewString, false); (BorderWidth, ViewInt, false); (CornerRadius, ViewInt, false); (WidthValue, ViewInt, false); (HeightValue, ViewInt, false); (MinWidth, ViewInt, false); (MaxWidth, ViewInt, false); (MinHeight, ViewInt, false); (MaxHeight, ViewInt, false); (ContainerRelativeFrameValue, view_frame_axes, false); (ContainerRelativeFrameInset, ViewInt, false); (AccessibilityIdentifier, ViewString, false); (StyleClass, ViewString, false); (DataAttrs, ViewAttributes, false); (TextValue, ViewString, false); (FontSize, ViewString, false); (FontWeight, ViewInt, false); (LineHeight, ViewString, false); (SizeValue, view_cell_size, false); (TextAlignment, view_text_alignment, false); (Transition, ViewString, false)];
      view_events = ["appear"; "pointer-enter"; "pointer-leave"; "press"; "press-modifiers"; "press-detail"; "pointer-down"; "pointer-up"; "context-menu"];
      view_slots = [];
    }
  | Tree -> Some {
      view_result = "t";
      view_children = ViewList "t";
      view_properties = [(KeyValue, ViewString, false); (Gap, ViewInt, false); (MainAlignment, view_main_alignment, false); (CrossAlignment, view_cross_alignment, false); (GrowValue, ViewFloat, false); (GridColumns, ViewInt, false); (PaddingValue, ViewInt, false); (PaddingHorizontal, ViewInt, false); (PaddingVertical, ViewInt, false); (MarginValue, ViewInt, false); (MarginHorizontal, ViewInt, false); (MarginVertical, ViewInt, false); (MarginTop, ViewInt, false); (MarginRight, ViewInt, false); (MarginBottom, ViewInt, false); (MarginLeft, ViewInt, false); (BackgroundValue, ViewString, false); (ForegroundValue, ViewString, false); (BorderColorValue, ViewString, false); (BorderWidth, ViewInt, false); (CornerRadius, ViewInt, false); (WidthValue, ViewInt, false); (HeightValue, ViewInt, false); (MinWidth, ViewInt, false); (MaxWidth, ViewInt, false); (MinHeight, ViewInt, false); (MaxHeight, ViewInt, false); (ContainerRelativeFrameValue, view_frame_axes, false); (ContainerRelativeFrameInset, ViewInt, false); (AccessibilityIdentifier, ViewString, false); (StyleClass, ViewString, false); (DataAttrs, ViewAttributes, false); (AccessibilityLabel, ViewString, false); (RoleValue, view_role, false); (TreeLevel, ViewInt, false); (Expanded, ViewBool, false); (Transition, ViewString, false); (AlignmentValue, view_alignment, false)];
      view_events = ["appear"; "pointer-enter"; "pointer-leave"; "press"; "press-modifiers"; "change"; "toggle"; "press-detail"; "pointer-down"; "pointer-up"; "context-menu"];
      view_slots = [];
    }
  | Resizable -> Some {
      view_result = "t";
      view_children = ViewList "t";
      view_properties = [(KeyValue, ViewString, false); (Gap, ViewInt, false); (MainAlignment, view_main_alignment, false); (CrossAlignment, view_cross_alignment, false); (GrowValue, ViewFloat, false); (GridColumns, ViewInt, false); (PaddingValue, ViewInt, false); (PaddingHorizontal, ViewInt, false); (PaddingVertical, ViewInt, false); (MarginValue, ViewInt, false); (MarginHorizontal, ViewInt, false); (MarginVertical, ViewInt, false); (MarginTop, ViewInt, false); (MarginRight, ViewInt, false); (MarginBottom, ViewInt, false); (MarginLeft, ViewInt, false); (BackgroundValue, ViewString, false); (ForegroundValue, ViewString, false); (BorderColorValue, ViewString, false); (BorderWidth, ViewInt, false); (CornerRadius, ViewInt, false); (WidthValue, ViewInt, false); (HeightValue, ViewInt, false); (MinWidth, ViewInt, false); (MaxWidth, ViewInt, false); (MinHeight, ViewInt, false); (MaxHeight, ViewInt, false); (ContainerRelativeFrameValue, view_frame_axes, false); (ContainerRelativeFrameInset, ViewInt, false); (AccessibilityIdentifier, ViewString, false); (StyleClass, ViewString, false); (DataAttrs, ViewAttributes, false); (AccessibilityLabel, ViewString, false); (Transition, ViewString, false); (AlignmentValue, view_alignment, false)];
      view_events = ["appear"; "pointer-enter"; "pointer-leave"];
      view_slots = [];
    }
  | Split -> Some {
      view_result = "t";
      view_children = ViewArguments ["t"; "t"];
      view_properties = [(KeyValue, ViewString, false); (Gap, ViewInt, false); (MainAlignment, view_main_alignment, false); (CrossAlignment, view_cross_alignment, false); (GrowValue, ViewFloat, false); (GridColumns, ViewInt, false); (PaddingValue, ViewInt, false); (PaddingHorizontal, ViewInt, false); (PaddingVertical, ViewInt, false); (MarginValue, ViewInt, false); (MarginHorizontal, ViewInt, false); (MarginVertical, ViewInt, false); (MarginTop, ViewInt, false); (MarginRight, ViewInt, false); (MarginBottom, ViewInt, false); (MarginLeft, ViewInt, false); (BackgroundValue, ViewString, false); (ForegroundValue, ViewString, false); (BorderColorValue, ViewString, false); (BorderWidth, ViewInt, false); (CornerRadius, ViewInt, false); (WidthValue, ViewInt, false); (HeightValue, ViewInt, false); (MinWidth, ViewInt, false); (MaxWidth, ViewInt, false); (MinHeight, ViewInt, false); (MaxHeight, ViewInt, false); (ContainerRelativeFrameValue, view_frame_axes, false); (ContainerRelativeFrameInset, ViewInt, false); (AccessibilityIdentifier, ViewString, false); (StyleClass, ViewString, false); (DataAttrs, ViewAttributes, false); (ProgressValue, ViewFloat, false); (FirstPaneWidth, ViewFloat, false); (ResizeHandleWidth, ViewInt, false); (ResizeHandleOffset, ViewFloat, false); (ResizeDuration, ViewInt, false); (ResizeEasing, view_resize_easing, false); (ResizeOrigin, ViewFloat, false); (AccessibilityLabel, ViewString, false); (Transition, ViewString, false); (AlignmentValue, view_alignment, false)];
      view_events = ["appear"; "pointer-enter"; "pointer-leave"; "resize"];
      view_slots = [];
    }
  | Dialog -> Some {
      view_result = "t";
      view_children = ViewList "t";
      view_properties = [(KeyValue, ViewString, false); (Gap, ViewInt, false); (MainAlignment, view_main_alignment, false); (CrossAlignment, view_cross_alignment, false); (GrowValue, ViewFloat, false); (GridColumns, ViewInt, false); (PaddingValue, ViewInt, false); (PaddingHorizontal, ViewInt, false); (PaddingVertical, ViewInt, false); (MarginValue, ViewInt, false); (MarginHorizontal, ViewInt, false); (MarginVertical, ViewInt, false); (MarginTop, ViewInt, false); (MarginRight, ViewInt, false); (MarginBottom, ViewInt, false); (MarginLeft, ViewInt, false); (BackgroundValue, ViewString, false); (ForegroundValue, ViewString, false); (BorderColorValue, ViewString, false); (BorderWidth, ViewInt, false); (CornerRadius, ViewInt, false); (WidthValue, ViewInt, false); (HeightValue, ViewInt, false); (MinWidth, ViewInt, false); (MaxWidth, ViewInt, false); (MinHeight, ViewInt, false); (MaxHeight, ViewInt, false); (ContainerRelativeFrameValue, view_frame_axes, false); (ContainerRelativeFrameInset, ViewInt, false); (AccessibilityIdentifier, ViewString, false); (StyleClass, ViewString, false); (DataAttrs, ViewAttributes, false); (TextValue, ViewString, false); (DescriptionValue, ViewString, false); (AlignmentValue, view_alignment, false)];
      view_events = ["appear"; "pointer-enter"; "pointer-leave"; "dismiss"];
      view_slots = [];
    }
  | Drawer -> Some {
      view_result = "t";
      view_children = ViewArguments ["t"; "t"];
      view_properties = [(KeyValue, ViewString, false); (Gap, ViewInt, false); (MainAlignment, view_main_alignment, false); (CrossAlignment, view_cross_alignment, false); (GrowValue, ViewFloat, false); (GridColumns, ViewInt, false); (PaddingValue, ViewInt, false); (PaddingHorizontal, ViewInt, false); (PaddingVertical, ViewInt, false); (MarginValue, ViewInt, false); (MarginHorizontal, ViewInt, false); (MarginVertical, ViewInt, false); (MarginTop, ViewInt, false); (MarginRight, ViewInt, false); (MarginBottom, ViewInt, false); (MarginLeft, ViewInt, false); (BackgroundValue, ViewString, false); (ForegroundValue, ViewString, false); (BorderColorValue, ViewString, false); (BorderWidth, ViewInt, false); (CornerRadius, ViewInt, false); (WidthValue, ViewInt, false); (HeightValue, ViewInt, false); (MinWidth, ViewInt, false); (MaxWidth, ViewInt, false); (MinHeight, ViewInt, false); (MaxHeight, ViewInt, false); (ContainerRelativeFrameValue, view_frame_axes, false); (ContainerRelativeFrameInset, ViewInt, false); (AccessibilityIdentifier, ViewString, false); (StyleClass, ViewString, false); (DataAttrs, ViewAttributes, false); (Selected, ViewBool, false); (Enabled, ViewBool, false); (AccessibilityLabel, ViewString, false); (AlignmentValue, view_alignment, false)];
      view_events = ["appear"; "pointer-enter"; "pointer-leave"; "toggle"];
      view_slots = [];
    }
  | Sheet -> Some {
      view_result = "t";
      view_children = ViewList "t";
      view_properties = [(KeyValue, ViewString, false); (Gap, ViewInt, false); (MainAlignment, view_main_alignment, false); (CrossAlignment, view_cross_alignment, false); (GrowValue, ViewFloat, false); (GridColumns, ViewInt, false); (PaddingValue, ViewInt, false); (PaddingHorizontal, ViewInt, false); (PaddingVertical, ViewInt, false); (MarginValue, ViewInt, false); (MarginHorizontal, ViewInt, false); (MarginVertical, ViewInt, false); (MarginTop, ViewInt, false); (MarginRight, ViewInt, false); (MarginBottom, ViewInt, false); (MarginLeft, ViewInt, false); (BackgroundValue, ViewString, false); (ForegroundValue, ViewString, false); (BorderColorValue, ViewString, false); (BorderWidth, ViewInt, false); (CornerRadius, ViewInt, false); (WidthValue, ViewInt, false); (HeightValue, ViewInt, false); (MinWidth, ViewInt, false); (MaxWidth, ViewInt, false); (MinHeight, ViewInt, false); (MaxHeight, ViewInt, false); (ContainerRelativeFrameValue, view_frame_axes, false); (ContainerRelativeFrameInset, ViewInt, false); (AccessibilityIdentifier, ViewString, false); (StyleClass, ViewString, false); (DataAttrs, ViewAttributes, false); (TextValue, ViewString, false); (Detents, ViewString, false); (Sizing, ViewString, false); (AlignmentValue, view_alignment, false)];
      view_events = ["appear"; "pointer-enter"; "pointer-leave"; "dismiss"];
      view_slots = [];
    }
  | Tooltip -> Some {
      view_result = "t";
      view_children = ViewList "nothing";
      view_properties = [(KeyValue, ViewString, false); (Gap, ViewInt, false); (MainAlignment, view_main_alignment, false); (CrossAlignment, view_cross_alignment, false); (GrowValue, ViewFloat, false); (GridColumns, ViewInt, false); (PaddingValue, ViewInt, false); (PaddingHorizontal, ViewInt, false); (PaddingVertical, ViewInt, false); (MarginValue, ViewInt, false); (MarginHorizontal, ViewInt, false); (MarginVertical, ViewInt, false); (MarginTop, ViewInt, false); (MarginRight, ViewInt, false); (MarginBottom, ViewInt, false); (MarginLeft, ViewInt, false); (BackgroundValue, ViewString, false); (ForegroundValue, ViewString, false); (BorderColorValue, ViewString, false); (BorderWidth, ViewInt, false); (CornerRadius, ViewInt, false); (WidthValue, ViewInt, false); (HeightValue, ViewInt, false); (MinWidth, ViewInt, false); (MaxWidth, ViewInt, false); (MinHeight, ViewInt, false); (MaxHeight, ViewInt, false); (ContainerRelativeFrameValue, view_frame_axes, false); (ContainerRelativeFrameInset, ViewInt, false); (AccessibilityIdentifier, ViewString, false); (StyleClass, ViewString, false); (DataAttrs, ViewAttributes, false); (TextValue, ViewString, false); (AnchorValue, view_anchor, false); (AnchorAlignmentValue, view_anchor_alignment, false); (AnchorOffset, ViewFloat, false); (TooltipDelay, ViewInt, false); (AlignmentValue, view_alignment, false)];
      view_events = ["appear"; "pointer-enter"; "pointer-leave"];
      view_slots = [];
    }
  | Toast -> Some {
      view_result = "t";
      view_children = ViewList "t";
      view_properties = [(KeyValue, ViewString, false); (Gap, ViewInt, false); (MainAlignment, view_main_alignment, false); (CrossAlignment, view_cross_alignment, false); (GrowValue, ViewFloat, false); (GridColumns, ViewInt, false); (PaddingValue, ViewInt, false); (PaddingHorizontal, ViewInt, false); (PaddingVertical, ViewInt, false); (MarginValue, ViewInt, false); (MarginHorizontal, ViewInt, false); (MarginVertical, ViewInt, false); (MarginTop, ViewInt, false); (MarginRight, ViewInt, false); (MarginBottom, ViewInt, false); (MarginLeft, ViewInt, false); (BackgroundValue, ViewString, false); (ForegroundValue, ViewString, false); (BorderColorValue, ViewString, false); (BorderWidth, ViewInt, false); (CornerRadius, ViewInt, false); (WidthValue, ViewInt, false); (HeightValue, ViewInt, false); (MinWidth, ViewInt, false); (MaxWidth, ViewInt, false); (MinHeight, ViewInt, false); (MaxHeight, ViewInt, false); (ContainerRelativeFrameValue, view_frame_axes, false); (ContainerRelativeFrameInset, ViewInt, false); (AccessibilityIdentifier, ViewString, false); (StyleClass, ViewString, false); (DataAttrs, ViewAttributes, false); (DurationValue, ViewInt, false); (AccessibilityLabel, ViewString, false); (AlignmentValue, view_alignment, false)];
      view_events = ["appear"; "pointer-enter"; "pointer-leave"; "dismiss"];
      view_slots = [];
    }
  | Toolbar -> Some {
      view_result = "t";
      view_children = ViewList "t";
      view_properties = [(KeyValue, ViewString, false); (Gap, ViewInt, false); (MainAlignment, view_main_alignment, false); (CrossAlignment, view_cross_alignment, false); (GrowValue, ViewFloat, false); (GridColumns, ViewInt, false); (PaddingValue, ViewInt, false); (PaddingHorizontal, ViewInt, false); (PaddingVertical, ViewInt, false); (MarginValue, ViewInt, false); (MarginHorizontal, ViewInt, false); (MarginVertical, ViewInt, false); (MarginTop, ViewInt, false); (MarginRight, ViewInt, false); (MarginBottom, ViewInt, false); (MarginLeft, ViewInt, false); (BackgroundValue, ViewString, false); (ForegroundValue, ViewString, false); (BorderColorValue, ViewString, false); (BorderWidth, ViewInt, false); (CornerRadius, ViewInt, false); (WidthValue, ViewInt, false); (HeightValue, ViewInt, false); (MinWidth, ViewInt, false); (MaxWidth, ViewInt, false); (MinHeight, ViewInt, false); (MaxHeight, ViewInt, false); (ContainerRelativeFrameValue, view_frame_axes, false); (ContainerRelativeFrameInset, ViewInt, false); (AccessibilityIdentifier, ViewString, false); (StyleClass, ViewString, false); (DataAttrs, ViewAttributes, false); (OrientationValue, view_orientation, false); (AccessibilityLabel, ViewString, false); (PlacementValue, ViewString, false); (AlignmentValue, view_alignment, false)];
      view_events = ["appear"; "pointer-enter"; "pointer-leave"];
      view_slots = [];
    }
  | StatusBar -> Some {
      view_result = "t";
      view_children = ViewList "nothing";
      view_properties = [(KeyValue, ViewString, false); (Gap, ViewInt, false); (MainAlignment, view_main_alignment, false); (CrossAlignment, view_cross_alignment, false); (GrowValue, ViewFloat, false); (GridColumns, ViewInt, false); (PaddingValue, ViewInt, false); (PaddingHorizontal, ViewInt, false); (PaddingVertical, ViewInt, false); (MarginValue, ViewInt, false); (MarginHorizontal, ViewInt, false); (MarginVertical, ViewInt, false); (MarginTop, ViewInt, false); (MarginRight, ViewInt, false); (MarginBottom, ViewInt, false); (MarginLeft, ViewInt, false); (BackgroundValue, ViewString, false); (ForegroundValue, ViewString, false); (BorderColorValue, ViewString, false); (BorderWidth, ViewInt, false); (CornerRadius, ViewInt, false); (WidthValue, ViewInt, false); (HeightValue, ViewInt, false); (MinWidth, ViewInt, false); (MaxWidth, ViewInt, false); (MinHeight, ViewInt, false); (MaxHeight, ViewInt, false); (ContainerRelativeFrameValue, view_frame_axes, false); (ContainerRelativeFrameInset, ViewInt, false); (AccessibilityIdentifier, ViewString, false); (StyleClass, ViewString, false); (DataAttrs, ViewAttributes, false); (TextValue, ViewString, false); (TextAlignment, view_text_alignment, false); (Transition, ViewString, false); (AlignmentValue, view_alignment, false)];
      view_events = ["appear"; "pointer-enter"; "pointer-leave"];
      view_slots = [];
    }
  | ListSection -> Some {
      view_result = "t";
      view_children = ViewList "t";
      view_properties = [(KeyValue, ViewString, false); (AccessibilityIdentifier, ViewString, false); (SeparatorValue, view_separator_visibility, false); (AlignmentValue, view_alignment, false)];
      view_events = [];
      view_slots = [("header", "t", false); ("footer", "t", false)];
    }
  | ListSectionHeader -> None
  | ListSectionFooter -> None
  | SwipeActions -> Some {
      view_result = "t";
      view_children = ViewList "swipe_action_el";
      view_properties = [(KeyValue, ViewString, false); (AccessibilityIdentifier, ViewString, false); (AlignmentValue, view_alignment, false)];
      view_events = [];
      view_slots = [];
    }
  | SwipeAction -> Some {
      view_result = "swipe_action_el";
      view_children = ViewList "nothing";
      view_properties = [(KeyValue, ViewString, false); (AccessibilityIdentifier, ViewString, false); (TextValue, ViewString, false); (InlineIconName, view_icon, false); (VariantValue, view_variant, false); (EdgeValue, view_swipe_edge, false); (BackgroundValue, ViewString, false); (Enabled, ViewBool, false)];
      view_events = ["press"; "press-modifiers"; "press-detail"; "pointer-down"; "pointer-up"];
      view_slots = [];
    }
  | FilePicker -> Some {
      view_result = "t";
      view_children = ViewList "t";
      view_properties = [(KeyValue, ViewString, false); (Gap, ViewInt, false); (MainAlignment, view_main_alignment, false); (CrossAlignment, view_cross_alignment, false); (GrowValue, ViewFloat, false); (GridColumns, ViewInt, false); (PaddingValue, ViewInt, false); (PaddingHorizontal, ViewInt, false); (PaddingVertical, ViewInt, false); (MarginValue, ViewInt, false); (MarginHorizontal, ViewInt, false); (MarginVertical, ViewInt, false); (MarginTop, ViewInt, false); (MarginRight, ViewInt, false); (MarginBottom, ViewInt, false); (MarginLeft, ViewInt, false); (BackgroundValue, ViewString, false); (ForegroundValue, ViewString, false); (BorderColorValue, ViewString, false); (BorderWidth, ViewInt, false); (CornerRadius, ViewInt, false); (WidthValue, ViewInt, false); (HeightValue, ViewInt, false); (MinWidth, ViewInt, false); (MaxWidth, ViewInt, false); (MinHeight, ViewInt, false); (MaxHeight, ViewInt, false); (ContainerRelativeFrameValue, view_frame_axes, false); (ContainerRelativeFrameInset, ViewInt, false); (AccessibilityIdentifier, ViewString, false); (StyleClass, ViewString, false); (DataAttrs, ViewAttributes, false); (PickerSource, view_file_picker_source, false); (PickerRequest, ViewToken, false); (PickerTypes, ViewString, false); (PickerMultiple, ViewBool, false); (Enabled, ViewBool, false); (PickerCompletion, ViewToken, false); (PickerAccept, ViewString, false); (PickerDirectory, ViewBool, false); (AlignmentValue, view_alignment, false)];
      view_events = ["appear"; "pointer-enter"; "pointer-leave"; "picked"; "dismiss"];
      view_slots = [];
    }
  | Kbd -> Some {
      view_result = "t";
      view_children = ViewList "nothing";
      view_properties = [(KeyValue, ViewString, false); (Gap, ViewInt, false); (MainAlignment, view_main_alignment, false); (CrossAlignment, view_cross_alignment, false); (GrowValue, ViewFloat, false); (GridColumns, ViewInt, false); (PaddingValue, ViewInt, false); (PaddingHorizontal, ViewInt, false); (PaddingVertical, ViewInt, false); (MarginValue, ViewInt, false); (MarginHorizontal, ViewInt, false); (MarginVertical, ViewInt, false); (MarginTop, ViewInt, false); (MarginRight, ViewInt, false); (MarginBottom, ViewInt, false); (MarginLeft, ViewInt, false); (BackgroundValue, ViewString, false); (ForegroundValue, ViewString, false); (BorderColorValue, ViewString, false); (BorderWidth, ViewInt, false); (CornerRadius, ViewInt, false); (WidthValue, ViewInt, false); (HeightValue, ViewInt, false); (MinWidth, ViewInt, false); (MaxWidth, ViewInt, false); (MinHeight, ViewInt, false); (MaxHeight, ViewInt, false); (ContainerRelativeFrameValue, view_frame_axes, false); (ContainerRelativeFrameInset, ViewInt, false); (AccessibilityIdentifier, ViewString, false); (StyleClass, ViewString, false); (DataAttrs, ViewAttributes, false); (TextValue, ViewString, false); (Transition, ViewString, false); (AlignmentValue, view_alignment, false)];
      view_events = ["appear"; "pointer-enter"; "pointer-leave"];
      view_slots = [];
    }
  | Link -> Some {
      view_result = "t";
      view_children = ViewList "t";
      view_properties = [(KeyValue, ViewString, false); (Gap, ViewInt, false); (MainAlignment, view_main_alignment, false); (CrossAlignment, view_cross_alignment, false); (GrowValue, ViewFloat, false); (GridColumns, ViewInt, false); (PaddingValue, ViewInt, false); (PaddingHorizontal, ViewInt, false); (PaddingVertical, ViewInt, false); (MarginValue, ViewInt, false); (MarginHorizontal, ViewInt, false); (MarginVertical, ViewInt, false); (MarginTop, ViewInt, false); (MarginRight, ViewInt, false); (MarginBottom, ViewInt, false); (MarginLeft, ViewInt, false); (BackgroundValue, ViewString, false); (ForegroundValue, ViewString, false); (BorderColorValue, ViewString, false); (BorderWidth, ViewInt, false); (CornerRadius, ViewInt, false); (WidthValue, ViewInt, false); (HeightValue, ViewInt, false); (MinWidth, ViewInt, false); (MaxWidth, ViewInt, false); (MinHeight, ViewInt, false); (MaxHeight, ViewInt, false); (ContainerRelativeFrameValue, view_frame_axes, false); (ContainerRelativeFrameInset, ViewInt, false); (AccessibilityIdentifier, ViewString, false); (StyleClass, ViewString, false); (DataAttrs, ViewAttributes, false); (UrlValue, ViewString, false); (TargetValue, view_link_target, false); (TextValue, ViewString, false); (InlineIconName, view_icon, false); (IconPlacementValue, view_icon_placement, false); (AccessibilityLabel, ViewString, false); (Enabled, ViewBool, false); (Transition, ViewString, false); (AlignmentValue, view_alignment, false)];
      view_events = ["appear"; "pointer-enter"; "pointer-leave"; "press"; "press-modifiers"];
      view_slots = [];
    }
  | FileImage -> Some {
      view_result = "t";
      view_children = ViewList "nothing";
      view_properties = [(KeyValue, ViewString, false); (Gap, ViewInt, false); (MainAlignment, view_main_alignment, false); (CrossAlignment, view_cross_alignment, false); (GrowValue, ViewFloat, false); (GridColumns, ViewInt, false); (PaddingValue, ViewInt, false); (PaddingHorizontal, ViewInt, false); (PaddingVertical, ViewInt, false); (MarginValue, ViewInt, false); (MarginHorizontal, ViewInt, false); (MarginVertical, ViewInt, false); (MarginTop, ViewInt, false); (MarginRight, ViewInt, false); (MarginBottom, ViewInt, false); (MarginLeft, ViewInt, false); (BackgroundValue, ViewString, false); (ForegroundValue, ViewString, false); (BorderColorValue, ViewString, false); (BorderWidth, ViewInt, false); (CornerRadius, ViewInt, false); (WidthValue, ViewInt, false); (HeightValue, ViewInt, false); (MinWidth, ViewInt, false); (MaxWidth, ViewInt, false); (MinHeight, ViewInt, false); (MaxHeight, ViewInt, false); (ContainerRelativeFrameValue, view_frame_axes, false); (ContainerRelativeFrameInset, ViewInt, false); (AccessibilityIdentifier, ViewString, false); (StyleClass, ViewString, false); (DataAttrs, ViewAttributes, false); (PathValue, ViewString, false); (MaxPixelSize, ViewInt, false); (ImageFitValue, view_image_fit, false); (AccessibilityLabel, ViewString, false); (Transition, ViewString, false); (AlignmentValue, view_alignment, false)];
      view_events = ["appear"; "pointer-enter"; "pointer-leave"; "press"; "press-modifiers"; "press-detail"; "pointer-down"; "pointer-up"];
      view_slots = [];
    }
  | FilePreview -> Some {
      view_result = "t";
      view_children = ViewList "nothing";
      view_properties = [(KeyValue, ViewString, false); (PathValue, ViewString, false); (AccessibilityIdentifier, ViewString, false); (AlignmentValue, view_alignment, false)];
      view_events = ["dismiss"];
      view_slots = [];
    }
  | Popover -> Some {
      view_result = "t";
      view_children = ViewList "t";
      view_properties = [(KeyValue, ViewString, false); (Gap, ViewInt, false); (MainAlignment, view_main_alignment, false); (CrossAlignment, view_cross_alignment, false); (GrowValue, ViewFloat, false); (GridColumns, ViewInt, false); (PaddingValue, ViewInt, false); (PaddingHorizontal, ViewInt, false); (PaddingVertical, ViewInt, false); (MarginValue, ViewInt, false); (MarginHorizontal, ViewInt, false); (MarginVertical, ViewInt, false); (MarginTop, ViewInt, false); (MarginRight, ViewInt, false); (MarginBottom, ViewInt, false); (MarginLeft, ViewInt, false); (BackgroundValue, ViewString, false); (ForegroundValue, ViewString, false); (BorderColorValue, ViewString, false); (BorderWidth, ViewInt, false); (CornerRadius, ViewInt, false); (WidthValue, ViewInt, false); (HeightValue, ViewInt, false); (MinWidth, ViewInt, false); (MaxWidth, ViewInt, false); (MinHeight, ViewInt, false); (MaxHeight, ViewInt, false); (ContainerRelativeFrameValue, view_frame_axes, false); (ContainerRelativeFrameInset, ViewInt, false); (AccessibilityIdentifier, ViewString, false); (StyleClass, ViewString, false); (DataAttrs, ViewAttributes, false); (Opacity, ViewFloat, false); (PopupX, ViewFloat, false); (PopupY, ViewFloat, false); (AnchorValue, view_anchor, false); (AnchorTarget, ViewString, false); (AnchorRect, (ViewFloatTuple 4), false); (AnchorAlignmentValue, view_anchor_alignment, false); (AnchorOffset, ViewFloat, false); (AnchorAlignmentOffset, ViewFloat, false); (AvailableHeight, ViewFloat, false); (RoleValue, view_popover_role, false); (Transition, ViewString, false); (AlignmentValue, view_alignment, false)];
      view_events = ["appear"; "pointer-enter"; "pointer-leave"; "dismiss"];
      view_slots = [];
    }




let extension_view_contract = function
  | "split-view" -> Some {
      view_result = "t";
      view_children = ViewList "t";
      view_properties = [("divider-thickness", ViewFloat, false); ("animation", ViewBool, false); ("accessibility-identifier", ViewString, false)];
      view_events = [];
      view_slots = [];
    }
  | "split-branch" -> Some {
      view_result = "t";
      view_children = ViewList "t";
      view_properties = [("orientation", (ViewEnum ["horizontal"; "vertical"]), true); ("ratio", ViewFloat, true)];
      view_events = ["ratio-changed"];
      view_slots = [];
    }
  | "split-pane" -> Some {
      view_result = "t";
      view_children = ViewList "t";
      view_properties = [("pane-id", ViewString, true); ("selected", ViewString, false); ("focused", ViewBool, false); ("accessibility-identifier", ViewString, false)];
      view_events = ["tab-selected"; "tab-closed"; "tab-moved"; "pane-focused"; "navigate"; "split-requested"; "split-drop"; "pane-closed"];
      view_slots = [];
    }
  | "split-tab" -> Some {
      view_result = "t";
      view_children = ViewList "t";
      view_properties = [("tab-id", ViewString, true); ("title", ViewString, true); ("icon", ViewString, false); ("dirty", ViewBool, false); ("closable", ViewBool, false); ("accessibility-identifier", ViewString, false)];
      view_events = [];
      view_slots = [];
    }
  | _ -> None
