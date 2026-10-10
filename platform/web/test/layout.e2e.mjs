import assert from "node:assert/strict"
import { once } from "node:events"
import { readFile } from "node:fs/promises"
import test, { after, before } from "node:test"

import { createStaticServer } from "../../../tooling/serve_web.mjs"
import { createPlaywrightSession } from "./playwright-session.mjs"

let server, origin, session, page
before(async () => {
  session = await createPlaywrightSession()
  page = session.page
  server = createStaticServer(new URL("../../../", import.meta.url).pathname)
  server.listen(0, "127.0.0.1")
  await once(server, "listening")
  origin = `http://127.0.0.1:${server.address().port}`
})
after(async () => {
  if (session) await session.close()
  if (server?.listening) {
    const closed = once(server, "close")
    server.close()
    await closed
  }
})

test("composer action overflow keeps full touch height and a stationary Send", async () => {
  const css = await readFile(new URL("../dist/lui.css", import.meta.url), "utf8")
  await page.setContent(`<style>${css}
    *::-webkit-scrollbar { height: 16px; width: 16px; }
    .actions { display: flex; gap: 8px; width: 236px; }
    .actions button { flex: none; width: 44px; height: 44px; }
    .actions button:first-child { width: 132px; }
  </style>
  <div style="width:256px;display:flex;gap:8px">
    <div class="lui-scroll composer-actions" style="min-width:0;height:44px;flex-grow:1">
      <div class="actions"><button>Attachments</button><button>Task</button><button>Discard</button></div>
    </div><button id="send" style="width:36px;height:36px;flex:none">Send</button>
  </div>`)
  const strip = page.locator(".composer-actions")
  const metrics = await strip.evaluate(element => ({
    height: element.clientHeight, contentHeight: element.scrollHeight,
    width: element.clientWidth, contentWidth: element.scrollWidth,
    overflowY: getComputedStyle(element).overflowY,
  }))
  assert.equal(metrics.height, 44)
  assert.equal(metrics.contentHeight, 44)
  assert.equal(metrics.overflowY, "hidden")
  assert.ok(metrics.contentWidth > metrics.width)
  const sendBefore = await page.locator("#send").boundingBox()
  await strip.hover()
  await page.mouse.wheel(400, 0)
  await page.waitForFunction(() => {
    const element = document.querySelector(".composer-actions")
    return element.scrollLeft + element.clientWidth >= element.scrollWidth - 1
  })
  const discard = await page.getByRole("button", { name: "Discard", exact: true }).boundingBox()
  const sendAfter = await page.locator("#send").boundingBox()
  assert.ok(discard.x + discard.width <= sendAfter.x)
  assert.deepEqual(sendAfter, sendBefore)
})

test("View That Fits switches retained candidates and moves only hidden focus", async () => {
  await page.setViewportSize({ width: 900, height: 900 })
  await page.goto(`${origin}/platform/web/test/fixtures/fit-regression.html`)
  const draft = page.getByPlaceholder("Retained draft")
  await draft.fill("Keep this draft")
  await page.setViewportSize({ width: 800, height: 900 })
  await page.waitForFunction(() => document.activeElement === window.fit.input)
  await page.setViewportSize({ width: 390, height: 844 })
  await page.waitForFunction(() =>
    document.activeElement === document.querySelector(".horizontal-fit"))
  assert.equal(await page.locator(".horizontal-fit").getAttribute("tabindex"), "-1")
  assert.equal(await page.getByText("Compact candidate", { exact: true }).isVisible(), true)
  assert.equal(await draft.isVisible(), false)
  assert.equal(await page.evaluate(() =>
    document.documentElement.scrollWidth <= window.innerWidth), true)
  await page.getByRole("button", { name: "External control", exact: true }).click()
  await page.setViewportSize({ width: 900, height: 900 })
  await draft.waitFor({ state: "visible" })
  assert.deepEqual(await page.evaluate(() => ({
    same: document.querySelector("input") === window.fit.input,
    draft: window.fit.input.value,
    focus: document.activeElement.textContent,
    inert: window.fit.input.closest(".lui-column").inert,
  })), { same: true, draft: "Keep this draft", focus: "External control", inert: false })
})

test("vertical fit chooses the first fitting candidate and keeps external focus", async () => {
  await page.goto(`${origin}/platform/web/test/fixtures/fit-regression.html`)
  await page.getByText("Tall candidate", { exact: true }).waitFor({ state: "visible" })
  await page.getByRole("button", { name: "Short vertical", exact: true }).click()
  await page.getByText("Tall candidate", { exact: true }).waitFor({ state: "hidden" })
  assert.equal(await page.getByText("Short candidate", { exact: true }).isVisible(), true)
  assert.equal(await page.evaluate(() => document.activeElement.textContent), "Short vertical")
})

test("mobile gallery controls and layout examples remain reachable without overflow", async () => {
  await page.setViewportSize({ width: 390, height: 844 })
  await page.goto(`${origin}/examples/components/web/index.html`)
  for (const name of ["Overlay", "View That Fits", "DropdownMenu", "Sidebar"]) {
    await page.locator(".lui-gallery-nav-item").filter({ hasText: new RegExp(`^${name}$`) }).click()
    if (name === "View That Fits") {
      await page
        .locator(".lui-view-that-fits")
        .getByText("COMPACT — narrow fallback", { exact: true })
        .waitFor({ state: "visible" })
    }
    assert.equal(await page.evaluate(() => {
      const content = document.querySelector(".lui-gallery-content")
      return content.scrollWidth <= content.clientWidth + 1
    }), true, `${name} should fit the mobile width`)
    if (name === "DropdownMenu") {
      await page.getByRole("button", { name: "Choose environment", exact: true }).click()
      await page.getByRole("menuitem", { name: "Staging", exact: true }).click()
      await page.getByText("Environment: Staging", { exact: true }).waitFor({ state: "visible" })
    } else if (name === "Sidebar") {
      await page.getByText("Getting started", { exact: true }).click()
      await page.getByText("Current: Getting started", { exact: true }).waitFor({ state: "visible" })
      await page.getByRole("button", { name: "Logseq Docs", exact: true }).click()
      await page.getByRole("menuitem", { name: "Work", exact: true }).click()
      await page.getByText("Current: Work", { exact: true }).waitFor({ state: "visible" })
    }
    await page.locator(".lui-gallery-navigation-back").click()
  }
})
