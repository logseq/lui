import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"

const root = new URL("../../", import.meta.url)

test("Web development composes Dune watch, Tailwind watch, and Vite", async () => {
  const [makefile, packageJson, devRunner] = await Promise.all([
    readFile(new URL("Makefile", root), "utf8"),
    readFile(new URL("platform/web/package.json", root), "utf8").then(JSON.parse),
    readFile(new URL("tooling/dev_web.mjs", root), "utf8"),
  ])

  assert.match(makefile, /dev-web:[^\n]*\n\tnode tooling\/dev_web\.mjs/)
  assert.ok(packageJson.devDependencies.vite)
  assert.match(devRunner, /dune["'],\s*["']build["']/)
  assert.match(devRunner, /await runOnce\([^)]*["']Dune initial build["']/s)
  assert.match(devRunner, /["']@web["']/)
  assert.match(devRunner, /["']-w["']/)
  assert.match(devRunner, /node_modules["'],\s*["']\.bin["'],\s*["']tailwindcss["']/)
  assert.match(devRunner, /node_modules["'],\s*["']\.bin["'],\s*["']vite["']/)
  assert.match(devRunner, /["']--minify["']/)
})

test("Vite serves generated Melange modules without LG runtime integration", async () => {
  const config = await readFile(
    new URL("platform/web/vite.config.mjs", root),
    "utf8",
  )
  const componentsApp = await readFile(
    new URL("examples/components/lg/components/app.cljc", root),
    "utf8",
  )

  assert.match(config, /root:\s*projectRoot/)
  assert.doesNotMatch(config, /handleHotUpdate/)
  assert.doesNotMatch(config, /replace_for_redefinition/)
  assert.doesNotMatch(componentsApp, /create-reloadable/)
  assert.match(componentsApp, /app\/create-with-extensions/)
})
