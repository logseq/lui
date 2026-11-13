import assert from "node:assert/strict"
import { once } from "node:events"
import test from "node:test"

import { listenWs, run } from "../../../tooling/lui_agent.mjs"
import { createStaticServer } from "../../../tooling/serve_web.mjs"
import { createPlaywrightSession } from "./playwright-session.mjs"

// The shared agent protocol keeps this script host-agnostic.
const script = [
  "hello",
  "press prop:accessibility-identifier=events-button",
  'expect "text:Event: press"',
  'type prop:accessibility-identifier=events-editor "agent 你好"',
  'wait "text:Event: text-changed:agent 你好" 2',
  'expect-prop prop:accessibility-identifier=events-status text "Event: text-changed:agent 你好"',
  "find kind:checkbox",
]

test("the actual Gallery page dials tooling/lui_agent.mjs and runs a Drive-vocabulary script", async () => {
  const server = createStaticServer(new URL("../../../", import.meta.url).pathname)
  server.listen(0, "127.0.0.1")
  await once(server, "listening")
  let session
  let agent
  try {
    session = await createPlaywrightSession()
    const { page } = session
    const errors = []
    page.on("pageerror", error => errors.push(error.message))
    const origin = `http://127.0.0.1:${server.address().port}`
    agent = await listenWs(0, {
      timeout: 20_000,
      onListening: port => {
        page.goto(`${origin}/examples/components/web/index.html?lui-agent=ws://127.0.0.1:${port}`)
          .catch(error => errors.push(error.message))
      },
    })
    const hello = await agent.request({ op: "hello" })
    assert.equal(hello.host, "web")
    // Mounting the section reports appear into the same status text.
    await session.command("click-text", ".lui-gallery-nav-item", "Event payloads")
    await page.waitForFunction(() => document.querySelector("#events-status")?.textContent === "Event: appear")
    assert.deepEqual(await run(agent, script), [])
    await page.waitForFunction(() =>
      document.querySelector("#events-status")?.textContent === "Event: text-changed:agent 你好")
    assert.equal(await page.evaluate(() => JSON.parse(window.__luiAgent('{"op":"hello"}')).protocol), "lui-agent")
    const missing = await agent.request({ op: "press", selector: "text:no such node" })
    assert.equal(missing.ok, false)
    assert.deepEqual(errors, [])
  } finally {
    agent?.close()
    await session?.close()
    const closed = once(server, "close")
    server.close()
    await closed
  }
})
