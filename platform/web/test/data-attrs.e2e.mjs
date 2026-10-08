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

test("data-attrs lands allowed attributes on the node's root element", async () => {
  await page.goto(`${origin}/platform/web/test/fixtures/data-attrs-regression.html`)
  const tracked = page.locator(`#lui-node-${await page.evaluate(() => window.probe.tracked)}`)
  assert.deepEqual(await tracked.evaluate((el) => ({
    testid: el.getAttribute("data-testid"),
    role: el.getAttribute("role"),
    tabindex: el.getAttribute("tabindex"),
    ariaLabel: el.getAttribute("aria-label"),
    draggable: el.getAttribute("draggable"),
    id: el.getAttribute("id"),
  })), {
    testid: "greeting", role: "note", tabindex: "0",
    ariaLabel: "greeting text", draggable: "true",
    id: `lui-node-${await page.evaluate(() => window.probe.tracked)}`,
  })
  // selectors and e2e locators contract on the emitted attributes
  assert.equal(await page.locator("[data-testid='greeting']").count(), 1)
  assert.equal(await page.locator("[role='note']").count(), 1)
  assert.equal(await tracked.evaluate((el) =>
    el.closest("[data-testid]") === el && el.closest("[role=note]") === el), true)
})

test("data-attrs updates drop disappeared attributes", async () => {
  await page.goto(`${origin}/platform/web/test/fixtures/data-attrs-regression.html`)
  await page.evaluate(() => {
    window.probe.set(window.probe.tracked, "data-attrs",
      window.probe.attrs([["data-testid", "renamed"], ["tabindex", "-1"]]))
  })
  const tracked = page.locator(`#lui-node-${await page.evaluate(() => window.probe.tracked)}`)
  assert.deepEqual(await tracked.evaluate((el) => ({
    testid: el.getAttribute("data-testid"),
    role: el.getAttribute("role"),
    tabindex: el.getAttribute("tabindex"),
    ariaLabel: el.getAttribute("aria-label"),
    draggable: el.getAttribute("draggable"),
  })), {
    testid: "renamed", role: null, tabindex: "-1",
    ariaLabel: null, draggable: null,
  })
})

test("removing data-attrs clears every managed attribute", async () => {
  await page.goto(`${origin}/platform/web/test/fixtures/data-attrs-regression.html`)
  await page.evaluate(() => {
    window.probe.unset(window.probe.tracked, "data-attrs")
  })
  const tracked = page.locator(`#lui-node-${await page.evaluate(() => window.probe.tracked)}`)
  assert.deepEqual(await tracked.evaluate((el) => ({
    testid: el.getAttribute("data-testid"),
    role: el.getAttribute("role"),
    tabindex: el.getAttribute("tabindex"),
    ariaLabel: el.getAttribute("aria-label"),
    draggable: el.getAttribute("draggable"),
    id: el.getAttribute("id"),
  })), {
    testid: null, role: null, tabindex: null,
    ariaLabel: null, draggable: null,
    id: `lui-node-${await page.evaluate(() => window.probe.tracked)}`,
  })
})

test("data-attrs rejects invalid names and control characters", async () => {
  await page.goto(`${origin}/platform/web/test/fixtures/data-attrs-regression.html`)
  const failures = await page.evaluate(() => {
    const attempts = [
      ["id", "x"], ["class", "fancy"], ["onclick", "boom"],
      ["data-x", "a\x1fb"],
    ]
    return attempts.map(([name, value]) => {
      try {
        window.probe.set(window.probe.tracked, "data-attrs",
          window.probe.attrs([[name, value]]))
        return null
      } catch (error) {
        return String(error)
      }
    })
  })
  assert.deepEqual(failures.map((message) => message !== null), [true, true, true, true])
  // rejected payloads leave the previously emitted attributes untouched
  const tracked = page.locator(`#lui-node-${await page.evaluate(() => window.probe.tracked)}`)
  assert.equal(await tracked.getAttribute("data-testid"), "greeting")
})

test("data-attrs applies, updates and removes inline style declarations", async () => {
  await page.goto(`${origin}/platform/web/test/fixtures/data-attrs-regression.html`)
  const tracked = page.locator(`#lui-node-${await page.evaluate(() => window.probe.tracked)}`)
  await page.evaluate(() => {
    window.probe.set(window.probe.tracked, "data-attrs",
      window.probe.attrs([["style", "--probe-color: tomato; overflow-anchor: none"]]))
  })
  assert.deepEqual(await tracked.evaluate((el) => ({
    color: el.style.getPropertyValue("--probe-color"),
    anchor: el.style.getPropertyValue("overflow-anchor"),
  })), { color: "tomato", anchor: "none" })

  await page.evaluate(() => {
    window.probe.set(window.probe.tracked, "data-attrs",
      window.probe.attrs([["style", "--probe-color: teal"]]))
  })
  assert.deepEqual(await tracked.evaluate((el) => ({
    color: el.style.getPropertyValue("--probe-color"),
    anchor: el.style.getPropertyValue("overflow-anchor"),
  })), { color: "teal", anchor: "" })

  await page.evaluate(() => window.probe.unset(window.probe.tracked, "data-attrs"))
  assert.equal(await tracked.getAttribute("style"), null)
})

test("empty data-attrs style updates remove the empty attribute", async () => {
  await page.goto(`${origin}/platform/web/test/fixtures/data-attrs-regression.html`)
  const tracked = page.locator(`#lui-node-${await page.evaluate(() => window.probe.tracked)}`)
  for (const replacement of [[["style", ""]], [["data-testid", "updated"]]]) {
    await page.evaluate((replacement) => {
      const { tracked, set, attrs } = window.probe
      set(tracked, "data-attrs", attrs([["style", "--probe-color: teal"]]))
      set(tracked, "data-attrs", attrs(replacement))
    }, replacement)
    assert.equal(await tracked.getAttribute("style"), null)
  }
})

test("removing user style restores retained layout styles", async () => {
  await page.goto(`${origin}/platform/web/test/fixtures/data-attrs-regression.html`)
  const tracked = page.locator(`#lui-node-${await page.evaluate(() => window.probe.tracked)}`)
  await page.evaluate(() => {
    const { tracked, set, attrs } = window.probe
    set(tracked, "width", 120)
    set(tracked, "data-attrs", attrs([["style", "width: 64px; --probe-color: teal"]]))
  })
  assert.equal(await tracked.evaluate((el) => el.style.width), "64px")
  await page.evaluate(() => window.probe.unset(window.probe.tracked, "data-attrs"))
  assert.deepEqual(await tracked.evaluate((el) => ({
    width: el.style.width,
    color: el.style.getPropertyValue("--probe-color"),
    hasStyle: el.hasAttribute("style"),
  })), { width: "120px", color: "", hasStyle: true })
})

test("as emits the override tag on create", async () => {
  await page.goto(`${origin}/platform/web/test/fixtures/data-attrs-regression.html`)
  const tags = await page.evaluate(() => {
    const { heading, inline, para, lbl } = window.probe
    return {
      heading: window.probe.node(heading).tagName,
      inline: window.probe.node(inline).tagName,
      para: window.probe.node(para).tagName,
      lbl: window.probe.node(lbl).tagName,
      nestedParent: window.probe.node(inline).children.length === 1
        && window.probe.node(inline).firstElementChild.textContent === "child",
    }
  })
  assert.deepEqual(tags, {
    heading: "H3", inline: "MARK", para: "DIV", lbl: "LABEL",
    nestedParent: true,
  })
  // heading keeps its semantics class so existing styling still applies
  const heading = page.locator(`#lui-node-${await page.evaluate(() => window.probe.heading)}`)
  assert.equal(await heading.evaluate((el) => el.classList.contains("lui-heading")), true)
})

test("as retags mid-life, preserving identity, attributes, and children", async () => {
  await page.goto(`${origin}/platform/web/test/fixtures/data-attrs-regression.html`)
  const before = await page.evaluate(() => ({
    tag: window.probe.node(window.probe.inline).tagName,
    childText: window.probe.node(window.probe.inline).firstElementChild.textContent,
  }))
  assert.deepEqual(before, { tag: "MARK", childText: "child" })
  await page.evaluate(() => {
    window.probe.set(window.probe.inline, "as", "strong")
  })
  const after = await page.evaluate(() => {
    const el = document.getElementById(`lui-node-${window.probe.inline}`)
    return {
      tag: el.tagName,
      id: el.getAttribute("id"),
      className: el.className,
      childText: el.firstElementChild.textContent,
      connected: el.isConnected,
    }
  })
  assert.deepEqual(after, {
    tag: "STRONG", id: `lui-node-${await page.evaluate(() => window.probe.inline)}`,
    className: "lui-text", childText: "child", connected: true,
  })
})

test("removing as restores the kind's default tag", async () => {
  await page.goto(`${origin}/platform/web/test/fixtures/data-attrs-regression.html`)
  await page.evaluate(() => {
    window.probe.unset(window.probe.inline, "as")
  })
  const tag = await page.evaluate(() =>
    document.getElementById(`lui-node-${window.probe.inline}`).tagName)
  assert.equal(tag, "SPAN")
})

test("as rejects a tag outside the kind's vocabulary", async () => {
  await page.goto(`${origin}/platform/web/test/fixtures/data-attrs-regression.html`)
  const rejected = await page.evaluate(() => {
    try {
      window.probe.set(window.probe.inline, "as", "div")
      return null
    } catch (error) {
      return String(error)
    }
  })
  assert.notEqual(rejected, null)
  const tag = await page.evaluate(() =>
    document.getElementById(`lui-node-${window.probe.inline}`).tagName)
  assert.equal(tag, "MARK")
})
