# Native keyed ancestor reorder preserves desktop editor focus

Date: 2026-11-11 (UTC)

## Reproduction

The real LUI navigation/Split OCaml fixture runs in the pinned NSH AppKit
development host at `d21573c25984e9603bf878ae8bb73c1e23408936`.

The driver types into each retained Split editor, then presses a hardware `z`
without re-focusing. That control updates the First model, proving the driver
can deliver a character to the focused native editor. It arms a model edit to
swap two keyed panes, types `~` into First, then presses hardware `x` without
calling `app.type` or focusing again. The model receives `~` and reorders its
children. The following `x` never reaches either input, including after a
five-second asynchronous worker wait.

The native trace publishes exactly one structural operation at that edit:
`Insert { parent: 93, child: 211, before: Some(95) }`. The moved pane contains
native Input 283. Both canonical pane appearance counts remain one, and both
native editor drafts survive. There is no Delete/Create of the editor. The
failure is native focus continuity, not canonical keyed identity or draft
retention. The equivalent Headless reorder/focus regression passes.

Run the real fixture after building it without Dune edits:

```sh
python3 platform/nsh/tests/fixtures/build_virtual.py --fixture navigation
LUI_OCAML_LIBRARY="$PWD/_build/nsh/navigation-qualification/liblui_navigation.dylib" \
  platform/nsh/.nsh/toolchain/nsh test \
  platform/nsh/tests/fixtures/navigation_native.test.ts --target macos --trace
```

The preserved RED log is `/tmp/lui-nsh-split-focus-reorder-red.log`, SHA-256
`333e0e8fdc42513d9403719d021ec347886ee5ea9f41b2d7f30ccc2b0ee15803`.
The subsequent control-augmented run in `/tmp/lui-nsh-navigation-native.log`
also records hardware `z` succeeding before the move and `x` failing afterward.
Logs/build artifacts are ignored local evidence, not committed dependencies.

## Source finding and scope

At d215, macOS `mount.rs` unconditionally calls `child.unparent()` for every
Insert on an attached view. `NshView::unparent` calls AppKit
`removeFromSuperview()`. The same-parent move consequently detaches the focused
editor's ancestor from the window before inserting it again. Input and waiting
subtree counts are removed and re-added as if this were a cross-parent attach.

The published repair preserves the existing insertion API and true cross-parent
path. macOS checks the actual physical container before unparenting and avoids
incrementing the input/waiting subtree counts twice for an in-place move. Linux
checks the actual GTK parent before detaching. No public app-specific NSH API,
focus replay, alternate controller or adapter remount was introduced. Windows
uses retained Rc children and a windowless RichEdit service; no Windows source
change was justified by this finding.

The production fixes are commits `ba0106f` and `fabe499` on `fork/logseq`.
Commit `bfa15d0c843c0d6f5bf3a2a230e8ca56b876b61c` additionally fixes a Linux
test-only Clippy diagnostic. LUI pins that immutable fork revision.

## RED/GREEN qualification

The same macOS native regression was run with the baseline mount implementation
restored temporarily (RED) and then with the repair restored (GREEN). Eight
cases cover plain, clip/shadow, blur and scroll containers, each with and without
a foreign native sibling. The checks assert the same NSViews, field editor,
first responder, selection/caret continuity and native sibling ordering.

```sh
NSH_KEYED_FOCUS_CHECK_ONLY=1 cargo test --locked \
  -p nsh-platform-macos --test native -- --ignored
NSH_MOUNT_CHECK_ONLY=1 cargo test --locked \
  -p nsh-platform-macos --test native -- --ignored
```

The full NSH workspace at `fabe499` passed 5,300 tests, with 63 existing ignored
tests, and strict all-target workspace Clippy passed on macOS. Its compatibility
CI also passed: https://github.com/logseq/nsh/actions/runs/43064553271.
These results do not establish execution of Linux-only GTK code. The first Linux
CI stopped at a test-only Clippy diagnostic; the corrected revision requires its
own successful Linux run before this platform is qualified.

The real LUI native fixture also passed all navigation, retained editor and
focused keyed-reorder assertions (37.5 seconds). That probe used LUI source at
`946436f1` and the same macOS repair through ignored local path dependencies;
it is historical integration evidence, not qualification of later component
changes or the final pinned/package build. The public test now has a 60-second
whole-test budget while preserving the individual assertions and timeouts.

| Local evidence log | SHA-256 |
| --- | --- |
| `/tmp/nsh-keyed-native-focus-red.log` | `bd5afe796a554244fe485f092000586f6d630b915b02fd1ecf54886afb81f792` |
| `/tmp/nsh-keyed-native-focus-green.log` | `7bc1d56e183c8ed0cb8d497c4e0e2470110f1897af298edc2f0a83d4491449e7` |
| `/tmp/nsh-keyed-native-mount-tests.log` | `ce5fd1f633e17e99672debcffdfe7b2976c9ebd291530556576fb455601721ce` |
| `/tmp/nsh-native-focus-workspace-tests.log` | `18edc10a54783eb2e51fd3c6cb003be4b24fd810eb70de362dd60d520d451228` |
| `/tmp/nsh-native-focus-clippy.log` | `21dcd6b5971cfe0dd2253465a52823da34cf50a616c54a91e80f40ecc432e6b9` |
| `/tmp/lui-nsh-native-focus-path-probe.log` | `6efd2c5c86aa19ac47a91ae31917eeb43380d32cf8b3d212629bd5b2e2db4f5c` |

Logs and build artifacts remain ignored local evidence, not committed dependency
trees. Final LUI runtime/package qualification and the remaining migration gates
stay open.

## Pinned LUI native panel follow-up

The public `navigation_native.test.ts` subsequently passed against the exact
pinned `bfa15d0` dependency and its installed CLI, with LUI production source at
`49f23d4e`, with the pending pinned manifest/generated-contract refresh and
updated navigation fixture in this batch. The OCaml fixture uses
native panels, absolute point completion events and no legacy ratio/refusal
controller. Its complete native flow passed in 36.7 seconds: Breadcrumb and
Pagination keyboard navigation, live Step/Timeline state, independent editor
drafts, local resize retention without model echo, programmatic pixel sizing,
and hardware input after focused keyed pane reorder. Both appearance counts
remain one. All six light/dark navigation/activity/panel screenshots were
inspected for typography, spacing, token contrast, selected/disabled states,
control corners and pane geometry. Hover/pressed motion, screen-reader output,
IME and other operating systems are not qualified by these screenshots.

Log `/tmp/lui-nsh-pinned-native-panels-navigation.log` SHA-256:
`8983941851a97b4980f3e342d17e679986c544358e97bc23bf0d6bf49e2faeb9`.
The CLI receipt names revision `bfa15d0c843c0d6f5bf3a2a230e8ca56b876b61c`
and SHA-256 `5f02970c290287c0d469f25905e20d76478bbe74df6a406967e565bca9e4d95f`.

## Linux native result at the exact pin

Linux run [43067839700](https://github.com/logseq/nsh/actions/runs/43067839700)
completed successfully at `bfa15d0c843c0d6f5bf3a2a230e8ca56b876b61c`.
The `check` job (130687600266) passed strict Clippy with/without WebKitGTK,
optional-feature checks, both test configurations, AT-SPI activation/input and
GTK-window examples. Its logs explicitly report these three GTK regressions as
passed in both relevant test configurations:

- `mount::tests::same_parent_insert_keeps_a_focused_editor_rooted`
- `mount::tests::same_parent_insert_keeps_a_focused_descendant_rooted`
- `mount::tests::cross_parent_insert_still_detaches_from_the_old_parent`

The GPUI gallery job (130687599801) also passed. This closes the fork's pending
Linux execution noted above. It does not qualify later LUI FileImage/MenuItem
source, the actual Logseq app, Windows execution or distribution signing.
