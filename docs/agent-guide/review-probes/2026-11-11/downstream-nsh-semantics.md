# Downstream requirements and native NSH semantics

Policy clarified by the user on 2026-11-12: preserve actual production usage in
mobile and Journal; use NSH's native model for components unused by both. This
is an explicit scope clarification, not permission to infer absence from a
component name in a single file or silently ignore a used API.

## Inspected application snapshots

- `logseq/mobile`: `82b6da991bc0e6987f652f6f5cd91d1e37f58498`.
- `logseq/logseq_journal`: `6c030857d0bc417d11394a73282a87416b8006cc`.

The audit inspected production OCaml sources under mobile shared/src and
Journal app, plus application-owned Apple/Android/Swift code. Build products,
vendor dependencies, generated schemas, backend compatibility tables and tests
were not counted as application use. Tests were read separately to establish
what existing production call sites require. Module aliases such as Journal's
`module L = Lui_elements` were followed.

## Confirmed decision points

| Component/API | Production use | Desktop decision |
| --- | --- | --- |
| Tree | No canonical Tree constructor, raw UI Tree creation or treeitem role found in either application. Mobile's outliner uses native editor extensions and keyed rows; Journal's Worker.Tree is a database DTO. | Use native NSH Tree data/selection/expansion/virtualization/keyboard semantics. Do not integrate the unused custom Tree focus coordinator draft. |
| Toast | Mobile shared/src/logseq/view_screens.ml capture confirmation passes explicit duration and on_dismiss cleanup. No Journal Toast call found. | Reuse native Toast, ToastStack and ToastManager. No dismissal veto/rebound controller. |
| FilePicker | No canonical constructor/raw picker-source/request/on_picked component usage found in production sources. Attachment selection uses distinct host services. | Thin native pick_paths/OpenDialog service; document unsupported legacy sources and result-shape migration. |
| ContextMenu | Mobile view_sidebar.ml, view_graphs.ml, view_composer.ml and view_outliner.ml; Journal application.ml also constructs Lui_elements.context_menu. | Preserve the used contextual attachment/menu behavior. Do not confuse Journal's separate Native_list context-menu data with a canonical ContextMenu node. |
| FileImage | Mobile view_composer.ml passes path, max_pixel_size=384 and fill fit; Journal journal_media_view.ml calls L.file_image. | Preserve the actual path/fit/decode-size requirements. Native Image availability alone does not prove them. |
| FilePreview | Mobile view_screens.ml constructs file_preview for attachments. | Preserve used presentation/dismissal behavior; an external open_path operation is not automatically an equivalent preview. |
| ViewThatFits | Journal journal_header.ml constructs Lui_elements.view_that_fits in production feedback. | Retain it; see the separate usage report. |
| Breadcrumb | Mobile view_outliner.ml constructs breadcrumbs for the focused node and related blocks. | Preserve authored children/layout. Native Toolbar composition remains appropriate; a domain breadcrumb string is not the only usage evidence. |
| Textarea Enter policy | Mobile view_composer.ml propagates explicit submit_on_enter; view_query.ml sets false. Journal journal_view.ml also sets false. | Bind the used policy to native Input submit configuration. Do not add unused navigation or modified-Enter controllers solely because another backend has them. |
| MediaSurface | No canonical constructor/raw kind references found in either inspected production tree. | Use native Video URLs and document the resource-ID migration. |
| SwipeActions/SwipeAction | No canonical constructor/raw kind references found in either inspected production tree. | The user explicitly excluded them from NSH desktop scope on 2026-11-12. Preserve the common/mobile APIs; desktop uses ordinary commands or ContextMenu. Explicit rejection remains. |

These are specific reviewed components, not an exhaustive claim that all 87
kinds or all their optional properties have been audited. Every later adapter
increment must inspect its own relevant downstream calls before imposing an old
backend's convention.

## Toast correction

The earlier surface-gap note treated refusal recovery as a desktop requirement.
That was an inference from retained-node ownership, not a Toast veto API.
`Lui_elements.toast` registers an ordinary on_dismiss callback with no boolean
response. Removed MyGo menus.go171-187 closes native presentation before
emitting Dismiss; its timeout regression explicitly keeps the canonical node
while requiring the expired toast to remain invisible and never rearm.
MyGo's absent duration was 4000ms and explicit zero meant persistent.
Mobile's app test dispatches Dismiss and checks that capture confirmation is
removed; it does not veto the native closure. This evidence supports direct NSH
lifecycle reuse rather than custom gesture/visibility recovery.
