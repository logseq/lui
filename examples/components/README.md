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

Run the iOS interaction suite against a booted simulator:

```sh
make test-components-ios-e2e
```

Reuse an existing Simulator app while iterating on the Maestro flow:

```sh
LUI_IOS_E2E_SKIP_BUILD=1 make test-components-ios-e2e
```

## Android

Build the shared LG runtime and arm64 debug APK in one command:

```sh
make build-components-android
```

Run the real interaction suite against the only connected Android device or
emulator:

```sh
make test-components-android-e2e
```

When more than one device is connected, select it explicitly:

```sh
LUI_ANDROID_DEVICE_ID=emulator-5554 make test-components-android-e2e
```

Reuse an existing APK while iterating on interactions:

```sh
LUI_ANDROID_E2E_SKIP_BUILD=1 \
LUI_ANDROID_DEVICE_ID=emulator-5554 \
make test-components-android-e2e
```

The runner builds the shared OCaml/JNI library and APK, installs it, drives the
adaptive Material Gallery with Maestro, and writes the final screenshot to
`_build/mobile-components/android-e2e/final.png`.

## Qualification snapshot

The following production-boundary checks passed on 2026-08-26 at commit
`2cdf8ad`:

- `swift test --package-path platform/apple`: 62 retained SwiftUI backend tests;
- `make test-components-ios-e2e`: signed app build plus the complete Maestro
  interaction flow on an iPhone 17 Pro Simulator running iOS 26.0;
- `swift build --package-path examples/components/ios-swiftui` with
  `--target LUIComponentsApp`: the shared SwiftUI Gallery target on macOS;
- `make build-components-flutter-macos` and
  `make test-components-flutter-macos`: the Flutter desktop app and packaged
  native-library/code-signature smoke test;
- `make test-components-android-e2e`: fresh arm64 debug APK build, install, and
  complete Maestro interaction flow on an Android 16 emulator;
- `npm --prefix platform/web run check`: 37 production CSS and backend-boundary
  tests, followed by the focused Toolbar and all-65-page compact viewport E2E
  pass.

The resulting debug artifacts were 9,412 KiB for the iOS Simulator app,
110,528 KiB for the Flutter macOS app, and 98,368 KiB for the Android APK.
These numbers qualify repeatability and packaging content; they are not release
size budgets.

## Known limitations

- Physical iPhone/iPad and physical Android-device interaction passes are not
  yet recorded. The current mobile evidence is Simulator/emulator evidence.
- Android release shrinking, store signing, and AAB packaging are not qualified;
  the current Android artifact is a debug APK.
- The SwiftUI macOS target is compile-qualified, while the Flutter macOS app is
  the packaged desktop showcase. A separately bundled SwiftUI macOS `.app` is
  not produced by this example.
- SwiftUI is the only Apple renderer. UIKit applications can host the public
  `LUISwiftUIRoot` with `UIHostingController`, but LUI intentionally does not
  maintain a second UIKit component backend or a separate UIKit Gallery.
- Web interaction E2E currently runs through Chromium. Cross-browser Safari and
  Firefox qualification remains outstanding.
