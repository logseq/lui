# Actual Logseq parent-viewport integration checkpoint

## Revisions and scope

This checkpoint uses Logseq `78d0759ecda21fae0b79e9ab44ec502a00bf12a2`,
LUI `c754e0c57c61e829db90794d8bbeb58ef2d85e8f` and NSH
`ea23ae9cd5f56426145ea225f1a220e1eca0d3a2`. The NSH pin includes upstream
main `f60a4791b9b5a26ede288a80792c7b8c542e138d` and the authorized repairs.
These are integration results, not final migration acceptance.

Actual Logseq `Virt_list` and `Lazy_children` now use canonical sparse
`virtual_rows` on NSH, borrowing the existing outer scroll through the typed
`Parent` viewport. Other native hosts retain their maintained paths. Parent
ownership is validated before native publication, and scroll completion/drag
events belong to the actual nearest compatible scroll owner. Ordinary updates
do not subscribe and remount an owning virtual list.

The real seven-argument Logseq bridge now additionally exports the existing
six-argument `lui_ocaml_virtual_window` maintenance ABI. It validates integers
and pins before OCaml entry and runs under the existing application lock.
Candidate exports are checked before schema extraction, startup and publication;
a failing candidate preserves previously published artifacts and receipts.

Update preparation now fences ordinary input, waits for actual saves, observed
descendants and mailbox/worker drain, and acknowledges correlated abort release
only after accepted work settles. Native passive virtualization feedback remains
admitted. This does not grant an install lease: actual whole-app installation
still refuses until worker compatibility/ownership and relaunch are implemented.

## Local evidence

- Actual App all-target Rust tests: 48 passed, zero failed or ignored, including
  real startup with the built OCaml library, resources and private worker.
  Log: `/tmp/logseq-nsh-parent-main-final-all-tests.log`.
- Actual App strict all-target Clippy and formatting passed.
  Logs: `/tmp/logseq-nsh-parent-main-final-clippy.log` and
  `/tmp/logseq-nsh-parent-main-final-fmt.log`.
- Real native save/abort and actual `Native_embed.Ffi.virtual_window` regression
  passed, including a 100,000-row sparse source while held. The controlled worker
  in this test is not a real database performance workload.
  Log: `/tmp/logseq-nsh-actual-virtual-window-admission-races.log`.
- Production OCaml row-helper tests passed at 1,000 and 100,000 rows using the
  installed PPX. Log: `/tmp/logseq-nsh-production-virtual-native-default-ppx.log`.
  This recording-backend test does not qualify the actual database and NSH Engine.
- Actual staged build/startup and complete macOS development-profile package
  passed. Logs: `/tmp/logseq-nsh-parent-main-final-build.log` and
  `/tmp/logseq-nsh-parent-main-package.log`.
- Windows tooling: 28 Python tests passed. Package/publication tooling: 22 Node
  tests passed. These are source/tooling checks, not native Windows execution.

The latest macOS archive was extracted outside the checkout and launched with
private storage. Its actual background native launcher gate passed. Journal,
More and Appearance content images were inspected. A separate fresh-receipt CLI
capture opened both sidebars and CmdK, verified its own listener and actual
AppKit input bounds, and captured visible palette pixels. The application stayed
inactive and the window stayed non-key; only task-owned processes were stopped.

Local artifacts in the Logseq worktree are intentionally ignored:

- `deps/ui/_build/nsh/parent-main-packaged-native/` (Journal, More, Appearance).
- `deps/ui/_build/nsh/parent-main-cmdk/result.json` and `sidebars-cmdk.png`.
- `deps/ui/_build/packages/Logseq-NSH-2.0.2-macos-aarch64.zip` and its receipts.

AppKit view bounds are not layer presentation coordinates or an animation-end
certificate. Visual inspection establishes the palette's presence in this PNG;
it does not establish hardware keyboard, IME or master UX parity.

## Remaining acceptance

Real database-backed 1,000/100,000-row Journal and Page measurements are still
required. Bounded mounted rows do not imply bounded business-data memory: the
current page pipeline fetches and decodes its complete block tree. Sparse update
churn, time, memory and idle CPU need separate measurements.

Appearance theme thumbnails are still gray/missing. Master comparison, visible
text geometry, editing/IME, accessibility and all required product flows remain
open. Latest-revision Windows/Linux native results, credentialed signing and a
safe whole-app N-to-N+1 installation/restart are also unqualified. Windows v1
installer admission is explicitly machine-conservative; multiuser SID scoping
is not established. No completion claim follows from this checkpoint.
