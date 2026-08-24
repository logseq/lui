# LUI

LUI is a retained cross-platform UI runtime written in LG and powered by
[`signal-lg`](../signal-lg). Application code, state, effects, diffing, and
patch generation stay in LG. Each backend applies those patches to real UI
objects:

- Apple: Swift and AppKit (`NSStackView`, `NSTextField`, `NSButton`, and
  `NSScrollView`).
- Flutter: Dart and Flutter widgets (`Row`, `Column`, `Text`,
  `TextButton`, `TextField`, and `SingleChildScrollView`).
- Web: LG compiled by Melange, using typed `melange-webapi` bindings to the
  browser DOM without a JavaScript UI framework.

Apple and Flutter use one JSON object per atomic `PatchBatch` at their native
host boundaries. `lui.wire` encodes the closed LG protocol directly; it does
not erase values into a dynamic representation. The Web backend runs in the
same Melange module as the LG application and applies typed patches directly
to DOM nodes, so it has no JSON bridge and no handwritten JavaScript.

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

LG tests run on both Native and Melange. Apple tests instantiate real AppKit
views and exercise target-action. Flutter widget tests mount real widgets,
drive `TextField` input and button taps through the OCaml bridge, and verify
that keyed moves preserve Flutter render identity.

Build and serve the browser example with:

```sh
make serve-web
```

Then open <http://127.0.0.1:8765/platform/web/index.html>. The page loads the
Melange output from `_build`; the renderer and Todos entrypoint are LG source
under `lg/lui/backend/web.cljc` and `platform/web/lg/todos/web_main.cljc`.

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
