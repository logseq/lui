# NSH active cell demand qualification

Date: 2026-11-11

Published dependency: `logseq/nsh`, branch `fork/logseq`, commit
`028574b7de9ee25a7c6f60660ef72fcb8790a27e`.
The original keyed-reorder repair is its parent,
`a4c64cb33f739368f113d8eaf3c80cc335ef7253`.

The keyed-reorder repair preserves editor identity, but the sparse LUI adapter
also needs to distinguish native demand from cached cells. A Rust cell owner
and its last `Position::index()` can survive native release so that NSH can
reuse the cell later. Owner existence therefore does not prove that LUI must
retain the old row.

## Observed failure

The real NSH headless probe focuses row 2, jumps to the end of a 100,000-row
source, then blurs the editor without moving the viewport. The blur callback
fires, but the old public position bindings still report three distant cached
rows as pins for at least three seconds. These are bounded cached owners, not
an unbounded representation; the failure is that inactive row pins do not
release on a stationary viewport.

Public `ElementRef::measure` also returns the old offscreen geometry after
release. Negative page coordinates cannot distinguish a genuinely retained
editor from a free cached cell, so geometry is not a correct replacement for
native demand. The adapter must not reproduce NSH's focus, selection, pointer
and overlay retention state machine.

Regression: `virtual_rows::tests::native_cell_feedback_releases_distant_focus_without_scrolling_again`.
The test remains active and the production bounded-row capability stays off.

## Published repair

Within the authorized list-retention repair, NSH now exposes the read-only
`Position::is_requested() -> bool` binding. It must reflect NSH's own native
slot assignment, including overscan and interaction-retained rows, and become
false when an inactive pooled cell only holds its previous index. Ordinary
child positions default to true. No JS/wire operation or platform API changes
are needed.

Only existing virtual cells need a request signal. Publish a reused cell's
new index before its requested state; update signals when the corresponding
native list window changes, with no polling or source-wide scan. LUI can then
hide inactive cached content and omit its row from window/pin feedback.

The initial regression exposed a second ordering issue: layout can generate
component patches when request bindings change. The commit loop must flush
those patches before declaring the virtual-list rounds complete. The repair
checks the existing patch queue in that termination condition, so the update
finishes in the same commit without polling or an adapter retention manager.

## Qualification

- The new NSH core regression passes at 1,000 and 100,000 source rows. It
  focuses row 2, jumps away, blurs without another scroll, observes demand
  release, and returns to the retained cached native cell.
- NSH workspace tests: 5,259 passed, 0 failed, 63 existing ignored tests and
  examples. Strict all-target workspace Clippy and `cargo xtask compat`
  passed. The compatibility repository revision was
  `714e6fd8bdf0cc1ea54e924456aec2f013d3751c`.
- LUI pins the published Git revision with no local dependency override.
  `cargo check --locked --all-targets`, `cargo test --locked`, strict
  all-target Clippy and formatting passed. The LUI suite had 44 passing
  tests, 0 failed and 0 ignored; the real OCaml virtual fixture was enabled
  through `LUI_NSH_VIRTUAL_LIBRARY`.
- The actual OCaml fixture retains 23 mounted rows at both 1,000 and 100,000
  source items (85 LUI nodes, 142 NSH nodes). It covers editor identity,
  focused reorder, stationary blur release, controlled remount, removal,
  source shrink, missing targets, exactly-once completion and ten additional
  100,000-row load/far-jump/Clear cycles.

The changes are published in [draft review #1](https://github.com/logseq/nsh/pull/1).
These are macOS host and headless-engine results, not native IME, visual,
accessibility or cross-OS performance qualification. The production bounded-row
capability remains off until its negotiation and required native qualification
are complete. No existing ignored NSH tests were added or enabled selectively.
