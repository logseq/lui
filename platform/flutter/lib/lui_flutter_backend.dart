import 'dart:convert';

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

enum _NodeKind { row, column, text, button, textInput, scroll, spacer }

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
}

final class LUIFlutterBackend extends ChangeNotifier {
  LUIFlutterBackend({this.onEvent});

  final void Function(LUIEvent event)? onEvent;
  Map<int, _NodeState> _states = {};
  int generation = 0;

  static Key nodeKey(int id) => ValueKey('lui-node-$id');

  bool containsNode(int id) => _states.containsKey(id);

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
    _states = next;
    generation = nextGeneration;
    notifyListeners();
  }

  Widget widget({required int node}) {
    _requireState(_states, node);
    return ListenableBuilder(
      listenable: this,
      builder: (context, _) => _buildNode(node),
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

  Widget _buildNode(int id) {
    final state = _requireState(_states, id);
    final children = state.children.map(_buildNode).toList(growable: false);
    final enabled = state.properties['enabled'] as bool? ?? true;
    final text = state.properties['text'] as String? ?? '';
    final gap = (state.properties['gap'] as int? ?? 0).toDouble();
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
      _NodeKind.text => Text(text),
      _NodeKind.button => TextButton(
        onPressed: enabled ? () => performAction(id) : null,
        child: Text(text),
      ),
      _NodeKind.textInput => SizedBox(
        width: 240,
        child: _LUITextInput(
          text: text,
          enabled: enabled,
          onChanged: (value) =>
              onEvent?.call(LUIEvent.textChanged(node: id, text: value)),
        ),
      ),
      _NodeKind.scroll => SingleChildScrollView(
        child: children.isEmpty ? const SizedBox.shrink() : children.single,
      ),
      _NodeKind.spacer => const SizedBox.shrink(),
    };

    return Container(
      key: nodeKey(id),
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
                kind == _NodeKind.button ||
                kind == _NodeKind.textInput),
      'enabled' =>
        value is bool &&
            (kind == _NodeKind.button || kind == _NodeKind.textInput),
      'gap' =>
        value is int && (kind == _NodeKind.row || kind == _NodeKind.column),
      'padding' => value is int,
      'background' => value is String,
      _ => false,
    };
  }

  static bool _canContainChildren(_NodeKind kind) =>
      kind == _NodeKind.row ||
      kind == _NodeKind.column ||
      kind == _NodeKind.scroll;

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

  static _NodeKind _kind(Object? value) => switch (_string(value, 'kind')) {
    'row' => _NodeKind.row,
    'column' => _NodeKind.column,
    'text' => _NodeKind.text,
    'button' => _NodeKind.button,
    'text-input' => _NodeKind.textInput,
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
}

final class _LUITextInput extends StatefulWidget {
  const _LUITextInput({
    required this.text,
    required this.enabled,
    required this.onChanged,
  });

  final String text;
  final bool enabled;
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
    onChanged: widget.onChanged,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}
