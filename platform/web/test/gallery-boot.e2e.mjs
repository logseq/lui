import assert from "node:assert/strict"
import { once } from "node:events"
import test from "node:test"

import { createStaticServer } from "../../../tooling/serve_web.mjs"
import { createPlaywrightSession } from "./playwright-session.mjs"

test("actual Gallery boots, navigates, and retains its native event targets", async () => {
  const server = createStaticServer(new URL("../../../", import.meta.url).pathname)
  server.listen(0, "127.0.0.1")
  await once(server, "listening")
  let session
  try {
    session = await createPlaywrightSession()
    const { page } = session
    const errors = []
    page.on("pageerror", error => errors.push(error.message))
    const origin = `http://127.0.0.1:${server.address().port}`
    await page.goto(`${origin}/examples/components/web/index.html`)
    await page.waitForFunction(() => document.querySelector("#app[data-error]")
      || document.querySelector(".lui-gallery-nav-item"))
    assert.equal(await page.locator("#app").getAttribute("data-error"), null,
      await page.locator("#app").innerText())

    for (const name of ["Dialog", "DropdownMenu", "Tree", "Event payloads"]) {
      await session.command("click-text", ".lui-gallery-nav-item", name)
      await page.getByRole("heading", { name, exact: true }).waitFor({ state: "visible" })
    }
    assert.equal(await page.locator("#events-picker").count(), 1)
    const status = page.locator("#events-status")
    const before = await status.textContent()
    await page.getByRole("button", { name: "Inspect event", exact: true }).click()
    await page.waitForFunction(before => document.querySelector("#events-status")?.textContent !== before, before)
    assert.deepEqual(errors, [])
  } finally {
    await session?.close()
    const closed = once(server, "close")
    server.close()
    await closed
  }
})
