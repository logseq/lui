#include "lui_extension_registry.h"

#include "lui_wire_schema.h"

#include <QSet>
#include <cmath>

namespace LUI {

namespace {

bool stringValue(const QVariant &v) { return v.typeId() == QMetaType::QString; }
bool boolValue(const QVariant &v) { return v.typeId() == QMetaType::Bool; }
bool intValue(const QVariant &v) {
  if (v.typeId() == QMetaType::Int) return true;
  if (v.typeId() != QMetaType::Double && v.typeId() != QMetaType::Float &&
      v.typeId() != QMetaType::LongLong &&
      v.typeId() != QMetaType::ULongLong) {
    return false;
  }
  const double n = v.toDouble();
  return std::isfinite(n) && std::floor(n) == n;
}
bool doubleValue(const QVariant &v) {
  switch (v.typeId()) {
  case QMetaType::Double:
  case QMetaType::Float:
  case QMetaType::Int:
  case QMetaType::LongLong:
  case QMetaType::ULongLong:
    return std::isfinite(v.toDouble());
  default:
    return false;
  }
}

} // namespace

bool ExtensionProperty::accepts(const QVariant &value) const {
  switch (kind) {
  case ExtensionValueKind::String:
    return stringValue(value);
  case ExtensionValueKind::Boolean:
    return boolValue(value);
  case ExtensionValueKind::Integer:
    return intValue(value);
  case ExtensionValueKind::Double:
    return doubleValue(value);
  }
  return false;
}

QVariant ExtensionProperty::normalize(const QVariant &value) const {
  if (!isRequired && !value.isValid()) return defaultValue;
  return value;
}

const ExtensionProperty *ExtensionSpec::property(const QString &name) const {
  for (const ExtensionProperty &prop : properties) {
    if (prop.name == name) return &prop;
  }
  return nullptr;
}

const ExtensionEventSchema *ExtensionSpec::event(const QString &name) const {
  for (const ExtensionEventSchema &schema : events) {
    if (schema.name == name) return &schema;
  }
  return nullptr;
}

bool ExtensionRegistry::validName(const QString &value) {
  if (value.isEmpty()) return false;
  bool lastWasDash = true; // first char cannot be a dash
  for (const QChar c : value) {
    const bool lower = (c >= u'a' && c <= u'z');
    const bool digit = (c >= u'0' && c <= u'9');
    if (lower || digit) {
      lastWasDash = false;
      continue;
    }
    if (c == u'-' && !lastWasDash) {
      lastWasDash = true;
      continue;
    }
    return false;
  }
  return !lastWasDash; // trailing dash rejected
}

bool ExtensionRegistry::add(const ExtensionSpec &spec, QString *error) {
  ExtensionSpec copy = spec;
  copy.isTweak = false;
  if (!validName(copy.identifier)) {
    *error = QStringLiteral("Invalid extension identifier: %1").arg(copy.identifier);
    return false;
  }
  if (standardNodeName(qPrintable(copy.identifier))) {
    *error = QStringLiteral(
        "Extension identifier %1 shadows a standard node")
        .arg(copy.identifier);
    return false;
  }
  if (copy.fingerprint.isEmpty() || copy.componentSource.isEmpty()) {
    *error = QStringLiteral(
        "Extension %1 requires a fingerprint and componentSource")
        .arg(copy.identifier);
    return false;
  }
  if (copy.isTweak && copy.childIdentifiers.size() != 1) {
    *error = QStringLiteral(
        "Tweak component %1 must list exactly one child identifier")
        .arg(copy.identifier);
    return false;
  }
  if (copy.isTweak && copy.acceptsStandardChildren) {
    *error = QStringLiteral(
        "Tweak component %1 cannot accept standard children")
        .arg(copy.identifier);
    return false;
  }
  QSet<QString> propNames;
  for (const ExtensionProperty &prop : copy.properties) {
    if (prop.name.isEmpty() || propNames.contains(prop.name)) {
      *error = QStringLiteral(
          "Duplicate or empty extension property name in %1")
          .arg(copy.identifier);
      return false;
    }
    propNames.insert(prop.name);
  }
  QSet<QString> eventNames;
  for (const ExtensionEventSchema &event : copy.events) {
    if (!validName(event.name) || eventNames.contains(event.name)) {
      *error = QStringLiteral(
          "Duplicate or invalid extension event name in %1")
          .arg(copy.identifier);
      return false;
    }
    eventNames.insert(event.name);
    QSet<QString> fieldNames;
    for (const ExtensionEventField &field : event.fields) {
      if (field.name.isEmpty() || fieldNames.contains(field.name)) {
        *error = QStringLiteral(
            "Duplicate or empty extension event field in %1.%2")
            .arg(copy.identifier, event.name);
        return false;
      }
      fieldNames.insert(field.name);
    }
  }
  if (m_frozen) {
    const ExtensionSpec *found =
        m_registrations.contains(copy.identifier)
            ? &m_registrations[copy.identifier]
            : nullptr;
    if (found == nullptr || found->fingerprint != copy.fingerprint) {
      *error = QStringLiteral(
          "Cannot register extension %1 after the registry was frozen")
          .arg(copy.identifier);
      return false;
    }
    return true;
  }
  if (m_registrations.contains(copy.identifier)) {
    const ExtensionSpec &existing = m_registrations[copy.identifier];
    if (existing.fingerprint != copy.fingerprint) {
      *error = QStringLiteral(
          "Extension %1 already registered with a different fingerprint")
          .arg(copy.identifier);
      return false;
    }
    // Same fingerprint → idempotent re-registration.
    return true;
  }
  for (auto it = m_registrations.constBegin(); it != m_registrations.constEnd();
       ++it) {
    if (it->fingerprint == copy.fingerprint) {
      *error = QStringLiteral(
          "Extension fingerprint collision between %1 and %2")
          .arg(copy.identifier, it->identifier);
      return false;
    }
  }
  m_registrations.insert(copy.identifier, copy);
  return true;
}

bool ExtensionRegistry::addTweak(const ExtensionSpec &spec, QString *error) {
  ExtensionSpec copy = spec;
  copy.isTweak = true;
  return add(copy, error);
}

const ExtensionSpec *ExtensionRegistry::registration(
    const QString &identifier) const {
  const auto it = m_registrations.constFind(identifier);
  return it == m_registrations.constEnd() ? nullptr : &it.value();
}

bool ExtensionRegistry::freeze(QString *error) {
  m_frozen = true;
  for (auto it = m_registrations.constBegin(); it != m_registrations.constEnd();
       ++it) {
    const ExtensionSpec &spec = it.value();
    if (spec.isTweak) {
      const QString &childId = spec.childIdentifiers.first();
      if (!m_registrations.contains(childId)) {
        *error = QStringLiteral(
            "Tweak component %1 requires child %2")
            .arg(spec.identifier, childId);
        return false;
      }
    }
    for (const QString &childId : spec.childIdentifiers) {
      if (childId == spec.identifier) {
        *error = QStringLiteral(
            "Extension component %1 cannot list itself as a child")
            .arg(spec.identifier);
        return false;
      }
      if (!m_registrations.contains(childId)) {
        *error = QStringLiteral(
            "Extension component %1 requires unknown child %2")
            .arg(spec.identifier, childId);
        return false;
      }
    }
  }
  return true;
}

} // namespace LUI
