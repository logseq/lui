# NSH keyed-list reorder feasibility result

Date: 2026-11-11

NSH revision: `cdfdf75c1509cdb34c6220e6b5bf923452c0cb76`

Reproducer: `platform/nsh/tests/public_list_seam.rs`

```sh
cargo test --manifest-path platform/nsh/Cargo.toml \
  --test public_list_seam \
  public_keys_preserve_the_focused_editor_across_source_reorder -- --nocapture
```

## Observed behavior

The probe uses public Rust APIs: `virtual_list`, `keys`, position bindings,
owner cleanup, `ElementRef::scroll_to_end`, input events and keyboard shortcuts.
Editing state belongs to the root, not the recycled cell. A shortcut triggers
reorder without moving focus to a button. The new model position is checked
separately from cell retention.

For both 1,000 and 100,000 items, a far jump left 23 live public cell demands,
including the distant focused row. Its input held the edited value before
reorder. Swapping logical row 2 with the last row updated the model to index
999 / 99,999, but the focused cell's public position did not follow it. The
identity-preservation assertion failed for both sizes. These are headless
results, not native IME or timing qualification.

## Source explanation

`nsh-core/src/element/virtual_list.rs::splice` reduces changed key arrays to
one replacement span using a common prefix and suffix. This swap's span
includes the focused row and almost the entire source.

`nsh-core/src/core/components.rs` uses that span for Rust cell position updates
(`move_rows`) and `Prop::Splice` in `send_list_rows`.
`nsh-core/src/core/list.rs::ListState::splice` keeps positions before/after
the replacement but invalidates positions and retention inside it. This works
for contiguous insert/remove; it does not remap a moved key to its new index.
The Rust `keys` docs promise retention when rows are added or removed before
an item, rather than arbitrary reorder.

## Required boundary decision

Public cell bindings can expose bounded demand, but the key-splice path does
not satisfy LUI's retained-editor/reorder contract. Keep the failing regression;
do not substitute eager rendering, forced remounts or private-field access.

A focused upstream change should reconcile retained cells, active pins and
measurements by key on genuine reorder, updating position bindings coherently.
Keep contiguous splices on their existing fast path. Source-length work belongs
only to source/key changes, never scrolling or text edits. Test multiple
retained rows, removal, variable heights, focus/composition and overlay owners.
Determine whether the existing public `keys` API suffices before adding one.

The user subsequently authorized the minimal repair in `logseq/nsh`, branch
`fork/logseq`. It is published as
[`a4c64cb33f739368f113d8eaf3c80cc335ef7253`](https://github.com/logseq/nsh/commit/a4c64cb33f739368f113d8eaf3c80cc335ef7253),
with [draft review #1](https://github.com/logseq/nsh/pull/1). LUI's manifest and
lockfile now use that immutable Git revision without a local path override.
The adapter's public-API boundary and restriction against unrelated dependency
changes remain in effect.

## Repair verification

The repaired path maps retained unique keys to new positions, preserving cell
owners, measurements and indexed scroll targets. Pure insertion/removal uses
the existing contiguous-splice path. Key lookup is confined to source changes.
The public probe passes at both source sizes; each keeps 23 active cell demands
after a far jump and retains the same edited input across reorder. Core tests
also cover two retained rows moving in opposite order, mixed insertion/removal,
variable measurements and removal of a pending scroll target.

On macOS 27.2 arm64 / Apple M6 / Rust 1.97.0:

- Full NSH workspace tests: 5,258 passed, 0 failed, 63 existing ignored tests
  and documentation examples. Canonicalize `TMPDIR` to avoid the unrelated
  CLI mock's `/var/folders` versus `/private/var/folders` string comparison.
- Workspace Clippy and core Clippy with `-D warnings`: passed.
- `cargo xtask compat`: passed against `nsh-compat` revision
  `714e6fd8bdf0cc1ea54e924456aec2f013d3751c`, including current application
  scripts and API coverage claims. No compatible release was recorded yet.
- Changed Rust files pass nightly rustfmt. Full-tree formatting flags three
  unchanged native files; unrelated formatting is excluded from the repair.
- The debug CLI retains its existing linker warning about a large `__eh_frame`
  section. No warning is disabled.

Counter control: five debug `nsh test examples/counter/App.tsx --trace`
processes per version, with `await app.press("+1")` on stdin:

| Commit | Before median | After median | Counts, both versions |
| --- | --- | --- | --- |
| Initial | 253 microseconds | 255 microseconds | 57 ops / 51 mount items / 21 nodes |
| Press | 732 microseconds | 699 microseconds | 10 ops / 7 mount items / 24 nodes |

These timings are noisy smoke observations, not release performance or native
IME/composition qualification. This probe still does not establish the full
LUI sparse-window adapter or packaged application behavior.
