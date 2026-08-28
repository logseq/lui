import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"

const manifestUrl = new URL("../references/web-simulator.json", import.meta.url)
const fetcherUrl = new URL("../../../tooling/fetch_web_simulator_references.mjs", import.meta.url)

test("the simulator comparison corpus is immutable and license-auditable", async () => {
  const manifest = JSON.parse(await readFile(manifestUrl, "utf8"))

  assert.equal(manifest.version, 1)
  assert.ok(manifest.references.length >= 4)
  assert.ok(manifest.references.filter(({ language }) => language === "swift").length >= 3)
  assert.ok(manifest.references.some(({ platform }) => platform === "android"))

  for (const reference of manifest.references) {
    assert.match(reference.repository, /^https:\/\/github\.com\/[^/]+\/[^/]+$/)
    assert.match(reference.commit, /^[0-9a-f]{40}$/)
    assert.ok(["ios", "android"].includes(reference.platform))
    assert.ok(reference.license.name.length > 0)
    assert.ok(reference.license.path.length > 0)
    assert.ok(reference.sourcePaths.length > 0)
    assert.ok(reference.scenarios.length > 0)

    for (const scenario of reference.scenarios) {
      assert.ok(scenario.name.length > 0)
      assert.ok(scenario.viewport.width > 0)
      assert.ok(scenario.viewport.height > 0)
      assert.ok(scenario.assertions.length > 0)
    }
  }
})

test("the comparison corpus has a reproducible immutable fetch command", async () => {
  const source = await readFile(fetcherUrl, "utf8")

  assert.match(source, /git/)
  assert.match(source, /clone/)
  assert.match(source, /checkout/)
  assert.match(source, /--detach/)
  assert.match(source, /reference\.commit/)
  assert.match(source, /reference\.license\.path/)
  assert.match(source, /reference\.sourcePaths/)
  assert.doesNotMatch(source, /shell:\s*true/)
})
