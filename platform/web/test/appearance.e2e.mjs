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

test("typed appearance props land as styles and state channels", async () => {
  await page.goto(`${origin}/platform/web/test/fixtures/appearance-regression.html`)

  // Typography + text overflow on the text node.
  const typography = page.locator(`#lui-node-${await page.evaluate(() => window.probe.typography)}`)
  assert.deepEqual(await typography.evaluate((el) => {
    const style = getComputedStyle(el)
    return {
      fontSize: style.fontSize,
      fontWeight: style.fontWeight,
      lineHeight: style.lineHeight,
      letterSpacing: style.letterSpacing,
      whiteSpace: style.whiteSpace,
      textOverflow: style.textOverflow,
      userSelect: style.userSelect,
    }
  }), {
    fontSize: "12px", // 0.75rem at the 16px root
    fontWeight: "500",
    lineHeight: "20px", // 1.25rem
    letterSpacing: "-0.5px",
    whiteSpace: "nowrap",
    textOverflow: "ellipsis",
    userSelect: "none",
  })

  // Position, insets, z-index, overflow, cursor, viewport-relative sizing
  // on the box node.
  const positioned = page.locator(`#lui-node-${await page.evaluate(() => window.probe.positioned)}`)
  const positionedStyles = await positioned.evaluate((el) => {
    const style = getComputedStyle(el)
    return {
      position: style.position,
      top: style.top,
      right: style.right,
      bottom: style.bottom,
      left: style.left,
      zIndex: style.zIndex,
      overflow: style.overflow,
      cursor: style.cursor,
      width: style.width,
      maxHeight: style.maxHeight,
    }
  })
  assert.equal(positionedStyles.position, "absolute")
  assert.equal(positionedStyles.top, "4px") // inset-top overrides inset
  assert.equal(positionedStyles.right, "0px")
  assert.equal(positionedStyles.bottom, "0px")
  assert.equal(positionedStyles.left, "0px")
  assert.equal(positionedStyles.zIndex, "30")
  assert.equal(positionedStyles.overflow, "hidden")
  assert.equal(positionedStyles.cursor, "pointer")
  // width-viewport 0.5 and max-height-viewport 0.65 emit 50dvw/65dvh.
  assert.equal(positionedStyles.width, `${0.5 * 1280}px`)
  assert.equal(positionedStyles.maxHeight, `${0.65 * 720}px`)

  // `shadow` and the state channels land as --lui-* custom properties so
  // the zero-specificity state rules in lui.css can compose them.
  const interactive = page.locator(`#lui-node-${await page.evaluate(() => window.probe.interactive)}`)
  assert.deepEqual(await interactive.evaluate((el) => {
    const style = getComputedStyle(el)
    return {
      shadow: style.getPropertyValue("--lui-shadow").trim(),
      hoverBg: style.getPropertyValue("--lui-hover-bg").trim(),
      hoverOpacity: style.getPropertyValue("--lui-hover-opacity").trim(),
      hoverShadow: style.getPropertyValue("--lui-hover-shadow").trim(),
      pressedBg: style.getPropertyValue("--lui-pressed-bg").trim(),
      pressedOpacity: style.getPropertyValue("--lui-pressed-opacity").trim(),
      pressedShadow: style.getPropertyValue("--lui-pressed-shadow").trim(),
      focusShadow: style.getPropertyValue("--lui-focus-shadow").trim(),
      selectedBg: style.getPropertyValue("--lui-selected-bg").trim(),
      selectedShadow: style.getPropertyValue("--lui-selected-shadow").trim(),
      selectedHoverShadow: style.getPropertyValue("--lui-selected-hover-shadow").trim(),
      disabledOpacity: style.getPropertyValue("--lui-disabled-opacity").trim(),
      resolvedBoxShadow: style.boxShadow,
      resolvedOpacity: style.opacity,
    }
  }), {
    shadow: "0 1px 3px rgba(0,0,0,0.12)",
    hoverBg: "var(--color-accent)",
    hoverOpacity: "0.9",
    hoverShadow: "0 2px 4px rgba(0,0,0,0.2)",
    pressedBg: "var(--color-primary)",
    pressedOpacity: "0.8",
    pressedShadow: "inset 0 0 0 1px var(--color-primary)",
    focusShadow: "0 0 0 2px var(--color-ring)",
    selectedBg: "var(--color-accent)",
    selectedShadow: "inset 0 0 0 1px var(--color-accent)",
    selectedHoverShadow: "inset 0 0 0 2px var(--color-accent)",
    disabledOpacity: "0.5",
    // Not selected and not disabled — base channel paints `shadow`.
    resolvedBoxShadow: "rgba(0, 0, 0, 0.12) 0px 1px 3px",
    resolvedOpacity: "1",
  })

  // Hover paints the hover channels through the lui.css state rules.
  await interactive.hover()
  assert.deepEqual(await interactive.evaluate((el) => {
    const style = getComputedStyle(el)
    return {
      background: style.backgroundColor,
      shadow: style.boxShadow,
      opacity: style.opacity,
    }
  }), {
    background: "oklch(0.97 0 0)", // --color-accent, resolved through var()
    shadow: "rgba(0, 0, 0, 0.2) 0px 2px 4px",
    opacity: "0.9",
  })
})
