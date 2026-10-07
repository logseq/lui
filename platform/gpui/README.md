# LUI GPUI backend

A GPUI backend for LUI built on `gpui-kit` (gpui-component + gpui-base +
gpui-pre). The OCaml runtime drives a retained node store in Rust over the
existing `lui_ocaml_*` C ABI; every LUI node is rendered by its own
`Entity<LuiNodeView>`, so a patch batch only re-renders the nodes it dirtied
— never the whole tree.

## Crates

| crate      | role |
| ---------- | ---- |
| `lui-core` | wire batch decoding, retained node store, dirty-id tracking, event gating, `lui_ocaml_*` FFI bindings |
| `lui-gpui` | `LuiNodeView` (per-node entity), kind → gpui-kit component mapping, style-class → Styled resolver, extension host |
| `lui-demo` | runs `examples/components` (the gallery) inside a gpui window |

## Build & run

```sh
# Rust toolchain on PATH first
export PATH="$HOME/.rustup/toolchains/stable-aarch64-apple-darwin/bin:$PATH"

# 1. Build the OCaml gallery dylib (uses the ambient 5.5.0 switch)
cd <repo root>
OPAMSWITCH=5.5.0 opam exec -- dune build \
  examples/components/native/liblui_components.dylib

# 2. Build + run the demo (build.rs copies the dylib next to the binary
#    and rewrites its install name)
cd platform/gpui
cargo run -p lui-demo
```

## OCaml side

- `host_kind` gained `GPUIHost` (host code `6`); `lui_extension` reports the
  host as `"gpui"`, so extension profiles can gate on GPUI.
- Gallery extensions (`apple-map`, `apple-map-marker`, `simulator-camera`,
  `split-*`, `native-card`) now include a GPUIHost profile so the gallery
  boots; unregistered extension identifiers fall back to a generic host
  container (children + labeled box).

## `gpui-*` extension namespace

`lui-gpui` has an `ExtensionRenderer` registry keyed by extension
identifier; `gpui-<name>` is reserved for gpui-kit-specific components.
`LuiShared::new` registers the builtin set (extension.rs
`register_builtin_renderers`); apps can register more on top.

| identifier          | gpui-kit component | props | events |
| ------------------- | ------------------ | ----- | ------ |
| `gpui-rating`       | `Rating`           | `value` int, `max` int (default 5) | `change` `{value:int}` |
| `gpui-color-picker` | `ColorPicker` + `ColorPickerState` (per-node entity) | `value` `#rrggbb[aa]` | `change` `{color:string}` |
| `gpui-empty`        | `Empty`            | `title`, `description`; standard children render as the action slot | — |
| `gpui-tag`          | `Tag`              | `text`, `variant` (primary\|secondary\|danger\|success\|warning\|info) | — |
| `gpui-chart-bar`    | `BarChart`         | `name`, `data` (`"Label:Value,…"`) | — |
| `gpui-table`        | `DataTable` + `TableState` (per-node entity) | `columns` csv, `rows` `;`-separated csv rows, `bordered`, `stripe` | — |

The gallery mounts all six under a "GPUI" section that only appears on
`GPUIHost`. Props update via `set-extension-prop` like any signal; stateful
components keep their entities in `ComponentStates` per node id.

The `split-*` family (`split-view`/`split-branch`/`split-pane`/`split-tab`)
is backed by gpui-base `DockArea` (`crates/lui-gpui/src/dock.rs`): the model
remains source of truth — the renderer rebuilds the center `DockLayout` on
structure/prop signature changes, and `DockEvent::LayoutChanged` diffs the
dock's `dump()` against the last sync to emit the granular `split-pane` /
`split-branch` events (`tab-selected`, `tab-moved`, `split-drop`,
`pane-closed`, `ratio-changed`) back to the model.

## Kind coverage

All 85 wire `NodeKind`s render. Notable mappings:

- gpui-component widgets: Button, Checkbox, Switch, RadioGroup,
  Input/Textarea (`InputState` per node id), Slider, Progress, Spinner,
  Alert, MenuItem, Select/Combobox (`SelectState`/`ComboboxState` +
  `SearchableListDelegate` over `menu_item` children), Kbd.
- gpui-base `ResizablePanelGroup` backs both `resizable`
  (`width`/`min-width`/`max-width` → `size`/`size_range`) and `split`
  (`value` fraction tracks the measured group width; `on_resize` reports the new
  first-pane fraction via `slider_changed`).
- `deferred` + `anchored` overlays back `dialog`/`sheet`/`drawer`/`toast`
  (full-window modal), `dropdown_menu` (anchored under its stack
  trigger), `context_menu` (at the pointer), `tooltip` (hover), and
  `menu_trigger` submenus (anchored beside the row).
- `edge_inset` pins its last child at `edge`; `view_that_fits` renders its
  first child; `stacked` keeps the first child in-flow and absolutes the
  rest (absolute-only stacks collapse to 0×0).
- `file_image` draws `img(path)`; `image`, `media_surface` and
  `file_preview` render a labeled placeholder — their wire props are
  host-owned registry/surface ids, no bytes cross the wire.
- `file_picker` opens `cx.prompt_for_paths` and returns
  `lui_ocaml_picked`.

## Known gaps

- `select`/`combobox` use `SearchableListDelegate`-backed native pickers
  only when the node carries `menu_item` children (the children are the
  option source); Confirm fires `Press` on the picked item's node so the
  model's own `on_press` runs. Without `menu_item` children they keep the
  trigger/field rendering (the model mounts a `dropdown_menu` itself), so
  keyboard focus/filtering there is still model-managed.
- `tabs`/`bottom_tabs`/`pagination`/`segmented` render as styled
  containers; the model owns selection (LUI sends `press` for each entry),
  matching other backends.
- `video_player`, `image`, `media_surface`, `file_preview`: no
  GPUI-side content source exists; they are labeled placeholders.
- `style-class` resolves common Tailwind utilities + `gpui-theme` colors;
  `cp-`/`ls-` semantic classes map through the style dictionary (subset).

## Retained rendering and virtualization

`Shared` retains one `Entity<LuiNodeView>` for each mounted node. Property
patches notify the changed view; structural patches also notify the parent.
Notification uses `App::notify` without updating the entity, so synchronous
OCaml feedback can patch a node from inside its own input subscription.
Rejected batches restore only the touched nodes' before-images; an ordinary
property patch no longer copies the complete tree.

GPUI's view cache skips content measurement. Explicitly sized stateless
leaves use that cache; content-sized and stateful nodes keep normal layout
so wrapping, intrinsic sizes, and component interactions remain correct.
Entity children alone do not guarantee render isolation. Every node records
its own bounds without adding an extra layout container.

`virtual-list` uses gpui-kit's re-exported native `list` / `ListState` primitive.
It measures variable-height rows lazily, renders the viewport plus measurement
overscan, and keeps a focused row mounted for keyboard dispatch. The parent
must give the list a finite viewport (for example, a `height` property).
Row updates invalidate only that row's measurements; insert/remove/reorder
operations reconcile the child sequence and preserve the visible node's
scroll anchor. Scrolling does not copy the full child sequence. Imperative
scroll operations can jump to an unmeasured row by logical index; offscreen
geometry is retired. `list-container` remains an ordinary full collection.
The store still retains all model nodes, and visited rows retain component
state until dropped.

Run the regression suite with `cargo test -p lui-core -p lui-gpui --locked`.
A reproducible Store-only microbenchmark is available with
`cargo run -p lui-core --release --example store_patch_bench`.
