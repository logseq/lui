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
const named = (values, nameOf, name) => {
  for (let rest = values; rest; rest = rest.tl) if (nameOf(rest.hd) === name) return rest.hd
  throw new Error(`Unknown schema value: ${name}`)
}
const list = values => values.reduceRight((tl, hd) => ({hd, tl}), 0)
const prop = name => named(Schema.all_properties, Schema.property_name, name)
const eventTarget = () => {
  const listeners = new Map()
  return {
    addEventListener(name, handler) {
      if (!listeners.has(name)) listeners.set(name, new Set())
      listeners.get(name).add(handler)
    },
    removeEventListener(name, handler) { listeners.get(name)?.delete(handler) },
    send(name, fields = {}) {
      const event = {pointerId: 1, pointerType: 'mouse', button: 0, clientX: 10, clientY: 20,
        ctrlKey: false, shiftKey: false, metaKey: false, isTrusted: false,
        target: {className: ''}, preventDefault() {}, stopPropagation() {}, ...fields}
      for (const handler of [...listeners.get(name) ?? []]) handler(event)
    },
  }
}

test('Row/Box capture survives DOM apply, opt-out, removal and subscription cleanup', () => {
  for (const name of ['row', 'box']) {
    const kind = named(Schema.all_node_kinds, Schema.node_kind_name, name)
    const store = Store.create_store(), attributes = new Map(), events = []
    const element = {...eventTarget(), tagName: 'DIV',
      setAttribute: (key, value) => attributes.set(key, value),
      removeAttribute: key => attributes.delete(key)}
    const renderer = {web_store: store, web_document: {defaultView: eventTarget()},
      web_pointer_cleanups: Tables.create(undefined, 4),
      web_event_handler: {contents: event => {events.push(event); return true}}}
    let generation = 0
    const apply = ops => assert.equal(Store.apply_batch(store, () => element,
      {generation: ++generation, ops: list(ops)}), true)
    const sync = () => Events.sync_pointer_events(renderer, 1, kind, element)
    const set = (name, enabled) => {
      const property = prop(name), value = {TAG: 1, _0: enabled}
      apply([Protocol.set_prop_op(1, property, value)])
      Props.apply_property(renderer, () => {}, 1, kind, element, property, value)
      sync()
    }
    const expect = names => {
      assert.deepEqual(events.splice(0).map(event => schema.events[event.TAG].lg), names)
    }
    apply([Protocol.create_node_op(1, kind)])
    set('pointer-enabled', true)
    set('pointer-capture', true)
    element.send('pointerdown')
    element.send('pointermove', {clientX: 35})
    element.send('click')
    element.send('pointerup')
    expect(['PointerDown', 'PointerMove', 'PointerUp'])

    element.send('pointerdown')
    set('pointer-capture', false)
    element.send('pointermove')
    element.send('click')
    expect(['PointerDown', 'PointerCancel', 'PressDetail'])

    set('pointer-capture', true)
    element.send('pointerdown')
    apply([Protocol.remove_prop_op(1, prop('pointer-capture'))])
    Props.remove_property(renderer, () => {}, 1, kind, element, prop('pointer-capture'))
    sync()
    assert.equal(attributes.has('data-pointer-capture'), false)
    element.send('pointermove')
    element.send('click')
    expect(['PointerDown', 'PointerCancel', 'PressDetail'])

    set('pointer-capture', true)
    element.send('pointerdown')
    set('pointer-enabled', false)
    element.send('pointerup')
    element.send('pointermove')
    expect(['PointerDown', 'PointerCancel'])

    set('pointer-enabled', true)
    element.send('pointerdown')
    Events.release_pointer_events(renderer, 1)
    element.send('pointerup')
    element.send('pointermove')
    expect(['PointerDown', 'PointerCancel'])
  }
})
