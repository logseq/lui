# Default-look analysis: reference vs LUI native backend

Goal: explain why our self-drawn native UI looks cruder than the reference
implementation, and record the token values adopted to close the gap.

## Root causes

1. **No design tokens below the view layer.** The only palette lives inside
   each host (`Lui_window.Theme.palette`, gallery `color_of`, demo hexes).
   `lui_paint` falls back to scattered hard-coded Tailwind-gray literals when a
   resolver doesn't know a name. The gallery resolver knows 8 names; every
   other token (`border`, `input`, `muted-foreground`, `foreground`, `ring`,
   `selection`) silently hit those gray fallbacks — and names *not* in the
   fallback set resolved to nothing, so chrome painted missing pieces
   transparent or black.

2. **Interactive kinds have no paint-level chrome.** `paint_own` gives
   `button`, `text-field`, `menu-item`, `list-item`, `bottom-tab`, `popover`,
   `dialog`, `tooltip`, etc. *no* default look: bare `box_ops` + text. Unless
   the view passes background/border/radius props, a button is invisible.
   The reference styles every widget from tokens by default.

3. **Control chrome differs measurably.** Unchecked checkbox/radio drew an
   *accent* border (looks pre-selected) instead of a neutral control border;
   radio inner dot was 8px filled with page background instead of a crisp
   6px white dot; switch was oversized (44x24 vs 36x20) with a flat thumb;
   slider thumb was a flat accent disc instead of a white capsule with
   layered shadows; scrollbar was a wide muted-foreground bar instead of a
   slim overlay thumb; avatar was accent-filled.

4. **No focus indication.** `focus-shadow` existed as a prop but nothing
   emitted the reference's standard 2px offset ring, so keyboard focus was
   invisible by default.

5. **Continuous (squircle) corners existed but were never enabled** —
   `fcontinuous`/`scontinuous` were hard-wired `false` in every emitted op.
   Flat shadows and square-cornered borders add to the crude look.

6. **State colors weren't state-aware.** Hover/press changes only happen
   via per-node props (`hover-background`), which views rarely set — so
   controls felt dead. Selection/hover needed default token-driven fills.

## Token table (reference -> adopted)

Light theme (hex):

| token            | reference | ours (old fallback) | adopted |
|------------------|-----------|---------------------|---------|
| background       | `#ffffff` | `#ffffff`           | `#ffffff` |
| surface          | `#f4f4f5` | `#e5e7eb` (secondary) | `#f4f4f5` |
| surface-hover    | `#e9e9ec` | —                   | `#e9e9ec` |
| surface-pressed  | `#dddde1` | —                   | `#dddde1` |
| border           | `#d9d9de` | `#d1d5db`           | `#d9d9de` |
| control-border   | mix(border,text,.25) | —         | `#a9aaae` |
| switch-track     | mix(border,text,.15) | `#e5e7eb` | `#bcbcc1` |
| text/foreground  | `#18181b` | `#000000`           | `#18181b` |
| text-muted       | `#71717a` | `#6b7280`           | `#71717a` |
| accent/primary   | `#2563eb` | `#2563eb`           | `#2563eb` |
| accent-hover     | `#1d4ed8` | —                   | `#1d4ed8` |
| accent-pressed   | `#1e40af` | —                   | `#1e40af` |
| danger           | `#dc2626` | `#dc2626`           | `#dc2626` |
| warning          | `#d97706` | —                   | `#d97706` |
| success          | `#16a34a` | —                   | `#16a34a` |
| focus            | accent@55%| —                   | `#2563eb` @55% |
| selection        | accent@25%| —                   | `#2563eb` @25% |
| scrollbar-thumb  | black@32% | `#808080`@63%       | `#000000` @32% |
| inverse (tooltip)| `#18181b` | —                   | `#18181b` |

Dark theme mirrors the reference table (`background #18181b`, `surface
#27272a`, `border #3f3f46`, `text #f4f4f5`, `text-muted #a1a1aa`, `accent
#3b82f6`, focus/selection accent @60%/40%, scrollbar white@35%).

Legacy shadcn names already on the wire (`primary`, `secondary`, `input`,
`ring`, `muted-foreground`, `destructive`, `card`, `popover`) alias onto the
same tokens so existing views keep working.

Metrics (shared): radius 6, spacing unit 4, focus ring = 2px border drawn
1px outside the box, scrollbar = 6px overlay thumb (full-round, min 16),
control radius for checkbox 4 / panels-popovers 8 / tooltip 5.
Font stack: `system-ui` (SF on darwin, resolved by the text engine),
`Segoe UI -> Tahoma -> Arial` on Windows, fontconfig sans on Linux;
default size 13 darwin / 14 elsewhere (matches the reference).

## Where the fix lives

- `lui_theme` (this dir): canonical tokens, metrics, typography scale,
  named shadow pairs, `color_of`/`shadow_of` resolvers hosts can adopt.
- `lui_paint`: `default_palette` mirrors the light tokens (only reachable
  when the host resolver returns None); `default_chrome` paints unstyled
  interactive kinds from tokens + state; control chrome aligned to the
  reference; continuous corners enabled on interactive surfaces; default
  focus ring; disabled dimming.
- `lui_gallery`: `color_of` resolves every token (light) so the committed
  gallery shows the new defaults end to end.
- `Lui_window.Theme.palette`: dark token values + the new names so the
  shipped demo resolves the same system.

The `lui_theme` test pins every mirror: all tokens resolve in both modes,
text/background pairs keep contrast >= 4.5, and `Lui_paint.default_palette`
agrees with the light tokens (no orphan fallbacks).
