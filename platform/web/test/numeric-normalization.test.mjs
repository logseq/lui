import assert from 'node:assert/strict'
import test from 'node:test'

const build = process.env.LUI_TEST_BUILD_DIR ?? '_build'
const modules = new URL(`../../../${build}/default/examples/components/web/lui-components-web/node_modules/`, import.meta.url)
const [Store, Protocol, Schema] = await Promise.all([
  import(new URL('lui.web.dom/core/lui_web_store.js', modules)),
  import(new URL('lui/lui_protocol.js', modules)),
  import(new URL('lui/lui_wire_schema.js', modules)),
])
const list = values => values.reduceRight((tl, hd) => ({hd, tl}), 0)
const named = (values, nameOf, name) => {
  for (let rest = values; rest; rest = rest.tl) if (nameOf(rest.hd) === name) return rest.hd
  throw new Error(`Unknown schema value: ${name}`)
}
const prop = name => named(Schema.all_properties, Schema.property_name, name)
const kind = name => named(Schema.all_node_kinds, Schema.node_kind_name, name)

test('numeric values normalize before final size validation', () => {
  const store = Store.create_store()
  const set = (name, value, tag = 2) => Protocol.set_prop_op(1, prop(name), {TAG: tag, _0: value})
  Store.apply_batch(store, () => ({}), {generation: 1, ops: list([
    Protocol.create_node_op(1, kind('box')), set('width', 10),
    set('min-width', 100), set('max-width', 50), set('height', -4),
    set('padding', -2), set('opacity', Number.NaN, 3),
  ])})
  const value = name => Store.property(store, 1, prop(name))._0
  assert.equal(value('width'), 100)
  assert.equal(value('max-width'), 100)
  assert.equal(value('height'), 0)
  assert.equal(value('padding'), 0)
  assert.equal(value('opacity'), 1)
  Store.apply_batch(store, () => ({}), {generation: 2, ops: list([set('opacity', -0.5, 3)])})
  assert.equal(value('opacity'), 0)
})
