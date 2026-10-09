import assert from "node:assert/strict"
import { once } from "node:events"
import test, { before, after } from "node:test"
import { createStaticServer } from "../../../tooling/serve_web.mjs"
import { createPlaywrightSession } from "./playwright-session.mjs"
let session, server, page, origin
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
  if (server?.listening) { const closed = once(server, "close"); server.close(); await closed }
})
const open = async () => {
  await page.goto(`${origin}/platform/web/test/fixtures/review-regression.html`)
  await page.waitForFunction(() => window.review)
}

test("virtual-list attaches a bounded window and renders distant rows after scrolling", async () => {
  await open()
  const count = () => page.evaluate(() => review.node(4).querySelectorAll('[id^="lui-node-"]').length)
  assert.ok(await count() < 100, "initial DOM must be bounded by viewport, not the 1000 retained rows")
  await page.evaluate(() => { review.node(4).scrollTop = 12000; review.node(4).dispatchEvent(new Event("scroll")) })
  await page.waitForFunction(() => review.node(505)?.isConnected)
  assert.ok(await count() < 100)
  assert.equal(await page.locator("#lui-node-505").textContent(), "virtual row 500")
  await page.evaluate(() => {
    review.apply([review.set(505, "text", "updated distant row")])
  })
  assert.equal(await page.locator("#lui-node-505").textContent(), "updated distant row")
})

test("list scroll tokens complete and report the visible range", async () => {
  await open()
  await page.evaluate(() => review.apply([
    review.set(1005, "track-visible-range", true),
    review.set(1005, "scroll-target", "row-75"),
    review.set(1005, "scroll-anchor", "center"),
    review.set(1005, "scroll-animated", false),
    review.set(1005, "scroll-token", 1),
  ]))
  await page.waitForFunction(() => review.events.some(e => e.TAG === 10 && e._0 === 1005 && e._1 === 1))
  assert.ok(await page.evaluate(() => review.node(1005).scrollTop > 1000))
  assert.ok(await page.evaluate(() => review.events.some(e => e.TAG === 11 && e._0 === 1005 && e._1 >= 60)))
})

test("virtual-list updates distant size estimates and preserves keyed row measurements", async () => {
  await open()
  await page.evaluate(() => review.apply([review.set(505, "height", 60)]))
  await page.waitForFunction(() => Number.parseFloat(review.node(4).firstElementChild.style.height) === 24036)
  await page.evaluate(() => review.apply([review.Protocol.move_child_op(4, 505, 0)]))
  await page.waitForFunction(() => review.node(505)?.isConnected)
  assert.equal(await page.evaluate(() => review.node(505).getBoundingClientRect().height), 60)
  await page.waitForFunction(() => Math.abs(review.node(5).getBoundingClientRect().top
    - review.node(505).getBoundingClientRect().top - 60) < 1)
  assert.equal(await page.evaluate(() => Number.parseFloat(review.node(4).firstElementChild.style.height)), 24036)
})

test("virtual-list retains a focused row until focus leaves it", async () => {
  await open()
  await page.evaluate(() => {
    review.node(5).tabIndex = 0
    review.node(5).focus()
    review.node(4).scrollTop = 12000
    review.node(4).dispatchEvent(new Event("scroll"))
  })
  await page.waitForFunction(() => review.node(505)?.isConnected)
  assert.equal(await page.evaluate(() => document.activeElement === review.node(5)), true)
  await page.evaluate(() => review.node(5).blur())
  await page.waitForFunction(() => !review.node(5))
})

test("virtual-list preserves DOM order while scrolling back toward earlier rows", async () => {
  await open()
  await page.evaluate(() => { review.node(4).scrollTop = 12000; review.node(4).dispatchEvent(new Event("scroll")) })
  await page.waitForFunction(() => review.node(505)?.isConnected)
  await page.evaluate(() => { review.node(4).scrollTop = 11800; review.node(4).dispatchEvent(new Event("scroll")) })
  await page.waitForFunction(() => review.node(497)?.isConnected)
  const indices = await page.evaluate(() => [...review.node(4).querySelectorAll('[data-index]')].map(row => Number(row.dataset.index)))
  assert.deepEqual(indices, [...indices].sort((a, b) => a - b))
})

test("virtual tree focus only initializes visible retained rows", async () => {
  await open()
  await page.evaluate(() => {
    const tree = review.Protocol.create_node_op(2000, review.kinds.get("tree"))
    const operations = [tree, review.set(2000, "accessibility-label", "Virtual tree"),
      review.Protocol.remove_child_op(1, 4), review.Protocol.insert_child_op(1, 2000, 3),
      review.Protocol.insert_child_op(2000, 4, 0)]
    // Tree rows are containers with a treeitem role; update the initial window.
    for (let index = 0; index < 1000; index++) {
      const id = 3000 + index
      operations.push(review.Protocol.create_node_op(id, review.kinds.get("column")),
        review.set(id, "role", "treeitem"), review.set(id, "height", 24),
        review.Protocol.insert_child_op(4, id, index))
    }
    try { review.apply(operations) } catch (e) { throw new Error(e._1 ?? e.message) }
  })
  assert.ok(await page.evaluate(() => review.node(2000).querySelectorAll('[role="treeitem"]').length) < 100)
  assert.equal(await page.evaluate(() => review.node(3999)), null)
  await page.evaluate(() => { review.node(4).scrollTop = 12000; review.node(4).dispatchEvent(new Event("scroll")) })
  await page.waitForFunction(() => review.node(3500)?.isConnected)
  assert.equal(await page.evaluate(() => review.node(3500).getAttribute("aria-level")), "1")
  assert.ok(await page.evaluate(() => [...review.node(2000).querySelectorAll('[role="treeitem"]')].some(n => n.tabIndex === 0)))
})

test("a DOM failure rebuilds a coherent mirror and accepts the following delta", async () => {
  await open()
  const result = await page.evaluate(() => {
    const target = review.node(3)
    const descriptor = Object.getOwnPropertyDescriptor(Node.prototype, "textContent")
    let fail = true
    Object.defineProperty(target, "textContent", {
      configurable: true,
      get() { return descriptor.get.call(this) },
      set(value) { if (fail) { fail = false; throw new Error("injected DOM failure") }; descriptor.set.call(this, value) },
    })
    try { review.apply([review.set(2, "text", "after A"), review.set(3, "text", "after B")]) } catch {}
    const coherent = [2, 3].every(id => review.node(id).textContent === review.property(id, "text")._0)
    review.apply([review.set(3, "text", "later")])
    return { coherent, text: review.node(3).textContent,
      roots: document.querySelectorAll("#lui-node-1").length }
  })
  assert.deepEqual(result, { coherent: true, text: "later", roots: 1 })
})
