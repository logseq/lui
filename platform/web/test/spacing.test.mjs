import assert from 'node:assert/strict'
import test from 'node:test'

const build = process.env.LUI_TEST_BUILD_DIR ?? '_build'
const modules = new URL(`../../../${build}/default/examples/components/web/lui-components-web/node_modules/`, import.meta.url)
const [Store, Protocol, Schema, Props] = await Promise.all([
  import(new URL('lui.web.dom/core/lui_web_store.js', modules)),
  import(new URL('lui/lui_protocol.js', modules)),
  import(new URL('lui/lui_wire_schema.js', modules)),
  import(new URL('lui.web.dom/render/lui_web_props.js', modules)),
])
const list = items => items.reduceRight((tl, hd) => ({hd, tl}), 0)
const named = (values, nameOf, name) => {
  for (let rest = values; rest; rest = rest.tl) if (nameOf(rest.hd) === name) return rest.hd
  throw new Error(`Unknown schema value: ${name}`)
}
const property = name => named(Schema.all_properties, Schema.property_name, name)
const kind = named(Schema.all_node_kinds, Schema.node_kind_name, 'column')

function fixture() {
  const store = Store.create_store()
  const styles = new Map()
  const element = {style: {setProperty(name, value) {
    styles.set(name, value)
    for (const prefix of ['padding', 'margin']) {
      const sides = name === prefix ? ['top', 'right', 'bottom', 'left']
        : name === `${prefix}-inline` ? ['left', 'right']
        : name === `${prefix}-block` ? ['top', 'bottom'] : []
      for (const side of sides) styles.set(`${prefix}-${side}`, value)
    }
  }}}
  const renderer = {web_store: store}
  let generation = 0
  const apply = ops => Store.apply_batch(store, () => element, {generation: ++generation, ops: list(ops)})
  apply([Protocol.create_node_op(1, kind)])
  return {
    styles,
    set(name, number) {
      const prop = property(name), value = {TAG: 2, _0: number}
      apply([Protocol.set_prop_op(1, prop, value)])
      Props.apply_property(renderer, () => {}, 1, kind, element, prop, value)
    },
    remove(name) {
      const prop = property(name)
      apply([Protocol.remove_prop_op(1, prop)])
      Props.remove_property(renderer, () => {}, 1, kind, element, prop)
    },
    edges(prefix) {
      return ['top', 'right', 'bottom', 'left'].map(side => styles.get(`${prefix}-${side}`))
    },
  }
}

for (const prefix of ['padding', 'margin']) {
  test(`${prefix} side and axis overrides are independent of application order`, () => {
    const declarations = [[prefix, 4], [`${prefix}-horizontal`, 8], [`${prefix}-left`, 12]]
    for (const order of [[0, 1, 2], [0, 2, 1], [1, 0, 2], [1, 2, 0], [2, 0, 1], [2, 1, 0]]) {
      const f = fixture()
      for (const index of order) f.set(...declarations[index])
      assert.deepEqual(f.edges(prefix), ['4px', '8px', '4px', '12px'], `Order ${order}`)
      f.set(prefix, 6)
      assert.deepEqual(f.edges(prefix), ['6px', '8px', '6px', '12px'])
      f.set(`${prefix}-vertical`, 10)
      f.set(`${prefix}-bottom`, 0)
      assert.deepEqual(f.edges(prefix), ['10px', '8px', '0px', '12px'])
      f.remove(`${prefix}-left`)
      f.remove(`${prefix}-bottom`)
      assert.deepEqual(f.edges(prefix), ['10px', '8px', '10px', '8px'])
      f.remove(`${prefix}-horizontal`)
      f.remove(`${prefix}-vertical`)
      assert.deepEqual(f.edges(prefix), ['6px', '6px', '6px', '6px'])
      f.remove(prefix)
      assert.deepEqual(f.edges(prefix), ['', '', '', ''])
    }
  })
}

test('negative margins retain their axis and side overrides when the base changes', () => {
  const f = fixture()
  f.set('margin-horizontal', -8)
  f.set('margin-top', -6)
  f.set('margin', 0)
  assert.deepEqual(f.edges('margin'), ['-6px', '-8px', '0px', '-8px'])
})
