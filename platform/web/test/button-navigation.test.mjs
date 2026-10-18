import assert from 'node:assert/strict'
import {readFile} from 'node:fs/promises'
import test from 'node:test'

const build = process.env.LUI_TEST_BUILD_DIR ?? '_build'
const modules = new URL(`../../../${build}/default/examples/components/web/lui-components-web/node_modules/`, import.meta.url)
const [Store, Protocol, Schema, Events, Tables] = await Promise.all([
  import(new URL('lui.web.dom/core/lui_web_store.js', modules)),
  import(new URL('lui/lui_protocol.js', modules)),
  import(new URL('lui/lui_wire_schema.js', modules)),
  import(new URL('lui.web.dom/events/lui_web_events.js', modules)),
  import(new URL('melange/hashtbl.js', modules)),
])
const schema = JSON.parse(await readFile(new URL('../../../schema/components.json', import.meta.url)))
const named = (values, nameOf, name) => {
  for (let rest = values; rest; rest = rest.tl) if (nameOf(rest.hd) === name) return rest.hd
  throw new Error(`Unknown schema value: ${name}`)
}
const list = values => values.reduceRight((tl, hd) => ({hd, tl}), 0)
const kind = named(Schema.all_node_kinds, Schema.node_kind_name, 'button')
const prop = name => named(Schema.all_properties, Schema.property_name, name)

function fixture() {
  const store = Store.create_store(), events = [], listeners = new Map()
  const element = {
    addEventListener(name, handler) {
      const handlers = listeners.get(name) ?? new Set()
      handlers.add(handler); listeners.set(name, handlers)
    },
    removeEventListener(name, handler) { listeners.get(name)?.delete(handler) },
    getAttribute() { return null }, hasAttribute() { return false },
  }
  const renderer = {web_store: store, web_cleanups: Tables.create(undefined, 4),
    web_event_handler: {contents: event => { events.push(event); return true }}}
  let generation = 0
  const apply = ops => Store.apply_batch(store, () => element, {generation: ++generation, ops: list(ops)})
  assert.equal(apply([Protocol.create_node_op(1, kind),
    Protocol.set_prop_op(1, prop('text'), {TAG: 0, _0: 'Day'})]), true)
  Events.attach_button_events(renderer, 1, kind, element)
  const set = (name, value, node = 1) => assert.equal(apply([
    Protocol.set_prop_op(node, prop(name), {TAG: 1, _0: value}),
  ]), true, `${name} must be admitted for buttons`)
  const remove = (name, node = 1) => assert.equal(apply([Protocol.remove_prop_op(node, prop(name))]), true)
  const key = (key, modifiers = {}) => {
    events.length = 0
    let prevented = false
    const event = {key, shiftKey: false, ctrlKey: false, altKey: false, metaKey: false,
      isComposing: false, ...modifiers, preventDefault() { prevented = true }}
    for (const handler of listeners.get('keydown') ?? []) handler(event)
    return {prevented, events: events.map(e => ({tag: e.TAG, node: e._0, key: e._1, shift: e._2}))}
  }
  const dispose = () => Tables.find_opt(renderer.web_cleanups, 1)()
  return {set, remove, key, dispose, listeners}
}

const untouched = {prevented: false, events: []}
for (const key of ['ArrowLeft', 'ArrowRight', 'ArrowUp', 'ArrowDown', 'Home', 'End', 'PageUp', 'PageDown']) {
  test(`button ${key} navigation is opt-in and retains Shift`, () => {
    const f = fixture()
    assert.deepEqual(f.key(key), untouched)
    f.set('navigate-enabled', true)
    const tag = schema.events.findIndex(e => e.lg === 'NavigationKey')
    assert.deepEqual(f.key(key), {prevented: true, events: [{tag, node: 1, key, shift: false}]})
    assert.deepEqual(f.key(key, {shiftKey: true}), {prevented: true, events: [{tag, node: 1, key, shift: true}]})
    f.dispose()
    assert.deepEqual(f.key(key), untouched)
  })
}

test('button navigation preserves composing, shortcut and activation keys and observes opt-out', () => {
  const f = fixture()
  f.set('navigate-enabled', true)
  for (const modifier of ['ctrlKey', 'altKey', 'metaKey', 'isComposing']) {
    assert.deepEqual(f.key('ArrowRight', {[modifier]: true}), untouched, modifier)
  }
  for (const key of ['Enter', ' ', 'Escape', 'Tab', 'a']) assert.deepEqual(f.key(key), untouched, key)
  f.set('enabled', false)
  assert.deepEqual(f.key('ArrowRight'), untouched)
  f.set('enabled', true)
  f.set('navigate-enabled', false)
  assert.deepEqual(f.key('ArrowRight'), untouched)
  f.set('navigate-enabled', true)
  f.remove('navigate-enabled')
  assert.deepEqual(f.key('ArrowRight'), untouched)
  f.dispose()
  assert.equal(f.listeners.get('keydown')?.size ?? 0, 0)
})
