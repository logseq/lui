# MyGo backend

`luimygo` applies LUI's JSON patch protocol to [MyGo native UI](https://github.com/egoist/mygo).
The OCaml application owns the model, reducer, signals and retained tree. MyGo
provides native desktop windows, text input, accessibility and GPU rendering.
There is no HTML or JavaScript frontend.

## Run Todos

Requirements: Go 1.27.2 or later and the repository's configured OCaml/opam
environment. Linux windows also need GTK 3; headless rendering needs Pango,
Cairo and installed fonts. The module pins MyGo to commit `43c624d77fdb` and commits `go.sum`.

From the repository root on macOS or Linux:

```sh
library=$(./tooling/build_mygo_todos.sh)
go -C platform/mygo run ./cmd/lui-mygo -library "$library"
```

The build script uses the existing Todos bridge and the shared
`platform/native/lui_ocaml_bridge.c`. It does not change Dune configuration.
On Windows, pass an equivalent OCaml DLL built with your platform toolchain.

To render the actual app without a window:

```sh
go -C platform/mygo run ./cmd/lui-mygo -library "$library" \
  -screenshot /tmp/lui-mygo-todos.png -width 800 -height 600
```

## Embed a backend

```go
backend := luimygo.New(luimygo.Config{})
session, err := luimygo.OpenRuntime(libraryPath, backend)
if err != nil {
    return err
}
defer session.Close()
mygo.App.WhenReady(func() {
    mygo.NewWindow(mygo.WindowOptions{
        Title: "LUI",
        Content: ui.View(backend.View),
    })
})
return mygo.App.Run()
```

For another transport, set `Config.Dispatch` to your event sink and call
`ApplyJSON(data, false)` for deltas or `ApplyJSON(data, true)` for an authoritative
snapshot. `ApplyBatch` and `ApplySnapshot` accept decoded batches. Backend calls,
including session methods, belong to the UI goroutine. Use one backend per window.
`Err()` reports the first event delivery failure; applications should surface it.

The runtime adapter copies each callback payload and applies it after the C call
returns. All C entries run on the same permanently registered OS thread, and
callbacks never reenter OCaml. A rejected delta requests an authoritative snapshot.
A process can load one OCaml runtime library and run one session at a time; closing
a session disposes its app, and a later session reuses the registered thread.
The library stays loaded because OCaml domains and callbacks outlive the app.

## Components and extension points

The current implementation is partial. The
[MyGo capability and parity report](../../docs/agent-guide/003-mygo-capabilities_report.md)
accounts for all 87 standard node kinds, distinguishes current mappings from
complete behavior, and records source findings and reproducible probes.
The target is built-in support for all portable LUI components; application
renderers are an extension point, not the intended solution for missing standard
components.
The [component API and parity implementation plan](../../docs/agent-guide/004-component-api-mygo-parity.md)
defines API improvements, feature-level platform exceptions, implementation
phases and behavior-based completion gates.

`SupportedKinds()` returns the built-in kind list. The backend provides rows,
columns, grids, surfaces, typography, buttons and groups, text/password/multiline
fields, toggles, checkboxes, radios, switches, sliders, number steppers, progress,
scroll containers, lists, model-owned picker triggers, accordions and modal
surfaces. Layout supports dimensions, constraints, spacing, alignment, wrapping,
borders, colors, opacity and typography. Theme tokens merge per subtree, including
adaptive light/dark values; colors accept hex values or semantic/token names.

Select triggers and combobox text input send events to OCaml. The app determines
which retained menu nodes to mount. Modal lifetime is likewise model-owned:
dismissal sends an event, and the reducer removes the surface.

This backend does not yet provide every specialized LUI component or every
web styling property. Virtual lists, images, icons, media surfaces, file pickers,
anchored popovers/menus, split panes, layered layouts and specialized composite
components require an application renderer. Such kinds are rejected with the
missing registration in the error; they are not silently dropped. Register a
`Config.Renderers[kind]` function to implement them with MyGo. Platform-specific
CSS effects and web attributes are retained but do not affect native rendering.

`Config.Extensions` registers custom nodes by identifier, fingerprint, default
scalar properties and `Renderer`. A renderer receives a detached `Node` snapshot,
a function that mounts retained children, and an event emitter. Call `children`
inside the MyGo container's `Children` callback. Keys are assigned before control
construction, preserving editor/focus identity during moves. Events emitted while
building are delivered after construction. Extension events use
`Event{Kind: "extension-event", Identifier: ..., Name: ..., Values: ...}`.

## Tests

```sh
make test-mygo               # schema drift check and Go tests with race detection
make test-mygo-integration   # build actual OCaml Todos and run all tests with races
```

The suite tests batch rollback, all eleven patch operations, generation gaps,
snapshot recovery, malformed wire data, precise 64-bit IDs, subtree removal,
extensions, a 10,000-node tree and every built-in kind in MyGo's software renderer.
Interaction tests drive real pointer and keyboard input, Unicode editing, disabled
controls, modifier keys, model-owned pickers, focus preservation, theme scopes and
modal dismissal. The integration test runs the real OCaml reducer through the C ABI,
including automatic resync, disposal and restart. Plain `go test` skips that one
test unless `LUI_MYGO_TEST_LIBRARY` points to the Todos shared library.

```sh
cd platform/mygo
go test -run '^$' -fuzz FuzzApplyJSON -fuzztime 10s
go vet ./...
```

Regenerate wire-name and scalar-type tables after schema/protocol changes:

```sh
python3 tooling/generate_mygo_schema.py
```

CI checks generated-table freshness and runs the Go suite on macOS, Linux and
Windows. A separate macOS job builds and tests the OCaml integration.
