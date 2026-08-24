import 'dart:io';

import 'package:flutter/material.dart';
import 'package:lui_flutter_backend/lui_flutter_backend.dart';
import 'package:lui_flutter_backend/lui_ocaml_bridge.dart';

String _libraryPath() {
  const configured = String.fromEnvironment('LUI_NATIVE_LIBRARY');
  if (configured.isNotEmpty) return configured;
  final contents = File(Platform.resolvedExecutable).parent.parent;
  return '${contents.path}/Frameworks/liblui_todos.dylib';
}

void main() {
  runApp(const TodosHost());
}

class TodosHost extends StatefulWidget {
  const TodosHost({super.key});

  @override
  State<TodosHost> createState() => _TodosHostState();
}

class _TodosHostState extends State<TodosHost> {
  late final LUIFlutterBackend _backend;
  late final LUIOcamlBridge _bridge;

  @override
  void initState() {
    super.initState();
    _backend = LUIFlutterBackend(onEvent: _dispatch);
    _bridge = LUIOcamlBridge.open(_libraryPath(), onPatch: _backend.applyJson);
    _bridge.start();
  }

  void _dispatch(LUIEvent event) {
    switch (event) {
      case LUIPressEvent(:final node):
        _bridge.press(node);
      case LUITextChangedEvent(:final node, :final text):
        _bridge.textChanged(node, text);
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'LUI Todos',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff6750a4)),
        useMaterial3: true,
      ),
      home: Scaffold(
        appBar: AppBar(title: const Text('LUI · LG Todos')),
        body: Align(
          alignment: Alignment.topLeft,
          child: _backend.widget(node: _bridge.rootNode),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _bridge.close();
    _backend.dispose();
    super.dispose();
  }
}
