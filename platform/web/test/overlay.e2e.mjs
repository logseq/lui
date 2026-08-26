import assert from "node:assert/strict"
import { execFile } from "node:child_process"
import { once } from "node:events"
import { promisify } from "node:util"
import test, { after, before } from "node:test"

import { createStaticServer } from "../../../tooling/serve_web.mjs"

const execFileAsync = promisify(execFile)
const projectRoot = new URL("../../../", import.meta.url)
const session = `lui-overlay-${process.pid}`
let origin
let server

async function browser(...args) {
  const { stdout } = await execFileAsync(
    "agent-browser",
    ["--session", session, ...args],
    { cwd: projectRoot, maxBuffer: 4 * 1024 * 1024 },
  )
  return stdout.trim()
}

async function evaluate(source) {
  return browser("eval", "-b", Buffer.from(source).toString("base64"))
}

async function openGalleryPage(name) {
  await browser("set", "media", "light")
  await browser("set", "viewport", "1280", "900")
  await browser("open", `${origin}/examples/components/web/index.html`)
  await browser("wait", "--load", "networkidle")
  await evaluate(`
    [...document.querySelectorAll('nav button')]
      .find((node) => node.textContent === ${JSON.stringify(name)})
      ?.click()
  `)
}

async function clickButton(name) {
  await evaluate(`
    (() => {
      const button = [...document.querySelectorAll('button')]
        .find((node) => node.textContent.trim() === ${JSON.stringify(name)} && node.getBoundingClientRect().width > 0)
      button?.focus()
      button?.click()
    })()
  `)
}

async function state(expression) {
  const output = await evaluate(`JSON.stringify(${expression})`)
  return JSON.parse(JSON.parse(output))
}

before(async () => {
  server = createStaticServer(new URL("../../../", import.meta.url).pathname)
  server.listen(0, "127.0.0.1")
  await once(server, "listening")
  origin = `http://127.0.0.1:${server.address().port}`
})

after(async () => {
  await browser("close").catch(() => {})
  server.close()
  await once(server, "close")
})

test("Dialog is a portaled modal with model-owned dismissal and focus restoration", async () => {
  await openGalleryPage("Dialog")
  await clickButton("Open dialog")

  assert.deepEqual(
    await state(`(() => {
      const layer = document.querySelector('.lui-modal-layer:not([hidden])')
      const surface = layer?.querySelector('[role=dialog]')
      return {
        layers: document.querySelectorAll('.lui-modal-layer:not([hidden])').length,
        modal: surface?.getAttribute('aria-modal'),
        className: surface?.className,
        hostInert: document.querySelector('#app')?.hasAttribute('inert'),
        focusInside: Boolean(surface?.contains(document.activeElement)),
        focusedPlaceholder: document.activeElement?.getAttribute('placeholder'),
        open: layer?.hasAttribute('data-open'),
      }
    })()`),
    {
      layers: 1,
      modal: "true",
      className: "lui-dialog",
      hostInert: true,
      focusInside: true,
      focusedPlaceholder: "Note name",
      open: true,
    },
  )

  await browser("press", "Shift+Tab")
  assert.equal(await state(`document.activeElement?.textContent?.trim()`), "Save")
  await browser("press", "Tab")
  assert.equal(await state(`document.activeElement?.getAttribute('placeholder')`), "Note name")

  await evaluate(`(() => {
    window.__luiDialogExitObserved = false
    const layer = document.querySelector('.lui-modal-layer')
    new MutationObserver(() => {
      if (layer?.hasAttribute('data-ending-style')) window.__luiDialogExitObserved = true
    }).observe(layer, { attributes: true })
  })()`)
  const dialogExit = await state(`(() => {
    document.activeElement?.dispatchEvent(
      new KeyboardEvent('keydown', { key: 'Escape', bubbles: true, cancelable: true }),
    )
    const layer = document.querySelector('.lui-modal-layer[data-ending-style]')
    const endingObserved = Boolean(layer)
    layer?.querySelector('.lui-modal-backdrop')?.dispatchEvent(
      new TransitionEvent('transitionend', {
        bubbles: true,
        propertyName: 'opacity',
      }),
    )
    return {
      endingObserved,
      remainingLayers: document.querySelectorAll('.lui-modal-layer').length,
    }
  })()`)
  assert.deepEqual(dialogExit, { endingObserved: true, remainingLayers: 0 })
  assert.deepEqual(
    await state(`({
      openLayers: document.querySelectorAll('.lui-modal-layer[data-open]').length,
      exitObserved: window.__luiDialogExitObserved,
      hostInert: document.querySelector('#app')?.hasAttribute('inert'),
      focus: document.activeElement?.textContent?.trim(),
    })`),
    { openLayers: 0, exitObserved: true, hostInert: false, focus: "Open dialog" },
  )
  assert.equal(await state(`document.querySelectorAll('.lui-modal-layer').length`), 0)

  await clickButton("Open dialog")
  await evaluate(`document.querySelector('.lui-modal-backdrop')?.click()`)
  await browser("wait", "180")
  assert.equal(
    await state(`document.querySelectorAll('.lui-modal-layer:not([hidden])').length`),
    0,
  )
})

test("Sheet uses the same modal lifecycle with its own native surface", async () => {
  await openGalleryPage("Sheet")
  await clickButton("Open sheet")

  assert.deepEqual(
    await state(`(() => {
      const layer = document.querySelector('.lui-modal-layer:not([hidden])')
      const surface = layer?.querySelector('[role=dialog]')
      return {
        layers: document.querySelectorAll('.lui-modal-layer:not([hidden])').length,
        className: surface?.className,
        modal: surface?.getAttribute('aria-modal'),
        hostInert: document.querySelector('#app')?.hasAttribute('inert'),
        open: layer?.hasAttribute('data-open'),
      }
    })()`),
    { layers: 1, className: "lui-sheet", modal: "true", hostInert: true, open: true },
  )

  assert.deepEqual(
    await state(`(() => {
      document.activeElement?.dispatchEvent(
        new KeyboardEvent('keydown', { key: 'Escape', bubbles: true, cancelable: true }),
      )
      const layer = document.querySelector('.lui-modal-layer[data-ending-style]')
      const endingObserved = Boolean(layer)
      layer?.querySelector('.lui-sheet')?.dispatchEvent(
        new TransitionEvent('transitioncancel', {
          bubbles: true,
          propertyName: 'transform',
        }),
      )
      return {
        endingObserved,
        remainingLayers: document.querySelectorAll('.lui-modal-layer').length,
      }
    })()`),
    { endingObserved: true, remainingLayers: 0 },
  )
})

test("Reduced motion removes a closing Dialog without waiting for a fallback", async () => {
  await openGalleryPage("Dialog")
  await browser("set", "media", "light", "reduced-motion")
  await clickButton("Open dialog")

  assert.equal(
    await state(`(() => {
      document.activeElement?.dispatchEvent(
        new KeyboardEvent('keydown', { key: 'Escape', bubbles: true, cancelable: true }),
      )
      return document.querySelectorAll('.lui-modal-layer').length
    })()`),
    0,
  )
  await browser("set", "media", "light")
})

test("Sheet preserves native Chinese composition through visual viewport changes", async () => {
  await openGalleryPage("Sheet")
  await browser("set", "viewport", "390", "844")
  await clickButton("Open sheet")

  await evaluate(`(() => {
    const input = document.querySelector('.lui-sheet input[placeholder="Share link"]')
    window.__sheetCompositionInput = input
    input.focus()
    input.dispatchEvent(new CompositionEvent('compositionstart', {
      bubbles: true,
      data: '',
    }))
    input.value = '中'
    input.dispatchEvent(new InputEvent('input', {
      bubbles: true,
      data: '中',
      inputType: 'insertCompositionText',
      isComposing: true,
    }))
  })()`)

  await browser("set", "viewport", "390", "520")
  await browser("wait", "50")
  assert.deepEqual(
    await state(`(() => {
      const input = document.querySelector('.lui-sheet input[placeholder="Share link"]')
      const sheet = document.querySelector('.lui-sheet')
      return {
        sameInput: input === window.__sheetCompositionInput,
        focused: document.activeElement === input,
        value: input?.value,
        insideViewport: (sheet?.getBoundingClientRect().bottom ?? innerHeight + 1) <= innerHeight,
      }
    })()`),
    { sameInput: true, focused: true, value: "中", insideViewport: true },
  )

  assert.deepEqual(
    await state(`(() => {
      const input = window.__sheetCompositionInput
      input.value = '中文'
      input.dispatchEvent(new CompositionEvent('compositionend', {
        bubbles: true,
        data: '中文',
      }))
      input.dispatchEvent(new InputEvent('input', {
        bubbles: true,
        data: '中文',
        inputType: 'insertFromComposition',
        isComposing: false,
      }))
      return {
        sameInput: document.querySelector('.lui-sheet input[placeholder="Share link"]') === input,
        focused: document.activeElement === input,
        value: input.value,
      }
    })()`),
    { sameInput: true, focused: true, value: "中文" },
  )
})

test("Compact Sheet arbitrates scroll, direction, distance, and velocity", async () => {
  await openGalleryPage("Sheet")
  await browser("set", "viewport", "390", "844")
  await clickButton("Open sheet")
  await browser("wait", "100")

  const compactSheet = await state(`(() => {
      const sheet = document.querySelector('.lui-sheet')
      const bounds = sheet?.getBoundingClientRect()
      return {
        bottomAligned: Math.abs((bounds?.bottom ?? 0) - innerHeight) < 1,
        fullWidth: Math.abs((bounds?.width ?? 0) - innerWidth) < 1,
        height: Math.round(bounds?.height ?? 0),
        viewportHeight: innerHeight,
      }
    })()`)
  assert.equal(compactSheet.bottomAligned, true)
  assert.equal(compactSheet.fullWidth, true)
  assert.ok(compactSheet.height > 0 && compactSheet.height < compactSheet.viewportHeight)

  await evaluate(`(() => {
    const sheet = document.querySelector('.lui-sheet')
    const dispatch = (type, y) => sheet.dispatchEvent(new PointerEvent(type, {
      bubbles: true,
      cancelable: true,
      isPrimary: true,
      pointerId: 41,
      pointerType: 'touch',
      clientX: 190,
      clientY: y,
      button: 0,
      buttons: type === 'pointerup' ? 0 : 1,
    }))
    dispatch('pointerdown', 200)
    dispatch('pointermove', 235)
    dispatch('pointerup', 235)
  })()`)
  assert.equal(await state(`document.querySelector('.lui-sheet')?.hasAttribute('data-swiping')`), false)
  assert.equal(await state(`document.querySelectorAll('.lui-modal-layer[data-open]').length`), 1)

  await evaluate(`(() => {
    const sheet = document.querySelector('.lui-sheet')
    const dispatch = (type, x, y) => sheet.dispatchEvent(new PointerEvent(type, {
      bubbles: true,
      cancelable: true,
      isPrimary: true,
      pointerId: 43,
      pointerType: 'touch',
      clientX: x,
      clientY: y,
      button: 0,
      buttons: type === 'pointerup' ? 0 : 1,
    }))
    dispatch('pointerdown', 40, 180)
    dispatch('pointermove', 180, 190)
    dispatch('pointermove', 180, 540)
    dispatch('pointerup', 180, 540)
  })()`)
  assert.equal(await state(`document.querySelectorAll('.lui-modal-layer[data-open]').length`), 1)

  await evaluate(`(() => {
    const sheet = document.querySelector('.lui-sheet')
    const scroller = document.createElement('div')
    const content = document.createElement('div')
    scroller.style.cssText = 'height:40px;overflow-y:auto'
    content.style.height = '200px'
    scroller.append(content)
    sheet.append(scroller)
    scroller.scrollTop = 20
    const dispatch = (type, y) => content.dispatchEvent(new PointerEvent(type, {
      bubbles: true,
      cancelable: true,
      isPrimary: true,
      pointerId: 44,
      pointerType: 'touch',
      clientX: 190,
      clientY: y,
      button: 0,
      buttons: type === 'pointerup' ? 0 : 1,
    }))
    dispatch('pointerdown', 180)
    dispatch('pointermove', 540)
    dispatch('pointerup', 540)
    scroller.remove()
  })()`)
  assert.equal(await state(`document.querySelectorAll('.lui-modal-layer[data-open]').length`), 1)

  await evaluate(`(() => {
    const sheet = document.querySelector('.lui-sheet')
    const dispatch = (type, y) => sheet.dispatchEvent(new PointerEvent(type, {
      bubbles: true,
      cancelable: true,
      isPrimary: true,
      pointerId: 42,
      pointerType: 'touch',
      clientX: 190,
      clientY: y,
      button: 0,
      buttons: type === 'pointerup' ? 0 : 1,
    }))
    dispatch('pointerdown', 180)
    dispatch('pointermove', 520)
    dispatch('pointercancel', 560)
  })()`)
  assert.equal(await state(`document.querySelector('.lui-sheet')?.hasAttribute('data-swiping')`), false)
  assert.equal(await state(`document.querySelectorAll('.lui-modal-layer[data-open]').length`), 1)

  const dismissedSheetState = await state(`(() => {
    const sheet = document.querySelector('.lui-sheet')
    const dispatch = (type, y) => sheet.dispatchEvent(new PointerEvent(type, {
      bubbles: true,
      cancelable: true,
      isPrimary: true,
      pointerId: 45,
      pointerType: 'touch',
      clientX: 190,
      clientY: y,
      button: 0,
      buttons: type === 'pointerup' ? 0 : 1,
    }))
    dispatch('pointerdown', 180)
    dispatch('pointermove', 240)
    dispatch('pointerup', 240)
    return {
      open: document.querySelectorAll('.lui-modal-layer[data-open]').length,
      ending: document.querySelectorAll('.lui-modal-layer[data-ending-style]').length,
    }
  })()`)
  assert.deepEqual(dismissedSheetState, { open: 0, ending: 1 })
})

test("Button long press uses one movement-safe Pointer Events lifecycle", async () => {
  await openGalleryPage("Button")

  await evaluate(`(() => {
    const button = [...document.querySelectorAll('button')]
      .find((node) => node.textContent.trim() === 'Primary')
    button.dispatchEvent(new PointerEvent('pointerdown', {
      bubbles: true, pointerId: 101, pointerType: 'touch',
      clientX: 100, clientY: 200, button: 0, buttons: 1,
    }))
  })()`)
  await browser("wait", "380")
  await evaluate(`document.querySelector('button[data-long-press-enabled]')?.dispatchEvent(
    new PointerEvent('pointerup', { bubbles: true, pointerId: 101, pointerType: 'touch' }),
  )`)
  assert.equal(await state(`document.body.textContent.includes('Controls are disabled.')`), true)

  await clickButton("Toggle disabled")
  assert.equal(await state(`document.body.textContent.includes('Controls are disabled.')`), false)

  await evaluate(`(() => {
    const button = document.querySelector('button[data-long-press-enabled]')
    const pointer = (type, x, y) => new PointerEvent(type, {
      bubbles: true, pointerId: 102, pointerType: 'touch',
      clientX: x, clientY: y, button: 0, buttons: type === 'pointerup' ? 0 : 1,
    })
    button.dispatchEvent(pointer('pointerdown', 100, 200))
    button.dispatchEvent(pointer('pointermove', 120, 200))
  })()`)
  await browser("wait", "380")
  await evaluate(`document.querySelector('button[data-long-press-enabled]')?.dispatchEvent(
    new PointerEvent('pointerup', { bubbles: true, pointerId: 102, pointerType: 'touch' }),
  )`)
  assert.equal(await state(`document.body.textContent.includes('Controls are disabled.')`), false)

  await evaluate(`(() => {
    const button = document.querySelector('button[data-long-press-enabled]')
    button.dispatchEvent(new PointerEvent('pointerdown', {
      bubbles: true, pointerId: 103, pointerType: 'mouse',
      clientX: 100, clientY: 200, button: 0, buttons: 1,
    }))
    button.dispatchEvent(new PointerEvent('lostpointercapture', {
      bubbles: true, pointerId: 103, pointerType: 'mouse',
    }))
  })()`)
  await browser("wait", "380")
  assert.equal(await state(`document.body.textContent.includes('Controls are disabled.')`), false)

  await evaluate(`(() => {
    const button = document.querySelector('button[data-long-press-enabled]')
    button.dispatchEvent(new PointerEvent('pointerdown', {
      bubbles: true, pointerId: 104, pointerType: 'touch',
      clientX: 100, clientY: 200, button: 0, buttons: 1,
    }))
    ;[...document.querySelectorAll('nav button')]
      .find((node) => node.textContent === 'Row')?.click()
  })()`)
  await browser("wait", "380")
  await evaluate(`[...document.querySelectorAll('nav button')]
    .find((node) => node.textContent === 'Button')?.click()`)
  assert.equal(await state(`document.body.textContent.includes('Controls are disabled.')`), false)
})

test("Tree click toggles disclosure and keeps selection model-owned", async () => {
  await openGalleryPage("Tree")

  assert.deepEqual(
    await state(`(() => {
      const item = document.querySelector('[role=treeitem]')
      return {
        expanded: item?.getAttribute('aria-expanded'),
        children: document.querySelectorAll('[role=treeitem]').length,
      }
    })()`),
    { expanded: "false", children: 1 },
  )

  await evaluate(`document.querySelector('[role=treeitem]')?.click()`)

  assert.deepEqual(
    await state(`(() => {
      const items = [...document.querySelectorAll('[role=treeitem]')]
      return {
        expanded: items[0]?.getAttribute('aria-expanded'),
        labels: items.map((item) => item.textContent.trim()),
        selected: items
          .filter((item) => item.getAttribute('aria-selected') === 'true')
          .map((item) => item.textContent.trim()),
      }
    })()`),
    {
      expanded: "true",
      labels: ["Documents", "Quarterly report.md", "Launch checklist.md"],
      selected: ["Quarterly report.md"],
    },
  )
})

test("Tree is fully operable with one keyboard tab stop", async () => {
  await openGalleryPage("Tree")
  await evaluate(`document.querySelector('[role=treeitem]')?.focus()`)

  await browser("press", "ArrowRight")
  assert.deepEqual(
    await state(`(() => {
      const items = [...document.querySelectorAll('[role=treeitem]')]
      return {
        labels: items.map((item) => item.textContent.trim()),
        tabStops: items.filter((item) => item.tabIndex === 0).map((item) => item.textContent.trim()),
        focus: document.activeElement?.textContent.trim(),
      }
    })()`),
    {
      labels: ["Documents", "Quarterly report.md", "Launch checklist.md"],
      tabStops: ["Documents"],
      focus: "Documents",
    },
  )

  await browser("press", "ArrowRight")
  assert.equal(await state(`document.activeElement?.textContent.trim()`), "Quarterly report.md")
  await browser("press", "ArrowDown")
  assert.equal(await state(`document.activeElement?.textContent.trim()`), "Launch checklist.md")
  await browser("press", "Home")
  assert.equal(await state(`document.activeElement?.textContent.trim()`), "Documents")
  await browser("press", "End")
  assert.equal(await state(`document.activeElement?.textContent.trim()`), "Launch checklist.md")
  await browser("press", "ArrowLeft")
  assert.equal(await state(`document.activeElement?.textContent.trim()`), "Documents")
  await browser("press", "ArrowLeft")
  assert.deepEqual(
    await state(`({
      expanded: document.querySelector('[role=treeitem]')?.getAttribute('aria-expanded'),
      children: document.querySelectorAll('[role=treeitem]').length,
      focus: document.activeElement?.textContent.trim(),
    })`),
    { expanded: "false", children: 1, focus: "Documents" },
  )
})

test("Tree typeahead wraps visible items and supports rapid prefixes", async () => {
  await openGalleryPage("Tree")
  await evaluate(`document.querySelector('[role=treeitem]')?.focus()`)
  await browser("press", "ArrowRight")
  await browser("press", "ArrowRight")
  assert.equal(await state(`document.activeElement?.textContent.trim()`), "Quarterly report.md")

  await browser("press", "l")
  assert.equal(await state(`document.activeElement?.textContent.trim()`), "Launch checklist.md")
  await browser("wait", "550")
  await browser("press", "q")
  await browser("press", "u")
  assert.equal(await state(`document.activeElement?.textContent.trim()`), "Quarterly report.md")

  await browser("wait", "550")
  await browser("press", "d")
  assert.equal(await state(`document.activeElement?.textContent.trim()`), "Documents")
  await browser("wait", "550")
  await browser("press", "z")
  assert.equal(await state(`document.activeElement?.textContent.trim()`), "Documents")
  await evaluate(`document.activeElement?.dispatchEvent(
    new KeyboardEvent('keydown', {
      key: 'k',
      ctrlKey: true,
      bubbles: true,
      cancelable: true,
    }),
  )`)
  assert.equal(await state(`document.activeElement?.textContent.trim()`), "Documents")

  await browser("press", "ArrowLeft")
  assert.equal(await state(`document.querySelectorAll('[role=treeitem]').length`), 1)
  await browser("wait", "550")
  await browser("press", "q")
  assert.equal(await state(`document.activeElement?.textContent.trim()`), "Documents")
})

test("DropdownMenu typeahead moves focus to the matching enabled item", async () => {
  await openGalleryPage("DropdownMenu")
  await evaluate(`[
    ...document.querySelectorAll('.lui-menu-item'),
  ].find((item) => item.textContent.trim() === 'Production'
    && item.getBoundingClientRect().width > 0)?.focus()`)
  assert.equal(await state(`document.activeElement?.textContent.trim()`), "Production")

  await evaluate(`document.activeElement?.dispatchEvent(
    new KeyboardEvent('keydown', { key: 's', bubbles: true, cancelable: true }),
  )`)
  assert.equal(await state(`document.activeElement?.textContent.trim()`), "Staging")
})

test("Nested menu keeps its right-side submenu open through the pointer corridor", async () => {
  await openGalleryPage("DropdownMenu")

  assert.equal(
    await state(`(() => {
      const trigger = [...document.querySelectorAll('.lui-menu-item')]
        .find((item) => item.textContent.includes('More environments')
          && item.getBoundingClientRect().width > 0)
      trigger?.dispatchEvent(new MouseEvent('mouseenter', {
        clientX: trigger.getBoundingClientRect().right,
        clientY: trigger.getBoundingClientRect().top
          + trigger.getBoundingClientRect().height / 2,
      }))
      return trigger?.getAttribute('aria-expanded')
    })()`),
    "true",
  )
  await browser("wait", "30")

  const side = await state(`(() => {
    const trigger = [...document.querySelectorAll('.lui-menu-item')]
      .find((item) => item.textContent.includes('More environments')
        && item.getBoundingClientRect().width > 0)
    const submenu = [...document.querySelectorAll('.lui-popup-positioner[data-submenu]')]
      .find((node) => !node.hasAttribute('hidden')
        && node.textContent.includes('Production region'))
    const popup = submenu?.querySelector('.lui-dropdown-menu')
    const triggerBounds = trigger?.getBoundingClientRect()
    const popupBounds = popup?.getBoundingClientRect()
    window.__submenuCorridor = {
      startX: triggerBounds?.right,
      startY: (triggerBounds?.top ?? 0) + (triggerBounds?.height ?? 0) / 2,
      endX: popupBounds?.left,
      endY: (popupBounds?.top ?? 0) + (popupBounds?.height ?? 0) / 2,
    }
    trigger?.dispatchEvent(new MouseEvent('mouseleave', {
      clientX: window.__submenuCorridor.startX,
      clientY: window.__submenuCorridor.startY,
      relatedTarget: document.body,
    }))
    ;[0.35, 0.7].forEach((progress, index) => {
      setTimeout(() => {
        const point = window.__submenuCorridor
        document.dispatchEvent(new MouseEvent('mousemove', {
          bubbles: true,
          clientX: point.startX + (point.endX - point.startX) * progress,
          clientY: point.startY + (point.endY - point.startY) * progress,
        }))
      }, index * 70)
    })
    setTimeout(() => {
      window.__submenuCorridorResult = {
        expanded: trigger?.getAttribute('aria-expanded'),
        open: popup?.hasAttribute('data-open'),
      }
    }, 180)
    return submenu?.getAttribute('data-side')
  })()`)
  assert.equal(side, "right")
  await browser("wait", "230")

  assert.deepEqual(
    await state(`window.__submenuCorridorResult`),
    { expanded: "true", open: true },
  )

  await evaluate(`[...document.querySelectorAll('.lui-popup-positioner[data-submenu]')]
    .find((node) => !node.hasAttribute('hidden')
      && node.textContent.includes('Production region'))
    ?.querySelector('.lui-dropdown-menu')
    ?.dispatchEvent(new MouseEvent('mouseenter'))`)

  await evaluate(`(() => {
    const trigger = [...document.querySelectorAll('.lui-menu-item')]
      .find((item) => item.textContent.includes('More environments')
        && item.getBoundingClientRect().width > 0)
    const bounds = trigger?.getBoundingClientRect()
    trigger?.dispatchEvent(new MouseEvent('mouseenter'))
    trigger?.dispatchEvent(new MouseEvent('mouseleave', {
      clientX: bounds?.left,
      clientY: (bounds?.top ?? 0) + (bounds?.height ?? 0) / 2,
      relatedTarget: document.body,
    }))
    document.dispatchEvent(new MouseEvent('mousemove', {
      bubbles: true,
      clientX: (bounds?.left ?? 0) - 40,
      clientY: (bounds?.top ?? 0) - 40,
    }))
  })()`)
  await browser("wait", "150")
  assert.equal(
    await state(`[...document.querySelectorAll('.lui-popup-positioner[data-submenu]')]
      .find((node) => !node.hasAttribute('hidden')
        && node.textContent.includes('Production region'))
      ?.querySelector('.lui-dropdown-menu')
      ?.hasAttribute('data-open')`),
    false,
  )
})

test("Nested menu corridor follows a submenu that flips to the left", async () => {
  await openGalleryPage("Select")
  await browser("set", "viewport", "480", "720")
  await evaluate(`(() => {
    const select = document.querySelector('.lui-select')
    Object.assign(select.style, {
      position: 'fixed',
      right: '4px',
      bottom: '160px',
      width: '180px',
      zIndex: '1',
    })
    select.focus()
  })()`)
  await browser("press", "Enter")
  await browser("wait", "30")

  assert.equal(
    await state(`(() => {
      const rootPopup = document.getElementById(
        document.querySelector('.lui-select')?.getAttribute('aria-controls'),
      )
      const trigger = [...(rootPopup?.querySelectorAll('.lui-menu-item') ?? [])]
        .find((item) => item.textContent.includes('More environments'))
      trigger?.dispatchEvent(new MouseEvent('mouseenter', {
        clientX: trigger.getBoundingClientRect().left,
        clientY: trigger.getBoundingClientRect().top
          + trigger.getBoundingClientRect().height / 2,
      }))
      return trigger?.getAttribute('aria-expanded')
    })()`),
    "true",
  )
  await browser("wait", "30")

  assert.equal(
    await state(`(() => {
      const rootPopup = document.getElementById(
        document.querySelector('.lui-select')?.getAttribute('aria-controls'),
      )
      const trigger = [...(rootPopup?.querySelectorAll('.lui-menu-item') ?? [])]
        .find((item) => item.textContent.includes('More environments'))
      const submenu = [...document.querySelectorAll('.lui-popup-positioner[data-submenu]')]
        .find((node) => !node.hasAttribute('hidden')
          && node.textContent.includes('Production region'))
      const popup = submenu?.querySelector('.lui-dropdown-menu')
      const triggerBounds = trigger?.getBoundingClientRect()
      const popupBounds = popup?.getBoundingClientRect()
      window.__flippedSubmenuCorridor = {
        startX: triggerBounds?.left,
        startY: (triggerBounds?.top ?? 0) + (triggerBounds?.height ?? 0) / 2,
        endX: popupBounds?.right,
        endY: (popupBounds?.top ?? 0) + (popupBounds?.height ?? 0) / 2,
      }
      trigger?.dispatchEvent(new MouseEvent('mouseleave', {
        clientX: window.__flippedSubmenuCorridor.startX,
        clientY: window.__flippedSubmenuCorridor.startY,
        relatedTarget: document.body,
      }))
      ;[0.4, 0.8].forEach((progress, index) => {
        setTimeout(() => {
          const point = window.__flippedSubmenuCorridor
          document.dispatchEvent(new MouseEvent('mousemove', {
            bubbles: true,
            clientX: point.startX + (point.endX - point.startX) * progress,
            clientY: point.startY + (point.endY - point.startY) * progress,
          }))
        }, index * 70)
      })
      setTimeout(() => {
        window.__flippedSubmenuCorridorOpen = popup?.hasAttribute('data-open')
      }, 180)
      return submenu?.getAttribute('data-side')
    })()`),
    "left",
  )
  await browser("wait", "230")

  assert.equal(
    await state(`window.__flippedSubmenuCorridorOpen`),
    true,
  )
})

test("Select keyboard navigation enters submenus and restores trigger focus", async () => {
  await openGalleryPage("Select")
  await evaluate(`(() => {
    window.__selectStartingObserved = false
    window.__selectEndingObserved = false
    new MutationObserver((records) => {
      for (const record of records) {
        const popup = record.target?.classList?.contains('lui-dropdown-menu')
          ? record.target
          : document.querySelector('.lui-dropdown-menu')
        if (popup?.hasAttribute('data-starting-style')) window.__selectStartingObserved = true
        if (popup?.hasAttribute('data-ending-style')) window.__selectEndingObserved = true
      }
    }).observe(document.querySelector('.lui-popup-portal'), {
      attributes: true,
      childList: true,
      subtree: true,
    })
  })()`)
  await evaluate(`document.querySelector('.lui-select')?.focus()`)
  await browser("press", "Enter")

  assert.deepEqual(
    await state(`({
      expanded: document.querySelector('.lui-select')?.getAttribute('aria-expanded'),
      focus: document.activeElement?.textContent.trim(),
      focusClass: document.activeElement?.className,
      startingObserved: window.__selectStartingObserved,
      listbox: (() => {
        const trigger = document.querySelector('.lui-select')
        window.__selectPopupID = trigger?.getAttribute('aria-controls')
        return document.getElementById(window.__selectPopupID)?.getAttribute('role')
      })(),
    })`),
    {
      expanded: "true",
      focus: "Production",
      focusClass: "lui-menu-item",
      startingObserved: true,
      listbox: "listbox",
    },
  )

  await browser("press", "ArrowDown")
  assert.equal(await state(`document.activeElement?.textContent.trim()`), "Staging")
  await evaluate(`document.activeElement?.dispatchEvent(
    new KeyboardEvent('keydown', { key: 'p', bubbles: true, cancelable: true }),
  )`)
  assert.equal(await state(`document.activeElement?.textContent.trim()`), "Production")
  await browser("press", "ArrowDown")
  assert.equal(await state(`document.activeElement?.textContent.trim()`), "Staging")
  await browser("press", "ArrowDown")
  assert.equal(await state(`document.activeElement?.textContent.trim()`), "More environments")
  await browser("press", "ArrowRight")
  assert.deepEqual(
    await state(`({
      focus: document.activeElement?.textContent.trim(),
      submenuExpanded: [...document.getElementById(window.__selectPopupID)
        .querySelectorAll('.lui-menu-item')]
        .find((item) => item.textContent.includes('More environments'))
        ?.getAttribute('aria-expanded'),
    })`),
    { focus: "Production region", submenuExpanded: "true" },
  )

  await evaluate(`document.activeElement?.dispatchEvent(
    new KeyboardEvent('keydown', { key: 'Escape', bubbles: true, cancelable: true }),
  )`)
  assert.equal(await state(`document.activeElement?.textContent.trim()`), "More environments")
  await evaluate(`(() => {
    const popup = document.getElementById(window.__selectPopupID)
    document.activeElement?.dispatchEvent(
      new KeyboardEvent('keydown', { key: 'Escape', bubbles: true, cancelable: true }),
    )
    popup?.dispatchEvent(new TransitionEvent('transitionend', {
      bubbles: true,
      propertyName: 'opacity',
    }))
  })()`)
  assert.deepEqual(
    await state(`({
      expanded: document.querySelector('.lui-select')?.getAttribute('aria-expanded'),
      popupRemoved: document.getElementById(window.__selectPopupID) === null,
      endingObserved: window.__selectEndingObserved,
      triggerFocused: document.activeElement === document.querySelector('.lui-select'),
    })`),
    { expanded: "false", popupRemoved: true, endingObserved: true, triggerFocused: true },
  )
})

test("Select reopens on the selected item and aligns it with the trigger", async () => {
  await openGalleryPage("Select")
  await clickButton("Production")
  await browser("wait", "30")
  await evaluate(`[
    ...document.querySelectorAll('.lui-menu-item'),
  ].find((item) => item.textContent.trim() === 'Staging'
    && item.getBoundingClientRect().width > 0)?.click()`)
  await browser("wait", "180")

  await evaluate(`document.querySelector('.lui-select')?.focus()`)
  await browser("press", "Enter")
  await browser("wait", "180")

  assert.deepEqual(
    await state(`(() => {
      const trigger = document.querySelector('.lui-select')
      const popup = document.getElementById(trigger?.getAttribute('aria-controls'))
      const selected = popup?.querySelector('[aria-selected="true"]')
      const label = selected?.querySelector('.lui-menu-item-label')
      const value = trigger?.querySelector('.lui-select-value')
      const triggerBounds = trigger?.getBoundingClientRect()
      const labelBounds = label?.getBoundingClientRect()
      const valueBounds = value?.getBoundingClientRect()
      return {
        triggerText: trigger?.textContent.trim(),
        focus: document.activeElement?.textContent.trim(),
        side: popup?.parentElement?.getAttribute('data-side'),
        inlineStartAligned: Math.abs(
          (valueBounds?.left ?? -1) - (labelBounds?.left ?? 1),
        ) < 1,
        centersAligned: Math.abs(
          ((triggerBounds?.top ?? 0) + (triggerBounds?.height ?? 0) / 2)
            - ((labelBounds?.top ?? 0) + (labelBounds?.height ?? 0) / 2),
        ) < 1,
      }
    })()`),
    {
      triggerText: "Staging",
      focus: "Staging",
      side: "none",
      inlineStartAligned: true,
      centersAligned: true,
    },
  )
})

test("Select falls back to anchored positioning near a viewport edge", async () => {
  await openGalleryPage("Select")
  await browser("set", "viewport", "390", "844")
  await evaluate(`(() => {
    const trigger = document.querySelector('.lui-select')
    Object.assign(trigger.style, {
      position: 'fixed',
      left: '8px',
      top: '4px',
      width: '180px',
      zIndex: '1',
    })
    trigger.focus()
  })()`)
  await browser("press", "Enter")
  await browser("wait", "30")

  assert.deepEqual(
    await state(`(() => {
      const trigger = document.querySelector('.lui-select')
      const popup = document.getElementById(trigger?.getAttribute('aria-controls'))
      const triggerBounds = trigger?.getBoundingClientRect()
      const popupBounds = popup?.getBoundingClientRect()
      return {
        side: popup?.parentElement?.getAttribute('data-side'),
        anchoredBelow: (popupBounds?.top ?? 0) >= (triggerBounds?.bottom ?? 1),
        insideTop: (popupBounds?.top ?? -1) >= 8,
      }
    })()`),
    { side: "below", anchoredBelow: true, insideTop: true },
  )
})

test("Select touch opening keeps ordinary anchored positioning", async () => {
  await openGalleryPage("Select")
  await clickButton("Production")
  await browser("wait", "30")
  await evaluate(`[
    ...document.querySelectorAll('.lui-menu-item'),
  ].find((item) => item.textContent.trim() === 'Staging'
    && item.getBoundingClientRect().width > 0)?.click()`)
  await browser("wait", "180")

  assert.deepEqual(
    await state(`(() => {
      const trigger = document.querySelector('.lui-select')
      trigger.dispatchEvent(new PointerEvent('pointerdown', {
        bubbles: true,
        cancelable: true,
        pointerType: 'touch',
        pointerId: 82,
        button: 0,
        buttons: 1,
      }))
      trigger.dispatchEvent(new MouseEvent('mousedown', {
        bubbles: true,
        cancelable: true,
        button: 0,
        buttons: 1,
      }))
      const popup = document.getElementById(trigger?.getAttribute('aria-controls'))
      const triggerBounds = trigger?.getBoundingClientRect()
      const popupBounds = popup?.getBoundingClientRect()
      return {
        selected: popup?.querySelector('[aria-selected="true"]')?.textContent.trim(),
        side: popup?.parentElement?.getAttribute('data-side'),
        anchoredBelow: (popupBounds?.top ?? 0) >= (triggerBounds?.bottom ?? 1),
      }
    })()`),
    { selected: "Staging", side: "below", anchoredBelow: true },
  )
})

test("Select touch press opens safely and flips inside a compact viewport", async () => {
  await openGalleryPage("Select")
  await browser("set", "viewport", "390", "844")

  const opened = await state(`(() => {
    const trigger = document.querySelector('.lui-select')
    Object.assign(trigger.style, {
      position: 'fixed',
      right: '4px',
      bottom: '4px',
      width: '180px',
      zIndex: '1',
    })
    trigger.focus()
    trigger.dispatchEvent(new PointerEvent('pointerdown', {
      bubbles: true,
      cancelable: true,
      pointerType: 'touch',
      pointerId: 81,
      button: 0,
      buttons: 1,
    }))
    trigger.dispatchEvent(new MouseEvent('mousedown', {
      bubbles: true,
      cancelable: true,
      button: 0,
      buttons: 1,
    }))
    return trigger.getAttribute('aria-expanded')
  })()`)
  assert.equal(opened, "true")
  await browser("wait", "30")

  assert.deepEqual(
    await state(`(() => {
      const trigger = document.querySelector('.lui-select')
      const popup = document.getElementById(trigger?.getAttribute('aria-controls'))
      const positioner = popup?.parentElement
      const options = [...(popup?.querySelectorAll('.lui-menu-item') ?? [])]
      const staging = options.find((option) => option.textContent.trim() === 'Staging')

      staging?.dispatchEvent(new PointerEvent('pointerup', {
        bubbles: true,
        cancelable: true,
        pointerType: 'touch',
        pointerId: 81,
        button: 0,
        buttons: 0,
      }))
      staging?.dispatchEvent(new MouseEvent('mouseup', {
        bubbles: true,
        cancelable: true,
        button: 0,
        buttons: 0,
      }))

      const bounds = popup?.getBoundingClientRect()
      return {
        expanded: trigger?.getAttribute('aria-expanded'),
        side: positioner?.getAttribute('data-side'),
        insideLeft: (bounds?.left ?? -1) >= 8,
        insideRight: (bounds?.right ?? innerWidth + 1) <= innerWidth - 8,
        insideTop: (bounds?.top ?? -1) >= 8,
        insideBottom: (bounds?.bottom ?? innerHeight + 1) <= innerHeight - 8,
        productionSelected: options
          .find((option) => option.textContent.trim() === 'Production')
          ?.getAttribute('aria-selected'),
        stagingSelected: staging?.getAttribute('aria-selected'),
      }
    })()`),
    {
      expanded: "true",
      side: "above",
      insideLeft: true,
      insideRight: true,
      insideTop: true,
      insideBottom: true,
      productionSelected: "true",
      stagingSelected: "false",
    },
  )
})

test("Open Select tracks anchor movement on viewport resize", async () => {
  await openGalleryPage("Select")
  await browser("set", "viewport", "480", "720")
  await clickButton("Production")
  await browser("wait", "30")

  await evaluate(`(() => {
    const trigger = document.querySelector('.lui-select')
    Object.assign(trigger.style, {
      position: 'fixed',
      right: '4px',
      bottom: '4px',
      width: '180px',
      zIndex: '1',
    })
    window.dispatchEvent(new Event('resize'))
  })()`)
  await browser("wait", "30")

  assert.deepEqual(
    await state(`(() => {
      const trigger = document.querySelector('.lui-select')
      const popup = document.getElementById(trigger?.getAttribute('aria-controls'))
      const triggerBounds = trigger?.getBoundingClientRect()
      const bounds = popup?.getBoundingClientRect()
      return {
        side: popup?.parentElement?.getAttribute('data-side'),
        insideRight: (bounds?.right ?? innerWidth + 1) <= innerWidth - 8,
        insideBottom: (bounds?.bottom ?? innerHeight + 1) <= innerHeight - 8,
        followsAnchor: (bounds?.bottom ?? innerHeight + 1) <= (triggerBounds?.top ?? -1)
          && Math.abs((bounds?.right ?? 0) - (innerWidth - 8)) <= 2,
      }
    })()`),
    { side: "above", insideRight: true, insideBottom: true, followsAnchor: true },
  )
})

test("Combobox keeps DOM focus in the input while navigating its listbox", async () => {
  await openGalleryPage("Combobox")
  await evaluate(`(() => {
    window.__comboboxStartingObserved = false
    window.__comboboxEndingObserved = false
    new MutationObserver((records) => {
      for (const record of records) {
        const popup = record.target?.classList?.contains('lui-dropdown-menu')
          ? record.target
          : document.querySelector('.lui-dropdown-menu')
        if (popup?.hasAttribute('data-starting-style')) window.__comboboxStartingObserved = true
        if (popup?.hasAttribute('data-ending-style')) window.__comboboxEndingObserved = true
      }
    }).observe(document.querySelector('.lui-popup-portal'), {
      attributes: true,
      childList: true,
      subtree: true,
    })
  })()`)
  const input = '.lui-combobox-control'
  await evaluate(`document.querySelector(${JSON.stringify(input)})?.focus()`)
  await browser("press", "ArrowDown")

  const comboboxOpened = await state(`(() => {
    const control = document.querySelector(${JSON.stringify(input)})
    const active = document.getElementById(control?.getAttribute('aria-activedescendant'))
    const listbox = document.getElementById(control?.getAttribute('aria-controls'))
    return {
      expanded: control?.getAttribute('aria-expanded'),
      controls: control?.getAttribute('aria-controls'),
      listbox: listbox?.id,
      listboxRole: listbox?.getAttribute('role'),
      focusStayed: document.activeElement === control,
      active: active?.textContent.trim(),
    }
  })()`)
  assert.equal(comboboxOpened.expanded, "true")
  assert.ok(comboboxOpened.controls)
  assert.equal(comboboxOpened.listbox, comboboxOpened.controls)
  assert.equal(comboboxOpened.listboxRole, "listbox")
  assert.equal(comboboxOpened.focusStayed, true)
  assert.equal(comboboxOpened.active, "Production")
  assert.equal(await state(`window.__comboboxStartingObserved`), true)

  await browser("press", "ArrowDown")
  assert.equal(
    await state(`document.getElementById(document.querySelector(${JSON.stringify(input)})
      ?.getAttribute('aria-activedescendant'))?.textContent.trim()`),
    "Staging",
  )
  await evaluate(`(() => {
    const control = document.querySelector(${JSON.stringify(input)})
    const popup = document.getElementById(control?.getAttribute('aria-controls'))
    control?.dispatchEvent(
      new KeyboardEvent('keydown', { key: 'Escape', bubbles: true, cancelable: true }),
    )
    popup?.dispatchEvent(new TransitionEvent('transitionend', {
      bubbles: true,
      propertyName: 'opacity',
    }))
  })()`)
  assert.deepEqual(
    await state(`(() => {
      const control = document.querySelector(${JSON.stringify(input)})
      return {
        value: control?.value,
        expanded: control?.getAttribute('aria-expanded'),
        activeDescendant: control?.getAttribute('aria-activedescendant'),
        endingObserved: window.__comboboxEndingObserved,
        focused: document.activeElement === control,
      }
    })()`),
    { value: "", expanded: "false", activeDescendant: null, endingObserved: true, focused: true },
  )
})

test("Combobox leaves composition text and navigation keys owned by the IME", async () => {
  await openGalleryPage("Combobox")
  const result = await state(`(() => {
    const control = document.querySelector('.lui-combobox-control')
    control.focus()
    control.dispatchEvent(
      new KeyboardEvent('keydown', { key: 'ArrowDown', bubbles: true, cancelable: true }),
    )
    const originalControl = control
    const initialActive = control.getAttribute('aria-activedescendant')

    control.dispatchEvent(new CompositionEvent('compositionstart', {
      bubbles: true,
      data: '',
    }))
    control.value = '中'
    control.dispatchEvent(new InputEvent('input', {
      bubbles: true,
      cancelable: false,
      data: '中',
      inputType: 'insertCompositionText',
      isComposing: true,
    }))

    const composingKeys = ['ArrowDown', 'Enter', 'Escape'].map((key) => {
      const event = new KeyboardEvent('keydown', {
        key,
        bubbles: true,
        cancelable: true,
        isComposing: true,
      })
      control.dispatchEvent(event)
      return {
        key,
        expanded: control.getAttribute('aria-expanded'),
        activeUnchanged: control.getAttribute('aria-activedescendant') === initialActive,
        value: control.value,
      }
    })

    return {
      sameControl: document.querySelector('.lui-combobox-control') === originalControl,
      focused: document.activeElement === originalControl,
      value: originalControl.value,
      expanded: originalControl.getAttribute('aria-expanded'),
      activeUnchanged: originalControl.getAttribute('aria-activedescendant') === initialActive,
      composingKeys,
    }
  })()`)

  assert.deepEqual(result, {
    sameControl: true,
    focused: true,
    value: "中",
    expanded: "true",
    activeUnchanged: true,
    composingKeys: [
      { key: "ArrowDown", expanded: "true", activeUnchanged: true, value: "中" },
      { key: "Enter", expanded: "true", activeUnchanged: true, value: "中" },
      { key: "Escape", expanded: "true", activeUnchanged: true, value: "中" },
    ],
  })
  await browser("wait", "30")
  assert.equal(
    await state(`document.querySelector('.lui-combobox-query-value')?.textContent`),
    "",
  )
})

test("Combobox commits the final composition and resumes normal option selection", async () => {
  await openGalleryPage("Combobox")
  assert.deepEqual(
    await state(`(() => {
      const control = document.querySelector('.lui-combobox-control')
      const originalControl = control
      control.focus()
      control.dispatchEvent(new CompositionEvent('compositionstart', {
        bubbles: true,
        data: '',
      }))
      control.value = '中文'
      control.dispatchEvent(new InputEvent('input', {
        bubbles: true,
        data: '文',
        inputType: 'insertCompositionText',
        isComposing: true,
      }))
      control.dispatchEvent(new CompositionEvent('compositionend', {
        bubbles: true,
        data: '中文',
      }))
      control.dispatchEvent(new InputEvent('input', {
        bubbles: true,
        data: '中文',
        inputType: 'insertFromComposition',
        isComposing: false,
      }))
      return {
        sameControl: document.querySelector('.lui-combobox-control') === originalControl,
        focused: document.activeElement === originalControl,
        value: originalControl.value,
        expanded: originalControl.getAttribute('aria-expanded'),
      }
    })()`),
    {
      sameControl: true,
      focused: true,
      value: "中文",
      expanded: "true",
    },
  )
  await browser("wait", "30")
  assert.equal(
    await state(`document.querySelector('.lui-combobox-query-value')?.textContent`),
    "中文",
  )

  await evaluate(`[
    ...document.querySelectorAll('nav button'),
  ].find((node) => node.textContent === 'Button')?.click()`)
  await evaluate(`[
    ...document.querySelectorAll('nav button'),
  ].find((node) => node.textContent === 'Combobox')?.click()`)
  await browser("wait", "30")
  assert.equal(await state(`document.querySelector('.lui-combobox-control')?.value`), "中文")

  await evaluate(`(() => {
    const control = document.querySelector('.lui-combobox-control')
    control.focus()
    control.value = ''
    control.dispatchEvent(new InputEvent('input', {
      bubbles: true,
      inputType: 'deleteContentBackward',
    }))
  })()`)
  await browser("wait", "30")
  await browser("press", "ArrowDown")
  await browser("wait", "30")
  await browser("press", "Enter")
  assert.deepEqual(
    await state(`(() => {
      const control = document.querySelector('.lui-combobox-control')
      return {
        value: control?.value,
        expanded: control?.getAttribute('aria-expanded'),
        focused: document.activeElement === control,
      }
    })()`),
    { value: "Staging", expanded: "false", focused: true },
  )
  assert.equal(
    await state(`document.querySelector('.lui-combobox-query-value')?.textContent`),
    "Staging",
  )
})

test("Combobox touch trigger opens without moving input focus and stays onscreen", async () => {
  await openGalleryPage("Combobox")
  await browser("set", "viewport", "390", "844")

  assert.deepEqual(
    await state(`(() => {
      const root = document.querySelector('.lui-combobox')
      const input = root?.querySelector('.lui-combobox-control')
      const trigger = root?.querySelector('.lui-combobox-trigger')
      Object.assign(root.style, {
        position: 'fixed',
        right: '4px',
        bottom: '4px',
        width: '200px',
        zIndex: '1',
      })
      input?.focus()
      trigger?.dispatchEvent(new PointerEvent('pointerdown', {
        bubbles: true,
        cancelable: true,
        pointerType: 'touch',
        pointerId: 82,
        button: 0,
        buttons: 1,
      }))
      trigger?.dispatchEvent(new MouseEvent('mousedown', {
        bubbles: true,
        cancelable: true,
        button: 0,
        buttons: 1,
      }))

      const popup = document.getElementById(input?.getAttribute('aria-controls'))
      const bounds = popup?.getBoundingClientRect()
      return {
        expanded: input?.getAttribute('aria-expanded'),
        inputFocused: document.activeElement === input,
        side: popup?.parentElement?.getAttribute('data-side'),
        insideLeft: (bounds?.left ?? -1) >= 8,
        insideRight: (bounds?.right ?? innerWidth + 1) <= innerWidth - 8,
        insideBottom: (bounds?.bottom ?? innerHeight + 1) <= innerHeight - 8,
      }
    })()`),
    {
      expanded: "true",
      inputFocused: true,
      side: "above",
      insideLeft: true,
      insideRight: true,
      insideBottom: true,
    },
  )
})

test("Combobox exposes and recovers from an empty filtered result", async () => {
  await openGalleryPage("Combobox")
  await evaluate(`(() => {
    const control = document.querySelector('.lui-combobox-control')
    control.focus()
    control.dispatchEvent(
      new KeyboardEvent('keydown', { key: 'ArrowDown', bubbles: true, cancelable: true }),
    )
    control.value = 'zzz'
    control.dispatchEvent(new InputEvent('input', {
      bubbles: true,
      data: 'zzz',
      inputType: 'insertText',
    }))
  })()`)
  await browser("wait", "30")

  assert.deepEqual(
    await state(`(() => {
      const control = document.querySelector('.lui-combobox-control')
      const root = control?.closest('.lui-combobox')
      const trigger = root?.querySelector('.lui-combobox-trigger')
      const popup = document.getElementById(control?.getAttribute('aria-controls'))
      const status = popup?.querySelector('[role=status]')
      const press = (key) => {
        const event = new KeyboardEvent('keydown', {
          key, bubbles: true, cancelable: true,
        })
        control.dispatchEvent(event)
        return event.defaultPrevented
      }
      return {
        sameControl: document.querySelector('.lui-combobox-control') === control,
        focused: document.activeElement === control,
        value: control?.value,
        expanded: control?.getAttribute('aria-expanded'),
        activeDescendant: control?.getAttribute('aria-activedescendant'),
        controlEmpty: control?.hasAttribute('data-list-empty'),
        triggerEmpty: trigger?.hasAttribute('data-list-empty'),
        popupEmpty: popup?.hasAttribute('data-empty'),
        positionerEmpty: popup?.parentElement?.hasAttribute('data-empty'),
        options: [...(popup?.querySelectorAll('[role=option]') ?? [])]
          .map((option) => option.textContent.trim()),
        status: status?.textContent,
        statusLive: status?.getAttribute('aria-live'),
        statusAtomic: status?.getAttribute('aria-atomic'),
        arrowPrevented: press('ArrowDown'),
        enterPrevented: press('Enter'),
        activeAfterKeys: control?.getAttribute('aria-activedescendant'),
        expandedAfterKeys: control?.getAttribute('aria-expanded'),
      }
    })()`),
    {
      sameControl: true,
      focused: true,
      value: "zzz",
      expanded: "true",
      activeDescendant: null,
      controlEmpty: true,
      triggerEmpty: true,
      popupEmpty: true,
      positionerEmpty: true,
      options: [],
      status: "No results.",
      statusLive: "polite",
      statusAtomic: "true",
      arrowPrevented: true,
      enterPrevented: true,
      activeAfterKeys: null,
      expandedAfterKeys: "true",
    },
  )

  await evaluate(`(() => {
    const control = document.querySelector('.lui-combobox-control')
    control.value = 'STAG'
    control.dispatchEvent(new InputEvent('input', {
      bubbles: true,
      data: 'STAG',
      inputType: 'insertText',
    }))
  })()`)
  await browser("wait", "30")

  assert.deepEqual(
    await state(`(() => {
      const control = document.querySelector('.lui-combobox-control')
      const root = control?.closest('.lui-combobox')
      const popup = document.getElementById(control?.getAttribute('aria-controls'))
      const active = document.getElementById(control?.getAttribute('aria-activedescendant'))
      return {
        sameControl: document.querySelector('.lui-combobox-control') === control,
        focused: document.activeElement === control,
        value: control?.value,
        controlEmpty: control?.hasAttribute('data-list-empty'),
        triggerEmpty: root?.querySelector('.lui-combobox-trigger')
          ?.hasAttribute('data-list-empty'),
        popupEmpty: popup?.hasAttribute('data-empty'),
        positionerEmpty: popup?.parentElement?.hasAttribute('data-empty'),
        options: [...(popup?.querySelectorAll('[role=option]') ?? [])]
          .map((option) => option.textContent.trim()),
        active: active?.textContent.trim(),
        status: popup?.querySelector('[role=status]')?.textContent,
      }
    })()`),
    {
      sameControl: true,
      focused: true,
      value: "STAG",
      controlEmpty: false,
      triggerEmpty: false,
      popupEmpty: false,
      positionerEmpty: false,
      options: ["Staging"],
      active: "Staging",
      status: "1 result available.",
    },
  )
})

test("ContextMenu opens from the keyboard and returns focus on Escape", async () => {
  await openGalleryPage("ContextMenu")
  const host = '.lui-list-item'
  await evaluate(`document.querySelector(${JSON.stringify(host)})?.focus()`)
  await browser("press", "Shift+F10")

  assert.deepEqual(
    await state(`({
      open: document.querySelector('.lui-context-menu')?.hasAttribute('data-open'),
      focus: document.activeElement?.textContent.trim(),
    })`),
    { open: true, focus: "Rename" },
  )
  await browser("press", "ArrowDown")
  assert.equal(await state(`document.activeElement?.textContent.trim()`), "Archive")
  await browser("press", "Escape")
  assert.deepEqual(
    await state(`({
      open: document.querySelector('.lui-context-menu')?.hasAttribute('data-open'),
      hostFocused: document.activeElement === document.querySelector(${JSON.stringify(host)}),
    })`),
    { open: false, hostFocused: true },
  )
})

test("ContextMenu long press follows the touch point and cancels after movement", async () => {
  await openGalleryPage("ContextMenu")
  await browser("set", "viewport", "390", "844")

  await evaluate(`(() => {
    const host = document.querySelector('.lui-list-item')
    const pointer = (type, x, y) => new PointerEvent(type, {
      bubbles: true, cancelable: true, isPrimary: true, pointerId: 1,
      pointerType: 'touch', clientX: x, clientY: y, button: 0,
      buttons: type === 'pointerup' ? 0 : 1,
    })
    host.dispatchEvent(pointer('pointerdown', 80, 180))
    host.dispatchEvent(pointer('pointermove', 100, 180))
  })()`)
  await browser("wait", "550")
  assert.equal(await state(`document.querySelector('.lui-context-menu')?.hasAttribute('data-open')`), false)

  await evaluate(`(() => {
    const host = document.querySelector('.lui-list-item')
    host.dispatchEvent(new PointerEvent('pointerdown', {
      bubbles: true, cancelable: true, isPrimary: true, pointerId: 2,
      pointerType: 'touch', clientX: 84, clientY: 220, button: 0, buttons: 1,
    }))
  })()`)
  await browser("wait", "550")
  assert.deepEqual(
    await state(`(() => {
      const menu = document.querySelector('.lui-context-menu')
      const bounds = menu?.getBoundingClientRect()
      return {
        open: menu?.hasAttribute('data-open'),
        left: Math.round(bounds?.left ?? 0),
        top: Math.round(bounds?.top ?? 0),
      }
    })()`),
    { open: true, left: 84, top: 220 },
  )
})

test("Toolbar exposes orientation-aware roving focus over composed controls", async () => {
  await openGalleryPage("Toolbar")

  assert.deepEqual(
    await state(`(() => {
      const toolbars = [...document.querySelectorAll('[role=toolbar]')]
      return toolbars.map((toolbar) => ({
        label: toolbar.getAttribute('aria-label'),
        orientation: toolbar.getAttribute('aria-orientation'),
        controls: [...toolbar.querySelectorAll('button')].map((button) => ({
          label: button.textContent.trim(),
          tabIndex: button.tabIndex,
          disabled: button.disabled,
        })),
      }))
    })()`),
    [
      {
        label: "Formatting",
        orientation: "horizontal",
        controls: [
          { label: "Bold", tabIndex: 0, disabled: false },
          { label: "Italic", tabIndex: -1, disabled: false },
          { label: "Underline", tabIndex: -1, disabled: false },
          { label: "Redo", tabIndex: -1, disabled: false },
          { label: "More", tabIndex: -1, disabled: false },
        ],
      },
      {
        label: "Insert",
        orientation: "vertical",
        controls: [
          { label: "Link", tabIndex: 0, disabled: false },
          { label: "Image", tabIndex: -1, disabled: false },
          { label: "Locked picker", tabIndex: -1, disabled: false },
        ],
      },
    ],
  )

  await evaluate(`document.querySelector('[aria-label="Formatting"] button')?.focus()`)
  await browser("press", "ArrowRight")
  assert.equal(await state(`document.activeElement?.textContent.trim()`), "Italic")
  await browser("press", "ArrowRight")
  assert.equal(await state(`document.activeElement?.textContent.trim()`), "Underline")
  await browser("press", "ArrowRight")
  assert.equal(await state(`document.activeElement?.textContent.trim()`), "Redo")
  assert.deepEqual(
    await state(`(() => {
      const redo = [...document.querySelectorAll('[aria-label="Formatting"] button')]
        .find((button) => button.textContent.trim() === 'Redo')
      return {
        ariaDisabled: redo.getAttribute('aria-disabled'),
        dataDisabled: redo.hasAttribute('data-disabled'),
      }
    })()`),
    { ariaDisabled: "true", dataDisabled: true },
  )
  await browser("press", "Enter")
  assert.equal(await state(`document.activeElement?.textContent.trim()`), "Redo")
  await browser("press", "ArrowRight")
  assert.equal(await state(`document.activeElement?.textContent.trim()`), "More")
  await browser("press", "Home")
  assert.equal(await state(`document.activeElement?.textContent.trim()`), "Bold")

  await evaluate(`document.querySelector('[aria-label="Insert"] button')?.focus()`)
  await browser("press", "ArrowDown")
  assert.equal(await state(`document.activeElement?.textContent.trim()`), "Image")
  await browser("press", "ArrowUp")
  assert.equal(await state(`document.activeElement?.textContent.trim()`), "Link")
})

test("Toolbar keeps disabled native controls focusable without activating them", async () => {
  await openGalleryPage("Toolbar")
  const toolbar = '[aria-label="Insert"]'

  assert.deepEqual(
    await state(`(() => {
      const root = document.querySelector(${JSON.stringify(toolbar)})
      return [...root.querySelectorAll('button, input')].map((control) => ({
        className: control.className,
        disabled: control.disabled,
        ariaDisabled: control.getAttribute('aria-disabled'),
        dataDisabled: control.hasAttribute('data-disabled'),
        tabIndex: control.tabIndex,
      }))
    })()`),
    [
      { className: "lui-button", disabled: false, ariaDisabled: null, dataDisabled: false, tabIndex: 0 },
      { className: "lui-button", disabled: false, ariaDisabled: null, dataDisabled: false, tabIndex: -1 },
      { className: "lui-checkbox-control", disabled: false, ariaDisabled: "true", dataDisabled: true, tabIndex: -1 },
      { className: "lui-select", disabled: false, ariaDisabled: "true", dataDisabled: true, tabIndex: -1 },
      { className: "lui-input", disabled: false, ariaDisabled: "true", dataDisabled: true, tabIndex: -1 },
    ],
  )

  await evaluate(`document.querySelector(${JSON.stringify(toolbar)}).querySelector('button').focus()`)
  for (const selector of [
    ".lui-button:nth-of-type(2)",
    ".lui-checkbox-control",
    ".lui-select",
    ".lui-input",
  ]) {
    await browser("press", "ArrowDown")
    assert.equal(
      await state(`document.activeElement === document.querySelector(${JSON.stringify(toolbar)}).querySelector(${JSON.stringify(selector)})`),
      true,
    )
  }

  await evaluate(`document.querySelector(${JSON.stringify(toolbar)}).querySelector('.lui-checkbox-control').focus()`)
  await browser("press", "Space")
  assert.equal(await state(`document.querySelector(${JSON.stringify(toolbar)}).querySelector('.lui-checkbox-control').checked`), false)

  await evaluate(`document.querySelector(${JSON.stringify(toolbar)}).querySelector('.lui-input').focus()`)
  const lockedValue = await state(`document.querySelector(${JSON.stringify(toolbar)}).querySelector('.lui-input').value`)
  await browser("press", "x")
  assert.equal(await state(`document.querySelector(${JSON.stringify(toolbar)}).querySelector('.lui-input').value`), lockedValue)
})

test("Select placeholder preserves its retained value child through Signal patches", async () => {
  await openGalleryPage("Toolbar")
  const toolbar = '[aria-label="Insert"]'

  assert.deepEqual(
    await state(`(() => {
      const select = document.querySelector(${JSON.stringify(toolbar)}).querySelector('.lui-select')
      const value = select.querySelector('.lui-select-value')
      return { valueChild: Boolean(value), text: value?.textContent }
    })()`),
    { valueChild: true, text: "Locked picker" },
  )

  assert.deepEqual(
    await state(`(() => {
      const formatting = document.querySelector('[aria-label="Formatting"] input')
      const select = document.querySelector(${JSON.stringify(toolbar)}).querySelector('.lui-select')
      const value = select.querySelector('.lui-select-value')
      formatting.value = 'patched'
      formatting.dispatchEvent(new InputEvent('input', { bubbles: true, inputType: 'insertText' }))
      return {
        sameValueChild: select.querySelector('.lui-select-value') === value,
        text: value?.textContent,
      }
    })()`),
    { sameValueChild: true, text: "patched" },
  )
})

test("Toolbar flattens nested control groups into one roving sequence", async () => {
  await openGalleryPage("Toolbar")
  const toolbar = '[aria-label="Formatting"]'

  assert.deepEqual(
    await state(`(() => {
      const root = document.querySelector(${JSON.stringify(toolbar)})
      const group = root.querySelector('[role=group]')
      return {
        label: group.getAttribute('aria-label'),
        items: [...group.querySelectorAll('button')].map((item) => item.textContent.trim()),
      }
    })()`),
    { label: "Text style", items: ["Italic", "Underline"] },
  )

  await evaluate(`document.querySelector(${JSON.stringify(toolbar)}).querySelector('button').focus()`)
  for (const expected of ["Italic", "Underline", "Redo", "More"]) {
    await browser("press", "ArrowRight")
    assert.equal(await state(`document.activeElement?.textContent.trim()`), expected)
  }
})

test("Toolbar input keeps editing keys until its caret reaches a boundary", async () => {
  await openGalleryPage("Toolbar")
  const toolbar = '[aria-label="Formatting"]'

  assert.deepEqual(
    await state(`(() => {
      const root = document.querySelector(${JSON.stringify(toolbar)})
      const input = root?.querySelector('input')
      const more = [...(root?.querySelectorAll('button') ?? [])]
        .find((button) => button.textContent.trim() === 'More')
      input.value = 'abcd'
      input.dispatchEvent(new InputEvent('input', { bubbles: true, inputType: 'insertText' }))
      more.focus()
      more.dispatchEvent(new KeyboardEvent('keydown', {
        key: 'ArrowRight', bubbles: true, cancelable: true,
      }))
      return {
        focused: document.activeElement === input,
        tabIndex: input.tabIndex,
        value: input.value,
        selectionStart: input.selectionStart,
        selectionEnd: input.selectionEnd,
      }
    })()`),
    {
      focused: true,
      tabIndex: 0,
      value: "abcd",
      selectionStart: 0,
      selectionEnd: 4,
    },
  )

  assert.deepEqual(
    await state(`(() => {
      const root = document.querySelector(${JSON.stringify(toolbar)})
      const input = root.querySelector('input')
      const run = (key, start, end = start, modifiers = {}) => {
        input.focus()
        input.setSelectionRange(start, end)
        const event = new KeyboardEvent('keydown', {
          key, ...modifiers, bubbles: true, cancelable: true,
        })
        input.dispatchEvent(event)
        return {
          key,
          focused: document.activeElement === input,
          prevented: event.defaultPrevented,
          selectionStart: input.selectionStart,
          selectionEnd: input.selectionEnd,
        }
      }
      return [
        run('ArrowRight', 2),
        run('ArrowLeft', 1, 3),
        run('ArrowRight', 2, 2, { shiftKey: true }),
        run('ArrowRight', 4, 4, { ctrlKey: true }),
        run('ArrowRight', 4, 4, { altKey: true }),
        run('ArrowRight', 4, 4, { metaKey: true }),
        run('Home', 2),
        run('End', 2),
      ]
    })()`),
    [
      { key: "ArrowRight", focused: true, prevented: false, selectionStart: 2, selectionEnd: 2 },
      { key: "ArrowLeft", focused: true, prevented: false, selectionStart: 1, selectionEnd: 3 },
      { key: "ArrowRight", focused: true, prevented: false, selectionStart: 2, selectionEnd: 2 },
      { key: "ArrowRight", focused: true, prevented: false, selectionStart: 4, selectionEnd: 4 },
      { key: "ArrowRight", focused: true, prevented: false, selectionStart: 4, selectionEnd: 4 },
      { key: "ArrowRight", focused: true, prevented: false, selectionStart: 4, selectionEnd: 4 },
      { key: "Home", focused: true, prevented: false, selectionStart: 2, selectionEnd: 2 },
      { key: "End", focused: true, prevented: false, selectionStart: 2, selectionEnd: 2 },
    ],
  )

  assert.deepEqual(
    await state(`(() => {
      const root = document.querySelector(${JSON.stringify(toolbar)})
      const input = root.querySelector('input')
      const pressAt = (key, caret) => {
        input.focus()
        input.setSelectionRange(caret, caret)
        const event = new KeyboardEvent('keydown', {
          key, bubbles: true, cancelable: true,
        })
        input.dispatchEvent(event)
        return {
          key,
          prevented: event.defaultPrevented,
          focusedText: document.activeElement?.textContent?.trim() ?? '',
          inputFocused: document.activeElement === input,
        }
      }
      return [pressAt('ArrowLeft', 0), pressAt('ArrowRight', input.value.length)]
    })()`),
    [
      { key: "ArrowLeft", prevented: true, focusedText: "More", inputFocused: false },
      { key: "ArrowRight", prevented: true, focusedText: "Bold", inputFocused: false },
    ],
  )

  assert.deepEqual(
    await state(`(() => {
      const root = document.querySelector(${JSON.stringify(toolbar)})
      const input = root.querySelector('input')
      root.style.direction = 'rtl'
      const pressAt = (key, caret) => {
        input.focus()
        input.setSelectionRange(caret, caret)
        const event = new KeyboardEvent('keydown', {
          key, bubbles: true, cancelable: true,
        })
        input.dispatchEvent(event)
        return {
          key,
          prevented: event.defaultPrevented,
          focusedText: document.activeElement?.textContent?.trim() ?? '',
          inputFocused: document.activeElement === input,
        }
      }
      const result = [
        pressAt('ArrowRight', 0),
        pressAt('ArrowLeft', input.value.length),
      ]
      root.style.direction = ''
      return result
    })()`),
    [
      { key: "ArrowRight", prevented: true, focusedText: "More", inputFocused: false },
      { key: "ArrowLeft", prevented: true, focusedText: "Bold", inputFocused: false },
    ],
  )
})

test("Toast portals stable updates and supports Base UI down/right touch dismissal", async () => {
  await openGalleryPage("Toast")
  await clickButton("Show notifications")

  assert.deepEqual(
    await state(`(() => {
      const viewport = document.querySelector('.lui-toast-viewport')
      const toasts = [...(viewport?.querySelectorAll('[role=status]') ?? [])]
      window.__firstToast = toasts[0]
      return {
        label: viewport?.getAttribute('aria-label') ?? null,
        portaled: Boolean(viewport?.parentElement?.classList.contains('lui-popup-portal')),
        messages: toasts.map((toast) =>
          [...toast.querySelectorAll('.lui-text, .lui-paragraph, button')]
            .map((node) => node.textContent.trim()),
        ),
      }
    })()`),
    {
      label: "Notifications",
      portaled: true,
      messages: [
        ["Saved", "Draft saved locally", "Update notification", "Close"],
        ["Synced", "Changes are available on every device", "Close"],
      ],
    },
  )

  await clickButton("Update notification")
  assert.deepEqual(
    await state(`({
      stable: window.__firstToast === document.querySelector('[role=status]'),
      message: document.querySelector('[role=status] .lui-text')?.textContent.trim(),
      description: document.querySelector('[role=status] .lui-paragraph')?.textContent.trim(),
    })`),
    {
      stable: true,
      message: "Updated",
      description: "Draft remains the same retained toast",
    },
  )

  await browser("press", "F6")
  assert.equal(
    await state(`document.querySelector('.lui-toast-viewport')?.contains(document.activeElement)`),
    true,
  )
  await evaluate(`document.activeElement?.blur()`)

  await browser("hover", ".lui-toast:first-child")
  await browser("wait", "2100")
  assert.equal(await state(`document.querySelectorAll('[role=status]').length`), 2)
  await browser("hover", '[role="heading"]')
  await browser("wait", "2100")
  assert.equal(await state(`document.querySelectorAll('[role=status]').length`), 0)

  await clickButton("Show notifications")
  await clickButton("Close")
  assert.equal(await state(`document.querySelectorAll('[role=status]').length`), 0)

  await clickButton("Show notifications")
  await evaluate(`(() => {
    const toast = document.querySelector('[role=status]')
    const action = [...toast.querySelectorAll('button')]
      .find((button) => button.textContent.trim() === 'Update notification')
    const event = (name, x, pointerId = 7) => new PointerEvent(name, {
      bubbles: true,
      cancelable: true,
      clientX: x,
      clientY: 20,
      isPrimary: true,
      pointerId,
      pointerType: 'touch',
      button: 0,
      buttons: name === 'pointerup' ? 0 : 1,
    })
    action.dispatchEvent(event('pointerdown', 20))
    action.dispatchEvent(event('pointermove', 180))
    action.dispatchEvent(event('pointerup', 180))
  })()`)
  assert.equal(await state(`document.querySelectorAll('[role=status]').length`), 2)
  await evaluate(`(() => {
    const toast = document.querySelector('[role=status]')
    const event = (name, x) => new PointerEvent(name, {
      bubbles: true,
      cancelable: true,
      clientX: x,
      clientY: 20,
      isPrimary: true,
      pointerId: 8,
      pointerType: 'touch',
      button: 0,
      buttons: name === 'pointerup' ? 0 : 1,
    })
    toast.dispatchEvent(event('pointerdown', 20))
    toast.dispatchEvent(event('pointermove', 180))
    toast.dispatchEvent(event('pointercancel', 180))
  })()`)
  assert.equal(await state(`document.querySelectorAll('[role=status]').length`), 2)
  await evaluate(`(() => {
    const toast = document.querySelector('[role=status]')
    const event = (name, x, y) => new PointerEvent(name, {
      bubbles: true,
      cancelable: true,
      clientX: x,
      clientY: y,
      isPrimary: true,
      pointerId: 9,
      pointerType: 'touch',
      button: 0,
      buttons: name === 'pointerup' ? 0 : 1,
    })
    toast.dispatchEvent(event('pointerdown', 180, 20))
    toast.dispatchEvent(event('pointermove', 20, 20))
    toast.dispatchEvent(event('pointerup', 20, 20))
  })()`)
  assert.equal(await state(`document.querySelectorAll('[role=status]').length`), 2)
  await evaluate(`(() => {
    const toast = document.querySelector('[role=status]')
    const event = (name, y) => new PointerEvent(name, {
      bubbles: true,
      cancelable: true,
      clientX: 20,
      clientY: y,
      isPrimary: true,
      pointerId: 10,
      pointerType: 'touch',
      button: 0,
      buttons: name === 'pointerup' ? 0 : 1,
    })
    toast.dispatchEvent(event('pointerdown', 20))
    toast.dispatchEvent(event('pointermove', 180))
    toast.dispatchEvent(event('pointerup', 180))
  })()`)
  assert.equal(await state(`document.querySelectorAll('[role=status]').length`), 0)
})

test("Tooltip owns delayed pointer, immediate focus, Escape, ARIA, and static-label behavior", async () => {
  await openGalleryPage("Tooltip")

  const initial = await state(`(() => {
    const trigger = document.querySelector('button[aria-label="Edit document"]')
    const anchored = document.querySelector('.lui-tooltip[data-anchor]')
    const staticLabel = [...document.querySelectorAll('.lui-tooltip')]
      .find((node) => node.textContent === 'Saved')
    return {
      portaled: anchored?.parentElement?.classList.contains('lui-popup-portal'),
      open: anchored?.hasAttribute('data-open'),
      describedBy: trigger?.getAttribute('aria-describedby'),
      linked: trigger?.getAttribute('aria-describedby') === anchored?.id,
      staticVisible: Boolean(staticLabel && staticLabel.getBoundingClientRect().width > 0),
    }
  })()`)
  assert.deepEqual(initial, {
    portaled: true,
    open: false,
    describedBy: initial.describedBy,
    linked: true,
    staticVisible: true,
  })
  assert.ok(initial.describedBy)

  await browser("hover", '[role="heading"]')

  await evaluate(`(() => {
    window.__tooltipStartingObserved = false
    window.__tooltipEndingObserved = false
    const tooltip = document.querySelector('.lui-tooltip[data-anchor]')
    new MutationObserver(() => {
      if (tooltip?.hasAttribute('data-starting-style')) window.__tooltipStartingObserved = true
      if (tooltip?.hasAttribute('data-ending-style')) window.__tooltipEndingObserved = true
    }).observe(tooltip, { attributes: true })
    document.querySelector('button[aria-label="Edit document"]')?.dispatchEvent(
      new PointerEvent('pointerenter', { pointerType: 'touch', pointerId: 71 }),
    )
  })()`)
  await browser("wait", "300")
  assert.equal(await state(`document.querySelector('.lui-tooltip[data-anchor]')?.hasAttribute('data-open')`), false)

  await browser("hover", 'button[aria-label="Edit document"]')
  assert.equal(await state(`document.querySelector('.lui-tooltip[data-anchor]')?.hasAttribute('data-open')`), false)
  await browser("wait", "300")
  assert.equal(await state(`document.querySelector('.lui-tooltip[data-anchor]')?.hasAttribute('data-open')`), true)
  assert.equal(await state(`window.__tooltipStartingObserved`), true)

  await browser("hover", '[role="heading"]')
  await browser("wait", "80")
  assert.equal(await state(`document.querySelector('.lui-tooltip[data-anchor]')?.hasAttribute('data-open')`), false)
  assert.equal(await state(`window.__tooltipEndingObserved`), true)
  await browser("hover", 'button[aria-label="Edit document"]')
  await browser("wait", "20")
  assert.deepEqual(
    await state(`(() => {
      const tooltip = document.querySelector('.lui-tooltip[data-anchor]')
      tooltip?.dispatchEvent(new TransitionEvent('transitioncancel', {
        bubbles: true,
        propertyName: 'opacity',
      }))
      return {
        open: tooltip?.hasAttribute('data-open'),
        ending: tooltip?.hasAttribute('data-ending-style'),
      }
    })()`),
    { open: true, ending: false },
  )

  await browser("press", "Escape")
  assert.equal(await state(`document.querySelector('.lui-tooltip[data-anchor]')?.hasAttribute('data-open')`), false)

  await browser("hover", '[role="heading"]')
  await browser("hover", 'button[aria-label="Edit document"]')
  assert.equal(await state(`document.querySelector('.lui-tooltip[data-anchor]')?.hasAttribute('data-open')`), false)
  await browser("wait", "300")
  assert.equal(await state(`document.querySelector('.lui-tooltip[data-anchor]')?.hasAttribute('data-open')`), true)

  await browser("hover", '[role="heading"]')
  await browser("wait", "80")
  await evaluate(`document.querySelector('button[aria-label="Edit document"]')?.focus()`)
  assert.equal(await state(`document.querySelector('.lui-tooltip[data-anchor]')?.hasAttribute('data-open')`), true)

  await evaluate(`document.querySelector('button[aria-label="Edit document"]')?.blur()`)
  await browser("wait", "80")
  assert.equal(await state(`document.querySelector('.lui-tooltip[data-anchor]')?.hasAttribute('data-open')`), false)
})

test("Tooltip flips and shifts inside compact viewport edges", async () => {
  await openGalleryPage("Tooltip")
  await browser("set", "viewport", "320", "640")
  await evaluate(`(() => {
    const trigger = document.querySelector('button[aria-label="Edit document"]')
    Object.assign(trigger.style, {
      position: 'fixed',
      right: '2px',
      top: '2px',
      zIndex: '1',
    })
    trigger.focus()
  })()`)
  await browser("wait", "30")

  assert.deepEqual(
    await state(`(() => {
      const tooltip = document.querySelector('.lui-tooltip[data-anchor]')
      const bounds = tooltip?.getBoundingClientRect()
      return {
        open: tooltip?.hasAttribute('data-open'),
        side: tooltip?.getAttribute('data-side'),
        insideLeft: (bounds?.left ?? -1) >= 8,
        insideRight: (bounds?.right ?? innerWidth + 1) <= innerWidth - 8,
        insideTop: (bounds?.top ?? -1) >= 8,
        insideBottom: (bounds?.bottom ?? innerHeight + 1) <= innerHeight - 8,
      }
    })()`),
    {
      open: true,
      side: "below",
      insideLeft: true,
      insideRight: true,
      insideTop: true,
      insideBottom: true,
    },
  )
})

test("Tabs use Base UI keyboard, orientation, RTL, and roving-focus semantics", async () => {
  await openGalleryPage("Tabs")

  assert.deepEqual(
    await state(`(() => {
      const horizontal = document.querySelector('.lui-tabs[aria-label="Workspace sections"]')
      const vertical = document.querySelector('.lui-tabs[aria-label="Workspace sections vertical"]')
      const tabs = [...(horizontal?.querySelectorAll(':scope > button') ?? [])]
      return {
        orientation: horizontal?.getAttribute('aria-orientation'),
        verticalOrientation: vertical?.getAttribute('aria-orientation'),
        roles: tabs.map((tab) => tab.getAttribute('role')),
        selected: tabs.map((tab) => tab.getAttribute('aria-selected')),
        tabStops: tabs.map((tab) => tab.tabIndex),
      }
    })()`),
    {
      orientation: "horizontal",
      verticalOrientation: "vertical",
      roles: ["tab", "tab"],
      selected: ["true", "false"],
      tabStops: [0, -1],
    },
  )

  await evaluate(`document.querySelector(
    '.lui-tabs[aria-label="Workspace sections"] > button[aria-selected="true"]',
  )?.focus()`)
  await browser("press", "ArrowRight")
  assert.deepEqual(
    await state(`({
      focus: document.activeElement?.textContent.trim(),
      content: document.querySelector('.lui-tabs[aria-label="Workspace sections"]')
        ?.nextElementSibling?.textContent.trim(),
      selected: [...document.querySelectorAll(
        '.lui-tabs[aria-label="Workspace sections"] > button',
      )].map((tab) => tab.getAttribute('aria-selected')),
    })`),
    {
      focus: "Activity",
      content: "Signal updates remain local",
      selected: ["true", "false"],
    },
  )

  await browser("press", "Enter")
  await browser("wait", "30")
  assert.deepEqual(
    await state(`({
      content: document.querySelector('.lui-tabs[aria-label="Workspace sections"]')
        ?.nextElementSibling?.textContent.trim(),
      selected: [...document.querySelectorAll(
        '.lui-tabs[aria-label="Workspace sections"] > button',
      )].map((tab) => tab.getAttribute('aria-selected')),
      tabStops: [...document.querySelectorAll(
        '.lui-tabs[aria-label="Workspace sections"] > button',
      )].map((tab) => tab.tabIndex),
    })`),
    {
      content: "Recent retained updates",
      selected: ["false", "true"],
      tabStops: [-1, 0],
    },
  )

  await browser("press", "Home")
  assert.equal(await state(`document.activeElement?.textContent.trim()`), "Overview")
  await browser("press", "End")
  assert.equal(await state(`document.activeElement?.textContent.trim()`), "Activity")

  await evaluate(`(() => {
    const tabs = document.querySelector('.lui-tabs[aria-label="Workspace sections"]')
    tabs.style.direction = 'rtl'
    tabs.querySelector(':scope > button')?.focus()
  })()`)
  await browser("press", "ArrowLeft")
  assert.equal(await state(`document.activeElement?.textContent.trim()`), "Activity")

  await evaluate(`document.querySelector(
    '.lui-tabs[aria-label="Workspace sections vertical"] > button',
  )?.focus()`)
  await browser("press", "ArrowDown")
  assert.equal(await state(`document.activeElement?.textContent.trim()`), "Activity")
  await browser("press", "ArrowLeft")
  assert.equal(await state(`document.activeElement?.textContent.trim()`), "Activity")
  await browser("press", "ArrowUp")
  assert.equal(await state(`document.activeElement?.textContent.trim()`), "Overview")
})

test("Accordion keeps a linked retained panel through controlled motion", async () => {
  await openGalleryPage("Accordion")

  assert.deepEqual(
    await state(`(() => {
      const root = document.querySelector('.lui-accordion')
      const trigger = root?.querySelector('.lui-accordion-summary')
      const panel = root?.querySelector('.lui-accordion-content')
      window.__luiAccordionPanel = panel
      window.__luiAccordionStartingObserved = false
      window.__luiAccordionEndingObserved = false
      new MutationObserver(() => {
        if (panel?.hasAttribute('data-starting-style')) {
          window.__luiAccordionStartingObserved = true
        }
        if (panel?.hasAttribute('data-ending-style')) {
          window.__luiAccordionEndingObserved = true
        }
      }).observe(panel, { attributes: true })
      return {
        rootTag: root?.tagName,
        triggerTag: trigger?.tagName,
        triggerType: trigger?.getAttribute('type'),
        expanded: trigger?.getAttribute('aria-expanded'),
        controlsPanel: trigger?.getAttribute('aria-controls') === panel?.id,
        panelNamed: Boolean(panel?.id),
        panelRole: panel?.getAttribute('role'),
        panelLabelled: panel?.getAttribute('aria-labelledby') === trigger?.id,
        triggerNamed: Boolean(trigger?.id),
        hidden: panel?.hidden,
        retainedText: panel?.textContent.trim(),
      }
    })()`),
    {
      rootTag: "DIV",
      triggerTag: "BUTTON",
      triggerType: "button",
      expanded: "false",
      controlsPanel: true,
      panelNamed: true,
      panelRole: "region",
      panelLabelled: true,
      triggerNamed: true,
      hidden: true,
      retainedText:
        "Yes. The native disclosure hides this content while LUI preserves its node identity.",
    },
  )

  await evaluate(`document.querySelector('.lui-accordion-summary')?.focus()`)
  await browser("press", "Enter")
  await browser("wait", "30")
  assert.deepEqual(
    await state(`(() => {
      const root = document.querySelector('.lui-accordion')
      const trigger = root?.querySelector('.lui-accordion-summary')
      const panel = root?.querySelector('.lui-accordion-content')
      return {
        expanded: trigger?.getAttribute('aria-expanded'),
        open: root?.hasAttribute('data-open'),
        panelOpen: panel?.hasAttribute('data-open'),
        hidden: panel?.hidden,
        samePanel: panel === window.__luiAccordionPanel,
        startingObserved: window.__luiAccordionStartingObserved,
        measuredHeight: (() => {
          const value = panel?.style.getPropertyValue('--lui-accordion-panel-height') ?? ''
          return value === 'auto' || (value.endsWith('px') && Number.parseFloat(value) > 0)
        })(),
      }
    })()`),
    {
      expanded: "true",
      open: true,
      panelOpen: true,
      hidden: false,
      samePanel: true,
      startingObserved: true,
      measuredHeight: true,
    },
  )

  await browser("press", "Escape")
  assert.equal(
    await state(`document.querySelector('.lui-accordion-summary')?.getAttribute('aria-expanded')`),
    "true",
  )

  await browser("press", "Space")
  const closingState = await state(`(() => {
      const panel = document.querySelector('.lui-accordion-content')
      return {
        expanded: document.querySelector('.lui-accordion-summary')
          ?.getAttribute('aria-expanded'),
        ending: panel?.hasAttribute('data-ending-style'),
        endingObserved: window.__luiAccordionEndingObserved,
        hidden: panel?.hidden,
      }
    })()`)
  assert.equal(closingState.expanded, "false")
  assert.equal(closingState.endingObserved, true)
  assert.equal(closingState.ending, !closingState.hidden)
  await evaluate(`document.querySelector('.lui-accordion-content')?.dispatchEvent(
    new TransitionEvent('transitionend', {
      bubbles: true,
      propertyName: 'height',
    }),
  )`)
  assert.deepEqual(
    await state(`(() => {
      const panel = document.querySelector('.lui-accordion-content')
      return {
        ending: panel?.hasAttribute('data-ending-style'),
        hidden: panel?.hidden,
        samePanel: panel === window.__luiAccordionPanel,
      }
    })()`),
    { ending: false, hidden: true, samePanel: true },
  )

  await evaluate(`document.querySelector('.lui-accordion-summary')?.click()`)
  await browser("wait", "30")
  assert.equal(
    await state(`(() => {
      document.querySelector('.lui-accordion-summary')?.click()
      return document.querySelector('.lui-accordion-content')
        ?.hasAttribute('data-ending-style')
    })()`),
    true,
  )
  await evaluate(`document.querySelector('.lui-accordion-summary')?.click()`)
  await evaluate(`document.querySelector('.lui-accordion-content')?.dispatchEvent(
    new TransitionEvent('transitioncancel', {
      bubbles: true,
      propertyName: 'height',
    }),
  )`)
  assert.deepEqual(
    await state(`(() => {
      const panel = document.querySelector('.lui-accordion-content')
      return {
        expanded: document.querySelector('.lui-accordion-summary')
          ?.getAttribute('aria-expanded'),
        ending: panel?.hasAttribute('data-ending-style'),
        hidden: panel?.hidden,
        samePanel: panel === window.__luiAccordionPanel,
      }
    })()`),
    { expanded: "true", ending: false, hidden: false, samePanel: true },
  )

  await browser("set", "media", "light", "reduced-motion")
  await browser("press", "Space")
  assert.deepEqual(
    await state(`(() => {
      const panel = document.querySelector('.lui-accordion-content')
      return {
        expanded: document.querySelector('.lui-accordion-summary')
          ?.getAttribute('aria-expanded'),
        ending: panel?.hasAttribute('data-ending-style'),
        hidden: panel?.hidden,
      }
    })()`),
    { expanded: "false", ending: false, hidden: true },
  )
  await browser("set", "media", "light")
})

test("ToggleGroup keeps plain Buttons in its accessible roving control set", async () => {
  await openGalleryPage("ToggleGroup")

  assert.deepEqual(
    await state(`(() => {
      const group = document.querySelector('.lui-toggle-group')
      const controls = [...(group?.querySelectorAll(':scope > button') ?? [])]
      return {
        role: group?.getAttribute('role'),
        label: group?.getAttribute('aria-label'),
        controls: controls.map((control) => ({
          text: control.textContent.trim(),
          tabIndex: control.tabIndex,
        })),
      }
    })()`),
    {
      role: "group",
      label: "View options",
      controls: [
        { text: "Controlled", tabIndex: 0 },
        { text: "Multi-select", tabIndex: -1 },
        { text: "Action chip", tabIndex: -1 },
      ],
    },
  )

  await evaluate(`document.querySelector('.lui-toggle-group > button')?.focus()`)
  await browser("press", "ArrowRight")
  assert.equal(await state(`document.activeElement?.textContent.trim()`), "Multi-select")
  await browser("press", "ArrowRight")
  assert.equal(await state(`document.activeElement?.textContent.trim()`), "Action chip")
  await browser("press", "ArrowRight")
  assert.equal(await state(`document.activeElement?.textContent.trim()`), "Controlled")
  await browser("press", "ArrowLeft")
  assert.equal(await state(`document.activeElement?.textContent.trim()`), "Action chip")

  await evaluate(`document.activeElement?.click()`)
  assert.deepEqual(
    await state(`[
      ...document.querySelectorAll('.lui-toggle-group > button'),
    ].map((control) => control.disabled)`),
    [true, true, true],
  )
})

test("every Gallery page fits the compact one-page mobile shell", async () => {
  await openGalleryPage("Button")
  await browser("set", "viewport", "390", "844")

  const audit = await state(`(() => {
    const content = document.querySelector('.lui-gallery-content')
    const buttons = [...document.querySelectorAll('.lui-gallery-nav-item')]
    const failures = []
    for (const button of buttons) {
      button.click()
      const headings = content.querySelectorAll('[role="heading"]')
      if (headings.length !== 1 || content.scrollWidth > content.clientWidth + 1) {
        const contentRight = content.getBoundingClientRect().right
        failures.push({
          page: button.textContent,
          headings: headings.length,
          clientWidth: content.clientWidth,
          scrollWidth: content.scrollWidth,
          offenders: [...content.querySelectorAll('*')]
            .filter((element) => element.getBoundingClientRect().right > contentRight + 1)
            .map((element) => ({
              className: element.className,
              right: Math.round(element.getBoundingClientRect().right),
              width: Math.round(element.getBoundingClientRect().width),
            }))
            .slice(0, 8),
        })
      }
    }
    return {
      count: buttons.length,
      minNavigationHeight: Math.min(...buttons.map((button) => button.getBoundingClientRect().height)),
      mountedPages: document.querySelectorAll('.lui-gallery-content > *').length,
      failures,
    }
  })()`)

  assert.equal(audit.count, 65)
  assert.ok(audit.minNavigationHeight >= 44, JSON.stringify(audit))
  assert.equal(audit.mountedPages, 1)
  assert.deepEqual(audit.failures, [])
})
