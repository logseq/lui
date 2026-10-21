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
const opacity = named(Schema.all_properties, Schema.property_name, 'label-opacity')
const element = children => {
  const styles = new Map()
  return {styles, style: {setProperty: (name, value) => styles.set(name, value)},
    children: {item: index => children[index] ?? null}}
}

for (const name of ['checkbox', 'radio']) {
  test(`${name} caption opacity updates and clears without fading the indicator`, () => {
    const kind = named(Schema.all_node_kinds, Schema.node_kind_name, name)
    const indicator = element([]), caption = element([])
    const root = element([indicator, caption])
    const store = Store.create_store(), renderer = {web_store: store}
    let generation = 0
    const apply = ops => assert.equal(Store.apply_batch(store, () => root,
      {generation: ++generation, ops: list(ops)}), true)
    apply(name === 'radio'
      ? [Protocol.create_node_op(2, named(Schema.all_node_kinds, Schema.node_kind_name, 'radio-group')),
        Protocol.set_prop_op(2, named(Schema.all_properties, Schema.property_name, 'accessibility-label'),
          {TAG: 0, _0: 'Choices'}),
        Protocol.create_node_op(1, kind),
        Protocol.set_prop_op(1, named(Schema.all_properties, Schema.property_name, 'text'),
          {TAG: 0, _0: 'Caption café 中文 😀'}), Protocol.insert_child_op(2, 1, 0)]
      : [Protocol.create_node_op(1, kind),
        Protocol.set_prop_op(1, named(Schema.all_properties, Schema.property_name, 'text'),
          {TAG: 0, _0: 'Caption café 中文 😀'})])
    for (const value of [0, 0.7, 1, 0.25]) {
      const wire = {TAG: 3, _0: value}
      apply([Protocol.set_prop_op(1, opacity, wire)])
      Props.apply_property(renderer, () => {}, 1, kind, root, opacity, wire)
      assert.equal(Number(caption.styles.get('opacity')), value)
      assert.equal(root.styles.size, 0, 'Root appearance stays inherited')
      assert.equal(indicator.styles.size, 0, 'Indicator contrast is unchanged')
      assert.equal(root.children.item(1), caption, 'Caption identity is retained')
    }
    apply([Protocol.remove_prop_op(1, opacity)])
    Props.remove_property(renderer, () => {}, 1, kind, root, opacity)
    assert.equal(caption.styles.get('opacity'), '', 'Removal restores normal caption opacity')
    assert.equal(indicator.styles.size, 0)
  })
}

for (const name of ['indicator-border-color', 'checked-indicator-border-color']) {
  test(`checkbox ${name} updates and clears without decorating its caption`, () => {
    const kind = named(Schema.all_node_kinds, Schema.node_kind_name, 'checkbox')
    const property = named(Schema.all_properties, Schema.property_name, name)
    const indicator = element([]), caption = element([]), root = element([indicator, caption])
    const store = Store.create_store(), renderer = {web_store: store}
    let generation = 0
    const apply = ops => assert.equal(Store.apply_batch(store, () => root,
      {generation: ++generation, ops: list(ops)}), true)
    apply([Protocol.create_node_op(1, kind)])
    for (const color of ['#171717', 'var(--neutral-edge)', '#a4b5b6']) {
      const wire = {TAG: 0, _0: color}
      apply([Protocol.set_prop_op(1, property, wire)])
      Props.apply_property(renderer, () => {}, 1, kind, root, property, wire)
      assert.equal(indicator.styles.get(`--lui-${name}`), color)
      assert.equal(root.styles.size, 0, 'The whole labeled control stays borderless')
      assert.equal(caption.styles.size, 0, 'The caption keeps its inherited ink')
    }
    apply([Protocol.remove_prop_op(1, property)])
    Props.remove_property(renderer, () => {}, 1, kind, root, property)
    assert.equal(indicator.styles.get(`--lui-${name}`), '')
    if (name === 'checked-indicator-border-color')
      assert.equal(indicator.styles.get('--lui-checked-indicator-border-width'), '')
  })
}
