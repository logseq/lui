// Retained node exposed to QML. One LuiNode per wire node id; the backend
// mutates `properties`/`children` in place and emits changed() so bindings
// re-evaluate without rebuilding views.

#pragma once

#include <QObject>
#include <QUrl>
#include <QVariantList>
#include <QVariantMap>

namespace LUI {

class LuiQmlBackend;

class LuiNode : public QObject {
  Q_OBJECT
  Q_PROPERTY(qint64 nodeId READ nodeId CONSTANT)
  Q_PROPERTY(QString kind READ kindName CONSTANT)
  Q_PROPERTY(bool extension READ isExtension CONSTANT)
  Q_PROPERTY(QString identifier READ identifier CONSTANT)
  Q_PROPERTY(QUrl componentSource READ componentSource CONSTANT)
  Q_PROPERTY(QVariantMap properties READ properties NOTIFY changed)
  Q_PROPERTY(QVariantList children READ children NOTIFY changed)
  Q_PROPERTY(LuiNode *parent READ parentNode NOTIFY changed)
  Q_PROPERTY(int revision READ revision NOTIFY changed)

public:
  LuiNode(qint64 id, QString kind, LuiQmlBackend *backend);

  qint64 nodeId() const { return m_id; }
  QString kindName() const { return m_kind; }
  bool isExtension() const { return m_isExtension; }
  QString identifier() const { return m_identifier; }
  QUrl componentSource() const { return m_componentSource; }
  QVariantMap properties() const { return m_properties; }
  QVariantList children() const { return m_children; }
  LuiNode *parentNode() const;
  int revision() const { return m_revision; }

  // Convenience accessor for QML: node.prop("text", "")
  Q_INVOKABLE QVariant prop(const QString &name,
                            const QVariant &fallback = QVariant()) const {
    const QVariant value = m_properties.value(name);
    return value.isValid() ? value : fallback;
  }

  // Event entry points called from QML controls. Each forwards to the
  // backend, which validates the gesture and emits LuiQmlBackend::luiEvent.
  Q_INVOKABLE void appear();
  Q_INVOKABLE void press();
  Q_INVOKABLE void longPress();
  Q_INVOKABLE void doublePress();
  Q_INVOKABLE void submit();
  Q_INVOKABLE void dismiss();
  Q_INVOKABLE void toggle(bool checked);
  Q_INVOKABLE void change();
  Q_INVOKABLE void valueChanged(double value);
  Q_INVOKABLE void textChanged(const QString &text);
  Q_INVOKABLE void emitExtensionEvent(const QString &name,
                                      const QVariantMap &values);

signals:
  void changed();

private:
  friend class LuiQmlBackend;

  void markExtension(const QString &identifier, const QString &fingerprint,
                     const QUrl &componentSource);
  // Replaces parent/properties; returns true when the rendered content
  // actually changed.
  bool apply(qint64 parent, const QVariantMap &properties,
             const QList<qint64> &childIds);
  void setChildren(const QVariantList &children);
  void notifyChanged() { emit changed(); }

  qint64 m_id;
  QString m_kind;
  bool m_isExtension = false;
  QString m_identifier;
  QString m_fingerprint;
  QUrl m_componentSource;
  qint64 m_parent = -1;
  QList<qint64> m_childIds;
  QVariantMap m_properties;
  QVariantList m_children;
  int m_revision = 0;
  bool m_initialized = false;
  LuiQmlBackend *m_backend;
};

} // namespace LUI
