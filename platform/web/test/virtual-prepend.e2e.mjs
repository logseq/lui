import assert from "node:assert/strict"
import { once } from "node:events"
import test, { before, after } from "node:test"
import { createStaticServer } from "../../../tooling/serve_web.mjs"
import { createPlaywrightSession } from "./playwright-session.mjs"

let server, origin, session, page
before(async () => {
  session = await createPlaywrightSession()
  page = session.page
  page.setDefaultTimeout(5000)
  server = createStaticServer(new URL("../../../", import.meta.url).pathname)
  server.listen(0, "127.0.0.1")
  await once(server, "listening")
  origin = `http://127.0.0.1:${server.address().port}`
})
after(async () => {
  await session?.close()
  if (server?.listening) {
    const done = once(server, "close")
    server.close()
    await done
  }
})
const frames = () => page.evaluate(() => new Promise(resolve =>
  requestAnimationFrame(() => requestAnimationFrame(() => requestAnimationFrame(resolve)))))
const viewport = () => page.locator(".lui-virtual-list")
const row = index => page.locator(`[data-row="${index}"]`)

function aligned(index) {
  const item = document.querySelector(`[data-row="${index}"]`)
  const root = document.querySelector(".lui-virtual-list")
  return item && Math.abs(item.getBoundingClientRect().top - root.getBoundingClientRect().top) < 2
}

async function open() {
  await page.goto(`${origin}/platform/web/test/fixtures/virtual-prepend-regression.html`)
  await page.waitForFunction(() => window.probe)
  await page.evaluate(() => window.probe.jump(120))
  await page.waitForFunction(aligned, 120)
  await viewport().hover()
  await page.mouse.wheel(0, 20)
  await frames()
}

async function visible() {
  return viewport().evaluate(root => {
    const top = root.getBoundingClientRect().top
    const item = [...root.querySelectorAll("[data-row]")]
      .find(item => item.getBoundingClientRect().top >= top)
    return { index: Number(item.dataset.row), y: item.getBoundingClientRect().top }
  })
}

async function unchanged(anchor) {
  await page.waitForFunction(({ index, y }) => {
    const item = document.querySelector(`[data-row="${index}"]`)
    return item && Math.abs(item.getBoundingClientRect().top - y) < 2
  }, anchor)
  await frames()
  assert.ok(Math.abs((await row(anchor.index).boundingBox()).y - anchor.y) < 2)
}

test("mixed-height prepend restores the same visible retained row and offset", async () => {
  await open()
  const anchor = await visible()
  await page.evaluate(() => window.probe.prepend(63))
  await unchanged(anchor)
})

test("repeated prepends preserve reading and later append does not reuse the anchor", async () => {
  await open()
  const anchor = await visible()
  for (const count of [63, 17]) {
    await page.evaluate(count => window.probe.prepend(count), count)
    await unchanged(anchor)
  }
  await viewport().hover()
  await page.mouse.wheel(0, 200)
  await frames()
  const moved = await visible()
  assert.notEqual(moved.index, anchor.index)
  await page.evaluate(() => window.probe.append())
  await unchanged(moved)
})

test("an explicit scroll after prepend supersedes its reading anchor", async () => {
  await open()
  await page.evaluate(() => window.probe.prepend(63))
  await page.evaluate(() => window.probe.jump(180))
  await page.waitForFunction(aligned, 180)
  await page.evaluate(() => window.probe.append())
  await frames()
  const bounds = await row(180).boundingBox(), root = await viewport().boundingBox()
  assert.ok(Math.abs(bounds.y - root.y) < 2)
})
