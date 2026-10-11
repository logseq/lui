# platform/native/perf — headless perf harness for the native LUI backend

A headless benchmark + regression suite for the OCaml native backend
(`Lui_host` store → `Lui_layout` → `Lui_paint` → `Lui_raster`), built the
same way `platform/native/e2e` drives the pipeline but timing each stage
separately.

## Method

- One `Harness.t` per scenario owns a `Lui_host` (store + scene), a
  `Lui_layout` flex mirror, and one `Lui_raster.Renderer` (the
  damage-limited renderer a real window drives).
- Each frame is timed per stage:
  - `patch apply` — `Lui_host.apply_batch` on a wire batch.
  - `layout` — `Lui_layout.sync` with the deterministic stub measure
    (8 px/byte, 16 px line).
  - `paint` — `Lui_paint.paint` with production-style hooks; scroll is
    modelled exactly like `lui_window`: ancestor scroll offsets are
    summed in the paint `layout` hook and subtracted from placements.
  - `raster` — `Lui_raster.Renderer.render` (damage-limited), with
    `Lui_raster.render` (full) alongside for the damage comparison.
  - `~workers:1` throughout: deterministic single-core numbers.
- Frame geometry: 1280×800 @ scale 1.
- Text: the stub text engine emits one empty-range `Glyphs` op per call;
  the `Quads` engine (text scenario) appends real 8×16 glyph records
  into the mask atlas so shaping/blit work is measured without a
  platform font stack.
- `Harness.create` runs `Gc.full_major ()` first: scenarios share the
  process heap, so garbage owed by an earlier scenario's mounts would
  otherwise be collected inside the next scenario's timed stages.
- RSS: `/proc/self/status` VmRSS, `ps -o rss=` fallback on macOS.

## Scenarios

| scenario | what it stresses |
|---|---|
| `vlist-{10,50,100}k` | mount N list-items under a `virtual-list`, then scroll at 40 px/frame for 30 frames; per-stage p50/p95, visible window, ops emitted |
| `damage-5k` | flip one visible node's `background` in a 5k-row tree; damaged rect count, damage-limited vs full raster |
| `text-500` | 500 text leaves through the glyph-quad engine; layout+measure, paint+shape, raster+blit |
| `first-frame-10k` | one 10k-node initial patch, apply through pixels |
| `rss-100k` | RSS before/after a 100k-node patch and after the first frame |

## Running it

```sh
opam exec -- dune build
_build/default/platform/native/perf/main.exe          # full sizes
_build/default/platform/native/perf/main.exe --small  # bounded sizes, ~10 s
opam exec -- dune runtest platform/native/            # alcotest regression bounds (small sizes)
```

`main.exe` prints the markdown table below
(`| scenario | metric | value | unit |`).

## Measured numbers

Machine: Mac (Apple Silicon, arm64), macOS 26.5.2, OCaml 5.5.0,
`dune exec` release profile.

| scenario | metric | value | unit |
|---|---|---|---|
| vlist-10k | mount patch apply | 6.77 | ms |
| vlist-10k | mount layout | 38.25 | ms |
| vlist-10k | mount paint | 16.90 | ms |
| vlist-10k | mount raster | 6.17 | ms |
| vlist-10k | frame apply p50 | 0.00 | ms |
| vlist-10k | frame layout p50 | 33.49 | ms |
| vlist-10k | frame paint p50 | 20.35 | ms |
| vlist-10k | frame raster p50 | 4.41 | ms |
| vlist-10k | frame total p50 | 59.98 | ms |
| vlist-10k | frame total p95 | 63.41 | ms |
| vlist-10k | visible children | 30 | nodes |
| vlist-10k | scene ops/frame | 20002 | ops |
| vlist-50k | mount patch apply | 39.72 | ms |
| vlist-50k | mount layout | 213.62 | ms |
| vlist-50k | mount paint | 105.54 | ms |
| vlist-50k | mount raster | 21.60 | ms |
| vlist-50k | frame apply p50 | 0.00 | ms |
| vlist-50k | frame layout p50 | 187.30 | ms |
| vlist-50k | frame paint p50 | 114.02 | ms |
| vlist-50k | frame raster p50 | 17.82 | ms |
| vlist-50k | frame total p50 | 318.61 | ms |
| vlist-50k | frame total p95 | 339.11 | ms |
| vlist-50k | visible children | 30 | nodes |
| vlist-50k | scene ops/frame | 100002 | ops |
| vlist-100k | mount patch apply | 74.63 | ms |
| vlist-100k | mount layout | 377.77 | ms |
| vlist-100k | mount paint | 248.46 | ms |
| vlist-100k | mount raster | 17.14 | ms |
| vlist-100k | frame apply p50 | 0.00 | ms |
| vlist-100k | frame layout p50 | 394.77 | ms |
| vlist-100k | frame paint p50 | 251.81 | ms |
| vlist-100k | frame raster p50 | 29.60 | ms |
| vlist-100k | frame total p50 | 685.53 | ms |
| vlist-100k | frame total p95 | 737.27 | ms |
| vlist-100k | visible children | 30 | nodes |
| vlist-100k | scene ops/frame | 200002 | ops |
| damage-5k | mount patch apply | 3.09 | ms |
| damage-5k | mount layout | 13.98 | ms |
| damage-5k | mount paint | 9.42 | ms |
| damage-5k | mount raster | 2.10 | ms |
| damage-5k | flip apply p50 | 0.00 | ms |
| damage-5k | damaged raster p50 | 0.96 | ms |
| damage-5k | full raster p50 | 2.87 | ms |
| damage-5k | damaged rects | 1.00 | rects |
| text-500 | patch apply | 0.13 | ms |
| text-500 | layout+measure | 1.49 | ms |
| text-500 | paint+shape | 3.67 | ms |
| text-500 | raster+blit | 5.50 | ms |
| text-500 | glyphs | 25890 | glyphs |
| text-500 | scene ops | 500 | ops |
| first-frame-10k | patch apply | 9.10 | ms |
| first-frame-10k | layout | 28.89 | ms |
| first-frame-10k | paint | 15.30 | ms |
| first-frame-10k | raster | 7.83 | ms |
| first-frame-10k | total | 62.93 | ms |
| rss-100k | RSS before apply | 50.4 | MiB |
| rss-100k | patch apply | 83.96 | ms |
| rss-100k | RSS after apply | 82.7 | MiB |
| rss-100k | apply delta | 32.3 | MiB |
| rss-100k | RSS after first frame | 309.5 | MiB |

## What was unexpectedly slow, and the fix that landed

The first run of this harness found two super-linear stages; both root
causes have since been fixed upstream and re-measured below.

**Patch apply was ~O(n^2.8) in sibling count → now linear.**
`Lui_store.insert_child` ran a full `List.filter` over the parent's
children plus an `insert_at` walk for every `InsertChild` (100k mount
measured at 306s). `node.children` is now a growable `child_vec`
(array + length): appends are O(1) amortized, and the dedupe filter
runs only when the child already had a parent (`c.parent = None`
means first attach, no scan). Mount apply: 606→6.8ms @10k,
53s→40ms @50k, 306s→75ms @100k. The twin implementation in
`deps/drive/src/model.ml` got the same treatment. Small incremental
patches were already free (prop flip: 0.00ms).

**Paint was ~O(n^2.7) in container fan-out → now linear.**
`Lui_paint.default_chrome` computed `last_sibling` per node via
`List.rev (Lui_store.child_ids parent)` — an O(fan-out) walk per
child (100k frame: 131s). The store now answers the question in O(1)
via `Lui_store.last_child_id`. Frame paint p50: 233→20ms @10k,
17.1s→114ms @50k, 131s→252ms @100k.

**Layout and raster are ~linear** (layout p50: 33→187→395ms,
raster p50: 4.4→17.8→29.6ms across 10k/50k/100k). Layout re-syncs the
whole flex tree every scroll frame and is now the largest per-frame
cost at 100k (~0.4s) — incremental layout is the next candidate if
big-list scrolling must hit 60fps.

**Paint still emits an op for every mounted child** (`visible
children` stays 30 while `scene ops/frame` is 200002 at 100k):
emission is correct-but-unclipped, so paint cost scales with tree size,
not viewport size — ~250ms/frame at 100k. Viewport-aware emission
would cut the largest stage again; the raster already discards
off-clip ops cheaply.

**Damage-limited raster does its job:** one color flip inside a 5k
tree damages exactly 1 rect and rasters in 0.96ms vs 2.87ms for a
full pass. The win grows with scene size.

**Memory:** ~0.34KB/node in the store (50→83 MiB across a 100k
patch), then ~2.7KB/node total after the first frame (309.5 MiB)
once the flex tree, emitted ops, and the damage tracker's
prev_ops/prev_glyphs/bounds snapshots are live. High but proportional;
the retained snapshots (a second copy of every op) are the largest
single share.

## Regression bounds

`dune runtest platform/native/` runs the same scenarios at reduced
sizes (`--small`: vlist-10k, 2k damage tree, 500 texts, 2k first
frame, 20k RSS patch; ~10 s) and asserts:

- structural: the scrolled window shows only viewport-capacity
  children (≤ height/28 + 2), paint still emits ops for all mounted
  children, a single prop flip damages 1–64 rects, and damage-limited
  raster is never slower than ~3× a full pass.
- absolute ceilings, ~3× the small-suite values measured on the
  reference machine: vlist frame total p50 < 1000ms, first-frame
  total < 500ms, text layout/paint stages < 50ms, flip apply < 50ms,
  20k mount apply < 15000ms.
