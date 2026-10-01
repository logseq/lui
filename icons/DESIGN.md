# Logseq Icons — Design System

One icon system for Logseq, Logseq Chat, and Simple Journal.
Built after the process described in
[The Making of Cursor's Icons](https://www.minoradventures.co/blog/the-making-of-cursors-icons).

## Files

```
icons/
  16/            outline SVGs drawn on a 16px grid
    filled/      filled variants on the 16px grid
  24/            outline SVGs drawn on a 24px grid
    filled/      filled variants on the 24px grid
  metadata.json  per-icon tags, aliases, available sizes/styles
  tooling/build.py
  site/index.html  generated preview (open in a browser)
```

## Two sizes, drawn on separate grids

Each icon exists as two independently drawn SVGs, not one icon resized:

| size | grid | stroke | use |
|------|------|--------|-----|
| 16px | 16×16, 1px units | 1.25px | the workhorse; legible rendered 12–20px |
| 24px | 24×24, 1px units | 1.5px | rendered ≥22px: nav, empty states, feature spots |

The 24px version is redrawn on its own grid — shapes re-measured to fit the
bigger canvas rather than scaled 1.5×.

## Two styles

- **Outline** — the default. `fill="none"`, `stroke="currentColor"`,
  `stroke-width` 1.25 (16px) or 1.5 (24px), `stroke-linecap="round"`,
  `stroke-linejoin="round"`. Renders in the surrounding text color.
- **Filled** — `fill="currentColor"`, interior detail knocked out with
  `fill-rule="evenodd"`. Used sparingly where state or emphasis needs weight:
  task states, playback (play/pause), selection (check-circle), status dots,
  star.

## Geometry rules

### Optical shapes, not math shapes

Four base shapes sized to *read* as equal, centered on a shared focus point
— not four shapes with identical bounding boxes:

| shape | 16px bounds | 24px bounds |
|-------|-------------|-------------|
| Square | 2.5–13.5 (11px) | 4–20 (16px) |
| Circle | 2–14 Ø12 | 3.5–20.5 Ø17 |
| Horizontal bar | full width, ≤11 tall | full width, ≤16 tall |
| Vertical bar | ≤11 wide, full height | ≤16 wide, full height |

Circles overflow the square bounds slightly — a circle at the same width as
a square looks smaller.

### Construction

- Every path is built from horizontal, vertical, and 45° diagonal segments,
  then corners are rounded. No freeform bezier curves — curves live inside
  circles, arcs, and `rx` on rects.
- Closed shapes over open ones wherever possible.
- Lines extend past the shape they touch (the mono/staff-line aesthetic):
  a checkmark's long arm crosses through, list lines run edge to edge.
- Diagonals run bottom-left → top-right; slashing diagonals run the opposite
  direction (top-left → bottom-right).
- ≥3 grid units of empty space between overlapping shapes; use optical
  breaks at junctions rather than letting strokes collide.
- Natural proportions — a lock body is wider than its shackle, a page is
  taller than wide. Don't stretch a shape to fill the canvas.
- Grid-unit alignment: coordinates land on whole or half grid units so
  strokes stay sharp on 1× displays. Stroke-centered edges fall on .5
  values (1.25 stroke → x.375/.625 edges are avoided where it blurs;
  dominant edges sit on whole pixels).

### Recurring elements

- **Task states**: a 6.25px circle carrying a fraction — open ring
  (todo), quarter wedge (doing), dashed ring (backlog), X through ring
  (canceled), check through ring (done), clock hands (review). The circle
  is the constant; the interior tells the state.
- **Arrows**: 45° arrowheads, shaft length a multiple of the grid.
- **Document page**: 8.5px-wide rect with a folded corner, used by
  `file`, `file-text`, `save`.
- **Outliner**: `bullet` is the unit — a solid dot that reads at 1×.

## Naming and metadata

- Names are `kebab-case` concept names, not visual names:
  `task-doing` not `circle-quarter`, `search` not `magnifying-glass`.
- `metadata.json` carries `tags` (search terms) and `aliases` — the names
  each product already calls the concept (`navigation-back` → `arrow-left`,
  `toolbar-copy-url` → `link`, `graph-remote` → `cloud`,
  `xmark.circle.fill` → filled `x-circle`). Products adopt the set by
  resolving their existing names through aliases, so no consumer rename is
  required.

## Tooling

`python3 tooling/build.py` — collects `16/` and `24/` (+ `filled/`),
validates stroke width, fill mode, and round caps per the rules above,
merges `metadata.json`, and regenerates `site/index.html` — a
self-contained preview with search (names, tags, aliases), size and style
switches, and 1×/2×/3× zoom for pixel review.

## Adding an icon

1. Draw the 16px outline version on the rules above — start from the
   nearest existing icon and reuse its shapes.
2. Redraw at 24px on its own grid.
3. Add a filled variant only if a state truly needs it.
4. Add its entry to `metadata.json` with tags and product aliases.
5. Run `python3 tooling/build.py` and check it at 1× in `site/index.html`.
