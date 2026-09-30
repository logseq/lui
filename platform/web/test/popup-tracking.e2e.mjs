import assert from "node:assert/strict"
import { once } from "node:events"
import test, { before, after } from "node:test"
import { createStaticServer } from "../../../tooling/serve_web.mjs"
import { createPlaywrightSession } from "./playwright-session.mjs"

let session, server, origin
before(async () => {
  session = await createPlaywrightSession()
  await session.page.addInitScript(() => {
    window.activeResizeObservers = new Set()
    const NativeObserver = window.ResizeObserver
    window.ResizeObserver = class extends NativeObserver {
      observe(...args) { window.activeResizeObservers.add(this); return super.observe(...args) }
      disconnect() { window.activeResizeObservers.delete(this); return super.disconnect() }
    }
  })
  server = createStaticServer(new URL("../../../", import.meta.url).pathname)
  server.listen(0, "127.0.0.1")
  await once(server, "listening")
  origin = `http://127.0.0.1:${server.address().port}`
})
after(async () => {
  await session?.close()
  if (server?.listening) {
    const closed = once(server, "close")
    server.close()
    await closed
  }
})

async function setup(count = 4, tooltip = false) {
  await session.page.setViewportSize({ width: 1000, height: 800 })
  await session.page.goto(`${origin}/platform/web/test/fixtures/layer-regression.html`)
  await session.page.waitForFunction(() => window.audit)
  await session.page.evaluate(({ count, tooltip }) => {
    window.audit.setupTracking(count, tooltip)
    document.querySelector("#host>.lui-column").style.position = "static"
    const scroller = document.querySelector(".tracking-scroll")
    scroller.style.overflow = "auto"
    scroller.style.display = "block"
    const content = document.querySelector(".tracking-content")
    content.style.width = "100%"
    content.style.alignItems = "flex-end"
    const select = document.querySelector(".tracking-anchor .lui-select")
    if (select) select.setAttribute("data-lui-open-method", "touch")
  }, { count, tooltip })
  if (tooltip) await session.page.getByRole("button", { name: "Tracking tooltip" }).focus()
  else await session.page.evaluate(() => window.audit.tracking.open())
  await session.page.waitForFunction(() => document.querySelector(".lui-dropdown-menu[data-open], .lui-tooltip[data-open]")?.getBoundingClientRect().width > 0)
  await session.page.waitForTimeout(180)
}

async function aligned(tooltip = false) {
  await session.page.waitForFunction(tooltip => {
    const anchor = document.querySelector(".tracking-anchor > :first-child")
    const popup = document.querySelector(tooltip ? ".lui-tooltip[data-open]" : ".lui-dropdown-menu[data-open]")
    if (!anchor || !popup) return false
    const a = anchor.getBoundingClientRect(), p = popup.getBoundingClientRect()
    return Math.abs(a.left - p.left) < 2 && Math.abs(a.bottom - p.top) < 12
  }, tooltip)
  if (!tooltip) assert.equal(await session.page.evaluate(() => {
    const popup = document.querySelector(".lui-dropdown-menu[data-open]")
    const p = popup.getBoundingClientRect()
    return popup.contains(document.elementFromPoint(p.left + p.width / 2, p.top + Math.min(p.height / 2, 18)))
  }), true)
}

test("popup tracking follows ancestor scroll, ancestor/anchor resize and layout shifts with retained hit targets", async () => {
  await setup()
  await aligned()
  await session.page.evaluate(() => {
    window.retainedPopup = document.querySelector(".lui-dropdown-menu")
    document.querySelector(".tracking-scroll").scrollTop = 25
  })
  await aligned()
  await session.page.evaluate(() => { document.querySelector(".tracking-scroll").style.width = "540px" })
  await aligned()
  await session.page.evaluate(() => { document.querySelector(".tracking-anchor .lui-select").style.height = "64px" })
  await aligned()
  await session.page.evaluate(() => window.audit.tracking.resizeSpacer(110))
  await aligned()
  await session.page.evaluate(() => { document.querySelector(".tracking-content").style.transform = "translateX(35px)" })
  await aligned()
  assert.equal(await session.page.evaluate(() => window.retainedPopup === document.querySelector(".lui-dropdown-menu")), true)
  await session.page.getByText("Tracking option 0", { exact: true }).click()
  await session.page.waitForFunction(() => !document.querySelector(".lui-dropdown-menu[data-open]"))
})

test("popup tracking clamps oversized menus on window resize and reveals highlighted rows", async () => {
  await setup(50)
  await session.page.setViewportSize({ width: 360, height: 460 })
  await session.page.waitForTimeout(150)
  const geometry = await session.page.evaluate(() => {
    const menu = document.querySelector(".lui-dropdown-menu[data-open]")
    const r = menu.getBoundingClientRect()
    return { left: r.left, top: r.top, right: r.right, bottom: r.bottom, scroll: menu.scrollHeight > menu.clientHeight }
  })
  assert.ok(geometry.left >= 7 && geometry.top >= 7 && geometry.right <= 353 && geometry.bottom <= 453, JSON.stringify(geometry))
  assert.equal(geometry.scroll, true)
  await session.page.evaluate(() => document.querySelector(".lui-dropdown-menu .lui-menu-item:last-child").setAttribute("data-highlighted", ""))
  await session.page.waitForFunction(() => {
    const menu = document.querySelector(".lui-dropdown-menu[data-open]"), row = menu.querySelector("[data-highlighted]")
    const m = menu.getBoundingClientRect(), r = row.getBoundingClientRect()
    return r.top >= m.top && r.bottom <= m.bottom + 1 && row.contains(document.elementFromPoint(r.left + r.width / 2, r.top + r.height / 2))
  })
})

test("popup tracking stops on close/removal and safely restarts a retained popup", async () => {
  await setup()
  await session.page.evaluate(() => {
    window.retainedPopup = document.querySelector(".lui-dropdown-menu")
    window.audit.tracking.retainReopen()
  })
  await aligned()
  assert.equal(await session.page.evaluate(() => window.retainedPopup === document.querySelector(".lui-dropdown-menu")), true)
  await session.page.evaluate(() => {
    const anchor = document.querySelector(".tracking-anchor .lui-select")
    const read = anchor.getBoundingClientRect.bind(anchor)
    window.anchorReads = 0
    anchor.getBoundingClientRect = () => { window.anchorReads++; return read() }
    window.audit.tracking.close()
  })
  await session.page.waitForTimeout(200)
  assert.equal(await session.page.evaluate(() => window.activeResizeObservers.size), 0)
  const reads = await session.page.evaluate(() => window.anchorReads)
  await session.page.evaluate(() => {
    document.querySelector(".tracking-scroll").scrollTop += 20
    window.dispatchEvent(new Event("resize"))
  })
  await session.page.waitForTimeout(250)
  assert.equal(await session.page.evaluate(() => window.anchorReads), reads)
  await session.page.evaluate(() => window.audit.tracking.open())
  await aligned()
  await session.page.evaluate(() => window.audit.tracking.removeAnchor())
  await session.page.waitForFunction(() => !document.querySelector(".lui-dropdown-menu[data-open]"))
  assert.equal(await session.page.evaluate(() => window.activeResizeObservers.size), 0)
})

test("popup tracking uses visual viewport offsets and available size", async () => {
  await setup(50)
  await session.page.evaluate(() => {
    const viewport = new EventTarget()
    Object.assign(viewport, { offsetLeft: 40, offsetTop: 60, width: 320, height: 350 })
    Object.defineProperty(window, "visualViewport", { configurable: true, value: viewport })
    window.audit.tracking.retainReopen()
  })
  await session.page.waitForTimeout(150)
  assert.equal(await session.page.evaluate(() => {
    const r = document.querySelector(".lui-dropdown-menu[data-open]").getBoundingClientRect()
    return r.left >= 47 && r.right <= 353 && r.top >= 67 && r.bottom <= 403
  }), true)
  await session.page.evaluate(() => {
    window.visualViewport.offsetTop = 90
    window.visualViewport.height = 240
    window.visualViewport.dispatchEvent(new Event("scroll"))
    window.visualViewport.dispatchEvent(new Event("resize"))
  })
  await session.page.waitForFunction(() => {
    const r = document.querySelector(".lui-dropdown-menu[data-open]").getBoundingClientRect()
    return r.top >= 97 && r.bottom <= 323
  })
})

test("anchored tooltip tracks scroll and layout shifts then closes for a hidden anchor", async () => {
  await setup(0, true)
  await aligned(true)
  await session.page.evaluate(() => { document.querySelector(".tracking-scroll").scrollTop = 25 })
  await aligned(true)
  await session.page.evaluate(() => { document.querySelector(".tracking-content").style.transform = "translateX(30px)" })
  await aligned(true)
  await session.page.evaluate(() => { document.querySelector(".tracking-anchor button").style.visibility = "hidden" })
  await session.page.waitForFunction(() => !document.querySelector(".lui-tooltip[data-open]"))
})
