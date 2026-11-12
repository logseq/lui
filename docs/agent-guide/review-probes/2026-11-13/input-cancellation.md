# Opt-in input cancellation qualification

Date: 2026-11-13

Source checkpoint: `e8e51daaa202c75307831a082d105f6b918688e5`.
NSH remains pinned to `adc186db7213f3ccd1eacaa836cc721e9779fd14`.
This report covers input cancellation, not completion of the desktop migration.
The public contract and migration examples are in `docs/api-migrations.md`.

## Contract and ownership

The five text-entry constructors accept optional `on_dismiss`. They reuse the
existing Dismiss event and append the Boolean `dismiss-enabled` property without
renumbering existing properties or events. The absent default remains false.
Disabled inputs and unfinished composition cannot cancel. Application code
continues to own the draft and decides what cancellation does to it.

Cancellation is armed before application dispatch, so synchronous blur cannot
also save. A canceled interval rejects duplicate cancellation and late submit;
genuine editing or fresh focus starts another interval. Controlled source
patches and handler removal do not revive the canceled draft. Finishing native
composition during blur does not count as beginning another composition.

NSH keeps the existing native Input, renderer incarnation/admission checks and
one change listener. Inputs without authored policy allocate no extra policy
state. Native key callbacks expose only a key string: modifier/repeat metadata
must not be invented. The segmented NSH TimeField has no dismissal projection;
its explicit refusal remains a separate actual-application preflight test.

## Executed checks

The commands below were serialized. Later commits after the indicated source
checkpoints changed other backends, tests or documentation, not the respective
tested implementation.

| Check | Result | Evidence |
| --- | --- | --- |
| `make test`, canonical constructor/schema and OCaml checks | Passed; 44 tooling tests, 259 core cases and five wire cases, with cached unchanged targets | `/tmp/lui-input-dismiss-core-tests-rerun.log` |
| `dune build @all` | Passed | `/tmp/lui-input-dismiss-current-all.log` |
| NSH `cargo test --release --locked --lib` at `1c42d6ab` | 283 passed, none skipped | `/tmp/lui-input-dismiss-native-ack-rust-tests.log` |
| NSH release Clippy, all targets, `-D warnings` | Passed | `/tmp/lui-input-dismiss-current-clippy.log` |
| `dune build @web`, followed by `npm --prefix platform/web run check` | CSS/assets built; 183 tests passed | `/tmp/lui-input-dismiss-web-built-check.log` |
| Apple `swift test --package-path platform/apple --filter LUIInputDismissTests` | Eight passed | `/tmp/lui-input-dismiss-apple-native-tests.log` |
| iOS `xcodebuild -scheme LUI-Package -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/lui-input-dismiss-ios-build build-for-testing` | Test build succeeded; no simulator booted | `/tmp/lui-input-dismiss-ios-build.log` |
| Android `./gradlew :lui:testDebugUnitTest --no-daemon --max-workers=2 --console=plain` | 87 passed, no failures/errors/skips | `/tmp/lui-input-dismiss-android-complete-tests.log` and JUnit XML |

The exhaustive wire fixture adds only the new property's transport case: 431
operations instead of 430, with no removed or changed earlier operations. Wire
transport tests deliberately include scalar values outside individual property
domains; domain validation has separate Boolean/kind/atomic-rejection tests.

## Native evidence boundaries

NSH Headless does not synthesize the native Input Escape callback. Its retained
input cases send the source-verified public KeyPress event at the actual native
input, then wait for a visible acknowledgement from the real renderer. The
acknowledgement leaves the edited input's text, focus and identity untouched.
Actual edits, blur, controlled updates and delayed SubmitEditing are checked
through the public engine and Headless interfaces. This is event-boundary
evidence, not physical keyboard evidence.

The AppKit probe uses a real field editor, marked text, exact first-responder
ownership and local monitor lifetime. Its off-screen window is ordered behind
other windows without becoming key. It does not certify hardware delivery to
every SwiftUI text kind or the complete Logseq application.

Android uses the real Compose/Paparazzi focus, selection and input connection
paths. Each alias owns a separate native frame session. A range selection uses
the public traversal mode, preserving range/controlled-echo assertions without
requesting the separate unavailable smart-classification service. Control-key
events carry zero Unicode through their public Android methods; physical device
keyboard/IME delivery is not claimed. The stale-input-connection case transfers
focus between two ordinary inputs and requires that the canceled primary cannot
submit or reacquire focus. Separate lifecycle cases exercise LUI's late-submit
guard directly.

Clearing focus alone was an invalid test assumption: Android may immediately
restore the only focusable input. Similarly, Headless batch-silence completion
is not acknowledgement of a callback which produces no native batch. Neither
observation justified changing production behavior to accommodate the fixture.

## Remaining gates

- Execute the final Logseq release property-input scenarios with actual native
  keyboard delivery and persisted worker state.
- Qualify iOS hardware Escape, including the system `.searchable` field; the
  successful test build is not runtime evidence.
- Run the new revision's Linux/Windows/macOS CI and native interaction gates.
- Preserve the migration's independent editor/IME, accessibility, performance,
  packaging, signing and actual whole-application update requirements.
