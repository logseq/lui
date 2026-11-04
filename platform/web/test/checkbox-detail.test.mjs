import assert from 'node:assert/strict'
import {readFile} from 'node:fs/promises'
import test from 'node:test'

const build = process.env.LUI_TEST_BUILD_DIR ?? '_build'
const modules = new URL(`../../../${build}/default/examples/components/web/lui-components-web/node_modules/`, import.meta.url)
const [Store, Protocol, Schema, Props, Events] = await Promise.all([
  import(new URL('lui.web.dom/core/lui_web_store.js', modules)),
  import(new URL('lui/lui_protocol.js', modules)),
  import(new URL('lui/lui_wire_schema.js', modules)),
  import(new URL('lui.web.dom/render/lui_web_props.js', modules)),
  import(new URL('lui.web.dom/events/lui_web_events.js', modules)),
])
const schema = JSON.parse(await readFile(new URL('../../../schema/components.json', import.meta.url)))
const named = (values, nameOf, name) => {
  for (let rest = values; rest; rest = rest.tl) if (nameOf(rest.hd) === name) return rest.hd
  throw new Error(`Unknown schema value: ${name}`)
}
const list = values => values.reduceRight((tl, hd) => ({hd, tl}), 0)
const kind = named(Schema.all_node_kinds, Schema.node_kind_name, 'checkbox')
const prop = name => named(Schema.all_properties, Schema.property_name, name)

test('checkbox detail capability survives DOM apply and obeys opt-out and removal', () => {
  const store = Store.create_store(), attributes = new Map(), listeners = new Map(), events = []
  const input = {nodeType: 1, tagName: 'INPUT', checked: true,
    addEventListener: (name, handler) => listeners.set(name, handler)}
  const element = {tagName: 'LABEL', children: {item: i => i === 0 ? input : null, length: 1},
    setAttribute: (key, value) => attributes.set(key, value),
    removeAttribute: key => attributes.delete(key)}
  const renderer = {web_store: store,
    web_event_handler: {contents: event => {events.push(event); return true}}}
  let generation = 0
  const apply = ops => assert.equal(Store.apply_batch(store, () => element,
    {generation: ++generation, ops: list(ops)}), true)
  const set = (name, enabled) => {
    const property = prop(name), value = {TAG: 1, _0: enabled}
    apply([Protocol.set_prop_op(1, property, value)])
    Props.apply_property(renderer, () => {}, 1, kind, element, property, value)
  }
  const change = () => {
    events.length = 0
    listeners.get('change')({})
    return events.map(event => ({tag: event.TAG, checked: event._1, modifiers: event._2}))
  }
  apply([Protocol.create_node_op(1, kind)])
  Events.attach_toggle_event(renderer, 1, kind, element)
  assert.deepEqual(change(), [])
  set('toggle-detail-enabled', true)
  listeners.get('click')({ctrlKey: false, shiftKey: true, metaKey: false, altKey: false,
    button: 0, clientX: 0, clientY: 0, target: {className: ''}})
  assert.deepEqual(change(), [{tag: schema.events.findIndex(e => e.lg === 'ToggleChangedDetail'),
    checked: true, modifiers: 2}])
  set('toggle-detail-enabled', false)
  assert.deepEqual(change(), [])
  set('toggle-detail-enabled', true)
  apply([Protocol.remove_prop_op(1, prop('toggle-detail-enabled'))])
  Props.remove_property(renderer, () => {}, 1, kind, element, prop('toggle-detail-enabled'))
  assert.equal(attributes.has('data-toggle-detail-enabled'), false)
  assert.deepEqual(change(), [])
  set('toggle-enabled', true)
  assert.deepEqual(change(), [{tag: schema.events.findIndex(e => e.lg === 'ToggleChanged'),
    checked: true, modifiers: undefined}])
  set('toggle-detail-enabled', true)
  assert.deepEqual(change().map(event => event.tag),
    ['ToggleChanged', 'ToggleChangedDetail'].map(name => schema.events.findIndex(e => e.lg === name)))
})
