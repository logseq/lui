import assert from "node:assert/strict"
import { once } from "node:events"
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

const scrollerSel = "#app [data-lui-kind='virtual-list'], #app .lui-virtual-list"

async function scrollerMetrics() {
  return page.evaluate(() => {
    const sc = [...document.querySelectorAll("#app div")].find(
      (d) => d.scrollHeight > d.clientHeight + 2 &&
        getComputedStyle(d).overflowY === "auto")
    if (!sc) return null
    return { top: sc.scrollTop, h: sc.clientHeight, sh: sc.scrollHeight,
             bottom: sc.scrollHeight - sc.clientHeight }
  })
}

test("jump-to-latest scrolls the virtual transcript to the real bottom", async () => {
  await page.setViewportSize({ width: 1280, height: 800 })
  await page.goto(`${origin}/examples/chat/web/index.html`,
    { waitUntil: "networkidle" })
  await page.waitForSelector("#app textarea", { timeout: 10000 })
  await page.waitForTimeout(3500)

  // The demo self-streams; the pinned transcript must already sit at the
  // bottom of a settled layout before the test scrolls away.
  let m = await scrollerMetrics()
  assert.ok(m, "expected a bounded internal scroller")
  assert.ok(m.top > m.bottom - 64,
    `expected pinned tail-follow near bottom, got top=${m.top} bottom=${m.bottom}`)

  // Scroll up into history: the pill appears once unpinned.
  await page.mouse.move(640, 400)
  await page.mouse.wheel(0, -2400)
  await page.waitForTimeout(600)
  const jump = page.getByRole("button", { name: "Jump to latest" })
  await assert.doesNotReject(async () =>
    assert.ok(await jump.isVisible(), "Jump pill must appear when unpinned"))
  const scrolled = await scrollerMetrics()
  assert.ok(scrolled.top < scrolled.bottom - 64,
    "expected the scroll position to be in history")

  // Click Jump to latest: the scroller must reach the actual bottom —
  // not merely hide the pill while staying in history.
  await jump.click()
  await page.waitForTimeout(1200)
  m = await scrollerMetrics()
  assert.ok(m.top > m.bottom - 64,
    `jump must land at the bottom, got top=${m.top} bottom=${m.bottom}`)
  assert.equal(await jump.isVisible().catch(() => false), false,
    "pill stays hidden once pinned")
})

test("oversized final response: scroll-within unpins, jump reaches real bottom", async () => {
  await page.setViewportSize({ width: 1280, height: 800 })
  await page.goto(`${origin}/examples/chat/web/index.html?tall`,
    { waitUntil: "networkidle" })
  await page.waitForSelector("#app textarea", { timeout: 10000 })
  // Wait for settle: pinned at the true bottom of a >viewport tail row.
  await page.waitForFunction(() => {
    const sc = [...document.querySelectorAll("#app div")].find(
      (d) => d.scrollHeight > d.clientHeight + 2 &&
        getComputedStyle(d).overflowY === "auto")
    return sc && sc.scrollTop > 0 &&
      sc.scrollTop >= sc.scrollHeight - sc.clientHeight - 4
  }, null, { timeout: 10000 })

  // Scroll up ~1000px INSIDE the tall tail row — the same row stays the
  // last visible, yet the tail edge is gone: must unpin.
  const jump = page.getByRole("button", { name: "Jump to latest" })
  await page.mouse.move(640, 400)
  await page.mouse.wheel(0, -1000)
  await page.waitForFunction(() =>
    [...document.querySelectorAll("button")].some(
      (b) => b.getAttribute("aria-label") === "Jump to latest" ||
        b.textContent.includes("Jump to latest")), null, { timeout: 5000 })
  assert.ok(await jump.isVisible(),
    "scrolling up inside the tall tail row must unpin")

  // Rapid double-Jump: second token supersedes the first; the scroller
  // still lands at the true bottom.
  await jump.click(); await jump.click().catch(() => {})
  await page.waitForFunction(() => {
    const sc = [...document.querySelectorAll("#app div")].find(
      (d) => d.scrollHeight > d.clientHeight + 2 &&
        getComputedStyle(d).overflowY === "auto")
    return sc && sc.scrollTop >= sc.scrollHeight - sc.clientHeight - 4
  }, null, { timeout: 8000 })
  const m = await scrollerMetrics()
  assert.ok(m.top > m.bottom - 64,
    `jump on tall tail must reach bottom, got top=${m.top} bottom=${m.bottom}`)
})
