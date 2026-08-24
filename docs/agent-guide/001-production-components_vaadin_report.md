# Vaadin Web Component provider report

Date: 2026-08-24

## Decision

Use standalone Vaadin Web Components as LUI's default Web control provider.
This is the npm-distributed browser component library, not Vaadin Flow: LUI
does not add Java, a server runtime, React, or another application state tree.

The default provider must remain a thin adapter. LG owns semantic state and
retained identity; Vaadin owns the internal implementation of each opaque
control. Native DOM remains the layout/content layer and fallback path.

## Why this candidate

Vaadin's Apache-licensed core set includes Button, TextField, TextArea,
Checkbox, Switch, Select, ComboBox, DatePicker, Dialog, Popover, Grid and
VirtualList. This covers more of the required LUI catalog without depending on
commercial components. Commercial Pro controls are outside the capability
floor.

Aura and Lumo provide finished themes, dark-mode support and documented CSS
custom properties. LUI can map semantic tokens to those properties instead of
styling every shadow part itself.

`vaadin-text-area` grows with content by default and exposes `min-rows` and
`max-rows`. The provider therefore owns auto-sizing; LUI only maps semantic
constraints and never implements browser text measurement.

## Bundle experiment

The local experiment used esbuild 0.25.9, ESM output, minification and gzip.
Vaadin packages were version 25.2.8; Spectrum packages were version 1.12.2.
Sizes include transitive runtime and component styles and are reproducible
measurements, not vendor guarantees.

| Imports | Minified | Gzip |
| --- | ---: | ---: |
| Vaadin TextField | 107.8 KB | 28.4 KB |
| Vaadin Button, TextField, TextArea, Select and Dialog | 192.0 KB | 48.3 KB |
| Spectrum TextField plus Theme | 188.4 KB | 49.1 KB |
| Spectrum Button, TextField, Picker, Dialog and Theme | 469.2 KB | 93.7 KB |

The representative Vaadin set stays below a 55 KB gzip budget and costs only
19.9 KB gzip beyond its first TextField. Spectrum exceeds both the isolated
control and common-set budgets. Web Awesome was excluded by product decision;
Lion was rejected as the default because it requires a separate visual design
implementation.

## Integration rules

1. Install only required `@vaadin/*` npm packages.
2. Import individual component entry points; never import an aggregate bundle.
3. Keep provider registration and property/event adaptation in `platform/web`.
4. Keep Vaadin names and provider-only properties out of the LG wire protocol.
5. Preserve custom-element identity across patches and keyed movement.
6. Lazy-load route-local Tier 2 and Tier 3 components.
7. Fail the production build when either gzip budget regresses.
8. Verify focus, composition, selection, accessibility and cleanup in a real
   browser before marking a semantic component supported.
