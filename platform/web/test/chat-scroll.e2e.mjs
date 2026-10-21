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

test("anchored-list mode: bounded scroller, unpin, Jump lands at bottom", async () => {
  await page.setViewportSize({ width: 1280, height: 800 })
  await page.goto(`${origin}/examples/chat/web/index.html?list`,
    { waitUntil: "networkidle" })
  await page.waitForSelector("#app textarea", { timeout: 10000 })
  // Bounded internal scroller + tail-follow to the real bottom.
  await page.waitForFunction(() => {
    const sc = [...document.querySelectorAll("#app div")].find(
      (d) => d.scrollHeight > d.clientHeight + 2 &&
        getComputedStyle(d).overflowY === "auto")
    return sc && sc.scrollTop > 0 &&
      sc.scrollTop >= sc.scrollHeight - sc.clientHeight - 4
  }, null, { timeout: 10000 })
  const m = await scrollerMetrics()
  assert.ok(m && m.top > 0 && m.top >= m.bottom - 4,
    `anchored-list must bound and follow tail, got ${JSON.stringify(m)}`)

  await page.mouse.move(640, 400)
  await page.mouse.wheel(0, -2400)
  const jump = page.getByRole("button", { name: "Jump to latest" })
  await page.waitForFunction(() =>
    [...document.querySelectorAll("button")].some(
      (b) => (b.getAttribute("aria-label") || "").includes("Jump")),
    null, { timeout: 5000 })
  await jump.click()
  await page.waitForFunction(() => {
    const sc = [...document.querySelectorAll("#app div")].find(
      (d) => d.scrollHeight > d.clientHeight + 2 &&
        getComputedStyle(d).overflowY === "auto")
    return sc && sc.scrollTop >= sc.scrollHeight - sc.clientHeight - 4
  }, null, { timeout: 8000 })
})

test("scroll completion outcomes are observable (succeeded, cancelled)", async () => {
  await page.setViewportSize({ width: 1280, height: 800 })
  await page.goto(`${origin}/examples/chat/web/index.html?debug`,
    { waitUntil: "networkidle" })
  await page.waitForSelector("#app textarea", { timeout: 10000 })
  // "At the tail" = the last mounted row's bottom edge inside the
  // scroller's viewport — robust to post-landing geometry shifts.
  await page.waitForFunction(() => {
    const sc = [...document.querySelectorAll("#app div")].find(
      (d) => d.scrollHeight > d.clientHeight + 2 &&
        getComputedStyle(d).overflowY === "auto")
    if (!sc) return false
    const rows = [...sc.querySelectorAll("[data-index]")]
    const last = rows[rows.length - 1]
    if (!last) return false
    const sr = sc.getBoundingClientRect()
    const rr = last.getBoundingClientRect()
    return rr.bottom <= sr.bottom + 4 && rr.bottom > sr.top
  }, null, { timeout: 10000 })
  const outcomeText = () =>
    page.evaluate(() => {
      const el = [...document.querySelectorAll("#app *")].find(
        (e) => e.children.length === 0 &&
          /succeeded|cancelled|missing-target/.test(e.textContent || ""))
      return el ? el.textContent : ""
    })
  // Unpin then Jump: outcome "succeeded" must appear in the debug line.
  await page.mouse.move(640, 400)
  await page.mouse.wheel(0, -2400)
  const jump = page.getByRole("button", { name: "Jump to latest" })
  await jump.click()
  await page.waitForFunction(() =>
    [...document.querySelectorAll("#app *")].some(
      (e) => e.children.length === 0 &&
        (e.textContent || "").includes("succeeded")),
    null, { timeout: 8000 })
  assert.ok((await outcomeText()).includes("succeeded"),
    "expected succeeded outcome")
  // Each Jump intent settles exactly once: another unpin+Jump appends
  // one more terminal outcome — no double emits, no pending hangs.
  await page.mouse.wheel(0, -2400)
  await page.waitForFunction(() =>
    [...document.querySelectorAll("button")].some(
      (b) => (b.getAttribute("aria-label") || "").includes("Jump")),
    null, { timeout: 5000 })
  const before = await outcomeText()
  const jump2 = page.getByRole("button", { name: "Jump to latest" })
  await jump2.click()
  await page.waitForFunction(() => {
    const el = [...document.querySelectorAll("#app *")].find(
      (e) => e.children.length === 0 &&
        /succeeded|cancelled|missing-target/.test(e.textContent || ""))
    const t = el ? el.textContent : ""
    return t.trim().split("succeeded").length - 1 >= 2 ||
      /cancelled|missing-target/.test(t)
  }, null, { timeout: 8000 })
  const t = await outcomeText()
  assert.ok(/succeeded/.test(t), `expected terminal outcome, got "${t}"`)
  assert.ok(!/pending|stalled/.test(t), "intent must not hang pending")
})

test("plain virtual_list keeps position while children arrive", async () => {
  await page.setViewportSize({ width: 1280, height: 800 })
  await page.goto(`${origin}/examples/chat/web/index.html?v`,
    { waitUntil: "networkidle" })
  await page.waitForSelector("#app [data-index='0']", { timeout: 10000 })
  // Rows grow 0 -> 400 in committed chunks; a non-following list must
  // never be re-anchored to the bottom just because geometry changed.
  await page.waitForFunction(() => {
    const sc = [...document.querySelectorAll("#app div")].find(
      (d) => d.scrollHeight > d.clientHeight + 2 &&
        getComputedStyle(d).overflowY === "auto")
    return sc && sc.scrollHeight >= 9500
  }, { timeout: 15000 })
  const m = await scrollerMetrics()
  assert.ok(m, "expected a bounded virtual scroller")
  assert.equal(m.top, 0,
    `plain virtual_list yanked to ${m.top}; expected scrollTop 0`)
  assert.ok(await page.$("#app [data-index='0']"),
    "first row must stay mounted at the top")
})

test("chunked replay keeps the pinned transcript following the tail", async () => {
  await page.setViewportSize({ width: 1280, height: 800 })
  await page.goto(`${origin}/examples/chat/web/index.html?r`,
    { waitUntil: "networkidle" })
  await page.waitForSelector("#app textarea", { timeout: 10000 })
  // 1050 items arrive in committed chunks; the pinned transcript must
  // land on and hold the real bottom — a stale mid-list success or a
  // transit bottom=false must not permanently unpin it.
  await page.waitForFunction(() => {
    const sc = [...document.querySelectorAll("#app div")].find(
      (d) => d.scrollHeight > d.clientHeight + 2 &&
        getComputedStyle(d).overflowY === "auto")
    if (!sc || sc.scrollHeight < 30000) return false
    return Math.abs(sc.scrollTop - (sc.scrollHeight - sc.clientHeight)) < 2
  }, { timeout: 30000 })
  await page.waitForTimeout(400)
  const m = await scrollerMetrics()
  assert.ok(m.top >= m.bottom - 2,
    `replay left transcript unpinned at ${m.top}/${m.bottom}`)
})
