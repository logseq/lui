# LUI native backend — self-drawn OCaml UI stack

A desktop UI backend for LUI written entirely in OCaml + C stubs. It renders
the LUI patch tree into pixels through a shared scene IR with interchangeable
CPU and GPU evaluators, and provides the app-facing surface a desktop shell
needs: windows, events, text, IME, accessibility, desktop-shell APIs,
packaging and self-update. It plugs into the existing `Lui_protocol.backend`
seam — the same patch batches that drive the other backends drive this one.

## Architecture

```
Lui_app ──patch_batch──▶ Lui_store ──▶ Lui_layout (Lui_flex) ──▶ Lui_paint
                                                               │
                                                Lui_scene.t ops (shared IR)
                                                               │
            ┌──────────────────┬───────────────┬───────────────┤
            ▼                  ▼               ▼               ▼
       Lui_raster (CPU)   Lui_gl (GL3)   Lui_metal (macOS)  Lui_d3d11 (Win)
            │                  │               │               │
            └─────── Lui_blit / SDL present / swapchain ───────┘
                                 (CPU-equivalent pixels: Lui_vulkan on Linux)
```

Every evaluator consumes the same `Lui_gpu` instance/batch encoding and the
same signed-distance coverage math, so CPU and GPU produce the same pixels.
The `platform/native/parity/` suite enforces this: 46 scenes, byte-exact or
within documented ±1/±2 tolerances.

## Renderer selection

| Platform | Order |
|---|---|
| macOS | Metal → GL → CPU |
| Windows | D3D11 → GL → CPU |
| Linux | GL → CPU (Vulkan offscreen available via `lui_vulkan`) |

`LUI_GPU=0` (or `cpu`) forces the CPU path: `Lui_raster` renders, `Lui_blit`
uploads only damaged rects to an SDL streaming texture. `LUI_GPU=gl` forces
GL on macOS. CPU is also the headless/test/screenshot path.

## Module map

Core pipeline:

| dir | role |
|---|---|
| `lui_scene` | display-list IR: ops, atlas, coverage + blur math |
| `lui_store` | retained mirror of `patch_batch` + dirty tracking |
| `lui_paint` | LUI node → scene ops; standard kinds + extension renderer registry |
| `lui_flex` / `lui_layout` | flexbox engine + store→flex mirror + wire-prop styles |
| `lui_host` | `Lui_protocol.backend` assembly (apply_batch → paint → pixels) |
| `lui_raster` | CPU evaluator + damage/dirty-rect + Domain multi-core bands |
| `lui_gpu` | scene → instance/batch compiler + embedded shader source |
| `lui_gl` / `lui_metal` / `lui_d3d11` / `lui_vulkan` | GPU frontends (same encoding/math) |
| `lui_blit` | SDL software present (full frame or damaged rows) |
| `lui_window` | macOS window host executable + interactive demo |
| `lui_window_linux` / `lui_window_windows` | sibling hosts for Linux/Windows |

Text / input / accessibility / shell:

| dir | role |
|---|---|
| `lui_text` | engine-agnostic text API; CoreText backend (shape, CJK/emoji, subpixel, RTL) |
| `lui_text_pango` / `lui_text_dwrite` | Linux Pango / Windows DirectWrite backends (same `.mli`) |
| `lui_ime` | IME composition state machine + SDL text-input wiring |
| `lui_a11y` | platform-neutral semantic tree (38 roles, names, states, diffs) |
| `lui_ax` / `lui_ax_linux` / `lui_ax_windows` | NSAccessibility / AT-SPI / UIA bridges |
| `lui_shell` / `lui_shell_linux` / `lui_shell_windows` | tray, menus, notify, clipboard, dialogs, open-url |
| `lui_image` | PNG/JPEG decode → premultiply → color atlas + fit modes |

Release chain + verification:

| dir | role |
|---|---|
| `lui_pkg` | .app bundle → codesign → notarize → DMG → bsdiff delta + CLI |
| `lui_pkg_linux` | AppDir → tar/deb/AppImage packaging on Linux |
| `lui_pkg_windows` | portable dir → zip/MSIX/NSIS packaging on Windows |
| `lui_updater` | update feed → delta-first download → staged apply → relaunch |
| `lui_cli` | `lui` developer CLI: init/dev/build/package/doctor/keygen |
| `parity` | CPU↔GPU pixel-parity suite (46 scenes + damage + corpus) |
| `e2e` | headless end-to-end pipeline tests (patch → pixels) |
| `lui_gallery` | all-85-kind visual suite → PNG cells + manifest |
| `coverage` | test-coverage audit + gaps ledger |

Plugins (JSON-in/JSON-out services under the `plugin:<name>` namespace):

| dir | role |
|---|---|
| `lui_plugin` | plugin registry: named services, setup/teardown, dispatch |
| `lui_plugin_fetch` | HTTP client plugin over dlopen'ed libcurl (`plugin:fetch`) |
| `lui_plugin_websocket` | WebSocket client plugin, pure OCaml RFC 6455 (`plugin:websocket`) |

## Build & test

```sh
OPAMSWITCH=5.5.0 opam exec -- dune build platform/native/
OPAMSWITCH=5.5.0 opam exec -- dune runtest platform/native/ --force
```

System deps (macOS): `brew install sdl2 sdl2_ttf`; opam: `tsdl tsdl-ttf tgls
alcotest imagelib`. Platform libs build everywhere — real implementations are
`#if defined(__APPLE__)/(__linux__)/(_WIN32)`; calls on the wrong platform
raise `Failure`. Tests that need a real device/API are `enabled_if`-gated.

## Run the demo

```sh
OPAMSWITCH=5.5.0 opam exec -- dune exec platform/native/lui_window/main.exe
```

Interactive window with five sections (inputs / controls / lists / overlays /
decorations), live FPS + renderer badge, tray icon, notifications, clipboard.
`--headless N` runs N deterministic frames and prints a scene checksum — the
same command is a regression test. Renderer selection can be inspected from
the log line (`renderer=lui_metal|lui_gl|lui_raster+blit`).
