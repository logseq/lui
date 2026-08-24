import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';

typedef _NativePatchCallback = Void Function(Pointer<Utf8> json);
typedef _NativeStart =
    Int32 Function(
      Pointer<NativeFunction<_NativePatchCallback>> callback,
      Int32 platform,
    );
typedef _DartStart =
    int Function(
      Pointer<NativeFunction<_NativePatchCallback>> callback,
      int platform,
    );
typedef _NativePress = Int32 Function(Int64 node);
typedef _DartPress = int Function(int node);
typedef _NativeHold = Int32 Function(Int64 node);
typedef _DartHold = int Function(int node);
typedef _NativeTextChanged = Int32 Function(Int64 node, Pointer<Utf8> text);
typedef _DartTextChanged = int Function(int node, Pointer<Utf8> text);
typedef _NativeSubmit = Int32 Function(Int64 node);
typedef _DartSubmit = int Function(int node);
typedef _NativeDismiss = Int32 Function(Int64 node);
typedef _DartDismiss = int Function(int node);
typedef _NativeDoublePress = Int32 Function(Int64 node);
typedef _DartDoublePress = int Function(int node);
typedef _NativeToggleChanged = Int32 Function(Int64 node, Int32 checked);
typedef _DartToggleChanged = int Function(int node, int checked);
typedef _NativeRadioChanged = Int32 Function(Int64 node);
typedef _DartRadioChanged = int Function(int node);
typedef _NativeSliderChanged = Int32 Function(Int64 node, Double value);
typedef _DartSliderChanged = int Function(int node, double value);
typedef _NativeStop = Int32 Function();
typedef _DartStop = int Function();
typedef _NativeNode = Int64 Function();
typedef _DartNode = int Function();

final class LUIOcamlBridge {
  LUIOcamlBridge._(this.library, this.onPatch)
    : _start = library.lookupFunction<_NativeStart, _DartStart>(
        'lui_ocaml_start',
      ),
      _press = library.lookupFunction<_NativePress, _DartPress>(
        'lui_ocaml_press',
      ),
      _hold = library.lookupFunction<_NativeHold, _DartHold>('lui_ocaml_hold'),
      _textChanged = library
          .lookupFunction<_NativeTextChanged, _DartTextChanged>(
            'lui_ocaml_text_changed',
          ),
      _submit = library.lookupFunction<_NativeSubmit, _DartSubmit>(
        'lui_ocaml_submit',
      ),
      _dismiss = library.lookupFunction<_NativeDismiss, _DartDismiss>(
        'lui_ocaml_dismiss',
      ),
      _doublePress = library
          .lookupFunction<_NativeDoublePress, _DartDoublePress>(
            'lui_ocaml_double_press',
          ),
      _toggleChanged = library
          .lookupFunction<_NativeToggleChanged, _DartToggleChanged>(
            'lui_ocaml_toggle_changed',
          ),
      _radioChanged = library
          .lookupFunction<_NativeRadioChanged, _DartRadioChanged>(
            'lui_ocaml_radio_changed',
          ),
      _sliderChanged = library
          .lookupFunction<_NativeSliderChanged, _DartSliderChanged>(
            'lui_ocaml_slider_changed',
          ),
      _stop = library.lookupFunction<_NativeStop, _DartStop>('lui_ocaml_stop'),
      _rootNode = library.lookupFunction<_NativeNode, _DartNode>(
        'lui_ocaml_root_node',
      );

  factory LUIOcamlBridge.open(
    String libraryPath, {
    required void Function(String json) onPatch,
  }) => LUIOcamlBridge._(DynamicLibrary.open(libraryPath), onPatch);

  final DynamicLibrary library;
  final void Function(String json) onPatch;
  final _DartStart _start;
  final _DartPress _press;
  final _DartHold _hold;
  final _DartTextChanged _textChanged;
  final _DartSubmit _submit;
  final _DartDismiss _dismiss;
  final _DartDoublePress _doublePress;
  final _DartToggleChanged _toggleChanged;
  final _DartRadioChanged _radioChanged;
  final _DartSliderChanged _sliderChanged;
  final _DartStop _stop;
  final _DartNode _rootNode;
  NativeCallable<_NativePatchCallback>? _patchCallback;

  void start() {
    if (_patchCallback != null) {
      throw StateError('OCaml bridge is already started');
    }
    final callback = NativeCallable<_NativePatchCallback>.isolateLocal(
      (Pointer<Utf8> json) => onPatch(json.toDartString()),
    );
    _patchCallback = callback;
    if (_start(callback.nativeFunction, _platformCode(defaultTargetPlatform)) !=
        1) {
      callback.close();
      _patchCallback = null;
      throw StateError('OCaml runtime initialization failed');
    }
  }

  static int _platformCode(TargetPlatform platform) => switch (platform) {
    TargetPlatform.macOS => 1,
    TargetPlatform.iOS => 2,
    TargetPlatform.android => 3,
    TargetPlatform.linux => 4,
    TargetPlatform.windows => 5,
    TargetPlatform.fuchsia => 0,
  };

  void press(int node) {
    if (_press(node) != 1) throw StateError('OCaml press dispatch failed');
  }

  void hold(int node) {
    if (_hold(node) != 1) throw StateError('OCaml hold dispatch failed');
  }

  void doublePress(int node) {
    if (_doublePress(node) != 1) {
      throw StateError('OCaml double-press dispatch failed');
    }
  }

  void textChanged(int node, String text) {
    final nativeText = text.toNativeUtf8();
    try {
      if (_textChanged(node, nativeText) != 1) {
        throw StateError('OCaml text dispatch failed');
      }
    } finally {
      malloc.free(nativeText);
    }
  }

  void submit(int node) {
    if (_submit(node) != 1) throw StateError('OCaml submit dispatch failed');
  }

  void dismiss(int node) {
    if (_dismiss(node) != 1) throw StateError('OCaml dismiss dispatch failed');
  }

  void toggleChanged(int node, bool checked) {
    if (_toggleChanged(node, checked ? 1 : 0) != 1) {
      throw StateError('OCaml toggle dispatch failed');
    }
  }

  void radioChanged(int node) {
    if (_radioChanged(node) != 1) {
      throw StateError('OCaml radio dispatch failed');
    }
  }

  void sliderChanged(int node, double value) {
    if (_sliderChanged(node, value) != 1) {
      throw StateError('OCaml slider dispatch failed');
    }
  }

  int get rootNode => _requiredNode(_rootNode(), 'root');

  int _requiredNode(int node, String name) {
    if (node < 0) throw StateError('OCaml $name node lookup failed');
    return node;
  }

  void close() {
    final callback = _patchCallback;
    if (callback == null) return;
    if (_stop() != 1) {
      throw StateError('OCaml runtime disposal failed');
    }
    callback.close();
    _patchCallback = null;
  }
}
