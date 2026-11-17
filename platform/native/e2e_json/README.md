# e2e_json — JSON scenario e2e tests for the native backend

Writing an e2e test is dropping a `*.json` file into `scenarios/`.
`test/e2e_json_test.exe` runs every file as one alcotest case, driven
by `E2e_json_scenario` through the same headless harness
(`Lui_e2e.E2e_harness` + `Lui_window.Ui`) the handwritten suites use.

## Scenario shape

```json
{
  "name": "my-test",
  "app": "e2e",            // optional: mount a registered app
  "width": 320, "height": 240, "scale": 1.0,
  "steps": [ /* ... */ ]
}
```

`"app"` mounts a built-in app from `E2e_json_apps` (`"e2e"`: the todo
list app; `"menu"`: textarea + menu-button + context-menu). Without an
app, `{"apply": ...}` steps drive the store/scene directly and
`{"dispatch": ...}` steps are unavailable.

Every step is a single-key object:

### Actions

- `{"apply": {"generation": N, "ops": [...]}}` — patch batch, wire op
  spellings (`create-node`, `create-extension`, `drop-node`,
  `detach-subtree`, `set-prop`, `remove-prop`, `set-extension-prop`,
  `remove-extension-prop`, `insert-child`, `remove-child`,
  `move-child`). Kind/property names are the wire names.
- `{"click": ref}` / `{"right-click": ref}` / `{"double-click": ref}` —
  pointer click at the node's center; `{"node": ref, "mods": [...]}`
  for modifier clicks.
- `{"hover": ref}` / `{"drag": {"from": ref, "to": ref | {"x","y"}}}`
- `{"input": "text"}` — text input to the focused node.
- `{"key": "return"}` or `{"key": {"key": "return", "mods": ["shift"],
  "repeat": false}}` — keys: return, escape, backspace, delete, tab,
  space, arrows, home, end, page-up/down.
- `{"ime": {"mark": {"text","start","len"} | "commit": s | "caret":
  {"x","y","w","h"}}}` — composition/commit/caret.
- `{"scroll": {"node": ref, "dx": f, "dy": f, "mods": [...]}}` —
  wheel at node center.
- `{"scroll-to" | "scroll-by": {"node": ref, "x"|"y": v}}`
- `{"drop": {"file": path} | {"text": s}}` / `{"paste": s}`
- `{"dispatch": {"kind": "press", "node": ref, ...}}` — inject a
  protocol event into the mounted app (all `Lui_protocol.event` kinds:
  press, long-press, double-press, text-changed, submit,
  toggle-changed, change, value-changed, dismiss, appear,
  scroll-completed, visible-range, picked, press-modifiers,
  press-detail, pointer-down/up/enter/leave, context-menu-press, load,
  extension-event).
- `{"app-dispose": true}` / `{"resize": {"width","height"}}` /
  `{"repaint": true}`

### Node refs

An integer id, `"lui-N"`, or `{"kind": wire-name, "text": s,
"index": i}` — the i-th node of that kind (optionally whose "text"
prop equals s).

### Assertions

- `{"expect-events": [...]}` — exact sequence match on events recorded
  since the last expect-events (or `"*"` to drain unchecked). Each
  element is subset-matched, so volatile fields (x, y) can be `("*"`.
- `{"expect-store": {...}}` — `node-count`, `generation`, `roots`,
  `absent` (refs that must not resolve to live nodes), `nodes` (per-
  node subset match: kind, parent, children refs, ext-id, props),
  `dirty` (drains; `"*"` drains unchecked).
- `{"expect-frame": {...}}` — `ops` (exact op-name list), `frames`,
  `bytes`, `wants-repaint`, `scene` (w/h/scale), `op-count` (per-name
  counts), `match` (ordered subsequence of op specs), `find` (each
  spec must match >=1 op; `"rect-of": ref` pins the op's rect to a
  node's layout rect).
- `{"expect-bounds": {"node": ref, "rect": {"x","y","w","h"} | "left",
  "top","right","bottom" | "absent": true}}`
- `{"expect-focused": ref | {"none": true}}`
- `{"expect-scroll": {"node": ref, "x","y": spec}}`
- `{"expect-marked": "text"}` / `{"expect-drop": {"target","payload"}}`
- `{"expect-hit": {"x","y","node"|"path": ref|[refs]}}`
- `{"expect-ui": {"hovered","pressed","focused","open-menu",
  "overlay-top": ref|null, "drag-active": bool, "marked": s}}`

### Subset matching (everywhere)

`"*"` accepts anything; `"~x"` = string contains x;
`{"$gt"|"$lt"|"$ge"|"$le": n}` compares numbers; objects match
recursively by subset; lists match positionally with equal length.
