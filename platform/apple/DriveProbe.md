# DEBUG iOS Drive snapshot probe

The Apple CI compile gate covers this API and probe, but the Drive adapter's
Simulator/device input is not yet validated. They are excluded by
`#if DEBUG && os(iOS)` from Release, macOS, and other builds. No app starts a
listener automatically.

## Public API

```swift
@MainActor
public func LUIAppleBackend.debugDriveSnapshot() throws -> Data

@MainActor
public static func LUIDriveSnapshotProbe.startIfEnabled(
    backend: LUIAppleBackend, window: UIWindow,
    environment: [String: String] = ProcessInfo.processInfo.environment
) throws -> LUIDriveSnapshotProbe?

// On the retained probe:
public private(set) var failure: String?
public func stop()
```

These are additive DEBUG iOS APIs; production APIs, wire events, and input
defaults do not change. Downstream callers must gate references with `#if DEBUG`
(and `os(iOS)` if sharing source with macOS). Do not expose backend models,
retained tree objects, or mutable frame tables to the UI-test process.

`debugDriveSnapshot()` returns an immutable JSON data snapshot of the current
retained standard/extension nodes, properties (existing scalar wire types),
child order, roots, generation, commit sequence/pending-commit state, collected
frames, and effective accessibility identifiers. Standard identifiers follow
the renderer's explicit identifier then accessibility-label fallback. The
metadata distinguishes explicit identifiers; Drive target actions require those,
not fallback labels. Extension metadata reflects declared identifier properties;
the XCTest runner must validate that the actual native extension control exposes
that identifier uniquely. Removed nodes are excluded from frame output.

The data API itself is read-only and does not force pending commits, enable
geometry probes, change callbacks, or dispatch input/events. The standalone
probe temporarily enables frame reporting and resumes collection, leaves
`onFramesReport` untouched, and restores the saved flags on `stop()` or isolated
deinitialization. Only one probe may be active per backend. Retain the probe for
the desired debug session and stop it during host teardown; do not create it as
an unretained temporary.

## Navigation demo host hookup (no view edits)

In `examples/navigation/ios-swiftui/Sources/NavigationDemo/NavigationDemo.swift`,
add `import UIKit`, and put this stored property in `NavigationHost`:

```swift
#if DEBUG
private var driveProbe: LUIDriveSnapshotProbe?
#endif
```

At the end of `NavigationHost.start()`, after `startOCaml(...)` succeeds, add:

```swift
#if DEBUG
if ProcessInfo.processInfo.environment["LUI_DRIVE_PROBE"] == "1" {
    let windows = UIApplication.shared.connectedScenes
        .compactMap { $0 as? UIWindowScene }
        .filter { $0.activationState == .foregroundActive }
        .flatMap(\.windows)
        .filter(\.isKeyWindow)
    guard windows.count == 1, let window = windows.first else {
        preconditionFailure("Drive requires one foreground key window")
    }
    do {
        driveProbe = try LUIDriveSnapshotProbe.startIfEnabled(backend: backend, window: window)
    } catch {
        preconditionFailure("Drive probe failed: \(error)")
    }
}
#endif
```

This is a downstream integration snippet, **not an already-applied demo change**.
The app must already have its foreground key window when `start()` runs; hosts
with a different lifecycle should call the factory at their window-ready hook.
If the host has explicit shutdown, call `driveProbe?.stop()` there. The existing
LUI geometry probes report SwiftUI scene-global/window-local logical points;
use one fixed-orientation window. Hoisted toolbar nodes intentionally do not
report SwiftUI geometry; the native XCTest adapter obtains their actual frames.
No root view or OCaml `Lui_elements` view change is needed.

Enable only through the UI test's app launch environment:

```swift
app.launchEnvironment["LUI_DRIVE_PROBE"] = "1"
app.launchEnvironment["LUI_DRIVE_PROBE_PORT"] = "49378" // optional default
```

Do not add these to production launch defaults. Ports must be `1024...65535`.
The factory returns `nil` without `LUI_DRIVE_PROBE=1`. Network listener failures
set `failure` and stop/restore the probe; inspect this in the integrating host's
debug diagnostics. A missing/hidden/non-key window rejects the snapshot request.

## Private probe transport

The probe binds Foundation Network TCP strictly to IPv4 `127.0.0.1`, accepts a
single loopback peer, and implements only a read request (not Drive actions):

```json
{"probe":"snapshot","version":1,"request":1}
```

It responds with the same probe/version/request and a `snapshot` object that
also includes `viewport:[0,0,width,height]` and
`coordinateSpace:"window-top-left-points"`. The runner maps native screen frames
through the matching XCTest window before publishing Drive frame snapshots.
No physical screenshot scaling is applied.

Requests start at 1 and increase by exactly 1 on each connection. Non-snapshot,
malformed/version-mismatched, duplicate/out-of-order, pipelined requests and
non-loopback peers are rejected by closing that connection. Input is limited to
4096 bytes; a partial request/response has a 5s absolute deadline that is not
extended by each received chunk. An otherwise idle connection is allowed.

The probe is not an authenticated service: another local process can read the
opt-in debug app's retained content. Use isolated development environments. It
has no injection command, shell launch, private HID/touch API, event dispatch,
or native input responsibility. The separate Drive XCTest UI-testing target
owns all input and must never be linked into the production application.

## Migration-note text for the integration owner

Add an entry to the repository-level API migrations document when integrating:

> Apple DEBUG iOS builds add a read-only `debugDriveSnapshot()` data API and an
> explicit `LUIDriveSnapshotProbe.startIfEnabled(backend:window:environment:)`
> lifecycle. Retain the probe at a single-window-ready host hook; gate references
> with `#if DEBUG`. Without `LUI_DRIVE_PROBE=1` no listener is opened; Release
> builds contain no probe/API. The loopback-only probe temporarily enables frame
> collection and restores settings without replacing callbacks. It exposes LUI
> wire snapshots and expected/effective accessibility identifiers, not input.
> Native Drive input belongs exclusively to a separate XCTest UI-testing target
> with explicit stable identifiers; there is no semantic or coordinate fallback
> for target actions. Existing production behavior and event contracts are
> unchanged. Xcode compilation/Simulator verification remain required.
