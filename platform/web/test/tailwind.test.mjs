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
