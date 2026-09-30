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

async function touchEvent(type, touchPoints) {
  await cdp.send("Input.dispatchTouchEvent", {
    type,
    touchPoints,
    modifiers: 0,
  })
}

async function withTouchEmulation(run) {
  const connection = await session.page.context().newCDPSession(session.page)
  cdp = connection
  await connection.send("Emulation.setTouchEmulationEnabled", { enabled: true, maxTouchPoints: 2 })
  try {
    return await run()
  } finally {
    await connection.send("Input.dispatchTouchEvent", {
      type: "touchCancel",
      touchPoints: [],
      modifiers: 0,
    }).catch(() => {})
    await connection.send("Emulation.setTouchEmulationEnabled", { enabled: false }).catch(() => {})
    await connection.detach().catch(() => {})
    if (cdp === connection) cdp = undefined
  }
}

async function openGallery() {
  await browser("set", "media", "light")
  await browser("set", "viewport", "390", "844")
  await browser("open", `${origin}/examples/components/web/index.html`)
  await browser("wait", "--load", "networkidle")
}

async function selectPlatform(platform) {
  await browser("select", 'select[aria-label="Simulator platform"]', platform)
}

async function selectFormFactor(formFactor) {
  await browser("select", 'select[aria-label="Simulator form factor"]', formFactor)
}

async function rotateSimulator() {
  await browser("click", 'button[aria-label="Rotate simulator"]')
}

async function openGalleryPage(name) {
  await browser("click-text", "nav button", name)
}

async function openSheet() {
  await openGalleryPage("Sheet")
  await browser("click-button", "Open sheet")
  await session.page.locator(".lui-sheet").evaluate(async (sheet) => {
    await new Promise((resolve) => requestAnimationFrame(() => resolve()))
    await Promise.all(sheet.getAnimations().map((animation) => animation.finished.catch(() => {})))
    await new Promise((resolve) => requestAnimationFrame(() => resolve()))
  })
}

before(async () => {
  session = await createPlaywrightSession()
  server = createStaticServer(new URL("../../../", import.meta.url).pathname)
  server.listen(0, "127.0.0.1")
  await once(server, "listening")
  origin = `http://127.0.0.1:${server.address().port}`
})

after(async () => {
  await cdp?.detach().catch(() => {})
  if (session) await session.close().catch(() => {})
  if (server?.listening) {
    const closed = once(server, "close")
    server.close()
    await closed
  }
})

test("the Web Gallery starts as a semantic iOS simulator", async () => {
  await openGallery()

  assert.deepEqual(
    await state(`({
      hostProfile: document.querySelector('#app')?.getAttribute('data-lui-platform'),
      portalProfile: document.querySelector('.lui-popup-portal')?.getAttribute('data-lui-platform'),
      selectedProfile: document.querySelector('select[aria-label="Simulator platform"]')?.value,
      selectedFormFactor: document.querySelector('select[aria-label="Simulator form factor"]')?.value,
      controlsOutsideHost: !document.querySelector('#app')?.contains(
        document.querySelector('select[aria-label="Simulator platform"]'),
      ),
      formFactor: document.querySelector('#app')?.getAttribute('data-lui-form-factor'),
      portalFormFactor: document.querySelector('.lui-popup-portal')?.getAttribute('data-lui-form-factor'),
      orientation: document.querySelector('#app')?.getAttribute('data-lui-orientation'),
      pointer: document.querySelector('#app')?.getAttribute('data-lui-pointer'),
      keyboard: document.querySelector('#app')?.getAttribute('data-lui-keyboard'),
      viewportWidth: getComputedStyle(document.querySelector('#app')).getPropertyValue('--lui-viewport-width').trim(),
      viewportHeight: getComputedStyle(document.querySelector('#app')).getPropertyValue('--lui-viewport-height').trim(),
      deviceScale: getComputedStyle(document.querySelector('#app')).getPropertyValue('--lui-device-scale').trim(),
      safeAreaTop: getComputedStyle(document.querySelector('#app')).getPropertyValue('--lui-safe-area-top').trim(),
      safeAreaBottom: getComputedStyle(document.querySelector('#app')).getPropertyValue('--lui-safe-area-bottom').trim(),
      keyboardHeight: getComputedStyle(document.querySelector('#app')).getPropertyValue('--lui-keyboard-height').trim(),
      canvasCount: document.querySelectorAll('#app canvas, .lui-popup-portal canvas').length,
      buttonTag: document.querySelector('nav button')?.tagName,
    })`),
    {
      hostProfile: "ios",
      portalProfile: "ios",
      selectedProfile: "ios",
      selectedFormFactor: "phone",
      controlsOutsideHost: true,
      formFactor: "phone",
      portalFormFactor: "phone",
      orientation: "portrait",
      pointer: "touch",
      keyboard: "hidden",
      viewportWidth: "390px",
      viewportHeight: "844px",
      deviceScale: "3",
      safeAreaTop: "47px",
      safeAreaBottom: "34px",
      keyboardHeight: "0px",
      canvasCount: 0,
      buttonTag: "BUTTON",
    },
  )
})

test("phone Gallery starts with an accessible component list and an in-bounds simulator dock", async () => {
  await openGallery()

  assert.deepEqual(
    await state(`(() => {
      const shell = document.querySelector('.lui-gallery-shell')
      const navigationBar = shell?.querySelector('.lui-gallery-navigation-bar')
      const back = navigationBar?.querySelector('button')
      const sidebar = shell?.querySelector('.lui-gallery-sidebar')
      const content = shell?.querySelector('.lui-gallery-content')
      const items = [...(sidebar?.querySelectorAll('.lui-gallery-nav-item') ?? [])]
      const toolbar = document.querySelector('.lui-simulator-toolbar')
      const toolbarRect = toolbar?.getBoundingClientRect()
      const firstRect = items[0]?.getBoundingClientRect()
      const secondRect = items[1]?.getBoundingClientRect()
      return {
        navigation: shell?.getAttribute('data-lui-navigation'),
        title: navigationBar?.querySelector('.lui-gallery-navigation-title')?.textContent,
        backHidden: back?.hidden,
        backLabel: back?.getAttribute('aria-label'),
        sidebarDisplay: getComputedStyle(sidebar).display,
        sidebarHidden: sidebar?.getAttribute('aria-hidden'),
        sidebarInert: sidebar?.hasAttribute('inert'),
        contentDisplay: getComputedStyle(content).display,
        contentHidden: content?.getAttribute('aria-hidden'),
        contentInert: content?.hasAttribute('inert'),
        itemDirection: Math.round(secondRect.top - firstRect.top) > 0 ? 'vertical' : 'horizontal',
        itemWidth: Math.round(firstRect.width),
        toolbarInsideViewport: toolbarRect.left >= 8 && toolbarRect.right <= innerWidth - 8,
        toolbarBeforeContent: toolbarRect.bottom <= shell.getBoundingClientRect().top,
      }
    })()`),
    {
      navigation: "list",
      title: "Components",
      backHidden: true,
      backLabel: "Back to Components",
      sidebarDisplay: "flex",
      sidebarHidden: "false",
      sidebarInert: false,
      contentDisplay: "none",
      contentHidden: "true",
      contentInert: true,
      itemDirection: "vertical",
      itemWidth: 358,
      toolbarInsideViewport: true,
      toolbarBeforeContent: true,
    },
  )
})

test("phone Gallery push and back preserve the retained page and restore focus", async () => {
  await openGallery()
  await openGalleryPage("TextField")

  assert.deepEqual(
    await state(`(() => {
      const shell = document.querySelector('.lui-gallery-shell')
      const back = shell.querySelector('.lui-gallery-navigation-back')
      const input = shell.querySelector('.lui-text-field')
      input.value = 'retained draft'
      window.__luiPhoneGalleryInput = input
      window.__luiPhoneGalleryShell = shell
      return {
        navigation: shell.dataset.luiNavigation,
        title: shell.querySelector('.lui-gallery-navigation-title').textContent,
        backHidden: back.hidden,
        backFocused: document.activeElement === back,
        sidebarDisplay: getComputedStyle(shell.querySelector('.lui-gallery-sidebar')).display,
        contentDisplay: getComputedStyle(shell.querySelector('.lui-gallery-content')).display,
      }
    })()`),
    {
      navigation: "detail",
      title: "TextField",
      backHidden: false,
      backFocused: true,
      sidebarDisplay: "none",
      contentDisplay: "block",
    },
  )

  await browser("click", ".lui-gallery-navigation-back")

  assert.deepEqual(
    await state(`(() => {
      const shell = document.querySelector('.lui-gallery-shell')
      const selected = shell.querySelector('.lui-gallery-nav-item[data-selected="true"]')
      return {
        sameShell: shell === window.__luiPhoneGalleryShell,
        navigation: shell.dataset.luiNavigation,
        title: shell.querySelector('.lui-gallery-navigation-title').textContent,
        selected: selected?.textContent,
        selectedFocused: document.activeElement === selected,
        sameInput: shell.querySelector('.lui-text-field') === window.__luiPhoneGalleryInput,
        inputValue: shell.querySelector('.lui-text-field')?.value,
        contentHidden: shell.querySelector('.lui-gallery-content')?.getAttribute('aria-hidden'),
        contentInert: shell.querySelector('.lui-gallery-content')?.hasAttribute('inert'),
      }
    })()`),
    {
      sameShell: true,
      navigation: "list",
      title: "Components",
      selected: "TextField",
      selectedFocused: true,
      sameInput: true,
      inputValue: "retained draft",
      contentHidden: "true",
      contentInert: true,
    },
  )

  await browser("click", ".lui-gallery-nav-item[data-selected='true']")
  await selectPlatform("android")

  assert.deepEqual(
    await state(`(() => {
      const shell = document.querySelector('.lui-gallery-shell')
      const input = shell.querySelector('.lui-text-field')
      return {
        sameShell: shell === window.__luiPhoneGalleryShell,
        navigation: shell.dataset.luiNavigation,
        sameInput: input === window.__luiPhoneGalleryInput,
        inputValue: input.value,
        platform: shell.closest('[data-lui-platform]')?.dataset.luiPlatform,
        backFocused: document.activeElement === shell.querySelector('.lui-gallery-navigation-back'),
      }
    })()`),
    {
      sameShell: true,
      navigation: "detail",
      sameInput: true,
      inputValue: "retained draft",
      platform: "android",
      backFocused: true,
    },
  )
})

test("tablet Gallery keeps sidebar and detail visible across phone adaptation and rotation", async () => {
  await openGallery()
  await browser("set", "viewport", "1280", "900")
  await selectFormFactor("tablet")
  await openGalleryPage("NativeExtension")

  assert.deepEqual(
    await state(`(() => {
      const shell = document.querySelector('.lui-gallery-shell')
      const sidebar = shell.querySelector('.lui-gallery-sidebar')
      const content = shell.querySelector('.lui-gallery-content')
      const map = shell.querySelector('.lui-simulator-map')
      window.__luiAdaptiveMap = map
      return {
        formFactor: document.querySelector('#app').dataset.luiFormFactor,
        sidebarDisplay: getComputedStyle(sidebar).display,
        contentDisplay: getComputedStyle(content).display,
        sidebarHidden: sidebar.getAttribute('aria-hidden'),
        contentHidden: content.getAttribute('aria-hidden'),
        backHidden: shell.querySelector('.lui-gallery-navigation-back').hidden,
        selected: sidebar.querySelector('[data-selected="true"]')?.textContent,
        mapPresent: Boolean(map),
      }
    })()`),
    {
      formFactor: "tablet",
      sidebarDisplay: "flex",
      contentDisplay: "block",
      sidebarHidden: "false",
      contentHidden: "false",
      backHidden: true,
      selected: "NativeExtension",
      mapPresent: true,
    },
  )

  await selectFormFactor("phone")
  await rotateSimulator()

  assert.deepEqual(
    await state(`(() => {
      const shell = document.querySelector('.lui-gallery-shell')
      return {
        formFactor: document.querySelector('#app').dataset.luiFormFactor,
        orientation: document.querySelector('#app').dataset.luiOrientation,
        navigation: shell.dataset.luiNavigation,
        sidebarDisplay: getComputedStyle(shell.querySelector('.lui-gallery-sidebar')).display,
        contentDisplay: getComputedStyle(shell.querySelector('.lui-gallery-content')).display,
        backHidden: shell.querySelector('.lui-gallery-navigation-back').hidden,
        sameMap: shell.querySelector('.lui-simulator-map') === window.__luiAdaptiveMap,
      }
    })()`),
    {
      formFactor: "phone",
      orientation: "landscape",
      navigation: "detail",
      sidebarDisplay: "none",
      contentDisplay: "block",
      backHidden: false,
      sameMap: true,
    },
  )

  await selectFormFactor("tablet")

  assert.deepEqual(
    await state(`(() => {
      const shell = document.querySelector('.lui-gallery-shell')
      return {
        sidebarDisplay: getComputedStyle(shell.querySelector('.lui-gallery-sidebar')).display,
        contentDisplay: getComputedStyle(shell.querySelector('.lui-gallery-content')).display,
        backHidden: shell.querySelector('.lui-gallery-navigation-back').hidden,
        sameMap: shell.querySelector('.lui-simulator-map') === window.__luiAdaptiveMap,
      }
    })()`),
    {
      sidebarDisplay: "flex",
      contentDisplay: "block",
      backHidden: true,
      sameMap: true,
    },
  )
})

test("Bottom Tabs retain native page state across iOS Liquid Glass and Android Material profiles", async () => {
  await openGallery()
  await openGalleryPage("BottomTabs")

  const initial = await state(`(() => {
    const root = document.querySelector('.lui-bottom-tabs')
    const bar = root?.querySelector('.lui-bottom-tabs-bar')
    const tabs = [...(bar?.querySelectorAll('.lui-bottom-tabs-tab') ?? [])]
    const panels = [...(root?.querySelectorAll('.lui-bottom-tab') ?? [])]
    const barStyle = bar ? getComputedStyle(bar) : null
    window.__luiBottomTabsRoot = root
    window.__luiBottomTabPanels = panels
    return {
      rootPresent: Boolean(root),
      role: bar?.getAttribute('role'),
      label: bar?.getAttribute('aria-label'),
      tabLabels: tabs.map((tab) => tab.textContent.trim()),
      tabRoles: tabs.map((tab) => tab.getAttribute('role')),
      tabIcons: tabs.map((tab) => tab.querySelector('.lui-icon')?.dataset.name),
      selected: tabs.find((tab) => tab.getAttribute('aria-selected') === 'true')?.textContent.trim(),
      panelRoles: panels.map((panel) => panel.getAttribute('role')),
      panelHidden: panels.map((panel) => panel.hidden),
      panelInert: panels.map((panel) => panel.hasAttribute('inert')),
      tabIds: tabs.map((tab) => tab.id),
      panelIds: panels.map((panel) => panel.id),
      controlled: tabs.map((tab) => tab.getAttribute('aria-controls')),
      labelled: panels.map((panel) => panel.getAttribute('aria-labelledby')),
      barHeight: Math.round(bar?.getBoundingClientRect().height ?? 0),
      bottomGap: barStyle?.marginBottom,
      radius: barStyle?.borderRadius,
      backdrop: barStyle?.backdropFilter,
      canvasCount: root?.querySelectorAll('canvas').length,
    }
  })()`)

  assert.deepEqual(initial, {
    rootPresent: true,
    role: "tablist",
    label: "Primary destinations",
    tabLabels: ["Home", "Search", "Settings"],
    tabRoles: ["tab", "tab", "tab"],
    tabIcons: ["folder", "search", "settings"],
    selected: "Home",
    panelRoles: ["tabpanel", "tabpanel", "tabpanel"],
    panelHidden: [false, true, true],
    panelInert: [false, true, true],
    tabIds: initial.tabIds,
    panelIds: initial.panelIds,
    controlled: initial.controlled,
    labelled: initial.labelled,
    barHeight: 64,
    bottomGap: "34px",
    radius: "32px",
    backdrop: "blur(24px) saturate(1.8)",
    canvasCount: 0,
  })
  assert.ok(initial.controlled.every(Boolean))
  assert.ok(initial.labelled.every(Boolean))
  assert.deepEqual(initial.controlled, initial.panelIds)
  assert.deepEqual(initial.labelled, initial.tabIds)

  await evaluate(`(() => {
    const root = document.querySelector('.lui-bottom-tabs')
    const homeInput = root.querySelector('input[placeholder="Retained home draft"]')
    homeInput.value = 'kept draft'
    window.__luiBottomTabHomeInput = homeInput
  })()`)
  await browser("click", ".lui-bottom-tabs-tab:nth-child(2)")

  assert.deepEqual(
    await state(`(() => {
      const root = document.querySelector('.lui-bottom-tabs')
      const tabs = [...root.querySelectorAll('.lui-bottom-tabs-tab')]
      const panels = [...root.querySelectorAll('.lui-bottom-tab')]
      return {
        sameRoot: root === window.__luiBottomTabsRoot,
        samePanels: panels.every((panel, index) => panel === window.__luiBottomTabPanels[index]),
        selected: tabs.find((tab) => tab.getAttribute('aria-selected') === 'true')?.textContent.trim(),
        focused: document.activeElement?.textContent.trim(),
        panelHidden: panels.map((panel) => panel.hidden),
        panelInert: panels.map((panel) => panel.hasAttribute('inert')),
        sameInput: root.querySelector('input[placeholder="Retained home draft"]') === window.__luiBottomTabHomeInput,
        inputValue: window.__luiBottomTabHomeInput.value,
      }
    })()`),
    {
      sameRoot: true,
      samePanels: true,
      selected: "Search",
      focused: "Search",
      panelHidden: [true, false, true],
      panelInert: [true, false, true],
      sameInput: true,
      inputValue: "kept draft",
    },
  )

  await selectPlatform("android")

  assert.deepEqual(
    await state(`(() => {
      const root = document.querySelector('.lui-bottom-tabs')
      const bar = root.querySelector('.lui-bottom-tabs-bar')
      const selected = bar.querySelector('[aria-selected="true"]')
      const style = getComputedStyle(bar)
      const indicator = getComputedStyle(selected, '::before')
      return {
        sameRoot: root === window.__luiBottomTabsRoot,
        samePanels: [...root.querySelectorAll('.lui-bottom-tab')]
          .every((panel, index) => panel === window.__luiBottomTabPanels[index]),
        selected: selected.textContent.trim(),
        focused: document.activeElement === selected,
        platform: document.querySelector('#app').dataset.luiPlatform,
        height: Math.round(bar.getBoundingClientRect().height),
        bottomGap: style.marginBottom,
        radius: style.borderRadius,
        backdrop: style.backdropFilter,
        indicatorWidth: indicator.width,
        indicatorHeight: indicator.height,
        sameInput: root.querySelector('input[placeholder="Retained home draft"]') === window.__luiBottomTabHomeInput,
        inputValue: window.__luiBottomTabHomeInput.value,
      }
    })()`),
    {
      sameRoot: true,
      samePanels: true,
      selected: "Search",
      focused: true,
      platform: "android",
      height: 104,
      bottomGap: "0px",
      radius: "0px",
      backdrop: "none",
      indicatorWidth: "64px",
      indicatorHeight: "32px",
      sameInput: true,
      inputValue: "kept draft",
    },
  )
})

test("platform switching preserves focused retained input identity and rejects unknown profiles", async () => {
  await openGallery()
  await openGalleryPage("TextField")

  await session.page.locator(".lui-text-field").focus()
  await session.page.locator(".lui-text-field").fill("draft text")
  await evaluate(`(() => {
    const input = document.querySelector('.lui-text-field')
    input.setSelectionRange(3, 7)
    window.__luiSimulatorInput = input
  })()`)
  await selectPlatform("android")

  assert.deepEqual(
    await state(`(() => {
      const input = document.querySelector('.lui-text-field')
      return {
        hostProfile: document.querySelector('#app')?.getAttribute('data-lui-platform'),
        portalProfile: document.querySelector('.lui-popup-portal')?.getAttribute('data-lui-platform'),
        sameInput: input === window.__luiSimulatorInput,
        focused: input === document.activeElement,
        value: input?.value,
        selectionStart: input?.selectionStart,
        selectionEnd: input?.selectionEnd,
        formFactor: document.querySelector('#app')?.getAttribute('data-lui-form-factor'),
        orientation: document.querySelector('#app')?.getAttribute('data-lui-orientation'),
        keyboard: document.querySelector('#app')?.getAttribute('data-lui-keyboard'),
        viewportWidth: getComputedStyle(document.querySelector('#app')).getPropertyValue('--lui-viewport-width').trim(),
        viewportHeight: getComputedStyle(document.querySelector('#app')).getPropertyValue('--lui-viewport-height').trim(),
        safeAreaTop: getComputedStyle(document.querySelector('#app')).getPropertyValue('--lui-safe-area-top').trim(),
        safeAreaBottom: getComputedStyle(document.querySelector('#app')).getPropertyValue('--lui-safe-area-bottom').trim(),
        keyboardHeight: getComputedStyle(document.querySelector('#app')).getPropertyValue('--lui-keyboard-height').trim(),
      }
    })()`),
    {
      hostProfile: "android",
      portalProfile: "android",
      sameInput: true,
      focused: true,
      value: "draft text",
      selectionStart: 3,
      selectionEnd: 7,
      formFactor: "phone",
      orientation: "portrait",
      keyboard: "visible",
      viewportWidth: "412px",
      viewportHeight: "915px",
      safeAreaTop: "24px",
      safeAreaBottom: "24px",
      keyboardHeight: "300px",
    },
  )

  await evaluate(`document.querySelector('.lui-text-field')?.blur()`)
  assert.deepEqual(
    await state(`({
      hostKeyboard: document.querySelector('#app')?.getAttribute('data-lui-keyboard'),
      portalKeyboard: document.querySelector('.lui-popup-portal')?.getAttribute('data-lui-keyboard'),
      keyboardHeight: getComputedStyle(document.querySelector('#app')).getPropertyValue('--lui-keyboard-height').trim(),
    })`),
    { hostKeyboard: "hidden", portalKeyboard: "hidden", keyboardHeight: "0px" },
  )

  await evaluate(`(() => {
    const select = document.querySelector('select[aria-label="Simulator platform"]')
    select.append(new Option('Unknown', 'unknown'))
    select.value = 'unknown'
    select.dispatchEvent(new Event('change', { bubbles: true }))
  })()`)

  assert.deepEqual(
    await state(`({
      hostProfile: document.querySelector('#app')?.getAttribute('data-lui-platform'),
      portalProfile: document.querySelector('.lui-popup-portal')?.getAttribute('data-lui-platform'),
    })`),
    { hostProfile: "android", portalProfile: "android" },
  )
})

test("tablet and rotation traits propagate without replacing the retained application", async () => {
  await openGallery()
  await evaluate(`window.__luiSimulatorRoot = document.querySelector('.lui-root')`)

  await selectFormFactor("tablet")
  await rotateSimulator()

  assert.deepEqual(
    await state(`(() => {
      const host = document.querySelector('#app')
      const portal = document.querySelector('.lui-popup-portal')
      const hostStyle = getComputedStyle(host)
      const portalStyle = getComputedStyle(portal)
      return {
        sameRoot: document.querySelector('.lui-root') === window.__luiSimulatorRoot,
        hostFormFactor: host?.getAttribute('data-lui-form-factor'),
        portalFormFactor: portal?.getAttribute('data-lui-form-factor'),
        hostOrientation: host?.getAttribute('data-lui-orientation'),
        portalOrientation: portal?.getAttribute('data-lui-orientation'),
        pointer: host?.getAttribute('data-lui-pointer'),
        viewportWidth: hostStyle.getPropertyValue('--lui-viewport-width').trim(),
        viewportHeight: hostStyle.getPropertyValue('--lui-viewport-height').trim(),
        portalWidth: portalStyle.getPropertyValue('--lui-viewport-width').trim(),
        deviceScale: hostStyle.getPropertyValue('--lui-device-scale').trim(),
        safeAreaTop: hostStyle.getPropertyValue('--lui-safe-area-top').trim(),
        safeAreaRight: hostStyle.getPropertyValue('--lui-safe-area-right').trim(),
        safeAreaBottom: hostStyle.getPropertyValue('--lui-safe-area-bottom').trim(),
        safeAreaLeft: hostStyle.getPropertyValue('--lui-safe-area-left').trim(),
      }
    })()`),
    {
      sameRoot: true,
      hostFormFactor: "tablet",
      portalFormFactor: "tablet",
      hostOrientation: "landscape",
      portalOrientation: "landscape",
      pointer: "hybrid",
      viewportWidth: "1366px",
      viewportHeight: "1024px",
      portalWidth: "1366px",
      deviceScale: "2",
      safeAreaTop: "24px",
      safeAreaRight: "0px",
      safeAreaBottom: "20px",
      safeAreaLeft: "0px",
    },
  )

  await evaluate(`(() => {
    const select = document.querySelector('select[aria-label="Simulator form factor"]')
    select.append(new Option('Unknown', 'unknown'))
    select.value = 'unknown'
    select.dispatchEvent(new Event('change', { bubbles: true }))
  })()`)

  assert.deepEqual(
    await state(`({
      formFactor: document.querySelector('#app')?.getAttribute('data-lui-form-factor'),
      orientation: document.querySelector('#app')?.getAttribute('data-lui-orientation'),
      viewportWidth: getComputedStyle(document.querySelector('#app')).getPropertyValue('--lui-viewport-width').trim(),
    })`),
    { formFactor: "tablet", orientation: "landscape", viewportWidth: "1366px" },
  )
})

test("an open portaled surface follows profile changes without replacement", async () => {
  await openGallery()
  await selectPlatform("android")
  await openGalleryPage("Dialog")
  await browser("click-button", "Open dialog")

  assert.deepEqual(
    await state(`(() => {
      const surface = document.querySelector('.lui-dialog')
      window.__luiSimulatorDialog = surface
      return {
        portalProfile: surface?.closest('.lui-popup-portal')?.getAttribute('data-lui-platform'),
        role: surface?.getAttribute('role'),
      }
    })()`),
    { portalProfile: "android", role: "dialog" },
  )

  await selectPlatform("ios")

  assert.deepEqual(
    await state(`(() => {
      const surface = document.querySelector('.lui-dialog')
      return {
        hostProfile: document.querySelector('#app')?.getAttribute('data-lui-platform'),
        portalProfile: surface?.closest('.lui-popup-portal')?.getAttribute('data-lui-platform'),
        sameDialog: surface === window.__luiSimulatorDialog,
      }
    })()`),
    { hostProfile: "ios", portalProfile: "ios", sameDialog: true },
  )
})

test("iOS and Android produce deterministic computed control metrics", async () => {
  await openGallery()
  await openGalleryPage("Button")

  const ios = await state(`(() => {
    const button = document.querySelector('.lui-button[data-variant="primary"]')
    const style = getComputedStyle(button)
    window.__luiSimulatorMetricButton = button
    return {
      minHeight: style.minHeight,
      borderRadius: style.borderRadius,
      fontSize: style.fontSize,
      fontWeight: style.fontWeight,
      backgroundColor: style.backgroundColor,
    }
  })()`)

  await selectPlatform("android")
  await browser("wait", "300")

  const android = await state(`(() => {
    const button = document.querySelector('.lui-button[data-variant="primary"]')
    const style = getComputedStyle(button)
    return {
      sameButton: button === window.__luiSimulatorMetricButton,
      minHeight: style.minHeight,
      borderRadius: style.borderRadius,
      fontSize: style.fontSize,
      fontWeight: style.fontWeight,
      backgroundColor: style.backgroundColor,
    }
  })()`)

  assert.deepEqual(ios, {
    minHeight: "44px",
    borderRadius: "10px",
    fontSize: "17px",
    fontWeight: "600",
    backgroundColor: "rgb(0, 122, 255)",
  })
  assert.deepEqual(android, {
    sameButton: true,
    minHeight: "40px",
    borderRadius: "20px",
    fontSize: "14px",
    fontWeight: "500",
    backgroundColor: "rgb(103, 80, 164)",
  })
})

test("Switch keeps its label leading and native control trailing", async () => {
  await openGallery()
  await openGalleryPage("Switch")

  assert.deepEqual(
    await state(`(() => {
      const field = document.querySelector('.lui-switch')
      const label = field?.querySelector('.lui-control-label')?.getBoundingClientRect()
      const control = field?.querySelector('.lui-switch-control')?.getBoundingClientRect()
      return {
        labelLeading: (label?.left ?? Infinity) < (control?.left ?? -Infinity),
        controlTrailing: Math.abs((field?.getBoundingClientRect().right ?? 0) - (control?.right ?? 1)) < 1,
      }
    })()`),
    { labelLeading: true, controlTrailing: true },
  )
})

test("phone Sheet uses the simulated viewport on a wide browser and avoids its keyboard", async () => {
  await withTouchEmulation(async () => {
  await openGallery()
  await browser("set", "viewport", "1280", "900")
  await openSheet()
  const sheet = session.page.locator(".lui-sheet")
  await sheet.locator(".lui-sheet-title").click()
  await browser("wait", "--fn", "document.querySelector('#app')?.getAttribute('data-lui-keyboard') === 'hidden'")
  assert.deepEqual(
    await state(`(() => {
      const host = document.querySelector('#app')
      const toolbar = document.querySelector('.lui-simulator-toolbar')
      const layer = document.querySelector('.lui-modal-layer')
      const sheet = document.querySelector('.lui-sheet')
      const hostRect = host.getBoundingClientRect()
      const toolbarRect = toolbar.getBoundingClientRect()
      const layerRect = layer.getBoundingClientRect()
      const sheetRect = sheet.getBoundingClientRect()
      return {
        host: {
          left: Math.round(hostRect.left), top: Math.round(hostRect.top),
          width: Math.round(hostRect.width), height: Math.round(hostRect.height),
        },
        hostFlowOffset: Math.round(hostRect.top - toolbarRect.bottom),
        layer: {
          left: Math.round(layerRect.left), top: Math.round(layerRect.top),
          width: Math.round(layerRect.width), height: Math.round(layerRect.height),
        },
        sheetWidth: Math.round(sheetRect.width),
        sheetBottom: Math.round(sheetRect.bottom),
        layerBottom: Math.round(layerRect.bottom),
        safePaddingBottom: getComputedStyle(sheet).paddingBottom,
        handleVisible: getComputedStyle(sheet.querySelector('.lui-sheet-handle')).display !== 'none',
      }
    })()`),
    {
      host: { left: 445, top: 82, width: 390, height: 844 },
      hostFlowOffset: 28,
      layer: { left: 445, top: 28, width: 390, height: 844 },
      sheetWidth: 390,
      sheetBottom: 872,
      layerBottom: 872,
      safePaddingBottom: "34px",
      handleVisible: true,
    },
  )
  const bounds = await sheet.boundingBox()
  assert.ok(bounds)
  await evaluate(`window.__luiSimulatorPointerId = null;
    document.querySelector('.lui-sheet').addEventListener('pointerdown', event => {
      if (event.pointerType === 'touch') window.__luiSimulatorPointerId = event.pointerId
    }, { once: true })`)
  await touchEvent("touchStart", [{
    x: bounds.x + 40,
    y: bounds.y + 40,
    id: 91,
  }])
  await touchEvent("touchMove", [{
    x: bounds.x + 40,
    y: bounds.y + 120,
    id: 91,
  }])

  assert.deepEqual(
    await state(`(() => {
      const sheet = document.querySelector('.lui-sheet')
      return {
        swiping: sheet.hasAttribute('data-swiping'),
        swipeDirection: sheet.getAttribute('data-swipe-direction'),
        swipeMovement: sheet.style.getPropertyValue('--drawer-swipe-movement-y'),
      }
    })()`),
    { swiping: true, swipeDirection: "down", swipeMovement: "80px" },
  )

  await evaluate(`new Promise((resolve) => {
    const sheet = document.querySelector('.lui-sheet')
    sheet.addEventListener('transitionend', (event) => {
      if (event.propertyName !== 'transform') return
      const input = sheet.querySelector('.lui-input')
      input.focus()
      window.__luiSimulatorSheetInput = input
      resolve(true)
    }, { once: true })
    sheet.dispatchEvent(new PointerEvent('pointercancel', {
      bubbles: true, pointerId: window.__luiSimulatorPointerId, pointerType: 'touch', button: 0,
    }))
  })`)

  assert.deepEqual(
    await state(`(() => {
      const layerRect = document.querySelector('.lui-modal-layer').getBoundingClientRect()
      const sheet = document.querySelector('.lui-sheet')
      const sheetRect = sheet.getBoundingClientRect()
      const input = sheet.querySelector('.lui-input')
      return {
        sameInput: input === window.__luiSimulatorSheetInput,
        focused: input === document.activeElement,
        keyboard: document.querySelector('#app')?.getAttribute('data-lui-keyboard'),
        keyboardHeight: getComputedStyle(document.querySelector('#app')).getPropertyValue('--lui-keyboard-height').trim(),
        computedBottom: getComputedStyle(sheet).bottom,
        layerBottom: Math.round(layerRect.bottom),
        sheetBottom: Math.round(sheetRect.bottom),
        bottomGap: Math.round(layerRect.bottom - sheetRect.bottom),
      }
    })()`),
    {
      sameInput: true,
      focused: true,
      keyboard: "visible",
      keyboardHeight: "291px",
      computedBottom: "291px",
      layerBottom: 872,
      sheetBottom: 581,
      bottomGap: 291,
    },
  )
  })
})

test("phone Sheet retains a focused draft through a short viewport shrink", async () => {
  await openGallery()
  await browser("set", "viewport", "390", "620")
  await openSheet()
  const sheet = session.page.locator(".lui-sheet")
  const input = sheet.locator(".lui-input")
  const originalInput = await input.elementHandle()
  assert.ok(originalInput, "simulator Sheet input handle should exist before resize")
  await input.click()
  await session.page.keyboard.type("retained draft")
  await input.press("End")
  await input.press("Shift+Home")
  await browser("wait", "--fn", "document.querySelector('#app')?.getAttribute('data-lui-keyboard') === 'visible'")

  await browser("set", "viewport", "390", "520")
  await browser("wait", "50")
  const shortViewport = await state(`(() => {
    const host = document.querySelector('#app')
    const layer = document.querySelector('.lui-modal-layer')
    const sheet = document.querySelector('.lui-sheet')
    const title = sheet?.querySelector('.lui-sheet-title')
    const handle = sheet?.querySelector('.lui-sheet-handle')
    const input = sheet?.querySelector('.lui-input')
    const keyboardHeight = Number.parseFloat(
      getComputedStyle(host).getPropertyValue('--lui-keyboard-height'),
    )
    const layerRect = layer?.getBoundingClientRect()
    const sheetRect = sheet?.getBoundingClientRect()
    const inside = (element) => {
      const rect = element?.getBoundingClientRect()
      return Boolean(
        rect
        && layerRect
        && rect.width > 0
        && rect.height > 0
        && rect.left >= Math.max(0, layerRect.left)
        && rect.right <= Math.min(innerWidth, layerRect.right)
        && rect.top >= Math.max(0, layerRect.top)
        && rect.bottom <= Math.min(innerHeight, layerRect.bottom),
      )
    }
    return {
      layerTop: layerRect?.top,
      layerBottom: layerRect?.bottom,
      sheetTop: sheetRect?.top,
      sheetBottom: sheetRect?.bottom,
      effectiveKeyboardHeight: keyboardHeight,
      sheetWithinKeyboardGap: Boolean(
        layerRect
        && sheetRect
        && sheetRect.bottom <= layerRect.bottom - keyboardHeight + 1,
      ),
      value: input?.value,
      selected: input?.selectionStart === 0 && input?.selectionEnd === input?.value.length,
      focused: document.activeElement === input,
      titleInBounds: inside(title),
      handleInBounds: inside(handle),
      sheetBodyScrollable: (sheet?.querySelector('.lui-sheet-body')?.scrollHeight ?? 0)
        > (sheet?.querySelector('.lui-sheet-body')?.clientHeight ?? 0),
    }
  })()`)
  assert.deepEqual(
    {
      effectiveKeyboardHeight: shortViewport.effectiveKeyboardHeight,
      sheetWithinKeyboardGap: shortViewport.sheetWithinKeyboardGap,
      value: shortViewport.value,
      selected: shortViewport.selected,
      focused: shortViewport.focused,
      titleInBounds: shortViewport.titleInBounds,
      handleInBounds: shortViewport.handleInBounds,
      sheetBodyScrollable: shortViewport.sheetBodyScrollable,
    },
    {
      effectiveKeyboardHeight: 291,
      sheetWithinKeyboardGap: true,
      value: "retained draft",
      selected: true,
      focused: true,
      titleInBounds: true,
      handleInBounds: true,
      sheetBodyScrollable: true,
    },
  )
  assert.ok(shortViewport.sheetTop >= shortViewport.layerTop)
  assert.ok(shortViewport.sheetBottom <= shortViewport.layerBottom - shortViewport.effectiveKeyboardHeight + 1)
  assert.equal(
    await originalInput.evaluate((element) =>
      element.isConnected
      && element === document.querySelector('.lui-sheet .lui-input')),
    true,
  )

  const cancel = sheet.getByRole("button", { name: "Cancel", exact: true })
  await cancel.scrollIntoViewIfNeeded()
  await browser("wait", "50")
  const cancelBounds = await cancel.boundingBox()
  const bodyBounds = await sheet.locator(".lui-sheet-body").boundingBox()
  assert.ok(cancelBounds, "simulator Cancel should be reachable after body scrolling")
  assert.ok(bodyBounds)
  assert.ok(
    cancelBounds.y >= bodyBounds.y
    && cancelBounds.y + cancelBounds.height <= bodyBounds.y + bodyBounds.height
    && cancelBounds.y >= 0
    && cancelBounds.y + cancelBounds.height <= 520,
  )
})

test("tablet Sheet stays a side surface on a compact browser and rejects phone swipes", async () => {
  await withTouchEmulation(async () => {
  await openGallery()
  await selectFormFactor("tablet")
  await openSheet()
  const sheet = session.page.locator(".lui-sheet")
  const bounds = await sheet.boundingBox()
  assert.ok(bounds)
  await touchEvent("touchStart", [{
    x: bounds.x + 40,
    y: bounds.y + 40,
    id: 92,
  }])
  await touchEvent("touchMove", [{
    x: bounds.x + 40,
    y: bounds.y + 120,
    id: 92,
  }])

  assert.deepEqual(
    await state(`(() => {
      const hostRect = document.querySelector('#app').getBoundingClientRect()
      const layerRect = document.querySelector('.lui-modal-layer').getBoundingClientRect()
      const sheet = document.querySelector('.lui-sheet')
      const sheetRect = sheet.getBoundingClientRect()
      return {
        hostWidth: Math.round(hostRect.width),
        hostHeight: Math.round(hostRect.height),
        layerWidth: Math.round(layerRect.width),
        layerHeight: Math.round(layerRect.height),
        sheetWidth: Math.round(sheetRect.width),
        sheetHeight: Math.round(sheetRect.height),
        topGap: Math.round(sheetRect.top - layerRect.top),
        rightGap: Math.round(layerRect.right - sheetRect.right),
        swiping: sheet.hasAttribute('data-swiping'),
        swipeDirection: sheet.getAttribute('data-swipe-direction'),
      }
    })()`),
    {
      hostWidth: 390,
      hostHeight: 844,
      layerWidth: 390,
      layerHeight: 844,
      sheetWidth: 384,
      sheetHeight: 844,
      topGap: 0,
      rightGap: 0,
      swiping: false,
      swipeDirection: null,
    },
  )
  })
})

test("Map extension keeps deterministic camera state across platform profiles", async () => {
  await openGallery()
  await openGalleryPage("NativeExtension")
  await browser("click-button", "Zoom in")

  assert.deepEqual(
    await state(`(() => {
      const map = document.querySelector('.lui-simulator-map')
      const marker = map?.querySelector('.lui-simulator-map-marker')
      window.__luiSimulatorMap = map
      window.__luiSimulatorMapMarker = marker
      return {
        role: map?.getAttribute('role'),
        label: map?.getAttribute('aria-label'),
        canvasCount: map?.querySelectorAll('canvas').length,
        centerLatitude: map?.getAttribute('data-center-latitude'),
        centerLongitude: map?.getAttribute('data-center-longitude'),
        latitudeDelta: map?.getAttribute('data-latitude-delta'),
        longitudeDelta: map?.getAttribute('data-longitude-delta'),
        markerTag: marker?.tagName,
        markerTitle: marker?.textContent,
        markerLatitude: marker?.getAttribute('data-latitude'),
        markerLongitude: marker?.getAttribute('data-longitude'),
        markerLeft: marker?.style.left,
        markerTop: marker?.style.top,
        zoomControls: [...(map?.querySelectorAll('.lui-simulator-map-controls button') ?? [])]
          .map((button) => button.getAttribute('aria-label')),
      }
    })()`),
    {
      role: "region",
      label: "Map of San Francisco",
      canvasCount: 0,
      centerLatitude: "37.7793",
      centerLongitude: "-122.4193",
      latitudeDelta: "0.04",
      longitudeDelta: "0.04",
      markerTag: "BUTTON",
      markerTitle: "San Francisco",
      markerLatitude: "37.7793",
      markerLongitude: "-122.4193",
      markerLeft: "50%",
      markerTop: "50%",
      zoomControls: ["Zoom in", "Zoom out", "Recenter map"],
    },
  )

  await browser("drag", ".lui-simulator-map", "160", "120", "120", "160")

  const movedCamera = await state(`(() => {
    const map = document.querySelector('.lui-simulator-map')
    return {
      latitude: map.getAttribute('data-center-latitude'),
      longitude: map.getAttribute('data-center-longitude'),
      grabbed: map.getAttribute('aria-grabbed'),
    }
  })()`)
  assert.notEqual(movedCamera.latitude, "37.7793")
  assert.notEqual(movedCamera.longitude, "-122.4193")
  assert.equal(movedCamera.grabbed, "false")

  await selectPlatform("android")

  assert.deepEqual(
    await state(`(() => {
      const map = document.querySelector('.lui-simulator-map')
      const marker = map.querySelector('.lui-simulator-map-marker')
      return {
        sameMap: map === window.__luiSimulatorMap,
        sameMarker: marker === window.__luiSimulatorMapMarker,
        latitude: map.getAttribute('data-center-latitude'),
        longitude: map.getAttribute('data-center-longitude'),
        latitudeDelta: map.getAttribute('data-latitude-delta'),
        longitudeDelta: map.getAttribute('data-longitude-delta'),
        platform: map.closest('[data-lui-platform]')?.getAttribute('data-lui-platform'),
      }
    })()`),
    {
      sameMap: true,
      sameMarker: true,
      latitude: movedCamera.latitude,
      longitude: movedCamera.longitude,
      latitudeDelta: "0.04",
      longitudeDelta: "0.04",
      platform: "android",
    },
  )
})

test("Camera extension requests permission only on demand and can return to its mock feed", async () => {
  await openGallery()
  await openGalleryPage("NativeExtension")

  assert.deepEqual(
    await state(`(() => {
      const camera = document.querySelector('.lui-simulator-camera')
      const video = camera?.querySelector('video')
      window.__luiSimulatorCamera = camera
      window.__luiSimulatorCameraVideo = video
      return {
        role: camera?.getAttribute('role'),
        label: camera?.getAttribute('aria-label'),
        state: camera?.getAttribute('data-camera-state'),
        videoTag: video?.tagName,
        autoplay: video?.autoplay,
        muted: video?.muted,
        playsInline: video?.playsInline,
        hidden: video?.hidden,
        mockHidden: camera?.querySelector('.lui-simulator-camera-mock')?.hidden,
        status: camera?.querySelector('[role="status"]')?.textContent,
        actions: [...(camera?.querySelectorAll('button') ?? [])].map((button) => button.textContent.trim()),
      }
    })()`),
    {
      role: "group",
      label: "Back camera preview",
      state: "mock",
      videoTag: "VIDEO",
      autoplay: true,
      muted: true,
      playsInline: true,
      hidden: true,
      mockHidden: false,
      status: "Using deterministic simulator camera",
      actions: ["Use browser camera"],
    },
  )

  await evaluate(`(() => {
    window.__luiCameraRequestedConstraints = null
    window.__luiCameraTrackStopped = false
    const stream = new MediaStream()
    Object.defineProperty(stream, 'getTracks', {
      value: () => [{ stop: () => { window.__luiCameraTrackStopped = true } }],
    })
    window.__luiCameraStream = stream
    Object.defineProperty(navigator, 'mediaDevices', {
      configurable: true,
      value: {
        getUserMedia: async (constraints) => {
          window.__luiCameraRequestedConstraints = constraints
          return stream
        },
      },
    })
  })()`)
  await browser("click", ".lui-simulator-camera button")
  await browser("wait", "--fn", "document.querySelector('.lui-simulator-camera')?.dataset.cameraState === 'live'")

  await selectPlatform("android")

  assert.deepEqual(
    await state(`(() => {
      const camera = document.querySelector('.lui-simulator-camera')
      const video = camera.querySelector('video')
      return {
        sameCamera: camera === window.__luiSimulatorCamera,
        sameVideo: video === window.__luiSimulatorCameraVideo,
        state: camera.dataset.cameraState,
        constraints: window.__luiCameraRequestedConstraints,
        sameStream: video.srcObject === window.__luiCameraStream,
        hidden: video.hidden,
        mockHidden: camera.querySelector('.lui-simulator-camera-mock').hidden,
        status: camera.querySelector('[role="status"]').textContent,
        action: camera.querySelector('button').textContent.trim(),
        platform: camera.closest('[data-lui-platform]')?.getAttribute('data-lui-platform'),
      }
    })()`),
    {
      sameCamera: true,
      sameVideo: true,
      state: "live",
      constraints: { audio: false, video: { facingMode: { ideal: "environment" } } },
      sameStream: true,
      hidden: false,
      mockHidden: true,
      status: "Using browser camera",
      action: "Use simulator camera",
      platform: "android",
    },
  )

  await browser("click", ".lui-simulator-camera button")

  assert.deepEqual(
    await state(`(() => {
      const camera = document.querySelector('.lui-simulator-camera')
      const video = camera.querySelector('video')
      return {
        state: camera.dataset.cameraState,
        stopped: window.__luiCameraTrackStopped,
        streamCleared: video.srcObject === null,
        hidden: video.hidden,
        mockHidden: camera.querySelector('.lui-simulator-camera-mock').hidden,
        status: camera.querySelector('[role="status"]').textContent,
      }
    })()`),
    {
      state: "mock",
      stopped: true,
      streamCleared: true,
      hidden: true,
      mockHidden: false,
      status: "Using deterministic simulator camera",
    },
  )
})

test("Camera extension exposes denied permission without losing its deterministic fallback", async () => {
  await openGallery()
  await openGalleryPage("NativeExtension")
  assert.equal(
    await state("Boolean(document.querySelector('.lui-simulator-camera'))"),
    true,
    "the retained Camera extension must exist before permission is requested",
  )
  await evaluate(`(() => {
    Object.defineProperty(navigator, 'mediaDevices', {
      configurable: true,
      value: {
        getUserMedia: async () => {
          throw new DOMException('Camera access was denied', 'NotAllowedError')
        },
      },
    })
  })()`)
  await browser("click", ".lui-simulator-camera button")
  await browser("wait", "--fn", "document.querySelector('.lui-simulator-camera')?.dataset.cameraState === 'denied'")

  assert.deepEqual(
    await state(`(() => {
      const camera = document.querySelector('.lui-simulator-camera')
      return {
        state: camera.dataset.cameraState,
        alert: camera.querySelector('[role="alert"]')?.textContent,
        status: camera.querySelector('[role="status"]')?.textContent,
        action: camera.querySelector('button').textContent.trim(),
        mockHidden: camera.querySelector('.lui-simulator-camera-mock').hidden,
      }
    })()`),
    {
      state: "denied",
      alert: "Camera permission denied. The simulator camera remains available.",
      status: "Using deterministic simulator camera",
      action: "Use browser camera",
      mockHidden: false,
    },
  )
})
