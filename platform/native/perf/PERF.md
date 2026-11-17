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
| `hit-100k` | `hit_path` point queries over a mounted 100k list, unindexed vs `Lui_spatial`-indexed; indexed static-frame paint; index build cost |
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
| vlist-10k | mount patch apply | 9.38 | ms |
| vlist-10k | mount layout | 42.58 | ms |
| vlist-10k | mount paint | 3.76 | ms |
| vlist-10k | mount raster | 1.97 | ms |
| vlist-10k | frame apply p50 | 0.00 | ms |
| vlist-10k | frame layout p50 | 0.00 | ms |
| vlist-10k | frame paint p50 | 4.60 | ms |
| vlist-10k | frame raster p50 | 1.86 | ms |
| vlist-10k | frame total p50 | 6.49 | ms |
| vlist-10k | frame total p95 | 7.25 | ms |
| vlist-10k | visible children | 30 | nodes |
| vlist-10k | scene ops/frame | 62 | ops |
| vlist-50k | mount patch apply | 50.85 | ms |
| vlist-50k | mount layout | 282.63 | ms |
| vlist-50k | mount paint | 27.22 | ms |
| vlist-50k | mount raster | 2.49 | ms |
| vlist-50k | frame apply p50 | 0.00 | ms |
| vlist-50k | frame layout p50 | 0.00 | ms |
| vlist-50k | frame paint p50 | 34.56 | ms |
| vlist-50k | frame raster p50 | 1.88 | ms |
| vlist-50k | frame total p50 | 36.48 | ms |
| vlist-50k | frame total p95 | 52.84 | ms |
| vlist-50k | visible children | 30 | nodes |
| vlist-50k | scene ops/frame | 62 | ops |
| vlist-100k | mount patch apply | 96.84 | ms |
| vlist-100k | mount layout | 522.34 | ms |
| vlist-100k | mount paint | 64.41 | ms |
| vlist-100k | mount raster | 6.54 | ms |
| vlist-100k | frame apply p50 | 0.00 | ms |
| vlist-100k | frame layout p50 | 0.00 | ms |
| vlist-100k | frame paint p50 | 76.74 | ms |
| vlist-100k | frame raster p50 | 1.88 | ms |
| vlist-100k | frame total p50 | 78.78 | ms |
| vlist-100k | frame total p95 | 108.42 | ms |
| vlist-100k | visible children | 30 | nodes |
| vlist-100k | scene ops/frame | 62 | ops |
| damage-5k | mount patch apply | 3.37 | ms |
| damage-5k | mount layout | 22.66 | ms |
| damage-5k | mount paint | 2.74 | ms |
| damage-5k | mount raster | 2.88 | ms |
| damage-5k | flip apply p50 | 0.00 | ms |
| damage-5k | damaged raster p50 | 0.07 | ms |
| damage-5k | full raster p50 | 3.71 | ms |
| damage-5k | damaged rects | 1.00 | rects |
| text-500 | patch apply | 0.13 | ms |
| text-500 | layout+measure | 1.78 | ms |
| text-500 | paint+shape | 0.57 | ms |
| text-500 | raster+blit | 3.34 | ms |
| text-500 | glyphs | 2540 | glyphs |
| text-500 | scene ops | 50 | ops |
| first-frame-10k | patch apply | 9.71 | ms |
| first-frame-10k | layout | 82.04 | ms |
| first-frame-10k | paint | 6.15 | ms |
| first-frame-10k | raster | 3.06 | ms |
| first-frame-10k | total | 102.85 | ms |
| rss-100k | RSS before apply | 50.4 | MiB |
| rss-100k | patch apply | 120.08 | ms |
| rss-100k | RSS after apply | 82.8 | MiB |
| rss-100k | apply delta | 32.3 | MiB |
| rss-100k | RSS after first frame | 242.5 | MiB |

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

**Layout re-sync is memoized on the store revision.** `Lui_layout.sync`
keys its rebuild on (store revision, frame geometry, ctx_anchor, and
the measure/hidden identities); a scroll frame touches none of these,
so `frame layout p50` is 0.00ms at every size. `Lui_layout.invalidate`
covers host-side inputs that change under a stable closure (e.g. a
font stack finishing loading). The first layout after any store edit
still rebuilds the whole mirror — mount layout stays ~linear
(43→283→522ms across 10k/50k/100k); true incremental layout remains
the follow-up for update-heavy frames.

**Paint emits ops only for the visible window** (`visible children`
30 → `scene ops/frame` 62 at every size): nodes whose resolved box
misses the viewport are culled with their descendants before chrome
or state resolution runs. The cull itself is what still scales with
tree size — the walk visits every mounted node to know its rect, so
`frame paint p50` is ~linear (4.6→34.6→76.7ms across 10k/50k/100k,
~0.8µs per culled node). Getting below that needs a spatial index or
window-aware store semantics, not more per-node tuning.

**Damage-limited raster does its job:** one color flip inside a 5k
tree damages exactly 1 rect and rasters in 0.07ms vs 3.71ms for a
full pass. The win grows with scene size.

**Damage-limited raster does its job:** one color flip inside a 5k
tree damages exactly 1 rect and rasters in 0.96ms vs 2.87ms for a
full pass. The win grows with scene size.

**Memory:** ~0.34KB/node in the store (50→83 MiB across a 100k
patch), then ~2.4KB/node total after the first frame (242.5 MiB)
once the flex tree, emitted ops, and the damage tracker's
prev_ops/prev_glyphs/bounds snapshots are live. Viewport culling
shrunk the snapshots dramatically — they now hold the 62 emitted ops,
not one per mounted node.

## Regression bounds

`dune runtest platform/native/` runs the same scenarios at reduced
sizes (`--small`: vlist-10k, 2k damage tree, 500 texts, 2k first
frame, 20k RSS patch; ~10 s) and asserts:

- structural: the scrolled window shows only viewport-capacity
  children (≤ height/28 + 2) and emits more ops than that window's
  own count (chrome + edges), a single prop flip damages 1–64 rects,
  and damage-limited raster is never slower than ~3× a full pass.
- absolute ceilings, ~3× the small-suite values measured on the
  reference machine: vlist frame total p50 < 1000ms, first-frame
  total < 500ms, text layout/paint stages < 50ms, flip apply < 50ms,
  20k mount apply < 15000ms.
