import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"

const referencesUrl = new URL("../references/web-simulator.json", import.meta.url)
const visualUrl = new URL("../references/visual-baselines.json", import.meta.url)
const captureUrl = new URL("../../../tooling/capture_web_simulator_baselines.mjs", import.meta.url)

test("visual scenarios are traceable to pinned public references and explicit budgets", async () => {
  const references = JSON.parse(await readFile(referencesUrl, "utf8"))
  const visual = JSON.parse(await readFile(visualUrl, "utf8"))
  const referenceScenarios = new Set(
    references.references.flatMap((reference) =>
      reference.scenarios.map((scenario) => `${reference.id}:${scenario.name}`),
    ),
  )

  assert.equal(visual.version, 1)
  assert.equal(visual.engine.name, "chromium")
  assert.equal(visual.engine.locale, "en-US")
  assert.equal(visual.engine.timezoneId, "UTC")
  assert.equal(visual.engine.colorScheme, "light")
  assert.equal(visual.engine.reducedMotion, "reduce")
  assert.ok(visual.scenarios.length >= 6)
  assert.deepEqual(new Set(visual.scenarios.map(({ platform }) => platform)), new Set(["ios", "android"]))
  const scenarioIds = new Set(visual.scenarios.map(({ id }) => id))
  assert.equal(scenarioIds.size, visual.scenarios.length)
  assert.ok(scenarioIds.has("ios-switch-phone"))
  assert.ok(scenarioIds.has("android-switch-phone"))

  for (const scenario of visual.scenarios) {
    assert.ok(referenceScenarios.has(`${scenario.reference.id}:${scenario.reference.scenario}`))
    assert.ok(["ios", "android"].includes(scenario.platform))
    assert.ok(["phone", "tablet"].includes(scenario.device.formFactor))
    assert.ok(["portrait", "landscape"].includes(scenario.device.orientation))
    assert.ok(scenario.device.viewport.width > 0)
    assert.ok(scenario.device.viewport.height > 0)
    assert.ok(scenario.device.scale > 0)
    assert.ok(scenario.galleryPage.length > 0)
    assert.match(scenario.baseline, /^baselines\/[a-z0-9-]+\.png$/)
    assert.ok(scenario.budget.pixelDifferenceRatio >= 0)
    assert.ok(scenario.budget.pixelDifferenceRatio <= 0.01)
    assert.ok(scenario.budget.maxDifferentPixels > 0)
    assert.ok(scenario.assertions.length > 0)

    const image = await readFile(new URL(`../references/${scenario.baseline}`, import.meta.url))
    assert.deepEqual([...image.subarray(0, 8)], [137, 80, 78, 71, 13, 10, 26, 10])
  }
})

test("the capture runner fixes every browser input that affects screenshots", async () => {
  const source = await readFile(captureUrl, "utf8")

  assert.match(source, /chromium\.launch/)
  assert.match(source, /deviceScaleFactor/)
  assert.match(source, /locale:/)
  assert.match(source, /timezoneId:/)
  assert.match(source, /colorScheme:/)
  assert.match(source, /reducedMotion:/)
  assert.match(source, /animations:\s*"disabled"/)
  assert.match(source, /document\.activeElement\?\.blur\(\)/)
  assert.match(source, /pixelmatch/)
  assert.match(source, /pixelDifferenceRatio/)
  assert.match(source, /maxDifferentPixels/)
  assert.match(source, /LUI_UPDATE_VISUAL_BASELINES/)
})
