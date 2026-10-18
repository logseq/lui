import assert from 'node:assert/strict'
import test from 'node:test'

const build = process.env.LUI_TEST_BUILD_DIR ?? '_build'
const modules = new URL(`../../../${build}/default/examples/components/web/lui-components-web/node_modules/`, import.meta.url)
const [Store, Protocol, Schema, Nodes, Props] = await Promise.all([
  import(new URL('lui.web.dom/core/lui_web_store.js', modules)),
  import(new URL('lui/lui_protocol.js', modules)),
  import(new URL('lui/lui_wire_schema.js', modules)),
  import(new URL('lui.web.dom/nodes/lui_web_nodes.js', modules)),
  import(new URL('lui.web.dom/render/lui_web_props.js', modules)),
])
const list = values => values.reduceRight((tl, hd) => ({hd, tl}), 0)
const named = (values, nameOf, name) => {
  for (let rest = values; rest; rest = rest.tl) if (nameOf(rest.hd) === name) return rest.hd
  throw new Error(`Unknown schema value: ${name}`)
}
const kind = named(Schema.all_node_kinds, Schema.node_kind_name, 'list-item')
const selected = named(Schema.all_properties, Schema.property_name, 'selected')
const text = named(Schema.all_properties, Schema.property_name, 'text')

function fixture() {
  const attributes = new Map()
  const element = {
    setAttribute: (name, value) => attributes.set(name, value),
    getAttribute: name => attributes.get(name) ?? null,
    removeAttribute: name => attributes.delete(name),
  }
  const renderer = {web_store: Store.create_store(), web_document: {createElement: () => element}}
  let generation = 0
  const apply = ops => Store.apply_batch(renderer.web_store,
    value => Nodes.platform_node(renderer, value), {generation: ++generation, ops: list(ops)})
  assert.equal(apply([Protocol.create_node_op(1, kind),
    Protocol.set_prop_op(1, text, {TAG: 0, _0: 'Result'})]), true)
  assert.equal(Nodes.dom_node(renderer, 1), element)
  return {
    attributes,
    set(value) {
      const encoded = {TAG: 1, _0: value}
      apply([Protocol.set_prop_op(1, selected, encoded)])
      Props.apply_property(renderer, () => {}, 1, kind, element, selected, encoded)
    },
    remove() {
      apply([Protocol.remove_prop_op(1, selected)])
      Props.remove_property(renderer, () => {}, 1, kind, element, selected)
    },
  }
}

test('an action list item only exposes pressed state when selection is authored', () => {
  const f = fixture()
  assert.equal(f.attributes.get('type'), 'button')
  assert.equal(f.attributes.has('aria-pressed'), false)
  f.set(true)
  assert.equal(f.attributes.get('aria-pressed'), 'true')
  assert.equal(f.attributes.has('data-selected'), true)
  f.set(false)
  assert.equal(f.attributes.get('aria-pressed'), 'false')
  assert.equal(f.attributes.has('data-selected'), false)
  f.remove()
  assert.equal(f.attributes.has('aria-pressed'), false)
  assert.equal(f.attributes.has('data-selected'), false)
})

test('removing list selection also removes its pressed and selected attributes', () => {
  const f = fixture()
  f.set(true)
  f.remove()
  assert.equal(f.attributes.has('aria-pressed'), false)
  assert.equal(f.attributes.has('data-selected'), false)
})
