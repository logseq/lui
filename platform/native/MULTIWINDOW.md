# Multi-window + multi-monitor support

Status: **macOS driver implemented** (`lui_window`). Windows and Linux
share the pure `Lui_window.Multi` registry today and carry the design
notes below; their drivers port the same recipe when scheduled.

## Window model (decision)

Each top-level OS window is an **independent surface**: its own
`Lui_host` (store, layout engine, scene, renderer), `Lui_app`,
`Ui` interaction state, `Rects` hit-test mirror, a11y tree, checksum
and stats. A registry maps the OS window id → surface.

Alternatives considered and why they lost:

- **One store rendered into several windows.** `Lui_host` fuses
  store + layout + scene into one paint pipeline; a shared store would
  need a scene fan-out inside `Lui_host` (new engine/core API), and
  hit-testing, IME, a11y and checksums are all per-surface anyway.
- **A wire-level `window` node kind.** `Lui_protocol.node_kind` has no
  window kind; adding one changes the shared schema and every
  consumer. Overlay/dialog/drawer already cover in-window layers.

Independent surfaces are the least invasive: zero core changes,
per-window checksums/a11y/IME for free, clean per-window teardown, and
each window can host a different view — the desktop semantic. The cost
(no live views of one model across windows) is acceptable for this
backend; a shared-model document app would add a sync layer on top.

## Layers

- **Pure** — `Lui_window.Multi` (`platform/native/lui_window`): the
  `'d t` registry, `'d surface` (id, host, ui, rects, driver payload,
  logical size, drawable size, scale cell, last display index), and
  `dispatch`, `apply_logical_size`, `apply_drawable`, `drawable_scale`,
  `scale`, `set_focused`/`focused`/`find_focused`, `first`/`last`/`any`.
  SDL-free and unit-tested under `dune runtest`.
- **Driver (macOS)** — `lui_window/main.ml`: `open_window` builds one
  surface end-to-end (SDL window → Metal/GL/CPU/noop ladder → host +
  hooks + app + a11y), registers it under `SDL_GetWindowID`;
  `close_window`, `focus_window` (`SDL_RaiseWindow` + registry focus);
  `drain_events` routes every SDL event by its windowID to that
  window's `Ui.handle`; `tick` runs each window's frame;
  `refresh_scale` re-queries drawable size on `Moved`/display events
  and re-lays out via `Multi.apply_drawable`.

## Event routing

| SDL event | Route |
| --- | --- |
| key / text / editing | its `*_window_id` |
| mouse motion / buttons / wheel | its `*_window_id` |
| drop (file/text/begin/complete) | its `drop_window_id` |
| `WINDOWEVENT` resized/moved/close/focus | its `window_window_id` |
| `DISPLAYEVENT` (hotplug/mode) | all windows: re-query scale |
| `QUIT`, menu items, unknown-source | focused window (first if none) |
| `SDL_RENDER_TARGETS_RESET` / `DEVICE_RESET` (0x2000/0x2001) | all windows — the GPU device is shared |

A renderer demote recreates the OS window (a rung change needs
different creation flags), which mints a fresh windowID —
`Multi.rekey` moves the surface's registry key while keeping order,
focus and routing intact.

IME is process-global: text input stays on while **any** window holds
a field; the candidate window anchors on the focused window's caret
rect (`focused_field`).

## Multi-monitor / DPI

- Display hotplug (`SDL_DISPLAYEVENT_*`) → `refresh_scale` on every
  window: re-reads `gl_get_drawable_size` + `get_window_display_index`;
  `Multi.apply_drawable` recomputes `scale = drawable/logical`
  (clamped ≥ 0.01), pushes it into `Ui`, resizes the host and marks
  dirty — a no-op when nothing changed, so the blanket refresh is
  cheap.
- `SDL_WINDOWEVENT_MOVED` → same re-query for that window (the
  crossing-monitor case — its backing scale may have changed even
  though its logical size didn't).
- `Resized`/`Size_changed` → logical size stored on the surface, then
  the usual `Resize` → `Resize_host` → drawable-apply chain.

## API

| Call | Where | Semantics |
| --- | --- | --- |
| `open_window ~title ~idx` | `main.ml` | build + register a surface; returns it |
| `close_window id` | `main.ml` | dispose app, delete GL ctx/Metal, destroy, unregister; quit on last close |
| `focus_window id` | `main.ml` | `SDL_RaiseWindow` + registry focus |
| scale query | `Multi.scale s` / `Option.map Multi.scale (Multi.find windows id)` | current backing scale |
| per-window headless | `main.exe --headless N --windows M` | M surfaces under the dummy driver; per-window `win=i done: frames=… checksum=…` |

`--windows N` (1–8) opens N surfaces; window 0 keeps the single-window
defaults (autofocus, `--drop-file` injection, identical checksums);
extra windows open on a different demo tab (deterministic cycling)
and, headless, receive a Tab at frame 1 so the routing path diverges
their scene — proving per-window input.

## Windows (`lui_window_windows`) — TODO

The driver is pure Win32 (no SDL). Port:

- Registry: `HWND` → surface map (same `Multi.t` keyed by the HWND's
  `IntPtr` bits → int64/int).
- Routing: `WndProc` already receives the HWND — dispatch input there
  exactly as now, per surface.
- Per-window host/renderer: the current single-window init becomes
  `open_window`; each window gets its own swap chain / raster target.
- DPI: `WM_DPICHANGED` carries the suggested rect + new DPI — feed
  `apply_logical_size` + `apply_drawable` (scale = dpi/96, or
  drawable/logical like macOS); `WM_DISPLAYCHANGE` → refresh all.
- Focus: `WM_SETFOCUS`/`WM_KILLFOCUS` → `set_focused`/`clear_focus`;
  `WM_ACTIVATE` ≈ `Take_focus` → `SetForegroundWindow` + focus.
- Close: `WM_CLOSE`/`WM_DESTROY` → unregister + teardown; `PostQuitMessage`
  when the registry empties.

## Linux (`lui_window_linux`) — TODO

Same SDL recipe as macOS (it mirrors the SDL driver): the
`open_window`/`close_window`/`focus_window`/`refresh_scale` port is
near-mechanical — swap the renderer ladder entries (GL → Vulkan → CPU
per the existing ladder), keep `--windows N` parsing and the headless
dummy-driver tests. Watch out: X11 fractional scaling means the
drawable/logical ratio is the reliable scale source (as on macOS);
`xrandr` display events arrive as SDL display events.
