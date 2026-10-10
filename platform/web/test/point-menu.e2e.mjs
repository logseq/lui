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

const openPositioner = () =>
  page.locator(".lui-popup-positioner", {
    has: page.locator(".lui-dropdown-menu[data-open]"),
  })

test("dropdown-menu x/y mounts at a computed point away from any DOM parent", async () => {
  await page.goto(`${origin}/platform/web/test/fixtures/point-menu-regression.html`)
  await page.evaluate(() => window.audit.openPointMenu(64, 96))

  const menu = page.locator(".lui-dropdown-menu[data-open]")
  await menu.waitFor()

  const positioner = openPositioner()
  const bounds = await positioner.evaluate((el) => {
    const rect = el.getBoundingClientRect()
    return {
      left: rect.left,
      top: rect.top,
      inPortal: Boolean(el.closest(".lui-popup-portal")),
      inHost: Boolean(el.closest("#host")),
      availableWidth: el.style.getPropertyValue("--lui-popup-available-width").trim(),
      availableHeight: el.style.getPropertyValue("--lui-popup-available-height").trim(),
      hidden: el.getAttribute("data-hidden"),
    }
  })
  // position_at_point parity: the positioner lands at the emitted point and
  // carries the clamp channel values like a popover ~at.
  assert.equal(bounds.left, 64)
  assert.equal(bounds.top, 96)
  assert.ok(bounds.availableWidth.length > 0)
  assert.ok(bounds.availableHeight.length > 0)
  // The surface lives in the popup portal — not under the retained parent
  // box and not inside #host at all.
  assert.equal(bounds.inPortal, true)
  assert.equal(bounds.inHost, false)

  // menu_item state channels keep working: the first item carries the
  // selected channel through data-selected plus the menu styling.
  const selected = page.locator(".lui-menu-item[data-selected]")
  assert.equal(await selected.count(), 1)
  assert.equal(await selected.evaluate((el) => el.textContent.trim()), "Point alpha")
  const selectedBg = await selected.evaluate((el) => getComputedStyle(el).backgroundColor)
  assert.notEqual(selectedBg, "rgba(0, 0, 0, 0)")
  assert.notEqual(selectedBg, "transparent")

  // x/y updates re-position the open menu.
  await page.evaluate(() => window.audit.movePointMenu(120, 200))
  const moved = await positioner.evaluate((el) => {
    const rect = el.getBoundingClientRect()
    return { left: rect.left, top: rect.top }
  })
  assert.equal(moved.left, 120)
  assert.equal(moved.top, 200)

  // Escape dismiss parity with a DOM-anchored dropdown_menu.
  await page.keyboard.press("Escape")
  await page.waitForFunction(() => !document.querySelector(".lui-dropdown-menu[data-open]"))

  // on_press channel: reopen and activate the item — the press event fires
  // and item activation closes the menu like a DOM-anchored dropdown_menu.
  await page.evaluate(() => window.audit.openPointMenu(64, 96))
  await page.locator(".lui-dropdown-menu[data-open]").waitFor()
  await page.locator(".lui-menu-item", { hasText: "Point beta" }).click()
  await page.waitForFunction(() => window.audit.activations.includes("beta"))
})

test("point-anchored menu dismisses on outside press like a dropdown_menu", async () => {
  await page.goto(`${origin}/platform/web/test/fixtures/point-menu-regression.html`)
  await page.evaluate(() => window.audit.openPointMenu(64, 96))
  await page.locator(".lui-dropdown-menu[data-open]").waitFor()

  await page.mouse.click(500, 500)
  await page.waitForFunction(() => !document.querySelector(".lui-dropdown-menu[data-open]"))
})

test("DOM-anchored dropdown-menu still follows its sibling anchor", async () => {
  await page.goto(`${origin}/platform/web/test/fixtures/point-menu-regression.html`)
  const select = await page.evaluate(() => window.audit.openAnchoredMenu())
  await page.locator(`#lui-node-${select}`).click()
  const menu = page.locator(".lui-dropdown-menu[data-open]")
  await menu.waitFor()

  // The anchored menu keeps positioning relative to its trigger sibling —
  // the point path did not steal the anchor path.
  const selectRect = await page.locator(`#lui-node-${select}`).evaluate((el) => el.getBoundingClientRect())
  const popupRect = await openPositioner().evaluate((el) => el.getBoundingClientRect())
  assert.ok(popupRect.top >= selectRect.bottom - 1,
    `expected popup below trigger (top ${popupRect.top} >= bottom ${selectRect.bottom})`)
})
