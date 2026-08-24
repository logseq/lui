import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

sealed class LUIEvent {
  const LUIEvent();

  const factory LUIEvent.press({required int node}) = LUIPressEvent;
  const factory LUIEvent.textChanged({
    required int node,
    required String text,
  }) = LUITextChangedEvent;
}

final class LUIPressEvent extends LUIEvent {
  const LUIPressEvent({required this.node});
  final int node;

  @override
  bool operator ==(Object other) =>
      other is LUIPressEvent && other.node == node;

  @override
  int get hashCode => node.hashCode;
}

final class LUITextChangedEvent extends LUIEvent {
  const LUITextChangedEvent({required this.node, required this.text});
  final int node;
  final String text;

  @override
  bool operator ==(Object other) =>
      other is LUITextChangedEvent && other.node == node && other.text == text;

  @override
  int get hashCode => Object.hash(node, text);
}

final class LUIBackendException implements Exception {
  const LUIBackendException(this.message);
  final String message;

  @override
  String toString() => 'LUIBackendException: $message';
}

enum _NodeKind {
  row,
  column,
  box,
  text,
  heading,
  paragraph,
  button,
  textInput,
  textArea,
  scroll,
  spacer,
}

final class _NodeState {
  _NodeState(this.kind);
  _NodeState.copy(_NodeState other)
    : kind = other.kind,
      parent = other.parent,
      children = List.of(other.children),
      properties = Map.of(other.properties);

  final _NodeKind kind;
  int? parent;
  List<int> children = [];
  Map<String, Object> properties = {};

  bool rendersLike(_NodeState other) =>
      kind == other.kind &&
      listEquals(children, other.children) &&
      mapEquals(properties, other.properties);
}

final class _NodeHandle extends ChangeNotifier {
  _NodeHandle(this.state);

  _NodeState state;
  int revision = 0;

  void markChanged() {
    revision += 1;
    notifyListeners();
  }
}

final class LUIFlutterBackend {
  LUIFlutterBackend({this.onEvent});

  final void Function(LUIEvent event)? onEvent;
  Map<int, _NodeState> _states = {};
  final Map<int, _NodeHandle> _handles = {};
  int generation = 0;

  static Key nodeKey(int id) => ValueKey('lui-node-$id');

  bool containsNode(int id) => _states.containsKey(id);

  int debugRevision(int id) => _requireHandle(id).revision;

  void dispose() {
    for (final handle in _handles.values) {
      handle.dispose();
    }
    _handles.clear();
    _states = {};
  }

  void applyJson(String source) {
    final Object? decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException catch (error) {
      throw LUIBackendException(error.message);
    }
    final batch = _objectMap(decoded, 'patch batch');
    final nextGeneration = _integer(batch['generation'], 'generation');
    final expectedGeneration = generation + 1;
    if (nextGeneration != expectedGeneration) {
      throw LUIBackendException(
        'expected patch generation $expectedGeneration, '
        'received $nextGeneration',
      );
    }
    final operations = _objectList(batch['ops'], 'ops')
        .map((operation) => _objectMap(operation, 'operation'))
        .toList(growable: false);
    final next = {
      for (final entry in _states.entries)
        entry.key: _NodeState.copy(entry.value),
    };

    for (final operation in operations) {
      _applyState(next, operation);
    }
    final changed = <_NodeHandle>[];
    final removed = _handles.keys
        .where((id) => !next.containsKey(id))
        .toList(growable: false);
    for (final entry in next.entries) {
      final handle = _handles[entry.key];
      if (handle == null) {
        _handles[entry.key] = _NodeHandle(entry.value);
      } else {
        if (!handle.state.rendersLike(entry.value)) changed.add(handle);
        handle.state = entry.value;
      }
    }
    for (final id in removed) {
      _handles.remove(id);
    }
    _states = next;
    generation = nextGeneration;
    for (final handle in changed) {
      handle.markChanged();
    }
  }

  Widget widget({required int node}) {
    final handle = _requireHandle(node);
    return ListenableBuilder(
      key: nodeKey(node),
      listenable: handle,
      builder: (context, _) => _buildNode(context, node),
    );
  }

  void performAction(int node) {
    final state = _requireState(_states, node);
    if (state.kind != _NodeKind.button ||
        state.properties['enabled'] == false) {
      throw LUIBackendException('node $node is not an enabled button');
    }
    onEvent?.call(LUIEvent.press(node: node));
  }

  Widget _buildNode(BuildContext context, int id) {
    final state = _requireState(_states, id);
    final children = state.children
        .map((child) => widget(node: child))
        .toList(growable: false);
    final enabled = state.properties['enabled'] as bool? ?? true;
    final text = state.properties['text'] as String? ?? '';
    final placeholder = state.properties['placeholder'] as String?;
    final readOnly = state.properties['read-only'] as bool? ?? false;
    final accessibilityLabel =
        state.properties['accessibility-label'] as String?;
    final gap = (state.properties['gap'] as int? ?? 0).toDouble();
    final headingLevel = state.properties['heading-level'] as int? ?? 1;
    Widget textControl({required bool multiline}) => SizedBox(
      width: 240,
      child: Semantics(
        label: accessibilityLabel,
        textField: true,
        readOnly: readOnly,
        multiline: multiline,
        child: _LUITextInput(
          text: text,
          enabled: enabled,
          readOnly: readOnly,
          placeholder: placeholder,
          minLines: multiline
              ? (state.properties['min-lines'] as int? ?? 2)
              : 1,
          maxLines: multiline ? state.properties['max-lines'] as int? : 1,
          onChanged: (value) =>
              onEvent?.call(LUIEvent.textChanged(node: id, text: value)),
        ),
      ),
    );
    final content = switch (state.kind) {
      _NodeKind.row => Row(
        mainAxisSize: MainAxisSize.min,
        spacing: gap,
        children: children,
      ),
      _NodeKind.column => Column(
        mainAxisSize: MainAxisSize.min,
        spacing: gap,
        children: children,
      ),
      _NodeKind.box => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
      _NodeKind.text => Text(text),
      _NodeKind.heading => Semantics(
        header: true,
        child: Text(text, style: _headingStyle(context, headingLevel)),
      ),
      _NodeKind.paragraph => Text(text),
      _NodeKind.button => TextButton(
        onPressed: enabled ? () => performAction(id) : null,
        child: Text(text),
      ),
      _NodeKind.textInput => textControl(multiline: false),
      _NodeKind.textArea => textControl(multiline: true),
      _NodeKind.scroll => SingleChildScrollView(
        child: children.isEmpty ? const SizedBox.shrink() : children.single,
      ),
      _NodeKind.spacer => const SizedBox.shrink(),
    };

    return Container(
      padding: EdgeInsets.all(
        (state.properties['padding'] as int? ?? 0).toDouble(),
      ),
      color: _color(state.properties['background'] as String?),
      child: content,
    );
  }

  void _applyState(
    Map<int, _NodeState> states,
    Map<String, Object?> operation,
  ) {
    switch (_string(operation['op'], 'op')) {
      case 'create-node':
        final id = _integer(operation['id'], 'id');
        if (states.containsKey(id)) {
          throw const LUIBackendException('node already exists');
        }
        states[id] = _NodeState(_kind(operation['kind']));
      case 'drop-node':
        final id = _integer(operation['id'], 'id');
        final node = _requireState(states, id);
        if (node.parent != null || node.children.isNotEmpty) {
          throw const LUIBackendException('cannot drop an attached node');
        }
        states.remove(id);
      case 'set-prop':
        final node = _requireState(states, _integer(operation['id'], 'id'));
        final property = _string(operation['property'], 'property');
        final value = operation['value'];
        if (!_supports(node.kind, property, value)) {
          throw const LUIBackendException('unsupported property value');
        }
        node.properties[property] = value!;
      case 'insert-child':
        final parentID = _integer(operation['parent'], 'parent');
        final childID = _integer(operation['child'], 'child');
        final index = _integer(operation['index'], 'index');
        final parent = _requireState(states, parentID);
        final child = _requireState(states, childID);
        if (child.parent != null) {
          throw const LUIBackendException('child is already attached');
        }
        if (!_canContainChildren(parent.kind) ||
            (_isSingleChild(parent.kind) && parent.children.isNotEmpty)) {
          throw const LUIBackendException('parent cannot contain child');
        }
        if (index < 0 || index > parent.children.length) {
          throw const LUIBackendException('child index is out of bounds');
        }
        if (_isDescendant(states, target: parentID, root: childID)) {
          throw const LUIBackendException(
            'child insertion would create a cycle',
          );
        }
        parent.children.insert(index, childID);
        child.parent = parentID;
      case 'remove-child':
        final parentID = _integer(operation['parent'], 'parent');
        final childID = _integer(operation['child'], 'child');
        final parent = _requireState(states, parentID);
        final child = _requireState(states, childID);
        if (!parent.children.remove(childID)) {
          throw const LUIBackendException('child is not attached to parent');
        }
        child.parent = null;
      case 'move-child':
        final parent = _requireState(
          states,
          _integer(operation['parent'], 'parent'),
        );
        final childID = _integer(operation['child'], 'child');
        final index = _integer(operation['index'], 'index');
        if (!parent.children.remove(childID)) {
          throw const LUIBackendException('child is not attached to parent');
        }
        if (index < 0 || index > parent.children.length) {
          throw const LUIBackendException('child index is out of bounds');
        }
        parent.children.insert(index, childID);
      default:
        throw const LUIBackendException('unknown patch operation');
    }
  }

  static bool _supports(_NodeKind kind, String property, Object? value) {
    return switch (property) {
      'text' =>
        value is String &&
            (kind == _NodeKind.text ||
                kind == _NodeKind.heading ||
                kind == _NodeKind.paragraph ||
                kind == _NodeKind.button ||
                _isTextControl(kind)),
      'enabled' =>
        value is bool && (kind == _NodeKind.button || _isTextControl(kind)),
      'gap' =>
        value is int && (kind == _NodeKind.row || kind == _NodeKind.column),
      'padding' => value is int,
      'background' => value is String,
      'style-class' => value is String,
      'heading-level' =>
        value is int && value >= 1 && value <= 6 && kind == _NodeKind.heading,
      'placeholder' => value is String && _isTextControl(kind),
      'read-only' => value is bool && _isTextControl(kind),
      'accessibility-label' => value is String && _isTextControl(kind),
      'min-lines' => value is int && value > 0 && kind == _NodeKind.textArea,
      'max-lines' => value is int && value > 0 && kind == _NodeKind.textArea,
      _ => false,
    };
  }

  static bool _canContainChildren(_NodeKind kind) =>
      kind == _NodeKind.row ||
      kind == _NodeKind.column ||
      kind == _NodeKind.box ||
      kind == _NodeKind.scroll;

  static bool _isTextControl(_NodeKind kind) =>
      kind == _NodeKind.textInput || kind == _NodeKind.textArea;

  static bool _isSingleChild(_NodeKind kind) => kind == _NodeKind.scroll;

  static bool _isDescendant(
    Map<int, _NodeState> states, {
    required int target,
    required int root,
  }) {
    if (target == root) return true;
    return _requireState(states, root).children.any(
      (child) => _isDescendant(states, target: target, root: child),
    );
  }

  static _NodeState _requireState(Map<int, _NodeState> states, int id) {
    final node = states[id];
    if (node == null) throw LUIBackendException('unknown node $id');
    return node;
  }

  _NodeHandle _requireHandle(int id) {
    final handle = _handles[id];
    if (handle == null) throw LUIBackendException('unknown node $id');
    return handle;
  }

  static _NodeKind _kind(Object? value) => switch (_string(value, 'kind')) {
    'row' => _NodeKind.row,
    'column' => _NodeKind.column,
    'box' => _NodeKind.box,
    'text' => _NodeKind.text,
    'heading' => _NodeKind.heading,
    'paragraph' => _NodeKind.paragraph,
    'button' => _NodeKind.button,
    'text-input' => _NodeKind.textInput,
    'text-area' => _NodeKind.textArea,
    'scroll' => _NodeKind.scroll,
    'spacer' => _NodeKind.spacer,
    _ => throw const LUIBackendException('unknown node kind'),
  };

  static Map<String, Object?> _objectMap(Object? value, String name) {
    if (value is! Map<String, Object?>) {
      throw LUIBackendException('$name must be an object');
    }
    return value;
  }

  static List<Object?> _objectList(Object? value, String name) {
    if (value is! List<Object?>) {
      throw LUIBackendException('$name must be an array');
    }
    return value;
  }

  static int _integer(Object? value, String name) {
    if (value is! int) throw LUIBackendException('$name must be an integer');
    return value;
  }

  static String _string(Object? value, String name) {
    if (value is! String) throw LUIBackendException('$name must be a string');
    return value;
  }

  static Color? _color(String? name) => switch (name?.toLowerCase()) {
    null => null,
    'black' => Colors.black,
    'white' => Colors.white,
    'red' => Colors.red,
    'blue' => Colors.blue,
    'green' => Colors.green,
    _ => Colors.transparent,
  };

  static TextStyle? _headingStyle(BuildContext context, int level) {
    final textTheme = Theme.of(context).textTheme;
    return switch (level) {
      1 => textTheme.headlineLarge,
      2 => textTheme.headlineMedium,
      3 => textTheme.titleLarge,
      4 => textTheme.titleMedium,
      5 => textTheme.titleSmall,
      _ => textTheme.labelLarge,
    };
  }
}

final class _LUITextInput extends StatefulWidget {
  const _LUITextInput({
    required this.text,
    required this.enabled,
    required this.readOnly,
    required this.placeholder,
    required this.minLines,
    required this.maxLines,
    required this.onChanged,
  });

  final String text;
  final bool enabled;
  final bool readOnly;
  final String? placeholder;
  final int minLines;
  final int? maxLines;
  final ValueChanged<String> onChanged;

  @override
  State<_LUITextInput> createState() => _LUITextInputState();
}

final class _LUITextInputState extends State<_LUITextInput> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.text);
  }

  @override
  void didUpdateWidget(_LUITextInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_controller.text != widget.text) {
      _controller.value = TextEditingValue(
        text: widget.text,
        selection: TextSelection.collapsed(offset: widget.text.length),
      );
    }
  }

  @override
  Widget build(BuildContext context) => TextField(
    controller: _controller,
    enabled: widget.enabled,
    readOnly: widget.readOnly,
    keyboardType: widget.maxLines == 1
        ? TextInputType.text
        : TextInputType.multiline,
    minLines: widget.minLines,
    maxLines: widget.maxLines,
    decoration: InputDecoration(hintText: widget.placeholder),
    onChanged: widget.onChanged,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}
