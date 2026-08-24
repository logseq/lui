import assert from "node:assert/strict"
import { readFile, stat } from "node:fs/promises"
import test from "node:test"

const outputUrl = new URL("../dist/lui.css", import.meta.url)

test("the production stylesheet contains the Vercel Native Button contract", async () => {
  const css = await readFile(outputUrl, "utf8")

  assert.match(css, /\.lui-button\{[^}]*display:inline-flex/)
  assert.match(css, /\.lui-button\[data-variant=primary\]\{[^}]*background-color:var\(--color-primary\)/)
  assert.match(css, /\.lui-button\[data-variant=default\]/)
  assert.match(css, /\.lui-button\[data-variant=secondary\]/)
  assert.match(css, /\.lui-button\[data-variant=outline\]/)
  assert.match(css, /\.lui-button\[data-variant=ghost\]/)
  assert.match(css, /\.lui-button\[data-variant=destructive\]/)
  assert.match(css, /\.lui-button\[data-selected\]/)
  assert.match(css, /\.lui-button:focus-visible/)
  assert.match(css, /\.lui-button\[data-size=sm\]\{[^}]*height:calc\(var\(--spacing\)\*9\)/)
  assert.match(css, /\.lui-button\[data-size=icon\]\{[^}]*width:calc\(var\(--spacing\)\*10\)/)
  assert.match(css, /\.lui-button-icon\{[^}]*width:calc\(var\(--spacing\)\*4\)/)
  assert.doesNotMatch(css, /\.lui-button--link/)
  assert.doesNotMatch(css, /\.lui-button--size-default/)
  assert.doesNotMatch(css, /\.inline-flex\{/)
})

test("ToggleButton reuses Button chrome with explicit pressed state", async () => {
  const css = await readFile(outputUrl, "utf8")

  assert.match(css, /\.lui-toggle-button/)
  assert.match(css, /\.lui-toggle-button\[data-selected\]/)
  assert.match(css, /\.lui-toggle-button:focus-visible/)
})

test("Tabs is a retained TabsList whose direct Buttons become triggers", async () => {
  const css = await readFile(outputUrl, "utf8")

  assert.match(css, /\.lui-tabs\{[^}]*display:inline-flex/)
  assert.match(css, /\.lui-tabs\{[^}]*align-items:center/)
  assert.match(css, /\.lui-tabs>\.lui-button\{[^}]*border-radius:/)
  assert.match(css, /\.lui-tabs>\.lui-button\[data-selected\]/)
  assert.doesNotMatch(css, /\.lui-tab(?:\{|-|\[)/)
})

test("ButtonGroup and ToggleGroup use compact Tailwind horizontal layouts", async () => {
  const css = await readFile(outputUrl, "utf8")

  assert.match(css, /\.lui-button-group\{[^}]*display:inline-flex/)
  assert.match(css, /\.lui-button-group\{[^}]*align-items:center/)
  assert.match(css, /\.lui-button-group\{[^}]*gap:calc\(var\(--spacing\)\*1\)/)
  assert.match(css, /\.lui-toggle-group[^\{]*\{[^}]*display:inline-flex/)
  assert.match(css, /\.lui-toggle-group[^\{]*\{[^}]*align-items:center/)
  assert.match(css, /\.lui-toggle-group[^\{]*\{[^}]*gap:calc\(var\(--spacing\)\*1\)/)
  assert.match(css, /\.lui-button-group>\.lui-button\{/)
})

test("Breadcrumb and Pagination use compact Tailwind composition", async () => {
  const css = await readFile(outputUrl, "utf8")

  assert.match(css, /\.lui-breadcrumb\{[^}]*display:inline-flex/)
  assert.match(css, /\.lui-breadcrumb\{[^}]*align-items:center/)
  assert.match(css, /\.lui-breadcrumb\{[^}]*gap:calc\(var\(--spacing\)\*1\)/)
  assert.match(css, /\.lui-pagination\{[^}]*display:inline-flex/)
  assert.match(css, /\.lui-pagination\{[^}]*align-items:center/)
  assert.match(css, /\.lui-pagination\{[^}]*gap:2px/)
  assert.match(css, /\.lui-pagination>\.lui-button\{[^}]*height:calc\(var\(--spacing\)\*9\)/)
  assert.match(css, /\.lui-text\[data-pressable\]\{[^}]*cursor:pointer/)
  assert.match(css, /\.lui-text\[data-pressable\]:focus-visible/)
  assert.doesNotMatch(css, /\.lui-breadcrumb-item/)
  assert.doesNotMatch(css, /\.lui-pagination-item/)
})

test("the production stylesheet contains Vercel Native overlay surfaces", async () => {
  const css = await readFile(outputUrl, "utf8")

  assert.match(css, /\.lui-stack[^\{]*\{[^}]*display:grid/)
  assert.match(css, /\.lui-panel[^\{]*\{[^}]*border-radius:var\(--radius-xl\)/)
  assert.match(css, /\.lui-card[^\{]*\{[^}]*padding:calc\(var\(--spacing\)\*6\)/)
  assert.match(css, /\.lui-(?:stack|panel|card)>\*\{[^}]*grid-area:1\/1/)
  assert.doesNotMatch(css, /\.lui-card-(?:header|content|footer|title|description)/)
})

test("the production stylesheet distinguishes List flow from Scroll overlays", async () => {
  const css = await readFile(outputUrl, "utf8")

  assert.match(css, /\.lui-list[^\{]*\{[^}]*flex-direction:column/)
  assert.match(css, /\.lui-scroll[^\{]*\{[^}]*overflow:auto/)
  assert.match(css, /\.lui-scroll>\*\{[^}]*grid-area:1\/1/)
})

test("the production stylesheet contains the retained ListItem contract", async () => {
  const css = await readFile(outputUrl, "utf8")

  assert.match(css, /\.lui-list-item\{[^}]*display:flex/)
  assert.match(css, /\.lui-list-item\{[^}]*width:100%/)
  assert.match(css, /\.lui-list-item\[data-selected\]/)
  assert.match(css, /\.lui-list-item:focus-visible/)
  assert.match(css, /\.lui-list-item\[data-name\]:{1,2}before\{[^}]*width:calc\(var\(--spacing\)\*4\)/)
})

test("the production stylesheet contains the registered-image Avatar contract", async () => {
  const css = await readFile(outputUrl, "utf8")

  assert.match(css, /\.lui-avatar\{[^}]*position:relative/)
  assert.match(css, /\.lui-avatar\{[^}]*border-radius:3\.40282e38px/)
  assert.match(css, /\.lui-avatar-image\{[^}]*position:absolute/)
  assert.match(css, /\.lui-avatar-initials\{[^}]*display:flex/)
  assert.doesNotMatch(css, /\.lui-avatar\[data-size=/)
})

test("the production stylesheet contains the direct text-entry contract", async () => {
  const css = await readFile(outputUrl, "utf8")

  assert.match(css, /\.lui-text-field,\.lui-input,\.lui-search-field\{[^}]*height:calc\(var\(--spacing\)\*10\)/)
  assert.match(css, /\.lui-text-field,\.lui-input,\.lui-search-field,\.lui-textarea\{[^}]*border-radius:var\(--radius-md\)/)
  assert.match(css, /\.lui-text-field:focus-visible,\.lui-input:focus-visible,\.lui-search-field:focus-visible,\.lui-textarea:focus-visible/)
  assert.match(css, /\.lui-textarea\{[^}]*min-height:80px/)
  assert.match(css, /\.lui-textarea\{[^}]*field-sizing:content/)
  assert.doesNotMatch(css, /\.h-10\{/)
})

test("the production stylesheet contains the retained picker contract", async () => {
  const css = await readFile(outputUrl, "utf8")

  assert.match(css, /\.lui-select\{[^}]*min-width:calc\(var\(--spacing\)\*40\)/)
  assert.match(css, /\.lui-combobox\{[^}]*display:flex/)
  assert.match(css, /\.lui-dropdown-menu\{[^}]*position:absolute/)
  assert.match(css, /\.lui-dropdown-menu\[data-anchor=above\]\{[^}]*bottom:calc\(100% \+ var\(--lui-anchor-offset\)\)/)
  assert.match(css, /\.lui-dropdown-menu\[data-anchor-alignment=stretch\]/)
  assert.match(css, /\.lui-menu-item\{[^}]*display:flex/)
  assert.match(css, /\.lui-menu-item:not\(\[data-selected\]\) \.lui-menu-item-check/)
})

test("the production stylesheet contains direct Vercel Native toggle controls", async () => {
  const css = await readFile(outputUrl, "utf8")

  assert.match(css, /\.lui-checkbox\{[^}]*display:inline-flex/)
  assert.match(css, /\.lui-checkbox-control\{[^}]*appearance:none/)
  assert.match(css, /\.lui-checkbox-control:checked/)
  assert.match(css, /\.lui-checkbox-control:focus-visible/)
  assert.match(css, /\.lui-switch\{[^}]*display:inline-flex/)
  assert.match(css, /\.lui-switch-control\{[^}]*appearance:none/)
  assert.match(css, /\.lui-switch-control:checked/)
  assert.match(css, /\.lui-switch-control:checked:after\{[^}]*translate:/)
  assert.match(css, /\.lui-control-label\{[^}]*font-size:var\(--text-sm\)/)
  assert.doesNotMatch(css, /data-indeterminate/)
  assert.doesNotMatch(css, /\.lui-switch-thumb/)
  assert.doesNotMatch(css, /\.lui-switch-error-message/)
  assert.doesNotMatch(css, /\.size-4\{/)
})

test("the production stylesheet contains the daily value-control batch", async () => {
  const css = await readFile(outputUrl, "utf8")

  assert.match(css, /\.lui-toggle\{[^}]*display:inline-flex/)
  assert.match(css, /\.lui-toggle\[aria-pressed=true\]/)
  assert.match(css, /\.lui-radio-group\{[^}]*display:flex/)
  assert.match(css, /\.lui-radio-control\{[^}]*appearance:none/)
  assert.match(css, /\.lui-radio-control:checked/)
  assert.match(css, /\.lui-slider\{[^}]*accent-color:var\(--color-primary\)/)
})

test("the production stylesheet contains the Solid UI Badge contract", async () => {
  const css = await readFile(outputUrl, "utf8")

  assert.match(css, /\.lui-badge\{[^}]*display:inline-flex/)
  assert.match(css, /\.lui-badge\{[^}]*border-radius:var\(--radius-md\)/)
  assert.match(css, /\.lui-badge--default\{[^}]*background-color:var\(--color-primary\)/)
  assert.match(css, /\.lui-badge--secondary\{[^}]*background-color:var\(--color-secondary\)/)
  assert.match(css, /\.lui-badge--outline\{[^}]*color:var\(--color-foreground\)/)
  assert.match(css, /\.lui-badge--success\{[^}]*background-color:var\(--color-success\)/)
  assert.match(css, /\.lui-badge--warning\{[^}]*background-color:var\(--color-warning\)/)
  assert.match(css, /\.lui-badge--error\{[^}]*background-color:var\(--color-error\)/)
  assert.match(css, /\.lui-badge--round\{[^}]*border-radius:3\.40282e38px/)
  assert.doesNotMatch(css, /\.rounded-full\{/)
})

test("the production stylesheet contains the direct Progress contract", async () => {
  const css = await readFile(outputUrl, "utf8")

  assert.match(css, /\.lui-progress\{[^}]*height:calc\(var\(--spacing\)\*2\)/)
  assert.match(css, /\.lui-progress\{[^}]*background-color:var\(--color-secondary\)/)
  assert.match(css, /\.lui-progress:{1,2}before\{[^}]*background-color:var\(--color-primary\)/)
  assert.match(css, /\.lui-progress:{1,2}before\{[^}]*width:var\(--lui-progress-position\)/)
  assert.doesNotMatch(css, /\.h-2\{/)
})

test("the production stylesheet contains the Solid UI Separator contract", async () => {
  const css = await readFile(outputUrl, "utf8")

  assert.match(css, /\.lui-separator\{[^}]*background-color:var\(--color-border\)/)
  assert.match(css, /\.lui-separator\[data-orientation=horizontal\]\{[^}]*height:1px/)
  assert.match(css, /\.lui-separator\[data-orientation=horizontal\]\{[^}]*width:100%/)
  assert.match(css, /\.lui-separator\[data-orientation=vertical\]\{[^}]*height:100%/)
  assert.match(css, /\.lui-separator\[data-orientation=vertical\]\{[^}]*width:1px/)
  assert.doesNotMatch(css, /\.h-px\{/)
})

test("the production stylesheet contains the Solid UI Skeleton contract", async () => {
  const css = await readFile(outputUrl, "utf8")

  assert.match(css, /\.lui-skeleton\{[^}]*background-color:/)
  assert.match(css, /\.lui-skeleton\{[^}]*animation:/)
  assert.match(css, /@media \(prefers-reduced-motion:reduce\)/)
  assert.match(
    css,
    /@media \(prefers-reduced-motion:reduce\)\{[^{}]*\.lui-skeleton[^{}]*\{[^}]*animation:none/,
  )
  assert.doesNotMatch(css, /\.animate-pulse\{/)
})

test("the production stylesheet contains the Vercel Native Spinner contract", async () => {
  const css = await readFile(outputUrl, "utf8")

  assert.match(css, /\.lui-spinner\{[^}]*width:calc\(var\(--spacing\)\*5\)/)
  assert.match(css, /\.lui-spinner\{[^}]*animation:/)
  assert.match(css, /\.lui-spinner\[data-size=sm\]\{[^}]*width:calc\(var\(--spacing\)\*4\)/)
  assert.match(css, /\.lui-spinner\[data-size=lg\]\{[^}]*width:calc\(var\(--spacing\)\*6\)/)
  assert.match(css, /\.lui-spinner\[data-size=icon\]\{[^}]*width:calc\(var\(--spacing\)\*5\)/)
  assert.match(
    css,
    /@media \(prefers-reduced-motion:reduce\)\{[^{}]*\.lui-spinner[^{}]*\{[^}]*animation:none/,
  )
})

test("the production stylesheet contains the Vercel Native Icon contract", async () => {
  const css = await readFile(outputUrl, "utf8")

  assert.match(css, /\.lui-icon\{[^}]*width:18px/)
  assert.match(css, /\.lui-icon\{[^}]*background-color:currentColor/)
  assert.match(css, /\.lui-icon\[data-size=sm\]\{[^}]*width:calc\(var\(--spacing\)\*4\)/)
  assert.match(css, /\.lui-icon\[data-size=lg\]\{[^}]*width:calc\(var\(--spacing\)\*6\)/)
  for (const name of ["search", "trash", "git-pull-request"]) {
    assert.match(css, new RegExp(`\\.lui-icon\\[data-name=${name}\\]\\{[^}]*--lui-icon-image:`))
  }
  await stat(new URL("../dist/icons/missing.svg", import.meta.url))
})
