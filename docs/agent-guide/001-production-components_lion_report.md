# Lion Web Component provider spike

Date: 2026-08-24

Status: rejected as a runtime dependency; retained-behavior findings remain
valid.

## Question

Can LUI reuse an existing Web Component library for complex controls without
introducing React, a second application state tree or a Web-only semantic API?

## Candidate result at the time of the spike

[Lion](https://lion.js.org/) is the best fit for the default behavior
foundation. It is framework-agnostic, MIT licensed, accessibility-focused and
intentionally white-label. It exposes custom elements, properties and custom
events that a retained backend can drive directly.

[Web Awesome](https://webawesome.com/) is the strongest ready-styled optional
provider. Its open-source catalog is broad, but combobox, date picker and data
grid are among its commercial Pro components. It should not define LUI's core
capability floor.

[Spectrum Web Components](https://opensource.adobe.com/spectrum-web-components/)
is comprehensive and production-used, but intentionally implements Adobe's
Spectrum design language. It is a good optional provider rather than the
neutral default.

[UI5 Web Components](https://ui5.github.io/webcomponents/docs/getting-started/first-steps/)
has strong complex controls and accessibility support, but is optimized around
SAP Fiori and is heavier than the default LUI Web layer should be.

[Material Web](https://github.com/material-components/material-web/discussions/5642)
was excluded because the official project remains in maintenance mode and does
not plan new components or features.

## Bundle experiment

The spike used `@lion/ui` 0.21.0, esbuild 0.28.2, ESM output and minification.
Sizes include the component and its transitive runtime; gzip sizes are local
measurements, not published guarantees.

| Imports | Minified | Gzip |
| --- | ---: | ---: |
| `lion-input` | 98.6 KB | 27.7 KB |
| `lion-dialog` | 72.1 KB | 22.5 KB |
| `lion-combobox` and `lion-option` | 196.9 KB | 53.8 KB |
| Input, dialog and combobox together | 200.6 KB | 54.5 KB |

The measured shared total was reasonable for the behavior spike. It did not
account for the additional visual component implementation Lion requires, so
bundle size alone was not sufficient to make Lion the finished default.

## Browser behavior

The spike created elements with `document.createElement`, assigned properties,
attached native/custom event listeners and moved retained elements in the DOM.

| Check | Result |
| --- | --- |
| Input property update preserves native input identity | Pass |
| Input property update preserves focus | Pass |
| User input emits `model-value-changed` | Pass |
| Combobox accepts a retained model value | Pass |
| Combobox emits `model-value-changed` | Pass |
| Dialog opens and emits `opened-changed` | Pass |
| Dialog traps focus while open | Pass |
| DOM reparent preserves custom element identity | Pass |
| DOM reparent preserves focused descendant | Fail |

The move failure also occurs with a direct `append`/`insertBefore`, not only
with the current explicit remove-and-insert implementation. It is a browser DOM
movement limitation, not a Lion state recreation. The tested browser did not
expose the newer state-preserving `moveBefore` API.

## Superseded decision

Lion proved that an opaque custom-element implementation can coexist with the
LUI retained tree, but it is intentionally white-label and does not meet the
later requirement for a polished, ready-to-use default visual component set.
Web Awesome was also explicitly excluded. The current LUI-native decision and
historical bundle comparison are recorded in
`001-production-components_web_report.md`.

The adapter and focus findings below remain useful evidence about opaque custom
elements, although the current Web design uses retained semantic HTML.
The following list records the original spike recommendations and is not the
current provider decision:

### Original recommendations

1. Keep native HTML for layout, content, scrolling and fallback primitives.
2. Fix Web keyed movement so focus is captured and restored when the platform
   lacks state-preserving DOM movement.
3. Define an opaque Web Component adapter for tag creation, property mapping,
   slots, events, readiness and capability reporting.
4. Prove the adapter first with Lion input, textarea, combobox and dialog.
5. Import provider components individually and measure the production bundle.
6. Keep Web Awesome, Spectrum and UI5 as optional providers behind the same
   semantic contract.

Lion is installed through the `@lion/ui` npm package. Provider entry points
import registrations individually, for example
`@lion/ui/define/lion-textarea.js`, so an application includes only the
components it uses plus their shared dependencies.

Lion's internal Lit tree owns only the implementation of one opaque custom
element. LG remains the application state owner, and LUI remains responsible
for retained application identity and cross-platform semantic events.

The keyed-movement prerequisite was subsequently implemented in the retained
Web backend. It restores the focused descendant after the synchronous move and
once more after browser click-default processing, but only when focus otherwise
falls back to the document body. The original browser regression (focused `Up`
button became `body`) now retains the same focused `Up` button after reorder.
