import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

part 'lui_wire_schema.g.dart';
part 'lui_flutter_extension.dart';

sealed class LUIEvent {
  const LUIEvent();

  const factory LUIEvent.appear({required int node}) = LUIAppearEvent;
  const factory LUIEvent.press({required int node}) = LUIPressEvent;
  const factory LUIEvent.longPress({required int node}) = LUILongPressEvent;
  const factory LUIEvent.textChanged({
    required int node,
    required String text,
  }) = LUITextChangedEvent;
  const factory LUIEvent.submit({required int node}) = LUISubmitEvent;
  const factory LUIEvent.toggleChanged({
    required int node,
    required bool checked,
  }) = LUIToggleChangedEvent;
  const factory LUIEvent.change({required int node}) = LUIChangeEvent;
  const factory LUIEvent.valueChanged({
    required int node,
    required double value,
  }) = LUIValueChangedEvent;
  const factory LUIEvent.dismiss({required int node}) = LUIDismissEvent;
  const factory LUIEvent.doublePress({required int node}) = LUIDoublePressEvent;
  const factory LUIEvent.extension({
    required int node,
    required String identifier,
    required String name,
    required Map<String, Object> values,
  }) = LUIExtensionComponentEvent;
}

@immutable
final class LUIRootSection {
  const LUIRootSection({required this.id, required this.title});

  final int id;
  final String title;

  @override
  bool operator ==(Object other) =>
      other is LUIRootSection && other.id == id && other.title == title;

  @override
  int get hashCode => Object.hash(id, title);
}

final class LUIAppearEvent extends LUIEvent {
  const LUIAppearEvent({required this.node});
  final int node;

  @override
  bool operator ==(Object other) =>
      other is LUIAppearEvent && other.node == node;

  @override
  int get hashCode => node.hashCode;
}

final class LUIDoublePressEvent extends LUIEvent {
  const LUIDoublePressEvent({required this.node});
  final int node;

  @override
  bool operator ==(Object other) =>
      other is LUIDoublePressEvent && other.node == node;

  @override
  int get hashCode => node.hashCode;
}

final class LUIDismissEvent extends LUIEvent {
  const LUIDismissEvent({required this.node});
  final int node;

  @override
  bool operator ==(Object other) =>
      other is LUIDismissEvent && other.node == node;

  @override
  int get hashCode => node.hashCode;
}

final class LUIChangeEvent extends LUIEvent {
  const LUIChangeEvent({required this.node});
  final int node;
  @override
  bool operator ==(Object other) =>
      other is LUIChangeEvent && other.node == node;
  @override
  int get hashCode => node.hashCode;
}

final class LUIValueChangedEvent extends LUIEvent {
  const LUIValueChangedEvent({required this.node, required this.value});
  final int node;
  final double value;
  @override
  bool operator ==(Object other) =>
      other is LUIValueChangedEvent &&
      other.node == node &&
      other.value == value;
  @override
  int get hashCode => Object.hash(node, value);
}

final class LUILongPressEvent extends LUIEvent {
  const LUILongPressEvent({required this.node});
  final int node;

  @override
  bool operator ==(Object other) =>
      other is LUILongPressEvent && other.node == node;

  @override
  int get hashCode => node.hashCode;
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

final class LUISubmitEvent extends LUIEvent {
  const LUISubmitEvent({required this.node});
  final int node;

  @override
  bool operator ==(Object other) =>
      other is LUISubmitEvent && other.node == node;

  @override
  int get hashCode => node.hashCode;
}

final class LUIToggleChangedEvent extends LUIEvent {
  const LUIToggleChangedEvent({required this.node, required this.checked});
  final int node;
  final bool checked;

  @override
  bool operator ==(Object other) =>
      other is LUIToggleChangedEvent &&
      other.node == node &&
      other.checked == checked;

  @override
  int get hashCode => Object.hash(node, checked);
}

final class LUIBackendException implements Exception {
  const LUIBackendException(this.message);
  final String message;

  @override
  String toString() => 'LUIBackendException: $message';
}

const _iconNames = <String>{
  'alert',
  'archive',
  'arrow-down',
  'arrow-right',
  'arrow-up',
  'check',
  'check-circle',
  'chevron-down',
  'chevron-left',
  'chevron-right',
  'chevron-up',
  'circle-dot',
  'clock',
  'copy',
  'download',
  'edit',
  'ellipsis',
  'external-link',
  'eye',
  'file-text',
  'folder',
  'folder-open',
  'git-branch',
  'git-merge',
  'git-pull-request',
  'info',
  'menu',
  'mic',
  'moon',
  'music',
  'panel-left',
  'panel-right',
  'pause',
  'play',
  'plus',
  'refresh-cw',
  'repeat',
  'save',
  'search',
  'send',
  'settings',
  'shuffle',
  'skip-back',
  'skip-forward',
  'sun',
  'terminal',
  'trash',
  'volume',
  'wrench',
  'x',
  'x-circle',
};

final _appIconNamePattern = RegExp(r'^app:[a-z0-9]+(?:-[a-z0-9]+)*$');

IconData _materialIcon(String name) => switch (name) {
  'alert' => Icons.warning_amber,
  'archive' => Icons.archive_outlined,
  'arrow-down' => Icons.arrow_downward,
  'arrow-right' => Icons.arrow_forward,
  'arrow-up' => Icons.arrow_upward,
  'check' => Icons.check,
  'check-circle' => Icons.check_circle_outline,
  'chevron-down' => Icons.keyboard_arrow_down,
  'chevron-left' => Icons.chevron_left,
  'chevron-right' => Icons.chevron_right,
  'chevron-up' => Icons.keyboard_arrow_up,
  'circle-dot' => Icons.radio_button_checked,
  'clock' => Icons.schedule,
  'copy' => Icons.content_copy,
  'download' => Icons.download,
  'edit' => Icons.edit_outlined,
  'ellipsis' => Icons.more_horiz,
  'external-link' => Icons.open_in_new,
  'eye' => Icons.visibility_outlined,
  'file-text' => Icons.description_outlined,
  'folder' => Icons.folder_outlined,
  'folder-open' => Icons.folder_open,
  'git-branch' => Icons.account_tree_outlined,
  'git-merge' => Icons.merge,
  'git-pull-request' => Icons.call_merge,
  'info' => Icons.info_outline,
  'menu' => Icons.menu,
  'mic' => Icons.mic_none,
  'moon' => Icons.dark_mode_outlined,
  'music' => Icons.music_note,
  'panel-left' => Icons.view_sidebar_outlined,
  'panel-right' => Icons.view_sidebar,
  'pause' => Icons.pause,
  'play' => Icons.play_arrow,
  'plus' => Icons.add,
  'refresh-cw' => Icons.refresh,
  'repeat' => Icons.repeat,
  'save' => Icons.save_outlined,
  'search' => Icons.search,
  'send' => Icons.send_outlined,
  'settings' => Icons.settings_outlined,
  'shuffle' => Icons.shuffle,
  'skip-back' => Icons.skip_previous,
  'skip-forward' => Icons.skip_next,
  'sun' => Icons.light_mode_outlined,
  'terminal' => Icons.terminal,
  'trash' => Icons.delete_outline,
  'volume' => Icons.volume_up_outlined,
  'wrench' => Icons.build_outlined,
  'x' => Icons.close,
  'x-circle' => Icons.cancel_outlined,
  _ => Icons.question_mark,
};

Color _mediaSurfacePlaceholderColor(int id) => Color.fromARGB(
  0xff,
  64 + (id * 37) % 64,
  64 + (id * 57) % 64,
  64 + (id * 83) % 64,
);

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
      parent == other.parent &&
      listEquals(children, other.children) &&
      mapEquals(properties, other.properties);
}

final class _NodeHandle extends ChangeNotifier {
  _NodeHandle(int id, this.state)
    : focusNode = FocusNode(debugLabel: 'lui-node-$id');

  _NodeState state;
  final FocusNode focusNode;
  int revision = 0;

  void markChanged() {
    revision += 1;
    notifyListeners();
  }

  void markDependencyChanged() {
    notifyListeners();
  }

  @override
  void dispose() {
    focusNode.dispose();
    super.dispose();
  }
}

final class _LUIAppearDispatcher extends StatefulWidget {
  const _LUIAppearDispatcher({
    super.key,
    required this.node,
    required this.onAppear,
    required this.child,
  });

  final int node;
  final VoidCallback onAppear;
  final Widget child;

  @override
  State<_LUIAppearDispatcher> createState() => _LUIAppearDispatcherState();
}

final class _LUIAppearDispatcherState extends State<_LUIAppearDispatcher> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onAppear();
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

final class LUIFlutterBackend {
  LUIFlutterBackend({
    this.onEvent,
    Map<String, IconData> appIcons = const {},
    LUIFlutterExtensionRegistry? extensionRegistry,
  }) : appIcons = Map.unmodifiable(appIcons),
       _extensionRegistry = extensionRegistry ?? LUIFlutterExtensionRegistry() {
    _extensionRegistry._freeze();
  }

  final void Function(LUIEvent event)? onEvent;
  final Map<String, IconData> appIcons;
  final LUIFlutterExtensionRegistry _extensionRegistry;
  final _LUITooltipSession _tooltipSession = _LUITooltipSession();
  Map<int, _NodeState> _states = {};
  final Map<int, _NodeHandle> _handles = {};
  Map<int, _ExtensionNodeState> _extensionStates = {};
  final Map<int, _ExtensionNodeHandle> _extensionHandles = {};
  final Map<int, ui.Image> _images = {};
  final Map<int, ui.Image> _mediaSurfaces = {};
  int generation = 0;

  static Key nodeKey(int id) => ValueKey('lui-node-$id');

  bool containsNode(int id) =>
      _states.containsKey(id) || _extensionStates.containsKey(id);

  List<LUIRootSection> rootSections(int root) {
    final rootState = _requireState(_states, root);
    final children =
        rootState.kind == _NodeKind.root && rootState.children.length == 1
        ? _requireState(_states, rootState.children.single).children
        : rootState.children;
    return List.unmodifiable(
      children.map(
        (pageID) => LUIRootSection(
          id: pageID,
          title: _firstSectionTitle(pageID) ?? 'Component $pageID',
        ),
      ),
    );
  }

  String? _firstSectionTitle(int node) {
    final state = _states[node];
    if (state != null) {
      final text = state.properties['text'];
      if ((state.kind == _NodeKind.heading || state.kind == _NodeKind.text) &&
          text is String &&
          text.isNotEmpty) {
        return text;
      }
      for (final child in state.children) {
        final title = _firstSectionTitle(child);
        if (title != null) return title;
      }
      return null;
    }
    final extension = _extensionStates[node];
    if (extension == null) return null;
    for (final child in extension.children) {
      final title = _firstSectionTitle(child);
      if (title != null) return title;
    }
    return null;
  }

  int debugRevision(int id) =>
      _handles[id]?.revision ?? _requireExtensionHandle(id).revision;

  IconData _iconData(String name) {
    if (name.startsWith('app:')) {
      return appIcons[name.substring(4)] ?? Icons.question_mark;
    }
    return _materialIcon(name);
  }

  void dispose() {
    for (final handle in _handles.values) {
      handle.dispose();
    }
    _handles.clear();
    for (final handle in _extensionHandles.values) {
      handle.dispose();
    }
    _extensionHandles.clear();
    for (final image in _images.values) {
      image.dispose();
    }
    _images.clear();
    for (final image in _mediaSurfaces.values) {
      image.dispose();
    }
    _mediaSurfaces.clear();
    _states = {};
    _extensionStates = {};
  }

  void registerImage({required int id, required ui.Image image}) {
    if (id <= 0) {
      throw const LUIBackendException('registered image id must be positive');
    }
    final replacement = image.clone();
    final previous = _images[id];
    _images[id] = replacement;
    previous?.dispose();
    _invalidateAvatars(id);
  }

  void unregisterImage(int id) {
    final image = _images.remove(id);
    if (image == null) return;
    image.dispose();
    _invalidateAvatars(id);
  }

  void _invalidateAvatars(int imageID) {
    for (final entry in _states.entries) {
      if ((entry.value.kind == _NodeKind.avatar ||
              entry.value.kind == _NodeKind.image) &&
          entry.value.properties['image'] == imageID) {
        _handles[entry.key]?.markChanged();
      }
    }
  }

  void presentMediaSurfaceFrame({required int id, required ui.Image image}) {
    if (id <= 0) {
      throw const LUIBackendException('media surface id must be positive');
    }
    final replacement = image.clone();
    final previous = _mediaSurfaces[id];
    _mediaSurfaces[id] = replacement;
    previous?.dispose();
    _invalidateMediaSurfaces(id);
  }

  void unregisterMediaSurface(int id) {
    final image = _mediaSurfaces.remove(id);
    if (image == null) return;
    image.dispose();
    _invalidateMediaSurfaces(id);
  }

  void _invalidateMediaSurfaces(int surfaceID) {
    for (final entry in _states.entries) {
      if (entry.value.kind == _NodeKind.mediaSurface &&
          entry.value.properties['surface'] == surfaceID) {
        _handles[entry.key]?.markChanged();
      }
    }
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
    final nextExtensions = {
      for (final entry in _extensionStates.entries)
        entry.key: _ExtensionNodeState.copy(entry.value),
    };

    for (final operation in operations) {
      _applyState(next, nextExtensions, operation);
    }
    _validateStates(next);
    _validateExtensionStates(next, nextExtensions);
    final changedIDs = <int>{};
    final removed = _handles.keys
        .where((id) => !next.containsKey(id))
        .toList(growable: false);
    final removedExtensions = _extensionHandles.keys
        .where((id) => !nextExtensions.containsKey(id))
        .toList(growable: false);
    for (final entry in next.entries) {
      final handle = _handles[entry.key];
      if (handle == null) {
        _handles[entry.key] = _NodeHandle(entry.key, entry.value);
      } else {
        if (!handle.state.rendersLike(entry.value)) {
          changedIDs.add(entry.key);
        }
        handle.state = entry.value;
      }
    }
    for (final id in removed) {
      _handles.remove(id)?.dispose();
    }
    for (final entry in nextExtensions.entries) {
      final handle = _extensionHandles[entry.key];
      if (handle == null) {
        _extensionHandles[entry.key] = _ExtensionNodeHandle(entry.value);
      } else {
        if (!handle.state.rendersLike(entry.value)) {
          changedIDs.add(entry.key);
        }
        handle.state = entry.value;
      }
    }
    for (final id in removedExtensions) {
      _extensionHandles.remove(id)?.dispose();
    }
    _states = next;
    _extensionStates = nextExtensions;
    generation = nextGeneration;
    final changedSources = Set<int>.of(changedIDs);
    final dependentIDs = <int>{};
    for (final source in changedSources) {
      final sourceState = next[source];
      var parent = next[source]?.parent ?? nextExtensions[source]?.parent;
      while (parent != null) {
        final ancestor = next[parent];
        final extensionAncestor = nextExtensions[parent];
        if (ancestor == null && extensionAncestor == null) break;
        if (ancestor?.kind == _NodeKind.radioGroup) changedIDs.add(parent);
        if (ancestor?.kind == _NodeKind.bottomTabs) dependentIDs.add(parent);
        if (ancestor?.kind == _NodeKind.stack &&
            (sourceState?.kind == _NodeKind.dropdownMenu ||
                sourceState?.kind == _NodeKind.tooltip)) {
          changedIDs.add(parent);
        }
        if (extensionAncestor != null) changedIDs.add(parent);
        parent = ancestor?.parent ?? extensionAncestor?.parent;
      }
    }
    for (final id in changedIDs) {
      _handles[id]?.markChanged();
      _extensionHandles[id]?.markChanged();
    }
    for (final id in dependentIDs.difference(changedIDs)) {
      _handles[id]?.markDependencyChanged();
    }
  }

  Widget widget({required int node}) {
    final extensionHandle = _extensionHandles[node];
    if (extensionHandle != null) {
      return ListenableBuilder(
        key: nodeKey(node),
        listenable: extensionHandle,
        builder: (context, _) => _buildExtensionNode(node),
      );
    }
    final handle = _requireHandle(node);
    return ListenableBuilder(
      key: nodeKey(node),
      listenable: handle,
      builder: (context, _) => _withAppear(node, _buildNode(context, node)),
    );
  }

  Widget _withAppear(int node, Widget child) {
    final state = _requireState(_states, node);
    if (state.properties['appear-enabled'] != true) return child;
    return _LUIAppearDispatcher(
      key: ValueKey('lui-appear-$node'),
      node: node,
      onAppear: () => onEvent?.call(LUIEvent.appear(node: node)),
      child: child,
    );
  }

  Widget _buildExtensionNode(int node) {
    final state = _requireExtensionState(node);
    final registration = _extensionRegistry._registration(state.identifier);
    if (registration == null) {
      throw LUIBackendException('unknown extension ${state.identifier}');
    }
    return registration.builder(LUIFlutterExtensionContext._(node, this));
  }

  void performAction(int node) {
    final state = _requireState(_states, node);
    final treeItem = state.properties['role'] == 'treeitem';
    final pressable =
        state.kind == _NodeKind.button ||
        state.kind == _NodeKind.select ||
        state.kind == _NodeKind.combobox ||
        state.kind == _NodeKind.menuItem ||
        state.kind == _NodeKind.listItem ||
        (state.kind == _NodeKind.bottomTab &&
            state.properties['press-enabled'] == true) ||
        (state.kind == _NodeKind.timelineItem &&
            state.properties['press-enabled'] == true) ||
        (treeItem && state.properties['press-enabled'] == true) ||
        (state.kind == _NodeKind.tableCell &&
            state.properties['press-enabled'] == true) ||
        (state.kind == _NodeKind.text &&
            state.properties['press-enabled'] == true);
    if (!pressable || state.properties['enabled'] == false) {
      throw LUIBackendException(
        'node $node is not an enabled pressable control',
      );
    }
    onEvent?.call(LUIEvent.press(node: node));
  }

  void performExtensionEvent(
    int node, {
    required String name,
    Map<String, Object> values = const {},
  }) {
    final state = _requireExtensionState(node);
    final registration = _extensionRegistry._registration(state.identifier);
    if (registration == null) {
      throw LUIBackendException('unknown extension ${state.identifier}');
    }
    final event = registration.events
        .where((candidate) => candidate.name == name)
        .firstOrNull;
    if (event == null) {
      throw const LUIBackendException('unknown extension event');
    }
    final fields = {for (final field in event.fields) field.name: field};
    if (!values.keys.every(fields.containsKey)) {
      throw const LUIBackendException('unknown extension event field');
    }
    for (final field in event.fields) {
      final value = values[field.name];
      if (value == null) {
        if (field.isRequired) {
          throw const LUIBackendException(
            'missing required extension event field',
          );
        }
      } else if (!field.kind.accepts(value)) {
        throw const LUIBackendException('invalid extension event field');
      }
    }
    final normalized = {
      for (final entry in values.entries)
        entry.key: fields[entry.key]!.kind.normalize(entry.value),
    };
    onEvent?.call(
      LUIEvent.extension(
        node: node,
        identifier: state.identifier,
        name: name,
        values: Map.unmodifiable(normalized),
      ),
    );
  }

  void _moveHorizontalFocus(int groupID, LogicalKeyboardKey key) {
    final group = _requireState(_states, groupID);
    final children = group.children
        .where((childID) {
          final child = _requireState(_states, childID);
          return _isHorizontalGroupChild(group.kind, child.kind) &&
              child.properties['enabled'] != false;
        })
        .toList(growable: false);
    if (children.isEmpty) return;

    final current = children.indexWhere(
      (childID) => _requireHandle(childID).focusNode.hasFocus,
    );
    final targetIndex = switch (key) {
      LogicalKeyboardKey.home => 0,
      LogicalKeyboardKey.end => children.length - 1,
      LogicalKeyboardKey.arrowLeft =>
        current < 0 ? 0 : (current + children.length - 1) % children.length,
      _ => current < 0 ? 0 : (current + 1) % children.length,
    };
    _requireHandle(children[targetIndex]).focusNode.requestFocus();
  }

  int? _treeAncestor(int node) {
    var parent = _states[node]?.parent;
    while (parent != null) {
      final state = _states[parent];
      if (state == null) return null;
      if (state.kind == _NodeKind.tree) return parent;
      parent = state.parent;
    }
    return null;
  }

  List<int> _treeItems(int tree) {
    final result = <int>[];
    void visit(int node) {
      final state = _requireState(_states, node);
      if (state.properties['role'] == 'treeitem' &&
          state.properties['enabled'] != false) {
        result.add(node);
      }
      for (final child in state.children) {
        visit(child);
      }
    }

    for (final child in _requireState(_states, tree).children) {
      visit(child);
    }
    return result;
  }

  int _treeLevel(int tree, int node) {
    final explicit = _states[node]?.properties['tree-level'] as int?;
    if (explicit != null) return explicit;
    var level = 1;
    var parent = _states[node]?.parent;
    while (parent != null && parent != tree) {
      if (_states[parent]?.properties['role'] == 'treeitem') level += 1;
      parent = _states[parent]?.parent;
    }
    return level;
  }

  int? _treeTabstop(int tree) {
    final items = _treeItems(tree);
    if (items.isEmpty) return null;
    return items.firstWhere(
      (node) => _states[node]?.properties['selected'] == true,
      orElse: () => items.first,
    );
  }

  void _selectTreeItem(int node) {
    final state = _requireState(_states, node);
    _requireHandle(node).focusNode.requestFocus();
    if (state.properties['change-enabled'] == true) {
      performChange(node);
    } else if (state.properties['press-enabled'] == true) {
      performAction(node);
    }
  }

  void _performTreeTap(int node) {
    final state = _requireState(_states, node);
    if (state.properties['enabled'] == false) return;
    if (state.properties['press-enabled'] == true) {
      performAction(node);
    } else if (state.properties['change-enabled'] == true) {
      performChange(node);
    }
    if (state.properties['toggle-enabled'] == true) {
      performToggle(node, state.properties['expanded'] != true);
    }
  }

  void _performTreeKey(int tree, int node, LogicalKeyboardKey key) {
    final items = _treeItems(tree);
    final index = items.indexOf(node);
    if (index < 0) return;
    if (key == LogicalKeyboardKey.arrowUp && index > 0) {
      _selectTreeItem(items[index - 1]);
    } else if (key == LogicalKeyboardKey.arrowDown &&
        index + 1 < items.length) {
      _selectTreeItem(items[index + 1]);
    } else if (key == LogicalKeyboardKey.home) {
      _selectTreeItem(items.first);
    } else if (key == LogicalKeyboardKey.end) {
      _selectTreeItem(items.last);
    } else if (key == LogicalKeyboardKey.arrowLeft) {
      final state = _requireState(_states, node);
      if (state.properties['expanded'] == true &&
          state.properties['toggle-enabled'] == true) {
        performToggle(node, false);
        return;
      }
      final level = _treeLevel(tree, node);
      for (var candidate = index - 1; candidate >= 0; candidate -= 1) {
        if (_treeLevel(tree, items[candidate]) == level - 1) {
          _selectTreeItem(items[candidate]);
          return;
        }
      }
    } else if (key == LogicalKeyboardKey.arrowRight) {
      final state = _requireState(_states, node);
      if (state.properties['expanded'] == false &&
          state.properties['toggle-enabled'] == true) {
        performToggle(node, true);
      } else if (index + 1 < items.length &&
          _treeLevel(tree, items[index + 1]) == _treeLevel(tree, node) + 1) {
        _selectTreeItem(items[index + 1]);
      }
    }
  }

  void performDoublePress(int node) {
    final state = _requireState(_states, node);
    if (state.kind != _NodeKind.listItem ||
        state.properties['enabled'] == false ||
        state.properties['double-press-enabled'] != true) {
      throw LUIBackendException(
        'node $node is not an enabled double-press control',
      );
    }
    onEvent?.call(LUIEvent.doublePress(node: node));
  }

  void performSubmit(int node) {
    final state = _requireState(_states, node);
    if (state.kind != _NodeKind.listItem ||
        state.properties['enabled'] == false ||
        state.properties['submit-enabled'] != true) {
      throw LUIBackendException('node $node is not an enabled submit control');
    }
    onEvent?.call(LUIEvent.submit(node: node));
  }

  void performLongPress(int node) {
    final state = _requireState(_states, node);
    if (!(_isButtonKind(state.kind) || state.kind == _NodeKind.listItem) ||
        state.properties['enabled'] == false ||
        state.properties['long-press-enabled'] != true) {
      throw LUIBackendException('node $node is not enabled for long press');
    }
    onEvent?.call(LUIEvent.longPress(node: node));
  }

  void performToggle(int node, bool checked) {
    final state = _requireState(_states, node);
    final treeItem = state.properties['role'] == 'treeitem';
    final isToggle =
        state.kind == _NodeKind.toggleButton ||
        state.kind == _NodeKind.toggle ||
        state.kind == _NodeKind.accordion ||
        state.kind == _NodeKind.drawer ||
        treeItem;
    final hasHandler =
        (state.kind != _NodeKind.accordion &&
            state.kind != _NodeKind.drawer &&
            !treeItem) ||
        state.properties['toggle-enabled'] == true;
    if (!isToggle || state.properties['enabled'] == false || !hasHandler) {
      throw LUIBackendException('node $node is not an enabled toggle button');
    }
    onEvent?.call(LUIEvent.toggleChanged(node: node, checked: checked));
  }

  void performChange(int node) {
    final state = _requireState(_states, node);
    if ((state.kind != _NodeKind.radio &&
            state.properties['role'] != 'treeitem') ||
        state.properties['enabled'] == false) {
      throw LUIBackendException('node $node is not an enabled change control');
    }
    if (state.properties['change-enabled'] == true) {
      if (state.properties['checked'] != true) {
        onEvent?.call(LUIEvent.change(node: node));
      }
    } else if (state.properties['toggle-enabled'] == true) {
      onEvent?.call(LUIEvent.toggleChanged(node: node, checked: true));
    } else if (state.properties['press-enabled'] == true) {
      onEvent?.call(LUIEvent.press(node: node));
    }
  }

  void performValueChange(int node, double value) {
    final state = _requireState(_states, node);
    if ((state.kind != _NodeKind.slider && state.kind != _NodeKind.split) ||
        state.properties['enabled'] == false ||
        !value.isFinite) {
      throw LUIBackendException('node $node is not an enabled value control');
    }
    onEvent?.call(LUIEvent.valueChanged(node: node, value: value.clamp(0, 1)));
  }

  void performDismiss(int node) {
    final state = _requireState(_states, node);
    if (state.kind != _NodeKind.select &&
        state.kind != _NodeKind.combobox &&
        state.kind != _NodeKind.dropdownMenu &&
        state.kind != _NodeKind.toast &&
        !state.kind.isModalSurface) {
      throw LUIBackendException('node $node is not dismissible');
    }
    onEvent?.call(LUIEvent.dismiss(node: node));
  }

  Widget _buildNode(BuildContext context, int id) {
    final state = _requireState(_states, id);
    final contextMenuID = state.children.cast<int?>().firstWhere(
      (childID) =>
          childID != null && _states[childID]?.kind == _NodeKind.contextMenu,
      orElse: () => null,
    );
    final children = state.children
        .where((child) => child != contextMenuID)
        .map((child) {
          final childWidget = widget(node: child);
          final childState = _states[child];
          if (state.kind == _NodeKind.row &&
              childState?.kind == _NodeKind.bubble &&
              childState?.properties['variant'] != 'ghost' &&
              childState?.properties.containsKey('width') == false) {
            return Flexible(child: childWidget);
          }
          if (state.kind != _NodeKind.row &&
              state.kind != _NodeKind.column &&
              state.kind != _NodeKind.list &&
              state.kind != _NodeKind.virtualList &&
              state.kind != _NodeKind.inputGroupActions) {
            return childWidget;
          }
          final grow = childState?.properties['grow'] as num? ?? 0;
          if (grow <= 0) return childWidget;
          final scaled = (grow * 1000).round();
          return Expanded(flex: scaled < 1 ? 1 : scaled, child: childWidget);
        })
        .toList(growable: false);
    final enabled = state.properties['enabled'] as bool? ?? true;
    final text = state.properties['text'] as String? ?? '';
    final placeholder = state.properties['placeholder'] as String?;
    final accessibilityLabel =
        state.properties['accessibility-label'] as String?;
    final accessibilityIdentifier =
        state.properties['accessibility-identifier'] as String?;
    final checked = state.properties['checked'] as bool? ?? false;
    final progressFraction = ((state.properties['value'] as double?) ?? 0)
        .clamp(0.0, 1.0);
    final orientation =
        state.properties['orientation'] as String? ?? 'horizontal';
    final foreground = _color(
      context,
      state.properties['foreground'] as String?,
    );
    final background = _color(
      context,
      state.properties['background'] as String?,
    );
    final borderColor = _color(
      context,
      state.properties['border-color'] as String?,
    );
    final borderWidth = state.properties['border-width'] as int?;
    final cornerRadius = state.properties['corner-radius'] as int?;
    final gap =
        (state.properties['gap'] as int? ??
                (_isHorizontalGroupKind(state.kind)
                    ? _horizontalGroupDefaultGap(state.kind)
                    : 0))
            .toDouble();
    final main = state.properties['main'] as String? ?? 'start';
    final cross =
        state.properties['cross'] as String? ??
        (_isHorizontalGroupKind(state.kind) ? 'center' : 'stretch');
    final headingLevel = state.properties['heading-level'] as int? ?? 1;
    final spinnerExtent = switch (state.properties['size'] as String? ??
        'default') {
      'sm' => 16.0,
      'lg' => 24.0,
      _ => 20.0,
    };
    final iconExtent = switch (state.properties['size'] as String? ??
        'default') {
      'sm' => 16.0,
      'lg' => 24.0,
      'icon' => 24.0,
      _ => 18.0,
    };
    final buttonVariant = state.properties['variant'] as String? ?? 'default';
    final buttonSize = state.properties['size'] as String? ?? 'default';
    final buttonIcon = state.properties['icon'] as String?;
    final buttonIconPlacement =
        state.properties['icon-placement'] as String? ?? 'leading';
    final buttonSelected = state.properties['selected'] as bool? ?? false;
    final buttonAutofocus = state.properties['autofocus'] as bool? ?? false;
    final longPressEnabled =
        state.properties['long-press-enabled'] as bool? ?? false;
    final isTabTrigger =
        state.kind == _NodeKind.button &&
        state.parent != null &&
        _states[state.parent]?.kind == _NodeKind.tabs;
    Widget textControl({required _NodeKind kind}) {
      final multiline = kind == _NodeKind.textarea;
      final combobox = kind == _NodeKind.combobox;
      final grouped =
          state.parent != null &&
          _states[state.parent]?.kind == _NodeKind.inputGroup;
      return SizedBox(
        width: grouped ? double.infinity : 240,
        child: Semantics(
          label: accessibilityLabel,
          textField: true,
          readOnly: false,
          multiline: multiline,
          child: _LUITextInput(
            text: text,
            enabled: enabled,
            placeholder: placeholder,
            foreground: foreground,
            autofocus: state.properties['autofocus'] as bool? ?? false,
            multiline: multiline,
            secure: kind == _NodeKind.secureField,
            search: kind == _NodeKind.searchField,
            grouped: grouped,
            onOpen: combobox && enabled ? () => performAction(id) : null,
            submitOnEnter:
                state.properties['submit-on-enter'] as bool? ?? false,
            onChanged: (value) =>
                onEvent?.call(LUIEvent.textChanged(node: id, text: value)),
            onSubmitted: (_) => state.properties['submit-enabled'] == true
                ? onEvent?.call(LUIEvent.submit(node: id))
                : combobox
                ? performAction(id)
                : onEvent?.call(LUIEvent.submit(node: id)),
          ),
        ),
      );
    }

    Widget toggleSemantics({required bool asSwitch, required Widget child}) {
      final label = accessibilityLabel?.isNotEmpty ?? false
          ? accessibilityLabel
          : (text.isEmpty ? null : text);
      return Semantics(
        label: label,
        enabled: enabled,
        checked: asSwitch ? null : checked,
        toggled: asSwitch ? checked : null,
        onTap: enabled
            ? () => onEvent?.call(
                LUIEvent.toggleChanged(node: id, checked: !checked),
              )
            : null,
        excludeSemantics: true,
        child: child,
      );
    }

    Widget buttonLabel() {
      final icon = buttonIcon == null
          ? null
          : Icon(_iconData(buttonIcon), size: iconExtent);
      if (text.isEmpty) return icon ?? const SizedBox.shrink();
      if (icon == null) return Text(text);
      return Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 8,
        children: buttonIconPlacement == 'trailing'
            ? [Text(text), icon]
            : [icon, Text(text)],
      );
    }

    ButtonStyle buttonStyle({Color? backgroundColor}) {
      final dimensions = switch (buttonSize) {
        'sm' => (const Size(0, 36), const EdgeInsets.symmetric(horizontal: 12)),
        'lg' => (const Size(0, 44), const EdgeInsets.symmetric(horizontal: 32)),
        'icon' => (const Size.square(48), EdgeInsets.zero),
        _ => (const Size(0, 40), const EdgeInsets.symmetric(horizontal: 16)),
      };
      return ButtonStyle(
        minimumSize: WidgetStatePropertyAll(dimensions.$1),
        padding: WidgetStatePropertyAll(dimensions.$2),
        foregroundColor: foreground == null
            ? null
            : WidgetStatePropertyAll(foreground),
        backgroundColor: backgroundColor == null
            ? null
            : WidgetStatePropertyAll(backgroundColor),
      );
    }

    Widget button({
      required bool selected,
      required VoidCallback? onPressed,
      Key? semanticsKey,
    }) {
      final onLongPress = enabled && longPressEnabled
          ? () => performLongPress(id)
          : null;
      final colors = Theme.of(context).colorScheme;
      final selectedColor = selected ? colors.secondaryContainer : null;
      final style = buttonStyle(backgroundColor: selectedColor);
      final label = buttonLabel();
      final tabStyle = ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(Size(0, 32)),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 12),
        ),
        foregroundColor: WidgetStatePropertyAll(foreground ?? colors.onSurface),
        backgroundColor: WidgetStatePropertyAll(
          selected ? colors.surface : Colors.transparent,
        ),
        elevation: WidgetStatePropertyAll(selected ? 1 : 0),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        ),
      );
      final materialButton = isTabTrigger
          ? TextButton(
              onPressed: onPressed,
              onLongPress: onLongPress,
              autofocus: buttonAutofocus,
              focusNode: _requireHandle(id).focusNode,
              style: tabStyle,
              child: label,
            )
          : switch (buttonVariant) {
              'primary' => FilledButton(
                onPressed: onPressed,
                onLongPress: onLongPress,
                autofocus: buttonAutofocus,
                focusNode: _requireHandle(id).focusNode,
                style: style,
                child: label,
              ),
              'secondary' => FilledButton.tonal(
                onPressed: onPressed,
                onLongPress: onLongPress,
                autofocus: buttonAutofocus,
                focusNode: _requireHandle(id).focusNode,
                style: style,
                child: label,
              ),
              'outline' => OutlinedButton(
                onPressed: onPressed,
                onLongPress: onLongPress,
                autofocus: buttonAutofocus,
                focusNode: _requireHandle(id).focusNode,
                style: style,
                child: label,
              ),
              'destructive' => FilledButton(
                onPressed: onPressed,
                onLongPress: onLongPress,
                autofocus: buttonAutofocus,
                focusNode: _requireHandle(id).focusNode,
                style: buttonStyle(backgroundColor: colors.error),
                child: label,
              ),
              _ => TextButton(
                onPressed: onPressed,
                onLongPress: onLongPress,
                autofocus: buttonAutofocus,
                focusNode: _requireHandle(id).focusNode,
                style: style,
                child: label,
              ),
            };
      return Semantics(
        key: semanticsKey ?? (isTabTrigger ? ValueKey('lui-tab-$id') : null),
        label: accessibilityLabel?.isNotEmpty ?? false
            ? accessibilityLabel
            : (text.isEmpty ? null : text),
        button: true,
        selected: selected,
        enabled: enabled,
        onTap: onPressed,
        onLongPress: onLongPress,
        excludeSemantics: true,
        child: materialButton,
      );
    }

    Widget toggleButton() => _LUIToggleSelection(
      modelSelected: state.properties['selected'] as bool?,
      builder: (context, selected, setSelected) => button(
        selected: selected,
        semanticsKey: ValueKey('lui-toggle-$id'),
        onPressed: enabled
            ? () {
                final next = !selected;
                setSelected(next);
                performToggle(id, next);
              }
            : null,
      ),
    );

    Widget grid() => LayoutBuilder(
      builder: (context, constraints) {
        final requested = state.properties['columns'] as int? ?? 0;
        final columns = requested > 0
            ? requested
            : (children.isEmpty ? 1 : children.length);
        final available = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : 0.0;
        final cellWidth = available > 0
            ? (available - gap * (columns - 1)) / columns
            : 0.0;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: children
              .map(
                (child) => cellWidth > 0
                    ? SizedBox(width: cellWidth, child: child)
                    : child,
              )
              .toList(growable: false),
        );
      },
    );
    Widget row() => LayoutBuilder(
      builder: (context, constraints) => Row(
        mainAxisSize: constraints.hasBoundedWidth
            ? MainAxisSize.max
            : MainAxisSize.min,
        mainAxisAlignment: _mainAxisAlignment(main),
        crossAxisAlignment: _crossAxisAlignment(
          cross,
          canStretch: constraints.hasBoundedHeight,
        ),
        spacing: gap,
        children: children,
      ),
    );
    Widget horizontalGroup() => CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
            _moveHorizontalFocus(id, LogicalKeyboardKey.arrowLeft),
        const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
            _moveHorizontalFocus(id, LogicalKeyboardKey.arrowRight),
        const SingleActivator(LogicalKeyboardKey.home): () =>
            _moveHorizontalFocus(id, LogicalKeyboardKey.home),
        const SingleActivator(LogicalKeyboardKey.end): () =>
            _moveHorizontalFocus(id, LogicalKeyboardKey.end),
      },
      child: LayoutBuilder(
        builder: (context, constraints) {
          final expandsForAlignment =
              state.properties.containsKey('main') &&
              constraints.hasBoundedWidth;
          return Semantics(
            container: true,
            label: accessibilityLabel,
            child: Row(
              mainAxisSize: expandsForAlignment
                  ? MainAxisSize.max
                  : MainAxisSize.min,
              mainAxisAlignment: _mainAxisAlignment(main),
              crossAxisAlignment: _crossAxisAlignment(
                cross,
                canStretch: constraints.hasBoundedHeight,
              ),
              spacing: gap,
              children: children,
            ),
          );
        },
      ),
    );
    Widget column() => LayoutBuilder(
      builder: (context, constraints) => Column(
        mainAxisSize: constraints.hasBoundedHeight
            ? MainAxisSize.max
            : MainAxisSize.min,
        mainAxisAlignment: _mainAxisAlignment(main),
        crossAxisAlignment: _crossAxisAlignment(
          cross,
          canStretch: constraints.hasBoundedWidth,
        ),
        spacing: gap,
        children: children,
      ),
    );
    Widget stack() {
      final menuID = state.children.cast<int?>().firstWhere(
        (childID) =>
            childID != null && _states[childID]?.kind == _NodeKind.dropdownMenu,
        orElse: () => null,
      );
      final tooltipID = state.children.cast<int?>().firstWhere(
        (childID) =>
            childID != null &&
            _states[childID]?.kind == _NodeKind.tooltip &&
            _states[childID]?.properties.containsKey('anchor') == true,
        orElse: () => null,
      );
      final menuState = menuID == null ? null : _requireState(_states, menuID);
      final tooltipState = tooltipID == null
          ? null
          : _requireState(_states, tooltipID);
      final triggerChildren = state.children
          .where((childID) => childID != menuID && childID != tooltipID)
          .map((childID) => widget(node: childID))
          .toList(growable: false);
      Widget trigger = Stack(
        clipBehavior: Clip.none,
        children: triggerChildren,
      );
      if (tooltipState != null) {
        trigger = _LUIRetainedTooltip(
          session: _tooltipSession,
          message: tooltipState.properties['text'] as String? ?? '',
          waitDuration: Duration(
            milliseconds:
                tooltipState.properties['tooltip-delay'] as int? ?? 600,
          ),
          exitDuration: const Duration(milliseconds: 400),
          preferBelow: tooltipState.properties['anchor'] != 'above',
          verticalOffset:
              (tooltipState.properties['anchor-offset'] as num?)?.toDouble() ??
              4,
          enableTapToDismiss: true,
          child: trigger,
        );
      }
      return _LUIAnchoredStack(
        anchor: menuState?.properties['anchor'] as String? ?? 'below',
        alignment:
            menuState?.properties['anchor-alignment'] as String? ?? 'start',
        offset:
            (menuState?.properties['anchor-offset'] as num?)?.toDouble() ?? 0,
        menuID: menuID,
        menuChildren:
            menuState?.children
                .map((childID) => widget(node: childID))
                .toList(growable: false) ??
            const <Widget>[],
        minimumWidth: (menuState?.properties['min-width'] as num?)?.toDouble(),
        maximumWidth: (menuState?.properties['max-width'] as num?)?.toDouble(),
        onDismiss: menuID == null ? null : () => performDismiss(menuID),
        trigger: trigger,
      );
    }

    Widget select() => Semantics(
      label: accessibilityLabel,
      child: OutlinedButton(
        onPressed: enabled ? () => performAction(id) : null,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Expanded(
              child: Text(
                text.isEmpty ? placeholder ?? '' : text,
                style: text.isEmpty
                    ? TextStyle(color: Theme.of(context).hintColor)
                    : null,
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.arrow_drop_down),
          ],
        ),
      ),
    );
    Widget dropdownMenu() => CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            performDismiss(id),
      },
      child: Focus(
        autofocus: true,
        child: TapRegion(
          groupId: state.parent,
          onTapOutside: (_) => performDismiss(id),
          child: Material(
            elevation: 8,
            borderRadius: BorderRadius.circular(8),
            clipBehavior: Clip.antiAlias,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: gap,
              children: children,
            ),
          ),
        ),
      ),
    );
    Widget menuItem() {
      final submenuID = state.children.cast<int?>().firstWhere(
        (childID) =>
            childID != null && _states[childID]?.kind == _NodeKind.dropdownMenu,
        orElse: () => null,
      );
      final menuItemIconExtent =
          switch (state.properties['size'] as String? ?? 'default') {
        'sm' => 16.0,
        'lg' => 28.0,
        _ => 16.0,
      };
      final leadingIcon = buttonIcon == null
          ? null
          : Icon(_iconData(buttonIcon), size: menuItemIconExtent);
      if (submenuID != null) {
        final submenu = _requireState(_states, submenuID);
        return SubmenuButton(
          useRootOverlay: true,
          animated: true,
          leadingIcon: leadingIcon,
          menuChildren: enabled
              ? submenu.children
                    .map((childID) => widget(node: childID))
                    .toList(growable: false)
              : const <Widget>[],
          child: Text(text),
        );
      }
      final destructive = buttonVariant == 'destructive';
      final menuItemText = Text(
        text,
        style: destructive
            ? TextStyle(color: Theme.of(context).colorScheme.error)
            : null,
      );
      return MergeSemantics(
        child: Semantics(
          selected: buttonSelected,
          child: MenuItemButton(
            onPressed: enabled ? () => performAction(id) : null,
            leadingIcon: leadingIcon,
            trailingIcon: buttonSelected ? const Icon(Icons.check) : null,
            child: menuItemText,
          ),
        ),
      );
    }

    Widget listItem() => _LUIListItem(
      enabled: enabled,
      focusable: state.properties['role'] != 'treeitem',
      selected: buttonSelected,
      leading: buttonIcon == null
          ? null
          : Icon(_iconData(buttonIcon), size: 16),
      content: children.isEmpty
          ? Text(text)
          : children.length == 1
          ? children.single
          : Row(children: children),
      onPress:
          state.properties['role'] == 'treeitem' &&
              (state.properties['press-enabled'] == true ||
                  state.properties['change-enabled'] == true ||
                  state.properties['toggle-enabled'] == true)
          ? () => _performTreeTap(id)
          : state.properties['press-enabled'] == true
          ? () => performAction(id)
          : null,
      onDoublePress: state.properties['double-press-enabled'] == true
          ? () => performDoublePress(id)
          : null,
      onLongPress: longPressEnabled ? () => performLongPress(id) : null,
      onSubmit: state.properties['submit-enabled'] == true
          ? () => performSubmit(id)
          : null,
    );
    Widget table() => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
    Widget tree() => FocusTraversalGroup(
      child: Semantics(
        container: true,
        label: accessibilityLabel,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: gap,
          children: children,
        ),
      ),
    );
    Widget tableRow() {
      final columnWidths = <int, TableColumnWidth>{};
      for (var index = 0; index < state.children.length; index += 1) {
        final cell = _requireState(_states, state.children[index]);
        final grow = (cell.properties['grow'] as num?)?.toDouble() ?? 0;
        columnWidths[index] = grow > 0
            ? FlexColumnWidth(grow)
            : const IntrinsicColumnWidth();
      }
      final paddedCells = children
          .map(
            (child) => Padding(
              padding: EdgeInsets.symmetric(horizontal: gap / 2),
              child: child,
            ),
          )
          .toList(growable: false);
      final parent = state.parent == null ? null : _states[state.parent];
      final isLast = parent == null || parent.children.last == id;
      return Semantics(
        container: true,
        selected: buttonSelected,
        child: _LUITableRowSurface(
          selected: buttonSelected,
          showDivider: !isLast,
          child: Table(
            defaultVerticalAlignment: TableCellVerticalAlignment.middle,
            columnWidths: columnWidths,
            children: [TableRow(children: paddedCells)],
          ),
        ),
      );
    }

    Widget tableCell() {
      final alignment = switch (state.properties['text-alignment']) {
        'center' => Alignment.center,
        'end' => Alignment.centerRight,
        _ => Alignment.centerLeft,
      };
      final textAlign = switch (state.properties['text-alignment']) {
        'center' => TextAlign.center,
        'end' => TextAlign.end,
        _ => TextAlign.start,
      };
      final label = Align(
        alignment: alignment,
        child: Text(
          text,
          textAlign: textAlign,
          style: _textStyleForSize(
            context,
            state.properties['size'] as String?,
          )?.copyWith(color: foreground),
        ),
      );
      if (state.properties['press-enabled'] != true) return label;
      return Semantics(
        button: true,
        child: InkWell(
          onTap: () => performAction(id),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: label,
          ),
        ),
      );
    }

    Widget accordion() => _LUIAccordion(
      expanded: buttonSelected,
      title: text,
      onToggle: state.properties['toggle-enabled'] == true
          ? (value) => performToggle(id, value)
          : null,
      children: children,
    );
    Widget alert() => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 8,
      children: [
        if (text.isNotEmpty)
          Text(text, style: Theme.of(context).textTheme.titleSmall),
        Stack(children: children),
      ],
    );
    Widget bubble() {
      final reactionAlignment = switch (state.properties['text-alignment']) {
        'start' => Alignment.centerLeft,
        'center' => Alignment.center,
        _ => Alignment.centerRight,
      };
      return IntrinsicWidth(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Stack(children: children),
            if (text.isNotEmpty)
              Align(
                alignment: reactionAlignment,
                child: Chip(
                  label: Text(text),
                  labelStyle: Theme.of(context).textTheme.labelSmall,
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
          ],
        ),
      );
    }

    Widget statusBar() => Align(
      alignment: switch (state.properties['text-alignment']) {
        'center' => Alignment.center,
        'end' => Alignment.centerRight,
        _ => Alignment.centerLeft,
      },
      child: Text(
        text,
        textAlign: switch (state.properties['text-alignment']) {
          'center' => TextAlign.center,
          'end' => TextAlign.end,
          _ => TextAlign.start,
        },
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: foreground ?? Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
    Widget textNode() {
      final label = Text(
        text,
        textAlign: switch (state.properties['text-alignment']) {
          'center' => TextAlign.center,
          'end' => TextAlign.end,
          _ => TextAlign.start,
        },
        style: _textStyleForSize(
          context,
          state.properties['size'] as String?,
        )?.copyWith(color: foreground),
      );
      if (state.properties['press-enabled'] != true) return label;
      return TextButton(
        onPressed: () => performAction(id),
        focusNode: _requireHandle(id).focusNode,
        style: TextButton.styleFrom(
          foregroundColor: foreground,
          minimumSize: Size.zero,
          padding: EdgeInsets.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: label,
      );
    }

    Widget avatar() {
      final imageID = state.properties['image'] as int? ?? 0;
      final image = imageID == 0 ? null : _images[imageID];
      final sourceX = (state.properties['source-x'] as num?)?.toDouble();
      final sourceY = (state.properties['source-y'] as num?)?.toDouble();
      final sourceWidth = (state.properties['source-width'] as num?)
          ?.toDouble();
      final sourceHeight = (state.properties['source-height'] as num?)
          ?.toDouble();
      final source = sourceX == null
          ? null
          : Rect.fromLTWH(sourceX, sourceY!, sourceWidth!, sourceHeight!);
      final imageBounds = image == null
          ? null
          : Rect.fromLTWH(
              0,
              0,
              image.width.toDouble(),
              image.height.toDouble(),
            );
      final displayImage =
          source == null ||
              imageBounds == null ||
              (source.left >= imageBounds.left &&
                  source.top >= imageBounds.top &&
                  source.right <= imageBounds.right &&
                  source.bottom <= imageBounds.bottom)
          ? image
          : null;
      return Semantics(
        label: accessibilityLabel ?? text,
        image: true,
        excludeSemantics: true,
        child: ClipOval(
          child: SizedBox.square(
            dimension: 40,
            child: displayImage == null
                ? ColoredBox(
                    color: Theme.of(context).colorScheme.secondaryContainer,
                    child: Center(
                      child: Text(
                        text,
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                    ),
                  )
                : CustomPaint(
                    painter: _LUIAvatarPainter(
                      image: displayImage,
                      source: source,
                    ),
                  ),
          ),
        ),
      );
    }

    Rect? imageSource(ui.Image? image) {
      if (image == null || !state.properties.containsKey('source-x')) {
        return null;
      }
      final requested = Rect.fromLTWH(
        (state.properties['source-x'] as num).toDouble(),
        (state.properties['source-y'] as num).toDouble(),
        (state.properties['source-width'] as num).toDouble(),
        (state.properties['source-height'] as num).toDouble(),
      );
      final bounds = Rect.fromLTWH(
        0,
        0,
        image.width.toDouble(),
        image.height.toDouble(),
      );
      final clipped = requested.intersect(bounds);
      return clipped.isEmpty ? null : clipped;
    }

    Widget image() {
      final imageID = state.properties['image'] as int;
      final pixels = imageID == 0 ? null : _images[imageID];
      final source = imageSource(pixels);
      final hasDrawablePixels =
          pixels != null &&
          (!state.properties.containsKey('source-x') || source != null);
      return Semantics(
        label: accessibilityLabel,
        image: accessibilityLabel != null,
        excludeSemantics: true,
        child: !hasDrawablePixels
            ? const SizedBox.expand()
            : CustomPaint(
                painter: _LUIImagePainter(image: pixels, source: source),
              ),
      );
    }

    Widget mediaSurface() {
      final surfaceID = state.properties['surface'] as int;
      final frame = surfaceID == 0 ? null : _mediaSurfaces[surfaceID];
      return Semantics(
        label: accessibilityLabel,
        image: accessibilityLabel != null,
        excludeSemantics: true,
        child: frame == null
            ? surfaceID == 0
                  ? const SizedBox.expand()
                  : ColoredBox(color: _mediaSurfacePlaceholderColor(surfaceID))
            : RawImage(image: frame, fit: BoxFit.fill),
      );
    }

    Widget step() {
      final parent = state.parent == null ? null : _states[state.parent];
      final index = parent?.children.indexOf(id) ?? 0;
      final count = parent?.children.length ?? 1;
      final active = parent?.properties['active'] as int? ?? 0;
      final stepState = index < active
          ? 'completed'
          : index == active
          ? 'active'
          : 'pending';
      final activeColor = Theme.of(context).colorScheme.primary;
      return Semantics(
        label: '$text ($stepState)',
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 24,
              height: 24,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: stepState == 'pending' ? null : activeColor,
                border: Border.all(
                  color: stepState == 'pending'
                      ? Theme.of(context).colorScheme.outline
                      : activeColor,
                ),
              ),
              child: stepState == 'completed'
                  ? Icon(
                      Icons.check,
                      size: 14,
                      color: Theme.of(context).colorScheme.onPrimary,
                    )
                  : Text(
                      '${index + 1}',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: stepState == 'active'
                            ? Theme.of(context).colorScheme.onPrimary
                            : Theme.of(context).colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
            ),
            const SizedBox(width: 6),
            Text(
              text,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: stepState == 'pending'
                    ? Theme.of(context).colorScheme.onSurfaceVariant
                    : null,
                fontWeight: stepState == 'active'
                    ? FontWeight.w600
                    : FontWeight.normal,
              ),
            ),
            if (index + 1 < count) ...[
              const SizedBox(width: 8),
              Container(
                width: 24,
                height: 1,
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
              const SizedBox(width: 8),
            ],
          ],
        ),
      );
    }

    Widget timelineItem() {
      final title = state.properties['title'] as String? ?? '';
      final description = state.properties['description'] as String? ?? '';
      final meta = state.properties['meta'] as String? ?? '';
      final indicator = state.properties['indicator'] as String? ?? '';
      final icon = state.properties['icon'] as String? ?? '';
      final connector = state.properties['connector'] as bool? ?? true;
      final pressable = state.properties['press-enabled'] == true;
      final variantColor = switch (buttonVariant) {
        'primary' => Theme.of(context).colorScheme.primary,
        'destructive' => Theme.of(context).colorScheme.error,
        _ => Theme.of(context).colorScheme.outline,
      };
      Widget marker;
      if (icon.isNotEmpty) {
        marker = Icon(_iconData(icon), size: 16, color: variantColor);
      } else if (indicator.isNotEmpty) {
        marker = Text(
          indicator,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: variantColor,
            fontWeight: FontWeight.w600,
          ),
        );
      } else {
        marker = Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: variantColor,
          ),
        );
      }
      final row = Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: buttonSelected
              ? Theme.of(context).colorScheme.secondaryContainer
              : null,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 24,
              child: Column(
                children: [
                  SizedBox(width: 24, height: 24, child: Center(child: marker)),
                  if (connector)
                    Container(
                      width: 1,
                      height: 28,
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  if (description.isNotEmpty)
                    Text(
                      description,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  if (meta.isNotEmpty)
                    Text(
                      meta,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
            if (pressable)
              Icon(
                Icons.chevron_right,
                size: 18,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
          ],
        ),
      );
      return Semantics(
        label: title,
        selected: buttonSelected,
        button: pressable,
        child: pressable
            ? GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => performAction(id),
                child: row,
              )
            : row,
      );
    }

    Widget inputGroup() {
      final editor = children.first;
      final editorBody = state.properties.containsKey('height')
          ? Expanded(child: editor)
          : editor;
      return Semantics(
        container: true,
        label: accessibilityLabel,
        child: _LUIInputGroupSurface(
          child: Column(
            mainAxisSize: state.properties.containsKey('height')
                ? MainAxisSize.max
                : MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [editorBody, if (children.length == 2) children[1]],
          ),
        ),
      );
    }

    Widget inputGroupActions() => Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
      child: Row(
        mainAxisSize: MainAxisSize.max,
        crossAxisAlignment: CrossAxisAlignment.center,
        spacing: gap,
        children: children,
      ),
    );

    Widget bottomTabs() {
      final destinationIDs = state.children;
      final selectedIndex = destinationIDs.indexWhere(
        (nodeID) =>
            _requireState(_states, nodeID).properties['selected'] == true,
      );
      final currentIndex = selectedIndex < 0 ? 0 : selectedIndex;
      return Semantics(
        container: true,
        label: accessibilityLabel,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: widget(node: destinationIDs[currentIndex])),
            NavigationBar(
              selectedIndex: currentIndex,
              onDestinationSelected: (index) {
                final destinationID = destinationIDs[index];
                final destination = _requireState(_states, destinationID);
                if (destination.properties['enabled'] != false &&
                    destination.properties['press-enabled'] == true) {
                  performAction(destinationID);
                }
              },
              destinations: destinationIDs
                  .map(
                    (nodeID) => NavigationDestination(
                      icon: Icon(
                        _iconData(
                          _requireState(_states, nodeID).properties['icon']
                                  as String? ??
                              '',
                        ),
                      ),
                      label:
                          _requireState(_states, nodeID).properties['title']
                              as String? ??
                          '',
                      enabled:
                          _requireState(
                            _states,
                            nodeID,
                          ).properties['enabled'] !=
                          false,
                    ),
                  )
                  .toList(growable: false),
            ),
          ],
        ),
      );
    }

    final content = switch (state.kind) {
      _NodeKind.root => children.single,
      _NodeKind.row => row(),
      _NodeKind.tabs ||
      _NodeKind.buttonGroup ||
      _NodeKind.toggleGroup ||
      _NodeKind.breadcrumb ||
      _NodeKind.pagination => horizontalGroup(),
      _NodeKind.bottomTabs => bottomTabs(),
      _NodeKind.bottomTab => Stack(children: children),
      _NodeKind.column || _NodeKind.list => column(),
      _NodeKind.virtualList => ListView.separated(
        itemCount: state.children.length,
        itemBuilder: (context, index) => widget(node: state.children[index]),
        separatorBuilder: (context, index) => SizedBox(height: gap),
      ),
      _NodeKind.grid => grid(),
      _NodeKind.stack => stack(),
      _NodeKind.panel ||
      _NodeKind.card ||
      _NodeKind.resizable => Stack(children: children),
      _NodeKind.alert => alert(),
      _NodeKind.bubble => bubble(),
      _NodeKind.drawer => _LUIDrawer(
        sourcePresented: state.properties['selected'] as bool? ?? false,
        enabled: enabled,
        width: (state.properties['width'] as int? ?? 320).toDouble(),
        label: accessibilityLabel ?? (text.isEmpty ? 'Navigation' : text),
        onChanged: state.properties['toggle-enabled'] == true
            ? (presented) => performToggle(id, presented)
            : null,
        main: children[0],
        panel: children[1],
      ),
      _NodeKind.split => _LUISplit(
        sourceFraction: (state.properties['value'] as double?) ?? 0,
        gap: (state.properties['gap'] as int? ?? 9).toDouble(),
        firstMinimum:
            (_states[state.children[0]]?.properties['min-width'] as int? ?? 0)
                .toDouble(),
        secondMinimum:
            (_states[state.children[1]]?.properties['min-width'] as int? ?? 0)
                .toDouble(),
        duration: Duration(
          milliseconds: state.properties['resize-duration'] as int? ?? 0,
        ),
        easing: state.properties['resize-easing'] as String? ?? 'standard',
        origin: state.properties['resize-origin'] as double?,
        label: accessibilityLabel ?? 'Split',
        onChanged: (value) => performValueChange(id, value),
        first: children[0],
        second: children[1],
      ),
      _NodeKind.box => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
      _NodeKind.text => textNode(),
      _NodeKind.heading => Semantics(
        header: true,
        child: Text(
          text,
          style: _headingStyle(
            context,
            headingLevel,
          )?.copyWith(color: foreground),
        ),
      ),
      _NodeKind.paragraph => Text(text, style: TextStyle(color: foreground)),
      _NodeKind.label => Text(text, style: TextStyle(color: foreground)),
      _NodeKind.button => button(
        selected: buttonSelected,
        onPressed: enabled ? () => performAction(id) : null,
      ),
      _NodeKind.toggleButton => toggleButton(),
      _NodeKind.select => select(),
      _NodeKind.combobox => textControl(kind: state.kind),
      _NodeKind.dropdownMenu => dropdownMenu(),
      _NodeKind.contextMenu => const SizedBox.shrink(),
      _NodeKind.tooltip => Text(text),
      _NodeKind.toast => _LUIToast(
        node: id,
        duration: Duration(
          milliseconds: state.properties['duration'] as int? ?? 0,
        ),
        label: accessibilityLabel ?? 'Notification',
        onDismiss: () => performDismiss(id),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              spacing: 12,
              children: children,
            ),
          ),
        ),
      ),
      _NodeKind.toolbar => Semantics(
        container: true,
        label: accessibilityLabel,
        child: orientation == 'vertical'
            ? Column(
                mainAxisSize: MainAxisSize.min,
                spacing: gap,
                children: children,
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                spacing: gap,
                children: children,
              ),
      ),
      _NodeKind.accordion => accordion(),
      _NodeKind.dialog ||
      _NodeKind.sheet => _LUIModalPresenter(backend: this, node: id),
      _NodeKind.menuItem => menuItem(),
      _NodeKind.listItem => listItem(),
      _NodeKind.table => table(),
      _NodeKind.tree => tree(),
      _NodeKind.tableRow => tableRow(),
      _NodeKind.tableCell => tableCell(),
      _NodeKind.avatar => avatar(),
      _NodeKind.image => image(),
      _NodeKind.mediaSurface => mediaSurface(),
      _NodeKind.stepper => Semantics(
        label: accessibilityLabel,
        child: Row(mainAxisSize: MainAxisSize.min, children: children),
      ),
      _NodeKind.step => step(),
      _NodeKind.timeline => Semantics(
        label: accessibilityLabel,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: gap,
          children: children,
        ),
      ),
      _NodeKind.timelineItem => timelineItem(),
      _NodeKind.inputGroup => inputGroup(),
      _NodeKind.inputGroupActions => inputGroupActions(),
      _NodeKind.toggle => FilterChip(
        label: Text(text),
        selected: checked,
        onSelected: enabled ? (value) => performToggle(id, value) : null,
      ),
      _NodeKind.radioGroup => RadioGroup<int>(
        groupValue: _checkedRadio(state),
        onChanged: (value) {
          if (value != null) performChange(value);
        },
        child: Row(mainAxisSize: MainAxisSize.min, children: children),
      ),
      _NodeKind.radio => MergeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Radio<int>(value: id, enabled: enabled),
            InkWell(
              onTap: enabled ? () => performChange(id) : null,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(text),
              ),
            ),
          ],
        ),
      ),
      _NodeKind.slider => Slider(
        value: ((state.properties['value'] as num?)?.toDouble() ?? 0).clamp(
          0,
          1,
        ),
        onChanged: enabled ? (value) => performValueChange(id, value) : null,
      ),
      _NodeKind.textField ||
      _NodeKind.secureField ||
      _NodeKind.input ||
      _NodeKind.searchField ||
      _NodeKind.textarea => textControl(kind: state.kind),
      _NodeKind.checkbox => toggleSemantics(
        asSwitch: false,
        child: CheckboxListTile(
          value: checked,
          onChanged: enabled
              ? (value) => onEvent?.call(
                  LUIEvent.toggleChanged(node: id, checked: value ?? false),
                )
              : null,
          title: Text(text),
          controlAffinity: ListTileControlAffinity.leading,
          contentPadding: EdgeInsets.zero,
          dense: true,
        ),
      ),
      _NodeKind.switchControl => toggleSemantics(
        asSwitch: true,
        child: SwitchListTile(
          value: checked,
          onChanged: enabled
              ? (value) => onEvent?.call(
                  LUIEvent.toggleChanged(node: id, checked: value),
                )
              : null,
          title: Text(text),
          controlAffinity: ListTileControlAffinity.leading,
          contentPadding: EdgeInsets.zero,
          dense: true,
        ),
      ),
      _NodeKind.progress => LinearProgressIndicator(
        value: progressFraction,
        semanticsLabel: accessibilityLabel,
        semanticsValue: '${(progressFraction * 100).round()}%',
      ),
      _NodeKind.divider =>
        orientation == 'vertical'
            ? const VerticalDivider(width: 1)
            : const Divider(height: 1),
      _NodeKind.scroll => SingleChildScrollView(
        child: Stack(children: children),
      ),
      _NodeKind.spacer => const SizedBox.shrink(),
      _NodeKind.spinner => SizedBox.square(
        dimension: spinnerExtent,
        child: CircularProgressIndicator(strokeWidth: 2, color: foreground),
      ),
      _NodeKind.icon => Icon(
        _iconData(state.properties['name'] as String? ?? ''),
        size: iconExtent,
        color: foreground,
      ),
      _NodeKind.statusBar => statusBar(),
    };

    if (state.kind == _NodeKind.root || state.kind.isModalSurface) {
      return accessibilityIdentifier == null
          ? content
          : Semantics(identifier: accessibilityIdentifier, child: content);
    }

    final isSurface = state.kind.isOverlaySurface;
    final padding =
        state.properties['padding'] as int? ??
        (state.kind == _NodeKind.card
            ? 24
            : state.kind == _NodeKind.alert
            ? 16
            : state.kind == _NodeKind.bubble
            ? 12
            : state.kind == _NodeKind.tabs
            ? 4
            : 0);
    final paddingHorizontal =
        state.properties['padding-horizontal'] as int? ?? padding;
    final paddingVertical =
        state.properties['padding-vertical'] as int? ?? padding;
    final effectiveBorderWidth = borderWidth ?? (isSurface ? 1 : 0);
    final effectiveCornerRadius =
        cornerRadius ??
        (isSurface
            ? 12
            : state.kind == _NodeKind.tabs
            ? 8
            : 0);
    final contentPadding = EdgeInsets.symmetric(
      horizontal: paddingHorizontal.toDouble(),
      vertical: paddingVertical.toDouble(),
    );
    Widget surface = isSurface
        ? Material(
            color:
                background ??
                (state.kind == _NodeKind.bubble && buttonVariant == 'primary'
                    ? Theme.of(context).colorScheme.primary
                    : state.kind == _NodeKind.bubble && buttonVariant == 'ghost'
                    ? Colors.transparent
                    : state.kind == _NodeKind.alert &&
                          buttonVariant == 'destructive'
                    ? Theme.of(context).colorScheme.errorContainer
                    : Theme.of(context).colorScheme.surface),
            elevation: state.kind == _NodeKind.panel ? 1 : 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(
                effectiveCornerRadius.toDouble(),
              ),
              side: effectiveBorderWidth == 0
                  ? BorderSide.none
                  : BorderSide(
                      color:
                          borderColor ??
                          Theme.of(context).colorScheme.outlineVariant,
                      width: effectiveBorderWidth.toDouble(),
                    ),
            ),
            clipBehavior: Clip.antiAlias,
            child: Padding(padding: contentPadding, child: content),
          )
        : Container(
            padding: contentPadding,
            decoration: BoxDecoration(
              color:
                  background ??
                  (state.kind == _NodeKind.tabs
                      ? Theme.of(context).colorScheme.secondaryContainer
                      : null),
              border: effectiveBorderWidth == 0
                  ? null
                  : Border.all(
                      color: borderColor ?? Colors.transparent,
                      width: effectiveBorderWidth.toDouble(),
                    ),
              borderRadius: effectiveCornerRadius == 0
                  ? null
                  : BorderRadius.circular(effectiveCornerRadius.toDouble()),
            ),
            child: content,
          );
    if (state.kind == _NodeKind.bubble &&
        buttonVariant != 'ghost' &&
        !state.properties.containsKey('width')) {
      final bubbleSurface = surface;
      surface = LayoutBuilder(
        builder: (context, constraints) => constraints.hasBoundedWidth
            ? ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: constraints.maxWidth * 0.8,
                ),
                child: bubbleSurface,
              )
            : bubbleSurface,
      );
    }
    if (state.kind == _NodeKind.resizable) {
      surface = _LUIResizable(
        initialWidth: (state.properties['width'] as int?)?.toDouble(),
        minimumWidth: (state.properties['min-width'] as int?)?.toDouble(),
        maximumWidth: (state.properties['max-width'] as int?)?.toDouble(),
        label: accessibilityLabel ?? 'Resizable',
        child: surface,
      );
    }
    final width =
        state.kind == _NodeKind.resizable || state.kind == _NodeKind.drawer
        ? null
        : state.properties['width'] as int?;
    final height = state.properties['height'] as int?;
    if (width != null || height != null) {
      surface = SizedBox(
        width: width?.toDouble(),
        height: height?.toDouble(),
        child: surface,
      );
    }
    final minWidth = state.kind == _NodeKind.resizable
        ? null
        : state.properties['min-width'] as int?;
    final maxWidth = state.kind == _NodeKind.resizable
        ? null
        : state.properties['max-width'] as int?;
    final minHeight = state.properties['min-height'] as int?;
    final maxHeight = state.properties['max-height'] as int?;
    if (minWidth != null ||
        maxWidth != null ||
        minHeight != null ||
        maxHeight != null) {
      surface = ConstrainedBox(
        constraints: BoxConstraints(
          minWidth: minWidth?.toDouble() ?? 0,
          maxWidth: maxWidth?.toDouble() ?? double.infinity,
          minHeight: minHeight?.toDouble() ?? 0,
          maxHeight: maxHeight?.toDouble() ?? double.infinity,
        ),
        child: surface,
      );
    }
    if (state.properties['role'] == 'treeitem') {
      final tree = _treeAncestor(id)!;
      final shortcuts = <ShortcutActivator, VoidCallback>{
        for (final key in const [
          LogicalKeyboardKey.arrowUp,
          LogicalKeyboardKey.arrowDown,
          LogicalKeyboardKey.arrowLeft,
          LogicalKeyboardKey.arrowRight,
          LogicalKeyboardKey.home,
          LogicalKeyboardKey.end,
        ])
          SingleActivator(key): () => _performTreeKey(tree, id, key),
      };
      if (state.properties['press-enabled'] == true) {
        shortcuts[const SingleActivator(LogicalKeyboardKey.enter)] = () =>
            performAction(id);
        shortcuts[const SingleActivator(LogicalKeyboardKey.space)] = () =>
            performAction(id);
        if (state.kind != _NodeKind.listItem) {
          surface = GestureDetector(
            onTap: () => _performTreeTap(id),
            child: surface,
          );
        }
      } else if (state.kind != _NodeKind.listItem &&
          (state.properties['change-enabled'] == true ||
              state.properties['toggle-enabled'] == true)) {
        surface = GestureDetector(
          onTap: () => _performTreeTap(id),
          child: surface,
        );
      }
      surface = Semantics(
        container: true,
        selected: buttonSelected,
        expanded: state.properties['expanded'] as bool?,
        enabled: enabled,
        child: CallbackShortcuts(
          bindings: shortcuts,
          child: Focus(
            focusNode: _requireHandle(id).focusNode,
            canRequestFocus: enabled,
            skipTraversal: id != _treeTabstop(tree),
            child: surface,
          ),
        ),
      );
    }
    if (contextMenuID != null) {
      final menu = _requireState(_states, contextMenuID);
      Future<void> showContextMenu(Offset position) async {
        final selected = await showMenu<int>(
          context: context,
          position: RelativeRect.fromLTRB(
            position.dx,
            position.dy,
            position.dx,
            position.dy,
          ),
          items: menu.children
              .map<PopupMenuEntry<int>>((childID) {
                final child = _requireState(_states, childID);
                if (child.kind == _NodeKind.divider) {
                  return const PopupMenuDivider();
                }
                return PopupMenuItem<int>(
                  value: childID,
                  enabled: child.properties['enabled'] as bool? ?? true,
                  child: Text(child.properties['text'] as String? ?? ''),
                );
              })
              .toList(growable: false),
        );
        if (selected != null) performAction(selected);
      }

      surface = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onSecondaryTapDown: (details) =>
            showContextMenu(details.globalPosition),
        onLongPressStart: (details) => showContextMenu(details.globalPosition),
        child: surface,
      );
    }
    return accessibilityIdentifier == null
        ? surface
        : Semantics(identifier: accessibilityIdentifier, child: surface);
  }

  void _applyState(
    Map<int, _NodeState> states,
    Map<int, _ExtensionNodeState> extensions,
    Map<String, Object?> operation,
  ) {
    switch (_string(operation['op'], 'op')) {
      case 'create-node':
        final id = _integer(operation['id'], 'id');
        if (_containsState(states, extensions, id)) {
          throw const LUIBackendException('node already exists');
        }
        states[id] = _NodeState(_decodeNodeKind(operation['kind']));
      case 'create-extension':
        final id = _integer(operation['id'], 'id');
        if (_containsState(states, extensions, id)) {
          throw const LUIBackendException('node already exists');
        }
        final identifier = _string(operation['identifier'], 'identifier');
        final fingerprint = _string(operation['fingerprint'], 'fingerprint');
        final registration = _extensionRegistry._registration(identifier);
        if (registration == null) {
          throw const LUIBackendException('unknown extension');
        }
        if (registration.fingerprint != fingerprint) {
          throw const LUIBackendException('extension fingerprint mismatch');
        }
        extensions[id] = _ExtensionNodeState(
          identifier: identifier,
          fingerprint: fingerprint,
          properties: {
            for (final property in registration.properties)
              if (property.defaultValue != null)
                property.name: property.kind.normalize(property.defaultValue!),
          },
        );
      case 'drop-node':
        final id = _integer(operation['id'], 'id');
        final parent = _nodeParent(states, extensions, id);
        final children = _nodeChildren(states, extensions, id);
        if (parent != null || children.isNotEmpty) {
          throw const LUIBackendException('cannot drop an attached node');
        }
        if (states.remove(id) == null && extensions.remove(id) == null) {
          throw LUIBackendException('unknown node $id');
        }
      case 'set-prop':
        final node = _requireState(states, _integer(operation['id'], 'id'));
        final property = _string(operation['property'], 'property');
        final value = operation['value'];
        if (!_supports(node.kind, property, value)) {
          throw LUIBackendException(
            'unsupported property value: ${node.kind.name}.$property',
          );
        }
        node.properties[property] = value!;
      case 'remove-prop':
        final node = _requireState(states, _integer(operation['id'], 'id'));
        final property = _string(operation['property'], 'property');
        if (!node.properties.containsKey(property)) {
          throw LUIBackendException(
            'unsupported property: ${node.kind.name}.$property',
          );
        }
        node.properties.remove(property);
      case 'set-extension-prop':
        final node = _requireExtensionStateFrom(
          extensions,
          _integer(operation['id'], 'id'),
        );
        final propertyName = _string(operation['property'], 'property');
        final registration = _extensionRegistry._registration(node.identifier)!;
        final property = registration.properties
            .where((candidate) => candidate.name == propertyName)
            .firstOrNull;
        final value = operation['value'];
        if (property == null ||
            value == null ||
            !property.kind.accepts(value)) {
          throw const LUIBackendException(
            'unsupported extension property value',
          );
        }
        node.properties[propertyName] = property.kind.normalize(value);
      case 'remove-extension-prop':
        final node = _requireExtensionStateFrom(
          extensions,
          _integer(operation['id'], 'id'),
        );
        final propertyName = _string(operation['property'], 'property');
        final registration = _extensionRegistry._registration(node.identifier)!;
        final property = registration.properties
            .where((candidate) => candidate.name == propertyName)
            .firstOrNull;
        if (property == null) {
          throw const LUIBackendException('unknown extension property');
        }
        if (property.defaultValue == null) {
          node.properties.remove(propertyName);
        } else {
          node.properties[propertyName] = property.kind.normalize(
            property.defaultValue!,
          );
        }
      case 'insert-child':
        final parentID = _integer(operation['parent'], 'parent');
        final childID = _integer(operation['child'], 'child');
        final index = _integer(operation['index'], 'index');
        if (!_containsState(states, extensions, parentID) ||
            !_containsState(states, extensions, childID)) {
          throw const LUIBackendException('unknown parent or child node');
        }
        if (_nodeParent(states, extensions, childID) != null) {
          throw const LUIBackendException('child is already attached');
        }
        _validateChildRelationship(states, extensions, parentID, childID);
        final children = _nodeChildren(states, extensions, parentID);
        if (index < 0 || index > children.length) {
          throw const LUIBackendException('child index is out of bounds');
        }
        if (_isDescendantAny(
          states,
          extensions,
          target: parentID,
          root: childID,
        )) {
          throw const LUIBackendException(
            'child insertion would create a cycle',
          );
        }
        children.insert(index, childID);
        _setNodeParent(states, extensions, childID, parentID);
      case 'remove-child':
        final parentID = _integer(operation['parent'], 'parent');
        final childID = _integer(operation['child'], 'child');
        final children = _nodeChildren(states, extensions, parentID);
        if (!children.remove(childID)) {
          throw const LUIBackendException('child is not attached to parent');
        }
        _setNodeParent(states, extensions, childID, null);
      case 'move-child':
        final parentID = _integer(operation['parent'], 'parent');
        final children = _nodeChildren(states, extensions, parentID);
        final childID = _integer(operation['child'], 'child');
        final index = _integer(operation['index'], 'index');
        if (!children.remove(childID)) {
          throw const LUIBackendException('child is not attached to parent');
        }
        if (index < 0 || index > children.length) {
          throw const LUIBackendException('child index is out of bounds');
        }
        children.insert(index, childID);
      default:
        throw const LUIBackendException('unknown patch operation');
    }
  }

  void _validateChildRelationship(
    Map<int, _NodeState> states,
    Map<int, _ExtensionNodeState> extensions,
    int parentID,
    int childID,
  ) {
    if (states[childID]?.kind == _NodeKind.root) {
      throw const LUIBackendException('runtime root cannot be nested');
    }
    final transparentChild = extensions[childID];
    if (transparentChild != null &&
        _extensionRegistry
            ._registration(transparentChild.identifier)!
            .isTweak) {
      if (transparentChild.children.length != 1) {
        throw const LUIBackendException(
          'platform tweak requires exactly one child',
        );
      }
      _validateChildRelationship(
        states,
        extensions,
        parentID,
        transparentChild.children.single,
      );
      return;
    }
    final parent = states[parentID];
    final child = states[childID];
    if (parent != null && child == null) {
      if (!_acceptsExtensionChildren(parent.kind)) {
        throw const LUIBackendException(
          'standard node cannot contain extension',
        );
      }
      return;
    }
    final extensionParent = extensions[parentID];
    final extensionChild = extensions[childID];
    if (extensionParent != null) {
      final registration = _extensionRegistry._registration(
        extensionParent.identifier,
      )!;
      if (registration.isTweak) {
        if (extensionParent.children.isNotEmpty) {
          throw const LUIBackendException(
            'platform tweak requires exactly one child',
          );
        }
        return;
      }
      if (child != null) {
        if (!registration.acceptsStandardChildren) {
          throw const LUIBackendException(
            'extension does not accept standard children',
          );
        }
        return;
      }
      if (extensionChild == null ||
          !registration.childIdentifiers.contains(extensionChild.identifier)) {
        throw const LUIBackendException(
          'extension child relationship is not registered',
        );
      }
      return;
    }
    if (parent == null || child == null) {
      throw const LUIBackendException('unknown parent or child node');
    }
    if (!_canContainChildren(parent.kind)) {
      throw const LUIBackendException('parent cannot contain child');
    }
    if ((parent.kind == _NodeKind.dropdownMenu ||
            parent.kind == _NodeKind.contextMenu) &&
        child.kind != _NodeKind.menuItem &&
        child.kind != _NodeKind.divider) {
      throw const LUIBackendException(
        'menu accepts only menu-item or separator children',
      );
    }
    if (parent.kind == _NodeKind.menuItem &&
        child.kind != _NodeKind.contextMenu &&
        child.kind != _NodeKind.dropdownMenu) {
      throw const LUIBackendException(
        'menu-item accepts only nested menu metadata',
      );
    }
    if (parent.kind != _NodeKind.menuItem &&
        _isContextMenuLeafHost(parent.kind) &&
        child.kind != _NodeKind.contextMenu) {
      throw const LUIBackendException(
        'interactive leaf accepts only context-menu metadata',
      );
    }
    if (parent.kind == _NodeKind.table && child.kind != _NodeKind.tableRow) {
      throw const LUIBackendException('table can contain only table-row');
    }
    if (parent.kind == _NodeKind.tableRow &&
        child.kind != _NodeKind.tableCell) {
      throw const LUIBackendException('table-row can contain only table-cell');
    }
    if (parent.kind == _NodeKind.tree && !_isTreeRowKind(child.kind)) {
      throw const LUIBackendException('tree accepts only row containers');
    }
    if (parent.kind == _NodeKind.stepper && child.kind != _NodeKind.step) {
      throw const LUIBackendException('stepper accepts only step children');
    }
    if (parent.kind == _NodeKind.timeline &&
        child.kind != _NodeKind.timelineItem) {
      throw const LUIBackendException(
        'timeline accepts only timeline-item children',
      );
    }
    if (parent.kind == _NodeKind.bottomTabs &&
        child.kind != _NodeKind.bottomTab) {
      throw const LUIBackendException(
        'bottom-tabs accepts only bottom-tab children',
      );
    }
    if (parent.kind == _NodeKind.bottomTab &&
        child.kind == _NodeKind.bottomTab) {
      throw const LUIBackendException(
        'bottom-tab cannot directly contain bottom-tab',
      );
    }
    if (parent.kind == _NodeKind.inputGroup &&
        child.kind != _NodeKind.textarea &&
        child.kind != _NodeKind.inputGroupActions) {
      throw const LUIBackendException(
        'input-group accepts only textarea and input-group-actions children',
      );
    }
    if (parent.kind == _NodeKind.toolbar && !_isToolbarChild(child.kind)) {
      throw const LUIBackendException(
        'toolbar accepts only interactive controls and dividers',
      );
    }
  }

  static bool _supports(_NodeKind kind, String property, Object? value) {
    if (property == 'accessibility-identifier') return value is String;
    if (kind == _NodeKind.root) return false;
    if (kind == _NodeKind.contextMenu) return false;
    if (kind == _NodeKind.accordion) {
      return switch (property) {
        'text' => value is String,
        'selected' || 'toggle-enabled' => value is bool,
        'height' => value is int && value >= 0,
        _ => false,
      };
    }
    if (kind == _NodeKind.stepper) {
      return switch (property) {
        'active' => value is int && value >= 0,
        'accessibility-label' => value is String,
        _ => false,
      };
    }
    if (kind == _NodeKind.step) {
      return property == 'text' && value is String;
    }
    if (kind == _NodeKind.timeline) {
      return switch (property) {
        'gap' => value is int && value >= 0,
        'grow' => value is num && value.isFinite && value >= 0,
        'accessibility-label' => value is String,
        _ => false,
      };
    }
    if (kind == _NodeKind.timelineItem) {
      return switch (property) {
        'title' || 'description' || 'meta' || 'indicator' => value is String,
        'icon' =>
          value is String &&
              (_iconNames.contains(value) ||
                  _appIconNamePattern.hasMatch(value)),
        'variant' => value is String && _buttonVariants.contains(value),
        'connector' || 'selected' || 'press-enabled' => value is bool,
        _ => false,
      };
    }
    if (kind == _NodeKind.inputGroup) {
      return switch (property) {
        'accessibility-label' => value is String,
        'width' || 'height' || 'min-width' => value is int && value >= 0,
        'grow' => value is num && value.isFinite && value >= 0,
        _ => false,
      };
    }
    if (kind == _NodeKind.inputGroupActions) {
      return property == 'gap' && value is int && value >= 0;
    }
    if (kind == _NodeKind.toast) {
      return switch (property) {
        'duration' => value is int && value >= 0 && value <= 0x7fffffff,
        'accessibility-label' || 'style-class' => value is String,
        _ => false,
      };
    }
    if (kind == _NodeKind.toolbar) {
      return switch (property) {
        'orientation' =>
          value is String && (value == 'horizontal' || value == 'vertical'),
        'gap' => value is int && value >= 0,
        'accessibility-label' || 'style-class' => value is String,
        _ => false,
      };
    }
    if (kind == _NodeKind.bottomTabs) {
      return switch (property) {
        'accessibility-label' || 'style-class' => value is String,
        'grow' => value is num && value.isFinite && value >= 0,
        'width' ||
        'height' ||
        'min-width' ||
        'max-width' ||
        'min-height' ||
        'max-height' => value is int && value >= 0,
        _ => false,
      };
    }
    if (kind == _NodeKind.bottomTab) {
      return switch (property) {
        'title' => value is String,
        'icon' =>
          value is String &&
              (_iconNames.contains(value) ||
                  _appIconNamePattern.hasMatch(value)),
        'selected' || 'enabled' || 'press-enabled' => value is bool,
        _ => false,
      };
    }
    return switch (property) {
      'main' =>
        value is String &&
            _mainAlignments.contains(value) &&
            (kind == _NodeKind.row ||
                kind == _NodeKind.column ||
                kind == _NodeKind.list ||
                kind == _NodeKind.virtualList ||
                _isHorizontalGroupKind(kind)),
      'cross' =>
        value is String &&
            _crossAlignments.contains(value) &&
            (kind == _NodeKind.row ||
                kind == _NodeKind.column ||
                kind == _NodeKind.list ||
                kind == _NodeKind.virtualList ||
                _isHorizontalGroupKind(kind)),
      'grow' =>
        value is num &&
            value.isFinite &&
            value >= 0 &&
            kind != _NodeKind.avatar &&
            kind != _NodeKind.tooltip &&
            !kind.isModalSurface,
      'columns' => value is int && value >= 0 && kind == _NodeKind.grid,
      'text' =>
        value is String &&
            (kind == _NodeKind.text ||
                kind == _NodeKind.heading ||
                kind == _NodeKind.paragraph ||
                kind == _NodeKind.label ||
                _isButtonKind(kind) ||
                _isTextControl(kind) ||
                kind == _NodeKind.checkbox ||
                kind == _NodeKind.switchControl ||
                kind == _NodeKind.toggle ||
                kind == _NodeKind.radio ||
                kind == _NodeKind.select ||
                kind == _NodeKind.menuItem ||
                kind == _NodeKind.listItem ||
                kind == _NodeKind.tableCell ||
                kind == _NodeKind.avatar ||
                kind == _NodeKind.tooltip ||
                kind == _NodeKind.alert ||
                kind == _NodeKind.bubble ||
                kind == _NodeKind.statusBar ||
                kind == _NodeKind.drawer ||
                kind.isModalSurface),
      'enabled' =>
        value is bool &&
            (_isButtonKind(kind) ||
                _isTextControl(kind) ||
                kind == _NodeKind.checkbox ||
                kind == _NodeKind.switchControl ||
                kind == _NodeKind.toggle ||
                kind == _NodeKind.radio ||
                kind == _NodeKind.slider ||
                kind == _NodeKind.select ||
                kind == _NodeKind.menuItem ||
                kind == _NodeKind.listItem ||
                kind == _NodeKind.drawer),
      'value' =>
        value is double &&
            value.isFinite &&
            (kind == _NodeKind.progress ||
                kind == _NodeKind.slider ||
                kind == _NodeKind.split),
      'resize-duration' =>
        value is int && value >= 0 && kind == _NodeKind.split,
      'resize-easing' =>
        value is String &&
            const {
              'linear',
              'standard',
              'emphasized',
              'spring',
            }.contains(value) &&
            kind == _NodeKind.split,
      'resize-origin' =>
        value is double && value.isFinite && kind == _NodeKind.split,
      'orientation' =>
        value is String &&
            (value == 'horizontal' || value == 'vertical') &&
            (kind == _NodeKind.divider || kind == _NodeKind.tabs),
      'size' =>
        value is String &&
            (_controlSizes.contains(value) ||
                (kind == _NodeKind.tableCell && _textSizes.contains(value))) &&
            (_isButtonKind(kind) ||
                kind == _NodeKind.spinner ||
                kind == _NodeKind.icon ||
                kind == _NodeKind.tableCell ||
                kind == _NodeKind.menuItem),
      'name' =>
        value is String &&
            (_iconNames.contains(value) ||
                _appIconNamePattern.hasMatch(value)) &&
            kind == _NodeKind.icon,
      'variant' =>
        value is String &&
            _buttonVariants.contains(value) &&
            (_isButtonKind(kind) ||
                kind == _NodeKind.alert ||
                kind == _NodeKind.bubble ||
                kind == _NodeKind.menuItem),
      'icon' =>
        value is String &&
            (_iconNames.contains(value) ||
                _appIconNamePattern.hasMatch(value)) &&
            (_isButtonKind(kind) ||
                kind == _NodeKind.menuItem ||
                kind == _NodeKind.listItem),
      'icon-placement' =>
        value is String &&
            (value == 'leading' || value == 'trailing') &&
            _isButtonKind(kind),
      'selected' =>
        value is bool &&
            (_isButtonKind(kind) ||
                kind == _NodeKind.menuItem ||
                kind == _NodeKind.listItem ||
                kind == _NodeKind.tableRow ||
                kind == _NodeKind.drawer ||
                _isTreeRowKind(kind)),
      'long-press-enabled' =>
        value is bool && (_isButtonKind(kind) || kind == _NodeKind.listItem),
      'autofocus' =>
        value is bool && (_isButtonKind(kind) || _isTextControl(kind)),
      'submit-on-enter' => value is bool && kind == _NodeKind.textarea,
      'change-enabled' =>
        value is bool && (kind == _NodeKind.radio || _isTreeRowKind(kind)),
      'toggle-enabled' =>
        value is bool &&
            (kind == _NodeKind.radio ||
                kind == _NodeKind.drawer ||
                _isTreeRowKind(kind)),
      'press-enabled' =>
        value is bool &&
            (kind == _NodeKind.text ||
                kind == _NodeKind.radio ||
                kind == _NodeKind.select ||
                kind == _NodeKind.combobox ||
                kind == _NodeKind.menuItem ||
                kind == _NodeKind.listItem ||
                kind == _NodeKind.tableCell ||
                _isTreeRowKind(kind)),
      'submit-enabled' =>
        value is bool &&
            (kind == _NodeKind.combobox || kind == _NodeKind.listItem),
      'double-press-enabled' => value is bool && kind == _NodeKind.listItem,
      'appear-enabled' => value is bool,
      'image' =>
        value is int &&
            value >= 0 &&
            (kind == _NodeKind.avatar || kind == _NodeKind.image),
      'surface' => value is int && value >= 0 && kind == _NodeKind.mediaSurface,
      'source-x' || 'source-y' || 'source-width' || 'source-height' =>
        value is num &&
            value.isFinite &&
            (kind == _NodeKind.avatar || kind == _NodeKind.image),
      'anchor' =>
        value is String &&
            const {'above', 'below', 'left', 'right'}.contains(value) &&
            (kind == _NodeKind.dropdownMenu || kind == _NodeKind.tooltip),
      'anchor-alignment' =>
        value is String &&
            const {'start', 'end', 'stretch'}.contains(value) &&
            (kind == _NodeKind.dropdownMenu || kind == _NodeKind.tooltip),
      'anchor-offset' =>
        value is num &&
            value.isFinite &&
            (kind == _NodeKind.dropdownMenu || kind == _NodeKind.tooltip),
      'tooltip-delay' =>
        value is int &&
            value >= 0 &&
            value <= 0x7fffffff &&
            kind == _NodeKind.tooltip,
      'gap' =>
        value is int &&
            value >= 0 &&
            (kind == _NodeKind.row ||
                kind == _NodeKind.column ||
                kind == _NodeKind.grid ||
                kind == _NodeKind.list ||
                kind == _NodeKind.virtualList ||
                kind == _NodeKind.dropdownMenu ||
                kind == _NodeKind.tableRow ||
                kind == _NodeKind.tree ||
                kind == _NodeKind.split ||
                _isHorizontalGroupKind(kind)),
      'padding' =>
        value is int && kind != _NodeKind.avatar && kind != _NodeKind.tooltip,
      'padding-horizontal' || 'padding-vertical' =>
        value is int &&
            value >= 0 &&
            (kind == _NodeKind.row ||
                kind == _NodeKind.column ||
                kind == _NodeKind.grid ||
                kind == _NodeKind.box),
      'background' =>
        value is String &&
            kind != _NodeKind.avatar &&
            kind != _NodeKind.tooltip &&
            !kind.isModalSurface,
      'foreground' =>
        value is String &&
            (kind == _NodeKind.text ||
                kind == _NodeKind.heading ||
                kind == _NodeKind.paragraph ||
                kind == _NodeKind.label ||
                _isButtonKind(kind) ||
                _isTextControl(kind) ||
                kind == _NodeKind.checkbox ||
                kind == _NodeKind.toggle ||
                kind == _NodeKind.radio ||
                kind == _NodeKind.slider ||
                kind == _NodeKind.spinner ||
                kind == _NodeKind.icon ||
                kind == _NodeKind.select ||
                kind == _NodeKind.dropdownMenu ||
                kind == _NodeKind.menuItem ||
                kind == _NodeKind.listItem ||
                kind == _NodeKind.tableCell ||
                kind == _NodeKind.resizable ||
                kind == _NodeKind.split ||
                kind == _NodeKind.alert ||
                kind == _NodeKind.bubble ||
                kind == _NodeKind.statusBar),
      'border-color' =>
        value is String &&
            kind != _NodeKind.avatar &&
            kind != _NodeKind.tooltip &&
            !kind.isModalSurface,
      'border-width' =>
        value is int &&
            value >= 0 &&
            kind != _NodeKind.avatar &&
            kind != _NodeKind.tooltip &&
            !kind.isModalSurface,
      'corner-radius' =>
        value is int &&
            value >= 0 &&
            kind != _NodeKind.avatar &&
            kind != _NodeKind.tooltip &&
            !kind.isModalSurface,
      'width' || 'height' =>
        value is int &&
            value >= 0 &&
            kind != _NodeKind.avatar &&
            kind != _NodeKind.tooltip,
      'min-width' || 'max-width' || 'min-height' || 'max-height' =>
        value is int &&
            value >= 0 &&
            kind != _NodeKind.avatar &&
            kind != _NodeKind.tooltip &&
            !kind.isModalSurface,
      'style-class' =>
        value is String &&
            kind != _NodeKind.avatar &&
            kind != _NodeKind.tooltip &&
            !kind.isModalSurface,
      'checked' =>
        value is bool &&
            (kind == _NodeKind.checkbox ||
                kind == _NodeKind.switchControl ||
                kind == _NodeKind.toggle ||
                kind == _NodeKind.radio),
      'heading-level' =>
        value is int && value >= 1 && value <= 6 && kind == _NodeKind.heading,
      'placeholder' =>
        value is String && (_isTextControl(kind) || kind == _NodeKind.select),
      'accessibility-label' =>
        value is String &&
            (_isButtonKind(kind) ||
                _isTextControl(kind) ||
                kind == _NodeKind.checkbox ||
                kind == _NodeKind.switchControl ||
                kind == _NodeKind.toggle ||
                kind == _NodeKind.radioGroup ||
                kind == _NodeKind.tabs ||
                kind == _NodeKind.buttonGroup ||
                kind == _NodeKind.toggleGroup ||
                kind == _NodeKind.breadcrumb ||
                kind == _NodeKind.pagination ||
                kind == _NodeKind.radio ||
                kind == _NodeKind.slider ||
                kind == _NodeKind.avatar ||
                kind == _NodeKind.image ||
                kind == _NodeKind.mediaSurface ||
                kind == _NodeKind.tree ||
                kind == _NodeKind.resizable ||
                kind == _NodeKind.split ||
                kind == _NodeKind.drawer ||
                kind == _NodeKind.alert ||
                kind == _NodeKind.bubble ||
                kind == _NodeKind.select ||
                _isTreeRowKind(kind)),
      'text-alignment' =>
        value is String &&
            _textAlignments.contains(value) &&
            (_isButtonKind(kind) ||
                kind == _NodeKind.text ||
                kind == _NodeKind.tableCell ||
                kind == _NodeKind.bubble ||
                kind == _NodeKind.statusBar),
      'role' => value == 'treeitem' && value is String && _isTreeRowKind(kind),
      'tree-level' => value is int && value > 0 && _isTreeRowKind(kind),
      'expanded' => value is bool && _isTreeRowKind(kind),
      _ => false,
    };
  }

  static void _validateStates(Map<int, _NodeState> states) {
    for (final state in states.values) {
      if (state.kind == _NodeKind.root) {
        if (state.parent != null) {
          throw const LUIBackendException('runtime root cannot have a parent');
        }
        if (state.children.length != 1) {
          throw const LUIBackendException(
            'runtime root requires exactly one child',
          );
        }
      }
      _validateSizeAxis(state, 'width', 'min-width', 'max-width');
      _validateSizeAxis(state, 'height', 'min-height', 'max-height');
      if (state.kind == _NodeKind.icon &&
          !state.properties.containsKey('name')) {
        throw const LUIBackendException('icon requires name');
      }
      if (_isButtonKind(state.kind)) {
        final text = state.properties['text'] as String? ?? '';
        final label = state.properties['accessibility-label'] as String? ?? '';
        final icon = state.properties['icon'] as String? ?? '';
        if (text.isEmpty && icon.isNotEmpty && label.isEmpty) {
          throw const LUIBackendException('icon-only button requires label');
        }
        if (text.isEmpty && label.isEmpty) {
          throw const LUIBackendException('button requires an accessible name');
        }
      }
      if (state.kind == _NodeKind.toggle || state.kind == _NodeKind.radio) {
        final text = state.properties['text'] as String? ?? '';
        final label = state.properties['accessibility-label'] as String? ?? '';
        if (text.isEmpty && label.isEmpty) {
          throw const LUIBackendException(
            'value control requires an accessible name',
          );
        }
      }
      if (state.kind == _NodeKind.radioGroup ||
          state.kind == _NodeKind.slider) {
        final label = state.properties['accessibility-label'] as String? ?? '';
        if (label.isEmpty) {
          throw const LUIBackendException(
            'value control requires an accessibility label',
          );
        }
      }
      if (state.kind == _NodeKind.split) {
        if (state.children.length != 2) {
          throw const LUIBackendException(
            'split requires exactly two children',
          );
        }
        final value = state.properties['value'];
        if (value is! double || !value.isFinite) {
          throw const LUIBackendException(
            'split requires a finite fractional value',
          );
        }
        final duration = state.properties['resize-duration'] as int? ?? 0;
        if ((state.properties.containsKey('resize-easing') ||
                state.properties.containsKey('resize-origin')) &&
            duration <= 0) {
          throw const LUIBackendException(
            'split animation options require a positive duration',
          );
        }
      }
      if (state.kind == _NodeKind.drawer && state.children.length != 2) {
        throw const LUIBackendException('drawer requires exactly two children');
      }
      if (state.kind == _NodeKind.radio &&
          !_hasAncestor(states, state.parent, _NodeKind.radioGroup)) {
        throw const LUIBackendException(
          'radio must be contained by a radio-group',
        );
      }
      if (state.kind == _NodeKind.select || state.kind == _NodeKind.combobox) {
        final text = state.properties['text'] as String? ?? '';
        final placeholder = state.properties['placeholder'] as String? ?? '';
        if (text.isEmpty && placeholder.isEmpty) {
          throw const LUIBackendException(
            'picker trigger requires text or placeholder',
          );
        }
      }
      if (state.kind == _NodeKind.menuItem &&
          (state.properties['text'] as String? ?? '').isEmpty) {
        throw const LUIBackendException('menu-item requires text');
      }
      if (state.kind == _NodeKind.contextMenu) {
        final parent = state.parent == null ? null : states[state.parent];
        if (parent == null || !_isContextMenuHost(parent)) {
          throw const LUIBackendException(
            'context-menu requires an interactive direct host',
          );
        }
        final count = parent.children
            .where((child) => states[child]?.kind == _NodeKind.contextMenu)
            .length;
        if (count != 1) {
          throw const LUIBackendException(
            'host accepts at most one context-menu',
          );
        }
        for (final childID in state.children) {
          final child = _requireState(states, childID);
          if (child.kind == _NodeKind.menuItem) {
            if (child.properties['press-enabled'] != true) {
              throw const LUIBackendException(
                'context-menu menu-item requires press support',
              );
            }
            if (child.children.isNotEmpty) {
              throw const LUIBackendException(
                'context-menu does not support nested menus',
              );
            }
            const allowed = {
              'text',
              'icon',
              'foreground',
              'enabled',
              'press-enabled',
              'variant',
            };
            if (!child.properties.keys.every(allowed.contains)) {
              throw const LUIBackendException(
                'context-menu menu-item has unsupported metadata',
              );
            }
          } else if (child.properties.isNotEmpty &&
              !(child.properties.length == 2 &&
                  child.properties['orientation'] == 'horizontal' &&
                  child.properties['style-class'] == 'lui-separator')) {
            throw const LUIBackendException(
              'context-menu separator accepts no attributes',
            );
          }
        }
      }
      if (state.kind.isModalSurface &&
          (state.properties['text'] as String? ?? '').isEmpty) {
        throw const LUIBackendException('modal surface requires text');
      }
      if (state.kind == _NodeKind.tooltip) {
        if ((state.properties['text'] as String? ?? '').isEmpty) {
          throw const LUIBackendException('tooltip requires text');
        }
        if (state.properties.containsKey('tooltip-delay') &&
            !state.properties.containsKey('anchor')) {
          throw const LUIBackendException('tooltip-delay requires anchor');
        }
      }
      if (state.kind == _NodeKind.accordion &&
          (state.properties['text'] as String? ?? '').isEmpty) {
        throw const LUIBackendException('accordion requires text');
      }
      if (state.kind == _NodeKind.tree &&
          (state.properties['accessibility-label'] as String? ?? '').isEmpty) {
        throw const LUIBackendException('tree requires an accessibility label');
      }
      if (state.kind == _NodeKind.toolbar &&
          (state.properties['accessibility-label'] as String? ?? '').isEmpty) {
        throw const LUIBackendException(
          'toolbar requires an accessibility label',
        );
      }
      if (state.kind == _NodeKind.bottomTabs) {
        if ((state.properties['accessibility-label'] as String? ?? '')
            .isEmpty) {
          throw const LUIBackendException(
            'bottom-tabs requires an accessibility label',
          );
        }
        if (state.children.length < 2 || state.children.length > 5) {
          throw const LUIBackendException(
            'bottom-tabs requires two to five destinations',
          );
        }
      }
      if (state.kind == _NodeKind.bottomTab &&
          ((state.properties['title'] as String? ?? '').isEmpty ||
              state.properties['press-enabled'] != true ||
              state.children.isEmpty ||
              state.parent == null ||
              states[state.parent]?.kind != _NodeKind.bottomTabs)) {
        throw const LUIBackendException(
          'bottom-tab requires title, press support, content, and a direct bottom-tabs parent',
        );
      }
      final hasTreeMetadata =
          state.properties.containsKey('role') ||
          state.properties.containsKey('tree-level') ||
          state.properties.containsKey('expanded');
      if (hasTreeMetadata) {
        if (state.properties['role'] != 'treeitem' ||
            !_hasAncestor(states, state.parent, _NodeKind.tree)) {
          throw const LUIBackendException(
            'tree row metadata requires a treeitem inside tree',
          );
        }
        if (state.properties.containsKey('expanded') &&
            state.properties['toggle-enabled'] != true) {
          throw const LUIBackendException(
            'expanded treeitem requires toggle support',
          );
        }
      }
      if (state.kind == _NodeKind.dropdownMenu ||
          state.kind == _NodeKind.tooltip) {
        if (state.properties.containsKey('anchor-alignment') &&
            !state.properties.containsKey('anchor')) {
          throw const LUIBackendException('anchor-alignment requires anchor');
        }
        if (state.properties.containsKey('anchor-offset') &&
            !state.properties.containsKey('anchor')) {
          throw const LUIBackendException('anchor-offset requires anchor');
        }
      }
      if (state.kind == _NodeKind.listItem) {
        final hasText = (state.properties['text'] as String? ?? '').isNotEmpty;
        final hasChildren = state.children.any(
          (child) => states[child]?.kind != _NodeKind.contextMenu,
        );
        if (!hasText && !hasChildren) {
          throw const LUIBackendException(
            'list-item requires text or children',
          );
        }
        if (hasText && hasChildren) {
          throw const LUIBackendException(
            'list-item accepts text or children, not both',
          );
        }
      }
      if (state.kind == _NodeKind.avatar || state.kind == _NodeKind.image) {
        final text = state.properties['text'] as String? ?? '';
        if (state.kind == _NodeKind.avatar && text.isEmpty) {
          throw const LUIBackendException('avatar requires initials');
        }
        if (state.kind == _NodeKind.image &&
            !state.properties.containsKey('image')) {
          throw const LUIBackendException('image requires image');
        }
        const sourceNames = {
          'source-x',
          'source-y',
          'source-width',
          'source-height',
        };
        final sourceCount = sourceNames
            .where(state.properties.containsKey)
            .length;
        final mediaKind = state.kind == _NodeKind.avatar ? 'avatar' : 'image';
        if (sourceCount != 0 && sourceCount != sourceNames.length) {
          throw LUIBackendException(
            '$mediaKind source crop requires all four coordinates',
          );
        }
        if (sourceCount == sourceNames.length) {
          if (!state.properties.containsKey('image')) {
            throw LUIBackendException(
              '$mediaKind source crop requires an image',
            );
          }
          final x = (state.properties['source-x'] as num).toDouble();
          final y = (state.properties['source-y'] as num).toDouble();
          final width = (state.properties['source-width'] as num).toDouble();
          final height = (state.properties['source-height'] as num).toDouble();
          if (x < 0 || y < 0) {
            throw LUIBackendException(
              '$mediaKind source crop coordinates must be non-negative',
            );
          }
          if (width <= 0 || height <= 0) {
            throw LUIBackendException(
              '$mediaKind source crop dimensions must be positive',
            );
          }
        }
      }
      if (state.kind == _NodeKind.mediaSurface &&
          !state.properties.containsKey('surface')) {
        throw const LUIBackendException('media-surface requires surface');
      }
      if (state.kind == _NodeKind.stepper &&
          !state.properties.containsKey('active')) {
        throw const LUIBackendException('stepper requires active');
      }
      if (state.kind == _NodeKind.step) {
        if ((state.properties['text'] as String? ?? '').isEmpty ||
            state.parent == null ||
            states[state.parent]?.kind != _NodeKind.stepper) {
          throw const LUIBackendException(
            'step requires text and a direct stepper parent',
          );
        }
      }
      if (state.kind == _NodeKind.timelineItem) {
        if ((state.properties['title'] as String? ?? '').isEmpty) {
          throw const LUIBackendException('timeline-item requires title');
        }
        if (state.parent == null ||
            states[state.parent]?.kind != _NodeKind.timeline) {
          throw const LUIBackendException(
            'timeline-item requires a direct timeline parent',
          );
        }
      }
      if (state.kind == _NodeKind.inputGroup) {
        if (state.children.isEmpty || state.children.length > 2) {
          throw const LUIBackendException(
            'input-group requires one textarea and optional actions',
          );
        }
        if (states[state.children.first]?.kind != _NodeKind.textarea ||
            (state.children.length == 2 &&
                states[state.children[1]]?.kind !=
                    _NodeKind.inputGroupActions)) {
          throw const LUIBackendException(
            'input-group requires textarea first and actions second',
          );
        }
      }
      if (state.kind == _NodeKind.inputGroupActions &&
          (state.parent == null ||
              states[state.parent]?.kind != _NodeKind.inputGroup)) {
        throw const LUIBackendException(
          'input-group-actions requires a direct input-group parent',
        );
      }
    }
  }

  void _validateExtensionStates(
    Map<int, _NodeState> states,
    Map<int, _ExtensionNodeState> extensions,
  ) {
    for (final entry in extensions.entries) {
      final id = entry.key;
      final state = entry.value;
      final registration = _extensionRegistry._registration(state.identifier);
      if (registration == null ||
          registration.fingerprint != state.fingerprint) {
        throw const LUIBackendException('invalid extension registration');
      }
      if (registration.isTweak && state.children.length != 1) {
        throw const LUIBackendException(
          'platform tweak requires exactly one child',
        );
      }
      final properties = {
        for (final property in registration.properties) property.name: property,
      };
      if (!state.properties.keys.every(properties.containsKey)) {
        throw const LUIBackendException('unknown extension property');
      }
      for (final property in registration.properties) {
        final value = state.properties[property.name];
        if (value == null) {
          if (property.isRequired) {
            throw const LUIBackendException(
              'missing required extension property',
            );
          }
        } else if (!property.kind.accepts(value)) {
          throw const LUIBackendException('invalid extension property');
        }
      }
      final parent = state.parent;
      if (parent != null &&
          !_nodeChildren(states, extensions, parent).contains(id)) {
        throw const LUIBackendException('extension parent is inconsistent');
      }
      for (final child in state.children) {
        if (_nodeParent(states, extensions, child) != id) {
          throw const LUIBackendException('extension child is inconsistent');
        }
      }
    }
  }

  static void _validateSizeAxis(
    _NodeState state,
    String fixedProperty,
    String minProperty,
    String maxProperty,
  ) {
    final minimum = state.properties[minProperty] as int? ?? 0;
    final maximum = state.properties[maxProperty] as int? ?? 0x7fffffffffffffff;
    final fixed = state.properties[fixedProperty] as int? ?? minimum;
    if (minimum > maximum || fixed < minimum || fixed > maximum) {
      throw const LUIBackendException('surface size constraints conflict');
    }
  }

  static bool _canContainChildren(_NodeKind kind) =>
      kind == _NodeKind.root ||
      kind == _NodeKind.row ||
      kind == _NodeKind.column ||
      kind == _NodeKind.grid ||
      kind == _NodeKind.stack ||
      kind == _NodeKind.panel ||
      kind == _NodeKind.card ||
      kind == _NodeKind.box ||
      kind == _NodeKind.scroll ||
      kind == _NodeKind.list ||
      kind == _NodeKind.virtualList ||
      _isHorizontalGroupKind(kind) ||
      kind == _NodeKind.radioGroup ||
      kind == _NodeKind.dropdownMenu ||
      kind == _NodeKind.contextMenu ||
      kind == _NodeKind.listItem ||
      kind == _NodeKind.accordion ||
      kind == _NodeKind.table ||
      kind == _NodeKind.tableRow ||
      kind == _NodeKind.tree ||
      kind == _NodeKind.resizable ||
      kind == _NodeKind.split ||
      kind == _NodeKind.drawer ||
      kind == _NodeKind.alert ||
      kind == _NodeKind.bubble ||
      kind == _NodeKind.stepper ||
      kind == _NodeKind.timeline ||
      kind == _NodeKind.inputGroup ||
      kind == _NodeKind.inputGroupActions ||
      kind == _NodeKind.toast ||
      kind == _NodeKind.toolbar ||
      kind == _NodeKind.bottomTabs ||
      kind == _NodeKind.bottomTab ||
      _isContextMenuLeafHost(kind) ||
      kind.isModalSurface;

  static bool _acceptsExtensionChildren(_NodeKind kind) =>
      kind == _NodeKind.root ||
      kind == _NodeKind.row ||
      kind == _NodeKind.column ||
      kind == _NodeKind.grid ||
      kind == _NodeKind.stack ||
      kind == _NodeKind.panel ||
      kind == _NodeKind.card ||
      kind == _NodeKind.box ||
      kind == _NodeKind.scroll ||
      kind == _NodeKind.list ||
      kind == _NodeKind.virtualList ||
      kind == _NodeKind.listItem ||
      kind == _NodeKind.dialog ||
      kind == _NodeKind.sheet ||
      kind == _NodeKind.accordion ||
      kind == _NodeKind.resizable ||
      kind == _NodeKind.split ||
      kind == _NodeKind.drawer ||
      kind == _NodeKind.alert ||
      kind == _NodeKind.bubble ||
      kind == _NodeKind.toast ||
      kind == _NodeKind.toolbar ||
      kind == _NodeKind.bottomTab;

  static bool _isToolbarChild(_NodeKind kind) =>
      kind == _NodeKind.button ||
      kind == _NodeKind.toggleButton ||
      kind == _NodeKind.buttonGroup ||
      kind == _NodeKind.toggleGroup ||
      kind == _NodeKind.checkbox ||
      kind == _NodeKind.switchControl ||
      kind == _NodeKind.toggle ||
      kind == _NodeKind.radioGroup ||
      kind == _NodeKind.select ||
      kind == _NodeKind.combobox ||
      kind == _NodeKind.textField ||
      kind == _NodeKind.secureField ||
      kind == _NodeKind.input ||
      kind == _NodeKind.searchField ||
      kind == _NodeKind.divider;

  static bool _isContextMenuLeafHost(_NodeKind kind) {
    const kinds = {
      _NodeKind.button,
      _NodeKind.toggleButton,
      _NodeKind.toggle,
      _NodeKind.radio,
      _NodeKind.slider,
      _NodeKind.textField,
      _NodeKind.secureField,
      _NodeKind.input,
      _NodeKind.searchField,
      _NodeKind.textarea,
      _NodeKind.checkbox,
      _NodeKind.switchControl,
      _NodeKind.select,
      _NodeKind.combobox,
      _NodeKind.menuItem,
      _NodeKind.text,
      _NodeKind.tableCell,
    };
    return kinds.contains(kind);
  }

  static bool _isContextMenuHost(_NodeState state) {
    const inherent = {
      _NodeKind.button,
      _NodeKind.toggleButton,
      _NodeKind.toggle,
      _NodeKind.radio,
      _NodeKind.slider,
      _NodeKind.textField,
      _NodeKind.secureField,
      _NodeKind.input,
      _NodeKind.searchField,
      _NodeKind.textarea,
      _NodeKind.checkbox,
      _NodeKind.switchControl,
      _NodeKind.select,
      _NodeKind.combobox,
      _NodeKind.menuItem,
      _NodeKind.listItem,
      _NodeKind.accordion,
      _NodeKind.text,
      _NodeKind.tableCell,
    };
    return inherent.contains(state.kind) ||
        state.properties['press-enabled'] == true ||
        state.properties['double-press-enabled'] == true ||
        state.properties['toggle-enabled'] == true ||
        state.properties['long-press-enabled'] == true;
  }

  int? _checkedRadio(_NodeState root) {
    for (final child in root.children) {
      final state = _requireState(_states, child);
      if (state.kind == _NodeKind.radio &&
          state.properties['checked'] == true) {
        return child;
      }
      final nested = _checkedRadio(state);
      if (nested != null) return nested;
    }
    return null;
  }

  static bool _hasAncestor(
    Map<int, _NodeState> states,
    int? parent,
    _NodeKind kind,
  ) {
    if (parent == null) return false;
    final state = _requireState(states, parent);
    return state.kind == kind || _hasAncestor(states, state.parent, kind);
  }

  static bool _isButtonKind(_NodeKind kind) =>
      kind == _NodeKind.button || kind == _NodeKind.toggleButton;

  static bool _isHorizontalGroupKind(_NodeKind kind) =>
      kind == _NodeKind.tabs ||
      kind == _NodeKind.buttonGroup ||
      kind == _NodeKind.toggleGroup ||
      kind == _NodeKind.breadcrumb ||
      kind == _NodeKind.pagination;

  static bool _isTreeRowKind(_NodeKind kind) =>
      kind == _NodeKind.row ||
      kind == _NodeKind.column ||
      kind == _NodeKind.panel ||
      kind == _NodeKind.card ||
      kind == _NodeKind.box ||
      kind == _NodeKind.listItem;

  static int _horizontalGroupDefaultGap(_NodeKind kind) =>
      kind == _NodeKind.pagination ? 2 : 4;

  static bool _isHorizontalGroupChild(
    _NodeKind groupKind,
    _NodeKind childKind,
  ) => switch (groupKind) {
    _NodeKind.tabs => childKind == _NodeKind.button,
    _NodeKind.buttonGroup => _isButtonKind(childKind),
    _NodeKind.toggleGroup => childKind == _NodeKind.toggleButton,
    _NodeKind.breadcrumb ||
    _NodeKind.pagination => childKind == _NodeKind.button,
    _ => false,
  };

  static bool _isTextControl(_NodeKind kind) =>
      kind == _NodeKind.textField ||
      kind == _NodeKind.secureField ||
      kind == _NodeKind.input ||
      kind == _NodeKind.searchField ||
      kind == _NodeKind.textarea ||
      kind == _NodeKind.combobox;

  static bool _containsState(
    Map<int, _NodeState> states,
    Map<int, _ExtensionNodeState> extensions,
    int id,
  ) => states.containsKey(id) || extensions.containsKey(id);

  static int? _nodeParent(
    Map<int, _NodeState> states,
    Map<int, _ExtensionNodeState> extensions,
    int id,
  ) {
    final standard = states[id];
    if (standard != null) return standard.parent;
    return _requireExtensionStateFrom(extensions, id).parent;
  }

  static List<int> _nodeChildren(
    Map<int, _NodeState> states,
    Map<int, _ExtensionNodeState> extensions,
    int id,
  ) {
    final standard = states[id];
    if (standard != null) return standard.children;
    return _requireExtensionStateFrom(extensions, id).children;
  }

  static void _setNodeParent(
    Map<int, _NodeState> states,
    Map<int, _ExtensionNodeState> extensions,
    int id,
    int? parent,
  ) {
    final standard = states[id];
    if (standard != null) {
      standard.parent = parent;
      return;
    }
    _requireExtensionStateFrom(extensions, id).parent = parent;
  }

  static bool _isDescendantAny(
    Map<int, _NodeState> states,
    Map<int, _ExtensionNodeState> extensions, {
    required int target,
    required int root,
  }) {
    if (target == root) return true;
    return _nodeChildren(states, extensions, root).any(
      (child) =>
          _isDescendantAny(states, extensions, target: target, root: child),
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

  static _ExtensionNodeState _requireExtensionStateFrom(
    Map<int, _ExtensionNodeState> states,
    int id,
  ) {
    final node = states[id];
    if (node == null) throw LUIBackendException('unknown extension node $id');
    return node;
  }

  _ExtensionNodeState _requireExtensionState(int id) =>
      _requireExtensionStateFrom(_extensionStates, id);

  _ExtensionNodeHandle _requireExtensionHandle(int id) {
    final handle = _extensionHandles[id];
    if (handle == null) {
      throw LUIBackendException('unknown extension node $id');
    }
    return handle;
  }

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

  static Color? _color(BuildContext context, String? name) {
    final colors = Theme.of(context).colorScheme;
    return switch (name?.toLowerCase()) {
      null => null,
      'transparent' => Colors.transparent,
      'background' => colors.surface,
      'foreground' => colors.onSurface,
      'primary' => colors.primary,
      'primary-foreground' => colors.onPrimary,
      'secondary' => colors.secondaryContainer,
      'glass' => colors.surface.withValues(alpha: 0.75),
      'secondary-foreground' => colors.onSecondaryContainer,
      'success' => colors.tertiaryContainer,
      'success-foreground' => colors.onTertiaryContainer,
      'warning' => colors.secondaryContainer,
      'warning-foreground' => colors.onSecondaryContainer,
      'error' => colors.errorContainer,
      'error-foreground' => colors.onErrorContainer,
      'border' => colors.outlineVariant,
      'black' => Colors.black,
      'white' => Colors.white,
      'red' => Colors.red,
      'blue' => Colors.blue,
      'green' => Colors.green,
      _ => Colors.transparent,
    };
  }

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

  static TextStyle? _textStyleForSize(BuildContext context, String? size) {
    final textTheme = Theme.of(context).textTheme;
    return switch (size) {
      'sm' => textTheme.bodySmall,
      'lg' => textTheme.titleMedium,
      'heading' => textTheme.headlineSmall,
      'display' => textTheme.displaySmall,
      _ => textTheme.bodyMedium,
    };
  }

  Widget _modalSurface(BuildContext context, int node) {
    final state = _requireState(_states, node);
    final width = (state.properties['width'] as int?)?.toDouble();
    final height = (state.properties['height'] as int?)?.toDouble();
    return switch (state.kind) {
      _NodeKind.dialog => Dialog(
        child: SizedBox(
          key: ValueKey('lui-dialog-surface-$node'),
          width: width ?? 420,
          height: height ?? 220,
          child: _modalSurfaceBody(context, state),
        ),
      ),
      _NodeKind.sheet => SizedBox(
        key: ValueKey('lui-sheet-surface-$node'),
        width: width ?? double.infinity,
        height: height,
        child: SafeArea(child: _modalSurfaceBody(context, state)),
      ),
      _ => throw const LUIBackendException('node is not a modal surface'),
    };
  }

  Widget _modalSurfaceBody(BuildContext context, _NodeState state) {
    final children = state.children
        .map((child) => widget(node: child))
        .toList(growable: false);
    return Padding(
      padding: EdgeInsets.all(
        (state.properties['padding'] as int? ?? 24).toDouble(),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            state.properties['text'] as String? ?? '',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 16),
          Expanded(child: Stack(children: children)),
        ],
      ),
    );
  }

  static MainAxisAlignment _mainAxisAlignment(String value) => switch (value) {
    'center' => MainAxisAlignment.center,
    'end' => MainAxisAlignment.end,
    'space_between' => MainAxisAlignment.spaceBetween,
    _ => MainAxisAlignment.start,
  };

  static CrossAxisAlignment _crossAxisAlignment(
    String value, {
    required bool canStretch,
  }) => switch (value) {
    'start' => CrossAxisAlignment.start,
    'center' => CrossAxisAlignment.center,
    'end' => CrossAxisAlignment.end,
    _ => canStretch ? CrossAxisAlignment.stretch : CrossAxisAlignment.start,
  };

  static const _mainAlignments = {'start', 'center', 'end', 'space_between'};

  static const _crossAlignments = {'stretch', 'start', 'center', 'end'};

  static const _controlSizes = {'default', 'sm', 'lg', 'icon'};

  static const _textSizes = {'heading', 'display'};

  static const _textAlignments = {'start', 'center', 'end'};

  static const _buttonVariants = {
    'default',
    'primary',
    'secondary',
    'outline',
    'ghost',
    'destructive',
  };
}

final class _LUIToast extends StatefulWidget {
  const _LUIToast({
    required this.node,
    required this.duration,
    required this.label,
    required this.onDismiss,
    required this.child,
  });

  final int node;
  final Duration duration;
  final String label;
  final VoidCallback onDismiss;
  final Widget child;

  @override
  State<_LUIToast> createState() => _LUIToastState();
}

final class _LUIToastState extends State<_LUIToast> {
  Timer? _timer;
  var _dismissed = false;

  @override
  void initState() {
    super.initState();
    _scheduleDismissal();
  }

  @override
  void didUpdateWidget(_LUIToast oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.duration != widget.duration) _scheduleDismissal();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    liveRegion: true,
    label: widget.label,
    child: MouseRegion(
      onEnter: (_) => _timer?.cancel(),
      onExit: (_) => _scheduleDismissal(),
      child: Dismissible(
        key: ValueKey('lui-toast-${widget.node}'),
        direction: DismissDirection.horizontal,
        onDismissed: (_) => _dismiss(),
        child: widget.child,
      ),
    ),
  );

  void _scheduleDismissal() {
    _timer?.cancel();
    if (_dismissed || widget.duration == Duration.zero) return;
    _timer = Timer(widget.duration, _dismiss);
  }

  void _dismiss() {
    if (_dismissed) return;
    _dismissed = true;
    _timer?.cancel();
    widget.onDismiss();
  }
}

final class _LUITableRowSurface extends StatefulWidget {
  const _LUITableRowSurface({
    required this.selected,
    required this.showDivider,
    required this.child,
  });

  final bool selected;
  final bool showDivider;
  final Widget child;

  @override
  State<_LUITableRowSurface> createState() => _LUITableRowSurfaceState();
}

final class _LUITableRowSurfaceState extends State<_LUITableRowSurface> {
  var hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return MouseRegion(
      onEnter: (_) => setState(() => hovered = true),
      onExit: (_) => setState(() => hovered = false),
      child: ColoredBox(
        color: widget.selected || hovered
            ? colors.secondaryContainer
            : Colors.transparent,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: widget.showDivider
                ? Border(bottom: BorderSide(color: colors.outlineVariant))
                : null,
          ),
          child: widget.child,
        ),
      ),
    );
  }
}

final class _LUIInputGroupSurface extends StatefulWidget {
  const _LUIInputGroupSurface({required this.child});

  final Widget child;

  @override
  State<_LUIInputGroupSurface> createState() => _LUIInputGroupSurfaceState();
}

final class _LUIInputGroupSurfaceState extends State<_LUIInputGroupSurface> {
  var focused = false;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Focus(
      canRequestFocus: false,
      onFocusChange: (value) => setState(() => focused = value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        decoration: BoxDecoration(
          color: colors.surface,
          border: Border.all(
            color: focused ? colors.primary : colors.outlineVariant,
            width: focused ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        clipBehavior: Clip.antiAlias,
        child: widget.child,
      ),
    );
  }
}

class _LUIModalPresenter extends StatefulWidget {
  const _LUIModalPresenter({required this.backend, required this.node});

  final LUIFlutterBackend backend;
  final int node;

  @override
  State<_LUIModalPresenter> createState() => _LUIModalPresenterState();
}

class _LUIModalPresenterState extends State<_LUIModalPresenter> {
  NavigatorState? _navigator;
  Route<void>? _route;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _present());
  }

  void _present() {
    if (!mounted || _route != null) return;
    final navigator = Navigator.of(context, rootNavigator: true);
    final route = _modalRoute(navigator);
    _navigator = navigator;
    _route = route;
    navigator.push(route).whenComplete(() {
      if (!mounted || _route != route) return;
      _route = null;
      widget.backend.performDismiss(widget.node);
    });
  }

  Route<void> _modalRoute(NavigatorState navigator) {
    final state = LUIFlutterBackend._requireState(
      widget.backend._states,
      widget.node,
    );
    final localizations = MaterialLocalizations.of(context);
    Widget surface(BuildContext context) => ListenableBuilder(
      listenable: widget.backend._requireHandle(widget.node),
      builder: (context, _) =>
          widget.backend._modalSurface(context, widget.node),
    );
    return switch (state.kind) {
      _NodeKind.sheet => ModalBottomSheetRoute<void>(
        builder: surface,
        capturedThemes: InheritedTheme.capture(
          from: context,
          to: navigator.context,
        ),
        isScrollControlled: true,
        barrierLabel: localizations.scrimLabel,
        barrierOnTapHint: localizations.scrimOnTapHint(
          localizations.bottomSheetLabel,
        ),
        isDismissible: true,
        enableDrag: true,
        showDragHandle: true,
        useSafeArea: true,
      ),
      _NodeKind.dialog => DialogRoute<void>(
        context: context,
        barrierDismissible: true,
        barrierLabel: localizations.modalBarrierDismissLabel,
        builder: surface,
      ),
      _ => throw const LUIBackendException('node is not a modal surface'),
    };
  }

  @override
  void dispose() {
    final route = _route;
    if (route != null) {
      _route = null;
      _navigator?.removeRoute(route);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

extension on _NodeKind {
  bool get isModalSurface =>
      this == _NodeKind.dialog || this == _NodeKind.sheet;

  bool get isOverlaySurface =>
      this == _NodeKind.panel ||
      this == _NodeKind.card ||
      this == _NodeKind.alert ||
      this == _NodeKind.bubble ||
      this == _NodeKind.resizable;
}

final class _LUIDrawer extends StatefulWidget {
  const _LUIDrawer({
    required this.sourcePresented,
    required this.enabled,
    required this.width,
    required this.label,
    required this.onChanged,
    required this.main,
    required this.panel,
  });

  final bool sourcePresented;
  final bool enabled;
  final double width;
  final String label;
  final ValueChanged<bool>? onChanged;
  final Widget main;
  final Widget panel;

  @override
  State<_LUIDrawer> createState() => _LUIDrawerState();
}

final class _LUIDrawerState extends State<_LUIDrawer> {
  late bool _presented;
  double _dragOffset = 0;
  bool _dragging = false;

  @override
  void initState() {
    super.initState();
    _presented = widget.sourcePresented;
  }

  @override
  void didUpdateWidget(covariant _LUIDrawer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled) {
      _dragging = false;
      _dragOffset = 0;
    }
    if (widget.sourcePresented == oldWidget.sourcePresented) return;
    _presented = widget.sourcePresented;
    _dragOffset = 0;
  }

  void _updatePresentation(bool presented) {
    setState(() {
      _presented = presented;
      _dragOffset = 0;
    });
    if (presented != widget.sourcePresented) widget.onChanged?.call(presented);
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final availableWidth = constraints.hasBoundedWidth
          ? constraints.maxWidth
          : widget.width;
      final width = widget.width.clamp(0, availableWidth * 0.9).toDouble();
      final visibleWidth = ((_presented ? width : 0) + _dragOffset)
          .clamp(0, width)
          .toDouble();
      final progress = width == 0 ? 0.0 : visibleWidth / width;
      final canToggle = widget.enabled && widget.onChanged != null && width > 0;

      return GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragStart: !canToggle
            ? null
            : (details) {
                _dragging = true;
              },
        onHorizontalDragUpdate: !canToggle
            ? null
            : (details) {
                if (!_dragging) return;
                setState(() {
                  final next = _dragOffset + details.delta.dx;
                  _dragOffset = _presented
                      ? next.clamp(-width, 0).toDouble()
                      : next.clamp(0, width).toDouble();
                });
              },
        onHorizontalDragEnd: !canToggle
            ? null
            : (details) {
                if (!_dragging) return;
                _dragging = false;
                final settledWidth = ((_presented ? width : 0) + _dragOffset)
                    .clamp(0, width)
                    .toDouble();
                final projectedWidth =
                    (settledWidth + (details.primaryVelocity ?? 0) * 0.2)
                        .clamp(0, width)
                        .toDouble();
                _updatePresentation(projectedWidth >= width * 0.5);
              },
        child: Stack(
          fit: StackFit.expand,
          children: [
            widget.main,
            if (visibleWidth > 0)
              Positioned.fill(
                key: const ValueKey('lui-drawer-scrim'),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: !canToggle ? null : () => _updatePresentation(false),
                  child: ColoredBox(
                    color: Colors.black.withValues(alpha: 0.32 * progress),
                  ),
                ),
              ),
            Positioned(
              key: const ValueKey('lui-drawer-panel'),
              left: -width + visibleWidth,
              top: 0,
              bottom: 0,
              width: width,
              child: Semantics(
                container: true,
                label: widget.label,
                hidden: visibleWidth == 0,
                child: widget.panel,
              ),
            ),
          ],
        ),
      );
    },
  );
}

final class _LUISplit extends StatefulWidget {
  const _LUISplit({
    required this.sourceFraction,
    required this.gap,
    required this.firstMinimum,
    required this.secondMinimum,
    required this.duration,
    required this.easing,
    required this.origin,
    required this.label,
    required this.onChanged,
    required this.first,
    required this.second,
  });

  final double sourceFraction;
  final double gap;
  final double firstMinimum;
  final double secondMinimum;
  final Duration duration;
  final String easing;
  final double? origin;
  final String label;
  final ValueChanged<double> onChanged;
  final Widget first;
  final Widget second;

  @override
  State<_LUISplit> createState() => _LUISplitState();
}

final class _LUISplitState extends State<_LUISplit>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late double _fraction;
  Animation<double>? _animation;

  @override
  void initState() {
    super.initState();
    _fraction = _normalize(
      widget.duration > Duration.zero
          ? widget.origin ?? widget.sourceFraction
          : widget.sourceFraction,
    );
    _controller = AnimationController(vsync: this, duration: widget.duration)
      ..addListener(() {
        final animation = _animation;
        if (animation == null) return;
        setState(() => _fraction = animation.value);
        widget.onChanged(_fraction);
      });
    if (widget.origin != null && widget.duration > Duration.zero) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _animateTo(widget.sourceFraction);
      });
    }
  }

  @override
  void didUpdateWidget(covariant _LUISplit oldWidget) {
    super.didUpdateWidget(oldWidget);
    _controller.duration = widget.duration;
    if (widget.sourceFraction == oldWidget.sourceFraction) return;
    final next = _normalize(widget.sourceFraction);
    if ((next - _fraction).abs() <= 0.000001) return;
    _animateTo(next);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  double _normalize(double value) =>
      value.isFinite && value > 0 ? value.clamp(0, 1).toDouble() : 0.5;

  double _effective(
    double value,
    double available,
    double firstMinimum,
    double secondMinimum,
  ) {
    if (!available.isFinite || available <= 0) return 0.5;
    final base = _normalize(value);
    final low = firstMinimum.clamp(0, double.infinity) / available;
    final high = 1 - secondMinimum.clamp(0, double.infinity) / available;
    if (low > high) {
      return low / (low + (1 - high)).clamp(0.0001, double.infinity);
    }
    return base.clamp(low, high).toDouble();
  }

  Curve get _curve => switch (widget.easing) {
    'linear' => Curves.linear,
    'emphasized' => const Cubic(0.2, 0, 0, 1),
    'spring' => Curves.easeOutBack,
    _ => Curves.easeInOut,
  };

  void _animateTo(double target) {
    final next = _normalize(target);
    final disableAnimations =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (widget.duration == Duration.zero || disableAnimations) {
      _controller.stop();
      setState(() => _fraction = next);
      return;
    }
    _controller.stop();
    _animation = Tween<double>(
      begin: _fraction,
      end: next,
    ).animate(CurvedAnimation(parent: _controller, curve: _curve));
    _controller.forward(from: 0);
  }

  void _updateUser(
    double value,
    double available,
    double firstMinimum,
    double secondMinimum,
  ) {
    _controller.stop();
    final next = _effective(value, available, firstMinimum, secondMinimum);
    setState(() => _fraction = next);
    widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final gap = widget.gap.clamp(0, constraints.maxWidth).toDouble();
        final available = (constraints.maxWidth - gap)
            .clamp(0, double.infinity)
            .toDouble();
        final effective = _effective(
          _fraction,
          available,
          widget.firstMinimum,
          widget.secondMinimum,
        );
        final firstWidth = available * effective;
        final secondWidth = available - firstWidth;
        return Row(
          children: [
            SizedBox(width: firstWidth, child: widget.first),
            Semantics(
              label: '${widget.label} divider',
              value: '${(effective * 100).round()}%',
              increasedValue:
                  '${((_effective(effective + 0.05, available, widget.firstMinimum, widget.secondMinimum)) * 100).round()}%',
              decreasedValue:
                  '${((_effective(effective - 0.05, available, widget.firstMinimum, widget.secondMinimum)) * 100).round()}%',
              onIncrease: () => _updateUser(
                effective + 0.05,
                available,
                widget.firstMinimum,
                widget.secondMinimum,
              ),
              onDecrease: () => _updateUser(
                effective - 0.05,
                available,
                widget.firstMinimum,
                widget.secondMinimum,
              ),
              child: MouseRegion(
                cursor: SystemMouseCursors.resizeLeftRight,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onHorizontalDragUpdate: (details) => _updateUser(
                    effective +
                        details.delta.dx / available.clamp(1, double.infinity),
                    available,
                    widget.firstMinimum,
                    widget.secondMinimum,
                  ),
                  child: SizedBox(width: gap, height: double.infinity),
                ),
              ),
            ),
            SizedBox(width: secondWidth, child: widget.second),
          ],
        );
      },
    );
  }
}

final class _LUIResizable extends StatefulWidget {
  const _LUIResizable({
    required this.initialWidth,
    required this.minimumWidth,
    required this.maximumWidth,
    required this.label,
    required this.child,
  });

  final double? initialWidth;
  final double? minimumWidth;
  final double? maximumWidth;
  final String label;
  final Widget child;

  @override
  State<_LUIResizable> createState() => _LUIResizableState();
}

final class _LUIResizableState extends State<_LUIResizable> {
  double? _width;

  @override
  void initState() {
    super.initState();
    _width = _clamp(widget.initialWidth);
  }

  @override
  void didUpdateWidget(covariant _LUIResizable oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialWidth != oldWidget.initialWidth) {
      _width = _clamp(widget.initialWidth);
    } else if (widget.minimumWidth != oldWidget.minimumWidth ||
        widget.maximumWidth != oldWidget.maximumWidth) {
      _width = _clamp(_width);
    }
  }

  double? _clamp(double? width) {
    if (width == null) return null;
    return width.clamp(
      widget.minimumWidth ?? 0,
      widget.maximumWidth ?? double.infinity,
    );
  }

  void _resize(double delta, double fallbackWidth) {
    setState(() {
      _width = _clamp((_width ?? fallbackWidth) + delta);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: widget.label,
      onIncrease: () => _resize(16, context.size?.width ?? 0),
      onDecrease: () => _resize(-16, context.size?.width ?? 0),
      child: SizedBox(
        width: _width,
        child: Stack(
          fit: StackFit.passthrough,
          children: [
            widget.child,
            Positioned(
              top: 0,
              right: 0,
              bottom: 0,
              width: 12,
              child: MouseRegion(
                cursor: SystemMouseCursors.resizeLeftRight,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onHorizontalDragUpdate: (details) =>
                      _resize(details.delta.dx, context.size?.width ?? 0),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

final class _LUIAvatarPainter extends CustomPainter {
  const _LUIAvatarPainter({required this.image, required this.source});

  final ui.Image image;
  final Rect? source;

  @override
  void paint(Canvas canvas, Size size) {
    final available =
        source ??
        Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble());
    final fitted = applyBoxFit(BoxFit.cover, available.size, size);
    final sourceRect = Alignment.center.inscribe(fitted.source, available);
    final destinationRect = Alignment.center.inscribe(
      fitted.destination,
      Offset.zero & size,
    );
    canvas.drawImageRect(image, sourceRect, destinationRect, Paint());
  }

  @override
  bool shouldRepaint(_LUIAvatarPainter oldDelegate) =>
      oldDelegate.image != image || oldDelegate.source != source;
}

final class _LUIImagePainter extends CustomPainter {
  const _LUIImagePainter({required this.image, required this.source});

  final ui.Image image;
  final Rect? source;

  @override
  void paint(Canvas canvas, Size size) {
    final available =
        source ??
        Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble());
    final fitted = applyBoxFit(BoxFit.fill, available.size, size);
    final sourceRect = Alignment.center.inscribe(fitted.source, available);
    final destinationRect = Alignment.center.inscribe(
      fitted.destination,
      Offset.zero & size,
    );
    canvas.drawImageRect(image, sourceRect, destinationRect, Paint());
  }

  @override
  bool shouldRepaint(_LUIImagePainter oldDelegate) =>
      oldDelegate.image != image || oldDelegate.source != source;
}

final class _LUIAccordion extends StatefulWidget {
  const _LUIAccordion({
    required this.expanded,
    required this.title,
    required this.onToggle,
    required this.children,
  });

  final bool expanded;
  final String title;
  final ValueChanged<bool>? onToggle;
  final List<Widget> children;

  @override
  State<_LUIAccordion> createState() => _LUIAccordionState();
}

final class _LUIAccordionState extends State<_LUIAccordion> {
  final ExpansibleController _controller = ExpansibleController();
  bool _syncing = false;

  @override
  void didUpdateWidget(_LUIAccordion oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.expanded != widget.expanded) _scheduleSync();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _scheduleSync() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _controller.isExpanded == widget.expanded) return;
      _syncing = true;
      widget.expanded ? _controller.expand() : _controller.collapse();
      _syncing = false;
    });
  }

  void _expansionChanged(bool expanded) {
    if (_syncing) return;
    widget.onToggle?.call(expanded);
    _scheduleSync();
  }

  @override
  Widget build(BuildContext context) => ExpansionTile(
    controller: _controller,
    initiallyExpanded: widget.expanded,
    maintainState: true,
    enabled: widget.onToggle != null,
    title: Text(widget.title),
    onExpansionChanged: _expansionChanged,
    children: widget.children,
  );
}

final class _LUIListItem extends StatefulWidget {
  const _LUIListItem({
    required this.enabled,
    required this.focusable,
    required this.selected,
    required this.leading,
    required this.content,
    required this.onPress,
    required this.onDoublePress,
    required this.onLongPress,
    required this.onSubmit,
  });

  final bool enabled;
  final bool focusable;
  final bool selected;
  final Widget? leading;
  final Widget content;
  final VoidCallback? onPress;
  final VoidCallback? onDoublePress;
  final VoidCallback? onLongPress;
  final VoidCallback? onSubmit;

  @override
  State<_LUIListItem> createState() => _LUIListItemState();
}

final class _LUIListItemState extends State<_LUIListItem> {
  int? _primaryPointer;
  Duration? _lastRelease;
  Offset? _lastPosition;
  Timer? _releaseTimer;
  Timer? _longPressTimer;
  var _didLongPress = false;

  void _handlePointerDown(PointerDownEvent event) {
    if (widget.enabled && event.buttons & kPrimaryButton != 0) {
      _primaryPointer = event.pointer;
      _didLongPress = false;
      _longPressTimer?.cancel();
      if (widget.onLongPress != null) {
        _longPressTimer = Timer(const Duration(milliseconds: 450), () {
          if (_primaryPointer != event.pointer || !mounted) return;
          _didLongPress = true;
          widget.onLongPress?.call();
        });
      }
    }
  }

  void _handlePointerCancel(PointerCancelEvent event) {
    if (_primaryPointer == event.pointer) _primaryPointer = null;
    _longPressTimer?.cancel();
  }

  void _handlePointerUp(PointerUpEvent event) {
    if (_primaryPointer != event.pointer) return;
    _primaryPointer = null;
    _longPressTimer?.cancel();
    if (!widget.enabled) return;
    if (_didLongPress) return;
    widget.onPress?.call();

    final previousRelease = _lastRelease;
    final previousPosition = _lastPosition;
    final isDoublePress =
        previousRelease != null &&
        previousPosition != null &&
        event.timeStamp - previousRelease <= kDoubleTapTimeout &&
        (event.position - previousPosition).distance <= kDoubleTapSlop;
    if (isDoublePress) {
      _releaseTimer?.cancel();
      _lastRelease = null;
      _lastPosition = null;
      widget.onDoublePress?.call();
    } else {
      _lastRelease = event.timeStamp;
      _lastPosition = event.position;
      _releaseTimer?.cancel();
      _releaseTimer = Timer(kDoubleTapTimeout, () {
        _lastRelease = null;
        _lastPosition = null;
      });
    }
  }

  @override
  void dispose() {
    _releaseTimer?.cancel();
    _longPressTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final press = widget.enabled ? widget.onPress : null;
    final submit = widget.enabled ? widget.onSubmit : null;
    final bindings = <ShortcutActivator, VoidCallback>{};
    if (press != null) {
      bindings[const SingleActivator(LogicalKeyboardKey.space)] = press;
    }
    if (submit != null || press != null) {
      bindings[const SingleActivator(LogicalKeyboardKey.enter)] =
          submit ?? press!;
    }
    return Semantics(
      button: true,
      enabled: widget.enabled,
      selected: widget.selected,
      onTap: press,
      onLongPress: widget.enabled ? widget.onLongPress : null,
      child: CallbackShortcuts(
        bindings: bindings,
        child: Focus(
          canRequestFocus: widget.enabled && widget.focusable,
          skipTraversal: !widget.focusable,
          child: Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: _handlePointerDown,
            onPointerCancel: _handlePointerCancel,
            onPointerUp: _handlePointerUp,
            child: ListTile(
              enabled: widget.enabled,
              selected: widget.selected,
              leading: widget.leading,
              title: widget.content,
              dense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

final class _LUIAnchoredStack extends StatefulWidget {
  const _LUIAnchoredStack({
    required this.anchor,
    required this.alignment,
    required this.offset,
    required this.menuID,
    required this.menuChildren,
    required this.minimumWidth,
    required this.maximumWidth,
    required this.onDismiss,
    required this.trigger,
  });

  final String anchor;
  final String alignment;
  final double offset;
  final int? menuID;
  final List<Widget> menuChildren;
  final double? minimumWidth;
  final double? maximumWidth;
  final VoidCallback? onDismiss;
  final Widget trigger;

  @override
  State<_LUIAnchoredStack> createState() => _LUIAnchoredStackState();
}

final class _LUIAnchoredStackState extends State<_LUIAnchoredStack> {
  final MenuController _menu = MenuController();
  bool _closingForModel = false;

  @override
  void initState() {
    super.initState();
    _syncMenu();
  }

  @override
  void didUpdateWidget(_LUIAnchoredStack oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.menuID != widget.menuID) _syncMenu();
  }

  void _syncMenu() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (widget.menuID == null) {
        if (_menu.isOpen) {
          _closingForModel = true;
          _menu.close();
        }
      } else if (!_menu.isOpen && widget.menuChildren.isNotEmpty) {
        _menu.open();
      }
    });
  }

  AlignmentGeometry get _menuAlignment => switch (widget.anchor) {
    'above' => switch (widget.alignment) {
      'center' => Alignment.topCenter,
      'end' => AlignmentDirectional.topEnd,
      _ => AlignmentDirectional.topStart,
    },
    'left' => AlignmentDirectional.centerStart,
    'right' => AlignmentDirectional.centerEnd,
    _ => switch (widget.alignment) {
      'center' => Alignment.bottomCenter,
      'end' => AlignmentDirectional.bottomEnd,
      _ => AlignmentDirectional.bottomStart,
    },
  };

  Offset get _alignmentOffset => switch (widget.anchor) {
    'above' => Offset(0, -widget.offset),
    'left' => Offset(-widget.offset, 0),
    'right' => Offset(widget.offset, 0),
    _ => Offset(0, widget.offset),
  };

  void _menuClosed() {
    if (_closingForModel) {
      _closingForModel = false;
      if (widget.menuID != null) _syncMenu();
      return;
    }
    widget.onDismiss?.call();
  }

  @override
  Widget build(BuildContext context) {
    return MenuAnchor(
      controller: _menu,
      useRootOverlay: true,
      animated: true,
      crossAxisUnconstrained: widget.alignment != 'stretch',
      alignmentOffset: _alignmentOffset,
      style: MenuStyle(
        alignment: _menuAlignment,
        minimumSize: widget.minimumWidth == null
            ? null
            : WidgetStatePropertyAll(Size(widget.minimumWidth!, 0)),
        maximumSize: widget.maximumWidth == null
            ? null
            : WidgetStatePropertyAll(
                Size(widget.maximumWidth!, double.infinity),
              ),
      ),
      onClose: _menuClosed,
      menuChildren: widget.menuChildren,
      child: widget.trigger,
    );
  }
}

final class _LUITooltipSession {
  final Stopwatch _clock = Stopwatch()..start();
  Duration _warmUntil = Duration.zero;

  bool get isWarm => _clock.elapsed < _warmUntil;

  void warm() {
    _warmUntil = _clock.elapsed + const Duration(milliseconds: 400);
  }

  void clear() {
    _warmUntil = Duration.zero;
  }
}

final class _LUIRetainedTooltip extends StatefulWidget {
  const _LUIRetainedTooltip({
    required this.session,
    required this.message,
    required this.waitDuration,
    required this.exitDuration,
    required this.preferBelow,
    required this.verticalOffset,
    required this.enableTapToDismiss,
    required this.child,
  });

  final _LUITooltipSession session;
  final String message;
  final Duration waitDuration;
  final Duration exitDuration;
  final bool preferBelow;
  final double verticalOffset;
  final bool enableTapToDismiss;
  final Widget child;

  @override
  State<_LUIRetainedTooltip> createState() => _LUIRetainedTooltipState();
}

final class _LUIRetainedTooltipState extends State<_LUIRetainedTooltip>
    with WidgetsBindingObserver {
  final GlobalKey<TooltipState> _tooltipKey = GlobalKey<TooltipState>();
  bool _pointerInside = false;
  bool _pointerPresented = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.session.clear();
    Tooltip.dismissAllToolTips();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _dismissCold();
  }

  void _pointerEntered(PointerEnterEvent event) {
    _pointerInside = true;
    if (!widget.session.isWarm) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _pointerInside) {
        _tooltipKey.currentState?.ensureTooltipVisible();
      }
    });
  }

  void _pointerExited(PointerExitEvent event) {
    _pointerInside = false;
    if (_pointerPresented) widget.session.warm();
    _pointerPresented = false;
  }

  void _focusChanged(bool focused) {
    if (focused) {
      _tooltipKey.currentState?.ensureTooltipVisible();
    } else if (!_pointerInside) {
      Tooltip.dismissAllToolTips();
    }
  }

  void _triggered() {
    _pointerPresented = _pointerInside;
  }

  void _dismissCold() {
    widget.session.clear();
    _pointerPresented = false;
    Tooltip.dismissAllToolTips();
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): _dismissCold,
      },
      child: Focus(
        onFocusChange: _focusChanged,
        child: Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: (event) {
            if (event.kind == PointerDeviceKind.mouse) _dismissCold();
          },
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onLongPress: () {
              _triggered();
              _tooltipKey.currentState?.ensureTooltipVisible();
            },
            child: Tooltip(
              key: _tooltipKey,
              message: widget.message,
              waitDuration: widget.waitDuration,
              exitDuration: widget.exitDuration,
              preferBelow: widget.preferBelow,
              verticalOffset: widget.verticalOffset,
              enableTapToDismiss: widget.enableTapToDismiss,
              triggerMode: TooltipTriggerMode.manual,
              onTriggered: _triggered,
              child: MouseRegion(
                onEnter: _pointerEntered,
                onExit: _pointerExited,
                child: widget.child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

typedef _LUIToggleSelectionBuilder =
    Widget Function(
      BuildContext context,
      bool selected,
      ValueChanged<bool> setSelected,
    );

final class _LUIToggleSelection extends StatefulWidget {
  const _LUIToggleSelection({
    required this.modelSelected,
    required this.builder,
  });

  final bool? modelSelected;
  final _LUIToggleSelectionBuilder builder;

  @override
  State<_LUIToggleSelection> createState() => _LUIToggleSelectionState();
}

final class _LUIToggleSelectionState extends State<_LUIToggleSelection> {
  late bool _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.modelSelected ?? false;
  }

  @override
  void didUpdateWidget(_LUIToggleSelection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.modelSelected != null &&
        widget.modelSelected != oldWidget.modelSelected) {
      _selected = widget.modelSelected!;
    }
  }

  @override
  Widget build(BuildContext context) => widget.builder(
    context,
    _selected,
    (selected) => setState(() => _selected = selected),
  );
}

final class _LUITextInput extends StatefulWidget {
  const _LUITextInput({
    required this.text,
    required this.enabled,
    required this.placeholder,
    required this.foreground,
    required this.autofocus,
    required this.multiline,
    required this.secure,
    required this.search,
    required this.grouped,
    required this.onOpen,
    required this.submitOnEnter,
    required this.onChanged,
    required this.onSubmitted,
  });

  final String text;
  final bool enabled;
  final String? placeholder;
  final Color? foreground;
  final bool autofocus;
  final bool multiline;
  final bool secure;
  final bool search;
  final bool grouped;
  final VoidCallback? onOpen;
  final bool submitOnEnter;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;

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
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      enabled: widget.enabled,
      autofocus: widget.autofocus,
      keyboardType: widget.multiline
          ? TextInputType.multiline
          : TextInputType.text,
      textInputAction: widget.multiline && !widget.submitOnEnter
          ? TextInputAction.newline
          : TextInputAction.done,
      minLines: 1,
      maxLines: widget.multiline ? null : 1,
      obscureText: widget.secure,
      style: TextStyle(color: widget.foreground),
      decoration: InputDecoration(
        hintText: widget.placeholder,
        border: widget.grouped ? InputBorder.none : null,
        prefixIcon: widget.search ? const Icon(Icons.search) : null,
        suffixIcon: widget.search && _controller.text.isNotEmpty
            ? IconButton(
                tooltip: 'Clear',
                icon: const Icon(Icons.clear),
                onPressed: _clear,
              )
            : widget.onOpen != null
            ? IconButton(
                tooltip: 'Open menu',
                icon: const Icon(Icons.arrow_drop_down),
                onPressed: widget.onOpen,
              )
            : null,
      ),
      onChanged: _handleChanged,
      onSubmitted: widget.onSubmitted,
    );
  }

  void _handleChanged(String value) {
    if (widget.search) setState(() {});
    widget.onChanged(value);
  }

  void _clear() {
    _controller.clear();
    setState(() {});
    widget.onChanged('');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}
