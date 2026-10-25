# MyGo backend

`luimygo` renders LUI's retained declarative component tree with
[MyGo native UI](https://github.com/egoist/mygo). The OCaml application owns
state, reducers, subscriptions and patches. Standard portable components use
built-in adapters; `Config.Renderers` is reserved for deliberate overrides.

See the [API migration guide](../../docs/api-migrations.md) before updating an
existing application. The generated [support inventory](SUPPORT.md) lists every
component, applicable property, event, feature exception and test reference.
The [parity plan](../../docs/agent-guide/004-component-api-mygo-parity.md)
tracks remaining feature audits and desktop qualification; a built-in kind is
not by itself evidence that every property has been verified.

## Run the real applications

Requirements: Go 1.27.3 or later and the repository's OCaml/opam environment.
Linux windows need GTK3; headless text needs Pango, Cairo and installed fonts.
The module pins the [logseq/mygo compatibility branch](https://github.com/logseq/mygo/tree/eed47c5888e73c0bd722baf4d722b65ac2929143),
based on MyGo 0.6.4, for local fitting, list tuning, frame completion, overlay
anchoring and native lifecycle fixes. Go downloads it as a normal versioned
dependency; LUI does not include a copy of the third-party source tree.

From the repository root on macOS or Linux:

```sh
library=$(./tooling/build_mygo_todos.sh)
go -C platform/mygo run ./cmd/lui-mygo -library "$library"

components=$(./tooling/build_mygo_components.sh)
go -C platform/mygo run ./cmd/lui-mygo -library "$components" -title Components
```

Each application runs in its own process. The scripts build existing library
and archive targets and link the shared C bridge; they do not build the Native
OCaml renderer or alter Dune files. Windows hosts accept an equivalent OCaml DLL
built with the Windows toolchain.

For a headless image of the actual application:

```sh
go -C platform/mygo run ./cmd/lui-mygo -library "$library" \
  -screenshot /tmp/lui-mygo-todos.png -width 800 -height 600
```

## Embed a backend

```go
backend := luimygo.New(luimygo.Config{})
defer backend.Close()
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

All backend and session methods belong to the UI goroutine. Use one backend per
window, surface `Err()` failures, close the session before the backend, and
retain application model ownership of controlled values and popup visibility.
A process loads one OCaml runtime library and runs one session at a time. A later
session reuses its registered OS thread; the runtime library stays loaded.

Go hosts keep importing `github.com/egoist/mygo` and `github.com/egoist/mygo/ui`.
The fork preserves the original module identity and upstream links. The adapter
uses a pinned Go replacement to select the compatibility changes. Go does not
inherit replacements from dependency modules, so an embedding application's
root `go.mod` must select the same fork version. To develop against a local LUI
checkout from another module:

```sh
go mod edit -replace github.com/logseq/lui/platform/mygo=/path/to/lui/platform/mygo
go mod edit -replace github.com/egoist/mygo=github.com/logseq/mygo@v0.0.0-20261025154713-eed47c5888e7
go get github.com/logseq/lui/platform/mygo
go mod tidy
```

For another transport, configure `Dispatch` and call `ApplyJSON(data,false)` for
deltas or `ApplyJSON(data,true)` for an authoritative snapshot. Decoded callers
can use `ApplyBatch` and `ApplySnapshot`. The adapter validates complete final
contracts atomically, including property types, required labels, child shapes,
size bounds, popup anchors and image crops. Invalid batches preserve live UI
identity and asynchronous work.

## Components and resources

Built-in adapters cover the 87 schema kinds, including local stacked/overlay
layout, edge insets, measured fitting, controls, menus and submenus, tabs and
bottom-tab pages, trees, bounded virtual lists, rich table cells, split panes,
composites, images/media, file services and modal/anchored surfaces. Detailed
feature qualification remains tracked by the parity plan.

LUI's model supplies retained selection, menu membership and popup lifetime.
MyGo behavior bases supply native focus, keyboard interaction and accessibility.
Stable node incarnation keys preserve editors across moves. Virtualized-out rows
retain their identity; detached nodes cancel owned work immediately after commit.
Events from late row builders and fitting layouts dispatch after committed
layout, while callbacks from retired incarnations are ignored.

Image hosts call `RegisterImage(id,pixels)` or
`PresentMediaSurfaceFrame(id,pixels)` on the UI goroutine. The backend copies
caller buffers. Invalid replacements leave prior resources intact; unregister
methods or `Close()` release registrations. Canonical SVG icons are built in;
custom `app:slug` icons use `RegisterIcon(name,svg)` and `UnregisterIcon(name)`.
URI/file decoding is bounded, cancellable and incarnation-aware.

`Config.FileServices` optionally replaces the OS dialog boundary. Its default
uses native MyGo dialogs; request correlation, completion acknowledgement,
retained identity and event payloads remain backend-owned. File previews use an
owned modal with selectable UTF-8 text, images and paginated PDF rendering;
missing/unsupported files show an owned error. Native cancellation and live
host checks are release gates recorded in the parity plan.

Generic CSS transition declarations, DOM tags/classes/attributes, browser link
targets and browser referrer policies remain Web features. Typed legacy virtual
attributes retain their semantic compatibility behavior. This desktop C bridge
cannot run in a browser; the existing LUI DOM backend remains available.

## Extensions

`Config.Extensions` registers actual custom nodes by identifier, fingerprint,
scalar defaults and renderer. Renderers receive a detached `Node` snapshot, a
child builder and an emitter. Build children inside MyGo's `Children` callback;
never retain a pass-scoped `ui.Element`. Extension events use
`Event{Kind:"extension-event",Identifier:...,Name:...,Values:...}`. Standard
portable components do not require application renderer registrations.

## Reproduce tests

```sh
make test-mygo
./tooling/test_mygo.sh --unit
make test-mygo-integration
```

Unit mode checks schema freshness and runs real MyGo input/layout/pixel tests
with the race detector. It covers controlled rejection/normalization, focus,
keyboard and timed gestures, menus, local fitting, 10,000-row virtualization,
scroll tokens/ranges, resource pixels/retirement and actual PDF pages. Generated
validation is checked against more than a million actual OCaml decisions in
integration mode. Exported compiler data and oracle vectors live in temporary
directories; only generated Go source and a small integrity manifest are tracked.
Generation drift tests reject stale sources and edited output.

Integration mode requires OCaml, generates and checks the canonical oracle,
builds both application libraries, runs Todos and
Components in separate Go processes, then runs the fresh-process startup soak.
Components verifies every standard event family through real retained
subscriptions and its reducer, including UTF-8, embedded NULs and exact large
integer payloads. Todos covers real editing, actions, resync, disposal and restart.
Startup qualification preserves signal-stack/mask/handler ownership and exercises
profiling, scheduler preemption, queued signals and repeated sessions without
retrying failed processes.

Plain `go test` uses documented unit mode by skipping native suites without the
relevant library variable. Explicit commands must use separate processes:

```sh
LUI_MYGO_TEST_LIBRARY="$library" go -C platform/mygo test -race -count=1 -run '^TestOCamlTodos' .
LUI_MYGO_COMPONENTS_LIBRARY="$components" go -C platform/mygo test -race -count=1 -run '^TestOCamlComponents' .
go -C platform/mygo test -run '^$' -fuzz FuzzApplyJSON -fuzztime 30s
go -C platform/mygo vet ./...
```

Regenerate authoritative metadata after canonical API/protocol changes:

```sh
make generate-component-schema
make generate-json-view
```

The exporter links the existing compiled OCaml library and derives kind,
property, child, event and final-value rules. Full export and oracle data are
temporary build inputs. CI freshness checks use the compact committed manifest
and need no OCaml compiler. Go/race/fuzz/vet gates cover macOS, Linux and Windows; real OCaml
integration runs where the desktop OCaml toolchain is configured. Native
OCaml/Metal renderer work is outside this parity task.
