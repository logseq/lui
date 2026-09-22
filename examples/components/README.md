# Component gallery

This showcase renders the same OCaml model, reducer, and component tree
(`examples/gallery`) on a native Apple host. The platform directories contain
only lifecycle, event, and rendering bridge code; interactive state lives in
the shared OCaml application.

## Apple

The SwiftUI host (`ios-swiftui/`) uses `NavigationSplitView`: iPhone gets the
standard pushed list/detail flow, while iPad and macOS show the component
sidebar beside the selected page. It `dlopen`s `liblui_components.dylib`,
which packages the OCaml gallery through
`examples/components/native/components_bridge.ml` and the C entry points in
`platform/native/lui_ocaml_bridge.c`.

Build the native library and the macOS target from the repository root:

```sh
dune build examples/components/native/liblui_components.dylib
LUI_COMPONENTS_NATIVE_LINK_INPUTS=examples/components/native/liblui_components.dylib \
  swift build --package-path examples/components/ios-swiftui --target LUIComponentsApp
```

The `ios-swiftui` package declares `.iOS(.v17)` and `.macOS(.v14)` targets, so
the same app builds for macOS on Apple Silicon. The iOS Simulator build
additionally needs an OCaml toolchain cross-compiled for the simulator.

UIKit applications embed the same SwiftUI renderer without a second backend:

```swift
let controller = LUIUIKitHost.makeViewController(
    backend: backend,
    rootID: rootID
)
navigationController.pushViewController(controller, animated: true)
```
