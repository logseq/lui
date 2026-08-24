import 'dart:ffi';

import 'package:ffi/ffi.dart';

typedef _NativePatchCallback = Void Function(Pointer<Utf8> json);
typedef _NativeStart =
    Int32 Function(Pointer<NativeFunction<_NativePatchCallback>> callback);
typedef _DartStart =
    int Function(Pointer<NativeFunction<_NativePatchCallback>> callback);
typedef _NativePress = Int32 Function(Int64 node);
typedef _DartPress = int Function(int node);
typedef _NativeTextChanged = Int32 Function(Int64 node, Pointer<Utf8> text);
typedef _DartTextChanged = int Function(int node, Pointer<Utf8> text);
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
      _textChanged = library
          .lookupFunction<_NativeTextChanged, _DartTextChanged>(
            'lui_ocaml_text_changed',
          ),
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
  final _DartTextChanged _textChanged;
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
    if (_start(callback.nativeFunction) != 1) {
      callback.close();
      _patchCallback = null;
      throw StateError('OCaml runtime initialization failed');
    }
  }

  void press(int node) {
    if (_press(node) != 1) throw StateError('OCaml press dispatch failed');
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

  int get rootNode => _requiredNode(_rootNode(), 'root');

  int _requiredNode(int node, String name) {
    if (node < 0) throw StateError('OCaml $name node lookup failed');
    return node;
  }

  void close() {
    _patchCallback?.close();
    _patchCallback = null;
  }
}
