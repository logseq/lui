// Generated from schema/components.json. Do not edit by hand.
#pragma once

namespace LUI {

enum class NodeKind {
  Root,
  Row,
  Column,
  Grid,
  Stack,
  Panel,
  Card,
  Alert,
  Bubble,
  Box,
  Text,
  Heading,
  Paragraph,
  Label,
  Button,
  ToggleButton,
  Toggle,
  RadioGroup,
  Radio,
  Slider,
  TextField,
  SecureField,
  Input,
  SearchField,
  Textarea,
  Checkbox,
  SwitchControl,
  Progress,
  Divider,
  Scroll,
  ListContainer,
  VirtualList,
  Tabs,
  BottomTabs,
  BottomTab,
  ButtonGroup,
  ToggleGroup,
  Spacer,
  Spinner,
  Icon,
  Select,
  Combobox,
  DropdownMenu,
  ContextMenu,
  MenuItem,
  ListItem,
  Avatar,
  Image,
  MediaSurface,
  Stepper,
  Step,
  Timeline,
  TimelineItem,
  InputGroup,
  InputGroupActions,
  Breadcrumb,
  Pagination,
  Accordion,
  Table,
  TableRow,
  TableCell,
  Tree,
  Resizable,
  Split,
  Dialog,
  Drawer,
  Sheet,
  Tooltip,
  Toast,
  Toolbar,
  StatusBar,
};

enum class Property {
  TextValue,
  Enabled,
  Gap,
  MainAlignment,
  CrossAlignment,
  GrowValue,
  GridColumns,
  PaddingValue,
  PaddingHorizontal,
  PaddingVertical,
  BackgroundValue,
  ForegroundValue,
  BorderColorValue,
  BorderWidth,
  CornerRadius,
  WidthValue,
  HeightValue,
  MinWidth,
  MaxWidth,
  MinHeight,
  MaxHeight,
  ContainerRelativeFrameValue,
  ContainerRelativeFrameInset,
  PlaceholderValue,
  AccessibilityLabel,
  AccessibilityIdentifier,
  StyleClass,
  HeadingLevel,
  Checked,
  ProgressValue,
  OrientationValue,
  SizeValue,
  IconName,
  VariantValue,
  InlineIconName,
  IconPlacementValue,
  Selected,
  Autofocus,
  SubmitOnEnter,
  LongPressEnabled,
  ChangeEnabled,
  ToggleEnabled,
  PressEnabled,
  SubmitEnabled,
  DoublePressEnabled,
  AppearEnabled,
  ImageIdValue,
  SurfaceIdValue,
  ActiveIndex,
  TitleValue,
  DescriptionValue,
  MetaValue,
  IndicatorValue,
  Connector,
  SourceX,
  SourceY,
  SourceWidth,
  SourceHeight,
  AnchorValue,
  AnchorAlignmentValue,
  AnchorOffset,
  TooltipDelay,
  DurationValue,
  TextAlignment,
  RoleValue,
  TreeLevel,
  Expanded,
  ResizeDuration,
  ResizeEasing,
  ResizeOrigin,
};

inline const char *nodeKindWireName(NodeKind kind) {
  switch (kind) {
    case NodeKind::Root: return "root";
    case NodeKind::Row: return "row";
    case NodeKind::Column: return "column";
    case NodeKind::Grid: return "grid";
    case NodeKind::Stack: return "stack";
    case NodeKind::Panel: return "panel";
    case NodeKind::Card: return "card";
    case NodeKind::Alert: return "alert";
    case NodeKind::Bubble: return "bubble";
    case NodeKind::Box: return "box";
    case NodeKind::Text: return "text";
    case NodeKind::Heading: return "heading";
    case NodeKind::Paragraph: return "paragraph";
    case NodeKind::Label: return "label";
    case NodeKind::Button: return "button";
    case NodeKind::ToggleButton: return "toggle-button";
    case NodeKind::Toggle: return "toggle";
    case NodeKind::RadioGroup: return "radio-group";
    case NodeKind::Radio: return "radio";
    case NodeKind::Slider: return "slider";
    case NodeKind::TextField: return "text-field";
    case NodeKind::SecureField: return "secure-field";
    case NodeKind::Input: return "input";
    case NodeKind::SearchField: return "search-field";
    case NodeKind::Textarea: return "textarea";
    case NodeKind::Checkbox: return "checkbox";
    case NodeKind::SwitchControl: return "switch";
    case NodeKind::Progress: return "progress";
    case NodeKind::Divider: return "divider";
    case NodeKind::Scroll: return "scroll";
    case NodeKind::ListContainer: return "list";
    case NodeKind::VirtualList: return "virtual-list";
    case NodeKind::Tabs: return "tabs";
    case NodeKind::BottomTabs: return "bottom-tabs";
    case NodeKind::BottomTab: return "bottom-tab";
    case NodeKind::ButtonGroup: return "button-group";
    case NodeKind::ToggleGroup: return "toggle-group";
    case NodeKind::Spacer: return "spacer";
    case NodeKind::Spinner: return "spinner";
    case NodeKind::Icon: return "icon";
    case NodeKind::Select: return "select";
    case NodeKind::Combobox: return "combobox";
    case NodeKind::DropdownMenu: return "dropdown-menu";
    case NodeKind::ContextMenu: return "context-menu";
    case NodeKind::MenuItem: return "menu-item";
    case NodeKind::ListItem: return "list-item";
    case NodeKind::Avatar: return "avatar";
    case NodeKind::Image: return "image";
    case NodeKind::MediaSurface: return "media-surface";
    case NodeKind::Stepper: return "stepper";
    case NodeKind::Step: return "step";
    case NodeKind::Timeline: return "timeline";
    case NodeKind::TimelineItem: return "timeline-item";
    case NodeKind::InputGroup: return "input-group";
    case NodeKind::InputGroupActions: return "input-group-actions";
    case NodeKind::Breadcrumb: return "breadcrumb";
    case NodeKind::Pagination: return "pagination";
    case NodeKind::Accordion: return "accordion";
    case NodeKind::Table: return "table";
    case NodeKind::TableRow: return "table-row";
    case NodeKind::TableCell: return "table-cell";
    case NodeKind::Tree: return "tree";
    case NodeKind::Resizable: return "resizable";
    case NodeKind::Split: return "split";
    case NodeKind::Dialog: return "dialog";
    case NodeKind::Drawer: return "drawer";
    case NodeKind::Sheet: return "sheet";
    case NodeKind::Tooltip: return "tooltip";
    case NodeKind::Toast: return "toast";
    case NodeKind::Toolbar: return "toolbar";
    case NodeKind::StatusBar: return "status-bar";
  }
  return "unknown";
}

inline bool decodeNodeKind(const char *name, NodeKind *kind) {
  if (name == "root") { *kind = NodeKind::Root; return true; }
  if (name == "row") { *kind = NodeKind::Row; return true; }
  if (name == "column") { *kind = NodeKind::Column; return true; }
  if (name == "grid") { *kind = NodeKind::Grid; return true; }
  if (name == "stack") { *kind = NodeKind::Stack; return true; }
  if (name == "panel") { *kind = NodeKind::Panel; return true; }
  if (name == "card") { *kind = NodeKind::Card; return true; }
  if (name == "alert") { *kind = NodeKind::Alert; return true; }
  if (name == "bubble") { *kind = NodeKind::Bubble; return true; }
  if (name == "box") { *kind = NodeKind::Box; return true; }
  if (name == "text") { *kind = NodeKind::Text; return true; }
  if (name == "heading") { *kind = NodeKind::Heading; return true; }
  if (name == "paragraph") { *kind = NodeKind::Paragraph; return true; }
  if (name == "label") { *kind = NodeKind::Label; return true; }
  if (name == "button") { *kind = NodeKind::Button; return true; }
  if (name == "toggle-button") { *kind = NodeKind::ToggleButton; return true; }
  if (name == "toggle") { *kind = NodeKind::Toggle; return true; }
  if (name == "radio-group") { *kind = NodeKind::RadioGroup; return true; }
  if (name == "radio") { *kind = NodeKind::Radio; return true; }
  if (name == "slider") { *kind = NodeKind::Slider; return true; }
  if (name == "text-field") { *kind = NodeKind::TextField; return true; }
  if (name == "secure-field") { *kind = NodeKind::SecureField; return true; }
  if (name == "input") { *kind = NodeKind::Input; return true; }
  if (name == "search-field") { *kind = NodeKind::SearchField; return true; }
  if (name == "textarea") { *kind = NodeKind::Textarea; return true; }
  if (name == "checkbox") { *kind = NodeKind::Checkbox; return true; }
  if (name == "switch") { *kind = NodeKind::SwitchControl; return true; }
  if (name == "progress") { *kind = NodeKind::Progress; return true; }
  if (name == "divider") { *kind = NodeKind::Divider; return true; }
  if (name == "scroll") { *kind = NodeKind::Scroll; return true; }
  if (name == "list") { *kind = NodeKind::ListContainer; return true; }
  if (name == "virtual-list") { *kind = NodeKind::VirtualList; return true; }
  if (name == "tabs") { *kind = NodeKind::Tabs; return true; }
  if (name == "bottom-tabs") { *kind = NodeKind::BottomTabs; return true; }
  if (name == "bottom-tab") { *kind = NodeKind::BottomTab; return true; }
  if (name == "button-group") { *kind = NodeKind::ButtonGroup; return true; }
  if (name == "toggle-group") { *kind = NodeKind::ToggleGroup; return true; }
  if (name == "spacer") { *kind = NodeKind::Spacer; return true; }
  if (name == "spinner") { *kind = NodeKind::Spinner; return true; }
  if (name == "icon") { *kind = NodeKind::Icon; return true; }
  if (name == "select") { *kind = NodeKind::Select; return true; }
  if (name == "combobox") { *kind = NodeKind::Combobox; return true; }
  if (name == "dropdown-menu") { *kind = NodeKind::DropdownMenu; return true; }
  if (name == "context-menu") { *kind = NodeKind::ContextMenu; return true; }
  if (name == "menu-item") { *kind = NodeKind::MenuItem; return true; }
  if (name == "list-item") { *kind = NodeKind::ListItem; return true; }
  if (name == "avatar") { *kind = NodeKind::Avatar; return true; }
  if (name == "image") { *kind = NodeKind::Image; return true; }
  if (name == "media-surface") { *kind = NodeKind::MediaSurface; return true; }
  if (name == "stepper") { *kind = NodeKind::Stepper; return true; }
  if (name == "step") { *kind = NodeKind::Step; return true; }
  if (name == "timeline") { *kind = NodeKind::Timeline; return true; }
  if (name == "timeline-item") { *kind = NodeKind::TimelineItem; return true; }
  if (name == "input-group") { *kind = NodeKind::InputGroup; return true; }
  if (name == "input-group-actions") { *kind = NodeKind::InputGroupActions; return true; }
  if (name == "breadcrumb") { *kind = NodeKind::Breadcrumb; return true; }
  if (name == "pagination") { *kind = NodeKind::Pagination; return true; }
  if (name == "accordion") { *kind = NodeKind::Accordion; return true; }
  if (name == "table") { *kind = NodeKind::Table; return true; }
  if (name == "table-row") { *kind = NodeKind::TableRow; return true; }
  if (name == "table-cell") { *kind = NodeKind::TableCell; return true; }
  if (name == "tree") { *kind = NodeKind::Tree; return true; }
  if (name == "resizable") { *kind = NodeKind::Resizable; return true; }
  if (name == "split") { *kind = NodeKind::Split; return true; }
  if (name == "dialog") { *kind = NodeKind::Dialog; return true; }
  if (name == "drawer") { *kind = NodeKind::Drawer; return true; }
  if (name == "sheet") { *kind = NodeKind::Sheet; return true; }
  if (name == "tooltip") { *kind = NodeKind::Tooltip; return true; }
  if (name == "toast") { *kind = NodeKind::Toast; return true; }
  if (name == "toolbar") { *kind = NodeKind::Toolbar; return true; }
  if (name == "status-bar") { *kind = NodeKind::StatusBar; return true; }
  return false;
}

inline bool standardNodeName(const char *name) {
  NodeKind ignored;
  return decodeNodeKind(name, &ignored);
}

inline bool containerNodeKind(NodeKind kind) {
  switch (kind) {
    case NodeKind::Root:
    case NodeKind::Row:
    case NodeKind::Column:
    case NodeKind::Grid:
    case NodeKind::Stack:
    case NodeKind::Panel:
    case NodeKind::Card:
    case NodeKind::Alert:
    case NodeKind::Bubble:
    case NodeKind::Box:
    case NodeKind::RadioGroup:
    case NodeKind::Scroll:
    case NodeKind::ListContainer:
    case NodeKind::VirtualList:
    case NodeKind::Tabs:
    case NodeKind::BottomTabs:
    case NodeKind::BottomTab:
    case NodeKind::ButtonGroup:
    case NodeKind::ToggleGroup:
    case NodeKind::DropdownMenu:
    case NodeKind::ContextMenu:
    case NodeKind::MenuItem:
    case NodeKind::ListItem:
    case NodeKind::Stepper:
    case NodeKind::Timeline:
    case NodeKind::InputGroup:
    case NodeKind::InputGroupActions:
    case NodeKind::Breadcrumb:
    case NodeKind::Pagination:
    case NodeKind::Accordion:
    case NodeKind::Table:
    case NodeKind::TableRow:
    case NodeKind::Tree:
    case NodeKind::Resizable:
    case NodeKind::Split:
    case NodeKind::Dialog:
    case NodeKind::Drawer:
    case NodeKind::Sheet:
    case NodeKind::Toast:
    case NodeKind::Toolbar:
    return true;
    default:
    return false;
  }
}

// QML file (inside the Lui module) rendering this node kind.
inline const char *nodeKindComponentName(NodeKind kind) {
  switch (kind) {
    case NodeKind::Root: return "LuiRoot.qml";
    case NodeKind::Row: return "LuiRow.qml";
    case NodeKind::Column: return "LuiColumn.qml";
    case NodeKind::Grid: return "LuiGrid.qml";
    case NodeKind::Stack: return "LuiStack.qml";
    case NodeKind::Panel: return "LuiPanel.qml";
    case NodeKind::Card: return "LuiCard.qml";
    case NodeKind::Alert: return "LuiAlert.qml";
    case NodeKind::Bubble: return "LuiBubble.qml";
    case NodeKind::Box: return "LuiBox.qml";
    case NodeKind::Text: return "LuiText.qml";
    case NodeKind::Heading: return "LuiHeading.qml";
    case NodeKind::Paragraph: return "LuiParagraph.qml";
    case NodeKind::Label: return "LuiLabel.qml";
    case NodeKind::Button: return "LuiButton.qml";
    case NodeKind::ToggleButton: return "LuiToggleButton.qml";
    case NodeKind::Toggle: return "LuiToggle.qml";
    case NodeKind::RadioGroup: return "LuiRadioGroup.qml";
    case NodeKind::Radio: return "LuiRadio.qml";
    case NodeKind::Slider: return "LuiSlider.qml";
    case NodeKind::TextField: return "LuiTextField.qml";
    case NodeKind::SecureField: return "LuiSecureField.qml";
    case NodeKind::Input: return "LuiInput.qml";
    case NodeKind::SearchField: return "LuiSearchField.qml";
    case NodeKind::Textarea: return "LuiTextarea.qml";
    case NodeKind::Checkbox: return "LuiCheckbox.qml";
    case NodeKind::SwitchControl: return "LuiSwitch.qml";
    case NodeKind::Progress: return "LuiProgress.qml";
    case NodeKind::Divider: return "LuiDivider.qml";
    case NodeKind::Scroll: return "LuiScroll.qml";
    case NodeKind::ListContainer: return "LuiList.qml";
    case NodeKind::VirtualList: return "LuiVirtualList.qml";
    case NodeKind::Tabs: return "LuiTabs.qml";
    case NodeKind::BottomTabs: return "LuiBottomTabs.qml";
    case NodeKind::BottomTab: return "LuiBottomTab.qml";
    case NodeKind::ButtonGroup: return "LuiButtonGroup.qml";
    case NodeKind::ToggleGroup: return "LuiToggleGroup.qml";
    case NodeKind::Spacer: return "LuiSpacer.qml";
    case NodeKind::Spinner: return "LuiSpinner.qml";
    case NodeKind::Icon: return "LuiIcon.qml";
    case NodeKind::Select: return "LuiSelect.qml";
    case NodeKind::Combobox: return "LuiCombobox.qml";
    case NodeKind::DropdownMenu: return "LuiDropdownMenu.qml";
    case NodeKind::ContextMenu: return "LuiContextMenu.qml";
    case NodeKind::MenuItem: return "LuiMenuItem.qml";
    case NodeKind::ListItem: return "LuiListItem.qml";
    case NodeKind::Avatar: return "LuiAvatar.qml";
    case NodeKind::Image: return "LuiImage.qml";
    case NodeKind::MediaSurface: return "LuiMediaSurface.qml";
    case NodeKind::Stepper: return "LuiStepper.qml";
    case NodeKind::Step: return "LuiStep.qml";
    case NodeKind::Timeline: return "LuiTimeline.qml";
    case NodeKind::TimelineItem: return "LuiTimelineItem.qml";
    case NodeKind::InputGroup: return "LuiInputGroup.qml";
    case NodeKind::InputGroupActions: return "LuiInputGroupActions.qml";
    case NodeKind::Breadcrumb: return "LuiBreadcrumb.qml";
    case NodeKind::Pagination: return "LuiPagination.qml";
    case NodeKind::Accordion: return "LuiAccordion.qml";
    case NodeKind::Table: return "LuiTable.qml";
    case NodeKind::TableRow: return "LuiTableRow.qml";
    case NodeKind::TableCell: return "LuiTableCell.qml";
    case NodeKind::Tree: return "LuiTree.qml";
    case NodeKind::Resizable: return "LuiResizable.qml";
    case NodeKind::Split: return "LuiSplit.qml";
    case NodeKind::Dialog: return "LuiDialog.qml";
    case NodeKind::Drawer: return "LuiDrawer.qml";
    case NodeKind::Sheet: return "LuiSheet.qml";
    case NodeKind::Tooltip: return "LuiTooltip.qml";
    case NodeKind::Toast: return "LuiToast.qml";
    case NodeKind::Toolbar: return "LuiToolbar.qml";
    case NodeKind::StatusBar: return "LuiStatusBar.qml";
  }
  return "LuiBox.qml";
}

inline const char *propertyWireName(Property property) {
  switch (property) {
    case Property::TextValue: return "text";
    case Property::Enabled: return "enabled";
    case Property::Gap: return "gap";
    case Property::MainAlignment: return "main";
    case Property::CrossAlignment: return "cross";
    case Property::GrowValue: return "grow";
    case Property::GridColumns: return "columns";
    case Property::PaddingValue: return "padding";
    case Property::PaddingHorizontal: return "padding-horizontal";
    case Property::PaddingVertical: return "padding-vertical";
    case Property::BackgroundValue: return "background";
    case Property::ForegroundValue: return "foreground";
    case Property::BorderColorValue: return "border-color";
    case Property::BorderWidth: return "border-width";
    case Property::CornerRadius: return "corner-radius";
    case Property::WidthValue: return "width";
    case Property::HeightValue: return "height";
    case Property::MinWidth: return "min-width";
    case Property::MaxWidth: return "max-width";
    case Property::MinHeight: return "min-height";
    case Property::MaxHeight: return "max-height";
    case Property::ContainerRelativeFrameValue: return "container-relative-frame";
    case Property::ContainerRelativeFrameInset: return "container-relative-frame-inset";
    case Property::PlaceholderValue: return "placeholder";
    case Property::AccessibilityLabel: return "accessibility-label";
    case Property::AccessibilityIdentifier: return "accessibility-identifier";
    case Property::StyleClass: return "style-class";
    case Property::HeadingLevel: return "heading-level";
    case Property::Checked: return "checked";
    case Property::ProgressValue: return "value";
    case Property::OrientationValue: return "orientation";
    case Property::SizeValue: return "size";
    case Property::IconName: return "name";
    case Property::VariantValue: return "variant";
    case Property::InlineIconName: return "icon";
    case Property::IconPlacementValue: return "icon-placement";
    case Property::Selected: return "selected";
    case Property::Autofocus: return "autofocus";
    case Property::SubmitOnEnter: return "submit-on-enter";
    case Property::LongPressEnabled: return "long-press-enabled";
    case Property::ChangeEnabled: return "change-enabled";
    case Property::ToggleEnabled: return "toggle-enabled";
    case Property::PressEnabled: return "press-enabled";
    case Property::SubmitEnabled: return "submit-enabled";
    case Property::DoublePressEnabled: return "double-press-enabled";
    case Property::AppearEnabled: return "appear-enabled";
    case Property::ImageIdValue: return "image";
    case Property::SurfaceIdValue: return "surface";
    case Property::ActiveIndex: return "active";
    case Property::TitleValue: return "title";
    case Property::DescriptionValue: return "description";
    case Property::MetaValue: return "meta";
    case Property::IndicatorValue: return "indicator";
    case Property::Connector: return "connector";
    case Property::SourceX: return "source-x";
    case Property::SourceY: return "source-y";
    case Property::SourceWidth: return "source-width";
    case Property::SourceHeight: return "source-height";
    case Property::AnchorValue: return "anchor";
    case Property::AnchorAlignmentValue: return "anchor-alignment";
    case Property::AnchorOffset: return "anchor-offset";
    case Property::TooltipDelay: return "tooltip-delay";
    case Property::DurationValue: return "duration";
    case Property::TextAlignment: return "text-alignment";
    case Property::RoleValue: return "role";
    case Property::TreeLevel: return "tree-level";
    case Property::Expanded: return "expanded";
    case Property::ResizeDuration: return "resize-duration";
    case Property::ResizeEasing: return "resize-easing";
    case Property::ResizeOrigin: return "resize-origin";
  }
  return "unknown";
}

inline bool decodePropertyWireName(const char *name, Property *property) {
  if (name == "text") { *property = Property::TextValue; return true; }
  if (name == "enabled") { *property = Property::Enabled; return true; }
  if (name == "gap") { *property = Property::Gap; return true; }
  if (name == "main") { *property = Property::MainAlignment; return true; }
  if (name == "cross") { *property = Property::CrossAlignment; return true; }
  if (name == "grow") { *property = Property::GrowValue; return true; }
  if (name == "columns") { *property = Property::GridColumns; return true; }
  if (name == "padding") { *property = Property::PaddingValue; return true; }
  if (name == "padding-horizontal") { *property = Property::PaddingHorizontal; return true; }
  if (name == "padding-vertical") { *property = Property::PaddingVertical; return true; }
  if (name == "background") { *property = Property::BackgroundValue; return true; }
  if (name == "foreground") { *property = Property::ForegroundValue; return true; }
  if (name == "border-color") { *property = Property::BorderColorValue; return true; }
  if (name == "border-width") { *property = Property::BorderWidth; return true; }
  if (name == "corner-radius") { *property = Property::CornerRadius; return true; }
  if (name == "width") { *property = Property::WidthValue; return true; }
  if (name == "height") { *property = Property::HeightValue; return true; }
  if (name == "min-width") { *property = Property::MinWidth; return true; }
  if (name == "max-width") { *property = Property::MaxWidth; return true; }
  if (name == "min-height") { *property = Property::MinHeight; return true; }
  if (name == "max-height") { *property = Property::MaxHeight; return true; }
  if (name == "container-relative-frame") { *property = Property::ContainerRelativeFrameValue; return true; }
  if (name == "container-relative-frame-inset") { *property = Property::ContainerRelativeFrameInset; return true; }
  if (name == "placeholder") { *property = Property::PlaceholderValue; return true; }
  if (name == "accessibility-label") { *property = Property::AccessibilityLabel; return true; }
  if (name == "accessibility-identifier") { *property = Property::AccessibilityIdentifier; return true; }
  if (name == "style-class") { *property = Property::StyleClass; return true; }
  if (name == "heading-level") { *property = Property::HeadingLevel; return true; }
  if (name == "checked") { *property = Property::Checked; return true; }
  if (name == "value") { *property = Property::ProgressValue; return true; }
  if (name == "orientation") { *property = Property::OrientationValue; return true; }
  if (name == "size") { *property = Property::SizeValue; return true; }
  if (name == "name") { *property = Property::IconName; return true; }
  if (name == "variant") { *property = Property::VariantValue; return true; }
  if (name == "icon") { *property = Property::InlineIconName; return true; }
  if (name == "icon-placement") { *property = Property::IconPlacementValue; return true; }
  if (name == "selected") { *property = Property::Selected; return true; }
  if (name == "autofocus") { *property = Property::Autofocus; return true; }
  if (name == "submit-on-enter") { *property = Property::SubmitOnEnter; return true; }
  if (name == "long-press-enabled") { *property = Property::LongPressEnabled; return true; }
  if (name == "change-enabled") { *property = Property::ChangeEnabled; return true; }
  if (name == "toggle-enabled") { *property = Property::ToggleEnabled; return true; }
  if (name == "press-enabled") { *property = Property::PressEnabled; return true; }
  if (name == "submit-enabled") { *property = Property::SubmitEnabled; return true; }
  if (name == "double-press-enabled") { *property = Property::DoublePressEnabled; return true; }
  if (name == "appear-enabled") { *property = Property::AppearEnabled; return true; }
  if (name == "image") { *property = Property::ImageIdValue; return true; }
  if (name == "surface") { *property = Property::SurfaceIdValue; return true; }
  if (name == "active") { *property = Property::ActiveIndex; return true; }
  if (name == "title") { *property = Property::TitleValue; return true; }
  if (name == "description") { *property = Property::DescriptionValue; return true; }
  if (name == "meta") { *property = Property::MetaValue; return true; }
  if (name == "indicator") { *property = Property::IndicatorValue; return true; }
  if (name == "connector") { *property = Property::Connector; return true; }
  if (name == "source-x") { *property = Property::SourceX; return true; }
  if (name == "source-y") { *property = Property::SourceY; return true; }
  if (name == "source-width") { *property = Property::SourceWidth; return true; }
  if (name == "source-height") { *property = Property::SourceHeight; return true; }
  if (name == "anchor") { *property = Property::AnchorValue; return true; }
  if (name == "anchor-alignment") { *property = Property::AnchorAlignmentValue; return true; }
  if (name == "anchor-offset") { *property = Property::AnchorOffset; return true; }
  if (name == "tooltip-delay") { *property = Property::TooltipDelay; return true; }
  if (name == "duration") { *property = Property::DurationValue; return true; }
  if (name == "text-alignment") { *property = Property::TextAlignment; return true; }
  if (name == "role") { *property = Property::RoleValue; return true; }
  if (name == "tree-level") { *property = Property::TreeLevel; return true; }
  if (name == "expanded") { *property = Property::Expanded; return true; }
  if (name == "resize-duration") { *property = Property::ResizeDuration; return true; }
  if (name == "resize-easing") { *property = Property::ResizeEasing; return true; }
  if (name == "resize-origin") { *property = Property::ResizeOrigin; return true; }
  return false;
}

} // namespace LUI
