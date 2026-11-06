# Android native Drive host (explicit test opt-in)

The optional `:drive` Android library runs under real Android Instrumentation,
not inside the OCaml reducer. It requires API 30+, a debuggable target, a
registered `DriveTarget`, and an explicit `-e drive true` launch. It binds only
`127.0.0.1:49377` (override with `-e port`). There is no manifest receiver,
application initializer, release dependency, or automatic listener startup.

## Hook up a debug host

Add `debugImplementation(project(":drive"))` to the Android app. Keep the
library, its INTERNET permission, IME service and instrumentation declaration
out of the release variant. The instrumented test variant must have minSdk 30+.
In debug source, register after `setContent` and keep the handle until Activity
destruction. In release source, use a no-op hook. For example:

```kotlin
// Debug source only, and only for an explicitly enabled test Activity.
val drive = if (intent.getBooleanExtra("luiDrive", false)) {
    DriveTarget.attach(this, backend)
} else null
// In onDestroy, on the UI thread:
drive?.close()
```

Declare a self-instrumenting runner in the app's **debug** manifest, replacing
the target package:

```xml
<instrumentation android:name="dev.lui.drive.DriveInstrumentation"
    android:targetPackage="your.debug.package" />
```

The runner starts the supplied Activity with `luiDrive=true` in a new cleared
task. Use an isolated debug/test app, not a production task. The SDK never
enables or selects an IME, changes accessibility settings, or grants itself
permissions through shell commands.

## Build and run the sample

From `platform/android`, with an Android SDK and JDK 17+:

```sh
./gradlew :drive-sample:assembleDebug
adb install -r drive-sample/build/outputs/apk/debug/drive-sample-debug.apk
```

On an isolated, unlocked API 30+ emulator/test device only, use the explicit
sample launcher. It saves the currently selected/enabled IME state and restores
it on normal completion, errors and shell signals. Do not terminate it with
SIGKILL; if interrupted outside normal cleanup, restore the printed original
IME manually with `adb shell ime set ORIGINAL_COMPONENT`.

```sh
DRIVE_BIN=/path/to/drive ./drive-sample/run-drive.sh --test-device scenario.drive
```

The Drive binary needs loopback TCP support (`--tcp 127.0.0.1:49377`). The
equivalent manual input-free launch (without IME setup, so no `type` capability):

```sh
adb forward tcp:49377 tcp:49377
adb shell am instrument -w -e drive true -e port 49377 \
  -e activity dev.lui.drive.sample/.MainActivity \
  dev.lui.drive.sample/dev.lui.drive.DriveInstrumentation
# In another terminal:
drive --tcp 127.0.0.1:49377 --input native scenario.drive
# Afterwards:
adb forward --remove tcp:49377
```

For text, explicitly enable/select
`dev.lui.drive.sample/dev.lui.drive.DriveInputMethod` on the test device, saving
the previous `default_input_method` first and restoring it afterwards. Prefer
the launcher so cleanup is not forgotten. Missing selection is rejected before
the target is tapped. `type` is omitted from hello unless this test IME is
selected. No clipboard, accessibility set-text, property assignment or LUI
event injection is used. Empty text replaces the full value with an empty
string; Unicode is committed through the real editor `InputConnection`.

## Protocol and behavior

* Native protocol v1 is unchanged. Initial writes are hello, full frames, then
  authoritative ops (the readiness marker). Updates remove previously
  published IDs, recreate all current nodes/properties/links, and replace the
  complete frame table. A single worker serializes actions and the ordered
  writer publishes fresh ops and frames before each correlated result,
  including screenshot and rejected actions. Changes between actions are
  published while reading the connection.
* Coordinates/deltas are logical viewport units (Android dp), origin at the
  content view's top-left. Geometry uses clipped actual Compose bounds. The
  adapter converts dp plus the current content view screen offset to physical
  screen coordinates for OS input, including status bar/inset movement and
  resized IME layouts. PNG captures the content viewport in physical pixels.
* `UiAutomation.injectInputEvent` routes MotionEvent/KeyEvent through Android's
  input dispatcher and the real Window/View/Compose input path. Clicks, double
  clicks, long clicks, coordinate taps and drags never invoke semantics actions.
  Positive scroll dx/dy means content right/down, using an opposite finger swipe.
  Deltas must fit in the target's visible bounds; use multiple smaller swipes.
* The read-only accessibility hierarchy verifies native window layering,
  visibility, enabled state and tagged hit ancestry. Model/ancestor visibility,
  enabled state, clipped bounds and retained-node incarnation are checked too.
  Missing geometry, untagged occluders, different windows, destroyed targets,
  stale/reused IDs and unknown actions fail explicitly. There is no auto-scroll
  or semantic fallback. Extensions/modals without measured/tagged nodes are not
  selector-input targets; offscreen/unmaterialized virtual rows must be brought
  into view by native scrolling first.
* `type` requires native editable focus and the selected test IME, complete
  `getExtractedText`, `setSelection`, `beginBatchEdit` and `commitText` support.
  Read-only, partial-extraction and unsupported input connections are rejected.
  InputConnection queries run off the editor UI looper to avoid deadlock.
* Keys: letters, digits, Enter, Tab, Escape, Backspace, Delete, Space,
  ArrowLeft/Right/Up/Down, Home, End, PageUp/Down. Combine with `ctrl`/`mod`
  (Control on Android), `shift`, `alt`, or `meta`/`cmd`. Unknown keys/modifiers
  fail; use `type` for arbitrary Unicode. Physical key-up and gesture cancel
  cleanup run even after injection failure or timeout.
* `settle` means at least 100ms of retained-model, measured-layout, host draw
  and accessibility-event quiet, bounded by a 3s action deadline. It is not
  application-task/network idle and cannot prove completion of every
  render-thread/paint-only animation. Continuous redraws fail the deadline;
  use Drive `wait` for business effects.
* One connection is accepted per instrumentation launch. Accept/read idle
  deadline is 120s; action lines are limited to 1 MiB; writes and UI-thread
  waits are bounded to 1s. Bad envelopes without a correlatable request close
  the connection. A timeout returns an error when possible, then closes rather
  than retrying possibly applied input. EOF closes inspection and the Activity.
  Timed-out, not-yet-started UI callbacks are removed; already running native
  work cannot be rolled back.

## Evidence and limitations

Compile/lint and the pure v1 validation contract test are not device input
evidence. Run real-device/emulator native tests before relying on a downstream
app. Accessibility inspection cannot establish the hit behavior of arbitrary
custom, accessibility-invisible input interceptors; those need application-
specific instrumentation. Multi-display, split-screen, system UI automation,
external keyboard/IME behavior, clipboard, OS drag-and-drop and semantic-only
Drive actions are not supported. Pointer drag is a touch gesture, not a promise
of application drag-and-drop semantics. Secure-window screenshots are rejected.
The adapter never claims input changed product state: assert resulting state
with Drive expectations.
