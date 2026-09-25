// Ported from platform/flutter/lib/lui_flutter_backend.dart.

#include "lui_qml_backend.h"

#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonValue>
#include <QQmlEngine>
#include <QQuickImageProvider>
#include <QSet>
#include <QVariantList>
#include <algorithm>
#include <cmath>
#include <utility>

namespace LUI {

namespace {

class LuiImageProvider : public QQuickImageProvider {
public:
  explicit LuiImageProvider(LuiQmlBackend *backend)
      : QQuickImageProvider(QQuickImageProvider::Image),
        m_backend(backend) {}

  QImage requestImage(const QString &id, QSize *size,
                      const QSize & /*requestedSize*/) override {
    const int slash = id.indexOf(QLatin1Char('/'));
    const QString scope = slash < 0 ? QStringLiteral("image")
                                    : id.left(slash);
    const int question = id.indexOf(QLatin1Char('?'));
    const QString name =
        slash < 0
            ? id.left(question < 0 ? -1 : question)
            : id.mid(slash + 1, question < 0 ? -1 : question - slash - 1);
    bool ok = false;
    const qint64 number = name.toLongLong(&ok);
    QImage image;
    if (ok) {
      image = scope == QStringLiteral("surface")
                  ? m_backend->mediaSurface(number)
                  : m_backend->image(number);
    }
    if (size != nullptr) *size = image.size();
    return image;
  }

private:
  LuiQmlBackend *m_backend;
};

bool decodeInteger(const QVariant &value, qint64 *out) {
  if (value.typeId() == QMetaType::Int) {
    *out = value.toInt();
    return true;
  }
  if (value.typeId() == QMetaType::LongLong ||
      value.typeId() == QMetaType::ULongLong) {
    *out = value.toLongLong();
    return true;
  }
  if (value.typeId() != QMetaType::Double && value.typeId() != QMetaType::Float)
    return false;
  const double number = value.toDouble();
  if (!std::isfinite(number) || std::floor(number) != number) return false;
  *out = static_cast<qint64>(number);
  return true;
}

bool requireInteger(const QVariant &value, const char *name, qint64 *out,
                    QString *error) {
  if (!decodeInteger(value, out)) {
    *error = QStringLiteral("%1 must be an integer").arg(QLatin1String(name));
    return false;
  }
  return true;
}

bool requireString(const QVariant &value, const char *name, QString *out,
                   QString *error) {
  if (value.typeId() != QMetaType::QString) {
    *error = QStringLiteral("%1 must be a string").arg(QLatin1String(name));
    return false;
  }
  *out = value.toString();
  return true;
}

bool requireObject(const QVariant &value, const char *name, QVariantMap *out,
                   QString *error) {
  if (value.typeId() != QMetaType::QVariantMap) {
    *error = QStringLiteral("%1 must be an object").arg(QLatin1String(name));
    return false;
  }
  *out = value.toMap();
  return true;
}

bool requireList(const QVariant &value, const char *name, QVariantList *out,
                 QString *error) {
  if (value.typeId() != QMetaType::QVariantList) {
    *error = QStringLiteral("%1 must be an array").arg(QLatin1String(name));
    return false;
  }
  *out = value.toList();
  return true;
}

bool isTrue(const QVariant &value) {
  return value.typeId() == QMetaType::Bool && value.toBool();
}

bool isFalse(const QVariant &value) {
  return value.typeId() == QMetaType::Bool && !value.toBool();
}

QString stringOr(const QVariantMap &properties, const char *name) {
  const QVariant value = properties.value(QLatin1String(name));
  return value.typeId() == QMetaType::QString ? value.toString() : QString();
}

bool isTreeItem(const QVariantMap &properties) {
  return properties.value(QStringLiteral("role")) ==
         QStringLiteral("treeitem");
}

} // namespace

LuiQmlBackend::LuiQmlBackend(ExtensionRegistry extensions, QObject *parent)
    : QObject(parent), m_extensions(std::move(extensions)) {
  QString error;
  if (!m_extensions.isFrozen() && !m_extensions.freeze(&error)) {
    m_lastError = error;
  }
}

bool LuiQmlBackend::fail(const QString &message) {
  m_lastError = message;
  emit lastErrorChanged();
  return false;
}

// An event arriving for a node the latest patch already removed is a
// benign delivery race, not an error — drop it without touching
// lastError (which surfaces as a fatal page).
bool LuiQmlBackend::staleNode(qint64 node) {
  qWarning("dropping event on removed node %lld", (long long)node);
  return false;
}

bool LuiQmlBackend::applyJson(const QByteArray &source) {
  QJsonParseError parseError;
  const QJsonDocument doc =
      QJsonDocument::fromJson(source, &parseError);
  if (parseError.error != QJsonParseError::NoError || !doc.isObject()) {
    return fail(parseError.error != QJsonParseError::NoError
                    ? parseError.errorString()
                    : QStringLiteral("patch batch must be an object"));
  }
  QString error;
  const bool ok = applyJson(doc.object().toVariantMap(), &error);
  return ok ? true : fail(error);
}

namespace {

bool containsNodeId(const QHash<qint64, NodeState> &states,
                    const QHash<qint64, ExtensionState> &extensions,
                    qint64 id) {
  return states.contains(id) || extensions.contains(id);
}

NodeState *standardState(QHash<qint64, NodeState> &states, qint64 id) {
  const auto it = states.find(id);
  return it == states.end() ? nullptr : &it.value();
}

const NodeState *standardState(const QHash<qint64, NodeState> &states,
                               qint64 id) {
  const auto it = states.constFind(id);
  return it == states.constEnd() ? nullptr : &it.value();
}

ExtensionState *extensionState(QHash<qint64, ExtensionState> &extensions,
                               qint64 id) {
  const auto it = extensions.find(id);
  return it == extensions.end() ? nullptr : &it.value();
}

const ExtensionState *extensionState(
    const QHash<qint64, ExtensionState> &extensions, qint64 id) {
  const auto it = extensions.constFind(id);
  return it == extensions.constEnd() ? nullptr : &it.value();
}

bool nodeParent(const QHash<qint64, NodeState> &states,
                const QHash<qint64, ExtensionState> &extensions, qint64 id,
                qint64 *parent) {
  if (const NodeState *state = standardState(states, id)) {
    *parent = state->parent;
    return true;
  }
  if (const ExtensionState *state = extensionState(extensions, id)) {
    *parent = state->parent;
    return true;
  }
  return false;
}

QList<qint64> *nodeChildren(QHash<qint64, NodeState> &states,
                            QHash<qint64, ExtensionState> &extensions,
                            qint64 id) {
  if (NodeState *state = standardState(states, id)) return &state->children;
  if (ExtensionState *state = extensionState(extensions, id))
    return &state->children;
  return nullptr;
}

void setNodeParent(QHash<qint64, NodeState> &states,
                   QHash<qint64, ExtensionState> &extensions, qint64 id,
                   qint64 parent) {
  if (NodeState *state = standardState(states, id)) {
    state->parent = parent;
    return;
  }
  if (ExtensionState *state = extensionState(extensions, id))
    state->parent = parent;
}

bool isDescendant(const QHash<qint64, NodeState> &states,
                  const QHash<qint64, ExtensionState> &extensions,
                  qint64 target, qint64 root) {
  if (target == root) return true;
  // const-cast-free access: walk the tree by hand.
  const QList<qint64> *children = nullptr;
  if (const NodeState *state = standardState(states, root)) {
    children = &state->children;
  } else if (const ExtensionState *state =
                 extensionState(extensions, root)) {
    children = &state->children;
  } else {
    return false;
  }
  for (const qint64 child : *children) {
    if (isDescendant(states, extensions, target, child)) return true;
  }
  return false;
}

bool hasAncestor(const QHash<qint64, NodeState> &states, qint64 parent,
                 NodeKind kind) {
  while (parent >= 0) {
    const NodeState *state = standardState(states, parent);
    if (state == nullptr) return false;
    if (state->kind == kind) return true;
    parent = state->parent;
  }
  return false;
}

} // namespace

bool LuiQmlBackend::applyJson(const QVariantMap &batch, QString *error) {
  qint64 nextGeneration = 0;
  if (!requireInteger(batch.value(QStringLiteral("generation")), "generation",
                      &nextGeneration, error)) {
    return false;
  }
  const qint64 expectedGeneration = m_generation + 1;
  if (nextGeneration != expectedGeneration) {
    *error = QStringLiteral("expected patch generation %1, received %2")
                 .arg(expectedGeneration)
                 .arg(nextGeneration);
    return false;
  }
  QVariantList ops;
  if (!requireList(batch.value(QStringLiteral("ops")), "ops", &ops, error)) {
    return false;
  }

  QHash<qint64, NodeState> next = m_states;
  QHash<qint64, ExtensionState> nextExtensions = m_extensionStates;

  for (const QVariant &operationValue : ops) {
    QVariantMap operation;
    if (!requireObject(operationValue, "operation", &operation, error)) {
      return false;
    }
    if (!applyOp(next, nextExtensions, operation, error)) return false;
  }
  if (!validateStates(next, error)) return false;
  if (!validateExtensionStates(next, nextExtensions, error)) return false;

  // Commit the new snapshot before notifying any handles: QML bindings
  // re-evaluated by the notify below may call back into this object
  // (performPress, rootNode, ...), and those must see the committed state.
  m_states = next;
  m_extensionStates = nextExtensions;
  m_generation = static_cast<int>(nextGeneration);

  // Update handles in place so QML bindings keep their object
  // identity; drop handles for removed nodes.
  QSet<qint64> changed;
  QSet<qint64> dependents;
  for (auto it = m_handles.begin(); it != m_handles.end();) {
    if (!next.contains(it.key()) && !nextExtensions.contains(it.key())) {
      // Deferred deletion: QML may still hold this handle in bindings
      // that re-evaluate during the notify phase below; freeing it here
      // is a use-after-free inside the QV4 property getter.
      it.value()->deleteLater();
      it = m_handles.erase(it);
    } else {
      ++it;
    }
  }
  for (auto it = next.constBegin(); it != next.constEnd(); ++it) {
    const qint64 id = it.key();
    const NodeState &state = it.value();
    LuiNode *handle = m_handles.value(id);
    if (handle == nullptr) {
      handle = new LuiNode(id, QString::fromLatin1(nodeKindWireName(state.kind)),
                           this);
      m_handles.insert(id, handle);
      changed.insert(id);
    }
    QVariantList children;
    children.reserve(state.children.size());
    for (const qint64 child : state.children)
      children.append(QVariant::fromValue(static_cast<QObject *>(
          m_handles.contains(child) ? m_handles.value(child)
                                    : nullptr)));
    // Children may be extension nodes created later in this loop; resolve
    // after all handles exist (second pass below).
    if (handle->apply(state.parent, state.properties, state.children)) {
      changed.insert(id);
    }
  }
  for (auto it = nextExtensions.constBegin(); it != nextExtensions.constEnd();
       ++it) {
    const qint64 id = it.key();
    const ExtensionState &state = it.value();
    const ExtensionSpec *spec = m_extensions.registration(state.identifier);
    LuiNode *handle = m_handles.value(id);
    if (handle == nullptr) {
      handle = new LuiNode(
          id, QStringLiteral("extension"), this);
      handle->markExtension(state.identifier, state.fingerprint,
                            spec != nullptr ? spec->componentSource : QUrl());
      m_handles.insert(id, handle);
      changed.insert(id);
    }
    if (handle->apply(state.parent, state.properties, state.children)) {
      changed.insert(id);
    }
  }
  // Refresh child object lists now that every handle exists.
  for (auto it = next.constBegin(); it != next.constEnd(); ++it) {
    LuiNode *handle = m_handles.value(it.key());
    QVariantList children;
    children.reserve(it.value().children.size());
    for (const qint64 child : it.value().children)
      children.append(
          QVariant::fromValue(static_cast<QObject *>(m_handles.value(child))));
    if (handle->children() != children) {
      handle->setChildren(children);
    }
  }
  for (auto it = nextExtensions.constBegin();
       it != nextExtensions.constEnd(); ++it) {
    LuiNode *handle = m_handles.value(it.key());
    QVariantList children;
    children.reserve(it.value().children.size());
    for (const qint64 child : it.value().children)
      children.append(
          QVariant::fromValue(static_cast<QObject *>(m_handles.value(child))));
    if (handle->children() != children) {
      handle->setChildren(children);
    }
  }

  // Ancestor propagation, mirroring Flutter: a changed child refreshes
  // radio-group ancestors (exclusive check display), stack ancestors hosting
  // overlay children, any extension ancestor, and bottom-tabs dependents.
  for (const qint64 source : std::as_const(changed)) {
    const NodeState *sourceState = standardState(next, source);
    qint64 parent = -1;
    if (!nodeParent(next, nextExtensions, source, &parent)) continue;
    while (parent >= 0) {
      const NodeState *ancestor = standardState(next, parent);
      const ExtensionState *extensionAncestor =
          extensionState(nextExtensions, parent);
      if (ancestor == nullptr && extensionAncestor == nullptr) break;
      if (ancestor != nullptr && ancestor->kind == NodeKind::RadioGroup) {
        changed.insert(parent);
      }
      if (ancestor != nullptr && ancestor->kind == NodeKind::BottomTabs) {
        dependents.insert(parent);
      }
      if (ancestor != nullptr && ancestor->kind == NodeKind::Stack &&
          sourceState != nullptr &&
          (sourceState->kind == NodeKind::DropdownMenu ||
           sourceState->kind == NodeKind::Tooltip)) {
        changed.insert(parent);
      }
      if (extensionAncestor != nullptr) changed.insert(parent);
      parent = ancestor != nullptr ? ancestor->parent
                                   : extensionAncestor->parent;
    }
  }
  for (const qint64 id : std::as_const(changed)) {
    if (LuiNode *handle = m_handles.value(id)) handle->notifyChanged();
  }
  for (const qint64 id : std::as_const(dependents)) {
    if (!changed.contains(id)) {
      if (LuiNode *handle = m_handles.value(id)) handle->notifyChanged();
    }
  }

  emit generationChanged();
  // Emit only when the root handle actually changed: var-typed QML bindings
  // refire onNodeChanged for the same object, which would reload (destroy
  // and rebuild) the entire view on every batch — dropping input focus.
  LuiNode *root = rootNode();
  if (root != m_rootHandle) {
    m_rootHandle = root;
    emit rootNodeChanged();
  }
  return true;
}

bool LuiQmlBackend::supports(NodeKind kind, const QString &property,
                             const QVariant &value) const {
  Property decoded;
  if (!decodeProperty(property, &decoded)) return false;
  if (!propertySupported(kind, decoded)) return false;
  return propertyValueSupportedForKind(kind, decoded, value);
}

bool LuiQmlBackend::applyOp(QHash<qint64, NodeState> &states,
                            QHash<qint64, ExtensionState> &extensions,
                            const QVariantMap &operation, QString *error) {
  QString op;
  if (!requireString(operation.value(QStringLiteral("op")), "op", &op,
                     error)) {
    return false;
  }
  if (op == QLatin1String("create-node")) {
    qint64 id = 0;
    if (!requireInteger(operation.value(QStringLiteral("id")), "id", &id,
                        error)) {
      return false;
    }
    if (containsNodeId(states, extensions, id)) {
      *error = QStringLiteral("node already exists");
      return false;
    }
    QString kind;
    if (!requireString(operation.value(QStringLiteral("kind")), "kind", &kind,
                       error)) {
      return false;
    }
    NodeKind decoded;
    if (!decodeNodeKind(qPrintable(kind), &decoded)) {
      *error = QStringLiteral("unsupported node kind: %1").arg(kind);
      return false;
    }
    NodeState state;
    state.kind = decoded;
    states.insert(id, state);
    return true;
  }
  if (op == QLatin1String("create-extension")) {
    qint64 id = 0;
    if (!requireInteger(operation.value(QStringLiteral("id")), "id", &id,
                        error)) {
      return false;
    }
    if (containsNodeId(states, extensions, id)) {
      *error = QStringLiteral("node already exists");
      return false;
    }
    QString identifier, fingerprint;
    if (!requireString(operation.value(QStringLiteral("identifier")),
                       "identifier", &identifier, error) ||
        !requireString(operation.value(QStringLiteral("fingerprint")),
                       "fingerprint", &fingerprint, error)) {
      return false;
    }
    const ExtensionSpec *spec = m_extensions.registration(identifier);
    if (spec == nullptr) {
      *error = QStringLiteral("unknown extension");
      return false;
    }
    if (spec->fingerprint != fingerprint) {
      *error = QStringLiteral("extension fingerprint mismatch");
      return false;
    }
    ExtensionState state;
    state.identifier = identifier;
    state.fingerprint = fingerprint;
    for (const ExtensionProperty &prop : spec->properties) {
      if (prop.defaultValue.isValid())
        state.properties.insert(prop.name, prop.normalize(prop.defaultValue));
    }
    extensions.insert(id, state);
    return true;
  }
  if (op == QLatin1String("drop-node")) {
    qint64 id = 0;
    if (!requireInteger(operation.value(QStringLiteral("id")), "id", &id,
                        error)) {
      return false;
    }
    qint64 parent = -1;
    const QList<qint64> *children = nullptr;
    if (const NodeState *state = standardState(states, id)) {
      parent = state->parent;
      children = &state->children;
    } else if (const ExtensionState *state =
                   extensionState(extensions, id)) {
      parent = state->parent;
      children = &state->children;
    } else {
      *error = QStringLiteral("unknown node %1").arg(id);
      return false;
    }
    if (parent >= 0 || !children->isEmpty()) {
      *error = QStringLiteral("cannot drop an attached node");
      return false;
    }
    states.remove(id);
    extensions.remove(id);
    return true;
  }
  if (op == QLatin1String("set-prop")) {
    qint64 id = 0;
    if (!requireInteger(operation.value(QStringLiteral("id")), "id", &id,
                        error)) {
      return false;
    }
    NodeState *node = standardState(states, id);
    if (node == nullptr) {
      *error = QStringLiteral("unknown node %1").arg(id);
      return false;
    }
    QString property;
    if (!requireString(operation.value(QStringLiteral("property")), "property",
                       &property, error)) {
      return false;
    }
    const QVariant value = operation.value(QStringLiteral("value"));
    if (!value.isValid() || !supports(node->kind, property, value)) {
      *error = QStringLiteral("unsupported property value: %1.%2")
                   .arg(QString::fromLatin1(nodeKindWireName(node->kind)),
                        property);
      return false;
    }
    node->properties.insert(property, value);
    return true;
  }
  if (op == QLatin1String("remove-prop")) {
    qint64 id = 0;
    if (!requireInteger(operation.value(QStringLiteral("id")), "id", &id,
                        error)) {
      return false;
    }
    NodeState *node = standardState(states, id);
    if (node == nullptr) {
      *error = QStringLiteral("unknown node %1").arg(id);
      return false;
    }
    QString property;
    if (!requireString(operation.value(QStringLiteral("property")), "property",
                       &property, error)) {
      return false;
    }
    if (!node->properties.contains(property)) {
      *error = QStringLiteral("unsupported property: %1.%2")
                   .arg(QString::fromLatin1(nodeKindWireName(node->kind)),
                        property);
      return false;
    }
    node->properties.remove(property);
    return true;
  }
  if (op == QLatin1String("set-extension-prop")) {
    qint64 id = 0;
    if (!requireInteger(operation.value(QStringLiteral("id")), "id", &id,
                        error)) {
      return false;
    }
    ExtensionState *node = extensionState(extensions, id);
    if (node == nullptr) {
      *error = QStringLiteral("unknown extension node %1").arg(id);
      return false;
    }
    QString propertyName;
    if (!requireString(operation.value(QStringLiteral("property")), "property",
                       &propertyName, error)) {
      return false;
    }
    const ExtensionSpec *spec = m_extensions.registration(node->identifier);
    const ExtensionProperty *property =
        spec != nullptr ? spec->property(propertyName) : nullptr;
    const QVariant value = operation.value(QStringLiteral("value"));
    if (property == nullptr || !value.isValid() || !property->accepts(value)) {
      *error = QStringLiteral("unsupported extension property value");
      return false;
    }
    node->properties.insert(propertyName, property->normalize(value));
    return true;
  }
  if (op == QLatin1String("remove-extension-prop")) {
    qint64 id = 0;
    if (!requireInteger(operation.value(QStringLiteral("id")), "id", &id,
                        error)) {
      return false;
    }
    ExtensionState *node = extensionState(extensions, id);
    if (node == nullptr) {
      *error = QStringLiteral("unknown extension node %1").arg(id);
      return false;
    }
    QString propertyName;
    if (!requireString(operation.value(QStringLiteral("property")), "property",
                       &propertyName, error)) {
      return false;
    }
    const ExtensionSpec *spec = m_extensions.registration(node->identifier);
    const ExtensionProperty *property =
        spec != nullptr ? spec->property(propertyName) : nullptr;
    if (property == nullptr) {
      *error = QStringLiteral("unknown extension property");
      return false;
    }
    if (!property->defaultValue.isValid()) {
      node->properties.remove(propertyName);
    } else {
      node->properties.insert(propertyName,
                              property->normalize(property->defaultValue));
    }
    return true;
  }
  if (op == QLatin1String("insert-child")) {
    qint64 parentID = 0, childID = 0, index = 0;
    if (!requireInteger(operation.value(QStringLiteral("parent")), "parent",
                        &parentID, error) ||
        !requireInteger(operation.value(QStringLiteral("child")), "child",
                        &childID, error) ||
        !requireInteger(operation.value(QStringLiteral("index")), "index",
                        &index, error)) {
      return false;
    }
    if (!containsNodeId(states, extensions, parentID) ||
        !containsNodeId(states, extensions, childID)) {
      *error = QStringLiteral("unknown parent or child node");
      return false;
    }
    qint64 existingParent = -1;
    nodeParent(states, extensions, childID, &existingParent);
    if (existingParent >= 0) {
      *error = QStringLiteral("child is already attached");
      return false;
    }
    if (!validateChildRelationship(states, extensions, parentID, childID,
                                   error)) {
      return false;
    }
    QList<qint64> *children = nodeChildren(states, extensions, parentID);
    if (index < 0 || index > children->size()) {
      *error = QStringLiteral("child index is out of bounds");
      return false;
    }
    if (isDescendant(states, extensions, parentID, childID)) {
      *error = QStringLiteral("child insertion would create a cycle");
      return false;
    }
    children->insert(static_cast<int>(index), childID);
    setNodeParent(states, extensions, childID, parentID);
    return true;
  }
  if (op == QLatin1String("remove-child")) {
    qint64 parentID = 0, childID = 0;
    if (!requireInteger(operation.value(QStringLiteral("parent")), "parent",
                        &parentID, error) ||
        !requireInteger(operation.value(QStringLiteral("child")), "child",
                        &childID, error)) {
      return false;
    }
    QList<qint64> *children = nodeChildren(states, extensions, parentID);
    if (children == nullptr || !children->removeOne(childID)) {
      *error = QStringLiteral("child is not attached to parent");
      return false;
    }
    setNodeParent(states, extensions, childID, -1);
    return true;
  }
  if (op == QLatin1String("move-child")) {
    qint64 parentID = 0, childID = 0, index = 0;
    if (!requireInteger(operation.value(QStringLiteral("parent")), "parent",
                        &parentID, error) ||
        !requireInteger(operation.value(QStringLiteral("child")), "child",
                        &childID, error) ||
        !requireInteger(operation.value(QStringLiteral("index")), "index",
                        &index, error)) {
      return false;
    }
    QList<qint64> *children = nodeChildren(states, extensions, parentID);
    if (children == nullptr || !children->removeOne(childID)) {
      *error = QStringLiteral("child is not attached to parent");
      return false;
    }
    if (index < 0 || index > children->size()) {
      *error = QStringLiteral("child index is out of bounds");
      return false;
    }
    children->insert(static_cast<int>(index), childID);
    return true;
  }
  *error = QStringLiteral("unknown patch operation");
  return false;
}

bool LuiQmlBackend::isContextMenuHost(const NodeState &state) const {
  return contextMenuHostKind(state.kind) ||
         isTrue(state.properties.value(QStringLiteral("press-enabled"))) ||
         isTrue(state.properties.value(QStringLiteral("double-press-enabled"))) ||
         isTrue(state.properties.value(QStringLiteral("toggle-enabled"))) ||
         isTrue(state.properties.value(QStringLiteral("long-press-enabled")));
}

bool LuiQmlBackend::validateChildRelationship(
    const QHash<qint64, NodeState> &states,
    const QHash<qint64, ExtensionState> &extensions, qint64 parentID,
    qint64 childID, QString *error) const {
  const NodeState *child = standardState(states, childID);
  if (child != nullptr && child->kind == NodeKind::Root) {
    *error = QStringLiteral("runtime root cannot be nested");
    return false;
  }
  const ExtensionState *transparentChild =
      extensionState(extensions, childID);
  if (transparentChild != nullptr) {
    const ExtensionSpec *spec =
        m_extensions.registration(transparentChild->identifier);
    if (spec != nullptr && spec->isTweak) {
      if (transparentChild->children.size() != 1) {
        *error = QStringLiteral("platform tweak requires exactly one child");
        return false;
      }
      return validateChildRelationship(states, extensions, parentID,
                                       transparentChild->children.first(),
                                       error);
    }
  }
  const NodeState *parent = standardState(states, parentID);
  if (parent != nullptr && child == nullptr) {
    if (!acceptsExtensionChildren(parent->kind)) {
      *error = QStringLiteral("standard node cannot contain extension");
      return false;
    }
    return true;
  }
  const ExtensionState *extensionParent =
      extensionState(extensions, parentID);
  const ExtensionState *extensionChild = extensionState(extensions, childID);
  if (extensionParent != nullptr) {
    const ExtensionSpec *spec =
        m_extensions.registration(extensionParent->identifier);
    if (spec == nullptr) {
      *error = QStringLiteral("invalid extension registration");
      return false;
    }
    if (spec->isTweak) {
      if (!extensionParent->children.isEmpty()) {
        *error = QStringLiteral("platform tweak requires exactly one child");
        return false;
      }
      return true;
    }
    if (child != nullptr) {
      if (!spec->acceptsStandardChildren) {
        *error =
            QStringLiteral("extension does not accept standard children");
        return false;
      }
      return true;
    }
    if (extensionChild == nullptr ||
        !spec->childIdentifiers.contains(extensionChild->identifier)) {
      *error =
          QStringLiteral("extension child relationship is not registered");
      return false;
    }
    return true;
  }
  if (parent == nullptr || child == nullptr) {
    *error = QStringLiteral("unknown parent or child node");
    return false;
  }
  if (!canContainChildren(parent->kind)) {
    *error = QStringLiteral("parent cannot contain child");
    return false;
  }
  if ((parent->kind == NodeKind::DropdownMenu ||
       parent->kind == NodeKind::ContextMenu) &&
      child->kind != NodeKind::MenuItem && child->kind != NodeKind::Divider) {
    *error =
        QStringLiteral("menu accepts only menu-item or separator children");
    return false;
  }
  if (parent->kind == NodeKind::MenuItem &&
      child->kind != NodeKind::ContextMenu &&
      child->kind != NodeKind::DropdownMenu) {
    *error =
        QStringLiteral("menu-item accepts only nested menu metadata");
    return false;
  }
  if (parent->kind != NodeKind::MenuItem &&
      contextMenuLeafHostKind(parent->kind) &&
      child->kind != NodeKind::ContextMenu) {
    *error =
        QStringLiteral("interactive leaf accepts only context-menu metadata");
    return false;
  }
  if (parent->kind == NodeKind::Table && child->kind != NodeKind::TableRow) {
    *error = QStringLiteral("table can contain only table-row");
    return false;
  }
  if (parent->kind == NodeKind::TableRow &&
      child->kind != NodeKind::TableCell) {
    *error = QStringLiteral("table-row can contain only table-cell");
    return false;
  }
  if (parent->kind == NodeKind::Tree &&
      !(treeRowKind(child->kind) || child->kind == NodeKind::VirtualList)) {
    *error = QStringLiteral("tree accepts only row containers");
    return false;
  }
  if (parent->kind == NodeKind::Stepper && child->kind != NodeKind::Step) {
    *error = QStringLiteral("stepper accepts only step children");
    return false;
  }
  if (parent->kind == NodeKind::Timeline &&
      child->kind != NodeKind::TimelineItem) {
    *error =
        QStringLiteral("timeline accepts only timeline-item children");
    return false;
  }
  if (parent->kind == NodeKind::BottomTabs &&
      child->kind != NodeKind::BottomTab) {
    *error =
        QStringLiteral("bottom-tabs accepts only bottom-tab children");
    return false;
  }
  if (parent->kind == NodeKind::BottomTab &&
      child->kind == NodeKind::BottomTab) {
    *error =
        QStringLiteral("bottom-tab cannot directly contain bottom-tab");
    return false;
  }
  if (parent->kind == NodeKind::InputGroup &&
      child->kind != NodeKind::Textarea &&
      child->kind != NodeKind::InputGroupActions) {
    *error = QStringLiteral(
        "input-group accepts only textarea and input-group-actions children");
    return false;
  }
  if (parent->kind == NodeKind::Toolbar && !toolbarChild(child->kind)) {
    *error = QStringLiteral(
        "toolbar accepts only interactive controls and dividers");
    return false;
  }
  return true;
}

bool LuiQmlBackend::validateStates(const QHash<qint64, NodeState> &states,
                                   QString *error) const {
  for (auto it = states.constBegin(); it != states.constEnd(); ++it) {
    const NodeState &state = it.value();
    const QVariantMap &props = state.properties;
    const QString kindName =
        QString::fromLatin1(nodeKindWireName(state.kind));
    const auto reject = [&error, &kindName](const char *message) {
      *error = QStringLiteral("%1: %2").arg(kindName, QLatin1String(message));
      return false;
    };

    for (auto prop = props.constBegin(); prop != props.constEnd(); ++prop) {
      Property decoded;
      if (!decodeProperty(prop.key(), &decoded)) {
        return reject("unknown property");
      }
      if (!propertySupported(state.kind, decoded)) {
        return reject("unsupported property");
      }
      if (!propertyValueSupportedForKind(state.kind, decoded,
                                         prop.value())) {
        return reject("unsupported property value");
      }
    }

    if (state.kind == NodeKind::Root) {
      if (state.parent >= 0)
        return reject("runtime root cannot have a parent");
      if (state.children.size() != 1)
        return reject("runtime root requires exactly one child");
    }
    if (!nodePropertiesSupported(state.kind, props)) {
      return reject("invalid node properties");
    }
    if (state.kind == NodeKind::Split && state.children.size() != 2) {
      return reject("split requires exactly two children");
    }
    if (state.kind == NodeKind::Split) {
      const QVariant value = props.value(QStringLiteral("value"));
      if (value.typeId() != QMetaType::Double &&
          value.typeId() != QMetaType::Float) {
        return reject("split requires a finite fractional value");
      }
      if (!std::isfinite(value.toDouble()))
        return reject("split requires a finite fractional value");
    }
    if (state.kind == NodeKind::Drawer && state.children.size() != 2) {
      return reject("drawer requires exactly two children");
    }
    if (state.kind == NodeKind::Radio &&
        !hasAncestor(states, state.parent, NodeKind::RadioGroup)) {
      return reject("radio must be contained by a radio-group");
    }
    if (state.kind == NodeKind::ContextMenu) {
      const NodeState *parent =
          state.parent >= 0 ? standardState(states, state.parent) : nullptr;
      if (parent == nullptr || !isContextMenuHost(*parent)) {
        return reject("context-menu requires an interactive direct host");
      }
      int count = 0;
      for (const qint64 sibling : parent->children) {
        const NodeState *siblingState = standardState(states, sibling);
        if (siblingState != nullptr &&
            siblingState->kind == NodeKind::ContextMenu) {
          ++count;
        }
      }
      if (count != 1)
        return reject("host accepts at most one context-menu");
      for (const qint64 childID : state.children) {
        const NodeState *childState = standardState(states, childID);
        if (childState == nullptr) return reject("unknown child node");
        if (childState->kind == NodeKind::MenuItem) {
          if (!isTrue(childState->properties.value(
                  QStringLiteral("press-enabled")))) {
            return reject("context-menu menu-item requires press support");
          }
          if (!childState->children.isEmpty())
            return reject("context-menu does not support nested menus");
          static const QSet<QString> allowed = {
              QStringLiteral("text"), QStringLiteral("icon"),
              QStringLiteral("foreground"), QStringLiteral("enabled"),
              QStringLiteral("press-enabled"), QStringLiteral("variant"),
          };
          for (auto prop = childState->properties.constBegin();
               prop != childState->properties.constEnd(); ++prop) {
            if (!allowed.contains(prop.key())) {
              return reject(
                  "context-menu menu-item has unsupported metadata");
            }
          }
        } else if (!childState->properties.isEmpty() &&
                   !(childState->properties.size() == 2 &&
                     childState->properties.value(
                         QStringLiteral("orientation")) ==
                         QStringLiteral("horizontal") &&
                     childState->properties.value(
                         QStringLiteral("style-class")) ==
                         QStringLiteral("lui-separator"))) {
          return reject("context-menu separator accepts no attributes");
        }
      }
    }
    if (state.kind == NodeKind::BottomTabs &&
        (state.children.size() < 2 || state.children.size() > 5)) {
      return reject("bottom-tabs requires two to five destinations");
    }
    if (state.kind == NodeKind::BottomTab &&
        (!isTrue(props.value(QStringLiteral("press-enabled"))) ||
         state.children.isEmpty() || state.parent < 0 ||
         standardState(states, state.parent) == nullptr ||
         standardState(states, state.parent)->kind != NodeKind::BottomTabs)) {
      return reject(
          "bottom-tab requires title, press support, content, and a direct "
          "bottom-tabs parent");
    }
    const bool hasTreeMetadata =
        props.contains(QStringLiteral("role")) ||
        props.contains(QStringLiteral("tree-level")) ||
        props.contains(QStringLiteral("expanded"));
    if (hasTreeMetadata) {
      if (!isTreeItem(props) ||
          !hasAncestor(states, state.parent, NodeKind::Tree)) {
        return reject("tree row metadata requires a treeitem inside tree");
      }
      if (props.contains(QStringLiteral("expanded")) &&
          !isTrue(props.value(QStringLiteral("toggle-enabled")))) {
        return reject("expanded treeitem requires toggle support");
      }
    }
    if (state.kind == NodeKind::ListItem) {
      const bool hasText = !stringOr(props, "text").isEmpty();
      bool hasChildren = false;
      for (const qint64 child : state.children) {
        const NodeState *childState = standardState(states, child);
        if (childState == nullptr ||
            childState->kind != NodeKind::ContextMenu) {
          hasChildren = true;
        }
      }
      if (!hasText && !hasChildren)
        return reject("list-item requires text or children");
      if (hasText && hasChildren)
        return reject("list-item accepts text or children, not both");
    }
    if (state.kind == NodeKind::Step &&
        (stringOr(props, "text").isEmpty() || state.parent < 0 ||
         standardState(states, state.parent) == nullptr ||
         standardState(states, state.parent)->kind != NodeKind::Stepper)) {
      return reject("step requires text and a direct stepper parent");
    }
    if (state.kind == NodeKind::TimelineItem &&
        state.parent >= 0) {
      const NodeState *parent = standardState(states, state.parent);
      if (parent == nullptr || parent->kind != NodeKind::Timeline)
        return reject("timeline-item requires a direct timeline parent");
    } else if (state.kind == NodeKind::TimelineItem) {
      return reject("timeline-item requires a direct timeline parent");
    }
    if (state.kind == NodeKind::InputGroup) {
      if (state.children.isEmpty() || state.children.size() > 2) {
        return reject(
            "input-group requires one textarea and optional actions");
      }
      const NodeState *first = standardState(states, state.children.first());
      if (first == nullptr || first->kind != NodeKind::Textarea) {
        return reject(
            "input-group requires textarea first and actions second");
      }
      if (state.children.size() == 2) {
        const NodeState *second =
            standardState(states, state.children.at(1));
        if (second == nullptr ||
            second->kind != NodeKind::InputGroupActions) {
          return reject(
              "input-group requires textarea first and actions second");
        }
      }
    }
    if (state.kind == NodeKind::InputGroupActions &&
        (state.parent < 0 ||
         standardState(states, state.parent) == nullptr ||
         standardState(states, state.parent)->kind != NodeKind::InputGroup)) {
      return reject(
          "input-group-actions requires a direct input-group parent");
    }
  }
  return true;
}

bool LuiQmlBackend::validateExtensionStates(
    const QHash<qint64, NodeState> &states,
    const QHash<qint64, ExtensionState> &extensions, QString *error) const {
  for (auto it = extensions.constBegin(); it != extensions.constEnd(); ++it) {
    const qint64 id = it.key();
    const ExtensionState &state = it.value();
    const ExtensionSpec *spec = m_extensions.registration(state.identifier);
    if (spec == nullptr || spec->fingerprint != state.fingerprint) {
      *error = QStringLiteral("invalid extension registration");
      return false;
    }
    if (spec->isTweak && state.children.size() != 1) {
      *error = QStringLiteral("platform tweak requires exactly one child");
      return false;
    }
    QSet<QString> names;
    for (const ExtensionProperty &prop : spec->properties)
      names.insert(prop.name);
    for (auto prop = state.properties.constBegin();
         prop != state.properties.constEnd(); ++prop) {
      if (!names.contains(prop.key())) {
        *error = QStringLiteral("unknown extension property");
        return false;
      }
    }
    for (const ExtensionProperty &prop : spec->properties) {
      const QVariant value = state.properties.value(prop.name);
      if (!value.isValid()) {
        if (prop.isRequired) {
          *error = QStringLiteral("missing required extension property");
          return false;
        }
      } else if (!prop.accepts(value)) {
        *error = QStringLiteral("invalid extension property");
        return false;
      }
    }
    if (state.parent >= 0) {
      const QList<qint64> *parentChildren = nullptr;
      if (const NodeState *parent = standardState(states, state.parent)) {
        parentChildren = &parent->children;
      } else if (const ExtensionState *parent =
                     extensionState(extensions, state.parent)) {
        parentChildren = &parent->children;
      }
      if (parentChildren == nullptr || !parentChildren->contains(id)) {
        *error = QStringLiteral("extension parent is inconsistent");
        return false;
      }
    }
    for (const qint64 child : state.children) {
      qint64 childParent = -1;
      if (!nodeParent(states, extensions, child, &childParent) ||
          childParent != id) {
        *error = QStringLiteral("extension child is inconsistent");
        return false;
      }
    }
  }
  return true;
}

void LuiQmlBackend::emitEvent(qint64 node, const QString &name,
                              const QVariantMap &payload) {
  emit luiEvent(node, name, payload);
}

bool LuiQmlBackend::performPress(qint64 node) {
  const NodeState *state = standardState(m_states, node);
  if (state == nullptr) return staleNode(node);
  const bool treeItem = isTreeItem(state->properties);
  const bool pressable =
      state->kind == NodeKind::Button || state->kind == NodeKind::Select ||
      state->kind == NodeKind::Combobox || state->kind == NodeKind::MenuItem ||
      state->kind == NodeKind::ListItem ||
      (state->kind == NodeKind::BottomTab &&
       isTrue(state->properties.value(QStringLiteral("press-enabled")))) ||
      (state->kind == NodeKind::TimelineItem &&
       isTrue(state->properties.value(QStringLiteral("press-enabled")))) ||
      (treeItem &&
       isTrue(state->properties.value(QStringLiteral("press-enabled")))) ||
      (state->kind == NodeKind::TableCell &&
       isTrue(state->properties.value(QStringLiteral("press-enabled")))) ||
      (state->kind == NodeKind::Text &&
       isTrue(state->properties.value(QStringLiteral("press-enabled"))));
  if (!pressable || isFalse(state->properties.value(QStringLiteral("enabled")))) {
    return fail(QStringLiteral("node %1 is not an enabled pressable control")
                    .arg(node));
  }
  emitEvent(node, QStringLiteral("press"));
  return true;
}

bool LuiQmlBackend::performLongPress(qint64 node) {
  const NodeState *state = standardState(m_states, node);
  if (state == nullptr) return staleNode(node);
  if (!(buttonKind(state->kind) || state->kind == NodeKind::ListItem) ||
      isFalse(state->properties.value(QStringLiteral("enabled"))) ||
      !isTrue(state->properties.value(QStringLiteral("long-press-enabled")))) {
    return fail(QStringLiteral("node %1 is not enabled for long press")
                    .arg(node));
  }
  emitEvent(node, QStringLiteral("long-press"));
  return true;
}

bool LuiQmlBackend::performDoublePress(qint64 node) {
  const NodeState *state = standardState(m_states, node);
  if (state == nullptr) return staleNode(node);
  if (state->kind != NodeKind::ListItem ||
      isFalse(state->properties.value(QStringLiteral("enabled"))) ||
      !isTrue(state->properties.value(QStringLiteral("double-press-enabled")))) {
    return fail(QStringLiteral("node %1 is not an enabled double-press control")
                    .arg(node));
  }
  emitEvent(node, QStringLiteral("double-press"));
  return true;
}

bool LuiQmlBackend::performSubmit(qint64 node) {
  const NodeState *state = standardState(m_states, node);
  if (state == nullptr) return staleNode(node);
  if (state->kind == NodeKind::ListItem) {
    if (isFalse(state->properties.value(QStringLiteral("enabled"))) ||
        !isTrue(state->properties.value(QStringLiteral("submit-enabled")))) {
      return fail(QStringLiteral("node %1 is not an enabled submit control")
                      .arg(node));
    }
    emitEvent(node, QStringLiteral("submit"));
    return true;
  }
  if (textControlKind(state->kind) &&
      !isFalse(state->properties.value(QStringLiteral("enabled")))) {
    emitEvent(node, QStringLiteral("submit"));
    return true;
  }
  return fail(QStringLiteral("node %1 is not an enabled submit control")
                  .arg(node));
}

bool LuiQmlBackend::performDismiss(qint64 node) {
  const NodeState *state = standardState(m_states, node);
  if (state == nullptr) return staleNode(node);
  if (state->kind != NodeKind::Select && state->kind != NodeKind::Combobox &&
      state->kind != NodeKind::DropdownMenu &&
      state->kind != NodeKind::Toast && !modalSurface(state->kind)) {
    return fail(QStringLiteral("node %1 is not dismissible").arg(node));
  }
  emitEvent(node, QStringLiteral("dismiss"));
  return true;
}

bool LuiQmlBackend::performToggle(qint64 node, bool checked) {
  const NodeState *state = standardState(m_states, node);
  if (state == nullptr) return staleNode(node);
  const bool treeItem = isTreeItem(state->properties);
  // Flutter emits toggleChanged directly from its checkbox/switch controls
  // (only gated on enabled); the other kinds route through this gate.
  const bool isToggle = state->kind == NodeKind::ToggleButton ||
                        state->kind == NodeKind::Toggle ||
                        state->kind == NodeKind::Checkbox ||
                        state->kind == NodeKind::SwitchControl ||
                        state->kind == NodeKind::Accordion ||
                        state->kind == NodeKind::Drawer || treeItem;
  const bool hasHandler =
      (state->kind != NodeKind::Accordion &&
       state->kind != NodeKind::Drawer && !treeItem) ||
      isTrue(state->properties.value(QStringLiteral("toggle-enabled")));
  if (!isToggle ||
      isFalse(state->properties.value(QStringLiteral("enabled"))) ||
      !hasHandler) {
    return fail(QStringLiteral("node %1 is not an enabled toggle button")
                    .arg(node));
  }
  emitEvent(node, QStringLiteral("toggle-changed"),
            {{QStringLiteral("checked"), checked}});
  return true;
}

bool LuiQmlBackend::performChange(qint64 node) {
  const NodeState *state = standardState(m_states, node);
  if (state == nullptr) return staleNode(node);
  if ((state->kind != NodeKind::Radio && !isTreeItem(state->properties)) ||
      isFalse(state->properties.value(QStringLiteral("enabled")))) {
    return fail(QStringLiteral("node %1 is not an enabled change control")
                    .arg(node));
  }
  if (isTrue(state->properties.value(QStringLiteral("change-enabled")))) {
    if (!isTrue(state->properties.value(QStringLiteral("checked")))) {
      emitEvent(node, QStringLiteral("change"));
    }
  } else if (isTrue(state->properties.value(QStringLiteral("toggle-enabled")))) {
    emitEvent(node, QStringLiteral("toggle-changed"),
              {{QStringLiteral("checked"), true}});
  } else if (isTrue(state->properties.value(QStringLiteral("press-enabled")))) {
    emitEvent(node, QStringLiteral("press"));
  }
  return true;
}

bool LuiQmlBackend::performValueChanged(qint64 node, double value) {
  const NodeState *state = standardState(m_states, node);
  if (state == nullptr) return staleNode(node);
  if ((state->kind != NodeKind::Slider && state->kind != NodeKind::Split) ||
      isFalse(state->properties.value(QStringLiteral("enabled"))) ||
      !std::isfinite(value)) {
    return fail(QStringLiteral("node %1 is not an enabled value control")
                    .arg(node));
  }
  emitEvent(node, QStringLiteral("value-changed"),
            {{QStringLiteral("value"), std::clamp(value, 0.0, 1.0)}});
  return true;
}

bool LuiQmlBackend::performTextChanged(qint64 node, const QString &text) {
  const NodeState *state = standardState(m_states, node);
  if (state == nullptr) return staleNode(node);
  if (!textControlKind(state->kind) ||
      isFalse(state->properties.value(QStringLiteral("enabled")))) {
    return fail(QStringLiteral("node %1 is not an enabled text control")
                    .arg(node));
  }
  emitEvent(node, QStringLiteral("text-changed"),
            {{QStringLiteral("text"), text}});
  return true;
}

bool LuiQmlBackend::performAppear(qint64 node) {
  const NodeState *state = standardState(m_states, node);
  if (state == nullptr) return staleNode(node);
  if (state->kind == NodeKind::Root ||
      !isTrue(state->properties.value(QStringLiteral("appear-enabled")))) {
    return false; // appear is best-effort; no error raised
  }
  emitEvent(node, QStringLiteral("appear"));
  return true;
}

bool LuiQmlBackend::performExtensionEvent(qint64 node, const QString &name,
                                          const QVariantMap &values) {
  const ExtensionState *state = extensionState(m_extensionStates, node);
  if (state == nullptr) {
    // A surface torn down by the latest patch can still deliver an
    // in-flight emit against its old node id — drop it rather than
    // surfacing a fatal error for a benign race.
    qWarning("dropping event on removed extension node %lld",
             (long long)node);
    return false;
  }
  const ExtensionSpec *spec = m_extensions.registration(state->identifier);
  if (spec == nullptr) {
    return fail(QStringLiteral("unknown extension %1").arg(state->identifier));
  }
  const ExtensionEventSchema *event = spec->event(name);
  if (event == nullptr) {
    return fail(QStringLiteral("unknown extension event"));
  }
  QHash<QString, const ExtensionEventField *> fields;
  for (const ExtensionEventField &field : event->fields)
    fields.insert(field.name, &field);
  for (auto it = values.constBegin(); it != values.constEnd(); ++it) {
    if (!fields.contains(it.key())) {
      return fail(QStringLiteral("unknown extension event field"));
    }
  }
  for (const ExtensionEventField &field : event->fields) {
    const QVariant value = values.value(field.name);
    if (!value.isValid()) {
      if (field.isRequired) {
        return fail(QStringLiteral("missing required extension event field"));
      }
      continue;
    }
    ExtensionProperty probe;
    probe.name = field.name;
    probe.kind = field.kind;
    probe.isRequired = true;
    if (!probe.accepts(value)) {
      return fail(QStringLiteral("invalid extension event field"));
    }
  }
  QVariantMap normalized;
  for (auto it = values.constBegin(); it != values.constEnd(); ++it) {
    ExtensionProperty probe;
    probe.kind = fields.value(it.key())->kind;
    normalized.insert(it.key(), probe.normalize(it.value()));
  }
  emitEvent(node, QStringLiteral("extension"),
            {{QStringLiteral("identifier"), state->identifier},
             {QStringLiteral("name"), name},
             {QStringLiteral("values"), normalized}});
  return true;
}

LuiNode *LuiQmlBackend::rootNode() const {
  for (auto it = m_states.constBegin(); it != m_states.constEnd(); ++it) {
    if (it.value().kind == NodeKind::Root) return m_handles.value(it.key());
  }
  // Apps created without a Root wrapper (Lui_app.create) top out at a
  // single detached node — that orphan is the root.
  LuiNode *orphan = nullptr;
  for (auto it = m_states.constBegin(); it != m_states.constEnd(); ++it) {
    if (it.value().parent < 0) {
      if (orphan != nullptr) return nullptr; // ambiguous
      orphan = m_handles.value(it.key());
    }
  }
  return orphan;
}

bool LuiQmlBackend::containsNode(qint64 id) const {
  return m_states.contains(id) || m_extensionStates.contains(id);
}

QList<qint64> LuiQmlBackend::nodeIds() const {
  QList<qint64> ids = m_states.keys();
  ids += m_extensionStates.keys();
  return ids;
}

void LuiQmlBackend::registerImage(qint64 id, const QImage &image) {
  if (id <= 0) {
    fail(QStringLiteral("registered image id must be positive"));
    return;
  }
  m_images.insert(id, image);
  for (auto it = m_states.constBegin(); it != m_states.constEnd(); ++it) {
    if ((it.value().kind == NodeKind::Avatar ||
         it.value().kind == NodeKind::Image) &&
        it.value().properties.value(QStringLiteral("image")) ==
            QVariant::fromValue(id)) {
      if (LuiNode *handle = m_handles.value(it.key()))
        handle->bumpRevision();
    }
  }
}

void LuiQmlBackend::unregisterImage(qint64 id) {
  if (m_images.remove(id) == 0) return;
  for (auto it = m_states.constBegin(); it != m_states.constEnd(); ++it) {
    if ((it.value().kind == NodeKind::Avatar ||
         it.value().kind == NodeKind::Image) &&
        it.value().properties.value(QStringLiteral("image")) ==
            QVariant::fromValue(id)) {
      if (LuiNode *handle = m_handles.value(it.key()))
        handle->bumpRevision();
    }
  }
}

void LuiQmlBackend::presentMediaSurfaceFrame(qint64 id, const QImage &image) {
  if (id <= 0) {
    fail(QStringLiteral("media surface id must be positive"));
    return;
  }
  m_mediaSurfaces.insert(id, image);
  for (auto it = m_states.constBegin(); it != m_states.constEnd(); ++it) {
    if (it.value().kind == NodeKind::MediaSurface &&
        it.value().properties.value(QStringLiteral("surface")) ==
            QVariant::fromValue(id)) {
      if (LuiNode *handle = m_handles.value(it.key()))
        handle->bumpRevision();
    }
  }
}

void LuiQmlBackend::unregisterMediaSurface(qint64 id) {
  if (m_mediaSurfaces.remove(id) == 0) return;
  for (auto it = m_states.constBegin(); it != m_states.constEnd(); ++it) {
    if (it.value().kind == NodeKind::MediaSurface &&
        it.value().properties.value(QStringLiteral("surface")) ==
            QVariant::fromValue(id)) {
      if (LuiNode *handle = m_handles.value(it.key()))
        handle->bumpRevision();
    }
  }
}

void LuiQmlBackend::installImageProvider(QQmlEngine *engine) {
  engine->addImageProvider(QStringLiteral("lui"), new LuiImageProvider(this));
}

} // namespace LUI
