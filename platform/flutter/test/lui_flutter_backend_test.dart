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

  testWidgets('maps progress ranges to one retained LinearProgressIndicator', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final backend = LUIFlutterBackend()
      ..applyJson('''
      {"generation":1,"ops":[
        {"op":"create-node","id":1,"kind":"label"},
        {"op":"create-node","id":2,"kind":"progress"},
        {"op":"set-prop","id":1,"property":"text","value":"Processing"},
        {"op":"set-prop","id":2,"property":"min-value","value":0},
        {"op":"set-prop","id":2,"property":"max-value","value":10},
        {"op":"set-prop","id":2,"property":"value","value":3},
        {"op":"set-prop","id":2,"property":"labelled-by","value":1}
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
      matchesSemantics(label: 'Processing', value: '30%'),
    );

    backend.applyJson('''
    {"generation":2,"ops":[
      {"op":"set-prop","id":2,"property":"value","value":12}
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

  test('rejects an empty progress range atomically', () {
    final backend = LUIFlutterBackend();

    expect(
      () => backend.applyJson('''
      {"generation":1,"ops":[
        {"op":"create-node","id":1,"kind":"progress"},
        {"op":"set-prop","id":1,"property":"min-value","value":10},
        {"op":"set-prop","id":1,"property":"max-value","value":10}
      ]}
      '''),
      throwsA(isA<LUIBackendException>()),
    );
    expect(backend.containsNode(1), isFalse);
    expect(backend.generation, 0);
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
