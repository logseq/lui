import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lui_flutter_backend/lui_flutter_backend.dart';
import 'package:lui_flutter_backend/lui_ocaml_bridge.dart';

String _libraryPath() {
  const configured = String.fromEnvironment('LUI_NATIVE_LIBRARY');
  if (configured.isNotEmpty) return configured;
  final contents = File(Platform.resolvedExecutable).parent.parent;
  return '${contents.path}/Frameworks/liblui_components.dylib';
}

void main() {
  runApp(const ComponentGalleryHost());
}

class ComponentGalleryHost extends StatefulWidget {
  const ComponentGalleryHost({super.key});

  @override
  State<ComponentGalleryHost> createState() => _ComponentGalleryHostState();
}

class _ComponentGalleryHostState extends State<ComponentGalleryHost> {
  late final LUIFlutterBackend _backend;
  late final LUIOcamlBridge _bridge;

  @override
  void initState() {
    super.initState();
    _backend = LUIFlutterBackend(onEvent: _dispatch);
    _bridge = LUIOcamlBridge.open(_libraryPath(), onPatch: _backend.applyJson);
    _bridge.start();
    unawaited(_registerGalleryMedia());
  }

  Future<void> _registerGalleryMedia() async {
    ui.Codec? codec;
    ui.Image? image;
    try {
      final data = await rootBundle.load(
        'macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_128.png',
      );
      codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
      image = (await codec.getNextFrame()).image;
      if (mounted) {
        _backend.registerImage(id: 1, image: image);
        _backend.presentMediaSurfaceFrame(id: 1, image: image);
      }
    } catch (error, stack) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'LUI component gallery',
          context: ErrorDescription('while registering Gallery media'),
        ),
      );
    } finally {
      image?.dispose();
      codec?.dispose();
    }
  }

  void _dispatch(LUIEvent event) {
    switch (event) {
      case LUIPressEvent(:final node):
        _bridge.press(node);
      case LUIHoldEvent(:final node):
        _bridge.hold(node);
      case LUITextChangedEvent(:final node, :final text):
        _bridge.textChanged(node, text);
      case LUISubmitEvent(:final node):
        _bridge.submit(node);
      case LUIDismissEvent(:final node):
        _bridge.dismiss(node);
      case LUIDoublePressEvent(:final node):
        _bridge.doublePress(node);
      case LUIToggleChangedEvent(:final node, :final checked):
        _bridge.toggleChanged(node, checked);
      case LUIChangeEvent(:final node):
        _bridge.radioChanged(node);
      case LUIValueChangedEvent(:final node, :final value):
        _bridge.sliderChanged(node, value);
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'LUI Components',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff6750a4)),
        useMaterial3: true,
      ),
      home: Scaffold(
        appBar: AppBar(title: const Text('LUI Component Gallery')),
        body: SingleChildScrollView(
          child: Align(
            alignment: Alignment.topLeft,
            child: _backend.widget(node: _bridge.rootNode),
          ),
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
