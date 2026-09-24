// Node-kind / property semantics for the Qt QML backend, ported from
// src/lui_protocol.ml. Keep the two in sync — the OCaml module is canonical.

#pragma once

#include <QVariantMap>
#include <QString>

#include "lui_wire_schema.h"

namespace LUI {

enum class Event {
  Press,
  LongPress,
  TextChanged,
  Submit,
  ToggleChanged,
  Change,
  ValueChanged,
  Dismiss,
  DoublePress,
  Appear,
};

bool modalSurface(NodeKind kind);
bool treeRowKind(NodeKind kind);
bool contextMenuHostKind(NodeKind kind);
bool contextMenuLeafHostKind(NodeKind kind);
bool horizontalContainer(NodeKind kind);
bool buttonKind(NodeKind kind);
bool textControlKind(NodeKind kind);
bool horizontalGroupChild(NodeKind group, NodeKind child);
bool toolbarChild(NodeKind kind);

bool canContainChildren(NodeKind kind);
bool acceptsExtensionChildren(NodeKind kind);
bool childKindSupported(NodeKind parent, NodeKind child);
bool eventSupported(NodeKind kind, Event event);

bool slugSegment(const QString &value);
bool builtInIconName(const QString &value);
bool customIconName(const QString &value);
bool iconName(const QString &value);

bool decodeProperty(const QString &wire, Property *property);

bool propertySupported(NodeKind kind, Property property);
bool propertyValueSupported(Property property, const QVariant &value);
bool propertyValueSupportedForKind(NodeKind kind, Property property,
                                   const QVariant &value);

// Whole-node checks from lui_protocol.ml#node_properties_supported plus the
// structural invariants the other native backends enforce per batch
// (parent/child wiring is checked by the backend, not here).
bool nodePropertiesSupported(NodeKind kind, const QVariantMap &properties);

} // namespace LUI
