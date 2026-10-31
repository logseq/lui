# Native presentation regression checks

Run these on a booted iOS simulator on an Apple silicon Mac with Xcode:

```sh
python3 platform/apple/Tests/RuntimeChecks/run-ios-check.py file-preview --simulator booted
python3 platform/apple/Tests/RuntimeChecks/run-ios-check.py drawer-first-reveal --simulator booted
python3 platform/apple/Tests/RuntimeChecks/run-ios-check.py drawer-rapid-swipes --simulator booted
python3 platform/apple/Tests/RuntimeChecks/run-ios-check.py bounded-virtual-rows --simulator booted
```

The runner builds the Release static backend, launches an isolated app host, and
removes it after completion. It invokes neither XCTest nor `swift test`.

Completion requires a zero launch return code and a final
`NATIVE_PRESENTATION_CHECK_COMPLETE` entry in the host's atomically written
checkpoint log. Each temporary host embeds a unique checkpoint filename, so an
earlier run cannot supply its result. Missing logs and failed or incomplete final
entries fail the check even if the console contains a completion message.
`simctl` console output can omit the tail of a successfully completed check; it
remains diagnostic rather than the completion oracle. Failure artifacts preserve
the current run's checkpoints. The original 30-second launch hang guard, native
assertions, and failure exits are unchanged; there is no retry or grace period.

`file-preview` checks that QuickLook is absent from the loaded images before any
preview request and after mounting an idle root. It creates a PDF, verifies native
preview presentation, removes it during presentation, reopens it, and checks that
native dismissal emits exactly one wire event without immediately reopening.

`drawer-first-reveal` checks compact-width drawers that start closed and open.
An unopened panel must not mount; its first reveal must use the latest wire data;
closing and reopening must preserve the panel's SwiftUI state identity. The
regular-width NavigationSplitView path continues to mount its sidebar normally.

`drawer-rapid-swipes` delivers pan events to a mounted drawer and checks gesture
admission during opening and closing animations. It covers repeated reversals,
cancelled gestures, delayed controlled-state acknowledgements, and stale animation
completions. Descendant controls must remain locked throughout each active drag
and recover after the final transition.

`bounded-virtual-rows` checks real UIKit adjusted-inset geometry and a SwiftUI
host with 100,000 logical rows. It focuses a native text field, starts marked
text, reorders its stable key from index 2 to 99,999, scrolls to the actual bottom
and back to the top, and clears. Native editor identity and composition must
survive while row models stay bounded; active interaction pins remain separate
from the requested viewport. The application driver answers real maintenance
events through the public backend; the separate OCaml integration test exercises
the shared native runtime boundary.
