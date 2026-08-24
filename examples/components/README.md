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

## Flutter desktop

Build the signed macOS app with the native LG library embedded:

```sh
make build-components-flutter-macos
```

Run it from the Flutter tool:

```sh
make run-components-flutter-macos
```

Run both the real Dart-to-OCaml FFI interaction test and the signed application
package smoke test:

```sh
make test-flutter
```

The interaction test drives retained Flutter widgets through Dart FFI and
verifies that Signal patches preserve unrelated widget identity and
backend-owned state. The package test performs a real macOS Flutter build and
checks the executable, embedded native library, Mach-O type, and code signature.
