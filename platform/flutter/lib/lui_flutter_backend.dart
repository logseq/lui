import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

part 'lui_wire_schema.g.dart';

sealed class LUIEvent {
  const LUIEvent();

  const factory LUIEvent.press({required int node}) = LUIPressEvent;
  const factory LUIEvent.hold({required int node}) = LUIHoldEvent;
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

final class LUIHoldEvent extends LUIEvent {
  const LUIHoldEvent({required this.node});
  final int node;

  @override
  bool operator ==(Object other) => other is LUIHoldEvent && other.node == node;

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

  @override
  void dispose() {
    focusNode.dispose();
    super.dispose();
  }
}

final class LUIFlutterBackend {
  LUIFlutterBackend({this.onEvent, Map<String, IconData> appIcons = const {}})
    : appIcons = Map.unmodifiable(appIcons);

  final void Function(LUIEvent event)? onEvent;
  final Map<String, IconData> appIcons;
  Map<int, _NodeState> _states = {};
  final Map<int, _NodeHandle> _handles = {};
  final Map<int, ui.Image> _images = {};
  int generation = 0;

  static Key nodeKey(int id) => ValueKey('lui-node-$id');

  bool containsNode(int id) => _states.containsKey(id);

  int debugRevision(int id) => _requireHandle(id).revision;

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
    for (final image in _images.values) {
      image.dispose();
    }
    _images.clear();
    _states = {};
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
      if (entry.value.kind == _NodeKind.avatar &&
          entry.value.properties['image'] == imageID) {
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

    for (final operation in operations) {
      _applyState(next, operation);
    }
    _validateStates(next);
    final changedIDs = <int>{};
    final removed = _handles.keys
        .where((id) => !next.containsKey(id))
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
    _states = next;
    generation = nextGeneration;
    final changedSources = Set<int>.of(changedIDs);
    for (final source in changedSources) {
      var parent = next[source]?.parent;
      while (parent != null) {
        final ancestor = next[parent];
        if (ancestor == null) break;
        if (ancestor.kind == _NodeKind.radioGroup) changedIDs.add(parent);
        parent = ancestor.parent;
      }
    }
    for (final id in changedIDs) {
      _handles[id]?.markChanged();
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
    if (state.kind != _NodeKind.button &&
            state.kind != _NodeKind.select &&
            state.kind != _NodeKind.combobox &&
            state.kind != _NodeKind.menuItem &&
            state.kind != _NodeKind.listItem ||
        state.properties['enabled'] == false) {
      throw LUIBackendException(
        'node $node is not an enabled pressable control',
      );
    }
    onEvent?.call(LUIEvent.press(node: node));
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

  void performHold(int node) {
    final state = _requireState(_states, node);
    if (!_isButtonKind(state.kind) ||
        state.properties['enabled'] == false ||
        state.properties['hold-enabled'] != true) {
      throw LUIBackendException('node $node is not an enabled holdable button');
    }
    onEvent?.call(LUIEvent.hold(node: node));
  }

  void performToggle(int node, bool checked) {
    final state = _requireState(_states, node);
    if (state.kind != _NodeKind.toggleButton &&
            state.kind != _NodeKind.toggle ||
        state.properties['enabled'] == false) {
      throw LUIBackendException('node $node is not an enabled toggle button');
    }
    onEvent?.call(LUIEvent.toggleChanged(node: node, checked: checked));
  }

  void performChange(int node) {
    final state = _requireState(_states, node);
    if (state.kind != _NodeKind.radio || state.properties['enabled'] == false) {
      throw LUIBackendException('node $node is not an enabled radio');
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
    if (state.kind != _NodeKind.slider ||
        state.properties['enabled'] == false ||
        !value.isFinite) {
      throw LUIBackendException('node $node is not an enabled slider');
    }
    onEvent?.call(LUIEvent.valueChanged(node: node, value: value.clamp(0, 1)));
  }

  void performDismiss(int node) {
    final state = _requireState(_states, node);
    if (state.kind != _NodeKind.select &&
        state.kind != _NodeKind.combobox &&
        state.kind != _NodeKind.dropdownMenu) {
      throw LUIBackendException('node $node is not dismissible');
    }
    onEvent?.call(LUIEvent.dismiss(node: node));
  }

  Widget _buildNode(BuildContext context, int id) {
    final state = _requireState(_states, id);
    final children = state.children
        .map((child) {
          final childWidget = widget(node: child);
          if (state.kind != _NodeKind.row &&
              state.kind != _NodeKind.column &&
              state.kind != _NodeKind.list) {
            return childWidget;
          }
          final grow = _states[child]?.properties['grow'] as num? ?? 0;
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
                (_isHorizontalGroupKind(state.kind) ? 4 : 0))
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
      _ => 18.0,
    };
    final buttonVariant = state.properties['variant'] as String? ?? 'default';
    final buttonSize = state.properties['size'] as String? ?? 'default';
    final buttonIcon = state.properties['icon'] as String?;
    final buttonIconPlacement =
        state.properties['icon-placement'] as String? ?? 'leading';
    final buttonSelected = state.properties['selected'] as bool? ?? false;
    final buttonAutofocus = state.properties['autofocus'] as bool? ?? false;
    final buttonHoldEnabled =
        state.properties['hold-enabled'] as bool? ?? false;
    final isTabTrigger =
        state.kind == _NodeKind.button &&
        state.parent != null &&
        _states[state.parent]?.kind == _NodeKind.tabs;
    Widget textControl({required _NodeKind kind}) {
      final multiline = kind == _NodeKind.textarea;
      final combobox = kind == _NodeKind.combobox;
      return SizedBox(
        width: 240,
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
            search: kind == _NodeKind.searchField,
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
          : Icon(_iconData(buttonIcon), size: 16);
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
        'icon' => (const Size.square(40), EdgeInsets.zero),
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
      final onLongPress = enabled && buttonHoldEnabled
          ? () => performHold(id)
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
            childID != null &&
            _requireState(_states, childID).kind == _NodeKind.dropdownMenu,
        orElse: () => null,
      );
      final menuState = menuID == null ? null : _requireState(_states, menuID);
      return _LUIAnchoredStack(
        groupID: id,
        anchor: menuState?.properties['anchor'] as String? ?? 'below',
        alignment:
            menuState?.properties['anchor-alignment'] as String? ?? 'start',
        offset:
            (menuState?.properties['anchor-offset'] as num?)?.toDouble() ?? 0,
        menu: menuID == null ? null : widget(node: menuID),
        children: state.children
            .where((childID) => childID != menuID)
            .map((childID) => widget(node: childID))
            .toList(growable: false),
      );
    }

    Widget select() => OutlinedButton(
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
    Widget menuItem() => MenuItemButton(
      onPressed: enabled ? () => performAction(id) : null,
      leadingIcon: buttonIcon == null
          ? null
          : Icon(_iconData(buttonIcon), size: 16),
      trailingIcon: buttonSelected ? const Icon(Icons.check) : null,
      child: Text(text),
    );
    Widget listItem() => _LUIListItem(
      enabled: enabled,
      selected: buttonSelected,
      leading: buttonIcon == null
          ? null
          : Icon(_iconData(buttonIcon), size: 16),
      content: children.isEmpty
          ? Text(text)
          : children.length == 1
          ? children.single
          : Row(children: children),
      onPress: state.properties['press-enabled'] == true
          ? () => performAction(id)
          : null,
      onDoublePress: state.properties['double-press-enabled'] == true
          ? () => performDoublePress(id)
          : null,
      onSubmit: state.properties['submit-enabled'] == true
          ? () => performSubmit(id)
          : null,
    );
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

    final content = switch (state.kind) {
      _NodeKind.row => row(),
      _NodeKind.tabs ||
      _NodeKind.buttonGroup ||
      _NodeKind.toggleGroup => horizontalGroup(),
      _NodeKind.column || _NodeKind.list => column(),
      _NodeKind.grid => grid(),
      _NodeKind.stack => stack(),
      _NodeKind.panel || _NodeKind.card => Stack(children: children),
      _NodeKind.box => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
      _NodeKind.text => Text(text, style: TextStyle(color: foreground)),
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
      _NodeKind.menuItem => menuItem(),
      _NodeKind.listItem => listItem(),
      _NodeKind.avatar => avatar(),
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
    };

    final isSurface = state.kind.isOverlaySurface;
    final padding =
        state.properties['padding'] as int? ??
        (state.kind == _NodeKind.card
            ? 24
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
            color: background ?? Theme.of(context).colorScheme.surface,
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
    final width = state.properties['width'] as int?;
    final height = state.properties['height'] as int?;
    if (width != null || height != null) {
      surface = SizedBox(
        width: width?.toDouble(),
        height: height?.toDouble(),
        child: surface,
      );
    }
    final minWidth = state.properties['min-width'] as int?;
    final maxWidth = state.properties['max-width'] as int?;
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
    return surface;
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
        states[id] = _NodeState(_decodeNodeKind(operation['kind']));
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
        if (!_canContainChildren(parent.kind)) {
          throw const LUIBackendException('parent cannot contain child');
        }
        if (parent.kind == _NodeKind.dropdownMenu &&
            child.kind != _NodeKind.menuItem &&
            child.kind != _NodeKind.divider) {
          throw const LUIBackendException(
            'dropdown-menu accepts only menu-item or separator children',
          );
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
      'main' =>
        value is String &&
            _mainAlignments.contains(value) &&
            (kind == _NodeKind.row ||
                kind == _NodeKind.column ||
                kind == _NodeKind.list ||
                _isHorizontalGroupKind(kind)),
      'cross' =>
        value is String &&
            _crossAlignments.contains(value) &&
            (kind == _NodeKind.row ||
                kind == _NodeKind.column ||
                kind == _NodeKind.list ||
                _isHorizontalGroupKind(kind)),
      'grow' =>
        value is num &&
            value.isFinite &&
            value >= 0 &&
            kind != _NodeKind.avatar,
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
                kind == _NodeKind.avatar),
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
                kind == _NodeKind.listItem),
      'value' =>
        value is double &&
            value.isFinite &&
            (kind == _NodeKind.progress || kind == _NodeKind.slider),
      'orientation' =>
        value is String &&
            (value == 'horizontal' || value == 'vertical') &&
            kind == _NodeKind.divider,
      'size' =>
        value is String &&
            _controlSizes.contains(value) &&
            (_isButtonKind(kind) ||
                kind == _NodeKind.spinner ||
                kind == _NodeKind.icon),
      'name' =>
        value is String &&
            (_iconNames.contains(value) ||
                _appIconNamePattern.hasMatch(value)) &&
            kind == _NodeKind.icon,
      'variant' =>
        value is String &&
            _buttonVariants.contains(value) &&
            _isButtonKind(kind),
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
                kind == _NodeKind.listItem),
      'hold-enabled' => value is bool && _isButtonKind(kind),
      'autofocus' =>
        value is bool && (_isButtonKind(kind) || _isTextControl(kind)),
      'submit-on-enter' => value is bool && kind == _NodeKind.textarea,
      'change-enabled' ||
      'toggle-enabled' => value is bool && kind == _NodeKind.radio,
      'press-enabled' =>
        value is bool &&
            (kind == _NodeKind.radio ||
                kind == _NodeKind.select ||
                kind == _NodeKind.combobox ||
                kind == _NodeKind.menuItem ||
                kind == _NodeKind.listItem),
      'submit-enabled' =>
        value is bool &&
            (kind == _NodeKind.combobox || kind == _NodeKind.listItem),
      'double-press-enabled' => value is bool && kind == _NodeKind.listItem,
      'image' => value is int && value >= 0 && kind == _NodeKind.avatar,
      'source-x' || 'source-y' || 'source-width' || 'source-height' =>
        value is num && value.isFinite && kind == _NodeKind.avatar,
      'anchor' =>
        value is String &&
            (value == 'above' || value == 'below') &&
            kind == _NodeKind.dropdownMenu,
      'anchor-alignment' =>
        value is String &&
            const {'start', 'center', 'end', 'stretch'}.contains(value) &&
            kind == _NodeKind.dropdownMenu,
      'anchor-offset' =>
        value is num && value.isFinite && kind == _NodeKind.dropdownMenu,
      'gap' =>
        value is int &&
            value >= 0 &&
            (kind == _NodeKind.row ||
                kind == _NodeKind.column ||
                kind == _NodeKind.grid ||
                kind == _NodeKind.list ||
                kind == _NodeKind.dropdownMenu ||
                _isHorizontalGroupKind(kind)),
      'padding' => value is int && kind != _NodeKind.avatar,
      'padding-horizontal' || 'padding-vertical' =>
        value is int &&
            value >= 0 &&
            (kind == _NodeKind.row ||
                kind == _NodeKind.column ||
                kind == _NodeKind.grid ||
                kind == _NodeKind.box),
      'background' => value is String && kind != _NodeKind.avatar,
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
                kind == _NodeKind.listItem),
      'border-color' => value is String && kind != _NodeKind.avatar,
      'border-width' => value is int && value >= 0 && kind != _NodeKind.avatar,
      'corner-radius' => value is int && value >= 0 && kind != _NodeKind.avatar,
      'width' ||
      'height' ||
      'min-width' ||
      'max-width' ||
      'min-height' ||
      'max-height' => value is int && value >= 0 && kind != _NodeKind.avatar,
      'style-class' => value is String && kind != _NodeKind.avatar,
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
                kind == _NodeKind.buttonGroup ||
                kind == _NodeKind.toggleGroup ||
                kind == _NodeKind.radio ||
                kind == _NodeKind.slider ||
                kind == _NodeKind.avatar),
      _ => false,
    };
  }

  static void _validateStates(Map<int, _NodeState> states) {
    for (final state in states.values) {
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
      if (state.kind == _NodeKind.listItem) {
        final hasText = (state.properties['text'] as String? ?? '').isNotEmpty;
        final hasChildren = state.children.isNotEmpty;
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
      if (state.kind == _NodeKind.avatar) {
        final text = state.properties['text'] as String? ?? '';
        if (text.isEmpty) {
          throw const LUIBackendException('avatar requires initials');
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
        if (sourceCount != 0 && sourceCount != sourceNames.length) {
          throw const LUIBackendException(
            'avatar source crop requires all four coordinates',
          );
        }
        if (sourceCount == sourceNames.length) {
          if (!state.properties.containsKey('image')) {
            throw const LUIBackendException(
              'avatar source crop requires an image',
            );
          }
          final x = (state.properties['source-x'] as num).toDouble();
          final y = (state.properties['source-y'] as num).toDouble();
          final width = (state.properties['source-width'] as num).toDouble();
          final height = (state.properties['source-height'] as num).toDouble();
          if (x < 0 || y < 0) {
            throw const LUIBackendException(
              'avatar source crop coordinates must be non-negative',
            );
          }
          if (width <= 0 || height <= 0) {
            throw const LUIBackendException(
              'avatar source crop dimensions must be positive',
            );
          }
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
      kind == _NodeKind.row ||
      kind == _NodeKind.column ||
      kind == _NodeKind.grid ||
      kind == _NodeKind.stack ||
      kind == _NodeKind.panel ||
      kind == _NodeKind.card ||
      kind == _NodeKind.box ||
      kind == _NodeKind.scroll ||
      kind == _NodeKind.list ||
      _isHorizontalGroupKind(kind) ||
      kind == _NodeKind.radioGroup ||
      kind == _NodeKind.dropdownMenu ||
      kind == _NodeKind.listItem;

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
      kind == _NodeKind.toggleGroup;

  static bool _isHorizontalGroupChild(
    _NodeKind groupKind,
    _NodeKind childKind,
  ) => switch (groupKind) {
    _NodeKind.tabs => childKind == _NodeKind.button,
    _NodeKind.buttonGroup => _isButtonKind(childKind),
    _NodeKind.toggleGroup => childKind == _NodeKind.toggleButton,
    _ => false,
  };

  static bool _isTextControl(_NodeKind kind) =>
      kind == _NodeKind.textField ||
      kind == _NodeKind.input ||
      kind == _NodeKind.searchField ||
      kind == _NodeKind.textarea ||
      kind == _NodeKind.combobox;

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

  static const _buttonVariants = {
    'default',
    'primary',
    'secondary',
    'outline',
    'ghost',
    'destructive',
  };
}

extension on _NodeKind {
  bool get isOverlaySurface =>
      this == _NodeKind.panel || this == _NodeKind.card;
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

final class _LUIListItem extends StatefulWidget {
  const _LUIListItem({
    required this.enabled,
    required this.selected,
    required this.leading,
    required this.content,
    required this.onPress,
    required this.onDoublePress,
    required this.onSubmit,
  });

  final bool enabled;
  final bool selected;
  final Widget? leading;
  final Widget content;
  final VoidCallback? onPress;
  final VoidCallback? onDoublePress;
  final VoidCallback? onSubmit;

  @override
  State<_LUIListItem> createState() => _LUIListItemState();
}

final class _LUIListItemState extends State<_LUIListItem> {
  int? _primaryPointer;
  Duration? _lastRelease;
  Offset? _lastPosition;
  Timer? _releaseTimer;

  void _handlePointerDown(PointerDownEvent event) {
    if (widget.enabled && event.buttons & kPrimaryButton != 0) {
      _primaryPointer = event.pointer;
    }
  }

  void _handlePointerCancel(PointerCancelEvent event) {
    if (_primaryPointer == event.pointer) _primaryPointer = null;
  }

  void _handlePointerUp(PointerUpEvent event) {
    if (_primaryPointer != event.pointer) return;
    _primaryPointer = null;
    if (!widget.enabled) return;
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
      child: CallbackShortcuts(
        bindings: bindings,
        child: Focus(
          canRequestFocus: widget.enabled,
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
    required this.groupID,
    required this.anchor,
    required this.alignment,
    required this.offset,
    required this.menu,
    required this.children,
  });

  final int groupID;
  final String anchor;
  final String alignment;
  final double offset;
  final Widget? menu;
  final List<Widget> children;

  @override
  State<_LUIAnchoredStack> createState() => _LUIAnchoredStackState();
}

final class _LUIAnchoredStackState extends State<_LUIAnchoredStack> {
  final LayerLink _link = LayerLink();
  final OverlayPortalController _overlay = OverlayPortalController();

  @override
  void initState() {
    super.initState();
    _syncOverlay();
  }

  @override
  void didUpdateWidget(_LUIAnchoredStack oldWidget) {
    super.didUpdateWidget(oldWidget);
    if ((oldWidget.menu == null) != (widget.menu == null)) _syncOverlay();
  }

  void _syncOverlay() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (widget.menu == null) {
        _overlay.hide();
      } else {
        _overlay.show();
      }
    });
  }

  Alignment get _horizontalAnchor => switch (widget.alignment) {
    'center' => Alignment.bottomCenter,
    'end' => Alignment.bottomRight,
    _ => Alignment.bottomLeft,
  };

  Alignment get _targetAnchor => widget.anchor == 'above'
      ? Alignment(_horizontalAnchor.x, -1)
      : _horizontalAnchor;

  Alignment get _followerAnchor => widget.anchor == 'above'
      ? Alignment(_horizontalAnchor.x, 1)
      : Alignment(_horizontalAnchor.x, -1);

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _link,
      child: OverlayPortal(
        controller: _overlay,
        overlayChildBuilder: (context) => CompositedTransformFollower(
          link: _link,
          showWhenUnlinked: false,
          targetAnchor: _targetAnchor,
          followerAnchor: _followerAnchor,
          offset: Offset(
            0,
            widget.anchor == 'above' ? -widget.offset : widget.offset,
          ),
          child: TapRegion(
            groupId: widget.groupID,
            child: SizedBox(
              width: widget.alignment == 'stretch'
                  ? _link.leaderSize?.width
                  : null,
              child: widget.menu ?? const SizedBox.shrink(),
            ),
          ),
        ),
        child: TapRegion(
          groupId: widget.groupID,
          child: Stack(clipBehavior: Clip.none, children: widget.children),
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
    required this.search,
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
  final bool search;
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
      style: TextStyle(color: widget.foreground),
      decoration: InputDecoration(
        hintText: widget.placeholder,
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
