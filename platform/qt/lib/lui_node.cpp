#include "lui_node.h"

#include "lui_qml_backend.h"
#include <QGuiApplication>
#include <QList>
#include <QStyleHints>

namespace LUI {

LuiNode::LuiNode(qint64 id, QString kind, LuiQmlBackend *backend)
    : QObject(backend), m_id(id), m_kind(std::move(kind)), m_backend(backend) {
#if QT_VERSION >= QT_VERSION_CHECK(6, 5, 0)
  QObject::connect(QGuiApplication::styleHints(),
                   &QStyleHints::colorSchemeChanged, this,
                   &LuiNode::notifyChanged);
#endif
}

LuiNode *LuiNode::parentNode() const { return m_backend->node(m_parent); }

// The root `theme-mode` feeds QGuiApplication::styleHints()->setColorScheme,
// whose colorScheme() reports the resolved scheme (system followed when
// unset), so every node's effective mode comes from here.
bool LuiNode::darkMode() const {
#if QT_VERSION >= QT_VERSION_CHECK(6, 5, 0)
  return QGuiApplication::styleHints()->colorScheme() ==
         Qt::ColorScheme::Dark;
#else
  return false;
#endif
}

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
  // The first apply after construction leaves revision at 0; each later
  // diff bumps it, mirroring the Flutter backend's debugRevision.
  const bool firstApply = !m_initialized;
  const bool differs = firstApply || m_parent != parent ||
                       m_properties != properties || m_childIds != childIds;
  if (!differs) return false;
  m_initialized = true;
  m_parent = parent;
  m_childIds = childIds;
  m_properties = properties;
  if (!firstApply) ++m_revision;
  return true;
}

void LuiNode::setChildren(const QVariantList &children) {
  if (m_children == children) return;
  m_children = children;
  emit changed();
}

} // namespace LUI
