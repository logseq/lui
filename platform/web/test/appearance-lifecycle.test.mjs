import assert from 'node:assert/strict'
import test from 'node:test'

const build = process.env.LUI_TEST_BUILD_DIR ?? '_build'
const modules = new URL(`../../../${build}/default/examples/components/web/lui-components-web/node_modules/`, import.meta.url)
const [Store, Protocol, Schema, Props, Events, Tables, Lazy] = await Promise.all([
  import(new URL('lui.web.dom/core/lui_web_store.js', modules)),
  import(new URL('lui/lui_protocol.js', modules)),
  import(new URL('lui/lui_wire_schema.js', modules)),
  import(new URL('lui.web.dom/render/lui_web_props.js', modules)),
  import(new URL('lui.web.dom/events/lui_web_events.js', modules)),
  import(new URL('melange/hashtbl.js', modules)),
  import(new URL('melange/camlinternalLazy.js', modules)),
])
const list = items => items.reduceRight((tl, hd) => ({hd, tl}), 0)
const value = (values, nameOf, name) => {
  for (let rest = values; rest; rest = rest.tl) if (nameOf(rest.hd) === name) return rest.hd
  throw new Error(`Unknown schema value: ${name}`)
}
const column = value(Schema.all_node_kinds, Schema.node_kind_name, 'column')
const row = value(Schema.all_node_kinds, Schema.node_kind_name, 'list-item')
const appear = value(Schema.all_properties, Schema.property_name, 'appear-enabled')
const enabled = value(Schema.all_properties, Schema.property_name, 'enabled')
const text = value(Schema.all_properties, Schema.property_name, 'text')
const bool = flag => ({TAG: 1, _0: flag})
const settle = async renderer => {
  const deadline = performance.now() + 1000
  do {
    await new Promise(resolve => setTimeout(resolve, 0))
    if (renderer.web_appear_timer.contents === undefined) return
  } while (performance.now() < deadline)
  assert.fail('Appearance lifecycle timer did not drain')
}

test('focus-within appearance crosses the protocol and clears independently', () => {
  const f=fixture(),node=Lazy.force(Store.node(f.renderer.web_store,1).platform_node)
  const styles=new Map()
  node.style={setProperty(name,value){styles.set(name,value)}}
  for(const [name,channel] of [['focus-within-background','--lui-focus-within-bg'],
    ['focus-within-border','--lui-focus-within-border']]) {
    const property=value(Schema.all_properties,Schema.property_name,name)
    Props.apply_property(f.renderer,()=>{},1,column,node,property,{TAG:0,_0:'#112233'})
    assert.equal(styles.get(channel),'#112233',`${name} reaches its rendering surface`)
    Props.remove_property(f.renderer,()=>{},1,column,node,property)
    assert.equal(styles.get(channel),'',`${name} retires independently`)
  }
})

function fixture() {
  const store = Store.create_store()
  const elements = []
  const events = []
  let generation = 0
  let mounted = false
  const renderer = {
    web_store: store,
    web_document: {documentElement: {contains: element => mounted && elements.includes(element)}},
    web_appear_pending: Tables.create(undefined, 8),
    web_appear_seen: Tables.create(undefined, 8),
    web_appear_timer: {contents: undefined},
    web_mounted_roots: Tables.create(undefined, 4),
    web_event_handler: {contents: event => {events.push(event._0); return true}},
  }
  const dom = () => {
    const element = {setAttribute() {}, removeAttribute() {}}
    elements.push(element)
    return element
  }
  const apply = ops => Store.apply_batch(store, dom, {generation: ++generation, ops: list(ops)})
  const set = (id, property, flag) => {
    apply([Protocol.set_prop_op(id, property, bool(flag))])
    Props.apply_property(renderer, () => {}, id, id === 1 ? row : column,
      Lazy.force(Store.node(store, id).platform_node), property, bool(flag))
  }
  apply([Protocol.create_node_op(1, row), Protocol.set_prop_op(1, text, {TAG: 0, _0: 'Parent'}),
    Protocol.create_node_op(2, column), Protocol.insert_child_op(1, 2, 0)])
  Tables.replace(renderer.web_mounted_roots, 1, {})
  return {renderer, events, apply, set, mount() {mounted = true}, appear}
}

test('appearance runs once in tree order after DOM attachment and outside batch application', async () => {
  const f = fixture()
  f.set(2, appear, true)
  f.set(1, appear, true)
  Events.schedule_appear(f.renderer)
  await settle(f.renderer)
  assert.deepEqual(f.events, [], 'Unattached elements must not appear')
  f.mount()
  Events.schedule_appear(f.renderer)
  assert.deepEqual(f.events, [], 'Appearance must not reenter batch application')
  await settle(f.renderer)
  assert.deepEqual(f.events, [1, 2])
  Events.schedule_appear(f.renderer)
  await settle(f.renderer)
  assert.deepEqual(f.events, [1, 2], 'Unrelated updates must not repeat appearance')
  assert.equal(f.renderer.web_appear_timer.contents, undefined, 'No timer may remain while idle')
})

test('appearance respects enablement, property removal and disposal before delivery', async () => {
  const f = fixture()
  f.mount()
  f.set(1, appear, true)
  f.set(1, enabled, false)
  Events.schedule_appear(f.renderer)
  await settle(f.renderer)
  assert.deepEqual(f.events, [])
  f.set(1, enabled, true)
  Events.schedule_appear(f.renderer)
  await settle(f.renderer)
  assert.deepEqual(f.events, [1])
  f.apply([Protocol.remove_prop_op(1, appear)])
  Props.remove_property(f.renderer, () => {}, 1, row, {}, appear)
  f.set(1, appear, true)
  Events.schedule_appear(f.renderer)
  await settle(f.renderer)
  assert.deepEqual(f.events, [1, 1], 'Re-enabling the lifecycle must announce it again')
  f.set(2, appear, true)
  Events.schedule_appear(f.renderer)
  f.apply([Protocol.remove_child_op(1, 2), Protocol.drop_node_op(2)])
  await settle(f.renderer)
  assert.deepEqual(f.events, [1, 1], 'Disposed nodes must not deliver stale callbacks')
})

test('appearance callbacks may change lifecycle membership without replay or iteration corruption', async () => {
  const f = fixture()
  f.mount()
  f.set(1, appear, true)
  f.renderer.web_event_handler.contents = event => {
    f.events.push(event._0)
    if (event._0 === 1) {
      f.set(2, appear, true)
      Events.schedule_appear(f.renderer)
    }
    return true
  }
  Events.schedule_appear(f.renderer)
  const settled = settle(f.renderer)
  // Both the first callback and the fixed-delay assertion can become due
  // before the event loop resumes; nested lifecycle work needs another turn.
  const resume = performance.now() + 25
  while (performance.now() < resume) {}
  await settled
  assert.deepEqual(f.events, [1, 2])
  Events.schedule_appear(f.renderer)
  await settle(f.renderer)
  assert.deepEqual(f.events, [1, 2])
})
