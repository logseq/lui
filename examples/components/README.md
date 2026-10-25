# Component gallery

This showcase renders the same OCaml model, reducer, and component tree
(`examples/gallery`) on native Apple and Android hosts. The platform directories
contain only lifecycle, event, and rendering bridge code; interactive state lives in
the shared OCaml application.

## Apple

The SwiftUI host (`ios-swiftui/`) uses `NavigationSplitView`: iPhone gets the
standard pushed list/detail flow, while iPad and macOS show the component
sidebar beside the selected page. It links the OCaml Gallery as a native
library or complete object through
`examples/components/native/components_bridge.ml` and the C entry points in
`platform/native/lui_ocaml_bridge.c`.

Build the native library and the macOS target from the repository root:

```sh
opam exec -- dune build examples/components/native/liblui_components.dylib
LUI_COMPONENTS_NATIVE_LINK_INPUTS="$PWD/_build/default/examples/components/native/liblui_components.dylib" \
  swift build --package-path examples/components/ios-swiftui --product LUIComponentsApp
```

The `ios-swiftui` package declares `.iOS(.v17)` and `.macOS(.v14)` targets.
For a development iOS Simulator build:

```sh
bash tooling/mobile/build_components_ios_simulator.sh
xcrun simctl install booted _build/mobile-components/ios-simulator/LUIComponents.app
xcrun simctl launch booted dev.lui.components
```

Pass `LUI_GALLERY_OCAML_OBJECT` to use an existing target-compiled complete OCaml
object. Select an explicit simulator UUID instead of `booted` when several
simulators are running.

UIKit applications embed the same SwiftUI renderer without a second backend:

```swift
let controller = LUIUIKitHost.makeViewController(
    backend: backend,
    rootID: rootID
)
navigationController.pushViewController(controller, animated: true)
```

## Android

The Compose host uses the same maintained OCaml Gallery and native bridge.
It requires JDK 21, Android SDK 37.0, an NDK, and the matching Android OCaml
toolchain. For the default ARM64 target, set `LG_ANDROID_OCAML_PREFIX` to the
toolchain prefix containing `bin/ocamlopt.opt` and `lib/ocaml`.

```sh
bash tooling/mobile/build_components_android.sh
LUI_OCAML_INCLUDE="$LG_ANDROID_OCAML_PREFIX/lib/ocaml" \
  platform/android/gradlew --no-daemon -p examples/components/android :app:assembleDebug
```

The build cross-compiles the current core, pinned `ocaml-signal` sources from
the active opam switch, and `examples/gallery`. It links the target Unix and
Threads runtime libraries required by JNI. Compiler intermediates stay outside
the source tree; packaged libraries and APKs remain ignored build artifacts.
The obsolete LG application directories are not required.

Updated SwiftUI and Kotlin hosts negotiate bounded virtual rows with the
application library. In the 100k section, use `Load 100k`, `Jump to last`,
`Back to top` and `Clear` to exercise distant targets through the shared model.
Jump controls are disabled while empty; replacing the source cancels the old
target and every new jump receives a fresh request token.

The large-list section uses `virtual_rows`; literal or
`keyed` children keep eager LUI ownership. See the
[migration guide](../../docs/api-migrations.md#bounded-row-generation-for-virtual-lists)
for capability negotiation, controlled row state and compatibility.

## Bounded virtual-row regression tests

Build the portable OCaml integration application once from the repository root:

```sh
bash tooling/test/build_bounded_virtual_fixture.sh /tmp/lui-bounded-native-fixture
```

On macOS, exercise the actual SwiftUI host and then its complete package suite:

```sh
LUI_APPLE_BOUNDED_LIBRARY=/tmp/lui-bounded-native-fixture/liblui_bounded_virtual.dylib \
  swift test --package-path platform/apple --filter LUISparseVirtualNativeTests
swift test --package-path platform/apple
```

The integration test loads 100,000 rows, scrolls to the logical bottom, reorders
an actively composing editor, varies row height, rebuilds from an authoritative
snapshot, shrinks and clears twice. Host tests separately exercise actual pointer,
menu and sheet ownership. On a booted Apple Silicon iOS simulator, also run:

```sh
python3 platform/apple/Tests/RuntimeChecks/run-ios-check.py bounded-virtual-rows --simulator booted
```

This checks UIKit inset geometry, focused marked-text reorder, native far
scrolling and Clear. See the [native runtime checks](../../platform/apple/Tests/RuntimeChecks/README.md).

The integration library is optional for ordinary package
tests; CI builds it and runs the integration test explicitly.

With JDK 21, run the real JVM/JNI/OCaml lifecycle and Compose renderer tests:

```sh
python3 platform/android/test_native_virtual_rows.py /tmp/lui-bounded-native-fixture
platform/android/gradlew --no-daemon -p platform/android :lui:testDebugUnitTest
```

The JVM test checks old/new library negotiation, integer-range validation, stale
requests, snapshots and bounded node counts through the production JNI bridge.
Compose tests exercise native scrolling, editor and input-connection identity,
composition, pointer/selection/popup pins, variable geometry and scroll targets.
Run Dune-based builders sequentially; Android builds that include the same `lui`
project must also run sequentially because they share its build directory.
