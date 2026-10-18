import assert from 'node:assert/strict'
import {readFile} from 'node:fs/promises'
import test from 'node:test'

const build = process.env.LUI_TEST_BUILD_DIR ?? '_build'
const modules = new URL(`../../../${build}/default/examples/components/web/lui-components-web/node_modules/`, import.meta.url)
const [Store, Protocol, Schema, Events, Props] = await Promise.all([
  import(new URL('lui.web.dom/core/lui_web_store.js', modules)),
  import(new URL('lui/lui_protocol.js', modules)),
  import(new URL('lui/lui_wire_schema.js', modules)),
  import(new URL('lui.web.dom/events/lui_web_events.js', modules)),
  import(new URL('lui.web.dom/render/lui_web_props.js', modules)),
])
const schema = JSON.parse(await readFile(new URL('../../../schema/components.json', import.meta.url)))
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
  const element = {tagName: kindName==='textarea' ? 'TEXTAREA' : 'INPUT', value: '13:45', setAttribute: (k,v) => attributes.set(k,v),
    removeAttribute: k => attributes.delete(k),
    addEventListener: (name,f) => listeners.set(name,f),
    querySelector: () => null}
  const renderer = {web_store: store, web_event_handler: {contents: event => {events.push(event);return true}}}
  let generation = 0
  const apply = ops => Store.apply_batch(store, () => element, {generation: ++generation, ops: list(ops)})
  apply([Protocol.create_node_op(1,kind)])
  Events.attach_text_events(renderer,1,kind,element)
  const set = (name,value) => apply([Protocol.set_prop_op(1,property(name),value)])
  const fire = name => {events.length=0;listeners.get(name)?.({});return events.map(e=>({tag:e.TAG,node:e._0}))}
  return {set,fire,apply,renderer,kind,element,attributes}
}
for (const kind of ['text-field','secure-field','input','search-field','textarea']) {
  test(`${kind} submits on blur only when enabled and outside composition`, () => {
    const f = fixture(kind)
    const submit = [{tag:schema.events.findIndex(e=>e.lg==='Submit'),node:1}]
    assert.deepEqual(f.fire('blur'),[])
    f.set('submit-on-blur',bool(true))
    assert.deepEqual(f.fire('blur'),submit)
    f.set('enabled',bool(false))
    assert.deepEqual(f.fire('blur'),[])
    f.set('enabled',bool(true))
    f.fire('compositionstart')
    assert.deepEqual(f.fire('blur'),[])
    f.fire('compositionend')
    assert.deepEqual(f.fire('blur'),submit)
    f.set('submit-on-blur',bool(false))
    assert.deepEqual(f.fire('blur'),[])
    f.set('submit-on-blur',bool(true))
    f.apply([Protocol.drop_node_op(1)])
    assert.deepEqual(f.fire('blur'),[])
  })
}
test('time is a typed input kind on the real Web property path', () => {
  const f = fixture('input')
  const value = {TAG:0,_0:'time'}
  f.set('input-type',value)
  Props.apply_property(f.renderer,()=>{},1,f.kind,f.element,property('input-type'),value)
  assert.equal(f.attributes.get('type'),'time')
})
