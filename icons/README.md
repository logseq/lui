# Logseq Icons

A unified SVG icon set for Logseq, Logseq Chat, and Simple Journal —
one construction system, two drawn sizes (16px, 24px), two styles
(outline, filled). See [DESIGN.md](DESIGN.md) for the full spec.

## Browse

Open `site/index.html` in a browser — search by name, tag, or product
alias; switch size, style, and zoom.

## Rebuild the preview / validate

```
python3 tooling/build.py
```

Validates every SVG against the system rules (stroke width, fill mode,
round caps) and regenerates `site/index.html` from `metadata.json`.

## Adopting the set in a product

1. Pick the size by render target: use `16/` (1.25px stroke) when the icon
   will render 12–20px, `24/` (1.5px stroke) at ≥22px.
2. Resolve product-side names through `metadata.json` `aliases` —
   e.g. chat's `navigation-back` → `arrow-left`, `graph-remote` → `cloud`,
   `toolbar-copy-url` → `link`; journal's `xmark.circle.fill` → filled
   `x-circle`, `globe` → `world`.
3. Color is `currentColor` — set CSS `color` on the parent; no fill/stroke
   overrides needed.

## Conventions

- Outline: `stroke="currentColor"`, `fill="none"`, round caps/joins.
- Filled: `fill="currentColor"`, `fill-rule="evenodd"` knockouts.
- `viewBox="0 0 16 16"` or `0 0 24 24`; no width/height attributes — the
  consumer sizes it.
