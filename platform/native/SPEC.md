# LUI native self-drawn backend — SPEC

Self-drawn UI backend for LUI in pure OCaml: the app core, the display
list, the paint pass and both renderers all live in one OCaml process —
no external UI toolkit, no Rust, no Go.

## Architecture

```
LUI patch_batch (typed, in-process)
  → lui_store      retained node mirror
  → lui_flex       flexbox layout (vendored Yoga port, OCaml 5)
  → lui_text       platform text shaping → glyph bitmaps → scene atlas
  → lui_paint      LUI kind + props → scene ops (incl. extension renderers)
  → Lui_scene      display list IR  (platform/native/lui_scene — DONE)
  → renderers
      lui_raster   CPU evaluator, premultiplied BGRA (Domain-parallel rows)
      lui_gl       GPU evaluator: lui_gpu_builder → instances → tgls GL3
  → lui_host       tsdl window/event loop, dirty → repaint → present
```

CPU and GPU renderers evaluate the same `Lui_scene` and must produce
identical pixels. `LUI_GPU=0` forces CPU; CPU is also the headless/test
path and the screenshot path.

## Module ownership (one dir per worker, touch nothing else)

| dir | contents | notes |
|---|---|---|
| `platform/native/lui_scene` | display list IR: ops, atlas, coverage + blur math | DONE — the shared contract |
| `platform/native/lui_raster` | CPU evaluator + damage/merge + Domain row teams | signed-distance coverage identical to the shader |
| `platform/native/lui_gpu` | op → instance/batch compiler + `shader.glsl` | pure OCaml, no GL calls |
| `platform/native/lui_gl` | tgls GL3 renderer consuming lui_gpu output | shader = lui_gpu/shader.glsl verbatim |
| `platform/native/lui_text` | text engine: shape → runs+metrics, rasterize → atlas | engine-agnostic API; CoreText backend first |
| `platform/native/lui_flex` | vendored flexbox layout | must build on OCaml 5.5.0 |
| `platform/native/lui_store` | retained mirror of patch_batch | consumes `Lui_protocol.patch_op` |
| `platform/native/lui_paint` | LUI node → scene ops | standard kinds + extension renderer registry |
| `platform/native/lui_host` | tsdl window + event loop + backend glue | implements `Lui_protocol.backend` |
| `platform/native/spike` | throwaway validation app | proves tsdl end-to-end |
| `platform/native/test` | cross-module tests (pixel parity, e2e) | |

## Rules (hard)

- Branch `feat/ml-backend`. Work only in your assigned dir. `git pull --rebase`
  before every push; never force-push, never touch other modules' files or
  existing files outside your dir.
- Never name the reference implementation or any other UI toolkit in
  committed files — code, comments, docs and commit messages describe
  this code on its own terms only.
- AGENTS.md: never disable compiler warnings, never `Obj.magic`, never modify
  an existing dune file — creating NEW dune files inside your own new
  directory is required and allowed. Code comments in English.
- Build with `OPAMSWITCH=5.5.0 opam exec -- dune build`. If a needed opam
  package is missing: `opam install -y --assume-depexts <pkg>`.
- Keep ported math byte-faithful (float64 math is fine; GPU packs to
  float32 at the boundary). Do not redesign — port first, optimize later.
- Every module ships: `dune` file + `<name>.ml` (+ `.mli` where it pins the
  contract) + `test/` unit tests via alcotest. `dune build` AND
  `dune runtest` must be green for your dir before you push.
- Pixel-parity tests compare renderers on the same scene; write golden data
  into `test/golden/` (generated fixtures may be committed).

## Scene contract (lui_scene.ml — read it, don't duplicate)

Ops: `Fill | Shadow | Glyphs | Image | Push_clip | Pop_clip | Effect | Hole`.
All geometry float device px. `corners`/`fit_radii`/`inner_radii` give fitted
radii (negative = continuous). `Atlas.t` packs glyph masks (bpp 1) and color
glyphs (bpp 4). `text_coverage`/`subpixel_coverage`/`gamma_ratios` are the
text corrections — reuse verbatim. `backdrop_of`/`blur_weight`/
`backdrop_sample`/`sd_round_rect` are the shared blur/SDF math.

## Test coverage

- raster: every op kind rasterized vs golden pixels; corner SDF incl.
  continuous; damage rect union/intersect/merge; multicore == singlecore output
- atlas: alloc/grow/repack/reset_transient/changes-version tracking
- gpu builder: ops → correct instance packing + batch splitting (scissor /
  clip / effect / hole ordering), clip stack semantics
- text: shape → positioned glyphs + metrics; atlas upload; subpixel coverage;
  measure width/height; CJK + emoji shaping (macOS)
- store: every patch_op applied; invalid ops rejected per lui_protocol rules
- paint: each standard kind maps to expected ops; extension renderer dispatch
- parity: same scene through raster and gl builders → same coverage decisions
- host/e2e: boot window headless (SDL_VIDEODRIVER=dummy or offscreen),
  apply patch batches, screenshot checksums
