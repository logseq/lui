# Logseq Icons

A unified SVG icon set for Logseq, Logseq Chat, and Simple Journal —
one construction system, two grids (16px/1.5px stroke, 24px/2px stroke),
two styles (outline, filled). Authored as `.tu` scenes and compiled with
[`tu`](https://github.com/logseq/tu). See [DESIGN.md](DESIGN.md).

## Browse

Open `site/index.html` — search by name, tag, or product alias;
switch size, style, and zoom.

## Regenerate

```
TU=/path/to/tu python3 tooling/generate.py   # scenes -> SVGs (needs tu)
python3 tooling/build.py                      # validate + rebuild site
```

`tooling/generate.py` maps generic icons to Lucide (ISC) geometry and
holds the Logseq-specific glyphs; `tooling/build.py --emit` re-emits
SVGs from committed scenes without regenerating them.

## Adopting the set in a product

1. Pick the size by render target: `16/` for 12–20px, `24/` for ≥22px.
2. Resolve product-side names through `metadata.json` `aliases` —
   chat's `navigation-back` → `arrow-left`, `toolbar-copy-url` → `link`,
   `graph-remote` → `cloud`; journal's `xmark.circle.fill` → filled
   `x-circle`, `globe` → `world`.
3. Color is `currentColor` — set CSS `color` on the parent.

## Conventions

- Outline: `stroke="currentColor"`, `fill="none"`, round caps/joins.
- Filled: `fill="currentColor"`, `fill-rule="evenodd"` knockouts.
- `viewBox="0 0 16 16"` / `0 0 24 24`; no width/height attributes.

Generic icons derive geometry from Lucide (ISC) — keep the license
notice on redistribution.
