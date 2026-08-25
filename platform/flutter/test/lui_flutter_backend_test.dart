import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lui_flutter_backend/lui_flutter_backend.dart';

void main() {
  testWidgets('applies one LG patch batch to real Flutter widgets', (
    tester,
  ) async {
    final events = <LUIEvent>[];
    final backend = LUIFlutterBackend(onEvent: events.add)
      ..applyJson(_initialBatch);

    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: backend.widget(node: 1))),
    );

    final row = tester.widget<Row>(find.byType(Row));
    expect(row.spacing, 12);
    expect(find.text('Hello from LG'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Continue'));
    expect(events, [const LUIEvent.press(node: 3)]);
  });

  testWidgets('maps Tabs to retained native Button triggers', (tester) async {
    final semantics = tester.ensureSemantics();
    final events = <LUIEvent>[];
    final backend = LUIFlutterBackend(onEvent: events.add)
      ..applyJson('''
      {"generation":1,"ops":[
        {"op":"create-node","id":1,"kind":"tabs"},
        {"op":"create-node","id":2,"kind":"button"},
        {"op":"create-node","id":3,"kind":"button"},
        {"op":"create-node","id":4,"kind":"toggle-button"},
        {"op":"set-prop","id":1,"property":"gap","value":4},
        {"op":"set-prop","id":2,"property":"text","value":"Overview"},
        {"op":"set-prop","id":2,"property":"selected","value":true},
        {"op":"set-prop","id":3,"property":"text","value":"Activity"},
        {"op":"set-prop","id":3,"property":"selected","value":false},
        {"op":"set-prop","id":4,"property":"text","value":"Pinned"},
        {"op":"set-prop","id":4,"property":"selected","value":false},
        {"op":"insert-child","parent":1,"child":2,"index":0},
        {"op":"insert-child","parent":1,"child":3,"index":1},
        {"op":"insert-child","parent":1,"child":4,"index":2}
      ]}
      ''');

    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: backend.widget(node: 1))),
    );

    final tabs = tester.widget<Row>(
      find
          .descendant(
            of: find.byKey(LUIFlutterBackend.nodeKey(1)),
            matching: find.byType(Row),
          )
          .first,
    );
    expect(tabs.spacing, 4);
    expect(find.text('Overview'), findsOneWidget);
    expect(find.text('Activity'), findsOneWidget);
    expect(
      tester
          .widget<Semantics>(find.byKey(const ValueKey('lui-tab-2')))
          .properties
          .selected,
      isTrue,
    );

    await tester.tap(find.text('Activity'));
    await tester.tap(find.text('Pinned'));
    await tester.pump();
    expect(events, const [
      LUIEvent.press(node: 3),
      LUIEvent.toggleChanged(node: 4, checked: true),
    ]);

    final tabsRevision = backend.debugRevision(1);
    final overviewRevision = backend.debugRevision(2);
    final toggleRevision = backend.debugRevision(4);
    backend.applyJson('''
      {"generation":2,"ops":[
        {"op":"set-prop","id":2,"property":"selected","value":false},
        {"op":"set-prop","id":3,"property":"selected","value":true}
      ]}
      ''');
    await tester.pump();
    expect(backend.debugRevision(1), tabsRevision);
    expect(backend.debugRevision(2), overviewRevision + 1);
    expect(backend.debugRevision(4), toggleRevision);
    expect(
      tester
          .widget<Semantics>(find.byKey(const ValueKey('lui-tab-3')))
          .properties
          .selected,
      isTrue,
    );
    semantics.dispose();
  });

  testWidgets('maps ButtonGroup and ToggleGroup as retained native groups', (
    tester,
  ) async {
    final events = <LUIEvent>[];
    final backend = LUIFlutterBackend(onEvent: events.add)
      ..applyJson('''
      {"generation":1,"ops":[
        {"op":"create-node","id":1,"kind":"column"},
        {"op":"create-node","id":2,"kind":"button-group"},
        {"op":"create-node","id":3,"kind":"toggle-group"},
        {"op":"create-node","id":4,"kind":"button"},
        {"op":"create-node","id":5,"kind":"toggle-button"},
        {"op":"create-node","id":6,"kind":"toggle-button"},
        {"op":"set-prop","id":2,"property":"gap","value":4},
        {"op":"set-prop","id":3,"property":"gap","value":8},
        {"op":"set-prop","id":4,"property":"text","value":"Save"},
        {"op":"set-prop","id":5,"property":"text","value":"Pin"},
        {"op":"set-prop","id":5,"property":"selected","value":true},
        {"op":"set-prop","id":6,"property":"text","value":"Backend-owned"},
        {"op":"insert-child","parent":1,"child":2,"index":0},
        {"op":"insert-child","parent":1,"child":3,"index":1},
        {"op":"insert-child","parent":2,"child":4,"index":0},
        {"op":"insert-child","parent":2,"child":5,"index":1},
        {"op":"insert-child","parent":3,"child":6,"index":0}
      ]}
      ''');

    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: backend.widget(node: 1))),
    );

    final buttonGroup = tester.widget<Row>(
      find
          .descendant(
            of: find.byKey(LUIFlutterBackend.nodeKey(2)),
            matching: find.byType(Row),
          )
          .first,
    );
    final toggleGroup = tester.widget<Row>(
      find
          .descendant(
            of: find.byKey(LUIFlutterBackend.nodeKey(3)),
            matching: find.byType(Row),
          )
          .first,
    );
    expect(buttonGroup.spacing, 4);
    expect(toggleGroup.spacing, 8);
    expect(find.text('Save'), findsOneWidget);
    expect(find.text('Backend-owned'), findsOneWidget);

    await tester.tap(find.text('Save'));
    await tester.tap(find.text('Pin'));
    await tester.pump();
    expect(events, const [
      LUIEvent.press(node: 4),
      LUIEvent.toggleChanged(node: 5, checked: false),
    ]);

    final buttonGroupRevision = backend.debugRevision(2);
    final toggleGroupRevision = backend.debugRevision(3);
    final pinRevision = backend.debugRevision(5);
    final backendOwnedRevision = backend.debugRevision(6);
    backend.applyJson('''
      {"generation":2,"ops":[
        {"op":"set-prop","id":5,"property":"selected","value":false},
        {"op":"remove-child","parent":3,"child":6},
        {"op":"insert-child","parent":2,"child":6,"index":2}
      ]}
      ''');
    await tester.pump();
    expect(backend.debugRevision(2), buttonGroupRevision + 1);
    expect(backend.debugRevision(3), toggleGroupRevision + 1);
    expect(backend.debugRevision(5), pinRevision + 1);
    expect(backend.debugRevision(6), backendOwnedRevision + 1);
    expect(find.text('Backend-owned'), findsOneWidget);
  });

  testWidgets('horizontal groups wrap focus and skip disabled controls', (
    tester,
  ) async {
    final events = <LUIEvent>[];
    final backend = LUIFlutterBackend(onEvent: events.add)
      ..applyJson('''
      {"generation":1,"ops":[
        {"op":"create-node","id":1,"kind":"button-group"},
        {"op":"create-node","id":2,"kind":"button"},
        {"op":"create-node","id":3,"kind":"button"},
        {"op":"create-node","id":4,"kind":"toggle-button"},
        {"op":"set-prop","id":2,"property":"text","value":"First"},
        {"op":"set-prop","id":2,"property":"autofocus","value":true},
        {"op":"set-prop","id":3,"property":"text","value":"Disabled"},
        {"op":"set-prop","id":3,"property":"enabled","value":false},
        {"op":"set-prop","id":4,"property":"text","value":"Last"},
        {"op":"insert-child","parent":1,"child":2,"index":0},
        {"op":"insert-child","parent":1,"child":3,"index":1},
        {"op":"insert-child","parent":1,"child":4,"index":2}
      ]}
      ''');

    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: backend.widget(node: 1))),
    );
    await tester.pump();

    ButtonStyleButton control(String label) => tester.widget<ButtonStyleButton>(
      find.ancestor(
        of: find.text(label),
        matching: find.byWidgetPredicate(
          (widget) => widget is ButtonStyleButton,
        ),
      ),
    );

    expect(control('First').focusNode?.hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(control('Last').focusNode?.hasFocus, isTrue);
    expect(events, isEmpty);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(control('First').focusNode?.hasFocus, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(control('Last').focusNode?.hasFocus, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.home);
    await tester.pump();
    expect(control('First').focusNode?.hasFocus, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.end);
    await tester.pump();
    expect(control('Last').focusNode?.hasFocus, isTrue);
    expect(control('Disabled').focusNode?.hasFocus, isFalse);
    expect(events, isEmpty);
  });

  testWidgets('maps Breadcrumb and Pagination as retained native groups', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final events = <LUIEvent>[];
    final backend = LUIFlutterBackend(onEvent: events.add)
      ..applyJson('''
      {"generation":1,"ops":[
        {"op":"create-node","id":1,"kind":"column"},
        {"op":"create-node","id":2,"kind":"breadcrumb"},
        {"op":"create-node","id":3,"kind":"text"},
        {"op":"create-node","id":4,"kind":"icon"},
        {"op":"create-node","id":5,"kind":"text"},
        {"op":"create-node","id":6,"kind":"pagination"},
        {"op":"create-node","id":7,"kind":"button"},
        {"op":"create-node","id":8,"kind":"button"},
        {"op":"set-prop","id":2,"property":"accessibility-label","value":"Component path"},
        {"op":"set-prop","id":3,"property":"text","value":"Home"},
        {"op":"set-prop","id":3,"property":"press-enabled","value":true},
        {"op":"set-prop","id":4,"property":"name","value":"chevron-right"},
        {"op":"set-prop","id":5,"property":"text","value":"Components"},
        {"op":"set-prop","id":6,"property":"accessibility-label","value":"Gallery pages"},
        {"op":"set-prop","id":7,"property":"text","value":"1"},
        {"op":"set-prop","id":7,"property":"selected","value":true},
        {"op":"set-prop","id":8,"property":"text","value":"2"},
        {"op":"insert-child","parent":1,"child":2,"index":0},
        {"op":"insert-child","parent":1,"child":6,"index":1},
        {"op":"insert-child","parent":2,"child":3,"index":0},
        {"op":"insert-child","parent":2,"child":4,"index":1},
        {"op":"insert-child","parent":2,"child":5,"index":2},
        {"op":"insert-child","parent":6,"child":7,"index":0},
        {"op":"insert-child","parent":6,"child":8,"index":1}
      ]}
      ''');

    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: backend.widget(node: 1))),
    );

    Row groupRow(int node) => tester.widget<Row>(
      find
          .descendant(
            of: find.byKey(LUIFlutterBackend.nodeKey(node)),
            matching: find.byType(Row),
          )
          .first,
    );
    expect(groupRow(2).spacing, 4);
    expect(groupRow(6).spacing, 2);
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Components'), findsOneWidget);
    expect(
      tester.getSemantics(find.text('Home')),
      matchesSemantics(
        label: 'Home',
        isButton: true,
        hasEnabledState: true,
        isEnabled: true,
        isFocusable: true,
        hasFocusAction: true,
        hasTapAction: true,
      ),
    );

    await tester.tap(find.text('Home'));
    await tester.tap(find.text('2'));
    await tester.pump();
    expect(events, const [LUIEvent.press(node: 3), LUIEvent.press(node: 8)]);

    final breadcrumbRevision = backend.debugRevision(2);
    final homeRevision = backend.debugRevision(3);
    final paginationRevision = backend.debugRevision(6);
    backend.applyJson('''
      {"generation":2,"ops":[
        {"op":"set-prop","id":7,"property":"selected","value":false},
        {"op":"set-prop","id":8,"property":"selected","value":true}
      ]}
      ''');
    await tester.pump();
    expect(backend.debugRevision(2), breadcrumbRevision);
    expect(backend.debugRevision(3), homeRevision);
    expect(backend.debugRevision(6), paginationRevision);
    semantics.dispose();
  });

  test('rejects text on Tabs instead of silently ignoring it', () {
    final backend = LUIFlutterBackend();
    expect(
      () => backend.applyJson('''
      {"generation":1,"ops":[
        {"op":"create-node","id":1,"kind":"tabs"},
        {"op":"set-prop","id":1,"property":"text","value":"Overview"}
      ]}
      '''),
      throwsA(
        isA<LUIBackendException>().having(
          (error) => error.message,
          'message',
          contains('unsupported property'),
        ),
      ),
    );
    expect(backend.generation, 0);
  });

  testWidgets('maps the complete Vercel Native Button contract', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final events = <LUIEvent>[];
    final backend = LUIFlutterBackend(onEvent: events.add)
      ..applyJson('''
      {"generation":1,"ops":[
        {"op":"create-node","id":1,"kind":"button"},
        {"op":"set-prop","id":1,"property":"text","value":"Download"},
        {"op":"set-prop","id":1,"property":"variant","value":"primary"},
        {"op":"set-prop","id":1,"property":"size","value":"lg"},
        {"op":"set-prop","id":1,"property":"icon","value":"download"},
        {"op":"set-prop","id":1,"property":"icon-placement","value":"trailing"},
        {"op":"set-prop","id":1,"property":"selected","value":true},
        {"op":"set-prop","id":1,"property":"autofocus","value":true},
        {"op":"set-prop","id":1,"property":"accessibility-label","value":"Download report"},
        {"op":"set-prop","id":1,"property":"hold-enabled","value":true}
      ]}
      ''');

    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: backend.widget(node: 1))),
    );

    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.autofocus, isTrue);
    expect(find.byIcon(Icons.download), findsOneWidget);
    expect(
      tester.getSemantics(find.byType(FilledButton)),
      matchesSemantics(
        label: 'Download report',
        hasSelectedState: true,
        isButton: true,
        isSelected: true,
        isEnabled: true,
        hasEnabledState: true,
        hasTapAction: true,
        hasLongPressAction: true,
      ),
    );

    await tester.longPress(find.byType(FilledButton));
    await tester.pump();
    expect(events, [const LUIEvent.hold(node: 1)]);

    events.clear();
    await tester.tap(find.byType(FilledButton));
    await tester.pump();
    expect(events, [const LUIEvent.press(node: 1)]);
    semantics.dispose();
  });

  test('rejects invalid and unnamed icon-only Buttons atomically', () {
    final invalidVariant = LUIFlutterBackend();
    expect(
      () => invalidVariant.applyJson('''
      {"generation":1,"ops":[
        {"op":"create-node","id":1,"kind":"button"},
        {"op":"set-prop","id":1,"property":"text","value":"Link"},
        {"op":"set-prop","id":1,"property":"variant","value":"link"}
      ]}
      '''),
      throwsA(isA<LUIBackendException>()),
    );
    expect(invalidVariant.generation, 0);

    final unnamed = LUIFlutterBackend();
    expect(
      () => unnamed.applyJson('''
      {"generation":1,"ops":[
        {"op":"create-node","id":1,"kind":"button"},
        {"op":"set-prop","id":1,"property":"size","value":"icon"},
        {"op":"set-prop","id":1,"property":"icon","value":"plus"}
      ]}
      '''),
      throwsA(isA<LUIBackendException>()),
    );
    expect(unnamed.generation, 0);
  });

  testWidgets('retains controlled and uncontrolled ToggleButton selection', (
    tester,
  ) async {
    final events = <LUIEvent>[];
    final backend = LUIFlutterBackend(onEvent: events.add)
      ..applyJson('''
      {"generation":1,"ops":[
        {"op":"create-node","id":1,"kind":"row"},
        {"op":"create-node","id":2,"kind":"toggle-button"},
        {"op":"create-node","id":3,"kind":"toggle-button"},
        {"op":"set-prop","id":2,"property":"text","value":"Bold"},
        {"op":"set-prop","id":2,"property":"variant","value":"outline"},
        {"op":"set-prop","id":2,"property":"selected","value":false},
        {"op":"set-prop","id":3,"property":"text","value":"Italic"},
        {"op":"set-prop","id":3,"property":"icon","value":"edit"},
        {"op":"insert-child","parent":1,"child":2,"index":0},
        {"op":"insert-child","parent":1,"child":3,"index":1}
      ]}
      ''');

    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: backend.widget(node: 1))),
    );
    await tester.tap(find.widgetWithText(OutlinedButton, 'Bold'));
    await tester.tap(find.widgetWithText(TextButton, 'Italic'));
    await tester.pump();

    expect(events, const [
      LUIEvent.toggleChanged(node: 2, checked: true),
      LUIEvent.toggleChanged(node: 3, checked: true),
    ]);
    expect(
      tester
          .widget<Semantics>(find.byKey(const ValueKey('lui-toggle-2')))
          .properties
          .selected,
      isTrue,
    );
    expect(
      tester
          .widget<Semantics>(find.byKey(const ValueKey('lui-toggle-3')))
          .properties
          .selected,
      isTrue,
    );

    backend.applyJson('''
      {"generation":2,"ops":[
        {"op":"set-prop","id":3,"property":"text","value":"Italic style"}
      ]}
      ''');
    await tester.pump();
    expect(
      tester
          .widget<Semantics>(find.byKey(const ValueKey('lui-toggle-3')))
          .properties
          .selected,
      isTrue,
      reason: 'an unrelated patch must not erase backend-owned selection',
    );

    backend.applyJson('''
      {"generation":3,"ops":[
        {"op":"set-prop","id":2,"property":"selected","value":true}
      ]}
      ''');
    await tester.pump();
    expect(
      tester
          .widget<Semantics>(find.byKey(const ValueKey('lui-toggle-2')))
          .properties
          .selected,
      isTrue,
      reason: 'a model selection patch must reconcile local interaction',
    );
  });

  testWidgets('keyed move preserves the Flutter RenderObject', (tester) async {
    final backend = LUIFlutterBackend()..applyJson(_initialBatch);

    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: backend.widget(node: 1))),
    );
    final originalButton = tester.renderObject(
      find.byKey(LUIFlutterBackend.nodeKey(3)),
    );

    backend.applyJson(
      '{"generation":2,"ops":['
      '{"op":"move-child","parent":1,"child":3,"index":0}]}',
    );
    await tester.pump();

    expect(
      tester.renderObject(find.byKey(LUIFlutterBackend.nodeKey(3))),
      same(originalButton),
    );
  });

  test('rejects an invalid batch atomically', () {
    final backend = LUIFlutterBackend()..applyJson(_initialBatch);

    expect(
      () => backend.applyJson(
        '{"generation":2,"ops":['
        '{"op":"create-node","id":4,"kind":"text"},'
        '{"op":"insert-child","parent":99,"child":4,"index":0}]}',
      ),
      throwsA(isA<LUIBackendException>()),
    );
    expect(backend.containsNode(4), isFalse);
    expect(backend.generation, 1);
  });

  test('rejects duplicate or skipped generations atomically', () {
    final backend = LUIFlutterBackend()..applyJson(_initialBatch);

    expect(
      () => backend.applyJson(
        '{"generation":3,"ops":['
        '{"op":"create-node","id":4,"kind":"text"}]}',
      ),
      throwsA(
        isA<LUIBackendException>().having(
          (error) => error.message,
          'message',
          contains('expected patch generation 2'),
        ),
      ),
    );
    expect(backend.containsNode(4), isFalse);
    expect(backend.generation, 1);
  });

  test('property patches invalidate only their retained node', () {
    final backend = LUIFlutterBackend()..applyJson(_initialBatch);

    backend.applyJson(
      '{"generation":2,"ops":['
      '{"op":"set-prop","id":2,"property":"text","value":"Updated"}]}',
    );

    expect(backend.debugRevision(1), 0);
    expect(backend.debugRevision(2), 1);
    expect(backend.debugRevision(3), 0);
  });

  testWidgets('maps all direct text-entry kinds to native TextFields', (
    tester,
  ) async {
    final events = <LUIEvent>[];
    final backend = LUIFlutterBackend(onEvent: events.add)
      ..applyJson('''
      {"generation":1,"ops":[
        {"op":"create-node","id":1,"kind":"column"},
        {"op":"create-node","id":2,"kind":"text-field"},
        {"op":"create-node","id":3,"kind":"input"},
        {"op":"create-node","id":4,"kind":"search-field"},
        {"op":"create-node","id":5,"kind":"textarea"},
        {"op":"set-prop","id":2,"property":"text","value":"Draft"},
        {"op":"set-prop","id":2,"property":"placeholder","value":"Project"},
        {"op":"set-prop","id":2,"property":"autofocus","value":true},
        {"op":"set-prop","id":3,"property":"placeholder","value":"Email"},
        {"op":"set-prop","id":4,"property":"text","value":"Query"},
        {"op":"set-prop","id":4,"property":"placeholder","value":"Search"},
        {"op":"set-prop","id":5,"property":"text","value":"One line"},
        {"op":"set-prop","id":5,"property":"submit-on-enter","value":true},
        {"op":"insert-child","parent":1,"child":2,"index":0},
        {"op":"insert-child","parent":1,"child":3,"index":1},
        {"op":"insert-child","parent":1,"child":4,"index":2},
        {"op":"insert-child","parent":1,"child":5,"index":3}
      ]}
      ''');

    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: backend.widget(node: 1))),
    );

    expect(find.byType(TextField), findsNWidgets(4));
    final textFieldFinder = find.descendant(
      of: find.byKey(LUIFlutterBackend.nodeKey(2)),
      matching: find.byType(TextField),
    );
    final searchFinder = find.descendant(
      of: find.byKey(LUIFlutterBackend.nodeKey(4)),
      matching: find.byType(TextField),
    );
    final textareaFinder = find.descendant(
      of: find.byKey(LUIFlutterBackend.nodeKey(5)),
      matching: find.byType(TextField),
    );
    final textField = tester.widget<TextField>(textFieldFinder);
    final search = tester.widget<TextField>(searchFinder);
    final textarea = tester.widget<TextField>(textareaFinder);
    expect(textField.autofocus, isTrue);
    expect(textField.decoration?.hintText, 'Project');
    expect(search.decoration?.prefixIcon, isA<Icon>());
    expect(search.decoration?.suffixIcon, isA<IconButton>());
    expect(textarea.minLines, 1);
    expect(textarea.maxLines, isNull);
    expect(textarea.keyboardType, TextInputType.multiline);

    await tester.enterText(textFieldFinder, 'Updated');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(
      events,
      contains(const LUITextChangedEvent(node: 2, text: 'Updated')),
    );
    expect(events, contains(const LUISubmitEvent(node: 2)));

    await tester.tap(
      find.descendant(
        of: find.byKey(LUIFlutterBackend.nodeKey(4)),
        matching: find.byType(IconButton),
      ),
    );
    await tester.pump();
    expect(events, contains(const LUITextChangedEvent(node: 4, text: '')));
  });

  testWidgets('maps picker primitives to native retained widgets and events', (
    tester,
  ) async {
    final events = <LUIEvent>[];
    final backend = LUIFlutterBackend(onEvent: events.add)
      ..applyJson('''
      {"generation":1,"ops":[
        {"op":"create-node","id":1,"kind":"column"},
        {"op":"create-node","id":2,"kind":"select"},
        {"op":"create-node","id":3,"kind":"combobox"},
        {"op":"create-node","id":4,"kind":"dropdown-menu"},
        {"op":"create-node","id":5,"kind":"menu-item"},
        {"op":"create-node","id":6,"kind":"stack"},
        {"op":"set-prop","id":1,"property":"cross","value":"start"},
        {"op":"set-prop","id":2,"property":"text","value":"Production"},
        {"op":"set-prop","id":2,"property":"press-enabled","value":true},
        {"op":"set-prop","id":3,"property":"placeholder","value":"Search"},
        {"op":"set-prop","id":3,"property":"submit-enabled","value":true},
        {"op":"set-prop","id":4,"property":"anchor","value":"below"},
        {"op":"set-prop","id":4,"property":"anchor-alignment","value":"stretch"},
        {"op":"set-prop","id":4,"property":"anchor-offset","value":6.0},
        {"op":"set-prop","id":5,"property":"text","value":"Production"},
        {"op":"set-prop","id":5,"property":"selected","value":true},
        {"op":"set-prop","id":5,"property":"press-enabled","value":true},
        {"op":"insert-child","parent":1,"child":6,"index":0},
        {"op":"insert-child","parent":1,"child":3,"index":1},
        {"op":"insert-child","parent":6,"child":2,"index":0},
        {"op":"insert-child","parent":6,"child":4,"index":1},
        {"op":"insert-child","parent":4,"child":5,"index":0}
      ]}
      ''');

    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: backend.widget(node: 1))),
    );
    await tester.pump();

    expect(find.widgetWithText(OutlinedButton, 'Production'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    expect(find.byType(MenuItemButton), findsOneWidget);
    expect(find.byIcon(Icons.check), findsOneWidget);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Production'));
    await tester.tap(find.byType(MenuItemButton));
    await tester.pump();
    backend.performDismiss(4);
    backend.applyJson('''
      {"generation":2,"ops":[
        {"op":"remove-child","parent":6,"child":4},
        {"op":"remove-child","parent":4,"child":5},
        {"op":"drop-node","id":5},
        {"op":"drop-node","id":4}
      ]}
      ''');
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'sol');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(events, [
      const LUIPressEvent(node: 2),
      const LUIPressEvent(node: 5),
      const LUIDismissEvent(node: 4),
      const LUITextChangedEvent(node: 3, text: 'sol'),
      const LUISubmitEvent(node: 3),
    ]);
  });

  testWidgets(
    'maps Tooltip to native hover intent while retaining its trigger',
    (tester) async {
      final events = <LUIEvent>[];
      final backend = LUIFlutterBackend(onEvent: events.add)
        ..applyJson('''
      {"generation":1,"ops":[
        {"op":"create-node","id":1,"kind":"column"},
        {"op":"create-node","id":2,"kind":"stack"},
        {"op":"create-node","id":3,"kind":"button"},
        {"op":"create-node","id":4,"kind":"tooltip"},
        {"op":"create-node","id":5,"kind":"tooltip"},
        {"op":"set-prop","id":3,"property":"text","value":"Bold"},
        {"op":"set-prop","id":4,"property":"text","value":"Bold the selection"},
        {"op":"set-prop","id":4,"property":"anchor","value":"above"},
        {"op":"set-prop","id":4,"property":"anchor-alignment","value":"end"},
        {"op":"set-prop","id":4,"property":"anchor-offset","value":8.0},
        {"op":"set-prop","id":4,"property":"tooltip-delay","value":250},
        {"op":"set-prop","id":5,"property":"text","value":"Copied!"},
        {"op":"insert-child","parent":1,"child":2,"index":0},
        {"op":"insert-child","parent":2,"child":3,"index":0},
        {"op":"insert-child","parent":2,"child":4,"index":1},
        {"op":"insert-child","parent":1,"child":5,"index":1}
      ]}
      ''');

      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: backend.widget(node: 1))),
      );

      final nativeTooltip = tester.widget<Tooltip>(find.byType(Tooltip));
      expect(nativeTooltip.message, 'Bold the selection');
      expect(nativeTooltip.waitDuration, const Duration(milliseconds: 250));
      expect(nativeTooltip.preferBelow, isFalse);
      expect(find.text('Copied!'), findsOneWidget);
      final buttonRenderObject = tester.renderObject(
        find.byKey(LUIFlutterBackend.nodeKey(3)),
      );

      final mouse = await tester.createGesture(kind: ui.PointerDeviceKind.mouse);
      await mouse.addPointer(location: const Offset(1, 1));
      await mouse.moveTo(tester.getCenter(find.text('Bold')));
      await tester.pump(const Duration(milliseconds: 249));
      expect(find.text('Bold the selection'), findsNothing);
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump();
      expect(find.text('Bold the selection'), findsOneWidget);

      await tester.tap(find.text('Bold'));
      await tester.pump();
      expect(events, const [LUIEvent.press(node: 3)]);
      expect(find.text('Bold the selection'), findsNothing);

      backend.applyJson('''
      {"generation":2,"ops":[
        {"op":"set-prop","id":4,"property":"text","value":"Toggle bold"},
        {"op":"set-prop","id":4,"property":"tooltip-delay","value":0}
      ]}
      ''');
      await tester.pump();
      expect(
        tester.renderObject(find.byKey(LUIFlutterBackend.nodeKey(3))),
        same(buttonRenderObject),
      );
      expect(tester.widget<Tooltip>(find.byType(Tooltip)).message, 'Toggle bold');
      expect(
        tester.widget<Tooltip>(find.byType(Tooltip)).waitDuration,
        Duration.zero,
      );
      await mouse.removePointer();

      expect(
        () => backend.applyJson('''
        {"generation":3,"ops":[
          {"op":"set-prop","id":5,"property":"tooltip-delay","value":20}
        ]}
        '''),
        throwsA(isA<LUIBackendException>()),
      );
      expect(backend.generation, 2);
    },
  );

  testWidgets(
    'maps ListItem text and custom children to retained native rows',
    (tester) async {
      final events = <LUIEvent>[];
      final backend = LUIFlutterBackend(onEvent: events.add)
        ..applyJson('''
      {"generation":1,"ops":[
        {"op":"create-node","id":1,"kind":"list"},
        {"op":"create-node","id":2,"kind":"list-item"},
        {"op":"create-node","id":3,"kind":"list-item"},
        {"op":"create-node","id":4,"kind":"row"},
        {"op":"create-node","id":5,"kind":"text"},
        {"op":"set-prop","id":2,"property":"text","value":"Quarterly report.md"},
        {"op":"set-prop","id":2,"property":"icon","value":"file-text"},
        {"op":"set-prop","id":2,"property":"selected","value":true},
        {"op":"set-prop","id":2,"property":"press-enabled","value":true},
        {"op":"set-prop","id":2,"property":"double-press-enabled","value":true},
        {"op":"set-prop","id":2,"property":"submit-enabled","value":true},
        {"op":"set-prop","id":5,"property":"text","value":"Custom child row"},
        {"op":"insert-child","parent":1,"child":2,"index":0},
        {"op":"insert-child","parent":1,"child":3,"index":1},
        {"op":"insert-child","parent":3,"child":4,"index":0},
        {"op":"insert-child","parent":4,"child":5,"index":0}
      ]}
      ''');

      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: backend.widget(node: 1))),
      );

      expect(find.byType(ListTile), findsNWidgets(2));
      expect(find.text('Quarterly report.md'), findsOneWidget);
      expect(find.text('Custom child row'), findsOneWidget);
      expect(find.byIcon(Icons.description_outlined), findsOneWidget);
      final retained = tester.renderObject(find.text('Quarterly report.md'));

      await tester.tap(find.text('Quarterly report.md'));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('Quarterly report.md'));
      await tester.pump(const Duration(milliseconds: 40));
      await tester.tap(find.text('Quarterly report.md'));
      await tester.pump();
      expect(
        events.map((event) => event.runtimeType.toString()),
        containsAllInOrder([
          'LUIPressEvent',
          'LUIPressEvent',
          'LUIPressEvent',
          'LUIDoublePressEvent',
        ]),
      );

      backend.applyJson('''
      {"generation":2,"ops":[
        {"op":"set-prop","id":2,"property":"selected","value":false}
      ]}
      ''');
      await tester.pump();
      expect(
        tester.renderObject(find.text('Quarterly report.md')),
        same(retained),
      );
    },
  );

  testWidgets(
    'registering an image invalidates only Avatars that reference its ImageId',
    (tester) async {
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      canvas.drawColor(const Color(0xff6750a4), BlendMode.src);
      final image = await recorder.endRecording().toImage(64, 64);
      addTearDown(image.dispose);

      final backend = LUIFlutterBackend()
        ..applyJson('''
      {"generation":1,"ops":[
        {"op":"create-node","id":1,"kind":"row"},
        {"op":"create-node","id":2,"kind":"avatar"},
        {"op":"create-node","id":3,"kind":"avatar"},
        {"op":"set-prop","id":2,"property":"text","value":"ZN"},
        {"op":"set-prop","id":2,"property":"image","value":7},
        {"op":"set-prop","id":2,"property":"source-x","value":8.0},
        {"op":"set-prop","id":2,"property":"source-y","value":4.0},
        {"op":"set-prop","id":2,"property":"source-width","value":32.0},
        {"op":"set-prop","id":2,"property":"source-height","value":24.0},
        {"op":"set-prop","id":2,"property":"accessibility-label","value":"Profile picture"},
        {"op":"set-prop","id":3,"property":"text","value":"CT"},
        {"op":"set-prop","id":3,"property":"image","value":8},
        {"op":"insert-child","parent":1,"child":2,"index":0},
        {"op":"insert-child","parent":1,"child":3,"index":1}
      ]}
      ''');

      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: backend.widget(node: 1))),
      );
      final firstRevision = backend.debugRevision(2);
      final secondRevision = backend.debugRevision(3);
      final retained = tester.renderObject(
        find.byKey(LUIFlutterBackend.nodeKey(2)),
      );
      expect(find.text('ZN'), findsOneWidget);
      expect(find.text('CT'), findsOneWidget);

      backend.registerImage(id: 7, image: image);
      await tester.pump();
      expect(find.text('ZN'), findsNothing);
      expect(find.text('CT'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(LUIFlutterBackend.nodeKey(2)),
          matching: find.byType(CustomPaint),
        ),
        findsOneWidget,
      );
      expect(backend.debugRevision(2), firstRevision + 1);
      expect(backend.debugRevision(3), secondRevision);
      expect(
        tester.renderObject(find.byKey(LUIFlutterBackend.nodeKey(2))),
        same(retained),
      );

      backend.unregisterImage(7);
      await tester.pump();
      expect(find.text('ZN'), findsOneWidget);
      expect(backend.debugRevision(2), firstRevision + 2);
      expect(backend.debugRevision(3), secondRevision);

      backend.unregisterImage(7);
      expect(backend.debugRevision(2), firstRevision + 2);
      expect(
        () => backend.registerImage(id: 0, image: image),
        throwsA(isA<LUIBackendException>()),
      );
      backend.dispose();
    },
  );

  test('rejects partial and invalid Avatar source crops atomically', () {
    final partial = LUIFlutterBackend();
    expect(
      () => partial.applyJson('''
      {"generation":1,"ops":[
        {"op":"create-node","id":1,"kind":"avatar"},
        {"op":"set-prop","id":1,"property":"text","value":"ZN"},
        {"op":"set-prop","id":1,"property":"image","value":7},
        {"op":"set-prop","id":1,"property":"source-x","value":0.0}
      ]}
      '''),
      throwsA(
        isA<LUIBackendException>().having(
          (error) => error.message,
          'message',
          contains('avatar source crop requires all four coordinates'),
        ),
      ),
    );
    expect(partial.generation, 0);

    final invalid = LUIFlutterBackend();
    expect(
      () => invalid.applyJson('''
      {"generation":1,"ops":[
        {"op":"create-node","id":1,"kind":"avatar"},
        {"op":"set-prop","id":1,"property":"text","value":"ZN"},
        {"op":"set-prop","id":1,"property":"image","value":7},
        {"op":"set-prop","id":1,"property":"source-x","value":0.0},
        {"op":"set-prop","id":1,"property":"source-y","value":0.0},
        {"op":"set-prop","id":1,"property":"source-width","value":-1.0},
        {"op":"set-prop","id":1,"property":"source-height","value":24.0}
      ]}
      '''),
      throwsA(
        isA<LUIBackendException>().having(
          (error) => error.message,
          'message',
          contains('avatar source crop dimensions must be positive'),
        ),
      ),
    );
    expect(invalid.generation, 0);

    final expanded = LUIFlutterBackend();
    expect(
      () => expanded.applyJson('''
      {"generation":1,"ops":[
        {"op":"create-node","id":1,"kind":"avatar"},
        {"op":"set-prop","id":1,"property":"text","value":"ZN"},
        {"op":"set-prop","id":1,"property":"width","value":40}
      ]}
      '''),
      throwsA(isA<LUIBackendException>()),
    );
    expect(expanded.generation, 0);
  });

  testWidgets('maps semantic content primitives to native Flutter widgets', (
    tester,
  ) async {
    final backend = LUIFlutterBackend()
      ..applyJson('''
      {"generation":1,"ops":[
        {"op":"create-node","id":1,"kind":"box"},
        {"op":"create-node","id":2,"kind":"heading"},
        {"op":"create-node","id":3,"kind":"paragraph"},
        {"op":"set-prop","id":2,"property":"heading-level","value":3},
        {"op":"set-prop","id":2,"property":"text","value":"Account"},
        {"op":"set-prop","id":3,"property":"text","value":"Manage your profile."},
        {"op":"insert-child","parent":1,"child":2,"index":0},
        {"op":"insert-child","parent":1,"child":3,"index":1}
      ]}
      ''');

    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: backend.widget(node: 1))),
    );

    final box = tester.widget<Column>(find.byType(Column));
    final headingSemantics = tester.widget<Semantics>(
      find.byWidgetPredicate(
        (widget) => widget is Semantics && widget.properties.header == true,
      ),
    );
    expect(box.crossAxisAlignment, CrossAxisAlignment.stretch);
    expect(headingSemantics.properties.header, isTrue);
    expect(find.text('Account'), findsOneWidget);
    expect(find.text('Manage your profile.'), findsOneWidget);
  });

  testWidgets('applies reusable Surface styles without replacing widgets', (
    tester,
  ) async {
    final backend = LUIFlutterBackend()
      ..applyJson('''
      {"generation":1,"ops":[
        {"op":"create-node","id":1,"kind":"row"},
        {"op":"create-node","id":2,"kind":"text"},
        {"op":"set-prop","id":1,"property":"padding-horizontal","value":10},
        {"op":"set-prop","id":1,"property":"padding-vertical","value":2},
        {"op":"set-prop","id":1,"property":"background","value":"success"},
        {"op":"set-prop","id":1,"property":"border-color","value":"success-foreground"},
        {"op":"set-prop","id":1,"property":"border-width","value":1},
        {"op":"set-prop","id":1,"property":"corner-radius","value":6},
        {"op":"set-prop","id":2,"property":"text","value":"Styled"},
        {"op":"set-prop","id":2,"property":"foreground","value":"success-foreground"},
        {"op":"insert-child","parent":1,"child":2,"index":0}
      ]}
      ''');

    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: backend.widget(node: 1))),
    );

    final rootFinder = find.byKey(LUIFlutterBackend.nodeKey(1));
    final surfaceFinder = find.descendant(
      of: rootFinder,
      matching: find.byType(Container),
    );
    final surface = tester.widget<Container>(surfaceFinder.first);
    final originalRow = tester.renderObject(
      find.byKey(LUIFlutterBackend.nodeKey(1)),
    );
    final originalText = tester.renderObject(
      find.byKey(LUIFlutterBackend.nodeKey(2)),
    );
    final decoration = surface.decoration! as BoxDecoration;
    expect(surface.padding, const EdgeInsets.fromLTRB(10, 2, 10, 2));
    expect(decoration.border, isA<Border>());
    expect(decoration.borderRadius, BorderRadius.circular(6));
    expect(tester.widget<Text>(find.text('Styled')).style?.color, isNotNull);

    backend.applyJson('''
    {"generation":2,"ops":[
      {"op":"set-prop","id":1,"property":"corner-radius","value":999},
      {"op":"set-prop","id":1,"property":"background","value":"error"}
    ]}
    ''');
    await tester.pump();

    expect(
      tester.renderObject(find.byKey(LUIFlutterBackend.nodeKey(1))),
      same(originalRow),
    );
    expect(
      tester.renderObject(find.byKey(LUIFlutterBackend.nodeKey(2))),
      same(originalText),
    );
  });

  testWidgets('maps typed Surface size constraints to native layout widgets', (
    tester,
  ) async {
    final backend = LUIFlutterBackend()
      ..applyJson('''
      {"generation":1,"ops":[
        {"op":"create-node","id":1,"kind":"box"},
        {"op":"set-prop","id":1,"property":"width","value":120},
        {"op":"set-prop","id":1,"property":"height","value":24},
        {"op":"set-prop","id":1,"property":"min-width","value":80},
        {"op":"set-prop","id":1,"property":"max-width","value":160},
        {"op":"set-prop","id":1,"property":"min-height","value":16},
        {"op":"set-prop","id":1,"property":"max-height","value":32}
      ]}
      ''');

    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: backend.widget(node: 1))),
    );

    final root = find.byKey(LUIFlutterBackend.nodeKey(1));
    final sized = tester.widget<SizedBox>(
      find.descendant(of: root, matching: find.byType(SizedBox)).first,
    );
    final constrained = tester.widget<ConstrainedBox>(
      find.descendant(of: root, matching: find.byType(ConstrainedBox)).first,
    );
    expect(sized.width, 120);
    expect(sized.height, 24);
    expect(
      constrained.constraints,
      const BoxConstraints(
        minWidth: 80,
        maxWidth: 160,
        minHeight: 16,
        maxHeight: 32,
      ),
    );

    final revision = backend.debugRevision(1);
    expect(
      () => backend.applyJson('''
      {"generation":2,"ops":[
        {"op":"set-prop","id":1,"property":"min-width","value":170},
        {"op":"set-prop","id":1,"property":"max-width","value":160}
      ]}
      '''),
      throwsA(isA<LUIBackendException>()),
    );
    expect(backend.generation, 1);
    expect(backend.debugRevision(1), revision);
  });

  testWidgets('maps the Vercel Native layout vocabulary to Flutter widgets', (
    tester,
  ) async {
    final backend = LUIFlutterBackend()
      ..applyJson('''
      {"generation":1,"ops":[
        {"op":"create-node","id":1,"kind":"row"},
        {"op":"create-node","id":2,"kind":"box"},
        {"op":"create-node","id":3,"kind":"box"},
        {"op":"create-node","id":4,"kind":"grid"},
        {"op":"create-node","id":5,"kind":"box"},
        {"op":"create-node","id":6,"kind":"box"},
        {"op":"set-prop","id":1,"property":"width","value":300},
        {"op":"set-prop","id":1,"property":"height","value":100},
        {"op":"set-prop","id":1,"property":"main","value":"space_between"},
        {"op":"set-prop","id":1,"property":"cross","value":"end"},
        {"op":"set-prop","id":2,"property":"grow","value":1.0},
        {"op":"set-prop","id":2,"property":"height","value":20},
        {"op":"set-prop","id":3,"property":"width","value":50},
        {"op":"set-prop","id":3,"property":"height","value":20},
        {"op":"set-prop","id":4,"property":"width","value":300},
        {"op":"set-prop","id":4,"property":"columns","value":2},
        {"op":"set-prop","id":4,"property":"gap","value":6},
        {"op":"set-prop","id":5,"property":"height","value":20},
        {"op":"set-prop","id":6,"property":"height","value":20},
        {"op":"insert-child","parent":1,"child":2,"index":0},
        {"op":"insert-child","parent":1,"child":3,"index":1},
        {"op":"insert-child","parent":4,"child":5,"index":0},
        {"op":"insert-child","parent":4,"child":6,"index":1}
      ]}
      ''');

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: backend.widget(node: 1),
          ),
        ),
      ),
    );

    final row = tester.widget<Row>(find.byType(Row).first);
    expect(row.mainAxisAlignment, MainAxisAlignment.spaceBetween);
    expect(row.crossAxisAlignment, CrossAxisAlignment.end);
    expect(tester.getSize(find.byKey(LUIFlutterBackend.nodeKey(2))).width, 250);
    expect(tester.getTopLeft(find.byKey(LUIFlutterBackend.nodeKey(2))).dy, 80);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: backend.widget(node: 4),
          ),
        ),
      ),
    );
    expect(tester.getSize(find.byKey(LUIFlutterBackend.nodeKey(5))).width, 147);
    expect(tester.getTopLeft(find.byKey(LUIFlutterBackend.nodeKey(6))).dx, 153);

    expect(
      () => backend.applyJson('''
      {"generation":2,"ops":[
        {"op":"set-prop","id":1,"property":"main","value":"between"}
      ]}
      '''),
      throwsA(isA<LUIBackendException>()),
    );
    expect(backend.generation, 1);
  });

  testWidgets('maps Vercel Native overlay surfaces to native Flutter widgets', (
    tester,
  ) async {
    final backend = LUIFlutterBackend()
      ..applyJson('''
      {"generation":1,"ops":[
        {"op":"create-node","id":1,"kind":"stack"},
        {"op":"create-node","id":2,"kind":"panel"},
        {"op":"create-node","id":3,"kind":"card"},
        {"op":"create-node","id":4,"kind":"text"},
        {"op":"create-node","id":5,"kind":"text"},
        {"op":"set-prop","id":1,"property":"width","value":320},
        {"op":"set-prop","id":1,"property":"height","value":180},
        {"op":"insert-child","parent":1,"child":2,"index":0},
        {"op":"insert-child","parent":1,"child":3,"index":1},
        {"op":"insert-child","parent":2,"child":4,"index":0},
        {"op":"insert-child","parent":3,"child":5,"index":0}
      ]}
      ''');

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: backend.widget(node: 1),
          ),
        ),
      ),
    );

    expect(
      find.descendant(
        of: find.byKey(LUIFlutterBackend.nodeKey(1)),
        matching: find.byType(Stack),
      ),
      findsNWidgets(3),
    );
    final panelMaterial = tester.widget<Material>(
      find
          .descendant(
            of: find.byKey(LUIFlutterBackend.nodeKey(2)),
            matching: find.byType(Material),
          )
          .first,
    );
    final cardMaterial = tester.widget<Material>(
      find
          .descendant(
            of: find.byKey(LUIFlutterBackend.nodeKey(3)),
            matching: find.byType(Material),
          )
          .first,
    );
    expect(panelMaterial.elevation, 1);
    expect(cardMaterial.elevation, 0);
    expect(
      find
          .descendant(
            of: find.byKey(LUIFlutterBackend.nodeKey(3)),
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is Padding &&
                  widget.padding == const EdgeInsets.all(24),
            ),
          )
          .evaluate(),
      hasLength(1),
    );

    expect(
      () => backend.applyJson('''
      {"generation":2,"ops":[
        {"op":"set-prop","id":3,"property":"gap","value":8}
      ]}
      '''),
      throwsA(isA<LUIBackendException>()),
    );
    expect(backend.generation, 1);
  });

  testWidgets(
    'maps Dialog to a native modal route with model-owned dismissal',
    (tester) async {
      final events = <LUIEvent>[];
      final backend = LUIFlutterBackend(onEvent: events.add)
        ..applyJson('''
      {"generation":1,"ops":[
        {"op":"create-node","id":1,"kind":"column"},
        {"op":"create-node","id":2,"kind":"dialog"},
        {"op":"create-node","id":3,"kind":"input"},
        {"op":"set-prop","id":2,"property":"text","value":"Rename note"},
        {"op":"set-prop","id":2,"property":"width","value":380},
        {"op":"set-prop","id":2,"property":"height","value":240},
        {"op":"set-prop","id":2,"property":"padding","value":24},
        {"op":"insert-child","parent":1,"child":2,"index":0},
        {"op":"insert-child","parent":2,"child":3,"index":0}
      ]}
      ''');

      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: backend.widget(node: 1))),
      );
      await tester.pumpAndSettle();

      expect(find.byType(Dialog), findsOneWidget);
      expect(find.text('Rename note'), findsOneWidget);
      expect(find.byKey(LUIFlutterBackend.nodeKey(3)), findsOneWidget);
      expect(
        tester
            .getSize(find.byKey(const ValueKey('lui-dialog-surface-2')))
            .width,
        380,
      );
      final inputRenderObject = tester.renderObject(
        find.byKey(LUIFlutterBackend.nodeKey(3)),
      );

      backend.applyJson('''
      {"generation":2,"ops":[
        {"op":"set-prop","id":2,"property":"text","value":"Renamed note"},
        {"op":"set-prop","id":2,"property":"width","value":400}
      ]}
      ''');
      await tester.pump();
      expect(find.text('Renamed note'), findsOneWidget);
      expect(
        tester
            .getSize(find.byKey(const ValueKey('lui-dialog-surface-2')))
            .width,
        400,
      );
      expect(
        tester.renderObject(find.byKey(LUIFlutterBackend.nodeKey(3))),
        same(inputRenderObject),
      );

      await tester.tapAt(const Offset(4, 4));
      await tester.pumpAndSettle();
      expect(events, const [LUIEvent.dismiss(node: 2)]);
      expect(find.byType(Dialog), findsNothing);

      expect(
        () => backend.performDismiss(1),
        throwsA(isA<LUIBackendException>()),
      );
    },
  );

  testWidgets('maps Drawer to a retained Material modal bottom sheet', (
    tester,
  ) async {
    final events = <LUIEvent>[];
    final backend = LUIFlutterBackend(onEvent: events.add)
      ..applyJson('''
      {"generation":1,"ops":[
        {"op":"create-node","id":1,"kind":"column"},
        {"op":"create-node","id":2,"kind":"drawer"},
        {"op":"create-node","id":3,"kind":"input"},
        {"op":"set-prop","id":2,"property":"text","value":"Filters"},
        {"op":"set-prop","id":2,"property":"height","value":260},
        {"op":"set-prop","id":2,"property":"padding","value":24},
        {"op":"insert-child","parent":1,"child":2,"index":0},
        {"op":"insert-child","parent":2,"child":3,"index":0}
      ]}
      ''');

    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: backend.widget(node: 1))),
    );
    await tester.pumpAndSettle();

    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.text('Filters'), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const ValueKey('lui-drawer-surface-2'))).height,
      260,
    );
    final inputRenderObject = tester.renderObject(
      find.byKey(LUIFlutterBackend.nodeKey(3)),
    );

    backend.applyJson('''
      {"generation":2,"ops":[
        {"op":"set-prop","id":2,"property":"text","value":"More filters"},
        {"op":"set-prop","id":2,"property":"height","value":300}
      ]}
      ''');
    await tester.pump();
    expect(find.text('More filters'), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const ValueKey('lui-drawer-surface-2'))).height,
      300,
    );
    expect(
      tester.renderObject(find.byKey(LUIFlutterBackend.nodeKey(3))),
      same(inputRenderObject),
    );

    backend.applyJson('''
      {"generation":3,"ops":[
        {"op":"remove-child","parent":1,"child":2},
        {"op":"remove-child","parent":2,"child":3},
        {"op":"drop-node","id":3},
        {"op":"drop-node","id":2}
      ]}
      ''');
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNothing);
    expect(events, isEmpty);
  });

  testWidgets('maps Sheet to a retained trailing Material Drawer route', (
    tester,
  ) async {
    final events = <LUIEvent>[];
    final backend = LUIFlutterBackend(onEvent: events.add)
      ..applyJson('''
      {"generation":1,"ops":[
        {"op":"create-node","id":1,"kind":"column"},
        {"op":"create-node","id":2,"kind":"sheet"},
        {"op":"create-node","id":3,"kind":"input"},
        {"op":"set-prop","id":2,"property":"text","value":"Share"},
        {"op":"set-prop","id":2,"property":"width","value":320},
        {"op":"set-prop","id":2,"property":"padding","value":24},
        {"op":"insert-child","parent":1,"child":2,"index":0},
        {"op":"insert-child","parent":2,"child":3,"index":0}
      ]}
      ''');

    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: backend.widget(node: 1))),
    );
    await tester.pumpAndSettle();

    expect(find.byType(Drawer), findsOneWidget);
    expect(find.text('Share'), findsOneWidget);
    final surface = find.byKey(const ValueKey('lui-sheet-surface-2'));
    expect(tester.getSize(surface).width, 320);
    expect(
      tester.getTopRight(surface).dx,
      tester.getSize(find.byType(Scaffold)).width,
    );
    final inputRenderObject = tester.renderObject(
      find.byKey(LUIFlutterBackend.nodeKey(3)),
    );

    backend.applyJson('''
      {"generation":2,"ops":[
        {"op":"set-prop","id":2,"property":"text","value":"Share link"},
        {"op":"set-prop","id":2,"property":"width","value":360}
      ]}
      ''');
    await tester.pump();
    expect(find.text('Share link'), findsOneWidget);
    expect(tester.getSize(surface).width, 360);
    expect(
      tester.renderObject(find.byKey(LUIFlutterBackend.nodeKey(3))),
      same(inputRenderObject),
    );

    await tester.tapAt(const Offset(4, 4));
    await tester.pumpAndSettle();
    expect(events, const [LUIEvent.dismiss(node: 2)]);
    expect(find.byType(Drawer), findsNothing);
  });

  testWidgets('maps List flow and multi-child Scroll to Flutter widgets', (
    tester,
  ) async {
    final backend = LUIFlutterBackend()
      ..applyJson('''
      {"generation":1,"ops":[
        {"op":"create-node","id":1,"kind":"row"},
        {"op":"create-node","id":2,"kind":"list"},
        {"op":"create-node","id":3,"kind":"scroll"},
        {"op":"create-node","id":4,"kind":"text"},
        {"op":"create-node","id":5,"kind":"text"},
        {"op":"create-node","id":6,"kind":"text"},
        {"op":"set-prop","id":1,"property":"width","value":400},
        {"op":"set-prop","id":1,"property":"height","value":200},
        {"op":"set-prop","id":2,"property":"width","value":180},
        {"op":"set-prop","id":2,"property":"height","value":100},
        {"op":"set-prop","id":2,"property":"gap","value":8},
        {"op":"set-prop","id":2,"property":"main","value":"end"},
        {"op":"set-prop","id":2,"property":"cross","value":"stretch"},
        {"op":"set-prop","id":3,"property":"width","value":180},
        {"op":"set-prop","id":3,"property":"height","value":100},
        {"op":"insert-child","parent":1,"child":2,"index":0},
        {"op":"insert-child","parent":1,"child":3,"index":1},
        {"op":"insert-child","parent":2,"child":4,"index":0},
        {"op":"insert-child","parent":3,"child":5,"index":0},
        {"op":"insert-child","parent":3,"child":6,"index":1}
      ]}
      ''');

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: backend.widget(node: 1),
          ),
        ),
      ),
    );

    final list = tester.widget<Column>(
      find
          .descendant(
            of: find.byKey(LUIFlutterBackend.nodeKey(2)),
            matching: find.byType(Column),
          )
          .first,
    );
    expect(list.spacing, 8);
    expect(list.mainAxisAlignment, MainAxisAlignment.end);
    expect(list.crossAxisAlignment, CrossAxisAlignment.stretch);

    final scroll = tester.widget<SingleChildScrollView>(
      find
          .descendant(
            of: find.byKey(LUIFlutterBackend.nodeKey(3)),
            matching: find.byType(SingleChildScrollView),
          )
          .first,
    );
    expect(scroll.child, isA<Stack>());
    expect((scroll.child! as Stack).children, hasLength(2));
  });

  testWidgets('maps a progress fraction to one retained native indicator', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final backend = LUIFlutterBackend()
      ..applyJson('''
      {"generation":1,"ops":[
        {"op":"create-node","id":2,"kind":"progress"},
        {"op":"set-prop","id":2,"property":"value","value":0.3}
      ]}
      ''');

    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: backend.widget(node: 2))),
    );

    final originalProgress = tester.renderObject(
      find.byKey(LUIFlutterBackend.nodeKey(2)),
    );
    expect(
      tester
          .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
          .value,
      0.3,
    );
    expect(
      tester.getSemantics(find.byType(LinearProgressIndicator)),
      matchesSemantics(value: '30%'),
    );

    backend.applyJson('''
    {"generation":2,"ops":[
      {"op":"set-prop","id":2,"property":"value","value":1.2}
    ]}
    ''');
    await tester.pump();
    expect(
      tester.renderObject(find.byKey(LUIFlutterBackend.nodeKey(2))),
      same(originalProgress),
    );
    expect(
      tester
          .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
          .value,
      1,
    );
    semantics.dispose();
  });

  testWidgets('maps Spinner size rungs to CircularProgressIndicator', (
    tester,
  ) async {
    final backend = LUIFlutterBackend()
      ..applyJson('''
      {"generation":1,"ops":[
        {"op":"create-node","id":1,"kind":"spinner"},
        {"op":"set-prop","id":1,"property":"size","value":"sm"},
        {"op":"set-prop","id":1,"property":"foreground","value":"red"}
      ]}
      ''');

    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: backend.widget(node: 1))),
    );

    final spinner = find.byType(CircularProgressIndicator);
    final originalNode = tester.renderObject(
      find.byKey(LUIFlutterBackend.nodeKey(1)),
    );
    expect(spinner, findsOneWidget);
    expect(tester.getSize(spinner), const Size.square(16));
    expect(tester.widget<CircularProgressIndicator>(spinner).color, Colors.red);

    backend.applyJson('''
    {"generation":2,"ops":[
      {"op":"set-prop","id":1,"property":"size","value":"lg"}
    ]}
    ''');
    await tester.pump();
    expect(
      tester.renderObject(find.byKey(LUIFlutterBackend.nodeKey(1))),
      same(originalNode),
    );
    expect(tester.getSize(spinner), const Size.square(24));

    backend.applyJson('''
    {"generation":3,"ops":[
      {"op":"set-prop","id":1,"property":"width","value":32},
      {"op":"set-prop","id":1,"property":"height","value":28}
    ]}
    ''');
    await tester.pump();
    expect(tester.getSize(spinner), const Size(32, 28));
  });

  test('rejects unsupported Spinner size names atomically', () {
    final backend = LUIFlutterBackend();

    expect(
      () => backend.applyJson('''
      {"generation":1,"ops":[
        {"op":"create-node","id":1,"kind":"spinner"},
        {"op":"set-prop","id":1,"property":"size","value":"heading"}
      ]}
      '''),
      throwsA(isA<LUIBackendException>()),
    );
    expect(backend.containsNode(1), isFalse);
    expect(backend.generation, 0);
  });

  testWidgets('maps Icon names to Material icons incrementally', (
    tester,
  ) async {
    final backend = LUIFlutterBackend()
      ..applyJson('''
      {"generation":1,"ops":[
        {"op":"create-node","id":1,"kind":"icon"},
        {"op":"set-prop","id":1,"property":"name","value":"search"},
        {"op":"set-prop","id":1,"property":"size","value":"sm"},
        {"op":"set-prop","id":1,"property":"foreground","value":"red"}
      ]}
      ''');

    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: backend.widget(node: 1))),
    );
    final originalNode = tester.renderObject(
      find.byKey(LUIFlutterBackend.nodeKey(1)),
    );
    expect(tester.widget<Icon>(find.byType(Icon)).icon, Icons.search);
    expect(tester.widget<Icon>(find.byType(Icon)).size, 16);
    expect(tester.widget<Icon>(find.byType(Icon)).color, Colors.red);

    backend.applyJson('''
    {"generation":2,"ops":[
      {"op":"set-prop","id":1,"property":"name","value":"trash"}
    ]}
    ''');
    await tester.pump();
    expect(
      tester.renderObject(find.byKey(LUIFlutterBackend.nodeKey(1))),
      same(originalNode),
    );
    expect(tester.widget<Icon>(find.byType(Icon)).icon, Icons.delete_outline);
  });

  test('rejects unsupported Icon names atomically', () {
    final backend = LUIFlutterBackend();
    expect(
      () => backend.applyJson('''
      {"generation":1,"ops":[
        {"op":"create-node","id":1,"kind":"icon"},
        {"op":"set-prop","id":1,"property":"name","value":"unknown"}
      ]}
      '''),
      throwsA(isA<LUIBackendException>()),
    );
    expect(backend.containsNode(1), isFalse);
    expect(backend.generation, 0);
  });

  testWidgets('resolves application icons through the Flutter registry', (
    tester,
  ) async {
    final backend =
        LUIFlutterBackend(appIcons: const {'wave-pulse': Icons.waves})
          ..applyJson('''
      {"generation":1,"ops":[
        {"op":"create-node","id":1,"kind":"icon"},
        {"op":"set-prop","id":1,"property":"name","value":"app:wave-pulse"}
      ]}
      ''');

    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: backend.widget(node: 1))),
    );
    expect(tester.widget<Icon>(find.byType(Icon)).icon, Icons.waves);

    backend.applyJson('''
    {"generation":2,"ops":[
      {"op":"set-prop","id":1,"property":"name","value":"app:missing"}
    ]}
    ''');
    await tester.pump();
    expect(tester.widget<Icon>(find.byType(Icon)).icon, Icons.question_mark);
  });

  testWidgets('maps Separator orientation to retained native dividers', (
    tester,
  ) async {
    final backend = LUIFlutterBackend()
      ..applyJson('''
      {"generation":1,"ops":[
        {"op":"create-node","id":1,"kind":"divider"},
        {"op":"set-prop","id":1,"property":"orientation","value":"horizontal"}
      ]}
      ''');

    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: backend.widget(node: 1))),
    );

    final original = tester.renderObject(
      find.byKey(LUIFlutterBackend.nodeKey(1)),
    );
    expect(find.byType(Divider), findsOneWidget);
    expect(find.byType(VerticalDivider), findsNothing);

    backend.applyJson('''
    {"generation":2,"ops":[
      {"op":"set-prop","id":1,"property":"orientation","value":"vertical"}
    ]}
    ''');
    await tester.pump();

    expect(
      tester.renderObject(find.byKey(LUIFlutterBackend.nodeKey(1))),
      same(original),
    );
    expect(find.byType(Divider), findsNothing);
    expect(find.byType(VerticalDivider), findsOneWidget);

    expect(
      () => backend.applyJson('''
      {"generation":3,"ops":[
        {"op":"set-prop","id":1,"property":"orientation","value":"diagonal"}
      ]}
      '''),
      throwsA(isA<LUIBackendException>()),
    );
    expect(backend.generation, 2);
    expect(backend.debugRevision(1), 1);
  });

  testWidgets('textarea auto-resizes without losing focus or retained state', (
    tester,
  ) async {
    final backend = LUIFlutterBackend()
      ..applyJson('''
      {"generation":1,"ops":[
        {"op":"create-node","id":1,"kind":"textarea"},
        {"op":"set-prop","id":1,"property":"text","value":"One line"},
        {"op":"set-prop","id":1,"property":"placeholder","value":"Notes"}
      ]}
      ''');

    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: backend.widget(node: 1))),
    );

    final field = tester.widget<TextField>(find.byType(TextField));
    final editable = tester.state<EditableTextState>(find.byType(EditableText));
    final oneLineHeight = tester.getSize(find.byType(TextField)).height;
    await tester.tap(find.byType(TextField));
    await tester.pump();

    expect(field.minLines, 1);
    expect(field.maxLines, isNull);
    expect(field.keyboardType, TextInputType.multiline);
    expect(field.decoration?.hintText, 'Notes');
    expect(editable.widget.focusNode.hasFocus, isTrue);

    backend.applyJson(r'''
    {"generation":2,"ops":[
      {"op":"set-prop","id":1,"property":"text","value":"One\nTwo\nThree"}
    ]}
    ''');
    await tester.pump();

    expect(
      tester.getSize(find.byType(TextField)).height,
      greaterThan(oneLineHeight),
    );
    expect(
      tester.state<EditableTextState>(find.byType(EditableText)),
      same(editable),
    );
    expect(editable.widget.focusNode.hasFocus, isTrue);
  });

  testWidgets('maps direct text-bearing checkbox and switch natively', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final events = <LUIEvent>[];
    final backend = LUIFlutterBackend(onEvent: events.add)
      ..applyJson('''
      {"generation":1,"ops":[
        {"op":"create-node","id":1,"kind":"box"},
        {"op":"create-node","id":2,"kind":"checkbox"},
        {"op":"create-node","id":3,"kind":"switch"},
        {"op":"set-prop","id":2,"property":"accessibility-label","value":"Select all"},
        {"op":"set-prop","id":2,"property":"text","value":"Select everything"},
        {"op":"set-prop","id":2,"property":"checked","value":true},
        {"op":"set-prop","id":3,"property":"accessibility-label","value":"Notifications"},
        {"op":"set-prop","id":3,"property":"text","value":"Email notifications"},
        {"op":"set-prop","id":3,"property":"checked","value":false},
        {"op":"insert-child","parent":1,"child":2,"index":0},
        {"op":"insert-child","parent":1,"child":3,"index":1}
      ]}
      ''');

    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: backend.widget(node: 1))),
    );

    final checkbox = tester.widget<Checkbox>(find.byType(Checkbox));
    final toggle = tester.widget<Switch>(find.byType(Switch));
    expect(checkbox.tristate, isFalse);
    expect(checkbox.value, isTrue);
    expect(toggle.value, isFalse);
    expect(find.text('Select everything'), findsOneWidget);
    expect(find.text('Email notifications'), findsOneWidget);
    expect(
      tester.getSemantics(find.bySemanticsLabel('Select all')),
      matchesSemantics(
        label: 'Select all',
        hasCheckedState: true,
        isChecked: true,
        hasEnabledState: true,
        isEnabled: true,
        hasTapAction: true,
      ),
    );
    expect(
      tester.getSemantics(find.bySemanticsLabel('Notifications')),
      matchesSemantics(
        label: 'Notifications',
        hasToggledState: true,
        hasEnabledState: true,
        isEnabled: true,
        hasTapAction: true,
      ),
    );
    await tester.tap(find.text('Select everything'));
    expect(events, const [LUIEvent.toggleChanged(node: 2, checked: false)]);
    events.clear();

    final originalCheckbox = tester.renderObject(
      find.byKey(LUIFlutterBackend.nodeKey(2)),
    );
    final originalSwitch = tester.renderObject(
      find.byKey(LUIFlutterBackend.nodeKey(3)),
    );
    await tester.tap(find.byType(Checkbox));
    await tester.tap(find.byType(Switch));
    expect(events, const [
      LUIEvent.toggleChanged(node: 2, checked: false),
      LUIEvent.toggleChanged(node: 3, checked: true),
    ]);

    backend.applyJson('''
    {"generation":2,"ops":[
      {"op":"set-prop","id":2,"property":"checked","value":false},
      {"op":"set-prop","id":2,"property":"text","value":"All items"},
      {"op":"set-prop","id":3,"property":"checked","value":true}
    ]}
    ''');
    await tester.pump();
    expect(
      tester.renderObject(find.byKey(LUIFlutterBackend.nodeKey(2))),
      same(originalCheckbox),
    );
    expect(
      tester.renderObject(find.byKey(LUIFlutterBackend.nodeKey(3))),
      same(originalSwitch),
    );
    expect(find.text('All items'), findsOneWidget);
    expect(
      () => backend.applyJson('''
      {"generation":3,"ops":[
        {"op":"set-prop","id":2,"property":"indeterminate","value":true}
      ]}
      '''),
      throwsA(isA<LUIBackendException>()),
    );
    expect(backend.generation, 2);
    semantics.dispose();
  });

  testWidgets('maps the daily value-control batch to native Flutter widgets', (
    tester,
  ) async {
    final events = <LUIEvent>[];
    final backend = LUIFlutterBackend(onEvent: events.add)
      ..applyJson('''
      {"generation":1,"ops":[
        {"op":"create-node","id":1,"kind":"column"},
        {"op":"create-node","id":2,"kind":"toggle"},
        {"op":"create-node","id":3,"kind":"radio-group"},
        {"op":"create-node","id":4,"kind":"radio"},
        {"op":"create-node","id":5,"kind":"slider"},
        {"op":"set-prop","id":2,"property":"text","value":"Bold"},
        {"op":"set-prop","id":2,"property":"checked","value":false},
        {"op":"set-prop","id":3,"property":"accessibility-label","value":"Density"},
        {"op":"set-prop","id":4,"property":"text","value":"Comfortable"},
        {"op":"set-prop","id":4,"property":"checked","value":false},
        {"op":"set-prop","id":4,"property":"change-enabled","value":true},
        {"op":"set-prop","id":5,"property":"value","value":0.25},
        {"op":"set-prop","id":5,"property":"accessibility-label","value":"Volume"},
        {"op":"insert-child","parent":1,"child":2,"index":0},
        {"op":"insert-child","parent":1,"child":3,"index":1},
        {"op":"insert-child","parent":3,"child":4,"index":0},
        {"op":"insert-child","parent":1,"child":5,"index":2}
      ]}
      ''');

    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: backend.widget(node: 1))),
    );

    expect(find.byType(FilterChip), findsOneWidget);
    expect(find.byType(RadioGroup<int>), findsOneWidget);
    expect(find.byType(Radio<int>), findsOneWidget);
    expect(find.byType(Slider), findsOneWidget);
    final originalToggle = tester.renderObject(
      find.byKey(LUIFlutterBackend.nodeKey(2)),
    );
    final originalRadio = tester.renderObject(
      find.byKey(LUIFlutterBackend.nodeKey(4)),
    );
    final originalSlider = tester.renderObject(
      find.byKey(LUIFlutterBackend.nodeKey(5)),
    );

    await tester.tap(find.byType(FilterChip));
    await tester.tap(find.text('Comfortable'));
    await tester.drag(find.byType(Slider), const Offset(100, 0));
    await tester.pump();

    expect(events[0], const LUIEvent.toggleChanged(node: 2, checked: true));
    expect(events[1], const LUIEvent.change(node: 4));
    final sliderEvent = events.last as LUIValueChangedEvent;
    expect(sliderEvent.node, 5);
    expect(sliderEvent.value, greaterThan(0.25));

    backend.applyJson('''
    {"generation":2,"ops":[
      {"op":"set-prop","id":2,"property":"checked","value":true},
      {"op":"set-prop","id":4,"property":"checked","value":true},
      {"op":"set-prop","id":5,"property":"value","value":0.75}
    ]}
    ''');
    await tester.pump();
    expect(
      tester.renderObject(find.byKey(LUIFlutterBackend.nodeKey(2))),
      same(originalToggle),
    );
    expect(
      tester.renderObject(find.byKey(LUIFlutterBackend.nodeKey(4))),
      same(originalRadio),
    );
    expect(
      tester.renderObject(find.byKey(LUIFlutterBackend.nodeKey(5))),
      same(originalSlider),
    );
    expect(tester.widget<FilterChip>(find.byType(FilterChip)).selected, isTrue);
    expect(
      tester.widget<RadioGroup<int>>(find.byType(RadioGroup<int>)).groupValue,
      4,
    );
    expect(tester.widget<Slider>(find.byType(Slider)).value, 0.75);
    final eventCount = events.length;
    await tester.tap(find.text('Comfortable'));
    await tester.pump();
    expect(events, hasLength(eventCount));

    final ungrouped = LUIFlutterBackend();
    expect(
      () => ungrouped.applyJson('''
      {"generation":1,"ops":[
        {"op":"create-node","id":1,"kind":"radio"},
        {"op":"set-prop","id":1,"property":"text","value":"Orphan"}
      ]}
      '''),
      throwsA(isA<LUIBackendException>()),
    );
  });
}

const _initialBatch = '''
{"generation":1,"ops":[
  {"op":"create-node","id":1,"kind":"row"},
  {"op":"create-node","id":2,"kind":"text"},
  {"op":"create-node","id":3,"kind":"button"},
  {"op":"set-prop","id":1,"property":"gap","value":12},
  {"op":"set-prop","id":2,"property":"text","value":"Hello from LG"},
  {"op":"set-prop","id":3,"property":"text","value":"Continue"},
  {"op":"set-prop","id":3,"property":"enabled","value":true},
  {"op":"insert-child","parent":1,"child":2,"index":0},
  {"op":"insert-child","parent":1,"child":3,"index":1}
]}
''';
