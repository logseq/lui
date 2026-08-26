import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lui_flutter_backend/lui_flutter_backend.dart';
import 'package:lui_flutter_backend/lui_ocaml_bridge.dart';

import 'gallery_extensions.dart';

LUIOcamlBridge _openBridge(void Function(String json) onPatch) {
  const configured = String.fromEnvironment('LUI_NATIVE_LIBRARY');
  if (configured.isNotEmpty) {
    return LUIOcamlBridge.open(configured, onPatch: onPatch);
  }
  if (Platform.isAndroid) {
    return LUIOcamlBridge.open('liblui_components.so', onPatch: onPatch);
  }
  if (Platform.isIOS) {
    return LUIOcamlBridge.process(onPatch: onPatch);
  }
  final contents = File(Platform.resolvedExecutable).parent.parent;
  return LUIOcamlBridge.open(
    '${contents.path}/Frameworks/liblui_components.dylib',
    onPatch: onPatch,
  );
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
  int? _selectedSectionID;

  @override
  void initState() {
    super.initState();
    _backend = LUIFlutterBackend(
      extensionRegistry: galleryExtensionRegistry(),
      onEvent: _dispatch,
    );
    _bridge = _openBridge(_applyPatch);
    _bridge.start();
    unawaited(_registerGalleryMedia());
  }

  void _applyPatch(String json) {
    _backend.applyJson(json);
    if (mounted) setState(() {});
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
      case LUILongPressEvent(:final node):
        _bridge.longPress(node);
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
      case LUIExtensionComponentEvent():
        throw StateError('Gallery extensions do not declare LG events');
    }
  }

  @override
  Widget build(BuildContext context) {
    final sections = _backend.rootSections(_bridge.rootNode);
    final selected = sections.firstWhere(
      (section) => section.id == _selectedSectionID,
      orElse: () => sections.first,
    );
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'LUI Components',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff6750a4)),
        useMaterial3: true,
      ),
      home: LayoutBuilder(
        builder: (context, constraints) => constraints.maxWidth >= 720
            ? _wideGallery(sections, selected)
            : _compactGallery(context, sections, selected),
      ),
    );
  }

  Widget _wideGallery(List<LUIRootSection> sections, LUIRootSection selected) {
    return Scaffold(
      appBar: AppBar(title: const Text('LUI Components')),
      body: Row(
        children: [
          NavigationRail(
            scrollable: true,
            extended: true,
            selectedIndex: sections.indexOf(selected),
            onDestinationSelected: (index) {
              setState(() => _selectedSectionID = sections[index].id);
            },
            destinations: [
              for (final section in sections)
                NavigationRailDestination(
                  icon: const Icon(Icons.widgets_outlined),
                  selectedIcon: const Icon(Icons.widgets),
                  label: _sectionLabel(section),
                ),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(child: _sectionContent(selected)),
        ],
      ),
    );
  }

  Widget _compactGallery(
    BuildContext context,
    List<LUIRootSection> sections,
    LUIRootSection selected,
  ) {
    return Scaffold(
      appBar: AppBar(title: Text(selected.title)),
      drawer: NavigationDrawer(
        selectedIndex: sections.indexOf(selected),
        onDestinationSelected: (index) {
          setState(() => _selectedSectionID = sections[index].id);
          Navigator.of(context).pop();
        },
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(28, 20, 16, 12),
            child: Text('Components'),
          ),
          for (final section in sections)
            _GalleryNavigationDrawerDestination(
              identifier: 'component-row-${section.title}',
              icon: const Icon(Icons.widgets_outlined),
              selectedIcon: const Icon(Icons.widgets),
              label: Text(section.title),
            ),
        ],
      ),
      body: _sectionContent(selected),
    );
  }

  Widget _sectionContent(LUIRootSection section) {
    return SingleChildScrollView(
      child: Align(
        alignment: Alignment.topLeft,
        child: _backend.widget(node: section.id),
      ),
    );
  }

  Widget _sectionLabel(LUIRootSection section) {
    return Semantics(
      identifier: 'component-row-${section.title}',
      child: Text(section.title),
    );
  }

  @override
  void dispose() {
    _bridge.close();
    _backend.dispose();
    super.dispose();
  }
}

class _GalleryNavigationDrawerDestination extends NavigationDrawerDestination {
  const _GalleryNavigationDrawerDestination({
    required this.identifier,
    required super.icon,
    super.selectedIcon,
    required super.label,
  });

  final String identifier;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      identifier: identifier,
      child: super.build(context),
    );
  }
}
