# Controlled NavigationStack

The API is available as `Lui.Navigation` / `Lui_navigation`:

```ocaml
type route = Block of int
let view _context model_source send =
  Lui.Navigation.navigation_stack
    ~key:"main-navigation"
    ~path_signal:model_source
    ~on_path_change:(fun path -> ignore (send path))
    ~destination:(fun entry ->
      let Block id = entry.route in
      Lui.Elements.text ~value:(string_of_int id) [])
    ~root:timeline ()
```

Mount the navigation component once. Subscribe individual parts of root or
entries to their own data signals. Wrapping the complete navigation component
in a `dyn` over every model change still requests an enclosing view remount;
the navigation component cannot prevent its owner from rebuilding it.

`Path.empty` is polymorphic. `push route path` allocates an entry ID; equal
routes pushed twice are distinct entries. A path is immutable, and pushing onto
a saved earlier path allocates another ID. `pop empty` and `pop_to_root empty`
are harmless. `entries` returns root-to-top order; the root is outside this
list. `push`/`pop` are O(1); `entries` is O(depth). IDs are process-local,
created on the UI scheduler; persist business routes, rather than entry IDs.
Routes can contain functions and never need a JSON encoder.

For Apple, add `Lui_navigation.register_into registry` before creating the
OCaml app with `Lui_app.create_with_extensions`. On the Swift side, call
`try LUINavigation.register(in: registry)` before passing that registry to
`LUIAppleBackend`. An app without other extensions can use
`Lui_navigation.registry ()` on the OCaml side.

The caller owns the authoritative path. A completed native back action
proposes a shorter path through `on_path_change`. The caller can accept,
reject, or synchronously replace it. Every reply has a fresh internal revision,
including rejection. Queued owner writes are stabilized before accepting a
host event, so an old graph/path revision cannot overwrite a new one.
Programmatic path changes never invoke `on_path_change`.

Root and covered entries keep their LUI nodes, render scopes, subscriptions,
and separate `ui_state_scope` / `state_at` slots. Apple keeps removed entries
until the host reports settlement of the current revision, so outgoing views
have content during the transition. Reintroducing the same saved entry before
settlement reuses that subtree. A matching settlement disposes only removed
entries and their state registry paths; component teardown disposes everything.
`onDisappear` never disposes LUI scopes. UIKit transition completion checks
cancellation; a cancelled pop produces no path proposal. SwiftUI may recompute
`body` or recreate internal native objects; this API does not promise otherwise.

Other hosts use a standard Column/Stack plus Back button, with no transition
animation or system/browser history integration. Covered page nodes are
detached from the visible slot but remain in the LUI runtime with live scopes,
subscriptions and OCaml local state. Popped pages dispose immediately. A host
may recreate its visible widget when the page is reattached, so native widget
state and scroll position need platform-specific verification. Web/Flutter/Qt/
WinUI do not yet have native navigation extension renderers.

## Independent iOS Simulator demo

```sh
bash examples/navigation/build-ios-simulator.sh
xcrun simctl install <simulator-udid> _build/navigation-demo/NavigationDemo.app
xcrun simctl launch --console-pty <simulator-udid> com.logseq.lui.navigation.demo
```

The app shows 300 rows in an actual LUI native List, with a root local counter
and per-entry detail counter. Scroll deep into the list, increment root, open
a detail, increment its local state, edit the covered root counter/row, push
the same route again, then return. Check root mount count and row/scroll anchor,
plus native Back, programmatic pop, pop-to-root and cancelled/completed edge
swipes. Its console logs root/detail mounts/disposal, host revision events and
patch counts. Build products are under ignored `_build/navigation-demo`.
Keep screenshots, recordings and run reports outside the Git worktree.

This build follows the existing components demo's arm64 macOS OCaml-object
restamping route. It is Simulator-only; it is not a device toolchain or phone
installation path. No dune files are changed.

## Regression commands

```sh
opam exec -- dune exec test/test_lui.exe -- test navigation
opam exec -- dune build @all
opam exec -- dune runtest
swift test
swift build --package-path platform/apple --target LUIAppleBackend \
  --triple arm64-apple-ios17.0-simulator --sdk "$(xcrun --sdk iphonesimulator --show-sdk-path)"
node --test tooling/test/*.mjs
```

The OCaml navigation tests cover branch identity, polymorphic empty, duplicate
routes, root/covered subscriptions and state slots, cleanup, native back,
synchronous replacement/rejection, invalid/echo/stale callbacks, queued graph
switches, rapid push/pop and fallback lifecycle. Swift tests cover cancellation,
proposal deduplication and synchronous/new-revision replacement. These tests do
not by themselves prove real native List scroll or interactive gesture behavior.
