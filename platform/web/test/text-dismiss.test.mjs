import assert from 'node:assert/strict'
import {readFile} from 'node:fs/promises'
import test from 'node:test'

const build = process.env.LUI_TEST_BUILD_DIR ?? '_build'
const modules = new URL(`../../../${build}/default/examples/components/web/lui-components-web/node_modules/`, import.meta.url)
const [Store, Protocol, Schema, Events, Props, Hashtbl] = await Promise.all([
  import(new URL('lui.web.dom/core/lui_web_store.js', modules)),
  import(new URL('lui/lui_protocol.js', modules)),
  import(new URL('lui/lui_wire_schema.js', modules)),
  import(new URL('lui.web.dom/events/lui_web_events.js', modules)),
  import(new URL('lui.web.dom/render/lui_web_props.js', modules)),
  import(new URL('melange/hashtbl.js', modules)),
])
const schema = JSON.parse(await readFile(new URL('../../../schema/components.json', import.meta.url)))
const tag = name => schema.events.findIndex(event => event.lg === name)
const named = (values, nameOf, name) => {
  for (let rest = values; rest; rest = rest.tl) if (nameOf(rest.hd) === name) return rest.hd
  assert.fail(`Missing shared capability: ${name}`)
}
const property = name => named(Schema.all_properties, Schema.property_name, name)
const list = values => values.reduceRight((tl, hd) => ({hd, tl}), 0)
const bool = value => ({TAG: 1, _0: value})

function fixture(kindName) {
  const kind = named(Schema.all_node_kinds, Schema.node_kind_name, kindName)
  const store = Store.create_store(), events = [], listeners = new Map(), attributes = new Map()
  const element = {nodeType: 1, tagName: kindName === 'textarea' ? 'TEXTAREA' : 'INPUT', value: 'draft',
    hasAttribute: name => attributes.has(name), setAttribute: (name, value) => attributes.set(name, value),
    removeAttribute: name => attributes.delete(name), addEventListener: (name, handler) => listeners.set(name, handler)}
  let blurDuringDismiss = false
  const renderer = {web_store: store,
    web_appear_pending: Hashtbl.create(undefined, 4),
    web_appear_seen: Hashtbl.create(undefined, 4),
    web_appear_timer: {contents: undefined},
    web_event_handler: {contents: event => {
    events.push(event)
    if (event.TAG === tag('Dismiss') && blurDuringDismiss) listeners.get('blur')({})
    return true
  }}}
  let generation = 0
  const apply = ops => assert.equal(Store.apply_batch(store, () => element,
    {generation: ++generation, ops: list(ops)}), true)
  apply([Protocol.create_node_op(1, kind)])
  Events.attach_text_events(renderer, 1, kind, element)
  const set = (name, enabled) => {
    const prop = property(name), value = bool(enabled)
    apply([Protocol.set_prop_op(1, prop, value)])
    Props.apply_property(renderer, () => {}, 1, kind, element, prop, value)
  }
  const fire = (name, fields = {}) => {
    events.length = 0
    let prevented = false, stopped = false
    listeners.get(name)?.({key: 'Escape', repeat: false, isComposing: false,
      shiftKey: false, ctrlKey: false, metaKey: false, altKey: false, ...fields,
      preventDefault() {prevented = true}, stopPropagation() {stopped = true}})
    return {prevented, stopped, events: events.map(event => ({tag: event.TAG, node: event._0}))}
  }
  return {set, fire, apply, renderer, kind, element, events,
    writeText: text => {
      const prop = property('text'), value = {TAG: 0, _0: text}
      apply([Protocol.set_prop_op(1, prop, value)])
      Props.apply_property(renderer, () => {}, 1, kind, element, prop, value)
    },
    synchronousBlur: () => {blurDuringDismiss = true}, remove: name => {
      const prop = property(name)
      apply([Protocol.remove_prop_op(1, prop)])
      Props.remove_property(renderer, () => {}, 1, kind, element, prop)
    }}
}

const untouched = {prevented: false, stopped: false, events: []}
const submit = {prevented: false, stopped: false, events: [{tag: tag('Submit'), node: 1}]}
const dismiss = {prevented: true, stopped: true, events: [{tag: tag('Dismiss'), node: 1}]}
for (const kind of ['text-field', 'secure-field', 'input', 'search-field', 'textarea']) {
  test(`${kind} only owns opt-in ordinary Escape and suppresses the following blur submit`, () => {
    const f = fixture(kind)
    f.set('submit-on-blur', true)
    assert.deepEqual(f.fire('keydown'), untouched)
    f.set('dismiss-enabled', true)
    assert.deepEqual(f.fire('keydown'), dismiss)
    assert.deepEqual(f.fire('blur'), untouched)
    f.fire('focusin')
    assert.deepEqual(f.fire('blur'), submit)
    assert.deepEqual(f.fire('keydown'), dismiss)
    f.fire('input')
    assert.deepEqual(f.fire('blur'), submit)
    f.set('dismiss-enabled', false)
    assert.deepEqual(f.fire('keydown'), untouched)
    assert.deepEqual(f.fire('blur'), submit)
    f.set('dismiss-enabled', true)
    f.remove('dismiss-enabled')
    assert.deepEqual(f.fire('keydown'), untouched)
    assert.deepEqual(f.fire('blur'), submit)
  })
  test(`${kind} arms cancellation before a synchronous application blur`, () => {
    const f = fixture(kind)
    f.set('submit-on-blur', true)
    if (kind === 'textarea') f.set('submit-on-enter', true)
    f.set('dismiss-enabled', true)
    f.synchronousBlur()
    assert.deepEqual(f.fire('keydown'), dismiss)
    assert.deepEqual(f.fire('keydown', {key: 'Enter'}), {prevented: true, stopped: false, events: []})
  })
  test(`${kind} keeps cancellation through duplicate keys and controlled patches until a new draft`, () => {
    const f = fixture(kind)
    f.set('submit-on-blur', true)
    if (kind === 'textarea') f.set('submit-on-enter', true)
    f.set('dismiss-enabled', true)
    assert.deepEqual(f.fire('keydown'), dismiss)
    assert.deepEqual(f.fire('keydown'), {prevented: true, stopped: true, events: []})
    const suppressedEnter = {prevented: true, stopped: false, events: []}
    assert.deepEqual(f.fire('keydown', {key: 'Enter'}), suppressedEnter)
    f.writeText('authoritative')
    assert.equal(f.element.value, 'authoritative')
    assert.deepEqual(f.events, [])
    assert.deepEqual(f.fire('keydown'), {prevented: true, stopped: true, events: []})
    assert.deepEqual(f.fire('blur'), untouched)
    assert.deepEqual(f.fire('keydown', {key: 'Enter'}), suppressedEnter)
    f.remove('dismiss-enabled')
    assert.deepEqual(f.fire('keydown'), untouched)
    assert.deepEqual(f.fire('keydown', {key: 'Enter'}), suppressedEnter)
    f.fire('input')
    assert.deepEqual(f.fire('keydown', {key: 'Enter'}), {prevented: true, stopped: false, events: submit.events})
    f.set('dismiss-enabled', true)
    assert.deepEqual(f.fire('keydown'), dismiss)
    f.fire('focusin')
    assert.deepEqual(f.fire('keydown', {key: 'Enter'}), {prevented: true, stopped: false, events: submit.events})
  })
  test(`${kind} preserves composing, modified, repeated, disabled and retired Escape`, () => {
    const f = fixture(kind)
    f.set('dismiss-enabled', true)
    for (const name of ['isComposing', 'shiftKey', 'ctrlKey', 'metaKey', 'altKey', 'repeat']) {
      assert.deepEqual(f.fire('keydown', {[name]: true}), untouched, name)
    }
    f.fire('compositionstart')
    assert.deepEqual(f.fire('keydown'), untouched)
    f.fire('compositionend')
    assert.deepEqual(f.fire('keydown'), dismiss)
    f.set('enabled', false)
    assert.deepEqual(f.fire('keydown'), untouched)
    f.set('enabled', true)
    f.apply([Protocol.drop_node_op(1)])
    assert.deepEqual(f.fire('keydown'), untouched)
  })
}
