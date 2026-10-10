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

test("shared composer row centers short drafts and preserves bounded editing", async () => {
  await page.setViewportSize({ width: 390, height: 844 })
  await page.goto(`${origin}/examples/components/web/index.html`)
  await page.locator(".lui-gallery-nav-item").filter({ hasText: /^Combine$/ }).click()
  const draft = page.getByPlaceholder("Capture", { exact: true })
  const measure = () => draft.evaluate(input => {
    const row = input.parentElement
    const inputBounds = input.getBoundingClientRect()
    const rowBounds = row.getBoundingClientRect()
    return {
      height: inputBounds.height,
      width: inputBounds.width,
      rowHeight: rowBounds.height,
      rowWidth: rowBounds.width,
      offset: inputBounds.top - rowBounds.top,
      minHeight: getComputedStyle(input).minHeight,
      rowMinHeight: getComputedStyle(row).minHeight,
      alignment: getComputedStyle(row).alignItems,
      clientHeight: input.clientHeight,
      scrollHeight: input.scrollHeight,
      focused: document.activeElement === input,
    }
  })
  for (const width of [390, 320]) {
    await page.setViewportSize({ width, height: 844 })
    for (const colorScheme of ["light", "dark"]) {
      await page.emulateMedia({ colorScheme })
      await draft.fill("A single line")
      const short = await measure()
      assert.equal(short.rowMinHeight, "36px")
      assert.equal(short.alignment, "center")
      assert.equal(short.minHeight, "0px")
      assert.ok(short.rowHeight >= 36)
      assert.ok(Math.abs(short.offset - (short.rowHeight - short.height) / 2) < 1)
      assert.ok(short.width <= short.rowWidth + 1)
      await draft.fill("First line\nSecond line\nThird line")
      const multiline = await measure()
      assert.ok(multiline.height > short.height)
      await draft.fill(Array.from({ length: 30 }, (_, index) => `Line ${index + 1}`).join("\n"))
      const long = await measure()
      assert.ok(long.height <= 168)
      assert.ok(long.scrollHeight > long.clientHeight)
      assert.equal(long.focused, true)
      const endpoints = await draft.evaluate(input => {
        input.scrollTop = 0
        const start = input.scrollTop
        input.scrollTop = input.scrollHeight
        return { start, end: input.scrollTop, maximum: input.scrollHeight - input.clientHeight }
      })
      assert.equal(endpoints.start, 0)
      assert.ok(Math.abs(endpoints.end - endpoints.maximum) < 1)
      await draft.fill("Short again")
      const shrunk = await measure()
      assert.equal(shrunk.height, short.height)
      assert.equal(shrunk.focused, true)
      await draft.fill("")
      const empty = await measure()
      assert.equal(empty.height, short.height)
    }
  }
  await page.emulateMedia({ colorScheme: null })
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
