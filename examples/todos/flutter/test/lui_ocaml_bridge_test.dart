import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lui_flutter_backend/lui_flutter_backend.dart';
import 'package:lui_flutter_backend/lui_ocaml_bridge.dart';

const _libraryPath = String.fromEnvironment('LUI_NATIVE_LIBRARY');

void main() {
  testWidgets('LG Todos uses real Flutter widgets through OCaml FFI', (
    tester,
  ) async {
    expect(
      _libraryPath,
      isNotEmpty,
      reason: 'Pass --dart-define=LUI_NATIVE_LIBRARY=...',
    );
    late LUIOcamlBridge bridge;
    final backend = LUIFlutterBackend(
      onEvent: (event) => switch (event) {
        LUIPressEvent(:final node) => bridge.press(node),
        LUITextChangedEvent(:final node, :final text) => bridge.textChanged(
          node,
          text,
        ),
      },
    );
    bridge = LUIOcamlBridge.open(_libraryPath, onPatch: backend.applyJson);
    addTearDown(bridge.close);

    bridge.start();
    expect(backend.generation, 1);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 640,
            height: 480,
            child: backend.widget(node: bridge.rootNode),
          ),
        ),
      ),
    );
    final draftField = find.byWidgetPredicate(
      (widget) => widget is TextField && widget.maxLines == 1,
      description: 'single-line todo draft field',
    );
    final draftEditor = find.descendant(
      of: draftField,
      matching: find.byType(EditableText),
    );
    expect(find.byType(EditableText), findsNWidgets(2));
    expect(draftEditor, findsOneWidget);
    expect(find.byType(SingleChildScrollView), findsOneWidget);
    expect(find.textContaining('Write LG todos'), findsNothing);

    final inputBefore = tester.widget<EditableText>(draftEditor);
    await tester.enterText(draftField, 'Write LG todos');
    await tester.pump();
    expect(backend.generation, 2);
    final inputAfter = tester.widget<EditableText>(draftEditor);
    expect(inputAfter.focusNode, same(inputBefore.focusNode));
    expect(inputAfter.focusNode.hasFocus, isTrue);
    await tester.tap(find.widgetWithText(TextButton, 'Add'));
    await tester.pump();
    expect(backend.generation, 3);
    expect(
      tester.widget<TextField>(draftField).controller!.text,
      '',
    );
    final label = find.text('[ ] Write LG todos');
    expect(label, findsOneWidget);
    final retainedLabel = tester.renderObject(label);

    await tester.tap(find.widgetWithText(TextButton, 'Toggle'));
    await tester.pump();
    expect(backend.generation, 4);
    expect(
      tester.renderObject(find.text('[x] Write LG todos')),
      same(retainedLabel),
    );
  });
}
