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
  assert.match(devRunner, /await runOnce\([^)]*["']Dune initial build["']/s)
  assert.doesNotMatch(devRunner, /watch\(["']Dune["'],\s*["']opam["']/)
  assert.match(devRunner, /await watchDune\(duneEnvironment\)/)
  assert.match(devRunner, /child\.stderr\.on\(["']data["']/)
  assert.ok(
    devRunner.indexOf("await watchDune(duneEnvironment)") <
      devRunner.indexOf('watch(\n    "Vite"'),
  )
  assert.match(devRunner, /["']@web["']/)
  assert.match(devRunner, /["']-w["']/)
  assert.match(devRunner, /node_modules["'],\s*["']\.bin["'],\s*["']tailwindcss["']/)
  assert.match(devRunner, /node_modules["'],\s*["']\.bin["'],\s*["']vite["']/)
  assert.match(devRunner, /["']--minify["']/)
})

test("Vite updates generated LG definitions through the runtime HMR boundary", async () => {
  const config = await readFile(
    new URL("platform/web/vite.config.mjs", root),
    "utf8",
  )
  const componentsApp = await readFile(
    new URL("examples/components/lg/components/app.cljc", root),
    "utf8",
  )

  assert.match(config, /import\.meta\.hot\.accept/)
  assert.match(config, /import\.meta\.hot\.data/)
  assert.match(config, /handleHotUpdate/)
  assert.match(config, /readFile/)
  assert.match(config, /settleGeneratedFile/)
  assert.match(config, /waitForMelangeOutput/)
  assert.match(config, /generatedBootstrap/)
  assert.match(config, /LG_SOURCE_EXTENSIONS/)
  assert.match(config, /["']\.cljc["']/)
  assert.match(config, /["']\.mli["']/)
  assert.match(config, /web_bootstrap\.js/)
  assert.match(config, /ignored:/)
  assert.match(config, /server\.moduleGraph\.getModuleById/)
  assert.match(config, /replace_for_redefinition/)
  assert.match(config, /__root/)
  assert.match(config, /_build\/default/)
  assert.match(componentsApp, /create-reloadable-with-extensions/)
})
