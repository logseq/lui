import assert from 'node:assert/strict'
import {once} from 'node:events'
import test, {before, after} from 'node:test'
import {createStaticServer} from '../../../tooling/serve_web.mjs'
import {createPlaywrightSession} from './playwright-session.mjs'

let server, session, page, origin
let pageErrors = []
before(async () => {
  session = await createPlaywrightSession()
  page = session.page
  page.on('pageerror', error => pageErrors.push(error.message))
  page.setDefaultTimeout(5000)
  server = createStaticServer(new URL('../../../', import.meta.url).pathname)
  server.listen(0, '127.0.0.1')
  await once(server, 'listening')
  origin = `http://127.0.0.1:${server.address().port}`
})
after(async () => {
  await session?.close()
  if (server?.listening) {
    const closed = once(server, 'close')
    server.close()
    await closed
  }
})

async function open() {
  pageErrors = []
  await page.goto(`${origin}/platform/web/test/fixtures/editor-virtual-tuning.html`)
  try {
    await page.waitForFunction(() => window.probe || window.fixtureError)
  } catch (error) {
    throw new Error(pageErrors.join('\n') || error.message)
  }
  assert.equal(await page.evaluate(() => window.fixtureError), undefined)
}

const editors = ['text-field', 'secure-field', 'input', 'search-field', 'textarea', 'combobox']
for (const kind of editors) {
  test(`${kind}: readonly retains focus/navigation, blocks typing and restores editing`, async () => {
    await open()
    const control = await page.locator(`#${kind}`).evaluateHandle(node =>
      node.matches('input,textarea') ? node : node.querySelector('input,textarea'))
    assert.equal(await control.evaluate(node => node.readOnly), true)
    await control.evaluate(node => {node.focus(); node.setSelectionRange(1, 4)})
    await page.keyboard.type('mutated')
    await page.keyboard.press('Backspace')
    assert.equal(await control.evaluate(node => node.value), 'preserved')
    assert.equal(await control.evaluate(node => document.activeElement === node), true)
    if (kind !== 'secure-field') {
      assert.deepEqual(await control.evaluate(node => [node.selectionStart, node.selectionEnd]), [1, 4])
    }
    if (kind !== 'combobox') {
      const before = await page.evaluate(() => window.probe.events.length)
      await page.keyboard.press('ArrowDown')
      assert.ok(await page.evaluate(before => window.probe.events.length > before, before))
    }
    const id = await page.evaluate(kind => window.probe.editors[kind], kind)
    await page.evaluate(id => window.probe.remove(id, 'read-only'), id)
    assert.equal(await control.evaluate(node => node.readOnly), false)
    assert.equal(await control.evaluate(node => document.activeElement === node), true)
    await page.keyboard.type('x')
    assert.notEqual(await control.evaluate(node => node.value), 'preserved')
    await control.dispose()
  })
}

test('virtual tuning uses typed values before legacy attributes and restores fallback on removal', async () => {
  await open()
  const root = page.locator('.lui-virtual-list')
  const waitHeight = (minimum, maximum = minimum) => page.waitForFunction(({minimum, maximum}) => {
    const height = Number.parseFloat(document.querySelector('.lui-virtual-list').firstElementChild.style.height)
    return height >= minimum && height <= maximum
  }, {minimum, maximum})
  const mountedRows = () => root.locator('[id^="row-"]').count()

  await waitHeight(4000)
  await page.evaluate(() => window.probe.set(window.probe.virtual, 'item-extent', 24.5))
  await waitHeight(2450, 2999)
  await page.evaluate(() => window.probe.set(window.probe.virtual, 'overscan', 0))
  const tight = await mountedRows()
  await page.evaluate(() => window.probe.set(window.probe.virtual, 'overscan', 8))
  await page.waitForFunction(tight =>
    document.querySelectorAll('.lui-virtual-list [id^="row-"]').length > tight, tight)

  await page.evaluate(() => {
    window.probe.remove(window.probe.virtual, 'item-extent')
    window.probe.remove(window.probe.virtual, 'overscan')
  })
  await waitHeight(4000)
  await page.evaluate(() => window.probe.remove(window.probe.virtual, 'data-attrs'))
  await waitHeight(3200, 3499)
})
