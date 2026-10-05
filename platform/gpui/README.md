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
identifier; `gpui-<name>` is reserved for gpui-kit-specific components
(DockArea, Table, charts…). No `gpui-*` components are registered yet —
that is the next PR. Registration is additive and needs no OCaml changes:
`create-extension` nodes carry an identifier + props, and events flow back
through `lui_ocaml_extension_event`.

## Kind coverage

All 85 wire `NodeKind`s render. Notable mappings:

- gpui-component widgets: Button, Checkbox, Switch, RadioGroup,
  Input/Textarea (`InputState` per node id), Slider, Progress, Spinner,
  Alert, MenuItem.
- gpui-base `ResizablePanelGroup` backs both `resizable`
  (`width`/`min-width`/`max-width` → `size`/`size_range`) and `split`
  (`value` fraction seeds pane one).
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

- `split`: `on_resize` can't reach the model — the C ABI has no
  `lui_ocaml_resize`; drags resize locally only. Add the symbol (or reuse
  `slider_changed`) when needed.
- `select`/`combobox`: render as trigger/field; opening mounts the
  gallery's conditional `dropdown_menu`, but there is no
  `SearchableListDelegate`-backed filtering yet.
- `menu_trigger` submenu: opens on hover, closes on outside press or a
  second click — there is no sibling coordination, so a submenu can stay
  open if you move straight to another menu row.
- `tabs`/`bottom_tabs`/`pagination`/`segmented` render as styled
  containers; the model owns selection (LUI sends `press` for each entry),
  matching other backends.
- `video_player`, `image`, `media_surface`, `file_preview`: no
  GPUI-side content source exists; they are labeled placeholders.
- `style-class` resolves common Tailwind utilities + `gpui-theme` colors;
  `cp-`/`ls-` semantic classes map through the style dictionary (subset).

## Minimal-granularity rendering

`Shared` keeps `HashMap<i64, Entity<LuiNodeView>>`. Applying a patch batch
returns the dirty id set: `set-*` ops dirty the node, structural ops dirty
the parent, `drop-node` releases the entity. Only dirty entities get
`cx.notify()`, so gpui's prepaint reuses everything else.
