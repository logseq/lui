import assert from "node:assert/strict"
import { once } from "node:events"
import test from "node:test"

import { firefox, webkit } from "playwright"

import { createStaticServer } from "../../../tooling/serve_web.mjs"

const browserName = process.env.LUI_WEB_BROWSER ?? "firefox"
const browserType = { firefox, webkit }[browserName]
const browserLabel = { firefox: "Firefox", webkit: "WebKit" }[browserName]

if (!browserType) {
  throw new Error(`unsupported LUI_WEB_BROWSER: ${browserName}`)
}

async function openGalleryPage(page, name) {
  await page.evaluate((pageName) => {
    const button = [...document.querySelectorAll("nav button")]
      .find((node) => node.textContent === pageName)
    button?.click()
  }, name)
}

test(`${browserLabel} preserves the Gallery's retained interaction contract`, async () => {
  const server = createStaticServer(new URL("../../../", import.meta.url).pathname)
  server.listen(0, "127.0.0.1")
  await once(server, "listening")

  let browser
  let page
  const pageErrors = []

  try {
    browser = await browserType.launch()
    page = await browser.newPage({ viewport: { width: 390, height: 844 } })
    page.on("pageerror", (error) => pageErrors.push(error.message))

    const origin = `http://127.0.0.1:${server.address().port}`
    await page.goto(`${origin}/examples/components/web/index.html`)

    const mobileAudit = await page.evaluate(() => {
      const content = document.querySelector(".lui-gallery-content")
      const buttons = [...document.querySelectorAll(".lui-gallery-nav-item")]
      document.querySelector(".lui-gallery-navigation-back:not([hidden])")?.click()
      const navigationHeights = []
      const failures = []
      for (const button of buttons) {
        navigationHeights.push(button.getBoundingClientRect().height)
        button.click()
        const headings = content.querySelectorAll('[role="heading"]')
        if (headings.length !== 1 || content.scrollWidth > content.clientWidth + 1) {
          failures.push({
            page: button.textContent,
            headings: headings.length,
            clientWidth: content.clientWidth,
            scrollWidth: content.scrollWidth,
          })
        }
        document.querySelector(".lui-gallery-navigation-back")?.click()
      }
      return {
        count: buttons.length,
        minNavigationHeight: Math.min(...navigationHeights),
        mountedPages: document.querySelectorAll(".lui-gallery-content > *").length,
        failures,
      }
    })
    assert.equal(mobileAudit.count, 66)
    assert.ok(mobileAudit.minNavigationHeight >= 44, JSON.stringify(mobileAudit))
    assert.equal(mobileAudit.mountedPages, 1)
    assert.deepEqual(mobileAudit.failures, [])

    await openGalleryPage(page, "Dialog")
    await page.evaluate(() => {
      window.__luiCompatDialogTrigger = [...document.querySelectorAll("button")]
        .find((button) => button.textContent.trim() === "Open dialog")
    })
    await page.getByRole("button", { name: "Open dialog", exact: true }).click()
    const dialogState = await page.evaluate(() => {
      const layer = document.querySelector(".lui-modal-layer[data-open]")
      const surface = layer?.querySelector('[role="dialog"]')
      return {
        portaled: layer?.parentElement?.classList.contains("lui-popup-portal"),
        modal: surface?.getAttribute("aria-modal"),
        hostInert: document.querySelector("#app")?.hasAttribute("inert"),
        focus: document.activeElement?.getAttribute("placeholder"),
      }
    })
    assert.deepEqual(dialogState, {
      portaled: true,
      modal: "true",
      hostInert: true,
      focus: "Note name",
    })
    await page.keyboard.press("Escape")
    await page.waitForFunction(() => !document.querySelector(".lui-modal-layer"))
    assert.deepEqual(
      await page.evaluate(() => ({
        tag: document.activeElement?.tagName,
        text: document.activeElement?.textContent?.trim(),
        sameTrigger: document.activeElement === window.__luiCompatDialogTrigger,
        triggerConnected: window.__luiCompatDialogTrigger?.isConnected,
        hostInert: document.querySelector("#app")?.hasAttribute("inert"),
      })),
      {
        tag: "BUTTON",
        text: "Open dialog",
        sameTrigger: true,
        triggerConnected: true,
        hostInert: false,
      },
    )

    await openGalleryPage(page, "Tree")
    await page.locator('[role="treeitem"]').first().focus()
    await page.keyboard.press("ArrowRight")
    await page.keyboard.press("ArrowRight")
    assert.equal(
      await page.evaluate(() => document.activeElement?.textContent?.trim()),
      "Quarterly report.md",
    )
    await page.keyboard.press("ArrowDown")
    assert.equal(
      await page.evaluate(() => document.activeElement?.textContent?.trim()),
      "Launch checklist.md",
    )

    await openGalleryPage(page, "DropdownMenu")
    const production = page.locator(".lui-menu-item:visible")
      .filter({ hasText: /^Production$/ })
      .last()
    await production.focus()
    await page.keyboard.press("s")
    assert.equal(
      await page.evaluate(() => document.activeElement?.textContent?.trim()),
      "Staging",
    )

    await openGalleryPage(page, "Sheet")
    await page.getByRole("button", { name: "Open sheet", exact: true }).click()
    const compositionState = await page.evaluate(() => {
      const input = document.querySelector('.lui-sheet input[placeholder="Share link"]')
      input.focus()
      input.dispatchEvent(new CompositionEvent("compositionstart", {
        bubbles: true,
        data: "",
      }))
      input.value = "中"
      input.dispatchEvent(new InputEvent("input", {
        bubbles: true,
        data: "中",
        inputType: "insertCompositionText",
        isComposing: true,
      }))
      input.value = "中文"
      input.dispatchEvent(new CompositionEvent("compositionend", {
        bubbles: true,
        data: "中文",
      }))
      input.dispatchEvent(new InputEvent("input", {
        bubbles: true,
        data: "中文",
        inputType: "insertFromComposition",
        isComposing: false,
      }))
      return {
        retained: document.querySelector('.lui-sheet input[placeholder="Share link"]') === input,
        focused: document.activeElement === input,
        value: input.value,
      }
    })
    assert.deepEqual(compositionState, {
      retained: true,
      focused: true,
      value: "中文",
    })
    assert.deepEqual(pageErrors, [])
  } finally {
    await page?.close()
    await browser?.close()
    server.close()
    await once(server, "close")
  }
})
