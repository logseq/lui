# LUI

LUI is a retained cross-platform UI runtime written in LG and powered by
[`signal-lg`](../signal-lg). Application code, state, effects, diffing, and
patch generation stay in LG. Each backend applies those patches to real UI
objects:

- Apple: one SwiftUI backend shared by iOS and macOS. AppKit is used only to
  host the SwiftUI root in command-line macOS examples.
- Flutter: Dart and Flutter widgets (`Row`, `Column`, `Text`,
  `TextButton`, `TextField`, and `SingleChildScrollView`).
- Web: LG compiled by Melange, using typed `melange-webapi` bindings to the
  browser DOM without a JavaScript UI framework.

Apple and Flutter use one JSON object per atomic `PatchBatch` at their native
host boundaries. `lui.wire` encodes the closed LG protocol directly; it does
not erase values into a dynamic representation. The Web backend runs in the
same Melange module as the LG application and applies typed patches directly
to DOM nodes, so it has no JSON bridge, JavaScript UI framework, or
component-specific JavaScript coordinator.

## Apple package

The repository root is a native Swift package for iOS 17 and macOS 14 or later,
using Swift 6.2. It exports `LUIAppleBackend` (dynamic) and
`LUIAppleBackendStatic` (static); both expose the `LUIAppleBackend` module.
Applications can depend on a Git revision and import that module without copying
backend sources. The root package has no Skip dependencies or build plugins.

The separate `platform/apple/Package.swift` remains the opt-in Skip package.
Both package entry points use the same backend sources.

## Test

Run every runtime and platform test:

```sh
make test
```

Or run one layer independently:

```sh
make test-lg
make test-apple
make test-flutter
```

LG tests run on both Native and Melange. Apple tests exercise the retained
SwiftUI model, per-node invalidation, typed events, and keyed identity. Flutter
widget tests mount real widgets, drive `TextField` input and button taps through
the OCaml bridge, and verify that keyed moves preserve Flutter render identity.

Build and serve the browser example with:

```sh
make serve-web
```

For development, start Dune watch, Tailwind watch, and Vite together:

```sh
make dev-web
```

LG edits are compiled to JavaScript by Dune and picked up by Vite, which reloads
the page without any LG runtime-state integration. CSS and JavaScript modules
use Vite hot module replacement. A failed LG compilation leaves the last valid
page running; saving valid source resumes the update automatically.

Then open <http://127.0.0.1:8765/examples/todos/web/index.html>. The page loads the
Melange output from `_build`; the renderer and Todos entrypoint are LG source
under `platform/web/lg/lui/backend/web.cljc` and
`examples/todos/web/lg/todos/web_main.cljc`.

`make serve-web` uses the Node static server and listens on all interfaces. To
preview from a phone on the same local network, replace `127.0.0.1` with the
Mac's LAN address. The equivalent explicit command is:

```sh
node tooling/serve_web.mjs --host 0.0.0.0 --port 8765
```

The component showcase is at
<http://127.0.0.1:8765/examples/components/web/index.html>. It uses the same LG
Signal reducer and component tree as the native hosts. The Flutter host and its
real OCaml FFI integration test are documented in
[`examples/components/README.md`](examples/components/README.md).

The Web showcase starts in the iOS simulator profile. Use its Platform control
to switch the same retained DOM tree between iOS and Android presentation. Its
Device and Rotate controls cover phone/tablet portrait and landscape traits,
including safe areas, touch/hybrid pointer input, scale, and focus-driven
virtual keyboard state. The simulator remains semantic DOM rather than a
full-screen Canvas renderer, and the detached popup portal follows the selected
platform and device without replacing open controls or focused text input.
The `NativeExtension` page also demonstrates a retained semantic Map and Camera.
The Map uses deterministic DOM geometry and accessible controls without Canvas;
the Camera starts with a deterministic mock feed and requests `getUserMedia`
only after an explicit user action, with denied-permission and stream-cleanup
behavior.
The `BottomTabs` page demonstrates the shared navigation contract: native
SwiftUI `TabView` on Apple, native Material `NavigationBar` on Android, and
retained semantic DOM with iOS Liquid Glass or Android Material presentation
in the Web Simulator.
The Switch page keeps the platform-sized control at the trailing edge, matching
native label placement. Dialog and Sheet actions update the shared model-owned
presentation state; phone sheets expose a drag handle and support downward
distance/velocity dismissal. SwiftUI uses its system drag indicator, while the
Android backend enables the Material bottom-sheet drag handle.

Fetch the pinned public SwiftUI and Compose comparison corpus, then run the
deterministic Chromium visual regression suite with:

```sh
make fetch-web-references
make test-web-visual
```

Baseline replacement is intentionally separate and must be reviewed:

```sh
make update-web-visual-baselines
```

The committed scenarios fix viewport, device scale, locale, timezone, color
scheme, reduced motion, time, randomness, and animation state. A failure writes
a pixel diff under `_build/web-simulator-visual-diffs`.

Build the iOS Simulator app and Android arm64 APK together with:

```sh
make build-components-mobile
```

Qualify a signed, shrunk Android release AAB without using production secrets:

```sh
make qualify-components-android-release
```

Compile the single SwiftUI Apple renderer through its public UIKit host adapter:

```sh
make test-apple-uikit-host
```

The command invokes the explicit `ios simulator` and `android` LG targets,
then links the two host applications. Shared toolchains are installed once
with `lg mobile setup ios simulator` and `lg mobile setup android`; LUI does
not clone OCaml or keep per-project cross-toolchain scripts.

## Declarative UI

Applications define views with `defui`. Views receive reactive model signals
and emit action values; reducers and effects remain outside the view. The
classic example is in `examples/todos`:

- `model.cljc` defines the model, actions, and pure reducer;
- `view.cljc` contains only declarative UI;
- `app.cljc` connects the reducer and view through `lui.app`.

Primitive tags are independent `defelement` definitions. A library can add a
qualified tag such as `:my.widgets/card` without changing `defui` or its tag
dispatcher.

## Host connection

Use `lui.backend.apple/create-wire` or
`lui.backend.flutter/create-wire` with a host function of type
`fn<string;bool>`. Each successful LUI flush invokes that function once with a
complete JSON batch. Return `false` to reject the batch without committing the
LG retained state.

The Web backend is `lui.backend.web`. It creates and updates DOM elements
through `melange-webapi` directly and dispatches browser events into the same
typed LUI event and effect pipeline used by the native backends.
