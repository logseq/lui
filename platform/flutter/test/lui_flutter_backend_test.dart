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
