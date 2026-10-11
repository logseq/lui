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
_build/default/platform/native/perf/main.exe          # full sizes (slow: 100k mounts are super-quadratic)
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
| vlist-10k | mount patch apply | 606.24 | ms |
| vlist-10k | mount layout | 31.37 | ms |
| vlist-10k | mount paint | 238.14 | ms |
| vlist-10k | mount raster | 3.38 | ms |
| vlist-10k | frame apply p50 | 0.00 | ms |
| vlist-10k | frame layout p50 | 30.85 | ms |
| vlist-10k | frame paint p50 | 233.36 | ms |
| vlist-10k | frame raster p50 | 4.68 | ms |
| vlist-10k | frame total p50 | 270.55 | ms |
| vlist-10k | frame total p95 | 276.11 | ms |
| vlist-10k | visible children | 30 | nodes |
| vlist-10k | scene ops/frame | 20002 | ops |
| vlist-50k | mount patch apply | 53034.46 | ms |
| vlist-50k | mount layout | 178.49 | ms |
| vlist-50k | mount paint | 17993.98 | ms |
| vlist-50k | mount raster | 10.38 | ms |
| vlist-50k | frame apply p50 | 0.00 | ms |
| vlist-50k | frame layout p50 | 190.62 | ms |
| vlist-50k | frame paint p50 | 17118.13 | ms |
| vlist-50k | frame raster p50 | 23.54 | ms |
| vlist-50k | frame total p50 | 17321.22 | ms |
| vlist-50k | frame total p95 | 18549.73 | ms |
| vlist-50k | visible children | 30 | nodes |
| vlist-50k | scene ops/frame | 100002 | ops |
| vlist-100k | mount patch apply | 305850.52 | ms |
| vlist-100k | mount layout | 379.80 | ms |
| vlist-100k | mount paint | 133357.70 | ms |
| vlist-100k | mount raster | 18.77 | ms |
| vlist-100k | frame apply p50 | 0.00 | ms |
| vlist-100k | frame layout p50 | 407.95 | ms |
| vlist-100k | frame paint p50 | 131374.39 | ms |
| vlist-100k | frame raster p50 | 42.56 | ms |
| vlist-100k | frame total p50 | 131792.48 | ms |
| vlist-100k | frame total p95 | 135095.22 | ms |
| vlist-100k | visible children | 30 | nodes |
| vlist-100k | scene ops/frame | 200002 | ops |
| damage-5k | mount patch apply | 98.08 | ms |
| damage-5k | mount layout | 14.90 | ms |
| damage-5k | mount paint | 46.83 | ms |
| damage-5k | mount raster | 2.59 | ms |
| damage-5k | flip apply p50 | 0.00 | ms |
| damage-5k | damaged raster p50 | 0.86 | ms |
| damage-5k | full raster p50 | 4.35 | ms |
| damage-5k | damaged rects | 1.00 | rects |
| text-500 | patch apply | 0.78 | ms |
| text-500 | layout+measure | 1.11 | ms |
| text-500 | paint+shape | 3.58 | ms |
| text-500 | raster+blit | 3.78 | ms |
| text-500 | glyphs | 25890 | glyphs |
| text-500 | scene ops | 500 | ops |
| first-frame-10k | patch apply | 676.13 | ms |
| first-frame-10k | layout | 36.61 | ms |
| first-frame-10k | paint | 246.70 | ms |
| first-frame-10k | raster | 2.17 | ms |
| first-frame-10k | total | 963.46 | ms |
| rss-100k | RSS before apply | 50.2 | MiB |
| rss-100k | patch apply | 290961.36 | ms |
| rss-100k | RSS after apply | 110.0 | MiB |
| rss-100k | apply delta | 59.8 | MiB |
| rss-100k | RSS after first frame | 510.6 | MiB |

## What is unexpectedly slow, and why

Two stages are super-linear; everything else is roughly linear in
mounted children. These are measured facts and code-level root causes —
reported, not silently optimized (the spec caps changes to this
directory; both fixes belong upstream).

**Patch apply is ~O(n^2.8) in sibling count.**
`Lui_store.insert_child` runs a full `List.filter` over the parent's
children plus an `insert_at` walk for every `InsertChild`, so mounting
n children ascending costs O(n²) list traversals — and every traversal
rebuilds the spine, so GC pressure pushes the measured exponent to
~2.8 (5k→0.11s, 10k→0.62s, 20k→4.5s, 40k→33s, 50k→53s, 100k→306s).
An array-backed or tail-registered child list would restore linear
apply; small incremental patches (a prop flip: 0.00ms) are already
free.

**Paint is ~O(n^2.7) in container fan-out.**
`Lui_paint.default_chrome` computes `last_sibling` for every node by
`List.rev (Lui_store.child_ids parent)` — an O(fan-out) walk per
child — so a 100k-child container paints 100k × 100k list walks:
10k→0.23s/frame, 50k→17.1s, 100k→131s per frame. The check only needs
the parent's last child id once per parent — hoisting it (or caching
a last-child pointer in the store) should return paint to ~linear.
Paint also emits an op for every mounted child regardless of the
viewport (`visible children` stays 30 while `scene ops/frame` is
200002 at 100k): emission is correct-but-unclipped, so the quadratic
walk is paid on all of them.

**Layout and raster are ~linear** (layout p50: 31→191→408ms,
raster p50: 4.7→23.5→42.6ms across 10k/50k/100k) — healthy at these
sizes. Layout still re-syncs the whole flex tree every scroll frame;
at 100k that is 0.4s/frame even though no store node changed.

**Damage-limited raster does its job:** one color flip inside a 5k
tree damages exactly 1 rect and rasters in 0.86ms vs 4.35ms for a
full pass. The win grows with scene size.

**Memory:** ~0.6KB/node in the store (50→110 MiB across a 100k
patch), then ~4.5KB/node total after the first frame (510.6 MiB)
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
