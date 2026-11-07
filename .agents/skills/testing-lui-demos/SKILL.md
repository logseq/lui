---
name: testing-lui-demos
description: How to run and test supported LUI Web demos — standalone pages in platform/web/demo and the Melange component gallery — including browser keyboard and focus quirks.
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
