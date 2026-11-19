import assert from 'node:assert/strict'
import {registerHooks} from 'node:module'
import test from 'node:test'

const build = process.env.LUI_TEST_BUILD_DIR ?? '_build'
const modules = new URL(`../../../${build}/default/examples/components/web/lui-components-web/node_modules/`, import.meta.url)
const resolution = registerHooks({resolve(specifier, context, nextResolve) {
  return nextResolve(specifier, specifier === '@tanstack/virtual-core'
    ? {...context, parentURL: import.meta.url} : context)
}})
const [Store, Protocol, Schema, Apply] = await Promise.all([
  import(new URL('lui.web.dom/core/lui_web_store.js', modules)),
  import(new URL('lui/lui_protocol.js', modules)),
  import(new URL('lui/lui_wire_schema.js', modules)),
  import(new URL('lui.web.dom/shell/lui_web_apply.js', modules)),
])
resolution.deregister()
const list = values => values.reduceRight((tl, hd) => ({hd, tl}), 0)
const named = (values, nameOf, name) => {
  for (let rest = values; rest; rest = rest.tl) if (nameOf(rest.hd) === name) return rest.hd
  throw new Error(`Unknown schema value: ${name}`)
}
const prop = name => named(Schema.all_properties, Schema.property_name, name)
const kind = name => named(Schema.all_node_kinds, Schema.node_kind_name, name)

test('pixel-size replay preserves absent dimensions owned by viewport properties', () => {
  const styles = new Map()
  const element = {style: {setProperty: (key, value) => styles.set(key, value)}}
  const store = Store.create_store(), renderer = {web_store: store}
  let generation = 0
  const apply = ops => {
    Store.apply_batch(store, () => element, {generation: ++generation, ops: list(ops)})
    for (const op of ops) Apply.apply_dom_op(renderer, () => undefined, () => list([]),
      Apply.new_effects(), () => true, op)
  }
  Store.apply_batch(store, () => element, {generation: ++generation,
    ops: list([Protocol.create_node_op(1, kind('box'))])})
  const set = (name, value, tag = 2) => Protocol.set_prop_op(1, prop(name), {TAG: tag, _0: value})
  for (const [name, cssName, expected] of [
    ['width-viewport', 'width', '50dvw'], ['height-viewport', 'height', '50dvh'],
    ['min-width-viewport', 'min-width', '50dvw'], ['max-width-viewport', 'max-width', '50dvw'],
    ['max-height-viewport', 'max-height', '50dvh'],
  ]) {
    apply([set(name, 0.5, 3)])
    assert.equal(styles.get(cssName), expected)
  }
  apply([set('min-height', 10)])
  assert.equal(styles.get('width'), '50dvw')
  assert.equal(styles.get('height'), '50dvh')
  assert.equal(styles.get('min-width'), '50dvw')
  assert.equal(styles.get('max-width'), '50dvw')
  assert.equal(styles.get('max-height'), '50dvh')
  assert.equal(styles.get('min-height'), '10px')
  apply([set('width', 10), set('min-width', 100), set('max-width', 50)])
  assert.equal(styles.get('width'), '100px')
  assert.equal(styles.get('min-width'), '100px')
  assert.equal(styles.get('max-width'), '100px')
  apply([Protocol.remove_prop_op(1, prop('min-height'))])
  assert.equal(styles.get('min-height'), '')
  assert.equal(styles.get('height'), '50dvh')
})

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
