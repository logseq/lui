---
name: testing-lui-demos
description: How to run and test LUI demo apps — the standalone web demos in platform/web/demo and the native macOS demo apps under examples/ — including macOS keyboard-shortcut and accessibility quirks.
---

# Testing LUI demos

## Web demo (platform/web/demo/*.html)

Self-contained pages that load `../src/lui-*.js` + `.css`. Open directly via
`file://` — no server needed:

    open -a "Google Chrome" "file:///Users/devin/repos/lui/platform/web/demo/<demo>.html"

The demo host (`LUISplit.mount`) renders a plain-object tree and *echoes every
emitted event into the header `#log` element* — read it to verify which event
fired even when the local `apply()` doesn't mutate the layout.

Gotchas discovered while testing lui-split:

- `mount()`'s `emit()` calls `redraw()` unconditionally — every `pane-focused`
  emit on pointerdown re-renders the DOM mid-gesture, so clicks on tab chips
  can be eaten before `click` dispatches. If clicks don't register, suspect
  this redraw, not aim.
- HTML5 drag-and-drop works with synthesized mouse drags (mouse down, move in
  ~4-6 steps, screenshot while held, release). Drop only lands on elements with
  a `dragover` handler that calls `preventDefault` — empty strip space rejects
  the drop.
- Keyboard shortcuts only fire while a `.lui-split-pane` has DOM focus, and
  any pointerdown kills focus (see above) — use the **Tab key** to focus a pane
  instead of clicking. Each keypress that emits an event redraws and drops
  focus again, so re-Tab before every shortcut.
- **macOS Option+letter produces a special character** (Option+D = ∂), so
  `event.key === 'd'` style checks never match — test ⌘⌥/Ctrl+Alt+letter
  shortcuts on macOS with suspicion; Ctrl+Alt+arrows are fine (arrows have no
  character mapping). Prefer Ctrl over Cmd in Chrome (Cmd+W/Cmd+Alt+arrows are
  browser shortcuts). Even after adding `KeyEquivalent("∂")`/event.code
  handlers, verify empirically — ⌥⌘D is also the system "Dock autohide"
  shortcut (check `defaults read com.apple.dock autohide` before/after).
- Structural redraws (split/close) drop DOM focus even when restore logic
  exists — the keypress right after a split may be dead. Press Tab to refocus
  a pane between keyboard assertions, and verify each shortcut by the #log
  text, not just by layout.

## Web gallery demo (examples/components/web)

The shared OCaml gallery (`examples/gallery`) rendered by the pure
OCaml/Melange web backend (`platform/web/melange/`).

Run it:

    cd ~/repos/lui && opam exec --switch=default -- dune build
    cd platform/web && npm run build        # emits dist/lui.css
    cd ~/repos/lui && node tooling/serve_web.mjs --port 8977
    open http://127.0.0.1:8977/examples/components/web/index.html

Notes:

- The shell defaults to `data-lui-form-factor="phone"` — a compact
  one-page list→detail→back shell. The simulator toolbar (top-right, or
  bottom edge under ~720px) has Platform/Device/Rotate controls; switch
  Device to "Tablet" for the two-pane sidebar+content layout. Viewport
  width alone does NOT change the shell mode.
- The managed/headless Chrome's windows never paint; for visual testing
  launch a separate visible instance:
  `open -na "Google Chrome" --args --remote-debugging-port=9222 --user-data-dir=/tmp/lui-web-chrome <url>`
  then drive it with Playwright `chromium.connectOverCDP('http://127.0.0.1:9222')`
  (playwright is in platform/web/node_modules; import via absolute
  `file://` path when the script lives outside that tree). CDP is also
  the way to read console errors — the computer-tool browser target may
  be unavailable.
- Known failure modes seen on the melange port (2025-09): popups live in
  `.lui-popup-portal` which is `pointer-events:none`; anything without a
  `pointer-events:auto` re-enable (modals — `.lui-modal-layer`/`.lui-dialog`)
  is click-through even though it renders correctly, and Escape still works.
  Transient menus can dismiss on their own `mousedown` before `click`
  dispatches — check with `page.mouse.click`, not `dispatchEvent`, and
  instrument `data-open` between `mouse.down()`/`mouse.up()` to prove it.
  `Invalid_argument "unknown node"` from `store.children` (called by
  `update_splits_under` during `Lui_web.mount`) leaves a section
  half-mounted: content swaps but `data-lui-navigation` stays "list" and
  `data-selected` stays "false".

## Native macOS demo app (examples/split)

Build/run: `bash examples/split/macos-appkit/build-app.sh`, then the bundle is
at `examples/split/macos-appkit/.build/debug/LUISplitDemo.app`. Quit/relaunch
for a clean state: `osascript -e 'quit app "LUISplitDemo"'` then `open -a <app>`.
The process/app name is `LUISplitDemo` but the accessibility name is
`LUI Split` — query it with `computer query target=macos app="LUI Split"`.

Gotchas:

- Tab chips merge their children into one AX element
  (`accessibilityElement(children: .combine)`), so the per-tab × button is NOT
  in the accessibility tree — click it by coordinates or press it via the
  chip's combined element.
- A blue ring around a pane marks the model's `focused` pane.
- onKeyPress letter equivalents (e.g. `KeyEquivalent("d")`) don't match
  Option-modified keys on macOS (∂ again) — ⌘\ works, ⌘⌥D may not.
- Arrow key events carry an implicit `.function` modifier; handlers that check
  `press.modifiers == [.command, .option]` (strict equality) never fire for
  arrows — `.contains` is required.
- Drag drops land on three distinct targets with different code paths: tab
  chips (insert-at-index), pane edges (split-drop, outer 25% clamped
  [48,160]pt — the strip row itself counts as the *top edge* zone, so
  "drop onto the strip" can split instead of move), and pane body center
  (append move). Verify each path separately — a pass on one does not
  prove the others.
- Beware large-int sentinel values in event payloads: the JSON bridge's
  OCaml parser only accepts ints < 2^62 (`lui_json.ml` guard), so a
  `.int(Int.max)` "append" sentinel decodes as a Float and the whole event
  can silently fail to decode. If a drop emits but nothing happens, check
  the payload magnitudes.
- Model focus (border ring) and real SwiftUI key focus (`hasKeyFocus`) can
  diverge — `navigate` moves the border but keys may still hit the
  previously-clicked pane. After navigating, verify a subsequent shortcut
  acts on the navigated-to pane, not the previously focused one.
- To verify split/insert animations in a recording: record at 60fps (the
  spring is ~250ms), then extract frames with ffmpeg around the moment —
  `recording_stop` writes a `*-annotations.json` next to the video whose
  `edited_time_s` values map annotation/action timestamps into the
  exported video's timeline.
- Window positioning via System Events: batching
  `set {size, position} of window 1 to {...}` fails with -10003; set
  `position` and `size` in two separate commands.
- Synthesized drags need real gesture timing: `left_click_drag` can commit
  edge drops, but chip/strip targets are more reliable with an explicit
  `left_mouse_down` → several `mouse_move` steps → pause (`wait` ~0.7s,
  pane highlight/ghost visible) → `left_mouse_up` sequence.

### Exercising new/ordinary element kinds end-to-end

The split demo is the fastest vehicle even for non-split elements: scratch-edit
`examples/split/model.ml` + `view.ml` (uncommitted) so `view` returns a plain
`column` of the elements under test, add model fields/actions for any state you
need to observe (e.g. a press counter rendered via `dyn`/`text` so event
delivery is proven by an OCaml-rendered value, not just pixels), then rerun
`build-app.sh` — it rebuilds `liblui_split.dylib` and the bundle. Revert with
`git checkout` afterwards. `if_ ~test:(model_source >|= ...)` is the way to
mount/unmount presence-driven kinds (dialog/sheet/file-preview).

QuickLook panels (`file-preview`, `.quickLookPreview`) on macOS: the panel's
close affordance is small/hover-only; **Escape** reliably closes it and drives
the Dismiss binding. Clicking the panel title bar does nothing.
