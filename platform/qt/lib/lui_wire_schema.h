// Generated from schema/components.json. Do not edit by hand.
#pragma once

#include <cstring>

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
  if (std::strcmp(name, "root") == 0) { *kind = NodeKind::Root; return true; }
  if (std::strcmp(name, "row") == 0) { *kind = NodeKind::Row; return true; }
  if (std::strcmp(name, "column") == 0) { *kind = NodeKind::Column; return true; }
  if (std::strcmp(name, "grid") == 0) { *kind = NodeKind::Grid; return true; }
  if (std::strcmp(name, "stack") == 0) { *kind = NodeKind::Stack; return true; }
  if (std::strcmp(name, "panel") == 0) { *kind = NodeKind::Panel; return true; }
  if (std::strcmp(name, "card") == 0) { *kind = NodeKind::Card; return true; }
  if (std::strcmp(name, "alert") == 0) { *kind = NodeKind::Alert; return true; }
  if (std::strcmp(name, "bubble") == 0) { *kind = NodeKind::Bubble; return true; }
  if (std::strcmp(name, "box") == 0) { *kind = NodeKind::Box; return true; }
  if (std::strcmp(name, "text") == 0) { *kind = NodeKind::Text; return true; }
  if (std::strcmp(name, "heading") == 0) { *kind = NodeKind::Heading; return true; }
  if (std::strcmp(name, "paragraph") == 0) { *kind = NodeKind::Paragraph; return true; }
  if (std::strcmp(name, "label") == 0) { *kind = NodeKind::Label; return true; }
  if (std::strcmp(name, "button") == 0) { *kind = NodeKind::Button; return true; }
  if (std::strcmp(name, "toggle-button") == 0) { *kind = NodeKind::ToggleButton; return true; }
  if (std::strcmp(name, "toggle") == 0) { *kind = NodeKind::Toggle; return true; }
  if (std::strcmp(name, "radio-group") == 0) { *kind = NodeKind::RadioGroup; return true; }
  if (std::strcmp(name, "radio") == 0) { *kind = NodeKind::Radio; return true; }
  if (std::strcmp(name, "slider") == 0) { *kind = NodeKind::Slider; return true; }
  if (std::strcmp(name, "text-field") == 0) { *kind = NodeKind::TextField; return true; }
  if (std::strcmp(name, "secure-field") == 0) { *kind = NodeKind::SecureField; return true; }
  if (std::strcmp(name, "input") == 0) { *kind = NodeKind::Input; return true; }
  if (std::strcmp(name, "search-field") == 0) { *kind = NodeKind::SearchField; return true; }
  if (std::strcmp(name, "textarea") == 0) { *kind = NodeKind::Textarea; return true; }
  if (std::strcmp(name, "checkbox") == 0) { *kind = NodeKind::Checkbox; return true; }
  if (std::strcmp(name, "switch") == 0) { *kind = NodeKind::SwitchControl; return true; }
  if (std::strcmp(name, "progress") == 0) { *kind = NodeKind::Progress; return true; }
  if (std::strcmp(name, "divider") == 0) { *kind = NodeKind::Divider; return true; }
  if (std::strcmp(name, "scroll") == 0) { *kind = NodeKind::Scroll; return true; }
  if (std::strcmp(name, "list") == 0) { *kind = NodeKind::ListContainer; return true; }
  if (std::strcmp(name, "virtual-list") == 0) { *kind = NodeKind::VirtualList; return true; }
  if (std::strcmp(name, "tabs") == 0) { *kind = NodeKind::Tabs; return true; }
  if (std::strcmp(name, "bottom-tabs") == 0) { *kind = NodeKind::BottomTabs; return true; }
  if (std::strcmp(name, "bottom-tab") == 0) { *kind = NodeKind::BottomTab; return true; }
  if (std::strcmp(name, "button-group") == 0) { *kind = NodeKind::ButtonGroup; return true; }
  if (std::strcmp(name, "toggle-group") == 0) { *kind = NodeKind::ToggleGroup; return true; }
  if (std::strcmp(name, "spacer") == 0) { *kind = NodeKind::Spacer; return true; }
  if (std::strcmp(name, "spinner") == 0) { *kind = NodeKind::Spinner; return true; }
  if (std::strcmp(name, "icon") == 0) { *kind = NodeKind::Icon; return true; }
  if (std::strcmp(name, "select") == 0) { *kind = NodeKind::Select; return true; }
  if (std::strcmp(name, "combobox") == 0) { *kind = NodeKind::Combobox; return true; }
  if (std::strcmp(name, "dropdown-menu") == 0) { *kind = NodeKind::DropdownMenu; return true; }
  if (std::strcmp(name, "context-menu") == 0) { *kind = NodeKind::ContextMenu; return true; }
  if (std::strcmp(name, "menu-item") == 0) { *kind = NodeKind::MenuItem; return true; }
  if (std::strcmp(name, "list-item") == 0) { *kind = NodeKind::ListItem; return true; }
  if (std::strcmp(name, "avatar") == 0) { *kind = NodeKind::Avatar; return true; }
  if (std::strcmp(name, "image") == 0) { *kind = NodeKind::Image; return true; }
  if (std::strcmp(name, "media-surface") == 0) { *kind = NodeKind::MediaSurface; return true; }
  if (std::strcmp(name, "stepper") == 0) { *kind = NodeKind::Stepper; return true; }
  if (std::strcmp(name, "step") == 0) { *kind = NodeKind::Step; return true; }
  if (std::strcmp(name, "timeline") == 0) { *kind = NodeKind::Timeline; return true; }
  if (std::strcmp(name, "timeline-item") == 0) { *kind = NodeKind::TimelineItem; return true; }
  if (std::strcmp(name, "input-group") == 0) { *kind = NodeKind::InputGroup; return true; }
  if (std::strcmp(name, "input-group-actions") == 0) { *kind = NodeKind::InputGroupActions; return true; }
  if (std::strcmp(name, "breadcrumb") == 0) { *kind = NodeKind::Breadcrumb; return true; }
  if (std::strcmp(name, "pagination") == 0) { *kind = NodeKind::Pagination; return true; }
  if (std::strcmp(name, "accordion") == 0) { *kind = NodeKind::Accordion; return true; }
  if (std::strcmp(name, "table") == 0) { *kind = NodeKind::Table; return true; }
  if (std::strcmp(name, "table-row") == 0) { *kind = NodeKind::TableRow; return true; }
  if (std::strcmp(name, "table-cell") == 0) { *kind = NodeKind::TableCell; return true; }
  if (std::strcmp(name, "tree") == 0) { *kind = NodeKind::Tree; return true; }
  if (std::strcmp(name, "resizable") == 0) { *kind = NodeKind::Resizable; return true; }
  if (std::strcmp(name, "split") == 0) { *kind = NodeKind::Split; return true; }
  if (std::strcmp(name, "dialog") == 0) { *kind = NodeKind::Dialog; return true; }
  if (std::strcmp(name, "drawer") == 0) { *kind = NodeKind::Drawer; return true; }
  if (std::strcmp(name, "sheet") == 0) { *kind = NodeKind::Sheet; return true; }
  if (std::strcmp(name, "tooltip") == 0) { *kind = NodeKind::Tooltip; return true; }
  if (std::strcmp(name, "toast") == 0) { *kind = NodeKind::Toast; return true; }
  if (std::strcmp(name, "toolbar") == 0) { *kind = NodeKind::Toolbar; return true; }
  if (std::strcmp(name, "status-bar") == 0) { *kind = NodeKind::StatusBar; return true; }
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
  if (std::strcmp(name, "text") == 0) { *property = Property::TextValue; return true; }
  if (std::strcmp(name, "enabled") == 0) { *property = Property::Enabled; return true; }
  if (std::strcmp(name, "gap") == 0) { *property = Property::Gap; return true; }
  if (std::strcmp(name, "main") == 0) { *property = Property::MainAlignment; return true; }
  if (std::strcmp(name, "cross") == 0) { *property = Property::CrossAlignment; return true; }
  if (std::strcmp(name, "grow") == 0) { *property = Property::GrowValue; return true; }
  if (std::strcmp(name, "columns") == 0) { *property = Property::GridColumns; return true; }
  if (std::strcmp(name, "padding") == 0) { *property = Property::PaddingValue; return true; }
  if (std::strcmp(name, "padding-horizontal") == 0) { *property = Property::PaddingHorizontal; return true; }
  if (std::strcmp(name, "padding-vertical") == 0) { *property = Property::PaddingVertical; return true; }
  if (std::strcmp(name, "background") == 0) { *property = Property::BackgroundValue; return true; }
  if (std::strcmp(name, "foreground") == 0) { *property = Property::ForegroundValue; return true; }
  if (std::strcmp(name, "border-color") == 0) { *property = Property::BorderColorValue; return true; }
  if (std::strcmp(name, "border-width") == 0) { *property = Property::BorderWidth; return true; }
  if (std::strcmp(name, "corner-radius") == 0) { *property = Property::CornerRadius; return true; }
  if (std::strcmp(name, "width") == 0) { *property = Property::WidthValue; return true; }
  if (std::strcmp(name, "height") == 0) { *property = Property::HeightValue; return true; }
  if (std::strcmp(name, "min-width") == 0) { *property = Property::MinWidth; return true; }
  if (std::strcmp(name, "max-width") == 0) { *property = Property::MaxWidth; return true; }
  if (std::strcmp(name, "min-height") == 0) { *property = Property::MinHeight; return true; }
  if (std::strcmp(name, "max-height") == 0) { *property = Property::MaxHeight; return true; }
  if (std::strcmp(name, "container-relative-frame") == 0) { *property = Property::ContainerRelativeFrameValue; return true; }
  if (std::strcmp(name, "container-relative-frame-inset") == 0) { *property = Property::ContainerRelativeFrameInset; return true; }
  if (std::strcmp(name, "placeholder") == 0) { *property = Property::PlaceholderValue; return true; }
  if (std::strcmp(name, "accessibility-label") == 0) { *property = Property::AccessibilityLabel; return true; }
  if (std::strcmp(name, "accessibility-identifier") == 0) { *property = Property::AccessibilityIdentifier; return true; }
  if (std::strcmp(name, "style-class") == 0) { *property = Property::StyleClass; return true; }
  if (std::strcmp(name, "heading-level") == 0) { *property = Property::HeadingLevel; return true; }
  if (std::strcmp(name, "checked") == 0) { *property = Property::Checked; return true; }
  if (std::strcmp(name, "value") == 0) { *property = Property::ProgressValue; return true; }
  if (std::strcmp(name, "orientation") == 0) { *property = Property::OrientationValue; return true; }
  if (std::strcmp(name, "size") == 0) { *property = Property::SizeValue; return true; }
  if (std::strcmp(name, "name") == 0) { *property = Property::IconName; return true; }
  if (std::strcmp(name, "variant") == 0) { *property = Property::VariantValue; return true; }
  if (std::strcmp(name, "icon") == 0) { *property = Property::InlineIconName; return true; }
  if (std::strcmp(name, "icon-placement") == 0) { *property = Property::IconPlacementValue; return true; }
  if (std::strcmp(name, "selected") == 0) { *property = Property::Selected; return true; }
  if (std::strcmp(name, "autofocus") == 0) { *property = Property::Autofocus; return true; }
  if (std::strcmp(name, "submit-on-enter") == 0) { *property = Property::SubmitOnEnter; return true; }
  if (std::strcmp(name, "long-press-enabled") == 0) { *property = Property::LongPressEnabled; return true; }
  if (std::strcmp(name, "change-enabled") == 0) { *property = Property::ChangeEnabled; return true; }
  if (std::strcmp(name, "toggle-enabled") == 0) { *property = Property::ToggleEnabled; return true; }
  if (std::strcmp(name, "press-enabled") == 0) { *property = Property::PressEnabled; return true; }
  if (std::strcmp(name, "submit-enabled") == 0) { *property = Property::SubmitEnabled; return true; }
  if (std::strcmp(name, "double-press-enabled") == 0) { *property = Property::DoublePressEnabled; return true; }
  if (std::strcmp(name, "appear-enabled") == 0) { *property = Property::AppearEnabled; return true; }
  if (std::strcmp(name, "image") == 0) { *property = Property::ImageIdValue; return true; }
  if (std::strcmp(name, "surface") == 0) { *property = Property::SurfaceIdValue; return true; }
  if (std::strcmp(name, "active") == 0) { *property = Property::ActiveIndex; return true; }
  if (std::strcmp(name, "title") == 0) { *property = Property::TitleValue; return true; }
  if (std::strcmp(name, "description") == 0) { *property = Property::DescriptionValue; return true; }
  if (std::strcmp(name, "meta") == 0) { *property = Property::MetaValue; return true; }
  if (std::strcmp(name, "indicator") == 0) { *property = Property::IndicatorValue; return true; }
  if (std::strcmp(name, "connector") == 0) { *property = Property::Connector; return true; }
  if (std::strcmp(name, "source-x") == 0) { *property = Property::SourceX; return true; }
  if (std::strcmp(name, "source-y") == 0) { *property = Property::SourceY; return true; }
  if (std::strcmp(name, "source-width") == 0) { *property = Property::SourceWidth; return true; }
  if (std::strcmp(name, "source-height") == 0) { *property = Property::SourceHeight; return true; }
  if (std::strcmp(name, "anchor") == 0) { *property = Property::AnchorValue; return true; }
  if (std::strcmp(name, "anchor-alignment") == 0) { *property = Property::AnchorAlignmentValue; return true; }
  if (std::strcmp(name, "anchor-offset") == 0) { *property = Property::AnchorOffset; return true; }
  if (std::strcmp(name, "tooltip-delay") == 0) { *property = Property::TooltipDelay; return true; }
  if (std::strcmp(name, "duration") == 0) { *property = Property::DurationValue; return true; }
  if (std::strcmp(name, "text-alignment") == 0) { *property = Property::TextAlignment; return true; }
  if (std::strcmp(name, "role") == 0) { *property = Property::RoleValue; return true; }
  if (std::strcmp(name, "tree-level") == 0) { *property = Property::TreeLevel; return true; }
  if (std::strcmp(name, "expanded") == 0) { *property = Property::Expanded; return true; }
  if (std::strcmp(name, "resize-duration") == 0) { *property = Property::ResizeDuration; return true; }
  if (std::strcmp(name, "resize-easing") == 0) { *property = Property::ResizeEasing; return true; }
  if (std::strcmp(name, "resize-origin") == 0) { *property = Property::ResizeOrigin; return true; }
  return false;
}

} // namespace LUI
