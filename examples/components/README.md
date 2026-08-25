# Component gallery

This showcase renders the same LG model, reducer, and component tree on every
host. Platform directories contain only lifecycle, event, and rendering bridge
code; interactive state remains in `lg/components`. Every catalog component is
one direct root section, so Web, Flutter, iPhone, iPad, and macOS all navigate
to one component page at a time instead of rendering the full catalog at once.

## Web

From the repository root:

```sh
make serve-web
```

The Node host listens on all network interfaces. Open
<http://127.0.0.1:8765/examples/components/web/index.html> locally, or replace
`127.0.0.1` with the computer's LAN address when opening it from a phone.

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

## Apple

The SwiftUI host uses `NavigationSplitView`: iPhone gets the standard pushed
list/detail flow, while iPad and macOS show the component sidebar beside the
selected page. Its `NativeExtension` page is backed by MapKit; the identifier
is registered by the application and is not part of LUI's standard schema.

Build the macOS target from the Apple example directory:

```sh
cd examples/components/ios-swiftui
swift build --target LUIComponentsApp
```

The iOS Simulator build additionally requires the shared LG OCaml iOS
toolchain described by the repository bootstrap scripts.
