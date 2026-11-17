# platform/native/latency — end-to-end latency benchmark (P0-4)

A headless benchmark that times one action through the *whole* frame
pipeline — not just layout or paint in isolation:

```
action dispatch
  -> Signal.stabilize        (reducer + view recompute -> queued ops)
  -> patch batch generated   (Lui_runtime.flush -> backend.apply_batch)
  -> backend applied         (Lui_store.apply_batch)
  -> layout done             (Lui_layout.sync)
  -> scene ready             (Lui_paint.paint -> Lui_scene ops)
  -> present submitted       (Lui_raster.Renderer.render + damage upload)
  -> frame presented         (swap; immediate headless, no vsync)
```

## Method

- One `Harness.t` per scenario owns a `Lui_host` (store + scene), a
  `Lui_layout` flex mirror, a `Lui_raster.Renderer`, and a standing
  "screen" framebuffer the damage upload blits into.
- App-driven scenarios run a real `Lui_app` (scheduler + runtime +
  reducer + `Lui_elements` view) against the harness `backend`, which
  stamps the batch at `apply_batch` entry and exit — "patch generated"
  and "backend applied" split inside one flush without touching the
  runtime.
- `Signal.stabilize` is driven explicitly before `Lui_app.flush` so
  the signal/render pass is timed separately from batch assembly;
  flush's internal stabilize then observes a settled graph — the same
  work split a driver sees when it flushes after dispatch.
- Present is the window driver's CPU rung: `Renderer.render` produces
  damaged rects, each rect's rows are copied into the standing
  framebuffer (what `Lui_blit.update_region` does into the SDL
  texture), and the swap returns immediately (no vsync headless).
- All timestamps are taken by the harness around public calls — no
  production instrumentation exists, so there is nothing to disable
  and zero overhead when the bench is not running.
- Determinism: stub text measure (8 px/byte, 16 px line), frame
  1280x800 @ scale 1, `~workers:1` raster, `Gc.full_major` before each
  scenario.

## Metrics

| metric | span |
|---|---|
| `action_to_patch` | action handed over -> batch in the backend's hands (signal stabilize + assemble) |
| `patch_to_layout` | batch generated -> layout done (store apply + flex sync) |
| `layout_to_scene` | layout done -> scene ops emitted (paint) |
| `scene_to_present` | scene ready -> raster + damage upload submitted |
| `dirty_to_present` | action -> frame presented (the number a user feels) |
| `signal_stabilize` | sub-span: action -> graph settled (reducer + view) |
| `patch_apply` | sub-span: batch -> store committed |
| `patch ops` | ops in the flushed batch (0 = no batch) |

## Scenarios

| scenario | what it stresses |
|---|---|
| `typing` | `TextChanged` per keystroke -> draft model -> field + summary patch |
| `toggle` | `ToggleChanged` -> checked prop patch |
| `hover` | `PointerEnter`/`PointerLeave` -> hovered model -> background patch + host-side hovered state |
| `blocks-10k-text` | one block's text edit inside a 10k `keyed` list |
| `blocks-10k-insert` | one row inserted mid-list inside the same 10k list |
| `vlist-100k-scroll` | wheel-equivalent scroll frame over a wire-mounted 100k virtual list (host-side offsets — no patch, the production model) |
| `collapse-expand` | 200-row subtree mount/unmount through `if_` |
| `ime-compose` | composition-cadence `TextChanged` updates (marked text reaches the app through the same event today) |

## Running it

```sh
opam exec -- dune build
_build/default/platform/native/latency/main.exe          # full sizes
_build/default/platform/native/latency/main.exe --small  # bounded sizes, ~1 s
opam exec -- dune runtest platform/native/latency        # alcotest bounds
```

`main.exe` prints the markdown table below
(`| scenario | metric | value | unit |`).

## Measured numbers (baseline)

Machine: Linux x86_64 (Xeon, 8 cores), OCaml 5.5.1, dune dev profile,
worktree at feat/ml-backend 4b9a1360.

| scenario | metric | value | unit |
|---|---|---|---|
| typing | mount e2e | 0.944 | ms |
| typing | action_to_patch p50 | 0.001 | ms |
| typing | action_to_patch p95 | 0.002 | ms |
| typing | patch_to_layout p50 | 0.012 | ms |
| typing | patch_to_layout p95 | 0.013 | ms |
| typing | layout_to_scene p50 | 0.003 | ms |
| typing | layout_to_scene p95 | 0.004 | ms |
| typing | scene_to_present p50 | 0.001 | ms |
| typing | scene_to_present p95 | 0.001 | ms |
| typing | dirty_to_present p50 | 0.017 | ms |
| typing | dirty_to_present p95 | 0.019 | ms |
| typing | signal_stabilize p50 | 0.001 | ms |
| typing | patch_apply p50 | 0.000 | ms |
| typing | patch ops p50 | 1.00 | ops |
| typing | iters | 60 | frames |
| toggle | mount e2e | 1.138 | ms |
| toggle | action_to_patch p50 | 0.001 | ms |
| toggle | action_to_patch p95 | 0.002 | ms |
| toggle | patch_to_layout p50 | 0.012 | ms |
| toggle | patch_to_layout p95 | 0.014 | ms |
| toggle | layout_to_scene p50 | 0.004 | ms |
| toggle | layout_to_scene p95 | 0.004 | ms |
| toggle | scene_to_present p50 | 0.001 | ms |
| toggle | scene_to_present p95 | 0.001 | ms |
| toggle | dirty_to_present p50 | 0.018 | ms |
| toggle | dirty_to_present p95 | 0.021 | ms |
| toggle | signal_stabilize p50 | 0.001 | ms |
| toggle | patch_apply p50 | 0.000 | ms |
| toggle | patch ops p50 | 2.00 | ops |
| toggle | iters | 60 | frames |
| hover | mount e2e | 1.296 | ms |
| hover | action_to_patch p50 | 0.001 | ms |
| hover | action_to_patch p95 | 0.001 | ms |
| hover | patch_to_layout p50 | 0.009 | ms |
| hover | patch_to_layout p95 | 0.011 | ms |
| hover | layout_to_scene p50 | 0.003 | ms |
| hover | layout_to_scene p95 | 0.003 | ms |
| hover | scene_to_present p50 | 0.065 | ms |
| hover | scene_to_present p95 | 0.078 | ms |
| hover | dirty_to_present p50 | 0.078 | ms |
| hover | dirty_to_present p95 | 0.093 | ms |
| hover | signal_stabilize p50 | 0.001 | ms |
| hover | patch_apply p50 | 0.000 | ms |
| hover | patch ops p50 | 1.00 | ops |
| hover | iters | 60 | frames |
| blocks-10k-text | mount e2e | 248.622 | ms |
| blocks-10k-text | action_to_patch p50 | 27.929 | ms |
| blocks-10k-text | action_to_patch p95 | 45.172 | ms |
| blocks-10k-text | patch_to_layout p50 | 114.951 | ms |
| blocks-10k-text | patch_to_layout p95 | 177.259 | ms |
| blocks-10k-text | layout_to_scene p50 | 9.568 | ms |
| blocks-10k-text | layout_to_scene p95 | 19.822 | ms |
| blocks-10k-text | scene_to_present p50 | 0.015 | ms |
| blocks-10k-text | scene_to_present p95 | 0.021 | ms |
| blocks-10k-text | dirty_to_present p50 | 155.096 | ms |
| blocks-10k-text | dirty_to_present p95 | 228.578 | ms |
| blocks-10k-text | signal_stabilize p50 | 27.927 | ms |
| blocks-10k-text | patch_apply p50 | 0.004 | ms |
| blocks-10k-text | patch ops p50 | 1.00 | ops |
| blocks-10k-text | iters | 30 | frames |
| blocks-10k-insert | action_to_patch p50 | 27.239 | ms |
| blocks-10k-insert | action_to_patch p95 | 35.268 | ms |
| blocks-10k-insert | patch_to_layout p50 | 110.769 | ms |
| blocks-10k-insert | patch_to_layout p95 | 125.553 | ms |
| blocks-10k-insert | layout_to_scene p50 | 8.676 | ms |
| blocks-10k-insert | layout_to_scene p95 | 10.701 | ms |
| blocks-10k-insert | scene_to_present p50 | 1.064 | ms |
| blocks-10k-insert | scene_to_present p95 | 1.131 | ms |
| blocks-10k-insert | dirty_to_present p50 | 147.577 | ms |
| blocks-10k-insert | dirty_to_present p95 | 168.552 | ms |
| blocks-10k-insert | signal_stabilize p50 | 27.223 | ms |
| blocks-10k-insert | patch_apply p50 | 0.026 | ms |
| blocks-10k-insert | patch ops p50 | 6.00 | ops |
| blocks-10k-insert | iters | 30 | frames |
| vlist-100k-scroll | mount patch apply | 217.416 | ms |
| vlist-100k-scroll | action_to_patch p50 | 0.000 | ms |
| vlist-100k-scroll | action_to_patch p95 | 0.000 | ms |
| vlist-100k-scroll | patch_to_layout p50 | 0.003 | ms |
| vlist-100k-scroll | patch_to_layout p95 | 0.004 | ms |
| vlist-100k-scroll | layout_to_scene p50 | 93.064 | ms |
| vlist-100k-scroll | layout_to_scene p95 | 115.146 | ms |
| vlist-100k-scroll | scene_to_present p50 | 3.889 | ms |
| vlist-100k-scroll | scene_to_present p95 | 4.460 | ms |
| vlist-100k-scroll | dirty_to_present p50 | 97.051 | ms |
| vlist-100k-scroll | dirty_to_present p95 | 119.347 | ms |
| vlist-100k-scroll | signal_stabilize p50 | 0.000 | ms |
| vlist-100k-scroll | patch_apply p50 | 0.000 | ms |
| vlist-100k-scroll | patch ops p50 | 0.00 | ops |
| vlist-100k-scroll | iters | 30 | frames |
| collapse-expand | mount e2e | 6.720 | ms |
| collapse-expand | action_to_patch p50 | 0.478 | ms |
| collapse-expand | action_to_patch p95 | 0.958 | ms |
| collapse-expand | patch_to_layout p50 | 1.154 | ms |
| collapse-expand | patch_to_layout p95 | 2.300 | ms |
| collapse-expand | layout_to_scene p50 | 0.192 | ms |
| collapse-expand | layout_to_scene p95 | 0.457 | ms |
| collapse-expand | scene_to_present p50 | 0.005 | ms |
| collapse-expand | scene_to_present p95 | 0.010 | ms |
| collapse-expand | dirty_to_present p50 | 2.015 | ms |
| collapse-expand | dirty_to_present p95 | 3.510 | ms |
| collapse-expand | signal_stabilize p50 | 0.470 | ms |
| collapse-expand | patch_apply p50 | 0.135 | ms |
| collapse-expand | patch ops p50 | 1404.00 | ops |
| collapse-expand | iters | 40 | frames |
| ime-compose | mount e2e | 2.929 | ms |
| ime-compose | action_to_patch p50 | 0.001 | ms |
| ime-compose | action_to_patch p95 | 0.002 | ms |
| ime-compose | patch_to_layout p50 | 0.012 | ms |
| ime-compose | patch_to_layout p95 | 0.013 | ms |
| ime-compose | layout_to_scene p50 | 0.003 | ms |
| ime-compose | layout_to_scene p95 | 0.004 | ms |
| ime-compose | scene_to_present p50 | 0.001 | ms |
| ime-compose | scene_to_present p95 | 0.001 | ms |
| ime-compose | dirty_to_present p50 | 0.017 | ms |
| ime-compose | dirty_to_present p95 | 0.018 | ms |
| ime-compose | signal_stabilize p50 | 0.001 | ms |
| ime-compose | patch_apply p50 | 0.000 | ms |
| ime-compose | patch ops p50 | 2.00 | ops |
| ime-compose | iters | 60 | frames |

## Where the latency goes

The per-stage split points at the same gaps the plan's other
milestones target; the baseline is recorded here so each can show its
delta end to end.

- **A single block edit in a 10k tree costs ~155 ms end to end**
  (p50), ~19x the 8 ms target. The breakdown: `signal_stabilize` 28 ms
  (the `keyed` reconcile walks the whole 10k-item source on one item
  change), `patch_to_layout` 115 ms (any `SetProp` bumps the store
  revision and the flex mirror rebuilds wholesale — P0-1's typed
  dirty flags + persistent layout tree), `layout_to_scene` 9.6 ms
  (paint walks every mounted node — P0-3's retained scene
  fragments). The patch itself is already minimal: 1 op, ~0 ms to
  apply.
- **A 100k virtual-list scroll frame costs ~97 ms** — essentially all
  in `layout_to_scene` (93 ms): paint culls to ~30 visible rows but
  *finds* them by walking all 100k mounted nodes (P0-2's real
  virtualization). Layout is already free on scroll frames (memoized
  on store revision) and the damage-limited raster + upload stays
  ~4 ms.
- **Small-tree interactions are already frame-cheap**: typing, toggle,
  and IME composition all land ~0.02 ms dirty_to_present; hover ~0.08
  ms (one damaged rect upload dominates). collapse-expand remounts
  200 rows (1.4k ops) in ~2 ms.
- **Targets from the plan**: 60 Hz p50 < 8 ms / p95 < 16 ms — met
  today by every scenario except the 10k-tree and 100k-list ones,
  which is exactly the gap the incremental milestones are for.

## Regression bounds

`dune runtest platform/native/latency` runs the same scenarios at
reduced sizes (`--small`: 24 tiny-tree frames, 2k blocks, 10k vlist,
80 collapse kids; ~1 s) and asserts:

- structural: every scenario emits the full metric set; action-driven
  scenarios emit real patches (>=1 op); a single text edit stays a
  small patch (<=8 ops); scroll frames emit no patch at all; frame
  stamps are monotone action -> presented.
- absolute ceilings, ~3x the small-suite values measured on the
  reference machine: tiny-tree dirty_to_present p50 < 1 ms, 2k
  edit/insert < 75 ms, 10k scroll < 75 ms, collapse < 30 ms (skipped
  on shared CI runners, whose wall clocks bounce).
