# spike — tsdl substrate validation

Throwaway app proving the native-backend window/loop substrate end to end:
SDL2 window via tsdl, event loop (quit / resize / keyboard), an animated
CPU pixel buffer uploaded to a streaming texture every frame (no GL), SDF
rounded-rects via `Lui_scene.sd_round_rect`, and text rasterized by
tsdl-ttf blended into the framebuffer.

## Build & run

```
OPAMSWITCH=5.5.0 opam exec -- dune build platform/native/spike
OPAMSWITCH=5.5.0 opam exec -- dune exec platform/native/spike/spike.exe
OPAMSWITCH=5.5.0 opam exec -- dune runtest platform/native/spike   # unit tests, no SDL
```

Controls: **Esc/Q** quit, **Space** pause, **R** reset animation.
Args: `--frames N` (auto-quit), `--size WxH` (default 800x500),
`--no-ttf` (shapes only), `--headless`.

## Headless

```
SDL_VIDEODRIVER=dummy OPAMSWITCH=5.5.0 opam exec -- \
  dune exec platform/native/spike/spike.exe -- --headless --frames 60
```

Creates the window under the dummy video driver, renders N frames on a
fixed virtual clock, and prints a deterministic FNV-1a checksum of the
final framebuffer (stable across runs on this machine).

## Packages

- `tsdl` 1.3.0 — was NOT installed in the 5.5.0 switch; `opam install -y --assume-depexts tsdl`
- `tsdl-ttf` 0.7 — needed `brew install sdl2_ttf` first (`--assume-depexts`
  assumes system deps; `conf-sdl2-ttf` pkg-config check fails without it)
- system: `sdl2` (already present), `sdl2_ttf` 2.24.0

## Results (macOS arm64)

- Windowed: `metal` renderer, 800x500 out, ~40 fps, ~25 ms/frame — the
  per-pixel SDF raster is the bottleneck, not the upload/present path.
- Headless: `software` renderer, deterministic, e.g.
  `checksum=0x3d36299f7ed717cc` at `--frames 60`.

## Pitfalls found

- `(executable (name X))` needs a module named `x`; `spike.ml` is a
  one-line entry shim over `Spike_main.main`.
- Renderer *request* flags are hints: `accelerated + presentvsync`
  succeeds under the dummy driver but yields `software`, and
  `SDL_RENDERER_PRESENTVSYNC` shows set in `ri_flags` even though nothing
  paces the loop — inspect `Sdl.get_renderer_info` for the truth.
- `Sdl.update_texture`/`lock_texture` pitches are in bigarray *elements*,
  not bytes (int32 buffer → pitch = width).
- `get_renderer_output_size`/`get_renderer_info` return `result`; TTF
  `Error _` is just `Error (`Msg _)`.
- Framebuffer is logical 800x500 and `render_copy` stretches it to the
  full output — resize events are logged but need no texture recreation.
- Headless text must be a fixed string; wall-clock-refreshed labels break
  checksum determinism.
