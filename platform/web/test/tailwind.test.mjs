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

test("the production stylesheet stays within the initial size budget", async () => {
  const { size } = await stat(outputUrl)

  assert.ok(size <= 20_000, `expected at most 20 KB, received ${size} bytes`)
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
