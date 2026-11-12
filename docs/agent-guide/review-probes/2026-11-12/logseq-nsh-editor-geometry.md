# Logseq NSH editor geometry capability audit

Status: **minimal read-only NSH API implemented and qualified in NSH; Logseq geometry adapter pending**. On 2026-11-12 the user approved a committed-layout query API in the authorized fork and an immutable dependency pin. The implementation is published in `logseq/nsh` commit `2635333e4cc0d3be8032c97f3a5e08d3685179c6` on `fork/logseq`, incorporating source checkpoint `cffa79b`. LUI and the actual Logseq host select that immutable revision. Qualification on macOS passed eight core geometry tests, the real CoreText committed-layout test, the full core library suite (1,470 passed, 12 ignored), and strict Clippy for all targets of `nsh-core`, `nsh-base`, and `nsh-platform-macos`. This does not qualify Logseq caret placement, clicking to edit, selection, or typing: its source-span adapter and actual application checks remain required.

The original audit below records the earlier pinned revision. The implementation was checked against the current fork base `ea23ae9cd5f56426145ea225f1a220e1eca0d3a2`, which retains the same public access gap. `ElementRef::text_geometry` now queues a Rust-only query after the commit's `flush_text`, reading the existing `LaidText` and `TextEngine`. Its answer retains the exact mounted attributed snapshot, content box, ordinary root-view measurement and ancestor scroll scale; caret, range, hit-test and visual lines remain engine-owned. Invalid UTF-16 scalar boundaries, detached or hidden targets and non-finite points return no result. The Logseq adapter still needs to map source runs to that snapshot and discard stale replies before this capability is usable.

Sources inspected on 2026-11-12:

| Repository | Revision | Local checkout |
| --- | --- | --- |
| LUI | `50f0101e9d2fe0c456887bdc2c955006dccad37a` | `projects/lui` |
| Logseq | `b45c670eac7cdad0dcbbb5c6ccbb4d967bedfec1` | `projects/logseq.worktrees/nsh-host` |
| NSH, also the actual pinned dependency | `bfa15d0c843c0d6f5bf3a2a230e8ca56b876b61c` | `projects/nsh` |

## Current route and failure

Logseq `deps/ui/native/logseq_editor.ml:337–366` constructs the native conduit and issues these `Host.dom_op` requests. Coordinates are relative to the visible block-editor; native model offsets are UTF-8 bytes.

| Request | Input | Required reply |
| --- | --- | --- |
| `caret-rect` | `block-id`, `offset` | Same identity/offset plus `x`, `y`, `h`, window origin `ox`, `oy` |
| `selection-rects` | `block-id`, `first`, `last` | Same range plus actual line/bidi rectangles |
| `offset-at` | `block-id`, `x`, `y` | Same point plus source byte `offset` |
| `line-ranges` | `block-id` | `ranges` encoded as `lo,hi;…` in source bytes |

All four currently fail at `deps/ui/nsh/src/services/mod.rs:111` → `services/dom.rs:234` → `supported` at line 265. The supported set excludes them. `scroll-height` and `set-input-focus` from the same native contract are also absent. Existing `measure-node` and input selection commands do not implement text geometry.

The reply transport already exists: `deps/ui/native/native_embed.ml:786–789` forwards the four geometry names and `scroll-height` to `Logseq_editor.note_measurement`; lines 259–313 there consume actual measurements and reject obsolete requests. The NSH service can reuse its existing post-publication `AfterCommit` task and `PlatformEvent` return path once real geometry is available.

## Public access boundary

NSH has the precise algorithms: `crates/nsh-core/src/text.rs:975–1021` exposes `TextEngine::{lines, hit_test, caret_rect, range_rects}` over an existing `TextLayout`. The rendered attributed text and layout are retained privately in `Core::LaidText` (`core/mod.rs:1015`) and `TextContext::laid_out` (line 994). `MountItem::Text` (`mount.rs:765`) carries the actual `Arc<AttributedText>`, layout and content bounds to the platform-owned mount sink, but the normal `run_app`/`AppView` does not expose that committed snapshot to this application.

Public `ElementRef::measure` (`element/element_ref.rs:377`) returns whole-view bounds. It exposes no committed-text caret/range/hit/line query. `Input::on_caret_move` (`element/host.rs:850`) reports only that input's current caret. Logseq's input is intentionally transparent, absolute and 1×1 (`extensions/editor.rs:155–176`); its layout is **not** the visible rich-run layout.

`EditorApi::{caret_bounds, range_bounds}` (`nsh-base/src/editor/mod.rs:622–629`) and rich-editor session geometry (`rich_editor/view/session.rs:539–573`) belong to those components' own document/layout. Replacing the OCaml surface with either would introduce a different document/controller. macOS `CoreTextEngine` is publicly reexported, but the existing `CoreTextLayout` and platform range helpers are private (`nsh-platform-macos/src/text.rs:368,1938`). Creating another CoreText layout would measure a substitute, not the attributed lines actually rendered.

## Smallest proposed extension

Add one opt-in public retained-reference query in NSH, conceptually `ElementRef::text_geometry(request) -> Answer<Option<TextGeometry>>`. Request variants should cover a caret position with affinity, UTF-16 range, content-space hit point, and lines. The core would answer from the existing committed `LaidText` and running text engine, with actual content/root origins and relevant attributed-span identity. Return no data for retired/unlaid-out text. The user authorized this extension on 2026-11-12. The source implementation above passed the core and macOS checks recorded at the top; actual Logseq integration and Windows/Linux verification remain required.

The Logseq adapter would map that result onto its existing conduit, without a second layout, selector engine, document cache or focus controller:

- Query each actual `.ed-line` attributed layout, not separately shaped `.ed-r` fragments. `src/editor/edit_view.ml:510–529` creates those retained text flows; `runs_prop_of` at line 346 supplies source spans in emitted run order.
- Resolve retained line/run identities within the active editor's existing child relationships. NSH already retains inline test-id UTF-16 spans in `AttributedText::test_ids` (`text.rs:574`; `core/mod.rs:7446`). Use this as identity evidence, not a new application-wide search.
- Pin block id, wire incarnation/native identity, source/runs revision and composition display snapshot across the asynchronous commit query. Drop stale replies after edit, reorder, graph switch, disposal or remount.
- Convert only valid UTF-8 byte boundaries to/from UTF-16. Preserve wrap affinity, surrogate pairs, combining text and bidi range splits. Hidden delimiters still occupy source bytes: mapping must distinguish omitted layout from hidden-but-space-consuming text. Atomic attachments map to source edges rather than invented internal glyph positions.
- Derive visual line ranges and scroll height from committed layout. Do not infer them from source newlines, evenly spaced characters, the invisible input or a second typesetting pass.

Until that access exists, retain the explicit capability gap. A build gate must exercise an actual mounted editor and these required service operations before artifact publication; passing startup/sidebar tests cannot qualify editing geometry. Returning empty success or merely admitting operation names would conceal the missing implementation.
