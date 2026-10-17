import assert from 'node:assert/strict'
import {readFile} from 'node:fs/promises'
import test from 'node:test'

const build = process.env.LUI_TEST_BUILD_DIR ?? '_build'
const modules = new URL(`../../../${build}/default/examples/components/web/lui-components-web/node_modules/`, import.meta.url)
const [Store, Protocol, Schema, Props, Events, Tables] = await Promise.all([
  import(new URL('lui.web.dom/core/lui_web_store.js', modules)),
  import(new URL('lui/lui_protocol.js', modules)),
  import(new URL('lui/lui_wire_schema.js', modules)),
  import(new URL('lui.web.dom/render/lui_web_props.js', modules)),
  import(new URL('lui.web.dom/events/lui_web_events.js', modules)),
  import(new URL('melange/hashtbl.js', modules)),
])
const schema = JSON.parse(await readFile(new URL('../../../schema/components.json', import.meta.url)))
const eventTag = name => schema.events.findIndex(event => event.lg === name)
const named = (values, nameOf, name) => {
  for (let rest = values; rest; rest = rest.tl) if (nameOf(rest.hd) === name) return rest.hd
  throw new Error(`Unknown schema value: ${name}`)
}
const property = name => named(Schema.all_properties, Schema.property_name, name)
const list = items => items.reduceRight((tl, hd) => ({hd, tl}), 0)
const bool = value => ({TAG: 1, _0: value})

function fixture(kindName) {
  const kind = named(Schema.all_node_kinds, Schema.node_kind_name, kindName)
  const store = Store.create_store()
  const events = []
  const renderer = {web_store: store,
    web_appear_pending: Tables.create(undefined, 4),
    web_appear_seen: Tables.create(undefined, 4),
    web_appear_timer: {contents: undefined},
    web_event_handler: {contents: event => {events.push(event); return true}}}
  const element = {setAttribute() {}, removeAttribute() {}}
  let generation = 0
  const apply = ops => Store.apply_batch(store, () => element, {generation: ++generation, ops: list(ops)})
  apply([Protocol.create_node_op(1, kind)])
  const set = (name, value) => {
    apply([Protocol.set_prop_op(1, property(name), bool(value))])
    Props.apply_property(renderer, () => {}, 1, kind, element, property(name), bool(value))
  }
  const remove = name => {
    apply([Protocol.remove_prop_op(1, property(name))])
    Props.remove_property(renderer, () => {}, 1, kind, element, property(name))
  }
  const key = (key, modifiers = {}, composing = false) => {
    events.length = 0
    let prevented = false
    Events.text_keydown(renderer, 1, kind, {contents: composing}, {
      key, shiftKey: false, ctrlKey: false, metaKey: false, altKey: false,
      isComposing: false, ...modifiers, preventDefault() {prevented = true},
    })
    return {prevented, events: events.map(event => ({tag: event.TAG, node: event._0}))}
  }
  return {set, remove, key}
}

for (const kind of ['text-field', 'secure-field', 'input', 'search-field', 'textarea']) {
  test(`${kind} navigation is opt-in and preserves modified and composing keys`, () => {
    const f = fixture(kind)
    const untouched = {prevented: false, events: []}
    assert.deepEqual(f.key('ArrowDown'), untouched)
    f.set('navigate-enabled', true)
    assert.deepEqual(f.key('ArrowUp'), {prevented: true, events: [{tag: eventTag('NavigatePrevious'), node: 1}]})
    assert.deepEqual(f.key('ArrowDown'), {prevented: true, events: [{tag: eventTag('NavigateNext'), node: 1}]})
    for (const modifier of ['shiftKey', 'ctrlKey', 'metaKey', 'altKey', 'isComposing']) {
      assert.deepEqual(f.key('ArrowDown', {[modifier]: true}), untouched, modifier)
    }
    assert.deepEqual(f.key('ArrowUp', {}, true), untouched)
    assert.deepEqual(f.key('Home'), untouched)
    assert.deepEqual(f.key('End'), untouched)
    f.set('navigate-enabled', false)
    assert.deepEqual(f.key('ArrowDown'), untouched)
    f.set('navigate-enabled', true)
    f.remove('navigate-enabled')
    assert.deepEqual(f.key('ArrowDown'), untouched)
    f.set('navigate-enabled', true)
    f.set('enabled', false)
    assert.deepEqual(f.key('ArrowDown'), untouched)
  })
}
