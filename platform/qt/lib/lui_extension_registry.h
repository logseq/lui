// Host-side extension component registry, ported from
// platform/flutter/lib/lui_flutter_extension.dart. A host registers each
// extension component (identifier + fingerprint + prop/event schemas + a QML
// source rendering it) before constructing the backend; the registry freezes
// when the backend takes it.

#pragma once

#include <QHash>
#include <QString>
#include <QStringList>
#include <QUrl>
#include <QVariant>

namespace LUI {

enum class ExtensionValueKind { String, Boolean, Integer, Double };

struct ExtensionProperty {
  QString name;
  ExtensionValueKind kind = ExtensionValueKind::String;
  bool isRequired = false;
  QVariant defaultValue; // invalid when none

  bool accepts(const QVariant &value) const;
  QVariant normalize(const QVariant &value) const;
};

struct ExtensionEventField {
  QString name;
  ExtensionValueKind kind = ExtensionValueKind::String;
  bool isRequired = false;
};

struct ExtensionEventSchema {
  QString name;
  QVector<ExtensionEventField> fields;
};

struct ExtensionSpec {
  QString identifier;
  QString fingerprint;
  QUrl componentSource; // QML file rendering this component
  bool acceptsStandardChildren = false;
  QStringList childIdentifiers;
  QVector<ExtensionProperty> properties;
  QVector<ExtensionEventSchema> events;
  bool isTweak = false;

  const ExtensionProperty *property(const QString &name) const;
  const ExtensionEventSchema *event(const QString &name) const;
};

class ExtensionRegistry {
public:
  // Throws QmlBackendException-compatible errors via `error` out-param.
  bool add(const ExtensionSpec &spec, QString *error);
  bool addTweak(const ExtensionSpec &spec, QString *error);

  const ExtensionSpec *registration(const QString &identifier) const;
  bool freeze(QString *error);
  bool isFrozen() const { return m_frozen; }

  static bool validName(const QString &value);

private:
  QHash<QString, ExtensionSpec> m_registrations;
  bool m_frozen = false;
};

} // namespace LUI
