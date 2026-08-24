import assert from "node:assert/strict"
import { readFile, stat } from "node:fs/promises"
import test from "node:test"

const outputUrl = new URL("../dist/lui.css", import.meta.url)

test("the production stylesheet contains the Solid UI button contract", async () => {
  const css = await readFile(outputUrl, "utf8")

  assert.match(css, /\.lui-button\{[^}]*display:inline-flex/)
  assert.match(css, /\.lui-button--default\{[^}]*background-color:var\(--color-primary\)/)
  assert.match(css, /\.lui-button--default:hover/)
  assert.match(css, /\.lui-button:focus-visible/)
  assert.match(css, /\.lui-button--sm\{[^}]*height:calc\(var\(--spacing\)\*9\)/)
  assert.doesNotMatch(css, /\.inline-flex\{/)
})

test("the production stylesheet stays within the component-library size budget", async () => {
  const { size } = await stat(outputUrl)

  assert.ok(size <= 32_000, `expected at most 32 KB, received ${size} bytes`)
})

test("the production stylesheet contains the Solid UI Card parts", async () => {
  const css = await readFile(outputUrl, "utf8")

  assert.match(css, /\.lui-card\{[^}]*border-radius:var\(--radius-lg\)/)
  assert.match(css, /\.lui-card-header\{[^}]*display:flex/)
  assert.match(css, /\.lui-card-title\{[^}]*font-size:var\(--text-lg\)/)
  assert.match(css, /\.lui-card-description\{[^}]*color:var\(--color-muted-foreground\)/)
  assert.match(css, /\.lui-card-content\{[^}]*padding:calc\(var\(--spacing\)\*6\)/)
  assert.match(css, /\.lui-card-footer\{[^}]*align-items:center/)
})

test("the production stylesheet contains the Solid UI TextField contract", async () => {
  const css = await readFile(outputUrl, "utf8")

  assert.match(css, /\.lui-label(?:,\.lui-text-field-label)?\{[^}]*font-size:var\(--text-sm\)/)
  assert.match(css, /\.lui-text-field\{[^}]*display:flex/)
  assert.match(css, /\.lui-text-field\{[^}]*flex-direction:column/)
  assert.match(css, /\.lui-text-field-input\{[^}]*height:calc\(var\(--spacing\)\*10\)/)
  assert.match(css, /\.lui-text-field-input\[data-invalid\]/)
  assert.match(css, /\.lui-text-field-text-area\{[^}]*min-height:80px/)
  assert.match(css, /\.lui-text-field-description\{[^}]*color:var\(--color-muted-foreground\)/)
  assert.match(css, /\.lui-text-field-error-message\{[^}]*font-size:var\(--text-xs\)/)
  assert.match(css, /\.lui-text-field:has\(\[data-invalid\]\) \.lui-text-field-error-message/)
  assert.doesNotMatch(css, /\.h-10\{/)
})

test("the production stylesheet contains the Solid UI toggle contracts", async () => {
  const css = await readFile(outputUrl, "utf8")

  assert.match(css, /\.lui-checkbox\{[^}]*appearance:none/)
  assert.match(css, /\.lui-checkbox\[data-checked\]/)
  assert.match(css, /\.lui-checkbox\[data-indeterminate\]/)
  assert.match(css, /\.lui-checkbox:focus-visible/)
  assert.match(css, /\.lui-switch-control\{[^}]*display:inline-flex/)
  assert.match(css, /\.lui-switch-control\[data-checked\]/)
  assert.match(css, /\.lui-switch-thumb\{[^}]*pointer-events:none/)
  assert.match(
    css,
    /\.lui-switch-control\[data-checked\] \.lui-switch-thumb\{[^}]*translate:/,
  )
  assert.match(css, /\.lui-switch-error-message\{[^}]*display:none/)
  assert.match(css, /\.lui-switch:has\(\[data-invalid\]\) \.lui-switch-error-message/)
  assert.doesNotMatch(css, /\.size-4\{/)
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

test("the production stylesheet contains the Solid UI Progress contract", async () => {
  const css = await readFile(outputUrl, "utf8")

  assert.match(css, /\.lui-progress\{[^}]*display:flex/)
  assert.match(css, /\.lui-progress-control\{[^}]*height:calc\(var\(--spacing\)\*2\)/)
  assert.match(css, /\.lui-progress-control\{[^}]*background-color:var\(--color-secondary\)/)
  assert.match(css, /\.lui-progress-control:{1,2}before\{[^}]*background-color:var\(--color-primary\)/)
  assert.match(css, /\.lui-progress-control:{1,2}before\{[^}]*width:var\(--lui-progress-position\)/)
  assert.match(css, /\.lui-progress-label,\.lui-progress-value-label\{[^}]*font-size:var\(--text-sm\)/)
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
