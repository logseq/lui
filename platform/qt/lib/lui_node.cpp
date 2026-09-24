#include "lui_node.h"

#include "lui_qml_backend.h"
#include <QList>

namespace LUI {

LuiNode::LuiNode(qint64 id, QString kind, LuiQmlBackend *backend)
    : QObject(backend), m_id(id), m_kind(std::move(kind)), m_backend(backend) {}

LuiNode *LuiNode::parentNode() const { return m_backend->node(m_parent); }

void LuiNode::appear() { m_backend->performAppear(m_id); }
void LuiNode::press() { m_backend->performPress(m_id); }
void LuiNode::longPress() { m_backend->performLongPress(m_id); }
void LuiNode::doublePress() { m_backend->performDoublePress(m_id); }
void LuiNode::submit() { m_backend->performSubmit(m_id); }
void LuiNode::dismiss() { m_backend->performDismiss(m_id); }
void LuiNode::toggle(bool checked) {
  m_backend->performToggle(m_id, checked);
}
void LuiNode::change() { m_backend->performChange(m_id); }
void LuiNode::valueChanged(double value) {
  m_backend->performValueChanged(m_id, value);
}
void LuiNode::textChanged(const QString &text) {
  m_backend->performTextChanged(m_id, text);
}
void LuiNode::emitExtensionEvent(const QString &name,
                                 const QVariantMap &values) {
  m_backend->performExtensionEvent(m_id, name, values);
}

void LuiNode::markExtension(const QString &identifier,
                            const QString &fingerprint,
                            const QUrl &componentSource) {
  m_isExtension = true;
  m_identifier = identifier;
  m_fingerprint = fingerprint;
  m_componentSource = componentSource;
}

bool LuiNode::apply(qint64 parent, const QVariantMap &properties,
                    const QList<qint64> &childIds) {
  const bool differs = m_parent != parent || m_properties != properties ||
                       m_childIds != childIds;
  m_parent = parent;
  m_childIds = childIds;
  m_properties = properties;
  ++m_revision;
  return differs;
}

void LuiNode::setChildren(const QVariantList &children) {
  if (m_children == children) return;
  m_children = children;
  emit changed();
}

} // namespace LUI
