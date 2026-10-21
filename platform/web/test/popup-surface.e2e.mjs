import assert from 'node:assert/strict'
import { once } from 'node:events'
import test from 'node:test'
import { createStaticServer } from '../../../tooling/serve_web.mjs'
import { createPlaywrightSession } from './playwright-session.mjs'

test('popup surface styles retain geometry and collision bounds through updates and removal', async () => {
  const session = await createPlaywrightSession()
  const server = createStaticServer(new URL('../../../', import.meta.url).pathname)
  server.listen(0, '127.0.0.1')
  await once(server, 'listening')
  try {
    await session.page.goto(`http://127.0.0.1:${server.address().port}/platform/web/test/fixtures/popup-surface-regression.html`)
    await session.page.getByRole('button', { name: 'Run popup surface audit', exact: true }).click()
    await session.page.waitForFunction(() => document.querySelector('#result').textContent.startsWith('{'))
    const report = JSON.parse(await session.page.locator('#result').textContent())
    assert.equal(report.state, 'Complete')
    assert.equal(report.pass, true, JSON.stringify(report, null, 2))
  } finally {
    await session.close()
    const closed = once(server, 'close')
    server.close()
    await closed
  }
})
