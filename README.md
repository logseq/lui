# LUI

Updating an existing application? See the [API migration guide](docs/api-migrations.md)
for constructor, wire-contract and behavior changes.

LUI is a retained, cross-platform UI runtime written in OCaml and powered by
[`ocaml-signal`](https://github.com/logseq/ocaml-signal). Application code,
state, diffing, and patch generation stay in OCaml; each backend applies those
patches to real UI objects:

- **Desktop (default)**: the MyGo backend (`platform/mygo`) uses native
  desktop controls and the shared OCaml C ABI, with runnable Todos and
  Components hosts and headless interaction tests.
- **Apple**: one SwiftUI backend shared by iOS and macOS (`platform/apple`,
  `LUIAppleBackend` Swift package).
- **Web**: a Melange companion library (`platform/web/melange`) plus the
  shared stylesheet and icon set (`platform/web/src`).
- **Android**: a Kotlin backend (`platform/android`, package `dev.lui`)
  applying patches to native Android views.

Apple uses one JSON object per atomic `patch_batch` at its
native host boundary; `Lui_wire` encodes the protocol directly. The Web
backend runs in the same process as the OCaml application and applies typed
patches to DOM nodes — no JSON bridge, no JavaScript UI framework. MyGo,
Apple and Android hosts share the `lui_ocaml_*` C ABI in
`platform/bridge/lui_ocaml_bridge.c`; each host applies wire batches
incrementally. OCaml owns the application, not a second desktop renderer.
The former SDL-based OCaml renderer has been removed; see the
[breaking-change migration](docs/api-migrations.md#unreleased-mygo-desktop-and-portable-host-services).

## Layout

```
src/                  the lui library (protocol, runtime, elements, app)
examples/todos/       headless todo demo (pure OCaml + ocaml-signal)
examples/gallery/     headless component-gallery demo
platform/apple/       SwiftUI backend (SwiftPM package + tests)
platform/web/         Melange DOM library, stylesheet, icons
platform/android/     Kotlin Android backend (Gradle, dev.lui package)
platform/mygo/        MyGo native desktop backend (Go module + host + tests)
platform/bridge/      shared lui_ocaml_* C ABI and GC stress runner
platform/services/    portable lui.plugin and lui.plugin_fetch libraries
schema/               canonical component schema (components.json)
tooling/              schema code generator and tests
test/                 alcotest suite
```

## The element DSL

`Lui_elements` exposes one constructor per node kind — `row`, `column`,
`button`, `text_field`, `dialog`, `bottom_tabs`, … — each with the shape
`?props -> children:t list -> t`: optional props first, a positional children
list last (which is also what erases the optional args, so no extra `()` is
needed):

```ocaml
open Lui_elements

let view context model_source send : t =
  column ~gap:14 ~padding:24
    [ text_field
        ~text:(reactive (fun m -> m.draft) model_source)
        ~label:"New todo"
        ~on_input:(on_input send Model.ChangeDraft)
        []
    ; button ~text:"Add" ~on_press:(press send Model.AddTodo) []
    ; text ~value:(reactive summary_label model_source) []
    ]
```

A view returns an element `t`; `Lui_app` mounts it against the root context.
`press send action` wraps a bool `send` into the `event -> unit` handler the
`~on_press`/`~on_submit` props take, and `on_input` unwraps `TextChanged`
events the same way.

Signals (`ocaml-signal`) drive props through `reactive`; enable
`(preprocess (pps lui_ppx))` in the view's Dune stanza. A prop-position
`reactive` updates the existing node in place. Use children-position
`reactive` only when a signal changes the subtree's structure, `if_ ~test`
for conditional mounting, and `keyed ~source ~key ~cmp ~mount` for
identity-keyed child collections. Static branching remains ordinary OCaml.
Do not call the internal `dyn` expansion target directly.

Theming is scoped per subtree: `themed ~tokens ~mode el` wraps any element
with a JSON token table (`["primary", "#7c3aed"]` overrides the semantic
`primary` slot) and an optional `` `system`/`` `light`/`` `dark`` mode —
`~tokens:(reactive tokens_s)`/`~mode:(reactive mode_s)` hot-switch either in place. Backends
resolve semantic color names through the merged token table first, then the
platform default theme, so an app gets platform-native styling unless it
opts into overrides (`Lui_app.set_theme`/`set_theme_mode` patch the mounted
root directly). See the Theming section of
`docs/agent-guide/001-production-components.md`.

## Examples

Run the default desktop backend on macOS or Linux (Go 1.27.3+):

```sh
library=$(./tooling/build_mygo_todos.sh)
go -C platform/mygo run ./cmd/lui-mygo -library "$library"

components=$(./tooling/build_mygo_components.sh)
go -C platform/mygo run ./cmd/lui-mygo -library "$components" -title Components
```

The `examples/*/native` directories build shared OCaml application libraries
for hosts; they are not the removed renderer. See the
[MyGo guide](platform/mygo/README.md) for embedding and system requirements.

Both demos mount a real `Lui_app` against a printing backend, so running them
shows the generated patch batches:

```sh
eval $(opam env)
dune exec examples/todos/main.exe
dune exec examples/gallery/main.exe
```

`examples/todos` is the classic reducer + keyed-list app. `examples/gallery`
exercises ~10 sections of the component schema (layout, text, controls,
fields, pickers, lists, overlays, navigation) mirroring the original gallery.

## Build and test

```sh
# the (private) ocaml-signal pin lives in lui.opam.locked (pin-depends);
# --locked makes opam resolve it without a manual `opam pin`
opam install . --deps-only --with-test --locked

dune build @all  # all OCaml application, bridge and portable service targets
make test        # schema contract tests + dune @runtest
make test-ocaml  # alcotest suite only
make test-apple  # SwiftUI backend tests (macOS)
make test-mygo   # MyGo backend tests with race detection
make test-mygo-integration # actual OCaml Todos through MyGo
```

Per-platform backend builds and test recipes are documented under each
`platform/` directory (the Gradle wrapper under `platform/android` for
Android).

### Native Drive testing

[Drive](https://github.com/logseq/drive) keeps fast semantic/headless tests
separate from native input. Android has an optional, explicitly launched
[instrumentation host](platform/android/drive/README.md) for API 30+ debug
variants. It injects OS MotionEvent/KeyEvent input and uses a deliberately
selected test IME for Unicode/empty text replacement; it never emits LUI
semantic events as a fallback.

With the host running and an explicit `adb forward`, use a Drive version
that supports `drive --tcp 127.0.0.1:49377 --input native scenario.drive`.
The host, IME, permission and runner must remain outside release artifacts.
Its compile/protocol/lint checks do not establish real-device input behavior;
see the host guide for setup, cleanup, geometry and settling limits.

For iOS, a DEBUG-only, opt-in [read-only snapshot probe](platform/apple/DriveProbe.md)
connects to Drive's separate XCTest UI-testing runner. The probe does not inject
input. Apple compile checks cover the backend/probe and standalone runner;
Simulator/device input remains unverified. Build/install the integrating DEBUG
app and exercise its UI-testing target before relying on native interaction.

## Component schema

`schema/components.json` is the single source of truth for node kinds,
properties, events, and wire names. Regenerate the derived artifacts after
editing it:

```sh
make generate-component-schema
```

It emits `src/lui_protocol.mli`, `src/lui_wire_schema.ml`,
`src/lui_wire_schema.mli`, the Swift enum table, and the Dart decoder.
CI runs `--check`, so generated files must be committed.
