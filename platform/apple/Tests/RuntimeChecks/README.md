# Native presentation regression checks

Run these on a booted iOS simulator on an Apple silicon Mac with Xcode:

```sh
python3 platform/apple/Tests/RuntimeChecks/run-ios-check.py file-preview --simulator booted
python3 platform/apple/Tests/RuntimeChecks/run-ios-check.py drawer-first-reveal --simulator booted
python3 platform/apple/Tests/RuntimeChecks/run-ios-check.py bounded-virtual-rows --simulator booted
```

The runner builds the Release static backend, launches an isolated app host, and
removes it after completion. It invokes neither XCTest nor `swift test`.

`file-preview` checks that QuickLook is absent from the loaded images before any
preview request and after mounting an idle root. It creates a PDF, verifies native
preview presentation, removes it during presentation, reopens it, and checks that
native dismissal emits exactly one wire event without immediately reopening.

`drawer-first-reveal` checks compact-width drawers that start closed and open.
An unopened panel must not mount; its first reveal must use the latest wire data;
closing and reopening must preserve the panel's SwiftUI state identity. The
regular-width NavigationSplitView path continues to mount its sidebar normally.

`bounded-virtual-rows` checks real UIKit adjusted-inset geometry and a SwiftUI
host with 100,000 logical rows. It focuses a native text field, starts marked
text, reorders its stable key from index 2 to 99,999, scrolls to the actual bottom
and back to the top, and clears. Native editor identity and composition must
survive while row models stay bounded; active interaction pins remain separate
from the requested viewport. The application driver answers real maintenance
events through the public backend; the separate OCaml integration test exercises
the shared native runtime boundary.
