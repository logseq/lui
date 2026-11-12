# LUI API migration guide

## NSH coalesces pending virtual-list range feedback

NSH now keeps the latest pending visible range independently from the latest
pending virtual-row demand for each list. Fast scrolling no longer fills the
ordinary input queue with superseded range notifications. A delayed notification
is discarded when its list incarnation or virtual-source generation retires.
The wire fields and range boundaries are unchanged, including the empty-range
representation. Scroll-token completion events and accepted ordinary input keep
their existing ordered queue; they are not coalesced with range feedback.

Range handlers must treat notifications as current viewport state, rather than
counting them as scroll steps. For example, replace a counter increment in
`~on_visible_range` with assignment of the received range to application state.
Intermediate ranges may be superseded before OCaml consumes them; the final
pending range and row demand remain independently deliverable even if the user
queue is full. Apple/iOS, Android and Web delivery behavior is unchanged.

## NSH Link children suppress the implicit URL label

A Link with authored children and no explicit text now displays only those
children. The URL is used as a fallback label only when both text and children
are absent. This preserves URL-only links while avoiding a visible `#` beside
icon-only internal links, including Logseq outline disclosure controls.

For example, `link ~url:"#" [icon ...]` now renders its icon alone;
`link ~url:"https://example.org" []` still displays its destination. Explicit
text remains visible alongside children. Native activation, modifier details and
retained child identity are unchanged. Other backends are unchanged.

## NSH agent queries reject retained content after renderer failure

The NSH host now rejects semantic queries and interactions while its existing
renderer failure diagnostic is present, including `find`, `tree`, `prop`,
`native-bounds` and `native-press`. Checks run before dispatch and after reply
publication, so both an existing failure and a rejection in the current reply
produce `{ "ok": false, "error": "<original backend failure and recovery context>" }`.
Retained semantic nodes alone no longer establish successful native startup.
No new status controller or error cache is introduced.

`hello` and macOS `screenshot` remain available for diagnosis. Their successful
responses gain an optional `backend_error` string containing that same diagnostic;
existing handshake fields and PNG data are preserved. For example, a script that
previously treated `find` returning a Journal node as readiness must stop when
`ok` is false, then use `hello` and `screenshot` to collect failure evidence.
A successful diagnostic capture with `backend_error` is not a healthy app result.
Healthy replies and the Apple/iOS, Android and Web agent paths are unchanged.

## NSH relative font sizes use native text inheritance

The NSH backend now accepts every finite nonnegative `em` font-size ratio,
including `~font_size:"0.5em"` and `~font_size:"1.5em"`; these previously failed
at runtime unless the ratio was exactly one. The existing wire field stays
`font-size`. A node scales its actual NSH parent's resolved font size, including
native heading/control typography, before its own line height is resolved.
Nested explicit ratios multiply; descendants without a font size inherit the
computed points once. Parent updates recompute through NSH's existing retained
text pipeline.

For example, a `20px` container with a `1.5em` child and `0.5em` grandchild
resolves to 30pt and 15pt. Updating that container to `32px` yields 48pt and 24pt
without replacing either node. `1em` retains its existing inherited meaning,
and point/`px`/`rem` values retain their existing meaning. Apple/iOS, Android and
Web adapters are unchanged. Downstream applications need the updated pinned
NSH fork for this additive typed style capability; no LUI call-site migration
is required. Invalid, nonfinite and negative dynamic ratios are still rejected
atomically before a batch publishes.

## Virtual lists can use the surrounding NSH Scroll viewport

`Lui_elements.virtual_list` adds `?viewport:virtual_viewport`, where
`virtual_viewport = [ \`own | \`parent ]`. Omission preserves the existing owned
scroll viewport on every backend. NSH also supports `~viewport:\`parent` through
the public native `ListViewport::Parent` builder: the list keeps its complete
logical extent while rendering only rows requested by its surrounding Scroll.
This lets headers, multiple lists and other content share one scroll owner.

For example, migrate an eager collection inside an existing Scroll to:

```ocaml
scroll [
  text ~value:"Journal" [];
  virtual_list ~viewport:`parent ~item_extent:32. [
    virtual_rows ~source:rows ~key:(fun row -> row.id) ~cmp:String.compare
      ~mount:render_row ()
  ]
]
```

The append-only `VirtualViewport` property encodes as `virtual-viewport`, with
closed string values `own` and `parent`; absence means `own`. Parent ownership
currently requires NSH. Other host constructors and raw runtime property writes
reject `parent` explicitly before publishing it; existing Web, Apple/iOS and
Android callers need no changes. Use a matching updated NSH provider when opting
in; older providers reject this unknown wire property.

Updated Apple/iOS and Android providers accept explicit `virtual-viewport` value
`"own"` only on `VirtualList`, preserving their existing scroll owner and retained
rows. They reject `"parent"`, malformed raw values and viewport properties on
other kinds atomically. This also applies to raw wire clients: omit the property
or send `"own"` when targeting these maintained backends.

The generated JSON-view facade accepts either `viewport` or `virtual-viewport`.
Identical aliases are allowed; conflicting aliases, nonstring values and unknown
ownership names fail explicitly instead of silently selecting the default.

Viewport ownership is fixed for a retained list's lifetime. There is no signal
argument. Replace the keyed list node to change ownership. NSH rejects changes
between `own` and `parent`, including removing `parent`, atomically without
advancing the batch generation or disturbing existing row identities. Adding or
removing explicit `own` preserves the same default and remains valid. Visible
range, sparse row demand, active pins and scroll-token outcomes continue through
their existing ordered feedback paths, even while new user input is fenced.

Parent lists observe end/drag feedback and measure the viewport of their nearest
compatible native Scroll, canonical List or owned VirtualList. A farther
ancestor's end cannot finish the token, and user dragging cancels it once. A
compatible vertical owner must exist inside the selected application's native
surface; lookup stops at the selected root and modal/popup boundaries. Invalid
root selection or mounted reparenting fails before publication. Detached
subtrees may be staged and repaired before attachment. The adapter adds no
second scroll controller, viewport model or per-row visibility cache.

## Unreleased: NSH desktop migration (in progress)

The desktop implementation is moving from MyGo to a Rust-only NSH host.
Apple/iOS, Android and Web remain maintained. The NSH adapter is currently
experimental: real OCaml Todos input, keyed updates and application restart
are exercised, including a dedicated bounded-row fixture. Full component
parity, production bounded-row negotiation and delivery qualification are
still pending. Unsupported components are rejected before
their batch is published instead of rendering an empty generic view.

The desktop profile constructor changes from `MyGoHost` to `NshHost`, and its
serialized host name changes from `"mygo"` to `"nsh"`. Update exhaustive matches
and extension host registrations:

```ocaml
(* Before *)
let desktop = function MyGoHost -> true | _ -> false
(* After *)
let desktop = function NshHost -> true | _ -> false
```

Native host code `6` identifies NSH. MyGo code `5` is not reused and resolves
to the generic profile in a new library. SwiftUI `2`/`258`, Kotlin `4`/`260`
and operating-system codes retain their meanings. NSH bounded-row negotiation
remains disabled until negotiation and required native qualification are
complete. The experimental renderer accepts eager `virtual-list` children;
the real OCaml sparse-list fixture explicitly enables bounded rows for its
1,000/100,000-item qualification. Applications must not assume that using this
host code alone enables production sparse mounting.
Ordinary batch operations, event ordinals and the mobile bridge ABI are unchanged.

The renamed native application build commands are:

```sh
bash tooling/build_nsh_todos.sh
bash tooling/build_nsh_components.sh
```

To run an application with the experimental NSH desktop shell:

```sh
LUI_OCAML_LIBRARY="$(bash tooling/build_nsh_todos.sh)" \
  cargo run --manifest-path platform/nsh/Cargo.toml
```

The loader resolves this explicitly selected library, or, in a package,
`Contents/Resources/lui/liblui_app.dylib` on macOS,
`lui/lui_app.dll` beside the Windows executable, or `lui/liblui_app.so` beside
the Linux executable. The initialized OCaml library stays loaded for the
process lifetime. One process supports one loaded OCaml library and one active
application session; close/reopen reuses its persistent runtime worker.
On Windows, private dependent DLLs beside `lui_app.dll` are resolved through
per-load DLL search flags; the host does not change the process-wide search
path or working directory.

Input requests are serialized without blocking the NSH engine or platform UI
thread. The input/clock wake channel is bounded to 64 entries; overflow reports
an explicit backend error rather than silently discarding an edit. A refused
OCaml event returns its diagnostic and an authoritative snapshot before later
requests are published. Snapshot generation may equal or exceed the last
accepted delta; older snapshots are rejected without changing committed state.
Ordinary deltas must be sequential. Programmatic value synchronization never
emits another user edit event.

Missing wire `generation` defaults to zero and missing `ops` to an empty list,
as in the shared decoder; generation zero still cannot commit a transaction.
Unknown fields remain forward compatible. NSH rejects duplicate recognized
batch/operation fields instead of the former Go decoder's last-field rule;
canonical LUI encoders never emit duplicates. Raw producers must emit, for
example, `{"generation":3,"ops":[]}` once, rather than repeating `generation`
inside one object. Both node IDs and committed generations stay within the
native 64-bit OCaml integer domain (at most `2^62 - 1`), including snapshots; an oversized
snapshot cannot replace the accepted store.

Queued callbacks retain their original node incarnation and are checked again
before dispatch. A stale edit after snapshot replacement or node recreation
does not reach the new node. Internal virtual-window requests keep only the
latest request per list; they do not consume one queue entry per demanded cell.
The pump checks source generation before sending them and drains pending
windows even when the wake channel was full. Public visible-range callbacks
retain their ordinary event ordering. Local batch-validation failures recover
through an authoritative snapshot on the same pump before later events run.

An eager virtual list resolves `scroll-target` against the current direct
children's `key` values. `nearest` alignment uses measured native row and list
geometry: an already visible row completes successfully without starting an
animation, while a clipped row scrolls through NSH's native index API. An
issued animated scroll completes successfully only after the native scroll-end
event; target materialization alone is insufficient. Each token produces at
most one completion, and missing targets or user cancellation retain their
explicit outcomes. For example, moving a keyed row before changing its token
resolves the new child position instead of a cached index.

The experimental Rust retained store exposes `Node.children` as
`Arc<Vec<u64>>`. Read it with `.iter()` or `.as_slice()`; submit structural
changes through patch operations. Property-only updates share the existing
sequence and do not copy or republish every child identity.

`contract::validate_value` and `contract::validate_node` now enforce the full
canonical value domains, required properties, cross-property invariants and
sparse metadata/children relationship. Integer comparisons remain exact above
`2^53`; integer JSON syntax is normalized to a floating scalar only for
properties whose canonical type permits floats and not integers. Invalid
transactions leave the accepted tree and generation unchanged. NSH additionally
rejects virtual sources above `u32::MAX`, the native list count limit.
`contract::property_supported` and `event_supported` expose canonical metadata
queries. `contract::CONTRACT` contains metadata only: development-only validator
AST, presence trees and oracle data are no longer shipped. Use the validation
functions instead of inspecting those removed development fields.

The optional desktop agent uses the existing `lui-agent` JSON-line protocol:

```sh
LUI_AGENT_LISTEN=127.0.0.1:49380 \
  LUI_OCAML_LIBRARY="$(bash tooling/build_nsh_todos.sh)" \
  cargo run --manifest-path platform/nsh/Cargo.toml
```

Rust embedders can set `DesktopProps.agent_listen` instead. An empty value reads
the environment; when both are empty no listener is started. Only numeric
loopback addresses are accepted. Requests are limited to 1 MiB per line and
share the ordered application pump with input and clock work. Patches are
published before a reply; transport/queue failures return `ok:false` with an
error. Closing the surface closes its active agent connection.

Desktop delivery commands now use an immutable CLI build receipt and verify
the actual application/generated-runner dependency graphs:

```sh
python3 tooling/nsh_delivery.py setup --checkout ../nsh
python3 tooling/nsh_delivery.py package --library /path/to/liblui_app.dylib \
  --output _build/nsh-packages
```

Use `manifest` to sign a whole-application update from completed package
receipts. Intermediate NSH archives, code-only payloads and stale receipts are
not eligible. The delivery wrapper rebuilds archives after adding the OCaml
library, resources and signatures. See [delivery](../platform/nsh/DELIVERY.md)
for architecture checks, signing/notarization parameters and verification limits.

Rust applications can use `update::Updater::open(config, executable, cache)`,
then asynchronous `check`, `download` and `install` with opaque `Offer` and
`Downloaded` values. `progress()` returns a coalesced watch subscription;
`cancel()` invalidates pending downloads. One persistent worker streams each
archive through one HTTP client. Updates require authenticated signed metadata,
HTTPS and matching app/platform/version/size/hash checks; limits are 1 MiB for
metadata, 4 KiB for signatures and 2 GiB for an archive. Installation rechecks
the archive and uses NSH's whole-application installer. Restart is owned by the
embedding app, and cancellation cannot interrupt installation once it begins.
The standalone runner now uses the additive `DesktopApp` Rust root (and
`"root": "DesktopApp"` in `nsh.json`). `Desktop` and `DesktopProps` remain
available for embedding, where the host keeps its application menus.
`DesktopApp` discovers only the matching installed `nsh-updater.json` asset.
With no asset it creates no update worker, cache, network request or menu.
Configured packages gain native check, cancel, download and install/restart
actions while retaining standard edit/window menu roles. Installation requires
an explicit confirmation and requests NSH restart only after replacement
succeeds. Full configured-menu and packaged LUI upgrade qualification is still
pending; declaring an updater URL alone is not evidence of a working release.

Rust embedders can call `update::Updater::from_installed(executable, cache)` to
discover the same optional configuration. It returns `Ok(None)` when the asset
is absent and rejects invalid or mismatching installed configuration.
`Downloaded` tokens support equality by issuing updater and offer ticket; their
fields remain private and a foreign/stale token still cannot install.

Native Windows/Linux package execution, compiled LUI upgrade fixtures and
credentialed distribution signing remain qualification gates. Local ad hoc
signing and compiled native update fixtures do not establish those results.
Existing historical MyGo examples below describe the previous implementation.

## Unreleased: native navigation sheet action foregrounds

Apple navigation sheet toolbar actions honor the button's existing `foreground`
property. For example, set `button ~style_class:"confirmation-action"
~foreground:"foreground" ~text:"Done" []` to use the current semantic foreground
for the title. The native toolbar placement, styling and disabled behavior stay
in effect. With no resolvable explicit foreground, the system default remains.
No wire-format or handler changes are required.

## Unreleased: shared iOS input surface

Standalone iOS text, secure, search, and combo box inputs use a padded field
with a semantic fill and a visible focus outline. Grouped text controls, native
form rows, multiline editors, and other backends keep their existing rendering.
The wire schema, edit events, and focus behavior are unchanged.

The fill resolves `input`, `surface`, then `muted` before the system fallback.
The focus outline resolves `input-focus`, then `primary` before the system
accent. Native SwiftUI extensions can use the same surface without changing
their own keyboard or submission configuration:

```swift
TextField("Email address", text: $email)
    .keyboardType(.emailAddress)
    .focused($focused)
    .luiInputSurface(isFocused: focused)
```

## Unreleased: one lui-agent protocol on every host

Scripts and coding agents can now drive a running app the same way on MyGo,
Apple, Android and Web. The shared OCaml runtime answers every request, so
each host only carries strings.

A request is one flat JSON object with an `op`. The reply is one JSON object
with `ok`:

```json
{"op":"press","selector":"prop:accessibility-identifier=save"}
{"ok":true,"op":"press","node":42}
```

The protocol has these parts:

- **Ops.** `hello`, `tree`, `dump`, `find`, `prop`, `press`, `long-press`,
  `double-press`, `submit`, `dismiss`, `appear`, `change`, `type`, `toggle`,
  `value`, `key` and `ext`. `hello` reports `protocol` (`"lui-agent"`),
  `version` (`1`), `host`, `generation` and `ops`.
- **Selectors.** They use the Drive scenario grammar: `id:N`, `kind:name`,
  `ext:identifier`, `text:needle`, `prop:name=value` and `prop:name=prefix*`,
  joined with `&`. A bare number is an id and a bare word is a text needle.
- **Gestures.** `press`, `long-press` and `double-press` go to the nearest
  ancestor that handles them. Every other action requires the selected node
  itself to handle the event.
- **Rejected requests.** A malformed request, unknown op, missing node or
  unsupported event gets `{"ok":false,"error":...}` and changes nothing.
- **Refused requests.** If an application handler raises, the call is refused
  in phase `agent`, the same way a refused native event is. Hosts answer
  `{"ok":false,"refused":true,"error":...,"diagnostic":{...}}`.
- **Patches.** An action's patch batches reach the host's normal patch path
  before the reply.
- **Clock.** An action may arm or cancel application-clock timers, so every
  native host re-reads the clock's next delay after each agent request, as it
  does after an event.

The new APIs, by layer:

- **OCaml.** `Lui_agent.handle`, `Lui_agent.app_target` and `Lui_agent.target`.
  `Lui_native_bridge.agent bridge request` answers through a started bridge,
  and `register` adds `<prefix>_agent` (for example `lui_kotlin_agent`).
- **C ABI.** Two new exports:

  ```c
  int32_t lui_ocaml_agent_utf8(const char *request, int32_t length,
                               void (*reply)(const char *json));
  int32_t lui_ocaml_agent(const char *request, void (*reply)(const char *json));
  ```

  Both return `1` when answered, including `{"ok":false}` replies. They return
  `0` when refused; in that case read `lui_ocaml_last_error` and resync as
  after any refused call. The batches go to the patch callback given to
  `lui_ocaml_start`, then `reply` receives the reply object.
- **MyGo.** `(*Runtime).Agent(request) (string, error)` applies the batches and
  resyncs after a refusal. `ServeAgent(address, onUI)` and
  `ServeAgentFromEnv(onUI)` serve one loopback TCP client, one line per
  request, with lines capped at 1 MiB. `cmd/lui-mygo` listens when
  `LUI_AGENT_LISTEN=127.0.0.1:PORT` is set.

  ```go
  server, err := runtime.ServeAgentFromEnv(func(fn func()) {
      mygo.RunOnMain(func() { fn(); window.Invalidate() })
  })
  ```

- **Android.**
  - `LuiBridge.agent(request): String` blocks until the OCaml thread answers
    and queues the batches for the sink.
  - The JNI library exports `nativeAgent`.
  - `LuiAgentServer.start(port, answer)` serves the same line protocol on loopback. `answer` defaults to `LuiBridge.agent`.
  - The Components app starts it only in debug builds launched with
    `--ei lui-agent-port PORT`. The debug manifest adds `INTERNET`.
    Reach it with `adb forward tcp:PORT tcp:PORT`.

  ```kotlin
  val server = LuiAgentServer.start(port = 49380)  // after LuiBridge.start
  ```

- **Apple.**
  - `LUINativeAgent(library:recovery:)` (or `init(agent:recovery:)` with an
    `@_silgen_name` closure) answers requests and recovers refusals.
  - `LUIAgentServer.startFromEnvironment(answer:)` serves loopback TCP on the
    main queue when `LUI_AGENT_LISTEN` is set.
  - `LUINativeRefusalRecovery.recover(_:)` is `check(_:)` returning the
    failure.
  - The Todos, Split, Markdown, Components and Navigation hosts start the
    server in DEBUG builds. On the simulator, pass
    `SIMCTL_CHILD_LUI_AGENT_LISTEN=127.0.0.1:PORT` to `simctl launch`.

  ```swift
  let agent = LUINativeAgent(library: handle, recovery: recovery)
  agentServer = try LUIAgentServer.startFromEnvironment { agent.answer($0) }
  ```

- **Web.**
  - `Lui_web_agent.install target` sets `window.__luiAgent`.
  - When the page URL carries `?lui-agent=ws://127.0.0.1:PORT` (or
    `ws://localhost:PORT`), it dials that socket and answers each text frame.
    Other hosts are ignored.
  - A raising handler is answered as a refusal rather than thrown.
  - The Components and Chat pages install it.

  ```ocaml
  Lui_web_agent.install (Lui_agent.app_target ~host:"web" app)
  ```

### Refusing to drive a stale build

`tooling/lui_agent.mjs` is the client for every host. It accepts
`--tcp HOST:PORT` or `--ws-listen PORT`, and runs Drive-vocabulary script lines
(`press`, `type`, `toggle`, `expect`, `wait`, `expect-prop`, `dump`, …),
reporting every failing line.

The build scripts now write `<artifact>.lui-build.json`. It holds the
artifact digest and the sha256 of every input file. The scripts that write it
are:

- the MyGo Todos and Components builds;
- the Android and iOS Components builds;
- the Navigation simulator build;
- the macOS `build-app.sh` scripts;
- `build_web_release.mjs`.

`--artifact PATH` refuses to drive a build whose receipt is missing, or whose
artifact or inputs changed. It names the command that rebuilds it and exits
with code `3`. `--unchecked` skips the check. `node tooling/lui_build_receipt.mjs
check --artifact PATH` runs the check alone.

```sh
components=$(./tooling/build_mygo_components.sh)
LUI_AGENT_LISTEN=127.0.0.1:49380 go -C platform/mygo run ./cmd/lui-mygo -library "$components" &
node tooling/lui_agent.mjs --tcp 127.0.0.1:49380 --artifact "$components" \
  'press prop:accessibility-identifier=events-button' 'expect "text:Event: press"'
```

### Compatibility

Every server is opt-in and listens on loopback only, so apps that do not set
`LUI_AGENT_LISTEN`, pass the Android extra or call `install` behave as before.

The wire format, events and existing exports are unchanged. Hosts that load
the library with `dlopen` resolve `lui_ocaml_agent_utf8` optionally; a
`LUINativeAgent` without it answers every request with an error.

## Unreleased: wire batches skip unknown nested fields

`Lui_wire.decode_batch` still rejects malformed tokens, unknown operations,
unknown node kinds, and unknown properties. Extra object fields — on the
batch or on an operation — are now ignored when their names are not part of
the operation schema, including nested objects, arrays, and null. Previously
only extra scalars were skipped, so a newer encoder's object field failed
the OCaml decoder while MyGo accepted it.

Canonical encoder bytes are unchanged. Required fields stay scalars:
`"value": {"nested": true}` is still rejected. Duplicate keys are unchanged
(the first operation field wins; the last `generation` wins). Hosts that
want the MyGo duplicate-key rule should not emit duplicate keys; the shared
fixtures use unique keys.

```ocaml
let batch =
  Lui_wire.decode_batch
    {|{"schemaVersion":1,"meta":{"nested":[1]},"generation":1,"ops":[{"op":"drop-node","id":1,"trace":{"ok":true}}]}|}
(* generation = 1, ops = [DropNode 1] *)
```

## Unreleased: controllable application clock

Views schedule time-based work with `Lui_ui.after context ms action` and
`Lui_ui.every context ms action`. Both return a `Lui_clock.timer`, run on the
application's `Lui_clock.t` (`Lui_app.clock app`) and are cancelled when the
owning view scope is disposed; `Lui_clock.cancel` stops one earlier. Actions run
on the runtime thread like event handlers, so they may `send` directly:

```ocaml
let upload_button send : t =
  scoped (fun context ->
    let timer = ref None in
    button ~text:"Simulate upload"
      ~on_press:(fun _ ->
        Option.iter Lui_clock.cancel !timer;
        timer := Some (Lui_ui.every context 300. (fun () ->
          ignore (send Advance))))
      [])
```

Replace host-side `setTimeout`/`DispatchQueue`/`Handler` loops that only feed
actions back into the model with these timers: they become deterministic under
Drive and tests. Existing apps need no changes; a clock without timers costs
nothing and never wakes a host.

Time is in milliseconds (float). Host time only moves forward; the first
`Lui_clock.tick` anchors the clock without firing anything. `Lui_clock.pause`
makes host ticks no-ops, `Lui_clock.advance clock ms` moves simulated time and
fires due timers even while paused, and `Lui_clock.settle` fires every pending
timer (raising after 10,000 firings to stop runaway `every` loops). Time cannot
move from inside a timer action (`Invalid_argument`).

Host contract, implemented by every maintained host in this release:

- Native C ABI: new exports `lui_ocaml_clock_tick(double now_ms)`,
  `lui_ocaml_clock_advance(double ms)`, `lui_ocaml_clock_set_paused(int32_t)`
  and `double lui_ocaml_clock_next_delay(void)` (negative when nothing is due,
  paused or not started). After every call into the runtime the host reads
  `next_delay`, arms one wakeup and calls `clock_tick` with monotonic
  milliseconds when it fires. Bridges built with `Lui_native_bridge.register`
  get the OCaml side automatically.
- MyGo: `OpenRuntime` binds the four symbols when all are present (older
  libraries keep working without timers), arms a `time.AfterFunc` that only
  invalidates the window and ticks in the next frame. New
  `Runtime.AdvanceClock(ms)` and `Runtime.SetClockPaused(bool)`.
- Android: `LuiBridge` reschedules a `Handler.postAtTime` wakeup on the
  `lui-ocaml` thread after every dispatch, ticking with
  `SystemClock.uptimeMillis()`. New JNI exports `nativeClockTick`,
  `nativeClockAdvance`, `nativeClockSetPaused`, `nativeClockNextDelay` and
  public `LuiBridge.advanceClock(ms)` / `LuiBridge.setClockPaused(paused)`.
  Custom JNI libraries must compile the updated `lui_jni_bridge.c`.
- Apple: new `LUIRuntimeClock` in `LUIAppleBackend`. Create it with
  `LUIRuntimeClock(library: handle)` for `dlopen` hosts or
  `LUIRuntimeClock(tick:nextDelay:)` with `@_silgen_name` functions, call
  `reschedule()` after starting the runtime and after every runtime call
  (typically `defer { clock.reschedule() }` at the top of `backend.onEvent`),
  and `cancel()` before `lui_ocaml_stop`:

  ```swift
  let clock = LUIRuntimeClock(library: handle)
  backend.onEvent = { event in
      defer { clock.reschedule() }
      // existing dispatch
  }
  ```

- Web/Melange: call `Lui_web.drive_clock app` once after `Lui_app.start`. It
  ticks from `performance.now()` with one armed timeout and flushes after each
  tick, using the new `Lui_clock.set_wakeup` hook.
- A timer action that raises is a refused call with phase `clock`: every
  native host routes tick results through its existing refusal recovery
  (diagnostic plus resync), exactly as for a refused event.
- In-process apps (tests, custom hosts) call `Lui_app.tick_clock app ~now` or
  `Lui_app.advance_clock app ms`, then `Lui_app.flush`, or register a
  `Lui_clock.set_wakeup` callback.

Drive scenarios gain `clock pause`, `clock resume`, `clock advance <duration>`
(`250`, `250ms`, `1.5s`) and `clock settle`. In-process sessions support all
four; FFI targets support all but `settle` and report the missing exports for
libraries built before this release; live websocket targets report the
command as unsupported.

## Unreleased: native bridge reports refused calls

When OCaml raises while a native bridge boots, dispatches an event, resyncs or
disposes, the C entry still returns `0` and delivers no batch. The bridge now
also records a diagnostic, and the new export returns it:

```c
int32_t lui_ocaml_last_error(void (*receiver)(const char *json));
```

It hands `receiver` one JSON object, clears it, and returns `1`; it returns `0`
when no diagnostic is pending. A later accepted call also clears it.

```json
{"bridge":"Todos","phase":"dispatch","node":42,
 "message":"invalid property value ...","recovery":"resync"}
```

`phase` is `boot`, `dispatch`, `resync` or `dispose`; `node` is present for a
dispatch. Batches recorded before the exception are discarded, so the host
mirror is stale: report the message, then call `lui_ocaml_resync` and apply its
snapshot rather than keep rendering what mounted before the throw. The bridge
still prints the exception to stderr.

The wire format, existing exports and return codes are unchanged. A host that
does not adopt the export keeps its old behavior. Resolve the symbol
optionally to stay compatible with older libraries. A `0` without a pending
diagnostic is argument validation in C, which records no patches and needs no
resync. OCaml callers can read the same record with
`Lui_native_bridge.last_failure` and `take_failure`. Bridges registered with
`Lui_native_bridge.register` gain `<prefix>_last_error` automatically, so
`lui_kotlin_last_error` exists for JNI.

Every maintained host now consumes it:

- **MyGo**: `Runtime.Dispatch` returns a `*luimygo.RuntimeError` (`Phase`,
  `Node`, `Message`) and resyncs before returning. Initialization failures
  wrap the same error.

  ```go
  var failure *luimygo.RuntimeError
  if errors.As(runtime.Dispatch(event), &failure) {
      log.Printf("LUI %s failed at node %v: %s", failure.Phase, failure.Node, failure.Message)
  }
  ```

- **Android**: `LuiBridge` logs the failure, requests a snapshot through the
  existing resync path and notifies the optional `LuiBridge.failureListener` on
  the main thread with a `LuiRuntimeFailure`. A failed `start` reports its
  diagnostic the same way. The JNI library exports `nativeLastError()`.

  ```kotlin
  LuiBridge.failureListener = LuiBridge.FailureListener { failure ->
      showError("${failure.phase} failed: ${failure.message}")
  }
  ```

- **Apple**: `LUIAppleBackend.applySnapshot(json:)` replaces the retained tree
  with a `lui_ocaml_resync` batch. `apply(json:)` drops that batch as stale
  because it reuses the current generation. `LUINativeRefusalRecovery` wraps the
  two exports for hosts that load the C ABI themselves, and the Todos, Split,
  Markdown, Components and Navigation hosts use it. Hosts that resync outside
  this helper must use `applySnapshot` as well.

  ```swift
  let recovery = LUINativeRefusalRecovery(library: handle)  // or closures over @_silgen_name exports
  recovery.check(pressFunction(Int64(node)))

  func apply(json: String) throws {
      if recovery.isReceivingSnapshot {
          try backend.applySnapshot(json: json)
      } else {
          try backend.apply(json: json)
      }
  }
  ```

- **Drive**: the FFI driver fails the scenario line with the diagnostic, for
  example `target refused dispatch at node #1: …`, and rebuilds its model from
  a resync snapshot. `Drive.Model.clear` empties a model before a snapshot.

- **Web/Melange** runs OCaml in-process and has no C boundary. Exceptions
  still surface as uncaught JavaScript errors and no patches are dropped, so
  nothing changes there.

## Unreleased: independent flex shrink on Web and MyGo

`row`, `column` and `box` accept `?shrink:float`. The typed `ShrinkValue`
property uses wire name `shrink` and accepts only finite, nonnegative floats.
Only these three standard kinds admit it. Web maps it to CSS `flex-shrink`;
MyGo uses the existing `Element.Shrink` without an SDK or dependency update.
Generic, SwiftUI and Kotlin profiles reject explicit shrink values; Apple and
Android also reject direct standard wire patches rather than ignoring them.
Extensions/raw markup do not gain a shrink property or escape hatch.

Omitting or removing shrink preserves/restores the existing default factor 1.
Setting or removing it does not change `grow` or flex basis. Existing callers
need no changes. New callers must use a host supporting this property and a
LUI version that knows the new wire name; older hosts reject that opt-in.

For a bounded, clipped single-line strip, opt in on each direct pill container:

```ocaml
row ~flex_wrap:`nowrap
  [row ~shrink:0. [text ~value:"First" []];
   row ~shrink:0. [text ~value:"Second" []]]
```

Use the existing typed overflow property on the strip for clipping. Shrink on
the strip itself does not disable shrinking its children. Remove unnecessary
child `grow` props to keep intrinsic sizing; do not substitute `grow:0` for
`shrink:0`, because MyGo's `Grow` also changes an auto basis to zero percent.

## Unreleased: opt-in container focus-within observation (Web and MyGo)

`row`, `column` and `box` accept `?on_focus_within:(bool -> unit)` on
Web/Melange and MyGo. Installing the callback enables the new boolean
`focus-within-enabled` property and receives `FocusWithinChanged (node, within)`.
Without the callback/property, observation is off and existing views are unchanged.
The callback does not make the container focusable or change keyboard traversal.

After mount/enable settles, the observer publishes one current snapshot, then
only distinct transitions. True means focus is on the container or inside its
rendered subtree. Moving between descendants does not emit an exit/reentry pair.
Web coalesces local `focusin`/`focusout` checks at the microtask boundary, also
checking after retained child removal. MyGo shares its existing `FocusWithin`
read with appearance styling and delivers through the committed event queue.
Neither backend treats a popup/portal outside the subtree as inside merely
because it is attached to a trigger. Window activation is not a second condition
on retained focus membership; this is not an application-activation callback.

MyGo rejects `~on_focus_within` on ``box ~display:`contents``: a transparent
box has no native element to observe. The same restriction applies to raw wire
nodes with `display="contents"` and `focus-within-enabled=true`. Observe a real
row, column or non-transparent box instead. Web can observe this combination
through its retained DOM subtree.

Disabled/inert ancestors normalize membership to false, including a terminal
false for a previously focused subtree. Re-enabling observes current membership
again. The last value is recorded before dispatch, so reducer patches do not
cause repeated feedback. Same-node reconciliation retains the observation;
opt-out or node retirement discards it. A new incarnation receives a fresh
snapshot. Unmount cancels delayed checks without dispatching to a dead node.

SwiftUI, Kotlin and Generic host profiles explicitly reject this property,
including explicit false; Apple and Android raw-wire hosts reject it too.
Cross-platform applications must omit the callback on those paths, not expect
silent no-event support. No Apple/Android focus framework or focusable group is
introduced. Their existing focus behavior and appearance properties are unchanged.
Rebuild the shared OCaml application and Web/MyGo host together for the added
event constructor and native `lui_ocaml_focus_within_changed` bool callback.
Older native libraries remain usable without this opt-in; attempting to deliver
the new event to a library without its callback fails explicitly.

For example, replace per-control focus handlers with one row-owned signal:

```ocaml
row ~on_focus_within:(fun within -> Signal.set toolbar_focused within)
  [comment_body; reactions; toolbar]
```

Combine that signal with the existing hover state to drive typed toolbar opacity.
No new focus-within opacity property or data migration is needed.

## Unreleased: MyGo links in text flow

Text-content `link` nodes inside a native text flow now use MyGo's inline Link
instead of a block LinkBase. The actual native parent determines the mapping,
including through `box` nodes with `display=contents` and extension renderers. Existing
link text, nested text styling and URL activation remain available without
application changes. For example, `text [link ~text:"Guide" ~url:guide_url []]`
stays within one paragraph instead of failing native text-child validation.

Links outside text flow retain their existing block/icon layout. Icons and
arbitrary layout children still belong outside a text flow; native text-child
validation is unchanged. No API, wire format or SDK pin changes are required.

## Unreleased: Android editable Combobox menu focus

Android suggestion menus anchored beside a `combobox` retain keyboard focus in
the input while the menu is open, so edits continue to emit text changes and
filter the shared model-owned options. The native Material popup no longer
takes input focus from an editable anchor, and the anchor stays mounted when
its menu appears or disappears. Other dropdown and context menus keep their
existing focus and dismissal behavior.

Existing `stack [combobox ...; dropdown_menu ...]` integrations need no API or
wire changes; keep the query and filtered options in the shared model rather
than manually refocusing or remounting the input after each edit. Apple and Web
behavior is unchanged.

## Unreleased: Android growing content and Gallery navigation

Android columns apply `grow` only when their vertical extent is bounded.
Inside a vertical scroll viewport, growing children retain their authored
height or intrinsic content height instead of collapsing and overlapping
following controls. Bounded columns still distribute remaining height;
applications do not need to remove `grow` from scroll-contained textareas.
Android dialogs also render the existing `description` property above their
retained body. Neither correction changes the wire format or event ABI.

The native Android component Gallery now derives a Material navigation drawer
from the retained page roots and renders one selected page at a time. Shared
OCaml model state remains authoritative across page switches; navigation is
host-only and introduces no public LUI component. Its mobile E2E runner uses
the checked-in `platform/android/gradlew` wrapper.

## Unreleased: desktop input metadata

The pinned MyGo SDK preserves `InputEvent.PhysicalKey` and optional layout
`Text` on keydown and keyup. DOM-style adapters can map Shift+1 to
`code=Digit1` and `keyChar=!`; non-ASCII text is retained as UTF-8.
The native backend supplies the text; absent metadata
stays absent, with no synthesized US-keyboard shift table. Text metadata is
not a text-input commit and must not be inserted a second time. Darwin uses
`NSEvent.characters`, Linux uses GDK key values, and Windows uses a
non-mutating keyboard-layout query (Windows 10 version 1607 or newer).

Pointer capture preserves an active primary gesture when another button is
pressed or released. Non-primary events still reach the capture owner; they
do not end the primary gesture.

## Unreleased: preserve Apple and Android backends

The MyGo migration changes the default desktop renderer, not mobile support.
Apple/iOS and Android remain maintained backends alongside MyGo desktop and
Web/Melange. Their backend sources, packages, example hosts, mobile tooling,
Drive probes and CI jobs are restored after their unintended removal.

Downstream applications such as `logseq/mobile` and `logseq/logseq_journal`
must keep their native backend dependencies:

- SwiftPM consumers retain the `LUIAppleBackend` or `LUIAppleBackendStatic`
  product from the root package or `platform/apple` package. For example,
  Journal can continue using `JOURNAL_LUI_PACKAGE_PATH=../lui/platform/apple`.
- Android consumers retain the `platform/android/lui` Gradle module and its
  JNI bridge. The optional `platform/android/drive` instrumentation module
  remains debug-only.
- Schema generation emits `LUIWireSchema.swift` and `LuiWireSchema.kt` as
  well as the shared OCaml/PPX artifacts. Regenerate all of them from the
  current schema, including the modal transition declarations below.
- Mobile build/test scripts, Maestro flows, Apple/Android CI and
  `make test-apple` remain supported. See the
  [component gallery guide](../examples/components/README.md) for commands.

Restoration does not rename public APIs, change host defaults or event
semantics, or change wire batches and capability negotiation. Keep existing
SwiftUI/Kotlin host integrations; do not replace them with MyGo. The separate
desktop migration still relocates the shared C bridge to `platform/bridge`
as described below; it does not restore the retired SDL renderer.

## Unreleased: modal surface transitions

`dialog`, `drawer`, and `sheet` now accept `~transition:string`, like
`popover`. The wire `Transition` property is admitted on these modal kinds;
`Root` and `Tooltip` remain excluded, and transition values retain the same
validated CSS shorthand grammar.

Pass the transition to the surface constructor rather than a post-mount
property bind or a child container:

```ocaml
dialog ~transition:"opacity 200ms ease-out, transform 200ms ease-out"
  [text ~value:"Content" []]
```

Web applies this declaration to the real retained modal surface, preserving
its opening/closing animation, focus restoration, and exit-paint lifecycle.
MyGo accepts the shared property but applies state changes immediately;
CSS animation remains a documented host exception. Applications need no
backend capability guard. Omitted transitions keep the existing host defaults.

## Unreleased: MyGo desktop and portable host services

MyGo (`platform/mygo`) is now the default desktop renderer. The former
`platform/native` OCaml/SDL renderer, its executables, packaging tools,
renderer-specific plugins and native test jobs are removed, not deprecated.
There are no compatibility aliases or fallback renderer. Web/Melange and
the Apple/Android hosts remain supported; mobile backend retirement is not
part of this desktop migration.

The shared `lui_ocaml_*` C ABI moved byte-for-byte to
`platform/bridge/lui_ocaml_bridge.c` and
`platform/bridge/lui_caml_dispatch.h`. Symbols, event dispatch, ownership,
capability negotiation and wire batches are unchanged. Update source/header
dependencies and include paths in downstream build rules; keep application
bridge callbacks and `examples/*/native` libraries. These directories contain
shared OCaml applications, not the removed renderer. The GC runner is now
`opam exec -- sh platform/bridge/stress/run.sh`.

Exactly two former native libraries remain, under `platform/services`:

| Public library | Module | Dependencies and runtime |
| --- | --- | --- |
| `lui.plugin` | `Lui_plugin` | OCaml standard library (`Mutex`); unchanged registry API |
| `lui.plugin_fetch` | `Lui_plugin_fetch` | `yojson` and `lui_plugin`; runtime libcurl on macOS/Linux and libdl on Linux |

Their public names and modules are unchanged; no SDL or renderer dependency
is required. Fetch keeps its existing unsupported-platform error outside
macOS/Linux; this move does not add Windows HTTP transport.

Every other public library formerly supplied by `platform/native` is removed:

- Renderer/layout/resources: `lui.backend`, `lui.blit`, `lui.d3d11`,
  `lui.flex`, `lui.gl`, `lui.gpu`, `lui.host`, `lui.image`, `lui.layout`,
  `lui.media`, `lui.metal`, `lui.paint`, `lui.retained`, `lui.raster`,
  `lui.resource`, `lui.resource_loaders`, `lui.scene`, `lui.spatial`,
  `lui.store`, `lui.svg`, `lui.text`, `lui.text_dwrite`, `lui.text_pango`,
  `lui.theme`, `lui.vulkan`.
- Input/platform services: `lui.a11y`, `lui.ax`, `lui.ax_linux`,
  `lui.ax_windows`, `lui.gamepad`, `lui.ime`, `lui.input`, `lui.resilience`,
  `lui.shell`, `lui.shell_linux`, `lui.shell_windows`, `lui.updater`,
  `lui.webapp`, `lui.webview`, `lui.window`, `lui.window_linux`,
  `lui.window_windows`.
- Tools/plugins: `lui.cli`, `lui.e2e`, `lui.e2e_json`, `lui.ed25519`,
  `lui.pkg`, `lui.pkg_linux`, `lui.pkg_webapp`, `lui.pkg_windows`,
  `lui.plugin_gamepad`, `lui.plugin_glass`, `lui.plugin_sqlite`,
  `lui.plugin_terminal`, `lui.plugin_updater_ui`, `lui.plugin_websocket`,
  `lui.plugin_webview`, and the `lui_pkg` executable.

The shared `lui` runtime/element API remains. Keep reducers, signals and views
in OCaml and pass their existing shared application library to MyGo. For
example, replace an SDL host linked to `lui.host`/`lui.window` and a build
dependency on `platform/native/lui_ocaml_bridge.c` with:

```sh
# The builder links platform/bridge/lui_ocaml_bridge.c.
library=$(./tooling/build_mygo_todos.sh)
go -C platform/mygo run ./cmd/lui-mygo -library "$library"

# Components uses the same shared ABI and existing OCaml Gallery.
components=$(./tooling/build_mygo_components.sh)
go -C platform/mygo run ./cmd/lui-mygo -library "$components" -title Components
```

Downstream apps replace renderer-specific Dune libraries with `lui` and only
the portable services they actually use, then embed a MyGo host as described
in [the MyGo guide](../platform/mygo/README.md#embed-a-backend). Replace any
custom `../../../platform/native/lui_ocaml_bridge.c` and adjacent header
dependencies with `../../../platform/bridge/...` at the same relative depth.
The old `examples/components/webview-shell` depended on removed `lui.webapp`
and `lui.webview` and is deleted; use the native MyGo Components host above
or the existing Web build in a browser, not an SDL WebView wrapper.

Historical entries below describing the removed renderer record previous
releases; they do not promise those APIs remain available. Build and schema
checks do not establish visual parity or native interaction acceptance.

## MyGo standard dropdown menus

Standard standalone `dropdown-menu` components now present through MyGo's
native context-menu implementation, using the same `menu-item`, `menu-trigger`,
disabled/checked state, nested menus and action handlers as `context-menu`.
Selection dispatches the live item's `press` before one owner `dismiss`;
cancellation dispatches only `dismiss`. Retired items cannot receive a choice.
Keep `~on_dismiss` wired to remove the model-owned menu and mount a new menu
identity for each opening. No wire properties or events change.

```ocaml
dropdown_menu ~at:(x, y) ~on_dismiss:(fun _ -> close_menu ())
  [menu_item ~text:label ~on_press:(fun _ -> run_action ()) []]
```

Custom content and styled items still use the retained in-window menu route.
Hosts may set `luimygo.Config{RetainedMenus: true}` to use retained menus for
standard content too. Native shortcut hints remain descriptive labels, not new
accelerator registrations. Web rendering and its component API are unchanged.
The MyGo dependency includes the additive build-scoped
`Element.OpenContextMenuAt(x, y)` hook; do not replace the SDK pin with an older
version lacking it. Applications should use LUI components, not a second menu
specification or host-specific action-tag table.

## Unreleased: Apple minimum scroll viewport reference

Apple hosts may set the optional `EnvironmentValues.luiMinimumScrollViewport`
to a scene-global `CGRect` measured outside navigation keyboard avoidance and
editor safe-area insets. Windowed `virtual-list` first-section minimum heights
use the reference's bottom edge minus the scroll view's top edge, rather than
the already-reduced local viewport. Actual scrolling and visible-range tracking
are unchanged. With the default `nil`, existing local viewport measurement is
preserved; no wire-format change is required.

For example, measure a `NavigationStack` background using
`GeometryReader` with `.ignoresSafeArea(.all, edges: .bottom)`, then pass
`.environment(\.luiMinimumScrollViewport, measuredFrame)` to the stack.
The background reports `proxy.frame(in: .global)` without changing keyboard
avoidance on the interactive content. Update the frame on geometry changes so
rotation and split-view resizing still change the minimum height normally.

## Unreleased: Apple virtual-list first-section height retention

The legacy windowed `virtual-list` keeps `data-first-section-count` and
`data-first-section-inset` as a minimum viewport height for its first section.
The remaining space now belongs to the last real row instead of a synthetic
lazy-list slot. Scrolling, pinned editing and scroll requests therefore retain
the same logical row positions while row measurements survive recycling.
Content taller than the minimum still grows normally; it is never clipped.

No wire or application changes are required. For example, a source with
`data-first-section-count=2` and `data-first-section-inset=136` still reserves
at least the unobscured viewport height minus 136 points for its first two
rows. `data-scroll-index=2` continues to address the third logical row, without
an application-supplied padding offset. Sparse virtual-list sources are unchanged.

## Unreleased: Native dialog transitions keep a fixed zoom origin

Retained enter/exit motion no longer re-reads a surface's resolved rect
each frame while a track is running. The zoom anchor stays where the
transition started, so dialogs whose layout is still settling no longer
drift or shake during the fade/zoom. No view or wire changes are required.

## Unreleased: Android Drive sample safe drawing insets

The optional `:drive-sample` Activity now explicitly enables edge-to-edge and
wraps `backend.Content()` in `Box(Modifier.safeDrawingPadding())`. Controls
respect current system-bar, display-cutout and IME insets instead of relying on
fixed content padding. This changes only the sample's host layout; renderer
defaults, native protocol v1, measured-coordinate conversion and strict
occlusion checks are unchanged.

Applications that copied the sample should call `enableEdgeToEdge()` and
apply Compose safe-drawing insets at their content boundary, or use their
existing screen-specific inset handling. Do not compensate by shifting Drive
coordinates or allowing input through SystemUI windows. See
[`platform/android/drive/README.md`](../platform/android/drive/README.md).

## Unreleased: DEBUG iOS read-only Drive probe

DEBUG iOS builds add `LUIAppleBackend.debugDriveSnapshot()` and
`LUIDriveSnapshotProbe.startIfEnabled(backend:window:environment:)`. These APIs
are absent in Release and on other platforms. Retain the probe after the
single foreground key window is ready, and call `stop()` during host teardown.
Wrap host references in `#if DEBUG`:

```swift
#if DEBUG
driveProbe = try LUIDriveSnapshotProbe.startIfEnabled(
    backend: backend, window: window
)
#endif
```

No listener opens unless `LUI_DRIVE_PROBE=1` is explicitly supplied. The probe
temporarily enables frame collection and restores its settings without
replacing existing callbacks. It binds only IPv4 loopback (default port 49378)
and accepts versioned read-only snapshot requests; it has no Drive action or
semantic event endpoint. This is debug access for trusted local processes,
not authentication against other local applications.

Native input belongs to the separate Drive XCTest UI-testing target, never
the app binary. Selector actions require explicit stable native accessibility
identifiers and do not fall back to labels, coordinates or semantic events.
Frame coordinates are window-local logical points, not screenshot pixels.
Existing production event behavior and transport contracts do not change.
See [`platform/apple/DriveProbe.md`](../platform/apple/DriveProbe.md) for a
complete host hookup, protocol and lifecycle example. Apple-SDK compilation
and Simulator/device input verification are separate integration gates.

## Unreleased: Optional Android native Drive host

Android renderer defaults and existing semantic integrations are unchanged.
`LuiBackend.inspect()` is a new opt-in, UI-thread-only read-only inspection
API. Close its `LuiInspection` handle to remove inspection semantics and
layout observers. Snapshots copy retained nodes and carry host-local
incarnation guards; native targeting requires attached, visible geometry.

For an API 30+ debuggable test variant, add
`debugImplementation(project(":drive"))`, register
`DriveTarget.attach(activity, backend)` after `setContent` behind an explicit
debug intent flag, and close the handle in `onDestroy`. Declare
`dev.lui.drive.DriveInstrumentation` only in the debug manifest. Keep the
optional library, INTERNET permission, runner and test IME out of release
artifacts. The sample supplies separate debug/release hooks.

```sh
# The debug app must already be installed; this clears its Activity task.
adb forward tcp:49377 tcp:49377
adb shell am instrument -w -e drive true \
  -e activity your.debug.package/.MainActivity \
  your.debug.package/dev.lui.drive.DriveInstrumentation
# In another terminal, with a Drive version supporting loopback TCP:
drive --tcp 127.0.0.1:49377 --input native scenario.drive
# After the run:
adb forward --remove tcp:49377
```

Native protocol v1 is unchanged: initial hello, full frames, then ops establish
readiness; fresh ops and full frames precede each correlated result. Wire
coordinates/deltas are content-viewport dp, converted to screen pixels at OS
MotionEvent/KeyEvent injection. No action falls back to LUI semantic events.

Text replacement uses a real InputConnection and requires deliberately
selecting the test-device IME; `type` is not advertised otherwise. The host
never enables/selects an IME itself. Preserve and restore the original IME,
or use the explicit `--test-device` sample launcher. Missing selection or
geometry, stale incarnations, disabled/hidden targets, detectable native
occlusion and unsupported input fail explicitly. Offscreen targets need
native scrolling; there is no selector auto-scroll.

Settling is bounded model/layout/draw/accessibility quiet, not application or
network idle, or proof of every render-thread animation. Accessibility cannot
prove the behavior of arbitrary invisible custom touch interceptors;
unmeasured modals/extensions and system UI need separate instrumentation.
Already running input cannot be rolled back. Compile/protocol/lint checks
are not device-input evidence. See
[`platform/android/drive/README.md`](../platform/android/drive/README.md)
for complete integration, input and cleanup limits.

## Unreleased: MyGo overlay theme foreground

MyGo dialogs, sheets and popovers now initialize their detached panel's text
color from the current scoped theme, matching their themed backgrounds. Plain
text and inherited labels no longer fall back to the window's default foreground
when opened under a nested dark theme. Explicit child foreground properties
continue to override this default; no schema or wire change is required.

For example, a sheet beneath a column with `theme-mode="dark"` now displays its
title and unstyled text in the dark theme's foreground without per-label colors.
Do not add a `foreground` property to the sheet: that property is not supported
by the sheet kind.
## Unreleased: Native icon prop paints above state backgrounds

On the retained Native host, an `icon` prop on `menu-item` and
`number-stepper` now paints with the node's content — after its
`background`, `hover-background`, and `pressed-background` fills —
instead of in the default chrome layer underneath them. A hovered or
pressed control keeps its glyph visible; previously any declared state
background covered the icon. No view or wire changes are required.


## Unreleased: Native menu keyboard navigation

The retained Native window host opens a focused menu trigger with Return or
Space. Menu keyboard traversal includes enabled submenu triggers. Right,
Return, or Space opens the highlighted submenu. Left or Escape closes that
submenu and returns focus to its trigger. Menu typeahead clears its prefix
after 500 milliseconds of inactivity.

For example, a menu with a regular item followed by
`submenu ~text:"Type" entries` now reaches Type with Down and opens it with
Right. Hosts should keep forwarding native keyboard events and advancing the
existing window clock. This uses the existing menu constructors and wire
events.


## Unreleased: Web submenu placement through layout wrappers

Web dropdowns owned by a `menu-trigger` or `menu-item` now find their semantic
menu container through layout wrappers before choosing a default side. A
`context-menu`, non-picker `dropdown-menu`, or ``popover ~role:`menu`` qualifies.
For example, the following opens the submenu at logical inline-end (right in
LTR, left in RTL), rather than below its trigger over the following row:

```ocaml
popover ~role:`menu [column [submenu ~text:"Property type" entries]]
```

Top-level `menu` and `submenu` calls without a semantic menu ancestor retain
their below-trigger default. Listbox dropdowns and popovers without typed
``role:`menu`` stop the lookup; a DOM `role` data attribute is not a substitute.
Applications that use popovers as menu containers should pass the existing
typed ``~role:`menu`` only on those containers, not on ordinary dialogs.

Explicit `anchor` values, viewport collision handling, pointer corridors, hover
and keyboard behavior are unchanged. No constructor, wire, schema, native-host
or MyGo changes are required.

## Unreleased: Web nested-layer Escape ownership

Web layers now route Escape from their content through the shared topmost-layer
dispatcher before application document shortcuts run, even when those shortcuts
were registered before the layer opened. With a popover inside a dialog, the
first Escape dismisses only the popover; the next dismisses the dialog. This also
works when focus remains on the popover trigger inside the dialog. Target-local
handlers still run first, and `defaultPrevented` and composition guards remain
unchanged. Consumed Escape does not reach document shortcuts.

Applications should keep `dialog ~on_dismiss:close_dialog` and
`popover ~on_dismiss:close_popover` as the owners of dismissal rather than closing
both in a document Escape shortcut. No constructor, wire, native-host or other
keyboard behavior changes are required.

## Unreleased: MyGo select trigger chrome

Standard MyGo `select` triggers now align their label to the leading edge and
reserve space for one built-in trailing chevron. The label can shrink within
authored dimensions; the chevron inherits the control's foreground and disabled
appearance. Existing size, padding, variant and icon props still apply.

Use `select ~text:current ~on_press:open_menu []` without adding an application
chevron. Remove a previously authored arrow workaround to avoid duplicate arrows.
Press, Down-key activation, disabled behavior, popup-button accessibility and
model-owned menu lifetime are unchanged. No wire or schema migration is required.

## Unreleased: Apple closed drawer visibility

An overlay drawer's retained panel is hidden once closed. On iOS the panel uses
a retained hosting controller inside a plain UIKit container. Closing sets the
container's `accessibilityElementsHidden`, then detaches the hosted view from the
window when the animation completes. Reopening attaches the same hosted view.
The hosting controller and its SwiftUI content remain retained throughout;
hidden hosting views can otherwise leave virtual accessibility proxies in the
window despite SwiftUI and UIKit visibility flags.
The panel remains mounted after its first reveal, preserving scroll position,
native state and the inherited SwiftUI environment when reopened. Pinned
split-view drawers, wire props and drawer events are unchanged; no application
migration is required.

## Unreleased: Android button labels in horizontal scrolls

Android icon/label buttons measure their natural content width before allocating
space to the label. Both leading and trailing icon groups therefore retain their
text in horizontal scroll containers instead of reducing a weighted label to zero
width. Explicitly constrained buttons still reserve icon space and ellipsize long
labels; no application workaround or new props are required. Other hosts and
press events are unchanged.

## Unreleased: Android list and menu content padding

Android `list-item` and `menu-item` apply authored padding inside their native
Material controls, replacing native padding on each specified edge rather than
adding a second outer inset. Unspecified edges retain Material defaults. An
authored fixed height removes unspecified native vertical padding so compact
nested controls do not consume the label's entire height.

Compact selection rows can keep their existing geometry:

```ocaml
list_item ~height:44 ~padding_vertical:0 [
  menu_item ~height:44 ~padding_vertical:0 ~text:"Choice" ~selected:true []
]
```

Remove explicit padding or height to use the corresponding Material defaults.
Native selection, press events, disabled states and other hosts are unchanged;
no wire or schema migration is required.

This guide records changes applications must consider when updating LUI.
Keep it alongside the implementation: every public constructor, wire contract,
default, event or compatibility change must receive an entry before release.
Changes below are unreleased work following PR #271; host qualification is
tracked in [the MyGo parity plan](agent-guide/004-component-api-mygo-parity.md).

The Native OCaml renderer is outside this parity update except for the
input contracts explicitly qualified below. Its paint-property
inventory check is temporarily deferred until that inventory recognizes
`read-only`, `overscan` and `item-extent`; these features are not qualified on
that renderer. The MyGo, Web, Apple, Android and shared ABI regressions remain
covered separately.

## Unreleased: Android button content alignment

Android buttons center their label or icon/label group using the native Material
control. Custom child content now honors child `grow`; descendant text inherits
the button's `text-alignment` (center by default) unless it declares its own.
Icon/label pairs reserve space for either leading or trailing icons and ellipsize
long labels within the remaining width. Other hosts and press events are unchanged.

`text-alignment` no longer implicitly expands a label or its button to the full
available width. Adjacent aligned buttons therefore keep their natural widths.
Use explicit sizing when expansion is intended:

```ocaml
button ~grow:1.0 ~text_alignment:`center ~text:"Continue" []
button ~grow:1.0 [text ~grow:1.0 ~value:"Continue" []]
```

An explicit child `text_alignment` still takes precedence. No wire/schema
migration is required.

## Unreleased: Compile-time element nesting diagnostics

With `lui.ppx` enabled, statically resolved illegal element nesting now fails
during compilation with a `LUI nesting:` diagnostic, the parent/child kinds and
the offending source location. Admission rules are generated from the existing
runtime protocol; valid constructors, node IDs, events and wire batches do not
change. Applications without the PPX retain the existing runtime checks.

For example, replace `context_menu [button ~text:"Copy" []]` with
`context_menu [menu_item ~text:"Copy" []]`. A `tree` needs row containers, so
replace `tree [text ~value:"Item" []]` with
`tree [row [text ~value:"Item" []]]`. Menu/toolbar restrictions also apply through
statically resolved local values, nonrecursive helpers, `List.map`/`concat_map`,
list concatenation, conditional/match/exception branches and structural wrappers.
`separator`, `menu` and `submenu` use their actual underlying node contracts.

Correlated branches over immutable booleans or `Lui_ui.host context` retain their
relationship, including aliases, negation and boolean matches. For example,
`let child = if android then dropdown_menu [] else context_menu [] in
if android then menu_trigger [child] else button [child]` remains valid.
Separate effectful condition calls are not assumed to return the same value.

Structural `reactive`, `if_` and `keyed` callbacks mount without an anchor; when
one returns another structural primitive, the runtime creates a transparent Box.
The checker accounts for that Box rather than treating every dynamic wrapper as
transparent. For example, avoid nesting `if_` inside `reactive` under a
`context_menu`: choose the `menu_item` branch directly instead. `virtual_rows`
requires a direct `virtual_list` parent and must be its sole child; use
`virtual_list [virtual_rows ~source ~key ~cmp ~mount ()]`, not a sibling row or a
structural wrapper around `virtual_rows`.

This is a bounded source-level check, not a replacement for the type checker or
runtime validation. Unknown external functions/modules, recursive results,
runtime signals and expressions beyond the analysis budget can still require
runtime checks. Lexically shadowed constructor/module names are not assumed to
be LUI nodes. No type casts or protocol migration are required.

## Unreleased: Android text wrapping and overflow

Android text, labels and paragraphs now honor the existing `white-space` and
`text-overflow` properties. For example, `text ~white_space:"nowrap"
~text_overflow:"ellipsis" ~value:"Long title" []` stays on one ellipsized line
inside a constrained row. `pre` disables soft wrapping while preserving explicit
line breaks; omitted properties retain wrapping and clipping. Existing
`line-clamp` limits remain supported. No wire/schema migration is required;
other hosts are unchanged.

## Unreleased: Android sheets expand for text input

Android sheets that support the medium detent now expand when the software
keyboard is visible, keeping form fields and actions above the IME. Hiding the
keyboard leaves the sheet expanded; dismissal and explicit height constraints
are unchanged. Existing `sheet ~detents:"medium,large" [...]` forms need no
application workaround or wire/API migration. Apple and other hosts are unchanged.

## Unreleased: Web component defaults and interruptible Accordion motion

Web buttons without `size` now use the same height and padding as `size:default`.
On the iOS simulator profile, small buttons retain a smaller label while icon
buttons have a square 44px target. Separators without `orientation` now render
horizontally; vertical separators stretch across their row and have a one-em
minimum height when their parent has no definite height. Explicit typed sizes
and spacing remain supported; set `~min_height:0` when intentionally requesting
a shorter vertical separator. For example, `button ~text:"Save" []`
no longer needs ``~size:`default``, and `separator []` no longer needs
``~orientation:`horizontal`` to be visible. Remove padding or separator-height
workarounds added only to compensate for the missing defaults.

Web dialogs now separate their title and body, use the theme border color and
respect the simulated device width rather than the desktop browser width.
Explicit dialog heights remain supported and scroll when content does not fit;
omit `~height` for content-sized forms, as in `dialog ~width:380 ~padding:24 [...]`.
The gallery's rename form now follows this content-sized pattern. Simulated
keyboard space is still reserved while a field has focus, but is labelled as a
noninteractive placeholder instead of displaying striped keyboard chrome.
Use the host keyboard for text entry; this is not a software keyboard or IME.

Accordion expansion and collapse now transition from the current rendered
height, including when reversed mid-animation. Completion callbacks from an
older transition cannot hide or resize a newer one. The retained panel and
children, controlled `selected`/`on_toggle` behavior, linked accessibility
semantics and reduced-motion behavior are unchanged. Panel padding now belongs
to an internal `.lui-accordion-body` wrapper, allowing the animated panel to reach
zero height without a final padding jump. Applications styling that internal
panel's padding should move it to their content or the body wrapper. No OCaml
constructor, event payload or wire-schema migration is required.

## Unreleased: Apple drawer SDK compatibility

The Apple drawer builds with the existing Xcode 26 / Swift 6.2 toolchain again.
Its iOS 27.1 vertical-bar scene reader is compiled only when the SDK supplies
SwiftUI 8.1 or later, excluding Mac Catalyst, whose SDK lacks these iOS-only APIs.
The existing runtime iOS 27.1 availability check still applies. Older SDK builds
and Mac Catalyst retain the standard drawer presentation, even when run on a
newer OS; builds using a supported SDK retain the vertical-bar-aware presentation.

No constructor, wire schema, event or application source migration is required.
For example, an existing `drawer ~selected:is_open main sidebar` is unchanged;
rebuild its Apple host with the iOS 27.1 SDK or later to enable vertical-bar
adaptation on supported devices.

## Unreleased: Apple native button styles on OS 26

On iOS/iPadOS 26 and macOS 26, independent `button` and `toggle_button`
controls use the system's Liquid Glass button styles: absent/default, outline
and secondary variants use `.glass` (secondary keeps its secondary tint), while
primary and destructive use `.glassProminent` (destructive keeps its red tint).
Prominent labels retain readable white foreground ink when the application
sets an inherited foreground style. Standalone icon-only default buttons also
use `.glass`, rather than the former borderless style. The native styles supply
the glass material and interaction; applications should remove custom action
backgrounds, corner radii and padding that would cover the system treatment.

Ghost/content buttons remain borderless. Tab triggers keep their tab styling;
the default whole-row Form action remains automatic, and default icon-only
controls in native List rows remain borderless. Hoisted toolbar children retain
the system toolbar style, while cells inside an existing glass capsule remain unadorned
instead of drawing a second glass surface. Button actions, disabled/focus state,
selection tint and declared hit-target dimensions are unchanged. Earlier Apple
OS releases retain their existing bordered/borderless/automatic mapping. This
is a host presentation change only: there is no OCaml constructor, wire schema
or fingerprint migration. For example, existing
``button ~variant:`primary ~text:"Save" ~on_press:save []`` needs no source
change; remove any separately supplied background to see native prominent glass.

## Unreleased: Apple wrapping rows

Apple now honors the existing `row` property `flex-wrap: "wrap"`. Previously it
was decoded but rows always used a single HStack. No constructor, wire schema or
extension fingerprint changes. Rebuild the Apple host to enable the behavior;
existing ``row ~flex_wrap:`wrap ~gap:16 children`` needs no source migration.
Absent/`nowrap` retains the existing HStack path. This change is row-only: it
does not implement wrapping for `box` or `column`.

A finite width proposal (including zero) bounds each line; nil/infinite width
uses one natural-width line. Children are measured before breaking lines, and
an oversized child is remeasured with the bounded proposal. An explicitly fixed
child that cannot shrink occupies its own line and may overflow that line; it
does not widen the reported bounded row. Empty rows have zero size. `gap` is the
minimum space between items and between lines; no gap precedes the first item or
follows the last line.

`main` start/center/end/space_between applies independently to each line, with
logical horizontal placement mirrored in RTL. `cross` start/center/end/stretch
uses that line's maximum measured height. Positive `grow` shares remaining line
width proportionally after intrinsic bases and gaps; a `spacer` has a zero basis
and grow at least one. Growing children are remeasured at their allocated width
before line heights are finalized. Unbounded proposals do not allocate infinite
grow space. There is no geometry-to-state feedback or application-specific grid.

## Unreleased: Android pointer event capability checks

Android now checks the existing shared node-kind contract before emitting
`PointerDown` or `PointerUp`. The `pointer-enabled` property is also set by
ordinary input, submit, toggle and hover subscriptions; it does not grant every
pointer event to every node kind. Text fields and other unsupported kinds no
longer emit a rejected down/up pair before their native interaction. Supported
pointer kinds and the existing `role="treeitem"` opt-in continue to receive
down/up events when `pointer-enabled` is true. Disabled nodes remain inactive.

For example, an existing `text_field ~on_input:handle_input []` requires no
application change: native editing still emits `TextChanged`, without synthetic
down/up events. Existing `row ~on_pointer_down:handle_down
~on_pointer_up:handle_up []` handlers keep their shared event contract. Context
menu position observation remains independent of down/up capability, so an
attached context menu still observes its long-press location on a text control.

Pointer input restarts when the down/up capability changes. `PointerUp` is sent
only after the observed gesture releases, not from coroutine cancellation during
recomposition or removal. The shared receiver's strict unsupported-event checks,
wire schema, handler subscriptions and other platforms are unchanged. Rebuild
the Android host with this renderer; no source or wire migration is required.

## Unreleased: Web scoped theme mode

The Melange DOM backend now consumes the existing `theme-mode` property instead
of rejecting it during DOM application. `light` and `dark` select the default
Web palette and native control color scheme for the node's subtree; `system`
follows `prefers-color-scheme`, even inside a forced light or dark ancestor.
Nested modes override outer modes, including an explicit `light` mode under a
host `.dark` class. Removing the property restores the nearest enclosing mode
or the existing host appearance when no enclosing mode is present. Unthemed
hosts keep their existing default appearance.

For example, keep sending
`{"op":"set-prop","id":1,"property":"theme-mode","value":"dark"}`
to switch a mounted root to dark mode, or use `"light"` / `"system"` for the
other modes. Send
`{"op":"remove-prop","id":1,"property":"theme-mode"}`
to stop overriding its inherited mode. No wire, schema or application API
migration is required. Rebuild and deploy the Web stylesheet together with the
Melange backend; updating only the DOM code does not provide the scoped palette.

Open sheets and other portals follow their retained logical ancestry across
mode updates, property removal and reparenting, rather than the portal's physical
DOM parent. An explicitly themed portal keeps its own mode, and a detached
portal retains its last mode while exiting. Theme mode only selects palette
tokens: it does not rewrite explicit foregrounds, author colors, disabled states
or responsive styles. Custom token tables (`theme`) are a separate contract and
remain outside this Web receiver change.

## Unreleased: Android inherited foreground and scoped appearance

Android now applies a container's `foreground` to uncolored plain text in its
subtree, with the nearest explicit container color winning. An explicit text
leaf `foreground` still wins; an absent, empty, or whitespace-only value
inherits rather than resolving to transparent. Use `foreground: "transparent"`
or `"#00000000"` when transparency is intentional. Node colors resolve after
the node's own `theme` tokens and effective appearance, so a foreground token
on the same node uses the newly supplied palette. Removing a container's
`foreground` restores the nearest ancestor's color without remounting.

For example, set `{"op":"set-prop","id":2,"property":"foreground","value":"#EAE4DA"}`
on a Night tools column to color uncolored descendant text, and use
`{"op":"remove-prop","id":2,"property":"foreground"}` to resume inheritance.
Applications that relied on uncolored child text ignoring a container's
foreground should set a color explicitly on those leaves. This does not apply
the inherited color to every `TextStyle` or override Material buttons' native
enabled, disabled, selected, focus, and accessibility behavior.

Android `theme-mode: "dark"` and `"light"` now switch the scoped Material 3
color scheme as well as adaptive semantic tokens. `"system"` restores the
host's effective appearance, even under an explicitly dark/light parent;
removing `theme-mode` inherits the nearest parent again. Scoped schemes retain
the host's custom `LuiTheme(light = ..., darkScheme = ...)` palettes rather than
replacing them with defaults. For example, set a child node to `"system"` to
use the host palette inside a dark subtree, then remove that property to return
to the parent's dark palette. Applications that relied on an explicit `system`
silently inheriting the parent should remove that property instead. Material
controls and sheet chrome now follow the effective scoped scheme; their native
state colors remain owned by Material. No shared schema, wire format, or event
contract changes are required.

## Unreleased: Android text line clamps

Android now accepts the existing positive-integer `line-clamp` property on
`text`, `heading`, `paragraph` and `label`, matching the shared OCaml contract,
and passes it to those Compose text nodes as `maxLines`. Previously the Android
validator rejected this property, including in authoritative snapshots, and the
renderer had no line-limit consumer. This is not a numeric normalization change.

For example, keep sending
`{"op":"set-prop","id":2,"property":"line-clamp","value":1}`
to limit a text node to one line. Sending
`{"op":"remove-prop","id":2,"property":"line-clamp"}`
restores its original unlimited-line default. Nodes without the property keep
their previous behavior; button labels, text controls and other text consumers
are unchanged. No shared schema, wire, event or application rewrite is required.

## Unreleased: Android single-line text placeholders

Android placeholders now follow their control's line policy: `text-field`,
`secure-field`, `input`, `search-field` and `combobox` keep placeholders on one
line and ellipsize overflow. `textarea` placeholders continue to wrap. Previously
a narrow or zero-width field could wrap its placeholder character by character,
inflating a single-line control and its containing row to hundreds of dp even
though the editable text itself was single-line.

The wire format, default control height and `grow` behavior are unchanged. For
example, keep sending `{"op":"set-prop","id":2,"property":"placeholder","value":"Search this book…"}`;
no fixed height or placeholder rewrite is necessary. Applications must still
provide usable width or responsive toolbar alternatives: this correction does
not make a field usable when other row children consume all available width.

## Unreleased: Apple normalizes all floating wire properties

Apple now normalizes integral JSON numbers to its floating retained value for
every shared `FloatValue` property, not just the previously covered subset.
JSONDecoder can decode `2.0` or `2e0` as an integer; previously, for example,
`{"op":"set-prop","id":4,"property":"letter-spacing","value":2.0}`
rejected the entire batch even though the OCaml producer emitted a valid float.

Existing normalization remains for `item-extent`, `grow`, `anchor-offset`,
`anchor-alignment-offset`, `source-x`, `source-y`, `source-width`, `source-height`,
`value`, `min`, `max`, and `step`.
Newly covered properties are `first-pane-width`, `resize-origin`,
`resize-handle-offset`, `opacity`, `label-opacity`, `letter-spacing`, `inset`,
`inset-top`, `inset-right`, `inset-bottom`, `inset-left`, `hover-opacity`,
`pressed-opacity`, `disabled-opacity`, `width-viewport`, `height-viewport`,
`min-width-viewport`, `max-width-viewport`, `min-height-viewport`,
`max-height-viewport`, `popup-x`, `popup-y`, `available-height`, and
`collision-padding`.

No application migration or JSON rewriting is needed: continue emitting numeric
values, including integral floats such as `letter-spacing: 2.0` or `opacity: 1.0`.
Fractional numbers keep their existing behavior. Boolean and string values are
not converted; integer-only properties are unchanged. Property/kind admission,
finite-value checks, numeric bounds, and atomic batch rollback are unchanged.
The OCaml protocol and generic native ABI are unchanged.

## Unreleased: Android accepts wrapping preserved text

Android's retained text-flow validator now accepts `white-space: "pre-wrap"`,
matching the existing shared OCaml and Apple vocabulary for this mode. Previously
a valid batch such as `{"op":"set-prop","id":2,"property":"white-space","value":"pre-wrap"}`
was rejected atomically, including authoritative snapshots, even though Compose
`Text` already preserves the supplied text and wraps by default.

No application wire rewrite is required: keep sending `pre-wrap` for canonical
text whose whitespace must be retained. This only corrects validation; it does
not add CSS whitespace processing or change rendering of `normal`/`nowrap`.
Android still rejects `pre-line`, `pre`, unknown strings and non-string values.

## Unreleased: Linux native clipboard ownership result

`Lui_shell_linux.clipboard_write : string -> bool` keeps its signature but
now returns the synchronous `gtk_clipboard_set_with_data` ownership result.
Previously `true` only meant a GTK clipboard object existed after calling
the void `gtk_clipboard_set_text` function. It was not an ownership ACK.
There is no new checked/compatibility API or wire change. Existing
platform-selected `Shell.clipboard_write` callers keep compiling; callers
that ignore the result still do not receive a guarantee.

On Linux, `false` means missing clipboard support, ownership refusal,
allocation failure, or rejected text: invalid UTF-8, embedded NUL, or
`INT_MAX` bytes or more. The maximum accepted length is `INT_MAX - 1` bytes.
Rejected text is not silently truncated. Empty text is valid. The
implementation copies the entire accepted UTF-8 string before
acquisition, advertises GTK's text targets, serves requests through that
owned copy, and frees it on ownership loss/clear/replacement. Failed
acquisition frees the new copy immediately without first clearing the
clipboard. The result is not inferred from a readback, change counter,
transport enqueue, or SDL return value.

Replace an unchecked destructive continuation:

```ocaml
ignore (Shell.clipboard_write selected_text);
delete_selected_text ()
```

with an ownership-gated continuation using the existing platform-selected
Shell module:

```ocaml
if Shell.clipboard_write selected_text then
  delete_selected_text ()
else
  report_clipboard_write_failure ()
```

If the application forwards this result asynchronously, its success
continuation must additionally revalidate the original editor/selection
owner before deleting; an ownership result does not authorize a stale edit.
Keep failure handling explicit and never acknowledge an unhandled request.

Call the Linux Shell on the GTK UI thread and continue running `Shell.pump`
there while owning the selection, including when no frame needs repainting.
The existing pump iterates GLib's default main context and serves the data
and clear callbacks; no extra loop, thread, or event API is introduced.
`true` does not promise external paste success, indefinite ownership, or
clipboard-manager persistence after exit. Successful acquisition retains
the old `gtk_clipboard_set_text` helper's `gtk_clipboard_set_can_store`
hint; that void capability hint is not a persistence ACK. No explicit
store/manager handoff is added. macOS retains its existing
`NSPasteboard.setString` BOOL result; other backends and their input limits
are unchanged and are not newly qualified by this Linux change.

## Unreleased: component API and MyGo parity

### Apple drawer swipes can interrupt transitions

Compact Apple drawers now accept a reverse swipe while an opening or closing
animation is in progress. Previously, those swipes were discarded until the
transition completed. The new drag owns the interaction lock, so completion
callbacks and delayed model acknowledgements from the previous transition cannot
unlock descendant controls during it. Vertical gestures and outward swipes keep
their existing rejection rules.

No wire or application code migration is required. Continue acknowledging each
`ToggleChanged` event through the drawer's controlled `selected` property. For
example, after an opening gesture emits `checked=true`, publishing `selected=true`
while the user has begun closing acknowledges that opening gesture without
restarting its animation or cancelling the closing drag.

### Host commands on standard MyGo text editors

MyGo `Config` now accepts two optional, typed hooks:

```go
InputValue   func(Node, *string)
InputControl func(Node, ui.Element, string)
```

`InputValue` runs after ordinary model text reconciliation and immediately
before constructing the native `TextInput` or `TextArea`. It may update that
build's text through the pointer. `InputControl` runs after construction and
input-handler setup, receiving the resulting text for focus and selection
binding. It runs before the existing focus-transition sample, retained handle
binding and autofocus logic; their relative order is unchanged.

Both hooks run synchronously on the UI thread during live construction, never
in `view-that-fits` measurement probes. Do not retain the text pointer, Element
or its Context beyond the call. Nodes are detached read snapshots. Hooks cover
the text-editing paths of `text-field`, `secure-field`, `input`, `search-field`,
`textarea` and `combobox`. They do not run for specialized ColorWell/TimeInput
branches or custom renderers that replace the standard control. Nil hooks
preserve existing behavior; wire vocabulary and other platforms are unchanged.
Existing keyed Config literals need no changes; positional literals must be
updated for the added fields, preferably by switching to keyed initialization.

An imperative value command does not synthesize `OnChange`, `TextChanged` or
Dispatch, and does not persist a new model value. Keep the existing controlled
reducer and ordinary text reconciliation. The host still owns command queues,
node incarnation/epoch checks, invalidation and post-layout `AfterFrame`
acknowledgement/retirement. Publish and apply a node's creation before sending
commands for it; these hooks do not buffer missing references or repair message
ordering. Apply selection to the actual Element during construction. MyGo
selection offsets count runes: DOM-style UTF-16 offsets must be converted by
the host against the text passed to `InputControl`, without splitting surrogate
pairs. Any returned DOM offsets are build-time observations, not a substitute
for querying the native selection during an input event.

For a host with existing incarnation-scoped helpers, configure the standard
renderer rather than copying it or adding component-specific exceptions:

```go
backend := luimygo.New(luimygo.Config{
    Dispatch: runtime.Dispatch,
    InputValue: services.BindInputValue,
    InputControl: func(n luimygo.Node, e ui.Element, text string) {
        services.BindInputControl(n, e, text)
    },
})
```

Here `BindInputValue` has signature `func(luimygo.Node, *string)` and
`BindInputControl` may return UTF-16 `(start, end int)`; the closure deliberately
discards those results. Existing raw/extension renderers retain their own
bindings; the hooks do not duplicate their dispatch or command ownership.

### Bounded and content-sized Stacks on MyGo

The MyGo `stack` adapter now passes its allocated width and height through
each synthetic layer wrapper to its children. A bounded Stack no longer lets
an automatic content-height floor enlarge a nested Stack beyond that allocation.
Stacks without a bounded size still measure to their largest intrinsic child,
and removing that child lets the Stack shrink. Explicit child sizes, minimums,
maximums and margins remain effective; layer order, `z-index`, pointer
pass-through and retained child identity are unchanged.

Keep the finite shell constraint on the outer Stack, and use `grow: 1` and
`min-height: 0` on the inner flow Column and Scroll that share its height.
For example, an outer Stack with `height-viewport: 1` in an 897-DIP viewport,
containing a nested Stack and a Column with a 48-DIP header, now gives its
growing Scroll the remaining 849 DIPs even when the Scroll content is 1280
DIPs tall. Do not repeat the full viewport height on the Scroll: that would
ignore the header's share. Applications that require a content-sized Stack
should continue to leave its size unconstrained rather than add viewport
or fill constraints. No wire vocabulary or other host behavior changes.

### Owned pointer gestures on Row and Box

`row` and `box` now accept `?pointer_capture:bool`, `?on_pointer_down`,
`?on_pointer_move`, `?on_pointer_up` and `?on_pointer_cancel`. Capture defaults
to false. The new wire property is `pointer-capture`; the new events are
`PointerMove (node, detail)` and `PointerCancel (node, detail)`. Both use the
existing `pointer_detail` payload and client-space coordinates. Its modifier
mask is unchanged: Ctrl=1, Shift=2, Meta=4, secondary pointer button=8.

With capture enabled, an admitted primary down owns movement and completion
outside the handle. `PointerUp` means successful release; Escape, host blur,
capture loss, pointer cancellation, disablement and removal cancel instead.
A captured gesture does not activate Press, PressDetail or a context menu.
Handle cancellation by discarding the preview, never by committing it:

```ocaml
box ~pointer_capture:true
  ~on_pointer_down:begin_preview
  ~on_pointer_move:update_preview
  ~on_pointer_up:commit_preview
  ~on_pointer_cancel:discard_preview []
```

Applications should also discard owned preview state when their view unmounts;
a removed node cannot receive subsequent application events. Existing nodes
without capture retain their pointer/press behavior and do not subscribe to
movement or cancellation. The feature is implemented on Web and MyGo; adding
the shared vocabulary does not qualify other native hosts for captured gestures.

The Web DOM setter now accepts `pointer-capture` and clears its capability marker
on removal. The retained property continues to control gesture ownership;
changing or removing it resynchronizes the existing pointer listeners and cancels
any active preview. Native DOM capture still begins only on an admitted trusted
primary down, not when the property is applied. Existing typed handles, including
the example above, require no migration or application fallback.

MyGo's toolkit adds `HandleCapturedPointer` and `InputPointerCancel`. Use this
handler instead of `HandleInput` when successful release must differ from
cancellation. A primary down returning true owns the gesture. Existing
`HandleInput` consumers retain their legacy synthetic-release deactivation
behavior; they are not silently migrated to cancellation.

Row and Box also admit `NavigationKey` when `?on_navigation_key` is provided:
arrows, Home/End, PageUp/PageDown, Enter, Space and Escape, preserving Shift.
No handler means no navigation subscription. Keyboard focus still belongs to
the application's normal typed focus/role configuration.

### Row and Box navigation focus ownership

On Web, MyGo and the Native OCaml window hosts, Row/Box navigation callbacks
only receive keys owned by that focused container, never keys from a descendant
checkbox or editor.
Web stops propagation after an admitted navigation event. MyGo makes an
interactive navigation-enabled container focusable and registers shortcuts
only while its handle owns focus; filtering only inside a subtree shortcut
callback would still consume the child's default key behavior.
Disabled and inert ancestors block navigation. Other controls retain their
existing navigation behavior; no handler still means no subscription.
Applications can replace a container's raw keydown bridge with
`row ~on_navigation_key:handle_row_key ...` without intercepting keys typed
inside child controls. Web containers retain the application's normal
focus configuration, such as `~data_attrs:["tabindex", "0"]`.

Native OCaml makes navigation-enabled Row/Box containers focusable for pointer
and Tab focus. Only the actually focused node receives navigation; child
checkboxes and editors keep their default keys. Disabled/inert ancestors,
hidden containers, modal scope and IME composition block container navigation.
Ctrl/Meta/Alt combinations remain outside this navigation subscription; Shift
is preserved. Existing button navigation and Enter/Space activation are unchanged.

### Checkbox mixed state and modifier-aware proposals

Checkbox gains `?indeterminate:bool` and its reactive binding, defaulting to
false. The wire property is `indeterminate`. This is presentation and
accessibility state; it never changes accepted `checked`. Activating a mixed
checkbox proposes true. The next model update decides whether to retain or
clear the mixed state.

`?on_toggle_detail` opts in to `ToggleChangedDetail (node, checked, modifiers)`
through `toggle-detail-enabled`. Its independent physical-key modifier mask is
Ctrl=1, Shift=2, Meta=4, Alt=8; it must not be interpreted as the legacy
PressModifiers/pointer mask, whose bit 8 denotes a secondary pointer button.
The existing `?on_toggle`, bool `checked`, and `ToggleChanged` event are
unchanged. If both handlers are installed each receives one proposal; do not
apply the same state transition twice. With no detail handler no detail event
is emitted.

The Web DOM setter now accepts `toggle-detail-enabled` and clears its capability
marker on removal. This fixes a render failure for typed `~on_toggle_detail`
subscriptions; existing consumers require no migration or event fallback.

Mixed rendering and accessibility state are currently implemented only on Web
and MyGo. Those hosts also implement mixed-to-true proposals and
`ToggleChangedDetail` events.
Apple and Android recognize the shared property vocabulary and perform typed
admission; this does not qualify them for these behaviors.

The Native OCaml window input path now supports mixed-to-true proposals and
opt-in `ToggleChangedDetail` for primary clicks and focused Enter/Space
activation, including the physical Ctrl/Shift/Meta/Alt mask above. It does not
mutate accepted `checked` or `indeterminate`; a model echo decides the state.
Disabled/inert ancestors suppress checkbox activation. Legacy bool-event
admission is preserved, and without `toggle-detail-enabled=true` no detail event
is emitted. This qualifies only the window pointer/keyboard input contract,
not native mixed painting, accessibility state or accessibility-action producers.
Native consumers can use the typed `~on_toggle_detail` example below without
an application-level event fallback; handlers that also subscribe to `~on_toggle`
must still avoid applying the proposal twice.

```ocaml
checkbox ~checked:all_selected ~indeterminate:some_selected
  ~on_toggle_detail:(function
    | ToggleChangedDetail (_, checked, modifiers) ->
        select_rows ~range:(modifiers land 2 <> 0) checked
    | _ -> ()) []
```

### Pending-aware application model reads

`Lui_app.model app` now returns the latest reduced model even before a pending
signal update is published. This applies to regular, extension-enabled and
reloadable application constructors. Reading the model does not flush the
scheduler, run view updates or emit patches; view signals keep their existing
batched publication semantics.

An async context fence can capture `(Lui_app.model app).context_revision` before
starting a request and read it again before accepting the response. The revision
must be incremented by the reducer for every context publication, including an
A-to-B-to-A sequence in one flush. A published view signal cannot replace this
fresh read because intermediate updates may be coalesced. Existing callers that
read after `Lui_app.flush` require no changes; callers that intentionally need a
published view snapshot must read their borrowed model signal instead.

### MyGo transparent dynamic anchors

`box` nodes with `display="contents"` now render their children directly into
the current native parent, without creating a MyGo `Column` or consuming a
native element key. These are the transparent structural anchors emitted when
reactive, conditional or keyed branches nest. For example, the retained tree
`text -> box(display=contents) -> text` renders as inline text rather than
panicking when MyGo encounters a box inside a text paragraph.

The retained anchor, parent links, descendant order and incarnation keys remain
intact. Appearance still dispatches once per committed incarnation, never from
an unselected fitting probe; hidden anchors suppress their subtree and retired
incarnations remain stale. The anchor has no native bounds, focus target or
independent pointer surface. Box layout and paint properties do not create a
surface for it; put those properties and direct native interactions on a real
container or descendant instead. Retained ancestry remains available to hosts
and continues to enforce disabled/inert event filtering.

No OCaml API, wire format, dependency pin or application migration is required
for generated dynamic anchors. Do not replace the enclosing `text` with a
column or flatten arbitrary boxes as a workaround. A real `box`, `icon` or
other non-text child remains invalid inside native text, even through a contents
anchor; put it beside the text in a typed row. This change applies specifically
to structural `box` anchors, not to all component kinds with a display prop.

### MyGo authored switch chrome

Switches with authored dimensions, padding, foreground, background, border or
corner radius now use MyGo's public `SwitchBase` for their input, focus and
accessibility behavior. The shared renderer sizes the thumb inside the authored
padding and resolves its color from `foreground`, including scoped theme tokens
and existing state foreground overrides. The track continues to consume the
ordinary background, border and radius properties. Layout-only placement and
semantic class names do not select this rendering path.

For example, a `switch` with `width=32`, `height=18`, `padding=3` and
`foreground="var(--background)"` now has a 12-DIP thumb painted in the resolved
background color, rather than MyGo's default white thumb. Its checked state,
`toggle-enabled` subscription, disabled behavior and `toggle-changed` proposal
and acknowledgement contract are unchanged. Removing the authored chrome
properties restores the default MyGo `Switch`; switches without those properties
retain their existing native look. No wire or dependency-pin changes are needed.

### MyGo spacer hit transparency

`spacer` is a layout void and no longer owns pointer hits, matching the Native
and Web hosts. Internal `stack` and `overlay` placement wrappers are also
hit-transparent; real descendants still receive input normally. This fixes
full-window placeholders covering otherwise active controls. No wire or event
subscription changes are required. For example, `stack [button; spacer []]`
now lets the button receive native activation and document click capture;
preventing that capture still cancels the activation.

Ordinary transparent `box` nodes retain their existing hit behavior. Do not use
`spacer` as an interactive surface; use a container or control instead.

### MyGo inherited pointer policy

The MyGo adapter now maps the existing `pointer-enabled` protocol to MyGo's
public `Element.PointerEvents(bool)`: false suppresses the entire native
subtree, including internal captions; unset descendants inherit; explicit true
opts a subtree back in. This applies to standard nodes and raw extensions
bound with `Backend.BindHostElement`. No wire changes or Logseq-specific
workarounds are needed.

As on Native, presented `dialog`, `sheet`, `popover`, `dropdown-menu`,
`context-menu`, `toast` and drawers without a `selected` prop default to enabled
below a disabled ancestor. Explicit false still wins, and a permanent host
marked `data-overlay-layer=true` never implicitly opts in. For example,
`overlay ~pointer_enabled:false [button ~pointer_enabled:true ...]` accepts
input only in the opted-in button; other controls and native labels remain
transparent. Existing ordinary containers without a pointer policy retain
their previous hit behavior. Capture returning true still cancels activation;
paint, layout and keyboard focus are unchanged by the pointer policy.

Embedding hosts must select the same MyGo fork version as this adapter in
their root `go.mod`; Go does not inherit dependency replacements. The fork
must provide both `Element.PointerEvents` and the bounded-row
`ListState.Requested`/`SetKeyIndex` APIs. The integrated pin retains both
contracts, plain-hit document click capture and the native handle-lifetime
fixes; choosing an older pointer-only or bounded-row-only candidate is not a
compatible substitute.

### MyGo decoded image dimensions

Embedding hosts can call `Backend.NaturalImageSize(id)` on the UI goroutine to
read `(width, height, ready)` for standard `image`, `file-image` and `avatar`
nodes. Dimensions come from the current decoded pixels, including any
`max-pixel-size` downsampling, not layout size, cropping or avatar placeholders.
URL/path assets must match the current retained node's source and decode limit;
drop/recreation and snapshots discard that node's decoded state. Host-registered
images use the current image registration only when no URL takes precedence.

The query performs no I/O and starts no decode. Pending, lazy/unloaded, failed,
stale, unsupported, missing and closed resources return `(0, 0, false)`. Query
again after a frame processes the renderer's normal decode completion; do not
acknowledge an unavailable result as a guessed size or decode the source again.

### MyGo host theme defaults and authored variables

Embedding hosts can install per-window defaults with
`Backend.SetThemeDefaults(map[string]string)` between frames on the UI goroutine.
The map is copied and replaces previous host defaults; `nil` clears it. These
defaults do not change model-owned nodes or emit patches. Scoped `theme` props
override them only inside that subtree. Native widget semantic slots now use
the same defaults as explicit typed paint properties, including focus/status
colors. No application migration is required when host defaults are unused.

`ComputeThemeVariables(parent, declarations)` computes custom properties before
inheritance, invalidates cycles (including unused fallback references), and
handles `initial`, `inherit` and `unset`. `ResolveThemeValue(value, computed)`
substitutes nested `var()` expressions and empty fallbacks. These APIs process
declarations, not selectors, layout, utility classes or a stylesheet cascade.
Hosts must supply their authored palette and application layers explicitly.

Custom renderers can call `Backend.ResolveColor(context, value)` during their
build to use the current scoped tokens, adaptive colors and functional CSS
colors. Unknown values/cycles return an error rather than a successful default.
The existing internal fallback for unresolved standard paint values is unchanged.

Authored `font-family`, `font-size` and `line-height` now substitute `var()`
against those same scoped tokens before calling native typography APIs. This
includes nested fallbacks and adaptive values. Invalid substitutions leave the
native inherited/default typography unchanged instead of passing unresolved
expressions as font names. No host API or wire changes are required.

MyGo also accepts `em` typography lengths on the existing native 16-DIP baseline,
matching its `rem` handling and the OCaml native text adapter. These units are
not browser-style ancestor-relative computed lengths. Unitless `line-height`
remains a font-size multiplier; `px`, `em` and `rem` line heights are fixed DIPs.

### MyGo document input capture

Hosts can install `ui.Context.CaptureInput` once per view build and resolve its
opaque target with `Backend.InputNode`. This matches the actual committed focus
or hit ancestry, including internal children of standard controls and extension
elements registered with `BindHostElement`; it never infers targets from boxes.
The resulting `InputNode.Node` is a snapshot. Check `InputNode.Current()` before
using a saved press or deferred event: removing and remounting the same numeric
node ID invalidates it. Use only on the UI thread. The MyGo target itself expires
as soon as its capture callback returns.

This API needs MyGo's public `CaptureInput`/`InputTarget.Distance` API. Hosts must
update that dependency alongside this change. Existing element input callbacks
continue to run unless capture returns true. Observational capture must return
false so focused controls retain editing, IME, clipboard and native menu commands.
Do not also forward the same DOM event from a local extension handler: dispatch
once through the application's existing document capture/bubble implementation.

The pinned MyGo also reports one capture-only `InputClick` on ordinary live hits
without native gestures, such as a `column` or a bound raw `ui.Box`. The same
committed hit incarnation must remain enabled and hit-testable through release;
a drag, prevented down/up, window blur, removed capture or retired hit cancels
the candidate. Native buttons retain their existing activation/default rules.
Hosts that synthesized clicks for plain nodes or attached placeholder `OnClick`
handlers solely for document delegation must remove those workarounds. Keep one
`CaptureInput` -> `Backend.InputNode` -> document dispatch route; do not add native
press/focus semantics to ordinary content just to observe its click. Embedding
root modules must select the adapter's updated MyGo replacement as well.

The pinned MyGo also keeps built-in inspector input private to developer tools.
Application `CaptureInput` no longer observes inspector-focused key down/up,
text, composition or commands, or pointer/scroll hits in the committed inspector
subtree. A press on an inspector control stays isolated when moving or releasing
outside the panel. Inspector native controls still receive their input even if
application capture would prevent it; application targets retain their normal
capture and default-prevention behavior. Remove host-side forwarding of inspector
input to document shortcuts; do not install application handlers on the inspector
to work around this boundary. No LUI wire schema or host callback change is needed.
As Go does not inherit replacements, embedding applications must update their
root `go.mod` along with this adapter, for example:

```go
replace github.com/egoist/mygo => github.com/logseq/mygo v0.0.0-20261026012209-183f6afcb33a
```

### MyGo committed menu owners and scroll observation

`Backend.OpenMenuOwners(c)` returns unique, ID-sorted `InputNode` snapshots for
actual still-open native menus, retained context menus, dropdowns and popovers.
Call after final layout (for example in `AfterFrame`) or between frames on the
UI thread. An `AfterFrame` callback may be registered before `Backend.View`;
reading committed ownership does not depend on text-record callback ordering.
Only actual presentation builders register candidates; the query
checks native active/committed-pending presentation state or retained dismissal
state plus committed panel and owner identities. It does not scan the retained
tree, infer opening from widget existence, measure bounds, or change input.
Probes, omitted panels, hidden/inert/disabled owners, closed presentations and
retired incarnations do not resolve. Before a changed model has committed, the
query returns no owners rather than mixing model and presentation generations.

Native/context menus report their host. Dropdowns report the actual trigger or
placement anchor; a popover's `anchor-target` resolves outside its portal too.
A coordinate-only popup has no retained external anchor, so its own retained
popup node is the presentation owner. Supply a real `anchor-target` when a host
must protect a triggering row; coordinates never imply that row's identity.
Do not retain the result as an open-state cache: query each committed frame and
check `InputNode.Current()` before using a saved snapshot. Same-ID recreation
does not revive an earlier incarnation. Protect only the returned owners and
their actual retained ancestors, not every menu/widget node or the whole tree:

```go
c.AfterFrame(func() {
    for _, owner := range backend.OpenMenuOwners(c) {
        if owner.Current() {
            pinRetainedAncestors(owner.Node.ID)
        }
    }
})
```

`Backend.CommittedScrollOffset(c, id)` returns `(x, y float32, known bool)` for
any actual committed scroll host, including a normal `box` with `overflow:auto`.
It reads MyGo's public `Handle.ScrollOffset(c)`, not private engine state or
geometry differences. Call after layout on the UI thread. Non-scrollers,
probes, hidden, missing, stale and uncommitted hosts report `known == false`;
zero with `known == true` is a real scroll start. The axes match `ScrollState`.
Do not infer scroll end from an unknown value:

```go
if x, y, known := backend.CommittedScrollOffset(c, containerID); known {
    observeCommittedOffset(containerID, x, y)
}
```

The older `Backend.ScrollOffset(id)` still reads retained typed scroll state,
including an unapplied `ScrollTo`; its errors and all scroll command/token
semantics are unchanged. Migrate viewport observations to the new committed
query, but do not replace command handling. These APIs need the adapter's new
MyGo pin (`Context.NativeMenuOpen` and `Handle.ScrollOffset`); embedding root
modules must update their replacement too, since Go does not inherit it. No
LUI wire schema, default input or event forwarding changes are required.

The same MyGo pin finalizes Handle identity only after actual committed layout,
including deferred `view-that-fits` and virtual rows. Hosts can read public
`Bounds`/`FocusWithin` from `AfterFrame` without replaying input or focus, eagerly
building rejected candidates, or fabricating geometry. Omitted bindings and
same-ID recreated owners cannot keep an old committed identity alive.

### Bounded row generation for virtual lists

`virtual_list` continues to accept literal children and `keyed` sources. Those
forms retain every LUI row even when the host virtualizes its views. Applications
with large collections can opt into `virtual_rows` as the sole direct child:

```ocaml
(* Before: every item owns a mounted LUI row. *)
virtual_list ~height:400 [
  keyed ~source:rows ~key:(fun row -> row.id) ~cmp:Int.compare ~mount:row_view
]

(* After: the host requests a window of rows. *)
virtual_list ~height:400 ~overscan:5 ~item_extent:32. [
  virtual_rows ~source:rows ~key:(fun row -> row.id) ~cmp:Int.compare
    ~scroll_key:(fun row -> Printf.sprintf "row-%d" row.id)
    ~mount:row_view ()
]
```

The business data source and its key index remain complete. On Web, MyGo,
SwiftUI and Kotlin hosts that advertise window feedback,
only requested rows, overscan and active interaction pins own mounted scopes,
signals, handlers and host controls. Overlapping windows preserve row identity;
eviction disposes the row and a later visit creates a fresh incarnation.
Store persistent editor values, selection and other row state in application
data and bind them as controlled values. Late events cannot target a replacement
incarnation. Source reorders preserve still-existing mounted keys until the host
acknowledges the new source generation.

The source signal is borrowed. A `reactive` derivation passed as `~source` is
created and disposed per mount by the PPX, following the same ownership rule as
`keyed`. Rebuild the PPX together with LUI. `scroll_key` is optional unless a
lazy parent uses a nonempty `scroll_target`; it resolves targets without mounting
intermediate rows. Duplicate item keys or scroll keys are errors.

Updated SwiftUI and Kotlin hosts implement the same bounded source contract.
Literal children and the older application-managed window conventions retain
their existing behavior. An individual row may still own a large descendant
subtree, and host geometry caches may scale with source size.
Virtual rows require positive logical geometry: a zero-height or empty root
keeps a positive estimate or a host minimum of one pixel. This avoids
repeatedly expanding the mounted window when blank rows collapse during layout;
positive compact rows retain their measured heights.

Custom hosts must recognize the new `MyGoHost` case when matching
`host_kind`. Existing host cases keep their order; native host code 5 selects
MyGo. The MyGo loader selects that profile only if the optional
`lui_ocaml_virtual_window(node,generation,first,last,pins,count)` export exists;
older application libraries keep the Generic eager profile.

SwiftUI and Kotlin retain their semantic platform profiles, including native
extension selection. Their native startup handshake uses these codes:

| Host | Legacy code | Bounded-row code |
| --- | --- | --- |
| SwiftUI | 2 | 258 |
| Kotlin | 4 | 260 |

The new C export `lui_ocaml_virtual_rows_version()` returns 1 and is safe to
probe before starting the runtime. Updated Swift loaders select code 258 only
when this optional export is available. The Android JNI bridge exposes the
corresponding optional version probe before selecting code 260. Older libraries
and older host clients keep codes 2/4 and receive the complete eager collection.
Rebuild the OCaml application, native bridge and updated host together to enable
bounded rows. An unrelated or unknown host code does not enable this capability.

`Lui_app.create`, `create_with_extensions`, `create_reloadable` and
`create_reloadable_with_extensions`, and both `Lui_runtime.create` constructors,
accept an optional `~virtual_rows:bool` override. The default is true for Web,
MyGo, SwiftUI and Kotlin profiles and false for Generic. The override is fixed
before mounting the view and persists through reload without changing the host
profile. Custom native initializers must pass the negotiated capability:

```ocaml
let host_profile = Lui_native_bridge.profile platform_code host_code in
Lui_app.create
  ~virtual_rows:(Lui_native_bridge.virtual_rows_supported host_code)
  (Lui_native_bridge.backend bridge host_profile)
  initial_model reducer view
```

A custom Generic host may explicitly opt in after implementing the complete
window protocol. Passing false preserves eager behavior on any semantic host.
Code constructing a runtime record directly must account for its new immutable
`runtime_virtual_rows` capability; prefer the runtime constructors.

Custom Swift event switches and Kotlin sealed-event handlers must forward the
new `virtualWindow` / `VirtualWindow` maintenance event to the native window
entry point, independently of application visible-range subscriptions.
Apple's legacy C event callback appends kind 20 with legacy node argument 0;
its JSON object carries authoritative integer `node`, `generation`, `first`,
`last` and `pins` fields so IDs are never narrowed to the callback's Int32 node.
The typed Swift event and the native OCaml window ABI retain full native integer
precision. Existing ordinary callback kinds remain unchanged.

Sparse wire producers set `virtual-total-count`, `virtual-generation` and
`virtual-indices` together on the existing `virtual-list` node. The indices are
a canonical JSON integer vector parallel to committed children, strictly
increasing and within the logical count. Optional `virtual-scroll-index` is -1
for a missing target or a valid logical index. Invalid final metadata rejects
the entire batch. Internal `VirtualWindow` feedback uses a half-open interval
and direct row node IDs for pins. Public `VisibleRange` keeps its inclusive
range convention. The new event precedes `ExtensionEvent`; native consumers of
raw OCaml variant tags must rebuild for its shifted extension-event tag.

### Native host compatibility

Updated Apple hosts accept the existing `navigate-enabled` flag on buttons and
the canonical text-entry kinds. Updated Kotlin hosts accept the existing
`navigation` and `navigation-heading` list-item roles, with native selected-item
and heading accessibility semantics. These properties already come from LUI
constructors and the shared Gallery; applications need no source changes.
Custom native validators must preserve the canonical finite kind and role sets
when accepting sparse virtual-list metadata.

Kotlin ordinary lists use intrinsic column layout when their parent provides
unbounded vertical space, preserving the outer scroll owner. Finite viewports
retain native lazy-list scrolling and row targets. Applications can keep an
ordinary list inside `scroll` without adding an artificial fixed height.
Authored compact list-item heights preserve readable text by removing native
vertical content padding while retaining horizontal insets and native input.
Sparse Kotlin collections expose the supported native forward/backward scroll
actions on their viewport even when interactive rows cover its content.

The Apple C bridge now closes its ARC-owned window safely during reset.
The existing reset entry point and application lifecycle API are unchanged.

### Large-batch memory and handle ownership

The shared OCaml encoder and MyGo decoder now process large batches without
retaining per-operation JSON copies. MyGo applies JSON operations directly in
its rollback journal instead of retaining a complete operation array, and the
native receiver reads its owned wire string without another full byte copy.
Duplicate fields, final generation checks and complete-document validation
retain their existing atomic semantics. Wire bytes, integer precision and
application APIs are unchanged. Rebuild application libraries to include the
encoder improvement.

MyGo also releases abandoned handle bindings while preserving live hidden
handles and pending focus. Embedded Go applications must update their root
replacement to `github.com/logseq/mygo@v0.0.0-20261025230925-e952b021e9be`, as shown
in the [embedding guide](../platform/mygo/README.md#embed-a-backend). The upstream
module path and application imports remain unchanged.

### Nested toolbar focus ownership

On Web, a toolbar owns one keyboard Tab stop across its nested button and toggle
groups. Group refreshes no longer create additional stops after model updates;
arrow navigation continues through the complete toolbar sequence. Standalone
groups retain their own roving focus behavior. Applications need no source change.

### Toast keyboard dismissal

On Web, Escape now dismisses the open toast containing keyboard focus, matching
MyGo. Escape outside a toast, during IME composition, or after another handler
consumes the event leaves notifications open. Applications should handle the
existing dismiss event by removing that toast from their model. Independent
notifications retain their own lifetimes.

The Gallery now demonstrates one notification per activation and disables its
trigger while open. Its four-second duration is demo configuration; component
defaults are unchanged.

### Virtual-list configuration becomes typed

The OCaml constructor keeps its existing optional arguments:

```ocaml
virtual_list ~overscan:0 ~item_extent:32. rows
```

Previously these arguments generated `data-overscan` and `data-item-extent`
attributes inside `data-attrs`. They now generate the `overscan` integer and
`item-extent` float properties. `overscan` must be nonnegative; zero disables
extra rows. `item-extent` must be positive and finite and estimates unmeasured
rows; actual row measurements remain authoritative.

Applications using the constructor need no source change. Custom hosts and
wire consumers must recognize the two new properties. Legacy semantic
attributes remain readable during migration. Explicit typed properties take
precedence; removing a typed property restores the legacy attribute or host
default. Removing both restores the default. The MyGo default overscan is five
rows on either side; the fallback item estimate is 32 logical pixels.

Prefer constructor arguments over hand-written semantic attributes:

```ocaml
(* Before *)
virtual_list ~data_attrs:[ "data-overscan", "3" ] rows

(* Preferred *)
virtual_list ~overscan:3 rows
```

### Read-only editing is distinct from disabled editing

`text_field`, `secure_field`, `input`, `search_field`, `textarea` and `combobox`
gain `?read_only:bool` and reactive `?read_only_signal` bindings. The default is
false. Read-only controls preserve focus, selection, copying and navigation;
they reject user edits and do not emit text-change proposals. Application model
updates can still replace their displayed value. `disabled` continues to block
interaction.

Secure fields retain their password-copy restrictions in read-only mode.

```ocaml
text_field ~text:"Reference value" ~read_only:true []
textarea ~text:(reactive Model.notes model)
  ~read_only:(reactive Model.locked model) []
```

JSON views use `"read-only": true`; custom hosts must decode the `read-only`
boolean property. Removing it restores editable behavior. Applications that
used `disabled` solely to prevent edits may switch to `read_only` when users
should retain selection and copying.

### Controlled proposals require model acknowledgement

NSH desktop Split uses native wanted sizes and completion notifications instead;
see [NSH native panel Split](#nsh-native-panel-split) for its explicit exception.

MyGo controls now reconcile after each input callback, including callbacks that
produce no patch. If an application leaves `text`, `value`, `checked`, `selected`
or expansion state unchanged, its proposal is rejected and the control restores
that value. Accepted or normalized model values become the next displayed value.
Caret, focus and active IME composition remain host-owned.

Applications that previously relied on a no-op callback to keep a toolkit edit
must store the proposal in their model and bind the corresponding property.
For example, use `~on_input:(on_input send (fun text -> SetText text))` together
with `~text:(reactive Model.text model)` rather than a no-op input callback.

### MyGo validates complete final node contracts

MyGo now follows canonical LUI per-kind property and child rules, including
required labels, finite values, paired anchors, complete image crop regions,
consistent size/range constraints and exclusive split sizing modes. Validation
occurs against the final batch state, so property order and temporary
incompleteness inside a batch remain valid. Rejected batches preserve the live
tree and control identity.

Custom wire producers must fix invalid batches previously accepted by the
MyGo adapter. Examples: a button needs nonempty text or an accessibility label;
a table contains rows and each row contains cells; a text field may host a
context menu but cannot contain arbitrary controls; a split cannot set both
`value` and `first-pane-width`. Public constructors continue to supply the
appropriate interaction flags. Their validation now matches canonical event
support for text, numeric and toggle controls.

### Tabs, lifecycle and scroll results

Ordinary `tabs` keep their application-owned content. Arrow keys activate the
new focused tab, respecting orientation and disabled items. `bottom_tabs`
renders the selected retained tab's page. Applications must keep `selected`
under model control.

Scroll completion outcomes are `succeeded`, `cancelled` and `missing-target`.
Visible ranges use inclusive `first`/`last` indices and `0`/`-1` for an empty
viewport. Request tokens and appearance events are scoped to a node incarnation;
reusing an ID after removal does not revive old queued callbacks. Scroll request
tokens preserve exact OCaml integers, including neighboring values above 2^53;
each distinct token starts a new request.

### MyGo image and media ownership

The Go host registers ordinary pixels with `RegisterImage` and video frames
with `PresentMediaSurfaceFrame`. IDs must be positive and pixels non-nil. Both
methods copy caller buffers before publication. Calls belong to the UI
goroutine. Invalid replacements preserve the previous valid resource;
`UnregisterImage` and `UnregisterMediaSurface` retire it. Standard image and
media nodes no longer need application renderer registrations.

### MyGo compatibility module and custom icons

The desktop adapter pins the [logseq/mygo compatibility fork](https://github.com/logseq/mygo/tree/lui-bounded-virtual-rows)
for measured fitting, tunable lists, frame completion and native lifecycle
behavior. The fork preserves the upstream `github.com/egoist/mygo` module path,
Go imports and upstream documentation links. Existing Go and OCaml application
imports are unchanged.

The adapter selects the immutable fork version with a Go `replace` directive.
Go does not inherit dependency replacements: applications embedding this adapter
must copy its MyGo replacement into their own root `go.mod`. See the exact
[embedding commands](../platform/mygo/README.md#embed-a-backend). No vendored
source checkout is required.

Canonical icons remain built in. Custom `app:slug` icons use
`RegisterIcon(name,svg)` and `UnregisterIcon(name)`. Registration copies and parses
SVG data; invalid replacements preserve the previous icon. These are host
resource APIs and do not require a component renderer override.

### MyGo host disposal and file services

Go hosts must call `Backend.Close()` on the UI goroutine after closing their
OCaml `Runtime` session. Closing is idempotent. Committed node removal and
snapshots cancel node-owned asynchronous work immediately; failed batches do
not cancel live work. Host-registered image/media IDs survive snapshots and
are released by explicit unregister calls or backend closure.

The optional `Config.FileServices` interface replaces only the operating-system
file dialog boundary; the default implementation uses MyGo native dialogs.
Standard picker and preview nodes need no application renderers. Picker request
and completion tokens keep their original string/integer type and exact value;
applications acknowledge a result by setting `completion` to its request token.
Tokens already acknowledged on mount do not launch another dialog.

Desktop file previews are owned LUI presentations with dismissal, selectable
UTF-8 text, raster images and paginated PDF rendering. They do not launch an
external application. Unsupported or missing files show an owned error view.
Native macOS dialog cancellation has been verified against a real NSOpenPanel.
Other host live-service qualification remains tracked in the support inventory.

### Complete native event payloads

The MyGo bridge now carries pointer details, navigation keys, scroll completion,
visible ranges, scroll edges and picker payloads through the actual OCaml event
subscriptions. Strings preserve UTF-8 and embedded NULs; integers preserve values
above JavaScript's exact-number range. Invalid coordinates, modifier/button
values, ranges and native integer/length overflows are rejected before native
entry.

Existing C-string pointer exports remain available to existing hosts. New
length-carrying `lui_ocaml_*_utf8` pointer exports carry `target_class` without
truncation. Custom native bridge loaders targeting the new MyGo host must link
the matching rebuilt application library rather than an older cached binary.

## PR #271: removed line-break component

The `br` component, OCaml constructor and standard wire kind were removed.
Replace separate-line content with a `column`, or use a newline inside one text
value when it belongs to the same text run. Do not register a custom standard
`br` renderer: it does not restore a removed protocol kind. Raw HTML extensions
keep their independent HTML element rules.

## MyGo production host services

Desktop adapters can use `Backend.Bounds`, `RequestFocus`, `ScrollTo` and
`ScrollOffset` on the UI thread instead of relying on demo-only geometry hooks
or inspecting backend state. `Bounds(c, id)` reports window DIPs from committed
layout, with `false` for missing, hidden, unmounted or closed nodes. Measure
after a committed frame; do not treat unavailable geometry as a zero rectangle.

`RequestFocus(id)` requests focus for the current retained node, including before
its first render. It is not a focus acknowledgement. Unknown or dropped nodes
are errors; requests do not survive drop/recreation or a replacement snapshot.
`ScrollTo(id, x, y)` accepts finite DIPs on scroll/list/virtual-list nodes and
clamps to the content at layout. It rejects an active token-controlled scroll;
replace those requests through the standard scroll-token protocol instead.

Extensions and custom renderers opt into host services by binding their primary
control during rendering:

```go
element := ui.Box(c).Focusable()
if err := backend.BindHostElement(node.ID, element); err != nil {
    // Propagate this adapter error; do not claim a focus or geometry result.
    panic(err)
}
```

Standard nodes are already bound. Existing extension renderer signatures and
wire schemas do not change. No model-controlled text/selection is mutated by
these services; editors must obtain source and selection from their model.

## MyGo committed text geometry

`Backend.TextGeometry(context, nodeID)` exposes the retained text actually
painted by MyGo, including a text node's range in a rich inline paragraph.
Use it after layout (`Context.AfterFrame`) or between frames on the UI thread.
It returns `(ui.CommittedText, bool)`: missing, hidden, unmounted, closed or
patched-but-not-committed nodes report false. The value expires at the next
MyGo build; every query then reports false. Do not retain it across builds.

`Text`, `Caret`, `SelectionRects`, `IndexAt` and `Lines` use rune offsets
relative to the bound text node, and window-space DIPs including scrolling
and transforms. Applications with UTF-8 byte or UTF-16 model offsets must
convert at their own boundary, and map atomic/decorative runs explicitly.
The API never shapes a second approximation or owns an editable document.
Requires MyGo's public `Handle.TextGeometry` / `CommittedText` API.
`Backend.CommittedBounds(context, nodeID)` follows the same generation guard
and reports the transformed window-space box for non-text container origins.

## MyGo live native-input snapshots

`Backend.InputTextSnapshot(context, nodeID)` returns `(text, anchor, caret, ok)`
from the actual native TextInput/TextArea edit state. Unlike committed geometry,
it includes already-consumed edits before the next layout/bound-value update.
It does not process queued input, mutate selection, or cache model text. Text
excludes marked/preedit content; anchor/caret count runes, retain direction,
and must be converted explicitly for UTF-8/UTF-16 application protocols.
This trusted host query also reads secure-field text without redaction.

The window-stable `ui.Context` may be retained for this specific UI-thread query
in `CaptureInput` before default handling or `OnChange` after input. This does
not make build APIs or retained `ui.Element` queries safe in callbacks.
Requires MyGo's public `Handle.TextSnapshot` API; no wire schema changes.

```go
if text, anchor, caret, ok := backend.InputTextSnapshot(windowContext, nodeID); ok {
    dispatchInputSnapshot(text, anchor, caret)
}
```

Standard native fields are bound automatically. A raw/custom renderer must call
`backend.BindHostElement(node.ID, input)` on its actual native input each build,
before registering handlers; do not bind an enclosing box or a substitute buffer.
Unavailable, hidden, disabled, retired, remounted-before-commit, non-input and
closed nodes report `ok=false`. There is no stale-model fallback. Ordinary patch
generation changes do not invalidate this live query; drop/recreate and snapshot
replacement retire the binding immediately. Re-render to bind the new incarnation.

## Upgrade checks for application maintainers

1. Update generated wire schemas and custom host decoders together with LUI.
2. Replace uses of `br` and invalid retained child shapes.
3. Prefer typed virtual-list arguments; test any legacy attribute overrides.
4. Review disabled editors that should allow copying.
5. Exercise model rejection/normalization, keyboard navigation, resource
   replacement and stale async callbacks on each host the application ships.

The existing DOM backend remains available. MyGo's browser renderer requires a
separate browser runtime bridge; the desktop dynamic-library bridge cannot be
used directly in a browser.

## Apple virtual-list viewport changes

Apple virtual lists now recompute row visibility when the viewport height changes,
even when the row's frame stays unchanged. Initial layout and keyboard/viewport
transitions no longer leave visible top rows outside the emitted `VisibleRange`.
The event shape and virtual-window metadata are unchanged; applications need no
API migration. Applications with bounded windows should verify initial page load
and keyboard transitions without scrolling to repair the visible window.

## Apple search input traits

Apple `search-field` controls disable automatic capitalization and spelling
correction so a literal query is not silently changed by the keyboard. Inline
controls use the Search return key; navigation/list-hosted native search retains
its existing search submission. Ordinary `text-field` and `textarea` behavior is
unchanged. No schema, event, query normalization or matching semantics change.

Applications should use `Lui_elements.search_field ~on_submit:run_search []` for
search rather than `text_field`. Keep `on_input` bound to the shared query and
`on_submit` to the search action. Do not set `submit_on_enter` on either
single-line kind; that property belongs only to `textarea`.

## Web virtual-list resize measurements

Web virtual lists process TanStack ResizeObserver measurements in an animation
frame rather than synchronously inside the observer callback. Rendering a
measured row can resize an intrinsically sized list; deferring that render avoids
ResizeObserver delivery loops when switching views or changing row dimensions.
Initial layout, wire properties and event payloads are unchanged. Resize-driven
visible ranges and virtual windows can arrive on the next animation frame.

Applications should continue to use `virtual_list ~item_extent:320. rows` and
respond to `on_visible_range` rather than expecting the DOM range to change
synchronously with a browser resize notification. No API or schema migration is
required; other hosts are unchanged.

## Primary pointer capture retains non-primary events

Web and MyGo Row/Box `pointer-capture` no longer filters out non-primary
`PointerDown`/`PointerUp`. The LUI handler does not start or end its primary drag
state for those buttons. MyGo keeps translating its secondary button to protocol
button `2` and its middle button to protocol button `1`. This does not add
simultaneous-button gesture support to the underlying native SDK.

Applications can keep `~pointer_capture:true` for primary dragging and handle
`PointerUp (_, detail)` with `detail.button = 1` for middle-click actions. Do not
assume that a captured control filters out non-primary releases. No property,
event payload or primary drag/cancellation API changes are required.

## NSH scoped themes and canonical presentation

The NSH renderer now translates canonical layout and paint properties through
one checked style compiler. Previously, kebab-case edge spacing and several text
properties could be accepted but ignored by the native style-name parser.
Explicit edges now override axis spacing, which overrides all-edge spacing.
`main="space_between"` maps to native `space-between`; `font-style="oblique"`
retains the existing desktop italic equivalent. Font weights retain the canonical
1–1000 value rather than the NSH string parser's 100–900 clamp. Viewport fractions
use the actual renderer root's measured size and follow window resizing.

The existing `theme` wire value remains a JSON object encoded as a string: each
token is a string or a `{ "light": "…", "dark": "…" }` pair. Nested themes merge
over their ancestors and NSH's semantic token defaults. Bare token names, literal
CSS colors and `var(--name, fallback)` references are resolved in the effective
scope; authored data colors remain literal colors. A nested `theme-mode` applies
only to its subtree. Native control parts receive that same scoped theme, and
dialog/sheet dimensions apply to the visible panel. These updates preserve the
native identities of existing children and editors.

For example, keep a foreground bound to its semantic name instead of replacing
it with a resolved color in application state:

```ocaml
Lui_elements.themed
  ~tokens:[ "brand", Lui_ui.Adaptive { light = "#123456"; dark = "#abcdef" } ]
  (Lui_elements.column ~foreground:"brand"
     [ Lui_elements.text ~value:"Scoped content" [] ])
```

Invalid theme/style values reject the entire native patch before publication;
the committed tree, native identities and generation remain unchanged. Native
gaps now fail explicitly instead of silently dropping the property: CSS inline
display modes and `contents`, `white-space`, `overflow="auto"`, nonzero
`container-relative-frame-inset`, inert subtrees, shadows requiring inherited
`currentColor`, and parallel transitions with distinct timings are not yet
implemented. Use maintained explicit `scroll` containers for scrolling. Supported
parallel transitions share duration, delay and easing; reduced motion sets their
native duration and delay to zero. Apple, Android and Web behavior is unchanged.

### Retained NSH picker and menu controllers

NSH now renders `select`, `combobox`, `menu-trigger` and their retained
`dropdown-menu` segments. Select keeps the existing application-owned text and
`Press` contract; Combobox keeps controlled text, `TextChanged` and `Submit`.
There is no new options/value wire schema or `Picked` event. A picker may own a
dropdown child or be followed immediately by its model-owned dropdown sibling.
Opening, refusing an open request and removing that sibling preserve the
existing trigger/input native identity. Escape and outside cancellation deliver
the dropdown's existing `Dismiss` event; the application removes its segment.

`menu-trigger` uses NSH Menu, and nested menu triggers use NSH Submenu, preserving
native arrow navigation, disabled-item skipping, focus and action dispatch. Use
one dropdown child per menu trigger. This increment explicitly rejects unowned
standalone dropdowns, Combobox non-dropdown children, menu-trigger icons, and
custom dropdown anchor/point/collision placement instead of drawing a generic
container with incomplete behavior. Keep existing model reducers for picker
visibility and text; no application event migration is required.

### External NSH popovers and anchored hints

NSH `popover` now places arbitrary retained children through the native core
overlay API, using an existing node's accessibility identifier, the preceding
sibling/parent anchor, root coordinates, or a decimal `anchor-rect`. Native
placement, side flipping and collision margins remain in the engine. Repositioning
an open popover keeps its input/editor identity and text. Escape and outside
presses emit the existing `Dismiss`; the model owns removal. Closing returns
keyboard focus to the anchor when the popup held it, while an outside press
keeps the newly chosen focus.

Anchored `tooltip` uses the native hint policy: pointer delay, immediate keyboard
focus visibility and Escape hiding. It takes no pointer events. No new wire
events or popup state API are introduced. This increment explicitly rejects
unanchored tooltip status roles, popovers with `role="menu"`, nonzero
`anchor-alignment-offset`, nondecimal rectangle coordinates, and changing the
anchor source/target of an existing popup. Remount the popup when changing its
anchor target; ordinary placement/offset updates retain its children.

## NSH clock progress at request boundaries

The NSH runtime now sends a monotonic host tick before ordinary events, agent
requests and resynchronization. Previously, repeated input could continually
rearm an unchanged relative wakeup and postpone a pending timer. A timer created
after a long idle period could also consume that earlier idle time at its first
wakeup. Due timer patches now precede the requested action's patches in the same
ordered reply. A refused tick prevents the action and follows existing
diagnostic/resynchronization recovery.

An explicit resync advances the wall clock, then returns one authoritative
snapshot containing any timers fired during that synchronization. Intermediate
clock deltas are superseded by that snapshot.

Application time still moves only through `Lui_clock.tick` and explicit advances.
Pausing ignores host ticks; manual `Session::advance` remains deterministic.
`Session::pause(false)` anchors the resumed host mapping at the current
application time. The host schedules no wakeup when `next_delay` is absent.

Applications do not need to change timer creation or cancellation. Drivers that
previously compared sampled application time across ordinary requests should
pause first when they need a fixed manual clock. For example:

```rust
session.pause(true).await?;
session.advance(250.0).await?;
// Inspect or dispatch agent actions without advancing paused application time.
session.pause(false).await?;
```

## NSH delivery receipt source and installed-code evidence

Delivery receipts add `luiSourceHashes` for a local `lui-nsh` path dependency,
including its Rust sources, manifests, compiled `contract.json` and shared SVG
inputs. A thin application root no longer hides the adapter sources from the
receipt. The source map must remain unchanged through package publication.

External receipts add `installedCodeSha256`, keyed by executable and payload
library paths relative to the completed package root. These hashes describe the
final bytes after relocation, signing, notarization and stapling. Existing
`ocamlArtifactSha256` and `ocaml.librarySha256` retain their meaning as original
build-input digests; they can differ from the installed library after those
steps. `runnerSha256` remains compatible with the executable's final digest.
Consumers should accept the additive fields and compare installed library bytes
against `installedCodeSha256["Contents/Resources/lui/liblui_app.dylib"]` on macOS,
or `lui/liblui_app.so` / `lui/lui_app.dll` on Linux / Windows. The final archive
hash still authenticates the complete archive.

## NSH retained toolbar orientation and dropdown ownership

NSH fixes a toolbar's keyboard-navigation axis when its native controller is
created. Updating a retained toolbar between horizontal and vertical therefore
fails before committing any part of the batch. Omitted orientation and explicit
`horizontal` are equivalent. To change the axis, deliberately replace toolbar
node 11 with a new node 12 at the desired orientation; changing only node 11's
`orientation` fails. In a keyed OCaml composition, make the orientation part of
the structural item's identity. This remount changes lifetime intentionally,
so the application owns restoration of any desired focus or local state.

A sibling-owned dropdown must remain immediately after its select/combobox.
For example, `[select; label; dropdown]` is rejected; place the label before
the select or after the dropdown, or parent the dropdown directly under the
select, combobox or menu trigger. Structural insertion/move validates existing
dropdowns too. Rejection rolls back the entire batch, preserves identities and
leaves its generation available for a corrected retry.

## NSH command icons, variants and sizes

Desktop `button` and `toggle-button` now render authored built-in `icon`
values using the same tracked SVG assets as Web. The glyph inherits the
command foreground and is decorative in the accessibility tree. An icon-only
command must provide a meaningful label, for example:

```ocaml
button ~icon:`plus ~size:`icon ~label:"Add item" ~on_press:add_item []
```

`icon-placement` defaults to `leading`; `trailing` places the glyph after the
label and `top` places it above the label. Changing the icon, placement, size
or variant updates retained bindings rather than replacing the native
button controller. Application icon registration is not implemented by NSH
yet; unknown names, including unregistered `app:` names, show Web's missing
icon glyph rather than silently producing an empty control.

An explicit `gap` overrides shared spacing between the icon, label and
authored children. `main` and `cross` use the same canonical layout parser as
the native host. Trailing placement reorders three keyed content slots, so
the label stays before authored children and their native identities survive
the move. Icon-only commands remain centered.

Outside a tabs context, `variant` selects the shared `default`/`secondary`,
`primary`, `outline`, `ghost` or `destructive` appearance. These values were
previously accepted with a fixed secondary appearance. The desktop size
scale is `sm` (24-point minimum height), omitted/`default` (32), `lg` (40),
and `icon` (32-point square); explicit authored layout and paint properties
still override shared defaults. Hover, pressed, selected, disabled and
focus treatment remain owned by the native behavior component and shared
theme. A LUI button under `tabs` still uses native tab behavior and the tab
appearance; this change does not claim menu-item or tab appearance parity.

## NSH native host event delivery and callback flags

NSH's public native host elements now deliver authored generic activation,
pointer entry/exit, press detail/down/up, context-menu requests and supported
pointer move/cancel events. The existing C ABI and OCaml event constructors are
unchanged. Pointer coordinates use the native surface's points; `target_class`
is empty because there is no DOM. Available modifier bits retain the existing
contract: Control=1, Shift=2, Command/Super=4, secondary button=8. Alt has no bit
in that contract. Mouse move and pointer-origin context-menu payloads retain
available button information. NSH `PressEvent` has no mouse-button field, so
press detail/down/up use button 0. Touch move/cancel lacks modifier state and
uses zero modifiers. These defaults describe unavailable public payload fields,
not inferred physical input.

A model-owned select/combobox still requests activation through its native
Menu controller. A native trigger observer supplies that same action's available
modifiers and pointer detail without requesting activation twice. A pointer-only
trigger delivers detail without ordinary activation. Native NSH semantic
components such as Button, Checkbox, Switch and MenuItem expose unit behavior
events; this change does not claim full pointer/modifier parity for those
components. A parent observer cannot recover their ordinary press payload by
bubbling. Their existing semantic behavior remains in place.

`appear-enabled` now emits once when an authored node's native materialization
has attached its existing element reference, after the native commit answers.
Property-only edits do not synthesize another appearance. Disabled controls can
still appear. This is a native-materialization notification, not a guarantee that
the operating system presented a frame or that a clipped node became visible.
Row/Column/Box focus-within observers use the same native reference and emit
one transition when focus enters/leaves their subtree, including a real input
inside it. Their live focus-within flag can be enabled without changing
focusability or remounting children.

Input changes/submission and Checkbox toggles now honor the current
`change-enabled`, `submit-enabled` and `toggle-enabled` flags, as well as general
`enabled` state. Low-level authors must set those flags when they want callbacks;
ordinary `Lui_elements` handler registration already sets them. For example, a
raw `text-field` with `change-enabled=false` sends no foreign change request;
setting it to true enables the already-installed input callback without
remounting its editor.

Generic native press/pointer/long/double listener capabilities are installed from
the authored capabilities at native materialization. A callback always checks
its current live flags, node incarnation and general enabled state. Disabling
then restoring an installed capability preserves native identity. Temporarily,
enabling an initially unauthored host capability after that native root mounted
is rejected atomically and requires an explicit keyed/model remount. For example,
adding `press-enabled=true` to an already-mounted passive text node fails, while
changing its text remains valid at the same generation after the failed batch.
This prevents installing blanket no-op press listeners that steal clicks from
enclosing controls. It is an explicit partial-parity limit, not silent support.

Rust embedders matching public `render::Event` or `runtime::Event` exhaustively
must handle the additive native press/pointer/lifecycle variants. The pointer
types are re-exported by both modules. New optional C exports are required only
when those events are requested; an older library without one reports a missing
ABI error instead of accepting and losing the event. Queued events keep the
existing incarnation check so retired nodes cannot receive replacement-node
input.


## NSH native layer-index bounds

NSH now rejects an authored `z-index` before publishing a transaction when it
falls outside signed 32-bit range or loses integer precision in the native
numeric style parser. The canonical wire format continues to preserve OCaml
integers exactly. Use small relative layer indices such as `0`, `1` and `2`;
replace timestamp-derived or globally allocated layer indices with local order.
For example, change a `set-prop` patch with `property: "z-index"` and
`value: 16777217` to `value: 2` when the element only needs to appear above its
siblings. A rejected batch leaves other properties,
node identities and its retry generation unchanged.


## NSH basic presentation and links

The desktop adapter adds retained stack layers, alert titles and content,
bubble reaction badges, native indeterminate spinners, built-in icons, avatar
fallback text, status bars and keyboard-accessible links. Avatar image-resource
IDs still require an explicit resource bridge and are rejected before commit.
Standalone icons share Web's missing-glyph fallback for unregistered names.

A link with `press-enabled=true` leaves navigation to its canonical Press
handler. Without a handler, an absolute external URL opens in the system
browser or registered application; `_self` and `_blank` both use that desktop
behavior. Relative paths and fragment-only URLs require an authored handler
and are rejected otherwise. For example, use
`link ~url:"/settings" ~text:"Settings" ~on_press:show_settings []` for an
application route; a plain `link ~url:"https://example.com" ~text:"Website" []`
opens externally. This does not introduce an embedded browser or claim Apple
backend navigation behavior changed.


## NSH pinned edge layout

`edge-inset` now keeps its first child as the main content and reserves space
for every following child at `top`, `bottom`, `leading` or `trailing`.
`leading`/`trailing` follow NSH's native right-to-left setting; explicit left
and right padding keep their physical sides. Authored padding, background,
foreground, border and corner radius apply to the pooled pinned region.
The main content keeps its own surface and fills the remaining space.

For example:

```ocaml
edge_inset ~edge:`bottom ~padding:8 ~background:"secondary"
  [document; controls]
```

This pads and colors `controls`, without padding or coloring `document`.
Setting `visible=false` hides the pinned children and returns their
space to the main content. Their native identities survive visibility changes
and moves between the first/content position and later/pinned positions, so
editor drafts are retained.

This initial native grid composition rejects pooled `hover-*`, `pressed-*`,
`focus-*`, `selected-*` and `disabled-*` paint, opacity other than `1`, nonempty
shadow other than `none`, and authored transitions. These effects need a shared
native rendering group; applying them to the decoration alone would lose their
scope. Remove those properties when migrating; use `visible` for complete
shown/hidden state. Unsupported paint rejects the entire transaction before
publication, preserving other properties and the generation for a corrected
retry. The composition accepts at most 32,760 children because native grid line
indices are signed 16-bit values. The canonical wire contract is unchanged.


## Unreleased: NSH Drawer and Resizable surfaces

NSH `drawer` now uses the public native Sheet for its left panel, modal focus,
Escape/backdrop dismissal and native transitions. The canonical first child is
its sidebar; the second is the main content and stays mounted in normal flow.
`selected` remains application controlled. A native close requests
`Toggle(drawer_id, false)` when `toggle-enabled` is set; retaining `selected=true`
refuses the request. For example, accepting a close for node 12 publishes:

```json
{"op":"set-prop","id":12,"property":"selected","value":false}
```

No separate Dismiss event is introduced. Replacing the sidebar or changing
open state preserves the retained main editor's native ID and draft. The NSH
Drawer path requires both canonical children and rejects an incomplete shape
before committing its batch.

NSH `resizable` now uses the public native ResizeHandle for pointer capture and
direct bounded width updates. `width` (also written by OCaml `resizable_width`)
initializes its local width. Unrelated model patches preserve a user's resized
width; a changed authored width resets it, and changed minimum/maximum bounds
clamp it. For example, a source width of 140 can be resized locally to 240;
changing `max-width` to 150 clamps the retained view to 150 without rewriting its
source width. The ordinary canonical size invariants still apply to the source
properties.

The existing resizable root exposes increment/decrement accessibility actions
in 16-point steps. There is no new ValueChanged event or OCaml resize callback;
`split` is a separate API. Native-handle keyboard arrows and consolidated
handle accessibility semantics are not claimed by this increment. Headless
qualification covers real drag/release, bounds, source reconciliation and
retained editor identity/draft; desktop appearance and screen-reader output
remain separate qualification work.


### EdgeInset appearance while retained

For mounted `on_appear` handlers, initially hidden pinned nodes and their
nested descendants emit no `Appear`. Each later hidden-to-visible transition
emits once after the native ref is mounted. Repainting the inset or editing
unrelated properties does not emit another appearance. The main content stays
visible when only the pinned region is hidden. Native node identities remain
stable; stale pending appearances are cancelled when their scope is disposed
or becomes hidden before delivery. Ordinary nodes outside a scoped layout
retain the existing one-shot appearance path.


## Unreleased: NSH retained collections and tab navigation

These desktop routes reuse public NSH Accordion, Button, Tabs and Tab behavior.
They add no canonical node kinds, wire operations or callback signatures.
Unsupported callbacks below are rejected before a transaction is published;
other edits, retained identities and the generation remain available for a
corrected retry. A route being admitted does not imply complete visual or
property parity with the Apple, Android or Web backend.

### Accordion

With `toggle-enabled=true`, `selected` controls one native disclosure: absent or
false is collapsed, and true is expanded. Press, Space or Return proposes
`Toggle(accordion_id, next_selected)`; only a subsequent source update accepts
that proposal. Retaining the previous source value refuses it. For example,
accepting an open request for node 10 publishes:

```json
{"op":"set-prop","id":10,"property":"selected","value":true}
```

Without toggle support, the title is a static heading and the content is shown
regardless of `selected`, matching the existing Apple static-content path.
The native panel keeps descendants mounted when closed, preserving editor
identity and draft. Its reveal uses NSH's native motion and reduced-motion
setting. Authored root sizing, including `height`, still applies; it is not a
new scroll container or a content-height measurement API.

### Static Table, TableRow and TableCell

`table` uses NSH's static Table. Row and cell hosts reproduce the complete
underlying TableRow/TableCell behavior from official main `de7f363`
(`nsh-base/src/table.rs`): Row is a flex row with the Row role; Cell is a view
with the Cell role. Neither native part registers shared column measurements.
The host equivalents additionally preserve canonical row selection state and
cell pointer payloads. Retained children keep their own controls and identities.

The desktop cell default is equal flexible columns with a zero minimum width.
This is a desktop adapter default, not NSH DataTable sizing. An explicit `width`
or `width-viewport` opts that cell out of equal flex; authored presentation is
then applied. For example, use the same first-column width on each row to obtain
a fixed first column:

```json
[
  {"op":"set-prop","id":21,"property":"width","value":120},
  {"op":"set-prop","id":31,"property":"width","value":120}
]
```

Other cells share the remaining width. This static composition provides no new
sorting, resizing, automatic header inference, intrinsic cross-row column
measurement or table virtualization. Use explicit matching column widths when
migrating layouts that depend on those measurements. `selected` on a row is
source state, not a new row-selection callback. The legacy cell `size` alias is not mapped by
this route; use explicit `font-size` when migrating cell typography.

### ListItem and list sections

A flat `list-item` initially authored with `press-enabled=true` uses native
Button activation. Its Press callback is gated by the current flag and
`enabled`; selection remains source controlled. A content-only flat row uses a
passive host so its child controls handle their own input. The existing native
host rule still applies: enabling a previously uninstalled listener on a mounted
passive row requires a remount.

The **presence of `expanded` selects disclosure mode**, including when its value
is false. That mode uses native controlled Accordion behavior. Non-list-item
children remain in the row body; nested `list-item` children are keyed rows in
the retained disclosure panel. A native disclosure activation proposes Toggle
and does not additionally invoke the flat row's Press action. Updating
`expanded` accepts or refuses the proposal; editing body properties or reordering
retained children preserves their native identities and drafts. `list-section`
is a semantic group, its header uses the Header role, and its footer retains its
content. Row/section `separator` flags and `list-style` marker presentation are
not implemented by this increment. These parts introduce no implicit list
virtualization or additional selection store.

Adding or removing `expanded` on an existing incarnation is rejected even when
there are currently no nested rows. Prefer declaring the future disclosure mode
before the first publication. This initial batch, for example, starts closed
and can later receive nested rows without changing modes:

```json
{"generation":1,"ops":[
  {"op":"create-node","id":1,"kind":"list"},
  {"op":"create-node","id":10,"kind":"list-item"},
  {"op":"set-prop","id":10,"property":"text","value":"Group"},
  {"op":"set-prop","id":10,"property":"expanded","value":false},
  {"op":"set-prop","id":10,"property":"toggle-enabled","value":true},
  {"op":"insert-child","parent":1,"child":10,"index":0}
]}
```

Register the Toggle handler with that initial row. Later opens/closes only set
`expanded` true/false. If an already published flat row must become a disclosure,
create a replacement row with a fresh wire ID, its disclosure properties and its
registered handlers, then replace the old row in its parent. A normal property
patch or `move-child` does not create a new incarnation. Treat the replacement as
a remount and retain any necessary editor state in application data; the wire
format has no writable incarnation field.

The current ListItem route explicitly rejects these true flags:

| Flag | Required migration |
| --- | --- |
| `change-enabled` | Render a `text-field` child and register input callbacks on that child. The row has no inline editor mode. |
| `submit-enabled` | Register submission on the child editor; native row activation cannot distinguish a Return-only submission. |
| `long-press-enabled` | Remove the row callback until native typed long-press projection is implemented. |
| `double-press-enabled` | Remove the row callback until native typed double-press projection is implemented. |

Moving a flag alone does not move a callback registration: register the handler
against the child editor's ID and remove the unsupported parent flag. These
restrictions remain unresolved parity work. Native typed Button/Accordion/Tab
roots also retain the documented raw pointer/modifier projection gap; their unit
semantic events must not be interpreted as a complete PressDetail payload.
The separate NSH PressDetails proposal is not part of this implementation.

### BottomTabs and BottomTab

The desktop adapter separates native tab triggers from page content. Titles and
icons belong to public NSH Tabs/Tab controls in the bottom bar; each canonical
BottomTab owns a separate page surface containing its original children. Page
Buttons remain ordinary Buttons and do not register as tabs. This replaces the
earlier NSH composition that placed every page inside its trigger.

`selected` remains application controlled. The displayed destination is the
first direct BottomTab with `selected=true`, falling back to the first child
when none is selected, matching Apple and Web. Multiple selected flags therefore
show only the first matching destination. The fallback includes a disabled first
child; `enabled` governs navigation to a tab and does not disable controls inside
an already displayed page. The native bar uses this same effective selection.

Arrow, Home and End navigation skips disabled tabs and proposes the same
canonical Press as tab activation. The application accepts by updating its source
flags, or refuses by retaining them. There is no optimistic source mutation or
second focus manager. `enabled` defaults to true and `selected` to false. The
canonical requirements remain: each BottomTab has a nonempty title, Press
support and content, and is a direct BottomTabs child. Accepting activation of
tab 30 instead of tab 20, for example, publishes:

```json
[
  {"op":"set-prop","id":20,"property":"selected","value":false},
  {"op":"set-prop","id":30,"property":"selected","value":true}
]
```

A page is materialized on its first effective selection, then stays mounted
while hidden. Switching tabs or reordering retained tab identities preserves its
native editor identity, draft and scroll state. Each page has its own native
scroll surface; inactive pages leave layout, hit testing and accessibility.
Initially registered, supported nested `on_appear` handlers emit on
hidden-to-visible transitions, including after returning to a previously visited
page. Refused activation, ordinary body edits and reordering without a visibility change do not emit
another appearance. An unvisited hidden page has no native body and emits no
nested appearances. Pending appearances are cancelled if their scope is hidden
or disposed before delivery.

The canonical BottomTab ID now identifies its page surface, rather than the
native trigger. Native UI automation that previously pressed `id:lui-<tab_id>`
should activate `role:tab[<title>]` instead. Both native trigger activation and
existing canonical callbacks still report the original BottomTab wire ID.
There are no new wire operations, callback signatures or writable incarnation
fields. Native typed Tab raw modifier/pointer projection remains the documented
unresolved gap; no empty payload is synthesized.

In a bounded parent, the desktop composition fills the available area and puts
the bar below the selected page. **Automatic height inside an unbounded ancestor
scroll is not implemented.** Apple supplies a nearest-container height there;
Web has a 420px minimum. NSH does not invent either a 420-point clamp or a global
viewport height. Give the BottomTabs an explicit bounded height or put it in a
bounded, growing layout. For example:

```json
{"op":"set-prop","id":1,"property":"height","value":480}
```

That limit is a layout requirement of this desktop composition, not a change to
the canonical size contract or to the maintained Apple/Web backends.

## NSH portable package assets on Windows

The delivery wrapper validates package asset destinations in their portable
forward-slash spelling before converting them to host filesystem paths. A valid
argument such as `--asset NOTICE=licenses/lui-icons/NOTICE` and the default icon
license resources no longer fail on Windows merely because Windows Path uses
backslashes internally. Absolute paths, Windows drive paths, backslash input,
empty components and `.`/`..` traversal remain rejected before copying.

Applications do not need to change their wire contract or resource paths. Keep
using relative forward-slash destinations in release scripts. This fixes the
packaging wrapper; a Windows release still needs its native package and launch
qualification to complete successfully.


## NSH official-main dependency synchronization

The desktop dependency moves from `logseq/nsh` commit
`028574b7de9ee25a7c6f60660ef72fcb8790a27e` to
`d21573c25984e9603bf878ae8bb73c1e23408936`. The new immutable commit merges
`longbridge/nsh` main at `de7f3637171b769f18474796fd5159a60b2de726` and
preserves the authorized keyed-list repairs. All NSH crates and the lockfile
must resolve that same revision. Do not replace the revision with a floating
branch or the `v0.5.0` release tag.

Downstream Rust embedders that override NSH dependencies must update every
NSH override together, then regenerate their lockfile. Desktop packagers must
rerun `python3 tooling/nsh_delivery.py setup --checkout ../nsh` with a clean
checkout at the new commit; the old CLI receipt is intentionally rejected.
Application schemas, C ABI and wire event ordinals are unchanged by this pin
update. Previous-pin native package evidence does not qualify the new pin.

## NSH mixed checkboxes and named button groups

Checkbox and Toggle now forward canonical `indeterminate` to the existing
native Checkbox behavior and indicator. For example, a checkbox with
`checked=false` and `indeterminate=true` exposes the native mixed state rather
than appearing unchecked. A user toggle requests the proposed boolean; the
application retains ownership of both `checked` and `indeterminate`. Refusing
the request leaves the mixed state and native editor/control identity intact.
When accepting it, applications should set `checked` to the accepted value
and clear `indeterminate` explicitly. Ordinary two-state checkbox defaults
remain unchanged.

ButtonGroup now forwards its authored accessible name to NSH ToolbarGroup.
For example, `accessibility-label: "History"` names the native group around
Undo/Redo controls. An absent or empty name preserves the native unnamed
default. This requires no downstream remount or wire-format change.


## NSH default text foreground follows appearance

Plain text now inherits the current semantic `foreground` from the renderer
surface, including when the application root is a Column rather than Root.
Previously unstyled text inherited the native black default even against a
dark background. Appearance changes update the inherited color without
replacing retained nodes. Explicit node foregrounds and scoped theme colors
continue to override that default.

Applications need no migration for normal appearance-aware text. To retain a
specific color, set `foreground` on the text or its LUI container; for example,
use an authored `foreground: "brand"` within the existing theme declaring that
token, rather than relying on the platform's implicit black default.

### NSH canonical Image URLs and native Load

NSH desktop `image` now reads canonical `url`, including reactive URL updates,
through the public native Image loader. It retains the Image host and adjacent
editors when its source or fit changes. Successful native decoding dispatches the
existing canonical `Load` event through `lui_ocaml_load`; failures do not report
successful Load. Removed/recreated node incarnations cannot receive an earlier
host's completion. The exported C ABI is unchanged.

Rust embedders matching `render::Event` or `runtime::Event` exhaustively must
handle the added `Load` variant. The existing `lui_ocaml_load` export is looked
up optionally, so an application without Image Load keeps starting with an
older library; requesting Load without that export reports an ABI error.

Ordinary images preserve LUI's default stretch when both dimensions are authored;
`image-fit="fit"` uses contain and `image-fit="fill"` uses cover. Unspecified axes
use the native image's decoded intrinsic size. An explicit accessibility label
wins over `alt`; otherwise `alt` names the native image. For example:

```ocaml
image ~url:"file:///Users/example/Pictures/diagram.png"
  ~width:240 ~height:120 ~alt:"Architecture diagram"
  ~on_load:(fun _event -> report_loaded ()) []
```

This first native URL path explicitly rejects authored `image` resource IDs
(including zero and IDs supplied alongside a URL), source crop rectangles,
`loading="lazy"`, and authored `referrer-policy`. These values fail final
transaction validation before any part of that batch publishes. Use a URL with
no crop, eager/default loading and the native transport's default policy. Keep
resource-backed or cropped views on an existing backend until the NSH resource
bridge and source-rectangle semantics are implemented; an integer resource ID is
not a native URL or asset name. Apple, Android and Web behavior is unchanged.

`platform/nsh/tests/fixtures/build_virtual.py --fixture image` builds a real
OCaml Image application without modifying Dune files. After packaging that
library, `python3 tooling/test_nsh_image_app.py <package> --logs <directory>`
checks actual native file-URL decoding, Load callbacks, source replacement and
retained editor state. The separate `ocaml_image` Rust test verifies C dispatch
with an explicit Load; headless rendering does not decode images. Neither check
alone claims screenshot/pixel fit accuracy or HTTP transport qualification.

### Typed reactive property scopes

The PPX now preserves abstract child types when a typed element has derived
reactive props. For example, this existing view syntax now compiles without
converting `bottom_tab_el` to generic `t`:

```ocaml
bottom_tabs
  [ bottom_tab ~title:"Home"
      ~selected:(reactive (fun model -> model.active = "home") model_source) []
  ]
```

The same fix applies to `step`, `timeline_item`, `table_row`, `table_cell`,
`radio`, `input_group_actions` and `swipe_action`, using unqualified constructors
or `Lui_elements.<constructor>`. Their existing `keyed_*` forms also retain the
correct abstract result and own any source derivation created by
`~source:(reactive project source)` for that mount. Restricted child lists and
keyed mount functions remain checked; a button cannot become a radio or tab.
Generic `scoped` behavior and caller-owned signal lifetimes are unchanged.

This adds typed `scoped_step`, `scoped_timeline_item`, `scoped_bottom_tab`,
`scoped_table_row`, `scoped_table_cell`, `scoped_radio`,
`scoped_input_group_actions` and `scoped_swipe_action` helpers to `Lui_elements`.
The PPX selects them automatically; applications should keep using `reactive`.
Upgrade/rebuild `lui_ppx` together with the LUI library: newly expanded typed
scopes require these helpers. Existing compiled PPX output remains compatible;
no wire-contract or backend event change is introduced.


## NSH native panel Split

NSH desktop `split` now directly composes public ResizablePanelGroup and two
keyed ResizablePanels. NSH owns panel distribution, min/max constraints,
transient drag sizes, pointer capture, right-to-left layout and adjustable
accessibility actions. The adapter no longer carries a second geometry solver,
semantic divider or arrow-key controller. Both child native editors retain their
identities during live size updates and keyed reorder.

Without sizing props, the native panels share available space equally. Bind
`~first_width` / `first-pane-width` to request the first logical panel's absolute
width in points. Child `min-width` and `max-width` map to native panel bounds;
an omitted minimum uses NSH's 100-point default. Wanted sizes clamp to those
bounds and use NSH's proportional behavior when the group is too small. A changed
source wanted size replaces the native dragged size; parent size or constraint
updates use NSH layout and emit no user resize notification.

A completed native drag or adjustable action that changes the first panel emits
one existing `ValueChanged` notification with that logical panel's **absolute
width in points**, whether
or not an initial width was provided. This replaces the earlier desktop ratio
fallback. Native local resizing persists when the application does not echo a
value; `change-enabled` gates the notification, not pointer interaction. To save
or restore a width, use the pixel property:

```ocaml
split ~first_width:(reactive (fun model -> model.sidebar_width) model_source)
  ~on_resize:(fun event -> match event with
    | Lui_protocol.ValueChanged (_, width) -> ignore (send (Set_sidebar_width width))
    | _ -> ())
  sidebar editor
```

NSH's handles have a centered 9-point hit band and native adjustable
increment/decrement actions of 10 points. The native desktop component supplies
no arrow/Home/End resize bindings; the adapter does not add its own controller
or claim keyboard resizing qualification. Explicit `gap` remains ordinary native
group spacing; the default no longer reserves a 9-point gap between panels.

Authored ratio `value`, `resize-handle-width`, nonzero `resize-handle-offset`,
nonzero `resize-duration`, and authored `resize-easing`/`resize-origin` reject the
whole transaction before publication. Migrate ratio-based desktop views to
`first_width`, and remove custom capture-band/offset/track-animation options.
The native public panel API has absolute sizes and a fixed capture band; styling
its visual indicator cannot implement a different hit-area contract. Wanted
widths must fit the native point range. The typed native group exposes resize
completion rather than pointer enter/leave observations; authored pointer handlers
reject explicitly. Move those handlers to a surrounding LUI `row` or `column`.

The usage audit found no LUI Split calls in `mobile` revision
`82b6da991bc0e6987f652f6f5cd91d1e37f58498` or `logseq_journal` revision
`6c030857d0bc417d11394a73282a87416b8006cc`; matches were string/list helpers.
This permits using native NSH semantics instead of preserving unused desktop
controller behavior. Shared wire schemas and Apple/iOS, Android and Web backends
retain their existing behavior. Earlier controlled-Split measurements describe
their recorded historical commit; they do not qualify this replacement.

### NSH authored-child navigation, steps and timelines

NSH desktop now composes `breadcrumb`, `pagination`, `stepper` / `step`, and
`timeline` / `timeline_item` from public native controllers and retained native
hosts. These routes preserve the existing canonical wire kinds and callbacks;
Apple, Android and Web routes are unchanged. Route admission does not remove
existing shared NSH styling or lifecycle limitations documented above.

Breadcrumb and Pagination preserve every authored child. Pagination does not
infer a page count or create previous/next/page buttons: NSH's data-driven
Pagination component has a different API, so the adapter uses its public Toolbar
controller around LUI's existing children instead. The outer native Navigation
landmark keeps the authored identity, accessibility label, padding and sizing.
An omitted or empty label defaults to "Breadcrumb" or "Pagination" respectively.
Its inner native Toolbar receives `gap`, `main` and `cross` through the shared layout
compiler on the actual child row. Defaults remain horizontal with centered cross
alignment, gap 4 for Breadcrumb and gap 2 for Pagination. Breadcrumb inserts a
hidden decorative chevron before each child after the first, including an editor
or a non-button child. Keyed reorders retain each child's own native host.

The desktop keyboard pattern is the native Toolbar pattern: one Tab stop for
registered commands; Left/Right wrap, Home/End choose the first/last enabled
command, and moving focus does not activate it. Space/Return activate the focused
command. Inputs keep their own keyboard stops and editing keys. This differs
from Apple/Web groups' ordinary button Tab stops and direct-Button eligibility:
native registered descendant Buttons, Toggles, Links and popup triggers can
participate. Accessibility exposes the outer Navigation landmark and its nested
Toolbar. The landmark and fallback name are intentional desktop accessibility
defaults; Apple/Web continue to expose their existing group semantics.
For example, keep destination selection in the application callback:

```ocaml
pagination ~label:"Document pages" ~gap:8 [
  button ~text:"Previous" ~on_press:(fun _ -> previous_page ()) [];
  button ~text:"Next" ~on_press:(fun _ -> next_page ()) [];
]
```

Stepper derives completed/active/pending from each current source index. The
canonical final-node validator requires an explicit nonnegative `active` property:
use `~active:0` for the first step. An omitted or negative value is rejected
before native publication, even though existing backend rendering code has a
zero fallback. The adapter does not clamp an admitted value: an index beyond the
last step completes every step. Reordering keyed Steps updates their numbers,
state and last-connector visibility without replacing retained Step hosts. An
active Step exposes native accessibility `current = Step`; its name includes
`(active)`, `(completed)` or `(pending)`. NSH currently has no `ListItem` role or
public position-in-set/set-size fields, so the container is a native List and
its named Steps are Groups. It does not claim those extra Web ARIA attributes.
Steps remain display elements; advancing them is an application action:

```ocaml
stepper ~label:"Import progress"
  ~active:(reactive (fun progress -> progress.stage) progress_model) [
  step ~key:"choose" ~text:"Choose source" [];
  step ~key:"read" ~text:"Read records" [];
  step ~key:"finish" ~text:"Finish" [];
]
```

Timeline defaults to a vertical List with zero gap. TimelineItem keeps its title,
optional description/meta, selected state, variant, icon, indicator text and
connector live on the same native host. Marker precedence is icon, then indicator
text, then a dot. To clear a wire `icon`, remove that property; an empty icon
string is invalid. An empty `indicator` string is valid and selects the dot when
no icon is present. `connector` defaults to true even on the last item; pass false
explicitly to end a line. Primary/destructive markers use those semantic theme
colors, other variants use the muted foreground, and selection uses the shared
accent. Color feedback honors reduced motion. NSH has no public base
TimelineItem component. The adapter therefore uses the existing native
interactive host and `NativeEvents` projection, rather than adding a typed Button
that discards its pointer/modifier payloads on the pinned NSH API. A press-enabled
item is a native Button role; a passive item is a Group under the List.

```ocaml
timeline ~label:"Import history" [
  timeline_item ~key:"last-import" ~title:"Import finished"
    ~description:"240 records" ~meta:"Just now" ~icon:`check
    ~variant:`primary ~connector:false
    ~on_press:(fun _ -> open_import_report ()) [];
]
```

TimelineItem forwards canonical ordinary/modifier activation and the authored
PressDetail / pointer-down / pointer-up / enter / leave callbacks through the
existing guarded native event path. Payload coordinates use the native root
coordinate system and target class is empty. As with other NSH host events,
Ctrl/Shift/Command map to the existing modifier mask; Alt has no canonical bit.
NSH's public PressEvent has no mouse-button field, so these press-phase payloads
use button zero and cannot identify a secondary button. Keyboard activation uses
the native press path; no pointer coordinates are fabricated by a second
controller. Author the required callback capability at mount; later enabling a
listener that was absent still requires a new node incarnation under the shared
NSH event compatibility rule. Disabling an already installed callback is guarded
live. These routes do not add drag, move/cancel, context-menu, long/double press or
additional callbacks beyond each kind's canonical schema.

The navigation regression suite checks actual native roles, focus-only roving,
child-row layout, retained editor identity through reorder, live Step state and
marker precedence, and native pointer/modifier activation. Native visual review
in both appearances and real application qualification remain separate release
gates; source-level tests do not establish screenshot or cross-platform results.

### NSH semantic Heading levels

NSH `heading` now uses the existing native Text host with the public Header role
and reactive accessibility level. An absent `heading-level` defaults to **2**,
preserving the replaced desktop MyGo default. The canonical OCaml constructor
writes a level only when authored; there is no shared wire default. Apple uses
an absent level of 1, while Web forwards an authored level to `aria-level`.
Applications needing the same level across backends should pass `~level` explicitly.

Levels 1 through 6 use the native NSH theme text presets `3xl`, `2xl`, `xl`,
`lg`, `base`, `sm`, with bold weight. At the default NSH scale these are
30/24/20/18/16/14 points, replacing MyGo's ad hoc 28/26/24/22/20/18-point formula.
These native presets also supply their normal line heights. Explicit canonical
font size, weight, line height, color and other text styles take precedence. For
example, to retain the previous level-2 desktop size and bold weight:

```ocaml
heading ~level:2 ~value:"Section"
  ~font_size:"26px" ~font_weight:700 []
```

Updating `heading-level` on a retained node updates both the native level and
its default typography without replacing the Text host or adjacent editors.
Removing the property restores level 2; authored font overrides remain in force
until removed. The native accessible name follows the canonical text, and an
authored accessibility identifier remains attached to that same host. Heading
does not gain a separate label property: the existing canonical validator still
rejects `accessibility-label` on Heading. Its existing composed-text-child
limitation is unchanged by this semantic increment.

Headless regressions cover all six levels, default restoration, text/name updates,
authored style precedence, native identity and user draft retention, and atomic
rejection of invalid level/label batches. These source tests do not establish
OS screen-reader announcements or native screenshot typography qualification.

### Native Windows qualification fixture builds

`platform/nsh/tests/fixtures/build_virtual.py` now supports native Windows
fixture DLLs using the same configured OCaml C compiler and MainDll/FlexDLL
linker as `tooling/build_nsh_windows.py`. Windows PPX command strings use Windows
argument quoting, and the Image ABI test uses `python` when it needs to invoke
the builder itself. The Unix compiler/link flags and macOS/Linux receipt format and input roots
are unchanged. For example, on the pinned native Windows
OCaml toolchain:

```powershell
$imageLibrary = python platform/nsh/tests/fixtures/build_virtual.py --fixture image
$env:LUI_NSH_IMAGE_LIBRARY = $imageLibrary
cargo test --locked --manifest-path platform/nsh/Cargo.toml --test ocaml_image
```

The Windows job now builds that DLL and runs the real OCaml Image Load ABI test.
Its toolchain record covers native DLL loading/exports; runtime dispatch is
checked separately by the test. This adds a CI qualification path, not a claim
that the new Windows fixture has already passed, nor native image pixel/decode
qualification. The existing macOS/Linux fixture paths remain available.

### NSH native Input submission policies

NSH text controls continue to use the public `nsh_base::Input` alias and its
native editor. A single-line `text_field`, `secure_field`, `input` or
`search_field` keeps NSH's default Enter behavior: submit, then blur. The adapter
does not add a focus restoration command or another keyboard controller.
Controlled text, native composition, selection and undo stay with that editor.

For `textarea`, absent or false `submit_on_enter` keeps native multiline Return
behavior: insert a line break. Explicit true now binds native
`SubmitBehavior::Submit`: ordinary Return reports the existing Submit event and
keeps focus; Shift+Return and Alt/Option+Return use NSH's native line-break rules.
Changing or removing this property updates the retained editor's configuration.
Submit still requires the current `submit-enabled` flag, and stale-incarnation
callbacks remain suppressed by the existing renderer guard. No canonical wire
property or C ABI signature changes.

For example, a composer can retain multiline editing or explicitly request
native Return submission:

```ocaml
(* Native multiline editor; use the application's Send button to submit. *)
textarea ~submit_on_enter:false ~on_input:update_draft []

(* Native Return submits; Shift/Option+Return insert a line break. *)
textarea ~submit_on_enter:true ~on_input:update_draft ~on_submit:send []
```

This is NSH's native keyboard policy. It does not add the Web backend's custom
Control/Command+Return path. Apple, Android and Web behavior is unchanged.
The downstream audit found explicit false in mobile's query textarea and
`logseq_journal`'s composer, with the journal reducer test checking that emitted
property. Journal's composer Submit callback is ignored and its Save action is
separate. Mobile also exposes an explicit Send action. No downstream test or
documentation requiring a modified-Return shortcut or single-line focus retention
was found; NSH's own defaults are retained for these optional behaviors.

Input policies are validated before publication: unsupported options reject the
entire transaction, leaving other text and nodes unchanged. Native focused
navigation and opt-in blur submission are described below. Color input remains
an explicit gap rather than a text-editor alias. Time input now has the bounded
native TimeField route documented in "NSH native time inputs" below; its used
24-hour text and submission semantics do not imply support for every Input option.
Do not change a color/time input to plain text merely to bypass validation when
the application needs the semantic picker.

### NSH native FilePicker paths

The NSH desktop `file_picker` route now uses the public
`nsh_core::element::pick_paths(OpenDialog)` service. NSH owns the actual system
open dialog, platform result, asynchronous answer and task lifetime; the adapter
does not add a file service, executor, polling loop, temporary copies or leases.
A production-source audit found no canonical `file_picker`, raw
`Lui_ui.file_picker`, `FilePicker` node or picker-property aliases in either
`mobile` or `logseq_journal`. Those applications' attachment pickers use separate
host services, which are unchanged. This previously unsupported desktop route
therefore adopts NSH's native path semantics rather than Apple's file-retention
protocol.

A `request` string or integer token explicitly requests one dialog while the
node is enabled. Without a token, the node retains its authored children and
opens no dialog. Repeating the last issued token or editing other properties
does not reopen it. At most one native request is in flight per retained node;
request changes while it is pending are ignored. Wait for its answer, then issue
a distinct token to open another dialog. Tokens retain integer precision above
2^53. Removing the node disposes its native task; the renderer's existing
incarnation guard rejects late results after an ID is recreated. Disposing an
awaiting task does not promise that the platform immediately closes a dialog
already visible: its UI lifecycle remains NSH's.

Defaults are `source=files`, `directory=false` and `multiple=false`. Files and
folders map directly to `OpenDialog::files()` and `OpenDialog::folders()`;
`multiple` uses the native multiple-selection option. `accept` and `types`
optionally supply comma-separated extension groups such as `.md,*.txt`; NSH
normalizes case and leading dots. When both are supplied they are native filter
groups offered by the dialog. Folder dialogs ignore file filters, as NSH's
`OpenDialog` does. Titles, default locations and confirmation labels remain the
system's defaults; no new canonical properties are invented. Authored node styles
affect the retained child container, rather than the system dialog.

Success delivers the existing `Picked(node, payload)` event, whose opaque JSON
payload is now concretely defined for NSH:

```json
{"request":1,"paths":["/home/alex/notes.md","/home/alex/todo.txt"]}
```

Paths are the native filesystem paths returned by NSH, including Windows path
syntax on Windows. No bytes, URLs, MIME guesses, security bookmarks or retained
file handles are returned. A native dialog error delivers
`{"request":1,"paths":[],"error":"native error message"}`. A path that cannot be
represented in UTF-8 is reported as an error instead of changing its file name.
Native cancellation emits the existing Dismiss event and no Picked event. No
canonical event ordinal or C ABI changes; Rust's public render/runtime event
enums gain additive Picked variants. Rust clients with exhaustive matches must
handle them. The existing `lui_ocaml_picked_utf8` function is loaded optionally,
so older libraries can still start; using Picked with a library lacking that
export reports an explicit runtime ABI error.

For example:

```ocaml
file_picker
  ~source:`files ~request:(`Int 1)
  ~accept:".md,.txt" ~multiple:true
  ~on_picked:(function
    | Lui_protocol.Picked (_, payload) ->
        print_endline (Yojson.Safe.pretty_to_string (Yojson.Safe.from_string payload))
    | _ -> ())
  ~on_dismiss:(fun _ -> print_endline "File selection cancelled")
  []
```

The application consumes or opens those paths using its own native code; a
second selection uses a different request token. For folders, use
`~directory:true`. NSH rejects `source=photos`, `source=camera`, any `completion`
token, and MIME/UTI or wildcard filters such as `image/*` and `public.image`
before publishing the transaction. Use the native desktop files/folders route
when that is the intended UI; do not relabel a photo/camera workflow as files
merely to bypass validation. Apple/iOS, Android and Web API behavior is unchanged.

### NSH native Toast lifecycle and application-level placement

The desktop adapter renders canonical `toast` nodes once in a bottom-right
application-level native ToastStack. They occupy no slot or gap in their source
parent's ordinary layout. An attached canonical Toast is an app notification,
including when its source parent is a retained hidden native page. Desktop
placement and native stack expansion, swipe and Escape follow NSH behavior;
there is no new LUI placement, swipe-direction or focus-manager API.

NSH ToastManager owns entering, present and ending phases. The existing desktop
omitted-duration default remains **4000 ms**; explicit `~duration:0` persists.
The timeout counts native Present time, after the default 400 ms entry phase;
close notifies `Dismiss` after the default 200 ms exit phase. Native stack
hover/touch expansion and keyboard focus within the stack pause the timeout's
remaining time. Each incarnation captures its duration on first presentation:
text, label, style and even later duration patches preserve that lifetime.
The adapter schedules one owner-scoped next-deadline wake, with no interval or
idle polling for empty, paused-present or persistent-present notifications.

`on_dismiss` is cleanup notification after native dismissal, not an application
veto. This matches the former MyGo desktop close-before-Dismiss behavior.
Retaining or editing that closed canonical incarnation does not display it again.
To reopen, create a new Toast incarnation through ordinary conditional/keyed
membership. Source detach disposes its presentation and suppresses any later
close callback; an old timer cannot dismiss a replacement using the same wire id.
Arbitrary child controls retain their native identities during live content
updates. Explicit source removal takes effect immediately; native exit retention
applies when the native Toast closes while its source incarnation remains mounted.

```ocaml
toast ~duration:2500 ~label:"Saved"
  ~on_dismiss:(press send Dismiss_confirmation)
  [text ~value:"Saved" []]
```

The usage audit found one Toast site in `mobile` at revision
`82b6da991bc0e6987f652f6f5cd91d1e37f58498`: capture confirmation in
`shared/src/logseq/view_screens.ml:1052`, with explicit 1500 ms on iOS and
2500 ms elsewhere. Its `shared/test/logseq/app_test.ml:10499–10502` asserts
that Dismiss removes confirmation; it does not refuse native closure. No Toast
usage was found in `logseq_journal` revision
`6c030857d0bc417d11394a73282a87416b8006cc`. Apple/iOS, Android and Web keep
their maintained backend behavior and omitted-duration defaults.
### NSH native Tree and `tree_item` metadata

The production usage audit at
[Tree production usage](agent-guide/review-probes/2026-11-12/nsh-tree-production-usage.md)
found no LUI Tree/TreeItem consumers in the inspected `mobile` or
`logseq_journal` revisions. Under the requested policy, desktop Tree now follows
NSH's public Tree semantics. Production Lists, outliners and editor extensions
are unaffected. Apple, Android and Web implementations remain maintained; this
section describes the NSH desktop route rather than changing their existing Tree
interaction policy.

`tree` now supplies nested item metadata to public `nsh_base::Tree`. NSH owns
hierarchy, cursor/focus, keyboard navigation, typeahead, selection, expansion,
virtualization and native row lifetime. No separate LUI focus manager, Tree
controller or source virtualizer is introduced. Give the Tree a finite height,
or flex space in a sized parent, as NSH's native scroll/viewport contract
requires. The adapter does not guess a viewport height.

Use the new `tree_item` constructor inside `tree`. It uses existing ListItem and
role/property/event ordinals; no wire format or C ABI is added:

```ocaml
tree ~label:"Project files" ~height:320 [
  tree_item ~key:"documents" ~text:"Documents" ~icon:`folder
    ~on_selection:select_documents
    ~on_expand:observe_documents_expansion [
    tree_item ~key:"report" ~text:"Report" ~icon:`file_text
      ~on_selection:select_report ~on_action:open_report [];
  ];
]
```

The callbacks deliberately differ from legacy repeated press handling:

| Constructor callback | Existing event | Native meaning |
| --- | --- | --- |
| `on_selection` | `Change node` | Selected item changed, including cursor navigation. Re-selecting the native selected leaf does not emit another selection change. |
| `on_expand` | `ToggleChanged (node, expanded)` | Native expansion/collapse request for an item with children. |
| `on_action` | `Press node` | Native default action: Return on a leaf or a double press on any enabled item, including a folder. Ordinary selection is not an Action. |

Two rapid pointer presses can form a native double-click Action even though
SelectedChange itself is suppressed on an already selected item. For a folder,
that Action follows its ordinary selection/expansion events. Space follows
NSH's folder-toggle behavior; it is not an extra leaf Press.
Disabled items are skipped by the native cursor and do not activate. Callback
routing encodes the LUI id and incarnation in the native item key and checks
current identity/flags before dispatch. SelectedChange does not fall back to
Press, and no empty modifier or pointer detail is fabricated from a typed native
Tree event.

Omitting `selected` and `expanded` leaves those values native-owned. Authoring
`selected` on any item switches the Tree to native controlled selection: the
first source-selected item wins, and all authored false values mean none.
Authoring `expanded` switches to controlled expansion from the source items
whose value is true. In controlled mode, publish the requested value to accept
it; otherwise the native state remains at the source value. For example:

```ocaml
tree ~label:"Controlled files" ~height:320 [
  tree_item ~text:"Documents"
    ~expanded:(reactive (fun model -> model.documents_open) source)
    ~on_expand:request_documents_expansion [
    tree_item ~text:"Report"
      ~selected:(reactive (fun model -> model.report_selected) source)
      ~on_selection:request_report_selection ~on_action:open_report [];
  ];
]
```

Keep the complete nested item hierarchy emitted; native Tree owns collapsed
visibility. Replace legacy flat `tree_level` hints and externally hidden branch
rows with nested `tree_item` children. Native depth is derived from this data.
A metadata node's explicit accessibility label, when supplied, is the native
item's single label for both display and accessibility; otherwise its text is
used. Icon and accessibility identifier presentation use shared UI and update
from the retained source metadata. These metadata nodes are not independent
arbitrary view bodies or persistent editor hosts. Reordering preserves native
item keys; virtualization still governs which native rows exist.

The old ``list_item ~role:`treeitem ~on_press/on_input/on_toggle`` convenience
callbacks subscribe to generic pointer payloads and are not the native Tree
metadata API. Migrate them to `tree_item ~on_selection/on_expand/on_action`.
The new callbacks register the existing semantic event handlers without setting
`pointer-enabled`. A controlled `expanded` value enables the existing canonical
Toggle capability even without an application callback, retaining the shared
presence invariant and native read-only controlled behavior.

Actual unsupported metadata is rejected before any batch publishes: arbitrary
body views such as editors/buttons, virtual-list children, flat `tree-level`,
row layout/paint properties, appear/pointer/long/double-press/submit handlers and
non-TreeItem roles. Explicit false callback capabilities retain absence
semantics. Native Tree does not expose root pointer callbacks either. Use its
item callbacks and shared presentation; keep rich editable outlines on the
production List/extension path. Metadata `role="treeitem"` outside a Tree is
rejected, including when an ancestor moves outside the Tree. Generic ListItem
Button/Accordion behavior outside Tree is unchanged.

NSH's public `TreeProps.items` takes an owned `Vec<TreeItem>` and has no per-item
reactive field API. Source metadata publication can therefore perform a linear
adapter projection. Equality-checked items/selection/expanded projections keep a
selection/expansion-only change from rebuilding native `Flat` when item data is
unchanged. Actual label/hierarchy/disabled data changes incur the native whole
input flatten/index cost; viewport row mounting remains native and bounded. No
constant-time source-update claim or extra item cache is introduced.

The source regression suite covers native uncontrolled and controlled behavior,
selected-leaf suppression, Return/Space action semantics, disabled traversal,
metadata updates/reorder, atomic body rejection, retained surrounding editors,
and native virtualization with 1,000 metadata items. A core OCaml regression
checks callback delivery and absence of unintended PointerEnabled. Real native
Tree application, screen-reader and platform keyboard qualification remain
separate gates; source-only preparation does not mark them passed.

### NSH MediaSurface native video URLs

`media_surface` gains optional `url` and `url_signal` arguments. The existing
`UrlValue`/`url` wire property is now admitted for this kind; no wire property or
event ordinal is added. Supply exactly one source: the existing `surface`
resource ID or a nonempty URL. Existing Apple resource-ID callers remain valid.
The NSH route accepts URLs and explicitly rejects foreign surface IDs, including
zero, rather than interpreting an integer as a URL or displaying an empty host.

A production-source audit found no `media_surface`, raw `Lui_ui` MediaSurface
constructor, `MediaSurface` variant or `media-surface` wire node in either
mobile or `logseq_journal` outside dependency/build/test trees. The new unused
desktop route therefore adopts NSH's public native Video behavior. The adapter
uses `nsh_core::element::video(bound_url).controls(true)` on the actual retained
Video host. Changing URL, label or authored styles preserves that host and
nearby editor identities. There is no custom player, codec, WebView, frame-copy
loop or separate audio manager.

NSH's defaults apply: playback starts when ready, sound is unmuted at volume 1,
rate is 1, repeat is off and the image uses native contain sizing. Native
playback controls are enabled and own play/pause, seeking and other controls the
platform offers. No new LUI pause/rate/seek event or property matrix is added.
URI resolution, loading, decoding, audio and source replacement belong to the
native NSH player. Loading errors use the existing nonfatal backend diagnostic
(`Native video: ...`); the renderer and other controls keep running. This follows
the existing diagnostic policy, so an error message remains visible rather than
being treated as a fatal application failure or silently discarded. Late errors
from a disposed LUI node are blocked by its incarnation guard and native owner.

For example:

```ocaml
(* NSH native video with system playback controls. *)
media_surface ~url:"file:///home/alex/clip.mp4"
  ~width:640 ~height:360 ~label:"Recorded clip" []

(* URL replacement updates the same native host. *)
media_surface ~url:(reactive Fun.id video_url)
  ~width:640 ~height:360 ~label:"Recorded clip" []

(* Existing maintained Apple resource API. *)
media_surface ~surface:surface_id ~width:640 ~height:360 []
```

Use the platform-appropriate source; NSH does not import Apple's external
resource registry. Apple retains its resource route and rejects this NSH URL
alternative. Web also explicitly rejects a MediaSurface URL while preserving
its existing resource-ID route, so the shared canonical URL addition cannot be
silently ignored. Android and the other existing backends retain their resource
implementations. There are no native library exports or Rust semantic event
enum additions for this route. The headless tests check the real Video host,
public native property batches, retention, error dispatch and atomic source
validation; they do not qualify native decoding, audio output or video pixels.

The language-neutral JSON view facade adds `"kind": "tree-item"` as an alias
for this metadata constructor; the mounted wire kind remains `list-item` with
`role="treeitem"`. With an `id`, its event sink names are `change` for selection,
`toggle` for expansion and `press` for native Action. The facade calls
`tree_item` directly and does not register the generic pointer-enabling legacy
handlers. For example:

```json
{"kind":"tree","label":"Files","height":320,"children":[
  {"kind":"tree-item","id":"report","text":"Report"}
]}
```

JSON facade generation skips structural `virtual_rows` and typed `scoped_*`
ownership helpers; actual node constructors remain generated, including the
native MediaSurface URL parameters.

Regeneration also restores facade forwarding for already public `shrink` on
Row/Column/Box, `pointer-capture` on Row/Box, `indeterminate` on Checkbox, surface
`transition` on Drawer/Dialog/Sheet, and MediaSurface `url`. Their constructor
contracts remain unchanged. The existing raw FocusWithinChanged `within` payload
decoder is preserved; the typed `on_focus_within` optional argument remains
outside this facade's decoded arguments, as before.

## NSH ViewThatFits keeps ordered alternatives mounted

The NSH desktop backend now accepts `view_that_fits`. It chooses the first
candidate whose native intrinsic extent fits the available content box along
`orientation` (horizontal by default). The last candidate is always the fallback
and receives the available extent on that axis, including when none of its
predecessors fits. An empty candidate is a real, zero-sized alternative and can
win before a later nonempty alternative. With no candidates the host is empty.

Candidates use their existing keyed LUI/native identities. Each body is mounted
once; choosing, resizing, updating its contents or reordering alternatives does
not construct an extra probe body or reset an editor draft. Native `max-content`
layout and size-change callbacks measure the direct candidate wrappers. Hidden
alternatives remain laid out with native `visibility: hidden`, which excludes
their descendants from pointer interaction, keyboard focus and accessibility.
The adapter keeps only the current direct candidates' sizes and prunes them once
when direct candidate membership changes. It never walks their descendant trees
to estimate layout. A native layout change can require a subsequent reactive commit to
publish the selected alternative; there is no polling or synchronous layout
probe loop.

`on_appear` follows selected visibility, including inherited `EdgeInset.visible`.
An initially hidden candidate does not appear; selecting it emits its appearance
callback, and selecting it again after a hidden interval emits a new callback.
The outer `EdgeInset` body remains mounted independently. This preserves Journal's
`journal_header.feedback_with_visibility`: its model-owned `visible_signal`
controls the pinned feedback region; it is not a new ViewThatFits visibility
callback. The maintained Apple and Web implementations are unchanged.

For example, retain a compact alternative before a wider alternative, and use
an explicit last fallback when neither intrinsic size fits:

```ocaml
view_that_fits ~width:280 ~orientation:`horizontal
  [ column ~width:180 [ text ~value:"Compact status" [] ]
  ; column ~width:260 [ text ~value:"Expanded status" [] ]
  ; column [ text ~value:"Status" [] ]
  ]
```

The order expresses priority: in this example the compact alternative wins even
though the expanded alternative also fits. For vertical fitting, give the host a
finite height (or flex space inside a parent with a finite height); an unbounded
vertical layout naturally offers the first candidate its content height. Width
and height constraints, padding and paint remain on the actual outer host.
The measured content box excludes that host's padding. All alternatives remain
mounted, so keep the authored alternative set small; use native virtual lists
for growing collections rather than using ViewThatFits as a list virtualizer.

## NSH desktop excludes mobile swipe action containers

On 2026-11-12 the user explicitly excluded `swipe-actions` and `swipe-action`
from NSH desktop requirements. Their public constructors, wire ordinals and
maintained mobile backend behavior remain unchanged. NSH continues to reject
these kinds atomically; it does not render an inert placeholder or introduce a
custom desktop gesture controller.

Desktop callers expose these actions through ordinary commands or ContextMenu.
For example, choose the affordance in the mounted view's host context:

```ocaml
let remove_actions on_remove context parent =
  let open Lui_elements in
  let view =
    match Lui_ui.host context with
    | Lui_protocol.NshHost ->
        row [ button ~text:"Remove" ~on_press:on_remove [] ]
    | _ ->
        swipe_actions [ swipe_action ~text:"Remove" ~on_press:on_remove [] ]
  in
  view context parent
```

Keep the existing mobile action container at its supported parent location.
This example changes the desktop affordance only; the application's action
handler stays the same. The NSH inventory reports these two explicit platform
exceptions separately from missing required component routes.

## NSH Scroll forwards its authored native axis

``scroll ~orientation:`horizontal`` now uses native horizontal Scroll, fixing the
copied Logseq `views_table.ml` table/header scrolling paths. Omitted orientation
and explicit `vertical` keep the native vertical default. Pointer/wheel input
uses the corresponding native axis without a synthetic gesture controller.

The public NSH axis is fixed at construction. Changing the effective axis on an
existing incarnation fails the entire batch before publication; ordinary edits
and spelling the existing default explicitly preserve content, offsets and
editor identity. To change axis, mount the new Scroll under a different key
(for example `~key:"results-horizontal"` versus `~key:"results-vertical"`).
Both production horizontal Scroll calls in Logseq `refactor/lui` at
`29dcb60fdc976dcda1da6ec984057bbf79d88612` author a static axis. This restriction
does not alter maintained mobile/Web backends or canonical orientation values.

### NSH bounded local FileImage

NSH desktop `file_image` now uses the retained native Image host for layout,
fit, accessible name, press/detail/pointer events and appearance. `~path` accepts
an absolute local path or local `file://` URL; percent escapes in file URLs are
decoded. Relative paths resolve beneath the current user's native Documents
location (Foundation on macOS, the Windows known folder, and XDG on Linux).
The desktop adapter does not apply the Apple sandbox-container relocation
fallback. Remote URLs and `asset:/` sources reject atomically; use ordinary
`image ~url` for network or packaged images.

`max_pixel_size` defaults to 1024, matching the maintained Apple/Android FileImage default. The old MyGo desktop
used an unconstrained natural decode when this prop was absent; NSH deliberately
uses the bounded default. Author a permitted larger cap when needed.
The first frame is downsampled by ImageIO, WIC or GdkPixbuf before it is handed to
NSH as bounded straight RGBA. Its longest side is at most the requested cap,
independent of screen scale, the frame's dimensions or `fill` cropping. The
adapter accepts caps from 1 through 4096, checks decoded dimensions and byte
counts before allocating its RGBA buffer, and rejects larger caps before
publication. Encoded files over 64 MiB fail the load. These bounds limit the
adapter's output and input buffers; codec-internal temporary memory and codec
availability remain platform properties. No claim is made that every codec can
avoid a full internal source decode.

The default `fit` is containment; the authored `fill` mode maps to native cover. For example,
the existing composer preview remains:

```ocaml
file_image ~path ~max_pixel_size:384 ~fit:`fill
  ~width:128 ~height:128 ~label:"Attachment" []
```

Only a changed `(path, max_pixel_size)` requests another thumbnail. Fit, label,
frame and other presentation updates keep both the native image identity and
its current source. A changed path or cap hides the previous source while the
replacement loads; failure leaves an empty styled image frame. Owner disposal
or a newer request prevents old completion from publishing. FileImage adds no
`load` event to the wire contract. Existing `on_appear` and press handlers retain
their canonical meaning.

The adapter reuses NSH's decode pool, owner-scoped resource cancellation, native
Image host and shared native picture cache. It adds neither a worker nor a
second decoded-image cache. Independent FileImage nodes can each create their
own bounded thumbnail; caching or deduplication is not claimed at that service
boundary. Source RGBA and the platform picture coexist while displayed. No NSH
public API or fork change is required. Other LUI backends are unchanged.

The downstream audit covers `mobile` at
`82b6da991bc0e6987f652f6f5cd91d1e37f58498` (composer: cap384, fill128×128),
`logseq_journal` at `6c030857d0bc417d11394a73282a87416b8006cc`
(media previews: cap1024, fill190×90 or102×102, appear/press), and
`logseq` refactor/lui at `29dcb60fdc976dcda1da6ec984057bbf79d88612`.
The last checkout has no production FileImage/FilePreview constructor call;
its native embedding selector recognizes the kinds and its asset views use
ordinary Image. Shared `lui_element_combine` also uses cap384/fill120×120.

The added source regressions cover native BMP thumbnail bounds/aspect/no upscale,
path/cap/default-fit validation, stale and detached resource completion,
presentation-only updates, retained host/editor identity, press delivery and
atomic rejection. Platform compilation, execution and native visual qualification
must be run by the main session; source preparation alone does not establish them.

### NSH retained ContextMenu attachments

NSH now renders a canonical `context_menu` attached to a Button or ListItem
through the public NSH Menu/ContextMenu components. Buttons use a primary Menu,
matching the existing Apple Button convention and the graph/attachment actions
used by downstream applications. ListItems use native secondary-click,
Shift+F10/Menu-key and held-touch ContextMenu activation. NSH owns item traversal,
disabled-item skipping, focus restoration, outside dismissal and Escape. The
existing `on_dismiss` callback receives the canonical menu node ID when the native
controller closes. Native desktop context menus do not add Apple's ListItem
ellipsis button or mobile swipe affordances.

Keep the attachment present for the trigger's lifetime and update its items or
`disabled` value reactively:

```ocaml
button ~label:"Add attachment" ~width:32 ~height:44
  [context_menu
     [menu_item ~text:"Choose file" ~on_press:(fun _ -> choose_file ()) []]]
```

One direct ContextMenu child is supported per Button/ListItem. Other direct host
kinds and standalone root ContextMenus are rejected before publication. Changing
a previously constructed trigger between attached and unattached modes also
rejects the complete batch; remount that trigger with a new key to change modes.
Replacing the attached menu node while retaining attachment mode is supported.
The canonical child rule is unchanged: ContextMenu accepts MenuItem and Divider;
DropdownMenu remains the constructor for MenuTrigger/submenu hierarchies.

The native controller's outer view takes the trigger's parent-facing constraints
(size, flex, margins, position and grid placement); the retained trigger keeps its
padding, paint, content layout, accessibility identity and public ElementRef.
Ordinary hosts acquire no wrapper. Authored popup content and scoped theme remain
retained LUI nodes, and item/property updates do not rebuild the trigger or nearby
editors. Source regressions compare attached/plain intrinsic, fixed, stretched
and growing layouts, refs, native activation/dismissal, item updates and atomic
mode-change rollback. Headless and real native qualification must pass before
claiming platform validation; source preparation alone is not that evidence.

## NSH Input supports explicitly authored blur submission

`text_field`, `secure_field`, `input`, `search_field` and `textarea` now accept
`submit_on_blur=true` on NSH. Losing native keyboard focus emits the existing
canonical `Submit` event when both `enabled` and `submit-enabled` still permit
it. Logseq's property editor, repeat-frequency editor and home-page settings
use this callback to save their current model draft. Their existing calls can
remain unchanged:

```ocaml
text_field ~label:"Property value" ~submit_on_blur:true
  ~text:(reactive Fun.id draft)
  ~on_input:(on_input send (fun value -> Edit value))
  ~on_submit:(press send Save) []
```

The native Input continues to own editing, composition, focus and Return behavior.
A single-line Input's default Return reports Submit and then blurs; this remains
one canonical submission, in the original position after committed text updates.
The subsequent native Blur is suppressed only for that Return sequence. A
textarea configured to submit on Return keeps native focus, so a later ordinary
focus loss is a separate submission. The adapter never commits or synthesizes
composition text: a blur while composition is still reported active does not
submit it; when the native editor commits text and ends composition before
blurring, the committed text event remains before Submit.

Inputs that omit both `submit_on_blur` and navigation handlers retain their
previous path with no additional blur/focus/composition observers or policy state. Authoring the property at
initial mount, including explicit false, installs the small observer set. Its
value, `enabled` and `submit-enabled` are checked live; initially authored false
can subsequently become true on the same native editor, and removing the
property disables blur submission without replacing that editor.

Adding true to an already mounted Input that originally omitted the property
requires remounting that Input, just as other initially absent native listener
capabilities do. The batch is rejected atomically before any of its changes are
published. Setting false after an absent initial value is allowed, but does not
retroactively install observers; a later true still requires a remount. For a
wire producer that plans to toggle this policy without replacing its editor,
create the initial node with `submit-on-blur=false` rather than omitting the
property. For OCaml applications with a fixed blur-save policy, pass
`~submit_on_blur:true` on the original constructor as above.

No C ABI, wire event ordinal or semantic event payload changes. The existing
incarnation guard rejects retired callbacks, including the trailing native Blur
when a Submit handler replaces the source Input. Button calendar NavigationKey and native
color input remains a separate unresolved requirement; native TimeField support
and its explicit restrictions are documented below. The native focused
regressions cover callback count/order, policy/flag changes, atomic refusal,
editor retention, composition events and replacement; Headless composition
checks do not qualify an operating-system IME.

### NSH MenuItem presentation parameters

NSH MenuItem now forwards inline icons, selection-marker placement, control size,
variants and `shortcut_hint`/wire `tooltip-keys` through native MenuItem parts.
Native MenuItem still owns checked accessibility state, disabled-item traversal,
activation, focus and closing. `selected`/`checked` remains controlled: selection
reports the existing Press callback and does not change the source value itself.

```ocaml
menu_item ~text:"Delete" ~icon:(`app "trash") ~variant:`destructive
  ~shortcut_hint:"⌘ Backspace" ~on_press:(fun _ -> delete ()) [];
menu_item ~text:"Enable feature" ~checked_signal:enabled
  ~selection_placement:`leading ~on_press:(fun _ -> toggle ()) []
```

The default check position is trailing, matching the existing Web presentation;
explicit `leading` places it before the icon/content, and `top` places it above
that content. A present false selection reserves its native check part without
drawing the mark. Removing selection removes that part from layout; restoring
it, changing placement or replacing an icon keeps the same retained native
MenuItem and authored children. Icons use the existing shared SVG lookup and its
missing-icon fallback. MenuItem has no canonical `icon_placement` parameter;
icons remain leading, and unsupported raw `icon-placement` is still rejected by
the common wire contract.

Sizes reuse the desktop command theme: `sm` has a 24pt minimum row and a 14pt
glyph, default has a 32pt minimum and a 16pt glyph, `lg` has a 40pt minimum and a
20pt glyph, and `icon` uses a 32pt square with a 16pt glyph. This adopts the
existing NSH command typography rather than Apple's menu-specific icon scale.
Authored size, font, foreground, padding and state styles keep precedence over
these defaults. Destructive actions use the scoped destructive foreground;
primary/secondary/outline variants reuse their scoped command colors, and
other/default variants keep ordinary menu styling.

`shortcut_hint` is retained trailing text in the item's native content, with no
additional shortcut registration or accelerator controller. Clearing and
restoring the hint updates the same text host. These bindings apply both inside
native menus and to canonical MenuItems hosted in authored popup content.
Source regressions cover live icon/check/hint/size/variant changes, authored
foreground/font precedence, part removal/restoration, child/editor identity and
native disabled traversal with controlled selection. Real native appearance
and keyboard qualification remain separate gates.

## NSH Input forwards focused previous/next navigation

NSH now supports the existing `on_navigate` callback of `input`, `text_field`,
`secure_field`, `search_field` and `textarea`. An enabled, focused input with
`navigate-enabled=true` requests `NavigatePrevious` for unmodified Up and
`NavigateNext` for unmodified Down. The callback keeps its existing canonical
node identity and does not edit the draft or change focus. This preserves
Logseq's property picker, view picker and handbook search navigation:

```ocaml
input ~label:"Search results"
  ~text:(reactive Fun.id query)
  ~on_input:(on_input send (fun value -> Search value))
  ~on_navigate:(function
    | Lui_protocol.NavigatePrevious _ -> ignore (send Previous)
    | Lui_protocol.NavigateNext _ -> ignore (send Next)
    | _ -> ()) []
```

The adapter observes the actual native Input reference. It adds two public
native key bindings only while that input has keyboard focus, is enabled, has
navigation enabled and is not composing. Losing focus, disabling the input or
navigation, beginning composition or disposing the owner removes those bindings;
a guard inside a permanent window binding would still consume another input's
keys, so that approach is not used. Shift/Alt/Control/Command modified arrows
remain native editing commands. Held plain arrows repeat navigation. A narrow
boolean memo keeps ordinary draft updates from tearing down and recreating the
key bindings. No second focus manager or application tree is created.

The native composition listener is shared with the optional blur-submit policy.
Neither callback overwrites the other's listener, and native editing,
composition and Enter/blur order remain owned by Input. The Combobox's existing
Input helper also receives its actual reference; this does not add an
unsupported canonical Combobox navigation property or change its Menu-owned
selection behavior.

An absent navigation option allocates no navigation observer/state. Initially
authored `navigate-enabled=false` can be toggled true later on the retained
Input. Adding true to a mounted input that originally omitted the property
requires remounting it; the batch is atomically rejected. An intermediate false
patch cannot bypass this installed-capability rule. Ordinary OCaml
`~on_navigate` authors true on initial mount and needs no migration.

No C export or wire ordinal changes: the runtime loads the already existing
`lui_ocaml_navigate_previous` and `lui_ocaml_navigate_next` functions optionally
and reports a missing requested export if an older application library lacks
it. Rust exhaustive matches on `render::Event` or `runtime::Event` must handle
the added `NavigatePrevious(node)` and `NavigateNext(node)` variants.

This route covers input previous/next requests. The separate full
`NavigationKey(node,key,shift)` contract used by Logseq's calendar Buttons and
other navigation hosts remains open; an Input request is not a substitute for
those key names/modifiers. The native Input fixture now checks the existing
OCaml callbacks through the C ABI while retaining its four mounted fields and
blur-save assertions. Headless tests additionally check removal of actual
bindings, modified keys, composition, focus transfer, disabled/live flags,
keyed editor retention and atomic late-capability refusal.

## NSH Checkbox paints authored indicator and label parts

The Checkbox route now forwards `indicator-border-color` to the
actual native indicator, `checked-indicator-border-color` to its checked and
indeterminate border, and `label-opacity` to the direct text label. These are
part styles: they do not replace the component's outer border, dim the check
mark, change authored body opacity or insert another layout wrapper. Missing
properties retain the previous desktop theme defaults. Updating/removing them
or changing the checked/mixed state keeps the same native controller and label.
Invalid part colors, including unresolved scoped variables, fail the batch or
theme update before native publication.

These properties are used by Logseq's shared Checkbox recipe and table selection
chrome (`logseq/refactor/lui` at `29dcb60fdc976dcda1da6ec984057bbf79d88612`,
`deps/ui/src/shared/ui_components.ml:92`, `views/views_table.ml:319`), and settings
label opacity at `settings/settings_page.ml:147`. For example, downstream code
using the public property writer may keep its existing part bindings:

```ocaml
let indicator_chrome (child : Lui_elements.t) : Lui_elements.t =
  fun context parent ->
    let node = child context parent in
    Lui_ui.string_property context node Lui_protocol.IndicatorBorderColor "border";
    Lui_ui.string_property context node Lui_protocol.CheckedIndicatorBorderColor "primary";
    Lui_ui.float_property context node Lui_protocol.LabelOpacity 0.7;
    node

indicator_chrome
  (Lui_elements.checkbox ~text:"Use global font"
     ~on_toggle:(function
       | Lui_protocol.ToggleChanged (_, checked) -> ignore (send (Set_global checked))
       | _ -> ()) [])
```

The native NSH Checkbox still owns activation, keyboard focus, disabled behavior,
checked/mixed accessibility state and the requested next boolean. Mobile's
`shared/src/logseq/view_property.ml:228` uses ordinary `on_toggle`; no Journal UI
Checkbox detail callback was found. Their ordinary boolean path remains intact.

### NSH Checkbox preserves native activation modifiers

NSH Checkbox/Toggle now accepts `toggle-detail-enabled=true`. The existing LUI
`on_toggle_detail` callback receives the native Checkbox's requested value and
modifier mask: Control=1, Shift=2, Command/Super=4, Option/Alt=8. An ordinary
`on_toggle` callback still receives one boolean proposal per activation. When
both callbacks are subscribed, each receives that same proposal once; the
application should apply the change from one callback only.

```ocaml
checkbox ~checked:true
  ~on_toggle_detail:(function
    | Lui_protocol.ToggleChangedDetail (_, checked, modifiers) ->
        select_row ~extend:(modifiers land 2 <> 0) checked
    | _ -> ())
  []
```

The adapter reuses the NSH Checkbox root's press owner and its typed
`ChangeDetail` event. Pointer modifiers come from the native press. Focused
Space/Return on macOS and Linux carry the activating keyboard event's modifiers;
accessibility activation has no physical key event and reports zero. Disabled
controls remain silent, mixed state still requests checked, and checked state
remains application controlled. Changing either callback's live subscription
flag does not remount the control or surrounding editors.

The Rust host loads the existing `lui_ocaml_toggle_changed_detail(node, checked,
modifiers)` bridge export and dispatches `ToggleChangedDetail` through it. This
requires a native bridge exporting that symbol when detail is used. Existing
ordinary-toggle applications do not require it. No LUI constructor or wire
schema changed, so Logseq table range-selection callers retain their API.

The NSH fork adds `CheckboxEvent::ChangeDetail(CheckboxChangeDetail)` alongside
`Change(bool)`. Rust exhaustive matches on that dependency enum must handle the
new variant. Its original boolean handler and TSX `onChange` payload remain
unchanged. Native OS qualification is recorded separately from source tests.

### NSH application extension registrations

An NSH application can supply immutable trusted Rust factories before mounting
`Desktop`: export each OCaml schema with `Lui_extension.schema_json`, parse it
with `lui_nsh::extensions::Schema::from_json`, register the factory with
`Extensions::builder().register(schema, factory)?`, and call
`.freeze(Profile { os: "macos".into(), host: "nsh".into() })?`. Supply the result
with NSH `provide_context` above `Desktop`. Registrations are scoped to that
application; an unconfigured application still rejects extension nodes.

Factories receive `ExtensionContext`, including the existing retained node
signal, `property(name)` (explicit value or canonical default), child rendering
capabilities, native `ElementRef`, and a schema-checked event emitter. Factories
run once per mounted incarnation. Unknown registrations, nonempty fingerprint
mismatches, unsupported profiles, undeclared or mistyped properties, missing
required values and invalid child relationships reject the whole transaction
before native construction. Extension properties use `set-extension-prop`;
standard `set-prop` does not apply to extension nodes. Empty fingerprints resolve
against the frozen schema even on the first create or an authoritative snapshot,
matching the canonical producer's fingerprint elision. Integers retain signed
62-bit bounds; JSON `1.0` remains a Float and is distinct from Int `1`.

`register_tweak` projects its typed target directly onto the single retained
child root using public NSH component composition. It adds no native layout
View. Property updates retain the target; changing a mounted tweak's content
identity currently requires a new keyed tweak node and otherwise fails
atomically. A region as the projection root would add a View in NSH and change
intrinsic layout, so it is not a transparent substitute.

Extension events use the existing generic C bridge's exact seven-argument
`lui_ocaml_extension_event_utf8` function, with separate identifier, event-name
and JSON-value lengths. Declared scalar payloads and incarnation guards apply
before queueing; the ordered application pump rechecks the incarnation before
foreign dispatch. A missing event export produces an explicit diagnostic. This
extension event ABI does not change the generic three-argument application start
ABI and does not by itself port Logseq's different application/service ABI or
provide its editor, PDF or platform services.

### Explicit Logseq native bridge configuration and ordered host messages

The default NSH desktop runtime continues to use the standard three-argument
`lui_ocaml_start` and its host-driven clock. Logseq's native library exports a
seven-argument function with the same name. Select its ABI explicitly; symbol-name
probing cannot safely distinguish those function signatures:

```rust
use lui_nsh::runtime::{BridgeConfig, Session};
let (session, initial) = Session::open_with_config(
    library,
    1, // macOS
    BridgeConfig::Logseq { payload: r#"{"paintsCaret":false}"#.into() },
).await?;
```

`Session::open` remains the generic shorthand. An initialized process cannot
switch application libraries or startup ABIs. The payload is passed as UTF-8 bytes
with an explicit length. Logseq currently requires exactly one boolean
`paintsCaret` capability; its native editor requires `false` when OCaml paints the
measured caret.

Logseq patch callbacks encode JSON arrays of batches (the generic bridge emits
one batch object). The driver decodes that actual format without changing wire
ordinals. Logseq replies use `Reply.messages: Some(Vec<ApplicationMessage>)` in exact native
callback order. Entries are `Batch`, authoritative `Snapshot`, or
`PlatformRequest { operation, payload }`. The generic path retains the existing
`batches`/`snapshot` representation and allocates no Logseq callback state. A
Logseq caller must process the ordered stream before dispatching another input:
for example, register an `app-icons` request before applying the subsequent batch
that references those icons. Do not concatenate requests after all batches.

A request is the existing `operation\npayload` host protocol; the bridge copies
its length-carrying bytes before the C callback returns. Host services execute
outside the callback. Send their results as `PlatformEvent { operation, payload }`
using `session.platform_event(...)`; that worker operation calls the native event
export followed by `pump`, because Logseq's event export enqueues work without
returning patches itself. The response retains callback order as well. For
example, a `measure-node` service produces a `node-rect` event containing the
existing Logseq JSON response, rather than a new LUI measurement wire format.

The application's existing ordered response loop waits on `session.woken()` and
calls `session.pump()` on wakeup. Wakeups coalesce and are retained across START;
no polling timer or second OCaml thread is introduced. Callback state is weakly
scoped to the active session and detached at close. The C ABI has no user-data
argument: wakeups after disposal are ignored while no session is active; a late
wakeup after reopening can only request a drain of the current mailbox.

Logseq owns its timers through `Host`; it has no generic clock-control,
`last_error`, or focus-within export. `next_delay` is therefore absent, and explicit
clock-control/focus-within requests return an unsupported-ABI error. They are not
silently converted to successful no-ops. A refused Logseq operation uses the
existing authoritative resync path without inventing a diagnostic export.

The dedicated `runtime_logseq` test compiles a real C shared-library ABI fixture
that checks the seven arguments, foreign-thread wakeup, one worker thread,
interleaved service/patch order, recovery, embedded NUL/Unicode reply lengths, and
reopening. It does not qualify OCaml startup or actual Logseq UI/services; those
remain separate application build and native launch gates.

For lifecycle callbacks that may run while a native owner is retiring, use
`ExtensionEmitter::try_emit(name, values)`: `Ok(true)` means dispatched,
`Ok(false)` means the node/renderer incarnation was retired, and `Err` still
reports an undeclared event or malformed payload. `emit` retains its original
error-on-retired behavior. This lets native Blur cleanup avoid treating normal
owner disposal as a schema failure.

`Session::editor_snapshot(block_id).await` uses the existing optional
`lui_ocaml_editor_snapshot_utf8` export on that same worker. It returns `None`
when no matching editor is active, or `EditorSnapshot { source, anchor, caret }`
for the authoritative display model including composition. Anchor/caret are
UTF-8 byte offsets and must lie on source character boundaries; malformed
snapshots fail explicitly. Block identifiers and JSON replies carry lengths, so
embedded NUL bytes are preserved. The query has no input dispatch, clock tick,
secondary editor cache, or second runtime thread. A missing or refused query is
an error rather than an empty-editor result.

### NSH application SVG icons

Native application roots can create an `application_icons::IconRegistry`, provide
it above `Desktop` with NSH `provide_context`, and install the `app-icons` payload
before publishing the corresponding LUI patches. `replace_json` takes the
existing flat JSON map of unprefixed application icon slugs to SVG markup. It
validates every name, scalar value, XML document and SVG root before replacing
the table. `IconTable::from_json` prepares the same validated replacement without
requiring a native owner. Invalid messages preserve the previous table.

LUI `app:name` icons read that root's table reactively; updates preserve native
identity and geometry and reuse NSH's SVG drawing cache. Standard built-in names
keep their assets and cannot be overridden. An unregistered `app:` name falls
back to the matching canonical built-in when available, otherwise the existing
missing-icon asset. Roots have independent registries, and replacing an equal
table publishes no updates. Tables are limited to 32 MiB and 16384 entries, with
256 KiB per SVG; NSH retains its existing rendering/resource limits.

Logseq's existing native `app_icon_svgs` custom-only payload assumes its host
already bundles the complete Tabler table. An NSH application must supply that
existing application table as well as custom overrides; the generic adapter does
not import Logseq's asset catalog or create a second icon decoder/cache.

### Application services on the existing desktop pump

Provide `runtime::BridgeConfig` and `app::ApplicationServices::new(handler)` as
NSH contexts above `Desktop` to select Logseq startup and service dispatch.
The handler receives copied `PlatformRequest` and the retained `Renderer`, and
returns `app::ServiceFuture` with `ServiceResponse::Events` containing actual
`PlatformEvent` replies. It runs outside
the foreign callback. The same desktop task processes mixed native messages in
callback order; messages caused by service replies follow already captured
messages. It waits for an explicit runtime wakeup between application events.
Generic applications preserve their existing clock and publication path.

Native menu/window callbacks can capture `app::ApplicationEvents` from context
and call `send(event)`. This queues through that same ordered task and reports a
closed/full queue. Factories that need a read-only editor snapshot capture
`app::ApplicationRuntime` and call `editor_snapshot(block_id).await`. This is a
barrier on the same input queue, so a read cannot overtake earlier emitted edits.
The capability is provided before retained regions are constructed; adding a
context after opening asynchronously would not reliably reach those regions.

Host services may read `Renderer::node_snapshot`, `root_id` and
`find_by_identifier`, and obtain `native_reference(id, incarnation)` for an exact
retained node. Recheck its incarnation after awaiting measurements before
returning a node-specific reply; a replacement with the same numeric id must not
inherit work from the old native node. These are immutable snapshots and native
capabilities over the existing entries, not another application tree.

### NSH computed application themes

Provide `application_theme::ThemeRegistry::new()` above `Desktop`. The existing
`theme-snapshot` service payload is installed with
`install_snapshot_json(&payload)`, and `ui-state.data.theme` selects `set_mode`:
`light`, `dark`, empty or `system`. Snapshots contain a `light`/`dark` mode and a
map of computed `--custom-property` names to strings. Validation completes before
replacing that mode; malformed names, values, native role colors, radius or
application typography leave the previous snapshot intact. Missing snapshots use
native defaults. This consumes the producer's computed cascade; it adds no CSS
cascade implementation or polling.

The adapter maps `--lui-role` to its semantic native role, falling back to
`hsl(var(--role))`, as Logseq's previous desktop host did. Raw `--ls-*`/`--lx-*`
variables remain available through the existing scoped variable resolver.
`--lui-radius`/`--radius`, `--lx-font-stack` and positive pixel
`--lx-root-text-size` supply radius and inherited native typography. Per-node
LUI theme overlays remain authoritative. Theme changes update retained signals
and styles without recreating native controls or editor drafts. An explicit
application mode does not overwrite the operating system's real appearance.

Extension factories can resolve the same retained scope through
`ExtensionContext::color` and `resolve_text` inside reactive bindings. Standalone
applications may project the selected theme through `ThemeRegistry::native_tokens`
and explicitly call NSH `set_tokens` for their whole native surface. Embedding
applications retain ownership of that surface-wide choice; the generic registry
does not call `set_tokens` globally or change other embedded renderers.

Extension factories may attach `ExtensionContext.reference` to their actual
native control, including a control below a keyed region. This ref is separate
from the registry host's retained-root ref. `Renderer::native_reference` prefers
the actual attached factory ref, otherwise the host root; a region cannot
silently overwrite the editor's native focus/measurement target. Ordinary
standard components allocate no additional factory reference.

`ExtensionBuilder::validate_themed` adds pure native-style preflight against the
actual inherited `ExtensionStyle` resolver (`color` and `resolve_text`). The host
runs it on final affected nodes before committing a patch/snapshot, and before
publishing a theme refresh. Invalid resolved values preserve the previous native
tree and styles. Validation callbacks borrow immutable theme data; they must not
construct native views or mutate the application. Property-only edits validate
only affected entries, and registrations without themed checks keep the existing
path. Application adapters should compile authored variable expressions here;
substituting arbitrary paint placeholders for layout variables is invalid.

Geometry/focus service requests can arrive before the OCaml batch creating their
native target. Return `ServiceResponse::AfterCommit(future)` to execute after all
currently captured responses have been published and the next native frame.
Awaiting layout inline would block the batch needed to create that layout.
Deferred futures are owner-scoped; their replies enter `ApplicationEvents` on the
same input pump. Capture known target incarnations before deferring; unresolved
creation references may bind once after commit. No task cache or polling is used.

`ApplicationRuntime::editor_snapshot` is intended for factories outside a running
service handler. Do not await that queue barrier inside `ApplicationServices`:
the handler itself occupies the queue and would wait for its own completion.

### Native app-content screenshots through the LUI CLI

`tooling/lui_agent.mjs` accepts `screenshot "output.png"`. An opted-in NSH macOS
host (`LUI_AGENT_LISTEN=127.0.0.1:PORT`) captures its own content view in process
on AppKit's main queue and returns PNG bytes/dimensions through the existing
loopback protocol. The CLI validates PNG encoding/IHDR dimensions, writes the
artifact and prints metadata instead of base64 data. Screenshot replies are
bounded to 16 MiB of PNG data; the client accepts bounded 32 MiB reply lines.
Screenshots do not activate applications, change display power, unlock the Mac,
use WindowServer capture, or request Screen Recording permission. They exclude
system menus, other windows and separately composited video/shader surfaces.
Other operating systems currently return an explicit unsupported-capture error.

Capture now crosses the existing `wait_for_commit` answer boundary before reading
the AppKit view. This orders it after already published native changes without
waiting for a physical display tick, including a locked/background window. It
does not wait for future asynchronous graph work: callers must still check that
the expected page body is present in the captured image.

Generic OCaml agents retain their existing semantic commands. Logseq's
seven-argument native bridge now optionally exports the same
`lui_ocaml_agent_utf8(request, length, reply)` channel. Its implementation uses
`Lui_agent.app_target` against the real application reducer and drains every
ordered patch batch under the existing application entry lock before replying.
For example, `find prop:accessibility-identifier=left-menu` and `press id:42`
use the canonical LUI selector/event implementation; no native selector engine
is added. `hello` advertises supported semantic operations. An older library
without this optional export rejects semantic requests explicitly; it must be
rebuilt to use them. Semantic actions do not establish native hit testing, focus,
IME, accessibility or pixel correctness.
The Logseq runner accepts `LUI_AGENT_BACKGROUND=1` for a background-only AppKit
launch. Build receipts remain required unless the CLI's existing explicit
`--unchecked` option is selected. See the repository's
[lui-cli skill](../.agents/skills/lui-cli/SKILL.md) for the exact workflow.

### NSH structural `display: contents` anchors

NSH now flattens `box`, `row` and `column` nodes with `display="contents"` into
public retained child regions. For example, `row [box ~display:`contents
[editor; button]; sibling]` lays out the editor, button and sibling in the row's
single child sequence. No native Box, extra gap or focus target is introduced;
logical IDs, parent links, keyed child owners and scoped visibility remain.

Appear callbacks follow the logical mounted incarnation, including empty anchors;
scoped hidden anchors wait until visible. Pointer/focus callbacks, independent
accessibility labels/roles and subtree disabled/inert state require a real native
container and are rejected on contents anchors. Inherited text/theme properties
on the anchor currently require an enclosing native container and are rejected
explicitly. Its noninherited box layout and paint do not generate a native box.
Changing between contents and a native display mode while mounted requires a new
key; ordinary child edits and reorders preserve the retained children.

### NSH inherited `font-size: 1em`

Standard NSH elements now accept `font-size="1em"` (also `1.0em`) as native
inheritance. For example, ``column ~font_size:"24px" [text ~font_size:"1em"
~value:"Inherited" []]`` uses the parent's 24-point size and follows later parent
size changes without replacing the child. It does not substitute a fixed 16.

Point/`px` sizes and the existing NSH root `rem` unit retain their behavior.
All finite nonnegative `em` ratios now use the same native inheritance path
(see "NSH relative font sizes use native text inheritance" above). The internal
unit parser and native translation use an exhaustive typed representation. No
common OCaml constructor or wire scalar changes.

### NSH whitespace and wrapping

Canonical text-owning NSH hosts now translate `white-space` through an
exhaustive native policy. `nowrap` selects NSH's inherited NoWrap text property;
`normal` and `pre-wrap` select native wrapping. This uses public
whitespace classes, not a synthesized one-line clamp or a replacement container.
A child's explicit policy overrides its parent, including live changes and
transparent contents anchors.

Explicit `normal`/`nowrap` collapse CSS spaces, tabs, line feeds, carriage returns
and form feeds within library-owned display text/labels. Boundary spaces are
retained for adjacent inline text, and nonbreaking/Unicode spaces are preserved.
`pre-wrap` preserves the source string. Editable model values and custom
extension payloads are unchanged. With no authored/inherited policy, existing
native text presentation remains unchanged. For example, ``text
~white_space:"pre-wrap" ~value:"first  line\nsecond line" []`` preserves both
spaces and the line break while wrapping natively; `nowrap` renders collapsed
label text on an unwrapped native line. `pre-line` and `break-spaces` remain
explicit capability errors; they are not approximated by another mode.

The canonical whitespace property remains limited to kinds that own inline text;
ordinary Column, Box and editable Input/Textarea nodes do not acquire a new prop.
Native containers can carry inherited policy from text-owning parents such as
Alert/Bubble. `pre` and `break-spaces` are not admitted by the common wire schema;
no additional spelling is enabled by this adapter.

### Canonical closed domains in NSH provider compilation

The native contract exporter now includes `closedDomains` derived from the
existing generated typed constructor contracts. A property is closed only when
all constructors exposing it use finite enum values; free strings such as
`font_size` remain open and are not mislabeled as enums. No shared OCaml
constructor type, default, wire value or maintained Apple/Android/Web behavior
changes.

The same generator emits Rust `contract::DisplayValue`, including fallible
string conversion and exact wire roundtrips. NSH's structural contents predicate
and display provider consume this type. The provider matches every canonical
case without a wildcard: adding a case to the canonical typed domain now fails
its Rust compilation until the provider explicitly implements or rejects it.
`contents` remains structural; inline layout variants remain explicit native
errors. The generator checks typed-schema freshness before exporting, and its
source receipt includes the typed API and generator inputs.

This is compiler coverage for provider enum cases, not a claim that arbitrary
CSS strings are statically safe. Backend-specific PPX literal checks and a
checked typed metric API require a separately wired build profile; an unused
PPX option would not qualify as an enforced gate. Dynamic theme/style strings
continue through existing atomic preflight before native publication.

The same closed-domain compilation also covers `contract::ImageFitValue`.
`fit` maps to native contain and `fill` maps to native cover through an exhaustive
match. Missing fit still stretches ordinary Image and contains FileImage;
authored invalid values fail preflight rather than taking those missing-value
defaults. New canonical fit variants require an explicit Rust provider decision.
No image constructor or downstream migration is required.

### Initial NSH application theme preflight

`Renderer::element()` now synchronously seeds its base theme from an already
installed application `ThemeRegistry` snapshot before returning the native root.
The first immediately following patch can therefore resolve application variables
without waiting for the deferred reactive effect. Initial and later refreshes use
the same resolver, transactional preflight and diagnostic path; rejected refreshes
retain the last accepted theme. No wire values, defaults or maintained backend
behavior change.

### NSH inherited foreground preserves native ancestor and state colors

NSH now accepts `foreground="inherit"` (and the CSS equivalent `currentColor`)
for ordinary foreground and the canonical `hover-foreground` paint channel. It clears the local control
color and uses the actual native ancestor's foreground, including later ancestor
changes. It does not substitute the application theme's foreground or a fixed
color. For example, a button can inherit its containing column's color while
keeping an authored hover override:

```ocaml
column ~foreground:"#123456"
  [ button ~foreground:"inherit" ~hover_foreground:"#00ff00"
      ~text:"Open" [] ]
```

The adapter uses public `text-inherit` utilities at the corresponding native
state rank. It combines them with whitespace policy in one `app_class` binding;
these features cannot overwrite each other. A raw inline reset would outrank
state colors, so this implementation preserves authored hover paint precedence
and the control's existing native state behavior. This does not add new public
foreground channels for other control states.
CSS-variable aliases/fallbacks and scoped appearance are resolved before choosing
the native inherited or explicit color path.

This adds foreground inheritance only. Background, border and shadow colors
still require their own supported color semantics; `inherit` is not converted to
an arbitrary color for those properties. No OCaml wire ordinal or maintained
mobile backend changes.

### NSH desktop cover-layer pointer policy

NSH now projects an explicitly authored `pointer-enabled` value into native hit
testing, preserving the previous desktop MyGo policy. `false` makes the node
and its ordinary descendants transparent to the pointer; an explicit `true` on
a descendant restores native interaction for that subtree. Omitting the property
preserves the inherited native policy. Presented dialog, sheet, popover, dropdown,
context-menu and toast surfaces restore interaction by default; a structural
carrier marked `data-overlay-layer=true` does not. A drawer without an authored
`selected` state retains its previous desktop presented-surface default.

For example, the wire operations below keep a permanent overlay carrier from
covering underlying buttons while allowing its independently interactive content:

```json
[
  {"op":"set-prop","id":100,"property":"pointer-enabled","value":false},
  {"op":"set-prop","id":101,"property":"pointer-enabled","value":true}
]
```

Here node `101` is a descendant of node `100`. This does not change keyboard
focus or the enabled state. Pointer callback subscriptions still follow the same
flag. Web and Apple retain their existing implementation: Web uses its CSS layer
policy in addition to pointer subscriptions, and Apple uses its native surface
hit testing. Do not infer that disabling a pointer subscription on those backends
is a portable replacement for a hit-transparent native desktop cover.

### NSH nested Stack fills its assigned grid cell

NSH Stack now passes the full assigned grid-cell size through its retained
z-index wrapper to the actual child. Previously, a viewport-height Stack could
contain a second Stack that shrank to its header's intrinsic height, leaving a
`grow:1` main row with zero available height. Existing explicit child width and
height remain authoritative. No viewport constants or geometry feedback are
introduced, and retained child identities survive parent size changes.

For example, `stack [column ~grow:1. ~min_height:0 [header; row ~grow:1.
~min_height:0 [body]]]` fills an assigned parent height without adding a height to
the inner Stack. The parent must still receive a real size from its own layout.
Synthetic Stack/Overlay layer wrappers also ignore hits on themselves; their
actual child nodes retain the authored pointer policy and interactive behavior.
This changes no OCaml API, wire ordinal or maintained mobile backend.

### NSH empty Spacer hit testing

A desktop `Spacer` now takes no pointer by default. Its layout contribution and
retained native identity remain unchanged. This matters when an empty reactive
branch uses a Spacer inside a Stack: the spacer can fill the stack's grid cell
without covering the buttons beneath it. Explicit `pointer-enabled=true` restores
native hit testing and the supported pointer-enter/leave callbacks; setting it
back to `false` makes the same retained spacer transparent again. Spacer does not
gain a press callback.

No application change is required for ordinary `spacer []` placeholders. Code
that deliberately uses a Spacer as a hover target must explicitly author
`pointer-enabled=true` through its existing wire/property path. Apple, Android
and Web behavior is unchanged.

### Visible NSH backend diagnostics preserve the first rejection

`Renderer::fail` now preserves the first failure and a single latest follow-up
rather than replacing the cause with later generation or recovery errors.
Repeated identical diagnostics do not republish native UI, and changed failures
are also reported on stderr. The `lui-backend-error` test ID remains on the
message, now in a semantic alert panel pinned above the existing application
instead of below its full-height content. The mounted app and its retained
native identities remain in place; rejected patches and snapshots still fail
atomic validation. Downstream startup gates can use the same test ID and will
now observe the original cause within the viewport.

### NSH CSS shadows distinguish explicit colors from currentColor

CSS shadow layers that name concrete colors now use the native typed shadow
path in both base and state paint. For example,
`~shadow:"0 1px 3px rgba(0, 0, 0, 0.1)"` and
`~hover_shadow:"0 2px 4px #123456"` retain their native state precedence. The
adapter previously misinterpreted NSH's `has_color` parser flag as a
`currentColor` flag, rejecting the explicitly colored layers.

A layer with no color, an explicit `currentColor`, or a mixture that includes
an uncolored layer still fails validation before publication. These require a
faithful live foreground projection; they are not replaced with black or a
snapshot of an ancestor color. Name each layer's intended color when migrating
until that separate capability is available. Preset shadows remain unchanged.

### NSH display-none native accessibility visibility

NSH `display=none` now also projects public native `visibility=hidden` to the
same host. The pinned native engine removes layout frames for display-none but
its accessibility adapters use the visibility flag to exclude a whole subtree.
This closes the gap where a zero-sized control could remain represented to
assistive technologies. No new public property or general inert behavior is
introduced.

A normal child with `display=block`, or an explicit pointer opt-in, cannot make
itself interactive beneath a hidden ancestor. Restoring the parent's display to
block or removing that display property clears only that parent's local hidden
projection; an independently hidden child remains hidden. All retained native
IDs and editable content survive these property updates.

For example, update an existing sidebar's `display` from `none` to `block` to
reveal its retained controls. Removing the property returns to the node's normal
layout and inherited visibility. Do not replace the sidebar's child list to
perform this visibility change. Maintained Apple, Android and Web mappings are
unchanged.

### NSH host services wait for commits without requesting display frames

Deferred `ServiceResponse::AfterCommit` host operations now synchronize with the
owning native commit through public `after_answer`, then obtain geometry using
`ElementRef::measure`. They no longer wait for `next_frame`: macOS deliberately
stops display-link callbacks while the screen is locked or all application
windows are covered. This prevented real native content measurements from
completing even though Headless tests advanced their synthetic display frames.

Native host adapters can use `lui_nsh::app::wait_for_commit().await?` for the same
one-shot owner-scoped barrier before checking a newly mounted reference. Owner
disposal cancels the wait with an error; callers still check the target's current
incarnation. This is a commit boundary, not a promise that a window was displayed.
No polling, timeout, synthetic frame, window activation or geometry fallback is
introduced. Generic applications without deferred host work allocate no barrier.

### Exhaustive NSH frame and popup axes

The canonical contract generator now also emits `contract::FrameAxesValue`,
`AnchorValue` and `AnchorAlignmentValue` from the existing `closedDomains` export.
Native frame sizing explicitly matches all six canonical axes to the appropriate
percentage width/height or minimum dimension. Popup placement and alignment also
use exhaustive typed matches: `stretch` retains its existing start alignment plus
anchor-width minimum. Missing popup properties still default to below/start;
authored unknown or wrongly typed values fail atomic preflight rather than taking
those defaults. Nonzero frame insets and other existing unsupported options remain
explicit errors. No OCaml constructor, wire spelling or mobile/Web behavior changes.

These values are used by Logseq's native sidebar/content frames and page/editor
popups. Adding a canonical case now fails provider compilation until native
lowering explicitly implements or rejects it. Regression probes compile the actual
provider functions, verify every current semantic mapping and wire roundtrip, then
add an unhandled case to each domain and require Rust E0004. This checks provider
exhaustiveness; dynamic JSON/theme strings, geometry, source ownership and runtime
capabilities still require atomic validation and real application qualification.
Open strings such as font metrics are not relabeled as closed enums. Remaining
closed-domain providers, including variants, need the same gradual conversion; this change does not claim that every string path is statically checked.

### Exhaustive NSH orientation lowering

`contract::OrientationValue` now comes from the canonical `orientation` closed
domain. Native axis and flex-direction lowering exhaustively match the generated
variants. Scroll, Toolbar, Tabs, Divider and ViewThatFits reuse these mappings;
row-like layout uses the same typed domain. Adding a canonical orientation now
fails provider compilation until both native mappings handle it, with an E0004
regression probe that compiles the actual provider functions.

Defaults remain component-specific: omitted Scroll orientation means vertical;
omitted row, Toolbar, Tabs, Divider and ViewThatFits orientation means horizontal.
An authored unknown or wrongly typed value is an error, rather than a default.
Scroll and Toolbar still reject an axis change on a retained mounted node;
replacing its key remains the migration for an intended direction change. For
example, ``scroll ~orientation:`horizontal`` still selects horizontal native Scroll,
while omitting the argument selects vertical. OCaml constructors, wire spellings,
events, and maintained Apple/iOS, Android and Web behavior are unchanged. Dynamic
wire values still require atomic validation; this does not statically verify
arbitrary theme strings or geometry.

### ContextMenu rejects unsupported constructor options at compile time

`Lui_elements.context_menu` now exposes only `key`,
`accessibility_identifier` / `accessibility_identifier_signal`, `on_dismiss` and
its children. Its previously copied layout, appearance, disabled and pointer /
appear callback options were not admitted by the canonical ContextMenu contract;
using them failed during mounting. They are now absent from the OCaml signature,
so both direct and partially applied calls fail compilation. Existing valid
menu identity, restricted children and dismiss behavior are unchanged on every
backend. No wire property or mobile backend is removed.

For example, replace the already invalid
`context_menu ~width:256 ~style_class:"menu" [menu_item ~text:"Copy" []]`
with `context_menu ~key:"actions" [menu_item ~text:"Copy" []]`. The native menu
owns its surface presentation; style supported menu items or their trigger as
needed. This migration does not promise custom menu surface dimensions.

The generated JSON-view dispatcher is regenerated from the narrowed interface.
Dynamic menu options that name unsupported canonical properties still raise an
explicit error before mounting, using the shared property predicate, rather than
being silently discarded by the narrower constructor. Compile regressions reject
width, style, disabled and unsupported callbacks; valid identity/reactive identity
and dismiss calls compile, and JSON identity/dismiss behavior is exercised.


### NSH native time inputs

``input ~kind:`time`` now uses the public NSH `TimeField` for segmented native time
editing. This is the route used by Logseq's date-time property calendar. Source
`text` must be a valid, nonempty, zero-padded 24-hour `HH:MM` or `HH:MM:SS` value;
its shape selects minute or second precision, including explicit `:00` seconds.
Text is parsed/formatted with the same locked Chrono version used by NSH.
When source precision changes, the new format reaches native TimeField first;
its new time value is delivered at the public owner-scoped `after_answer`
boundary. The component's independent format/value effects otherwise can truncate
seconds using the previous precision. Only precision changes use this boundary;
same-precision values remain immediate. A stale source tuple cannot deliver after
a newer one, and owner disposal cancels the callback. This retains the same native
Input and focus without a timer, frame wait, remount or second editing controller. Empty,
invalid, fractional-second, leap-second or noncanonical drafts fail atomic
preflight; they never silently become midnight or an uncontrolled native value.

Native `TimeFieldEvent::Change` emits the existing `TextChanged` text payload at
the current precision, gated by live `enabled` and `change-enabled`. Source edits
update the retained field. NSH retains its segment selection, keyboard editing,
focus and accessibility ownership; the adapter adds no second segment controller,
parser state or text cache. Label/disabled updates use native props, and the
existing renderer focus observers retain their canonical semantics.

Single-line Return emits one Submit and dismisses native input focus. Its trailing
blur does not submit a second time. Ordinary focus loss submits only when the live
`submit-on-blur` policy is true. The observer is already installed for TimeField's
Return policy, so changing this flag does not remount the field. Event dispatch
uses the existing node-incarnation guard; removal/replacement cannot redirect a
trailing blur into the new Input. This does not qualify an operating-system IME.

Public TimeField does not expose read-only selection, autofocus of its internal
Input, placeholders or LUI navigation callbacks. True `read-only`, `autofocus`
or `navigate-enabled`, and nonempty placeholder text, are explicit atomic errors;
false/absent flags remain accepted. `pointer-enabled=true` remains admitted:
canonical input/submit registration also sets that shared semantic capability,
so it does not by itself imply an authored pointer controller.
The used Logseq calendar has valid `HH:MM` source text and blur submission without
those options. Color inputs remain rejected. Changing a retained Input between
text and time requires a new keyed node, because its native component is selected
once. Maintained Apple/iOS, Android and Web behavior is unchanged.

`contract::InputTypeValue` is generated from the canonical closed domain and
exhaustively lowered to native Text, TimeField or the explicit unsupported Color
case. A new canonical input type breaks provider compilation until handled; the
compiler regression adds such a case and requires E0004. Positive native component
regressions separately cover encoding/precision, Return/blur counts, live source
updates and native identity, disabled/blur policy changes, and rollback of invalid
text or unsupported options. An exhaustive error arm alone does not prove support.

### Reactive children can consume a projected reactive source

The PPX now recognizes a direct nested `reactive` in a reactive child's source
position as a signal projection, for example:

```ocaml
reactive (fun page_id -> page_menu page_id)
  (reactive (fun model -> model.page_id) model_source)
```

The inner projection belongs to each mounted consumer. Removing that consumer
releases its derived subscription without disposing the shared model source or
another consumer's projection. The outer subtree comparator retains its existing
semantics: the default structural equality skips reconstruction when the
projected value is equal; an explicit `~equal` still overrides that comparison.
Project immutable data here, rather than view closures, unless supplying an
appropriate explicit comparator.

The direct projection may combine existing sources using the normal
`reactive project source_a source_b` form. This addition covers the direct source
of reactive children; it does not reinterpret nested view expressions as signal
pipelines or introduce a separate public signal API. Existing children and
reactive property syntax are unchanged.


### NSH CLI native controller activation

NSH's loopback agent adds the explicit `native-press` operation and advertises it
in the additive `host_native_ops` hello field. Existing `ops` and `press` remain
unchanged. For example, `native-press "More"` activates the retained NSH menu
trigger even if it has no OCaml press handler; `press "More"` still dispatches
only the canonical OCaml event.

The host delegates selector matching to OCaml `find`, requires exactly one
match, pins its node incarnation and native reference, measures the current
center and rechecks identity/admission before calling public
`ElementRef::press_at`. It reuses the renderer's pointer policy, including
presented-surface overrides, rejects disabled/unmounted/retired targets, and
waits for a native commit without a display tick. Success reports the target
`node`, `incarnation`, `handled` and `activation: "native-controller"`.
`handled: false` is an explicit result when no native press listener takes it.

This operation supplies only a single Press to the native controller. It is not
hardware pointer, hit-testing from the application root, hover, PressDown/Up,
keyboard, focus or IME qualification. It never activates the application or
changes display power. macOS hello also advertises the existing `screenshot`
host operation; other hosts keep screenshot explicitly unavailable.
### Tooltip and FilePicker reject unusable constructor labels at compile time

`tooltip` and `file_picker` no longer expose copied universal optional labels
whose emitted property the canonical `property_supported` predicate always
rejects. Removed labels cover gap, main/cross alignment, grow/columns, padding,
margins, paint and paint signals, border/radius, width/height/min/max dimensions,
`style_class`, `data_attrs` and its signal form. FilePicker also removes
`container_relative_frame` and its inset; Tooltip retains both because they are
canonical properties of Tooltip. This is a typed API correction across hosts,
not an NSH-only restriction or a relaxation of the wire protocol.

Keyed identity, static/reactive accessibility identifiers, appear and pointer
enter/leave handlers remain available on both constructors. Tooltip retains its
text/static signal, frame axes/inset and all existing anchor/delay options.
FilePicker retains source, request, types, multiple, disabled, completion, accept,
directory, their existing signal forms, picked/dismiss handlers and children.
Only always-invalid labels are removed; backend-specific picker source/filter
restrictions are unchanged. The common implementation passes `None` for removed
universal helper arguments, rather than accepting public labels and ignoring them.

For example, move a picker's requested visual size onto its existing trigger:

```ocaml
file_picker ~request:(`Int 1) ~accept:".md" ~on_picked:handle_picked
  [box ~width:240 ~padding:8 [button ~text:"Choose a document" []]]

tooltip ~key:"details-hint" ~text:"Details" ~anchor:`below
  ~accessibility_identifier:"details-hint" []
```

Place Tooltip trigger geometry/paint on its containing control rather than the
leaf hint. `tooltip ~width:240 []` and `file_picker ~background:"surface" []`
now fail OCaml type checking instead of mounting and then failing wire validation.
The generated JSON view also checks these kinds against the existing canonical
predicate before constructing them, so dynamic callers cannot silently lose the
removed fields. Generated typed view metadata reflects the narrowed signatures.

The maintained mobile shared and logseq_journal app source audit found no direct
Tooltip or FilePicker constructor calls. Their button/icon `~tooltip` arguments
are separate APIs and unchanged. No backend, protocol rule, wire spelling, event
payload or default changes. PPX-suite positive probes exercise all retained
constructor argument families and reactive forms; negative probes require type
errors for every removed label. Runtime JSON regressions cover rejection before
mounting and preservation of admitted text/frame/identity/filter properties.


### NSH collapsed Text removes glyph advances while retaining logical source

Standard Text presentation under `display=none` now contributes an empty string
to native attributed text, including when a containing LUI ancestor is collapsed.
Previously native `visibility:hidden` concealed those glyphs but retained their
advances, so hidden editor delimiters left space and shifted caret/range geometry.
The source `text` property, wire node and native Text/span reference remain intact;
showing the node restores its current source without remounting. A descendant's
`display=block` cannot escape a collapsed ancestor.

This is a rendering projection in the existing whitespace helper, not an edit to
Store data or an additional text model. Its existing inherited scope memo now also
carries the effective display-none bit; unchanged scope values stop propagation,
and only affected descendant bindings update. No tree scan, native removal,
polling, independent layout or NSH change is introduced. Editable Input values and
extension payloads keep their existing source ownership. Native visibility hidden
continues to reserve glyph space: it is not treated as display-none. Existing
native hidden state continues to govern accessibility and interaction.

For example, a line containing nested `L`, `[**]`, `R` Text spans draws `LR` when
the middle span is collapsed, and restores `L[**]R` with the same native identities
when shown. A nested delimiter collapsed on its own produces `L[]R`; the original
`**` remains in the logical source throughout. Native text measurement, selection
ranges and caret positions use the rendered UTF-16 string, while editor run/source
spans remain logical offsets. Consumers translating byte/source offsets must keep
using their real run-to-span mapping; this projection does not implement a Logseq
geometry service or qualify native IME behavior. Maintained Apple/iOS, Android and
Web backends and the wire protocol are unchanged.


### Row and Column reject grid-only column counts at compile time

`Lui_elements.row` and `Lui_elements.column` no longer expose `?columns`. The
canonical `GridColumns` property has always been supported only by Grid, so
passing it to Row or Column previously compiled and then failed when mounting
on every backend. This removes an unusable constructor argument; the wire
property and valid Web, Apple/iOS, Android and NSH grid behavior are unchanged.

For example, replace `row ~columns:3 cells` with `grid ~columns:3 cells` only
when a three-column grid is the intended layout. If Row/Column is intentional,
remove the unsupported argument; this migration does not convert layouts
automatically. Helpers forwarding `?columns` to Row/Column must likewise remove
that forwarding. Static `grid ~columns:3 cells` and a reactive structural branch
such as `reactive (fun count -> grid ~columns:count cells) counts` remain valid.
Grid does not gain a new `columns_signal` property binding in this change.


The JSON view builder retains this same canonical distinction: for example,
`{"kind":"row","columns":3}` now fails immediately with
`Unsupported property for row: columns` instead of losing the supplied option.
`{"kind":"grid","columns":3}` remains valid. The JSON spelling is `columns`,
which resolves to the existing canonical `GridColumns` property; this adds no
new wire spelling or separate property-acceptance matrix.


### Submit-on-enter is a Textarea policy

`text_field`, `secure_field`, `input` and `search_field` no longer accept
`?submit_on_enter`. That wire property has always been valid only for Textarea;
explicitly supplying it to a single-line constructor previously compiled and
failed during mounting. Their existing `?on_submit`, `?submit_on_blur`, controlled
text and native focus behavior are unchanged. No host validator or event ordinal
changes in this correction.

For example, replace `text_field ~submit_on_enter:true ~on_submit:save []` with
`text_field ~on_submit:save []`. Web's existing single-line Enter path, Apple's
native submit callbacks and NSH's native Input defaults already operate without
this flag. Supplying `false` was also invalid; removing it does not introduce a
new single-line suppression policy. Use the platform's supported input contract
rather than treating that removal as a way to disable submission.

`textarea ~submit_on_enter:false ~on_submit:save []` remains valid, including the
maintained mobile composer and journal callers. The JSON view builder rejects
`{"kind":"input","submit-on-enter":false}` through the same canonical predicate,
and continues to accept the flag on `{"kind":"textarea",...}`. Android's existing
single-line IME/submit event wiring is a separate qualification gap; this API
correction makes no new claim about Android keyboard submission behavior.


### Typed view metadata reports existing state aliases accurately

Typed constructor introspection now reports `menu_item ~checked` and
`toggle_button ~checked` as emitting `selected`, and `radio ~selected` as
emitting `checked`. MenuItem/ToggleButton `checked_signal` continues to emit
`selected`, while Radio `checked_signal` continues to emit `checked`.
These aliases and their precedence already belonged to the constructors; this
correction changes metadata only, preserving constructor signatures, emitted
patches, events and maintained backend behavior.

For example, tooling inspecting `Lui_wire_schema.view_contract MenuItem` now
finds the canonical `Selected` property for checked menu rows, rather than
incorrectly treating the accepted constructor alias as the unsupported
`Checked` wire property. A consumer that generates wire patches from constructor
metadata should use the emitted canonical field; application view calls such as
`menu_item ~checked:true []` need no migration.


### NSH screenshot failures include bounded own-window diagnostics

On macOS, the existing `screenshot` operation still requires an already visible
content window. When none is eligible, its error now preserves the prefix
`the application has no visible content window to capture` and appends
`own-window diagnostics=<JSON>`. For example, a running background host with no
windows reports `windowCount: 0`, its application hidden/active state and numeric
AppKit activation policy. Hosts with windows include at most eight entries with
visibility, miniaturization, main/key state and content bounds; `truncated`
indicates additional windows. Nonfinite bounds are marked by `finite: false`.

Consumers that recognized this failure by exact string equality should match
the preserved prefix instead. No window title, document text or other app is
inspected. The diagnostic reads existing AppKit state on the main queue and does
not show, activate, restore or create a window, alter capture selection, change
display power or weaken the visible-window requirement.


### Pure signed update configuration validation

Packagers can call `lui_nsh::update::validate_configuration(bytes)` before signing
an installed application. It uses the same canonical configuration parser and
signed whole-application policy as `Updater::open`, without installation lookup,
cache access, worker creation or network requests. Success does not qualify the
feed, archive, installed root or restart path; those checks still belong to the
installed updater and release qualification.

For example, validate the exact generated `nsh/assets/nsh-updater.json` bytes,
then place those unchanged bytes into the package before signing. Invalid or
unsigned configurations remain errors; this API supplies no default URL or key.
Existing `Updater::open(config, executable, cache)` calls remain valid.

### Application-owned update menu contributions

`lui_nsh::desktop_updates::{UpdateActions, UpdateLabels}` lets an embedded
application retain its existing native menu. Construct `UpdateActions::installed(lifecycle)`
once inside the application owner, then read `menu_items(translated_labels)` in
that menu owner's existing effect and insert the returned items into its menu.
Call `UpdateLabels::validate()` before admitting externally translated labels;
`{version}` and `{notes}` placeholders are required where declared. `new(updater, lifecycle)`
also accepts an explicitly selected existing `Updater`, preserving all installed
root/configuration/signature checks.

For example, append `updates.menu_items(labels)` to an application's own About/
Quit group; do not mount a second `DesktopApp` to obtain update controls. This
controller never calls `set_application_menu`. Phase changes are reactive, with
no polling. It reuses the existing download/install confirmations, cancellation,
verification error handling and retained verified download. Installation and
relaunch require the application lifecycle described below.
Owner cleanup cancels/releases its updater, and retired menu callbacks are inert.

Missing installed `nsh/assets/nsh-updater.json` contributes no action and creates
no worker, cache or network request. Invalid installed configuration contributes
an explicit unavailable action. The generic `DesktopApp` delegates to the same
controller and preserves its English labels and menu behavior. Applications may
provide translated `UpdateLabels` without copying the updater workflow.

### Semantic tag overrides are checked by the OCaml type checker

The `as_` argument now uses a content-appropriate polymorphic variant type for
each constructor: `text_tag`, `heading_tag`, `paragraph_tag`, `label_tag`,
`column_tag`, and `row_tag`. The accepted tags match the existing canonical
`element_tag_supported` predicate; wire values, defaults, child contracts, and
Web/mobile/native rendering behavior do not change. Generated typed-view
metadata now exposes the same per-kind domains. Raw wire input retains canonical
runtime validation, and `element_tag` remains the complete vocabulary.

For example, ``text ~as_:`Div []`` and ``row ~as_:`Ul []`` previously compiled and
failed when emitted. They now fail compilation. Use a layout constructor for a
block: ``column ~as_:`Div [text ~as_:`Em ~value:"Content" []]``. Existing valid
calls such as ``heading ~as_:`H2 []`` and ``row ~as_:`Li []`` are unchanged.

Helpers with an explicit broad annotation must use their constructor's subset:

```ocaml
(* Before: accepted tags that text could never emit. *)
let emphasis (tag : element_tag) = text ~as_:tag []

(* After: reject unsupported tags at the helper call site. *)
let emphasis (tag : text_tag) = text ~as_:tag []
```

An unannotated `let emphasis ?as_ children = text ?as_ children` infers the
restricted type automatically. This is a common API correction; it does not
claim that all Web style values have an NSH layout provider.


### Update installation requires an application lifecycle

Both public constructors now require an explicit
`Rc<dyn desktop_updates::UpdateLifecycle>`: migrate `UpdateActions::installed()`
to `UpdateActions::installed(lifecycle)` and `UpdateActions::new(updater)` to
`UpdateActions::new(updater, lifecycle)`. Calls omitting this policy fail to
compile. There is no public default or compatibility constructor that silently
restarts an embedded application. The generic `DesktopApp` alone supplies its
private standalone policy and retains its existing installation/restart flow.

`UpdateLifecycle::prepare()` returns an owned `InstallPreparation` future,
invoked only after the user's final installation confirmation. Its result is:

- `Err(description)`: show the existing translated error dialog; do not install
  or restart, and retain the verified download.
- `Ok(None)`: application cancellation, with no error dialog or installation;
  retain the verified download for another attempt.
- `Ok(Some(InstallLease::new(abort, relaunch)))`: the application has saved and
  quiesced its writers. Construct the lease under its live application owner.
  A proven pre-replacement failure invokes `abort` once while that owner lives.
  Success consumes `relaunch` once, without a generic restart fallback.

A preparation future must clean up any reservation it acquires if cancelled
before returning its lease. A lease dropped before installer dispatch invokes
its live owner's `abort`; after dispatch, cancellation cannot prove whether the
installer committed, so it leaves the application quiescent. A retired lease
owner cannot dispatch installation or relaunch. A committed installation's
relaunch error is shown through the existing error dialog, clears the consumed
download and never invokes `abort`. The app must not capture a drop guard that
implicitly resumes writers when committed callback captures are released.

For an application whose save/shared-worker/relaunch policy is not yet proven,
use an explicit fail-closed implementation with an application-translated reason:

```rust
use lui_nsh::desktop_updates::{InstallPreparation, UpdateActions, UpdateLifecycle};
use std::rc::Rc;

struct InstallationUnavailable(String);
impl UpdateLifecycle for InstallationUnavailable {
    fn prepare(&self) -> InstallPreparation {
        let description = self.0.clone();
        Box::pin(async move { Err(description) })
    }
}
// Construct inside the application's live owner, using its current translation.
fn mount_updates(translated_reason: String) -> UpdateActions {
    UpdateActions::installed(Rc::new(InstallationUnavailable(translated_reason)))
}
```

A real lease must preserve the application's credential/isolation mode, validated
startup arguments and environment, and shared-worker ownership policy. This API
adds no save protocol, daemon authority, event pump, installer bypass or restart
qualification. Logseq's actual configured installation remains explicitly blocked
until its application-wide save, daemon compatibility/exclusivity and safe
relaunch requirements are implemented and qualified.


### Uncertain updater installation errors retain quiescence

The installation lease releases application preparation only for errors that
prove filesystem replacement has not begun: `Verification`, `Stale`, `Cancelled`,
`Transport` (reading/verifying the local archive) and `Busy` (the worker queue
rejected dispatch). An `Installation` error does not establish rollback success:
the pinned NSH installer can report replacement failure after a rollback rename
also fails. `Stopped` is also ambiguous because a reply can be lost after the
worker accepted the request. These and unknown error categories therefore do not
invoke the lease's `abort` or `relaunch` callbacks. The existing error dialog
reports failure and the application remains quiescent; there is no standalone
restart fallback. Nonwritable-installation failures conservatively follow the
same rule because the existing error category does not distinguish that case.

For example, an application lease whose abort resumes editor writes now resumes
after archive verification failure, but does **not** resume after an installation
or worker-disconnection error. Applications must keep their preparation gate
held until an independently established recovery/restart policy resolves the
uncertain state. This change does not add filesystem recovery authority or prove
any installed package safe to restart.


### Empty optional NSH dialog labels no longer reserve layout gaps

An NSH `dialog` now creates its optional title (`text`) and `description` text
hosts only while their current values are nonempty. Previously, two empty native
text hosts still participated in the dialog panel's authored `gap`, adding two
unwanted spaces above child-only dialogs such as Logseq CmdK. No title or
description value is invented, and the dialog's accessibility bindings remain
live. Nonempty labels preserve their existing typography and spacing.

For example, `dialog ~gap:16 [search_input]` with no title/description now places
its authored body at the panel's normal content origin instead of reserving
32 points for empty headings. Updating `text`/`description` from absent to present
and back adds/removes only the optional label hosts; authored children retain
their native identities, drafts and editing focus. Applications that intend an
empty inset must author padding or an explicit spacer rather than empty labels.
This native layout correction does not change Logseq CmdK's intentional master
65vh results region, fixed width policy or blank-query empty-state behavior.



### Read-only native bounds diagnostics

NSH macOS hosts additionally advertise `native-bounds` in `host_native_ops`.
`native-bounds "kind:dialog"` resolves exactly one node through the existing
OCaml selector, then reads its renderer-owned AppKit view without pressing,
activating, laying out or changing it. A retired or replaced node fails; a
semantic node not yet represented by a native view returns `present: false`.
Other operating systems report this diagnostic as unsupported.

The response includes node/incarnation and `diagnostics`: actual converted
window-content bounds, viewport intersection, hidden/alpha ancestry and bounded
sibling order. Traversal, retained views and each sibling scan are capped at
8,192; ancestry is capped at 12 and truncation is explicit. It inspects no titles,
text, other applications or desktop coordinates. Existing semantic `find` and
Core layout measurement are unchanged.

For example, inspect `native-bounds "kind:input"` before capturing a newly opened
dialog. A semantic node can exist while a native slide is still outside the
viewport. These diagnostics do not certify painted pixels, finished animation,
hardware focus or master UX parity; screenshots still require visual review.

### Application-owned mutation admission for NSH Desktop

Embedded apps can provide `app::ApplicationMutations::new(check)` above `Desktop`
to refuse newly produced renderer input and semantic/native agent mutations
while the application saves or prepares an update. Construct it inside the live
application owner; `check` is synchronous and reads current application state.
The optional context creates no new worker, queue or polling loop. Without it,
generic Desktop behavior is unchanged.

For example, provide a guard whose closure returns an error while an app-owned
`preparing` signal is true, then release that signal only after the application's
correlated abort acknowledgement. Inputs accepted before preparation retain their
existing FIFO order. Agent operations `hello`, `tree`, `dump`, `find`, `prop`,
`screenshot` and `native-bounds` remain read-only; mutating requests are refused.
`native-press` also rechecks admission after its layout answer immediately before
native controller dispatch, together with retained node/native identity checks.
A retired guard owner refuses access before calling its predicate.

This is admission for application/model events and explicit native-agent actions,
not an inherited native `disabled` state. NSH `disabled` applies to its actual
host, so setting it on a root View would not freeze descendant or portal
controllers. Application-owned native menus outside the renderer must consult
the same preparation policy. A real update also requires the OCaml/worker fence,
completed save/drain, worker compatibility and safe relaunch; this context alone
does not establish whole-application quiescence or authorize installation.


### Native bounds follows mounted presentation identifiers

`native-bounds <selector>` resolves a canonical node first, then inspects its
mounted standard host's actual identifier, including an authored
`accessibility_identifier`. For example, `native-bounds
prop:accessibility-identifier=search-button` now finds that host instead of
assuming it is named `lui-<node>`. Incarnation checks remain enforced.

A later property update does not rename an existing NSH test identifier; the
query follows the mounted identifier. Extension factories independently choose
native identifiers, so this diagnostic explicitly rejects them rather than
claiming that their native roots correspond to `lui-<node>`. No mutation or
paint/readiness guarantee is added.

### Update admission preserves accepted native feedback

`ApplicationMutations` fences new user/agent mutations while allowing retained
virtual-window requests, visible ranges, scroll completions, image loads,
appearance notifications and file-picker results to finish in their existing
order. These events keep their incarnation/generation checks and queue bounds;
no completion is discarded merely because preparation started after its work
was accepted. Unknown extension events, focus/blur and dismissal remain guarded
input. Applications with their own OCaml admission fence must preserve the same
completion paths; for example, an already accepted animated scroll still emits
its one `on_scroll_completed` result during preparation.

### Read-only native heap diagnostics during update preparation

NSH application admission now permits the existing agent channel's `gc-stats`
operation while update preparation fences input. Applications may implement and
advertise `{"op":"gc-stats"}` alongside their other read-only agent queries;
unknown operations remain guarded as mutations. This adds no collection,
compaction, sampler timer or listener. Consumers must treat reported OCaml heap
capacity as part of process memory rather than adding it to RSS or footprint.

## NSH Link activation preserves navigation modifiers

NSH Links with an authored `on_press` now deliver `PressModifiers` through that
same callback, including Control=1, Shift=2 and Command/Super=4. Plain activation
has mask zero. `register_press` already admits both ordinary and modifier
events, so ordinary callback code continues to work. Match both variants when
inspecting the raw protocol event. The adapter consumes only native
`LinkEvent::PressDetail`; subscribing to its ordinary `Press` as well would
deliver duplicate navigation. Pointer and focused macOS/Linux keyboard modifiers
come from their actual activation; accessibility activation has no key modifiers.

An internal hash/path still requires an authored callback. LUI does not silently
open it with the system or suppress invalid navigation. Applications using a
document-level delegated route controller must explicitly register their Link
press callback and forward its retained node and modifiers to that controller.
External URL links without a callback keep native system navigation. Rust users
of the NSH fork must handle its additive `LinkEvent::PressDetail` enum variant.

## NSH split source-size layout motion

NSH split's existing `first_width`, `resize_duration` and standard easing now use the retained ResizablePanelGroup's scoped native layout animation when the
authored first width changes. `standard` maps to native ease-in-out and `linear`
to native linear timing. Omitted/zero duration remains immediate. Native divider
drags remain direct, and other property updates do not request layout animation.
NSH reduced motion makes source-size updates immediate.

Both native panels clip their retained children, including at zero width.
Applications must keep closing content mounted and avoid setting display-none
at the start of a reveal. Reopening retains editor and scroll owners; the native
platform owns interruption from its current presentation. No application timer
or intermediate width updates are required.

Ratio `value`, custom handle options and `resize_origin` remain rejected on NSH.
`emphasized` and `spring` easing remain rejected because NSH's public layout
transition does not express the existing LUI curves exactly. Web and the
maintained mobile backends keep their existing curves and options. Applications
that formerly omitted motion only for NSH can share the standard reveal token:

```ocaml
split ~first_width:(reactive width) ~resize_duration:300
  ~resize_easing:`standard left right
```

A model echo matching the most recent native split resize completion acknowledges
that native endpoint without requesting layout motion. This keeps pointer drag
and release direct even when applications persist the emitted width. The next
independent source-size change still uses the authored reveal timing. The adapter
remembers only the pending completion for this acknowledgement; ResizablePanel
continues to own the actual size and drag policy.


## Native provider presentation can be checked before application startup

`Lui_nsh::preflight::validate_styles` validates an encoded manifest of statically
captured nodes with the existing native style compiler and application theme
resolver. Each site carries `location`, `kind` and encoded `props`; the manifest
also supplies computed light/dark theme snapshots. For example, a build tool can
capture `font-size = "16px"` from its actual OCaml constructor, then call this
entry before launching a window. A provider grammar error includes that source
location and rejects the target build. No independent supported-value list is
introduced. Unresolved scoped theme variables remain explicitly deferred to
runtime; this entry does not qualify event routing or arbitrary dynamic values.


## Native menu attachment rejection identifies the retained trigger

The existing NSH rejection of changing a retained trigger's menu attachment mode
now includes bounded structural diagnostics: canonical node ID/kind/incarnation,
old and requested attachment presence, previous canonical declaration, native ref
binding state and the previous popup identity. No labels, graph names or menu
contents are logged. This distinguishes a real mounted mode change from stale
association or pre-mount lifetime bugs without relaxing the invariant. Matching
clients should recognize the diagnostic prefix rather than its full text.
