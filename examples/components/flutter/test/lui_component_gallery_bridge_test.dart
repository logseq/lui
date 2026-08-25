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
        LUISubmitEvent(:final node) => bridge.submit(node),
        LUIDoublePressEvent(:final node) => bridge.doublePress(node),
        LUIDismissEvent(:final node) => bridge.dismiss(node),
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
    expect(find.byType(TextField), findsNWidgets(5));
    expect(find.text('TextField'), findsOneWidget);
    expect(find.text('Input'), findsOneWidget);
    expect(find.text('SearchField'), findsOneWidget);
    expect(find.text('Textarea'), findsOneWidget);
    expect(find.text('Controls are disabled.'), findsNothing);
    expect(find.text('ListItem'), findsOneWidget);
    expect(find.text('Tree'), findsOneWidget);
    expect(find.text('Split'), findsOneWidget);
    expect(find.text('Documents'), findsOneWidget);
    expect(find.text('Avatar'), findsOneWidget);
    expect(find.text('Image and MediaSurface'), findsOneWidget);
    expect(find.text('Stepper and Timeline'), findsOneWidget);
    expect(find.text('Review'), findsOneWidget);
    expect(find.text('Validated'), findsOneWidget);
    expect(find.text('ZN'), findsOneWidget);
    final listItems = find.byWidgetPredicate(
      (widget) => widget is ListTile && widget.shape is RoundedRectangleBorder,
      description: 'LUI ListItem rows',
    );
    expect(listItems, findsNWidgets(5));
    final toggleDisabled = find.widgetWithText(
      OutlinedButton,
      'Toggle disabled',
    );
    await tester.ensureVisible(toggleDisabled);
    await tester.tap(toggleDisabled);
    await tester.pump();
    expect(find.text('Controls are disabled.'), findsOneWidget);
    await tester.tap(toggleDisabled);
    await tester.pump();
    expect(find.text('Controls are disabled.'), findsNothing);
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

    final select = find.widgetWithText(OutlinedButton, 'Production');
    await tester.ensureVisible(select);
    final retainedSelect = tester.renderObject(select);
    await tester.tap(select);
    await tester.pump();
    await tester.pump();
    expect(find.byType(MenuItemButton), findsNWidgets(3));
    await tester.tap(find.widgetWithText(MenuItemButton, 'Staging'));
    await tester.pump();
    await tester.pump();
    expect(find.widgetWithText(OutlinedButton, 'Staging'), findsOneWidget);
    expect(
      tester.renderObject(find.widgetWithText(OutlinedButton, 'Staging')),
      same(retainedSelect),
      reason: 'selection patches the retained Select instead of rebuilding it',
    );
    expect(find.byType(MenuItemButton), findsNothing);

    final combobox = find.byWidgetPredicate(
      (widget) =>
          widget is TextField &&
          widget.decoration?.hintText == 'Search environments',
      description: 'environment Combobox',
    );
    await tester.ensureVisible(combobox);
    final editor = find.descendant(
      of: combobox,
      matching: find.byType(EditableText),
    );
    final retainedEditor = tester.widget<EditableText>(editor);
    await tester.tap(
      find.descendant(of: combobox, matching: find.byType(IconButton)),
    );
    await tester.pump();
    await tester.pump();
    expect(find.byType(MenuItemButton), findsNWidgets(3));
    await tester.enterText(combobox, 'Preview');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    await tester.pump();
    expect(find.widgetWithText(OutlinedButton, 'Preview'), findsOneWidget);
    expect(find.byType(MenuItemButton), findsNothing);
    expect(
      tester.widget<EditableText>(editor).focusNode,
      same(retainedEditor.focusNode),
      reason: 'query and submit patches preserve native input identity',
    );

    final checklist = find.text('Launch checklist.md');
    await tester.ensureVisible(checklist);
    final retainedChecklist = tester.renderObject(checklist);
    await tester.tap(checklist);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Selected Launch checklist.md'), findsNWidgets(2));
    expect(tester.renderObject(checklist), same(retainedChecklist));
    await tester.tap(checklist);
    await tester.pump(const Duration(milliseconds: 40));
    await tester.tap(checklist);
    await tester.pump();
    expect(find.text('Opened Launch checklist.md'), findsNWidgets(2));
  });
}
