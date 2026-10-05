part of 'lui_flutter_backend.dart';

/// Bonsplit-style tabbed split panes for the Flutter backend.
///
/// The OCaml app owns the tree (see src/lui_split.ml); these widgets own
/// gesture-time visuals — drag previews, drop-zone highlight, divider
/// feedback — so interactions run at display rate, and only committed
/// actions cross the bridge.
final class LUIFlutterSplit {
  static const _viewFingerprint =
      'lui-extension-v1|10:split-view|profiles:android/flutter,ios/flutter,ios/swiftui,linux/flutter,linux/gpui,macos/flutter,macos/gpui,macos/swiftui,web/web,windows/flutter,windows/gpui|standard-children:0|children:12:split-branch,10:split-pane|properties:17:divider-thickness:float:optional:none,24:accessibility-identifier:string:optional:none,9:animation:bool:optional:none|events:';
  static const _branchFingerprint =
      'lui-extension-v1|12:split-branch|profiles:android/flutter,ios/flutter,ios/swiftui,linux/flutter,linux/gpui,macos/flutter,macos/gpui,macos/swiftui,web/web,windows/flutter,windows/gpui|standard-children:0|children:12:split-branch,10:split-pane|properties:11:orientation:string:required:none,5:ratio:float:required:none|events:13:ratio-changed[5:ratio:float:required]';
  static const _paneFingerprint =
      'lui-extension-v1|10:split-pane|profiles:android/flutter,ios/flutter,ios/swiftui,linux/flutter,linux/gpui,macos/flutter,macos/gpui,macos/swiftui,web/web,windows/flutter,windows/gpui|standard-children:0|children:9:split-tab|properties:24:accessibility-identifier:string:optional:none,7:focused:bool:optional:none,7:pane-id:string:required:none,8:selected:string:optional:none|events:10:split-drop[3:tab:string:required,4:edge:string:required,9:from-pane:string:required],10:tab-closed[3:tab:string:required],11:pane-closed[],12:pane-focused[],12:tab-selected[3:tab:string:required],15:split-requested[11:orientation:string:required],8:navigate[9:direction:string:required],9:tab-moved[3:tab:string:required,5:index:int:required,9:from-pane:string:required]';
  static const _tabFingerprint =
      'lui-extension-v1|9:split-tab|profiles:android/flutter,ios/flutter,ios/swiftui,linux/flutter,linux/gpui,macos/flutter,macos/gpui,macos/swiftui,web/web,windows/flutter,windows/gpui|standard-children:1|children:|properties:24:accessibility-identifier:string:optional:none,4:icon:string:optional:none,5:dirty:bool:optional:none,5:title:string:required:none,6:tab-id:string:required:none,8:closable:bool:optional:none|events:';

  static const _accessibilityIdentifier = LUIExtensionProperty(
    name: 'accessibility-identifier',
    kind: LUIExtensionValueKind.string,
  );

  /// Registers all four split components.
  static void register(LUIFlutterExtensionRegistry registry) {
    registry
      ..register(
        LUIFlutterExtension(
          identifier: 'split-view',
          fingerprint: _viewFingerprint,
          childIdentifiers: const ['split-branch', 'split-pane'],
          properties: const [
            LUIExtensionProperty(
              name: 'divider-thickness',
              kind: LUIExtensionValueKind.doubleValue,
            ),
            LUIExtensionProperty(
              name: 'animation',
              kind: LUIExtensionValueKind.boolean,
            ),
            _accessibilityIdentifier,
          ],
          builder: _SplitView.new,
        ),
      )
      ..register(
        LUIFlutterExtension(
          identifier: 'split-branch',
          fingerprint: _branchFingerprint,
          childIdentifiers: const ['split-branch', 'split-pane'],
          properties: const [
            LUIExtensionProperty(
              name: 'orientation',
              kind: LUIExtensionValueKind.string,
              isRequired: true,
            ),
            LUIExtensionProperty(
              name: 'ratio',
              kind: LUIExtensionValueKind.doubleValue,
              isRequired: true,
            ),
          ],
          events: const [
            LUIExtensionEventSchema(
              name: 'ratio-changed',
              fields: [
                LUIExtensionEventField(
                  name: 'ratio',
                  kind: LUIExtensionValueKind.doubleValue,
                  isRequired: true,
                ),
              ],
            ),
          ],
          builder: _SplitBranch.new,
        ),
      )
      ..register(
        LUIFlutterExtension(
          identifier: 'split-pane',
          fingerprint: _paneFingerprint,
          childIdentifiers: const ['split-tab'],
          properties: const [
            LUIExtensionProperty(
              name: 'pane-id',
              kind: LUIExtensionValueKind.string,
              isRequired: true,
            ),
            LUIExtensionProperty(
              name: 'selected',
              kind: LUIExtensionValueKind.string,
            ),
            LUIExtensionProperty(
              name: 'focused',
              kind: LUIExtensionValueKind.boolean,
            ),
            _accessibilityIdentifier,
          ],
          events: const [
            LUIExtensionEventSchema(
              name: 'tab-selected',
              fields: [
                LUIExtensionEventField(
                  name: 'tab',
                  kind: LUIExtensionValueKind.string,
                  isRequired: true,
                ),
              ],
            ),
            LUIExtensionEventSchema(
              name: 'tab-closed',
              fields: [
                LUIExtensionEventField(
                  name: 'tab',
                  kind: LUIExtensionValueKind.string,
                  isRequired: true,
                ),
              ],
            ),
            LUIExtensionEventSchema(
              name: 'tab-moved',
              fields: [
                LUIExtensionEventField(
                  name: 'tab',
                  kind: LUIExtensionValueKind.string,
                  isRequired: true,
                ),
                LUIExtensionEventField(
                  name: 'index',
                  kind: LUIExtensionValueKind.integer,
                  isRequired: true,
                ),
                LUIExtensionEventField(
                  name: 'from-pane',
                  kind: LUIExtensionValueKind.string,
                  isRequired: true,
                ),
              ],
            ),
            LUIExtensionEventSchema(name: 'pane-focused'),
            LUIExtensionEventSchema(
              name: 'navigate',
              fields: [
                LUIExtensionEventField(
                  name: 'direction',
                  kind: LUIExtensionValueKind.string,
                  isRequired: true,
                ),
              ],
            ),
            LUIExtensionEventSchema(
              name: 'split-requested',
              fields: [
                LUIExtensionEventField(
                  name: 'orientation',
                  kind: LUIExtensionValueKind.string,
                  isRequired: true,
                ),
              ],
            ),
            LUIExtensionEventSchema(
              name: 'split-drop',
              fields: [
                LUIExtensionEventField(
                  name: 'tab',
                  kind: LUIExtensionValueKind.string,
                  isRequired: true,
                ),
                LUIExtensionEventField(
                  name: 'from-pane',
                  kind: LUIExtensionValueKind.string,
                  isRequired: true,
                ),
                LUIExtensionEventField(
                  name: 'edge',
                  kind: LUIExtensionValueKind.string,
                  isRequired: true,
                ),
              ],
            ),
            LUIExtensionEventSchema(name: 'pane-closed'),
          ],
          builder: _SplitPane.new,
        ),
      )
      ..register(
        LUIFlutterExtension(
          identifier: 'split-tab',
          fingerprint: _tabFingerprint,
          acceptsStandardChildren: true,
          properties: const [
            LUIExtensionProperty(
              name: 'tab-id',
              kind: LUIExtensionValueKind.string,
              isRequired: true,
            ),
            LUIExtensionProperty(
              name: 'title',
              kind: LUIExtensionValueKind.string,
              isRequired: true,
            ),
            LUIExtensionProperty(
              name: 'icon',
              kind: LUIExtensionValueKind.string,
            ),
            LUIExtensionProperty(
              name: 'dirty',
              kind: LUIExtensionValueKind.boolean,
            ),
            LUIExtensionProperty(
              name: 'closable',
              kind: LUIExtensionValueKind.boolean,
            ),
            _accessibilityIdentifier,
          ],
          builder: _SplitTab.new,
        ),
      );
  }
}

// MARK: - shared helpers

typedef _TabDrag = ({String tab, String pane});

extension on LUIFlutterExtensionContext {
  String? stringOf(String name) => property(name) as String?;
  bool boolOf(String name, {bool fallback = false}) =>
      property(name) as bool? ?? fallback;
  double doubleOf(String name, {double fallback = 0}) =>
      (property(name) as num?)?.toDouble() ?? fallback;
  String? childString(int childID, String name) =>
      childProperty(childID, name) as String?;
  bool childBool(int childID, String name, {bool fallback = false}) =>
      childProperty(childID, name) as bool? ?? fallback;
}

/// Visual settings broadcast by `split-view` through the extension tree.
final class _SplitSettings extends InheritedWidget {
  const _SplitSettings({
    required this.dividerThickness,
    required this.animationEnabled,
    required super.child,
  });

  final double dividerThickness;
  final bool animationEnabled;

  static _SplitSettings of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_SplitSettings>() ??
      const _SplitSettings(
        dividerThickness: 9,
        animationEnabled: true,
        child: SizedBox.shrink(),
      );

  @override
  bool updateShouldNotify(_SplitSettings old) =>
      dividerThickness != old.dividerThickness ||
      animationEnabled != old.animationEnabled;
}

// MARK: - split-view

final class _SplitView extends StatelessWidget {
  const _SplitView(this.ext);

  final LUIFlutterExtensionContext ext;

  @override
  Widget build(BuildContext context) => _SplitSettings(
    dividerThickness: ext.doubleOf('divider-thickness', fallback: 9).clamp(1, 1e9),
    animationEnabled: ext.boolOf('animation', fallback: true),
    child: ext.content,
  );
}

// MARK: - split-branch

final class _SplitBranch extends StatefulWidget {
  const _SplitBranch(this.ext);

  final LUIFlutterExtensionContext ext;

  @override
  State<_SplitBranch> createState() => _SplitBranchState();
}

final class _SplitBranchState extends State<_SplitBranch> {
  late double _ratio = _sourceRatio;
  bool _dragging = false;

  double get _sourceRatio =>
      (widget.ext.doubleOf('ratio', fallback: 0.5)).clamp(0.0, 1.0);

  bool get _horizontal =>
      widget.ext.stringOf('orientation') != 'vertical';

  @override
  void didUpdateWidget(_SplitBranch old) {
    super.didUpdateWidget(old);
    if (!_dragging && (_sourceRatio - _ratio).abs() > 0.000001) {
      _ratio = _sourceRatio;
    }
  }

  void _emit() => widget.ext.emit(
    name: 'ratio-changed',
    values: {'ratio': _ratio},
  );

  void _nudge(double delta) {
    setState(() => _ratio = (_ratio + delta).clamp(0.0, 1.0));
    _emit();
  }

  @override
  Widget build(BuildContext context) {
    final settings = _SplitSettings.of(context);
    final childIDs = widget.ext.childIDs;
    final first = childIDs.isNotEmpty ? childIDs[0] : null;
    final second = childIDs.length > 1 ? childIDs[1] : null;

    return LayoutBuilder(
      builder: (context, constraints) {
        final axis = _horizontal ? constraints.maxWidth : constraints.maxHeight;
        final gap = settings.dividerThickness;
        final available = (axis - gap).clamp(0.0, double.infinity);
        final firstLength = available * _ratio;
        final secondLength = available - firstLength;

        final firstChild = SizedBox(
          width: _horizontal ? firstLength : null,
          height: _horizontal ? null : firstLength,
          child: first != null ? widget.ext.contentFor(first) : null,
        );
        final secondChild = SizedBox(
          width: _horizontal ? secondLength : null,
          height: _horizontal ? null : secondLength,
          child: second != null ? widget.ext.contentFor(second) : null,
        );

        return Stack(
          children: [
            Positioned.fill(
              child: _horizontal
                  ? Row(children: [firstChild, SizedBox(width: gap), secondChild])
                  : Column(
                      children: [firstChild, SizedBox(height: gap), secondChild],
                    ),
            ),
            Positioned(
              left: _horizontal ? firstLength : 0,
              top: _horizontal ? 0 : firstLength,
              width: _horizontal ? gap : constraints.maxWidth,
              height: _horizontal ? constraints.maxHeight : gap,
              child: _Divider(
                horizontal: _horizontal,
                animate: settings.animationEnabled && !_dragging,
                onDragStart: () => _dragging = true,
                onDrag: (delta) {
                  setState(
                    () => _ratio = (_ratio + delta / available)
                        .clamp(0.0, 1.0),
                  );
                },
                onDragEnd: () {
                  _dragging = false;
                  _emit();
                },
                onNudge: _nudge,
              ),
            ),
          ],
        );
      },
    );
  }
}

final class _Divider extends StatelessWidget {
  const _Divider({
    required this.horizontal,
    required this.animate,
    required this.onDragStart,
    required this.onDrag,
    required this.onDragEnd,
    required this.onNudge,
  });

  final bool horizontal;
  final bool animate;
  final VoidCallback onDragStart;
  final ValueChanged<double> onDrag;
  final VoidCallback onDragEnd;
  final ValueChanged<double> onNudge;

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
    bindings: {
      SingleActivator(
        horizontal ? LogicalKeyboardKey.arrowLeft : LogicalKeyboardKey.arrowUp,
      ): () => onNudge(-0.05),
      SingleActivator(
        horizontal ? LogicalKeyboardKey.arrowRight : LogicalKeyboardKey.arrowDown,
      ): () => onNudge(0.05),
    },
    child: Focus(
      child: MouseRegion(
        cursor: horizontal
            ? SystemMouseCursors.resizeColumn
            : SystemMouseCursors.resizeRow,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanStart: (_) => onDragStart(),
          onPanUpdate: (details) =>
              onDrag(horizontal ? details.delta.dx : details.delta.dy),
          onPanEnd: (_) => onDragEnd(),
          onPanCancel: onDragEnd,
          child: Center(
            child: Container(
              width: horizontal ? 1 : null,
              height: horizontal ? null : 1,
              color: Theme.of(context).dividerColor,
            ),
          ),
        ),
      ),
    ),
  );
}

// MARK: - split-pane

final class _SplitPane extends StatefulWidget {
  const _SplitPane(this.ext);

  final LUIFlutterExtensionContext ext;

  @override
  State<_SplitPane> createState() => _SplitPaneState();
}

final class _SplitPaneState extends State<_SplitPane> {
  String? _dropZone; // null | 'center' | 'left' | 'right' | 'top' | 'bottom'
  int? _tabDropIndex;
  final _focusNode = FocusNode();
  final _contentKey = GlobalKey();
  final _chipKeys = <int, GlobalKey>{};

  GlobalKey _chipKey(int tabNode) =>
      _chipKeys.putIfAbsent(tabNode, GlobalKey.new);

  String get _paneId => widget.ext.stringOf('pane-id') ?? '';
  bool get _focused => widget.ext.boolOf('focused');

  List<int> get _tabs => widget.ext.childIDs;

  String _tabId(int tabNode) =>
      widget.ext.childString(tabNode, 'tab-id') ?? '';

  String get _selectedId {
    final selected = widget.ext.stringOf('selected');
    if (selected != null && selected.isNotEmpty) return selected;
    return _tabs.isNotEmpty ? _tabId(_tabs.first) : '';
  }

  void _emit(String name, [Map<String, Object> values = const {}]) =>
      widget.ext.emit(name: name, values: values);

  void _acceptDrag(_TabDrag drag, String zone) {
    setState(() => _dropZone = null);
    if (zone == 'center') {
      _emit('tab-moved', {
        'tab': drag.tab,
        'index': _tabs.length,
        'from-pane': drag.pane,
      });
    } else {
      _emit('split-drop', {
        'tab': drag.tab,
        'from-pane': drag.pane,
        'edge': zone,
      });
    }
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shortcuts = <ShortcutActivator, VoidCallback>{
      for (final entry in <String, LogicalKeyboardKey>{
        'left': LogicalKeyboardKey.arrowLeft,
        'right': LogicalKeyboardKey.arrowRight,
        'up': LogicalKeyboardKey.arrowUp,
        'down': LogicalKeyboardKey.arrowDown,
      }.entries)
        SingleActivator(entry.value, control: true, alt: true): () =>
            _emit('navigate', {'direction': entry.key}),
      for (final entry in <String, LogicalKeyboardKey>{
        'left': LogicalKeyboardKey.arrowLeft,
        'right': LogicalKeyboardKey.arrowRight,
        'up': LogicalKeyboardKey.arrowUp,
        'down': LogicalKeyboardKey.arrowDown,
      }.entries)
        SingleActivator(entry.value, meta: true, alt: true): () =>
            _emit('navigate', {'direction': entry.key}),
      const SingleActivator(LogicalKeyboardKey.keyD, control: true, alt: true):
          () => _emit('split-requested', {'orientation': 'horizontal'}),
      const SingleActivator(LogicalKeyboardKey.keyD, meta: true, alt: true):
          () => _emit('split-requested', {'orientation': 'horizontal'}),
      const SingleActivator(
        LogicalKeyboardKey.keyD,
        control: true,
        alt: true,
        shift: true,
      ): () => _emit('split-requested', {'orientation': 'vertical'}),
      const SingleActivator(
        LogicalKeyboardKey.keyD,
        meta: true,
        alt: true,
        shift: true,
      ): () => _emit('split-requested', {'orientation': 'vertical'}),
      const SingleActivator(LogicalKeyboardKey.backslash, control: true):
          () => _emit('split-requested', {'orientation': 'horizontal'}),
      const SingleActivator(LogicalKeyboardKey.backslash, meta: true):
          () => _emit('split-requested', {'orientation': 'horizontal'}),
      const SingleActivator(
        LogicalKeyboardKey.backslash,
        control: true,
        shift: true,
      ): () => _emit('split-requested', {'orientation': 'vertical'}),
      const SingleActivator(LogicalKeyboardKey.backslash, meta: true, shift: true):
          () => _emit('split-requested', {'orientation': 'vertical'}),
      const SingleActivator(LogicalKeyboardKey.keyW, control: true):
          _closeSelected,
      const SingleActivator(LogicalKeyboardKey.keyW, meta: true):
          _closeSelected,
      const SingleActivator(LogicalKeyboardKey.keyW, control: true, shift: true):
          () => _emit('pane-closed'),
      const SingleActivator(LogicalKeyboardKey.keyW, meta: true, shift: true):
          () => _emit('pane-closed'),
    };

    return CallbackShortcuts(
      bindings: shortcuts,
      child: Focus(
        focusNode: _focusNode,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            _focusNode.requestFocus();
            _emit('pane-focused');
          },
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(
                color: _focused
                    ? Theme.of(context).colorScheme.primary.withAlpha(140)
                    : Colors.transparent,
                width: 2,
              ),
              borderRadius: BorderRadius.circular(4),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                _tabBar(context),
                Expanded(child: _content(context)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _closeSelected() {
    final selected = _selectedId;
    if (selected.isNotEmpty) _emit('tab-closed', {'tab': selected});
  }

  Widget _tabBar(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      height: 30,
      color: theme.colorScheme.surfaceContainerHighest,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (var i = 0; i < _tabs.length; i++) _tabChip(_tabs[i], i),
          _trailingIndicator(),
        ],
      ),
    );
  }

  Widget _trailingIndicator() => AnimatedSize(
    duration: const Duration(milliseconds: 120),
    child: _tabDropIndex == _tabs.length
        ? Container(width: 2, height: 18, color: Colors.blueAccent)
        : const SizedBox.shrink(),
  );

  Widget _tabChip(int tabNode, int index) {
    final theme = Theme.of(context);
    final tabId = _tabId(tabNode);
    final selected = tabId == _selectedId;
    final title = widget.ext.childString(tabNode, 'title') ?? tabId;
    final dirty = widget.ext.childBool(tabNode, 'dirty');
    final closable = widget.ext.childBool(tabNode, 'closable', fallback: true);

    Widget chip = Container(
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      color: selected
          ? theme.colorScheme.surface
          : Colors.transparent,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dirty)
            const Padding(
              padding: EdgeInsets.only(right: 4),
              child: Icon(Icons.circle, size: 5),
            ),
          Text(
            title,
            style: theme.textTheme.labelMedium?.copyWith(
              color: selected ? null : theme.hintColor,
            ),
          ),
          if (closable)
            GestureDetector(
              onTap: () => _emit('tab-closed', {'tab': tabId}),
              child: const Padding(
                padding: EdgeInsets.only(left: 4),
                child: Icon(Icons.close, size: 12),
              ),
            ),
        ],
      ),
    );

    chip = GestureDetector(
      onTap: () {
        _focusNode.requestFocus();
        _emit('tab-selected', {'tab': tabId});
        _emit('pane-focused');
      },
      child: chip,
    );

    chip = Draggable<_TabDrag>(
      data: (tab: tabId, pane: _paneId),
      feedback: Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(6),
            boxShadow: kElevationToShadow[2],
          ),
          child: Text(title, style: theme.textTheme.labelMedium),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.4, child: chip),
      child: chip,
    );

    return DragTarget<_TabDrag>(
      key: _chipKey(tabNode),
      onMove: (details) {
        final box =
            _chipKey(tabNode).currentContext?.findRenderObject() as RenderBox?;
        if (box == null) return;
        final local = box.globalToLocal(details.offset);
        // Left/right halves pick before/after this index.
        setState(
          () => _tabDropIndex =
              local.dx < box.size.width / 2 ? index : index + 1,
        );
      },
      onLeave: (_) {
        if (_tabDropIndex == index || _tabDropIndex == index + 1) {
          setState(() => _tabDropIndex = null);
        }
      },
      onAcceptWithDetails: (details) {
        final target = _tabDropIndex ?? index;
        setState(() => _tabDropIndex = null);
        _emit('tab-moved', {
          'tab': details.data.tab,
          'index': target,
          'from-pane': details.data.pane,
        });
      },
      builder: (context, candidates, _) => Stack(
        children: [
          chip,
          if (_tabDropIndex == index)
            const Positioned(
              left: 0,
              top: 6,
              bottom: 6,
              child: SizedBox(
                width: 2,
                child: ColoredBox(color: Colors.blueAccent),
              ),
            ),
        ],
      ),
    );
  }

  Widget _content(BuildContext context) => DragTarget<_TabDrag>(
    key: _contentKey,
    onMove: (details) => setState(() {
      final box = _contentKey.currentContext?.findRenderObject() as RenderBox?;
      if (box == null) return;
      final local = box.globalToLocal(details.offset);
      final ex = (box.size.width * 0.25).clamp(48.0, 160.0);
      final ey = (box.size.height * 0.25).clamp(48.0, 160.0);
      _dropZone = local.dx < ex
          ? 'left'
          : local.dx > box.size.width - ex
          ? 'right'
          : local.dy < ey
          ? 'top'
          : local.dy > box.size.height - ey
          ? 'bottom'
          : 'center';
    }),
    onLeave: (_) => setState(() => _dropZone = null),
    onAcceptWithDetails: (details) => _acceptDrag(details.data, _dropZone ?? 'center'),
    builder: (context, candidates, _) => Stack(
      fit: StackFit.expand,
      children: [
        // Every tab stays mounted so scroll/focus/editor state survives
        // switching; only the selected one is visible and interactive.
        for (final tabNode in _tabs)
          Offstage(
            offstage: _tabId(tabNode) != _selectedId,
            child: TickerMode(
              enabled: _tabId(tabNode) == _selectedId,
              child: widget.ext.contentFor(tabNode),
            ),
          ),
        if (_dropZone != null) _dropZoneOverlay(context, _dropZone!),
      ],
    ),
  );

  Widget _dropZoneOverlay(BuildContext context, String zone) {
    final accent = Theme.of(context).colorScheme.primary;
    if (zone == 'center') {
      return IgnorePointer(child: ColoredBox(color: accent.withAlpha(26)));
    }
    final horizontal = zone == 'left' || zone == 'right';
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final primary =
              horizontal ? constraints.maxWidth : constraints.maxHeight;
          final extent = (primary * 0.35).clamp(48.0, double.infinity);
          return Align(
            alignment: switch (zone) {
              'left' => Alignment.centerLeft,
              'right' => Alignment.centerRight,
              'top' => Alignment.topCenter,
              _ => Alignment.bottomCenter,
            },
            child: Container(
              width: horizontal ? extent : constraints.maxWidth,
              height: horizontal ? constraints.maxHeight : extent,
              color: accent.withAlpha(46),
            ),
          );
        },
      ),
    );
  }
}

// MARK: - split-tab

/// Tab nodes are data carriers; a bare `split-tab` stacks its children.
final class _SplitTab extends StatelessWidget {
  const _SplitTab(this.ext);

  final LUIFlutterExtensionContext ext;

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      for (final child in ext.childIDs) Positioned.fill(child: ext.contentFor(child)),
    ],
  );
}
