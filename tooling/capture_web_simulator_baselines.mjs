import assert from "node:assert/strict"
import { once } from "node:events"
import { mkdir, readFile, rm, writeFile } from "node:fs/promises"
import path from "node:path"
import { createRequire } from "node:module"
import { fileURLToPath, pathToFileURL } from "node:url"

import { createStaticServer } from "./serve_web.mjs"

const projectRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..")
const webRoot = path.join(projectRoot, "platform/web")
const referencesRoot = path.join(webRoot, "references")
const manifestPath = path.join(referencesRoot, "visual-baselines.json")
const diffRoot = path.join(projectRoot, "_build/web-simulator-visual-diffs")
const webRequire = createRequire(path.join(webRoot, "package.json"))
const { chromium } = webRequire("playwright")
const { PNG } = webRequire("pngjs")
const pixelmatch = (
  await import(pathToFileURL(webRequire.resolve("pixelmatch")).href)
).default

const updateBaselines = process.env.LUI_UPDATE_VISUAL_BASELINES === "1"
const selectedScenario = process.argv.includes("--scenario")
  ? process.argv[process.argv.indexOf("--scenario") + 1]
  : null

async function settle(page) {
  await page.evaluate(
    () => new Promise((resolve) => requestAnimationFrame(() => requestAnimationFrame(resolve))),
  )
}

async function choose(select, value) {
  await select.evaluate((element, nextValue) => {
    element.value = nextValue
    element.dispatchEvent(new Event("change", { bubbles: true }))
  }, value)
}

async function prepareScenario(page, scenario, origin) {
  await page.goto(`${origin}/examples/components/web/index.html`, {
    waitUntil: "networkidle",
  })
  await choose(page.locator('select[aria-label="Simulator platform"]'), scenario.platform)
  await choose(
    page.locator('select[aria-label="Simulator form factor"]'),
    scenario.device.formFactor,
  )
  if (scenario.device.orientation === "landscape") {
    await page.getByRole("button", { name: "Rotate simulator" }).click()
  }
  await page.evaluate((galleryPage) => {
    const destination = [...document.querySelectorAll(".lui-gallery-nav-item")]
      .find((item) => item.textContent === galleryPage)
    if (!destination) throw new Error(`unknown Gallery page: ${galleryPage}`)
    destination.click()
  }, scenario.galleryPage)
  await page.addStyleTag({
    content: `
      *, *::before, *::after {
        animation-delay: 0s !important;
        animation-duration: 0s !important;
        caret-color: transparent !important;
        scroll-behavior: auto !important;
        transition-delay: 0s !important;
        transition-duration: 0s !important;
      }
      .lui-simulator-toolbar { display: none !important; }
    `,
  })

  if (scenario.state === "open-sheet") {
    await page.getByRole("button", { name: "Open sheet", exact: true }).click()
    await page.locator(".lui-modal-layer[data-open]").waitFor()
  } else {
    assert.equal(scenario.state, "default")
  }

  await page.evaluate(() => document.activeElement?.blur())
  await page.evaluate(() => document.fonts.ready)
  await settle(page)
}

async function verifyDom(page, scenario) {
  const result = await page.evaluate((dom) => {
    const missingSelectors = dom.requiredSelectors.filter(
      (selector) => !document.querySelector(selector),
    )
    const roleCounts = Object.fromEntries(
      Object.keys(dom.roleCounts ?? {}).map((role) => [
        role,
        document.querySelectorAll(`[role="${role}"]`).length,
      ]),
    )
    const metrics = (dom.metrics ?? []).map((metric) => {
      const element = document.querySelector(metric.selector)
      return {
        ...metric,
        actual: element?.getBoundingClientRect()[metric.dimension] ?? null,
      }
    })
    return {
      missingSelectors,
      roleCounts,
      metrics,
      canvasCount: document.querySelectorAll("canvas").length,
    }
  }, scenario.dom)

  assert.deepEqual(result.missingSelectors, [], `${scenario.id} is missing DOM landmarks`)
  assert.equal(result.canvasCount, scenario.dom.canvasCount, `${scenario.id} Canvas count`)
  for (const [role, expected] of Object.entries(scenario.dom.roleCounts ?? {})) {
    assert.equal(result.roleCounts[role], expected, `${scenario.id} ${role} count`)
  }
  for (const metric of result.metrics) {
    assert.ok(metric.actual !== null, `${scenario.id} metric ${metric.selector} is absent`)
    assert.ok(
      Math.abs(metric.actual - metric.value) <= metric.tolerance,
      `${scenario.id} ${metric.selector} ${metric.dimension}: ${metric.actual}, expected ${metric.value} ± ${metric.tolerance}`,
    )
  }
}

async function capture(page, scenario) {
  const options = { animations: "disabled", scale: "device" }
  return scenario.scope === "simulator"
    ? page.locator("#app").screenshot(options)
    : page.screenshot({ ...options, fullPage: false })
}

async function compareScreenshot(actualBytes, baselineBytes, scenario) {
  const actual = PNG.sync.read(actualBytes)
  const baseline = PNG.sync.read(baselineBytes)
  assert.equal(actual.width, baseline.width, `${scenario.id} baseline width`)
  assert.equal(actual.height, baseline.height, `${scenario.id} baseline height`)

  const diff = new PNG({ width: actual.width, height: actual.height })
  const differentPixels = pixelmatch(
    baseline.data,
    actual.data,
    diff.data,
    actual.width,
    actual.height,
    { includeAA: false, threshold: 0.1 },
  )
  const pixelDifferenceRatio = differentPixels / (actual.width * actual.height)
  const withinBudget =
    differentPixels <= scenario.budget.maxDifferentPixels &&
    pixelDifferenceRatio <= scenario.budget.pixelDifferenceRatio

  if (!withinBudget) {
    await mkdir(diffRoot, { recursive: true })
    await writeFile(path.join(diffRoot, `${scenario.id}.png`), PNG.sync.write(diff))
  }

  assert.ok(
    withinBudget,
    `${scenario.id} changed ${differentPixels} pixels (${pixelDifferenceRatio.toFixed(6)}); ` +
      `budget is ${scenario.budget.maxDifferentPixels} pixels and ${scenario.budget.pixelDifferenceRatio}`,
  )
  return { differentPixels, pixelDifferenceRatio }
}

async function run() {
  const manifest = JSON.parse(await readFile(manifestPath, "utf8"))
  const scenarios = manifest.scenarios.filter(
    (scenario) => selectedScenario === null || scenario.id === selectedScenario,
  )
  if (selectedScenario !== null && scenarios.length === 0) {
    throw new Error(`unknown visual scenario: ${selectedScenario}`)
  }

  const server = createStaticServer(projectRoot)
  server.listen(0, "127.0.0.1")
  await once(server, "listening")
  const origin = `http://127.0.0.1:${server.address().port}`
  const browser = await chromium.launch({ headless: true })

  try {
    if (!updateBaselines) await rm(diffRoot, { recursive: true, force: true })
    for (const scenario of scenarios) {
      const context = await browser.newContext({
        viewport: scenario.device.viewport,
        deviceScaleFactor: scenario.device.scale,
        locale: manifest.engine.locale,
        timezoneId: manifest.engine.timezoneId,
        colorScheme: manifest.engine.colorScheme,
        reducedMotion: manifest.engine.reducedMotion,
      })
      await context.addInitScript(() => {
        const fixedNow = Date.parse("2026-01-15T12:00:00.000Z")
        const NativeDate = Date
        globalThis.Date = class extends NativeDate {
          constructor(...args) {
            super(...(args.length === 0 ? [fixedNow] : args))
          }
          static now() {
            return fixedNow
          }
        }
        Math.random = () => 0.5
      })
      const page = await context.newPage()
      try {
        await prepareScenario(page, scenario, origin)
        await verifyDom(page, scenario)
        const screenshot = await capture(page, scenario)
        const baselinePath = path.join(referencesRoot, scenario.baseline)
        if (updateBaselines) {
          await mkdir(path.dirname(baselinePath), { recursive: true })
          await writeFile(baselinePath, screenshot)
          process.stdout.write(`updated ${scenario.id}\n`)
        } else {
          const comparison = await compareScreenshot(
            screenshot,
            await readFile(baselinePath),
            scenario,
          )
          process.stdout.write(
            `verified ${scenario.id}: ${comparison.differentPixels} pixels differ ` +
              `(${comparison.pixelDifferenceRatio.toFixed(6)})\n`,
          )
        }
      } finally {
        await context.close()
      }
    }
  } finally {
    await browser.close()
    server.close()
    await once(server, "close")
  }
}

await run()
