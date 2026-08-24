import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lui_flutter_backend/lui_flutter_backend.dart';
import 'package:lui_flutter_backend/lui_ocaml_bridge.dart';

const _libraryPath = String.fromEnvironment('LUI_NATIVE_LIBRARY');

void main() {
  testWidgets('shared LG gallery runs through the native Flutter host', (
    tester,
  ) async {
    expect(
      _libraryPath,
      isNotEmpty,
      reason: 'Pass --dart-define=LUI_NATIVE_LIBRARY=...',
    );
    expect(
      File(_libraryPath).existsSync(),
      isTrue,
      reason: 'Build the component-gallery native bridge first.',
    );

    late LUIOcamlBridge bridge;
    final backend = LUIFlutterBackend(
      onEvent: (event) => switch (event) {
        LUIPressEvent(:final node) => bridge.press(node),
        LUIHoldEvent(:final node) => bridge.hold(node),
        LUITextChangedEvent(:final node, :final text) => bridge.textChanged(
          node,
          text,
        ),
        LUIToggleChangedEvent(:final node, :final checked) =>
          bridge.toggleChanged(node, checked),
        LUIChangeEvent(:final node) => bridge.radioChanged(node),
        LUIValueChangedEvent(:final node, :final value) => bridge.sliderChanged(
          node,
          value,
        ),
      },
    );
    bridge = LUIOcamlBridge.open(_libraryPath, onPatch: backend.applyJson);
    addTearDown(() {
      bridge.close();
      backend.dispose();
    });

    bridge.start();
    expect(backend.generation, 1);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 1200,
            height: 900,
            child: SingleChildScrollView(
              child: backend.widget(node: bridge.rootNode),
            ),
          ),
        ),
      ),
    );

    expect(find.text('ToggleButton'), findsOneWidget);
    expect(find.text('Progress fraction: 0.3'), findsOneWidget);
    final backendOwnedLabel = find.text('Backend-owned');
    final retainedLabel = tester.renderObject(backendOwnedLabel);
    final backendOwnedSemantics = find.byWidgetPredicate(
      (widget) =>
          widget is Semantics && widget.properties.label == 'Backend-owned',
      description: 'Backend-owned ToggleButton semantics',
    );

    final backendOwned = find.widgetWithText(TextButton, 'Backend-owned');
    await tester.ensureVisible(backendOwned);
    await tester.tap(backendOwned);
    await tester.pump();
    expect(
      tester.widget<Semantics>(backendOwnedSemantics).properties.selected,
      isTrue,
      reason: 'uncontrolled selection is retained by the Flutter backend',
    );

    final advance = find.widgetWithText(OutlinedButton, 'Advance progress');
    await tester.ensureVisible(advance);
    await tester.tap(advance);
    await tester.pump();
    expect(find.text('Progress fraction: 0.4'), findsOneWidget);
    expect(tester.renderObject(backendOwnedLabel), same(retainedLabel));
    expect(
      tester.widget<Semantics>(backendOwnedSemantics).properties.selected,
      isTrue,
      reason: 'an unrelated Signal patch preserves backend-owned state',
    );

    final controlled = find.widgetWithText(OutlinedButton, 'Controlled');
    await tester.ensureVisible(controlled);
    await tester.tap(controlled);
    await tester.pump();
    expect(
      tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
      isTrue,
    );
    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
      isTrue,
    );
  });
}
