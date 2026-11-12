# Inspect and answer an owned macOS sheet

NSH macOS hosts add `native-dialog` and `native-dialog-answer` to `hello.host_native_ops`
when the existing LUI agent is enabled. No extra listener, development host, JavaScript VM or
installer startup flag is needed. Other native platforms do not advertise these operations and
return an explicit unsupported error. GTK and Windows NSH alerts are not AppKit-style native
sheet windows; this capability does not claim to automate their dialogs.

An inspection needs exactly one canonical **owner anchor** in the application's retained tree.
It resolves through the existing selector interpreter, captures that node's incarnation and
actually mounted native identifier, and then finds its exact NSView/window in this process.
The anchor may be disabled while its modal is open: inspection does not activate that anchor.
A retired, ambiguous, detached, hidden or replaced owner is refused. Only the sheet attached to
that exact window is inspected, without choosing a main/key/largest window or inspecting another
process. A different owned window's sheet is not a substitute.

```sh
node tooling/lui_agent.mjs --tcp 127.0.0.1:49417 --artifact /ABS/INSTALLED/ARTIFACT --json \
  'native-dialog "prop:accessibility-identifier=settings-check-for-updates"'
```

A successful reply contains `node`, `incarnation` and `dialog`. `dialog:null` means that window
currently has no attached sheet. Otherwise it contains a fresh `token`, `kind:"appkit-sheet"`,
window/sheet numbers, visible static `texts`, and native `buttons` with `label`, `enabled` and
`hidden`. The numbers are diagnostics, not reusable handles. Use the returned token and the exact
translated button label from the inspected sheet:

```sh
node tooling/lui_agent.mjs --tcp 127.0.0.1:49417 --artifact /ABS/INSTALLED/ARTIFACT --json \
  'native-dialog-answer "TOKEN_FROM_INSPECTION" "Download"'
```

JSON clients use `{"op":"native-dialog","selector":"..."}` and then
`{"op":"native-dialog-answer","token":"...","button":"Download"}`. Unknown fields,
empty/control-character strings, selectors/buttons over 1024 bytes and tokens over 64 bytes are
rejected. Every inspection invalidates the previous token, including an inspection that finds no
sheet. Keep one current token; do not cache it across another inspection, dialog replacement or
application restart.

One agent-owned lease retains the exact native owner, window, sheet and bounded contents using
`dispatch2::MainThreadBound`. There is no dialog registry or polling timer. Scans are bounded to
128 own windows, 8192 owner-tree views, 512 sheet views, 32 buttons, 64 static texts, 4096 bytes
per static text and 16 KiB total static text. An exceeded limit fails rather than returning a
partial identity witness. Editable text fields are not read. A new UUID distinguishes each lease.
The lease is released when replaced, consumed or its application pump is disposed.

Before answering, the engine rechecks its retained owner/incarnation and the existing
`ApplicationMutations` fence after the commit barrier and immediately before main-queue dispatch.
The Rc-owned admission callback stays on the engine thread. On AppKit's main queue, one callback
then rechecks the token, exact owner-window and sheet-parent/attachment, live content values and
retained view identities, and the unique visible enabled answer button. It consumes the lease
before `NSButton.performClick(None)`. A stale/duplicate answer, changed content, disabled button,
ambiguous label, retired owner or different sheet fails without a click. Existing backend-failure
and agent queue guards continue to apply; this operation does not bypass update preparation.

`activation:"native-controller",dispatched:true` acknowledges that native controller invocation,
not a physical mouse click, OS focus, completed download, installed update or successful relaunch.
It does not synthesize an OCaml event, dismiss a dialog by fabricated return code, activate an
application, make a window key, query the desktop or change display/lock state. The normal AppKit
sheet completion and NSH event path perform the real application action.

## Qualification

The source-only actual AppKit probe creates two private offscreen windows and real NSAlert
sheets, without using a Headless dialog surrogate:

```sh
cargo run --release --manifest-path platform/nsh/Cargo.toml --example native_dialog_probe
```

It checks real completion plus stale/reused tokens, changed/replaced sheets, disabled and
ambiguous buttons, retired native owners and wrong/ambiguous own-window anchors. Ordinary engine
unit-test source separately checks canonical incarnation retirement/replacement and admission,
including a disabled anchor. Neither source by itself qualifies an installed application update.
The qualification owner must execute them, then run the real standalone N1 Settings → available
update → Download → ready update → Install flow, verify N1/worker exit, and verify the installed N2
relaunch and preserved application data. Record the artifact/source identities and actual results;
do not replace that gate with Headless dialog answers, startup installation switches or fabricated
installer acknowledgements.

### Executed macOS qualification (2026-11-13)

At `e4ec2f3e` plus the two required Button text properties in the canonical
owner regression, the complete locked release library suite passed 292 tests,
with no failures or ignored tests. Strict release all-target Clippy and the
six CLI client tests passed. The owner fixture uses an ordinary valid Button;
the required-text contract was not weakened to admit the fixture.

The actual offscreen AppKit probe also passed, reporting normal sheet
completion and rejection of stale/reused tokens, changed/replaced sheets,
disabled/ambiguous buttons, retired owners and wrong/ambiguous windows. It
reported `activation:"native-controller"` and `hardwareInput:false`, as intended.
This proves the owned native controller seam, not an installed Logseq upgrade,
physical input, Windows/Linux dialogs or accessibility-client behavior.

Evidence logs and SHA-256 digests:

| Evidence | Log | SHA-256 |
| --- | --- | --- |
| Complete release library suite | `/tmp/lui-native-dialog-full-release-final.log` | `8ba4aeeb3eee48b9931fd2568f69977a3aa3e2c0676bb276ae3ba44080870257` |
| Strict release all-target Clippy | `/tmp/lui-native-dialog-final-clippy.log` | `4c786dd4d2a6a4de193132ce14d8ded4dc66de7c5638fbc761b814edad7dbc36` |
| CLI client regressions | `/tmp/lui-native-dialog-final-cli.log` | `0f953541d78634ea675cc92abc1ff2ffde9b22e3419f1bcbe8c8614b78637ecd` |
| Actual AppKit sheet probe | `/tmp/lui-native-dialog-real-appkit-probe.log` | `49622450854606f4c5a98fa46430bf45e9526ef0cc1f683c06c111901027d9c2` |
