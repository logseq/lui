import 'package:flutter/material.dart';
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

  test('rejects form relationships with the wrong semantic target', () {
    final backend = LUIFlutterBackend();

    expect(
      () => backend.applyJson('''
      {"generation":1,"ops":[
        {"op":"create-node","id":1,"kind":"paragraph"},
        {"op":"create-node","id":2,"kind":"text-input"},
        {"op":"set-prop","id":2,"property":"labelled-by","value":1}
      ]}
      '''),
      throwsA(isA<LUIBackendException>()),
    );
    expect(backend.containsNode(1), isFalse);
    expect(backend.generation, 0);
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

  test('dropping form content clears dependent relationships', () {
    final backend = LUIFlutterBackend();
    expect(
      () => backend.applyJson('''
      {"generation":1,"ops":[
        {"op":"create-node","id":1,"kind":"label"},
        {"op":"create-node","id":2,"kind":"text-input"},
        {"op":"set-prop","id":1,"property":"text","value":"Email"},
        {"op":"set-prop","id":2,"property":"labelled-by","value":1}
      ]}
      '''),
      returnsNormally,
    );
    if (backend.generation == 0) return;

    backend.applyJson('''
    {"generation":2,"ops":[
      {"op":"drop-node","id":1}
    ]}
    ''');

    expect(backend.containsNode(1), isFalse);
    expect(backend.debugRevision(2), 1);
  });

  testWidgets('maps semantic text-input properties to a native TextField', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final backend = LUIFlutterBackend()
      ..applyJson('''
      {"generation":1,"ops":[
        {"op":"create-node","id":1,"kind":"text-input"},
        {"op":"set-prop","id":1,"property":"placeholder","value":"Search"},
        {"op":"set-prop","id":1,"property":"read-only","value":true},
        {"op":"set-prop","id":1,"property":"accessibility-label","value":"Search todos"}
      ]}
      ''');

    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: backend.widget(node: 1))),
    );

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.decoration?.hintText, 'Search');
    expect(field.readOnly, isTrue);
    expect(
      tester.getSemantics(find.byType(TextField)),
      matchesSemantics(
        label: 'Search todos',
        isTextField: true,
        isReadOnly: true,
      ),
    );
    semantics.dispose();
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

  testWidgets('maps text-area sizing to one retained native TextField', (
    tester,
  ) async {
    final backend = LUIFlutterBackend()
      ..applyJson('''
      {"generation":1,"ops":[
        {"op":"create-node","id":1,"kind":"text-area"},
        {"op":"set-prop","id":1,"property":"text","value":"One line"},
        {"op":"set-prop","id":1,"property":"min-lines","value":2},
        {"op":"set-prop","id":1,"property":"max-lines","value":5},
        {"op":"set-prop","id":1,"property":"placeholder","value":"Notes"}
      ]}
      ''');

    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: backend.widget(node: 1))),
    );

    final field = tester.widget<TextField>(find.byType(TextField));
    final editable = tester.state<EditableTextState>(find.byType(EditableText));
    await tester.tap(find.byType(TextField));
    await tester.pump();

    expect(field.minLines, 2);
    expect(field.maxLines, 5);
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
      tester.state<EditableTextState>(find.byType(EditableText)),
      same(editable),
    );
    expect(editable.widget.focusNode.hasFocus, isTrue);
  });

  testWidgets('maps typed form relationships and invalid state', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final backend = LUIFlutterBackend()
      ..applyJson('''
      {"generation":1,"ops":[
        {"op":"create-node","id":1,"kind":"box"},
        {"op":"create-node","id":2,"kind":"label"},
        {"op":"create-node","id":3,"kind":"text-input"},
        {"op":"create-node","id":4,"kind":"paragraph"},
        {"op":"create-node","id":5,"kind":"paragraph"},
        {"op":"set-prop","id":2,"property":"text","value":"Email"},
        {"op":"set-prop","id":3,"property":"input-type","value":"email"},
        {"op":"set-prop","id":3,"property":"invalid","value":true},
        {"op":"set-prop","id":3,"property":"labelled-by","value":2},
        {"op":"set-prop","id":3,"property":"described-by","value":4},
        {"op":"set-prop","id":3,"property":"error-message-by","value":5},
        {"op":"set-prop","id":4,"property":"text","value":"Work address."},
        {"op":"set-prop","id":5,"property":"text","value":"Email is invalid."},
        {"op":"insert-child","parent":1,"child":2,"index":0},
        {"op":"insert-child","parent":1,"child":3,"index":1},
        {"op":"insert-child","parent":1,"child":4,"index":2},
        {"op":"insert-child","parent":1,"child":5,"index":3}
      ]}
      ''');

    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: backend.widget(node: 1))),
    );

    final field = tester.widget<TextField>(find.byType(TextField));
    final editable = tester.state<EditableTextState>(find.byType(EditableText));
    expect(field.keyboardType, TextInputType.emailAddress);
    expect(field.decoration?.errorText, isNull);
    expect(field.decoration?.enabledBorder, isA<OutlineInputBorder>());
    expect(
      tester.getSemantics(find.byType(TextField)),
      matchesSemantics(
        label: 'Email',
        hint: 'Work address. Email is invalid.',
        isTextField: true,
      ),
    );

    await tester.tap(find.byType(TextField));
    backend.applyJson('''
    {"generation":2,"ops":[
      {"op":"set-prop","id":4,"property":"text","value":"Primary work address."},
      {"op":"set-prop","id":3,"property":"invalid","value":false}
    ]}
    ''');
    await tester.pump();

    expect(
      tester.state<EditableTextState>(find.byType(EditableText)),
      same(editable),
    );
    expect(editable.widget.focusNode.hasFocus, isTrue);
    expect(
      tester.getSemantics(find.byType(TextField)),
      matchesSemantics(
        label: 'Email',
        hint: 'Primary work address.',
        isTextField: true,
      ),
    );
    semantics.dispose();
  });

  testWidgets('maps checkbox and switch to retained native controls', (
    tester,
  ) async {
    final events = <LUIEvent>[];
    final backend = LUIFlutterBackend(onEvent: events.add)
      ..applyJson('''
      {"generation":1,"ops":[
        {"op":"create-node","id":1,"kind":"box"},
        {"op":"create-node","id":2,"kind":"checkbox"},
        {"op":"create-node","id":3,"kind":"switch"},
        {"op":"set-prop","id":2,"property":"accessibility-label","value":"Select all"},
        {"op":"set-prop","id":2,"property":"checked","value":true},
        {"op":"set-prop","id":2,"property":"indeterminate","value":true},
        {"op":"set-prop","id":3,"property":"accessibility-label","value":"Notifications"},
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
    expect(checkbox.tristate, isTrue);
    expect(checkbox.value, isNull);
    expect(toggle.value, isFalse);

    final originalCheckbox = tester.renderObject(
      find.byKey(LUIFlutterBackend.nodeKey(2)),
    );
    final originalSwitch = tester.renderObject(
      find.byKey(LUIFlutterBackend.nodeKey(3)),
    );
    await tester.tap(find.byType(Checkbox));
    await tester.tap(find.byType(Switch));
    expect(events, const [
      LUIEvent.toggleChanged(node: 2, checked: true),
      LUIEvent.toggleChanged(node: 3, checked: true),
    ]);

    backend.applyJson('''
    {"generation":2,"ops":[
      {"op":"set-prop","id":2,"property":"indeterminate","value":false},
      {"op":"set-prop","id":2,"property":"checked","value":false},
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
