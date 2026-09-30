import { chromium } from "playwright"

export async function createPlaywrightSession() {
  const cdpEndpoint = process.env.LUI_WEB_CDP_ENDPOINT
  const browser = cdpEndpoint
    ? await chromium.connectOverCDP(cdpEndpoint)
    : await chromium.launch({ headless: true })
  const page = await browser.newPage({ viewport: { width: 1280, height: 900 } })
  let closed = false

  async function close() {
    if (closed) return
    closed = true
    if (cdpEndpoint) await page.close()
    else await browser.close()
  }

  async function command(...args) {
    const [commandName, ...values] = args
    if (commandName === "set") {
      if (values[0] === "viewport") {
        await page.setViewportSize({
          width: Number(values[1]),
          height: Number(values[2]),
        })
      } else if (values[0] === "media") {
        await page.emulateMedia({
          colorScheme: values[1] === "dark" ? "dark" : "light",
          reducedMotion: values[2] === "reduced-motion" ? "reduce" : "no-preference",
        })
      }
    } else if (commandName === "open") {
      await page.goto(values[0], { waitUntil: "networkidle" })
    } else if (commandName === "wait") {
      if (values[0] === "--load") {
        await page.waitForLoadState(values[1] ?? "load")
      } else if (values[0] === "--fn") {
        await page.waitForFunction(values[1], null, { timeout: 5000 })
      } else {
        await page.waitForTimeout(Number(values[0]))
      }
    } else if (commandName === "press") {
      await page.keyboard.press(values[0])
    } else if (commandName === "hover") {
      await page.locator(values[0]).first().hover()
    } else if (commandName === "click") {
      await page.locator(`${values[0]}:visible`).first().click()
    } else if (commandName === "click-text") {
      const [selector, text] = values
      await page.locator(`${selector}:visible`).filter({ hasText: text }).first().click()
    } else if (commandName === "click-button") {
      await page.getByRole("button", { name: values[0], exact: true }).first().click()
    } else if (commandName === "select") {
      await page.locator(values[0]).selectOption(values[1])
    } else if (commandName === "wheel") {
      const [selector, deltaY, offsetX, offsetY] = values
      const target = page.locator(`${selector}:visible`).first()
      const bounds = await target.boundingBox()
      if (!bounds) throw new Error(`Cannot scroll invisible target: ${selector}`)
      await page.mouse.move(
        bounds.x + (offsetX === undefined ? bounds.width / 2 : Number(offsetX)),
        bounds.y + (offsetY === undefined ? bounds.height / 2 : Number(offsetY)),
      )
      await page.mouse.wheel(0, Number(deltaY))
    } else if (commandName === "drag") {
      const [selector, startX, startY, endX, endY] = values
      const target = page.locator(`${selector}:visible`).first()
      const bounds = await target.boundingBox()
      if (!bounds) throw new Error(`Cannot drag invisible target: ${selector}`)
      await page.mouse.move(bounds.x + Number(startX), bounds.y + Number(startY))
      await page.mouse.down()
      await page.mouse.move(bounds.x + Number(endX), bounds.y + Number(endY), { steps: 4 })
      await page.mouse.up()
    } else if (commandName === "close") {
      await close()
    }
    return ""
  }

  async function evaluate(source) {
    const value = await page.evaluate(source)
    return JSON.stringify(value === undefined ? null : value)
  }

  return { command, evaluate, page, close }
}
