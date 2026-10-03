# Logseq Icons — Design System

One icon system for Logseq, Logseq Chat, and Simple Journal.
Built after the process described in
[The Making of Cursor's Icons](https://www.minoradventures.co/blog/the-making-of-cursors-icons),
and produced with [`tu`](https://github.com/logseq/tu) — every icon is
authored as a `.tu` scene (LUI wire vocabulary) and compiled to SVG by
`tu emit`.

## Files

```
icons/
  scenes/          .tu scene sources (canonical authoring format)
    16/  24/  filled/ per size
  16/              emitted outline SVGs, 16px grid
    filled/        filled variants
  24/              emitted outline SVGs, 24px grid
    filled/
  metadata.json    per-icon tags, aliases, available sizes/styles
  tooling/generate.py   authors scenes (generic icons derive Lucide
                   geometry; Logseq-specific glyphs are hand-authored),
                   then emits all SVGs via tu
  tooling/build.py --emit re-emits SVGs from scenes; then validates
                   and regenerates site/index.html
  site/index.html  generated preview (open in a browser)
```

## Two sizes, two grids

| size | grid | stroke | use |
|------|------|--------|-----|
| 16px | 16×16 | 1.5px | UI workhorse; legible 12–20px |
| 24px | 24×24 | 2px | ≥22px: nav, empty states |

The 16px set is derived from 24px-grid geometry scaled ×2/3 with the
stroke held proportionally heavier (1.5 vs 1.33 nominal) so small-size
rendering stays bold and readable — the same trade the Cursor post makes
between its two grids.

## Two styles

- **Outline** — `fill="none"`, `stroke="currentColor"`, round caps/joins.
- **Filled** — `fill="currentColor"`, interior detail knocked out with
  `fill-rule="evenodd"`. Only where state needs weight: task states,
  playback (play/pause), check-circle/x-circle, status dots, star.

## Geometry rules

- Optical shapes: circles overflow square bounds slightly; bars run the
  full keyline.
- Horizontal, vertical, and 45°-diagonal segments; corners rounded via
  `stroke-linejoin="round"`, `rx`, or arcs — no freeform curves.
- Closed shapes over open; ≥3 grid units between overlapping shapes;
  diagonals run bottom-left → top-right.
- Recurring elements: task states are a constant circle carrying a
  fraction (ring / quarter wedge / dashed ring / X / check / clock
  hands); `bullet` is the outliner unit.

## Provenance

Generic icons derive their geometry from [Lucide](https://lucide.dev)
(ISC license) — proven, consistent, round-capped geometry — adapted to
this system's grids and stroke weights. Logseq-specific icons
(`task-*`, `bullet`, `status-dot`, `logo`, `graph`, `sidebar-toggle`,
`keyboard-hide`, `cards`) are hand-authored in `tooling/generate.py`
(`CUSTOM24`/`FILLED24`). Keep the Lucide license notice with any
re-distribution of the derived set.

## Workflow

```
# regenerate everything (needs tu: $TU or PATH)
TU=/path/to/tu python3 tooling/generate.py     # scenes + SVGs
python3 tooling/build.py                        # validate + preview site

# or re-emit SVGs from existing scenes only
TU=/path/to/tu python3 tooling/build.py --emit

# eyeball a render: compose a contact-sheet svg and rasterize
tu render sheet.svg -o sheet.png --no-rate-limit
```

## Adding an icon

1. If a Lucide equivalent exists, add the mapping to `LUCIDE` in
   `tooling/generate.py`; otherwise author children in `CUSTOM24` (24px
   grid; the 16px version scales ×2/3 automatically).
2. Filled variant only if a state truly needs it (`FILLED24`).
3. Add tags/product aliases in `metadata.json`.
4. Run generate + build; review `site/index.html` at 1×.
