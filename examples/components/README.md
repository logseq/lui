# Component gallery

This showcase renders the same LG model, reducer, and component tree on every
host. Platform directories contain only lifecycle, event, and rendering bridge
code; interactive state remains in `lg/components`.

## Web

From the repository root:

```sh
make serve-web
```

Open <http://127.0.0.1:8765/examples/components/web/index.html>.

## Flutter

Build the native LG bridge and run the real Flutter integration test:

```sh
opam exec -- dune build -j 1 \
  examples/components/native/liblui_components.dylib
cd examples/components/flutter
flutter test \
  --dart-define=LUI_NATIVE_LIBRARY="$PWD/../../../_build/default/examples/components/native/liblui_components.dylib"
```

The test drives retained Flutter widgets through Dart FFI and verifies that
Signal patches preserve unrelated widget identity and backend-owned state.
