import assert from 'node:assert/strict'
import test from 'node:test'

const build = process.env.LUI_TEST_BUILD_DIR ?? '_build'
const modules = new URL(`../../../${build}/default/examples/components/web/lui-components-web/node_modules/`, import.meta.url)
const [Store, Protocol, Schema, Tables, Menu, Layers, Props] = await Promise.all([
  import(new URL('lui.web.dom/core/lui_web_store.js', modules)),
  import(new URL('lui/lui_protocol.js', modules)),
  import(new URL('lui/lui_wire_schema.js', modules)),
  import(new URL('melange/hashtbl.js', modules)),
  import(new URL('lui.web.dom/popup/lui_web_menu.js', modules)),
  import(new URL('lui.web.dom/core/lui_web_layers.js', modules)),
  import(new URL('lui.web.dom/render/lui_web_props.js', modules)),
])
const list = values => values.reduceRight((tl, hd) => ({hd, tl}), 0)
const named = (values, nameOf, name) => {
  for (let rest = values; rest; rest = rest.tl) if (nameOf(rest.hd) === name) return rest.hd
  throw new Error(`Unknown schema value: ${name}`)
}
const kind = name => named(Schema.all_node_kinds, Schema.node_kind_name, name)
const prop = name => named(Schema.all_properties, Schema.property_name, name)
const wire = value => ({TAG: 0, _0: value})
const element = (children = []) => {
  const attributes = new Map(), styles = new Map()
  return {
    style: {setProperty: (key, value) => styles.set(key, value)},
    children: {item: index => children[index] ?? null, length: children.length},
    setAttribute: (key, value) => attributes.set(key, value),
    getAttribute: key => attributes.get(key) ?? null,
    removeAttribute: key => attributes.delete(key),
    contains(target) { return target === this || children.some(child => child.contains(target)) },
  }
}
const fixture = (role, placement) => {
  const field = element(), surface = element([field]), positioner = element([surface]), outside = element()
  const document = {addEventListener() {}, removeEventListener() {}}
  const store = Store.create_store(), layers = Layers.create(), dismissed = []
  const renderer = {web_store: store, web_document: document, web_layers: layers,
    web_cleanups: Tables.create(undefined, 4), web_event_handler: {contents: event => dismissed.push(event._0)}}
  let generation = 0
  const apply = ops => assert.equal(Store.apply_batch(store,
    name => name === kind('popover') ? positioner : element(),
    {generation: ++generation, ops: list(ops)}), true)
  apply([Protocol.create_node_op(1, kind('column')), Protocol.create_node_op(2, kind('popover')),
    Protocol.insert_child_op(1, 2, 0),
    ...(role ? [Protocol.set_prop_op(2, prop('role'), wire(role))] : []),
    ...(placement === 'anchor' ? [Protocol.set_prop_op(2, prop('anchor'), wire('below'))]
      : ['x', 'y'].map(name => Protocol.set_prop_op(2, prop(name), {TAG: 3, _0: 10})))])
  const descendant = (_ancestor, _child) => false, targetElement = target => target
  Layers.install(layers, document, descendant, targetElement)
  Menu.attach_popover_events(renderer, 2, positioner)
  Layers.open_layer(layers, document, 2)
  return {dismissed,
    focus: target => Layers.dispatch_focus(layers, descendant, targetElement, {target}),
    pointer: target => Layers.dispatch_pointer(layers, descendant, targetElement, {target}),
    escape: () => Layers.dispatch_key(layers, {key: 'Escape', defaultPrevented: false,
      isComposing: false, stopImmediatePropagation() {}, preventDefault() {}}),
    role: value => {
      apply([value ? Protocol.set_prop_op(2, prop('role'), wire(value)) : Protocol.remove_prop_op(2, prop('role'))])
      if (value) Props.apply_property(renderer, () => {}, 2, kind('popover'), positioner, prop('role'), wire(value))
      else Props.remove_property(renderer, () => {}, 2, kind('popover'), positioner, prop('role'))
    }, field, outside}
}

for (const placement of ['anchor', 'point']) {
  test(`${placement} form popover survives keyboard focus outside but dismisses on outside pointer and Escape`, () => {
    const f = fixture('dialog', placement)
    f.focus(f.field)
    f.focus(f.outside)
    assert.deepEqual(f.dismissed, [], 'Tab out must preserve the nonmodal form')
    f.pointer(f.field)
    assert.deepEqual(f.dismissed, [])
    f.pointer(f.outside)
    assert.deepEqual(f.dismissed, [2])
    f.escape()
    assert.deepEqual(f.dismissed, [2, 2])
  })

  for (const role of ['menu', undefined]) test(`${placement} ${role ?? 'default'} popover still dismisses on focus outside`, () => {
    const f = fixture(role, placement)
    f.focus(f.field)
    assert.deepEqual(f.dismissed, [])
    f.focus(f.outside)
    assert.deepEqual(f.dismissed, [2])
  })

  test(`${placement} retained popover follows role changes and removal`, () => {
    const f = fixture('menu', placement)
    f.role('dialog')
    f.focus(f.outside)
    assert.deepEqual(f.dismissed, [])
    f.role('menu')
    f.focus(f.outside)
    assert.deepEqual(f.dismissed, [2])
    f.role('dialog')
    f.role(undefined)
    f.focus(f.outside)
    assert.deepEqual(f.dismissed, [2, 2])
  })
}
