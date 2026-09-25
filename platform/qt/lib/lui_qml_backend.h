// LuiQmlBackend consumes JSON patch batches on the LUI wire protocol and
// maintains a retained tree of LuiNode objects that QML binds to. Ported
// from platform/flutter/lib/lui_flutter_backend.dart — apply a batch with
// applyJson(), render backend.rootNode() with a LuiNodeView, and connect
// luiEvent to forward user events back to the OCaml runtime.

#pragma once

#include <QHash>
#include <QImage>
#include <QList>
#include <QObject>
#include <QVariantMap>

#include "lui_extension_registry.h"
#include "lui_node.h"
#include "lui_schema.h"
#include "lui_wire_schema.h"

class QQmlEngine;

namespace LUI {

struct NodeState {
  NodeKind kind = NodeKind::Root;
  qint64 parent = -1;
  QList<qint64> children;
  QVariantMap properties;
};

struct ExtensionState {
  QString identifier;
  QString fingerprint;
  qint64 parent = -1;
  QList<qint64> children;
  QVariantMap properties;
};

class LuiQmlBackend : public QObject {
  Q_OBJECT
  Q_PROPERTY(int generation READ generation NOTIFY generationChanged)
  Q_PROPERTY(LuiNode *rootNode READ rootNode NOTIFY rootNodeChanged)
  Q_PROPERTY(QString lastError READ lastError NOTIFY lastErrorChanged)

public:
  explicit LuiQmlBackend(ExtensionRegistry extensions,
                         QObject *parent = nullptr);

  // Applies one wire batch. Returns false and leaves the tree untouched on
  // any validation failure (error describes the failure).
  Q_INVOKABLE bool applyJson(const QByteArray &source);
  bool applyJson(const QVariantMap &batch, QString *error = nullptr);

  int generation() const { return m_generation; }
  QString lastError() const { return m_lastError; }

  LuiNode *node(qint64 id) const { return m_handles.value(id); }
  LuiNode *rootNode() const;
  bool containsNode(qint64 id) const;
  QList<qint64> nodeIds() const;

  // Host-rendered pixels for "image" nodes / "media-surface" nodes; QML
  // displays them through the "image://lui/image/<id>" and
  // "image://lui/surface/<id>" providers registered by installImageProvider.
  void registerImage(qint64 id, const QImage &image);
  void unregisterImage(qint64 id);
  void presentMediaSurfaceFrame(qint64 id, const QImage &image);
  void unregisterMediaSurface(qint64 id);
  QImage image(qint64 id) const { return m_images.value(id); }
  QImage mediaSurface(qint64 id) const { return m_mediaSurfaces.value(id); }
  void installImageProvider(QQmlEngine *engine);

  // Event entry points — LuiNode forwards these from QML controls. Each
  // throws-free: returns false on gating failure and sets lastError.
  bool performPress(qint64 node);
  bool performLongPress(qint64 node);
  bool performDoublePress(qint64 node);
  bool performSubmit(qint64 node);
  bool performDismiss(qint64 node);
  bool performToggle(qint64 node, bool checked);
  bool performChange(qint64 node);
  bool performValueChanged(qint64 node, double value);
  bool performTextChanged(qint64 node, const QString &text);
  bool performAppear(qint64 node);
  bool performExtensionEvent(qint64 node, const QString &name,
                             const QVariantMap &values);

  const ExtensionRegistry &extensions() const { return m_extensions; }

signals:
  // Emitted for every accepted user event; the OCaml bridge listens here.
  void luiEvent(qint64 node, const QString &name,
                const QVariantMap &payload);
  void generationChanged();
  void rootNodeChanged();
  void lastErrorChanged();

private:
  bool fail(const QString &message);
  // Like fail but for events arriving on nodes a patch already
  // removed — logs a warning without setting lastError.
  bool staleNode(qint64 node);
  bool applyOp(QHash<qint64, NodeState> &states,
               QHash<qint64, ExtensionState> &extensions,
               const QVariantMap &operation, QString *error);
  bool validateStates(const QHash<qint64, NodeState> &states,
                      QString *error) const;
  bool validateExtensionStates(
      const QHash<qint64, NodeState> &states,
      const QHash<qint64, ExtensionState> &extensions, QString *error) const;
  bool validateChildRelationship(const QHash<qint64, NodeState> &states,
                                 const QHash<qint64, ExtensionState> &exts,
                                 qint64 parentID, qint64 childID,
                                 QString *error) const;
  bool supports(NodeKind kind, const QString &property,
                const QVariant &value) const;
  bool isContextMenuHost(const NodeState &state) const;

  void emitEvent(qint64 node, const QString &name,
                 const QVariantMap &payload = {});

  ExtensionRegistry m_extensions;
  LuiNode *m_rootHandle = nullptr;
  QHash<qint64, NodeState> m_states;
  QHash<qint64, ExtensionState> m_extensionStates;
  QHash<qint64, LuiNode *> m_handles;
  QHash<qint64, QImage> m_images;
  QHash<qint64, QImage> m_mediaSurfaces;
  int m_generation = 0;
  QString m_lastError;
};

} // namespace LUI
