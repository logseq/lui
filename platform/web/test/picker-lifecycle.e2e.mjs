import assert from "node:assert/strict"
import { once } from "node:events"
import path from "node:path"
import { fileURLToPath } from "node:url"
import test, { after, before } from "node:test"

import { createStaticServer } from "../../../tooling/serve_web.mjs"
import { createPlaywrightSession } from "./playwright-session.mjs"

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../../..")
let origin
let server
let session

async function openPickerPage() {
  await session.command("set", "viewport", "1280", "900")
  await session.command("open", `${origin}/platform/web/test/fixtures/picker-regression.html`)
  await session.command("wait", "--fn", "window.audit !== undefined")
}

async function state(expression) {
  return JSON.parse(JSON.parse(await session.evaluate(`JSON.stringify(${expression})`)))
}

async function waitFor(expression) {
  await session.command("wait", "--fn", expression)
}

async function openSelectWithKey(key = "ArrowDown") {
  await session.page.locator("#picker-select").focus()
  await session.command("press", key)
  await waitFor("document.querySelector('.lui-dropdown-menu[data-open]')")
}

before(async () => {
  server = createStaticServer(root)
  server.listen(0, "127.0.0.1")
  await once(server, "listening")
  origin = `http://127.0.0.1:${server.address().port}`
  session = await createPlaywrightSession()
})

after(async () => {
  await session?.close()
  if (server?.listening) {
    server.close()
    await once(server, "close")
  }
})

test("Select keyboard navigation uses selected and enabled rows, typeahead and Enter press", async () => {
  await openPickerPage()
  await openSelectWithKey()
  assert.equal(await state("document.activeElement.textContent.trim()"), "Beta")

  await session.command("press", "Escape")
  await waitFor("!document.querySelector('.lui-dropdown-menu[data-open]')")
  await session.evaluate("window.audit.setSelectText('')")

  await openSelectWithKey("ArrowDown")
  assert.equal(await state("document.activeElement.textContent.trim()"), "Alpha")
  await session.command("press", "Escape")
  await waitFor("!document.querySelector('.lui-dropdown-menu[data-open]')")

  await openSelectWithKey("ArrowUp")
  assert.equal(await state("document.activeElement.textContent.trim()"), "Delta")
  await session.command("press", "Escape")
  await waitFor("!document.querySelector('.lui-dropdown-menu[data-open]')")

  await session.page.locator("#picker-select").focus()
  await session.command("press", "c")
  await waitFor("document.querySelector('.lui-dropdown-menu[data-open]')")
  assert.equal(await state("document.activeElement.textContent.trim()"), "Charlie")
  const option = await state("window.audit.menuItems.find(item => item.text === 'Charlie')")
  await session.command("press", "Enter")
  await waitFor("!document.querySelector('.lui-dropdown-menu[data-open]')")
  assert.equal(await state("document.querySelector('#picker-select').textContent.trim()"), "Charlie")
  assert.equal(await state(`window.audit.events.filter(event => event.TAG === 0 && event._0 === ${option.id}).length`), 1)
})

test("Select queues one open press until delayed model mounting finishes", async () => {
  await openPickerPage()
  await session.evaluate("window.audit.delayNextMount()")
  await session.page.locator("#picker-select").focus()
  await session.command("press", "ArrowDown")
  await waitFor("document.querySelector('.lui-dropdown-menu[data-open]')")
  assert.equal(await state("window.audit.isMenuMounted()"), true)
  assert.equal(await state(`window.audit.events.filter(event => event.TAG === 0 && event._0 === window.audit.selectId).length`), 1)
})

test("Select ignores modified, composing and disabled activation", async () => {
  await openPickerPage()
  await session.page.locator("#picker-select").focus()
  await session.page.locator("#picker-select").evaluate(element => {
    for (const options of [
      { key: "ArrowDown", ctrlKey: true },
      { key: "ArrowDown", altKey: true },
      { key: "ArrowDown", isComposing: true },
    ]) element.dispatchEvent(new KeyboardEvent("keydown", { ...options, bubbles: true, cancelable: true }))
  })
  await session.evaluate("window.audit.setEnabled(window.audit.selectId, false)")
  await session.page.locator("#picker-select").evaluate(element => {
    element.dispatchEvent(new KeyboardEvent("keydown", { key: "ArrowDown", bubbles: true, cancelable: true }))
    element.dispatchEvent(new PointerEvent("pointerdown", { bubbles: true, cancelable: true, pointerType: "mouse", button: 0, buttons: 1 }))
  })
  assert.equal(await state("document.querySelector('.lui-dropdown-menu[data-open]')"), null)
  assert.equal(await state(`window.audit.events.filter(event => event.TAG === 0 && event._0 === window.audit.selectId).length`), 0)
})

test("Select mouse hold emits once and pointer cancellation does not suppress keyboard click", async () => {
  await openPickerPage()
  const trigger = session.page.locator("#picker-select")
  const bounds = await trigger.boundingBox()
  assert.ok(bounds)
  await session.page.mouse.move(bounds.x + bounds.width / 2, bounds.y + bounds.height / 2)
  await session.page.mouse.down()
  await session.page.waitForTimeout(150)
  await session.page.mouse.up()
  await waitFor("document.querySelector('.lui-dropdown-menu[data-open]')")
  assert.equal(await state(`window.audit.events.filter(event => event.TAG === 0 && event._0 === window.audit.selectId).length`), 1)

  await trigger.evaluate(element => element.dispatchEvent(new PointerEvent("pointerdown", { bubbles: true, cancelable: true, pointerType: "mouse", pointerId: 1, button: 0, buttons: 1 })))
  await trigger.evaluate(element => element.dispatchEvent(new PointerEvent("pointercancel", { bubbles: true, pointerType: "mouse", pointerId: 1 })))
  await session.evaluate("window.audit.clearEvents()")
  await trigger.focus()
  await trigger.evaluate(element => {
    window.audit.keyboardClickDetails = []
    element.addEventListener("click", event => window.audit.keyboardClickDetails.push(event.detail), { once: true })
  })
  await session.command("press", "Space")
  assert.deepEqual(await state("window.audit.keyboardClickDetails"), [0])
  assert.equal(await state(`window.audit.events.filter(event => event.TAG === 0 && event._0 === window.audit.selectId).length`), 1)
})

test("Select touch opens on completed click while Combobox retains input focus", async () => {
  await openPickerPage()
  const input = session.page.locator("#picker-combo input")
  await input.focus()
  await session.page.locator("#picker-combo").evaluate(element => {
    const trigger = element.querySelector(".lui-combobox-trigger")
    trigger.dispatchEvent(new PointerEvent("pointerdown", { bubbles: true, cancelable: true, pointerType: "touch", pointerId: 7, button: 0, buttons: 1 }))
    trigger.dispatchEvent(new PointerEvent("pointerup", { bubbles: true, pointerType: "touch", pointerId: 7, button: 0 }))
  })
  assert.equal(await state("document.querySelector('.lui-dropdown-menu[data-open]')"), null)
  await session.page.locator("#picker-combo").evaluate(element => {
    element.querySelector(".lui-combobox-trigger").dispatchEvent(new MouseEvent("click", { bubbles: true, cancelable: true, detail: 1 }))
  })
  await waitFor("document.querySelector('.lui-dropdown-menu[data-open]')")
  assert.equal(await state("document.activeElement.matches('#picker-combo input')"), true)
  assert.equal(await state(`window.audit.events.filter(event => event.TAG === 0 && event._0 === window.audit.comboId).length`), 1)
})

test("Select Tab navigation closes options, outside clicks keep focus, Escape preserves the dialog", async () => {
  await openPickerPage()
  await openSelectWithKey()
  await session.command("press", "Tab")
  await waitFor("!document.querySelector('.lui-dropdown-menu[data-open]')")
  assert.equal(await state("document.activeElement.id"), "picker-after")

  await openSelectWithKey()
  await session.command("press", "Shift+Tab")
  await waitFor("!document.querySelector('.lui-dropdown-menu[data-open]')")
  assert.equal(await state("document.activeElement.id"), "picker-before")

  await openSelectWithKey()
  await session.page.getByRole("button", { name: "Outside target" }).click()
  await waitFor("!document.querySelector('.lui-dropdown-menu[data-open]')")
  assert.equal(await state("document.activeElement.id"), "picker-outside")

  await session.page.getByRole("button", { name: "Open dialog" }).click()
  await waitFor("document.querySelector('.lui-modal-layer[data-open]')")
  await session.page.locator("#dialog-select").focus()
  await session.command("press", "ArrowDown")
  await waitFor("document.querySelector('.lui-dropdown-menu[data-open]')")
  await session.evaluate("window.audit.clearEvents()")
  await session.command("press", "Escape")
  await waitFor("!document.querySelector('.lui-dropdown-menu[data-open]')")
  assert.equal(await state("document.querySelector('.lui-modal-layer[data-open]') !== null"), true)
  assert.equal(await state(`window.audit.events.filter(event => event.TAG === 7).length`), 1)
})

test("Combobox list navigation scrolls its popup and preserves highlighted option identity", async () => {
  await openPickerPage()
  const input = session.page.locator("#picker-combo input")
  await input.focus()
  await session.command("press", "ArrowDown")
  await waitFor("document.querySelector('.lui-dropdown-menu[data-open]')")
  for (let index = 0; index < 23; index++) await session.command("press", "ArrowDown")
  const activeId = await state("document.querySelector('[aria-activedescendant]')?.getAttribute('aria-activedescendant')")
  const scrollState = await state(`({
    activeText: document.getElementById(document.querySelector('[aria-activedescendant]')?.getAttribute('aria-activedescendant'))?.textContent.trim(),
    popupScrollTop: document.querySelector('.lui-dropdown-menu[data-open]')?.scrollTop,
    pageScrollY: window.scrollY,
  })`)
  assert.equal(scrollState.activeText, "Option 23")
  assert.ok(scrollState.popupScrollTop > 0)
  assert.equal(scrollState.pageScrollY, 0)

  await session.evaluate("window.audit.insertComboOption(0, 'Inserted option')")
  assert.equal(await state("document.querySelector('[aria-activedescendant]')?.getAttribute('aria-activedescendant')"), activeId)
  await session.evaluate("window.audit.removeComboOption(1)")
  assert.equal(await state("document.querySelector('[aria-activedescendant]')?.getAttribute('aria-activedescendant')"), activeId)
  const activeText = await state("document.getElementById(document.querySelector('[aria-activedescendant]')?.getAttribute('aria-activedescendant'))?.textContent.trim()")
  await session.evaluate(`window.audit.disableComboOption(${JSON.stringify(activeText)})`)
  const afterDisable = await state(`({
    activeText: document.getElementById(document.querySelector('[aria-activedescendant]')?.getAttribute('aria-activedescendant'))?.textContent.trim(),
    highlightedDisabled: [...document.querySelectorAll('[data-highlighted]')].some(item => item.getAttribute('aria-disabled') === 'true'),
  })`)
  assert.notEqual(afterDisable.activeText, activeText)
  assert.equal(afterDisable.highlightedDisabled, false)
  await session.evaluate("window.audit.disableAllComboOptions()")
  assert.equal(await state("document.querySelector('[aria-activedescendant]')?.getAttribute('aria-activedescendant') ?? null"), null)
  assert.equal(await state("document.querySelectorAll('[data-highlighted]').length"), 0)
})

test("Combobox composition patches retain the native input, draft and selection", async () => {
  await openPickerPage()
  await session.page.locator("#picker-combo input").evaluate(element => {
    element.focus()
    element.setSelectionRange(0, 0)
    window.audit.compositionInput = element
  })
  await session.page.locator("#picker-combo input").evaluate(element => {
    element.value = "draft文本"
    element.setSelectionRange(2, 5)
    element.dispatchEvent(new CompositionEvent("compositionstart", { bubbles: true }))
    element.dispatchEvent(new InputEvent("input", { bubbles: true, data: "draft文本", isComposing: true, inputType: "insertCompositionText" }))
  })
  await session.evaluate("window.audit.setText(window.audit.comboId, 'external value')")
  const duringComposition = await session.page.locator("#picker-combo input").evaluate(element => ({
    focused: document.activeElement === element,
    value: element.value,
    selectionStart: element.selectionStart,
    selectionEnd: element.selectionEnd,
    composing: document.querySelector("#picker-combo").hasAttribute("data-lui-composing"),
  }))
  assert.deepEqual(duringComposition, {
    focused: true,
    value: "draft文本",
    selectionStart: 2,
    selectionEnd: 5,
    composing: true,
  })

  await session.page.locator("#picker-combo input").evaluate(element => {
    element.dispatchEvent(new CompositionEvent("compositionend", { bubbles: true, data: "draft文本" }))
  })
  await session.evaluate("window.audit.setAccessibilityLabel(window.audit.comboId, 'Search catalog')")
  const afterComposition = await session.page.locator("#picker-combo input").evaluate(element => ({
    sameInput: element === window.audit.compositionInput,
    focused: document.activeElement === element,
    value: element.value,
    selectionStart: element.selectionStart,
    selectionEnd: element.selectionEnd,
  }))
  assert.equal(afterComposition.sameInput, true)
  assert.equal(afterComposition.focused, true)
  assert.equal(afterComposition.value, "draft文本")
  assert.equal(afterComposition.selectionStart, 2)
  assert.equal(afterComposition.selectionEnd, 5)
  assert.equal(await state(`window.audit.events.filter(event => event.TAG === 2 && event._0 === window.audit.comboId).length`), 1)
})

test("DropdownMenu submenu presence finishes on close and stale close cannot remove a reopened submenu", async () => {
  await openPickerPage()
  await session.evaluate("window.audit.enableSubmenu()")
  await openSelectWithKey()
  const more = session.page.locator(".lui-menu-item").filter({ hasText: "More" })
  await more.hover()
  await waitFor("document.querySelector('.lui-popup-positioner[data-submenu] .lui-dropdown-menu[data-open]')")

  await session.page.mouse.move(4, 4)
  await session.page.waitForTimeout(155)
  assert.equal(await state("document.querySelector('.lui-popup-positioner[data-submenu] .lui-dropdown-menu[data-ending-style]') !== null"), true)
  await more.hover()
  await session.page.waitForTimeout(170)
  assert.equal(await state("document.querySelector('.lui-popup-positioner[data-submenu] .lui-dropdown-menu[data-open]') !== null"), true)
  assert.equal(await state("document.querySelector('.lui-popup-positioner[data-submenu] .lui-dropdown-menu[data-ending-style]')"), null)

  await session.page.mouse.move(4, 4)
  await session.page.waitForTimeout(300)
  assert.equal(await state("document.querySelector('.lui-popup-positioner[data-submenu] .lui-dropdown-menu[data-open]')"), null)
  assert.equal(await state("document.querySelector('.lui-popup-positioner[data-submenu] .lui-dropdown-menu[data-ending-style]')"), null)
})
