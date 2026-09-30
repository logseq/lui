import assert from "node:assert/strict"
import { once } from "node:events"
import test, { after, before } from "node:test"

import { createStaticServer } from "../../../tooling/serve_web.mjs"
import { createPlaywrightSession } from "./playwright-session.mjs"

let origin
let server
let session
let cdp

async function browser(...args) {
  return session.command(...args)
}

async function evaluate(source) {
  return session.evaluate(source)
}

async function state(expression) {
  const output = await evaluate(`JSON.stringify(${expression})`)
  return JSON.parse(JSON.parse(output))
}

async function openFixture() {
  await browser("set", "viewport", "390", "620")
  await browser("open", `${origin}/platform/web/test/fixtures/layer-regression.html`)
  await browser("wait", "--fn", "window.audit !== undefined")
}

async function openSheet() {
  await browser("click-button", "Open regression sheet")
  const sheet = session.page.locator(".lui-sheet").first()
  await sheet.waitFor({ state: "visible" })
  await sheet.evaluate(async (element) => {
    await new Promise((resolve) => requestAnimationFrame(() => resolve()))
    await Promise.all(element.getAnimations().map((animation) => animation.finished.catch(() => {})))
    await new Promise((resolve) => requestAnimationFrame(() => resolve()))
  })
  return sheet
}

async function touchEvent(type, touchPoints) {
  await cdp.send("Input.dispatchTouchEvent", {
    type,
    touchPoints,
    modifiers: 0,
  })
}

async function touchDrag(locator, {
  from = 0.75,
  to = 0.2,
  horizontal = 0,
  deltaY,
  reverseBy,
  duration = 120,
} = {}) {
  const bounds = await locator.boundingBox()
  assert.ok(bounds, "touch target should be visible")
  const x = bounds.x + bounds.width / 2
  const startY = bounds.y + bounds.height * from
  const endY = deltaY === undefined ? bounds.y + bounds.height * to : startY + deltaY
  await touchEvent("touchStart", [{ x, y: startY, id: 1 }])
  await new Promise((resolve) => setTimeout(resolve, 16))
  await touchEvent("touchMove", [{
    x: x + horizontal,
    y: endY,
    id: 1,
  }])
  if (reverseBy !== undefined) {
    await touchEvent("touchMove", [{
      x: x + horizontal,
      y: startY - reverseBy,
      id: 1,
    }])
  }
  if (duration > 16) await new Promise((resolve) => setTimeout(resolve, duration - 16))
  await touchEvent("touchEnd", [])
}

async function waitForClosed() {
  await session.page.waitForFunction(
    () => !document.querySelector(".lui-modal-layer"),
    null,
    { timeout: 2000 },
  )
}

before(async () => {
  session = await createPlaywrightSession()
  cdp = await session.page.context().newCDPSession(session.page)
  await cdp.send("Emulation.setTouchEmulationEnabled", { enabled: true, maxTouchPoints: 2 })
  server = createStaticServer(new URL("../../../", import.meta.url).pathname)
  server.listen(0, "127.0.0.1")
  await once(server, "listening")
  origin = `http://127.0.0.1:${server.address().port}`
})

after(async () => {
  await cdp?.detach().catch(() => {})
  await session?.close().catch(() => {})
  if (server?.listening) {
    const closed = once(server, "close")
    server.close()
    await closed
  }
})

test("renderer Sheet retains draft selection and keeps its controls reachable", async () => {
  await openFixture()
  const sheet = await openSheet()
  const input = sheet.locator('input[placeholder="Draft"]')
  await input.focus()
  await session.page.keyboard.type("retained draft")
  await input.selectText()

  await browser("set", "viewport", "390", "400")
  await browser("wait", "50")
  assert.deepEqual(
    await state(`(() => {
      const surface = document.querySelector('.lui-sheet')
      const body = surface?.querySelector('.lui-sheet-body')
      const handle = surface?.querySelector('.lui-sheet-handle')
      const draft = surface?.querySelector('input[placeholder="Draft"]')
      return {
        sameInput: draft === window.audit.sheetInput,
        value: draft?.value,
        selected: draft?.selectionStart === 0 && draft?.selectionEnd === draft?.value.length,
        focused: document.activeElement === draft,
        titleVisible: Boolean(surface?.querySelector('.lui-sheet-title')?.getBoundingClientRect().height),
        handleVisible: getComputedStyle(handle).display !== 'none',
        bodyScrollable: (body?.scrollHeight ?? 0) > (body?.clientHeight ?? 0),
        cancelVisible: [...(surface?.querySelectorAll('button') ?? [])].some((button) => button.textContent.trim() === 'Cancel'),
      }
    })()`),
    {
      sameInput: true,
      value: "retained draft",
      selected: true,
      focused: true,
      titleVisible: true,
      handleVisible: true,
      bodyScrollable: true,
      cancelVisible: true,
    },
  )

  const scroller = sheet.locator("#inner-scroll")
  await scroller.evaluate((element) => { element.scrollTop = 160 })
  const before = await state("document.querySelector('#inner-scroll').scrollTop")
  await touchDrag(scroller, { from: 0.2, to: 0.8, duration: 100 })
  const after = await state("document.querySelector('#inner-scroll').scrollTop")
  assert.ok(after < before)
  assert.equal(await state("document.querySelectorAll('.lui-modal-layer[data-open]').length"), 1)

  await touchDrag(sheet.locator(".lui-sheet-body"), { from: 0.9, to: 0.15, duration: 120 })
  assert.ok(await state("document.querySelector('.lui-sheet-body').scrollTop") > 0)
  const cancel = sheet.getByRole("button", { name: "Cancel", exact: true })
  await cancel.scrollIntoViewIfNeeded()
  assert.equal(
    await cancel.evaluate((button) => {
      const body = button.closest(".lui-sheet-body")
      const buttonRect = button.getBoundingClientRect()
      const bodyRect = body.getBoundingClientRect()
      return buttonRect.top >= bodyRect.top && buttonRect.bottom <= bodyRect.bottom
    }),
    true,
  )
  await cancel.click()
  await waitForClosed()
})

test("trusted Sheet gestures reject unsafe starts and arbitrate scrolling", async () => {
  await openFixture()
  let sheet = await openSheet()
  const handle = sheet.locator(".lui-sheet-handle")

  await touchDrag(handle, { horizontal: 150, deltaY: 0 })
  assert.equal(await state("document.querySelectorAll('.lui-modal-layer[data-open]').length"), 1)
  await touchDrag(handle, { deltaY: -40 })
  assert.equal(await state("document.querySelectorAll('.lui-modal-layer[data-open]').length"), 1)

  await touchDrag(handle, { deltaY: 35 })
  assert.equal(await state("document.querySelectorAll('.lui-modal-layer[data-open]').length"), 1)

  await touchDrag(handle, { deltaY: 120, reverseBy: 10 })
  assert.equal(await state("document.querySelectorAll('.lui-modal-layer[data-open]').length"), 1)

  await touchDrag(handle, { deltaY: 140, duration: 360 })
  await waitForClosed()

  sheet = await openSheet()
  await touchDrag(sheet.locator(".lui-sheet-handle"), { deltaY: 60, duration: 40 })
  await waitForClosed()

  sheet = await openSheet()
  const input = sheet.locator('input[placeholder="Draft"]')
  await touchDrag(input, { from: 0.5, to: 0.05 })
  assert.equal(await state("document.querySelectorAll('.lui-modal-layer[data-open]').length"), 1)
  await touchDrag(sheet.getByRole("button", { name: "Cancel", exact: true }), { from: 0.5, to: 0.5 })
  await waitForClosed()

  sheet = await openSheet()
  await touchEvent("touchStart", [{ x: 180, y: 330, id: 1 }, { x: 220, y: 330, id: 2 }])
  await touchEvent("touchMove", [{ x: 180, y: 500, id: 1 }, { x: 220, y: 500, id: 2 }])
  await touchEvent("touchEnd", [])
  assert.equal(await state("document.querySelectorAll('.lui-modal-layer[data-open]').length"), 1)

  await sheet.getByText("Sheet content stays in the retained renderer.").evaluate((element) => {
    const range = document.createRange()
    range.selectNodeContents(element)
    window.getSelection().removeAllRanges()
    window.getSelection().addRange(range)
  })
  assert.equal(await state("window.getSelection().isCollapsed"), false)
  await touchDrag(sheet.locator(".lui-sheet-handle"), { deltaY: 120 })
  assert.equal(await state("document.querySelectorAll('.lui-modal-layer[data-open]').length"), 1)

  await evaluate("window.getSelection().removeAllRanges()")
  const gestureHandle = sheet.locator(".lui-sheet-handle")
  const bounds = await gestureHandle.boundingBox()
  assert.ok(bounds)
  await evaluate(`window.__touchPointerId = null;
    document.querySelector('.lui-sheet').addEventListener('pointerdown', event => {
      if (event.pointerType === 'touch') window.__touchPointerId = event.pointerId
    }, { once: true })`)
  await touchEvent("touchStart", [{ x: bounds.x + bounds.width / 2, y: bounds.y + bounds.height / 2, id: 1 }])
  await touchEvent("touchMove", [{ x: bounds.x + bounds.width / 2, y: bounds.y + bounds.height / 2 + 24, id: 1 }])
  assert.equal(await state(`document.querySelector('.lui-sheet')?.hasPointerCapture(window.__touchPointerId)`), true)
  assert.equal(await state("document.querySelector('.lui-sheet')?.hasAttribute('data-swiping')"), true)
  await evaluate(`document.querySelector('.lui-sheet-handle').dispatchEvent(new PointerEvent('lostpointercapture', {
    bubbles: true, cancelable: false, isPrimary: true, pointerId: window.__touchPointerId, pointerType: 'touch',
  }))`)
  assert.equal(await state("document.querySelector('.lui-sheet')?.hasAttribute('data-swiping')"), true)
  await evaluate(`document.querySelector('.lui-sheet').dispatchEvent(new PointerEvent('pointercancel', {
    bubbles: true, cancelable: true, isPrimary: true, pointerId: window.__touchPointerId, pointerType: 'touch',
    clientX: 195, clientY: 350,
  }))`)
  assert.equal(await state("document.querySelector('.lui-sheet')?.hasAttribute('data-swiping')"), false)
  await touchEvent("touchEnd", [])
  await touchDrag(gestureHandle, { deltaY: 35 })
  assert.equal(await state("document.querySelectorAll('.lui-modal-layer[data-open]').length"), 1)
  await touchDrag(gestureHandle, { deltaY: 60, duration: 40 })
  await waitForClosed()
})
