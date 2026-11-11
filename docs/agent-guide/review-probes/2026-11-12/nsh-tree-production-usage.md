# Tree production usage and the native NSH decision

The requested production applications do not construct LUI Tree or TreeItem UI
at the inspected revisions. The user's policy therefore makes native NSH Tree
semantics authoritative for the desktop implementation. The unpublished custom
focus/role coordinator checkpoint `5157c8a8` is preserved in an isolated branch;
it must not be integrated as the native Tree implementation.

## Inspected production sources

| Repository | Revision | Production scope and evidence |
| --- | --- | --- |
| `../mobile` | `82b6da991bc0e6987f652f6f5cd91d1e37f58498` | `shared/src`, `apple/Sources`, `android/app/src/main`; 13 `view*.ml` modules directly use `Lui_elements`. No Tree constructor, TreeItem role/level metadata, alias call or raw Tree node creation was found. |
| `../logseq_journal` | `6c030857d0bc417d11394a73282a87416b8006cc` | `app` and `swift`, including wrappers in `journal_view.ml` and `journal_native_collection.ml`. `module L = Lui_elements` appears in `journal_row.ml:3` and `journal_media_view.ml:2`; neither contains a Tree call. No unqualified Tree constructor, TreeItem role/level metadata or raw Tree node creation was found. |

Mobile's outline is not LUI Tree: `shared/src/logseq/view_rows.ml:79` defines the
retained/windowed row helpers, `view_rows.ml:87` uses LUI List, and
`view_rows.ml:98` mounts keyed rows. `view_outliner.ml:12`, `:48` and `:543` create
`outliner-editor`, `outliner-block-content` and `outliner-block-row` extensions.
Its query-result expansion in `view_query.ml` is application data flattened to
keyed row views, not a Tree widget.

Journal's `app/journal_lui_native.ml:107` creates registered native extensions;
`:126` exposes its custom list. `journal_view.ml` is the wrapper layer over
ordinary LUI elements and native collection extensions. These routes remain
outside the native Tree change.

## Deliberately excluded false positives

- Mobile `android/.../runtime/LuiPatchFilter.kt:102` recognizes the `treeitem`
  compatibility string when filtering generic backend properties. It does not
  produce a Tree or TreeItem application view.
- Mobile `shared/src/logseq/core/graph_read.ml` uses `tree` for immutable page
  query metadata, and `view_query.ml` defines an `Expanded` set of row UUIDs.
- Journal `app/journal_graph_feed_plan.ml:216` uses `Worker.Tree`, a database read
  DTO. Other `Worker.Tree` and `Outliner.Tree` references are data contracts,
  reducers or query transport, not `Lui_elements.tree`.
- Tests, schema definitions, compatibility filters, generated dependencies,
  caches and gallery/demo code do not establish production application usage.

## Search coverage

Read-only searches covered `tree` / `Tree` identifiers, qualified
`Lui_elements.tree` and aliased calls, `Lui_ui.tree` / `Lui_ui.create`, raw
`create_node` / `create-node` production, string kind `tree`, and
`treeitem`, `tree_level`, `tree-level`, `TreeLevel`, `RoleValue` metadata. Wrapper
modules and all production `Lui_elements` imports were inspected to distinguish
UI aliases from unrelated data names. Representative commands:

```sh
rg -n '\b(tree|Tree)\b|treeitem|tree_level|tree-level|TreeLevel|RoleValue' shared/src -g '*.ml' -g '*.mli'
rg -n 'module .*Lui_elements|include.*Lui_elements|Lui_ui\.(tree|create)|create_node|create-node' shared/src -g '*.ml' -g '*.mli'
rg -n 'L\.tree|Lui_elements\.tree|Lui_ui\.(tree|create)|treeitem|tree_level|tree-level|TreeLevel|RoleValue|create_node|create-node' app -g '*.ml' -g '*.mli'
```

This is source evidence at the named revisions, not a claim about future app
changes or dynamically downloaded external application code. Neither production
repository was modified and no build/test command was run for this audit.

## Implementation boundary

Use public `nsh_base::Tree`, `TreeItem`, `TreeProps` and `TreeEvent` from pinned
NSH `d21573c`. NSH owns hierarchy, cursor/focus, selection, expansion, typeahead,
virtualization and native row lifetimes. The LUI adapter supplies item metadata
and guarded callback identities. New desktop defaults and any incompatible
legacy Tree constructor behavior belong in `docs/api-migrations.md` with concrete
migration examples. Preserve the production List/outliner/native-extension
routes above; their identity and editor requirements must not be inferred as
unused Tree requirements.
