// Ported from src/lui_protocol.ml — keep the two implementations in sync.

#include "lui_schema.h"

#include <QSet>
#include <cmath>
#include <cstring>

namespace LUI {

namespace {

bool oneOf(NodeKind kind, std::initializer_list<NodeKind> kinds) {
  for (NodeKind candidate : kinds) {
    if (kind == candidate) return true;
  }
  return false;
}

bool inSet(const QString &value, std::initializer_list<const char *> options) {
  for (const char *option : options) {
    if (value == QLatin1String(option)) return true;
  }
  return false;
}

bool isString(const QVariant &value) {
  return value.typeId() == QMetaType::QString;
}

bool isBool(const QVariant &value) {
  return value.typeId() == QMetaType::Bool;
}

bool isNumeric(const QVariant &value) {
  switch (value.typeId()) {
  case QMetaType::Double:
  case QMetaType::Float:
  case QMetaType::Int:
  case QMetaType::UInt:
  case QMetaType::LongLong:
  case QMetaType::ULongLong:
  case QMetaType::Short:
  case QMetaType::UShort:
    return std::isfinite(value.toDouble());
  default:
    return false;
  }
}

// The wire sends IntValue without a fraction and FloatValue with one; JSON
// numbers lose that distinction, so an integral double satisfies IntValue
// slots and any finite double satisfies FloatValue slots.
bool isIntValue(const QVariant &value, int *out = nullptr) {
  if (!isNumeric(value)) return false;
  const double number = value.toDouble();
  if (std::floor(number) != number || number < -2147483648.0 ||
      number > 2147483647.0) {
    return false;
  }
  if (out != nullptr) *out = static_cast<int>(number);
  return true;
}

int intProperty(const QVariantMap &properties, const char *name,
                int fallback) {
  const QVariant value = properties.value(QLatin1String(name));
  int number = 0;
  return isIntValue(value, &number) ? number : fallback;
}

bool trueProperty(const QVariantMap &properties, const char *name) {
  const QVariant value = properties.value(QLatin1String(name));
  return value.typeId() == QMetaType::Bool && value.toBool();
}

QString stringPropertyOr(const QVariantMap &properties, const char *name,
                         const QString &fallback) {
  const QVariant value = properties.value(QLatin1String(name));
  return isString(value) ? value.toString() : fallback;
}

bool stringPropertyNonempty(const QVariantMap &properties, const char *name) {
  const QVariant value = properties.value(QLatin1String(name));
  return isString(value) && !value.toString().isEmpty();
}

bool treeitemProperties(const QVariantMap &properties) {
  return properties.value(QStringLiteral("role")) ==
         QStringLiteral("treeitem");
}

bool sizeAxisSupported(const QVariantMap &properties, const char *fixedName,
                       const char *minName, const char *maxName) {
  const int minimum = intProperty(properties, minName, 0);
  const int fixed = intProperty(properties, fixedName, minimum);
  if (fixed < minimum) return false;
  const QVariant maximum = properties.value(QLatin1String(maxName));
  if (!maximum.isValid()) return true;
  int maxValue = 0;
  return isIntValue(maximum, &maxValue) && minimum <= maxValue &&
         fixed <= maxValue;
}

} // namespace

bool modalSurface(NodeKind kind) {
  return oneOf(kind, {NodeKind::Dialog, NodeKind::Drawer, NodeKind::Sheet});
}

bool treeRowKind(NodeKind kind) {
  return oneOf(kind, {NodeKind::Row, NodeKind::Column, NodeKind::Panel,
                      NodeKind::Card, NodeKind::Box, NodeKind::ListItem});
}

bool contextMenuHostKind(NodeKind kind) {
  return oneOf(kind,
               {NodeKind::Button, NodeKind::ToggleButton, NodeKind::Toggle,
                NodeKind::Radio, NodeKind::Slider, NodeKind::TextField,
                NodeKind::SecureField, NodeKind::Input, NodeKind::SearchField,
                NodeKind::Textarea, NodeKind::Checkbox, NodeKind::SwitchControl,
                NodeKind::Select, NodeKind::Combobox, NodeKind::MenuItem,
                NodeKind::ListItem, NodeKind::Accordion, NodeKind::Text,
                NodeKind::TableCell});
}

bool contextMenuLeafHostKind(NodeKind kind) {
  return oneOf(kind,
               {NodeKind::Button, NodeKind::ToggleButton, NodeKind::Toggle,
                NodeKind::Radio, NodeKind::Slider, NodeKind::TextField,
                NodeKind::SecureField, NodeKind::Input, NodeKind::SearchField,
                NodeKind::Textarea, NodeKind::Checkbox, NodeKind::SwitchControl,
                NodeKind::Select, NodeKind::Combobox, NodeKind::MenuItem,
                NodeKind::Text, NodeKind::TableCell});
}

bool horizontalContainer(NodeKind kind) {
  return oneOf(kind, {NodeKind::Tabs, NodeKind::ButtonGroup,
                      NodeKind::ToggleGroup, NodeKind::Breadcrumb,
                      NodeKind::Pagination});
}

bool buttonKind(NodeKind kind) {
  return kind == NodeKind::Button || kind == NodeKind::ToggleButton;
}

bool textControlKind(NodeKind kind) {
  return oneOf(kind, {NodeKind::TextField, NodeKind::SecureField,
                      NodeKind::Input, NodeKind::SearchField,
                      NodeKind::Textarea, NodeKind::Combobox});
}

bool horizontalGroupChild(NodeKind group, NodeKind child) {
  switch (group) {
  case NodeKind::Tabs:
  case NodeKind::Breadcrumb:
  case NodeKind::Pagination:
    return child == NodeKind::Button;
  case NodeKind::ButtonGroup:
    return buttonKind(child);
  case NodeKind::ToggleGroup:
    return child == NodeKind::ToggleButton;
  default:
    return false;
  }
}

bool toolbarChild(NodeKind kind) {
  return oneOf(kind,
               {NodeKind::Button, NodeKind::ToggleButton, NodeKind::ButtonGroup,
                NodeKind::ToggleGroup, NodeKind::Checkbox,
                NodeKind::SwitchControl, NodeKind::Toggle,
                NodeKind::RadioGroup, NodeKind::Select, NodeKind::Combobox,
                NodeKind::TextField, NodeKind::SecureField, NodeKind::Input,
                NodeKind::SearchField, NodeKind::MenuItem, NodeKind::Divider});
}

bool canContainChildren(NodeKind kind) {
  if (horizontalContainer(kind) || contextMenuLeafHostKind(kind)) return true;
  return oneOf(kind,
               {NodeKind::Root, NodeKind::Row, NodeKind::Column,
                NodeKind::Grid, NodeKind::Stack, NodeKind::Panel,
                NodeKind::Card, NodeKind::Box, NodeKind::Scroll,
                NodeKind::ListContainer, NodeKind::VirtualList,
                NodeKind::RadioGroup, NodeKind::DropdownMenu,
                NodeKind::ContextMenu, NodeKind::ListItem,
                NodeKind::Dialog, NodeKind::Drawer, NodeKind::Sheet,
                NodeKind::Accordion, NodeKind::Table, NodeKind::TableRow,
                NodeKind::Tree, NodeKind::Resizable, NodeKind::Split,
                NodeKind::Stepper, NodeKind::Timeline, NodeKind::InputGroup,
                NodeKind::InputGroupActions, NodeKind::Toast,
                NodeKind::Toolbar, NodeKind::Alert, NodeKind::Bubble,
                NodeKind::BottomTabs, NodeKind::BottomTab});
}

bool acceptsExtensionChildren(NodeKind kind) {
  return oneOf(kind,
               {NodeKind::Root, NodeKind::Row, NodeKind::Column,
                NodeKind::Grid, NodeKind::Stack, NodeKind::Panel,
                NodeKind::Card, NodeKind::Box, NodeKind::Scroll,
                NodeKind::ListContainer, NodeKind::VirtualList,
                NodeKind::ListItem, NodeKind::Dialog, NodeKind::Sheet,
                NodeKind::Accordion, NodeKind::Resizable, NodeKind::Split,
                NodeKind::Drawer, NodeKind::Alert, NodeKind::Bubble,
                NodeKind::Toast, NodeKind::Toolbar, NodeKind::BottomTab});
}

bool childKindSupported(NodeKind parent, NodeKind child) {
  if (child == NodeKind::Root) return false;
  if (parent == NodeKind::Root) return true;
  if (parent == NodeKind::MenuItem) {
    return child == NodeKind::ContextMenu || child == NodeKind::DropdownMenu;
  }
  if (contextMenuLeafHostKind(parent)) return child == NodeKind::ContextMenu;
  switch (parent) {
  case NodeKind::Table:
    return child == NodeKind::TableRow;
  case NodeKind::TableRow:
    return child == NodeKind::TableCell;
  case NodeKind::BottomTabs:
    return child == NodeKind::BottomTab;
  case NodeKind::BottomTab:
    return child != NodeKind::BottomTab;
  case NodeKind::Tree:
    return treeRowKind(child) || child == NodeKind::VirtualList;
  case NodeKind::Stepper:
    return child == NodeKind::Step;
  case NodeKind::Timeline:
    return child == NodeKind::TimelineItem;
  case NodeKind::InputGroup:
    return child == NodeKind::Textarea ||
           child == NodeKind::InputGroupActions;
  case NodeKind::Toolbar:
    return toolbarChild(child);
  case NodeKind::DropdownMenu:
  case NodeKind::ContextMenu:
    return child == NodeKind::MenuItem || child == NodeKind::Divider;
  default:
    return true;
  }
}

bool eventSupported(NodeKind kind, Event event) {
  switch (event) {
  case Event::Press:
    return oneOf(kind, {NodeKind::Button, NodeKind::Radio, NodeKind::Select,
                        NodeKind::Combobox, NodeKind::MenuItem,
                        NodeKind::ListItem, NodeKind::Text,
                        NodeKind::TableCell, NodeKind::TimelineItem,
                        NodeKind::BottomTab});
  case Event::LongPress:
    return oneOf(kind,
                 {NodeKind::Button, NodeKind::ToggleButton,
                  NodeKind::ListItem});
  case Event::TextChanged:
    return oneOf(kind, {NodeKind::TextField, NodeKind::SecureField,
                        NodeKind::Input, NodeKind::SearchField,
                        NodeKind::Textarea, NodeKind::Combobox});
  case Event::Submit:
    return oneOf(kind, {NodeKind::TextField, NodeKind::SecureField,
                        NodeKind::Input, NodeKind::SearchField,
                        NodeKind::Textarea, NodeKind::Combobox,
                        NodeKind::ListItem});
  case Event::ToggleChanged:
    return oneOf(kind, {NodeKind::ToggleButton, NodeKind::Checkbox,
                        NodeKind::SwitchControl, NodeKind::Toggle,
                        NodeKind::Radio, NodeKind::Accordion,
                        NodeKind::Drawer});
  case Event::Change:
    return kind == NodeKind::Radio;
  case Event::ValueChanged:
    return kind == NodeKind::Slider || kind == NodeKind::Split;
  case Event::Dismiss:
    return oneOf(kind, {NodeKind::Select, NodeKind::Combobox,
                        NodeKind::DropdownMenu, NodeKind::Toast,
                        NodeKind::Dialog, NodeKind::Drawer, NodeKind::Sheet});
  case Event::DoublePress:
    return kind == NodeKind::ListItem;
  case Event::Appear:
    return kind != NodeKind::Root;
  }
  return false;
}

bool slugSegment(const QString &value) {
  const int length = value.size();
  if (length == 0) return false;
  const auto slugChar = [](QChar c) {
    return (c >= u'a' && c <= u'z') || (c >= u'0' && c <= u'9');
  };
  if (!slugChar(value.at(0)) || !slugChar(value.at(length - 1))) return false;
  for (int index = 0; index < length; ++index) {
    const QChar c = value.at(index);
    if (slugChar(c)) continue;
    // A '-' must be followed by a slug char; the final char is known to be
    // one, so index + 1 < length here.
    if (c != u'-' || index + 1 >= length || !slugChar(value.at(index + 1))) {
      return false;
    }
  }
  return true;
}

bool builtInIconName(const QString &value) {
  static const QSet<QString> names = {
      QStringLiteral("alert"),           QStringLiteral("archive"),
      QStringLiteral("arrow-down"),      QStringLiteral("arrow-right"),
      QStringLiteral("arrow-up"),        QStringLiteral("check"),
      QStringLiteral("check-circle"),    QStringLiteral("chevron-down"),
      QStringLiteral("chevron-left"),    QStringLiteral("chevron-right"),
      QStringLiteral("chevron-up"),      QStringLiteral("circle-dot"),
      QStringLiteral("clock"),           QStringLiteral("copy"),
      QStringLiteral("download"),        QStringLiteral("edit"),
      QStringLiteral("ellipsis"),        QStringLiteral("external-link"),
      QStringLiteral("eye"),             QStringLiteral("file-text"),
      QStringLiteral("folder"),          QStringLiteral("folder-open"),
      QStringLiteral("git-branch"),      QStringLiteral("git-merge"),
      QStringLiteral("git-pull-request"), QStringLiteral("info"),
      QStringLiteral("menu"),            QStringLiteral("mic"),
      QStringLiteral("moon"),            QStringLiteral("music"),
      QStringLiteral("panel-left"),      QStringLiteral("panel-right"),
      QStringLiteral("pause"),           QStringLiteral("play"),
      QStringLiteral("plus"),            QStringLiteral("refresh-cw"),
      QStringLiteral("repeat"),          QStringLiteral("save"),
      QStringLiteral("search"),          QStringLiteral("send"),
      QStringLiteral("settings"),        QStringLiteral("shuffle"),
      QStringLiteral("skip-back"),       QStringLiteral("skip-forward"),
      QStringLiteral("sun"),             QStringLiteral("terminal"),
      QStringLiteral("trash"),           QStringLiteral("volume"),
      QStringLiteral("wrench"),          QStringLiteral("x"),
      QStringLiteral("x-circle"),
  };
  return names.contains(value);
}

bool customIconName(const QString &value) {
  const QString prefix = QStringLiteral("app:");
  return value.size() > prefix.size() && value.startsWith(prefix) &&
         slugSegment(value.mid(prefix.size()));
}

bool iconName(const QString &value) {
  return builtInIconName(value) || customIconName(value);
}

bool decodeProperty(const QString &wire, Property *property) {
  return decodePropertyWireName(qPrintable(wire), property);
}

namespace {

bool mainAlignmentSupported(const QString &value) {
  return inSet(value, {"start", "center", "end", "space_between"});
}

bool crossAlignmentSupported(const QString &value) {
  return inSet(value, {"stretch", "start", "center", "end"});
}

bool orientationSupported(const QString &value) {
  return inSet(value, {"horizontal", "vertical"});
}

bool controlSizeSupported(const QString &value) {
  return inSet(value, {"default", "sm", "lg", "icon"});
}

bool buttonVariantSupported(const QString &value) {
  return inSet(value,
               {"default", "primary", "secondary", "outline", "ghost",
                "destructive"});
}

bool iconPlacementSupported(const QString &value) {
  return inSet(value, {"leading", "trailing", "top"});
}

bool containerRelativeFrameSupported(const QString &value) {
  return inSet(value, {"horizontal", "vertical", "both", "min-horizontal",
                       "min-vertical", "min-both"});
}

bool commonPropertySupported(NodeKind kind, Property property) {
  switch (property) {
  case Property::MainAlignment:
  case Property::CrossAlignment:
    return oneOf(kind, {NodeKind::Row, NodeKind::Column,
                        NodeKind::ListContainer, NodeKind::VirtualList,
                        NodeKind::Card, NodeKind::Panel, NodeKind::Box}) ||
           horizontalContainer(kind);
  case Property::GrowValue:
    return kind != NodeKind::Avatar && !modalSurface(kind) &&
           kind != NodeKind::Tooltip;
  case Property::GridColumns:
    return kind == NodeKind::Grid;
  case Property::PaddingValue:
    return kind != NodeKind::Avatar && kind != NodeKind::Tooltip;
  case Property::PaddingHorizontal:
    return oneOf(kind, {NodeKind::Row, NodeKind::Column, NodeKind::Grid,
                        NodeKind::Box, NodeKind::Button, NodeKind::Card,
                        NodeKind::Panel, NodeKind::Scroll});
  case Property::PaddingVertical:
    return oneOf(kind, {NodeKind::Row, NodeKind::Column, NodeKind::Grid,
                        NodeKind::Box, NodeKind::Card, NodeKind::Panel,
                        NodeKind::Scroll});
  case Property::BackgroundValue:
  case Property::BorderColorValue:
  case Property::BorderWidth:
  case Property::CornerRadius:
    return !modalSurface(kind) && kind != NodeKind::Tooltip;
  case Property::ForegroundValue:
    return oneOf(kind,
                 {NodeKind::Row, NodeKind::Column, NodeKind::Grid,
                  NodeKind::Box, NodeKind::Panel, NodeKind::Card,
                  NodeKind::Stack, NodeKind::Scroll, NodeKind::Avatar,
                  NodeKind::Text, NodeKind::Heading, NodeKind::Paragraph,
                  NodeKind::Label, NodeKind::Button, NodeKind::ToggleButton,
                  NodeKind::TextField, NodeKind::SecureField, NodeKind::Input,
                  NodeKind::SearchField, NodeKind::Textarea,
                  NodeKind::Checkbox, NodeKind::Toggle, NodeKind::Radio,
                  NodeKind::Slider, NodeKind::Spinner, NodeKind::Icon,
                  NodeKind::Select, NodeKind::Combobox,
                  NodeKind::DropdownMenu, NodeKind::MenuItem,
                  NodeKind::ListItem, NodeKind::TableCell,
                  NodeKind::Resizable, NodeKind::Split, NodeKind::Alert,
                  NodeKind::Bubble, NodeKind::StatusBar});
  case Property::WidthValue:
  case Property::HeightValue:
    return kind != NodeKind::Tooltip;
  case Property::MinWidth:
  case Property::MaxWidth:
  case Property::MinHeight:
  case Property::MaxHeight:
    return !modalSurface(kind) && kind != NodeKind::Tooltip;
  case Property::ContainerRelativeFrameValue:
  case Property::ContainerRelativeFrameInset:
    return kind != NodeKind::Root && !modalSurface(kind);
  case Property::StyleClass:
    return kind != NodeKind::Tooltip;
  case Property::AccessibilityLabel:
    return oneOf(kind, {NodeKind::Button, NodeKind::ToggleButton,
                        NodeKind::Select, NodeKind::TextField,
                        NodeKind::SecureField, NodeKind::Input,
                        NodeKind::SearchField, NodeKind::Textarea,
                        NodeKind::Checkbox, NodeKind::SwitchControl,
                        NodeKind::Toggle, NodeKind::RadioGroup,
                        NodeKind::Radio, NodeKind::Slider, NodeKind::Avatar,
                        NodeKind::Image, NodeKind::MediaSurface,
                        NodeKind::Tree, NodeKind::Resizable, NodeKind::Split,
                        NodeKind::Drawer, NodeKind::Alert, NodeKind::Bubble,
                        NodeKind::ListItem}) ||
           horizontalContainer(kind) || treeRowKind(kind);
  case Property::AccessibilityIdentifier:
    return true;
  case Property::PlaceholderValue:
    return oneOf(kind, {NodeKind::TextField, NodeKind::SecureField,
                        NodeKind::Input, NodeKind::SearchField,
                        NodeKind::Textarea, NodeKind::Select,
                        NodeKind::Combobox});
  case Property::HeadingLevel:
    return kind == NodeKind::Heading;
  case Property::Checked:
    return oneOf(kind, {NodeKind::Checkbox, NodeKind::SwitchControl,
                        NodeKind::Toggle, NodeKind::Radio});
  case Property::ProgressValue:
    return oneOf(kind,
                 {NodeKind::Progress, NodeKind::Slider, NodeKind::Split});
  case Property::OrientationValue:
    return oneOf(kind,
                 {NodeKind::Divider, NodeKind::Tabs, NodeKind::Scroll});
  case Property::SizeValue:
    return oneOf(kind, {NodeKind::Button, NodeKind::ToggleButton,
                        NodeKind::Spinner, NodeKind::Icon,
                        NodeKind::TableCell, NodeKind::MenuItem});
  case Property::IconName:
    return kind == NodeKind::Icon;
  case Property::VariantValue:
    return oneOf(kind, {NodeKind::Button, NodeKind::ToggleButton,
                        NodeKind::MenuItem, NodeKind::Alert,
                        NodeKind::Bubble});
  case Property::InlineIconName:
    return oneOf(kind, {NodeKind::Button, NodeKind::ToggleButton,
                        NodeKind::MenuItem, NodeKind::ListItem,
                        NodeKind::BottomTab});
  case Property::IconPlacementValue:
    return oneOf(kind,
                 {NodeKind::Button, NodeKind::ToggleButton,
                  NodeKind::ListItem});
  case Property::Selected:
    return oneOf(kind, {NodeKind::Button, NodeKind::ToggleButton,
                        NodeKind::MenuItem, NodeKind::ListItem,
                        NodeKind::TableRow, NodeKind::Drawer,
                        NodeKind::BottomTab, NodeKind::VirtualList}) ||
           treeRowKind(kind);
  case Property::Autofocus:
    return oneOf(kind, {NodeKind::Button, NodeKind::ToggleButton,
                        NodeKind::TextField, NodeKind::SecureField,
                        NodeKind::Input, NodeKind::SearchField,
                        NodeKind::Textarea});
  case Property::SubmitOnEnter:
    return kind == NodeKind::Textarea;
  case Property::LongPressEnabled:
    return oneOf(kind, {NodeKind::Button, NodeKind::ToggleButton,
                        NodeKind::ListItem});
  case Property::ChangeEnabled:
    return kind == NodeKind::Radio || treeRowKind(kind);
  case Property::ToggleEnabled:
    return kind == NodeKind::Radio || kind == NodeKind::Drawer ||
           treeRowKind(kind);
  case Property::PressEnabled:
    return oneOf(kind, {NodeKind::Text, NodeKind::Radio, NodeKind::Select,
                        NodeKind::Combobox, NodeKind::MenuItem,
                        NodeKind::ListItem, NodeKind::TableCell,
                        NodeKind::BottomTab}) ||
           treeRowKind(kind);
  case Property::SubmitEnabled:
    return kind == NodeKind::Combobox || kind == NodeKind::ListItem;
  case Property::DoublePressEnabled:
    return kind == NodeKind::ListItem;
  case Property::AppearEnabled:
    return kind != NodeKind::Root;
  case Property::ImageIdValue:
  case Property::SourceX:
  case Property::SourceY:
  case Property::SourceWidth:
  case Property::SourceHeight:
    return kind == NodeKind::Avatar || kind == NodeKind::Image;
  case Property::SurfaceIdValue:
    return kind == NodeKind::MediaSurface;
  case Property::AnchorValue:
  case Property::AnchorAlignmentValue:
  case Property::AnchorOffset:
    return kind == NodeKind::DropdownMenu || kind == NodeKind::Tooltip;
  case Property::TooltipDelay:
    return kind == NodeKind::Tooltip;
  case Property::DurationValue:
    return false;
  case Property::TextAlignment:
    return oneOf(kind, {NodeKind::Text, NodeKind::Button,
                        NodeKind::ToggleButton, NodeKind::TableCell,
                        NodeKind::Bubble, NodeKind::StatusBar});
  case Property::RoleValue:
    return treeRowKind(kind) || kind == NodeKind::ListItem;
  case Property::TreeLevel:
  case Property::Expanded:
    return treeRowKind(kind);
  case Property::ResizeDuration:
  case Property::ResizeEasing:
  case Property::ResizeOrigin:
    return kind == NodeKind::Split;
  case Property::TextValue:
    return oneOf(kind,
                 {NodeKind::Text, NodeKind::Heading, NodeKind::Paragraph,
                  NodeKind::Label, NodeKind::Button, NodeKind::ToggleButton,
                  NodeKind::TextField, NodeKind::SecureField, NodeKind::Input,
                  NodeKind::SearchField, NodeKind::Textarea,
                  NodeKind::Checkbox, NodeKind::SwitchControl,
                  NodeKind::Toggle, NodeKind::Radio, NodeKind::Select,
                  NodeKind::Combobox, NodeKind::MenuItem, NodeKind::ListItem,
                  NodeKind::Avatar, NodeKind::Dialog, NodeKind::Drawer,
                  NodeKind::Sheet, NodeKind::Tooltip, NodeKind::TableCell,
                  NodeKind::Alert, NodeKind::Bubble, NodeKind::StatusBar});
  case Property::Enabled:
    return oneOf(kind,
                 {NodeKind::Button, NodeKind::ToggleButton,
                  NodeKind::TextField, NodeKind::SecureField, NodeKind::Input,
                  NodeKind::SearchField, NodeKind::Textarea,
                  NodeKind::Checkbox, NodeKind::SwitchControl,
                  NodeKind::Toggle, NodeKind::Radio, NodeKind::Slider,
                  NodeKind::Select, NodeKind::Combobox, NodeKind::MenuItem,
                  NodeKind::ListItem, NodeKind::Drawer, NodeKind::BottomTab});
  case Property::ActiveIndex:
  case Property::DescriptionValue:
  case Property::MetaValue:
  case Property::IndicatorValue:
  case Property::Connector:
    return false;
  case Property::TitleValue:
    return kind == NodeKind::BottomTab;
  case Property::Gap:
    return oneOf(kind, {NodeKind::Row, NodeKind::Column, NodeKind::Grid,
                        NodeKind::ListContainer, NodeKind::VirtualList,
                        NodeKind::DropdownMenu, NodeKind::TableRow,
                        NodeKind::Tree, NodeKind::Scroll, NodeKind::Card,
                        NodeKind::Panel, NodeKind::Box, NodeKind::Split}) ||
           horizontalContainer(kind);
  }
  return false;
}

} // namespace

bool propertySupported(NodeKind kind, Property property) {
  if (property == Property::AccessibilityIdentifier) return true;
  // The restrictive arms below mirror schema/components.json kindProperties.
  switch (kind) {
  case NodeKind::Root:
  case NodeKind::ContextMenu:
    return false;
  case NodeKind::Toast:
    return property == Property::DurationValue ||
           property == Property::AccessibilityLabel ||
           property == Property::StyleClass;
  case NodeKind::Toolbar:
    return property == Property::OrientationValue ||
           property == Property::AccessibilityLabel ||
           property == Property::Gap || property == Property::StyleClass;
  case NodeKind::BottomTabs:
    return property == Property::AccessibilityLabel ||
           property == Property::StyleClass ||
           property == Property::GrowValue ||
           property == Property::WidthValue ||
           property == Property::HeightValue || property == Property::MinWidth ||
           property == Property::MaxWidth || property == Property::MinHeight ||
           property == Property::MaxHeight;
  case NodeKind::BottomTab:
    return property == Property::TitleValue ||
           property == Property::InlineIconName ||
           property == Property::Selected || property == Property::Enabled ||
           property == Property::PressEnabled;
  case NodeKind::Accordion:
    return property == Property::TextValue ||
           property == Property::Selected ||
           property == Property::ToggleEnabled ||
           property == Property::HeightValue;
  case NodeKind::Stepper:
    return property == Property::ActiveIndex ||
           property == Property::AccessibilityLabel;
  case NodeKind::Step:
    return property == Property::TextValue;
  case NodeKind::Timeline:
    return property == Property::Gap || property == Property::GrowValue ||
           property == Property::AccessibilityLabel;
  case NodeKind::TimelineItem:
    return property == Property::TitleValue ||
           property == Property::DescriptionValue ||
           property == Property::MetaValue ||
           property == Property::IndicatorValue ||
           property == Property::InlineIconName ||
           property == Property::VariantValue ||
           property == Property::Connector || property == Property::Selected ||
           property == Property::PressEnabled;
  case NodeKind::InputGroup:
    return property == Property::AccessibilityLabel ||
           property == Property::WidthValue ||
           property == Property::HeightValue || property == Property::MinWidth ||
           property == Property::GrowValue;
  case NodeKind::InputGroupActions:
    return property == Property::Gap;
  case NodeKind::Dialog:
    return property == Property::DescriptionValue ||
           commonPropertySupported(kind, property);
  default:
    return commonPropertySupported(kind, property);
  }
}

bool propertyValueSupported(Property property, const QVariant &value) {
  switch (property) {
  case Property::TextValue:
    return isString(value);
  case Property::Enabled:
    return isBool(value);
  case Property::Gap: {
    int number = 0;
    return isIntValue(value, &number) && number >= 0;
  }
  case Property::MainAlignment:
    return isString(value) && mainAlignmentSupported(value.toString());
  case Property::CrossAlignment:
    return isString(value) && crossAlignmentSupported(value.toString());
  case Property::GrowValue:
    return isNumeric(value) && value.toDouble() >= 0.0;
  case Property::GridColumns: {
    int number = 0;
    return isIntValue(value, &number) && number >= 0;
  }
  case Property::PaddingValue:
    return isIntValue(value);
  case Property::PaddingHorizontal:
  case Property::PaddingVertical: {
    int number = 0;
    return isIntValue(value, &number) && number >= 0;
  }
  case Property::BackgroundValue:
  case Property::ForegroundValue:
  case Property::BorderColorValue:
    return isString(value);
  case Property::BorderWidth:
  case Property::CornerRadius:
  case Property::WidthValue:
  case Property::HeightValue:
  case Property::MinWidth:
  case Property::MaxWidth:
  case Property::MinHeight:
  case Property::MaxHeight: {
    int number = 0;
    return isIntValue(value, &number) && number >= 0;
  }
  case Property::ContainerRelativeFrameValue:
    return isString(value) &&
           containerRelativeFrameSupported(value.toString());
  case Property::ContainerRelativeFrameInset: {
    int number = 0;
    return isIntValue(value, &number) && number >= 0;
  }
  case Property::PlaceholderValue:
  case Property::AccessibilityLabel:
  case Property::AccessibilityIdentifier:
  case Property::StyleClass:
    return isString(value);
  case Property::HeadingLevel: {
    int number = 0;
    return isIntValue(value, &number) && number >= 1 && number <= 6;
  }
  case Property::Checked:
    return isBool(value);
  case Property::ProgressValue:
    return isNumeric(value);
  case Property::OrientationValue:
    return isString(value) && orientationSupported(value.toString());
  case Property::SizeValue:
    return isString(value) && controlSizeSupported(value.toString());
  case Property::IconName:
  case Property::InlineIconName:
    return isString(value) && iconName(value.toString());
  case Property::VariantValue:
    return isString(value) && buttonVariantSupported(value.toString());
  case Property::IconPlacementValue:
    return isString(value) && iconPlacementSupported(value.toString());
  case Property::Selected:
  case Property::Autofocus:
  case Property::SubmitOnEnter:
  case Property::LongPressEnabled:
  case Property::ChangeEnabled:
  case Property::ToggleEnabled:
  case Property::PressEnabled:
  case Property::SubmitEnabled:
  case Property::DoublePressEnabled:
  case Property::AppearEnabled:
    return isBool(value);
  case Property::ImageIdValue:
  case Property::SurfaceIdValue:
  case Property::ActiveIndex: {
    int number = 0;
    return isIntValue(value, &number) && number >= 0;
  }
  case Property::TitleValue:
  case Property::DescriptionValue:
  case Property::MetaValue:
  case Property::IndicatorValue:
    return isString(value);
  case Property::Connector:
    return isBool(value);
  case Property::SourceX:
  case Property::SourceY:
  case Property::SourceWidth:
  case Property::SourceHeight:
    return isNumeric(value);
  case Property::AnchorValue:
    return isString(value) &&
           inSet(value.toString(), {"above", "below", "left", "right"});
  case Property::AnchorAlignmentValue:
    return isString(value) &&
           inSet(value.toString(), {"start", "end", "stretch"});
  case Property::AnchorOffset:
    return isNumeric(value);
  case Property::TooltipDelay:
  case Property::DurationValue: {
    int number = 0;
    return isIntValue(value, &number) && number >= 0 && number <= 2147483647;
  }
  case Property::TextAlignment:
    return isString(value) &&
           inSet(value.toString(), {"start", "center", "end"});
  case Property::RoleValue:
    return isString(value) &&
           inSet(value.toString(),
                 {"treeitem", "navigation", "navigation-heading"});
  case Property::TreeLevel: {
    int number = 0;
    return isIntValue(value, &number) && number > 0;
  }
  case Property::Expanded:
    return isBool(value);
  case Property::ResizeDuration: {
    int number = 0;
    return isIntValue(value, &number) && number >= 0;
  }
  case Property::ResizeEasing:
    return isString(value) &&
           inSet(value.toString(),
                 {"linear", "standard", "emphasized", "spring"});
  case Property::ResizeOrigin:
    return isNumeric(value);
  }
  return false;
}

bool propertyValueSupportedForKind(NodeKind kind, Property property,
                                   const QVariant &value) {
  if (property == Property::SizeValue) {
    if (!isString(value)) return false;
    const QString size = value.toString();
    if (kind == NodeKind::TableCell) {
      return controlSizeSupported(size) || size == QStringLiteral("heading") ||
             size == QStringLiteral("display");
    }
    return controlSizeSupported(size);
  }
  return propertyValueSupported(property, value);
}

bool nodePropertiesSupported(NodeKind kind, const QVariantMap &properties) {
  if (!sizeAxisSupported(properties, "width", "min-width", "max-width") ||
      !sizeAxisSupported(properties, "height", "min-height", "max-height")) {
    return false;
  }
  if (kind == NodeKind::Icon) {
    const QVariant name = properties.value(QStringLiteral("name"));
    if (!name.isValid() ||
        !propertyValueSupported(Property::IconName, name)) {
      return false;
    }
  }
  if (buttonKind(kind) || kind == NodeKind::Toggle || kind == NodeKind::Radio) {
    const QString text = stringPropertyOr(properties, "text", QString());
    const QString label =
        stringPropertyOr(properties, "accessibility-label", QString());
    const QString icon = stringPropertyOr(properties, "icon", QString());
    if (text.isEmpty() && label.isEmpty()) return false;
    if (text.isEmpty() && !icon.isEmpty() && label.isEmpty()) return false;
  }
  if (kind == NodeKind::RadioGroup || kind == NodeKind::Slider) {
    if (!stringPropertyNonempty(properties, "accessibility-label")) {
      return false;
    }
  }
  if (kind == NodeKind::Select || kind == NodeKind::Combobox) {
    const QString text = stringPropertyOr(properties, "text", QString());
    const QString placeholder =
        stringPropertyOr(properties, "placeholder", QString());
    if (text.isEmpty() && placeholder.isEmpty()) return false;
  }
  if (kind == NodeKind::MenuItem || kind == NodeKind::Accordion) {
    if (!stringPropertyNonempty(properties, "text")) return false;
  }
  if (modalSurface(kind) &&
      !stringPropertyNonempty(properties, "text")) {
    return false;
  }
  if (kind == NodeKind::Tooltip) {
    if (!stringPropertyNonempty(properties, "text")) return false;
    if (properties.contains(QStringLiteral("tooltip-delay")) &&
        !properties.contains(QStringLiteral("anchor"))) {
      return false;
    }
  }
  if (kind == NodeKind::DropdownMenu || kind == NodeKind::Tooltip) {
    if ((properties.contains(QStringLiteral("anchor-alignment")) ||
         properties.contains(QStringLiteral("anchor-offset"))) &&
        !properties.contains(QStringLiteral("anchor"))) {
      return false;
    }
  }
  if (kind == NodeKind::Avatar || kind == NodeKind::Image) {
    const bool hasImage = properties.contains(QStringLiteral("image"));
    const QStringList sourceNames = {
        QStringLiteral("source-x"), QStringLiteral("source-y"),
        QStringLiteral("source-width"), QStringLiteral("source-height")};
    int sourceCount = 0;
    for (const QString &name : sourceNames) {
      if (properties.contains(name)) ++sourceCount;
    }
    const auto floatProp = [&properties](const char *name) {
      return properties.value(QLatin1String(name)).toDouble();
    };
    if (kind == NodeKind::Avatar) {
      if (!stringPropertyNonempty(properties, "text")) return false;
    } else if (!hasImage) {
      return false;
    }
    if (sourceCount != 0 && sourceCount != 4) return false;
    if (sourceCount != 0 && !hasImage) return false;
    if (sourceCount != 0 &&
        !(floatProp("source-x") >= 0.0 && floatProp("source-y") >= 0.0 &&
          floatProp("source-width") > 0.0 && floatProp("source-height") > 0.0)) {
      return false;
    }
  }
  if (kind == NodeKind::MediaSurface &&
      !properties.contains(QStringLiteral("surface"))) {
    return false;
  }
  if (kind == NodeKind::Stepper &&
      !properties.contains(QStringLiteral("active"))) {
    return false;
  }
  if (kind == NodeKind::Step || kind == NodeKind::TimelineItem ||
      kind == NodeKind::BottomTabs) {
    const char *name = kind == NodeKind::Step         ? "text"
                       : kind == NodeKind::TimelineItem ? "title"
                                                        : "accessibility-label";
    if (!stringPropertyNonempty(properties, name)) return false;
  }
  if (kind == NodeKind::BottomTab &&
      !(stringPropertyNonempty(properties, "title") &&
        trueProperty(properties, "press-enabled"))) {
    return false;
  }
  if (kind == NodeKind::Slider || kind == NodeKind::Progress) {
    const QVariant value = properties.value(QStringLiteral("value"));
    if (!isNumeric(value)) return false;
  }
  if (kind == NodeKind::Tree || kind == NodeKind::Toolbar) {
    if (!stringPropertyNonempty(properties, "accessibility-label")) {
      return false;
    }
  }
  if (kind == NodeKind::Split) {
    const int duration = intProperty(properties, "resize-duration", 0);
    if (properties.contains(QStringLiteral("resize-easing")) && duration <= 0) {
      return false;
    }
    if (properties.contains(QStringLiteral("resize-origin")) && duration <= 0) {
      return false;
    }
  }
  if (treeRowKind(kind)) {
    const bool treeitem = treeitemProperties(properties);
    const bool hasTreeMetadata =
        properties.contains(QStringLiteral("tree-level")) ||
        properties.contains(QStringLiteral("expanded")) ||
        properties.contains(QStringLiteral("change-enabled")) ||
        properties.contains(QStringLiteral("toggle-enabled"));
    if (hasTreeMetadata && !treeitem) return false;
    if (properties.contains(QStringLiteral("expanded")) &&
        !trueProperty(properties, "toggle-enabled")) {
      return false;
    }
  }
  return true;
}

} // namespace LUI
