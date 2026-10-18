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
