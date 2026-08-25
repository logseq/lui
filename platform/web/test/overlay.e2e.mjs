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
