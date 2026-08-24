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
