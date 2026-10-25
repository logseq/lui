# LUI

Updating an existing application? See the [API migration guide](docs/api-migrations.md)
for constructor, wire-contract and behavior changes.

LUI is a retained, cross-platform UI runtime written in OCaml and powered by
[`ocaml-signal`](https://github.com/logseq/ocaml-signal). Application code,
state, diffing, and patch generation stay in OCaml; each backend applies those
patches to real UI objects:

- **Apple**: one SwiftUI backend shared by iOS and macOS (`platform/apple`,
  `LUIAppleBackend` Swift package).
- **Web**: a Melange companion library (`platform/web/melange`) plus the
  shared stylesheet and icon set (`platform/web/src`).
- **MyGo**: a Go native desktop backend (`platform/mygo`) using the shared
  OCaml C ABI, with a runnable Todos host and headless interaction tests.
- **Android**: a Kotlin backend (`platform/android`, package `dev.lui`)
  applying patches to native Android views.

Apple uses one JSON object per atomic `patch_batch` at its
native host boundary; `Lui_wire` encodes the protocol directly. The Web
backend runs in the same process as the OCaml application and applies typed
patches to DOM nodes — no JSON bridge, no JavaScript UI framework. The
native OCaml host (`platform/native`) renders the same retained tree on the
desktop through the `lui_ocaml_*` C ABI (`platform/native/lui_ocaml_bridge.c`);
each native host keeps a retained node store that applies wire batches
incrementally.

## Layout

```
src/                  the lui library (protocol, runtime, elements, app)
examples/todos/       headless todo demo (pure OCaml + ocaml-signal)
examples/gallery/     headless component-gallery demo
platform/apple/       SwiftUI backend (SwiftPM package + tests)
platform/web/         Melange DOM library, stylesheet, icons
platform/android/     Kotlin Android backend (Gradle, dev.lui package)
platform/mygo/        MyGo native desktop backend (Go module + host + tests)
platform/native/      shared lui_ocaml_* C ABI used by native hosts
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
        ~text_signal:(map (fun m -> m.draft) model_source)
        ~label:"New todo"
        ~on_input:(on_input send Model.ChangeDraft)
        []
    ; button ~text:"Add" ~on_press:(press send Model.AddTodo) []
    ; text ~value_signal:(map summary_label model_source) []
    ]
```

A view returns an element `t`; `Lui_app` mounts it against the root context.
`press send action` wraps a bool `send` into the `event -> unit` handler the
`~on_press`/`~on_submit` props take, and `on_input` unwraps `TextChanged`
events the same way.

Signals (`ocaml-signal`) drive dynamic props: every value prop `~p` has a
`~p_signal` twin taking an `'a Signal.signal`. `Lui_elements` re-exports
`map`, `sample`, `get`, and `>|=` (`src >|= f` for `map f src`) so view code
stays short.

Reactive structure mirrors lg's `reactive`/`:if`/`:keyed`. When a value
changes, prefer `~p_signal` — inside `map`/`sample` ordinary `if`/`match`
all work — since it updates the prop in place: `dyn f src` mounts a
re-rendering subtree for branches that change the element *structure*
(different kinds per branch); `if_ ~test el` shows/hides a single branch
without an else; `keyed ~source ~key ~compare ~mount:(row_fn send)` keeps an
identity-keyed child collection in sync (insert/remove/move patches).

Theming is scoped per subtree: `themed ~tokens ~mode el` wraps any element
with a JSON token table (`["primary", "#7c3aed"]` overrides the semantic
`primary` slot) and an optional `` `system`/`` `light`/`` `dark`` mode —
`~tokens_signal`/`~mode_signal` hot-switch either in place. Backends
resolve semantic color names through the merged token table first, then the
platform default theme, so an app gets platform-native styling unless it
opts into overrides (`Lui_app.set_theme`/`set_theme_mode` patch the mounted
root directly). See the Theming section of
`docs/agent-guide/001-production-components.md`.

## Examples

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

make test        # schema contract tests + dune @runtest
make test-ocaml  # alcotest suite only
make test-apple  # SwiftUI backend tests (macOS)
make test-mygo   # MyGo backend tests with race detection
make test-mygo-integration # actual OCaml Todos through MyGo
```

Per-platform backend builds and test recipes are documented under each
`platform/` directory (the Gradle wrapper under `platform/android` for
Android).

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
