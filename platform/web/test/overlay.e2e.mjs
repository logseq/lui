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
      }
    })()`),
    { layers: 1, modal: "true", className: "lui-dialog", hostInert: true, focusInside: true },
  )

  await browser("press", "Escape")
  assert.deepEqual(
    await state(`({
      layers: document.querySelectorAll('.lui-modal-layer:not([hidden])').length,
      hostInert: document.querySelector('#app')?.hasAttribute('inert'),
      focus: document.activeElement?.textContent?.trim(),
    })`),
    { layers: 0, hostInert: false, focus: "Open dialog" },
  )

  await clickButton("Open dialog")
  await evaluate(`document.querySelector('.lui-modal-backdrop')?.click()`)
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
      }
    })()`),
    { layers: 1, className: "lui-sheet", modal: "true", hostInert: true },
  )

  await browser("press", "Escape")
  assert.equal(
    await state(`document.querySelectorAll('.lui-modal-layer:not([hidden])').length`),
    0,
  )
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
          { label: "Redo", tabIndex: -1, disabled: true },
          { label: "More", tabIndex: -1, disabled: false },
        ],
      },
      {
        label: "Insert",
        orientation: "vertical",
        controls: [
          { label: "Link", tabIndex: 0, disabled: false },
          { label: "Image", tabIndex: -1, disabled: false },
        ],
      },
    ],
  )

  await evaluate(`document.querySelector('[aria-label="Formatting"] button')?.focus()`)
  await browser("press", "ArrowRight")
  assert.equal(await state(`document.activeElement?.textContent.trim()`), "Italic")
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

test("Toast portals stable updates and supports pause, F6, close, and swipe dismissal", async () => {
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
    const event = (name, x) => new MouseEvent(name, {
      bubbles: true,
      clientX: x,
      clientY: 20,
    })
    toast.dispatchEvent(event('mousedown', 20))
    toast.dispatchEvent(event('mousemove', 180))
    toast.dispatchEvent(event('mouseup', 180))
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

  await browser("hover", 'button[aria-label="Edit document"]')
  assert.equal(await state(`document.querySelector('.lui-tooltip[data-anchor]')?.hasAttribute('data-open')`), false)
  await browser("wait", "300")
  assert.equal(await state(`document.querySelector('.lui-tooltip[data-anchor]')?.hasAttribute('data-open')`), true)

  await browser("hover", '[role="heading"]')
  await browser("wait", "80")
  assert.equal(await state(`document.querySelector('.lui-tooltip[data-anchor]')?.hasAttribute('data-open')`), false)
  await browser("hover", 'button[aria-label="Edit document"]')
  await browser("wait", "20")
  assert.equal(await state(`document.querySelector('.lui-tooltip[data-anchor]')?.hasAttribute('data-open')`), true)

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
