# LUI-native Web component decision

Date: 2026-08-24

## Decision

LUI implements its own Web component layer on retained native DOM. It does not
use React, Solid, Vaadin, Lion, Web Awesome or another UI runtime as the default
provider.

Solid UI revision `21ba4fa` defines the Web parity contract: catalog, public
parts and props, variants, sizes, state attributes, behavior, examples and
visual output. Its component source is
available in a sibling local checkout for study, but no Solid JSX, Kobalte,
Corvu or Tailwind runtime is added to LUI. Solid's reactive model is replaced by
the existing LG Signal graph and retained incremental scheduler.

## Runtime boundary

- Native HTML owns text editing, selection, composition, focus, forms,
  scrolling and accessibility semantics.
- The Web backend owns retained element identity and typed property/event
  translation.
- LG behaviors own cross-platform interaction state that native controls do not
  provide consistently.
- LUI components own tokens, variants, named parts and finished visual styling.
- Applications consume components as library APIs instead of copying generated
  source into each project.

## Why not a provider

Provider experiments showed that third-party custom elements can preserve LUI
retained identity, but they add another component lifecycle, theming contract
and baseline bundle. Vaadin was briefly selected for its catalog and measured
size, then explicitly removed from the product direction. Lion requires LUI to
create nearly all visual styling. Spectrum imposes a larger bundle and Adobe's
design language. Base UI requires React, while Solid UI itself requires a Solid
JSX and Tailwind toolchain and distributes copied source rather than a runtime
component package.

Implementing LUI's styled layer directly makes platform tweaks, semantic tokens
and incremental diagnostics part of one cross-platform component contract.

## Implementation rules

1. Use the most specific semantic HTML element available.
2. Patch properties in place; never replace a control to update its value or
   appearance.
3. Preserve composition, selection, focus and scroll position during external
   value patches and keyed moves.
4. Prefer browser layout and presentation APIs over JavaScript measurement.
5. Keep behaviors headless and components composable through named parts.
6. Express visual state through theme tokens, semantic classes and data-state
   attributes, not inline provider-specific options.
7. Match every Solid UI registry component and its meaningful public parts as
   specified in `001-production-components_solid_ui_matrix.md`.
8. Test keyboard and accessibility contracts in a real browser.
9. Measure generated LUI JavaScript and CSS from the component gallery and fail
   production builds when agreed budgets regress.

## Historical measurements

The rejected provider experiment measured a minified common set of Button,
TextField, TextArea, Select and Dialog at 48.3 KB gzip for Vaadin 25.2.8 and
93.7 KB gzip for Spectrum 1.12.2. These numbers remain useful comparison data,
but they are not LUI's bundle budget.
