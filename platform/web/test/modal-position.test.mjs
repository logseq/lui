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
const list = values => values.reduceRight((tl, hd) => ({hd, tl}), 0)
const named = (values, nameOf, name) => {
  for (let rest = values; rest; rest = rest.tl) if (nameOf(rest.hd) === name) return rest.hd
  throw new Error(`Unknown schema value: ${name}`)
}

test('modal layout can distinguish positioned children throughout updates and removal', () => {
  const kind = named(Schema.all_node_kinds, Schema.node_kind_name, 'box')
  const position = named(Schema.all_properties, Schema.property_name, 'position')
  const attributes = new Map(), styles = new Map()
  const element = {
    style: {setProperty: (name, value) => styles.set(name, value)},
    setAttribute: (name, value) => attributes.set(name, value),
    removeAttribute: name => attributes.delete(name),
  }
  const store = Store.create_store(), renderer = {web_store: store}
  let generation = 0
  const apply = ops => assert.equal(Store.apply_batch(store, () => element,
    {generation: ++generation, ops: list(ops)}), true)
  apply([Protocol.create_node_op(1, kind)])
  for (const name of ['absolute', 'relative', 'fixed', 'static', 'absolute']) {
    const value = {TAG: 0, _0: name}
    apply([Protocol.set_prop_op(1, position, value)])
    Props.apply_property(renderer, () => {}, 1, kind, element, position, value)
    assert.equal(attributes.get('data-lui-position'), name)
    assert.equal(styles.get('position'), name)
  }
  apply([Protocol.remove_prop_op(1, position)])
  Props.remove_property(renderer, () => {}, 1, kind, element, position)
  assert.equal(attributes.has('data-lui-position'), false)
  assert.equal(styles.get('position'), '')
})


test('switch chrome reaches its input while sizing retains its wrapper and clears on removal', () => {
  const kind = named(Schema.all_node_kinds, Schema.node_kind_name, 'switch')
  const property = name => named(Schema.all_properties, Schema.property_name, name)
  const element = () => { const styles = new Map(); return {styles,
    style: {setProperty: (name, value) => styles.set(name, value)}} }
  const input = element(), root = element()
  root.children = {item: index => index === 0 ? input : null}
  const store = Store.create_store(), renderer = {web_store: store}
  let generation = 0
  const apply = ops => assert.equal(Store.apply_batch(store, () => root,
    {generation: ++generation, ops: list(ops)}), true)
  apply([Protocol.create_node_op(1, kind)])
  for (const [name, value, css] of [
    ['width', {TAG: 2, _0: 32}, 'width'], ['height', {TAG: 2, _0: 18}, 'height'],
    ['padding', {TAG: 2, _0: 3}, 'padding-left'], ['border-width', {TAG: 2, _0: 0}, 'border-width'],
    ['corner-radius', {TAG: 2, _0: 9}, 'border-radius'],
    ['background', {TAG: 0, _0: '#294556'}, 'background'],
  ]) {
    const prop = property(name)
    apply([Protocol.set_prop_op(1, prop, value)])
    Props.apply_property(renderer, () => {}, 1, kind, root, prop, value)
    assert.ok(input.styles.get(css), `${name} must style the input`)
    if (name === 'width' || name === 'height') assert.equal(root.styles.get(css), input.styles.get(css))
    else assert.equal(root.styles.has(css), false, `${name} must not add a second wrapper surface`)
    apply([Protocol.remove_prop_op(1, prop)])
    Props.remove_property(renderer, () => {}, 1, kind, root, prop)
    assert.equal(input.styles.get(css), '', `${name} must clear from its actual surface`)
  }
})
