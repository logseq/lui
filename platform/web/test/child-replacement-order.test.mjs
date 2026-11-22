import assert from 'node:assert/strict'
import {once} from 'node:events'
import test from 'node:test'
import {createStaticServer} from '../../../tooling/serve_web.mjs'
import {createPlaywrightSession} from './playwright-session.mjs'

test('replacing keyed siblings preserves the rendered position of a surviving row', async () => {
  const server = createStaticServer(new URL('../../../', import.meta.url).pathname)
  server.listen(0, '127.0.0.1')
  await once(server, 'listening')
  const session = await createPlaywrightSession()
  try {
    await session.page.goto(`http://127.0.0.1:${server.address().port}/platform/web/test/fixtures/point-menu-regression.html`)
    const result = await session.page.evaluate(async () => {
      const Web = await import('lui.web.dom/shell/lui_web.js')
      const {Protocol, properties, kinds} = await import('./protocol-fixture.mjs')
      const host = document.createElement('div')
      document.body.append(host)
      const renderer = Web.create(undefined, undefined, host)
      const backend = Web.backend(renderer)
      const list = values => values.reduceRight((tl, hd) => ({hd, tl}), 0)
      let generation = 0
      const apply = ops => backend.apply_batch({generation: ++generation, ops: list(ops)})
      const create = (id, text) => [Protocol.create_node_op(id, kinds.get('text')),
        Protocol.set_prop_op(id, properties.get('text'), {TAG: 0, _0: text})]
      const order = () => [...host.firstElementChild.children].map(child => child.textContent)
      apply([Protocol.create_node_op(1, kinds.get('column')),
        ...create(2, 'Exact result'), Protocol.insert_child_op(1, 2, 0),
        ...create(4, 'Old result'), Protocol.insert_child_op(1, 4, 1)])
      Web.mount(renderer, 1, host)
      const exact = order()
      apply([...create(3, 'Create'), Protocol.insert_child_op(1, 3, 1)])
      const inserted = order()
      const kept = host.firstElementChild.children[1]
      apply([...create(5, 'Source Two'), Protocol.insert_child_op(1, 5, 3),
        ...create(6, 'Source One'), Protocol.insert_child_op(1, 6, 4),
        Protocol.remove_child_op(1, 2), Protocol.detach_subtree_op(2),
        Protocol.remove_child_op(1, 4), Protocol.detach_subtree_op(4),
        Protocol.move_child_op(1, 5, 0)])
      const replaced = order()
      const same = host.firstElementChild.children[1] === kept
      apply([Protocol.remove_child_op(1, 5), Protocol.detach_subtree_op(5),
        Protocol.remove_child_op(1, 6), Protocol.detach_subtree_op(6)])
      const empty = order()
      let rejected = false
      try { apply([Protocol.move_child_op(1, 3, 99)]) } catch { rejected = true }
      return {exact, inserted, replaced, same, empty, rejected, afterError: order()}
    })
    assert.deepEqual(result.exact, ['Exact result', 'Old result'])
    assert.deepEqual(result.inserted, ['Exact result', 'Create', 'Old result'])
    assert.deepEqual(result.replaced, ['Source Two', 'Create', 'Source One'])
    assert.equal(result.same, true)
    assert.deepEqual(result.empty, ['Create'])
    assert.equal(result.rejected, true)
    assert.deepEqual(result.afterError, ['Create'])
  } finally {
    await session.close()
    await new Promise(resolve => server.close(resolve))
  }
})
