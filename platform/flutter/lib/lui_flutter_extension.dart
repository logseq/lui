part of 'lui_flutter_backend.dart';

enum LUIExtensionValueKind {
  string,
  boolean,
  integer,
  doubleValue;

  bool accepts(Object? value) => switch (this) {
    LUIExtensionValueKind.string => value is String,
    LUIExtensionValueKind.boolean => value is bool,
    LUIExtensionValueKind.integer => value is int,
    LUIExtensionValueKind.doubleValue => value is num && value.isFinite,
  };

  Object normalize(Object value) =>
      this == LUIExtensionValueKind.doubleValue && value is int
      ? value.toDouble()
      : value;
}

@immutable
final class LUIExtensionProperty {
  const LUIExtensionProperty({
    required this.name,
    required this.kind,
    this.isRequired = false,
    this.defaultValue,
  });

  final String name;
  final LUIExtensionValueKind kind;
  final bool isRequired;
  final Object? defaultValue;
}

@immutable
final class LUIExtensionEventField {
  const LUIExtensionEventField({
    required this.name,
    required this.kind,
    this.isRequired = false,
  });

  final String name;
  final LUIExtensionValueKind kind;
  final bool isRequired;
}

@immutable
final class LUIExtensionEventSchema {
  const LUIExtensionEventSchema({this.name = '', this.fields = const []});

  final String name;
  final List<LUIExtensionEventField> fields;
}

typedef LUIExtensionWidgetBuilder =
    Widget Function(LUIFlutterExtensionContext context);

@immutable
final class LUIFlutterExtension {
  const LUIFlutterExtension({
    required this.identifier,
    required this.fingerprint,
    required this.builder,
    this.acceptsStandardChildren = false,
    this.childIdentifiers = const [],
    this.properties = const [],
    this.events = const [],
  }) : isTweak = false;

  const LUIFlutterExtension._tweak({
    required this.identifier,
    required this.fingerprint,
    required this.builder,
    required this.properties,
  }) : acceptsStandardChildren = true,
       childIdentifiers = const [],
       events = const [],
       isTweak = true;

  final String identifier;
  final String fingerprint;
  final bool acceptsStandardChildren;
  final List<String> childIdentifiers;
  final List<LUIExtensionProperty> properties;
  final List<LUIExtensionEventSchema> events;
  final bool isTweak;
  final LUIExtensionWidgetBuilder builder;
}

typedef LUITweakWidgetBuilder =
    Widget Function(Widget content, LUIFlutterExtensionContext context);

@immutable
final class LUIFlutterTweak {
  const LUIFlutterTweak({
    required this.identifier,
    required this.fingerprint,
    required this.builder,
    this.properties = const [],
  });

  final String identifier;
  final String fingerprint;
  final List<LUIExtensionProperty> properties;
  final LUITweakWidgetBuilder builder;
}

final class LUIFlutterExtensionRegistry {
  final Map<String, LUIFlutterExtension> _registrations = {};
  bool _isFrozen = false;

  void register(LUIFlutterExtension registration) {
    if (_isFrozen) {
      throw const LUIBackendException('extension registry is frozen');
    }
    if (!_validExtensionName(registration.identifier)) {
      throw const LUIBackendException('invalid extension identifier');
    }
    if (_isStandardNodeName(registration.identifier)) {
      throw const LUIBackendException(
        'extension identifier shadows a standard node',
      );
    }
    if (_registrations.containsKey(registration.identifier)) {
      throw const LUIBackendException(
        'extension identifier is already registered',
      );
    }
    if (!registration.childIdentifiers.every(_validExtensionName)) {
      throw const LUIBackendException('invalid extension child identifier');
    }
    _validateUniqueNames(registration.childIdentifiers, 'child identifier');
    _validateUniqueNames(
      registration.properties.map((property) => property.name),
      'property',
    );
    _validateUniqueNames(
      registration.events.map((event) => event.name),
      'event',
    );
    for (final property in registration.properties) {
      if (!_validExtensionName(property.name)) {
        throw const LUIBackendException('invalid extension property name');
      }
      final value = property.defaultValue;
      if (value != null && !property.kind.accepts(value)) {
        throw const LUIBackendException('invalid extension property default');
      }
    }
    for (final event in registration.events) {
      if (!_validExtensionName(event.name)) {
        throw const LUIBackendException('invalid extension event name');
      }
      _validateUniqueNames(
        event.fields.map((field) => field.name),
        'event field',
      );
      if (!event.fields.every((field) => _validExtensionName(field.name))) {
        throw const LUIBackendException('invalid extension event field name');
      }
    }
    _registrations[registration.identifier] = registration;
  }

  void registerTweak(LUIFlutterTweak tweak) {
    register(
      LUIFlutterExtension._tweak(
        identifier: tweak.identifier,
        fingerprint: tweak.fingerprint,
        properties: tweak.properties,
        builder: (context) => tweak.builder(context.content, context),
      ),
    );
  }

  void _freeze() {
    if (_isFrozen) return;
    for (final registration in _registrations.values) {
      for (final child in registration.childIdentifiers) {
        if (!_registrations.containsKey(child)) {
          throw const LUIBackendException('unknown extension child schema');
        }
      }
    }
    _isFrozen = true;
  }

  LUIFlutterExtension? _registration(String identifier) =>
      _registrations[identifier];

  static void _validateUniqueNames(Iterable<String> names, String label) {
    final values = names.toList(growable: false);
    if (values.toSet().length != values.length) {
      throw LUIBackendException('duplicate extension $label');
    }
  }
}

@immutable
final class LUIExtensionComponentEvent extends LUIEvent {
  const LUIExtensionComponentEvent({
    required this.node,
    required this.identifier,
    required this.name,
    required this.values,
  });

  final int node;
  final String identifier;
  final String name;
  final Map<String, Object> values;

  @override
  bool operator ==(Object other) =>
      other is LUIExtensionComponentEvent &&
      other.node == node &&
      other.identifier == identifier &&
      other.name == name &&
      mapEquals(other.values, values);

  @override
  int get hashCode => Object.hash(
    node,
    identifier,
    name,
    Object.hashAllUnordered(values.entries),
  );
}

final class LUIFlutterExtensionContext {
  const LUIFlutterExtensionContext._(this.nodeID, this._backend);

  final int nodeID;
  final LUIFlutterBackend _backend;

  Object? property(String name) =>
      _backend._requireExtensionState(nodeID).properties[name];

  List<int> get childIDs =>
      List.unmodifiable(_backend._requireExtensionState(nodeID).children);

  Widget get content {
    final children = childIDs;
    return children.length == 1
        ? _backend.widget(node: children.single)
        : const SizedBox.shrink();
  }

  Object? childProperty(int childID, String name) =>
      _backend._requireExtensionState(childID).properties[name];

  void emit({required String name, Map<String, Object> values = const {}}) {
    _backend.performExtensionEvent(nodeID, name: name, values: values);
  }
}

final class _ExtensionNodeState {
  _ExtensionNodeState({
    required this.identifier,
    required this.fingerprint,
    List<int>? children,
    Map<String, Object>? properties,
  }) : parent = null,
       children = children ?? [],
       properties = properties ?? {};

  _ExtensionNodeState.copy(_ExtensionNodeState other)
    : identifier = other.identifier,
      fingerprint = other.fingerprint,
      parent = other.parent,
      children = List.of(other.children),
      properties = Map.of(other.properties);

  final String identifier;
  final String fingerprint;
  int? parent;
  final List<int> children;
  final Map<String, Object> properties;

  bool rendersLike(_ExtensionNodeState other) =>
      identifier == other.identifier &&
      fingerprint == other.fingerprint &&
      parent == other.parent &&
      listEquals(children, other.children) &&
      mapEquals(properties, other.properties);
}

final class _ExtensionNodeHandle extends ChangeNotifier {
  _ExtensionNodeHandle(this.state);

  _ExtensionNodeState state;
  int revision = 0;

  void markChanged() {
    revision += 1;
    notifyListeners();
  }
}

final _extensionNamePattern = RegExp(r'^[a-z0-9]+(?:-[a-z0-9]+)*$');

bool _validExtensionName(String value) => _extensionNamePattern.hasMatch(value);

bool _isStandardNodeName(String value) {
  try {
    _decodeNodeKind(value);
    return true;
  } on LUIBackendException {
    return false;
  }
}
